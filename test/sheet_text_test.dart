import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart';
import 'package:simple_sheet_music/src/painting.dart';
import 'package:simple_sheet_music/src/paragraph_measurer.dart';

import 'support/draw.dart';
import 'support/glyph_gate.dart';

// `flutter test` sets a text with no family in a font whose letters are
// boxes one em wide, from three quarters of an em above the baseline to a
// quarter of an em below it.
const TextSpec spec = TextSpec(size: 2);

/// `abc` with the start of its baseline at [origin], in the box [extent]
/// gives it.
TextDraw textAt(SpPoint origin, TextExtent extent) => TextDraw(
  'abc',
  origin,
  spec: spec,
  bounds: Box(
    origin.x,
    origin.y - extent.ascent,
    origin.x + extent.width,
    origin.y + extent.descent,
  ),
);

void main() {
  testWidgets(
    'a text is measured in staff spaces as the box its letters are painted '
    'in, at every scale',
    (tester) async {
      final extent = ParagraphMeasurer().measure('abc', spec);
      expect(extent.width, closeTo(6, 1e-9));
      expect(extent.ascent, closeTo(1.5, 1e-9));
      expect(extent.descent, closeTo(0.5, 1e-9));

      final text = textAt(const SpPoint(2, 3), extent);
      final painter = GlyphPainter(SmuflFont.bravura);
      for (final spacePx in [8.0, 20.0]) {
        final side = (10 * spacePx).toInt();
        final image = (await tester.runAsync(
          () => render(
            side,
            side,
            (canvas) => paintDrawables(
              canvas,
              painter,
              [text],
              SheetScale(spacePx: spacePx),
            ),
            background: null,
          ),
        ))!;
        final ink = inkIn(
          image.rgba,
          side,
          left: 0,
          top: 0,
          right: side,
          bottom: side,
        )!;
        final reason = 'at $spacePx pixels a staff space';
        expect(ink.left, closeTo(2 * spacePx, 1), reason: reason);
        expect(ink.top, closeTo(1.5 * spacePx, 1), reason: reason);
        expect(ink.right, closeTo(8 * spacePx, 1), reason: reason);
        expect(ink.bottom, closeTo(3.5 * spacePx, 1), reason: reason);
      }
    },
  );

  testWidgets('one painter draws a text in each colour asked for', (
    tester,
  ) async {
    const scale = SheetScale(spacePx: 8);
    const red = ui.Color(0xFFFF0000);
    const blue = ui.Color(0xFF0000FF);
    final extent = ParagraphMeasurer().measure('abc', spec);
    final painter = GlyphPainter(SmuflFont.bravura);
    final texts = [
      for (final (row, color) in const [red, blue, red].indexed)
        (text: textAt(SpPoint(1, 2.0 + 3 * row), extent), color: color),
    ];

    final image = (await tester.runAsync(
      () => render(
        64,
        96,
        (canvas) {
          for (final (:text, :color) in texts) {
            paintDrawable(canvas, text, painter, scale, color);
          }
        },
      ),
    ))!;
    for (final (:text, :color) in texts) {
      final middle = scale.toPx(
        SpPoint(
          (text.bounds.left + text.bounds.right) / 2,
          (text.bounds.top + text.bounds.bottom) / 2,
        ),
      );
      final at = (middle.dy.floor() * 64 + middle.dx.floor()) * 4;
      expect(
        (image.rgba[at], image.rgba[at + 2]),
        (color == red ? 255 : 0, color == blue ? 255 : 0),
        reason: 'the text at ${text.origin}',
      );
    }
  });
}
