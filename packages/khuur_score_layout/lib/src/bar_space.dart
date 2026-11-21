/// Bar space. How a bar stores positions before its system is known, and how a
/// system resolves them. Not exported.
library;

import 'dart:math' as math;

import 'drawable.dart';
import 'geometry.dart';

/// A position in bar space, made of a slice, an x offset from it, a staff and a
/// y from that staff's top line.
typedef BarAnchor = ({int slice, double dx, int staff, double dy});

/// A drawable fixed to a slice and a staff. Its coordinates are relative to
/// the slice's x and the staff's top line, so justification moves it with
/// its slice and never stretches it.
final class BarItem {
  /// Fixes [drawable] to [slice] on [staff]. It is not [centred] unless
  /// asked.
  const BarItem(this.slice, this.staff, this.drawable, {this.centred = false});

  /// Index into the bar's slices.
  final int slice;

  /// Index into the bar's visible staves.
  final int staff;

  /// What is drawn, relative to the slice's x and the staff's top line.
  final Drawable drawable;

  /// The drawable's x is from the middle of its slice and the bar's end,
  /// not from its slice. A measure rest is centred in its bar's content at
  /// any stretch, short of a clef that stands before the barline.
  final bool centred;

  @override
  bool operator ==(Object other) =>
      other is BarItem &&
      other.slice == slice &&
      other.staff == staff &&
      other.drawable == drawable &&
      other.centred == centred;

  @override
  int get hashCode => Object.hash(slice, staff, drawable, centred);
}

/// Where a bar landed on its system, as the x of every slice and the top line
/// of every staff, in system space. Assembly makes one per bar, and every
/// system-time function resolves bar space through it.
final class BarFrame {
  /// Makes a frame. [beforeBarline] defaults to 0, for no clef before the
  /// barline.
  const BarFrame({
    required this.left,
    required this.xs,
    required this.tops,
    this.beforeBarline = 0,
  });

  /// x where the bar's head starts. That is the end of the barline before
  /// it, or the end of the system's lead.
  final double left;

  /// x of each slice. The last is the bar's end, where its content ends.
  final List<double> xs;

  /// y of each visible staff's top line.
  final List<double> tops;

  /// Room between the bar's end and its barline, for a clef that the next
  /// bar, or the next system's first bar, changes to before the barline.
  final double beforeBarline;

  /// x where the bar's content ends, which is the last slice's x.
  double get right => xs.last;

  /// x where the bar's end barline starts.
  double get barline => xs.last + beforeBarline;

  /// [anchor] in system space.
  SpPoint at(BarAnchor anchor) =>
      SpPoint(xs[anchor.slice] + anchor.dx, tops[anchor.staff] + anchor.dy);

  /// The x [item] is placed from, in system space. A centred item takes the
  /// middle of its slice and the bar's end.
  double xOf(BarItem item) =>
      item.centred ? (xs[item.slice] + xs.last) / 2 : xs[item.slice];

  /// [item]'s drawable moved into system space.
  Drawable place(BarItem item) =>
      item.drawable.shift(xOf(item), tops[item.staff]);
}

/// One concern's stubs from one bar, with the bar's frame. A system-time
/// function takes a list of these, so it sees its own stubs and nothing
/// else of the bar.
typedef Framed<T> = ({T of, BarFrame frame});

/// The side of a staff a curve bulges to, or a piece reserves room on.
enum Side {
  /// Above the staff, toward smaller y.
  above,

  /// Below the staff, toward larger y.
  below,
}

/// The outline of what one staff of a bar has above its top line and below
/// its bottom line, in bar space at stretch 1, with x from the bar's first
/// slice and y from the staff's top line.
final class Skyline {
  final List<Box> _boxes = [];

  /// Adds [box] to the outline, in the skyline's coordinates.
  void add(Box box) => _boxes.add(box);

  /// The lowest y a box over [left] to [right] can end at and still clear
  /// everything above the staff there. Never below the top line.
  double freeAbove(double left, double right) {
    var free = 0.0;
    for (final box in _boxes) {
      if (_meets(box, left, right)) {
        free = math.min(free, box.top);
      }
    }
    return free;
  }

  /// The highest y a box over [left] to [right] can start at and still
  /// clear everything below the staff there. Never above the bottom line.
  double freeBelow(double left, double right) {
    var free = staffHeight;
    for (final box in _boxes) {
      if (_meets(box, left, right)) {
        free = math.max(free, box.bottom);
      }
    }
    return free;
  }

  /// The free edge on [side] over [left] to [right]: [freeAbove] or
  /// [freeBelow].
  double free(Side side, double left, double right) => switch (side) {
    Side.above => freeAbove(left, right),
    Side.below => freeBelow(left, right),
  };

  /// The free edge on [side] over each span from one of [edges] to the
  /// next, in one pass over the outline. [edges] ascend. A box that only
  /// touches a span's end is not over it.
  List<double> frees(Side side, List<double> edges) {
    final above = side == Side.above;
    final free = List.filled(edges.length - 1, above ? 0.0 : staffHeight);
    for (final box in _boxes) {
      for (var span = 0; span < free.length; span++) {
        if (edges[span] >= box.right) {
          break;
        }
        if (edges[span + 1] > box.left) {
          free[span] = above
              ? math.min(free[span], box.top)
              : math.max(free[span], box.bottom);
        }
      }
    }
    return free;
  }

  /// Reserves the room between [clear], the edge nearest the staff, and
  /// [limit], the edge farthest from it, on [side] over [left] to [right].
  /// The ends may come in either order.
  void reserve(
    Side side,
    double left,
    double right, {
    required double clear,
    required double limit,
  }) {
    final lo = math.min(left, right);
    final hi = math.max(left, right);
    add(
      side == Side.above
          ? Box(lo, limit, hi, clear)
          : Box(lo, clear, hi, limit),
    );
  }

  /// The y shift that puts [box] on [side] of everything the outline has
  /// from [left] to [right], [gap] clear of it.
  double clearance(
    Side side,
    Box box,
    double gap,
    double left,
    double right,
  ) => switch (side) {
    Side.above => freeAbove(left, right) - gap - box.bottom,
    Side.below => freeBelow(left, right) + gap - box.top,
  };

  /// How far the outline reaches above the top line. Never negative.
  double get above {
    var top = 0.0;
    for (final box in _boxes) {
      top = math.min(top, box.top);
    }
    return -top;
  }

  /// How far the outline reaches below the bottom line. Never negative.
  double get below {
    var bottom = staffHeight;
    for (final box in _boxes) {
      bottom = math.max(bottom, box.bottom);
    }
    return bottom - staffHeight;
  }
}

bool _meets(Box box, double left, double right) =>
    box.left <= right && box.right >= left;
