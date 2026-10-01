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

  Box get bounds;

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

  final List<SpPoint> points;

  @override
  Box get bounds => throw UnimplementedError();

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

/// A tie or a slur. It is a filled crescent between two cubic curves, thin at
/// the ends and thick in the middle, per the font's engraving defaults.
final class CurveDraw extends Drawable {
  const CurveDraw({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
    required this.endThickness,
    required this.midThickness,
    super.owner,
    super.ink,
  });

  final SpPoint start;
  final SpPoint control1;
  final SpPoint control2;
  final SpPoint end;
  final double endThickness;
  final double midThickness;

  @override
  Box get bounds => throw UnimplementedError();

  @override
  CurveDraw shift(double dx, double dy) => throw UnimplementedError();

  /// A curve is hit near its line, not anywhere in its box. A slur's box
  /// covers every note under the arc, and a tap on those is not a tap on
  /// the slur.
  @override
  bool hits(SpPoint point, double reach) => throw UnimplementedError();

  @override
  bool operator ==(Object other) =>
      other is CurveDraw &&
      other.start == start &&
      other.control1 == control1 &&
      other.control2 == control2 &&
      other.end == end &&
      other.endThickness == endThickness &&
      other.midThickness == midThickness &&
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
    owner,
    ink,
  );
}

/// A glyph repeated along a horizontal run, for a trill line or a wavy
/// glissando.
final class GlyphRunDraw extends Drawable {
  const GlyphRunDraw(
    this.glyph, {
    required this.from,
    required this.to,
    super.owner,
    super.ink,
  });

  final Glyph glyph;
  final SpPoint from;
  final SpPoint to;

  @override
  Box get bounds => throw UnimplementedError();

  @override
  GlyphRunDraw shift(double dx, double dy) => throw UnimplementedError();

  @override
  bool operator ==(Object other) =>
      other is GlyphRunDraw &&
      other.glyph == glyph &&
      other.from == from &&
      other.to == to &&
      other.owner == owner &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(glyph, from, to, owner, ink);
}

/// Text with its origin at the start of the baseline. [bounds] was measured
/// by the layout's TextMeasurer, so the painter never measures.
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

  /// Draw a box around the text, as for a rehearsal mark.
  final bool enclosed;

  @override
  final Box bounds;

  @override
  TextDraw shift(double dx, double dy) => throw UnimplementedError();

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
