/// Building one system from its plan. Not exported.
library;

import 'package:khuur_score_model/khuur_score_model.dart';

import 'bar_layout.dart';
import 'bar_space.dart';
import 'beams.dart';
import 'breaking.dart';
import 'chords.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'hit.dart';
import 'lyrics.dart';
import 'marks.dart';
import 'signatures.dart';
import 'spacing.dart';
import 'spanners.dart';
import 'style.dart';
import 'system_layout.dart';
import 'text.dart';

/// Assembles the system of [plan].
///
/// The plan already fixed the stretch, the staff tops and the height, so this
/// only places. A pure function of the plan, the style and the text
/// measurer, which measures the lyric hyphen.
SystemLayout assembleSystem(
  SystemPlan plan,
  EngravingStyle style,
  TextMeasurer text,
) {
  final key = plan.key;
  final units = key.units;
  final tops = plan.staffTops;
  final frames = frameUnits(plan);
  final last = frames.last;
  final courtesy = key.next?.heads.courtesy ?? SplitHead.none;
  final courtesyLeft = last.barline + units.last.slices.last.rod;
  final right = courtesyLeft + courtesy.after.width;
  // A stub arriving from an earlier system starts where the head glyphs end,
  // in the room `arrivingRoom` put in the system head, and so does a lyric
  // hyphen. One leaving for the next system stops before the courtesy, and
  // so do a lyric hyphen and extender. On a staff with a clef before the
  // last barline that is the content's end, and on any other staff the end
  // of that barline.
  final headEnd = frames.first.left + units.first.first.heads.system.width;
  final clefStaves = {for (final item in courtesy.before.items) item.staff};
  final leaveBy = [
    for (var staff = 0; staff < tops.length; staff++)
      clefStaves.contains(staff) ? last.right : courtesyLeft,
  ];

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
  final staffIds = [for (final staff in units.first.staves) staff.staff];
  final signatures = <SignatureHit, Box>{};
  void addSignature(Drawable drawable, int staff, ScorePoint at) {
    final kind = switch (drawable.ink) {
      InkRole.clef => SignatureKind.clef,
      InkRole.keySignature => SignatureKind.key,
      InkRole.timeSignature => SignatureKind.meter,
      // A tempo line's text shares the ink but is a spanner's, placed with
      // the spanners and never here.
      InkRole.tempo => SignatureKind.tempo,
      _ => null,
    };
    if (kind == null) {
      return;
    }
    signatures.update(
      SignatureHit(staff: staffIds[staff], kind: kind, at: at),
      (box) => box.union(drawable.bounds),
      ifAbsent: () => drawable.bounds,
    );
  }

  void drawHead(BarHead head, double x, MeasureId measure) {
    for (final item in head.items) {
      final drawable = item.drawable.shift(x, tops[item.staff]);
      drawables.add(drawable);
      addSignature(drawable, item.staff, ScorePoint(measure, Moment.zero));
    }
  }

  for (final (index, unit) in units.indexed) {
    final frame = frames[index];
    final heads = unit.first.heads;
    final head = index == 0 ? heads.system : heads.inline.after;
    edges.add((of: (edges: unit.edges, head: head.width), frame: frame));
    final measure = unit.first.measure;
    drawHead(head, frame.left, measure);
    if (index > 0) {
      drawHead(heads.inline.before, frames[index - 1].right, measure);
    }
    switch (unit) {
      case SingleBar(:final bar):
        singles.add((bar: bar, frame: frame));
        for (final item in bar.items) {
          final drawable = frame.place(item);
          drawables.add(drawable);
          addSignature(
            drawable,
            item.staff,
            ScorePoint(measure, bar.slices[item.slice].at),
          );
        }
        for (final beam in bar.beams) {
          drawables.addAll(placeBeam(beam, frame, style));
        }
        for (final tuplet in bar.tuplets) {
          drawables.addAll(placeTuplet(tuplet, frame, style));
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
  if (key.next case final next?) {
    drawHead(courtesy.before, last.right, next.measure);
    drawHead(courtesy.after, courtesyLeft, next.measure);
  }
  drawables
    ..addAll(
      placeBarlines(edges, groups: key.lead.groups, tops: tops, style: style),
    )
    ..addAll(
      placeTies(
        [for (final (:bar, :frame) in singles) (of: bar.ties, frame: frame)],
        left: headEnd,
        right: leaveBy,
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
        right: leaveBy,
        style: style,
      ),
    )
    ..addAll(
      placeVoltas(
        [for (final (:bar, :frame) in singles) (of: bar.volta, frame: frame)],
        style: style,
      ),
    );
  for (final (index, staff) in plan.staves.indexed) {
    drawables.addAll(
      placeLyrics(
        [
          for (final (index, unit) in units.indexed)
            (of: unit.first.lyrics, frame: frames[index]),
        ],
        rows: staff.rows,
        baselines: lyricBaselines(staff.rows, staff.lyricsFrom, style),
        carry: key.carry,
        carryOut: key.carryOut,
        next: key.next?.lyrics,
        left: headEnd,
        right: leaveBy[index],
        style: style,
        text: text,
      ),
    );
  }

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
    signatures: [
      for (final MapEntry(key: signature, value: bounds) in signatures.entries)
        PlacedSignature(signature: signature, bounds: bounds),
    ],
  );
}

/// The frame of each unit of [plan], left to right. This is where each
/// barline's x is decided. A barline stands after its bar's content and the
/// room for any clef that the bar after it changes to.
List<BarFrame> frameUnits(SystemPlan plan) {
  final units = plan.key.units;
  final tops = plan.staffTops;
  final frames = <BarFrame>[];
  var x = plan.indent;
  for (final (index, unit) in units.indexed) {
    final head = index == 0
        ? unit.widths.systemHead
        : unit.first.heads.inline.after.width;
    final next = index + 1 < units.length
        ? units[index + 1].first.heads.inline
        : plan.key.next?.heads.courtesy;
    final frame = BarFrame(
      left: x,
      xs: fitXs(
        unit.slices,
        plan.fit,
        x + head,
        lead: unit.lead,
        markRoom: unit.markRoom,
      ),
      tops: tops,
      beforeBarline: next?.before.width ?? 0,
      holdFrom: plan.fit.squeezed ? x + head : null,
    );
    frames.add(frame);
    x = frame.barline + unit.slices.last.rod;
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
