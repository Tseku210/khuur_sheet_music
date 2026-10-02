import 'dart:math' as math;

import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/breaking.dart';
import 'package:score_layout/src/chords.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/signatures.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/bars.dart';
import 'support/fake_measurer.dart';

const EngravingStyle style = EngravingStyle.standard;
const EngravingStyle folding = EngravingStyle(multiMeasureRests: true);
const SystemLead lead = SystemLead(parts: [], firstIndent: 6, indent: 2);
const SystemLead flush = SystemLead(parts: [], firstIndent: 0, indent: 0);

/// A score whose bar `b` holds `counts[b]` equal notes on every staff, or a
/// whole-bar rest where the count is 0.
Score barsOf(List<int> counts, {int staves = 1}) => scoreOf([
  for (final (b, count) in counts.indexed)
    [
      for (var s = 0; s < staves; s++)
        staffOf([
          if (count == 0)
            MeasureRest(
              id: EventId(b * 100 + s * 20 + 1),
              span: Meter.fourFour.length,
            )
          else
            for (var k = 0; k < count; k++)
              chordOf(
                b * 100 + s * 20 + k + 1,
                'B4',
                value: NoteValue(
                  DurationBase.values.firstWhere(
                    (base) => base.length == Length(Fraction(1, count)),
                  ),
                ),
              ),
        ]),
    ],
]);

List<BarLayout> layoutsOf(Score score) => [
  for (final column in score.measures)
    layoutBar(score.measureView(column.id), style, const FakeMeasurer()),
];

Breaks breaksOf(
  List<BarLayout> bars,
  double width, {
  SystemLead lead = lead,
  EngravingStyle style = style,
  Breaks? previous,
}) => breakSystems(
  bars: bars,
  width: width,
  lead: lead,
  style: style,
  text: const FakeMeasurer(),
  previous: previous,
);

/// The natural width of a system of the units [from] to [to], by the rule on
/// [BarWidths].
double naturalOf(
  List<BreakUnit> units,
  int from,
  int to, {
  SystemLead lead = lead,
}) {
  var width =
      (from == 0 ? lead.firstIndent : lead.indent) +
      units[from].widths.systemHead +
      (to + 1 < units.length ? units[to + 1].widths.courtesy : 0);
  for (var i = from; i <= to; i++) {
    width +=
        units[i].widths.body + (i == from ? 0 : units[i].widths.inlineHead);
  }
  return width;
}

/// The first and last unit index of each system.
List<(int, int)> systemsOf(Breaks breaks) {
  final at = [
    for (final start in breaks.starts)
      breaks.units.indexWhere((unit) => unit.first.measure == start),
    breaks.units.length,
  ];
  return [for (var i = 0; i + 1 < at.length; i++) (at[i], at[i + 1] - 1)];
}

List<int> startsOf(Breaks breaks) => [
  for (final start in breaks.starts) start.value - 3000,
];

/// How wide the slices of [plan] are at its stretch.
double springsOf(SystemPlan plan) => [
  for (final unit in plan.key.units)
    for (final slice in unit.slices)
      math.max(slice.rod, slice.ideal * plan.stretch),
].fold(0, (sum, width) => sum + width);

/// Where the system of [plan] ends at its stretch.
double endOf(SystemPlan plan) {
  final units = plan.key.units;
  var x =
      plan.indent +
      units.first.widths.systemHead +
      (plan.key.next?.widths.courtesy ?? 0) +
      springsOf(plan);
  for (final (index, unit) in units.indexed) {
    x += unit.lead + (index == 0 ? 0 : unit.widths.inlineHead);
  }
  return x;
}

void main() {
  group('breakSystems', () {
    final twelve = layoutsOf(barsOf(List.filled(12, 4)));

    /// A sheet that takes three of [twelve]'s bars a system, with 5 to
    /// spare on the first.
    final sheet = naturalOf(foldBars(twelve, style), 0, 2) + 5;

    /// Bar [index] of [twelve] laid out again with [count] notes.
    BarLayout barOf(int index, int count) => layoutsOf(
      barsOf([...List.filled(index, 4), count]),
    )[index];

    test('a sheet wide enough takes every bar on one system', () {
      final breaks = breaksOf(twelve, 1000);

      expect(startsOf(breaks), [0]);
      expect(breaks.plans.single.bars, [
        for (var bar = 0; bar < 12; bar++) barId(bar),
      ]);
    });

    test('a bar with a system or a page break starts a system', () {
      final score = after(barsOf(List.filled(6, 4)), [
        SetBreak(barId(2), LayoutBreak.system),
        SetBreak(barId(3), LayoutBreak.page),
      ]);

      expect(startsOf(breaksOf(layoutsOf(score), 1000)), [0, 2, 3]);
    });

    test('a system of two bars or more fits the sheet, and takes every bar '
        'that fits', () {
      final score = after(
        barsOf([4, 16, 1, 8, 2, 16, 16, 4, 1, 1, 8, 4, 2, 16, 4, 8, 1, 2]),
        [
          SetKey(from: barId(3), key: const KeySignature(4)),
          SetKey(from: barId(9), key: const KeySignature(-3)),
          SetMeter(
            from: barId(12),
            meter: Meter.cut,
            content: MeterContent.keepBars,
          ),
          SetBreak(barId(15), LayoutBreak.system),
        ],
      );
      final bars = layoutsOf(score);
      var joined = 0;

      for (final width in [20.0, 45.0, 60.0, 80.0, 100.0, 140.0]) {
        final breaks = breaksOf(bars, width);
        final systems = systemsOf(breaks);

        expect(systems.first.$1, 0);
        for (final (index, (from, to)) in systems.indexed) {
          final reason = 'width $width, system $index';
          if (index > 0) {
            expect(from, systems[index - 1].$2 + 1, reason: reason);
          }
          if (to > from) {
            joined++;
            expect(
              naturalOf(breaks.units, from, to),
              lessThanOrEqualTo(width),
              reason: reason,
            );
          }
          if (to + 1 < bars.length && bars[to + 1].breakBefore == null) {
            expect(
              naturalOf(breaks.units, from, to + 1),
              greaterThan(width),
              reason: reason,
            );
          }
        }
        expect(systems.last.$2, bars.length - 1);
        expect(breaks.starts, contains(barId(15)));
      }
      expect(joined, greaterThan(10));
    });

    test('a system that fills the sheet exactly keeps its last bar', () {
      final exact =
          twelve[0].widths.systemHead +
          twelve[0].widths.body +
          twelve[1].widths.body +
          twelve[2].widths.body;

      expect(startsOf(breaksOf(twelve, exact, lead: flush)).take(2), [0, 3]);
      expect(
        startsOf(breaksOf(twelve, exact - 1e-6, lead: flush)).take(2),
        [0, 2],
      );
    });

    test('a bar wider than the sheet takes a system alone, as wide as its '
        'rods', () {
      final bars = layoutsOf(barsOf([16, 16, 16]));
      final breaks = breaksOf(bars, 10, lead: flush);
      final plan = breaks.plans[1];

      expect(startsOf(breaks), [0, 1, 2]);
      expect(plan.stretch, 0);
      expect(plan.width, greaterThan(10));
      expect(
        plan.width,
        closeTo(bars[1].widths.systemHead + bars[1].widths.minBody, 1e-9),
      );
      expect(endOf(plan), closeTo(plan.width, 1e-9));
    });

    test('a key change at a system\'s first bar puts its courtesy at the end '
        'of the system before', () {
      final score = after(barsOf(List.filled(12, 4)), [
        SetKey(from: barId(3), key: const KeySignature(2)),
      ]);
      final plain = breaksOf(twelve, sheet);
      final bars = layoutsOf(score);
      final breaks = breaksOf(bars, sheet);
      final courtesy = bars[3].widths.courtesy;

      expect(startsOf(plain).take(2), [0, 3]);
      expect(startsOf(breaks).take(2), [0, 3]);
      expect(courtesy, greaterThan(2));
      expect(breaks.plans[0].key.next, same(bars[3]));
      expect(endOf(breaks.plans[0]), closeTo(sheet, 1e-9));
      expect(
        springsOf(breaks.plans[0]),
        closeTo(springsOf(plain.plans[0]) - courtesy, 1e-9),
      );
    });

    test('noCourtesy removes the courtesy from the system before', () {
      final score = after(barsOf(List.filled(12, 4)), [
        SetKey(from: barId(3), key: const KeySignature(2)),
        SetKeyDisplay(barId(3), SignatureDisplay.noCourtesy),
      ]);
      final bars = layoutsOf(score);
      final breaks = breaksOf(bars, sheet);

      expect(startsOf(breaks).take(2), [0, 3]);
      expect(bars[3].widths.courtesy, 0);
      expect(
        springsOf(breaks.plans[0]),
        closeTo(springsOf(breaksOf(twelve, sheet).plans[0]), 1e-9),
      );
    });

    test('a courtesy with no room sends the bar before it to the next '
        'system', () {
      final score = after(barsOf(List.filled(12, 4)), [
        SetKey(from: barId(3), key: const KeySignature(2)),
      ]);
      final bars = layoutsOf(score);
      final tight = sheet - 4;

      expect(startsOf(breaksOf(twelve, tight)).take(2), [0, 3]);
      expect(startsOf(breaksOf(bars, tight)).take(2), [0, 2]);
    });

    test('a courtesy that goes away lets the bar before it back into the '
        'system it left', () {
      final keyed = after(barsOf(List.filled(12, 4)), [
        SetKey(from: barId(3), key: const KeySignature(2)),
      ]);
      final silent = after(keyed, [
        SetKeyDisplay(barId(3), SignatureDisplay.noCourtesy),
      ]);
      final tight = sheet - 4;
      final previous = breaksOf(layoutsOf(keyed), tight);
      final bars = [...previous.units.map((unit) => unit.first)]
        ..[3] = layoutsOf(silent)[3];
      final resumed = breaksOf(bars, tight, previous: previous);

      expect(startsOf(previous).take(2), [0, 2]);
      expect(bars[3].widths.inlineHead, previous.units[3].widths.inlineHead);
      expect(startsOf(resumed).take(2), [0, 3]);
      expect(resumed.starts, breaksOf(bars, tight).starts);
    });

    test('a wider bar mid-score leaves every earlier system where it was', () {
      final previous = breaksOf(twelve, sheet);
      final bars = [...twelve]..[7] = barOf(7, 16);
      final resumed = breaksOf(bars, sheet, previous: previous);

      expect(startsOf(previous), [0, 3, 6, 9]);
      expect(startsOf(resumed).take(3), [0, 3, 6]);
      expect(startsOf(resumed), isNot(startsOf(previous)));
      expect(resumed.starts, breaksOf(bars, sheet).starts);
      expect(resumed.plans[0], same(previous.plans[0]));
      expect(resumed.plans[1], same(previous.plans[1]));
    });

    test('a bar laid out again at the same widths rebreaks nothing, and only '
        'its own system is planned again', () {
      final previous = breaksOf(twelve, sheet);
      final again = barOf(7, 4);
      final bars = [...twelve]..[7] = again;
      final resumed = breaksOf(bars, sheet, previous: previous);

      expect(again, isNot(same(twelve[7])));
      expect(again.widths, twelve[7].widths);
      expect(identical(resumed.starts, previous.starts), isTrue);
      expect(resumed.plans[2], isNot(same(previous.plans[2])));
      expect(resumed.plans[2].stretch, previous.plans[2].stretch);
      for (final system in [0, 1, 3]) {
        expect(
          resumed.plans[system],
          same(previous.plans[system]),
          reason: 'system $system',
        );
      }
    });

    test('the same bars break to the same list of starts', () {
      final previous = breaksOf(twelve, sheet);
      final resumed = breaksOf(twelve, sheet, previous: previous);

      expect(identical(resumed.starts, previous.starts), isTrue);
      for (final (index, plan) in resumed.plans.indexed) {
        expect(plan, same(previous.plans[index]));
      }
    });

    test('a bar that changes width without moving a break leaves the later '
        'systems as they were', () {
      final previous = breaksOf(twelve, sheet);
      final bars = [...twelve]..[4] = barOf(4, 8);
      final resumed = breaksOf(bars, sheet, previous: previous);

      expect(bars[4].widths.body, greaterThan(twelve[4].widths.body));
      expect(startsOf(resumed), [0, 3, 6, 9]);
      expect(identical(resumed.starts, previous.starts), isFalse);
      expect(resumed.plans[0], same(previous.plans[0]));
      expect(resumed.plans[1].stretch, lessThan(previous.plans[1].stretch));
      expect(resumed.plans[2], same(previous.plans[2]));
      expect(resumed.plans[3], same(previous.plans[3]));
    });

    test('a narrower first bar of a system moves back to the system before '
        'it', () {
      final previous = breaksOf(twelve, sheet);
      final bars = [...twelve]..[6] = barOf(6, 1);
      final resumed = breaksOf(bars, sheet, previous: previous);

      expect(startsOf(previous), [0, 3, 6, 9]);
      expect(startsOf(resumed), [0, 3, 7, 10]);
      expect(resumed.starts, breaksOf(bars, sheet).starts);
      expect(resumed.plans[0], same(previous.plans[0]));
    });

    test('bars that lose their first bar, their last bar or every bar they '
        'had break as they do afresh', () {
      final previous = breaksOf(twelve.sublist(0, 10), sheet);

      expect(startsOf(previous), [0, 3, 6, 9]);
      for (final bars in [
        twelve.sublist(1, 10),
        twelve.sublist(0, 9),
        twelve.sublist(10),
      ]) {
        final resumed = breaksOf(bars, sheet, previous: previous);

        expect(resumed.starts, isNot(previous.starts));
        expect(resumed.starts, breaksOf(bars, sheet).starts);
      }
    });

    test('a new sheet width breaks again from the first bar', () {
      final previous = breaksOf(twelve, sheet);
      final wider = naturalOf(foldBars(twelve, style), 0, 3) + 5;
      final resumed = breaksOf(twelve, wider, previous: previous);

      expect(startsOf(resumed), [0, 4, 8]);
      expect(resumed.width, wider);
      expect(resumed.plans[0].key.width, wider);
    });

    test('a new lead breaks again from the first bar', () {
      const wide = SystemLead(parts: [], firstIndent: 20, indent: 20);
      final previous = breaksOf(twelve, sheet);
      final resumed = breaksOf(twelve, sheet, lead: wide, previous: previous);

      expect(startsOf(resumed), [0, 2, 4, 6, 8, 10]);
      expect(resumed.starts, breaksOf(twelve, sheet, lead: wide).starts);
      expect(resumed.lead, same(wide));
    });

    test('a later system has its own indent to fill', () {
      const deep = SystemLead(parts: [], firstIndent: 25, indent: 0);

      expect(startsOf(breaksOf(twelve, sheet, lead: deep)), [0, 2, 5, 8, 11]);
    });
  });

  group('foldBars', () {
    final score = barsOf([0, 0, 0, 4, 0, 4, 0, 0]);
    final bars = layoutsOf(score);

    test('without multi-measure rests every bar is its own unit', () {
      final units = foldBars(bars, style);

      expect(units, everyElement(isA<SingleBar>()));
      expect([for (final unit in units) unit.first], bars);
    });

    test('a run of two or more rest-only bars is one unit', () {
      final units = foldBars(bars, folding);

      expect(
        [
          for (final unit in units) [for (final bar in unit.bars) bar.measure],
        ],
        [
          [barId(0)],
          [barId(1), barId(2)],
          [barId(3)],
          [barId(4)],
          [barId(5)],
          [barId(6), barId(7)],
        ],
        reason: 'bar 0 prints the meter, and bar 4 is one bar alone',
      );
      expect(units[1], isA<RestRun>());
      expect(units[3], isA<SingleBar>());
    });

    test('a break inside a run ends it', () {
      final rests = barsOf([4, 0, 0, 0, 0, 0, 4]);
      List<List<MeasureId>> unitsWith(int breakAt) => [
        for (final unit in foldBars(
          layoutsOf(
            after(rests, [SetBreak(barId(breakAt), LayoutBreak.system)]),
          ),
          folding,
        ))
          [for (final bar in unit.bars) bar.measure],
      ];

      expect(unitsWith(3), [
        [barId(0)],
        [barId(1), barId(2)],
        [barId(3), barId(4), barId(5)],
        [barId(6)],
      ]);
      expect(unitsWith(2), [
        [barId(0)],
        [barId(1)],
        [barId(2), barId(3), barId(4), barId(5)],
        [barId(6)],
      ]);
    });

    test('a rest run has its first bar\'s heads, the style\'s width and its '
        'last bar\'s end', () {
      final keyed = layoutsOf(
        after(barsOf([4, 0, 0, 0]), [
          SetKey(from: barId(0), key: const KeySignature(3)),
          SetBarline(barId(3), Barline.finalBar),
        ]),
      );
      final run = foldBars(keyed, folding)[1];
      final ended = RestRun(
        [keyed[1], keyed[3]],
        body: style.spacing.restRunWidth,
        countRise: restRunRise(style),
      );

      expect(run.bars, [keyed[1], keyed[2]]);
      expect(run.widths.systemHead, keyed[1].widths.systemHead);
      expect(run.widths.inlineHead, 0);
      expect(run.widths.courtesy, 0);
      expect(run.widths.body, closeTo(12 + 0.16, 1e-9));
      expect(run.widths.minBody, closeTo(12 + 0.16, 1e-9));
      expect(run.lead, 0);
      expect(run.slices.map((slice) => slice.ideal), [12, 0]);
      expect(
        foldBars(
          keyed,
          const EngravingStyle(
            multiMeasureRests: true,
            spacing: SpacingPolicy(restRunWidth: 20),
          ),
        )[1].widths.body,
        closeTo(20 + 0.16, 1e-9),
      );
      expect(ended.widths.body, closeTo(12 + 0.16 + 0.4 + 0.5, 1e-9));
      expect(ended.edges.end, Barline.finalBar);
      expect(ended.edges.repeatStart, isFalse);
    });

    test('a rest run reaches as far as any of its bars', () {
      final [high, low, rest] = layoutsOf(
        scoreOf([
          [
            staffOf([chordOf(1, 'C7', value: whole)]),
          ],
          [
            staffOf([chordOf(2, 'C3', value: whole)]),
          ],
          [
            staffOf([
              MeasureRest(id: const EventId(3), span: Meter.fourFour.length),
            ]),
          ],
        ]),
      );

      expect(high.staves.single.above, greaterThan(low.staves.single.above));
      expect(high.staves.single.above, greaterThan(rest.staves.single.above));
      expect(low.staves.single.below, greaterThan(high.staves.single.below));
      expect(low.staves.single.below, greaterThan(rest.staves.single.below));
      for (final bars in [
        [high, low, rest],
        [rest, low, high],
      ]) {
        final staff = RestRun(bars, body: 12, countRise: 0).staves.single;

        expect(staff.staff, rest.staves.single.staff);
        expect(staff.above, high.staves.single.above);
        expect(staff.below, low.staves.single.below);
      }
    });

    test('a rest run reaches at least its rise above every staff, for the '
        'count the system draws', () {
      final all = layoutsOf(barsOf([4, 0, 0]));
      final bars = all.sublist(1);
      final own = bars.first.staves.single.above;
      final low = RestRun(bars, body: 12, countRise: own / 2).staves.single;
      final high = RestRun(bars, body: 12, countRise: own + 5).staves.single;

      expect(low.above, own);
      expect(high.above, own + 5);
      expect(restRunRise(style), greaterThan(2));
      expect(foldBars(all, folding)[1].staves.single.above, restRunRise(style));
    });

    test('two units are equal when they hold the same bar objects', () {
      final again = layoutsOf(score);

      expect(SingleBar(bars[3]), SingleBar(bars[3]));
      expect(SingleBar(bars[3]), isNot(SingleBar(again[3])));
      expect(
        RestRun([bars[1], bars[2]], body: 12, countRise: 0),
        RestRun([bars[1], bars[2]], body: 12, countRise: 0),
      );
      expect(
        RestRun([bars[1], bars[2]], body: 12, countRise: 0),
        isNot(RestRun([bars[1], again[2]], body: 12, countRise: 0)),
      );
      expect(
        RestRun([bars[1], bars[2]], body: 12, countRise: 0),
        isNot(RestRun([bars[1], bars[2], bars[4]], body: 12, countRise: 0)),
      );
    });

    test('a rest run is taken whole by one system', () {
      final rests = layoutsOf(barsOf([4, 0, 0, 0, 0, 0, 0, 4, 4]));
      final breaks = breaksOf(rests, 34, style: folding);

      expect(startsOf(breaks), [0, 1, 8]);
      expect(breaks.plans[1].bars, [
        for (var bar = 1; bar <= 7; bar++) barId(bar),
      ]);
      expect(endOf(breaks.plans[1]), closeTo(34, 1e-9));
    });
  });

  group('planSystem', () {
    final twelve = layoutsOf(barsOf(List.filled(12, 4)));
    final sheet = naturalOf(foldBars(twelve, style), 0, 2) + 5;

    test('the stretch makes a system end at the sheet width', () {
      final breaks = breaksOf(twelve, sheet);

      for (final (index, plan) in breaks.plans.indexed) {
        expect(endOf(plan), closeTo(sheet, 1e-9), reason: 'system $index');
        expect(plan.width, sheet);
        expect(plan.stretch, greaterThan(1));
      }
      expect(breaks.plans[0].stretch, lessThan(breaks.plans[1].stretch));
    });

    test('a signature inside a system takes its room from the springs', () {
      final bars = layoutsOf(
        after(barsOf(List.filled(12, 4)), [
          SetKey(from: barId(1), key: const KeySignature(3)),
        ]),
      );
      final plan = breaksOf(bars, sheet + 10).plans[0];

      expect(plan.bars.take(2), [barId(0), barId(1)]);
      expect(bars[1].widths.inlineHead, greaterThan(2));
      expect(endOf(plan), closeTo(sheet + 10, 1e-9));
    });

    test('a short system before a break fills the sheet all the same', () {
      final breaks = breaksOf(
        layoutsOf(
          after(barsOf(List.filled(4, 4)), [
            SetBreak(barId(1), LayoutBreak.system),
          ]),
        ),
        sheet,
      );

      expect(startsOf(breaks), [0, 1]);
      expect(naturalOf(breaks.units, 0, 0), lessThan(sheet / 2));
      expect(endOf(breaks.plans[0]), closeTo(sheet, 1e-9));
    });

    test('a short last system keeps its natural spacing', () {
      final breaks = breaksOf(twelve.sublist(0, 4), sheet);

      expect(startsOf(breaks), [0, 3]);
      expect(breaks.plans[0].key.last, isFalse);
      expect(breaks.plans[1].key.last, isTrue);
      expect(breaks.plans[1].stretch, 1);
      expect(endOf(breaks.plans[1]), lessThan(sheet * 0.75));
    });

    test('a last system is short by what its bars fill of the room its heads '
        'leave them, not by what it fills of the sheet', () {
      final two = twelve.sublist(0, 2);
      final loose = breaksOf(two, 1000, lead: flush).plans.single;
      final springs = springsOf(loose);
      final room = springs / 0.7;
      final deep = SystemLead(
        parts: const [],
        firstIndent: room - (endOf(loose) - springs),
        indent: 0,
      );
      final plan = breaksOf(two, 2 * room, lead: deep).plans.single;

      expect(loose.stretch, 1);
      expect(plan.stretch, 1);
      expect(endOf(plan), closeTo(0.85 * 2 * room, 1e-9));
    });

    test('a last system past the style\'s threshold fills the sheet', () {
      final nearlyFull = breaksOf(twelve, sheet);
      final always = breaksOf(
        twelve.sublist(0, 4),
        sheet,
        style: const EngravingStyle(justifyLastSystemFrom: 0),
      );

      expect(nearlyFull.plans.last.key.last, isTrue);
      expect(endOf(nearlyFull.plans.last), closeTo(sheet, 1e-9));
      expect(endOf(always.plans.last), closeTo(sheet, 1e-9));
    });

    test('the first system starts at the first indent and the others at the '
        'indent', () {
      final breaks = breaksOf(twelve, sheet);

      expect(breaks.plans[0].key.first, isTrue);
      expect(breaks.plans[1].key.first, isFalse);
      expect(breaks.plans[0].indent, 6);
      expect(breaks.plans[1].indent, 2);
      expect(breaks.plans[0].labelAt.x, 6);
      expect(breaks.plans[1].labelAt.x, 2);
    });

    test('staves stack by the furthest reach of any bar in the system', () {
      final score = scoreOf([
        [
          staffOf([chordOf(1, 'B4', value: whole)]),
          staffOf([chordOf(2, 'B4', value: whole)]),
        ],
        [
          staffOf([chordOf(3, 'C3', value: whole)]),
          staffOf([chordOf(4, 'B4', value: whole)]),
        ],
        [
          staffOf([chordOf(5, 'B4', value: whole)]),
          staffOf([chordOf(6, 'C7', value: whole)]),
        ],
      ]);
      final bars = layoutsOf(score);
      final plan = breaksOf(
        bars,
        1000,
        style: const EngravingStyle(barNumbers: false),
      ).plans.single;
      final low = bars[1].staves[0].below;
      final high = bars[2].staves[1].above;

      expect(low, greaterThan(4));
      expect(high, greaterThan(4));
      expect(plan.staffTops[0], closeTo(1.392, 1e-9), reason: 'the G clef');
      expect(
        plan.staffTops[1],
        closeTo(1.392 + staffHeight + low + 4 + high, 1e-9),
      );
      expect(
        plan.height,
        closeTo(plan.staffTops[1] + staffHeight + 1.632, 1e-9),
      );
    });

    test('a staff with nothing outside it still holds its outer lines', () {
      final bars = layoutsOf(
        scoreOf([
          [
            staffOf([chordOf(1, 'C5', value: whole)], lines: 1),
          ],
        ]),
      );
      final clefless = [
        BarLayout(
          measure: bars[0].measure,
          length: bars[0].length,
          breakBefore: null,
          restOnly: false,
          widths: bars[0].widths,
          lead: bars[0].lead,
          slices: bars[0].slices,
          staves: [
            (
              staff: bars[0].staves.single.staff,
              lines: 5,
              above: 0,
              below: 0,
            ),
          ],
          items: const [],
          heads: bars[0].heads,
          edges: bars[0].edges,
          beams: const [],
          tuplets: const [],
          ties: const [],
          spanners: const [],
          volta: null,
        ),
      ];
      final plan = breaksOf(
        clefless,
        1000,
        style: const EngravingStyle(barNumbers: false),
      ).plans.single;

      expect(plan.staffTops.single, closeTo(0.065, 1e-9));
      expect(plan.height, closeTo(0.065 + staffHeight + 0.065, 1e-9));
    });

    test('the bar number sits over what the first bar has above the top '
        'staff', () {
      final score = scoreOf([
        [
          staffOf([chordOf(1, 'B4', value: whole)]),
        ],
        [
          staffOf([chordOf(2, 'C7', value: whole)]),
        ],
      ]);
      final bars = layoutsOf(score);
      final high = bars[1].staves.single.above;
      final numbered = breaksOf(bars, 1000).plans.single;
      final bare = breaksOf(
        bars,
        1000,
        style: const EngravingStyle(barNumbers: false),
      ).plans.single;
      final alone = breaksOf(bars.sublist(0, 1), 1000).plans.single;

      expect(high, greaterThan(1.392 + 1.5));
      expect(bare.staffTops.single, closeTo(high, 1e-9));
      expect(numbered.staffTops.single, closeTo(high, 1e-9));
      expect(alone.staffTops.single, closeTo(1.392 + 1.5, 1e-9));
      expect(
        alone.staffTops.single - alone.labelAt.y,
        closeTo(1.392 + 0.3, 1e-9),
        reason: 'the baseline is a descent above the clef',
      );
      expect(
        numbered.staffTops.single - numbered.labelAt.y,
        closeTo(1.392 + 0.3, 1e-9),
      );
    });

    test('the courtesy of the next system\'s first bar counts toward the '
        'reach', () {
      final plainBars = layoutsOf(barsOf(List.filled(6, 4), staves: 2));
      final wide = naturalOf(foldBars(plainBars, style), 0, 2) + 5;
      final bars = layoutsOf(
        after(barsOf(List.filled(6, 4), staves: 2), [
          SetKey(from: barId(3), key: const KeySignature(3)),
        ]),
      );
      final plain = breaksOf(plainBars, wide).plans[0];
      final plan = breaksOf(bars, wide).plans[0];

      expect(plan.key.next, same(bars[3]));
      expect(
        plain.staffTops[1] - plain.staffTops[0],
        closeTo(staffHeight + 1.632 + 4 + 1.392, 1e-9),
      );
      expect(
        plan.staffTops[1] - plan.staffTops[0],
        closeTo(staffHeight + 1.632 + 4 + 1.9, 1e-9),
        reason: 'the sharp on G5 passes the clef',
      );
    });

    test('a courtesy that reaches below a staff counts on that staff '
        'alone', () {
      final flats = after(
        scoreOf([
          for (var b = 0; b < 6; b++)
            [
              staffOf([chordOf(b * 10 + 1, 'B4', value: whole)]),
              staffOf(
                [chordOf(b * 10 + 2, 'D3', value: whole)],
                clef: Clef.bass,
              ),
            ],
        ], key: const KeySignature(-5)),
        [SetBreak(barId(3), LayoutBreak.system)],
      );
      final cancelled = after(flats, [
        SetKey(from: barId(3), key: KeySignature.cMajor),
      ]);
      final plain = breaksOf(layoutsOf(flats), 1000).plans[0];
      final plan = breaksOf(layoutsOf(cancelled), 1000).plans[0];
      double below(SystemPlan plan) =>
          plan.height - plan.staffTops[1] - staffHeight;

      expect(plan.bars, [barId(0), barId(1), barId(2)]);
      expect(below(plain), closeTo(0.7, 1e-9), reason: 'the flat on G2');
      expect(
        below(plan),
        closeTo(1.34, 1e-9),
        reason: 'the natural that cancels it',
      );
      expect(plan.staffTops, plain.staffTops);
    });

    test('a plan lists its bars and is found again by its key', () {
      final breaks = breaksOf(twelve, sheet);
      final key = breaks.plans[1].key;
      final same = SystemKey(
        units: [for (final bar in twelve.sublist(3, 6)) SingleBar(bar)],
        next: twelve[6],
        width: sheet,
        lead: lead,
        first: false,
        last: false,
      );

      expect(breaks.plans[1].bars, [barId(3), barId(4), barId(5)]);
      expect(same, key);
      expect(same.hashCode, key.hashCode);
      for (final other in [
        SystemKey(
          units: key.units,
          next: twelve[7],
          width: sheet,
          lead: lead,
          first: false,
          last: false,
        ),
        SystemKey(
          units: key.units,
          next: key.next,
          width: sheet + 1,
          lead: lead,
          first: false,
          last: false,
        ),
        SystemKey(
          units: key.units,
          next: key.next,
          width: sheet,
          lead: flush,
          first: false,
          last: false,
        ),
        SystemKey(
          units: key.units,
          next: key.next,
          width: sheet,
          lead: lead,
          first: true,
          last: false,
        ),
        SystemKey(
          units: key.units,
          next: key.next,
          width: sheet,
          lead: lead,
          first: false,
          last: true,
        ),
        SystemKey(
          units: [for (final bar in twelve.sublist(6, 9)) SingleBar(bar)],
          next: key.next,
          width: sheet,
          lead: lead,
          first: false,
          last: false,
        ),
        SystemKey(
          units: key.units.sublist(0, 2),
          next: key.next,
          width: sheet,
          lead: lead,
          first: false,
          last: false,
        ),
      ]) {
        expect(other, isNot(key));
      }
    });
  });
}
