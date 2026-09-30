import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

String? moved(Transposition by, String pitch, [int fifths = 0]) =>
    by.apply(Pitch.parse(pitch), KeySignature(fifths))?.toString();

EditOutcome transpose(
  EditSession session,
  Selection selection,
  Transposition by,
) => session.run(Transpose(selection, by));

EditSession transposed(
  EditSession session,
  Selection selection,
  Transposition by,
) => applied(transpose(session, selection, by));

RangeSelection range(
  EditSession session,
  (int, Moment) from,
  (int, Moment) to, {
  int top = 0,
  int bottom = 0,
}) => RangeSelection(
  from: pointAt(session.score, from.$1, from.$2),
  to: pointAt(session.score, to.$1, to.$2),
  top: session.score.staves[top].id,
  bottom: session.score.staves[bottom].id,
);

Selection events(EditSession session, List<int> ids) =>
    ItemSelection(Seq([for (final id in ids) eventRef(session, id)]));

Selection head(EditSession session, int event, int note) => ItemSelection(
  Seq([NoteRef(eventRef(session, event), NoteId(note))]),
);

const up = Transposition.interval(Interval.majorSecond);

GraceChord graceOf(int id, String pitch) => GraceChord(
  id: EventId(id),
  kind: GraceKind.acciaccatura,
  value: NoteValue.eighth,
  notes: Seq([PitchedNote(id: NoteId(id * 10), pitch: Pitch.parse(pitch))]),
);

Score withKey(Score score, int bar, int fifths) => changeBar(
  score,
  bar,
  (column) => column.copyWith(key: KeySignature(fifths)),
);

void main() {
  group('Transposition.apply', () {
    test('moves by a spelled interval in any key', () {
      expect(
        moved(const Transposition.interval(Interval.majorThird), 'C4'),
        'E4',
      );
      expect(
        moved(const Transposition.interval(Interval(3, 4)), 'C4', 3),
        'Fb4',
      );
      expect(
        moved(Transposition.interval(-Interval.perfectFifth), 'F#4'),
        'B3',
      );
    });

    test('moves by scale steps and keeps alterations against the key', () {
      const step = Transposition.diatonic(1);
      expect(moved(step, 'A4', -1), 'Bb4');
      expect(moved(step, 'F#4', -1), 'G#4');
      expect(moved(step, 'B3'), 'C4');
      expect(moved(const Transposition.diatonic(-1), 'C4'), 'B3');
      expect(moved(const Transposition.diatonic(7), 'Eb4', -3), 'Eb5');
      expect(moved(const Transposition.diatonic(2), 'F#4', 1), 'A4');
    });

    test('spells semitones as the key does, then by its side', () {
      const semitone = Transposition.chromatic(1);
      expect(moved(semitone, 'C4', 2), 'C#4');
      expect(moved(semitone, 'A4', -1), 'Bb4');
      expect(moved(semitone, 'A4'), 'A#4');
      expect(moved(semitone, 'F4', -3), 'Gb4');
      expect(moved(semitone, 'E4', 6), 'E#4');
      expect(moved(semitone, 'Bb3', -7), 'Cb4');
      expect(moved(semitone, 'B3'), 'C4');
      expect(moved(const Transposition.chromatic(-1), 'C4', -2), 'B3');
      expect(moved(const Transposition.chromatic(12), 'D4', 2), 'D5');
      expect(moved(semitone, 'C+4'), 'C#+4');
      expect(moved(semitone, 'C+4', -1), 'Dd4');
    });

    test('is null past a double sharp or flat', () {
      const semitone = Transposition.interval(Interval(0, 1));
      expect(moved(semitone, 'B#4'), 'Bx4');
      expect(
        semitone.apply(
          const Pitch(Step.b, 4, Alter.threeQuarterSharp),
          KeySignature.cMajor,
        ),
        isNull,
      );
      expect(
        moved(const Transposition.interval(Interval(0, 1)), 'Bx4'),
        isNull,
      );
      expect(moved(const Transposition.diatonic(-1), 'Fbb4', 1), isNull);
      expect(
        moved(const Transposition.interval(Interval(0, -1)), 'Bbb4'),
        isNull,
      );
    });
  });

  group('Transpose', () {
    test('moves every head that starts in a range', () {
      final session = sessionWith([
        [
          chordOf(1, 'C4'),
          chordOf(2, 'E4 G4'),
          tripletOfEighths(3, [
            chordOf(4, 'A4', value: NoteValue.eighth),
            chordOf(5, 'B4', value: NoteValue.eighth),
            rest(6, NoteValue.eighth),
          ]),
          chordOf(7, 'D5'),
        ],
        [chordOf(8, 'F4', value: NoteValue.whole)],
      ]);

      final next = transposed(
        session,
        range(session, (0, at(1, 4)), (0, at(3, 4))),
        up,
      );

      expect(bar(next.score, 0), [
        'C4/quarter',
        'F#4+A4/quarter',
        '3:2[B4/eighth, C#5/eighth, rest/eighth]',
        'D5/quarter',
      ]);
      expect(bar(next.score, 1), ['F4/whole']);
    });

    test('moves every voice and staff in a range', () {
      var score = blankScore(parts: const [piano]);
      score = fill(score, 0, [chordOf(1, 'C5', value: NoteValue.whole)]);
      score = fill(score, 0, [
        chordOf(2, 'C4', value: NoteValue.whole),
      ], slot: VoiceSlot.two);
      score = fill(score, 0, [
        chordOf(3, 'C3', value: NoteValue.whole),
      ], staff: 1);
      final session = EditSession.start(score);

      final next = transposed(
        session,
        range(session, (0, Moment.zero), (1, Moment.zero), bottom: 1),
        up,
      );

      final staves = next.score.measures[0].staves;
      expect(describe(staves[0].voice(VoiceSlot.one)!.items), ['D5/whole']);
      expect(describe(staves[0].voice(VoiceSlot.two)!.items), ['D4/whole']);
      expect(describe(staves[1].voice(VoiceSlot.one)!.items), ['D3/whole']);
    });

    test('moves a picked event whole and a picked head alone', () {
      final session = sessionWith([
        [
          chordOf(1, 'C4 E4'),
          chordOf(2, 'C4 E4'),
          chordOf(3, 'C4'),
          rest(4, NoteValue.quarter),
        ],
      ]);

      final whole = transposed(session, events(session, [1, 4]), up);
      final one = transposed(
        session,
        head(session, 2, 20),
        const Transposition.interval(Interval(5, 9)),
      );

      expect(bar(whole.score, 0).take(2), ['D4+F#4/quarter', 'C4+E4/quarter']);
      expect(bar(one.score, 0).take(2), ['C4+E4/quarter', 'E4+A4/quarter']);
    });

    test('moves a whole tie chain as its first note moves', () {
      var score = sessionWith([
        [
          chordOf(1, 'A4', value: NoteValue.half),
          chordOf(2, 'A4', value: NoteValue.half, tie: true),
        ],
        [
          chordOf(3, 'A4', value: NoteValue.half, tie: true),
          chordOf(4, 'A4', value: NoteValue.half),
        ],
      ]).score;
      score = withKey(score, 1, -1);
      final session = EditSession.start(score);

      final next = transposed(
        session,
        events(session, [3]),
        const Transposition.diatonic(1),
      );

      expect(bar(next.score, 0), ['A4/half', 'B4/half~']);
      expect(bar(next.score, 1), ['B4/half~', 'B4/half']);
    });

    test('reads the key of each note', () {
      final session = EditSession.start(
        withKey(
          sessionWith([
            [chordOf(1, 'A4', value: NoteValue.whole)],
            [chordOf(2, 'A4', value: NoteValue.whole)],
          ]).score,
          1,
          -1,
        ),
      );

      final next = transposed(
        session,
        range(session, (0, Moment.zero), (1, at(1, 1))),
        const Transposition.diatonic(1),
      );

      expect(bar(next.score, 0), ['B4/whole']);
      expect(bar(next.score, 1), ['Bb4/whole']);
      expect(next.score.measures[1].key, const KeySignature(-1));
    });

    test('moves graces with their chord in its key, not with one head', () {
      final session = EditSession.start(
        withKey(
          sessionWith([
            [
              chordOf(
                1,
                'C4 E4',
                value: NoteValue.whole,
                graces: [graceOf(9, 'A4')],
              ),
            ],
          ]).score,
          0,
          -1,
        ),
      );
      List<String> graces(EditSession session) => [
        for (final n in chordIn(session, 1).graces.single.notes) '${n.tone}',
      ];
      const step = Transposition.diatonic(1);

      final byRange = transposed(
        session,
        range(session, (0, Moment.zero), (0, at(1, 2))),
        step,
      );
      final byEvent = transposed(session, events(session, [1]), step);
      final byHead = transposed(session, head(session, 1, 10), step);

      expect(graces(byRange), ['Bb4']);
      expect(graces(byEvent), ['Bb4']);
      expect(graces(byHead), ['A4']);
      expect(bar(byHead.score, 0), ['D4+E4/whole']);
    });

    test('moves the chord symbols in a range', () {
      var score = sessionWith([
        [chordOf(1, 'C4', value: NoteValue.whole)],
      ]).score;
      score = changeBar(
        score,
        0,
        (column) => column.withStaff(
          column.staves.first.copyWith(
            directions: Seq([
              const ChordSymbol(
                Moment.zero,
                root: PitchName(Step.c),
                quality: 'maj7',
                bass: PitchName(Step.e),
              ),
              ChordSymbol(at(3, 4), root: const PitchName(Step.a)),
            ]),
          ),
        ),
      );
      final session = EditSession.start(score);

      final byRange = transposed(
        session,
        range(session, (0, Moment.zero), (0, at(1, 2))),
        up,
      );
      final byEvent = transposed(session, events(session, [1]), up);

      final symbols = byRange.score.measures[0].staves.first.directions
          .cast<ChordSymbol>();
      expect(
        [for (final s in symbols) (s.root, s.quality, s.bass)],
        [
          (
            const PitchName(Step.d),
            'maj7',
            const PitchName(Step.f, Alter.sharp),
          ),
          (const PitchName(Step.a), '', null),
        ],
      );
      expect(
        byEvent.score.measures[0].staves.first.directions,
        session.score.measures[0].staves.first.directions,
      );
    });

    test('leaves drum notes alone and moves their staff\'s chord symbols', () {
      var score = blankScore(parts: const [drums, piano]);
      score = fill(score, 0, [
        hit(
          1,
          [snare],
          value: NoteValue.whole,
          graces: [
            GraceChord(
              id: const EventId(9),
              kind: GraceKind.acciaccatura,
              value: NoteValue.eighth,
              notes: Seq([const DrumNote(id: NoteId(90), drum: snare)]),
            ),
          ],
        ),
      ]);
      score = changeBar(
        score,
        0,
        (column) => column.withStaff(
          column.staves.first.copyWith(
            directions: Seq([
              const ChordSymbol(Moment.zero, root: PitchName(Step.c)),
            ]),
          ),
        ),
      );
      score = fill(score, 0, [
        chordOf(2, 'C4', value: NoteValue.whole),
      ], staff: 1);
      final session = EditSession.start(score);

      final next = transposed(
        session,
        range(session, (0, Moment.zero), (1, Moment.zero), bottom: 1),
        up,
      );
      final picked = transposed(session, events(session, [1]), up);

      final drumStaff = next.score.measures[0].staves.first;
      expect(
        identical(
          drumStaff.voice(VoiceSlot.one),
          session.score.measures[0].staves.first.voice(VoiceSlot.one),
        ),
        isTrue,
      );
      expect(
        (drumStaff.directions.single as ChordSymbol).root,
        const PitchName(Step.d),
      );
      expect(
        describe(next.score.measures[0].staves[1].voice(VoiceSlot.one)!.items),
        ['D4/whole'],
      );
      expect(identical(picked.score, session.score), isTrue);
    });

    test('drops a let-ring tie that now lands on a head', () {
      final session = sessionWith([
        [
          chordOf(1, 'E4', tie: true),
          chordOf(2, 'C4'),
          chordOf(3, 'C4', tie: true),
          chordOf(4, 'D4'),
        ],
      ]);

      final next = transposed(
        session,
        events(session, [2, 3]),
        const Transposition.interval(Interval.majorThird),
      );
      final moving = transposed(session, events(session, [3]), up);

      expect(bar(next.score, 0), [
        'E4/quarter',
        'E4/quarter',
        'E4/quarter~',
        'D4/quarter',
      ]);
      expect(bar(moving.score, 0).skip(2), ['D4/quarter', 'D4/quarter']);
    });

    test('keeps ties that still land on their heads', () {
      final session = sessionWith([
        [
          chordOf(1, 'C4 E4', value: NoteValue.half, tie: true),
          chordOf(2, 'C4 E4', value: NoteValue.half),
        ],
      ]);

      final next = transposed(session, events(session, [1]), up);

      expect(bar(next.score, 0), ['D4+F#4/half~', 'D4+F#4/half']);
    });

    test('refuses a chord that would hold one pitch twice', () {
      final session = sessionWith([
        [chordOf(1, 'C#4 Db4'), chordOf(2, 'C4 E4'), rest(3, NoteValue.half)],
      ]);

      expect(
        refusal(
          transpose(
            session,
            events(session, [1]),
            const Transposition.chromatic(1),
          ),
        ),
        isA<InvalidValue>(),
      );
      expect(
        refusal(
          transpose(
            session,
            head(session, 2, 20),
            const Transposition.interval(Interval.majorThird),
          ),
        ),
        isA<InvalidValue>(),
      );
    });

    test('refuses a note past a double sharp or flat', () {
      final session = sessionWith([
        [chordOf(1, 'Bx4', value: NoteValue.whole)],
      ]);

      expect(
        refusal(
          transpose(
            session,
            events(session, [1]),
            const Transposition.interval(Interval(0, 1)),
          ),
        ),
        isA<InvalidValue>(),
      );
    });

    test('changes nothing for a unison or nothing picked', () {
      final session = sessionWith([
        [
          chordOf(1, 'C4', value: NoteValue.whole, graces: [graceOf(9, 'D4')]),
        ],
        [rest(2, NoteValue.whole)],
      ]);

      expect(
        changesNothing(
          session,
          Transpose(
            events(session, [1]),
            const Transposition.interval(Interval.unison),
          ),
        ),
        isTrue,
      );
      expect(
        changesNothing(
          session,
          Transpose(range(session, (1, Moment.zero), (1, at(1, 1))), up),
        ),
        isTrue,
      );
      expect(
        changesNothing(session, const Transpose(Selection.none(), up)),
        isTrue,
      );
    });

    test('keeps the selection and the cursor', () {
      final session = sessionWith([
        [chordOf(1, 'C4', value: NoteValue.whole)],
      ]);
      final picked = session.select(events(session, [1]));

      final next = transposed(picked, picked.selection, up);

      expect(next.selection.singleEvent?.id, const EventId(1));
      expect(next.cursor, picked.cursor);
    });

    test('refuses a stale or outside reference', () {
      final session = sessionWith([
        [chordOf(1, 'C4', value: NoteValue.whole)],
      ]);
      final stale = ItemSelection(
        Seq([
          EventRef(
            measure: session.score.measures[0].id,
            staff: session.score.staves[0].id,
            id: const EventId(99),
          ),
        ]),
      );

      expect(refusal(transpose(session, stale, up)), isA<StaleReference>());
      expect(
        refusal(
          transpose(
            session,
            range(session, (0, Moment.zero), (0, at(5, 4))),
            up,
          ),
        ),
        isA<OutsideMeasure>(),
      );
    });
  });
}
