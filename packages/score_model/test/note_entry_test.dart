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

    for (final (what, build, message) in <(String, Score Function(), String)>[
      (
        'no bars',
        () => Score.blank(parts: const [morinKhuur], measureCount: 0),
        'a score has at least one measure',
      ),
      (
        'fewer than no bars',
        () => Score.blank(parts: const [morinKhuur], measureCount: -1),
        'a score has at least one measure',
      ),
      (
        'no parts',
        () => Score.blank(parts: const []),
        'a score has at least one part',
      ),
      (
        'a part of no staves',
        () => Score.blank(
          parts: const [
            PartTemplate(name: 'None', instrument: fiddle, staves: 0),
          ],
        ),
        'a part needs a staff and a clef each',
      ),
      (
        'more clefs than staves',
        () => Score.blank(
          parts: const [
            PartTemplate(
              name: 'Fiddle',
              instrument: fiddle,
              clefs: [Clef.treble, Clef.bass],
            ),
          ],
        ),
        'a part needs a staff and a clef each',
      ),
      (
        'fewer clefs than staves',
        () => Score.blank(
          parts: const [
            PartTemplate(
              name: 'Organ',
              instrument: fiddle,
              staves: 3,
              clefs: [Clef.treble, Clef.bass],
            ),
          ],
        ),
        'a part needs a staff and a clef each',
      ),
    ]) {
      test('refuses $what', () {
        expect(
          build,
          throwsA(
            isA<ArgumentError>().having((e) => e.message, 'message', message),
          ),
        );
      });
    }
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

  group('beam mode', () {
    List<List<EventId>> beamsIn(Score score, int bar) => [
      for (final group
          in score
              .measureView(score.measures[bar].id)
              .staves
              .first
              .voices
              .first
              .beams)
        group.events,
    ];

    test('two eighths entered with no beam stand apart', () {
      Score pair(BeamMode beam) {
        var session = blank();
        for (var i = 0; i < 2; i++) {
          session = applied(
            session.run(
              EnterNote(
                at: session.cursor,
                tone: f4,
                value: NoteValue.eighth,
                beam: beam,
              ),
            ),
          );
        }
        return session.score;
      }

      expect(beamsIn(pair(BeamMode.auto), 0), hasLength(1));
      expect(beamsIn(pair(BeamMode.none), 0), isEmpty);
    });

    test('a note cut at the barline keeps its mode on each piece', () {
      // An eighth on either side of the barline, so that each piece of the
      // cut note has a neighbour the meter would beam it with.
      var session = enterAt(blank(), 0, at(3, 4), value: NoteValue.eighth);
      session = enterAt(session, 1, at(1, 8), value: NoteValue.eighth);
      Score cut(BeamMode beam) => applied(
        session.run(
          EnterNote(
            at: point(session.score, 0, at(7, 8)),
            tone: f4,
            value: NoteValue.quarter,
            beam: beam,
          ),
        ),
      ).score;

      final beamed = cut(BeamMode.auto);
      final apart = cut(BeamMode.none);

      expect(bar(apart, 0).last, 'F4/eighth~');
      expect(bar(apart, 1).first, 'F4/eighth');
      expect([
        beamsIn(beamed, 0),
        beamsIn(beamed, 1),
      ], everyElement(hasLength(1)));
      expect([beamsIn(apart, 0), beamsIn(apart, 1)], everyElement(isEmpty));
    });
  });

  group('without a bar appended', () {
    EditOutcome enterLast(
      EditSession session,
      VoicePoint at,
      NoteValue value,
    ) => session.run(
      EnterNote(at: at, tone: f4, value: value, appendBar: false),
    );

    test('a note that ends the score adds no bar and leaves the cursor at '
        'its start', () {
      final start = blank(bars: 1);
      final last = point(start.score, 0, at(3, 4));

      final session = applied(enterLast(start, last, NoteValue.quarter));

      expect(session.score.measures.length, 1);
      expect(bar(session.score, 0), [
        'rest/half',
        'rest/quarter',
        'F4/quarter',
      ]);
      expect(session.cursor, last);
      expect(
        session.selection.singleEvent!.id,
        (voiceOf(session.score, 0).items.last as Event).id,
      );
    });

    test('a note that ends an inner bar moves the cursor into the next', () {
      final start = blank();

      final session = applied(
        enterLast(start, point(start.score, 0, at(3, 4)), NoteValue.quarter),
      );

      expect(session.score.measures.length, 2);
      expect(session.cursor, point(session.score, 1, Moment.zero));
    });

    test('a note split past the end gets the bars it needs and no more', () {
      final start = blank(bars: 1);
      final half = point(start.score, 0, at(1, 2));

      final inside = applied(
        enterLast(start, point(start.score, 0, at(3, 4)), NoteValue.whole),
      );
      final exact = applied(enterLast(start, half, NoteValue.whole.dotted));

      expect(inside.score.measures.length, 2);
      expect(bar(inside.score, 1), ['F4/half.', 'rest/quarter']);
      expect(inside.cursor, point(inside.score, 1, at(3, 4)));
      expect(exact.score.measures.length, 2);
      expect(bar(exact.score, 0), ['rest/half', 'F4/half~']);
      expect(bar(exact.score, 1), ['F4/whole']);
      expect(exact.cursor, half);
    });

    test('a rest that ends the score adds no bar either', () {
      final start = EditSession.start(
        scoreWith([chord(1, f4, NoteValue.whole)]),
      );
      final last = point(start.score, 0, at(3, 4));

      final session = applied(
        start.run(
          EnterRest(at: last, value: NoteValue.quarter, appendBar: false),
        ),
      );

      expect(session.score.measures.length, 1);
      expect(bar(session.score, 0), ['F4/half.', 'rest/quarter']);
      expect(session.cursor, last);
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

      final reason = refusal(outcome) as WouldSplitTuplet;
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

      expect((refusal(outcome) as StaleReference).target, gone);
    });

    test('an offset at the barline is outside the measure', () {
      final session = blank();
      final end = point(session.score, 0, at(1, 1));

      final outcome = enter(session, end);

      expect((refusal(outcome) as OutsideMeasure).at, end.at);
    });

    test('a point off the 128th-note grid is an invalid value', () {
      final session = blank();

      final outcome = enter(session, point(session.score, 0, at(1, 192)));

      expect(
        (refusal(outcome) as InvalidValue).message,
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
        (refusal(outcome) as InvalidValue).message,
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

    group('laneOf', () {
      List<(int, int, Moment)> lane(
        Score score,
        VoiceSlot voice, {
        int staff = 0,
      }) => [
        for (final timed in score.laneOf(score.staves[staff].id, voice))
          (score.indexOf(timed.ref.measure), timed.event.id.value, timed.onset),
      ];

      Score threeBars() {
        var score = blankScore(bars: 3);
        score = fill(score, 0, [
          chord(10, f4, NoteValue.half),
          rest(11, NoteValue.half),
        ]);
        score = fill(score, 1, [
          tripletOfEighths(1, [
            chord(12, f4, NoteValue.eighth),
            chord(13, g4, NoteValue.eighth),
            chord(14, f4, NoteValue.eighth),
          ]),
          chord(15, g4, NoteValue.quarter),
          chord(16, f4, NoteValue.half),
        ]);
        score = fill(score, 2, [chord(17, g4, NoteValue.whole)]);
        score = fill(score, 0, [
          Gap(len(1, 2)),
          chord(20, g4, NoteValue.half),
        ], slot: VoiceSlot.two);
        return fill(score, 2, [
          rest(21, NoteValue.quarter),
          Gap(len(3, 4)),
        ], slot: VoiceSlot.two);
      }

      test('walks voice one through every bar in order', () {
        expect(lane(threeBars(), VoiceSlot.one), [
          (0, 10, Moment.zero),
          (0, 11, at(1, 2)),
          (1, 12, Moment.zero),
          (1, 13, at(1, 12)),
          (1, 14, at(1, 6)),
          (1, 15, at(1, 4)),
          (1, 16, at(1, 2)),
          (2, 17, Moment.zero),
        ]);
      });

      test('walks voice two, skipping gaps and bars without it', () {
        expect(lane(threeBars(), VoiceSlot.two), [
          (0, 20, at(1, 2)),
          (2, 21, Moment.zero),
        ]);
      });

      test('lists what the bar views list for that voice', () {
        final score = threeBars();

        for (final slot in [VoiceSlot.one, VoiceSlot.two]) {
          expect(
            [
              for (final timed in score.laneOf(score.staves.first.id, slot))
                (timed.ref, timed.onset, timed.duration),
            ],
            [
              for (final column in score.measures)
                for (final voice
                    in score.measureView(column.id).staves.single.voices)
                  if (voice.slot == slot)
                    for (final timed in voice.events)
                      (timed.ref, timed.onset, timed.duration),
            ],
          );
        }
      });

      test('reads only the staff it names', () {
        var score = blankScore(
          parts: const [
            PartTemplate(
              name: 'Duo',
              instrument: fiddle,
              staves: 2,
              clefs: [Clef.treble, Clef.bass],
            ),
          ],
        );
        for (final bar in [0, 1]) {
          score = fill(score, bar, [chord(10 + bar, f4, NoteValue.whole)]);
          score = fill(score, bar, [
            chord(20 + bar, g4, NoteValue.whole),
          ], staff: 1);
        }

        expect(lane(score, VoiceSlot.one), [
          (0, 10, Moment.zero),
          (1, 11, Moment.zero),
        ]);
        expect(lane(score, VoiceSlot.one, staff: 1), [
          (0, 20, Moment.zero),
          (1, 21, Moment.zero),
        ]);
      });
    });

    group('eventBefore and eventAfter', () {
      Score threeBars() {
        var score = blankScore(bars: 3);
        score = fill(score, 0, [
          chord(10, f4, NoteValue.half),
          rest(11, NoteValue.half),
        ]);
        score = fill(score, 1, [
          chord(12, f4, NoteValue.half),
          chord(13, g4, NoteValue.half),
        ]);
        score = fill(score, 2, [chord(14, g4, NoteValue.whole)]);
        score = fill(score, 0, [
          Gap(len(1, 2)),
          chord(20, g4, NoteValue.half),
        ], slot: VoiceSlot.two);
        return fill(score, 2, [
          rest(21, NoteValue.quarter),
          Gap(len(3, 4)),
        ], slot: VoiceSlot.two);
      }

      TimedEvent event(Score score, int id) =>
          score.lookup(score.locate(EventId(id))!)!;

      int? before(Score score, int id) =>
          score.eventBefore(event(score, id))?.event.id.value;

      int? after(Score score, int id) =>
          score.eventAfter(event(score, id))?.event.id.value;

      test('step within a bar', () {
        final score = threeBars();

        expect(before(score, 11), 10);
        expect(after(score, 12), 13);
      });

      test('cross a bar line both ways', () {
        final score = threeBars();

        expect(before(score, 12), 11);
        expect(after(score, 11), 12);
        expect(before(score, 14), 13);
        expect(after(score, 13), 14);
      });

      test('end at the start and the end of the score', () {
        final score = threeBars();

        expect(before(score, 10), isNull);
        expect(after(score, 14), isNull);
      });

      test('do not count the gap that opens or closes a voice', () {
        final score = threeBars();

        expect(before(score, 20), isNull);
        expect(after(score, 21), isNull);
      });

      test('look only into the adjacent bar, which may lack the voice', () {
        final score = threeBars();

        expect(after(score, 20), isNull);
        expect(before(score, 21), isNull);
      });
    });

    group('compare', () {
      test('orders points in one bar by offset', () {
        final score = blankScore();
        final bar = score.measures.first.id;
        final early = ScorePoint(bar, at(1, 4));
        final late = ScorePoint(bar, at(1, 2));

        expect(score.compare(early, late), isNegative);
        expect(score.compare(late, early), isPositive);
        expect(score.compare(early, ScorePoint(bar, at(1, 4))), 0);
      });

      test('orders an earlier bar first whatever the offsets', () {
        final score = blankScore();
        final [first, second] = barIds(score);

        expect(
          score.compare(
            ScorePoint(first, at(3, 4)),
            ScorePoint(second, Moment.zero),
          ),
          isNegative,
        );
        expect(
          score.compare(
            ScorePoint(second, Moment.zero),
            ScorePoint(first, at(3, 4)),
          ),
          isPositive,
        );
      });

      test('orders bars by their place in the score, not their ids', () {
        final session = blank();
        final score = applied(
          session.run(InsertMeasures(before: idOf(session, 0))),
        ).score;
        final [inserted, old] = barIds(score).take(2).toList();
        expect(inserted.value, greaterThan(old.value));

        expect(
          score.compare(
            ScorePoint(inserted, Moment.zero),
            ScorePoint(old, Moment.zero),
          ),
          isNegative,
        );
      });

      test('throws for a bar not in the score', () {
        final score = blankScore();
        final known = ScorePoint(score.measures.first.id, Moment.zero);
        const stranger = ScorePoint(MeasureId(999), Moment.zero);

        expect(() => score.compare(known, stranger), throwsArgumentError);
      });
    });

    group('laneBetween', () {
      Score threeBars() {
        var score = blankScore(bars: 3);
        score = fill(score, 0, [
          chord(10, f4, NoteValue.half),
          chord(11, g4, NoteValue.half),
        ]);
        score = fill(score, 1, [
          chord(12, f4, NoteValue.quarter),
          chord(13, g4, NoteValue.quarter),
          chord(14, f4, NoteValue.half),
        ]);
        score = fill(score, 2, [chord(15, g4, NoteValue.whole)]);
        return fill(score, 1, [
          Gap(len(1, 2)),
          chord(20, g4, NoteValue.half),
        ], slot: VoiceSlot.two);
      }

      List<int> between(
        Score score,
        (int, Moment) from,
        (int, Moment) to, {
        VoiceSlot voice = VoiceSlot.one,
      }) {
        ScorePoint point((int, Moment) p) =>
            ScorePoint(score.measures[p.$1].id, p.$2);
        return [
          for (final timed in score.laneBetween(
            score.staves.first.id,
            voice,
            point(from),
            point(to),
          ))
            timed.event.id.value,
        ];
      }

      test('takes the events starting at or after from and before to', () {
        final score = threeBars();

        expect(between(score, (1, at(1, 4)), (1, at(3, 4))), [13, 14]);
        expect(between(score, (1, at(1, 4)), (1, at(1, 2))), [13]);
      });

      test('skips an event that starts before from and sounds into it', () {
        final score = threeBars();

        expect(between(score, (0, at(1, 4)), (1, at(1, 4))), [11, 12]);
      });

      test('runs across bars in score order', () {
        final score = threeBars();

        expect(
          between(score, (0, at(1, 2)), (2, Moment.zero)),
          [11, 12, 13, 14],
        );
      });

      test('reaches the last event when to sits at the end of its bar', () {
        final score = threeBars();

        expect(between(score, (1, at(1, 2)), (2, at(1, 1))), [14, 15]);
      });

      test('reads only the voice it names, skipping bars without it', () {
        final score = threeBars();

        expect(
          between(
            score,
            (0, Moment.zero),
            (2, at(1, 1)),
            voice: VoiceSlot.two,
          ),
          [20],
        );
      });

      test('is empty when to does not come after from', () {
        final score = threeBars();

        expect(between(score, (1, at(1, 2)), (1, at(1, 2))), isEmpty);
        expect(between(score, (2, Moment.zero), (0, Moment.zero)), isEmpty);
      });
    });

    group('stavesBetween', () {
      final score = blankScore(
        parts: const [
          PartTemplate(
            name: 'Trio',
            instrument: fiddle,
            staves: 3,
            clefs: [Clef.treble, Clef.treble, Clef.bass],
          ),
        ],
      );
      final [top, middle, bottom] = [for (final s in score.staves) s.id];

      test('lists the staves from the first end to the second', () {
        expect(score.stavesBetween(top, bottom), [top, middle, bottom]);
        expect(score.stavesBetween(middle, bottom), [middle, bottom]);
      });

      test('lists them in system order when the ends are inverted', () {
        expect(score.stavesBetween(bottom, top), [top, middle, bottom]);
        expect(score.stavesBetween(bottom, middle), [middle, bottom]);
      });

      test('is the one staff when both ends name it', () {
        expect(score.stavesBetween(middle, middle), [middle]);
      });

      test('is null when either staff is not in the score', () {
        const gone = StaffId(999);

        expect(score.stavesBetween(gone, bottom), isNull);
        expect(score.stavesBetween(top, gone), isNull);
      });
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
