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

import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/breaking.dart';
import 'package:score_layout/src/signatures.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';

import '../test/support/fake_measurer.dart';
import '../test/support/fixtures.dart';
import 'harness.dart';

const EngravingStyle _style = EngravingStyle.standard;
const FakeMeasurer _text = FakeMeasurer();

/// The sheet every fixture is broken at, in staff spaces. A printed page is
/// about this wide.
const double _sheetWidth = 100;

/// What a layout keeps for the update after it.
typedef Laid = ({
  Score score,
  Map<MeasureId, BarLayout> bars,
  Breaks breaks,

  /// How many bars this layout laid out, as against carried over.
  int laidOut,
});

/// A first layout of [score]: the model's view of every bar, the bar layout
/// of each, and the bars broken into planned systems. The units the engine
/// still lacks add their cost here as they land.
Laid firstLayout(Score score) {
  final bars = {
    for (final column in score.measures)
      column.id: layoutBar(score.measureView(column.id), _style, _text),
  };
  return (
    score: score,
    bars: bars,
    breaks: breakSystems(
      bars: [...bars.values],
      width: _sheetWidth,
      lead: systemLead(score, _style, _text),
      style: _style,
      text: _text,
    ),
    laidOut: bars.length,
  );
}

/// The update of [laid] to [next]: the bars the model says to lay out again,
/// each read and laid out, and the breaks resumed from the ones before.
Laid update(Laid laid, Score next) {
  final changes = next.changesSince(laid.score);
  final bars = {
    for (final column in next.measures)
      column.id: switch (laid.bars[column.id]) {
        final kept? when !changes.relayout.contains(column.id) => kept,
        _ => layoutBar(next.measureView(column.id), _style, _text),
      },
  };
  return (
    score: next,
    bars: bars,
    breaks: breakSystems(
      bars: [...bars.values],
      width: _sheetWidth,
      lead: identical(next.parts, laid.score.parts)
          ? laid.breaks.lead
          : systemLead(next, _style, _text),
      style: _style,
      text: _text,
      previous: laid.breaks,
    ),
    laidOut: changes.relayout.length,
  );
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
    run: (copy) => firstLayout(copy).laidOut,
    budget: fixture.firstLayoutBudget,
  );

  // An update starts from a score that was laid out, with its indexes built.
  final laid = firstLayout(score);
  final session = EditSession.start(score);
  final note = noteInBar(score, fixture.editedBar);
  final updated = measure(
    '${fixture.name} update',
    prepare: () => scoreAfter(session, note),
    run: (next) => update(laid, next).laidOut,
    budget: fixture.updateBudget,
  );

  return [first, updated];
}

void main() {
  exitCode = report(fixtures.expand(measureFixture).toList(), stdout);
}
