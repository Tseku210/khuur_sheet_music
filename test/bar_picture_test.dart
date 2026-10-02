import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/bar_space.dart';
import 'package:score_layout/src/beams.dart';
import 'package:score_layout/src/spacing.dart';
import 'package:score_model/score_model.dart';
import 'package:simple_sheet_music/src/painting.dart';

import '../packages/score_layout/test/support/bars.dart';
import '../packages/score_layout/test/support/fake_measurer.dart';
import 'support/draw.dart';
import 'support/glyph_gate.dart';

const EngravingStyle style = EngravingStyle.standard;
const double spacePx = 24;
const double margin = 1;

const NoteValue dottedQuarter = NoteValue(DurationBase.quarter, dots: 1);
const NoteValue dottedEighth = NoteValue(DurationBase.eighth, dots: 1);

/// One bar per concern this unit lays out, each drawn alone at stretch 1.
final Map<String, MeasureView> bars = {
  'scale': barOf([
    chordOf(1, 'C4', value: eighth),
    chordOf(2, 'D4', value: eighth),
    chordOf(3, 'E4', value: eighth),
    chordOf(4, 'F#4', value: eighth),
    chordOf(5, 'G4', value: eighth),
    chordOf(6, 'A4', value: eighth),
    chordOf(7, 'Bb4', value: eighth),
    chordOf(8, 'C5', value: eighth),
  ]),
  'chords': barOf([
    chordOf(1, 'C#4 D#4 F#4', value: half),
    chordOf(2, 'Eb5 F5 Ab5', value: dottedQuarter),
    chordOf(3, 'G3 B3 D4', value: eighth, tremolo: 2),
  ]),
  'beams': barOf([
    chordOf(1, 'G4', value: sixteenth, tremolo: 2),
    chordOf(2, 'A4', value: sixteenth),
    chordOf(3, 'B4', value: sixteenth),
    chordOf(4, 'C5', value: sixteenth),
    chordOf(5, 'D5', value: sixteenth),
    chordOf(6, 'E5', value: eighth),
    chordOf(7, 'F5', value: sixteenth),
    chordOf(8, 'E5', value: eighth),
    chordOf(9, 'D5', value: eighth),
    chordOf(10, 'C5', value: eighth),
    chordOf(11, 'B4', value: eighth),
  ]),
  'voices': barOf(
    [
      chordOf(1, 'C5'),
      chordOf(2, 'D5', value: eighth),
      chordOf(3, 'E5', value: eighth),
      chordOf(4, 'F5', value: half),
    ],
    two: [
      chordOf(5, 'A4', value: half),
      chordOf(6, 'G4'),
      restOf(7, NoteValue.quarter),
    ],
  ),
  'graces': barOf([
    chordOf(1, 'C5', graces: [graceOf(2, 'B4')]),
    chordOf(
      3,
      'D5',
      graces: [graceOf(4, 'C5', value: sixteenth), graceOf(5, 'B4')],
    ),
    chordOf(
      6,
      'E5',
      value: half,
      graces: [graceOf(7, 'D5', kind: GraceKind.appoggiatura)],
    ),
  ]),
  'drums': barOf(
    [
      hitOf(1, [snare]),
      hitOf(2, [bassDrum], value: eighth),
      hitOf(3, [sideStick], value: eighth),
      hitOf(4, [snare, bassDrum]),
      restOf(5, NoteValue.quarter),
    ],
    clef: Clef.percussion,
    lines: 1,
    instrument: drumKit,
  ),
  'rests': barOf([
    restOf(1, dottedQuarter),
    restOf(2, eighth),
    chordOf(3, 'C5', value: eighth),
    restOf(4, eighth),
    restOf(5, NoteValue.quarter),
  ]),
  'dots': barOf([
    chordOf(1, 'G4', value: dottedEighth),
    restOf(2, sixteenth),
    chordOf(3, 'F4', value: dottedEighth),
    restOf(4, sixteenth),
    chordOf(5, 'A4 C5', value: dottedQuarter),
    restOf(6, eighth),
  ]),
  'tremolo': barOf([chordOf(1, 'C5', value: whole, tremolo: 3)]),
};

/// A bar drawn alone: its drawables in sheet space and the image size.
({List<Drawable> drawables, int width, int height}) sheetOf(BarLayout layout) {
  final xs = sliceXs(layout.slices, 1, margin + layout.lead);
  final right = xs.last + layout.slices.last.rod;
  final tops = <double>[];
  var top = margin;
  for (final staff in layout.staves) {
    top += staff.above;
    tops.add(top);
    top += staffHeight + staff.below + margin;
  }
  final frame = BarFrame(left: margin, xs: xs, tops: tops);
  final defaults = style.font.defaults;
  return (
    drawables: [
      for (final (i, staff) in layout.staves.indexed) ...[
        ...staffLines(
          lines: staff.lines,
          top: tops[i],
          left: margin,
          right: right,
          thickness: defaults.staffLineThickness,
        ),
        LineDraw(
          SpPoint(right - defaults.thinBarlineThickness / 2, tops[i]),
          SpPoint(
              right - defaults.thinBarlineThickness / 2, tops[i] + staffHeight),
          thickness: defaults.thinBarlineThickness,
        ),
      ],
      for (final item in layout.items) frame.place(item),
      for (final beam in layout.beams) ...placeBeam(beam, frame, style),
    ],
    width: ((right + margin) * spacePx).ceil(),
    height: (top * spacePx).ceil(),
  );
}

void main() {
  testWidgets('every drawable of a laid-out bar leaves ink where it says', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      const scale = SheetScale(spacePx: spacePx);

      for (final MapEntry(key: name, value: view) in bars.entries) {
        final layout = layoutBar(view, style, const FakeMeasurer());
        final sheet = sheetOf(layout);

        expect(layout.items, isNotEmpty, reason: name);
        for (final drawable in sheet.drawables) {
          final alone = await render(
            sheet.width,
            sheet.height,
            (canvas) => paintDrawables(canvas, painter, [drawable], scale),
            background: null,
          );
          final ink = inkIn(
            alone.rgba,
            sheet.width,
            left: 0,
            top: 0,
            right: sheet.width,
            bottom: sheet.height,
          );
          final rect = scale.rectOf(drawable.bounds);
          final reason = '$name: $drawable';
          expect(ink, isNotNull, reason: reason);
          expect(ink!.left, greaterThanOrEqualTo(rect.left - 1),
              reason: reason);
          expect(ink.top, greaterThanOrEqualTo(rect.top - 1), reason: reason);
          expect(ink.right, lessThanOrEqualTo(rect.right + 1), reason: reason);
          expect(ink.bottom, lessThanOrEqualTo(rect.bottom + 1),
              reason: reason);
        }
        final image = await render(
          sheet.width,
          sheet.height,
          (canvas) => paintDrawables(canvas, painter, sheet.drawables, scale),
        );
        writeSnapshot('bar_$name', image.png);
      }
    });
  });

  testWidgets('out-of-range ink is drawn in its own colour', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      const alto = Instrument(
        key: 'alto',
        program: 0,
        lowest: Pitch(Step.c, 4),
        highest: Pitch(Step.c, 5),
      );
      final layout = layoutBar(
        barOf([chordOf(1, 'C5 A5', value: whole)], instrument: alto),
        style,
        const FakeMeasurer(),
      );
      final sheet = sheetOf(layout);
      const scale = SheetScale(spacePx: spacePx);
      final image = await render(
        sheet.width,
        sheet.height,
        (canvas) => paintDrawables(canvas, painter, sheet.drawables, scale),
      );
      writeSnapshot('bar_range', image.png);

      final heads = sheet.drawables.whereType<GlyphDraw>().where(
            (g) => g.glyph == Glyph.noteheadWhole,
          );
      expect(
        heads.map((h) => h.ink),
        unorderedEquals([InkRole.normal, InkRole.outOfRange]),
      );
      for (final head in heads) {
        expect(
          _hasReddish(image.rgba, sheet.width, scale.rectOf(head.bounds)),
          head.ink == InkRole.outOfRange,
          reason: '${head.glyph.name} at step ${head.origin.y}',
        );
      }
    });
  });
}

/// Whether any pixel inside [rect] is red rather than black, white or grey.
bool _hasReddish(Uint8List rgba, int width, ui.Rect rect) {
  for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
    for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
      final i = (y * width + x) * 4;
      if (rgba[i] > rgba[i + 1] + 60) {
        return true;
      }
    }
  }
  return false;
}
