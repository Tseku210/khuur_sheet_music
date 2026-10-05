import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/random_edits.dart';
import 'support/fake_measurer.dart';
import 'support/role_scores.dart';
import 'support/sheets.dart';

const measurer = FakeMeasurer();

/// Wide enough that each score below stands on one system.
const double wide = 300;

/// Narrow enough that each score below breaks once it is four bars longer.
const double narrow = 45;

SheetLayout lay(
  Score score, {
  EngravingStyle style = EngravingStyle.standard,
  double width = wide,
}) => SheetLayout(score, width: width, text: measurer, style: style);

SystemLayout only(SheetLayout layout) {
  expect(layout.systemCount, 1, reason: 'the score stands on one system');
  return layout.systemAt(0);
}

List<Drawable> drawn(SheetLayout layout) => [
  ...layout.header,
  for (var i = 0; i < layout.systemCount; i++) ...[
    ...layout.systemAt(i).drawables,
    ?layout.labelOf(i),
  ],
];

/// What event [id] owns, its heads included.
List<Drawable> ownedBy(SheetLayout layout, int id) => [
  ...only(
    layout,
  ).drawablesOf(ElementOwner(layout.score.locate(EventId(id))!)),
];

List<Drawable> ofSpanner(SheetLayout layout, int id) => [
  ...only(layout).drawablesOf(SpannerOwner(SpannerId(id))),
];

/// The glyphs of [from] whose SMuFL name starts with [family].
Iterable<GlyphDraw> glyphs(Iterable<Drawable> from, String family) => from
    .whereType<GlyphDraw>()
    .where((drawable) => drawable.glyph.name.startsWith(family));

Iterable<LineDraw> upright(Iterable<Drawable> from) =>
    from.whereType<LineDraw>().where((line) => line.from.x == line.to.x);

Iterable<LineDraw> level(Iterable<Drawable> from) =>
    from.whereType<LineDraw>().where((line) => line.from.y == line.to.y);

Iterable<TextDraw> texts(Iterable<Drawable> from, String text) =>
    from.whereType<TextDraw>().where((drawable) => drawable.text == text);

Iterable<Drawable> unowned(Iterable<Drawable> from) =>
    from.where((drawable) => drawable.owner == null);

Iterable<LineDraw> linesAbove(SystemLayout system) =>
    unowned(system.drawables)
        .whereType<LineDraw>()
        .where((line) => line.bounds.bottom < system.staves.first.top);

/// Expects [found] to hold [count] drawables, or one or more when [count]
/// is null, and each to have [role]. [rule] is the rule that says so.
void expectRole(
  Iterable<Drawable> found,
  InkRole role,
  String rule, {
  int? count,
}) {
  expect(
    found.length,
    count ?? greaterThan(0),
    reason: 'what the rule is about was not found. $rule',
  );
  expect({for (final drawable in found) drawable.ink}, {role}, reason: rule);
}

void main() {
  group('a chord', () {
    late final layout = lay(chordScore());

    test('gives an eighth note its head, its stem and its flag', () {
      final note = ownedBy(layout, 1);

      expect(note, hasLength(3));
      expectRole(
        glyphs(note, 'notehead'),
        InkRole.notehead,
        'A notehead inside its range is notehead.',
        count: 1,
      );
      expectRole(
        upright(note),
        InkRole.stem,
        "A note's vertical line is stem.",
        count: 1,
      );
      expectRole(
        glyphs(note, 'flag'),
        InkRole.flag,
        "A note's flag glyph is flag.",
        count: 1,
      );
    });

    test('keeps outOfRange for a head outside its instrument', () {
      expectRole(
        glyphs(ownedBy(layout, 2), 'notehead'),
        InkRole.outOfRange,
        'outOfRange stays a notehead outside its instrument\'s range.',
        count: 1,
      );
    });

    test('gives its ledger lines, its accidental and its dot each a role', () {
      final note = ownedBy(layout, 2);

      expectRole(
        level(note),
        InkRole.ledgerLine,
        'A ledger line is ledgerLine.',
        count: 2,
      );
      expect(
        glyphs(note, 'accidental').map((drawable) => drawable.glyph),
        unorderedEquals([
          Glyph.accidentalParensLeft,
          Glyph.accidentalSharp,
          Glyph.accidentalParensRight,
        ]),
      );
      expectRole(
        glyphs(note, 'accidental'),
        InkRole.accidental,
        "A cautionary accidental's parentheses are accidental.",
        count: 3,
      );
      expectRole(
        glyphs(note, 'augmentationDot'),
        InkRole.dot,
        "A chord's dot is dot.",
        count: 1,
      );
    });

    test('gives a beamed note a stem, and its beam and hook the beam', () {
      for (final beamed in [3, 4, 6, 7]) {
        expectRole(
          upright(ownedBy(layout, beamed)),
          InkRole.stem,
          "A beamed note's stem is stem.",
          count: 1,
        );
      }
      expectRole(
        unowned(only(layout).drawables).whereType<PolygonDraw>(),
        InkRole.beam,
        'A beam is beam.',
        count: 2,
      );
      expectRole(
        ownedBy(layout, 7).whereType<PolygonDraw>(),
        InkRole.beam,
        'A beam hook is beam.',
        count: 1,
      );
    });

    test('gives tremolo strokes the ornament role', () {
      expectRole(
        glyphs(ownedBy(layout, 8), 'tremolo'),
        InkRole.ornament,
        "A tremolo's strokes are ornament.",
        count: 1,
      );
    });

    test('gives a rest its role and a rest\'s dot the dot role', () {
      final dotted = ownedBy(layout, 9);

      expect(dotted, hasLength(2));
      expectRole(
        glyphs(dotted, 'rest'),
        InkRole.rest,
        'A rest is rest.',
        count: 1,
      );
      expectRole(
        glyphs(dotted, 'augmentationDot'),
        InkRole.dot,
        "A rest's dot is dot.",
        count: 1,
      );
    });

    test('gives a grace note the roles of a note', () {
      final small = ownedBy(layout, 10).where(
        (drawable) => switch (drawable) {
          GlyphDraw(:final scale) => scale != 1,
          LineDraw(:final thickness) =>
            thickness < layout.style.font.defaults.stemThickness,
          _ => true,
        },
      );

      expectRole(
        glyphs(small, 'notehead'),
        InkRole.notehead,
        'A grace head is notehead.',
        count: 1,
      );
      expectRole(
        upright(small),
        InkRole.stem,
        "A grace note's stem is stem.",
        count: 1,
      );
      expectRole(
        glyphs(small, 'flag'),
        InkRole.flag,
        "A grace note's flag is flag.",
        count: 1,
      );
      expectRole(
        small.whereType<LineDraw>().where(
          (line) => line.from.x != line.to.x && line.from.y != line.to.y,
        ),
        InkRole.flag,
        'The slash of an acciaccatura goes with the flag it crosses.',
        count: 1,
      );
      expectRole(
        small.whereType<CurveDraw>(),
        InkRole.tie,
        'A grace tie is tie.',
        count: 1,
      );
    });
  });

  group('a rest', () {
    test('that fills its bar is a rest', () {
      expectRole(
        glyphs(only(lay(restScore())).drawables, 'restWhole'),
        InkRole.rest,
        'A measure rest is rest.',
        count: 3,
      );
    });

    test('of several bars is a rest in its bar, its ends and its count', () {
      final system = only(lay(restScore(), style: multiRests));
      final staff = system.staves.single;
      final ends = glyphs(system.drawables, 'restHBar').toList();

      expectRole(
        ends,
        InkRole.rest,
        "A multi-measure rest's ends are rest.",
        count: 2,
      );
      final left = ends
          .map((end) => end.bounds.left)
          .reduce((a, b) => a < b ? a : b);
      final right = ends
          .map((end) => end.bounds.right)
          .reduce((a, b) => a > b ? a : b);
      expectRole(
        level(system.drawables).where(
          (line) => line.from.x >= left && line.to.x <= right,
        ),
        InkRole.rest,
        "A multi-measure rest's bar is rest.",
        count: 1,
      );
      expectRole(
        glyphs(
          system.drawables,
          'timeSig',
        ).where((digit) => digit.bounds.bottom < staff.top),
        InkRole.rest,
        "A multi-measure rest's count is rest.",
        count: 1,
      );
    });
  });

  group('a mark', () {
    late final layout = lay(markScore());
    late final all = drawn(layout);

    test('on a chord has the role of its kind', () {
      expectRole(
        [
          ...glyphs(ownedBy(layout, 1), 'articStaccato'),
          ...glyphs(ownedBy(layout, 1), 'articAccent'),
          ...glyphs(ownedBy(layout, 1), 'stringsHarmonic'),
        ],
        InkRole.articulation,
        'A staccato, an accent and a harmonic are articulation.',
        count: 3,
      );
      expectRole(
        glyphs(ownedBy(layout, 2), 'fermata'),
        InkRole.articulation,
        'A fermata is articulation.',
        count: 1,
      );
      expectRole(
        glyphs(ownedBy(layout, 3), 'ornament'),
        InkRole.ornament,
        'An ornament sign is ornament.',
        count: 1,
      );
      expectRole(
        glyphs(ownedBy(layout, 3), 'strings'),
        InkRole.bowing,
        'A bow mark is bowing.',
        count: 1,
      );
      expectRole(
        glyphs(ownedBy(layout, 4), 'fingering'),
        InkRole.fingering,
        'A finger number is fingering.',
        count: 1,
      );
      expectRole(
        glyphs(ownedBy(layout, 4), 'guitarString'),
        InkRole.stringNumber,
        'A circled string number is stringNumber.',
        count: 1,
      );
      expectRole(
        texts(ownedBy(lay(markScore(), style: roman), 4), 'II'),
        InkRole.stringNumber,
        'A roman string number is stringNumber.',
        count: 1,
      );
    });

    test('over a staff has the role of its kind', () {
      expectRole(
        glyphs(all, 'dynamic'),
        InkRole.dynamics,
        'A dynamic is dynamics.',
        count: 1,
      );
      expectRole(
        texts(all, 'dolce'),
        InkRole.expression,
        'A text mark is expression.',
        count: 1,
      );
      expectRole(
        [...texts(all, 'B'), ...glyphs(all, 'csym'), ...texts(all, 'm7')],
        InkRole.chordSymbol,
        "A chord symbol's letters and its accidental are chordSymbol.",
        count: 3,
      );
      expectRole(
        [
          ...texts(all, 'Allegro'),
          ...glyphs(all, 'metNote'),
          ...texts(all, '= 120'),
        ],
        InkRole.tempo,
        "A tempo mark's words, its note and its number are tempo.",
        count: 3,
      );
      expectRole(
        all.whereType<TextDraw>().where((drawable) => drawable.enclosed),
        InkRole.rehearsal,
        'A rehearsal mark is rehearsal.',
        count: 1,
      );
      expectRole(
        glyphs(all, 'segno'),
        InkRole.navigation,
        'A segno is navigation.',
        count: 1,
      );
      expectRole(
        texts(all, 'Fine'),
        InkRole.navigation,
        'A navigation label is navigation.',
        count: 1,
      );
    });

    test('of a tuplet is tuplet in its number and its bracket', () {
      final system = only(layout);
      final number = glyphs(system.drawables, 'tuplet').single;

      expectRole(
        [number],
        InkRole.tuplet,
        "A tuplet's number is tuplet.",
      );
      expectRole(
        unowned(system.drawables).whereType<LineDraw>().where(
          (line) =>
              line.bounds.top >= number.bounds.top - 0.2 &&
              line.bounds.bottom <= number.bounds.bottom + 0.2,
        ),
        InkRole.tuplet,
        "A tuplet's bracket is tuplet.",
        count: 4,
      );
    });
  });

  group('a line', () {
    late final layout = lay(lineScore());
    late final system = only(layout);

    test('that is a curve is a tie between notes and a slur as a spanner', () {
      expectRole(
        system.drawables.whereType<CurveDraw>().where(
          (curve) => curve.owner is ElementOwner,
        ),
        InkRole.tie,
        'A tie is tie.',
        count: 1,
      );
      expectRole(
        ofSpanner(layout, slur).whereType<CurveDraw>(),
        InkRole.slur,
        'A slur is slur.',
        count: 1,
      );
    });

    test('has one role in every part', () {
      expectRole(
        ofSpanner(layout, hairpin).whereType<LineDraw>(),
        InkRole.hairpin,
        "A hairpin's arms are hairpin.",
        count: 2,
      );
      expect(ofSpanner(layout, hairpin), hasLength(2));

      final octave = ofSpanner(layout, octaveLine);
      expect(octave, hasLength(3));
      expectRole(
        glyphs(octave, 'ottava'),
        InkRole.octaveLine,
        "An octave line's glyph is octaveLine.",
        count: 1,
      );
      expectRole(
        octave.whereType<LineDraw>().where(
          (line) => line.dash == LineDash.dashed,
        ),
        InkRole.octaveLine,
        "An octave line's dashes are octaveLine.",
        count: 1,
      );
      expectRole(
        upright(octave),
        InkRole.octaveLine,
        "An octave line's hook is octaveLine.",
        count: 1,
      );

      expectRole(
        ofSpanner(layout, glissando).whereType<LineDraw>(),
        InkRole.glissando,
        'A glissando is glissando.',
        count: 1,
      );
      expect(ofSpanner(layout, glissando), hasLength(1));

      final pedalParts = ofSpanner(layout, pedal);
      expect(pedalParts, hasLength(3));
      expectRole(
        glyphs(pedalParts, 'keyboardPedal'),
        InkRole.pedal,
        "A pedal's glyph is pedal.",
        count: 1,
      );
      expectRole(
        level(pedalParts),
        InkRole.pedal,
        "A pedal's line is pedal.",
        count: 1,
      );
      expectRole(
        upright(pedalParts),
        InkRole.pedal,
        "A pedal's hook is pedal.",
        count: 1,
      );

      final trill = ofSpanner(layout, trillLine);
      expect(trill, hasLength(2));
      expectRole(
        glyphs(trill, 'ornamentTrill'),
        InkRole.ornament,
        "A trill line's glyph is ornament.",
        count: 1,
      );
      expectRole(
        trill.whereType<GlyphRunDraw>(),
        InkRole.ornament,
        "A trill line's wavy run is ornament.",
        count: 1,
      );

      final tempo = ofSpanner(layout, tempoLine);
      expect(tempo, hasLength(2));
      expectRole(
        texts(tempo, 'rit.'),
        InkRole.tempo,
        "A tempo line's text is tempo.",
        count: 1,
      );
      expectRole(
        tempo.whereType<LineDraw>().where(
          (line) => line.dash == LineDash.dashed,
        ),
        InkRole.tempo,
        "A tempo line's dashes are tempo.",
        count: 1,
      );
    });

    test('of a volta is volta in its line, its hooks and its text', () {
      final lines = linesAbove(system).toList();
      final across = level(lines).single;

      expect(lines, hasLength(3));
      expectRole([across], InkRole.volta, "A volta's line is volta.");
      expectRole(
        upright(lines)
            .where((hook) => hook.from.x < (across.from.x + across.to.x) / 2),
        InkRole.volta,
        "A volta's left hook is volta.",
        count: 1,
      );
      expectRole(
        upright(lines)
            .where((hook) => hook.from.x > (across.from.x + across.to.x) / 2),
        InkRole.volta,
        "A volta's right hook is volta.",
        count: 1,
      );
      expectRole(
        texts(system.drawables, '1.'),
        InkRole.volta,
        "A volta's text is volta.",
        count: 1,
      );
    });
  });

  test('a lyric is lyric in its syllable, its hyphen and its extender', () {
    final layout = lay(lyricScore());
    final all = only(layout).drawables;

    expectRole(
      [...texts(all, 'Hal'), ...texts(all, 'le'), ...texts(all, 'ah')],
      InkRole.lyric,
      "A lyric's syllable is lyric.",
      count: 3,
    );
    expectRole(texts(all, '-'), InkRole.lyric, "A lyric's hyphen is lyric.");
    expectRole(
      level(ownedBy(layout, 3)),
      InkRole.lyric,
      "A lyric's extender is lyric.",
      count: 1,
    );
  });

  group('the frame of a system', () {
    late final layout = lay(frameScore());
    late final system = only(layout);
    late final structure = unowned(system.drawables).toList();
    late final top = system.staves.first.top;
    late final bottom = system.staves.last.top + staffHeight;
    bool joinsAll(LineDraw line) => line.from.y == top && line.to.y == bottom;

    test('draws staff lines as staffLine', () {
      expectRole(
        level(structure).where(
          (line) =>
              line.from.x <= system.bars.first.left &&
              line.to.x >= system.bars.last.right,
        ),
        InkRole.staffLine,
        'A staff line is staffLine.',
        count: 20,
      );
    });

    test('draws a brace as brace', () {
      expectRole(
        glyphs(structure, 'brace'),
        InkRole.brace,
        'A brace is brace.',
        count: 1,
      );
    });

    test('draws every barline, the line that joins the staves and repeat '
        'dots as barline', () {
      final barlines = upright(structure).where((line) => !joinsAll(line));

      expect(
        barlines.map((line) => line.thickness).toSet(),
        hasLength(2),
        reason: 'thin and thick barlines are both here',
      );
      expectRole(barlines, InkRole.barline, 'Every barline is barline.');
      expectRole(
        upright(structure).where(joinsAll),
        InkRole.barline,
        "The line that joins staves at a system's start is barline.",
        count: 1,
      );
      expectRole(
        glyphs(structure, 'repeatDots'),
        InkRole.barline,
        'Repeat dots are barline.',
        count: 8,
      );
    });

    test('draws clefs, key signatures and time signatures as themselves', () {
      final clefs = structure.whereType<GlyphDraw>().where(
        (drawable) => drawable.glyph.name.contains('Clef'),
      );

      expect(
        clefs.map((drawable) => drawable.glyph),
        containsAll([
          Glyph.gClef,
          Glyph.fClef,
          Glyph.unpitchedPercussionClef1,
          Glyph.gClefChange,
        ]),
      );
      expectRole(clefs, InkRole.clef, 'A clef and a clef change are clef.');
      expect(
        glyphs(structure, 'accidental').map((drawable) => drawable.glyph),
        containsAll([
          Glyph.accidentalSharp,
          Glyph.accidentalNatural,
          Glyph.accidentalFlat,
        ]),
      );
      expectRole(
        glyphs(structure, 'accidental'),
        InkRole.keySignature,
        "A key signature's sharps, flats and naturals are keySignature.",
      );
      expect(
        glyphs(structure, 'timeSig').map((drawable) => drawable.glyph),
        containsAll([Glyph.timeSig4, Glyph.timeSigCommon]),
      );
      expectRole(
        glyphs(structure, 'timeSig'),
        InkRole.timeSignature,
        'A time signature is timeSignature.',
      );
    });

    test('draws its header, its part names and its bar number as '
        'themselves', () {
      expectRole(
        texts(layout.header, 'A title'),
        InkRole.title,
        'A title is title.',
        count: 1,
      );
      expectRole(
        texts(layout.header, 'A subtitle'),
        InkRole.subtitle,
        'A subtitle is subtitle.',
        count: 1,
      );
      expectRole(
        [
          ...texts(layout.header, 'A composer'),
          ...texts(layout.header, 'A lyricist'),
        ],
        InkRole.credit,
        'A composer and a lyricist are credit.',
        count: 2,
      );
      expectRole(
        [
          for (final part in layout.score.parts) ...texts(structure, part.name),
        ],
        InkRole.partName,
        'A part name is partName.',
        count: 3,
      );
      expectRole(
        [?layout.labelOf(0)],
        InkRole.barNumber,
        'A bar number is barNumber.',
        count: 1,
      );
    });

    test('draws a drum\'s head as a notehead', () {
      expectRole(
        glyphs(ownedBy(layout, 1), 'notehead'),
        InkRole.notehead,
        'Every notehead that is not out of range is notehead.',
        count: 1,
      );
    });
  });

  test('a text has the role named like its TextRole, but for the text of a '
      'tempo line, which is tempo', () {
    final sized = EngravingStyle(
      stringNumbers: StringNumbers.roman,
      text: {
        for (final role in TextRole.values)
          role: TextSpec(size: 1 + role.index / 10),
      },
    );
    final seen = <TextRole>{};

    for (final (score, _) in roleSheets) {
      final layout = lay(score, style: sized);
      for (final drawable in drawn(layout).whereType<TextDraw>()) {
        final role = TextRole.values.singleWhere(
          (role) => sized.specOf(role).size == drawable.spec.size,
        );
        seen.add(role);
        expect(
          drawable.ink.name,
          drawable.owner is SpannerOwner ? InkRole.tempo.name : role.name,
          reason:
              'A text drawable takes the role named like its TextRole. '
              '"${drawable.text}" is set as $role.',
        );
      }
    }

    expect(seen, TextRole.values.toSet());
  });

  test('a moved drawable keeps its role', () {
    const box = Box(0, 0, 1, 1);
    for (final role in [InkRole.beam, InkRole.ornament]) {
      for (final drawable in [
        GlyphDraw(Glyph.noteheadBlack, SpPoint.zero, bounds: box, ink: role),
        LineDraw(SpPoint.zero, const SpPoint(1, 1), thickness: 0.1, ink: role),
        PolygonDraw(const [
          SpPoint.zero,
          SpPoint(1, 0),
          SpPoint(1, 1),
        ], ink: role),
        TextDraw(
          'a',
          SpPoint.zero,
          spec: const TextSpec(size: 2),
          bounds: box,
          ink: role,
        ),
        CurveDraw(
          start: SpPoint.zero,
          control1: SpPoint.zero,
          control2: const SpPoint(1, 0),
          end: const SpPoint(1, 0),
          endThickness: 0.1,
          midThickness: 0.2,
          ink: role,
        ),
        GlyphRunDraw(
          Glyph.wiggleTrill,
          from: SpPoint.zero,
          to: const SpPoint(1, 0),
          count: 1,
          bounds: box,
          ink: role,
        ),
      ]) {
        expect(
          drawable.shift(2, 3).ink,
          role,
          reason: '${drawable.runtimeType} moved',
        );
      }
    }
  });

  test('every role is drawn by one of the scores here', () {
    final roles = {
      for (final (score, style) in roleSheets)
        for (final drawable in drawn(lay(score, style: style))) drawable.ink,
    };

    expect(InkRole.values.toSet().difference(roles), isEmpty);
  });

  test('an updated layout draws every role and equals a fresh one', () {
    final roles = <InkRole>{};

    for (final (score, style) in roleSheets) {
      final longer = edited(score, const InsertMeasures(count: 4));
      final layout = lay(longer, style: style, width: narrow);
      expect(layout.systemCount, greaterThan(1));
      assembleAll(layout);
      final next = edited(
        longer,
        EnterNote(
          at: VoicePoint(
            staff: longer.staves.first.id,
            voice: VoiceSlot.one,
            at: ScorePoint(longer.measures.last.id, Moment.zero),
          ),
          tone: const Pitch(Step.a, 4),
          value: NoteValue.quarter,
        ),
      );

      final updated = layout.update(next);

      expect(
        updated.delta.relaid.intersection({
          for (final column in score.measures) column.id,
        }),
        isEmpty,
        reason: 'the bars with the marks are kept and not laid out again',
      );
      expectSameSheet(updated, lay(next, style: style, width: narrow));
      roles.addAll(drawn(updated).map((drawable) => drawable.ink));
    }

    expect(InkRole.values.toSet().difference(roles), isEmpty);
  });
}
