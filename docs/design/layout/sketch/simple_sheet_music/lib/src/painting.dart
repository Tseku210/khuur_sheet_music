/// Painting. The only code that knows pixels. Not exported.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';

import 'score_player.dart';
import 'sheet_palette.dart';

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
/// Whether the text stack puts every glyph's ink where the metadata says is
/// the first thing the implementation checks, on each platform, before any
/// layout code is written.
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

  static const int _capacity = 1024;

  /// The family to ask the engine for. The bundled Bravura is a package
  /// font, which Flutter names with the package prefix.
  String get family => font == SmuflFont.bravura
      ? 'packages/simple_sheet_music/Bravura'
      : font.family;

  void paint(Canvas canvas, GlyphDraw glyph, SheetScale scale, Color color) {
    final size = 4 * scale.spacePx * glyph.scale;
    final key = (glyph.glyph.codepoint, size, color);
    final paragraph =
        _paragraphs.remove(key) ?? _build(glyph.glyph.codepoint, size, color);
    _paragraphs[key] = paragraph;
    if (_paragraphs.length > _capacity) {
      _paragraphs.remove(_paragraphs.keys.first);
    }
    final at = scale.toPx(glyph.origin);
    final baseline = paragraph.alphabeticBaseline.roundToDouble();
    if (glyph.stretch == 1) {
      canvas.drawParagraph(paragraph, Offset(at.dx, at.dy - baseline));
      return;
    }
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..scale(1, glyph.stretch)
      ..drawParagraph(paragraph, Offset(0, -baseline))
      ..restore();
  }

  ui.Paragraph _build(int codepoint, double size, Color color) {
    // TODO: ParagraphBuilder with ParagraphStyle(fontFamily: family,
    // fontSize: size), TextStyle(color: color), addText of the codepoint,
    // build and layout with infinite width.
    throw UnimplementedError();
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
    case GlyphDraw():
      glyphs.paint(canvas, drawable, scale, color);
    case LineDraw():
    case PolygonDraw():
    case CurveDraw():
    case GlyphRunDraw():
    case TextDraw():
      // TODO: lines and polygons with Paint in px from SheetScale. Curves
      // as a filled crescent path. Glyph runs by repeating the glyph. Text
      // by the glyph painter, from a paragraph it keeps per text, spec,
      // pixel size and colour as it keeps a glyph's, placed by its rounded
      // baseline. The painter and the measurer build that paragraph with
      // one function, so a text's box holds the letters that are painted.
      throw UnimplementedError();
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
/// nothing. Its `CustomPaint` sits alone inside a `RepaintBoundary`,
/// under the overlay's `CustomPaint` in the tile's `Stack`. So a cursor
/// move, a selection or a playback tick repaints the overlay and composites
/// this layer as it is. Putting both painters on one `CustomPaint` would
/// not do that, because a `CustomPaint` paints its painter and its
/// foreground painter together.
final class SystemPainter extends CustomPainter {
  SystemPainter({
    required this.system,
    required this.label,
    required this.glyphs,
    required this.palette,
    required this.scale,
  });

  final SystemLayout system;
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

/// Paints what moves over one system, which is the selection, tints, the
/// playback highlight, the playhead and the caret.
///
/// The cursor, the selection and the tints are values of this painter, so
/// a new one repaints through [shouldRepaint] when the view rebuilds.
/// Playback is a listenable the painter listens to directly, so a tick
/// repaints without a build and without touching the view's state. The
/// painter reads geometry from the layout it was given and lays nothing
/// out. The system it reads is the one its tile already shows, so the read
/// assembles nothing new.
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

  @override
  void paint(Canvas canvas, Size size) {
    final system = layout.systemAt(index);
    final shade = Paint()..color = palette.selection;
    for (final box in layout.selectionIn(index, selection)) {
      canvas.drawRect(scale.rectOf(box), shade);
    }

    final position = playback?.value;
    final sounding = position?.sounding ?? const <EventRef>[];
    // A ref with no drawables here (a hidden staff, another system) draws
    // nothing, so neither list needs a filter. The system is asked by the
    // event's id and never by the ref's measure, which a change of meter
    // leaves stale.
    for (final (ref, color) in [
      for (final MapEntry(:key, :value) in tints.entries) (key, value),
      for (final ref in sounding) (ref, palette.playback),
    ]) {
      for (final drawable in system.drawablesOf(ElementOwner(ref))) {
        paintDrawable(canvas, drawable, glyphs, scale, color);
      }
    }

    final playhead = position == null
        ? null
        : layout.playheadIn(index, position.point);
    if (playhead != null) {
      _line(
        canvas,
        Box(playhead, 0, playhead, system.height),
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
