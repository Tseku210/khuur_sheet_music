/// Playback compilation (access pattern 6).
///
/// The score is compiled bar by bar. A bar's notes are compiled once into a
/// fragment in whole-note time and cached on the column object itself, so a
/// one-note edit recompiles one fragment. The part that runs on every
/// compile unrolls the repeats into a play order, folds tempo and each
/// part's dynamics over the bars, and places each played bar's fragment in
/// seconds, merging tie chains across the bars as they are played.
/// Dynamics are folded on every compile because a hairpin is stored beside
/// the columns it spans, not in them.
library;

import 'dart:math';

import 'events.dart';
import 'measure.dart';
import 'pitch.dart';
import 'refs.dart';
import 'score.dart';
import 'seq.dart';
import 'stable_sort.dart';
import 'time.dart';
import 'views.dart';
import 'voice_walk.dart';

part 'playback_attacks.dart';
part 'playback_dynamics.dart';
part 'playback_order.dart';
part 'playback_tempo.dart';

/// Long-lived. Keep one per composer screen so its fragment cache survives
/// across edits.
final class PlaybackCompiler {
  PlaybackCompiler();

  /// Fragments keyed by column identity. A column that an edit did not touch
  /// is the same object in the new score, so its fragment is reused. Entries
  /// die with their columns.
  final Expando<_Fragment> _fragments = Expando('playback fragments');

  PlaybackScript compile(
    Score score, [
    PlaybackOptions options = const PlaybackOptions(),
  ]) {
    final measures = score.measures;
    final starts = <Length>[];
    var elapsed = Length.zero;
    for (final column in measures) {
      starts.add(elapsed);
      elapsed += column.length;
    }
    final tempo = _TempoMap(score, starts);
    final channels = <ChannelSetup>[];
    final sounds = <StaffId, _Sound>{};
    var melodic = 0;
    for (final Part(:id, :instrument, :staves) in score.parts) {
      final channel = instrument.isPercussion
          ? 9
          : _melodicChannels[melodic++ % _melodicChannels.length];
      if (!options.muted.contains(id)) {
        channels.add(
          ChannelSetup(
            channel: channel,
            part: id,
            program: instrument.program,
            bank: instrument.bank,
          ),
        );
        final loudness = _Loudness(score, staves, starts);
        for (final staff in staves) {
          sounds[staff.id] = (
            channel: channel,
            instrument: instrument,
            loudness: loudness,
          );
        }
      }
    }
    final trills = <StaffId, List<(Moment, Moment)>>{};
    for (final Spanner(:kind, :staff, :first, :last) in score.spanners) {
      if (kind is TrillLine) {
        (trills[staff] ??= []).add((
          _place(score, starts, first.measure, first.offset),
          _place(score, starts, last.measure, last.offset),
        ));
      }
    }
    final windows = options.from == null && options.to == null
        ? [
            for (final (:index, :pass) in _playOrder(measures))
              (
                index: index,
                pass: pass,
                from: Moment.zero,
                to: Moment.zero + measures[index].length,
              ),
          ]
        : _range(score, options.from, options.to);
    final timeline = <_Bar>[];
    final sounding = <_Sounding>[];
    final ties = <(StaffId, VoiceSlot, Tone), (_Sounding, int, Moment)>{};
    var seconds = 0.0;
    for (final (k, (:index, :pass, :from, :to)) in windows.indexed) {
      final column = measures[index];
      final fragment = _fragments[column] ??= _compileBar(column);
      final clock = _Clock(
        tempo,
        Moment.zero + starts[index],
        column.length,
        fragment.holds,
      );
      final start = seconds;
      seconds += clock.at(to) - clock.at(from);
      final bar = _Bar(
        PlayedBar(
          measure: column.id,
          pass: pass,
          start: start,
          end: seconds,
        ),
        from: from,
        to: to,
        clock: clock,
        heard: [
          for (final chord in fragment.chords)
            if (sounds.containsKey(chord.timed.ref.staff) &&
                from <= chord.timed.onset &&
                chord.timed.onset < to)
              chord,
        ],
      );
      timeline.add(bar);
      for (final chord in bar.heard) {
        final TimedEvent(:onset, :voice, ref: EventRef(:staff)) = chord.timed;
        final (:channel, :instrument, :loudness) = sounds[staff]!;
        final position = onset + starts[index];
        final level = loudness.at(position);
        final trilled =
            trills[staff]?.any((t) => t.$1 <= position && position <= t.$2) ??
            false;
        for (final attack
            in trilled
                ? _attacks(chord.timed, chord.event, column.key, trill: true)
                : chord.attacks) {
          final (key, cents) = _key(attack.note, instrument);
          final start = bar.secondsAt(attack.onset);
          final end = bar.secondsAt(attack.onset + attack.length);
          final release = (end - start) * (1 - attack.gate);
          final lane = (staff, voice, attack.note.tone);
          final _Sounding note;
          if (ties.remove(lane) case (final held, final window, final expected)
              when window == k && expected == attack.onset) {
            note = held
              ..end = end
              ..release = release;
          } else {
            note = _Sounding(
              start: start,
              end: end,
              release: release,
              key: key,
              cents: cents,
              velocity: min((level * attack.stress).round(), 127),
              channel: channel,
              source: attack.source,
            );
            sounding.add(note);
          }
          if (attack.note.tie) {
            final after = attack.onset + attack.length;
            ties[lane] = after == Moment.zero + column.length
                ? (note, k + 1, Moment.zero)
                : (note, k, after);
          }
        }
      }
    }
    return PlaybackScript._(
      timeline,
      stableSorted(
        [for (final note in sounding) note.played],
        (a, b) => a.start.compareTo(b.start),
      ),
      totalSeconds: seconds,
      channels: channels,
      bars: [for (final bar in timeline) bar.played],
    );
  }
}

/// Where a staff's notes go and how loud its part plays.
typedef _Sound = ({int channel, Instrument instrument, _Loudness loudness});

/// Channels for pitched parts, in order. Channel 9 is General MIDI's
/// percussion channel.
const _melodicChannels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15];

/// A point in notated time from the start of the score.
Moment _place(
  Score score,
  List<Length> starts,
  MeasureId measure,
  Moment offset,
) => offset + starts[score.indexOf(measure)];

/// The MIDI key and cents [note] plays on [instrument]. A drum note plays
/// the kit sound it names.
(int, int) _key(Note note, Instrument instrument) => switch (note) {
  PitchedNote(:final pitch) => (pitch.midiKey, pitch.cents),
  DrumNote(:final drum) => (instrument.soundOf(drum)!.midiKey, 0),
};

/// A played bar with what the script needs to place times in it.
final class _Bar {
  const _Bar(
    this.played, {
    required this.from,
    required this.to,
    required this.clock,
    required this.heard,
  });

  final PlayedBar played;

  /// The part of the bar that plays: all of it, or the ends of a range.
  final Moment from;
  final Moment to;
  final _Clock clock;

  /// The chords that start in the played part, on parts not muted.
  final List<_Chord> heard;

  double secondsAt(Moment offset) =>
      played.start + clock.at(offset) - clock.at(from);
}

final class PlaybackOptions {
  const PlaybackOptions({this.from, this.to, this.muted = const {}});

  /// Play only `[from, to)` in notated order, ignoring repeats. The player
  /// loops the returned script when the user asked for a loop.
  final ScorePoint? from;
  final ScorePoint? to;

  final Set<PartId> muted;
}

/// A compiled score. Immutable; recompile after an edit (cheap, see the
/// library doc).
final class PlaybackScript {
  const PlaybackScript._(
    this._timeline,
    this._notes, {
    required this.totalSeconds,
    required this.channels,
    required this.bars,
  });

  final double totalSeconds;

  /// Program to load on each channel before playing.
  final List<ChannelSetup> channels;

  /// The unrolled play order with timings. The UI can show "2nd time".
  final List<PlayedBar> bars;

  final List<_Bar> _timeline;

  /// Sorted by start.
  final List<PlaybackNote> _notes;

  /// Notes whose start falls in `[from, to)` seconds, sorted by start. The
  /// player pulls windows ahead of a monotonic clock.
  Iterable<PlaybackNote> notesBetween(double from, double to) => _notes
      .skip(_partition(_notes.length, (i) => _notes[i].start >= from))
      .takeWhile((note) => note.start < to);

  /// Events sounding at [seconds], one per voice, for highlighting. An
  /// event sounds for its notated length, and rests sound nothing.
  List<EventRef> sourcesAt(double seconds) {
    final at = _partition(
      _timeline.length,
      (i) => _timeline[i].played.end > seconds,
    );
    if (at == _timeline.length) {
      return const [];
    }
    final bar = _timeline[at];
    final voices = <(StaffId, VoiceSlot)>{};
    return [
      for (final _Chord(timed: TimedEvent(:onset, :duration, :voice, :ref))
          in bar.heard)
        if (bar.secondsAt(onset) <= seconds &&
            seconds < bar.secondsAt(onset + duration) &&
            voices.add((ref.staff, voice)))
          ref,
    ];
  }

  /// When [point] is first reached, for starting playback at the cursor.
  /// Null if the point is not in the played range.
  double? secondsAt(ScorePoint point) {
    for (final bar in _timeline) {
      if (bar.played.measure == point.measure &&
          bar.from <= point.offset &&
          point.offset < bar.to) {
        return bar.secondsAt(point.offset);
      }
    }
    return null;
  }
}

final class PlaybackNote {
  const PlaybackNote({
    required this.start,
    required this.duration,
    required this.key,
    required this.velocity,
    required this.channel,
    required this.source,
    this.cents = 0,
  });

  /// Seconds from the script start.
  final double start;
  final double duration;

  /// MIDI key 0–127.
  final int key;

  /// 0 or 50 (quarter tones). The player applies pitch bend.
  final int cents;

  final int velocity;
  final int channel;

  /// The event that produced this note. A tie chain reports its first
  /// event; a grace note reports the grace chord's id.
  final EventRef source;
}

final class ChannelSetup {
  const ChannelSetup({
    required this.channel,
    required this.part,
    required this.program,
    this.bank = 0,
  });

  final int channel;
  final PartId part;
  final int program;
  final int bank;
}

final class PlayedBar {
  const PlayedBar({
    required this.measure,
    required this.pass,
    required this.start,
    required this.end,
  });

  final MeasureId measure;

  /// How many times the bar has played, counting this time: 1 for the
  /// first time through.
  final int pass;
  final double start;
  final double end;
}

/// A bar compiled in whole-note time relative to the bar. Depends on the
/// column alone, so it can be cached on the column. Hidden parts are
/// compiled too, because they play.
final class _Fragment {
  const _Fragment(this.chords, this.holds);

  /// In staff, voice and time order.
  final List<_Chord> chords;

  /// The time under each fermata, on any staff.
  final List<(Moment, Moment)> holds;
}

final class _Chord {
  const _Chord(this.timed, this.event, this.attacks);

  final TimedEvent timed;
  final ChordEvent event;

  /// What it plays when no trill line covers it.
  final List<_Attack> attacks;
}

/// One note struck, in whole-note time from the bar's downbeat.
final class _Attack {
  const _Attack({
    required this.onset,
    required this.length,
    required this.note,
    required this.stress,
    required this.gate,
    required this.source,
  });

  final Moment onset;
  final Length length;

  /// As played. Inside a figure only the last note keeps its tie.
  final Note note;

  /// The factor on its dynamic's velocity.
  final double stress;

  /// The share of [length] it sounds.
  final double gate;

  /// Its chord, or its grace chord.
  final EventRef source;
}

/// A note being placed in seconds. A tie chain extends it.
final class _Sounding {
  _Sounding({
    required this.start,
    required this.end,
    required this.release,
    required this.key,
    required this.cents,
    required this.velocity,
    required this.channel,
    required this.source,
  });

  final double start;
  double end;

  /// Seconds cut from the end, set by the chain's last note.
  double release;
  final int key;
  final int cents;
  final int velocity;
  final int channel;
  final EventRef source;

  PlaybackNote get played => PlaybackNote(
    start: start,
    duration: end - start - release,
    key: key,
    cents: cents,
    velocity: velocity,
    channel: channel,
    source: source,
  );
}

/// The first index in `[0, length)` where [reached] holds, given that it
/// holds from some index on, or [length] when it never does.
int _partition(int length, bool Function(int i) reached) {
  var low = 0;
  var high = length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (reached(mid)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}
