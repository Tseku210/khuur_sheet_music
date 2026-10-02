/// Bar space. How a bar stores positions before its system is known, and how a
/// system resolves them. Not exported.
library;

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

  /// The item's x is the middle between its slice and the bar's end, so it
  /// is not moved from its slice. A measure rest is centred in its bar at
  /// any stretch.
  final bool centred;
}

/// Where a bar landed on its system, as the x of every slice and the top line
/// of every staff, in system space. Assembly makes one per bar, and every
/// system-time function resolves bar space through it.
final class BarFrame {
  const BarFrame({
    required this.left,
    required this.xs,
    required this.tops,
  });

  /// x where the bar's head starts. That is the barline before it, or the end
  /// of the system's lead.
  final double left;

  /// x of each slice. The last is the bar's end, where its barline sits.
  final List<double> xs;

  /// y of each visible staff's top line.
  final List<double> tops;

  double get right => xs.last;

  SpPoint at(BarAnchor anchor) =>
      SpPoint(xs[anchor.slice] + anchor.dx, tops[anchor.staff] + anchor.dy);

  /// x of [item], which is its slice's, or the middle between its slice and
  /// the bar's end when it is centred.
  double xOf(BarItem item) =>
      item.centred ? (xs[item.slice] + xs.last) / 2 : xs[item.slice];

  Drawable place(BarItem item) =>
      item.drawable.shift(xOf(item), tops[item.staff]);
}

/// One concern's stubs from one bar, with the bar's frame. A system-time
/// function takes a list of these, so it sees its own stubs and nothing
/// else of the bar.
typedef Framed<T> = ({T of, BarFrame frame});
