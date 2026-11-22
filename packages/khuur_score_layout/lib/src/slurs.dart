/// The shape of a slur over what stands under it. Not exported.
///
/// A bar stores what it has under a slur, slice by slice, as [SlurGround].
/// The system turns that into [SlurObstacle]s at the slices' final x and
/// fits the curve over them with [slurOver], as MuseScore's
/// `SlurTieLayout::avoidCollisions` does. The curve is tested at points
/// along its length, and both its shape and its ends move.
library;

import 'dart:math' as math;

import 'bar_space.dart';
import 'drawable.dart';
import 'geometry.dart';

/// What a bar has under a slur at one of its slices, on the slur's side.
///
/// `left` and `right` bound the slice's content, as x offsets from the
/// slice's line, and `at` is the free edge over it. `after` is the free
/// edge over the gap between this slice's content and the next slice's,
/// where what spans several slices can stand, as a beam or a tie does.
/// Both are a y from the staff's top line. The content moves with its slice and the gap
/// stretches, so the outline holds at any stretch.
typedef SlurGround = ({double left, double right, double at, double after});

/// A stretch of a system from `left` to `right` with nothing outward of
/// `edge` on the slur's side, in system space.
typedef SlurObstacle = ({double left, double right, double edge});

/// How many points along the curve are tested, each against what stands
/// between it and the next.
const int _points = 20;

/// The most rounds of adjustment before a slur is left to collide.
const int _rounds = 30;

/// Clear space between a slur's ink and what it passes over. The arc adds more
/// toward the middle.
const double _clearance = 0.1;

/// How much of each adjustment goes to an end and not to the shape. An end
/// on a note mostly keeps its place. An end cut by the system's edge is
/// free to move.
const double _noteEndShare = 0.4;

/// The share of an end cut by the system's edge. See [_noteEndShare].
const double _cutEndShare = 0.9;

/// The crescent of a slur from [from] to [to], bulging to [side], fitted
/// over [under].
///
/// The arc's rise grows with its length up to [rise]. Its middle half is
/// then raised until it clears what stands under it. What still touches
/// the curve after that is cleared in rounds that lift the shape and the
/// ends by turns. Nothing of
/// the curve passes [limit], the outer edge of the room the bars under it
/// reserved, so a slur with no room left still touches what it could not
/// clear. [fromCut] and [toCut] say that an end is not on a note but where
/// the system cuts the slur.
CurveDraw slurOver(
  SpPoint from,
  SpPoint to, {
  required Side side,
  required double rise,
  required double limit,
  required List<SlurObstacle> under,
  required bool fromCut,
  required bool toCut,
  required double endThickness,
  required double midThickness,
  required Owner owner,
  bool dashed = false,
}) {
  final s = side == Side.above ? -1.0 : 1.0;
  final allowance = (midThickness + endThickness) / 2;
  final span = to.x - from.x;
  final top = s * limit - allowance;
  final start = s * from.y;
  final end = s * to.y;
  var a0 = start;
  var a1 = end;
  var d1 = math.min(rise, span.abs() / 4) / _pull(0.5);
  var d2 = d1;

  void clamp() {
    a0 = math.max(start, math.min(a0, top));
    a1 = math.max(end, math.min(a1, top));
    final most = math.max<double>(
      0,
      math.min(span.abs(), (top - math.max(a0, a1)) / _pull(0.5)),
    );
    d1 = math.min(d1, most);
    d2 = math.min(d2, most);
  }

  if (span > 0 && under.isNotEmpty) {
    final length = math.sqrt(span * span + (end - start) * (end - start));
    final arc = (0.04 * span * span / length).clamp(0.1, 0.5);
    final need = _needs(from.x, span, under, s);
    double needAt(int point) => math.max(
      point > 0 ? need[point - 1] : double.negativeInfinity,
      point < need.length ? need[point] : double.negativeInfinity,
    );
    double edgeAt(int point) {
      final t = point / _points;
      final u = 1 - t;
      final near = 3 * u * u * t;
      final far = 3 * u * t * t;
      return (u * u * u + near) * a0 +
          (far + t * t * t) * a1 +
          near * (d1 - arc) +
          far * (d2 - arc) -
          allowance;
    }

    for (var point = _points ~/ 4; point <= _points - _points ~/ 4; point++) {
      final t = point / _points;
      final blend = (1 - _blend(t)) * a0 + _blend(t) * a1;
      final d = arc + (needAt(point) + allowance - blend) / _pull(t);
      d1 = math.max(d1, d);
      d2 = math.max(d2, d);
    }

    final step = 0.3 * (length > 16 ? math.min(length / 16, 5) : 1);
    final share0 = fromCut ? _cutEndShare : _noteEndShare;
    final share1 = toCut ? _cutEndShare : _noteEndShare;
    final third = need.length ~/ 3;
    for (var round = 0; round < _rounds; round++) {
      clamp();
      var left = false;
      var mid = false;
      var right = false;
      var before = edgeAt(0);
      for (var rect = 0; rect < need.length; rect++) {
        final after = edgeAt(rect + 1);
        if (math.min(before, after) < need[rect] - 1e-9) {
          if (rect < third) {
            left = true;
          } else if (rect < 2 * third) {
            mid = true;
          } else {
            right = true;
          }
        }
        before = after;
      }
      if (!left && !mid && !right) {
        break;
      }
      if (round.isEven) {
        if (left) {
          d1 += (1 - share0) * step / 2;
          d2 += (1 - share0) * step / 4;
        }
        if (mid) {
          final both = (2 - share0 - share1) * step / 2;
          d1 += both;
          d2 += both;
        }
        if (right) {
          d2 += (1 - share1) * step / 2;
          d1 += (1 - share1) * step / 4;
        }
      } else {
        // A collision in the middle alone of a long slanted slur lifts the
        // end nearer the staff more, which also levels the slur.
        final slant = (a1 - a0).abs() / span;
        final level = mid && slant > _levelFrom && length > 8
            ? slant / _levelFrom
            : 1.0;
        final lift0 = share0 * step;
        final lift1 = share1 * step;
        if (left) {
          a0 += lift0;
        } else if (mid) {
          a0 += lift0 * (a0 > a1 ? 1 / level : level);
        }
        if (right) {
          a1 += lift1;
        } else if (mid) {
          a1 += lift1 * (a1 > a0 ? 1 / level : level);
        }
      }
    }
  }
  clamp();
  return CurveDraw(
    start: SpPoint(from.x, s * a0),
    control1: SpPoint(from.x + span / 4, s * (a0 + d1)),
    control2: SpPoint(from.x + 3 * span / 4, s * (a1 + d2)),
    end: SpPoint(to.x, s * a1),
    endThickness: endThickness,
    midThickness: midThickness,
    ink: InkRole.slur,
    dashed: dashed,
    owner: owner,
  );
}

/// The slant, as rise over run, from which a collision in the middle
/// levels a slur. Five degrees.
const double _levelFrom = 5 * math.pi / 180;

/// For each stretch of the curve between two tested points, how far out
/// its inner edge has to lie to clear [under], with out as `s * y`.
List<double> _needs(
  double from,
  double span,
  List<SlurObstacle> under,
  double s,
) {
  double xAt(int point) {
    final t = point / _points;
    final u = 1 - t;
    return from + span * (3 * u * u * t / 4 + 9 * u * t * t / 4 + t * t * t);
  }

  return [
    for (var rect = 0; rect < _points - 1; rect++)
      under.fold(double.negativeInfinity, (need, obstacle) {
        final meets =
            obstacle.left < xAt(rect + 1) && obstacle.right > xAt(rect);
        return meets ? math.max(need, s * obstacle.edge + _clearance) : need;
      }),
  ];
}

/// How far the curve at [t] moves when both control points move one unit,
/// `3t(1 - t)`.
double _pull(double t) => 3 * t * (1 - t);

/// How much of the far end's height the curve at [t] takes before its
/// control points rise, `3t² - 2t³`.
double _blend(double t) => t * t * (3 - 2 * t);
