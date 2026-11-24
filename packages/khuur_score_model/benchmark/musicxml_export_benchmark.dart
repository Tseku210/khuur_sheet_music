// Checks that a MusicXML export costs in step with the length of the score.
// It exports four kinds of score, then each at four times the length, and
// compares the two times: slurs and trill lines on notes, hairpins written as
// directions, glissandi that name their notes, and a run of measure-repeat
// signs.
//
// Run it compiled, from packages/khuur_score_model. A JIT run measures the
// compiler as much as the code. The compiler does not create `build`, which
// git ignores.
//
//   mkdir -p build && dart compile exe benchmark/musicxml_export_benchmark.dart -o build/musicxml_export_benchmark
//   build/musicxml_export_benchmark
//
// It prints one line per score and one per kind, and exits with 1 when a
// longer score costs more than [_mostGrowth] times the shorter.

import 'dart:io';

import 'package:khuur_score_model/khuur_score_model.dart';

import 'erase_benchmark.dart' show glided;
import 'playback_benchmark.dart' show lined;

/// Four times the bars cost four times the time when the export is linear
/// and sixteen times when it is quadratic. The bound sits between, clear of
/// the noise of a busy machine.
const double _mostGrowth = 8;

/// A kind of score, the bars of its shorter score, and the element the
/// export writes `perBar` times in each bar.
typedef _Kind = ({
  String name,
  int bars,
  Score Function(int bars) score,
  String element,
  int perBar,
});

final List<_Kind> _kinds = [
  (name: 'notes', bars: 2000, score: lined, element: '<slur ', perBar: 2),
  (
    name: 'directions',
    bars: 4000,
    score: _hairpinned,
    element: '<wedge ',
    perBar: 2,
  ),
  (
    name: 'glissandi',
    bars: 2000,
    score: (bars) => glided(bars, named: true),
    element: '<glissando ',
    perBar: 2,
  ),
  (
    name: 'repeats',
    bars: 4000,
    score: _repeated,
    element: '<note>',
    perBar: 4,
  ),
];

/// [lined] with only a hairpin over each bar.
Score _hairpinned(int bars) {
  final score = lined(bars);
  final staff = score.staves.first.id;
  return score.copyWith(
    spanners: Seq([
      for (final (bar, column) in score.measures.indexed)
        Spanner(
          id: SpannerId(bar),
          kind: const Hairpin(crescendo: true),
          staff: staff,
          first: ScorePoint(column.id, Moment.zero),
          last: ScorePoint(
            column.id,
            Moment.zero + NoteValue.quarter.length * Fraction(3),
          ),
        ),
    ]),
  );
}

/// A bar of four quarters, then one-bar repeat signs to the end.
Score _repeated(int bars) {
  final score = lined(bars);
  return score.copyWith(
    spanners: const Seq.empty(),
    measures: Seq([
      for (final (bar, column) in score.measures.indexed)
        if (bar == 0)
          column
        else
          column.withStaff(
            column.staves.first.copyWith(
              voices: Seq([
                Voice(
                  slot: VoiceSlot.one,
                  items: Seq([
                    MeasureRest(
                      id: EventId(4 * bars + bar),
                      span: column.length,
                    ),
                  ]),
                ),
              ]),
              measureRepeat: () => MeasureRepeat.oneBar,
            ),
          ),
    ]),
  );
}

/// The median time of [runs] exports of [score], after [warmUps] that do not
/// count. Fails when an export has other than [bars] bars, or other than
/// [marks] of [element].
Duration exportTime(
  Score score, {
  required int bars,
  required String element,
  required int marks,
  int warmUps = 1,
  int runs = 5,
}) {
  final watch = Stopwatch();
  final times = <Duration>[];
  for (var i = 0; i < warmUps + runs; i++) {
    watch
      ..reset()
      ..start();
    final text = scoreToMusicXml(score);
    watch.stop();
    final written = '<measure '.allMatches(text).length;
    final found = element.allMatches(text).length;
    if (written != bars || found != marks) {
      throw StateError(
        'wrote $written bars and $found of $element, not $bars and $marks',
      );
    }
    if (i >= warmUps) {
      times.add(watch.elapsed);
    }
  }
  times.sort();
  return times[times.length ~/ 2];
}

void main() {
  var failed = false;
  for (final (:name, :bars, :score, :element, :perBar) in _kinds) {
    final times = [
      for (final length in [bars, 4 * bars])
        (
          length,
          exportTime(
            score(length),
            bars: length,
            element: element,
            marks: length * perBar,
          ),
        ),
    ];
    for (final (length, time) in times) {
      stdout.writeln(
        'export of $name: $length bars, median '
        '${(time.inMicroseconds / 1000).toStringAsFixed(3)} ms',
      );
    }
    final growth = times.last.$2.inMicroseconds / times.first.$2.inMicroseconds;
    final over = growth > _mostGrowth;
    failed = failed || over;
    stdout.writeln(
      'four times the bars of $name cost ${growth.toStringAsFixed(2)} times '
      'as much, bound $_mostGrowth${over ? ', FAILED' : ''}',
    );
  }
  exitCode = failed ? 1 : 0;
}
