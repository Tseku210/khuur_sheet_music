import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Built at run time, so equal values are never the same object.
T fresh<T>(T Function() make) => make();

RepeatEnd repeatEnd(int times) => RepeatEnd(times: times);

Jump toCoda(String text) =>
    Jump(JumpTarget.segno, then: JumpThen.toCoda, text: text);

Spanner spannerIn(Score score, int id) =>
    score.spanners.firstWhere((s) => s.id == SpannerId(id));

void main() {
  group('InsertMeasures', () {
    test('inserts empty bars that carry on from the bar before', () {
      var score = blankScore(parts: const [piano], bars: 3);
      for (final i in [1, 2]) {
        score = changeBar(
          score,
          i,
          (c) => c.copyWith(key: const KeySignature(1)),
        );
      }
      score = changeBar(
        score,
        1,
        (c) => c.withStaff(
          c.staves.first.copyWith(
            clefChanges: Seq([ClefChange(at(1, 2), Clef.bass)]),
          ),
        ),
      );
      final session = EditSession.start(score);
      final before = barIds(score);

      final next = applied(
        session.run(InsertMeasures(before: idOf(session, 2), count: 2)),
      );

      final after = barIds(next.score);
      expect(after, hasLength(5));
      expect([after[0], after[1], after[4]], before);
      expect(before, isNot(contains(after[2])));
      for (final column in [next.score.measures[2], next.score.measures[3]]) {
        expect(column.meter, Meter.fourFour);
        expect(column.key, const KeySignature(1));
        expect([for (final s in column.staves) s.clef], [Clef.bass, Clef.bass]);
        expect(
          [
            for (final s in column.staves) describe(s.voices.single.items),
          ],
          [
            ['measure-rest'],
            ['measure-rest'],
          ],
        );
      }
      expect(identical(next.score.measures[1], score.measures[1]), isTrue);
    });

    test('inserts at the start from the first bar and at the end', () {
      final score = changeBar(
        blankScore(),
        0,
        (c) => c
            .copyWith(key: const KeySignature(-2))
            .withStaff(
              c.staves.first.copyWith(
                clefChanges: Seq([ClefChange(at(1, 2), Clef.bass)]),
              ),
            ),
      );
      final session = EditSession.start(score);

      final first = applied(
        session.run(InsertMeasures(before: idOf(session, 0))),
      ).score.measures.first;
      final last = applied(
        session.run(const InsertMeasures()),
      ).score.measures.last;

      expect(first.key, const KeySignature(-2));
      expect(first.staves.first.clef, Clef.treble);
      expect(last.key, KeySignature.cMajor);
      expect(barIds(score), isNot(contains(last.id)));
    });

    test('joins an ending only when inserted inside it', () {
      var score = blankScore(bars: 4);
      for (final i in [1, 2]) {
        score = changeBar(
          score,
          i,
          (c) => c.copyWith(volta: () => const Volta([1])),
        );
      }
      final session = EditSession.start(score);

      Volta? inserted(int before) => applied(
        session.run(InsertMeasures(before: idOf(session, before))),
      ).score.measures[before].volta;

      expect(inserted(2), const Volta([1]));
      expect(inserted(1), isNull);
      expect(inserted(3), isNull);
    });

    test('stretches a spanner that crosses the insertion point', () {
      final plain = blankScore(bars: 3);
      final score = withSlur(
        plain,
        pointAt(plain, 0, at(1, 2)),
        pointAt(plain, 2, Moment.zero),
      );
      final session = EditSession.start(score);

      final next = applied(
        session.run(InsertMeasures(before: idOf(session, 1), count: 2)),
      );

      expect(identical(next.score.spanners, score.spanners), isTrue);
      expect(
        [
          for (final c in next.score.measures)
            next.score.measureView(c.id).spanners.length,
        ],
        [1, 1, 1, 1, 1],
      );
    });

    test('clears a tie into the bar it is inserted before', () {
      final session = sessionWith([
        [chordOf(20, 'D4 F4', value: NoteValue.whole, tie: true)],
        [chordOf(30, 'F4', value: NoteValue.whole)],
      ]);

      final next = applied(
        session.run(InsertMeasures(before: idOf(session, 1))),
      );

      expect(tiesOf(next, 20), {'D4': true, 'F4': false});
    });
  });

  group('DeleteMeasures', () {
    test('deletes a range given in either order', () {
      final session = blank(bars: 5);
      final before = barIds(session.score);

      final next = applied(
        session.run(DeleteMeasures(idOf(session, 3), idOf(session, 1))),
      );

      expect(barIds(next.score), [before[0], before[4]]);
      expect(
        next.score.changesSince(session.score).removed,
        before.sublist(1, 4).toSet(),
      );
    });

    test('refuses to delete every bar', () {
      final session = blank();

      expect(
        refusal(
          session.run(DeleteMeasures(idOf(session, 0), idOf(session, 1))),
        ),
        isA<WouldEmptyScore>(),
      );
    });

    test('clears a tie that would land on a different note', () {
      final session = sessionWith([
        [chordOf(20, 'D4 F4 A4', value: NoteValue.whole, tie: true)],
        [chordOf(30, 'D4', value: NoteValue.whole)],
        [chordOf(40, 'A4', value: NoteValue.whole)],
      ]);

      final next = applied(
        session.run(DeleteMeasures(idOf(session, 1), idOf(session, 1))),
      );

      expect(tiesOf(next, 20), {'D4': false, 'F4': true, 'A4': false});
    });

    test('keeps a let-ring tie that meets a gap after the range', () {
      var score = sessionWith([
        [rest(20, NoteValue.whole)],
        [rest(30, NoteValue.whole)],
        [rest(40, NoteValue.whole)],
      ]).score;
      score = fill(score, 0, [
        chordOf(50, 'C4', value: NoteValue.whole, tie: true),
      ], slot: VoiceSlot.two);
      score = fill(score, 2, [
        Gap(len(1, 2)),
        chordOf(70, 'C4', value: NoteValue.half),
      ], slot: VoiceSlot.two);
      final session = EditSession.start(score);

      final next = applied(
        session.run(DeleteMeasures(idOf(session, 1), idOf(session, 1))),
      );

      expect(tiesOf(next, 50), {'C4': true});
    });

    test('drops spanners inside the range and clips those crossing it', () {
      var score = fill(blankScore(bars: 5), 0, [
        chordOf(20, 'F4'),
        chordOf(21, 'G4'),
        chordOf(22, 'A4'),
        chordOf(23, 'B4'),
      ]);
      for (final (first, last) in [
        (pointAt(score, 1, Moment.zero), pointAt(score, 2, at(1, 2))),
        (pointAt(score, 0, at(1, 4)), pointAt(score, 1, at(1, 2))),
        (pointAt(score, 2, at(1, 4)), pointAt(score, 4, Moment.zero)),
        (pointAt(score, 0, Moment.zero), pointAt(score, 4, Moment.zero)),
        (pointAt(score, 1, Moment.zero), pointAt(score, 3, Moment.zero)),
      ]) {
        score = withSlur(score, first, last);
      }
      final session = EditSession.start(score);

      final next = applied(
        session.run(DeleteMeasures(idOf(session, 1), idOf(session, 2))),
      ).score;

      expect([for (final s in next.spanners) s.id.value], [901, 902, 903]);
      expect(
        [spannerIn(next, 901).first, spannerIn(next, 901).last],
        [pointAt(score, 0, at(1, 4)), pointAt(score, 0, at(3, 4))],
      );
      expect(
        [spannerIn(next, 902).first, spannerIn(next, 902).last],
        [pointAt(score, 3, Moment.zero), pointAt(score, 4, Moment.zero)],
      );
      expect(
        identical(spannerIn(next, 903), spannerIn(score, 903)),
        isTrue,
      );
    });

    test('moves the cursor from a deleted bar to the nearest bar left', () {
      final start = blank(bars: 4);
      final session = start.placeCursor(point(start.score, 2, Moment.zero));

      final middle = applied(
        session.run(DeleteMeasures(idOf(start, 1), idOf(start, 2))),
      );
      final end = applied(
        session.run(DeleteMeasures(idOf(start, 2), idOf(start, 3))),
      );

      expect(middle.cursor.at, pointAt(start.score, 3, Moment.zero));
      expect(end.cursor.at, pointAt(start.score, 1, Moment.zero));
    });
  });

  group('SetBarLength', () {
    test('cuts a shortened bar from the end', () {
      final session = sessionWith([
        [
          chordOf(20, 'F4'),
          chordOf(21, 'A4', value: NoteValue.half),
          chordOf(22, 'C5'),
        ],
      ]);

      final next = applied(
        session.run(SetBarLength(idOf(session, 0), len(1, 2))),
      );

      expect(bar(next.score, 0), ['F4/quarter', 'A4/quarter']);
      expect(next.score.measures[0].irregularLength, len(1, 2));
      expect(chordIn(next, 21).value, NoteValue.quarter);
    });

    test('keeps a tie that still reaches the next bar and clears one '
        'into cut music', () {
      final session = sessionWith([
        [
          chordOf(20, 'F4', value: NoteValue.half, tie: true),
          chordOf(21, 'F4 G4', value: NoteValue.half, tie: true),
        ],
        [chordOf(30, 'F4 G4', value: NoteValue.whole)],
      ]);
      final first = idOf(session, 0);

      final threeQuarters = applied(
        session.run(SetBarLength(first, len(3, 4))),
      );
      final half = applied(session.run(SetBarLength(first, len(1, 2))));

      expect(bar(threeQuarters.score, 0), ['F4/half~', 'F4+G4/quarter~']);
      expect(bar(half.score, 0), ['F4/half']);
    });

    test('pads a lengthened bar and clears a tie that now meets rests', () {
      final voices = EditSession.start(
        fill(
          sessionWith([
            [chordOf(20, 'F4', value: NoteValue.whole, tie: true)],
            [chordOf(30, 'F4', value: NoteValue.whole)],
          ]).score,
          0,
          [chordOf(40, 'D4', value: NoteValue.half), Gap(len(1, 2))],
          slot: VoiceSlot.two,
        ),
      );
      final session = EditSession.start(
        fill(
          voices.score,
          0,
          [chordOf(50, 'C4', value: NoteValue.whole)],
          slot: VoiceSlot.three,
        ),
      );

      final next = applied(
        session.run(SetBarLength(idOf(session, 0), len(5, 4))),
      );

      expect(bar(next.score, 0), ['F4/whole', 'rest/quarter']);
      expect(bar(next.score, 0, slot: VoiceSlot.two), ['D4/half', 'gap 3/4']);
      expect(bar(next.score, 0, slot: VoiceSlot.three), [
        'C4/whole',
        'gap 1/4',
      ]);
    });

    test('resizes a measure rest and restores the meter length', () {
      final session = blank();
      final first = idOf(session, 0);

      final pickup = applied(session.run(SetBarLength(first, len(1, 4))));
      final restored = applied(pickup.run(SetBarLength(first, null)));

      expect(pickup.score.measures[0].length, len(1, 4));
      expect(bar(pickup.score, 0), ['measure-rest']);
      expect(restored.score.measures[0].irregularLength, isNull);
      expect(restored.score.measures[0].length, Meter.fourFour.length);
      expect(
        changesNothing(restored, SetBarLength(first, Meter.fourFour.length)),
        isTrue,
      );
    });

    test('restores a bar already as long as its meter without touching '
        'its music', () {
      final session = EditSession.start(
        changeBar(
          sessionWith([
            [chordOf(20, 'F4', value: NoteValue.whole, tie: true)],
            [chordOf(30, 'F4', value: NoteValue.whole)],
          ]).score,
          0,
          (c) => c.copyWith(irregularLength: () => Length.whole),
        ),
      );

      final next = applied(
        session.run(SetBarLength(idOf(session, 0), null)),
      );

      expect(next.score.measures[0].irregularLength, isNull);
      expect(bar(next.score, 0), ['F4/whole~']);
    });

    test('drops marks past a shortened end and clips spanners there', () {
      var score = fill(blankScore(), 0, [
        chordOf(20, 'F4'),
        chordOf(21, 'G4'),
        chordOf(22, 'A4'),
        chordOf(23, 'B4'),
      ]);
      score = fill(score, 1, [
        chordOf(24, 'F4', value: NoteValue.half),
        chordOf(25, 'G4', value: NoteValue.half),
      ]);
      score = changeBar(
        score,
        0,
        (c) => c
            .copyWith(
              tempos: Seq([
                const TempoMark(offset: Moment.zero, tempo: Tempo(90)),
                TempoMark(offset: at(3, 4), tempo: const Tempo(60)),
              ]),
            )
            .withStaff(
              c.staves.first.copyWith(
                clefChanges: Seq([
                  ClefChange(at(1, 4), Clef.alto),
                  ClefChange(at(1, 2), Clef.bass),
                ]),
                directions: Seq([
                  TextMark(at(1, 4), 'a'),
                  TextMark(at(3, 4), 'b'),
                ]),
              ),
            ),
      );
      for (final (first, last) in [
        (pointAt(score, 0, Moment.zero), pointAt(score, 0, at(3, 4))),
        (pointAt(score, 0, at(3, 4)), pointAt(score, 1, at(1, 2))),
        (pointAt(score, 0, at(1, 2)), pointAt(score, 0, at(3, 4))),
      ]) {
        score = withSlur(score, first, last);
      }
      final session = EditSession.start(score);

      final next = applied(
        session.run(SetBarLength(idOf(session, 0), len(1, 2))),
      ).score;

      final column = next.measures[0];
      expect([for (final t in column.tempos) t.tempo.bpm], [90]);
      expect(
        [for (final c in column.staves.first.clefChanges) c.clef],
        [
          Clef.alto,
        ],
      );
      expect(
        [
          for (final d in column.staves.first.directions) (d as TextMark).text,
        ],
        ['a'],
      );
      expect([for (final s in next.spanners) s.id.value], [900, 901]);
      expect(spannerIn(next, 900).last, pointAt(score, 0, at(1, 4)));
      expect(spannerIn(next, 901).first, pointAt(score, 1, Moment.zero));
    });

    test('refuses a length that cuts a tuplet or cannot be written', () {
      final session = sessionWith([
        [
          chordOf(20, 'F4', value: NoteValue.half),
          tripletOfEighths(30, [
            chordOf(31, 'F4', value: NoteValue.eighth),
            chordOf(32, 'G4', value: NoteValue.eighth),
            chordOf(33, 'A4', value: NoteValue.eighth),
          ]),
          rest(34, NoteValue.quarter),
        ],
      ]);
      final first = idOf(session, 0);

      expect(
        refusal(session.run(SetBarLength(first, len(5, 8)))),
        isA<WouldSplitTuplet>(),
      );
      expect(
        bar(applied(session.run(SetBarLength(first, len(3, 4)))).score, 0),
        ['F4/half', '3:2[F4/eighth, G4/eighth, A4/eighth]'],
      );
      expect(
        bar(applied(session.run(SetBarLength(first, len(1, 2)))).score, 0),
        ['F4/half'],
      );
      for (final length in [len(1, 12), Length.zero]) {
        expect(
          refusal(session.run(SetBarLength(first, length))),
          isA<InvalidValue>(),
        );
      }
    });
  });

  group('Bar marks', () {
    test('sets and clears marks on one bar', () {
      final session = blank(bars: 3);
      final m = idOf(session, 1);
      final set = [
        SetBarline(m, Barline.doubleBar),
        SetRepeatStart(m, start: true),
        SetRepeatEnd(m, const RepeatEnd(times: 3)),
        SetNavigation(
          m,
          Seq(const [Segno(), Jump(JumpTarget.segno, then: JumpThen.toCoda)]),
        ),
        SetRehearsal(m, 'A'),
      ].fold(session, (s, edit) => applied(s.run(edit)));

      final column = set.score.measures[1];
      expect(column.barline, Barline.doubleBar);
      expect(column.repeatStart, isTrue);
      expect(column.repeatEnd, const RepeatEnd(times: 3));
      expect(column.navigation, hasLength(2));
      expect(column.rehearsal, 'A');
      for (final i in [0, 2]) {
        expect(
          identical(set.score.measures[i], session.score.measures[i]),
          isTrue,
        );
      }

      final cleared = [
        SetBarline(m, Barline.regular),
        SetRepeatStart(m, start: false),
        SetRepeatEnd(m, null),
        SetNavigation(m, Seq(const [])),
        SetRehearsal(m, ''),
      ].fold(set, (s, edit) => applied(s.run(edit))).score.measures[1];

      expect(cleared.barline, Barline.regular);
      expect(cleared.repeatStart, isFalse);
      expect(cleared.repeatEnd, isNull);
      expect(cleared.navigation, isEmpty);
      expect(cleared.rehearsal, isNull);
    });

    test('changes nothing when a mark is set again', () {
      final session = blank(bars: 3);
      final m = idOf(session, 1);
      final set = [
        SetRepeatEnd(m, repeatEnd(3)),
        SetNavigation(m, Seq([const Segno(), toCoda('D.S.')])),
        SetRehearsal(m, 'A'),
      ].fold(session, (s, edit) => applied(s.run(edit)));

      for (final edit in <Edit>[
        SetBarline(m, Barline.regular),
        SetRepeatStart(m, start: false),
        SetRepeatEnd(m, repeatEnd(3)),
        SetNavigation(m, Seq([fresh(Segno.new), toCoda('D.S.')])),
        SetRehearsal(m, 'A'),
        SetVolta(m, m, null),
      ]) {
        expect(changesNothing(set, edit), isTrue, reason: edit.label);
      }
    });

    test('puts a range under an ending and clears part of it', () {
      final session = blank(bars: 4);
      const first = Volta([1]);

      final set = applied(
        session.run(SetVolta(idOf(session, 2), idOf(session, 1), first)),
      );
      final cleared = applied(
        set.run(SetVolta(idOf(session, 1), idOf(session, 1), null)),
      );

      expect(
        [for (final c in set.score.measures) c.volta],
        [
          null,
          first,
          first,
          null,
        ],
      );
      expect(
        [for (final c in cleared.score.measures) c.volta],
        [
          null,
          null,
          first,
          null,
        ],
      );
      expect(
        changesNothing(
          set,
          SetVolta(idOf(session, 1), idOf(session, 2), Volta(List.of([1]))),
        ),
        isTrue,
      );
    });

    test('refuses an ending that does not count passes from 1 in order', () {
      final session = blank();
      final m = idOf(session, 0);

      for (final endings in [
        <int>[],
        [0],
        [2, 1],
        [1, 1],
      ]) {
        expect(
          refusal(session.run(SetVolta(m, m, Volta(endings)))),
          isA<InvalidValue>(),
          reason: '$endings',
        );
      }
    });
  });

  test('every bar edit refuses a bar that is gone', () {
    final session = blank();
    const gone = MeasureId(999);
    final m = idOf(session, 0);

    for (final edit in <Edit>[
      const InsertMeasures(before: gone),
      DeleteMeasures(gone, m),
      DeleteMeasures(m, gone),
      const SetBarline(gone, Barline.doubleBar),
      const SetRepeatStart(gone, start: true),
      const SetRepeatEnd(gone, null),
      SetVolta(gone, m, null),
      SetVolta(m, gone, null),
      SetNavigation(gone, Seq(const [])),
      const SetRehearsal(gone, null),
      const SetBarLength(gone, null),
    ]) {
      expect(
        refusal(session.run(edit)),
        isA<StaleReference>(),
        reason: edit.label,
      );
    }
  });
}
