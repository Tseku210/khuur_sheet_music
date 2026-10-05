import 'dart:math' as math;

import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/bar_space.dart';
import 'package:score_layout/src/chords.dart';
import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/smufl_font.dart';
import 'package:score_layout/src/spacing.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/bars.dart';
import 'support/fake_measurer.dart';

const EngravingStyle style = EngravingStyle.standard;
final SmuflFont font = style.font;
final Box headBox = font[Glyph.noteheadBlack].box;
final Box dotBox = font[Glyph.augmentationDot].box;

const dottedQuarter = NoteValue(DurationBase.quarter, dots: 1);
const doubleDottedQuarter = NoteValue(DurationBase.quarter, dots: 2);
const dottedEighth = NoteValue(DurationBase.eighth, dots: 1);

TimedEvent timedOf(MeasureView view, {int index = 0, int voice = 0}) =>
    view.staves.first.voices[voice].events[index];

StemSide sideOf(MeasureView view, {int index = 0, int voice = 0}) {
  final staff = view.staves.first;
  final timed = timedOf(view, index: index, voice: voice);
  return stemSideFor(
    timed.event as ChordEvent,
    staff,
    staff.voices[voice].slot,
    at: timed.onset,
  );
}

ChordPlan planOf(
  MeasureView view, {
  int index = 0,
  int voice = 0,
  bool beamed = false,
  EngravingStyle style = style,
}) {
  final timed = timedOf(view, index: index, voice: voice);
  final staff = view.staves.first;
  return planChord(
    timed: timed,
    chord: timed.event as ChordEvent,
    staff: staff,
    lines: staff.part.staves
        .firstWhere((s) => s.id == staff.source.staff)
        .lines,
    stem: sideOf(view, index: index, voice: voice),
    beamed: beamed,
    style: style,
  );
}

List<Drawable> chordItems(
  MeasureView view, {
  int index = 0,
  int voice = 0,
  bool beamed = false,
  EngravingStyle style = style,
}) => [
  for (final item in placeChord(
    planOf(view, index: index, voice: voice, beamed: beamed, style: style),
    slice: 0,
    staff: 0,
  ))
    item.drawable,
];

List<BarItem> restBarItems(MeasureView view, {int index = 0, int voice = 0}) {
  final staff = view.staves.first;
  return placeRest(
    timed: timedOf(view, index: index, voice: voice),
    slice: 0,
    staff: 0,
    voiceCount: staff.voices.length,
    lines: staff.part.staves.first.lines,
    style: style,
  );
}

List<Drawable> restItems(MeasureView view, {int index = 0, int voice = 0}) => [
  for (final item in restBarItems(view, index: index, voice: voice))
    item.drawable,
];

Iterable<GlyphDraw> glyphsIn(Iterable<Drawable> drawables) =>
    drawables.whereType<GlyphDraw>();

Iterable<GlyphDraw> headsIn(Iterable<Drawable> drawables) =>
    glyphsIn(drawables).where((g) => g.glyph.name.startsWith('notehead'));

GlyphDraw headAt(Iterable<Drawable> drawables, int step) =>
    headsIn(drawables).singleWhere((g) => g.origin.y == yOfStep(step));

Iterable<GlyphDraw> accidentalsIn(Iterable<Drawable> drawables) =>
    glyphsIn(drawables).where((g) => g.glyph.name.startsWith('accidental'));

Iterable<GlyphDraw> dotsIn(Iterable<Drawable> drawables) =>
    glyphsIn(drawables).where((g) => g.glyph == Glyph.augmentationDot);

Iterable<GlyphDraw> flagsIn(Iterable<Drawable> drawables) =>
    glyphsIn(drawables).where((g) => g.glyph.name.startsWith('flag'));

Iterable<LineDraw> stemsIn(Iterable<Drawable> drawables) =>
    drawables.whereType<LineDraw>().where((l) => l.from.x == l.to.x);

Iterable<LineDraw> ledgersIn(Iterable<Drawable> drawables) =>
    drawables.whereType<LineDraw>().where((l) => l.from.y == l.to.y);

Iterable<LineDraw> slashesIn(Iterable<Drawable> drawables) => drawables
    .whereType<LineDraw>()
    .where((l) => l.from.x != l.to.x && l.from.y != l.to.y);

bool overlap(Box a, Box b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.top < b.bottom &&
    b.top < a.bottom;

void main() {
  group('stemSideFor', () {
    test('a stored stem direction wins over the mean step', () {
      final view = barOf([
        chordOf(1, 'C4', stem: StemDirection.down),
        chordOf(2, 'C6', stem: StemDirection.up),
        chordOf(3, 'C4', value: half),
      ]);

      expect(sideOf(view), StemSide.down);
      expect(sideOf(view, index: 1), StemSide.up);
      expect(sideOf(view, index: 2), StemSide.up);
    });

    test('with two voices the voice slot decides', () {
      final view = barOf(
        [chordOf(1, 'C6', value: whole)],
        two: [chordOf(2, 'C4', value: whole)],
      );

      expect(sideOf(view), StemSide.up);
      expect(sideOf(view, voice: 1), StemSide.down);
    });

    test('with one voice the mean step against the middle line decides', () {
      final view = barOf([
        chordOf(1, 'C4 E4'),
        chordOf(2, 'G5'),
        chordOf(3, 'E4 E5'),
        chordOf(4, 'D4 C6'),
      ]);

      expect(sideOf(view), StemSide.up);
      expect(sideOf(view, index: 1), StemSide.down);
      expect(sideOf(view, index: 2), StemSide.up);
      expect(sideOf(view, index: 3), StemSide.down);
    });

    test('a chord centred on the middle line stems down', () {
      final view = barOf([
        chordOf(1, 'B4'),
        chordOf(2, 'A4 C5', value: dottedHalf),
      ]);

      expect(sideOf(view), StemSide.down);
      expect(sideOf(view, index: 1), StemSide.down);
    });
  });

  group('heads', () {
    test('the heads of a second do not overlap, the upper one flipped right on an upstem', () {
      final items = chordItems(barOf([chordOf(1, 'C4 D4', value: whole)]));
      final lower = headAt(items, -2);
      final upper = headAt(items, -1);

      expect(lower.origin.x, 0);
      expect(
        upper.bounds.left,
        greaterThanOrEqualTo(lower.bounds.right - 1e-9),
      );
      expect(overlap(lower.bounds, upper.bounds), isFalse);
    });

    test('on a downstem chord the lower head of a second flips left', () {
      final items = chordItems(barOf([chordOf(1, 'C5 D5', value: whole)]));
      final lower = headAt(items, 5);
      final upper = headAt(items, 6);

      expect(upper.origin.x, 0);
      expect(lower.bounds.right, lessThanOrEqualTo(upper.bounds.left + 1e-9));
    });

    test('the heads of a unison sit side by side', () {
      final items = chordItems(barOf([chordOf(1, 'C4 C#4', value: whole)]));
      final [lower, upper] = headsIn(items).toList()
        ..sort((a, b) => a.origin.x.compareTo(b.origin.x));

      expect(lower.origin.y, upper.origin.y);
      expect(lower.origin.x, 0);
      expect(
        upper.bounds.left,
        greaterThanOrEqualTo(lower.bounds.right - 1e-9),
      );
    });

    test('the heads of a third stay in one column', () {
      final items = chordItems(barOf([chordOf(1, 'C4 E4', value: whole)]));

      expect(headAt(items, -2).origin.x, 0);
      expect(headAt(items, 0).origin.x, 0);
    });

    test('three seconds alternate sides', () {
      final items = chordItems(barOf([chordOf(1, 'C4 D4 E4', value: whole)]));

      expect(headAt(items, -2).origin.x, 0);
      expect(headAt(items, -1).origin.x, greaterThan(0));
      expect(headAt(items, 0).origin.x, 0);
    });

    test('three heads on one step stand in a row from the stem outward, each '
        'against the one before', () {
      final view = barOf([chordOf(1, 'Cb4 C4 C#4'), chordOf(2, 'Cb5 C5 C#5')]);
      final up = planOf(view);
      final upHeads = headsIn(chordItems(view)).toList()
        ..sort((a, b) => a.origin.x.compareTo(b.origin.x));
      final downHeads = headsIn(chordItems(view, index: 1)).toList()
        ..sort((a, b) => b.origin.x.compareTo(a.origin.x));

      expect(sideOf(view), StemSide.up);
      expect(upHeads, hasLength(3));
      expect({for (final head in upHeads) head.origin.y}, {yOfStep(-2)});
      expect(upHeads[0].origin.x, 0);
      expect(upHeads[1].bounds.left, closeTo(upHeads[0].bounds.right, 0.2));
      expect(
        upHeads[1].bounds.left,
        greaterThanOrEqualTo(upHeads[0].bounds.right - 1e-9),
      );
      expect(upHeads[2].bounds.left, closeTo(upHeads[1].bounds.right, 1e-9));
      expect(up.reach.right, greaterThanOrEqualTo(upHeads[2].bounds.right));

      expect(sideOf(view, index: 1), StemSide.down);
      expect(downHeads, hasLength(3));
      expect({for (final head in downHeads) head.origin.y}, {yOfStep(5)});
      expect(downHeads[0].origin.x, 0);
      expect(
        downHeads[1].bounds.right,
        lessThanOrEqualTo(downHeads[0].bounds.left + 1e-9),
      );
      expect(
        downHeads[2].bounds.right,
        closeTo(downHeads[1].bounds.left, 1e-9),
      );
    });

    test('a unison and a second in one chord keep all three heads apart', () {
      for (final pitches in ['C4 C#4 D4', 'C4 Db4 D4', 'C5 C#5 D5']) {
        final items = chordItems(barOf([chordOf(1, pitches)]));
        final heads = headsIn(items).toList();

        expect(heads, hasLength(3), reason: pitches);
        for (final (i, a) in heads.indexed) {
          for (final b in heads.skip(i + 1)) {
            expect(overlap(a.bounds, b.bounds), isFalse, reason: pitches);
          }
        }
      }
    });

    test('the accidentals of three heads on one step stay left of every head '
        'and clear of each other', () {
      for (final pitches in ['Cb4 C4 C#4', 'Cb5 C5 C#5']) {
        final items = chordItems(barOf([chordOf(1, pitches)]));
        final heads = headsIn(items).toList();
        final accidentals = accidentalsIn(items).toList();
        final left = heads.map((head) => head.bounds.left).reduce(math.min);

        expect(accidentals.length, greaterThanOrEqualTo(2), reason: pitches);
        for (final (i, accidental) in accidentals.indexed) {
          expect(accidental.bounds.right, lessThan(left), reason: pitches);
          for (final other in accidentals.skip(i + 1)) {
            expect(
              overlap(accidental.bounds, other.bounds),
              isFalse,
              reason: pitches,
            );
          }
        }
      }
    });

    test('a head glyph follows the value', () {
      final view = barOf([
        chordOf(1, 'C5', value: half),
        chordOf(2, 'C5'),
        chordOf(3, 'C5', value: eighth),
      ]);

      expect(headsIn(chordItems(view)).single.glyph, Glyph.noteheadHalf);
      expect(
        headsIn(chordItems(view, index: 1)).single.glyph,
        Glyph.noteheadBlack,
      );
      expect(
        headsIn(chordItems(view, index: 2)).single.glyph,
        Glyph.noteheadBlack,
      );
    });

    test('a note outside the instrument range is marked', () {
      const alto = Instrument(
        key: 'alto',
        program: 0,
        lowest: Pitch(Step.c, 4),
        highest: Pitch(Step.c, 5),
      );
      final items = chordItems(
        barOf([chordOf(1, 'C5 D5', value: whole)], instrument: alto),
      );

      expect(headAt(items, 5).ink, InkRole.notehead);
      expect(headAt(items, 6).ink, InkRole.outOfRange);
    });
  });

  group('accidentals', () {
    test('no accidental overlaps a head or another accidental', () {
      final items = chordItems(
        barOf([chordOf(1, 'F#4 G#4 A#4', value: whole)]),
      );
      final accidentals = accidentalsIn(items).toList();

      expect(accidentals, hasLength(3));
      for (final accidental in accidentals) {
        for (final head in headsIn(items)) {
          expect(overlap(accidental.bounds, head.bounds), isFalse);
        }
        for (final other in accidentals) {
          if (other != accidental) {
            expect(overlap(accidental.bounds, other.bounds), isFalse);
          }
        }
      }
    });

    test(
      'accidentals that clear each other share the column nearest the heads',
      () {
        final items = chordItems(barOf([chordOf(1, 'F#4 F#5', value: whole)]));
        final accidentals = accidentalsIn(items).toList();

        expect(
          accidentals.map((a) => a.glyph),
          everyElement(Glyph.accidentalSharp),
        );
        expect(
          accidentals[0].bounds.right,
          closeTo(accidentals[1].bounds.right, 1e-9),
        );
        expect(accidentals[0].bounds.right, closeTo(-0.25, 1e-9));
      },
    );

    test('accidentals of a second take two columns, the upper one nearer', () {
      final items = chordItems(barOf([chordOf(1, 'C#5 D#5', value: whole)]));
      final lower = accidentalsIn(items)
          .singleWhere((a) => a.origin.y == yOfStep(5));
      final upper = accidentalsIn(items)
          .singleWhere((a) => a.origin.y == yOfStep(6));

      expect(lower.bounds.right, lessThan(upper.bounds.left));
    });

    test('a quarter-tone note draws the glyph of the chosen family', () {
      final view = barOf([
        chordOf(1, 'C+5'),
        chordOf(2, 'Dd5', value: dottedHalf),
      ]);
      const gould = EngravingStyle(quarterTones: QuarterToneGlyphs.gouldArrows);

      expect(
        accidentalsIn(chordItems(view)).single.glyph,
        Glyph.accidentalQuarterToneSharpStein,
      );
      expect(
        accidentalsIn(chordItems(view, index: 1)).single.glyph,
        Glyph.accidentalQuarterToneFlatStein,
      );
      expect(
        accidentalsIn(chordItems(view, style: gould)).single.glyph,
        Glyph.accidentalQuarterToneSharpNaturalArrowUp,
      );
      expect(
        accidentalsIn(chordItems(view, index: 1, style: gould)).single.glyph,
        Glyph.accidentalQuarterToneFlatNaturalArrowDown,
      );
    });

    test('a cautionary accidental is wrapped in parentheses', () {
      final view = barOf([
        chordOf(1, 'F#4', value: half),
        chordOf(
          2,
          'F#4',
          value: half,
          accidental: AccidentalRequest.cautionary,
        ),
      ]);
      final glyphs = glyphsIn(chordItems(view, index: 1)).map((g) => g.glyph);

      expect(
        glyphs,
        containsAll([
          Glyph.accidentalParensLeft,
          Glyph.accidentalSharp,
          Glyph.accidentalParensRight,
        ]),
      );
    });
  });

  group('drum heads', () {
    test(
      'a drum note draws its sound head at its position on a one-line staff',
      () {
        final view = barOf(
          [
            hitOf(1, [snare, bassDrum]),
            hitOf(2, [sideStick]),
          ],
          clef: Clef.percussion,
          lines: 1,
          instrument: drumKit,
        );
        final hit = chordItems(view);

        expect(headAt(hit, 5).glyph, Glyph.noteheadBlack);
        expect(headAt(hit, 1).glyph, Glyph.noteheadBlack);
        expect(headAt(hit, 5).origin.y, yOfStep(4) - 0.5);
        expect(ledgersIn(hit), isEmpty);
        expect(
          headAt(chordItems(view, index: 1), 5).glyph,
          Glyph.noteheadXBlack,
        );
      },
    );
  });

  group('ledger lines', () {
    test('a note below the staff gets a line per even step down to it', () {
      final view = barOf([
        chordOf(1, 'C4'),
        chordOf(2, 'B3'),
        chordOf(3, 'A3'),
      ]);

      expect(ledgersIn(chordItems(view)).map((l) => l.from.y), [5]);
      expect(ledgersIn(chordItems(view, index: 1)).map((l) => l.from.y), [5]);
      expect(ledgersIn(chordItems(view, index: 2)).map((l) => l.from.y), [
        5,
        6,
      ]);
    });

    test('a note above the staff gets a line per even step up to it', () {
      final view = barOf([
        chordOf(1, 'A5'),
        chordOf(2, 'B5'),
        chordOf(3, 'C6'),
      ]);

      expect(ledgersIn(chordItems(view)).map((l) => l.from.y), [-1]);
      expect(ledgersIn(chordItems(view, index: 1)).map((l) => l.from.y), [-1]);
      expect(ledgersIn(chordItems(view, index: 2)).map((l) => l.from.y), [
        -1,
        -2,
      ]);
    });

    test('a one-line staff has no ledger lines, however far a head or a '
        'grace head lies from its line', () {
      const kit = Instrument(
        key: 'drums',
        program: 0,
        bank: 128,
        clef: Clef.percussion,
        drums: [
          DrumSound(name: 'Crash', position: Pitch(Step.a, 5), midiKey: 49),
          DrumSound(name: 'Low', position: Pitch(Step.c, 4), midiKey: 41),
        ],
      );
      final view = barOf(
        [
          ChordEvent(
            id: const EventId(1),
            value: NoteValue.quarter,
            notes: Seq([const DrumNote(id: NoteId(10), drum: Drum('Crash'))]),
            graces: Seq([
              GraceChord(
                id: const EventId(3),
                kind: GraceKind.acciaccatura,
                value: NoteValue.eighth,
                notes: Seq([
                  const DrumNote(id: NoteId(30), drum: Drum('Low')),
                ]),
              ),
            ]),
          ),
          hitOf(2, [const Drum('Low')]),
        ],
        clef: Clef.percussion,
        lines: 1,
        instrument: kit,
      );
      final crash = chordItems(view);
      final low = chordItems(view, index: 1);
      final grace = [
        for (final item in graceItems(
          planOf(view),
          slice: 0,
          staff: 0,
          style: style,
        ))
          item.drawable,
      ];
      final bar = [
        for (final item in layoutBar(view, style, const FakeMeasurer()).items)
          item.drawable,
      ];

      expect(headAt(crash, 10).glyph, Glyph.noteheadBlack);
      expect(headAt(low, -2).glyph, Glyph.noteheadBlack);
      expect(headsIn(grace).single.origin.y, yOfStep(-2));
      expect(ledgersIn(crash), isEmpty);
      expect(ledgersIn(low), isEmpty);
      expect(ledgersIn(grace), isEmpty);
      expect(headsIn(bar), hasLength(3));
      expect(ledgersIn(bar), isEmpty);
    });

    test('a ledger line extends past the heads it serves', () {
      final items = chordItems(barOf([chordOf(1, 'C4', value: whole)]));
      final head = headsIn(items).single.bounds;
      final line = ledgersIn(items).single;
      final extension = font.defaults.legerLineExtension;

      expect(line.from.x, closeTo(head.left - extension, 1e-9));
      expect(line.to.x, closeTo(head.right + extension, 1e-9));
      expect(line.thickness, font.defaults.legerLineThickness);
    });

    test('a ledger line spans the heads on it or beyond it, not the rest', () {
      final extension = font.defaults.legerLineExtension;
      final straddle = chordItems(barOf([chordOf(1, 'F3 B3 C4')]));
      final atC4 = ledgersIn(
        straddle,
      ).singleWhere((l) => l.from.y == yOfStep(-2));
      final atA3 = ledgersIn(
        straddle,
      ).singleWhere((l) => l.from.y == yOfStep(-4));
      final second = chordItems(barOf([chordOf(1, 'A3 B3')]));
      final throughA3 = ledgersIn(
        second,
      ).singleWhere((l) => l.from.y == yOfStep(-4));
      final aboveB3 = ledgersIn(
        second,
      ).singleWhere((l) => l.from.y == yOfStep(-2));
      final upper = chordItems(barOf([chordOf(1, 'G5 A5')]));
      final throughA5 = ledgersIn(upper).single;

      expect(
        atC4.to.x,
        closeTo(headAt(straddle, -2).bounds.right + extension, 1e-9),
      );
      expect(
        atA3.to.x,
        closeTo(headAt(straddle, -6).bounds.right + extension, 1e-9),
      );
      expect(atA3.to.x, lessThan(atC4.to.x));
      expect(
        throughA3.to.x,
        closeTo(headAt(second, -4).bounds.right + extension, 1e-9),
      );
      expect(
        aboveB3.to.x,
        closeTo(headAt(second, -3).bounds.right + extension, 1e-9),
      );
      expect(throughA3.to.x, lessThan(aboveB3.to.x));
      expect(
        throughA5.from.x,
        closeTo(headAt(upper, 10).bounds.left - extension, 1e-9),
      );
      expect(headAt(upper, 9).bounds.left, lessThan(throughA5.from.x));
    });

    test('an accidental sits clear of the ledger line through its note', () {
      final items = chordItems(barOf([chordOf(1, 'C#4', value: whole)]));
      final sharp = accidentalsIn(items).single;
      final line = ledgersIn(items).single;

      expect(sharp.bounds.right, closeTo(line.from.x - 0.25, 1e-9));
    });

    test('a note inside the staff gets no ledger line', () {
      expect(
        ledgersIn(chordItems(barOf([chordOf(1, 'E4', value: whole)]))),
        isEmpty,
      );
      expect(
        ledgersIn(chordItems(barOf([chordOf(1, 'F5', value: whole)]))),
        isEmpty,
      );
    });
  });

  group('dots', () {
    test('a dot sits in the space above a line note and in the space of a space note', () {
      final view = barOf([
        chordOf(1, 'B4', value: dottedQuarter),
        chordOf(2, 'C5', value: dottedQuarter),
        chordOf(3, 'C5'),
      ]);

      expect(dotsIn(chordItems(view)).single.origin.y, yOfStep(5));
      expect(dotsIn(chordItems(view, index: 1)).single.origin.y, yOfStep(5));
      expect(dotsIn(chordItems(view, index: 2)), isEmpty);
    });

    test(
      'dots start half a space right of the heads and follow each other',
      () {
        final items = chordItems(
          barOf([chordOf(1, 'C5', value: doubleDottedQuarter)]),
        );
        final dots = dotsIn(items).toList();
        final head = headsIn(items).single.bounds;

        expect(dots, hasLength(2));
        expect(dots[0].bounds.left, closeTo(head.right + 0.5, 1e-9));
        expect(
          dots[1].origin.x,
          closeTo(dots[0].origin.x + dotBox.width + 0.25, 1e-9),
        );
      },
    );

    test('heads that share a dot space share one dot', () {
      final items = chordItems(
        barOf([chordOf(1, 'B4 C5', value: dottedQuarter)]),
      );

      expect(dotsIn(items), hasLength(1));
    });
  });

  group('stems and flags', () {
    test('an unbeamed eighth hangs its flag from the stem tip', () {
      final items = chordItems(barOf([chordOf(1, 'C4', value: eighth)]));
      final stem = stemsIn(items).single;
      final flag = flagsIn(items).single;
      final anchor = font[Glyph.flag8thUp].anchors[GlyphAnchor.stemUpNW]!;

      expect(flag.glyph, Glyph.flag8thUp);
      expect(stem.to.y, closeTo(yOfStep(-2) - stemLength, 1e-9));
      expect(
        flag.origin.x + anchor.x,
        closeTo(stem.from.x - stem.thickness / 2, 1e-9),
      );
      expect(flag.origin.y + anchor.y, closeTo(stem.to.y, 1e-9));
    });

    test('a downstem sixteenth takes the down flag', () {
      final items = chordItems(barOf([chordOf(1, 'C5', value: sixteenth)]));
      final stem = stemsIn(items).single;
      final flag = flagsIn(items).single;
      final anchor = font[Glyph.flag16thDown].anchors[GlyphAnchor.stemDownSW]!;

      expect(flag.glyph, Glyph.flag16thDown);
      expect(stem.to.y, closeTo(yOfStep(5) + stemLength, 1e-9));
      expect(flag.origin.y + anchor.y, closeTo(stem.to.y, 1e-9));
    });

    test('a quarter has a stem and no flag', () {
      final items = chordItems(barOf([chordOf(1, 'C5')]));

      expect(stemsIn(items), hasLength(1));
      expect(flagsIn(items), isEmpty);
    });

    test('a whole note has neither stem nor flag, a half has a stem', () {
      final wholeItems = chordItems(barOf([chordOf(1, 'C5', value: whole)]));
      final halfItems = chordItems(barOf([chordOf(1, 'C5', value: half)]));

      expect(stemsIn(wholeItems), isEmpty);
      expect(flagsIn(wholeItems), isEmpty);
      expect(stemsIn(halfItems), hasLength(1));
    });

    test('a stem far outside the staff reaches the middle line', () {
      final high = chordItems(barOf([chordOf(1, 'C6')]));
      final low = chordItems(barOf([chordOf(1, 'G3')]));

      expect(stemsIn(high).single.to.y, yOfStep(4));
      expect(stemsIn(low).single.to.y, yOfStep(4));
    });

    test('the stem leaves the start head at its stem anchor', () {
      final items = chordItems(barOf([chordOf(1, 'C4 E4')]));
      final stem = stemsIn(items).single;
      final anchor = font[Glyph.noteheadBlack].anchors[GlyphAnchor.stemUpSE]!;

      expect(stem.from.x, closeTo(anchor.x - stem.thickness / 2, 1e-9));
      expect(stem.from.y, closeTo(yOfStep(-2) + anchor.y, 1e-9));
      expect(stem.thickness, font.defaults.stemThickness);
    });

    test('dots move past a flag that reaches their row', () {
      final onLine = chordItems(barOf([chordOf(1, 'G4', value: dottedEighth)]));
      final inSpace = chordItems(
        barOf([chordOf(1, 'F4', value: dottedEighth)]),
      );
      final flag = flagsIn(onLine).single.bounds;
      final lineDot = dotsIn(onLine).single.bounds;
      final spaceDot = dotsIn(inSpace).single.bounds;

      expect(lineDot.top, lessThan(flag.bottom));
      expect(lineDot.left, closeTo(flag.right + 0.5, 1e-9));
      expect(
        spaceDot.left,
        closeTo(headAt(inSpace, 1).bounds.right + 0.5, 1e-9),
      );
    });

    test('tremolo strokes on a stemless chord centre on its head', () {
      final items = chordItems(
        barOf([chordOf(1, 'C5', value: whole, tremolo: 3)]),
      );
      final head = headsIn(items).single.bounds;
      final strokes = glyphsIn(
        items,
      ).singleWhere((g) => g.glyph == Glyph.tremolo3);

      expect(stemsIn(items), isEmpty);
      expect(strokes.origin.x, closeTo((head.left + head.right) / 2, 1e-9));
      expect(strokes.bounds.top, greaterThanOrEqualTo(head.bottom));
    });

    test('a beamed chord has no stem and no flag, and its reach leaves the flag out', () {
      final view = barOf([chordOf(1, 'G4', value: eighth)]);
      final items = chordItems(view, beamed: true);

      expect(stemsIn(items), isEmpty);
      expect(flagsIn(items), isEmpty);
      expect(
        planOf(view, beamed: true).reach.right,
        closeTo(headBox.right, 1e-9),
      );
      expect(planOf(view).reach.right, greaterThan(headBox.right + 0.5));
    });

    test(
      'a tremolo draws its strokes across the stem and lengthens it past them',
      () {
        final items = chordItems(barOf([chordOf(1, 'C4', tremolo: 2)]));
        final stem = stemsIn(items).single;
        final strokes = glyphsIn(items)
            .singleWhere((g) => g.glyph == Glyph.tremolo2);

        expect(strokes.origin.x, stem.from.x);
        expect(strokes.origin.y, yOfStep(-2) - 2);
        expect(stem.to.y, lessThanOrEqualTo(strokes.bounds.top - 0.5 + 1e-9));
      },
    );

    test('a flagged tremolo lengthens the stem until the flag clears the '
        'strokes', () {
      for (final (pitch, up) in [('C4', true), ('C5', false)]) {
        final items = chordItems(
          barOf([chordOf(1, pitch, value: eighth, tremolo: 2)]),
        );
        final flag = flagsIn(items).single;
        final strokes = glyphsIn(items)
            .singleWhere((g) => g.glyph == Glyph.tremolo2);
        final head = headsIn(items).single;

        expect(strokes.origin.y, head.origin.y + (up ? -2 : 2), reason: pitch);
        if (up) {
          expect(
            flag.bounds.bottom,
            lessThanOrEqualTo(strokes.bounds.top - 0.5 + 1e-9),
            reason: pitch,
          );
        } else {
          expect(
            flag.bounds.top,
            greaterThanOrEqualTo(strokes.bounds.bottom + 0.5 - 1e-9),
            reason: pitch,
          );
        }
      }
    });
  });

  group('grace notes', () {
    test(
      'a grace head sits at the grace scale left of the principal, slashed',
      () {
        final view = barOf([
          chordOf(1, 'C5', graces: [graceOf(2, 'B4')]),
        ]);
        final plan = planOf(view);
        final items = [
          for (final item in graceItems(plan, slice: 0, staff: 0, style: style))
            item.drawable,
        ];
        final head = headsIn(items).single;
        final right = items
            .map((d) => d.bounds.right)
            .reduce((a, b) => a > b ? a : b);

        expect(plan.graces.single.x, lessThan(0));
        expect(head.scale, style.graceScale);
        expect(head.origin.y, yOfStep(4));
        expect(
          head.bounds.width,
          closeTo(headBox.width * style.graceScale, 1e-9),
        );
        expect(right, closeTo(-0.5, 1e-9));
        expect(flagsIn(items).single.glyph, Glyph.flag8thUp);
        expect(slashesIn(items), hasLength(1));
        expect(plan.reach.left, greaterThan(0.5));
      },
    );

    test('an appoggiatura has no slash', () {
      final plan = planOf(
        barOf([
          chordOf(
            1,
            'C5',
            graces: [graceOf(2, 'B4', kind: GraceKind.appoggiatura)],
          ),
        ]),
      );
      final items = [
        for (final item in graceItems(plan, slice: 0, staff: 0, style: style))
          item.drawable,
      ];

      expect(slashesIn(items), isEmpty);
      expect(stemsIn(items), hasLength(1));
    });

    test('a sixteenth or a quarter acciaccatura has its slash too', () {
      for (final value in [sixteenth, NoteValue.quarter]) {
        final plan = planOf(
          barOf([
            chordOf(1, 'C5', graces: [graceOf(2, 'B4', value: value)]),
          ]),
        );
        final items = [
          for (final item in graceItems(plan, slice: 0, staff: 0, style: style))
            item.drawable,
        ];
        final slash = slashesIn(items).single;
        final stem = stemsIn(items).single;

        expect(slash.from.x, lessThan(stem.from.x), reason: '$value');
        expect(slash.to.x, greaterThan(stem.from.x), reason: '$value');
        expect(slash.from.y, lessThan(stem.from.y), reason: '$value');
        expect(slash.to.y, greaterThan(stem.to.y), reason: '$value');
      }
    });

    test('every grace drawable is owned by the principal', () {
      final view = barOf([
        chordOf(1, 'C5', graces: [graceOf(2, 'B4 D5')]),
      ]);
      final items = graceItems(planOf(view), slice: 0, staff: 0, style: style);

      expect(headsIn(items.map((i) => i.drawable)), hasLength(2));
      expect(
        items.map((i) => i.drawable.owner),
        everyElement(ElementOwner(timedOf(view).ref)),
      );
    });

    test('graces keep their order from left to right', () {
      final plan = planOf(
        barOf([
          chordOf(1, 'C5', graces: [graceOf(2, 'A4'), graceOf(3, 'B4')]),
        ]),
      );
      final items = graceItems(plan, slice: 0, staff: 0, style: style);
      final heads = headsIn(items.map((i) => i.drawable)).toList();

      expect(plan.graces.map((g) => g.source.id), [
        const EventId(2),
        const EventId(3),
      ]);
      expect(plan.graces[0].x, lessThan(plan.graces[1].x));
      expect(heads[0].origin.y, yOfStep(3));
      expect(heads[1].origin.y, yOfStep(4));
      expect(heads[0].bounds.right, lessThan(heads[1].bounds.left));
    });

    test('a chord without graces plans none', () {
      expect(planOf(barOf([chordOf(1, 'C5')])).graces, isEmpty);
    });
  });

  group('rests', () {
    test(
      'a rest sits on the middle line, a whole rest hangs from the line above',
      () {
        final view = barOf([
          restOf(1, NoteValue.quarter),
          restOf(2, dottedHalf),
        ]);
        final wholeView = barOf([restOf(1, whole)]);
        final quarter = glyphsIn(restItems(view)).single;
        final wholeRest = glyphsIn(restItems(wholeView)).single;

        expect(quarter.glyph, Glyph.restQuarter);
        expect(quarter.origin, const SpPoint(0, 2));
        expect(wholeRest.glyph, Glyph.restWhole);
        expect(wholeRest.origin, const SpPoint(0, 1));
      },
    );

    test('on a one-line staff a whole rest hangs from the line', () {
      final view = barOf(
        [restOf(1, whole)],
        clef: Clef.percussion,
        lines: 1,
        instrument: drumKit,
      );

      expect(glyphsIn(restItems(view)).single.origin.y, yOfStep(4));
    });

    test('with two voices the rests move apart', () {
      final view = barOf(
        [restOf(1, NoteValue.quarter), chordOf(2, 'C5', value: dottedHalf)],
        two: [
          restOf(3, NoteValue.quarter),
          chordOf(4, 'A4', value: dottedHalf),
        ],
      );

      expect(glyphsIn(restItems(view)).single.origin.y, 1);
      expect(glyphsIn(restItems(view, voice: 1)).single.origin.y, 3);
    });

    test('a rest dot sits in the space above the middle line', () {
      final view = barOf([restOf(1, dottedQuarter), restOf(2, eighth)]);
      final items = restItems(view);
      final rest = glyphsIn(items).first.bounds;
      final dot = dotsIn(items).single;

      expect(dot.origin.y, yOfStep(5));
      expect(dot.bounds.left, closeTo(rest.right + 0.5, 1e-9));
      expect(
        restReach(timedOf(view).event, style).right,
        closeTo(dot.bounds.right, 1e-9),
      );
    });

    test('a hidden rest draws nothing and reaches nowhere', () {
      final view = barOf([restOf(1, whole, hidden: true)]);

      expect(restItems(view), isEmpty);
      expect(restReach(timedOf(view).event, style), noReach);
    });

    test(
      'a measure rest hangs centred from the middle of its slice and the '
      'bar end, so a frame centres it at any stretch, and reaches its own '
      'width, so the least bar holds it',
      () {
        final view = barOf([
          MeasureRest(id: const EventId(1), span: whole.length),
        ]);
        final item = restBarItems(view).single;
        final rest = item.drawable as GlyphDraw;

        expect(item.centred, isTrue);
        expect(rest.glyph, Glyph.restWhole);
        expect((rest.bounds.left + rest.bounds.right) / 2, closeTo(0, 1e-9));
        expect(rest.origin.y, 1);
        expect(restReach(timedOf(view).event, style), (
          left: 0,
          right: font[Glyph.restWhole].box.width,
        ));
        for (final end in [10.0, 25.0]) {
          final frame = BarFrame(left: 0, xs: [2, 6, end], tops: const [0]);
          final placed = frame.place(item).bounds;
          expect(
            (placed.left + placed.right) / 2,
            closeTo((2 + end) / 2, 1e-9),
            reason: 'bar end $end',
          );
        }
      },
    );

    test('a rest reach matches its glyph', () {
      final view = barOf([restOf(1, whole)]);

      expect(
        restReach(timedOf(view).event, style),
        (left: 0, right: font[Glyph.restWhole].box.right),
      );
    });

    test('a chord is not a rest', () {
      final view = barOf([chordOf(1, 'C5', value: whole)]);

      expect(() => restReach(timedOf(view).event, style), throwsArgumentError);
      expect(() => restItems(view), throwsArgumentError);
    });
  });

  group('ownership', () {
    test('heads belong to their note and the rest to the event', () {
      final view = barOf([chordOf(1, 'C#4', value: dottedQuarter)]);
      final items = chordItems(view);
      final ref = timedOf(view).ref;

      expect(
        (headsIn(items).single.owner! as ElementOwner).ref,
        NoteRef(ref, const NoteId(10)),
      );
      for (final other in items.where((d) => !headsIn([d]).contains(d))) {
        expect((other.owner! as ElementOwner).ref, ref);
      }
    });

    test('placed items carry their slice and staff', () {
      final plan = planOf(barOf([chordOf(1, 'C5')]));
      final items = placeChord(plan, slice: 2, staff: 1);

      expect(items.map((i) => i.slice), everyElement(2));
      expect(items.map((i) => i.staff), everyElement(1));
    });
  });
}
