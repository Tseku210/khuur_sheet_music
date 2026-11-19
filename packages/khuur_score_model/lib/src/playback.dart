/// Playback compilation (access pattern 6).
///
/// The score is compiled bar by bar. A bar's notes are compiled once into a
/// fragment in whole-note time and cached on the column object itself, so a
/// one-note edit recompiles one fragment. The part that runs on every
/// compile unrolls the repeats into a play order, folds tempo and each
/// part's dynamics over the bars, and places each played bar's fragment in
/// seconds, merging tie chains across the bars as they are played, and
/// holds what a part's pedal catches until the pedal lifts. Dynamics, slurs
/// and pedals are folded on every compile because a hairpin, a slur or a
/// pedal line is stored beside the columns it spans, not in them.
library;

import 'dart:math';

import 'events.dart';
import 'measure.dart';
import 'measure_repeats.dart';
import 'pitch.dart';
import 'refs.dart';
import 'rules.dart';
import 'score.dart';
import 'seq.dart';
import 'stable_sort.dart';
import 'time.dart';
import 'views.dart';
import 'voice_walk.dart';

part 'playback_attacks.dart';
part 'playback_dynamics.dart';
part 'playback_legato.dart';
part 'playback_order.dart';
part 'playback_pedal.dart';
part 'playback_tempo.dart';

/// Long-lived. Keep one per composer screen so its fragment cache survives
/// across edits.
final class PlaybackCompiler {
  /// Makes a compiler with an empty fragment cache.
  PlaybackCompiler();

  /// Fragments keyed by column identity. A column that an edit did not touch
  /// is the same object in the new score, so its fragment is reused. Entries
  /// die with their columns.
  final Expando<_Fragment> _fragments = Expando('playback fragments');

  /// The fragment of a bar under a measure-repeat sign, with the columns it
  /// borrows notes from. It is reused only while those are the same objects
  /// too, since an edit to a repeated bar leaves the repeating column as it
  /// was.
  final Expando<(List<MeasureColumn>, _Fragment)> _borrowed = Expando(
    'playback fragments of measure repeats',
  );

  _Fragment _fragmentOf(MeasureColumn column) =>
      _fragments[column] ??= _compileBar(column);

  /// What bar [index] plays. A staff under a measure-repeat sign plays the
  /// chords and fermatas of the bar the sign repeats on that staff, and
  /// keeps its own whole-bar rest as the event playing, so the sheet marks
  /// the sign.
  _Fragment _played(Seq<MeasureColumn> measures, int index) {
    final column = measures[index];
    final own = _fragmentOf(column);
    final from = <StaffId, MeasureColumn>{
      for (final (k, staff) in column.staves.indexed)
        if (playedBar(measures, index, k) case final bar when bar != index)
          staff.staff: measures[bar],
    };
    if (from.isEmpty) {
      return own;
    }
    final sources = from.values.toList();
    if (_borrowed[column] case (final was, final fragment)
        when was.length == sources.length &&
            Iterable<int>.generate(
              was.length,
            ).every((k) => identical(was[k], sources[k]))) {
      return fragment;
    }
    final chords = <_Chord>[];
    List<(Moment, Moment)> held(_Fragment of, bool Function(StaffId) on) => [
      for (final timed in of.events)
        if (on(timed.ref.staff) &&
            timed.event.articulations.contains(Articulation.fermata))
          (timed.onset, timed.onset + timed.duration),
    ];
    final holds = held(own, (staff) => !from.containsKey(staff));
    for (final staff in column.staves) {
      final source = from[staff.staff];
      final fragment = source == null ? own : _fragmentOf(source);
      chords.addAll(
        fragment.chords.where((c) => c.timed.ref.staff == staff.staff),
      );
      if (source != null) {
        holds.addAll(held(fragment, (id) => id == staff.staff));
      }
    }
    final fragment = _Fragment(own.events, chords, holds);
    _borrowed[column] = (sources, fragment);
    return fragment;
  }

  /// Compiles [score] into a script, playing what [options] asks.
  ///
  /// A bar whose column an edit did not replace reuses the fragment cached from
  /// an earlier compile.
  ///
  /// A staff's bar under a measure-repeat sign plays the notes of the bar
  /// the sign repeats, at its own place in the play order, so on every pass
  /// of a repeat and under a volta too. Each note plays with the dynamics,
  /// slur and trill line of the note it repeats. A dynamic or hairpin of the
  /// part written in the run of bars under signs takes over from where it
  /// stands to the end of the run.
  PlaybackScript compile(
    Score score, [
    PlaybackOptions options = const PlaybackOptions(),
  ]) {
    final measures = score.measures;
    final time = _Timeline(score);
    final tempo = _TempoMap(score, time);
    final (:channels, :sounds) = _soundSetup(score, options, time);
    final trills = _trillSpans(score, time);
    final slurs = _slurSpans(score, time);
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
      final fragment = _played(measures, index);
      final clock = _Clock(
        tempo,
        Moment.zero + time.startOf(index),
        column.length,
        fragment.holds,
      );
      final start = seconds;
      seconds += clock.at(to) - clock.at(from);
      bool plays(TimedEvent timed) =>
          sounds.containsKey(timed.ref.staff) &&
          from <= timed.onset &&
          timed.onset < to;
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
            if (plays(chord.timed)) chord,
        ],
        playing: fragment.events.where(plays).toList(),
      );
      timeline.add(bar);
      for (final chord in bar.heard) {
        final TimedEvent(:onset, :voice, ref: EventRef(:staff)) = chord.timed;
        final (:channel, :instrument, :loudness) = sounds[staff]!;
        final position = onset + time.startOf(index);
        final written = time.of(chord.timed.ref.measure, onset);
        final level = loudness.at(
          written == position ||
                  loudness.markedIn(
                    _underSignsFrom(measures, index, staff, time),
                    position,
                  )
              ? position
              : written,
        );
        final trilled =
            trills[staff]?.any((t) => t.$1 <= written && written <= t.$2) ??
            false;
        final slurred =
            slurs[(staff, voice)]?.any(
              (s) => s.$1 <= written && written < s.$2,
            ) ??
            false;
        for (final attack
            in trilled
                ? _attacks(chord.timed, chord.event, column.key, trill: true)
                : chord.attacks) {
          final (key, cents) = _key(attack.note, instrument);
          final start = bar.secondsAt(attack.onset);
          final end = bar.secondsAt(attack.onset + attack.length);
          final legato = slurred && attack.gate == null;
          final release = legato
              ? 0.0
              : (end - start) * (1 - (attack.gate ?? 0.9));
          final lane = (staff, voice, attack.note.tone);
          final _Sounding note;
          if (ties.remove(lane) case (final held, final window, final expected)
              when window == k && expected == attack.onset) {
            note = held
              ..end = end
              ..release = release
              ..legato = legato;
          } else {
            note = _Sounding(
              start: start,
              end: end,
              release: release,
              legato: legato,
              key: key,
              cents: cents,
              velocity: min((level * attack.stress).round(), 127),
              channel: channel,
              voice: voice,
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
    _join(sounding);
    final pedals = _pedals(score, time, windows, timeline);
    return PlaybackScript._(
      timeline,
      stableSorted(
        [for (final note in sounding) note.played(pedals[note.source.staff])],
        (a, b) => a.start.compareTo(b.start),
      ),
      totalSeconds: seconds,
      channels: channels,
      bars: [for (final bar in timeline) bar.played],
    );
  }
}

typedef _Sound = ({int channel, Instrument instrument, _Loudness loudness});

/// Where the run of bars under measure-repeat signs on [staff] that ends
/// with bar [index] starts.
Moment _underSignsFrom(
  Seq<MeasureColumn> measures,
  int index,
  StaffId staff,
  _Timeline time,
) {
  final k = measures[index].staves.indexWhere((s) => s.staff == staff);
  var first = index;
  while (first > 0 && measures[first - 1].staves[k].measureRepeat != null) {
    first--;
  }
  return Moment.zero + time.startOf(first);
}

typedef _Lane = (StaffId, VoiceSlot);

/// Channels for pitched parts, in order. Channel 9 is General MIDI's
/// percussion channel.
const _melodicChannels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15];

/// The tempo playback runs at through a score, from its tempo marks and its
/// tempo lines. Edits read it to keep the tempo of the bars they move.
final class PlayedTempo {
  /// Reads the tempo of every point of [score].
  factory PlayedTempo(Score score) {
    final time = _Timeline(score);
    return PlayedTempo._(time, _TempoMap(score, time));
  }

  PlayedTempo._(this._time, this._map);

  final _Timeline _time;
  final _TempoMap _map;

  /// The tempo at [offset] into [measure].
  Tempo at(MeasureId measure, Moment offset) =>
      _map.tempoAt(_time.of(measure, offset));

  /// The tempo [line] reaches at [offset] into [measure] when no later line
  /// takes over from it, or null when [line] is not a tempo line.
  Tempo? alongLine(SpannerId line, MeasureId measure, Moment offset) =>
      _map.pieceOf(line)?.tempoAt(_time.of(measure, offset));

  /// The tempo line still moving the tempo at [offset] into [measure], and
  /// the tempo it moves to, or null when the tempo holds there.
  ({SpannerId line, Tempo target})? movingAt(MeasureId measure, Moment offset) {
    final position = _time.of(measure, offset);
    return switch (_map.pieceAt(position)) {
      _TempoPiece(:final line?, :final to, :final target) when position < to =>
        (line: line, target: target),
      _ => null,
    };
  }
}

/// A window of one played bar: the bar's index in the score, which pass it is
/// on, and the part of it that plays.
typedef _Window = ({int index, int pass, Moment from, Moment to});

/// Where each bar of a score starts in notated time, and the points and
/// extents that the folds over the score place on that line. Positions count
/// from the start of the score.
final class _Timeline {
  _Timeline(this._score) {
    var elapsed = Length.zero;
    for (final column in _score.measures) {
      _starts.add(elapsed);
      elapsed += column.length;
    }
  }

  final Score _score;

  /// By bar index.
  final List<Length> _starts = [];

  /// How far into the score the bar at [index] starts.
  Length startOf(int index) => _starts[index];

  /// The point [offset] into [measure].
  Moment of(MeasureId measure, Moment offset) =>
      offset + _starts[_score.indexOf(measure)];

  /// Where [spanner] starts and where it reaches to, in time.
  (Moment, Moment) extentOf(Spanner spanner) => (
    of(spanner.first.measure, spanner.first.offset),
    of(spanner.last.measure, _score.endOf(spanner)),
  );
}

/// The channel and sound of every unmuted staff, and the channel setups to
/// send for the parts that are heard.
({List<ChannelSetup> channels, Map<StaffId, _Sound> sounds}) _soundSetup(
  Score score,
  PlaybackOptions options,
  _Timeline time,
) {
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
      final loudness = _Loudness(score, staves, time);
      for (final staff in staves) {
        sounds[staff.id] = (
          channel: channel,
          instrument: instrument,
          loudness: loudness,
        );
      }
    }
  }
  return (channels: channels, sounds: sounds);
}

/// The spans of every trill line, from its first point to its last point, by
/// staff.
Map<StaffId, List<(Moment, Moment)>> _trillSpans(
  Score score,
  _Timeline time,
) {
  final trills = <StaffId, List<(Moment, Moment)>>{};
  for (final Spanner(:kind, :staff, :first, :last) in score.spanners) {
    if (kind is TrillLine) {
      (trills[staff] ??= []).add((
        time.of(first.measure, first.offset),
        time.of(last.measure, last.offset),
      ));
    }
  }
  return trills;
}

/// Where each voice's slurs run, from the onset of the first slurred note
/// to the onset of the last.
Map<_Lane, List<(Moment, Moment)>> _slurSpans(Score score, _Timeline time) {
  final slurs = <_Lane, List<(Moment, Moment)>>{};
  for (final Spanner(:kind, :staff, :voice, :first, :last) in score.spanners) {
    if (kind is Slur) {
      final slot = voice ?? VoiceSlot.one;
      Moment onsetAt(ScorePoint point) => time.of(
        point.measure,
        score.anchorAt(staff, slot, point)!.onset,
      );
      (slurs[(staff, slot)] ??= []).add((onsetAt(first), onsetAt(last)));
    }
  }
  return slurs;
}

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
    required this.playing,
  });

  final PlayedBar played;

  /// The part of the bar that plays: all of it, or the ends of a range.
  final Moment from;
  final Moment to;
  final _Clock clock;

  /// The chords that start in the played part, on parts not muted.
  final List<_Chord> heard;

  /// The events that start in the played part, on parts not muted, rests
  /// too.
  final List<TimedEvent> playing;

  double secondsAt(Moment offset) =>
      played.start + clock.at(offset) - clock.at(from);

  /// Whole notes into the bar at [seconds] of the script.
  double wholesAt(double seconds) =>
      clock.wholesAt(seconds - played.start + clock.at(from));
}

/// What part of a score to play, and which parts to leave silent.
final class PlaybackOptions {
  /// By default the whole score plays, repeats unrolled, with every part heard.
  const PlaybackOptions({this.from, this.to, this.muted = const {}});

  /// The start of the range. Null starts at the first bar.
  ///
  /// Once [from] or [to] is set, only `[from, to)` plays, in notated order,
  /// with repeats and jumps ignored. With both null the whole score plays
  /// with its repeats unrolled. The player loops the returned script when
  /// the user asked for a loop.
  final ScorePoint? from;
  /// The end of the range, which does not play. Null plays to the end of the
  /// last bar.
  final ScorePoint? to;

  /// The parts that get no channel and no notes. Their events do not count in
  /// [PlaybackScript.playingAt] either.
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

  /// How long the script plays, in seconds.
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

  /// The bar playing at [seconds], or null outside `[0, totalSeconds)`.
  _Bar? _playing(double seconds) => switch (_playingIndex(seconds)) {
    final at? => _timeline[at],
    null => null,
  };

  /// The index in [_timeline] of the bar playing at [seconds], or null
  /// outside `[0, totalSeconds)`.
  int? _playingIndex(double seconds) {
    if (seconds < 0) {
      return null;
    }
    final at = _partition(
      _timeline.length,
      (i) => _timeline[i].played.end > seconds,
    );
    return at == _timeline.length ? null : at;
  }

  /// Events playing at [seconds], one per voice, for highlighting. An
  /// event plays for its notated length, and a rest plays like a note, so
  /// the reader keeps their place through it. The result includes events
  /// on hidden staves, because a hidden part plays.
  List<EventRef> playingAt(double seconds) {
    final bar = _playing(seconds);
    if (bar == null) {
      return const [];
    }
    final voices = <(StaffId, VoiceSlot)>{};
    return [
      for (final TimedEvent(:onset, :duration, :voice, :ref) in bar.playing)
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

  /// Where playback is at [seconds], for drawing a playhead. It is the
  /// inverse of the clock that times every note, on every pass, so it
  /// follows fermatas, tempo lines and tempo marks inside a bar. On the
  /// first pass it undoes [secondsAt]. Null outside `[0, totalSeconds)`.
  /// The instant a bar starts belongs to that bar.
  PlaybackPoint? pointAt(double seconds) {
    final at = _playingIndex(seconds);
    if (at == null) {
      return null;
    }
    final bar = _timeline[at];
    return PlaybackPoint(
      bar: bar.played,
      offset: bar.wholesAt(seconds),
      next: at + 1 < _timeline.length ? _timeline[at + 1].played : null,
    );
  }
}

/// The played bars of [script] as the clocks that time them, for a writer
/// that places the script in notated time, as a MIDI file does.
List<BarClock> barClocks(PlaybackScript script) => [
  for (final bar in script._timeline) BarClock._(bar),
];

/// How one played bar passes time, measured from the first point of it
/// that plays.
final class BarClock {
  BarClock._(this._bar);

  final _Bar _bar;

  /// The played bar this clock times.
  PlayedBar get played => _bar.played;

  /// How much of the bar plays: all of it, or the part a range keeps.
  Length get length => _bar.from.until(_bar.to);

  /// Where the tempo starts to hold or to move, first at zero and then in
  /// order. Each lasts until the next, or until [length].
  List<({Length at, bool steady})> get paces {
    final steps = _bar.clock._steps;
    final first =
        _partition(steps.length, (i) => steps[i].from > _bar.from) - 1;
    return [
      for (final step in steps.skip(first))
        if (step.from < _bar.to)
          (
            at: step.from <= _bar.from
                ? Length.zero
                : _bar.from.until(step.from),
            steady: step.pace.steady,
          ),
    ];
  }

  /// Seconds of the script at [into] past the first point that plays.
  double secondsAt(Length into) => _bar.secondsAt(_bar.from + into);
}

/// Where playback is at one moment of a script.
final class PlaybackPoint {
  /// A point [offset] whole notes into [bar], with the [next] bar to play.
  const PlaybackPoint({required this.bar, required this.offset, this.next});

  /// The bar being played, with its pass.
  final PlayedBar bar;

  /// The bar that plays after [bar], or null when [bar] plays last. After a
  /// repeat it is the bar the repeat returns to.
  final PlayedBar? next;

  /// How far into the bar, in whole notes from its downbeat. A double, not
  /// a [Moment], because a playhead moves continuously between onsets.
  final double offset;
}

/// One note for the player to send, timed in seconds of the script.
final class PlaybackNote {
  /// A note of [key] on [channel], [start] seconds into the script.
  const PlaybackNote({
    required this.start,
    required this.duration,
    required this.key,
    required this.velocity,
    required this.channel,
    required this.source,
    this.cents = 0,
    this.overlap = 0,
  });

  /// Seconds from the script start.
  final double start;

  /// How long it sounds, in seconds. It sounds until its key is let go, or
  /// until the pedal that holds it lifts.
  final double duration;

  /// Seconds of real time it sounds past [duration] at any speed, into the
  /// note after it under a slur.
  final double overlap;

  /// MIDI key 0–127.
  final int key;

  /// 0 or 50, the cents above [key] for a quarter tone. The player passes
  /// it to `MidiOutput.noteOn`, and `scoreToMidi` writes it as a pitch bend.
  final int cents;

  /// The MIDI velocity, from the dynamic at the note and its accents. It is
  /// 12 to 127, from [Dynamic.pppp] up to the cap.
  final int velocity;
  /// The MIDI channel, 0 to 15. Channel 9 plays percussion parts.
  final int channel;

  /// The event that produced this note. A tie chain reports its first
  /// event; a grace note reports the grace chord's id. A note a
  /// measure-repeat sign plays reports the written event it repeats.
  final EventRef source;
}

/// The program and bank one part plays with on its channel.
final class ChannelSetup {
  /// The setup of [channel] for [part].
  const ChannelSetup({
    required this.channel,
    required this.part,
    required this.program,
    this.bank = 0,
  });

  /// The MIDI channel, 0 to 15. A percussion part plays on 9, and pitched parts
  /// share channels in turn when there are more than 15.
  final int channel;
  /// The part it plays.
  final PartId part;
  /// The MIDI program, 0 to 127, of the part's instrument.
  final int program;
  /// The sound bank, 0 or more, of the part's instrument.
  final int bank;
}

/// One pass through a bar, and when in the script it plays.
final class PlayedBar {
  /// A pass through [measure] from [start] to [end] seconds.
  const PlayedBar({
    required this.measure,
    required this.pass,
    required this.start,
    required this.end,
  });

  /// The bar that plays.
  final MeasureId measure;

  /// How many times the bar has played, counting this time: 1 for the
  /// first time through.
  final int pass;
  /// Seconds from the script start to where the bar starts playing.
  final double start;
  /// Seconds from the script start to where the bar stops playing, which is
  /// where the next played bar starts.
  final double end;
}

/// A bar compiled in whole-note time relative to the bar. Depends on the
/// column alone, so it can be cached on the column. Hidden parts are
/// compiled too, because they play.
final class _Fragment {
  const _Fragment(this.events, this.chords, this.holds);

  /// Every event, rests too, in staff, voice and time order.
  final List<TimedEvent> events;

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

  /// The share of [length] its marks make it sound, or null where none do.
  final double? gate;

  /// Its chord, or its grace chord.
  final EventRef source;
}

/// A note being placed in seconds. A tie chain extends it.
final class _Sounding {
  _Sounding({
    required this.start,
    required this.end,
    required this.release,
    required this.legato,
    required this.key,
    required this.cents,
    required this.velocity,
    required this.channel,
    required this.voice,
    required this.source,
  });

  final double start;
  double end;

  /// Seconds cut from the end, set by the chain's last note.
  double release;

  /// Whether the chain's last note is slurred to the note after it and no
  /// mark sets its length.
  bool legato;
  double overlap = 0;
  final int key;
  final int cents;
  final int velocity;
  final int channel;
  final VoiceSlot voice;
  final EventRef source;

  _Lane get lane => (source.staff, voice);

  /// The note as it sounds. A [pedal] that is down when the key is let go
  /// holds it until the pedal lifts.
  PlaybackNote played(_Pedal? pedal) {
    final lift = pedal?.liftAfter(end - release);
    return PlaybackNote(
      start: start,
      duration: lift == null ? end - start - release : lift - start,
      overlap: lift == null ? overlap : 0,
      key: key,
      cents: cents,
      velocity: velocity,
      channel: channel,
      source: source,
    );
  }
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
