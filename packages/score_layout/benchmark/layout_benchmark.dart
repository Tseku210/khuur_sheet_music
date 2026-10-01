// Gate 2 of docs/design/layout/RATIONALE.md, decision 10. It measures what a
// first layout and an update after one entered note cost on two fixtures,
// and judges them against the budgets for the development host.
//
// Run it compiled, from packages/score_layout. A JIT run measures the
// compiler as much as the code. The compiler does not create `build`, which
// git ignores.
//
//   mkdir -p build && dart compile exe benchmark/layout_benchmark.dart -o build/layout_benchmark
//   build/layout_benchmark
//
// It prints one line per measurement and exits with 1 when one is over its
// budget.

import 'dart:io';

import 'package:score_model/score_model.dart';

import '../test/support/fixtures.dart';
import 'harness.dart';

/// A first layout of [score]. Until the engine exists this is its floor,
/// the model reads a layout must make. Returns the number of bars read.
int firstLayout(Score score) {
  for (final column in score.measures) {
    score.measureView(column.id);
  }
  return score.measures.length;
}

/// The update of a layout of [before] to [next]. Until the engine exists
/// this is its floor, the model reads an update must make. Returns the
/// number of bars read again.
int update(Score before, Score next) {
  final changes = next.changesSince(before);
  changes.relayout.forEach(next.measureView);
  return changes.relayout.length;
}

typedef Fixture = ({
  String name,
  Score Function() build,
  int editedBar,
  Duration firstLayoutBudget,
  Duration? updateBudget,
});

/// The budgets of decision 10. The second fixture has four times the bars
/// and four times the first layout budget, and the design names no update
/// budget for it. Bars are counted from 1.
const List<Fixture> fixtures = [
  (
    name: 'dense',
    build: denseScore,
    editedBar: 250,
    firstLayoutBudget: Duration(milliseconds: 50),
    updateBudget: Duration(milliseconds: 1),
  ),
  (
    name: 'spanner',
    build: spannerScore,
    editedBar: 1000,
    firstLayoutBudget: Duration(milliseconds: 200),
    updateBudget: null,
  ),
];

List<Measurement> measureFixture(Fixture fixture) {
  final watch = Stopwatch()..start();
  final score = fixture.build();
  watch.stop();
  stdout.writeln(
    '${fixture.name} fixture: ${score.measures.length} bars, '
    '${score.staves.length} staves, ${score.spanners.length} spanners, '
    'built in ${watch.elapsedMilliseconds} ms',
  );

  // A copy shares the music and has none of the indexes a score builds on
  // first use, so every run pays for them as a newly loaded score does.
  final first = measure(
    '${fixture.name} first layout',
    prepare: score.copyWith,
    run: firstLayout,
    budget: fixture.firstLayoutBudget,
  );

  // An update starts from a score that was laid out, with its indexes built.
  firstLayout(score);
  final session = EditSession.start(score);
  final note = noteInBar(score, fixture.editedBar);
  final updated = measure(
    '${fixture.name} update',
    prepare: () => scoreAfter(session, note),
    run: (next) => update(score, next),
    budget: fixture.updateBudget,
  );

  return [first, updated];
}

void main() {
  exitCode = report(fixtures.expand(measureFixture).toList(), stdout);
}
