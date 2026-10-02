import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:simple_sheet_music/src/painting.dart';

import '../packages/score_model/test/support.dart';
import 'support/draw.dart';
import 'support/glyph_gate.dart';

const double spacePx = 20;
const double margin = 2;
const double sheetWidth = 110;

const NoteValue dottedHalf = NoteValue(DurationBase.half, dots: 1);
const NoteValue eighth = NoteValue.eighth;
const NoteValue half = NoteValue.half;
const NoteValue whole = NoteValue.whole;

const violin = PartTemplate(
  name: 'Violin',
  shortName: 'Vln.',
  instrument: Instrument(key: 'violin', program: 40),
);

const grand = PartTemplate(
  name: 'Piano',
  shortName: 'Pno.',
  instrument: Instrument(key: 'piano', program: 0),
  staves: 2,
  clefs: [Clef.treble, Clef.bass],
);

Score edit(Score score, Edit edit) =>
    applied(EditSession.start(score).run(edit)).score;

List<Drawable> inkOf(SheetLayout layout, int system) {
  final label = layout.labelOf(system);
  return [...layout.systemAt(system).drawables, if (label != null) label];
}

Score ensemble() {
  var score = blankScore(parts: const [violin, grand], bars: 16).copyWith(
    meta: const ScoreMeta(
      title: 'Sheet Picture',
      subtitle: 'Sixteen bars for violin and piano',
      composer: 'The Layout Engine',
      lyricist: 'Nobody',
    ),
  );
  final ids = barIds(score);
  score = edit(score, SetBarLength(ids[0], len(1, 4)));
  score = edit(score, SetRepeatStart(ids[4], start: true));
  score = edit(score, SetRepeatEnd(ids[7], const RepeatEnd()));
  score = edit(score, SetKey(from: ids[8], key: const KeySignature(2)));
  score = edit(score, SetMeter(from: ids[12], meter: Meter.threeFour));
  score = edit(score, SetBarline(ids[15], Barline.finalBar));

  var id = 10000;
  ChordEvent chord(String pitches, [NoteValue value = NoteValue.quarter]) =>
      chordOf(id++, pitches, value: value);
  RestEvent silence(NoteValue value) => rest(id++, value);

  score = fill(score, 0, [chord('G4')]);
  for (final bar in [1, 2, 3]) {
    score = fill(score, bar, [
      for (final pitch in const [
        'G4',
        'A4',
        'B4',
        'C5',
        'D5',
        'C5',
        'B4',
        'A4'
      ])
        chord(pitch, eighth),
    ]);
    score = fill(
        score,
        bar,
        [
          chord('C4 E4 G4', half),
          chord('D4 F4 A4', half),
        ],
        staff: 1);
    score = fill(
        score,
        bar,
        [
          chord('C3'),
          chord('G2'),
          chord('E3'),
          chord('G2'),
        ],
        staff: 2);
  }
  for (final bar in [4, 5, 6, 7]) {
    score = fill(score, bar, [
      chord('D5'),
      silence(NoteValue.quarter),
      chord('E5', eighth),
      chord('F5', eighth),
      chord('G5'),
    ]);
    score = fill(
        score,
        bar,
        [
          silence(half),
          chord('E4 G4 B4', half),
        ],
        staff: 1);
    score = fill(score, bar, [chord('C3', whole)], staff: 2);
  }
  for (final bar in [8, 9, 10, 11]) {
    score = fill(score, bar, [
      chord('A4'),
      chord('D5', eighth),
      chord('F#5', eighth),
      chord('A5'),
      chord('F#5'),
    ]);
    score = fill(score, bar, [chord('D4 F#4 A4', whole)], staff: 1);
    score = fill(
        score,
        bar,
        [
          chord('D3'),
          chord('A2'),
          chord('D3', half),
        ],
        staff: 2);
  }
  for (final bar in [12, 13, 14]) {
    score = fill(score, bar, [chord('D5'), chord('C#5'), chord('D5')]);
    score = fill(
        score,
        bar,
        [
          chord('G4 B4'),
          silence(NoteValue.quarter),
          chord('A4 C#5'),
        ],
        staff: 1);
    score = fill(
        score,
        bar,
        [
          silence(NoteValue.quarter),
          chord('G2'),
          chord('A2'),
        ],
        staff: 2);
  }
  score = fill(score, 15, [chord('D5', dottedHalf)]);
  score = fill(score, 15, [chord('D4 F#4 A4', dottedHalf)], staff: 1);
  score = fill(score, 15, [chord('D3', dottedHalf)], staff: 2);
  return score;
}

void main() {
  testWidgets(
      'a sheet of systems paints each system inside its band, under '
      'its header', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();
      final layout = SheetLayout(
        ensemble(),
        width: sheetWidth,
        text: const UiMeasurer(),
      );
      final width = ((sheetWidth + 2 * margin) * spacePx).ceil();
      final height = ((layout.height + 2 * margin) * spacePx).ceil();
      // A system on a whole pixel keeps its glyphs where their boxes say.
      SheetScale scaleOf(double top) => SheetScale(
            spacePx: spacePx,
            origin: ui.Offset(
              margin * spacePx,
              ((margin + top) * spacePx).ceilToDouble(),
            ),
          );
      final header = scaleOf(0);

      expect(layout.systemCount, inInclusiveRange(3, 4));
      expect(layout.header, isNotEmpty);

      for (var i = 0; i < layout.systemCount; i++) {
        final system = layout.systemAt(i);
        final scale = scaleOf(layout.tops[i]);
        final drawables = inkOf(layout, i);
        final alone = await render(
          width,
          height,
          (canvas) => paintDrawables(canvas, painter, drawables, scale),
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
        final band = scale.rectOf(Box(0, 0, system.width, system.height));
        final reason = 'system $i';

        expect(system.width, sheetWidth, reason: reason);
        expect(ink, isNotNull, reason: reason);
        expect(ink!.left, greaterThanOrEqualTo(band.left - 1), reason: reason);
        expect(ink.top, greaterThanOrEqualTo(band.top - 1), reason: reason);
        expect(ink.right, lessThanOrEqualTo(band.right + 1), reason: reason);
        expect(ink.bottom, lessThanOrEqualTo(band.bottom + 1), reason: reason);
      }

      final headerAlone = await render(
        width,
        height,
        (canvas) => paintDrawables(canvas, painter, layout.header, header),
        background: null,
      );
      final headerInk = inkIn(
        headerAlone.rgba,
        width,
        left: 0,
        top: 0,
        right: width,
        bottom: height,
      );
      expect(headerInk, isNotNull);
      expect(headerInk!.top, greaterThanOrEqualTo(header.origin.dy - 1));
      expect(
        headerInk.bottom,
        lessThanOrEqualTo(scaleOf(layout.tops.first).origin.dy),
      );

      final image = await render(width, height, (canvas) {
        paintDrawables(canvas, painter, layout.header, header);
        for (var i = 0; i < layout.systemCount; i++) {
          paintDrawables(
            canvas,
            painter,
            inkOf(layout, i),
            scaleOf(layout.tops[i]),
          );
        }
      });
      writeSnapshot('sheet_ensemble', image.png);
    });
  });
}
