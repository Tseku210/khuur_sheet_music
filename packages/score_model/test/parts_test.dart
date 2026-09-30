import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

EditSession edited(EditSession session, Edit edit) =>
    applied(session.run(edit));

List<String> names(Score score) => [for (final part in score.parts) part.name];

void expectStavesInOrder(Score score) {
  final order = [for (final staff in score.staves) staff.id];
  for (final column in score.measures) {
    expect([for (final measure in column.staves) measure.staff], order);
  }
}

EditSession withCursor(Score score, int staff) =>
    EditSession.start(score).placeCursor(
      VoicePoint(
        staff: score.staves[staff].id,
        voice: VoiceSlot.two,
        at: pointAt(score, 1, at(1, 4)),
      ),
    );

/// Where [session]'s cursor is, as (staff index, bar index, offset, voice).
(int, int, Moment, VoiceSlot) cursorOf(EditSession session) {
  final VoicePoint(:staff, :voice, :at) = session.cursor;
  return (
    session.score.staves.indexWhere((s) => s.id == staff),
    session.score.indexOf(at.measure),
    at.offset,
    voice,
  );
}

const violin = PartTemplate(
  name: 'Violin',
  shortName: 'Vln.',
  instrument: Instrument(key: 'violin', program: 40),
);

void main() {
  group('AddPart', () {
    test('adds a part at the bottom with a measure rest in every bar', () {
      final session = EditSession.start(blankScore());

      final score = edited(session, const AddPart(piano)).score;

      expect(names(score), ['Морин хуур', 'Piano']);
      expect(score.parts.last.staves.length, 2);
      expectStavesInOrder(score);
      for (final column in score.measures) {
        final added = column.staves.skip(1);
        expect(
          [for (final measure in added) measure.clef],
          [
            Clef.treble,
            Clef.bass,
          ],
        );
        expect(
          [
            for (final measure in added)
              describe(measure.voice(VoiceSlot.one)!.items),
          ],
          [
            ['measure-rest'],
            ['measure-rest'],
          ],
        );
        expect(
          identical(
            column.staves.first,
            session.score.column(column.id).staves.first,
          ),
          isTrue,
        );
      }
    });

    test('adds a part at an index with its name and instrument', () {
      final session = EditSession.start(
        blankScore(parts: const [piano, drums]),
      );

      final first = edited(session, const AddPart(violin, index: 0)).score;
      final middle = edited(session, const AddPart(clarinet, index: 1)).score;
      final last = edited(session, const AddPart(clarinet, index: 2)).score;

      expect(names(first), ['Violin', 'Piano', 'Drums']);
      expect(names(middle), ['Piano', 'Clarinet in B♭', 'Drums']);
      expect(names(last), ['Piano', 'Drums', 'Clarinet in B♭']);
      expect(first.parts.first.shortName, 'Vln.');
      expect(middle.parts[1].instrument, clarinet.instrument);
      expect(middle.measures.first.staves[2].clef, Clef.treble);
      expect(middle.measures.first.staves[3].clef, Clef.percussion);
      expectStavesInOrder(first);
      expectStavesInOrder(middle);
      expectStavesInOrder(last);
    });

    test('fills a short bar', () {
      final session = edited(
        blank(),
        SetBarLength(idOf(blank(), 0), len(1, 4)),
      );

      final score = edited(session, const AddPart(violin)).score;

      final rest =
          score.measures.first.staves.last.voice(VoiceSlot.one)!.items.single
              as MeasureRest;
      expect(rest.span, len(1, 4));
    });

    test('mints new ids for the part, its staves and its rests', () {
      final session = EditSession.start(blankScore(bars: 3));

      final twice = edited(
        edited(session, const AddPart(piano)),
        const AddPart(piano),
      ).score;

      final staves = [for (final staff in twice.staves) staff.id];
      expect(staves.toSet().length, 5);
      expect({for (final part in twice.parts) part.id}.length, 3);
      for (final (k, staff) in staves.indexed) {
        for (final column in twice.measures) {
          final rest =
              column.staves[k].voice(VoiceSlot.one)!.items.single
                  as MeasureRest;
          expect(twice.locate(rest.id)?.staff, staff);
        }
      }
    });

    test('keeps the cursor and the selection', () {
      final score = blankScore(parts: const [morinKhuur, piano]);
      final session = withCursor(score, 1).select(
        RangeSelection(
          from: pointAt(score, 0, Moment.zero),
          to: pointAt(score, 1, Moment.zero),
          top: score.staves[0].id,
          bottom: score.staves[2].id,
        ),
      );

      final next = edited(session, const AddPart(violin, index: 1));

      expect(next.cursor, session.cursor);
      expect(identical(next.selection, session.selection), isTrue);
    });

    test('refuses a place outside the parts or a malformed template', () {
      final session = EditSession.start(blankScore());

      for (final edit in [
        const AddPart(violin, index: -1),
        const AddPart(violin, index: 2),
        AddPart(
          PartTemplate(name: 'None', instrument: violin.instrument, staves: 0),
        ),
        AddPart(
          PartTemplate(
            name: 'Organ',
            instrument: violin.instrument,
            staves: 3,
            clefs: const [Clef.treble, Clef.bass],
          ),
        ),
      ]) {
        expect(refusal(session.run(edit)), isA<InvalidValue>());
      }
    });
  });

  group('RemovePart', () {
    test('removes its staves from every bar, with their spanners', () {
      var score = blankScore(parts: const [morinKhuur, piano]);
      for (final staff in [0, 1, 2]) {
        score = withSlur(
          score,
          pointAt(score, 0, Moment.zero),
          pointAt(score, 1, Moment.zero),
          staff: staff,
        );
      }
      final session = EditSession.start(score);

      final next = edited(session, RemovePart(score.parts[1].id)).score;

      expect(names(next), ['Морин хуур']);
      expectStavesInOrder(next);
      expect([for (final s in next.spanners) s.staff], [score.staves[0].id]);
      for (final column in next.measures) {
        expect(
          identical(
            column.staves.single,
            score.column(column.id).staves.first,
          ),
          isTrue,
        );
      }
    });

    test('moves a cursor on it to the nearest shown staff', () {
      final score = hidePart(
        hidePart(
          blankScore(parts: const [piano, morinKhuur, clarinet, piano]),
          1,
        ),
        2,
      );

      final below = edited(
        withCursor(score, 0),
        RemovePart(score.parts[0].id),
      );
      final above = edited(
        withCursor(score, 5),
        RemovePart(score.parts[3].id),
      );
      final elsewhere = edited(
        withCursor(score, 0),
        RemovePart(score.parts[3].id),
      );

      expect(below.cursor.staff, score.staves[4].id);
      expect(above.cursor.staff, score.staves[1].id);
      expect(
        (below.cursor.voice, below.cursor.at),
        (
          VoiceSlot.two,
          pointAt(score, 1, at(1, 4)),
        ),
      );
      expect(elsewhere.cursor, withCursor(score, 0).cursor);
    });

    test('drops a selection on it', () {
      final score = blankScore(parts: const [morinKhuur, piano]);
      final session = EditSession.start(score).select(
        RangeSelection(
          from: pointAt(score, 0, Moment.zero),
          to: pointAt(score, 1, Moment.zero),
          top: score.staves[0].id,
          bottom: score.staves[1].id,
        ),
      );

      final next = edited(session, RemovePart(score.parts[1].id));

      expect(next.selection.isEmpty, isTrue);
    });

    test('refuses the last shown part or a stale part', () {
      final score = hidePart(blankScore(parts: const [morinKhuur, piano]), 1);
      final session = EditSession.start(score);

      expect(
        refusal(
          EditSession.start(blankScore()).run(RemovePart(score.parts[0].id)),
        ),
        isA<WouldEmptyScore>(),
      );
      expect(
        refusal(session.run(RemovePart(score.parts[0].id))),
        isA<WouldEmptyScore>(),
      );
      expect(names(edited(session, RemovePart(score.parts[1].id)).score), [
        'Морин хуур',
      ]);
      expect(
        refusal(session.run(const RemovePart(PartId(999)))),
        isA<StaleReference>(),
      );
    });
  });

  group('SetPartHidden', () {
    test('hides and shows a part and keeps the rest of it', () {
      final score = blankScore(parts: const [morinKhuur, violin]);
      final session = EditSession.start(score);

      final hidden = edited(
        session,
        SetPartHidden(score.parts[1].id, hidden: true),
      );
      final shown = edited(
        hidden,
        SetPartHidden(score.parts[1].id, hidden: false),
      );

      final part = hidden.score.parts[1];
      expect(part.hidden, isTrue);
      expect(shown.score.parts[1].hidden, isFalse);
      expect(
        (part.id, part.name, part.shortName),
        (
          score.parts[1].id,
          'Violin',
          'Vln.',
        ),
      );
      expect(identical(part.instrument, score.parts[1].instrument), isTrue);
      expect(identical(part.staves, score.parts[1].staves), isTrue);
      expect(identical(hidden.score.parts[0], score.parts[0]), isTrue);
      expect(identical(hidden.score.measures, score.measures), isTrue);
      expect(hidden.undoLabel, 'Hide instrument');
      expect(shown.undoLabel, 'Show instrument');
    });

    test('changes nothing when the part already is so', () {
      final score = hidePart(blankScore(parts: const [morinKhuur, piano]), 1);
      final session = EditSession.start(score);

      expect(
        changesNothing(session, SetPartHidden(score.parts[1].id, hidden: true)),
        isTrue,
      );
      expect(
        changesNothing(
          session,
          SetPartHidden(score.parts[0].id, hidden: false),
        ),
        isTrue,
      );
    });

    test('moves a cursor off a part it hides', () {
      final score = blankScore(parts: const [morinKhuur, piano]);

      final hidden = edited(
        withCursor(score, 2),
        SetPartHidden(score.parts[1].id, hidden: true),
      );
      final other = edited(
        withCursor(score, 0),
        SetPartHidden(score.parts[1].id, hidden: true),
      );
      final shown = edited(
        EditSession.start(
          hidePart(score, 1),
        ).placeCursor(withCursor(score, 2).cursor),
        SetPartHidden(score.parts[1].id, hidden: false),
      );

      expect(cursorOf(hidden), (0, 1, at(1, 4), VoiceSlot.two));
      expect(cursorOf(other), (0, 1, at(1, 4), VoiceSlot.two));
      expect(cursorOf(shown), (2, 1, at(1, 4), VoiceSlot.two));
    });

    test('refuses hiding the last shown part or a stale part', () {
      final score = hidePart(blankScore(parts: const [morinKhuur, piano]), 1);
      final session = EditSession.start(score);

      expect(
        refusal(session.run(SetPartHidden(score.parts[0].id, hidden: true))),
        isA<WouldEmptyScore>(),
      );
      expect(
        refusal(session.run(const SetPartHidden(PartId(999), hidden: true))),
        isA<StaleReference>(),
      );
    });
  });
}
