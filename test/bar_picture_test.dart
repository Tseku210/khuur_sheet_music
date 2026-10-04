import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/bar_space.dart';
import 'package:score_layout/src/beams.dart';
import 'package:score_layout/src/signatures.dart';
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
  'clusters': barOf([
    chordOf(1, 'Cb4 C4 C#4', value: half),
    chordOf(2, 'C5 C#5 D5'),
    chordOf(3, 'Cb5 C5 C#5'),
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
  'clef_change': viewOf(
    after(
      scoreOf([
        [
          staffOf([
            chordOf(1, 'G4', value: half),
            chordOf(2, 'F#4'),
            chordOf(3, 'A4'),
          ]),
        ],
      ]),
      [
        SetClef(
          staff: staffId(0),
          at: ScorePoint(barId(0), at(1, 2)),
          clef: Clef.alto,
        ),
        SetClef(
          staff: staffId(0),
          at: ScorePoint(barId(0), at(3, 4)),
          clef: Clef.bass,
        ),
      ],
    ),
  ),
};

/// The second bar of a two-bar score, which changes what the first bar had
/// to [key], [meter] or [clef], so that all three of its heads print.
MeasureView changedBar({
  Clef from = Clef.treble,
  Clef? clef,
  String pitch = 'B4',
  KeySignature fromKey = KeySignature.cMajor,
  KeySignature? key,
  Meter fromMeter = Meter.fourFour,
  Meter? meter,
  bool repeat = false,
}) =>
    viewOf(
      after(
        beatsScore(
          2,
          clefs: [from],
          key: fromKey,
          meter: fromMeter,
          pitch: pitch,
        ),
        [
          if (key != null) SetKey(from: barId(1), key: key),
          if (meter != null) SetMeter(from: barId(1), meter: meter),
          if (clef != null)
            SetClef(
              staff: staffId(0),
              at: ScorePoint(barId(1), Moment.zero),
              clef: clef,
            ),
          if (repeat) SetRepeatStart(barId(1), start: true),
        ],
      ),
      1,
    );

const KeySignature fourSharps = KeySignature(4);
const KeySignature fourFlats = KeySignature(-4);

/// One bar per signature concern. Each is drawn three times, behind its
/// system head, its inline head and its courtesy head.
final Map<String, MeasureView> headBars = {
  'treble_sharps': changedBar(key: fourSharps),
  'treble_flats': changedBar(key: fourFlats),
  'bass_sharps': changedBar(from: Clef.bass, pitch: 'D3', key: fourSharps),
  'bass_flats': changedBar(from: Clef.bass, pitch: 'D3', key: fourFlats),
  'alto_sharps': changedBar(from: Clef.alto, pitch: 'C4', key: fourSharps),
  'alto_flats': changedBar(from: Clef.alto, pitch: 'C4', key: fourFlats),
  'tenor_sharps': changedBar(
    from: Clef.tenor,
    pitch: 'A3',
    key: const KeySignature(7),
  ),
  'naturals_then_flats': changedBar(
    fromKey: fourSharps,
    key: const KeySignature(-2),
  ),
  'naturals_then_fewer_sharps': changedBar(
    fromKey: fourSharps,
    key: const KeySignature(1),
  ),
  'naturals_alone': changedBar(fromKey: fourFlats, key: KeySignature.cMajor),
  'meter_four_four': changedBar(
    fromMeter: Meter.threeFour,
    meter: Meter.fourFour,
  ),
  'meter_six_eight': changedBar(meter: Meter.sixEight),
  'meter_twelve_eight': changedBar(meter: Meter.simple(12, 8)),
  'meter_common': changedBar(fromMeter: Meter.threeFour, meter: Meter.common),
  'meter_cut': changedBar(meter: Meter.cut),
  'clef_key_meter_repeat': changedBar(
    clef: Clef.bass,
    pitch: 'D4',
    key: const KeySignature(-3),
    meter: Meter.threeFour,
    repeat: true,
  ),
};

/// A bar drawn alone: its drawables in sheet space and the image size.
///
/// With a [head], the head starts at the left margin and the notes follow
/// it, as they do on a system. A [barline] between the two parts of the head
/// shows the gap each part keeps from it. [from] is the y the picture starts
/// at, so that several bars can share one image.
({
  List<Drawable> drawables,
  List<Drawable> head,
  int width,
  int height,
  double bottom,
}) sheetOf(
  BarLayout layout, {
  SplitHead head = SplitHead.none,
  bool barline = false,
  double from = margin,
}) {
  final after = margin + head.before.width;
  final xs = sliceXs(layout.slices, 1, margin + head.width + layout.lead);
  final right = xs.last + layout.slices.last.rod;
  final tops = <double>[];
  var top = from;
  for (final (i, staff) in layout.staves.indexed) {
    final reach = headReach([head.before, head.after], i);
    // The engine puts glyph ink on whole pixels vertically, so a staff on a
    // whole pixel keeps every glyph where its box says.
    top =
        ((top + math.max(staff.above, reach.above)) * spacePx).ceilToDouble() /
            spacePx;
    tops.add(top);
    top += staffHeight + math.max(staff.below, reach.below) + margin;
  }
  final placedHead = [
    for (final item in head.before.items)
      item.drawable.shift(margin, tops[item.staff]),
    for (final item in head.after.items)
      item.drawable.shift(after, tops[item.staff]),
  ];
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
        for (final x in [
          if (barline) after + defaults.thinBarlineThickness / 2,
          right - defaults.thinBarlineThickness / 2,
        ])
          LineDraw(
            SpPoint(x, tops[i]),
            SpPoint(x, tops[i] + staffHeight),
            thickness: defaults.thinBarlineThickness,
          ),
      ],
      ...placedHead,
      for (final item in layout.items) frame.place(item),
      for (final beam in layout.beams) ...placeBeam(beam, frame, style),
    ],
    head: placedHead,
    width: ((right + margin) * spacePx).ceil(),
    height: (top * spacePx).ceil(),
    bottom: top,
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

  testWidgets(
      'each head of a bar leaves ink where it says, in front of the '
      'notes', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      const scale = SheetScale(spacePx: spacePx);

      for (final MapEntry(key: name, value: view) in headBars.entries) {
        final layout = layoutBar(view, style, const FakeMeasurer());
        final heads = [
          SplitHead(before: BarHead.none, after: layout.heads.system),
          layout.heads.inline,
          layout.heads.courtesy,
        ];
        final rows = [sheetOf(layout, head: heads.first)];
        for (final head in heads.skip(1)) {
          rows.add(
            sheetOf(layout, head: head, barline: true, from: rows.last.bottom),
          );
        }
        final width = rows.map((row) => row.width).reduce(math.max);
        final height = rows.last.height;

        for (final (index, row) in rows.indexed) {
          expect(row.head, isNotEmpty, reason: '$name, head $index');
          for (final drawable in row.head) {
            final alone = await render(
              width,
              height,
              (canvas) => paintDrawables(canvas, painter, [drawable], scale),
              background: null,
            );
            final ink = inkIn(
              alone.rgba,
              width,
              left: 0,
              top: 0,
              right: width,
              bottom: height,
            );
            final rect = scale.rectOf(drawable.bounds);
            final reason = '$name, head $index: $drawable';
            expect(ink, isNotNull, reason: reason);
            expect(ink!.left, greaterThanOrEqualTo(rect.left - 1),
                reason: reason);
            expect(ink.top, greaterThanOrEqualTo(rect.top - 1), reason: reason);
            expect(ink.right, lessThanOrEqualTo(rect.right + 1),
                reason: reason);
            expect(ink.bottom, lessThanOrEqualTo(rect.bottom + 1),
                reason: reason);
          }
        }
        final image = await render(
          width,
          height,
          (canvas) => paintDrawables(
            canvas,
            painter,
            [for (final row in rows) ...row.drawables],
            scale,
          ),
        );
        writeSnapshot('heads_$name', image.png);
      }
    });
  });
}
