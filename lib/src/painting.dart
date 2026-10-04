/// Painting. The only code that knows pixels. Not exported.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:simple_sheet_music/src/score_player.dart';
import 'package:simple_sheet_music/src/sheet_palette.dart';

/// The one conversion between staff spaces and logical pixels.
///
/// A point in sheet space maps to `origin + point * spacePx`. Every pixel
/// value in the package comes from here, so a unit mix-up (the old engine
/// added pixel margins to font-unit widths) has one place to happen.
@immutable
final class SheetScale {
  const SheetScale({required this.spacePx, this.origin = Offset.zero});

  /// Logical pixels per staff space, the view's staff size times zoom.
  final double spacePx;

  /// Where sheet (0, 0) sits in the target's pixel space.
  final Offset origin;

  Offset toPx(SpPoint point) =>
      origin + Offset(point.x * spacePx, point.y * spacePx);

  Rect rectOf(Box box) => Rect.fromLTRB(
    origin.dx + box.left * spacePx,
    origin.dy + box.top * spacePx,
    origin.dx + box.right * spacePx,
    origin.dy + box.bottom * spacePx,
  );

  SpPoint toSheet(Offset px) => SpPoint(
    (px.dx - origin.dx) / spacePx,
    (px.dy - origin.dy) / spacePx,
  );

  @override
  bool operator ==(Object other) =>
      other is SheetScale && other.spacePx == spacePx && other.origin == origin;

  @override
  int get hashCode => Object.hash(spacePx, origin);
}

/// [path] as [dash] strokes it, with lengths measured along the path. A dash
/// is half a space and a dot a tenth. The gap between two is a quarter of a
/// space, widened until the last dash ends where the path does, so a line
/// meets its hook and a curve its note. A path too short for two dashes is
/// stroked whole.
Path dashPath(Path path, LineDash dash, double spacePx) {
  if (dash == LineDash.solid) {
    return path;
  }
  final on = (dash == LineDash.dashed ? 0.5 : 0.1) * spacePx;
  final off = 0.25 * spacePx;
  final dashes = Path();
  for (final metric in path.computeMetrics()) {
    final count = (metric.length + off) ~/ (on + off);
    if (count < 2) {
      dashes.addPath(metric.extractPath(0, metric.length), Offset.zero);
      continue;
    }
    final step = (metric.length - on) / (count - 1);
    for (var i = 0; i < count; i++) {
      dashes.addPath(metric.extractPath(i * step, i * step + on), Offset.zero);
    }
  }
  return dashes;
}

/// Draws a tie or a slur.
///
/// The ink is the crescent between two cubics that share the curve's ends,
/// their control points `midThickness / 1.5` above and below the
/// centreline's, filled and outlined `endThickness` wide. A control point
/// moves a cubic's middle by three quarters of its own move, so the fill is
/// `midThickness` thick there and the ink stays within half of both
/// thicknesses of the centreline, which is what `CurveDraw.bounds` allows.
/// A dashed curve is its centreline alone, stroked `midThickness` wide.
void paintCurve(
  Canvas canvas,
  CurveDraw curve,
  SheetScale scale,
  Color color,
) {
  final start = scale.toPx(curve.start);
  final control1 = scale.toPx(curve.control1);
  final control2 = scale.toPx(curve.control2);
  final end = scale.toPx(curve.end);
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke;
  if (curve.dashed) {
    final centreline = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      dashPath(centreline, LineDash.dashed, scale.spacePx),
      stroke..strokeWidth = curve.midThickness * scale.spacePx,
    );
    return;
  }
  final s = curve.midThickness / 1.5 * scale.spacePx;
  final crescent = Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(
      control1.dx,
      control1.dy - s,
      control2.dx,
      control2.dy - s,
      end.dx,
      end.dy,
    )
    ..cubicTo(
      control2.dx,
      control2.dy + s,
      control1.dx,
      control1.dy + s,
      start.dx,
      start.dy,
    )
    ..close();
  canvas
    ..drawPath(crescent, Paint()..color = color)
    ..drawPath(
      crescent,
      stroke
        ..strokeWidth = curve.endThickness * scale.spacePx
        // A mitred tip can reach two end thicknesses past the curve's end,
        // which is outside its bounds.
        ..strokeJoin = StrokeJoin.round,
    );
}

/// Draws the box of a `TextDraw` that is `enclosed`, as around a rehearsal
/// mark. [bounds] is the box's outer edge, so the line, [thickness] staff
/// spaces wide, is stroked half its width inside it.
void paintEnclosure(
  Canvas canvas,
  Box bounds,
  double thickness,
  SheetScale scale,
  Color color,
) {
  final width = thickness * scale.spacePx;
  canvas.drawRect(
    scale.rectOf(bounds).deflate(width / 2),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width,
  );
}

/// One line of [text] set as [spec] says, [fontSize] logical pixels high.
/// The measurer and the painter both build their text here, so the box a
/// layout gives a text holds the letters that are painted.
ui.Paragraph textParagraph(
  String text,
  TextSpec spec,
  double fontSize,
  Color color,
) {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(fontFamily: spec.family, fontSize: fontSize),
        )
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontFamily: spec.family,
            fontSize: fontSize,
            fontWeight: spec.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
          ),
        )
        ..addText(text);
  return builder.build()
    ..layout(const ui.ParagraphConstraints(width: double.infinity));
}

/// Draws SMuFL glyphs as text in the font's family, and the sheet's text.
/// This class is the whole seam for the glyph source. A path-based painter
/// would replace it and nothing else.
///
/// The font is the unmodified Bravura OTF, declared as a package font, so
/// in an app it is loaded before the first frame and drawing needs no async
/// step. `flutter test` registers no pubspec font, so a test loads the file
/// with a `FontLoader` under [family] first. A glyph is one `dart:ui`
/// paragraph, built once per codepoint, pixel size and colour, and placed
/// by its baseline. The SMuFL origin is on the baseline, so no magic offset
/// is needed. Font size is 4 staff spaces, since a SMuFL em is 4 staff
/// spaces. The paragraph sets no line height, no font feature and no text
/// scale. Zoom is the size control.
///
/// The engine draws a line of text with its baseline on the nearest whole
/// pixel of the paragraph, and reports the baseline unrounded. So the
/// painter rounds what it subtracts. A probe on the host found glyphs up to
/// half a logical pixel off without that, which is 0.06 staff spaces at the
/// default size. The engine also puts glyph ink on whole device pixels
/// vertically, and the painter leaves that alone, so a glyph sits up to a
/// device pixel from the staff line it belongs on.
///
/// A painter is replaced, not cleared, when its paragraphs can no longer
/// be trusted (a new style, a font that loaded late). The system painters
/// compare it by identity, so a new one repaints them.
final class GlyphPainter {
  GlyphPainter(this.font);

  final SmuflFont font;

  /// At most [_capacity] paragraphs, the oldest dropped first. One zoom
  /// level and one palette need 222 at most, so a zoom or a tint colour
  /// that is no longer used falls out by itself.
  final Map<(int, double, Color), ui.Paragraph> _paragraphs = {};

  /// The sheet's text, kept as the glyphs are. A text that sounds is
  /// painted again on every playback tick.
  final Map<(String, TextSpec, double, Color), ui.Paragraph> _texts = {};

  static const int _capacity = 1024;

  static ui.Paragraph _kept<K>(
    Map<K, ui.Paragraph> cache,
    K key,
    ui.Paragraph Function() build,
  ) {
    final paragraph = cache.remove(key) ?? build();
    cache[key] = paragraph;
    if (cache.length > _capacity) {
      cache.remove(cache.keys.first);
    }
    return paragraph;
  }

  /// The family to ask the engine for. The bundled Bravura is a package
  /// font, which Flutter names with the package prefix.
  String get family => font == SmuflFont.bravura
      ? 'packages/simple_sheet_music/Bravura'
      : font.family;

  /// Draws [glyph] with its SMuFL origin at [origin], a point in staff
  /// spaces.
  ///
  /// [size] scales the glyph about its origin, as for a grace note.
  /// [stretch] scales it vertically on top of that, and is 1 for every
  /// glyph but a brace.
  void paint(
    Canvas canvas,
    Glyph glyph,
    SpPoint origin,
    SheetScale scale,
    Color color, {
    double size = 1,
    double stretch = 1,
  }) {
    final fontSize = 4 * scale.spacePx * size;
    final paragraph = _kept(
      _paragraphs,
      (glyph.codepoint, fontSize, color),
      () => _build(glyph.codepoint, fontSize, color),
    );
    final at = scale.toPx(origin);
    final baseline = paragraph.alphabeticBaseline.roundToDouble();
    if (stretch == 1) {
      canvas.drawParagraph(paragraph, Offset(at.dx, at.dy - baseline));
      return;
    }
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..scale(1, stretch)
      ..drawParagraph(paragraph, Offset(0, -baseline))
      ..restore();
  }

  /// Draws the copies of [run]'s glyph, evenly spaced from its `from` to
  /// its `to`.
  void paintRun(
    Canvas canvas,
    GlyphRunDraw run,
    SheetScale scale,
    Color color,
  ) {
    for (var i = 0; i < run.count; i++) {
      paint(
        canvas,
        run.glyph,
        SpPoint(
          run.from.x + i * (run.to.x - run.from.x) / run.count,
          run.from.y,
        ),
        scale,
        color,
      );
    }
  }

  /// Draws [text] with the start of its baseline at its origin, and its box
  /// when it is enclosed. The baseline is rounded as a glyph's is.
  void paintText(Canvas canvas, TextDraw text, SheetScale scale, Color color) {
    final fontSize = text.spec.size * scale.spacePx;
    final paragraph = _kept(
      _texts,
      (text.text, text.spec, fontSize, color),
      () => textParagraph(text.text, text.spec, fontSize, color),
    );
    final at = scale.toPx(text.origin);
    canvas.drawParagraph(
      paragraph,
      Offset(at.dx, at.dy - paragraph.alphabeticBaseline.roundToDouble()),
    );
    if (text.enclosed) {
      paintEnclosure(
        canvas,
        text.bounds,
        font.defaults.textEnclosureThickness,
        scale,
        color,
      );
    }
  }

  ui.Paragraph _build(int codepoint, double fontSize, Color color) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(fontFamily: family, fontSize: fontSize),
          )
          ..pushStyle(
            ui.TextStyle(color: color, fontFamily: family, fontSize: fontSize),
          )
          ..addText(String.fromCharCode(codepoint));
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }
}

/// Paints one drawable in [color].
void paintDrawable(
  Canvas canvas,
  Drawable drawable,
  GlyphPainter glyphs,
  SheetScale scale,
  Color color,
) {
  switch (drawable) {
    case GlyphDraw(
      :final glyph,
      :final origin,
      scale: final size,
      :final stretch,
    ):
      glyphs.paint(
        canvas,
        glyph,
        origin,
        scale,
        color,
        size: size,
        stretch: stretch,
      );
    case LineDraw(:final from, :final to, :final thickness, :final dash):
      final start = scale.toPx(from);
      final end = scale.toPx(to);
      canvas.drawPath(
        dashPath(
          Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(end.dx, end.dy),
          dash,
          scale.spacePx,
        ),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness * scale.spacePx,
      );
    case PolygonDraw(:final points):
      canvas.drawPath(
        Path()..addPolygon([for (final p in points) scale.toPx(p)], true),
        Paint()..color = color,
      );
    case TextDraw():
      glyphs.paintText(canvas, drawable, scale, color);
    case CurveDraw():
      paintCurve(canvas, drawable, scale, color);
    case GlyphRunDraw():
      glyphs.paintRun(canvas, drawable, scale, color);
  }
}

/// Paints the title block above the first system. It repaints when the
/// header list, the glyph painter, the palette or the scale changes. The
/// layout hands out the same list while the sheet width and `score.meta`
/// are unchanged.
final class HeaderPainter extends CustomPainter {
  HeaderPainter({
    required this.header,
    required this.glyphs,
    required this.palette,
    required this.scale,
  });

  /// In sheet space.
  final List<Drawable> header;
  final GlyphPainter glyphs;
  final SheetPalette palette;
  final SheetScale scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final drawable in header) {
      paintDrawable(
        canvas,
        drawable,
        glyphs,
        scale,
        palette.colorOf(drawable.ink),
      );
    }
  }

  @override
  bool shouldRepaint(HeaderPainter oldDelegate) =>
      !identical(oldDelegate.header, header) ||
      !identical(oldDelegate.glyphs, glyphs) ||
      oldDelegate.palette != palette ||
      oldDelegate.scale != scale;
}

/// Paints one system's drawables and its bar number. The base layer.
///
/// It repaints only when the system object, the label, the glyph painter,
/// the palette or the scale changes. The label is compared by value, so a
/// label made again for the same number at the same place repaints
/// nothing. Its `CustomPaint` sits alone inside a `RepaintBoundary`, under
/// the overlay's `CustomPaint` in the tile's `Stack`. So a cursor move, a
/// selection or a playback tick repaints the overlay and composites this
/// layer as it is. Both painters on one `CustomPaint` would not do that,
/// because a `CustomPaint` paints its painter and its foreground painter
/// together.
final class SystemPainter extends CustomPainter {
  SystemPainter({
    required this.system,
    required this.label,
    required this.glyphs,
    required this.palette,
    required this.scale,
  });

  final SystemLayout system;

  /// The bar number at the start of the system, in system space.
  final TextDraw? label;
  final GlyphPainter glyphs;
  final SheetPalette palette;
  final SheetScale scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final drawable in [...system.drawables, ?label]) {
      paintDrawable(
        canvas,
        drawable,
        glyphs,
        scale,
        palette.colorOf(drawable.ink),
      );
    }
  }

  @override
  bool shouldRepaint(SystemPainter oldDelegate) =>
      !identical(oldDelegate.system, system) ||
      oldDelegate.label != label ||
      !identical(oldDelegate.glyphs, glyphs) ||
      oldDelegate.palette != palette ||
      oldDelegate.scale != scale;
}

/// Paints what moves over one system, which is the selection, the tints,
/// the playback highlight, the playhead and the caret.
///
/// The cursor, the selection and the tints are values of this painter, so
/// a new one repaints through [shouldRepaint] when the view rebuilds.
/// Playback is a listenable the painter listens to directly, so a tick
/// repaints without a build and without touching the view's state. The
/// painter reads geometry from the layout it was given and lays nothing
/// out. The system it reads is the one its tile already shows, so the read
/// assembles nothing new.
///
/// A tick paints with the same painter. So the painter finds the
/// selection's boxes and the tinted drawables of its system once, on its
/// first paint, and a tick costs the sounding events and the playhead.
final class OverlayPainter extends CustomPainter {
  OverlayPainter({
    required this.layout,
    required this.index,
    required this.cursor,
    required this.selection,
    required this.tints,
    required this.playback,
    required this.glyphs,
    required this.palette,
    required this.scale,
  }) : super(repaint: playback);

  final SheetLayout layout;

  /// Which system of [layout] this tile shows.
  final int index;
  final VoicePoint? cursor;
  final Selection selection;
  final Map<ElementRef, Color> tints;
  final ValueListenable<PlaybackPosition?>? playback;
  final GlyphPainter glyphs;
  final SheetPalette palette;
  final SheetScale scale;

  late final SystemLayout _system = layout.systemAt(index);
  late final List<Box> _selected = layout.selectionIn(index, selection);

  // A ref with no drawables here (a hidden staff, another system) draws
  // nothing, so neither the tints nor the sounding events need a filter.
  // The system is asked by the event's id and never by the ref's measure,
  // which a change of meter leaves stale.
  late final List<(Drawable, Color)> _tinted = [
    for (final MapEntry(key: ref, value: color) in tints.entries)
      for (final drawable in _system.drawablesOf(ElementOwner(ref)))
        (drawable, color),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = palette.selection;
    for (final box in _selected) {
      canvas.drawRect(scale.rectOf(box), shade);
    }
    for (final (drawable, color) in _tinted) {
      paintDrawable(canvas, drawable, glyphs, scale, color);
    }

    final position = playback?.value;
    for (final ref in position?.sounding ?? const <EventRef>[]) {
      for (final drawable in _system.drawablesOf(ElementOwner(ref))) {
        paintDrawable(canvas, drawable, glyphs, scale, palette.playback);
      }
    }

    final playhead = position == null
        ? null
        : layout.playheadIn(index, position.point);
    if (playhead != null) {
      _line(
        canvas,
        Box(playhead, 0, playhead, _system.height),
        palette.playhead,
      );
    }
    final caret = switch (cursor) {
      final cursor? => layout.caretIn(index, cursor),
      null => null,
    };
    if (caret != null) {
      _line(canvas, caret, palette.cursor);
    }
  }

  void _line(Canvas canvas, Box box, Color color) {
    final rect = scale.rectOf(box);
    canvas.drawLine(
      rect.topLeft,
      rect.bottomLeft,
      Paint()
        ..color = color
        ..strokeWidth = scale.spacePx * 0.2,
    );
  }

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout) ||
      oldDelegate.index != index ||
      oldDelegate.cursor != cursor ||
      !identical(oldDelegate.selection, selection) ||
      !identical(oldDelegate.tints, tints) ||
      !identical(oldDelegate.playback, playback) ||
      !identical(oldDelegate.glyphs, glyphs) ||
      oldDelegate.palette != palette ||
      oldDelegate.scale != scale;
}
