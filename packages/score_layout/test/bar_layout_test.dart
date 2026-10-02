import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/bar_space.dart';
import 'package:score_layout/src/chords.dart';
import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/spacing.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/bars.dart';
import 'support/fake_measurer.dart';

const EngravingStyle style = EngravingStyle.standard;

BarLayout layoutOf(MeasureView view) =>
    layoutBar(view, style, const FakeMeasurer());

/// The slice of the head items of event [id].
int sliceOf(BarLayout layout, int id) => layout.items
    .where(
      (item) => switch (item.drawable) {
        GlyphDraw(owner: ElementOwner(ref: NoteRef(:final event))) =>
          event.id == EventId(id),
        _ => false,
      },
    )
    .map((item) => item.slice)
    .toSet()
    .single;

void main() {
  group('slices', () {
    final view = viewOf(
      scoreOf([
        [
          staffOf(
            [
              chordOf(1, 'C5'),
              chordOf(2, 'D5', value: eighth),
              chordOf(3, 'E5', value: eighth),
              chordOf(4, 'F5', value: half),
            ],
            two: [
              chordOf(5, 'A4', value: half),
              chordOf(6, 'G4', value: half),
            ],
          ),
          staffOf([
            chordOf(7, 'C3', value: half),
            chordOf(8, 'D3', value: half),
          ], clef: Clef.bass),
        ],
      ]),
    );
    final layout = layoutOf(view);

    test('events at one onset share a slice across voices and staves', () {
      expect(sliceOf(layout, 1), 0);
      expect(sliceOf(layout, 5), 0);
      expect(sliceOf(layout, 7), 0);
      expect(sliceOf(layout, 4), 3);
      expect(sliceOf(layout, 6), 3);
      expect(sliceOf(layout, 8), 3);
      expect(sliceOf(layout, 2), 1);
      expect(sliceOf(layout, 3), 2);
    });

    test('x grows strictly with onset within a staff', () {
      final xs = sliceXs(layout.slices, 1, 0);
      final times = layout.slices.map((s) => s.at).toList();

      expect(times, [at(0, 1), at(1, 4), at(3, 8), at(1, 2), at(1, 1)]);
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]));
        expect(times[i].wholeNotes > times[i - 1].wholeNotes, isTrue);
      }
    });

    test('a quarter gets more room than an eighth and less than twice it', () {
      final xs = sliceXs(layout.slices, 1, 0);
      final afterQuarter = xs[1] - xs[0];
      final afterEighth = xs[2] - xs[1];

      expect(afterQuarter, greaterThan(afterEighth));
      expect(afterQuarter, lessThan(2 * afterEighth));
    });

    test('the last slice is the bar end and widths include the lead', () {
      expect(layout.slices.last.at, at(1, 1));
      expect(layout.slices.last.ideal, 0);
      expect(layout.lead, style.spacing.barPad);
      expect(
        layout.widths.body,
        closeTo(layout.lead + naturalWidth(layout.slices), 1e-9),
      );
      expect(
        layout.widths.minBody,
        closeTo(layout.lead + rodWidth(layout.slices), 1e-9),
      );
      expect(layout.widths.body, greaterThanOrEqualTo(layout.widths.minBody));
    });

    test('an accidental on the first slice widens the lead', () {
      final sharp = layoutOf(barOf([chordOf(1, 'C#5', value: whole)]));

      expect(sharp.lead, greaterThan(style.spacing.barPad + 1));
    });
  });

  group('layoutBar is a function of the view', () {
    List<StaffSpec> bar(String pitch) => [
      staffOf([
        chordOf(1, pitch, value: eighth),
        chordOf(2, 'D5', value: eighth),
        chordOf(3, 'E#5', value: dottedHalf),
      ]),
    ];
    final shared = [
      staffOf(
        [
          chordOf(11, 'C4 D4', graces: [graceOf(12, 'B3')]),
          chordOf(13, 'F#4', value: eighth),
          chordOf(14, 'G4', value: eighth),
          restOf(15, NoteValue.quarter),
          chordOf(16, 'A4', value: eighth),
          chordOf(17, 'B4', value: eighth),
        ],
        two: [chordOf(18, 'E4', value: whole)],
      ),
    ];

    test('the same bar after different bars lays out equal', () {
      final a = layoutOf(viewOf(scoreOf([bar('C5'), shared]), 1));
      final b = layoutOf(viewOf(scoreOf([bar('G5'), shared]), 1));

      expect(a, b);
      expect(a.items, isNotEmpty);
      expect(a.beams, hasLength(2));
    });

    test('a different bar lays out differently', () {
      final a = layoutOf(viewOf(scoreOf([bar('C5'), shared])));
      final b = layoutOf(viewOf(scoreOf([bar('G5'), shared])));

      expect(a, isNot(b));
    });

    test('the layout keeps no bar number and names its measure', () {
      final layout = layoutOf(viewOf(scoreOf([bar('C5'), shared]), 1));

      expect(layout.measure, const MeasureId(3001));
      expect(layout.length, Meter.fourFour.length);
      expect(layout.breakBefore, isNull);
    });
  });

  group('content', () {
    test('beamed chords get a beam plan and no stem items', () {
      final layout = layoutOf(
        barOf([
          chordOf(1, 'C4', value: eighth),
          chordOf(2, 'D4', value: eighth),
          chordOf(3, 'E4'),
          chordOf(4, 'F4', value: half),
        ]),
      );
      final stems = layout.items
          .map((i) => i.drawable)
          .whereType<LineDraw>()
          .where((l) => l.from.x == l.to.x);

      expect(layout.beams, hasLength(1));
      expect(layout.beams.single.stems.map((s) => s.slice), [0, 1]);
      expect(stems, hasLength(2));
    });

    test('rests and chords of every voice are placed', () {
      final layout = layoutOf(
        barOf(
          [restOf(1, NoteValue.quarter), chordOf(2, 'C5', value: dottedHalf)],
          two: [
            chordOf(3, 'A4', value: half),
            restOf(4, half),
          ],
        ),
      );
      final glyphs = layout.items.map((i) => i.drawable).whereType<GlyphDraw>();

      expect(
        glyphs.where((g) => g.glyph == Glyph.restQuarter).single.origin.y,
        1,
      );
      expect(glyphs.where((g) => g.glyph == Glyph.restHalf).single.origin.y, 3);
      expect(glyphs.where((g) => g.glyph == Glyph.noteheadHalf), hasLength(2));
    });

    test('a measure rest bar is rest only and centred', () {
      final layout = layoutOf(
        viewOf(
          scoreOf([
            [
              staffOf([chordOf(1, 'C5', value: whole)]),
            ],
            [
              staffOf([MeasureRest(id: const EventId(2), span: whole.length)]),
            ],
          ]),
          1,
        ),
      );
      final xs = sliceXs(layout.slices, 1, 0);
      final frame = BarFrame(left: 0, xs: xs, tops: const [0]);
      final rest = frame.place(layout.items.single) as GlyphDraw;

      expect(layout.restOnly, isTrue);
      expect(layout.slices, hasLength(2));
      expect(layout.items.single.centred, isTrue);
      expect(
        (rest.bounds.left + rest.bounds.right) / 2,
        closeTo((xs.last + xs.first) / 2, 1e-9),
      );
    });

    test('each staff reports how far its notes and its clef reach outside '
        'it', () {
      final layout = layoutOf(
        viewOf(
          scoreOf([
            [
              staffOf([chordOf(1, 'C6', value: whole)]),
              staffOf([chordOf(2, 'E3', value: whole)], clef: Clef.bass),
              staffOf([chordOf(3, 'C2', value: whole)], clef: Clef.bass),
            ],
          ]),
        ),
      );

      expect(layout.staves.map((s) => s.lines), [5, 5, 5]);
      expect(layout.staves[0].above, greaterThan(2), reason: 'the C6');
      expect(
        layout.staves[0].below,
        closeTo(1.632, 1e-9),
        reason: 'the tail of the G clef',
      );
      expect(
        layout.staves[1].above,
        closeTo(0.048, 1e-9),
        reason: 'the top of the F clef',
      );
      expect(layout.staves[1].below, 0, reason: 'an E3 inside the staff');
      expect(layout.staves[2].above, closeTo(0.048, 1e-9));
      expect(layout.staves[2].below, greaterThan(1), reason: 'the C2');
    });

    test('what only the inline head prints counts toward the reach', () {
      final score = after(
        beatsScore(2, key: const KeySignature(3)),
        [SetKey(from: barId(1), key: KeySignature.cMajor)],
      );

      expect(
        layoutOf(viewOf(score, 1)).staves.single.above,
        closeTo(1.864, 1e-9),
        reason:
            'the natural on G5, which the system head leaves to the '
            'courtesy',
      );
    });

    test('a beam counts toward the reach of its staff', () {
      final layout = layoutOf(
        barOf([
          chordOf(1, 'C6', value: eighth, stem: StemDirection.up),
          chordOf(2, 'C6', value: eighth, stem: StemDirection.up),
          chordOf(3, 'C6', value: half),
        ]),
      );

      expect(layout.beams.single.stem, StemSide.up);
      expect(
        layout.staves.single.above,
        closeTo(-yOfStep(12) + stemLength, 1e-9),
      );
      expect(layout.staves.single.above, greaterThan(5));
    });

    test('the edges name the barline and whether the bar start joins the one before', () {
      final score = scoreOf([
        [
          staffOf([chordOf(1, 'C5', value: whole)]),
        ],
        [
          staffOf([chordOf(2, 'C5', value: whole)]),
        ],
      ]);
      final first = layoutOf(viewOf(score));
      final second = layoutOf(viewOf(score, 1));

      expect(first.edges.startJoins, isFalse);
      expect(second.edges.startJoins, isTrue);
      expect(second.edges.end, Barline.regular);
      expect(second.edges.repeatStart, isFalse);
      expect(second.edges.repeatEnd, isNull);
    });
  });
}
