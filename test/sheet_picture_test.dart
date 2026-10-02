import 'dart:typed_data';
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

SheetLayout layoutOf(Score score) =>
    SheetLayout(score, width: sheetWidth, text: const UiMeasurer());

List<Drawable> inkOf(SheetLayout layout, int system) {
  final label = layout.labelOf(system);
  return [...layout.systemAt(system).drawables, if (label != null) label];
}

Ink? inkOfImage(Uint8List rgba, int width) => inkIn(
      rgba,
      width,
      left: 0,
      top: 0,
      right: width,
      bottom: rgba.length ~/ (4 * width),
    );

/// The ink in each pixel column of an RGBA image [width] pixels wide, in
/// pixels fully covered.
List<double> columnInk(Uint8List rgba, int width) => [
      for (var x = 0; x < width; x++)
        [for (var at = x * 4 + 3; at < rgba.length; at += width * 4) rgba[at]]
                .fold(0, (sum, alpha) => sum + alpha) /
            255,
    ];

void expectInside(Ink? ink, ui.Rect rect, String reason) {
  expect(ink, isNotNull, reason: reason);
  expect(ink!.left, greaterThanOrEqualTo(rect.left - 1), reason: reason);
  expect(ink.top, greaterThanOrEqualTo(rect.top - 1), reason: reason);
  expect(ink.right, lessThanOrEqualTo(rect.right + 1), reason: reason);
  expect(ink.bottom, lessThanOrEqualTo(rect.bottom + 1), reason: reason);
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

  score = edit(score, SetVolta(ids[7], ids[7], const Volta([1])));
  score = edit(score, SetVolta(ids[8], ids[8], const Volta([2])));
  score = tiedInto(score, 13, staff: 0);
  ScorePoint point(int bar, [Moment offset = Moment.zero]) =>
      pointAt(score, bar, offset);
  score = withSlur(score, point(1), point(1, at(7, 8)));
  score = withSpanner(
    score,
    const Slur(dashed: true),
    point(3),
    point(3, at(7, 8)),
  );
  score = withSpanner(
    score,
    const PedalLine(),
    point(8),
    point(9, at(2, 4)),
    staff: 2,
  );
  score = withSpanner(
    score,
    const Hairpin(crescendo: true),
    point(10),
    point(11, at(3, 4)),
  );
  score = withSpanner(
    score,
    const Hairpin(crescendo: false),
    point(12),
    point(13, at(2, 4)),
  );
  return withSpanner(score, const TrillLine(), point(14), point(15));
}

/// [score] with the last chord of [staff] in the bar before [bar] tied to the
/// first chord of [bar], and retuned to it where the two differ.
Score tiedInto(Score score, int bar, {required int staff}) {
  List<VoiceItem> itemsOf(int bar) =>
      [...score.measures[bar].staves[staff].voice(VoiceSlot.one)!.items];
  final before = itemsOf(bar - 1);
  final from = before.removeLast() as ChordEvent;
  final to = itemsOf(bar).first as ChordEvent;
  return fill(
    score,
    bar - 1,
    [
      ...before,
      chordOf(
        from.id.value,
        [for (final note in to.notes) '${(note as PitchedNote).pitch}']
            .join(' '),
        value: from.value,
        tie: true,
      ),
    ],
    staff: staff,
  );
}

Score overBarline(Score score, int bar) => withSpanner(
      withSlur(
        tiedInto(score, bar, staff: 2),
        pointAt(score, bar - 1, at(2, 4)),
        pointAt(score, bar, Moment.zero),
      ),
      const OctaveLine(OctaveShift.up8),
      pointAt(score, bar - 1, Moment.zero),
      pointAt(score, bar + 1, Moment.zero),
    );

int secondSystemStart(Score score) {
  final layout = layoutOf(score);
  return barIds(score).indexWhere((id) => layout.systemOf(id) == 1);
}

int tiedBar(Score score, int staff) => score.measures.toList().indexWhere(
      (measure) =>
          switch (measure.staves[staff].voice(VoiceSlot.one)!.items.last) {
        ChordEvent(:final notes) => notes.any((note) => note.tie),
        _ => false,
      },
    );

/// [ensemble] with [overBarline] at its first system break. What that adds
/// can move the break, so it is added again where the break went, three
/// times at most.
Score pictured() {
  final base = ensemble();
  var bar = secondSystemStart(base);
  var score = overBarline(base, bar);
  for (var round = 1; round < 3 && secondSystemStart(score) != bar; round++) {
    bar = secondSystemStart(score);
    score = overBarline(base, bar);
  }
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
      final layout = layoutOf(pictured());
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
        expect(system.width, sheetWidth, reason: 'system $i');
        expectInside(
          inkOfImage(alone.rgba, width),
          scale.rectOf(Box(0, 0, system.width, system.height)),
          'system $i',
        );
      }

      final headerAlone = await render(
        width,
        height,
        (canvas) => paintDrawables(canvas, painter, layout.header, header),
        background: null,
      );
      final headerInk = inkOfImage(headerAlone.rgba, width);
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

  testWidgets(
      'every tie, slur, line and ending of the score is drawn on the '
      'systems its bars are on', (tester) async {
    await tester.runAsync(() async {
      await loadTextFont();
      final score = pictured();
      final ids = barIds(score);
      final layout = layoutOf(score);
      final first = layout.systemAt(0);
      final second = layout.systemAt(1);
      SystemLayout systemOf(MeasureId bar) =>
          layout.systemAt(layout.systemOf(bar)!);
      Iterable<T> drawn<T extends Drawable>(SystemLayout system, Spanner of) =>
          system.drawables
              .whereType<T>()
              .where((drawable) => drawable.owner == SpannerOwner(of.id));
      Iterable<CurveDraw> tiesOf(SystemLayout system) => system.drawables
          .whereType<CurveDraw>()
          .where((curve) => curve.owner is ElementOwner);
      Spanner only<K extends SpannerKind>() =>
          score.spanners.singleWhere((spanner) => spanner.kind is K);

      final slurs = score.spanners.where((spanner) => spanner.kind is Slur);
      final cut = slurs.singleWhere(
        (slur) => slur.first.measure != slur.last.measure,
      );
      final octave = only<OctaveLine>();
      final cutTie = tiedBar(score, 2);
      for (final (what, from) in [
        ('the tie', ids[cutTie]),
        ('the slur', cut.first.measure),
        ('the octave line', octave.first.measure),
      ]) {
        expect(
          first.bars.last.measure,
          from,
          reason: '$what starts in the last bar of the first system',
        );
      }
      for (final (what, to) in [
        ('the tie', ids[cutTie + 1]),
        ('the slur', cut.last.measure),
      ]) {
        expect(
          second.bars.first.measure,
          to,
          reason: '$what ends in the first bar of the second system',
        );
      }
      expect(
        layout.systemOf(octave.last.measure),
        greaterThan(0),
        reason: 'the octave line runs on after the first system',
      );
      expect(
        drawn<GlyphDraw>(second, octave).map((glyph) => glyph.glyph),
        contains(Glyph.octaveParensLeft),
        reason: 'the octave line restates its sign on the second system',
      );
      for (final system in [first, second]) {
        expect(
          tiesOf(system),
          hasLength(1),
          reason: 'each system draws its half of the cut tie',
        );
      }

      for (final slur in slurs) {
        final from = layout.systemOf(slur.first.measure)!;
        final to = layout.systemOf(slur.last.measure)!;
        for (var i = from; i <= to; i++) {
          expect(
            drawn<CurveDraw>(layout.systemAt(i), slur).map((c) => c.dashed),
            [(slur.kind as Slur).dashed],
            reason: 'system $i draws one piece of slur ${slur.id}',
          );
        }
      }

      final tied = ids[tiedBar(score, 0)];
      final barline = systemOf(tied).barOf(tied)!.right;
      expect(
        tiesOf(systemOf(tied)).where(
          (tie) => tie.start.x < barline && tie.end.x > barline,
        ),
        hasLength(1),
        reason: 'a tie inside a system is one curve over its barline',
      );

      for (final hairpin in score.spanners.where((s) => s.kind is Hairpin)) {
        expect(
          drawn<LineDraw>(systemOf(hairpin.first.measure), hairpin),
          hasLength(2),
          reason: 'hairpin ${hairpin.id} is two lines',
        );
      }
      final pedal = only<PedalLine>();
      expect(
        drawn<GlyphDraw>(systemOf(pedal.first.measure), pedal)
            .map((glyph) => glyph.glyph),
        [Glyph.keyboardPedalPed],
        reason: 'the pedal line starts with its sign',
      );
      final trill = only<TrillLine>();
      expect(
        drawn<GlyphRunDraw>(systemOf(trill.first.measure), trill),
        hasLength(1),
        reason: 'the trill line is a run of wiggles',
      );

      final endings = systemOf(
        score.measures.firstWhere((measure) => measure.volta != null).id,
      ).drawables.whereType<TextDraw>().map((label) => label.text);
      expect(
        endings.where(const ['1.', '2.'].contains),
        ['1.', '2.'],
        reason: 'both endings are labelled, on one system',
      );
    });
  });

  testWidgets(
      'a curve, a glyph run and a dashed line leave the ink their drawables '
      'describe', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();
      final layout = layoutOf(pictured());
      const pad = 4;
      final kinds = <String>{};

      for (var i = 0; i < layout.systemCount; i++) {
        for (final drawable in layout.systemAt(i).drawables) {
          final dashedLine =
              drawable is LineDraw && drawable.dash == LineDash.dashed;
          if (drawable is! CurveDraw &&
              drawable is! GlyphRunDraw &&
              !dashedLine) {
            continue;
          }
          final box = drawable.bounds;
          final scale = SheetScale(
            spacePx: spacePx,
            origin: ui.Offset(
              pad - (box.left * spacePx).floorToDouble(),
              pad - (box.top * spacePx).floorToDouble(),
            ),
          );
          final width = (box.width * spacePx).ceil() + 2 * pad + 1;
          final alone = await render(
            width,
            (box.height * spacePx).ceil() + 2 * pad + 1,
            (canvas) => paintDrawables(canvas, painter, [drawable], scale),
            background: null,
          );
          final ink = inkOfImage(alone.rgba, width);
          final rect = scale.rectOf(box);
          final reason = 'system $i, ${drawable.runtimeType} from x '
              '${box.left.toStringAsFixed(2)}';
          expectInside(ink, rect, reason);

          switch (drawable) {
            case GlyphRunDraw():
              kinds.add('glyph run');
              expect(ink!.left, closeTo(rect.left, 1), reason: reason);
              expect(ink.right, closeTo(rect.right, 1), reason: reason);
            case LineDraw(:final from, :final to, :final thickness):
              kinds.add('dashed line');
              expect(ink!.right, closeTo(rect.right, 1), reason: reason);
              final dashes =
                  columnInk(alone.rgba, width).reduce((a, b) => a + b) /
                      (thickness * spacePx);
              expect(
                dashes / ((to.x - from.x) * spacePx),
                inInclusiveRange(0.6, 0.7),
                reason: '$reason, the share of its length under dashes',
              );
            case CurveDraw(:final midThickness, :final endThickness):
              final start = scale.toPx(drawable.start).dx;
              final end = scale.toPx(drawable.end).dx;
              expect(ink!.left, lessThanOrEqualTo(start + 1), reason: reason);
              expect(ink.right, greaterThanOrEqualTo(end - 1), reason: reason);
              final columns = columnInk(alone.rgba, width);
              if (!drawable.dashed) {
                kinds.add('curve');
                expect(
                  columns[scale.toPx(drawable.pointAt(0.5)).dx.floor()],
                  closeTo((midThickness + endThickness) * spacePx, 0.5),
                  reason: '$reason, thickness at its middle',
                );
                continue;
              }
              kinds.add('dashed curve');
              final length = [
                for (var step = 0; step < 64; step++)
                  (scale.toPx(drawable.pointAt((step + 1) / 64)) -
                          scale.toPx(drawable.pointAt(step / 64)))
                      .distance,
              ].reduce((a, b) => a + b);
              final dashes =
                  columns.reduce((a, b) => a + b) / (midThickness * spacePx);
              expect(
                dashes / length,
                inInclusiveRange(0.6, 0.7),
                reason: '$reason, the share of its length under dashes '
                    'of its middle thickness',
              );
            default:
          }
        }
      }
      expect(kinds, {'curve', 'dashed curve', 'dashed line', 'glyph run'});
    });
  });

  test('a dashed path ends on a dash, and a short one is stroked whole', () {
    List<ui.Rect> dashesOf(double length) => [
          for (final metric in dashPath(
            ui.Path()..lineTo(length, 0),
            LineDash.dashed,
            spacePx,
          ).computeMetrics())
            metric.extractPath(0, metric.length).getBounds(),
        ];

    final long = dashesOf(10.2 * spacePx);
    expect(long, hasLength(13));
    expect(
      long.map((dash) => dash.width),
      everyElement(closeTo(0.5 * spacePx, 1e-3)),
    );
    expect(long.first.left, 0);
    expect(long.last.right, closeTo(10.2 * spacePx, 1e-3));

    final short = dashesOf(0.9 * spacePx);
    expect(short, hasLength(1));
    expect(short.single.width, closeTo(0.9 * spacePx, 1e-3));
  });
}
