/// Playback compilation (access pattern 6).
///
/// The score is compiled bar by bar. A bar's notes are compiled once into a
/// fragment in whole-note time and cached on the column object itself, so a
/// one-note edit recompiles one fragment. The part that runs on every
/// compile unrolls the repeats into a play order, folds tempo over the bars,
/// and places each played bar's fragment in seconds, merging tie chains
/// across the bars as they are played.
library;

import 'events.dart';
import 'measure.dart';
import 'pitch.dart';
import 'refs.dart';
import 'score.dart';
import 'seq.dart';
import 'time.dart';
import 'voice_walk.dart';

/// Long-lived. Keep one per composer screen so its fragment cache survives
/// across edits.
final class PlaybackCompiler {
  PlaybackCompiler();

  /// Fragments keyed by column identity. A column that an edit did not touch
  /// is the same object in the new score, so its fragment is reused. Entries
  /// die with their columns.
  final Expando<List<_Fragment>> _fragments = Expando('playback fragments');

  PlaybackScript compile(
    Score score, [
    PlaybackOptions options = const PlaybackOptions(),
  ]) {
    // TODO: shape velocity by dynamics, hairpins and accents, and length by
    // articulations and fermatas.
    final measures = score.measures;
    final channels = <ChannelSetup>[];
    final sounds = <StaffId, (int, Instrument)>{};
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
        for (final staff in staves) {
          sounds[staff.id] = (channel, instrument);
        }
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
    final entries = <Tempo>[];
    var tempo = Tempo.unmarked;
    for (final column in measures) {
      entries.add(tempo);
      tempo = column.tempos.lastOrNull?.tempo ?? tempo;
    }
    final timeline = <_Bar>[];
    final sounding = <_Sounding>[];
    final ties = <(StaffId, VoiceSlot, Pitch), (_Sounding, int, Moment)>{};
    var seconds = 0.0;
    for (final (k, (:index, :pass, :from, :to)) in windows.indexed) {
      final column = measures[index];
      final clock = _Clock(entries[index], column.tempos);
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
          for (final fragment in _fragments[column] ??= _compileBar(column))
            if (sounds.containsKey(fragment.source.staff) &&
                from <= fragment.onset &&
                fragment.onset < to)
              fragment,
        ],
      );
      timeline.add(bar);
      for (final fragment in bar.heard) {
        final (channel, instrument) = sounds[fragment.source.staff]!;
        final key = _key(fragment.note, instrument);
        if (key == null) {
          continue;
        }
        final start = bar.secondsAt(fragment.onset);
        final end = bar.secondsAt(fragment.onset + fragment.length);
        final lane = (
          fragment.source.staff,
          fragment.voice,
          fragment.note.pitch,
        );
        final _Sounding note;
        if (ties.remove(lane) case (final held, final at, final onset)
            when at == k && onset == fragment.onset) {
          note = held
            ..end = end
            ..last = end - start;
        } else {
          note = _Sounding(
            start: start,
            end: end,
            key: key,
            cents: fragment.note.pitch.cents,
            channel: channel,
            source: fragment.source,
          );
          sounding.add(note);
        }
        if (fragment.note.tie) {
          final after = fragment.onset + fragment.length;
          ties[lane] = after == Moment.zero + column.length
              ? (note, k + 1, Moment.zero)
              : (note, k, after);
        }
      }
    }
    final notes = [for (final note in sounding) note.played];
    final order = [for (var i = 0; i < notes.length; i++) i]
      ..sort((a, b) {
        final byStart = notes[a].start.compareTo(notes[b].start);
        return byStart != 0 ? byStart : a.compareTo(b);
      });
    return PlaybackScript._(
      timeline,
      [for (final i in order) notes[i]],
      totalSeconds: seconds,
      channels: channels,
      bars: [for (final bar in timeline) bar.played],
    );
  }
}

/// Channels for pitched parts, in order. Channel 9 is General MIDI's
/// percussion channel.
const _melodicChannels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15];

/// A bar's notes in whole-note time relative to the bar, one per head, in
/// staff, voice and time order. Depends on the column alone, so it can be
/// cached on the column. Hidden parts are compiled too, because they play.
// TODO: velocity inputs from DynamicMarks and accents, length shaping from
// articulations, grace chords (acciaccatura just before the beat,
// appoggiatura taking half the principal), tremolo strokes and ornaments.
List<_Fragment> _compileBar(MeasureColumn column) => [
  for (final measure in column.staves)
    for (final voice in measure.voices)
      for (final timed in timedEvents(
        voice,
        measure: column.id,
        staff: measure.staff,
      ))
        if (timed.event case ChordEvent(:final notes))
          for (final note in notes)
            _Fragment(
              onset: timed.onset,
              length: timed.duration,
              note: note,
              voice: timed.voice,
              source: timed.ref,
            ),
];

/// The MIDI key [note] plays on [instrument]. A drum note plays the sound
/// at its position with its head, or else the first at its position, and
/// nothing when no sound sits there.
int? _key(Note note, Instrument instrument) {
  if (!instrument.isPercussion) {
    return note.pitch.midiKey;
  }
  final there = instrument.drums.where((d) => d.position == note.pitch);
  return (there.where((d) => d.head == note.head).firstOrNull ??
          there.firstOrNull)
      ?.midiKey;
}

/// Unrolls repeats, voltas and navigation into (bar index, pass) pairs,
/// where pass counts the times the bar has played, this one included.
///
/// An end repeat returns to the last start repeat, or to the bar after the
/// previous repeated section, or to the score start. A bar under a volta
/// plays on the passes its endings list. A section being repeated ends
/// after its end repeat, or after the last bar of the endings that hold its
/// end repeat. A [Jump] is taken once, after the repeats of its bar are
/// done. A D.S. without a [Segno] goes to the start. After the jump,
/// repeats are not taken, a bar under a volta plays only if it is under
/// the last ending of its run, and the jump's [JumpThen] says whether [Fine] stops or
/// [ToCoda] leaves for the [Coda], once. A loop guard stops at 64 × bar
/// count.
List<({int index, int pass})> _playOrder(Seq<MeasureColumn> measures) {
  final segno = measures.indexWhere(
    (c) => c.navigation.contains(const Segno()),
  );
  final coda = measures.indexWhere((c) => c.navigation.contains(const Coda()));
  final plays = List.filled(measures.length, 0);
  final order = <({int index, int pass})>[];
  var i = 0;
  var pass = 1;
  var start = 0;
  int? sectionEnd;
  Jump? jump;
  var codaTaken = false;
  while (i < measures.length && order.length < 64 * measures.length) {
    final column = measures[i];
    if ((sectionEnd != null && i > sectionEnd) ||
        (column.repeatStart && i != start)) {
      pass = 1;
      start = i;
      sectionEnd = null;
    }
    final volta = column.volta;
    if (volta != null &&
        (jump == null
            ? !volta.endings.contains(pass)
            : volta != measures[_endingsEnd(measures, i)].volta)) {
      i++;
      continue;
    }
    order.add((index: i, pass: ++plays[i]));
    final marks = column.navigation;
    if (jump != null) {
      if (jump.then == JumpThen.toFine && marks.contains(const Fine())) {
        break;
      }
      if (jump.then == JumpThen.toCoda &&
          marks.contains(const ToCoda()) &&
          coda >= 0 &&
          !codaTaken) {
        codaTaken = true;
        i = coda;
        continue;
      }
    } else {
      final end = column.repeatEnd;
      if (end != null && pass < end.times) {
        pass++;
        sectionEnd = _endingsEnd(measures, i);
        i = start;
        continue;
      }
      jump = marks.whereType<Jump>().firstOrNull;
      if (jump != null) {
        i = jump.target == JumpTarget.segno && segno >= 0 ? segno : 0;
        continue;
      }
    }
    i++;
  }
  return order;
}

/// The last bar of the run of volta bars holding bar [i], or [i] when it
/// has no volta.
int _endingsEnd(Seq<MeasureColumn> measures, int i) {
  var end = i;
  while (measures[end].volta != null &&
      end + 1 < measures.length &&
      measures[end + 1].volta != null) {
    end++;
  }
  return end;
}

/// The bars of `[from, to)` in notated order, once, each with the part of
/// it that plays.
List<({int index, int pass, Moment from, Moment to})> _range(
  Score score,
  ScorePoint? from,
  ScorePoint? to,
) {
  final first = from == null ? 0 : score.indexOf(from.measure);
  final last = to == null
      ? score.measures.length - 1
      : score.indexOf(to.measure);
  return [
    for (var i = first; i <= last; i++)
      if ((
            index: i,
            pass: 1,
            from: i == first && from != null ? from.offset : Moment.zero,
            to: i == last && to != null
                ? to.offset
                : Moment.zero + score.measures[i].length,
          )
          case final window when window.from < window.to)
        window,
  ];
}

/// Seconds from a bar's downbeat, at the tempo in effect there and then at
/// each of the bar's tempo marks.
final class _Clock {
  _Clock(Tempo entry, Seq<TempoMark> marks)
    : _changes = [
        (Moment.zero, entry),
        for (final mark in marks) (mark.offset, mark.tempo),
      ];

  final List<(Moment, Tempo)> _changes;

  double at(Moment offset) {
    var seconds = 0.0;
    for (final (k, (from, tempo)) in _changes.indexed) {
      if (from >= offset) {
        break;
      }
      final next = k + 1 < _changes.length ? _changes[k + 1].$1 : offset;
      seconds += tempo.secondsFor(from.until(next < offset ? next : offset));
    }
    return seconds;
  }
}

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

  /// The fragment notes that start in the played part, on parts not muted.
  final List<_Fragment> heard;

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
      for (final fragment in bar.heard)
        if (bar.secondsAt(fragment.onset) <= seconds &&
            seconds < bar.secondsAt(fragment.onset + fragment.length) &&
            voices.add((fragment.source.staff, fragment.voice)))
          fragment.source,
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

/// One head of a compiled bar, in whole-note time relative to the bar.
final class _Fragment {
  const _Fragment({
    required this.onset,
    required this.length,
    required this.note,
    required this.voice,
    required this.source,
  });

  final Moment onset;
  final Length length;
  final Note note;
  final VoiceSlot voice;
  final EventRef source;
}

/// A note being placed in seconds. A tie chain extends it.
final class _Sounding {
  _Sounding({
    required this.start,
    required this.end,
    required this.key,
    required this.cents,
    required this.channel,
    required this.source,
  }) : last = end - start;

  final double start;
  double end;

  /// Seconds of the chain's last note, which the release shortens.
  double last;
  final int key;
  final int cents;
  final int channel;
  final EventRef source;

  PlaybackNote get played => PlaybackNote(
    start: start,
    duration: end - start - last * 0.1,
    key: key,
    cents: cents,
    velocity: Dynamic.mf.velocity,
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
