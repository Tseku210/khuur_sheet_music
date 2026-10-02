import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'geometry.dart';
import 'glyphs.dart';

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
