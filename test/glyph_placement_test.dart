import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart' show Glyph, SpPoint;
import 'package:simple_sheet_music/src/painting.dart';

import 'support/draw.dart';
import 'support/glyph_gate.dart';

Future<Ink?> inkOfRect(ui.Rect rect) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(rect, ui.Paint());
  final image = await recorder.endRecording().toImage(40, 40);
  final rgba = (await image.toByteData())!.buffer.asUint8List();
  return inkIn(rgba, 40, left: 0, top: 0, right: 40, bottom: 40);
}

void main() {
  testWidgets('the ink reader adds no error of its own', (tester) async {
    await tester.runAsync(() async {
      for (final rect in const [
        ui.Rect.fromLTRB(5, 7, 20, 30),
        ui.Rect.fromLTRB(5.25, 7.5, 20.75, 30.125),
      ]) {
        final ink = (await inkOfRect(rect))!;
        expect(ink.left, closeTo(rect.left, 0.01), reason: '$rect');
        expect(ink.right, closeTo(rect.right, 0.01), reason: '$rect');
        expect(ink.top, closeTo(rect.top, 0.01), reason: '$rect');
        expect(ink.bottom, closeTo(rect.bottom, 0.01), reason: '$rect');
      }
      expect(await inkOfRect(ui.Rect.zero), isNull);
    });
  });

  testWidgets('every glyph is drawn where the table says', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);

      final failures = await glyphGateFailures(painter, report: debugPrint);

      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });

  testWidgets('a small glyph is its box scaled about its origin', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);

      for (final glyph in [Glyph.noteheadBlack, Glyph.flag8thUp]) {
        final errors = await measureGlyph(
          painter,
          glyph,
          spacePx: 16,
          pixelRatio: 2,
          size: 0.6,
        );

        expect(failuresAtViewSize(errors!), isEmpty, reason: glyph.name);
      }
    });
  });

  testWidgets('one painter draws a glyph in each colour asked for', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      const scale = SheetScale(spacePx: 16);
      const red = ui.Color(0xFFFF0000);
      const blue = ui.Color(0xFF0000FF);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      painter
        ..paint(canvas, Glyph.noteheadBlack, const SpPoint(1, 2), scale, red)
        ..paint(canvas, Glyph.noteheadBlack, const SpPoint(4, 2), scale, blue)
        ..paint(canvas, Glyph.noteheadBlack, const SpPoint(7, 2), scale, red);
      final image = await recorder.endRecording().toImage(160, 64);
      final rgba = (await image.toByteData())!.buffer.asUint8List();

      // The red and blue of the most opaque pixel in a third of the image.
      (int, int) inkOf(int third) {
        var best = 0;
        for (var y = 0; y < 64; y++) {
          for (var x = third * 48 + 8; x < third * 48 + 48; x++) {
            final at = (y * 160 + x) * 4;
            if (rgba[at + 3] > rgba[best + 3]) {
              best = at;
            }
          }
        }
        expect(rgba[best + 3], 255, reason: 'third $third has no solid ink');
        return (rgba[best], rgba[best + 2]);
      }

      expect(inkOf(0), (255, 0));
      expect(inkOf(1), (0, 255));
      expect(inkOf(2), (255, 0));
    });
  });

  testWidgets('a stretched brace keeps its width and its origin', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);

      for (final stretch in [0.75, 2.5]) {
        final errors = (await measureGlyph(
          painter,
          Glyph.brace,
          spacePx: 16,
          pixelRatio: 2,
          stretch: stretch,
        ))!;

        expect(errors.centreX, lessThan(0.5), reason: 'stretch $stretch');
        expect(errors.centreY, lessThan(1), reason: 'stretch $stretch');
        expect(errors.width, lessThan(1), reason: 'stretch $stretch');
        // The rasteriser's thickening is stretched with the glyph.
        expect(
          errors.height,
          lessThan(stretch < 1 ? 1 : stretch),
          reason: 'stretch $stretch',
        );
      }
    });
  });
}
