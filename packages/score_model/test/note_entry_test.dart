import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('Score.blank', () {
    test('numbers ids in document order and fills bars with measure rests', () {
      final score = Score.blank(
        parts: const [morinKhuur],
        measureCount: 3,
        meter: Meter.threeFour,
      );

      expect(score.parts.single.id, const PartId(1));
      expect(score.staves.single.id, const StaffId(2));
      expect([for (final m in score.measures) m.id.value], [3, 5, 7]);
      expect(firstEvent(score, 2).id, const EventId(8));
      expect(bar(score, 0), ['measure-rest']);
      expect(voiceOf(score, 0).length, len(3, 4));
      expect(score.measures.first.staves.single.clef, Clef.treble);
      expect(score.measures.first.tempos.single.offset, Moment.zero);
      expect(score.measures[1].tempos, isEmpty);
    });
  });

  group('EditSession.start', () {
    test('puts the cursor at the start of the first bar with nothing '
        'selected', () {
      final session = blank();

      expect(session.cursor, point(session.score, 0, Moment.zero));
      expect(session.selection.isEmpty, isTrue);
      expect(session.canUndo, isFalse);
    });

    test('puts the cursor on the first shown staff', () {
      final score = hidePart(
        blankScore(parts: const [morinKhuur, clarinet]),
        0,
      );

      expect(EditSession.start(score).cursor.staff, score.staves[1].id);
    });

    test('mints ids above every id in a loaded score', () {
      final session = EditSession.start(
        scoreWith([chord(40, f4, NoteValue.whole)]),
      );

      final next = enterAt(session, 0, Moment.zero);

      expect(firstEvent(next.score, 0).id.value, greaterThan(102));
    });
  });

  group('entering a note', () {
    test('overwrites a measure rest and fills the rest of the bar', () {
      final start = blank();

      final session = enterAt(start, 0, Moment.zero);

      expect(bar(session.score, 0), [
        'F4/quarter',
        'rest/quarter',
        'rest/half',
      ]);
      expect(
        identical(session.score.measures[1], start.score.measures[1]),
        isTrue,
      );
      expect(session.cursor, point(session.score, 0, at(1, 4)));
      final selected = session.selection.singleEvent!;
      expect(selected.id, firstEvent(session.score, 0).id);
      expect(selected.measure, session.score.measures.first.id);
    });

    test('four quarters move the cursor to the next bar', () {
      var session = blank();
      for (var i = 0; i < 4; i++) {
        session = applied(enter(session, session.cursor));
      }

      expect(bar(session.score, 0), [
        'F4/quarter',
        'F4/quarter',
        'F4/quarter',
        'F4/quarter',
      ]);
      expect(session.cursor, point(session.score, 1, Moment.zero));
    });

    test('keeps the cut head of a note, with its id', () {
      final session = EditSession.start(
        scoreWith([
          chord(1, f4, NoteValue.half),
          rest(2, NoteValue.half),
        ]),
      );

      final next = enterAt(session, 0, at(1, 4), tone: g4);

      expect(bar(next.score, 0), ['F4/quarter', 'G4/quarter', 'rest/half']);
      expect(firstEvent(next.score, 0).id, const EventId(1));
    });

    test('ties a head that needs two values', () {
      final session = EditSession.start(
        scoreWith([chord(1, f4, NoteValue.whole)]),
      );

      final next = enterAt(
        session,
        0,
        at(5, 8),
        tone: g4,
        value: NoteValue.eighth,
      );

      expect(bar(next.score, 0), [
        'F4/half~',
        'F4/eighth',
        'G4/eighth',
        'rest/quarter',
      ]);
      expect(firstEvent(next.score, 0).id, const EventId(1));
    });

    test('turns the tail of a note into rests', () {
      final session = EditSession.start(
        scoreWith([chord(1, f4, NoteValue.whole)]),
      );

      final next = enterAt(session, 0, Moment.zero, tone: g4);

      expect(bar(next.score, 0), ['G4/quarter', 'rest/quarter', 'rest/half']);
    });

    test('writes the entered value as is when it fits', () {
      final next = enterAt(blank(), 0, at(1, 4), value: NoteValue.half);

      expect(bar(next.score, 0), ['rest/quarter', 'F4/half', 'rest/quarter']);
    });
  });

  group('overfill', () {
    test('splits at the barline and ties into the next bar', () {
      final session = enterAt(blank(), 0, at(3, 4), value: NoteValue.half);

      expect(bar(session.score, 0), [
        'rest/half',
        'rest/quarter',
        'F4/quarter~',
      ]);
      expect(bar(session.score, 1), [
        'F4/quarter',
        'rest/quarter',
        'rest/half',
      ]);
      expect(session.cursor, point(session.score, 1, at(1, 4)));
    });

    test('refuses with the excess and leaves the session alone', () {
      final session = blank();

      final outcome = enter(
        session,
        point(session.score, 0, at(3, 4)),
        value: NoteValue.half,
        overfill: Overfill.refuse,
      );

      final refused = outcome as Refused;
      final reason = refused.reason as WouldCrossBarline;
      expect(reason.measure, session.score.measures.first.id);
      expect(reason.excess, len(1, 4));
      expect(identical(refused.session, session), isTrue);
    });

    test('appends bars past the end of the score', () {
      final session = enterAt(
        blank(bars: 1),
        0,
        at(3, 4),
        value: NoteValue.whole,
      );

      expect(session.score.measures.length, 2);
      expect(bar(session.score, 0).last, 'F4/quarter~');
      expect(bar(session.score, 1), ['F4/half.', 'rest/quarter']);
      expect(session.cursor, point(session.score, 1, at(3, 4)));
    });

    test('appends a bar for the cursor when the write ends the score', () {
      final session = enterAt(
        blank(bars: 1),
        0,
        Moment.zero,
        value: NoteValue.whole,
      );

      expect(session.score.measures.length, 2);
      expect(bar(session.score, 1), ['measure-rest']);
      expect(session.cursor, point(session.score, 1, Moment.zero));
    });
  });

  group('ties into the entry point', () {
    EditSession tiedAcross() =>
        enterAt(blank(), 0, at(3, 4), value: NoteValue.half);

    test('are cleared when the new note has another pitch', () {
      final session = enterAt(tiedAcross(), 1, Moment.zero, tone: g4);

      expect(bar(session.score, 0).last, 'F4/quarter');
    });

    test('are kept when the new note has the tied pitch', () {
      final session = enterAt(tiedAcross(), 1, Moment.zero);

      expect(bar(session.score, 0).last, 'F4/quarter~');
    });
  });

  group('voice two', () {
    test('fills around new notes with gaps and leaves voice one alone', () {
      final start = blank();

      final session = enterAt(start, 0, at(1, 4), voice: VoiceSlot.two);

      expect(bar(session.score, 0, slot: VoiceSlot.two), [
        'gap 1/4',
        'F4/quarter',
        'gap 1/2',
      ]);
      expect(
        identical(voiceOf(session.score, 0), voiceOf(start.score, 0)),
        isTrue,
      );
    });

    test('merges the gaps left by an overwrite', () {
      var session = enterAt(blank(), 0, at(1, 4), voice: VoiceSlot.two);

      session = enterAt(
        session,
        0,
        at(1, 4),
        tone: g4,
        voice: VoiceSlot.two,
        value: NoteValue.eighth,
      );

      expect(bar(session.score, 0, slot: VoiceSlot.two), [
        'gap 1/4',
        'G4/eighth',
        'gap 5/8',
      ]);
    });
  });

  group('tuplets', () {
    Score triplet() => scoreWith([
      tripletOfEighths(1, [
        rest(2, NoteValue.eighth),
        rest(3, NoteValue.eighth),
        rest(4, NoteValue.eighth),
      ]),
      rest(5, NoteValue.quarter),
      rest(6, NoteValue.half),
    ]);

    test('an entry inside a triplet writes a triplet note', () {
      final session = enterAt(
        EditSession.start(triplet()),
        0,
        at(1, 12),
        value: NoteValue.eighth,
      );

      expect(bar(session.score, 0), [
        '3:2[rest/eighth, F4/eighth, rest/eighth]',
        'rest/quarter',
        'rest/half',
      ]);
      expect(session.cursor, point(session.score, 0, at(1, 6)));
    });

    test('a note that would run out of the triplet is refused', () {
      final session = EditSession.start(triplet());

      final outcome = enter(
        session,
        point(session.score, 0, at(1, 6)),
      );

      final reason = (outcome as Refused).reason as WouldSplitTuplet;
      expect(reason.tuplet, const TupletId(1));
      expect(reason.measure, const MeasureId(102));
    });

    test('a write covering a whole triplet removes it', () {
      final session = EditSession.start(
        scoreWith([
          rest(5, NoteValue.quarter),
          tripletOfEighths(1, [
            rest(2, NoteValue.eighth),
            rest(3, NoteValue.eighth),
            rest(4, NoteValue.eighth),
          ]),
          rest(6, NoteValue.half),
        ]),
      );

      final next = enterAt(session, 0, Moment.zero, value: NoteValue.half);

      expect(bar(next.score, 0), ['F4/half', 'rest/half']);
    });

    test('a write covering part of a triplet leaves rests for the rest', () {
      final session = EditSession.start(
        scoreWith([
          rest(5, NoteValue.quarter),
          tripletOfEighths(1, [
            rest(2, NoteValue.eighth),
            rest(3, NoteValue.eighth),
            rest(4, NoteValue.eighth),
          ]),
          rest(6, NoteValue.half),
        ]),
      );

      final next = enterAt(session, 0, at(1, 8));

      expect(bar(next.score, 0), [
        'rest/eighth',
        'F4/quarter',
        'rest/eighth',
        'rest/half',
      ]);
      expect(firstEvent(next.score, 0).id, const EventId(5));
    });
  });

  group('entering a rest', () {
    test('cuts the note it lands in and selects the rest', () {
      final session = EditSession.start(
        scoreWith([chord(1, f4, NoteValue.whole)]),
      );

      final next = applied(
        session.run(
          EnterRest(
            at: point(session.score, 0, at(1, 4)),
            value: NoteValue.quarter,
          ),
        ),
      );

      expect(bar(next.score, 0), ['F4/quarter', 'rest/quarter', 'rest/half']);
      final selected = next.selection.singleEvent!;
      expect(next.score.lookup(selected)!.event, isA<RestEvent>());
      expect(next.cursor, point(next.score, 0, at(1, 2)));
    });
  });

  group('refusals', () {
    test('a point in a measure that is gone is a stale reference', () {
      final session = blank();

      final gone = VoicePoint(
        staff: session.score.staves.first.id,
        voice: VoiceSlot.one,
        at: const ScorePoint(MeasureId(999), Moment.zero),
      );

      final outcome = enter(session, gone);

      expect(((outcome as Refused).reason as StaleReference).target, gone);
    });

    test('an offset at the barline is outside the measure', () {
      final session = blank();
      final end = point(session.score, 0, at(1, 1));

      final outcome = enter(session, end);

      expect(((outcome as Refused).reason as OutsideMeasure).at, end.at);
    });

    test('a point off the 128th-note grid is an invalid value', () {
      final session = blank();

      final outcome = enter(session, point(session.score, 0, at(1, 192)));

      expect(
        ((outcome as Refused).reason as InvalidValue).message,
        'a note starts a whole number of 128th notes into its bar or tuplet',
      );
    });

    test('a point off the written grid of a tuplet is an invalid value', () {
      final session = EditSession.start(
        scoreWith([
          Tuplet(
            id: const TupletId(1),
            ratio: TupletRatio.duplet,
            unit: NoteValue.quarter,
            members: Seq([
              rest(2, NoteValue.quarter),
              rest(3, NoteValue.quarter),
            ]),
          ),
          rest(4, NoteValue.quarter),
        ]),
      );

      final outcome = enter(
        session,
        point(session.score, 0, at(1, 8)),
        value: NoteValue.sixteenth,
      );

      expect(
        ((outcome as Refused).reason as InvalidValue).message,
        'a note starts a whole number of 128th notes into its bar or tuplet',
      );
    });
  });

  group('history', () {
    test('undo restores the score, cursor and selection; redo reapplies', () {
      final start = blank();
      final entered = enterAt(start, 0, Moment.zero);

      final undone = entered.undo();

      expect(
        identical(undone.score.measures, start.score.measures),
        isTrue,
      );
      expect(undone.cursor, start.cursor);
      expect(undone.selection.isEmpty, isTrue);
      expect(undone.canRedo, isTrue);
      expect(undone.redoLabel, 'Enter note');

      final redone = undone.redo();

      expect(
        identical(redone.score.measures, entered.score.measures),
        isTrue,
      );
      expect(redone.cursor, entered.cursor);
    });

    test('ids are never reissued, even after undo', () {
      final start = blank();
      final first = enterAt(start, 0, Moment.zero);
      final firstId = firstEvent(first.score, 0).id.value;

      final again = enterAt(first.undo(), 0, Moment.zero);

      expect(firstId, greaterThan(4));
      expect(firstEvent(again.score, 0).id.value, greaterThan(firstId));
    });
  });

  group('finding events', () {
    Score halves() => scoreWith([
      chord(1, f4, NoteValue.half),
      rest(2, NoteValue.half),
    ]);

    test('eventAt finds the event sounding at a point', () {
      final score = halves();

      final hit = score.eventAt(point(score, 0, at(1, 4)))!;

      expect(hit.event.id, const EventId(1));
      expect(hit.onset, Moment.zero);
      expect(hit.duration, len(1, 2));
      expect(
        score.eventAt(point(score, 0, at(1, 4), voice: VoiceSlot.two)),
        isNull,
      );
    });

    test('eventAt scales time inside tuplets', () {
      final score = scoreWith([
        tripletOfEighths(1, [
          rest(2, NoteValue.eighth),
          rest(3, NoteValue.eighth),
          rest(4, NoteValue.eighth),
        ]),
        rest(5, NoteValue.quarter),
        rest(6, NoteValue.half),
      ]);

      final hit = score.eventAt(point(score, 0, at(1, 10)))!;

      expect(hit.event.id, const EventId(3));
      expect(hit.onset, at(1, 12));
      expect(hit.duration, len(1, 12));
      expect(hit.tuplets, [const TupletId(1)]);
    });

    test('lookup falls back to the event id when the hint is wrong', () {
      final score = halves();
      const stale = EventRef(
        measure: MeasureId(999),
        staff: StaffId(101),
        id: EventId(2),
      );

      final found = score.lookup(stale)!;

      expect(found.onset, at(1, 2));
      expect(found.ref.measure, const MeasureId(102));
      expect(score.locate(const EventId(77)), isNull);
    });
  });

  test('an edit without a cursor of its own keeps the session cursor', () {
    final entered = enterAt(blank(), 0, Moment.zero);

    final next = applied(
      entered.run(
        SetKey(
          from: entered.score.measures.first.id,
          key: const KeySignature(-1),
        ),
      ),
    );

    expect(next.cursor, entered.cursor);
    expect(next.selection.singleEvent, entered.selection.singleEvent);
  });
}
