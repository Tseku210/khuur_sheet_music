import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

EditOutcome erase(EditSession session, List<ElementRef> items) =>
    session.run(Erase(ItemSelection(Seq(items))));

EditSession erased(EditSession session, List<int> ids) => applied(
  erase(session, [for (final id in ids) eventRef(session, id)]),
);

NoteRef head(EditSession session, int event, int note) =>
    NoteRef(eventRef(session, event), NoteId(note));

EditOutcome eraseRange(
  EditSession session,
  (int, Moment) from,
  (int, Moment) to, {
  int top = 0,
  int bottom = 0,
}) {
  final score = session.score;
  return session.run(
    Erase(
      RangeSelection(
        from: pointAt(score, from.$1, from.$2),
        to: pointAt(score, to.$1, to.$2),
        top: score.staves[top].id,
        bottom: score.staves[bottom].id,
      ),
    ),
  );
}

Voice? voiceTwo(Score score, int bar) =>
    score.measures[bar].staves.first.voice(VoiceSlot.two);

List<String> marksIn(Score score, int bar) => [
  for (final d in score.measures[bar].staves.first.directions) mark(d),
];

Score withMarks(Score score, int bar, List<StaffDirection> directions) =>
    changeBar(
      score,
      bar,
      (column) => column.withStaff(
        column.staves.first.copyWith(directions: Seq(directions)),
      ),
    );

/// A quarter, a triplet of quarters from beat two, and a quarter.
List<Content> triplet() => [
  chordOf(4, 'C5'),
  Tuplet(
    id: const TupletId(5),
    ratio: TupletRatio.triplet,
    unit: NoteValue.quarter,
    members: Seq([chordOf(1, 'F4'), chordOf(2, 'G4'), chordOf(3, 'A4')]),
  ),
  chordOf(6, 'D5'),
];

void main() {
  group('Erase events', () {
    test('leaves a rest of the value in voice one', () {
      final session = sessionWith([
        [chordOf(1, 'F4'), chordOf(2, 'G4'), rest(3, NoteValue.half)],
      ]);

      final next = erased(session, [1]);

      expect(bar(next.score, 0), ['rest/quarter', 'G4/quarter', 'rest/half']);
      expect(firstEvent(next.score, 0).id, const EventId(1));
    });

    test('keeps a fermata on the rest and nothing else', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4').copyWith(
            articulations: const {Articulation.staccato, Articulation.fermata},
          ),
          chordOf(2, 'G4'),
          rest(3, NoteValue.half),
        ],
      ]);

      final next = erased(session, [1]);

      expect(eventOf(next, 1), isA<RestEvent>());
      expect(eventOf(next, 1).articulations, {Articulation.fermata});
    });

    test('leaves one measure rest in a bar of only rests', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4'),
          rest(2, NoteValue.quarter),
          chordOf(3, 'G4', value: NoteValue.half),
        ],
      ]);

      final next = erased(session, [1, 3]);

      expect(bar(next.score, 0), ['measure-rest']);
      expect(firstEvent(next.score, 0).id, const EventId(1));
    });

    test('keeps a bar holding a marked or hidden rest as rests', () {
      for (final kept in const [
        RestEvent(
          id: EventId(2),
          value: NoteValue.quarter,
          articulations: {Articulation.fermata},
        ),
        RestEvent(id: EventId(2), value: NoteValue.quarter, hidden: true),
      ]) {
        final session = sessionWith([
          [chordOf(1, 'F4'), kept, rest(3, NoteValue.half)],
        ]);

        final next = erased(session, [1]);

        expect(bar(next.score, 0), [
          'rest/quarter',
          'rest/quarter',
          'rest/half',
        ]);
      }
    });

    test('changes nothing on a rest in voice one', () {
      final session = sessionWith([
        [
          rest(1, NoteValue.quarter),
          rest(2, NoteValue.quarter),
          rest(3, NoteValue.half),
        ],
      ]);

      expect(
        changesNothing(session, Erase(Selection.event(eventRef(session, 1)))),
        isTrue,
      );
    });

    test('leaves a gap in voice two, merged with its neighbours', () {
      final session = EditSession.start(
        fill(blankScore(), 0, [
          Gap(len(1, 4)),
          chordOf(1, 'F4'),
          chordOf(2, 'G4'),
          Gap(len(1, 4)),
        ], slot: VoiceSlot.two),
      );

      final next = erased(session, [1]);

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'gap 1/2',
        'G4/quarter',
        'gap 1/4',
      ]);
    });

    test('drops a voice left with only gaps', () {
      final session = EditSession.start(
        fill(blankScore(), 0, [
          chordOf(1, 'F4', value: NoteValue.half),
          Gap(len(1, 2)),
        ], slot: VoiceSlot.two),
      );

      final next = erased(session, [1]);

      expect(voiceTwo(next.score, 0), isNull);
    });

    test('leaves a rest inside a tuplet, in any voice', () {
      final session = EditSession.start(
        fill(blankScore(), 0, [
          ...triplet().take(2),
          Gap(len(1, 4)),
        ], slot: VoiceSlot.two),
      );

      final next = erased(session, [1]);

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'C5/quarter',
        '3:2[rest/quarter, G4/quarter, A4/quarter]',
        'gap 1/4',
      ]);
    });

    test('keeps a tuplet of voice one left with only rests', () {
      final session = sessionWith([triplet()]);

      final next = erased(session, [1, 2, 3]);

      expect(bar(next.score, 0), [
        'C5/quarter',
        '3:2[rest/quarter, rest/quarter, rest/quarter]',
        'D5/quarter',
      ]);
    });

    test('turns a tuplet of voice two left with only rests into a gap', () {
      final session = EditSession.start(
        fill(blankScore(), 0, [
          tripletOfEighths(5, [
            chordOf(1, 'F4', value: NoteValue.eighth),
            rest(2, NoteValue.eighth),
            rest(3, NoteValue.eighth),
          ]),
          chordOf(4, 'C5'),
          Gap(len(1, 2)),
        ], slot: VoiceSlot.two),
      );

      final next = erased(session, [1]);

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'gap 1/4',
        'C5/quarter',
        'gap 1/2',
      ]);
    });

    test('removes the picked heads of a chord', () {
      final session = sessionWith([
        [chordOf(1, 'F4 A4 C5'), chordOf(2, 'G4'), rest(3, NoteValue.half)],
      ]);

      final next = applied(
        erase(session, [head(session, 1, 10), head(session, 1, 12)]),
      );

      expect(bar(next.score, 0), ['A4/quarter', 'G4/quarter', 'rest/half']);
      expect(chordIn(next, 1).notes.single.id, const NoteId(11));
    });

    test('erases a chord whose every head is picked', () {
      final session = sessionWith([
        [chordOf(1, 'F4 A4'), chordOf(2, 'G4'), rest(3, NoteValue.half)],
      ]);

      final next = applied(
        erase(session, [head(session, 1, 10), head(session, 1, 11)]),
      );

      expect(bar(next.score, 0), ['rest/quarter', 'G4/quarter', 'rest/half']);
    });

    group('ties', () {
      EditSession tiedOver() => sessionWith([
        [
          rest(1, NoteValue.half),
          chordOf(2, 'F4 A4', value: NoteValue.half, tie: true),
        ],
        [
          chordOf(3, 'F4 A4', value: NoteValue.half),
          rest(4, NoteValue.half),
        ],
      ]);

      test('clears a tie into an erased chord, across the barline', () {
        final next = erased(tiedOver(), [3]);

        expect(tiesOf(next, 2), {'F4': false, 'A4': false});
      });

      test('clears a tie into a removed head only', () {
        final session = tiedOver();

        final next = applied(erase(session, [head(session, 3, 30)]));

        expect(tiesOf(next, 2), {'F4': false, 'A4': true});
      });

      test('keeps a let-ring tie', () {
        final session = sessionWith([
          [
            chordOf(1, 'F4', tie: true),
            chordOf(2, 'G4'),
            rest(3, NoteValue.half),
          ],
        ]);

        final next = erased(session, [2]);

        expect(tiesOf(next, 1), {'F4': true});
      });
    });

    test('keeps the erased event selected as its rest', () {
      final session = sessionWith([
        [chordOf(1, 'F4'), chordOf(2, 'G4'), rest(3, NoteValue.half)],
      ]);
      final selection = Selection.event(eventRef(session, 1));

      final next = applied(session.select(selection).run(Erase(selection)));

      expect(next.selection.singleEvent?.id, const EventId(1));
    });

    test('refuses a reference to an event that is gone', () {
      final session = sessionWith([
        [chordOf(1, 'F4'), chordOf(2, 'G4'), rest(3, NoteValue.half)],
      ]);
      final gone = EventRef(
        measure: idOf(session, 0),
        staff: session.score.staves.first.id,
        id: const EventId(99),
      );

      expect(refusal(erase(session, [gone])), isA<StaleReference>());
    });

    test('changes nothing with nothing selected', () {
      expect(changesNothing(blank(), const Erase(Selection.none())), isTrue);
    });
  });

  group('Erase a range', () {
    test('clears the events that start in it, in every voice', () {
      var score = fill(blankScore(), 0, [
        chordOf(1, 'F4', value: NoteValue.half),
        chordOf(2, 'G4'),
        chordOf(3, 'A4'),
      ]);
      score = fill(score, 0, [
        Gap(len(1, 4)),
        chordOf(4, 'C5'),
        Gap(len(1, 2)),
      ], slot: VoiceSlot.two);
      final session = EditSession.start(score);

      final next = applied(
        eraseRange(session, (0, at(1, 4)), (0, at(3, 4))),
      );

      expect(bar(next.score, 0), ['F4/half', 'rest/quarter', 'A4/quarter']);
      expect(voiceTwo(next.score, 0), isNull);
    });

    test('removes a tuplet wholly inside it', () {
      final session = sessionWith([triplet()]);

      final next = applied(
        eraseRange(session, (0, at(1, 4)), (0, at(3, 4))),
      );

      expect(bar(next.score, 0), [
        'C5/quarter',
        'rest/quarter',
        'rest/quarter',
        'D5/quarter',
      ]);
    });

    test('rests the members in it of a tuplet it cuts', () {
      for (final (from, to, members) in [
        (at(5, 12), at(3, 4), 'F4/quarter, rest/quarter, rest/quarter'),
        (at(1, 4), at(5, 12), 'rest/quarter, G4/quarter, A4/quarter'),
      ]) {
        final session = sessionWith([triplet()]);

        final next = applied(eraseRange(session, (0, from), (0, to)));

        expect(bar(next.score, 0), [
          'C5/quarter',
          '3:2[$members]',
          'D5/quarter',
        ]);
      }
    });

    test('spans bars and can end at the end of the score', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half),
          chordOf(2, 'G4', value: NoteValue.half),
        ],
        [
          chordOf(3, 'A4', value: NoteValue.half),
          chordOf(4, 'C5', value: NoteValue.half),
        ],
      ]);

      final next = applied(eraseRange(session, (0, at(1, 2)), (1, at(1, 1))));

      expect(bar(next.score, 0), ['F4/half', 'rest/half']);
      expect(bar(next.score, 1), ['measure-rest']);
    });

    test('clears a tie into it', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half, tie: true),
          chordOf(2, 'F4', value: NoteValue.half),
        ],
      ]);

      final next = applied(eraseRange(session, (0, at(1, 2)), (0, at(1, 1))));

      expect(tiesOf(next, 1), {'F4': false});
    });

    test('clears the directions in it and the spanners wholly inside it', () {
      var score = withMarks(blankScore(), 0, [
        const DynamicMark(Moment.zero, Dynamic.p),
        DynamicMark(at(1, 2), Dynamic.f),
      ]);
      score = withMarks(score, 1, [const TextMark(Moment.zero, 'dolce')]);
      score = fill(score, 0, [
        for (var i = 0; i < 4; i++) chordOf(100 + i, 'C5'),
      ]);
      for (final (first, last) in [
        ((0, Moment.zero), (0, at(1, 4))),
        ((0, at(1, 4)), (0, at(1, 2))),
        ((0, at(1, 2)), (1, Moment.zero)),
      ]) {
        score = withSlur(
          score,
          pointAt(score, first.$1, first.$2),
          pointAt(score, last.$1, last.$2),
        );
      }

      final next = applied(
        eraseRange(
          EditSession.start(score),
          (0, at(1, 4)),
          (1, Moment.zero),
        ),
      );

      expect(marksIn(next.score, 0), ['0 p']);
      expect(marksIn(next.score, 1), ['0 dolce']);
      expect(
        [for (final s in next.score.spanners) s.id],
        [
          const SpannerId(900),
          const SpannerId(902),
        ],
      );
    });

    test('leaves the staves outside it alone', () {
      var score = fill(blankScore(parts: const [piano]), 0, [
        chordOf(1, 'F4', value: NoteValue.half),
        chordOf(2, 'F4', value: NoteValue.half),
      ]);
      score = fill(score, 0, [
        chordOf(3, 'F4', value: NoteValue.whole),
      ], staff: 1);
      score = withSlur(
        score,
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(1, 2)),
      );

      final next = applied(
        eraseRange(
          EditSession.start(score),
          (0, Moment.zero),
          (1, Moment.zero),
          top: 1,
          bottom: 1,
        ),
      );

      List<String> staff(int index) => describe(
        next.score.measures[0].staves[index].voice(VoiceSlot.one)!.items,
      );
      expect(staff(0), ['F4/half', 'F4/half']);
      expect(staff(1), ['measure-rest']);
      expect(next.score.spanners, hasLength(1));
    });

    test('changes nothing over rests, or when it ends before it starts', () {
      final session = blank();

      for (final (from, to) in [
        ((0, Moment.zero), (1, Moment.zero)),
        ((1, at(1, 2)), (0, at(1, 4))),
      ]) {
        final next = applied(eraseRange(session, from, to));

        expect(identical(next.score, session.score), isTrue);
        expect(next.canUndo, isFalse);
      }
    });

    test('refuses a start or an end past its bar', () {
      for (final (from, to) in [
        (at(0, 4), at(5, 4)),
        (at(4, 4), at(4, 4)),
      ]) {
        expect(
          refusal(eraseRange(blank(), (0, from), (0, to))),
          isA<OutsideMeasure>(),
        );
      }
    });

    test('refuses a staff that is gone', () {
      final session = blank();
      final score = session.score;

      final outcome = session.run(
        Erase(
          RangeSelection(
            from: pointAt(score, 0, Moment.zero),
            to: pointAt(score, 1, Moment.zero),
            top: score.staves.first.id,
            bottom: const StaffId(999),
          ),
        ),
      );

      expect(refusal(outcome), isA<StaleReference>());
    });
  });
}
