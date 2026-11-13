import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:khuur_sheet_music/src/painting.dart';
import 'package:khuur_sheet_music/src/paragraph_measurer.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';

import '../packages/score_layout/test/support/bars.dart';
import 'support/draw.dart';
import 'support/glyph_gate.dart';

const double spacePx = 24;
const double margin = 1;

/// Wide enough that one system holds two of the bars below and that a
/// system of one of them stays ragged.
const double sheetWidth = 100;

const NoteValue dottedQuarter = NoteValue(DurationBase.quarter, dots: 1);
const NoteValue dottedEighth = NoteValue(DurationBase.eighth, dots: 1);

/// A one-bar, one-staff score.
Score oneBar(
  List<VoiceItem> one, {
  List<VoiceItem> two = const [],
  Clef clef = Clef.treble,
  int lines = 5,
  Instrument instrument = piano,
}) => scoreOf([
  [staffOf(one, two: two, clef: clef, lines: lines, instrument: instrument)],
]);

/// One bar per concern the engine lays out, each a one-bar score that
/// fits one ragged system at stretch 1.
final Map<String, Score> bars = {
  'scale': oneBar([
    chordOf(1, 'C4', value: eighth),
    chordOf(2, 'D4', value: eighth),
    chordOf(3, 'E4', value: eighth),
    chordOf(4, 'F#4', value: eighth),
    chordOf(5, 'G4', value: eighth),
    chordOf(6, 'A4', value: eighth),
    chordOf(7, 'Bb4', value: eighth),
    chordOf(8, 'C5', value: eighth),
  ]),
  'chords': oneBar([
    chordOf(1, 'C#4 D#4 F#4', value: half),
    chordOf(2, 'Eb5 F5 Ab5', value: dottedQuarter),
    chordOf(3, 'G3 B3 D4', value: eighth, tremolo: 2),
  ]),
  'beams': oneBar([
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
  'voices': oneBar(
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
  'graces': oneBar([
    chordOf(1, 'C5', graces: [graceOf(2, 'B4')]),
    chordOf(
      3,
      'D5',
      graces: [
        graceOf(4, 'C5', value: sixteenth),
        graceOf(5, 'B4'),
      ],
    ),
    chordOf(
      6,
      'E5',
      value: half,
      graces: [graceOf(7, 'D5', kind: GraceKind.appoggiatura)],
    ),
  ]),
  'clusters': oneBar([
    chordOf(1, 'Cb4 C4 C#4', value: half),
    chordOf(2, 'C5 C#5 D5'),
    chordOf(3, 'Cb5 C5 C#5'),
  ]),
  'drums': oneBar(
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
  'rests': oneBar([
    restOf(1, dottedQuarter),
    restOf(2, eighth),
    chordOf(3, 'C5', value: eighth),
    restOf(4, eighth),
    restOf(5, NoteValue.quarter),
  ]),
  'dots': oneBar([
    chordOf(1, 'G4', value: dottedEighth),
    restOf(2, sixteenth),
    chordOf(3, 'F4', value: dottedEighth),
    restOf(4, sixteenth),
    chordOf(5, 'A4 C5', value: dottedQuarter),
    restOf(6, eighth),
  ]),
  'tremolo': oneBar([chordOf(1, 'C5', value: whole, tremolo: 3)]),
  'clef_change': after(
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
};

/// A two-bar score whose second bar changes what the first bar had to
/// [key], [meter] or [clef], so that all three of its heads print.
Score changedScore({
  Clef from = Clef.treble,
  Clef? clef,
  String pitch = 'B4',
  KeySignature fromKey = KeySignature.cMajor,
  KeySignature? key,
  Meter fromMeter = Meter.fourFour,
  Meter? meter,
  bool repeat = false,
}) => after(
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
);

const KeySignature fourSharps = KeySignature(4);
const KeySignature fourFlats = KeySignature(-4);

/// One two-bar score per signature concern. The change in its second bar
/// is drawn three times, as an inline head, as a courtesy head and as a
/// system head.
final Map<String, Score> headBars = {
  'treble_sharps': changedScore(key: fourSharps),
  'treble_flats': changedScore(key: fourFlats),
  'bass_sharps': changedScore(from: Clef.bass, pitch: 'D3', key: fourSharps),
  'bass_flats': changedScore(from: Clef.bass, pitch: 'D3', key: fourFlats),
  'alto_sharps': changedScore(from: Clef.alto, pitch: 'C4', key: fourSharps),
  'alto_flats': changedScore(from: Clef.alto, pitch: 'C4', key: fourFlats),
  'tenor_sharps': changedScore(
    from: Clef.tenor,
    pitch: 'A3',
    key: const KeySignature(7),
  ),
  'naturals_then_flats': changedScore(
    fromKey: fourSharps,
    key: const KeySignature(-2),
  ),
  'naturals_then_fewer_sharps': changedScore(
    fromKey: fourSharps,
    key: const KeySignature(1),
  ),
  'naturals_alone': changedScore(fromKey: fourFlats, key: KeySignature.cMajor),
  'meter_four_four': changedScore(
    fromMeter: Meter.threeFour,
    meter: Meter.fourFour,
  ),
  'meter_six_eight': changedScore(meter: Meter.sixEight),
  'meter_twelve_eight': changedScore(meter: Meter.simple(12, 8)),
  'meter_common': changedScore(fromMeter: Meter.threeFour, meter: Meter.common),
  'meter_cut': changedScore(meter: Meter.cut),
  'clef_key_meter_repeat': changedScore(
    clef: Clef.bass,
    pitch: 'D4',
    key: const KeySignature(-3),
    meter: Meter.threeFour,
    repeat: true,
  ),
};

/// [score] laid out by the engine at [sheetWidth], with text measured as
/// the painter draws it.
SheetLayout layoutOf(Score score) => SheetLayout(
  score,
  width: sheetWidth,
  text: ParagraphMeasurer(),
  style: pictureStyle,
);

/// What a system prints in its heads rather than in its bars.
const Set<InkRole> headInk = {
  InkRole.clef,
  InkRole.keySignature,
  InkRole.timeSignature,
};

/// The head drawables of [system] that stand right of where its first bar's
/// content ends with [right] true, and left of it otherwise. On a system of
/// two bars the right ones are the second bar's inline head, and on a system
/// that ends with a courtesy they are that courtesy.
List<Drawable> headOf(SystemLayout system, {required bool right}) => [
  for (final drawable in system.drawables)
    if (headInk.contains(drawable.ink) &&
        (drawable.bounds.left + drawable.bounds.right) / 2 >
                system.bars.first.right ==
            right)
      drawable,
];

/// [systems] drawn one under another, with the scale that places each and
/// the size of the image that holds them.
///
/// The painter puts glyph ink on whole pixels vertically, so each system is
/// placed with its first staff on a whole pixel, which keeps every glyph
/// where its box says.
({List<SheetScale> scales, int width, int height}) stackOf(
  List<SystemLayout> systems,
) {
  final scales = <SheetScale>[];
  var right = 0.0;
  var top = margin;
  for (final system in systems) {
    final staffTop = system.staves.first.top * spacePx;
    final y = (top * spacePx + staffTop).ceilToDouble() - staffTop;
    scales.add(
      SheetScale(spacePx: spacePx, origin: ui.Offset(margin * spacePx, y)),
    );
    for (final drawable in system.drawables) {
      right = math.max(right, drawable.bounds.right);
    }
    top = y / spacePx + system.height + margin;
  }
  return (
    scales: scales,
    width: ((right + 2 * margin) * spacePx).ceil(),
    height: (top * spacePx).ceil(),
  );
}

/// Checks that [drawable], painted alone at [scale] on an image [width] by
/// [height] pixels, leaves ink and leaves it inside its bounds.
Future<void> expectInkInBounds(
  GlyphPainter painter,
  Drawable drawable,
  SheetScale scale, {
  required int width,
  required int height,
  required String reason,
}) async {
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
  expect(ink, isNotNull, reason: reason);
  expect(ink!.left, greaterThanOrEqualTo(rect.left - 1), reason: reason);
  expect(ink.top, greaterThanOrEqualTo(rect.top - 1), reason: reason);
  expect(ink.right, lessThanOrEqualTo(rect.right + 1), reason: reason);
  expect(ink.bottom, lessThanOrEqualTo(rect.bottom + 1), reason: reason);
}

void main() {
  testWidgets('every drawable of a laid-out bar leaves ink where it says', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();

      for (final MapEntry(key: name, value: score) in bars.entries) {
        final layout = layoutOf(score);
        expect(layout.systemCount, 1, reason: name);
        final system = layout.systemAt(0);
        final stack = stackOf([system]);
        final scale = stack.scales.single;

        expect(system.drawables, isNotEmpty, reason: name);
        for (final drawable in system.drawables) {
          await expectInkInBounds(
            painter,
            drawable,
            scale,
            width: stack.width,
            height: stack.height,
            reason: '$name: $drawable',
          );
        }
        final image = await render(
          stack.width,
          stack.height,
          (canvas) => paintDrawables(canvas, painter, system.drawables, scale),
        );
        writeSnapshot('bar_$name', image.png);
      }
    });
  });

  testWidgets('each head of a bar leaves ink where it says, in front of the '
      'notes', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();

      for (final MapEntry(key: name, value: score) in headBars.entries) {
        final joined = layoutOf(score);
        final broken = layoutOf(
          after(score, [SetBreak(barId(1), LayoutBreak.system)]),
        );
        expect(joined.systemCount, 1, reason: name);
        expect(broken.systemCount, 2, reason: name);
        final systems = [
          joined.systemAt(0),
          broken.systemAt(0),
          broken.systemAt(1),
        ];
        final stack = stackOf(systems);
        final heads = [
          (kind: 'inline', of: headOf(systems[0], right: true)),
          (kind: 'courtesy', of: headOf(systems[1], right: true)),
          (kind: 'system', of: headOf(systems[2], right: false)),
        ];

        for (final (index, (:kind, of: head)) in heads.indexed) {
          expect(head, isNotEmpty, reason: '$name, $kind head');
          for (final drawable in head) {
            await expectInkInBounds(
              painter,
              drawable,
              stack.scales[index],
              width: stack.width,
              height: stack.height,
              reason: '$name, $kind head: $drawable',
            );
          }
        }
        final image = await render(stack.width, stack.height, (canvas) {
          for (final (index, system) in systems.indexed) {
            paintDrawables(
              canvas,
              painter,
              system.drawables,
              stack.scales[index],
            );
          }
        });
        writeSnapshot('heads_$name', image.png);
      }
    });
  });
}
