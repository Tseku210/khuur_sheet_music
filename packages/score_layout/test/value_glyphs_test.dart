import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/bars.dart';
import 'support/fake_measurer.dart';

/// Four whole notes a bar, so a breve and its dot fit with room to spare.
const Meter long = Meter([4], 1);

const EventRef event = EventRef(
  measure: MeasureId(3000),
  staff: StaffId(2000),
  id: EventId(1),
);

SystemLayout systemOf(Score score, {EngravingStyle style = .standard}) =>
    SheetLayout(
      score,
      width: 400,
      text: const FakeMeasurer(),
      style: style,
    ).systemAt(0);

/// The glyphs of [owner] in [score]'s first system, in drawing order.
List<Glyph> glyphsOf(
  Score score, {
  Owner owner = const ElementOwner(event),
  EngravingStyle style = .standard,
}) => [
  for (final drawable in systemOf(score, style: style).drawablesOf(owner))
    if (drawable case GlyphDraw(:final glyph)) glyph,
];

/// Every glyph of [score]'s first system, in drawing order.
List<Glyph> allGlyphsOf(Score score) => [
  for (final drawable in systemOf(score).drawables)
    if (drawable case GlyphDraw(:final glyph)) glyph,
];

Score barOfOne(VoiceItem item, {Meter meter = .fourFour}) => scoreOf([
  [
    staffOf([item]),
  ],
], meter: meter);

Score withColumn(Score score, MeasureColumn Function(MeasureColumn) edit) =>
    score.copyWith(measures: Seq([edit(score.measures.first)]));

ChordEvent noteOf(Pitch pitch) => ChordEvent(
  id: const EventId(1),
  value: NoteValue.quarter,
  notes: Seq([
    PitchedNote(
      id: const NoteId(10),
      pitch: pitch,
      accidental: AccidentalRequest.always,
    ),
  ]),
);

void main() {
  test('a rest of every value is drawn with its restGlyph and its dots with '
      'the augmentation dot', () {
    for (final base in DurationBase.values) {
      // No rest fills the 256th a dotted 128th leaves of the bar.
      for (final dots in [0, if (base != .oneTwentyEighth) 1]) {
        final rest = RestEvent(
          id: const EventId(1),
          value: .new(base, dots: dots),
        );

        expect(
          glyphsOf(barOfOne(rest, meter: long)),
          [
            restGlyph(base),
            for (var i = 0; i < dots; i++) Glyph.augmentationDot,
          ],
          reason: '$base with $dots dots',
        );
      }
    }
  });

  test("a tempo mark's note of every value is its noteGlyph, and its dots "
      'the metronome dot', () {
    for (final base in DurationBase.values) {
      for (final dots in [0, 2]) {
        final score = withColumn(
          barOfOne(chordOf(1, 'A4', value: .whole), meter: long),
          (column) => column.copyWith(
            tempos: Seq([
              TempoMark(
                offset: Moment.zero,
                tempo: Tempo(60, beat: .new(base, dots: dots)),
              ),
            ]),
          ),
        );

        expect(
          allGlyphsOf(score).where(
            (glyph) =>
                glyph.name.startsWith('metNote') ||
                glyph == Glyph.metAugmentationDot,
          ),
          [
            noteGlyph(base),
            for (var i = 0; i < dots; i++) Glyph.metAugmentationDot,
          ],
          reason: '$base with $dots dots',
        );
      }
    }
  });

  test('an accidental of every alter is drawn with its accidentalGlyph in '
      "the style's quarter-tone family", () {
    for (final family in QuarterToneGlyphs.values) {
      final style = EngravingStyle(quarterTones: family);
      for (var quarterTones = -4; quarterTones <= 4; quarterTones++) {
        final alter = Alter.fromQuarterTones(quarterTones);
        final drawn = glyphsOf(
          barOfOne(noteOf(Pitch(Step.c, 5, alter))),
          style: style,
        );

        expect(
          drawn,
          contains(accidentalGlyph(alter, family)),
          reason: '$alter in $family',
        );
      }
    }
  });

  test('a dynamic of every level is drawn with its dynamicGlyph', () {
    for (final level in Dynamic.values) {
      final score = withColumn(
        barOfOne(chordOf(1, 'A4', value: .whole)),
        (column) => column.withStaff(
          column.staves.first.copyWith(
            directions: Seq([DynamicMark(Moment.zero, level)]),
          ),
        ),
      );

      expect(
        allGlyphsOf(score).where((glyph) => glyph.name.startsWith('dynamic')),
        [dynamicGlyph(level)],
        reason: '$level',
      );
    }
  });

  test('a bowing of either way is drawn with its bowingGlyph', () {
    for (final bowing in Bowing.values) {
      final chord = chordOf(1, 'A4').copyWith(bowing: () => bowing);

      expect(glyphsOf(barOfOne(chord)), contains(bowingGlyph(bowing)));
    }
  });

  test('a fingering of one digit or more is drawn with its fingeringGlyphs, '
      'and a negative finger is refused', () {
    const fingerings = {
      Glyph.fingering0,
      Glyph.fingering1,
      Glyph.fingering2,
      Glyph.fingering3,
      Glyph.fingering4,
      Glyph.fingering5,
      Glyph.fingering6,
      Glyph.fingering7,
      Glyph.fingering8,
      Glyph.fingering9,
    };
    for (final finger in [0, 1, 4, 9, 10, 25]) {
      final chord = chordOf(1, 'A4');
      final note = (chord.notes.first as PitchedNote).copyWith(
        fingering: () => finger,
      );
      final score = barOfOne(chord.copyWith(notes: Seq([note])));

      expect(
        glyphsOf(
          score,
          owner: ElementOwner(NoteRef(event, note.id)),
        ).where(fingerings.contains),
        fingeringGlyphs(finger),
        reason: '$finger',
      );
    }
    expect(() => fingeringGlyphs(-1), throwsA(isA<AssertionError>()));
  });

  test("the lookups give SMuFL's codepoints", () {
    List<int> codepoints(Iterable<Glyph> glyphs) => [
      for (final glyph in glyphs) glyph.codepoint,
    ];

    expect(codepoints(DurationBase.values.map(noteGlyph)), [
      0xECA0, 0xECA2, 0xECA3, 0xECA5, 0xECA7, //
      0xECA9, 0xECAB, 0xECAD, 0xECAF,
    ]);
    expect(codepoints(DurationBase.values.map(restGlyph)), [
      for (var i = 0; i < 9; i++) 0xE4E2 + i,
    ]);
    expect(
      codepoints([
        for (final alter in const [
          Alter.doubleFlat,
          Alter.flat,
          Alter.natural,
          Alter.sharp,
          Alter.doubleSharp,
        ])
          accidentalGlyph(alter, .steinZimmermann),
      ]),
      [0xE264, 0xE260, 0xE261, 0xE262, 0xE263],
    );
    expect(
      codepoints([
        for (final level in const [
          Dynamic.pp,
          Dynamic.p,
          Dynamic.mp,
          Dynamic.mf,
          Dynamic.f,
          Dynamic.ff,
        ])
          dynamicGlyph(level),
      ]),
      [0xE52B, 0xE520, 0xE52C, 0xE52D, 0xE522, 0xE52F],
    );
    expect(codepoints([bowingGlyph(.up), bowingGlyph(.down)]), [
      0xE612,
      0xE610,
    ]);
    expect(codepoints(fingeringGlyphs(1234567890)), [
      0xED11, 0xED12, 0xED13, 0xED14, 0xED15, //
      0xED24, 0xED25, 0xED26, 0xED27, 0xED10,
    ]);
    expect(codepoints([Glyph.augmentationDot, Glyph.metAugmentationDot]), [
      0xE1E7,
      0xECB7,
    ]);
  });
}
