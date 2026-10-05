import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart'
    show CurveDraw, LineDraw, SheetLayout, SpPoint, TextDraw;
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

/// The red ink in the pixels whose corner is in [area], in pixels fully
/// covered. Ink of another colour counts for nothing.
double inkIn(Pixels pixels, Rect area) {
  var alpha = 0;
  for (var y = area.top.floor(); y < area.bottom.floor(); y++) {
    for (var x = area.left.floor(); x < area.right.floor(); x++) {
      final i = (y * pixels.width + x) * 4;
      if (pixels.rgba[i] > 0 &&
          pixels.rgba[i + 1] == 0 &&
          pixels.rgba[i + 2] == 0) {
        alpha += pixels.rgba[i + 3];
      }
    }
  }
  return alpha / 255;
}

void main() {
  test('a copy of the bundled font with other defaults is drawn with the '
      'bundled font file, and a font of another family or over another glyph '
      'table with its own', () async {
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

    final parsed = SmuflFont(
      family: SmuflFont.bravura.family,
      glyphs: Map.of(copy.glyphs),
      defaults: copy.defaults,
    );
    expect(GlyphPainter(parsed).family, SmuflFont.bravura.family);
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

  test('a line, a curve and a box of no thickness draw nothing', () async {
    await loadTextFont();
    final font = fontWith(
      (defaults) => defaults.copyWith(
        stemThickness: 0,
        slurEndpointThickness: 0,
        slurMidpointThickness: 0,
        textEnclosureThickness: 0,
      ),
    );
    final layout = SheetLayout(
      pictured(),
      width: sheetWidth,
      text: ParagraphMeasurer(),
      style: EngravingStyle(font: font, text: pictureStyle.text),
    );
    final lines = quiet.copyWith(
      ink: clear,
      staffLines: clear,
      outOfRange: clear,
      inks: {InkRole.stem: red, InkRole.slur: red},
    );
    var stems = 0;
    final slurs = <bool>{};
    var marks = 0;

    for (var index = 0; index < layout.systemCount; index++) {
      final drawables = layout.systemAt(index).drawables;
      stems += drawables
          .whereType<LineDraw>()
          .where((line) => line.ink == InkRole.stem)
          .length;
      slurs.addAll([
        for (final curve in drawables.whereType<CurveDraw>())
          if (curve.ink == InkRole.slur) curve.dashed,
      ]);
      final pixels = await systemOf(layout, index, font, lines);
      expect(
        pixels.rgba.every((byte) => byte == 0),
        isTrue,
        reason: 'the stems and the slurs of system $index',
      );

      final boxed = drawables.whereType<TextDraw>().where(
        (text) => text.enclosed,
      );
      if (boxed.isEmpty) {
        continue;
      }
      final letters = await systemOf(
        layout,
        index,
        font,
        only(InkRole.rehearsal),
      );
      for (final mark in boxed) {
        marks++;
        final box = scale.rectOf(mark.bounds);
        expect(
          inkIn(letters, box.deflate(spacePx * 0.15)),
          greaterThan(0),
          reason: 'the letter of rehearsal mark ${mark.text}',
        );
        expect(
          inkIn(letters, box.inflate(2)) -
              inkIn(letters, box.deflate(spacePx * 0.15)),
          0,
          reason: 'the box of rehearsal mark ${mark.text}',
        );
      }
    }
    expect(stems, greaterThan(0));
    expect(slurs, {true, false}, reason: 'a dashed slur and a solid one');
    expect(marks, 2);
  });

  test('a slur whose ends have no thickness is drawn without an '
      'outline', () async {
    final layout = SheetLayout(
      pictured(),
      width: sheetWidth,
      text: ParagraphMeasurer(),
    );
    final slurs = [
      for (var index = 0; index < layout.systemCount; index++)
        for (final curve
            in layout.systemAt(index).drawables.whereType<CurveDraw>())
          if (curve.ink == InkRole.slur && !curve.dashed) (index, curve),
    ];
    expect(slurs, isNotEmpty);

    for (final (index, slur) in slurs) {
      final width = (sheetWidth * spacePx + 80).ceil();
      final height = (layout.heightOf(index) * spacePx + 80).ceil();
      Future<double> inkWith(double ends) async {
        final picture = await render(
          width,
          height,
          (canvas) => paintCurve(
            canvas,
            CurveDraw(
              start: slur.start,
              control1: slur.control1,
              control2: slur.control2,
              end: slur.end,
              endThickness: ends,
              midThickness: slur.midThickness,
              ink: slur.ink,
            ),
            scale,
            red,
          ),
          background: null,
        );
        return inkIn(
          (width: width, rgba: picture.rgba),
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        );
      }

      final bare = await inkWith(0);
      expect(bare, greaterThan(0));
      expect(
        bare,
        lessThan(await inkWith(0.01)),
        reason: 'the slur from x ${slur.start.x} of system $index',
      );
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
