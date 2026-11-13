import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

EnterNote noteAt(EditSession session, int bar, Moment offset, Pitch pitch) =>
    EnterNote(
      at: point(session.score, bar, offset),
      tone: pitch,
      value: NoteValue.quarter,
    );

EventId selected(EditSession session) => session.selection.singleEvent!.id;

void main() {
  group('Batch', () {
    test('runs each edit on the score the edit before it left', () {
      final session = blank();

      final next = applied(
        session.run(
          Batch([
            noteAt(session, 0, Moment.zero, f4),
            noteAt(session, 0, at(1, 4), g4),
          ]),
        ),
      );

      expect(bar(next.score, 0), ['F4/quarter', 'G4/quarter', 'rest/half']);
    });

    test('is one undo step under its label', () {
      final session = blank();

      final next = applied(
        session.run(
          Batch([
            noteAt(session, 0, Moment.zero, f4),
            noteAt(session, 1, Moment.zero, g4),
          ], label: 'Two notes'),
        ),
      );
      final undone = next.undo();

      expect(next.undoLabel, 'Two notes');
      expect(undone.canUndo, isFalse);
      expect(bar(undone.score, 0), bar(session.score, 0));
      expect(bar(undone.score, 1), bar(session.score, 1));
      expect(undone.cursor, session.cursor);
    });

    test('ends where running its edits one by one ends', () {
      final session = blank(bars: 3);
      final edits = [
        noteAt(session, 0, Moment.zero, f4),
        SetMeter(from: idOf(session, 0), meter: Meter.threeFour),
      ];

      final batched = applied(session.run(Batch(edits)));
      final stepped = edits.fold(
        session,
        (now, edit) => applied(now.run(edit)),
      );

      expect(
        [for (final c in batched.score.measures) c.length],
        [for (final c in stepped.score.measures) c.length],
      );
      expect(
        [for (var i = 0; i < 3; i++) bar(batched.score, i)],
        [for (var i = 0; i < 3; i++) bar(stepped.score, i)],
      );
      expect(batched.cursor, stepped.cursor);
      expect(batched.cursor.at.offset, at(1, 4));
      expect(selected(batched), selected(stepped));
      expect(firstEvent(batched.score, 0).id, firstEvent(stepped.score, 0).id);
    });

    test('mints each id once', () {
      final session = blank();

      final next = applied(
        session.run(
          Batch([
            noteAt(session, 0, Moment.zero, f4),
            noteAt(session, 1, Moment.zero, g4),
          ]),
        ),
      );
      final after = applied(next.run(noteAt(next, 0, at(1, 2), f4)));

      final ids = {
        firstEvent(after.score, 0).id,
        firstEvent(after.score, 1).id,
        selected(after),
      };
      expect(ids, hasLength(3));
    });

    test('is refused whole when one of its edits is refused', () {
      final session = blank();

      final outcome = session.run(
        Batch([
          noteAt(session, 0, Moment.zero, f4),
          SetClef(
            staff: const StaffId(999),
            at: pointAt(session.score, 0, Moment.zero),
            clef: Clef.bass,
          ),
        ]),
      );

      expect(
        refusal(outcome),
        isA<StaleReference>().having(
          (r) => r.target,
          'target',
          const StaffId(999),
        ),
      );
      expect(identical(outcome.session, session), isTrue);
    });

    test('adds no undo step when it changes nothing', () {
      final session = blank();

      for (final edits in <List<Edit>>[
        [],
        [
          SetClef(
            staff: session.score.staves.first.id,
            at: pointAt(session.score, 0, Moment.zero),
            clef: Clef.treble,
          ),
        ],
      ]) {
        final next = applied(session.run(Batch(edits)));

        expect(identical(next.score, session.score), isTrue);
        expect(next.canUndo, isFalse);
      }
    });
  });
}
