// Gate 2 of docs/design/layout/RATIONALE.md, decision 10. It measures what a
// first layout and an update after one entered note cost on two fixtures,
// and judges them against the budgets for the development host. It also
// reports what assembling every system, and the systems an update rekeyed,
// costs on top, which the design does not budget.
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

import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_model/score_model.dart';

import '../test/support/fake_measurer.dart';
import '../test/support/fixtures.dart';
import 'harness.dart';

const FakeMeasurer _text = FakeMeasurer();

/// The sheet every fixture is broken at, in staff spaces. A printed page is
/// about this wide.
const double _sheetWidth = 100;

SheetLayout firstLayout(Score score) =>
    SheetLayout(score, width: _sheetWidth, text: _text);

/// Assembles [systems] and returns how many bars they hold, so a run has a
/// result to report.
int assembleSystems(SheetLayout layout, Iterable<int> systems) {
  var bars = 0;
  for (final index in systems) {
    bars += layout.systemAt(index).bars.length;
  }
  return bars;
}

Iterable<int> allSystems(SheetLayout layout) =>
    Iterable<int>.generate(layout.systemCount);

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
    run: (copy) => firstLayout(copy).delta.relaid.length,
    budget: fixture.firstLayoutBudget,
  );

  final assembled = measure(
    '${fixture.name} every system assembled',
    prepare: () => firstLayout(score),
    run: (laid) => assembleSystems(laid, allSystems(laid)),
  );

  // Every system is assembled first, so the update carries the memo a view
  // would have.
  final laid = firstLayout(score);
  assembleSystems(laid, allSystems(laid));
  final session = EditSession.start(score);
  final note = noteInBar(score, fixture.editedBar);
  final updated = measure(
    '${fixture.name} update',
    prepare: () => scoreAfter(session, note),
    run: (next) => laid.update(next).delta.relaid.length,
    budget: fixture.updateBudget,
  );

  final reassembled = measure(
    '${fixture.name} update and the rekeyed systems assembled',
    prepare: () => scoreAfter(session, note),
    run: (next) {
      final layout = laid.update(next);
      return assembleSystems(layout, layout.delta.rekeyed);
    },
  );

  // The overlay queries read assembled systems and lay nothing out. The
  // design budgets none of them. Each reports the bars of the system it
  // read, through its result so that the query is not dropped.
  final edited = score.measures[fixture.editedBar - 1].id;
  final system = laid.systemOf(edited)!;
  final middle = SpPoint(
    _sheetWidth / 2,
    laid.tops[system] + laid.heightOf(system) / 2,
  );
  int barsAround(MeasureId measure) =>
      laid.systemAt(laid.systemOf(measure)!).bars.length;
  final tapped = measure(
    '${fixture.name} hitTest',
    prepare: () => laid,
    run: (laid) => barsAround(laid.hitTest(middle, reach: 0.5)!.at.measure),
  );
  final cursor = VoicePoint(
    staff: score.staves.first.id,
    voice: VoiceSlot.one,
    at: ScorePoint(edited, Moment.zero),
  );
  final caret = measure(
    '${fixture.name} caretOf',
    prepare: () => laid,
    run: (laid) =>
        laid.caretOf(cursor)!.height.isFinite ? barsAround(edited) : 0,
  );
  final script = PlaybackCompiler().compile(score);
  final point = script.pointAt(script.totalSeconds / 2)!;
  final playhead = measure(
    '${fixture.name} playheadAt',
    prepare: () => laid,
    run: (laid) => laid.playheadAt(point)!.height.isFinite
        ? barsAround(point.bar.measure)
        : 0,
  );

  return [first, assembled, updated, reassembled, tapped, caret, playhead];
}

void main() {
  exitCode = report(fixtures.expand(measureFixture).toList(), stdout);
}
