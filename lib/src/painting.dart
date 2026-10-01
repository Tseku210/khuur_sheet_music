/// Painting. The only code that knows pixels. Not exported.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:score_layout/score_layout.dart';

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

/// Draws SMuFL glyphs as text in the font's family. This class is the whole
/// seam for the glyph source. A path-based painter would replace it and
/// nothing else.
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
/// be trusted (a new style, a font that loaded late).
final class GlyphPainter {
  GlyphPainter(this.font);

  final SmuflFont font;

  /// At most [_capacity] paragraphs, the oldest dropped first. One zoom
  /// level and one palette need 222 at most, so a zoom or a tint colour
  /// that is no longer used falls out by itself.
  final Map<(int, double, Color), ui.Paragraph> _paragraphs = {};

  static const int _capacity = 1024;

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
    final key = (glyph.codepoint, fontSize, color);
    final paragraph =
        _paragraphs.remove(key) ?? _build(glyph.codepoint, fontSize, color);
    _paragraphs[key] = paragraph;
    if (_paragraphs.length > _capacity) {
      _paragraphs.remove(_paragraphs.keys.first);
    }
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

  ui.Paragraph _build(int codepoint, double fontSize, Color color) {
    final builder = ui.ParagraphBuilder(
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
