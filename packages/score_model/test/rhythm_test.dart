import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

EditOutcome setValue(EditSession session, int id, NoteValue value) =>
    session.run(SetValue(eventRef(session, id), value));

EditSession valueSet(EditSession session, int id, NoteValue value) =>
    applied(setValue(session, id, value));

EditOutcome enterTuplet(
  EditSession session,
  int bar,
  Moment offset, {
  TupletRatio ratio = TupletRatio.triplet,
  NoteValue unit = NoteValue.eighth,
  VoiceSlot voice = VoiceSlot.one,
}) => session.run(
  EnterTuplet(
    at: point(session.score, bar, offset, voice: voice),
    ratio: ratio,
    unit: unit,
  ),
);

void main() {
  group('SetValue shorter', () {
    test('rests the time it frees', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half),
          chordOf(2, 'G4', value: NoteValue.half),
        ],
      ]);

      final next = valueSet(session, 1, NoteValue.quarter);

      expect(bar(next.score, 0), ['F4/quarter', 'rest/quarter', 'G4/half']);
    });

    test('keeps the ids, marks and notes of the event', () {
      final start = sessionWith([
        [
          chordOf(1, 'F4 A4', value: NoteValue.half),
          chordOf(2, 'G4', value: NoteValue.half),
        ],
      ]);
      final session = applied(
        start.run(
          SetArticulation(
            eventRef(start, 1),
            Articulation.accent,
            present: true,
          ),
        ),
      );

      final next = valueSet(session, 1, NoteValue.quarter.dotted);

      final chord = chordIn(next, 1);
      expect(chord.value, NoteValue.quarter.dotted);
      expect(chord.articulations, {Articulation.accent});
      expect(
        [for (final n in chord.notes) n.id],
        [
          const NoteId(10),
          const NoteId(11),
        ],
      );
    });

    test('leaves a gap in voice two', () {
      final score = fill(blankScore(), 0, [
        chordOf(1, 'F4', value: NoteValue.half),
        Gap(len(1, 2)),
      ], slot: VoiceSlot.two);
      final session = EditSession.start(score);

      final next = valueSet(session, 1, NoteValue.quarter);

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'F4/quarter',
        'gap 3/4',
      ]);
    });

    test('turns a measure rest into a rest of the value', () {
      final session = blank();
      final rest = firstEvent(session.score, 0);

      final next = applied(
        session.run(
          SetValue(
            EventRef(
              measure: idOf(session, 0),
              staff: session.score.staves.first.id,
              id: rest.id,
            ),
            NoteValue.quarter,
          ),
        ),
      );

      expect(bar(next.score, 0), ['rest/quarter', 'rest/quarter', 'rest/half']);
      expect(firstEvent(next.score, 0).id, rest.id);
    });

    test('keeps a hidden rest hidden', () {
      final session = sessionWith([
        [
          const RestEvent(id: EventId(1), value: NoteValue.half, hidden: true),
          rest(2, NoteValue.half),
        ],
      ]);

      final next = valueSet(session, 1, NoteValue.quarter);

      expect((eventOf(next, 1) as RestEvent).hidden, isTrue);
    });

    test('clears a tie to a note it no longer meets', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', tie: true),
          chordOf(2, 'F4', value: NoteValue.half.dotted),
        ],
      ]);

      final next = valueSet(session, 1, NoteValue.eighth);

      expect(tiesOf(next, 1), {'F4': false});
    });

    test('keeps a tie that rang on into a rest', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', tie: true),
          rest(2, NoteValue.half.dotted),
        ],
      ]);

      final next = valueSet(session, 1, NoteValue.eighth);

      expect(tiesOf(next, 1), {'F4': true});
    });
  });

  group('SetValue longer', () {
    test('overwrites what follows', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4'),
          chordOf(2, 'G4'),
          chordOf(3, 'A4', value: NoteValue.half),
        ],
      ]);

      final next = valueSet(session, 1, NoteValue.half);

      expect(bar(next.score, 0), ['F4/half', 'A4/half']);
      expect(chordIn(next, 1).notes.single.id, const NoteId(10));
    });

    test('splits and ties a note that now crosses the barline', () {
      final session = sessionWith([
        [rest(1, NoteValue.half.dotted), chordOf(2, 'F4')],
        [chordOf(3, 'G4', value: NoteValue.whole)],
      ]);

      final next = valueSet(session, 2, NoteValue.half);

      expect(bar(next.score, 0), ['rest/half.', 'F4/quarter~']);
      expect(bar(next.score, 1), ['F4/quarter', 'rest/quarter', 'rest/half']);
      expect(firstEvent(next.score, 1).id, isNot(const EventId(2)));
    });

    test('spells a rest that now crosses the barline as rests', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half.dotted),
          rest(2, NoteValue.quarter),
        ],
        [chordOf(3, 'G4', value: NoteValue.whole)],
      ]);

      final next = valueSet(session, 2, NoteValue.whole);

      expect(bar(next.score, 1), ['rest/half', 'rest/quarter', 'rest/quarter']);
    });

    test('appends bars when it runs past the end of the score', () {
      final session = sessionWith([
        [rest(1, NoteValue.half.dotted), chordOf(2, 'F4')],
      ]);

      final next = valueSet(session, 2, NoteValue.half);

      expect(next.score.measures.length, 2);
      expect(bar(next.score, 1), ['F4/quarter', 'rest/quarter', 'rest/half']);
    });

    test('appends no bar when it fills the last bar', () {
      final session = sessionWith([
        [chordOf(1, 'F4', value: NoteValue.half), rest(2, NoteValue.half)],
      ]);

      final next = valueSet(session, 1, NoteValue.whole);

      expect(next.score.measures.length, 1);
      expect(bar(next.score, 0), ['F4/whole']);
    });

    test('clears a tie to the note it overwrites', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', tie: true),
          chordOf(2, 'F4'),
          chordOf(3, 'F4', value: NoteValue.half),
        ],
      ]);

      final next = valueSet(session, 1, NoteValue.half);

      expect(bar(next.score, 0), ['F4/half', 'F4/half']);
      expect(tiesOf(next, 1), {'F4': false});
    });

    test('keeps the last piece tied where the tie still rings on', () {
      final session = sessionWith([
        [rest(1, NoteValue.half.dotted), chordOf(2, 'F4', tie: true)],
        [MeasureRest(id: const EventId(3), span: len(1, 1))],
      ]);

      final next = valueSet(session, 2, NoteValue.half);

      expect(bar(next.score, 0).last, 'F4/quarter~');
      expect(bar(next.score, 1).first, 'F4/quarter~');
    });

    test('leaves the ties into it alone', () {
      final session = sessionWith([
        [
          chordOf(1, 'C4 F4', tie: true),
          chordOf(2, 'F4'),
          rest(3, NoteValue.half),
        ],
      ]);

      final next = valueSet(session, 2, NoteValue.half);

      expect(tiesOf(next, 1), {'C4': true, 'F4': true});
    });

    test('refuses to run past the end of its tuplet', () {
      final session = sessionWith([
        [
          tripletOfEighths(1, [
            chordOf(2, 'F4', value: NoteValue.eighth),
            chordOf(3, 'G4', value: NoteValue.eighth),
            chordOf(4, 'A4', value: NoteValue.eighth),
          ]),
          rest(5, NoteValue.quarter),
          rest(6, NoteValue.half),
        ],
      ]);

      expect(
        refusal(setValue(session, 4, NoteValue.quarter)),
        isA<WouldSplitTuplet>().having(
          (r) => r.tuplet,
          'tuplet',
          const TupletId(1),
        ),
      );

      final next = valueSet(session, 2, NoteValue.quarter);

      expect(bar(next.score, 0).first, '3:2[F4/quarter, A4/eighth]');
    });
  });

  group('SetValue', () {
    test('keeps the cursor and the selection', () {
      final start = sessionWith([
        [
          chordOf(1, 'F4'),
          chordOf(2, 'G4'),
          chordOf(3, 'A4', value: NoteValue.half),
        ],
      ]);
      final session = start
          .placeCursor(point(start.score, 0, at(3, 4)))
          .select(Selection.event(eventRef(start, 3)));

      final next = valueSet(session, 1, NoteValue.half);

      expect(next.cursor, session.cursor);
      expect(next.selection.singleEvent, eventRef(start, 3));
    });

    test('changes nothing for the value it has', () {
      final session = sessionWith([
        [chordOf(1, 'F4'), rest(2, NoteValue.half.dotted)],
      ]);

      expect(
        changesNothing(
          session,
          SetValue(eventRef(session, 1), NoteValue.quarter),
        ),
        isTrue,
      );
      expect(
        changesNothing(
          session,
          SetValue(eventRef(session, 2), NoteValue.half.dotted),
        ),
        isTrue,
      );
    });

    test('refuses an event that is gone', () {
      final session = blank();
      final gone = EventRef(
        measure: idOf(session, 0),
        staff: session.score.staves.first.id,
        id: const EventId(999),
      );

      expect(
        refusal(session.run(SetValue(gone, NoteValue.half))),
        isA<StaleReference>().having((r) => r.target, 'target', gone),
      );
    });
  });

  group('EnterTuplet', () {
    test('writes a tuplet of rests over what was there', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half),
          chordOf(2, 'G4', value: NoteValue.half),
        ],
      ]);

      final next = applied(enterTuplet(session, 0, at(1, 4)));

      expect(bar(next.score, 0), [
        'F4/quarter',
        '3:2[rest/eighth, rest/eighth, rest/eighth]',
        'G4/half',
      ]);
    });

    test('puts the cursor at its start and selects its first rest', () {
      final session = blank();

      final next = applied(
        enterTuplet(
          session,
          0,
          at(1, 2),
          ratio: TupletRatio.quintuplet,
          unit: NoteValue.sixteenth,
        ),
      );
      final filled = applied(
        enter(next, next.cursor, value: NoteValue.sixteenth),
      );

      expect(next.cursor, point(next.score, 0, at(1, 2)));
      expect(next.selection.singleEvent, isNotNull);
      expect(
        next.score.lookup(next.selection.singleEvent!)!.onset,
        at(1, 2),
      );
      expect(bar(filled.score, 0), [
        'rest/half',
        '5:4[F4/sixteenth, rest/sixteenth, rest/sixteenth, rest/sixteenth, rest/sixteenth]',
        'rest/quarter',
      ]);
    });

    test('nests inside a tuplet', () {
      final session = applied(
        enterTuplet(blank(), 0, Moment.zero, unit: NoteValue.quarter),
      );

      final next = applied(enterTuplet(session, 0, Moment.zero));

      expect(
        bar(next.score, 0).first,
        '3:2[3:2[rest/eighth, rest/eighth, rest/eighth], rest/quarter, rest/quarter]',
      );
    });

    test('refuses a tuplet that would cross the barline', () {
      final session = blank();

      expect(
        refusal(enterTuplet(session, 0, at(7, 8))),
        isA<WouldSplitTuplet>().having(
          (r) => r.measure,
          'measure',
          idOf(session, 0),
        ),
      );
    });

    test('refuses a tuplet that would run past the tuplet it is in', () {
      final session = applied(
        enterTuplet(blank(), 0, Moment.zero, unit: NoteValue.quarter),
      );
      final outer = (voiceOf(session.score, 0).items.first as Tuplet).id;

      expect(
        refusal(enterTuplet(session, 0, at(1, 3), unit: NoteValue.quarter)),
        isA<WouldSplitTuplet>().having((r) => r.tuplet, 'tuplet', outer),
      );
    });

    test('leaves gaps around it in voice two', () {
      final session = blank();

      final next = applied(
        enterTuplet(session, 0, at(1, 4), voice: VoiceSlot.two),
      );

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'gap 1/4',
        '3:2[rest/eighth, rest/eighth, rest/eighth]',
        'gap 1/2',
      ]);
    });

    test('clears a tie into it', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', tie: true),
          chordOf(2, 'F4', value: NoteValue.half.dotted),
        ],
      ]);

      final next = applied(enterTuplet(session, 0, at(1, 4)));

      expect(tiesOf(next, 1), {'F4': false});
    });

    test('appends no bar when it ends the score', () {
      final session = blank(bars: 1);

      final next = applied(enterTuplet(session, 0, at(3, 4)));

      expect(next.score.measures.length, 1);
    });

    test('refuses a point that is gone or outside its bar', () {
      final session = blank();

      expect(
        refusal(
          session.run(
            EnterTuplet(
              at: VoicePoint(
                staff: session.score.staves.first.id,
                voice: VoiceSlot.one,
                at: const ScorePoint(MeasureId(999), Moment.zero),
              ),
              ratio: TupletRatio.triplet,
              unit: NoteValue.eighth,
            ),
          ),
        ),
        isA<StaleReference>(),
      );
      expect(refusal(enterTuplet(session, 0, at(1, 1))), isA<OutsideMeasure>());
    });
  });
}
