/// Staff-space geometry. One staff space is the distance between two staff
/// lines. y grows downward, as on a canvas.
///
/// Three origins exist inside the engine, and each stored value says which
/// one it uses:
/// - bar space has x from a slice of the bar and y from the top line of a
///   staff;
/// - system space starts at the top-left corner of a system's box;
/// - sheet space starts at the top-left corner of the whole sheet.
///
/// Pixels never appear here. The Flutter shell converts sheet space to
/// logical pixels in one place (`SheetScale`).
library;

/// A point in staff spaces.
final class SpPoint {
  const SpPoint(this.x, this.y);

  static const zero = SpPoint(0, 0);

  final double x;
  final double y;

  SpPoint shift(double dx, double dy) => SpPoint(x + dx, y + dy);

  @override
  bool operator ==(Object other) =>
      other is SpPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// An axis-aligned box in staff spaces.
///
/// Invariant: `left <= right` and `top <= bottom`.
final class Box {
  const Box(this.left, this.top, this.right, this.bottom)
    : assert(left <= right && top <= bottom, 'a box is never inverted');

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  Box shift(double dx, double dy) =>
      Box(left + dx, top + dy, right + dx, bottom + dy);

  /// This box with [by] added on every side.
  Box grow(double by) => Box(left - by, top - by, right + by, bottom + by);

  Box union(Box other) => Box(
    left < other.left ? left : other.left,
    top < other.top ? top : other.top,
    right > other.right ? right : other.right,
    bottom > other.bottom ? bottom : other.bottom,
  );

  bool contains(SpPoint point) =>
      left <= point.x &&
      point.x <= right &&
      top <= point.y &&
      point.y <= bottom;

  @override
  bool operator ==(Object other) =>
      other is Box &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// The height of a staff, which is four spaces between five lines. A one-line
/// staff keeps the same band, with its line in the middle.
const double staffHeight = 4;

/// The y of [staffStep] below the top line of its staff.
///
/// Steps follow `Score.toneForStaffStep`: 0 is the bottom line of a
/// five-line staff, 1 the space above it, 8 the top line. A one-line staff
/// uses the same steps with its line drawn at step 4, so a tap and a drawn
/// head agree on every staff without a second convention.
double yOfStep(int staffStep) => (8 - staffStep) * 0.5;

/// The staff step nearest to [y], measured from the top line.
int stepAtY(double y) => (8 - y * 2).round();
