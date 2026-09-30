/// Playback compilation (access pattern 6).
///
/// The score is compiled bar by bar. A bar's notes are compiled once into a
/// fragment in whole-note time and cached on the column object itself, so a
/// one-note edit recompiles one fragment. The cheap part, which runs on
/// every compile, folds tempo and dynamics over the bars and unrolls the
/// repeats into a play order. Seconds are computed only when the player
/// asks for a window of notes.
library;

import 'measure.dart';
import 'refs.dart';
import 'score.dart';
import 'seq.dart';
import 'time.dart';

/// Long-lived. Keep one per composer screen so its fragment cache survives
/// across edits.
final class PlaybackCompiler {
  PlaybackCompiler();

  /// Fragments keyed by column identity. A column that an edit did not touch
  /// is the same object in the new score, so its fragment is reused. Entries
  /// die with their columns.
  // Read by `compile` once its body is written.
  // ignore: unused_field
  final Expando<List<_Fragment>> _fragments = Expando('playback fragments');

  PlaybackScript compile(
    Score score, [
    PlaybackOptions options = const PlaybackOptions(),
  ]) {
    // TODO: notes from the cached fragments, shaped by dynamics, hairpins
    // and fermatas, and one channel per part.
    final measures = score.measures;
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
    var seconds = 0.0;
    for (final (:index, :pass, :from, :to) in windows) {
      final column = measures[index];
      final clock = _Clock(entries[index], column.tempos);
      final start = seconds;
      seconds += clock.at(to) - clock.at(from);
      timeline.add(
        _Bar(
          PlayedBar(
            measure: column.id,
            pass: pass,
            start: start,
            end: seconds,
          ),
          from: from,
          to: to,
          clock: clock,
        ),
      );
    }
    return PlaybackScript._(
      timeline,
      totalSeconds: seconds,
      channels: const [],
      bars: [for (final bar in timeline) bar.played],
    );
  }

  /// Compiles one bar into notes in whole-note time relative to the bar.
  // TODO: for each visible or hidden staff (hidden parts still play), each
  // voice, each TimedEvent:
  //   - skip heads that a tie from the previous event lands on;
  //   - for heads with `tie`, follow the chain (into the next notated bar if
  //     needed) and sum sounding lengths: one attack, merged duration;
  //   - velocity = entry dynamic, updated by in-bar DynamicMarks, shaped by
  //     hairpin interpolation, +accent/marcato, sf/sfz/fp for one event;
  //   - length shaping: staccato 1/2, staccatissimo 1/4, tenuto full,
  //     default 0.9 of the notated length; fermata holds (from step 2);
  //   - grace chords: acciaccatura just before the beat, appoggiatura takes
  //     half the principal's length; tremolo strokes and the chord's
  //     ornament (trill, mordent, turn) expand to notes; percussion heads
  //     map through Instrument.drums;
  //   - key and cents from Pitch.midiKey / Pitch.cents (pitch is already
  //     concert; 8va lines and transposition are display-only).
  // ignore: unused_element
  List<_Fragment> _compileBar(Score score, MeasureColumn column) =>
      throw UnimplementedError();
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
  });

  final PlayedBar played;

  /// The part of the bar that plays: all of it, or the ends of a range.
  final Moment from;
  final Moment to;
  final _Clock clock;

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
    this._timeline, {
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

  /// Notes whose start falls in `[from, to)` seconds, sorted by start. The
  /// player pulls windows ahead of a monotonic clock.
  Iterable<PlaybackNote> notesBetween(double from, double to) {
    // TODO: binary search `bars` for the first bar ending after `from`;
    // convert that bar's fragment notes from whole-note time to seconds with
    // the bar's tempo map; continue until a bar starts at or after `to`.
    throw UnimplementedError();
  }

  /// Events sounding at [seconds], one per voice, for highlighting.
  List<EventRef> sourcesAt(double seconds) => throw UnimplementedError();

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

/// One note of a compiled bar, in whole-note time relative to the bar.
final class _Fragment {
  const _Fragment({
    required this.onset,
    required this.length,
    required this.key,
    required this.cents,
    required this.velocity,
    required this.part,
    required this.source,
  });

  final Moment onset;

  /// May reach past the bar end when a tie chain continues.
  final Length length;
  final int key;
  final int cents;
  final int velocity;
  final PartId part;
  final EventRef source;
}
