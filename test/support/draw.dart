/// Paints the engine's drawables through `GlyphPainter`, for the tests that
/// look at a laid-out bar.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:score_layout/score_layout.dart';
import 'package:simple_sheet_music/src/painting.dart';

const ui.Color black = ui.Color(0xFF000000);
const ui.Color red = ui.Color(0xFFC62828);

/// `flutter test` registers no pubspec font, so the file is loaded under the
/// family the painter asks for.
Future<void> loadBravura(GlyphPainter painter) async {
  final bytes = File('fonts/Bravura.otf').readAsBytesSync();
  final loader = FontLoader(painter.family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
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
        canvas.drawPath(
          _linePath(scale.toPx(from), scale.toPx(to), dash, scale.spacePx),
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
    }
  }
}

/// A dash is half a space, a dot a tenth, and the gap between them a
/// quarter of a space.
ui.Path _linePath(ui.Offset from, ui.Offset to, LineDash dash, double spacePx) {
  final path = ui.Path();
  if (dash == LineDash.solid) {
    return path
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
  }
  final on = (dash == LineDash.dashed ? 0.5 : 0.1) * spacePx;
  final off = 0.25 * spacePx;
  final length = (to - from).distance;
  final unit = (to - from) / length;
  for (var at = 0.0; at < length; at += on + off) {
    final start = from + unit * at;
    final end = from + unit * (at + on < length ? at + on : length);
    path
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
  }
  return path;
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
