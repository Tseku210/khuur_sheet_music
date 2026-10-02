import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'geometry.dart';
import 'glyphs.dart';
import 'text.dart';

/// What a drawable belongs to. Painting colours by it, hit testing reports
/// it, and overlays redraw an owner's drawables in a highlight colour.
sealed class Owner {
  const Owner();
}

/// A note or an event. A grace head is owned by its principal's event,
/// because a grace chord has no reference of its own.
final class ElementOwner extends Owner {
  const ElementOwner(this.ref);

  final ElementRef ref;

  @override
  bool operator ==(Object other) => other is ElementOwner && other.ref == ref;

  @override
  int get hashCode => ref.hashCode;
}

/// A spanner. Every drawable of a slur or a line is owned by the spanner's
/// id, so the whole run is one thing to hit and to highlight.
final class SpannerOwner extends Owner {
  const SpannerOwner(this.id);

  final SpannerId id;

  @override
  bool operator ==(Object other) => other is SpannerOwner && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The colour role layout assigns. The palette maps each role to a colour,
/// so a theme change repaints and never lays out.
enum InkRole {
  normal,
  staffLine,

  /// A note outside its instrument's `lowest` to `highest` range.
  outOfRange,
}

/// One thing to paint, in system space unless stated otherwise.
///
/// Drawables are values. Two are equal when every field is equal. The
/// incremental-layout tests compare an updated layout with a fresh one by
/// that equality, and the system painter compares a bar-number label by it,
/// so a label made again for an unchanged system does not repaint it.
sealed class Drawable {
  const Drawable({this.owner, this.ink = InkRole.normal});

  /// Null for structure, which is staff lines, barlines, clefs and signatures.
  final Owner? owner;
  final InkRole ink;

  /// The ink's box, in the drawable's own space.
  Box get bounds;

  /// The same drawable moved by [dx] and [dy] in its own space.
  Drawable shift(double dx, double dy);

  /// Whether a tap at [point] lands on this drawable, with a finger's
  /// [reach] in staff spaces. A stem is a tenth of a staff space wide, so
  /// without the reach a finger could not hit it.
  bool hits(SpPoint point, double reach) => bounds.grow(reach).contains(point);
}

/// A SMuFL glyph with its origin on the baseline.
final class GlyphDraw extends Drawable {
  const GlyphDraw(
    this.glyph,
    this.origin, {
    required this.bounds,
    this.scale = 1,
    this.stretch = 1,
    super.owner,
    super.ink,
  });

  final Glyph glyph;
  final SpPoint origin;

  /// 1 for normal size; the style's grace scale for grace notes.
  final double scale;

  /// A vertical scale on top of [scale], about [origin]. 1 for every glyph
  /// but a brace, which keeps one width and is stretched to its part's
  /// height.
  final double stretch;

  @override
  final Box bounds;

  @override
  GlyphDraw shift(double dx, double dy) => GlyphDraw(
    glyph,
    origin.shift(dx, dy),
    bounds: bounds.shift(dx, dy),
    scale: scale,
    stretch: stretch,
    owner: owner,
    ink: ink,
  );

  @override
  bool operator ==(Object other) =>
      other is GlyphDraw &&
      other.glyph == glyph &&
      other.origin == origin &&
      other.bounds == bounds &&
      other.scale == scale &&
      other.stretch == stretch &&
      other.owner == owner &&
      other.ink == ink;

  @override
  int get hashCode =>
      Object.hash(glyph, origin, bounds, scale, stretch, owner, ink);
}

/// How a [LineDraw] is stroked. The painter picks the dash and dot lengths.
enum LineDash { solid, dashed, dotted }

/// Staff and ledger lines, stems, barlines, brackets, hairpin arms, octave,
/// pedal and volta lines, tuplet brackets and lyric extenders.
final class LineDraw extends Drawable {
  const LineDraw(
    this.from,
    this.to, {
    required this.thickness,
    this.dash = LineDash.solid,
    super.owner,
    super.ink,
  });

  final SpPoint from;
  final SpPoint to;
  final double thickness;
  final LineDash dash;

  /// The line's ink, which is the segment widened by half its [thickness]
  /// on each side, with flat ends.
  @override
  Box get bounds {
    final dx = (to.x - from.x).abs();
    final dy = (to.y - from.y).abs();
    final length = math.sqrt(dx * dx + dy * dy);
    final halfX = length == 0 ? 0.0 : thickness / 2 * dy / length;
    final halfY = length == 0 ? 0.0 : thickness / 2 * dx / length;
    return Box(
      math.min(from.x, to.x) - halfX,
      math.min(from.y, to.y) - halfY,
      math.max(from.x, to.x) + halfX,
      math.max(from.y, to.y) + halfY,
    );
  }

  @override
  LineDraw shift(double dx, double dy) => LineDraw(
    from.shift(dx, dy),
    to.shift(dx, dy),
    thickness: thickness,
    dash: dash,
    owner: owner,
    ink: ink,
  );

  @override
  bool operator ==(Object other) =>
      other is LineDraw &&
      other.from == from &&
      other.to == to &&
      other.thickness == thickness &&
      other.dash == dash &&
      other.owner == owner &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(from, to, thickness, dash, owner, ink);
}

/// A filled polygon, which is one beam or a beam hook.
final class PolygonDraw extends Drawable {
  const PolygonDraw(this.points, {super.owner, super.ink});

  /// Three corners or more.
  final List<SpPoint> points;

  @override
  Box get bounds {
    var left = points.first.x;
    var top = points.first.y;
    var right = left;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.x);
      top = math.min(top, point.y);
      right = math.max(right, point.x);
      bottom = math.max(bottom, point.y);
    }
    return Box(left, top, right, bottom);
  }

  @override
  PolygonDraw shift(double dx, double dy) => PolygonDraw(
    [for (final p in points) p.shift(dx, dy)],
    owner: owner,
    ink: ink,
  );

  @override
  bool operator ==(Object other) =>
      other is PolygonDraw &&
      other.points.length == points.length &&
      other.points.indexed.every((point) => points[point.$1] == point.$2) &&
      other.owner == owner &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(Object.hashAll(points), owner, ink);
}

/// Text with its origin at the start of the baseline. [bounds] was measured
/// by the layout's `TextMeasurer`, so the painter never measures.
final class TextDraw extends Drawable {
  const TextDraw(
    this.text,
    this.origin, {
    required this.spec,
    required this.bounds,
    this.enclosed = false,
    super.owner,
    super.ink,
  });

  final String text;
  final SpPoint origin;
  final TextSpec spec;

  /// Draw a box around the text, as for a rehearsal mark. The box's outer
  /// edge is [bounds], and its line is the font's `textEnclosureThickness`
  /// thick.
  final bool enclosed;

  @override
  final Box bounds;

  @override
  TextDraw shift(double dx, double dy) => TextDraw(
    text,
    origin.shift(dx, dy),
    spec: spec,
    bounds: bounds.shift(dx, dy),
    enclosed: enclosed,
    owner: owner,
    ink: ink,
  );

  @override
  bool operator ==(Object other) =>
      other is TextDraw &&
      other.text == text &&
      other.origin == origin &&
      other.spec == spec &&
      other.bounds == bounds &&
      other.enclosed == enclosed &&
      other.owner == owner &&
      other.ink == ink;

  @override
  int get hashCode =>
      Object.hash(text, origin, spec, bounds, enclosed, owner, ink);
}

/// One cubic centreline, which is a tie, a slur or a grace tie. The painter
/// outlines it [endThickness] thick and fills [midThickness] more at the
/// middle, so the ink there is the sum of the two and [bounds] grows by half
/// that sum. A [dashed] curve is the centreline alone, stroked
/// [midThickness] thick.
final class CurveDraw extends Drawable {
  const CurveDraw({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
    required this.endThickness,
    required this.midThickness,
    this.dashed = false,
    super.owner,
    super.ink,
  });

  final SpPoint start;
  final SpPoint control1;
  final SpPoint control2;
  final SpPoint end;
  final double endThickness;
  final double midThickness;
  final bool dashed;

  /// The exact box of the centreline, grown on every side by half of the
  /// end and middle thicknesses together.
  @override
  Box get bounds {
    final allowance = (midThickness + endThickness) / 2;
    final xs = _extrema(start.x, control1.x, control2.x, end.x);
    final ys = _extrema(start.y, control1.y, control2.y, end.y);
    return Box(
      xs.reduce(math.min) - allowance,
      ys.reduce(math.min) - allowance,
      xs.reduce(math.max) + allowance,
      ys.reduce(math.max) + allowance,
    );
  }

  /// The centreline at [t], from [start] at 0 to [end] at 1.
  SpPoint pointAt(double t) => SpPoint(
    _cubic(start.x, control1.x, control2.x, end.x, t),
    _cubic(start.y, control1.y, control2.y, end.y, t),
  );

  @override
  CurveDraw shift(double dx, double dy) => CurveDraw(
    start: start.shift(dx, dy),
    control1: control1.shift(dx, dy),
    control2: control2.shift(dx, dy),
    end: end.shift(dx, dy),
    endThickness: endThickness,
    midThickness: midThickness,
    dashed: dashed,
    owner: owner,
    ink: ink,
  );

  /// A curve is hit near its line, not anywhere in its box. A slur's box
  /// covers every note under the arc, and a tap on those is not a tap on
  /// the slur.
  @override
  bool hits(SpPoint point, double reach) {
    final within = reach + midThickness / 2;
    var previous = start;
    for (var i = 1; i <= _hitSegments; i++) {
      final next = pointAt(i / _hitSegments);
      if (_distanceToSegment(point, previous, next) <= within) {
        return true;
      }
      previous = next;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is CurveDraw &&
      other.start == start &&
      other.control1 == control1 &&
      other.control2 == control2 &&
      other.end == end &&
      other.endThickness == endThickness &&
      other.midThickness == midThickness &&
      other.dashed == dashed &&
      other.owner == owner &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(
    start,
    control1,
    control2,
    end,
    endThickness,
    midThickness,
    dashed,
    owner,
    ink,
  );
}

const int _hitSegments = 16;

double _cubic(double p0, double p1, double p2, double p3, double t) {
  final u = 1 - t;
  return u * u * u * p0 +
      3 * u * u * t * p1 +
      3 * u * t * t * p2 +
      t * t * t * p3;
}

/// The cubic through [p0] to [p3] at its ends and at every interior
/// extremum, which is a root in (0, 1) of its derivative's quadratic.
List<double> _extrema(double p0, double p1, double p2, double p3) {
  final a = -p0 + 3 * p1 - 3 * p2 + p3;
  final b = 2 * (p0 - 2 * p1 + p2);
  final c = p1 - p0;
  return [
    p0,
    p3,
    for (final t in _roots(a, b, c))
      if (t > 0 && t < 1) _cubic(p0, p1, p2, p3, t),
  ];
}

/// The real roots of `a t^2 + b t + c`.
List<double> _roots(double a, double b, double c) {
  if (a == 0) {
    return b == 0 ? const [] : [-c / b];
  }
  final discriminant = b * b - 4 * a * c;
  if (discriminant < 0) {
    return const [];
  }
  // A nearly straight curve has a tiny a, where the textbook formula
  // cancels. This form keeps both roots exact.
  final q = -(b + (b < 0 ? -1 : 1) * math.sqrt(discriminant)) / 2;
  return [q / a, if (q != 0) c / q];
}

double _distanceToSegment(SpPoint point, SpPoint a, SpPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final length2 = dx * dx + dy * dy;
  final along = length2 == 0
      ? 0.0
      : (((point.x - a.x) * dx + (point.y - a.y) * dy) / length2).clamp(
          0.0,
          1.0,
        );
  final px = a.x + along * dx - point.x;
  final py = a.y + along * dy - point.y;
  return math.sqrt(px * px + py * py);
}

/// A glyph repeated [count] times from [from] to [to] on the baseline
/// `from.y`, for a trill line. The painter draws copy `i` at
/// `from.x + i * (to.x - from.x) / count`. [bounds] is the glyph's box over
/// the run, set by the producer, which knows the font.
final class GlyphRunDraw extends Drawable {
  const GlyphRunDraw(
    this.glyph, {
    required this.from,
    required this.to,
    required this.count,
    required this.bounds,
    super.owner,
    super.ink,
  });

  final Glyph glyph;
  final SpPoint from;
  final SpPoint to;
  final int count;

  @override
  final Box bounds;

  @override
  GlyphRunDraw shift(double dx, double dy) => GlyphRunDraw(
    glyph,
    from: from.shift(dx, dy),
    to: to.shift(dx, dy),
    count: count,
    bounds: bounds.shift(dx, dy),
    owner: owner,
    ink: ink,
  );

  @override
  bool operator ==(Object other) =>
      other is GlyphRunDraw &&
      other.glyph == glyph &&
      other.from == from &&
      other.to == to &&
      other.count == count &&
      other.bounds == bounds &&
      other.owner == owner &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(glyph, from, to, count, bounds, owner, ink);
}
