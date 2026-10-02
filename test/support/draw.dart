/// Paints the engine's drawables through `GlyphPainter` and measures its
/// text, for the tests that look at a picture.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:score_layout/score_layout.dart';
import 'package:simple_sheet_music/src/painting.dart';

const ui.Color black = ui.Color(0xFF000000);
const ui.Color red = ui.Color(0xFFC62828);

const String textFamily = 'SheetText';

/// `flutter test` registers no pubspec font, so the file is loaded under the
/// family the painter asks for.
Future<void> loadBravura(GlyphPainter painter) async {
  final bytes = File('fonts/Bravura.otf').readAsBytesSync();
  final loader = FontLoader(painter.family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// Loads a text font of the host under [textFamily] when it has one, so
/// that names and titles are letters in the pictures. Without one the
/// engine draws every letter as a box, which the tests accept.
Future<void> loadTextFont() async {
  final file = File('/System/Library/Fonts/Supplemental/Arial.ttf');
  if (!file.existsSync()) {
    return;
  }
  final loader = FontLoader(textFamily)
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

ui.Paragraph textParagraph(
  String text,
  TextSpec spec,
  double fontSize,
  ui.Color color,
) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(fontFamily: textFamily, fontSize: fontSize),
  )
    ..pushStyle(
      ui.TextStyle(
        color: color,
        fontFamily: textFamily,
        fontSize: fontSize,
        fontWeight: spec.bold ? ui.FontWeight.bold : ui.FontWeight.normal,
        fontStyle: spec.italic ? ui.FontStyle.italic : ui.FontStyle.normal,
      ),
    )
    ..addText(text);
  return builder.build()
    ..layout(const ui.ParagraphConstraints(width: double.infinity));
}

/// Measures text through the paragraphs [paintDrawables] draws, so that the
/// layout's text boxes hold the painted letters.
final class UiMeasurer implements TextMeasurer {
  const UiMeasurer();

  /// Pixels per staff space the probe paragraph is laid out at. Text metrics
  /// scale with the font size, so one size serves every zoom.
  static const double _probePx = 64;

  @override
  TextExtent measure(String text, TextSpec spec) {
    final paragraph = textParagraph(text, spec, spec.size * _probePx, black);
    return TextExtent(
      width: paragraph.maxIntrinsicWidth / _probePx,
      ascent: paragraph.alphabeticBaseline / _probePx,
      descent: (paragraph.height - paragraph.alphabeticBaseline) / _probePx,
    );
  }
}

/// Draws [drawables], already in sheet space, on [canvas] at [scale]. Ink
/// marked out of range is red, everything else black.
void paintDrawables(
  ui.Canvas canvas,
  GlyphPainter painter,
  Iterable<Drawable> drawables,
  SheetScale scale,
) {
  for (final drawable in drawables) {
    final color = drawable.ink == InkRole.outOfRange ? red : black;
    switch (drawable) {
      case GlyphDraw(
          :final glyph,
          :final origin,
          scale: final size,
          :final stretch
        ):
        painter.paint(
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
            ui.Path()
              ..moveTo(start.dx, start.dy)
              ..lineTo(end.dx, end.dy),
            dash,
            scale.spacePx,
          ),
          ui.Paint()
            ..color = color
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = thickness * scale.spacePx,
        );
      case PolygonDraw(:final points):
        canvas.drawPath(
          ui.Path()..addPolygon([for (final p in points) scale.toPx(p)], true),
          ui.Paint()..color = color,
        );
      case TextDraw(:final text, :final origin, :final spec):
        final paragraph = textParagraph(
          text,
          spec,
          spec.size * scale.spacePx,
          color,
        );
        final at = scale.toPx(origin);
        canvas.drawParagraph(
          paragraph,
          ui.Offset(at.dx, at.dy - paragraph.alphabeticBaseline),
        );
        if (drawable.enclosed) {
          paintEnclosure(
            canvas,
            drawable.bounds,
            painter.font.defaults.textEnclosureThickness,
            scale,
            color,
          );
        }
      case CurveDraw():
        paintCurve(canvas, drawable, scale, color);
      case GlyphRunDraw():
        painter.paintRun(canvas, drawable, scale, color);
    }
  }
}

/// The lines of a staff with its top line at [top], from [left] to [right].
/// A one-line staff draws its line at step 4.
List<LineDraw> staffLines({
  required int lines,
  required double top,
  required double left,
  required double right,
  required double thickness,
}) =>
    [
      for (final step in lines == 1 ? const [4] : const [0, 2, 4, 6, 8])
        LineDraw(
          SpPoint(left, top + yOfStep(step)),
          SpPoint(right, top + yOfStep(step)),
          thickness: thickness,
          ink: InkRole.staffLine,
        ),
    ];

/// Writes [png] as `<name>.png` into the directory the `SNAPSHOT_DIR`
/// environment variable names, when it is set, for looking at.
void writeSnapshot(String name, Uint8List png) {
  final dir = Platform.environment['SNAPSHOT_DIR'];
  if (dir != null) {
    File('$dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png);
  }
}

/// An RGBA image of [width] by [height] pixels after [draw] on a
/// [background], white unless given, or transparent when null, with its PNG
/// encoding. Only a transparent background lets `inkIn` tell ink apart.
Future<({Uint8List rgba, Uint8List png})> render(
  int width,
  int height,
  void Function(ui.Canvas canvas) draw, {
  ui.Color? background = const ui.Color(0xFFFFFFFF),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (background != null) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = background,
    );
  }
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final rgba = (await image.toByteData())!.buffer.asUint8List();
  final png = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!
      .buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return (rgba: rgba, png: png);
}
