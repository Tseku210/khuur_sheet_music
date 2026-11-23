import 'package:khuur_score_layout/src/drawable.dart';
import 'package:khuur_score_layout/src/sheet_layout.dart';
import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import '../../khuur_score_model/test/support.dart';
import 'support/fake_measurer.dart';
import 'support/sheets.dart';

const FakeMeasurer text = FakeMeasurer();

SheetLayout sheetOf(Score score, {double width = 120}) =>
    SheetLayout(score, width: width, text: text);

EventRef eventRef(Score score, int bar, int event) => EventRef(
  measure: score.measures[bar].id,
  staff: score.staves.first.id,
  id: EventId(event),
);

double lineEndY(SheetLayout sheet) => [
  for (var i = 0; i < sheet.systemCount; i++)
    ...sheet
        .systemAt(i)
        .drawables
        .whereType<LineDraw>()
        .where((line) => line.owner == const SpannerOwner(SpannerId(900))),
].last.to.y;

double headMiddleY(
  SheetLayout sheet,
  Score score,
  int bar,
  int event,
  int note,
) {
  final head = [
    for (var i = 0; i < sheet.systemCount; i++)
      ...sheet
          .systemAt(i)
          .drawables
          .whereType<GlyphDraw>()
          .where(
            (glyph) =>
                glyph.owner ==
                ElementOwner(
                  NoteRef(eventRef(score, bar, event), NoteId(note)),
                ),
          ),
  ].single.bounds;
  return (head.top + head.bottom) / 2;
}

Score bars(List<List<VoiceItem>> bars, {List<VoiceItem>? lastBarTwo}) {
  var score = blankScore(parts: const [clarinet], bars: bars.length);
  for (final (index, items) in bars.indexed) {
    if (items.isNotEmpty) {
      score = fill(score, index, items);
    }
  }
  return lastBarTwo == null
      ? score
      : fill(score, bars.length - 1, lastBarTwo, slot: VoiceSlot.two);
}

void main() {
  group('A glissando whose last end names no note and falls on a rest of '
      'its own voice', () {
    test('runs to the head of the chord voice two starts there', () {
      final plain = bars(
        [
          [
            chordOf(1, 'C4'),
            rest(2, NoteValue.quarter),
            chordOf(3, 'C5', value: NoteValue.half),
          ],
        ],
        lastBarTwo: [Gap(len(1, 4)), chordOf(5, 'G4'), Gap(len(1, 2))],
      );
      final score = withSpanner(
        plain,
        const Glissando(),
        pointAt(plain, 0, Moment.zero),
        pointAt(plain, 0, at(1, 4)),
      );
      final sheet = sheetOf(score);

      expect(
        lineEndY(sheet),
        closeTo(headMiddleY(sheet, score, 0, 5, 50), 1e-9),
      );
    });

    test('keeps that end in an update after an edit two bars before it, as '
        'a fresh layout draws it', () {
      for (final width in [120.0, 45.0, 25.0]) {
        final plain = bars(
          [
            [chordOf(1, 'G4', value: NoteValue.whole)],
            [],
            [
              rest(2, NoteValue.quarter),
              chordOf(3, 'C5', value: NoteValue.half),
              chordOf(4, 'C5'),
            ],
          ],
          lastBarTwo: [chordOf(5, 'D4'), Gap(len(3, 4))],
        );
        final score = withSpanner(
          plain,
          const Glissando(),
          pointAt(plain, 0, Moment.zero),
          pointAt(plain, 2, Moment.zero),
        );
        final layout = sheetOf(score, width: width);
        final next = applied(
          EditSession.start(score).run(
            AddToChord(event: eventRef(score, 0, 1), tone: Pitch.parse('E4')),
          ),
        ).score;

        final updated = layout.update(next);

        expect(
          lineEndY(updated),
          closeTo(headMiddleY(updated, next, 2, 5, 50), 1e-9),
          reason: 'width $width',
        );
        expectSameSheet(updated, sheetOf(next, width: width));
      }
    });
  });

  test('a glissando that names no end note runs into a crossing chord on '
      'the head of its lowest line', () {
    final plain = bars([
      [
        chordOf(1, 'C4'),
        chordOf(2, 'Cb4 B#3'),
        chordOf(3, 'C5', value: NoteValue.half),
      ],
    ]);
    final score = withSpanner(
      plain,
      const Glissando(),
      pointAt(plain, 0, Moment.zero),
      pointAt(plain, 0, at(1, 4)),
    );
    final sheet = sheetOf(score);

    expect(lineEndY(sheet), closeTo(headMiddleY(sheet, score, 0, 2, 21), 1e-9));
  });

  test('a glissando into a crossing chord keeps the head of its lowest line '
      'in an update after an edit two bars before it', () {
    for (final width in [120.0, 45.0, 25.0]) {
      final plain = bars([
        [chordOf(1, 'C4', value: NoteValue.whole)],
        [],
        [chordOf(2, 'Cb4 B#3', value: NoteValue.whole)],
      ]);
      final score = withSpanner(
        plain,
        const Glissando(),
        pointAt(plain, 0, Moment.zero),
        pointAt(plain, 2, Moment.zero),
      );
      final layout = sheetOf(score, width: width);
      final next = applied(
        EditSession.start(score).run(
          AddToChord(event: eventRef(score, 0, 1), tone: Pitch.parse('E4')),
        ),
      ).score;

      final updated = layout.update(next);

      expect(
        lineEndY(updated),
        closeTo(headMiddleY(updated, next, 2, 2, 21), 1e-9),
        reason: 'width $width',
      );
      expectSameSheet(updated, sheetOf(next, width: width));
    }
  });
}
