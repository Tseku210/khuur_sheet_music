/// Beams. One slope per group, stems that meet it, secondary beams and hooks.
/// Not exported.
///
/// The model says which events beam together (`BeamGroup`) and how each
/// joins every level (`BeamGroup.joins`). Layout decides the geometry. A
/// beam never crosses a barline, so it belongs to one bar, but its stems
/// depend on the system's stretch. So the bar keeps a plan in bar space and
/// the system draws it.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'chords.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'glyphs.dart';
import 'style.dart';

/// What each beam level past the first adds to an end stem.
const double _levelRise = 0.5;

/// The most a beam rises or falls from its first stem to its last.
const double _maxSlope = 0.5;

/// A beam decided in bar space.
final class BeamPlan {
  const BeamPlan({
    required this.owner,
    required this.stem,
    required this.stems,
    required this.first,
    required this.last,
    required this.joins,
    required this.boxes,
  });

  /// The group's first event, which owns the beam's drawables.
  final Owner owner;

  final StemSide stem;

  /// Where each event's stem leaves its outer head, in time order.
  final List<BarAnchor> stems;

  /// Ends of the primary beam's outer edge, at the first and last stem.
  final BarAnchor first;
  final BarAnchor last;

  /// Per event, per level, how it joins.
  final List<List<BeamJoin>> joins;

  /// What the beam and its stems cover at stretch 1, x from the bar's
  /// first slice and y from the staff's top line. The first box is the
  /// beam's own, and one box per stem follows, from its head to the far
  /// edge of the beam. The bar's skyline takes them, so what stands over one
  /// note of the group is that note's stem and not the group's tallest
  /// note. A stretch moves the stems apart and keeps both end heights, so
  /// the vertical range holds at any stretch.
  final List<Box> boxes;

  @override
  bool operator ==(Object other) =>
      other is BeamPlan &&
      other.owner == owner &&
      other.stem == stem &&
      _same(other.stems, stems) &&
      other.first == first &&
      other.last == last &&
      other.joins.length == joins.length &&
      other.joins.indexed.every((row) => _same(row.$2, joins[row.$1])) &&
      _same(other.boxes, boxes);

  @override
  int get hashCode =>
      Object.hash(owner, stem, first, last, Object.hashAll(boxes));
}

bool _same<T>(List<T> a, List<T> b) =>
    a.length == b.length && a.indexed.every((item) => b[item.$1] == item.$2);

/// The stem side of every beamed chord of [voice]. A group takes one side, the
/// side most of its chords want by `stemSideFor`, and on a tie the side of the
/// chord farthest from the middle line. Decided before the chords are planned,
/// because the stem side decides which heads flip.
Map<EventId, StemSide> beamStemSides(VoiceView voice, StaffView staff) {
  if (voice.beams.isEmpty) {
    return const {};
  }
  final events = {for (final timed in voice.events) timed.event.id: timed};
  final sides = <EventId, StemSide>{};
  for (final group in voice.beams) {
    var up = 0;
    var farthest = -1.0;
    var tieBreak = StemSide.down;
    for (final id in group.events) {
      final timed = events[id]!;
      final chord = timed.event as ChordEvent;
      final side = stemSideFor(chord, staff, voice.slot, at: timed.onset);
      if (side == StemSide.up) {
        up++;
      }
      final distance = _distanceFromMiddle(chord, staff, timed.onset);
      if (distance > farthest) {
        farthest = distance;
        tieBreak = side;
      }
    }
    final down = group.events.length - up;
    final side = up > down
        ? StemSide.up
        : up < down
        ? StemSide.down
        : tieBreak;
    for (final id in group.events) {
      sides[id] = side;
    }
  }
  return sides;
}

double _distanceFromMiddle(ChordEvent chord, StaffView staff, Moment at) {
  final clef = staff.source.clefAt(at);
  var steps = 0;
  for (final note in chord.notes) {
    steps += clef.staffStepOf(staff.writtenPitches[note.id]!);
  }
  return (steps / chord.notes.length - 4).abs();
}

/// Plans the beam of [group] over [chords], its chords in time order.
///
/// The slope follows the first and last far heads, capped at half a space
/// in all, and is flat when an inner head goes beyond both ends on the
/// beam's side. Each end stem is at least [stemLength] plus half a space
/// per extra level, the beam's inner edge stays clear of any chord's
/// tremolo strokes, and each end is moved outward until it sits on, hangs
/// from or straddles a staff line, so a beam never floats inside a staff
/// space. [xs] holds the slices' x at stretch 1, where the slope is
/// decided. The ends are stored as offsets from their slices, so a
/// stretched system flattens the beam and keeps its end heights.
BeamPlan planBeam(
  BeamGroup group,
  List<PlacedChord> chords, {
  required List<double> xs,
  required EngravingStyle style,
}) {
  final stem = chords.first.plan.stem;
  final up = stem == StemSide.up;
  final staff = chords.first.staff;
  final stems = [
    for (final (i, placed) in chords.indexed)
      () {
        final line = stemOf(placed.plan);
        return (
          x: xs[placed.slice] + line.x,
          start: line.start,
          far: line.far,
          keep: line.keep,
          levels: group.joins[i].length,
        );
      }(),
  ];

  final x0 = stems.first.x;
  final x1 = stems.last.x;
  final farFirst = stems.first.far;
  final farLast = stems.last.far;
  final beyond = stems
      .sublist(1, stems.length - 1)
      .any(
        (s) => up
            ? s.far < math.min(farFirst, farLast)
            : s.far > math.max(farFirst, farLast),
      );
  final rise = beyond ? 0.0 : (farLast - farFirst).clamp(-_maxSlope, _maxSlope);
  final slope = x1 == x0 ? 0.0 : rise / (x1 - x0);

  final thickness = style.font.defaults.beamThickness;
  final depth =
      thickness +
      (stems.fold(0, (most, s) => math.max(most, s.levels)) - 1) *
          (thickness + style.font.defaults.beamSpacing);
  var y0 = up ? double.infinity : double.negativeInfinity;
  for (final s in stems) {
    final length = stemLength + _levelRise * (s.levels - 1);
    final tip = up
        ? math.min(s.far - length, s.keep - depth)
        : math.max(s.far + length, s.keep + depth);
    final candidate = tip - slope * (s.x - x0);
    y0 = up ? math.min(y0, candidate) : math.max(y0, candidate);
  }
  final yFirst = _snap(y0, up: up, thickness: thickness);
  final yLast = _snap(yFirst + slope * (x1 - x0), up: up, thickness: thickness);

  final owner = ElementOwner(chords.first.plan.timed.ref);
  final half = style.font.defaults.stemThickness / 2;
  final drawnSlope = x1 == x0 ? 0.0 : (yLast - yFirst) / (x1 - x0);
  final edgeLeft = yFirst - drawnSlope * half;
  final edgeRight = yLast + drawnSlope * half;
  final top = math.min(edgeLeft, edgeRight) - (up ? 0 : depth);
  final bottom = math.max(edgeLeft, edgeRight) + (up ? depth : 0);
  final boxes = [
    Box(x0 - half, top, x1 + half, bottom),
    for (final s in stems)
      Box(
        s.x - half,
        math.min(top, s.start),
        s.x + half,
        math.max(bottom, s.start),
      ),
  ];
  return BeamPlan(
    owner: owner,
    stem: stem,
    stems: [
      for (final (i, placed) in chords.indexed)
        (
          slice: placed.slice,
          dx: stems[i].x - xs[placed.slice],
          staff: staff,
          dy: stems[i].start,
        ),
    ],
    first: (
      slice: chords.first.slice,
      dx: x0 - xs[chords.first.slice],
      staff: staff,
      dy: yFirst,
    ),
    last: (
      slice: chords.last.slice,
      dx: x1 - xs[chords.last.slice],
      staff: staff,
      dy: yLast,
    ),
    joins: group.joins,
    boxes: boxes,
  );
}

/// The outer edge [y] of a beam moved away from its heads until it sits on,
/// hangs from or straddles a staff line. Outside the staff it stays.
double _snap(double y, {required bool up, required double thickness}) {
  if (y <= 0 || y >= staffHeight) {
    return y;
  }
  final line = y.floorToDouble();
  if (up) {
    return [
      line,
      line + 1 - thickness,
      line + 1 - thickness / 2,
    ].where((v) => v <= y + 1e-9).reduce(math.max);
  }
  return [
    line,
    line + thickness / 2,
    line + thickness,
    line + 1,
  ].where((v) => v >= y - 1e-9).reduce(math.min);
}

/// The beam and its stems at their final place.
///
/// The end stems run from their heads to the beam's ends. Each inner stem
/// runs to the line between the ends at its own final x, so every stem
/// touches the beam at any stretch. Each level is a polygon
/// `beamThickness` thick, `beamSpacing` from the next, and a hook is one
/// notehead wide.
List<Drawable> placeBeam(BeamPlan plan, BarFrame frame, EngravingStyle style) =>
    _draw(
      owner: plan.owner,
      stem: plan.stem,
      stems: [for (final anchor in plan.stems) frame.at(anchor)],
      first: frame.at(plan.first),
      last: frame.at(plan.last),
      joins: plan.joins,
      style: style,
    );

List<Drawable> _draw({
  required Owner owner,
  required StemSide stem,
  required List<SpPoint> stems,
  required SpPoint first,
  required SpPoint last,
  required List<List<BeamJoin>> joins,
  required EngravingStyle style,
}) {
  final defaults = style.font.defaults;
  final inward = stem == StemSide.up ? 1.0 : -1.0;
  final slope = last.x == first.x
      ? 0.0
      : (last.y - first.y) / (last.x - first.x);
  double edge(double x) => first.y + slope * (x - first.x);
  final half = defaults.stemThickness / 2;
  final hook = style.font[Glyph.noteheadBlack].box.width;
  final drawables = <Drawable>[
    for (final s in stems)
      LineDraw(
        s,
        SpPoint(s.x, edge(s.x)),
        thickness: defaults.stemThickness,
        owner: owner,
      ),
  ];
  final levels = joins.fold(0, (most, row) => math.max(most, row.length));
  for (var level = 0; level < levels; level++) {
    final offset = level * (defaults.beamThickness + defaults.beamSpacing);
    void beam(double from, double to) {
      final near = offset * inward;
      final far = (offset + defaults.beamThickness) * inward;
      drawables.add(
        PolygonDraw([
          SpPoint(from, edge(from) + near),
          SpPoint(to, edge(to) + near),
          SpPoint(to, edge(to) + far),
          SpPoint(from, edge(from) + far),
        ], owner: owner),
      );
    }

    double? from;
    for (final (i, s) in stems.indexed) {
      if (level >= joins[i].length) {
        continue;
      }
      switch (joins[i][level]) {
        case BeamJoin.begin:
          from = s.x - half;
        case BeamJoin.continued:
          break;
        case BeamJoin.end:
          beam(from!, s.x + half);
          from = null;
        case BeamJoin.forwardHook:
          beam(s.x - half, s.x + hook);
        case BeamJoin.backwardHook:
          beam(s.x - hook, s.x + half);
      }
    }
  }
  return drawables;
}
