import 'dart:math';

import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/bar_space.dart';
import 'package:score_layout/src/beams.dart';
import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/marks.dart';
import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/smufl_font.dart';
import 'package:score_layout/src/spacing.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_layout/src/text.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/random_edits.dart';
import '../../score_model/test/support.dart' as model;
import 'support/bars.dart';
import 'support/fake_measurer.dart';

const EngravingStyle style = EngravingStyle.standard;
const FakeMeasurer text = FakeMeasurer();
final SmuflFont font = style.font;

const double hair = 1e-9;

/// The least a mark stands clear of what it stacks on, and the most.
const double clear = 0.1;
const double near = 1;

/// The least two marks of one lane stand apart sideways.
const double wordSpace = 0.5;

/// How far apart the staves of a placed bar are, so no two share a y.
const double staffPitch = 80;

const NoteValue eighth = NoteValue.eighth;
const NoteValue half = NoteValue.half;
const NoteValue whole = NoteValue.whole;

const violin = Instrument(
  key: 'violin',
  program: 40,
  strings: [
    Pitch(Step.g, 3),
    Pitch(Step.d, 4),
    Pitch(Step.a, 4),
    Pitch(Step.e, 5),
  ],
);

/// A bar laid out and put at one stretch, with its content starting at x 0
/// and the top staff's top line at y 0.
typedef Placed = ({
  BarLayout bar,
  BarFrame frame,
  List<({int staff, Drawable drawable})> items,
  List<({TupletStub stub, List<Drawable> drawables})> tuplets,
});

Placed place(
  MeasureView view, {
  double stretch = 1,
  EngravingStyle style = style,
}) {
  final bar = layoutBar(view, style, text);
  final frame = BarFrame(
    left: 0,
    xs: sliceXs(bar.slices, stretch, bar.lead),
    tops: [for (var i = 0; i < bar.staves.length; i++) i * staffPitch],
  );
  return (
    bar: bar,
    frame: frame,
    items: [
      for (final item in bar.items)
        (staff: item.staff, drawable: frame.place(item)),
    ],
    tuplets: [
      for (final stub in bar.tuplets)
        (stub: stub, drawables: placeTuplet(stub, frame, style)),
    ],
  );
}

/// [chordOf] with marks. Entry `i` of [fingerings] and of [strings] is for
/// note `i`.
ChordEvent marked(
  int id,
  String pitches, {
  NoteValue value = NoteValue.quarter,
  Set<Articulation> articulations = const {},
  Ornament? ornament,
  Bowing? bowing,
  List<int?> fingerings = const [],
  List<int?> strings = const [],
}) {
  final chord = chordOf(id, pitches, value: value);
  return chord.copyWith(
    articulations: articulations,
    ornament: () => ornament,
    bowing: () => bowing,
    notes: Seq([
      for (final (i, note) in chord.notes.indexed)
        (note as PitchedNote).copyWith(
          fingering: () => fingerings.elementAtOrNull(i),
          string: () => strings.elementAtOrNull(i),
        ),
    ]),
  );
}

/// The view of a one-bar, one-staff score with marks on its staff and its
/// column.
MeasureView barWith(
  List<VoiceItem> one, {
  List<VoiceItem> two = const [],
  List<StaffDirection> directions = const [],
  List<TempoMark> tempos = const [],
  List<NavigationMark> navigation = const [],
  String? rehearsal,
  Instrument instrument = piano,
}) {
  final score = scoreOf([
    [staffOf(one, two: two, instrument: instrument)],
  ]);
  final column = score.measures.first;
  final changed = column
      .withStaff(column.staves.first.copyWith(directions: Seq(directions)))
      .copyWith(
        tempos: Seq(tempos),
        navigation: Seq(navigation),
        rehearsal: () => rehearsal,
      );
  return viewOf(score.copyWith(measures: Seq([changed])));
}

Tuplet tupletOf(
  int id,
  List<Content> members, {
  TupletRatio ratio = TupletRatio.triplet,
  NoteValue unit = eighth,
  TupletBracket bracket = TupletBracket.auto,
}) => Tuplet(
  id: TupletId(id),
  ratio: ratio,
  unit: unit,
  members: Seq(members),
  bracket: bracket,
);

EventRef refOf(int event) => EventRef(
  measure: barId(0),
  staff: const StaffId(2000),
  id: EventId(event),
);

Owner eventOwner(int event) => ElementOwner(refOf(event));

Owner noteOwner(int event, [int note = 0]) =>
    ElementOwner(NoteRef(refOf(event), NoteId(event * 10 + note)));

Iterable<GlyphDraw> glyphsOf(Placed placed) =>
    placed.items.map((item) => item.drawable).whereType<GlyphDraw>();

Iterable<TextDraw> textsOf(Placed placed) =>
    placed.items.map((item) => item.drawable).whereType<TextDraw>();

GlyphDraw glyphOf(Placed placed, Glyph glyph) =>
    glyphsOf(placed).singleWhere((draw) => draw.glyph == glyph);

TextDraw textOf(Placed placed, String text) =>
    textsOf(placed).singleWhere((draw) => draw.text == text);

/// The one glyph [event] owns that is no part of its chord or rest.
GlyphDraw markOf(Placed placed, int event) => glyphsOf(
  placed,
).singleWhere((draw) => draw.owner == eventOwner(event) && isMark(draw));

Box headOf(Placed placed, int event, [int note = 0]) =>
    glyphsOf(placed)
        .singleWhere(
          (draw) =>
              draw.owner == noteOwner(event, note) &&
              draw.glyph.name.startsWith('notehead'),
        )
        .bounds;

Box stemOf(Placed placed, int event) => placed.items
    .map((item) => item.drawable)
    .whereType<LineDraw>()
    .singleWhere(
      (line) => line.owner == eventOwner(event) && line.from.x == line.to.x,
    )
    .bounds;

double centreOf(Box box) => (box.left + box.right) / 2;

double middleOf(Box box) => (box.top + box.bottom) / 2;

const List<String> markGlyphs = [
  'artic',
  'fermata',
  'ornament',
  'strings',
  'fingering',
  'guitarString',
  'dynamic',
  'segno',
  'coda',
  'csym',
  'metNote',
  'metAugmentationDot',
];

/// Whether [drawable] is part of a mark. A bar's items hold no other text.
bool isMark(Drawable drawable) => switch (drawable) {
  TextDraw() => true,
  GlyphDraw(:final glyph) => markGlyphs.any(glyph.name.startsWith),
  _ => false,
};

typedef MarkBox = ({int staff, Box box, String what});

/// The box of every part of every mark of [placed] among its items, and one
/// box per tuplet, round its number and its bracket.
List<MarkBox> markBoxes(Placed placed) => [
  for (final (:staff, :drawable) in placed.items)
    if (isMark(drawable))
      (staff: staff, box: drawable.bounds, what: '$drawable'),
  for (final (:stub, :drawables) in placed.tuplets)
    (
      staff: stub.first.staff,
      box: drawables
          .map((drawable) => drawable.bounds)
          .reduce((a, b) => a.union(b)),
      what: 'tuplet ${stub.digits} of ${stub.owner}',
    ),
];

bool overlap(Box a, Box b) =>
    min(a.right, b.right) - max(a.left, b.left) > hair &&
    min(a.bottom, b.bottom) - max(a.top, b.top) > hair;

void expectNoOverlap(List<MarkBox> boxes, String where) {
  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      final a = boxes[i];
      final b = boxes[j];
      expect(
        a.staff == b.staff && overlap(a.box, b.box),
        isFalse,
        reason: '$where: ${a.what} at ${a.box} meets ${b.what} at ${b.box}',
      );
    }
  }
}

void expectAbove(Box mark, Box of, String reason) => expect(
  min(0, of.top) - mark.bottom,
  inInclusiveRange(clear, near),
  reason: reason,
);

void expectBelow(Box mark, Box of, String reason) => expect(
  mark.top - max(staffHeight, of.bottom),
  inInclusiveRange(clear, near),
  reason: reason,
);

const Map<Articulation, (Glyph above, Glyph below)> articulationGlyphs = {
  Articulation.staccato: (Glyph.articStaccatoAbove, Glyph.articStaccatoBelow),
  Articulation.staccatissimo: (
    Glyph.articStaccatissimoAbove,
    Glyph.articStaccatissimoBelow,
  ),
  Articulation.tenuto: (Glyph.articTenutoAbove, Glyph.articTenutoBelow),
  Articulation.accent: (Glyph.articAccentAbove, Glyph.articAccentBelow),
  Articulation.marcato: (Glyph.articMarcatoAbove, Glyph.articMarcatoBelow),
  Articulation.harmonic: (Glyph.stringsHarmonic, Glyph.stringsHarmonic),
};

/// Every chord of [score] with a reference to it, tuplet members included.
List<(EventRef, ChordEvent)> chordsOf(Score score) {
  Iterable<ChordEvent> flat(Iterable<VoiceItem> items) => items.expand(
    (item) => switch (item) {
      ChordEvent() => [item],
      Tuplet(:final members) => flat(members),
      _ => const <ChordEvent>[],
    },
  );
  return [
    for (final column in score.measures)
      for (final staff in column.staves)
        for (final voice in staff.voices)
          for (final chord in flat(voice.items))
            (
              EventRef(measure: column.id, staff: staff.staff, id: chord.id),
              chord,
            ),
  ];
}

/// [score] with one more mark on one of its chords.
Score withOneMoreMark(Score score, Random random) {
  final chords = chordsOf(score);
  if (chords.isEmpty) {
    return score;
  }
  final (ref, chord) = pick(random, chords);
  final note = NoteRef(ref, pick(random, chord.notes.toList()).id);
  return edited(
    score,
    pick(random, [
      SetArticulation(ref, pick(random, Articulation.values), present: true),
      SetOrnament(ref, pick(random, Ornament.values)),
      SetBowing(ref, pick(random, Bowing.values)),
      SetFingering(note, random.nextInt(5)),
      SetString(note, random.nextInt(2)),
    ]),
  );
}

bool hasMarks(Event event) =>
    event.articulations.isNotEmpty ||
    (event is ChordEvent && (event.ornament != null || event.bowing != null));

void main() {
  group('articulations', () {
    test('a staccato of a voice alone sits in the first space clear of its '
        'head, on the note side', () {
      for (final (pitch, glyph, y) in [
        ('C5', Glyph.articStaccatoAbove, yOfStep(7)),
        ('B4', Glyph.articStaccatoAbove, yOfStep(7)),
        ('A4', Glyph.articStaccatoBelow, yOfStep(1)),
      ]) {
        final placed = place(
          barWith([
            marked(1, pitch, articulations: {Articulation.staccato}),
          ]),
        );
        final dot = markOf(placed, 1);

        expect(dot.glyph, glyph, reason: pitch);
        expect(middleOf(dot.bounds), closeTo(y, hair), reason: pitch);
        expect(
          centreOf(dot.bounds),
          closeTo(centreOf(headOf(placed, 1)), hair),
          reason: pitch,
        );
      }
    });

    test('a staccato and a tenuto inside the staff take one space each, and '
        'the next mark stacks outside the staff', () {
      final placed = place(
        barWith([
          marked(
            1,
            'D5',
            articulations: {
              Articulation.staccato,
              Articulation.tenuto,
              Articulation.accent,
            },
          ).copyWith(stem: StemDirection.up),
        ]),
      );
      final dot = glyphOf(placed, Glyph.articStaccatoBelow).bounds;
      final line = glyphOf(placed, Glyph.articTenutoBelow).bounds;
      final accent = glyphOf(placed, Glyph.articAccentBelow).bounds;

      expect(middleOf(dot), closeTo(yOfStep(3), hair));
      expect(middleOf(line), closeTo(yOfStep(1), hair));
      expect(accent.top - staffHeight, inInclusiveRange(clear, near));
    });

    test('a staccato with no space left inside the staff stacks outside '
        'it, close under its head', () {
      for (final pitch in ['F4', 'E4']) {
        final placed = place(
          barWith([
            marked(1, pitch, articulations: {Articulation.staccato}),
          ]),
        );
        final dot = glyphOf(placed, Glyph.articStaccatoBelow).bounds;

        expect(
          dot.top - max(staffHeight, headOf(placed, 1).bottom),
          inInclusiveRange(clear, 0.5),
          reason: pitch,
        );
      }
    });

    for (final MapEntry(key: kind, value: (above, below))
        in articulationGlyphs.entries) {
      test('a ${kind.name} of a voice alone is on the note side, centred on '
          'its head', () {
        final placed = place(
          barWith([
            marked(1, 'A4', articulations: {kind}),
            marked(2, 'C5', articulations: {kind}),
          ]),
        );
        final up = markOf(placed, 1);
        final down = markOf(placed, 2);
        final low = headOf(placed, 1);
        final high = headOf(placed, 2);

        expect(centreOf(up.bounds), closeTo(centreOf(low), hair));
        expect(centreOf(down.bounds), closeTo(centreOf(high), hair));
        expect(down.glyph, above);
        expect(down.bounds.bottom, lessThanOrEqualTo(high.top));
        if (kind == Articulation.harmonic) {
          expectAbove(up.bounds, stemOf(placed, 1), 'over the stem');
        } else {
          expect(up.glyph, below);
          expect(up.bounds.top, greaterThanOrEqualTo(low.bottom));
        }
      });

      test('a ${kind.name} of one of two voices is on the stem side, beyond '
          'the stem', () {
        final placed = place(
          barWith(
            [
              marked(1, 'C5', articulations: {kind}),
            ],
            two: [
              marked(2, 'E4', articulations: {kind}),
            ],
          ),
        );
        final one = markOf(placed, 1);
        final two = markOf(placed, 2);

        expect(one.glyph, above);
        expect(two.glyph, below);
        expect(
          centreOf(one.bounds),
          closeTo(centreOf(headOf(placed, 1)), hair),
        );
        expect(
          centreOf(two.bounds),
          closeTo(centreOf(headOf(placed, 2)), hair),
        );
        expectAbove(one.bounds, stemOf(placed, 1), 'voice one');
        expectBelow(two.bounds, stemOf(placed, 2), 'voice two');
      });
    }

    test('the articulations of one chord stack away from it in a fixed '
        'order, under its ornament, its bowing and its fermata', () {
      final placed = place(
        barWith(
          [
            marked(
              1,
              'C5',
              articulations: Articulation.values.toSet(),
              ornament: Ornament.turn,
              bowing: Bowing.down,
            ),
          ],
          two: [chordOf(2, 'E4')],
        ),
      );
      final stack = [
        for (final glyph in [
          Glyph.articStaccatoAbove,
          Glyph.articStaccatissimoAbove,
          Glyph.articTenutoAbove,
          Glyph.articAccentAbove,
          Glyph.articMarcatoAbove,
          Glyph.stringsHarmonic,
          Glyph.ornamentTurn,
          Glyph.stringsDownBow,
          Glyph.fermataAbove,
        ])
          glyphOf(placed, glyph).bounds,
      ];

      expectAbove(stack.first, stemOf(placed, 1), 'the first mark');
      for (var i = 1; i < stack.length; i++) {
        expect(
          stack[i - 1].top - stack[i].bottom,
          inInclusiveRange(clear, near),
          reason: 'mark $i over mark ${i - 1}',
        );
      }
    });
  });

  group('fermatas', () {
    test('a fermata stands above the staff, centred on its note', () {
      final placed = place(
        barWith([
          marked(1, 'A4', articulations: {Articulation.fermata}),
        ]),
      );
      final fermata = markOf(placed, 1);

      expect(fermata.glyph, Glyph.fermataAbove);
      expect(
        centreOf(fermata.bounds),
        closeTo(centreOf(headOf(placed, 1)), hair),
      );
      expectAbove(fermata.bounds, stemOf(placed, 1), 'over the stem');
    });

    test('the fermata of the lower of two voices is inverted, below the '
        'staff', () {
      final placed = place(
        barWith(
          [chordOf(1, 'C5')],
          two: [
            marked(2, 'E4', articulations: {Articulation.fermata}),
          ],
        ),
      );
      final fermata = markOf(placed, 2);

      expect(fermata.glyph, Glyph.fermataBelow);
      expect(
        centreOf(fermata.bounds),
        closeTo(centreOf(headOf(placed, 2)), hair),
      );
      expectBelow(fermata.bounds, stemOf(placed, 2), 'under the stem');
    });

    test('a rest holds its fermata over its middle, and a hidden rest draws '
        'none', () {
      const marks = {Articulation.fermata};
      final placed = place(
        barWith(const [
          RestEvent(
            id: EventId(1),
            value: NoteValue.quarter,
            articulations: marks,
          ),
          RestEvent(
            id: EventId(2),
            value: NoteValue.quarter,
            articulations: marks,
            hidden: true,
          ),
        ]),
      );
      final rest = glyphOf(placed, Glyph.restQuarter).bounds;
      final fermata = glyphOf(placed, Glyph.fermataAbove);

      expect(fermata.owner, eventOwner(1));
      expect(centreOf(fermata.bounds), closeTo(centreOf(rest), hair));
      expectAbove(fermata.bounds, rest, 'over the staff');
    });

    test('a measure rest keeps its fermata over it at any stretch, and its '
        'bar does not fold into a multi-measure rest', () {
      MeasureView bar(Set<Articulation> marks) => viewOf(
        scoreOf([
          [
            staffOf([chordOf(1, 'A4', value: whole)]),
          ],
          [
            staffOf([
              MeasureRest(
                id: const EventId(2),
                span: Meter.fourFour.length,
                articulations: marks,
              ),
            ]),
          ],
        ]),
        1,
      );

      for (final stretch in [1.0, 2.0, 3.0]) {
        final placed = place(
          bar({Articulation.fermata}),
          stretch: stretch,
        );
        final rest = glyphOf(placed, Glyph.restWhole).bounds;
        final fermata = glyphOf(placed, Glyph.fermataAbove).bounds;

        expect(centreOf(fermata), closeTo(centreOf(rest), hair));
        expect(-fermata.bottom, inInclusiveRange(clear, near));
        expect(placed.bar.restOnly, isFalse);
      }
      expect(place(bar(const {})).bar.restOnly, isTrue);
      expect(
        place(bar(const {Articulation.staccato})).bar.restOnly,
        isTrue,
        reason: 'a rest draws no staccato, so a fold hides nothing',
      );
    });

    test('a mark later in the bar stacks outside a measure rest\'s fermata, '
        'which a stretch moves along the bar', () {
      final placed = place(
        barWith(
          [
            MeasureRest(
              id: const EventId(1),
              span: Meter.fourFour.length,
              articulations: const {Articulation.fermata},
            ),
          ],
          directions: [TextMark(at(3, 4), 'a')],
        ),
      );
      final fermata = glyphOf(placed, Glyph.fermataAbove).bounds;
      final words = textOf(placed, 'a').bounds;

      expect(words.left, greaterThan(fermata.right));
      expectAbove(words, fermata, 'above the fermata');
    });
  });

  group('ornaments', () {
    const glyphs = {
      Ornament.trill: Glyph.ornamentTrill,
      Ornament.mordent: Glyph.ornamentMordent,
      Ornament.invertedMordent: Glyph.ornamentShortTrill,
      Ornament.turn: Glyph.ornamentTurn,
      Ornament.invertedTurn: Glyph.ornamentTurnInverted,
    };

    for (final ornament in Ornament.values) {
      test('a ${ornament.name} stands above the staff, centred on its '
          'note', () {
        final placed = place(barWith([marked(1, 'A4', ornament: ornament)]));
        final sign = markOf(placed, 1);

        expect(sign.glyph, glyphs[ornament]);
        expect(
          centreOf(sign.bounds),
          closeTo(centreOf(headOf(placed, 1)), hair),
        );
        expectAbove(sign.bounds, stemOf(placed, 1), 'over the stem');
      });
    }

    test('a trill on the chord a trill line starts on is drawn once', () {
      Iterable<GlyphDraw> trillsOf(Score score) =>
          SheetLayout(
                score,
                width: 120,
                text: text,
              )
              .systemAt(0)
              .drawables
              .whereType<GlyphDraw>()
              .where(
                (draw) => draw.glyph == Glyph.ornamentTrill,
              );
      Score scoreOf(Ornament? ornament) => model.fill(
        model.blankScore(parts: const [model.clarinet], bars: 1),
        0,
        [
          model
              .chordOf(1, 'C5', value: half)
              .copyWith(ornament: () => ornament),
          model.chordOf(2, 'D5', value: half),
        ],
      );
      Score lined(Score score) => model.withSpanner(
        score,
        const TrillLine(),
        model.pointAt(score, 0, Moment.zero),
        model.pointAt(score, 0, at(2, 4)),
      );

      expect(trillsOf(scoreOf(Ornament.trill)), hasLength(1));
      expect(trillsOf(lined(scoreOf(null))), hasLength(1));
      expect(trillsOf(lined(scoreOf(Ornament.trill))), hasLength(1));
      expect(trillsOf(lined(scoreOf(Ornament.turn))), hasLength(1));
    });
  });

  group('string marks', () {
    test('an up-bow and a down-bow stand above the staff, centred on their '
        'notes', () {
      final placed = place(
        barWith([
          marked(1, 'A4', bowing: Bowing.up),
          marked(2, 'C5', bowing: Bowing.down),
        ]),
      );
      final up = markOf(placed, 1);
      final down = markOf(placed, 2);

      expect(up.glyph, Glyph.stringsUpBow);
      expect(down.glyph, Glyph.stringsDownBow);
      expect(centreOf(up.bounds), closeTo(centreOf(headOf(placed, 1)), hair));
      expect(centreOf(down.bounds), closeTo(centreOf(headOf(placed, 2)), hair));
      expectAbove(up.bounds, stemOf(placed, 1), 'over the stem');
      expectAbove(down.bounds, headOf(placed, 2), 'over the staff');
    });

    test('a fingering stands above its chord, and the fingerings of several '
        'heads stack in head order', () {
      final placed = place(
        barWith([
          marked(1, 'C4 E4 G4', fingerings: [1, 3, 5]),
        ]),
      );
      final fingers = [
        for (final glyph in [
          Glyph.fingering1,
          Glyph.fingering3,
          Glyph.fingering5,
        ])
          glyphOf(placed, glyph),
      ];

      expect(
        [for (final finger in fingers) finger.owner],
        [for (var note = 0; note < 3; note++) noteOwner(1, note)],
      );
      expectAbove(fingers.first.bounds, stemOf(placed, 1), 'over the stem');
      for (var i = 1; i < 3; i++) {
        expect(
          fingers[i - 1].bounds.top - fingers[i].bounds.bottom,
          inInclusiveRange(clear, near),
        );
      }
    });

    test('the fingerings of the lower of two voices stack below the staff, '
        'the highest head\'s on top', () {
      final placed = place(
        barWith(
          [chordOf(1, 'C5')],
          two: [
            marked(2, 'E4 G4', fingerings: [1, 3]),
          ],
        ),
      );
      final low = glyphOf(placed, Glyph.fingering1).bounds;
      final high = glyphOf(placed, Glyph.fingering3).bounds;

      expectBelow(high, stemOf(placed, 2), 'under the stem');
      expect(low.top - high.bottom, inInclusiveRange(clear, near));
    });

    test('a string number counts from the highest string, in a circle or as '
        'a roman numeral', () {
      final view = barWith([
        marked(1, 'E5', strings: [3]),
        marked(2, 'G3', strings: [0]),
      ], instrument: violin);
      final circled = place(view);
      final roman = place(
        view,
        style: const EngravingStyle(stringNumbers: StringNumbers.roman),
      );

      final first = glyphOf(circled, Glyph.guitarString1);
      final fourth = glyphOf(circled, Glyph.guitarString4);
      expect(first.owner, noteOwner(1));
      expect(fourth.owner, noteOwner(2));
      expect(
        centreOf(fourth.bounds),
        closeTo(centreOf(headOf(circled, 2)), hair),
      );
      expectAbove(first.bounds, headOf(circled, 1), 'over the staff');
      expectAbove(fourth.bounds, stemOf(circled, 2), 'over the stem');

      expect(glyphsOf(roman).where(isMark), isEmpty);
      expect(textOf(roman, 'I').owner, noteOwner(1));
      final numeral = textOf(roman, 'IV');
      expect(numeral.spec, style.specOf(TextRole.stringNumber));
      expect(
        centreOf(numeral.bounds),
        closeTo(centreOf(headOf(roman, 2)), hair),
      );
      expectAbove(numeral.bounds, stemOf(roman, 2), 'over the stem');
    });

    test('a string the instrument does not have draws nothing', () {
      final placed = place(
        barWith([
          marked(1, 'A4', strings: [2]),
        ]),
      );

      expect(markBoxes(placed), isEmpty);
    });

    test('a fingering, a string number and a bowing of one chord stack in '
        'that order', () {
      final placed = place(
        barWith([
          marked(1, 'A4', fingerings: [2], strings: [2], bowing: Bowing.down),
        ], instrument: violin),
      );
      final finger = glyphOf(placed, Glyph.fingering2).bounds;
      final string = glyphOf(placed, Glyph.guitarString2).bounds;
      final bow = glyphOf(placed, Glyph.stringsDownBow).bounds;

      expectAbove(finger, stemOf(placed, 1), 'over the stem');
      expect(finger.top - string.bottom, inInclusiveRange(clear, near));
      expect(string.top - bow.bottom, inInclusiveRange(clear, near));
    });
  });

  group('directions', () {
    test('a dynamic stands below the staff with its optical centre under '
        'the middle of the notehead', () {
      final placed = place(
        barWith(
          [chordOf(1, 'A4', value: half), chordOf(2, 'F4', value: half)],
          directions: [
            const DynamicMark(Moment.zero, Dynamic.mf),
            DynamicMark(at(2, 4), Dynamic.p),
          ],
        ),
      );

      for (final (glyph, event) in [
        (Glyph.dynamicMF, 1),
        (Glyph.dynamicPiano, 2),
      ]) {
        final dynamic = glyphOf(placed, glyph);
        expect(
          dynamic.origin.x + font[glyph].anchors[GlyphAnchor.opticalCenter]!.x,
          closeTo(centreOf(headOf(placed, event)), hair),
        );
        expect(dynamic.owner, isNull);
        expectBelow(dynamic.bounds, headOf(placed, event), '$glyph');
      }
    });

    test('every dynamic level prints one glyph of its own', () {
      final glyphs = {
        for (final level in Dynamic.values)
          level: glyphsOf(
            place(
              barWith(
                [chordOf(1, 'A4')],
                directions: [DynamicMark(Moment.zero, level)],
              ),
            ),
          ).where(isMark).single.glyph,
      };

      expect(glyphs.values.toSet(), hasLength(Dynamic.values.length));
      expect(glyphs[Dynamic.f], Glyph.dynamicForte);
      expect(glyphs[Dynamic.pp], Glyph.dynamicPP);
      expect(glyphs[Dynamic.fp], Glyph.dynamicFortePiano);
      expect(glyphs[Dynamic.sfz], Glyph.dynamicSforzato);
    });

    test('a text mark stands above the staff, or below it when stored so, '
        'from its slice on', () {
      final placed = place(
        barWith(
          [chordOf(1, 'A4', value: half), restOf(2, half)],
          directions: [
            const TextMark(Moment.zero, ''),
            TextMark(at(2, 4), 'dolce'),
            TextMark(at(2, 4), 'sotto', above: false),
          ],
        ),
      );
      final above = textOf(placed, 'dolce');
      final below = textOf(placed, 'sotto');

      expect(textsOf(placed), hasLength(2));
      for (final mark in [above, below]) {
        expect(mark.spec, style.specOf(TextRole.expression));
        expect(mark.origin.x, closeTo(placed.frame.xs[1], hair));
        expect(mark.bounds.left, closeTo(placed.frame.xs[1], hair));
      }
      expect(-above.bounds.bottom, inInclusiveRange(clear, near));
      expect(below.bounds.top - staffHeight, inInclusiveRange(clear, near));
    });

    test('a chord symbol stands above the staff as its root, its '
        'accidental, its quality and its bass', () {
      final placed = place(
        barWith(
          [chordOf(1, 'A4', value: whole)],
          directions: const [
            ChordSymbol(
              Moment.zero,
              root: PitchName(Step.b, Alter.flat),
              quality: 'm7',
              bass: PitchName(Step.f, Alter.sharp),
            ),
          ],
        ),
      );
      final spec = style.specOf(TextRole.chordSymbol);
      final parts = [
        for (final (staff: _, :drawable) in placed.items)
          if (isMark(drawable)) drawable,
      ];

      expect(
        [
          for (final part in parts)
            switch (part) {
              TextDraw(:final text) => text,
              GlyphDraw(:final glyph) => glyph,
              _ => null,
            },
        ],
        [
          'B',
          Glyph.csymAccidentalFlat,
          'm7',
          '/',
          'F',
          Glyph.csymAccidentalSharp,
        ],
      );
      expect(parts.first.bounds.left, closeTo(placed.frame.xs[0], hair));
      for (var i = 1; i < parts.length; i++) {
        expect(
          parts[i].bounds.left,
          greaterThanOrEqualTo(parts[i - 1].bounds.right - hair),
          reason: 'part $i follows part ${i - 1}',
        );
      }
      for (final part in parts) {
        switch (part) {
          case TextDraw():
            expect(part.spec, spec);
            expect(
              part.origin.y,
              closeTo(parts.first.bounds.bottom - 0.2 * spec.size, hair),
            );
          case GlyphDraw():
            expect(part.scale, spec.size / 4);
            expect(part.bounds.height, lessThan(spec.size));
          default:
        }
        expect(part.bounds.bottom, lessThanOrEqualTo(-clear));
      }
    });

    test('a chord symbol on a transposing staff is spelled as stored, or '
        'for the player when the style asks', () {
      final view = barWith(
        [chordOf(1, 'A4', value: whole)],
        directions: const [
          ChordSymbol(
            Moment.zero,
            root: PitchName(Step.b, Alter.flat),
            quality: 'maj7',
            bass: PitchName(Step.d),
          ),
        ],
        instrument: model.clarinet.instrument,
      );
      List<String> lettersOf(Placed placed) => [
        for (final draw in textsOf(placed)) draw.text,
      ];
      final stored = place(view);
      final written = place(
        view,
        style: const EngravingStyle(chordSymbols: ChordSymbolSpelling.written),
      );

      expect(lettersOf(stored), ['B', 'maj7', '/', 'D']);
      expect(
        glyphsOf(stored).where(isMark).single.glyph,
        Glyph.csymAccidentalFlat,
      );
      expect(lettersOf(written), ['C', 'maj7', '/', 'E']);
      expect(glyphsOf(written).where(isMark), isEmpty);
    });

    test('a direction where no note starts gets a slice of its own', () {
      final plain = place(barWith([chordOf(1, 'A4', value: whole)]));
      final placed = place(
        barWith(
          [chordOf(1, 'A4', value: whole)],
          directions: [TextMark(at(2, 4), 'cresc.')],
        ),
      );
      final mark = textOf(placed, 'cresc.');

      expect(placed.bar.slices.length, plain.bar.slices.length + 1);
      expect(mark.bounds.left, greaterThan(headOf(placed, 1).right));
      expect(mark.bounds.right, lessThanOrEqualTo(placed.frame.right + hair));
    });
  });

  group('system marks', () {
    test('a tempo mark prints its words, its note and its number in a row '
        'above the top staff', () {
      final placed = place(
        barWith(
          [chordOf(1, 'A4', value: whole)],
          tempos: [
            TempoMark(
              offset: Moment.zero,
              tempo: Tempo(96, beat: NoteValue.quarter.dotted),
              text: 'Allegro',
            ),
          ],
        ),
      );
      final spec = style.specOf(TextRole.tempo);
      final words = textOf(placed, 'Allegro');
      final note = glyphOf(placed, Glyph.metNoteQuarterUp);
      final dot = glyphOf(placed, Glyph.metAugmentationDot);
      final number = textOf(placed, '= 96');

      expect(words.spec, spec);
      expect(number.spec, TextSpec(size: spec.size));
      expect(words.bounds.left, closeTo(placed.frame.xs[0], hair));
      expect(note.scale, spec.size / 4);
      expect(dot.scale, spec.size / 4);
      expect(note.bounds.bottom, closeTo(words.origin.y, hair));
      expect(number.origin.y, words.origin.y);
      final row = [words.bounds, note.bounds, dot.bounds, number.bounds];
      for (var i = 1; i < row.length; i++) {
        expect(
          row[i].left - row[i - 1].right,
          inInclusiveRange(clear, near),
          reason: 'part $i follows part ${i - 1}',
        );
      }
      for (final part in row) {
        expect(part.bottom, lessThanOrEqualTo(-clear));
      }
      expect(-words.bounds.bottom, lessThanOrEqualTo(near));
    });

    test('a tempo mark without its metronome prints its words alone, and a '
        'fractional tempo keeps its fraction', () {
      final placed = place(
        barWith(
          [chordOf(1, 'A4', value: half), chordOf(2, 'A4', value: half)],
          tempos: [
            const TempoMark(
              offset: Moment.zero,
              tempo: Tempo(50),
              text: 'Largo',
              showMetronome: false,
            ),
            TempoMark(
              offset: at(2, 4),
              tempo: const Tempo(96.5, beat: half),
            ),
          ],
        ),
      );

      expect(
        [for (final draw in textsOf(placed)) draw.text],
        [
          'Largo',
          '= 96.5',
        ],
      );
      expect(
        [for (final draw in glyphsOf(placed).where(isMark)) draw.glyph],
        [Glyph.metNoteHalfUp],
      );
      expect(
        glyphOf(placed, Glyph.metNoteHalfUp).origin.x,
        closeTo(placed.frame.xs[1], hair),
      );
    });

    test('a rehearsal mark stands in its box at the start of the bar, '
        'outside every other mark', () {
      final placed = place(
        barWith(
          [chordOf(1, 'A4', value: whole)],
          tempos: const [
            TempoMark(offset: Moment.zero, tempo: Tempo(120), text: 'Vivo'),
          ],
          navigation: const [Segno()],
          rehearsal: 'A',
        ),
      );
      final mark = textOf(placed, 'A');
      final spec = style.specOf(TextRole.rehearsal);
      final letter = text.measure('A', spec);
      final inset = mark.origin.x - mark.bounds.left;

      expect(mark.enclosed, isTrue);
      expect(mark.spec, spec);
      expect(mark.bounds.left, closeTo(0, hair));
      expect(inset, greaterThan(font.defaults.textEnclosureThickness + clear));
      expect(mark.bounds.width, closeTo(letter.width + 2 * inset, hair));
      expect(
        mark.bounds.height,
        closeTo(letter.ascent + letter.descent + 2 * inset, hair),
      );
      expect(
        mark.origin.y,
        closeTo(mark.bounds.bottom - inset - letter.descent, hair),
      );
      for (final under in [
        textOf(placed, 'Vivo').bounds,
        glyphOf(placed, Glyph.segno).bounds,
      ]) {
        expect(mark.bounds.bottom, lessThanOrEqualTo(under.top - clear));
      }
      expect(
        textsOf(placed).where((draw) => draw.enclosed),
        [mark],
      );
    });

    for (final (mark, glyph) in const [
      (Segno(), Glyph.segno),
      (Coda(), Glyph.coda),
    ]) {
      test('a ${glyph.name} stands above the top staff at the start of the '
          'bar', () {
        final placed = place(
          barWith([chordOf(1, 'A4', value: whole)], navigation: [mark]),
        );
        final sign = glyphOf(placed, glyph);

        expect(sign.bounds.left, closeTo(0, hair));
        expect(sign.owner, isNull);
        expect(-sign.bounds.bottom, inInclusiveRange(clear, near));
      });
    }

    for (final (mark, label) in const [
      (Fine(), 'Fine'),
      (ToCoda(), 'To Coda'),
      (Jump(JumpTarget.start), 'D.C.'),
      (Jump(JumpTarget.segno, then: JumpThen.toCoda), 'D.S. al Coda'),
      (
        Jump(JumpTarget.start, then: JumpThen.toFine, text: 'Да капо'),
        'Да капо',
      ),
    ]) {
      test('"$label" stands above the top staff, ending half a space before '
          'the end of its bar', () {
        final placed = place(
          barWith([chordOf(1, 'A4', value: whole)], navigation: [mark]),
        );
        final words = textsOf(placed).single;

        expect(words.text, label);
        expect(words.spec, style.specOf(TextRole.navigation));
        expect(words.bounds.right, closeTo(placed.frame.right - 0.5, hair));
        expect(-words.bounds.bottom, inInclusiveRange(clear, near));
      });
    }

    test('system marks stand over the top staff alone', () {
      final score = scoreOf([
        [
          staffOf([chordOf(1, 'A4', value: whole)]),
          staffOf([chordOf(2, 'C3', value: whole)], clef: Clef.bass),
        ],
      ]);
      final column = score.measures.first.copyWith(
        tempos: Seq(const [
          TempoMark(offset: Moment.zero, tempo: Tempo(72), text: 'Lento'),
        ]),
        navigation: Seq(const [Coda(), Fine()]),
        rehearsal: () => 'B',
      );
      final placed = place(
        viewOf(score.copyWith(measures: Seq([column]))),
      );
      final marks = markBoxes(placed);

      expect(marks, hasLength(6));
      for (final mark in marks) {
        expect(mark.staff, 0, reason: mark.what);
        expect(mark.box.bottom, lessThanOrEqualTo(-clear), reason: mark.what);
      }
    });
  });

  group('tuplets', () {
    test('a triplet under one beam prints its number alone, outside the '
        'beam and centred on its notes', () {
      final placed = place(
        barWith([
          tupletOf(50, [
            for (var i = 1; i <= 3; i++) chordOf(i, 'A4', value: eighth),
          ]),
        ]),
      );
      final (:stub, :drawables) = placed.tuplets.single;
      final number = drawables.single as GlyphDraw;
      final beam = placeBeam(
        placed.bar.beams.single,
        placed.frame,
        style,
      ).map((part) => part.bounds).reduce((a, b) => a.union(b));

      expect(number.glyph, Glyph.tuplet3);
      expect(number.owner, eventOwner(1));
      expect(stub.side, Side.above);
      expect(beam.top - number.bounds.bottom, inInclusiveRange(clear, near));
      expect(
        centreOf(number.bounds),
        closeTo((headOf(placed, 1).left + headOf(placed, 3).right) / 2, hair),
      );
    });

    test('a triplet of quarters prints a bracket round its number, from '
        'its first note to its last, with hooks to the notes', () {
      final placed = place(
        barWith([
          tupletOf(50, unit: NoteValue.quarter, [
            for (var i = 1; i <= 3; i++) chordOf(i, 'C5'),
          ]),
        ]),
      );
      final (:stub, :drawables) = placed.tuplets.single;
      final number = drawables.whereType<GlyphDraw>().single.bounds;
      final lines = drawables.whereType<LineDraw>().toList();
      final [leftHook, left, right, rightHook] = lines;
      final first = headOf(placed, 1);
      final last = headOf(placed, 3);
      final thickness = font.defaults.tupletBracketThickness;

      expect(stub.side, Side.below);
      expect(drawables, hasLength(5));
      for (final line in lines) {
        expect(line.thickness, thickness);
        expect(line.owner, eventOwner(1));
      }
      expect(left.from.x, closeTo(first.left, hair));
      expect(right.to.x, closeTo(last.right, hair));
      expect(left.from.y, left.to.y);
      expect(right.from.y, left.from.y);
      expect(middleOf(number), closeTo(left.from.y, hair));
      expect(number.left - left.to.x, inInclusiveRange(clear, near));
      expect(right.from.x - number.right, inInclusiveRange(clear, near));
      expect(centreOf(number), closeTo((first.left + last.right) / 2, hair));
      expect(
        left.from.y - max(staffHeight, stemOf(placed, 1).bottom),
        greaterThanOrEqualTo(clear),
      );
      for (final (hook, x) in [
        (leftHook, first.left),
        (rightHook, last.right),
      ]) {
        expect(hook.from.x, hook.to.x);
        expect(hook.bounds.left, greaterThanOrEqualTo(first.left - hair));
        expect(hook.bounds.right, lessThanOrEqualTo(last.right + hair));
        expect((centreOf(hook.bounds) - x).abs(), closeTo(thickness / 2, hair));
        expect(hook.bounds.bottom, closeTo(left.bounds.bottom, hair));
        expect(left.from.y - hook.bounds.top, greaterThan(2 * thickness));
      }
    });

    for (final stretch in [1.0, 2.0, 3.0]) {
      test('at stretch $stretch a tuplet\'s ends are on its first and last '
          'notes, and its number is midway', () {
        final placed = place(
          barWith([
            chordOf(9, 'C5'),
            tupletOf(50, unit: NoteValue.quarter, [
              chordOf(1, 'C5'),
              chordOf(2, 'E5'),
              restOf(3, NoteValue.quarter),
            ]),
          ]),
          stretch: stretch,
        );
        final drawables = placed.tuplets.single.drawables;
        final number = drawables.whereType<GlyphDraw>().single.bounds;
        final lines = drawables.whereType<LineDraw>().toList();
        final from = headOf(placed, 1).left;
        final to = glyphOf(placed, Glyph.restQuarter).bounds.right;

        expect(lines, hasLength(4));
        expect(lines[1].from.x, closeTo(from, hair));
        expect(lines[2].to.x, closeTo(to, hair));
        expect(centreOf(number), closeTo((from + to) / 2, hair));
      });
    }

    test('a tuplet prints its ratio when its number alone would not say '
        'it', () {
      List<Glyph> digitsOf(TupletRatio ratio) =>
          place(
                barWith([
                  tupletOf(50, ratio: ratio, [
                    for (var i = 1; i <= ratio.actual; i++)
                      chordOf(i, 'A4', value: eighth),
                  ]),
                ]),
              ).tuplets.single.drawables
              .whereType<GlyphDraw>()
              .map(
                (draw) => draw.glyph,
              )
              .toList();

      expect(digitsOf(TupletRatio.triplet), [Glyph.tuplet3]);
      expect(digitsOf(TupletRatio.duplet), [Glyph.tuplet2]);
      expect(digitsOf(TupletRatio.quintuplet), [Glyph.tuplet5]);
      expect(digitsOf(const TupletRatio(4, 3)), [Glyph.tuplet4]);
      expect(digitsOf(const TupletRatio(8, 6)), [Glyph.tuplet8]);
      expect(digitsOf(const TupletRatio(5, 3)), [
        Glyph.tuplet5,
        Glyph.tupletColon,
        Glyph.tuplet3,
      ]);
      expect(digitsOf(const TupletRatio(7, 8)), [
        Glyph.tuplet7,
        Glyph.tupletColon,
        Glyph.tuplet8,
      ]);
    });

    test('a stored bracket is drawn over a beam, and a hidden one is left '
        'off unbeamed notes', () {
      Iterable<LineDraw> bracketOf(NoteValue unit, TupletBracket bracket) =>
          place(
            barWith([
              tupletOf(50, unit: unit, bracket: bracket, [
                for (var i = 1; i <= 3; i++) chordOf(i, 'A4', value: unit),
              ]),
            ]),
          ).tuplets.single.drawables.whereType<LineDraw>();

      expect(bracketOf(eighth, TupletBracket.auto), isEmpty);
      expect(bracketOf(eighth, TupletBracket.shown), hasLength(4));
      expect(bracketOf(NoteValue.quarter, TupletBracket.auto), hasLength(4));
      expect(bracketOf(NoteValue.quarter, TupletBracket.hidden), isEmpty);
    });

    test('a bracket starts at the leftmost head of a chord with a second', () {
      final placed = place(
        barWith([
          tupletOf(50, unit: NoteValue.quarter, [
            chordOf(1, 'C5 D5'),
            chordOf(2, 'C5'),
            chordOf(3, 'C5'),
          ]),
        ]),
      );
      final lines = placed.tuplets.single.drawables.whereType<LineDraw>();
      final heads = [headOf(placed, 1).left, headOf(placed, 1, 1).left];

      expect(heads.reduce(max) - heads.reduce(min), greaterThan(1));
      expect(lines.elementAt(1).from.x, closeTo(heads.reduce(min), hair));
    });

    test('a tuplet at its rods is as wide as its number, and its bracket is '
        'left out until a line fits on each side of the number', () {
      Placed laid(double stretch) => place(
        barWith([
          tupletOf(
            50,
            ratio: const TupletRatio(12, 10),
            unit: NoteValue.sixteenth,
            [chordOf(1, 'C5', value: half), chordOf(2, 'C5')],
          ),
        ]),
        stretch: stretch,
      );
      final pressed = laid(0);
      final number = pressed.tuplets.single.drawables
          .map((drawable) => drawable.bounds)
          .reduce((a, b) => a.union(b));

      expect(pressed.tuplets.single.drawables, everyElement(isA<GlyphDraw>()));
      expect(number.left, closeTo(headOf(pressed, 1).left, 1e-6));
      expect(number.right, closeTo(headOf(pressed, 2).right, 1e-6));
      expect(
        laid(2).tuplets.single.drawables.whereType<LineDraw>(),
        hasLength(4),
      );
    });

    test('a tuplet with as many stems up as down goes above', () {
      final placed = place(
        barWith([
          tupletOf(50, unit: NoteValue.quarter, [
            chordOf(1, 'A4'),
            chordOf(2, 'C5'),
            restOf(3, NoteValue.quarter),
          ]),
        ]),
      );

      expect(stemOf(placed, 1).top, lessThan(headOf(placed, 1).top));
      expect(stemOf(placed, 2).bottom, greaterThan(headOf(placed, 2).bottom));
      expect(placed.tuplets.single.stub.side, Side.above);
    });

    test('a tuplet inside another sits nearer the notes', () {
      final placed = place(
        barWith([
          tupletOf(50, unit: NoteValue.quarter, [
            chordOf(1, 'C5'),
            tupletOf(51, [
              for (var i = 2; i <= 4; i++) chordOf(i, 'C5', value: eighth),
            ]),
            chordOf(5, 'C5'),
          ]),
        ]),
      );
      Box boxOf(int event) => placed.tuplets
          .singleWhere((tuplet) => tuplet.stub.owner == eventOwner(event))
          .drawables
          .map((drawable) => drawable.bounds)
          .reduce((a, b) => a.union(b));
      final inner = boxOf(2);
      final outer = boxOf(1);

      expect(inner.top, greaterThan(staffHeight));
      expect(outer.top - inner.bottom, inInclusiveRange(clear, near));
      expect(outer.left, lessThan(inner.left));
      expect(outer.right, greaterThan(inner.right));
    });

    test('a tuplet of rests alone goes on its voice\'s side', () {
      final placed = place(
        barWith(
          [
            tupletOf(50, [for (var i = 1; i <= 3; i++) restOf(i, eighth)]),
          ],
          two: [
            tupletOf(51, [for (var i = 4; i <= 6; i++) restOf(i, eighth)]),
          ],
        ),
      );

      expect(
        [for (final tuplet in placed.tuplets) tuplet.stub.side],
        [Side.above, Side.below],
      );
      expect(
        [
          for (final tuplet in placed.tuplets)
            tuplet.drawables.whereType<LineDraw>().length,
        ],
        [4, 4],
      );
    });
  });

  group('room', () {
    MeasureView crowded() => barWith(
      [
        marked(
          1,
          'E5',
          articulations: {
            Articulation.staccato,
            Articulation.accent,
            Articulation.fermata,
          },
          ornament: Ornament.mordent,
          bowing: Bowing.up,
          fingerings: [1],
          strings: [3],
        ),
        tupletOf(50, [
          for (var i = 2; i <= 4; i++)
            marked(
              i,
              'D5',
              value: eighth,
              articulations: {Articulation.staccato, Articulation.tenuto},
              fingerings: [i],
            ),
        ]),
        marked(
          5,
          'D5 F5',
          value: half,
          articulations: {Articulation.tenuto, Articulation.marcato},
          ornament: Ornament.trill,
          bowing: Bowing.down,
          fingerings: [2, 4],
          strings: [2, 3],
        ),
      ],
      two: [
        marked(
          11,
          'G3',
          articulations: {Articulation.staccato, Articulation.fermata},
          bowing: Bowing.down,
          fingerings: [0],
          strings: [0],
        ),
        marked(12, 'A3', articulations: {Articulation.accent}),
        marked(
          13,
          'B3',
          value: half,
          articulations: {Articulation.tenuto, Articulation.harmonic},
          ornament: Ornament.turn,
        ),
      ],
      directions: [
        const DynamicMark(Moment.zero, Dynamic.ff),
        const TextMark(Moment.zero, 'dolce'),
        const TextMark(Moment.zero, 'sotto voce', above: false),
        const ChordSymbol(
          Moment.zero,
          root: PitchName(Step.b, Alter.flat),
          quality: 'm7',
          bass: PitchName(Step.f),
        ),
        DynamicMark(at(1, 4), Dynamic.p),
        ChordSymbol(
          at(1, 4),
          root: const PitchName(Step.f, Alter.sharp),
          quality: 'sus4',
        ),
        TextMark(at(2, 4), 'cresc.', above: false),
      ],
      tempos: [
        const TempoMark(
          offset: Moment.zero,
          tempo: Tempo(120),
          text: 'Allegro',
        ),
        TempoMark(
          offset: at(2, 4),
          tempo: const Tempo(60, beat: half),
        ),
      ],
      navigation: const [
        Segno(),
        Jump(JumpTarget.segno, then: JumpThen.toCoda),
      ],
      rehearsal: 'A',
      instrument: violin,
    );

    test('no two mark boxes of one bar overlap, with every kind of mark in '
        'it, several on each chord, in two voices', () {
      for (final stretch in [1.0, 2.0, 3.0]) {
        final placed = place(crowded(), stretch: stretch);
        final boxes = markBoxes(placed);

        expect(boxes, hasLength(55));
        expectNoOverlap(boxes, 'stretch $stretch');
      }
    });

    test('a bar pressed to its rods holds every mark between its content '
        'start and its end, with padding at its ends and without', () {
      const unpadded = EngravingStyle(spacing: SpacingPolicy(barPad: 0));
      final views = [
        crowded(),
        barWith(
          [chordOf(1, 'A4', value: whole)],
          directions: [
            const DynamicMark(Moment.zero, Dynamic.ffff),
            TextMark(at(3, 4), 'molto espressivo'),
            ChordSymbol(
              at(3, 4),
              root: const PitchName(Step.e, Alter.flat),
              quality: 'maj7',
            ),
          ],
          tempos: [
            const TempoMark(
              offset: Moment.zero,
              tempo: Tempo(108),
              text: 'Allegro ma non troppo',
            ),
            TempoMark(offset: at(3, 4), tempo: const Tempo(54), text: 'Largo'),
          ],
          navigation: const [
            Coda(),
            Jump(JumpTarget.segno, then: JumpThen.toCoda),
          ],
          rehearsal: 'B2',
        ),
        barWith([
          tupletOf(50, ratio: const TupletRatio(6, 5), [
            chordOf(1, 'A4', value: NoteValue.half.dotted),
          ]),
        ]),
        barWith([
          MeasureRest(
            id: const EventId(1),
            span: Meter.fourFour.length,
            articulations: const {Articulation.fermata},
          ),
        ]),
      ];
      for (final (view, spaced) in [
        for (final view in views) ...[(view, style), (view, unpadded)],
      ]) {
        final placed = place(view, stretch: 0, style: spaced);
        final boxes = markBoxes(placed);

        expect(boxes, isNotEmpty);
        for (final (staff: _, :box, :what) in boxes) {
          expect(box.left, greaterThanOrEqualTo(-hair), reason: what);
          expect(
            box.right,
            lessThanOrEqualTo(placed.frame.right + hair),
            reason: what,
          );
        }
      }
    });

    test('a tuplet of one note keeps the whole width of its number clear, '
        'so a mark beside the note stacks outside it', () {
      final placed = place(
        barWith([
          tupletOf(
            50,
            ratio: const TupletRatio(12, 10),
            unit: NoteValue.sixteenth,
            [chordOf(1, 'A4', value: NoteValue.half.dotted)],
          ),
        ], rehearsal: 'A'),
      );
      final boxes = markBoxes(placed);
      final [mark, number] = boxes;

      expect(mark.box.right, greaterThan(number.box.left));
      expect(mark.box.right, lessThan(headOf(placed, 1).left));
      expectNoOverlap(boxes, 'a rehearsal mark and a one-note tuplet');
    });

    test('a bar whose tuplet alone changes lays out unequal', () {
      BarLayout laid(TupletBracket bracket) => layoutBar(
        barWith([
          tupletOf(50, bracket: bracket, [
            for (var i = 1; i <= 3; i++) chordOf(i, 'A4', value: eighth),
          ]),
        ]),
        style,
        text,
      );

      expect(laid(TupletBracket.auto), laid(TupletBracket.auto));
      expect(laid(TupletBracket.auto), isNot(laid(TupletBracket.shown)));
    });

    test('a mark wider than its bar widens every slice it spans by the same '
        'share, until the bar is as wide as the mark and no wider', () {
      Placed pressed(List<TempoMark> tempos) => place(
        barWith([
          for (var i = 1; i <= 4; i++) chordOf(i, 'A4'),
        ], tempos: tempos),
        stretch: 0,
      );
      List<double> gapsOf(Placed placed) {
        final xs = placed.frame.xs;
        return [for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1]];
      }

      final plain = gapsOf(pressed(const []));
      final marked = pressed(const [
        TempoMark(
          offset: Moment.zero,
          tempo: Tempo(108),
          text: 'Allegro ma non troppo e molto maestoso',
        ),
      ]);
      final grown = [
        for (final (i, gap) in gapsOf(marked).indexed) gap - plain[i],
      ];

      expect(grown.first, greaterThan(1));
      expect(grown, everyElement(closeTo(grown.first, 1e-6)));
      expect(
        markBoxes(marked).map((mark) => mark.box.right).reduce(max),
        closeTo(marked.frame.xs.last, 1e-6),
      );
    });

    test('two marks of one lane at neighbouring notes keep a word space '
        'between them in a bar pressed to its rods', () {
      final placed = place(
        barWith(
          [for (var i = 1; i <= 4; i++) chordOf(i, 'A4')],
          directions: [
            const TextMark(Moment.zero, 'molto espressivo'),
            TextMark(at(1, 4), 'dolce'),
          ],
        ),
        stretch: 0,
      );
      final first = textOf(placed, 'molto espressivo').bounds;
      final second = textOf(placed, 'dolce').bounds;

      expect(middleOf(second), closeTo(middleOf(first), 1e-6));
      expect(second.left - first.right, greaterThanOrEqualTo(wordSpace));
    });

    test('no two mark boxes of one bar overlap, and a bar at its rods holds '
        'its marks, over seeded random scores', () {
      var scores = 0;
      var bars = 0;
      var boxes = 0;
      var brackets = 0;
      var stacked = 0;
      var twoVoiced = 0;
      const labels = ['Fine', 'To Coda', 'D.C.', 'D.S.', 'Да капо'];
      final kinds = <String, int>{};
      void count(Drawable drawable) {
        final kind = switch (drawable) {
          TextDraw(enclosed: true) => 'rehearsal',
          TextDraw(:final text) when text.startsWith('= ') => 'tempo number',
          TextDraw(:final text) when labels.any(text.startsWith) => 'label',
          TextDraw(:final spec) => [
            TextRole.tempo,
            TextRole.chordSymbol,
            TextRole.expression,
          ].firstWhere((role) => style.specOf(role) == spec).name,
          GlyphDraw(:final glyph) => markGlyphs.firstWhere(
            glyph.name.startsWith,
          ),
          _ => '',
        };
        kinds.update(kind, (n) => n + 1, ifAbsent: () => 1);
      }

      for (final seed in [1, 2, 3, 4, 5, 6]) {
        final random = Random(seed);
        var score = model.blankScore(
          parts: const [
            model.morinKhuur,
            model.clarinet,
            model.piano,
            model.drums,
          ],
          bars: 4,
        );
        for (var step = 0; step < 250; step++) {
          final before = score;
          score = withOneMoreMark(randomEdit(before, random), random);
          scores++;
          for (final id in score.changesSince(before).relayout) {
            final where = 'seed $seed, step $step, bar ${score.indexOf(id)}';
            final view = score.measureView(id);
            bars++;
            for (final staff in view.staves) {
              final marked = [
                for (final voice in staff.voices)
                  voice.events.where((timed) => hasMarks(timed.event)).length,
              ];
              twoVoiced += marked.where((n) => n > 0).length > 1 ? 1 : 0;
            }
            for (final stretch in [1.0, 3.0]) {
              final placed = place(view, stretch: stretch);
              final found = markBoxes(placed);
              expectNoOverlap(found, '$where, stretch $stretch');
              if (stretch > 1) {
                continue;
              }
              boxes += found.length;
              final owned = <Object, int>{};
              for (final (staff: _, :drawable) in placed.items) {
                if (isMark(drawable)) {
                  count(drawable);
                  if (drawable.owner case ElementOwner(:final ref)) {
                    final event = ref is NoteRef ? ref.event : ref;
                    owned.update(event, (n) => n + 1, ifAbsent: () => 1);
                  }
                }
              }
              stacked += owned.values.where((n) => n > 2).length;
              kinds.update(
                'tuplet',
                (n) => n + placed.tuplets.length,
                ifAbsent: () => placed.tuplets.length,
              );
              brackets += placed.tuplets
                  .where((tuplet) => tuplet.drawables.length > 1)
                  .where((tuplet) => tuplet.drawables.last is LineDraw)
                  .length;
            }
            final pressed = place(view, stretch: 0);
            for (final (staff: _, :box, :what) in markBoxes(pressed)) {
              expect(
                box.left >= -1e-6 && box.right <= pressed.frame.right + 1e-6,
                isTrue,
                reason: '$where: $what at $box leaves its bar',
              );
            }
          }
        }
      }

      printOnFailure(
        '$scores scores, $bars bars, $boxes boxes, $brackets brackets, '
        '$stacked stacked, $twoVoiced two-voiced, $kinds',
      );
      expect(scores, 1500);
      expect(bars, greaterThan(4000));
      expect(boxes, greaterThan(20000));
      expect(brackets, greaterThan(300));
      expect(stacked, greaterThan(2000));
      expect(twoVoiced, greaterThan(100));
      for (final kind in [
        ...markGlyphs,
        'tuplet',
        'rehearsal',
        'tempo number',
        'label',
        TextRole.tempo.name,
        TextRole.chordSymbol.name,
        TextRole.expression.name,
      ]) {
        expect(kinds[kind], greaterThan(20), reason: kind);
      }
    });
  });
}
