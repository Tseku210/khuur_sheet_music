/// Paints the engine's drawables through the library's painter, for the
/// tests that look at a picture.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:score_layout/score_layout.dart';
import 'package:simple_sheet_music/src/painting.dart';

const ui.Color black = ui.Color(0xFF000000);

const String textFamily = 'SheetText';

const String bravuraFile = 'fonts/Bravura.otf';

/// Registers the font in the file at [path] under [family].
Future<void> loadFontFile(String path, String family) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

/// `flutter test` registers no pubspec font, so the file is loaded under the
/// family the painter asks for.
Future<void> loadBravura(GlyphPainter painter) =>
    loadFontFile(bravuraFile, painter.family);

/// Loads a text font of the host under [textFamily] when it has one, so
/// that names and titles are letters in the pictures. Without one the
/// engine draws every letter as a box, which the tests accept.
Future<void> loadTextFont() async {
  const path = '/System/Library/Fonts/Supplemental/Arial.ttf';
  if (File(path).existsSync()) {
    await loadFontFile(path, textFamily);
  }
}

/// The standard style with every text in [textFamily]. A layout in it, with
/// a `ParagraphMeasurer`, has text boxes that hold the letters
/// [paintDrawables] draws.
final EngravingStyle pictureStyle = EngravingStyle(
  text: {
    for (final role in TextRole.values)
      role: TextSpec(
        size: role.standard.size,
        italic: role.standard.italic,
        bold: role.standard.bold,
        family: textFamily,
      ),
  },
);

/// Draws [drawables], already in sheet space, on [canvas] at [scale], in
/// black.
void paintDrawables(
  ui.Canvas canvas,
  GlyphPainter painter,
  Iterable<Drawable> drawables,
  SheetScale scale,
) {
  for (final drawable in drawables) {
    paintDrawable(canvas, drawable, painter, scale, black);
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
}) => [
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
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return (rgba: rgba, png: png);
}
