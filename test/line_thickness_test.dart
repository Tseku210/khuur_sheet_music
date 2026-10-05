import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart'
    show LineDraw, SheetLayout, SpPoint, TextDraw;
import 'package:simple_sheet_music/simple_sheet_music.dart';
import 'package:simple_sheet_music/src/painting.dart';
import 'package:simple_sheet_music/src/paragraph_measurer.dart';

import 'sheet_palette_test.dart' show clear, quiet, red;
import 'sheet_picture_test.dart' show pictured, sheetWidth;
import 'sheet_view_test.dart' show host, paintersOf, shown, tune;
import 'support/draw.dart';
import 'support/glyph_gate.dart';

const double spacePx = 20;
const SheetScale scale = SheetScale(spacePx: spacePx, origin: Offset(40, 40));

/// The bundled font with [change] made to its defaults.
SmuflFont fontWith(EngravingDefaults Function(EngravingDefaults) change) =>
    SmuflFont.bravura.copyWith(defaults: change(SmuflFont.bravura.defaults));

/// A palette that paints the marks of [role] red and no other mark.
SheetPalette only(InkRole role) => quiet.copyWith(
  ink: clear,
  staffLines: clear,
  outOfRange: clear,
  inks: {role: red},
);

typedef Pixels = ({int width, Uint8List rgba});

/// What system [index] of [layout] looks like with [font] and [palette], on
/// a clear canvas.
Future<Pixels> systemOf(
  SheetLayout layout,
  int index,
  SmuflFont font,
  SheetPalette palette,
) async {
  final painter = SystemPainter(
    system: layout.systemAt(index),
    label: null,
    glyphs: GlyphPainter(font),
    palette: palette,
    scale: scale,
  );
  final width = (sheetWidth * spacePx + 80).ceil();
  final picture = await render(
    width,
    (layout.heightOf(index) * spacePx + 80).ceil(),
    (canvas) => painter.paint(canvas, Size.zero),
    background: null,
  );
  return (width: width, rgba: picture.rgba);
}

/// The ink in the pixels whose corner is in [area], in pixels fully covered.
double inkIn(Pixels pixels, Rect area) {
  var alpha = 0;
  for (var y = area.top.floor(); y < area.bottom.floor(); y++) {
    for (var x = area.left.floor(); x < area.right.floor(); x++) {
      alpha += pixels.rgba[(y * pixels.width + x) * 4 + 3];
    }
  }
  return alpha / 255;
}

void main() {
  test('a copy of the bundled font with other defaults is drawn with the '
      'bundled font file, and a font of another family with its own', () async {
    await loadBravura(bravuraPainter());
    final copy = fontWith(
      (defaults) => defaults.copyWith(stemThickness: 0.2),
    );
    expect(await noteheadFailures(GlyphPainter(copy)), isEmpty);

    final declared = SmuflFont(
      family: 'Declared',
      glyphs: copy.glyphs,
      defaults: copy.defaults,
    );
    expect(GlyphPainter(declared).family, 'Declared');
  });

  test('a stem is as thick as the defaults of the font say', () async {
    for (final thickness in [SmuflFont.bravura.defaults.stemThickness, 0.4]) {
      final font = fontWith(
        (defaults) => defaults.copyWith(stemThickness: thickness),
      );
      final layout = SheetLayout(
        tune(),
        width: sheetWidth,
        text: ParagraphMeasurer(),
        style: EngravingStyle(font: font),
      );
      final stems = layout
          .systemAt(0)
          .drawables
          .whereType<LineDraw>()
          .where((line) => line.ink == InkRole.stem);
      expect(stems, isNotEmpty);

      final pixels = await systemOf(layout, 0, font, only(InkRole.stem));
      for (final stem in stems) {
        final middle = scale.toPx(
          SpPoint(stem.from.x, (stem.from.y + stem.to.y) / 2),
        );
        expect(
          inkIn(
            pixels,
            Rect.fromLTWH(middle.dx - spacePx / 2, middle.dy, spacePx, 1),
          ),
          closeTo(thickness * spacePx, 0.25),
          reason: 'the stem at x ${stem.from.x}',
        );
      }
    }
  });

  test('the box of a rehearsal mark is as thick as the defaults of the font '
      'say', () async {
    await loadTextFont();
    for (final thickness in [
      SmuflFont.bravura.defaults.textEnclosureThickness,
      0.5,
    ]) {
      final font = fontWith(
        (defaults) => defaults.copyWith(textEnclosureThickness: thickness),
      );
      final layout = SheetLayout(
        pictured(),
        width: sheetWidth,
        text: ParagraphMeasurer(),
        style: EngravingStyle(font: font, text: pictureStyle.text),
      );
      final line = thickness * spacePx;
      var marks = 0;

      for (var index = 0; index < layout.systemCount; index++) {
        final boxed = layout
            .systemAt(index)
            .drawables
            .whereType<TextDraw>()
            .where((text) => text.enclosed);
        if (boxed.isEmpty) {
          continue;
        }
        final pixels = await systemOf(
          layout,
          index,
          font,
          only(InkRole.rehearsal),
        );
        for (final mark in boxed) {
          marks++;
          final box = scale.rectOf(mark.bounds);
          // One column of pixels between the box's left line and the
          // letter, which crosses the line at the top and at the bottom.
          expect(
            inkIn(
              pixels,
              Rect.fromLTRB(
                box.left + line + 2,
                box.top - 2,
                box.left + line + 3,
                box.bottom + 2,
              ),
            ),
            closeTo(2 * line, 0.5),
            reason: 'rehearsal mark ${mark.text}',
          );
        }
      }
      expect(marks, 2);
    }
  });

  testWidgets('the view lays the sheet out again and paints with the new font '
      'when the defaults change, and keeps its layout for equal ones', (
    tester,
  ) async {
    final score = tune();
    SmuflFont fontOf(double stem) =>
        fontWith((defaults) => defaults.copyWith(stemThickness: stem));
    Widget view(double stem) => host(
      SheetView(
        score: score,
        style: EngravingStyle(font: fontOf(stem)),
      ),
    );
    double stemOf() =>
        shown(tester)
            .systemAt(0)
            .drawables
            .whereType<LineDraw>()
            .firstWhere((line) => line.ink == InkRole.stem)
            .thickness;

    await tester.pumpWidget(view(0.3));
    final first = shown(tester);
    expect(stemOf(), 0.3);

    await tester.pumpWidget(view(0.3));
    expect(shown(tester), same(first));

    await tester.pumpWidget(view(0.2));
    expect(stemOf(), 0.2);
    expect(
      paintersOf<SystemPainter>(tester).map((painter) => painter.glyphs.font),
      everyElement(fontOf(0.2)),
    );
  });
}
