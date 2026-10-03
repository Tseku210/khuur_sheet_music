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
  const BarItem(this.slice, this.staff, this.drawable, {this.centred = false});

  final int slice;

  /// Index into the bar's visible staves.
  final int staff;

  final Drawable drawable;

  /// The drawable's x is from the middle of its slice and the bar's end,
  /// not from its slice. A measure rest is centred in its bar at any
  /// stretch.
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

  double get right => xs.last;

  /// x where the bar's end barline starts.
  double get barline => xs.last + beforeBarline;

  SpPoint at(BarAnchor anchor) =>
      SpPoint(xs[anchor.slice] + anchor.dx, tops[anchor.staff] + anchor.dy);

  double xOf(BarItem item) =>
      item.centred ? (xs[item.slice] + xs.last) / 2 : xs[item.slice];

  Drawable place(BarItem item) =>
      item.drawable.shift(xOf(item), tops[item.staff]);
}

/// One concern's stubs from one bar, with the bar's frame. A system-time
/// function takes a list of these, so it sees its own stubs and nothing
/// else of the bar.
typedef Framed<T> = ({T of, BarFrame frame});

/// The side of a staff a curve bulges to, or a piece reserves room on.
enum Side { above, below }

/// The outline of what one staff of a bar has above its top line and below
/// its bottom line, in bar space at stretch 1, with x from the bar's first
/// slice and y from the staff's top line.
final class Skyline {
  final List<Box> _boxes = [];

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
