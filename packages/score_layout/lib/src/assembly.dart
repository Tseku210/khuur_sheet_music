/// Building one system from its plan. Not exported.
library;

import 'bar_layout.dart';
import 'bar_space.dart';
import 'beams.dart';
import 'breaking.dart';
import 'chords.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'signatures.dart';
import 'spacing.dart';
import 'spanners.dart';
import 'style.dart';
import 'system_layout.dart';

/// Assembles the system of [plan].
///
/// The plan already fixed the stretch, the staff tops and the height, so this
/// only places. A pure function of the plan and the style.
SystemLayout assembleSystem(SystemPlan plan, EngravingStyle style) {
  final key = plan.key;
  final units = key.units;
  final tops = plan.staffTops;
  final frames = frameUnits(plan);
  final courtesyLeft = frames.last.right + units.last.slices.last.rod;
  final right = courtesyLeft + (key.next?.widths.courtesy ?? 0);
  // A stub arriving from an earlier system starts where the head glyphs end,
  // in the room `arrivingRoom` put in the system head. One leaving for the
  // next system stops at `courtesyLeft`, before any courtesy signature.
  final headEnd = frames.first.left + units.first.first.heads.system.width;

  final drawables = <Drawable>[
    ...placeLead(key.lead, first: key.first, tops: tops, style: style),
    for (final (index, staff) in units.first.staves.indexed)
      for (final step in staff.lines == 1 ? const [4] : const [0, 2, 4, 6, 8])
        LineDraw(
          SpPoint(plan.indent, tops[index] + yOfStep(step)),
          SpPoint(right, tops[index] + yOfStep(step)),
          thickness: style.font.defaults.staffLineThickness,
          ink: InkRole.staffLine,
        ),
  ];
  final edges = <Framed<PlacedEdges>>[];
  final singles = <({BarLayout bar, BarFrame frame})>[];
  for (final (index, unit) in units.indexed) {
    final frame = frames[index];
    final head = index == 0 ? unit.first.heads.system : unit.first.heads.inline;
    edges.add((of: (edges: unit.edges, head: head.width), frame: frame));
    for (final item in head.items) {
      drawables.add(item.drawable.shift(frame.left, tops[item.staff]));
    }
    switch (unit) {
      case SingleBar(:final bar):
        singles.add((bar: bar, frame: frame));
        drawables.addAll(bar.items.map(frame.place));
        for (final beam in bar.beams) {
          drawables.addAll(placeBeam(beam, frame, style));
        }
      case RestRun(:final bars):
        drawables.addAll(
          placeRestRun(
            bars.length,
            left: frame.xs.first,
            right: frame.right,
            tops: tops,
            style: style,
          ),
        );
    }
  }
  for (final item in key.next?.heads.courtesy.items ?? const <HeadItem>[]) {
    drawables.add(item.drawable.shift(courtesyLeft, tops[item.staff]));
  }
  drawables
    ..addAll(
      placeBarlines(edges, groups: key.lead.groups, tops: tops, style: style),
    )
    ..addAll(
      placeTies(
        [for (final (:bar, :frame) in singles) (of: bar.ties, frame: frame)],
        left: headEnd,
        right: courtesyLeft,
        style: style,
      ),
    )
    ..addAll(
      placeSpanners(
        [
          for (final (:bar, :frame) in singles)
            (of: bar.spanners, frame: frame),
        ],
        left: headEnd,
        right: courtesyLeft,
        style: style,
      ),
    )
    ..addAll(
      placeVoltas(
        [for (final (:bar, :frame) in singles) (of: bar.volta, frame: frame)],
        style: style,
      ),
    );

  assert(
    drawables.every((drawable) => _inside(drawable.bounds, plan)),
    'assembly draws inside the band its plan reserved',
  );
  return SystemLayout(
    drawables: drawables,
    bars: [
      for (final (index, unit) in units.indexed)
        ..._placedBars(unit, frames[index]),
    ],
    staves: [
      for (final (index, staff) in units.first.staves.indexed)
        PlacedStaff(staff: staff.staff, top: tops[index], lines: staff.lines),
    ],
    width: plan.width,
    height: plan.height,
  );
}

/// The frame of each unit of [plan], left to right.
List<BarFrame> frameUnits(SystemPlan plan) {
  final tops = plan.staffTops;
  final frames = <BarFrame>[];
  var x = plan.indent;
  for (final (index, unit) in plan.key.units.indexed) {
    final head = index == 0 ? unit.widths.systemHead : unit.widths.inlineHead;
    final xs = sliceXs(unit.slices, plan.stretch, x + head + unit.lead);
    frames.add(BarFrame(left: x, xs: xs, tops: tops));
    x = xs.last + unit.slices.last.rod;
  }
  return frames;
}

/// The bars of [unit] as the overlays see them. The bars of a rest run
/// share the run's content evenly, so each still has a place to tap and a
/// place for the caret, and the first keeps the head.
List<PlacedBar> _placedBars(BreakUnit unit, BarFrame frame) {
  switch (unit) {
    case SingleBar(:final bar):
      return [
        PlacedBar(
          measure: bar.measure,
          left: frame.left,
          right: frame.right,
          time: TimeAxis([
            for (final (index, slice) in bar.slices.indexed)
              (slice.at, frame.xs[index]),
          ]),
          length: bar.length,
        ),
      ];
    case RestRun(:final bars):
      final from = frame.xs.first;
      final each = (frame.right - from) / bars.length;
      double at(int share) =>
          share == bars.length ? frame.right : from + each * share;
      return [
        for (final (index, bar) in bars.indexed)
          PlacedBar(
            measure: bar.measure,
            left: index == 0 ? frame.left : at(index),
            right: at(index + 1),
            time: TimeAxis([
              (bar.slices.first.at, at(index)),
              (bar.slices.last.at, at(index + 1)),
            ]),
            length: bar.length,
          ),
      ];
  }
}

/// How far a drawable may pass its band and still count as inside, in
/// staff spaces. A slice's x is a sum of stretched springs, so the last
/// barline's right edge equals the plan's width only to rounding.
const double bandTolerance = 1e-6;

bool _inside(Box bounds, SystemPlan plan) =>
    -bandTolerance <= bounds.left &&
    bounds.right <= plan.width + bandTolerance &&
    -bandTolerance <= bounds.top &&
    bounds.bottom <= plan.height + bandTolerance;
