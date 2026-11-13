import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

EditOutcome push(
  EditSession session,
  VoicePoint at, {
  String tone = 'C5',
  NoteValue value = NoteValue.quarter,
  Overfill overfill = Overfill.splitAndTie,
  bool appendBar = false,
}) => session.run(
  EnterNote(
    at: at,
    tone: Pitch.parse(tone),
    value: value,
    overfill: overfill,
    appendBar: appendBar,
    ripple: Ripple.part,
  ),
);

EditOutcome pull(EditSession session, List<int> ids) => session.run(
  Erase(
    ItemSelection(Seq([for (final id in ids) eventRef(session, id)])),
    ripple: Ripple.part,
  ),
);

EditOutcome revalue(EditSession session, int id, NoteValue value) =>
    session.run(SetValue(eventRef(session, id), value, ripple: Ripple.part));

/// One quarter per pitch of [pitches], with ids from [first].
List<VoiceItem> quarters(int first, String pitches) => [
  for (final (i, pitch) in pitches.split(' ').indexed)
    chordOf(first + i, pitch),
];

/// A session over one bar per entry of [bars], an empty entry left as a
/// bar rest.
EditSession barsOf(List<List<VoiceItem>> bars) {
  var score = blankScore(bars: bars.length);
  for (final (i, items) in bars.indexed) {
    if (items.isNotEmpty) {
      score = fill(score, i, items);
    }
  }
  return EditSession.start(score);
}

Tuplet tripletOfQuarters() => Tuplet(
  id: const TupletId(5),
  ratio: TupletRatio.triplet,
  unit: NoteValue.quarter,
  members: Seq([chordOf(1, 'F4'), chordOf(2, 'G4'), chordOf(3, 'A4')]),
);

List<String> staffBar(Score score, int bar, int staff) => describe(
  score.measures[bar].staves[staff].voice(VoiceSlot.one)!.items,
);

void main() {
  group('Entry that pushes', () {
    test('pushes the later notes of the voice by the new note', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4'), []]);

      final next = applied(push(session, point(session.score, 0, at(1, 4))));

      expect(bar(next.score, 0), [
        'F4/quarter',
        'C5/quarter',
        'G4/quarter',
        'A4/quarter',
      ]);
      expect(bar(next.score, 1), ['B4/quarter', 'rest/quarter', 'rest/half']);
      expect(next.score.measures, hasLength(2));
    });

    test('takes the time of a rest and pushes nothing', () {
      final session = barsOf([
        [chordOf(1, 'F4'), rest(2, NoteValue.quarter), ...quarters(3, 'G4 A4')],
        quarters(5, 'B4 C5 D5 E5'),
      ]);

      final next = applied(push(session, point(session.score, 0, at(1, 4))));

      expect(bar(next.score, 0), [
        'F4/quarter',
        'C5/quarter',
        'G4/quarter',
        'A4/quarter',
      ]);
      expect(next.score.measures[1], same(session.score.measures[1]));
    });

    test(
      'takes the rest it finds first and pushes by the rest of the note',
      () {
        final session = barsOf([
          [
            chordOf(1, 'F4'),
            rest(2, NoteValue.quarter),
            ...quarters(3, 'G4 A4'),
          ],
          [],
        ]);

        final next = applied(
          push(
            session,
            point(session.score, 0, at(1, 4)),
            value: NoteValue.half,
          ),
        );

        expect(bar(next.score, 0), ['F4/quarter', 'C5/half', 'G4/quarter']);
        expect(bar(next.score, 1), ['A4/quarter', 'rest/quarter', 'rest/half']);
      },
    );

    test('splits a note it lands inside and pushes its tail', () {
      final session = barsOf([
        [chordOf(1, 'F4', value: NoteValue.half), ...quarters(2, 'G4 A4')],
        [],
      ]);

      final next = applied(push(session, point(session.score, 0, at(1, 4))));

      expect(bar(next.score, 0), [
        'F4/quarter',
        'C5/quarter',
        'F4/quarter',
        'G4/quarter',
      ]);
      expect(bar(next.score, 1), ['A4/quarter', 'rest/quarter', 'rest/half']);
      expect(tiesOf(next, 1), {'F4': false});
    });

    test('cuts a note pushed across a barline and ties it', () {
      final session = barsOf([
        [...quarters(1, 'F4 G4'), chordOf(3, 'A4', value: NoteValue.half)],
        [],
      ]);

      final next = applied(push(session, point(session.score, 0, Moment.zero)));

      expect(bar(next.score, 0), [
        'C5/quarter',
        'F4/quarter',
        'G4/quarter',
        'A4/quarter~',
      ]);
      expect(bar(next.score, 1), ['A4/quarter', 'rest/quarter', 'rest/half']);
      expect(firstEvent(next.score, 0), isA<ChordEvent>());
      expect(chordIn(next, 3).value, NoteValue.quarter);
    });

    test('adds bars when the music passes the last bar', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4')]);

      final next = applied(push(session, point(session.score, 0, Moment.zero)));

      expect(next.score.measures, hasLength(2));
      expect(bar(next.score, 1), ['B4/quarter', 'rest/quarter', 'rest/half']);
    });

    test('puts the cursor after the new note', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4'), []]);

      final next = applied(push(session, point(session.score, 0, at(3, 4))));

      expect(next.cursor.at, pointAt(next.score, 1, Moment.zero));
      expect(bar(next.score, 1), ['B4/quarter', 'rest/quarter', 'rest/half']);
    });

    test('refuses a note past the barline when asked to', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4'), []]);

      expect(
        refusal(
          push(
            session,
            point(session.score, 0, at(3, 4)),
            value: NoteValue.half,
            overfill: Overfill.refuse,
          ),
        ),
        isA<WouldCrossBarline>(),
      );
    });

    test('leaves entry overwriting when no ripple is asked for', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4'), []]);

      final next = applied(
        session.run(
          EnterNote(
            at: point(session.score, 0, at(1, 4)),
            tone: Pitch.parse('C5'),
            value: NoteValue.quarter,
          ),
        ),
      );

      expect(bar(next.score, 0), [
        'F4/quarter',
        'C5/quarter',
        'A4/quarter',
        'B4/quarter',
      ]);
      expect(next.score.measures[1], same(session.score.measures[1]));
    });
  });

  group('Delete and value changes that pull', () {
    test('a deleted note pulls the later notes back', () {
      final session = barsOf([
        quarters(1, 'F4 G4 A4 B4'),
        quarters(5, 'C5 D5 E5 F5'),
      ]);

      final next = applied(pull(session, [2]));

      expect(bar(next.score, 0), [
        'F4/quarter',
        'A4/quarter',
        'B4/quarter',
        'C5/quarter',
      ]);
      expect(bar(next.score, 1), [
        'D5/quarter',
        'E5/quarter',
        'F5/quarter',
        'rest/quarter',
      ]);
      expect(next.score.measures, hasLength(2));
    });

    test('a longer value pushes and a shorter one pulls', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4'), []]);

      final longer = applied(revalue(session, 2, NoteValue.half));

      expect(bar(longer.score, 0), ['F4/quarter', 'G4/half', 'A4/quarter']);
      expect(bar(longer.score, 1), ['B4/quarter', 'rest/quarter', 'rest/half']);

      final shorter = applied(revalue(longer, 2, NoteValue.quarter));

      expect(bar(shorter.score, 0), bar(session.score, 0));
      expect(bar(shorter.score, 1), ['measure-rest']);
    });

    test('keeps a note a pull brings back into one bar tied', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4'), []]);
      final pushed = applied(
        push(
          session,
          point(session.score, 0, Moment.zero),
          value: NoteValue.eighth,
        ),
      );

      final next = applied(pull(pushed, [eventIdAt(pushed, 0, 0)]));

      expect(bar(next.score, 0), [
        'F4/quarter',
        'G4/quarter',
        'A4/quarter',
        'B4/eighth~',
        'B4/eighth',
      ]);
      expect(bar(next.score, 1), ['measure-rest']);
    });

    test('refuses to change the value of a tuplet note', () {
      final session = barsOf([
        [
          chordOf(4, 'C5'),
          tripletOfQuarters(),
          chordOf(6, 'D5'),
        ],
      ]);

      expect(
        refusal(revalue(session, 2, NoteValue.quarter)),
        isA<WouldSplitTuplet>(),
      );
      expect(refusal(pull(session, [2])), isA<WouldSplitTuplet>());
    });
  });

  group('What a ripple moves', () {
    test('moves only the edited part', () {
      final score = fill(
        fill(
          blankScore(parts: const [morinKhuur, morinKhuur]),
          0,
          quarters(1, 'F4 G4 A4 B4'),
        ),
        0,
        quarters(11, 'D4 E4 F4 G4'),
        staff: 1,
      );
      final session = EditSession.start(score);

      final next = applied(push(session, point(score, 0, Moment.zero)));

      expect(staffBar(next.score, 0, 1), staffBar(score, 0, 1));
      expect(
        next.score.measures[0].staves[1],
        same(score.measures[0].staves[1]),
      );
      expect(
        next.score.measures[1].staves[1],
        same(score.measures[1].staves[1]),
      );
    });

    test('moves every voice and staff of the part together', () {
      var score = blankScore(parts: const [piano]);
      score = fill(score, 0, quarters(1, 'F4 G4 A4 B4'));
      score = fill(score, 0, quarters(11, 'C3 D3 E3 F3'), staff: 1);
      score = fill(
        score,
        0,
        [chordOf(21, 'C4', value: NoteValue.whole)],
        slot: VoiceSlot.two,
      );
      final session = EditSession.start(score);

      final next = applied(push(session, point(score, 0, at(1, 4))));

      expect(staffBar(next.score, 0, 1), [
        'C3/quarter',
        'rest/quarter',
        'D3/quarter',
        'E3/quarter',
      ]);
      expect(staffBar(next.score, 1, 1), [
        'F3/quarter',
        'rest/quarter',
        'rest/half',
      ]);
      expect(describe(voiceOf(next.score, 0, slot: VoiceSlot.two).items), [
        'C4/whole~',
      ]);
      expect(describe(voiceOf(next.score, 1, slot: VoiceSlot.two).items), [
        'C4/quarter',
        'gap 3/4',
      ]);
    });

    test('carries slurs, dynamics and fingerings with their notes', () {
      var score = fill(blankScore(), 0, [
        chordOf(1, 'F4'),
        ChordEvent(
          id: const EventId(2),
          value: NoteValue.quarter,
          notes: Seq([
            PitchedNote(id: const NoteId(20), pitch: g4, fingering: 2),
          ]),
        ),
        ...quarters(3, 'A4 B4'),
      ]);
      score = withSlur(
        score,
        pointAt(score, 0, at(1, 4)),
        pointAt(score, 0, at(3, 4)),
      );
      score = changeBar(
        score,
        0,
        (column) => column.withStaff(
          column.staves.first.copyWith(
            directions: Seq([DynamicMark(at(1, 4), Dynamic.f)]),
          ),
        ),
      );
      final session = EditSession.start(score);

      final next = applied(push(session, point(score, 0, Moment.zero)));
      final slur = next.score.spanners.single;

      expect(slur.first, pointAt(next.score, 0, at(1, 2)));
      expect(slur.last, pointAt(next.score, 1, Moment.zero));
      expect(
        [
          for (final d in next.score.measures[0].staves.first.directions)
            mark(d),
        ],
        ['1/2 f'],
      );
      expect((chordIn(next, 2).notes.single as PitchedNote).fingering, 2);
    });

    test('grows a section before its closing barline', () {
      var score = fill(blankScore(), 0, quarters(1, 'F4 G4 A4 B4'));
      score = fill(score, 1, quarters(5, 'C5 D5 E5 F5'));
      score = changeBar(
        score,
        0,
        (column) => column.copyWith(repeatEnd: () => const RepeatEnd()),
      );
      final session = EditSession.start(score);

      final next = applied(push(session, point(score, 0, Moment.zero)));

      expect(next.score.measures, hasLength(3));
      expect(next.score.measures[0].repeatEnd, isNull);
      expect(next.score.measures[1].repeatEnd, const RepeatEnd());
      expect(bar(next.score, 1), ['B4/quarter', 'rest/quarter', 'rest/half']);
      expect(next.score.measures[2], same(score.measures[1]));
    });

    test('leaves rests at the end of a section a pull shortens', () {
      var score = fill(blankScore(bars: 3), 0, quarters(1, 'F4 G4 A4 B4'));
      score = fill(score, 1, quarters(5, 'C5 D5 E5 F5'));
      score = fill(score, 2, quarters(9, 'G5 A5 B5 C6'));
      score = changeBar(
        score,
        1,
        (column) => column.copyWith(barline: Barline.doubleBar),
      );
      final session = EditSession.start(score);

      final next = applied(pull(session, [1]));

      expect(next.score.measures, hasLength(3));
      expect(bar(next.score, 1), [
        'D5/quarter',
        'E5/quarter',
        'F5/quarter',
        'rest/quarter',
      ]);
      expect(next.score.measures[2], same(score.measures[2]));
    });

    test('refuses to grow a pickup bar', () {
      final score = changeBar(
        blankScore(),
        0,
        (column) => column.copyWith(
          irregularLength: () => len(1, 4),
          staves: Seq([
            column.staves.first.withVoice(
              Voice(slot: VoiceSlot.one, items: Seq([chordOf(1, 'F4')])),
            ),
          ]),
        ),
      );
      final session = EditSession.start(score);

      expect(
        refusal(push(session, point(score, 0, Moment.zero))),
        isA<WouldCrossBarline>(),
      );
    });

    test('refuses a push that would cut a tuplet at a barline', () {
      final session = barsOf([
        [
          chordOf(4, 'C5'),
          tripletOfQuarters(),
          chordOf(6, 'D5'),
        ],
        [],
      ]);

      expect(
        refusal(
          push(
            session,
            point(session.score, 0, Moment.zero),
            value: NoteValue.half,
          ),
        ),
        isA<WouldSplitTuplet>(),
      );
    });
  });

  group('Tuplets, rests and ranges', () {
    test('pushes a whole tuplet a note is entered at the start of', () {
      final session = barsOf([
        [chordOf(4, 'C5'), tripletOfQuarters(), chordOf(6, 'D5')],
        [],
      ]);

      final next = applied(push(session, point(session.score, 0, at(1, 4))));

      expect(bar(next.score, 0), [
        'C5/quarter',
        'C5/quarter',
        '3:2[F4/quarter, G4/quarter, A4/quarter]',
      ]);
      expect(bar(next.score, 1), ['D5/quarter', 'rest/quarter', 'rest/half']);
    });

    test('fills a rest inside a tuplet and pushes nothing', () {
      final session = barsOf([
        [
          chordOf(4, 'C5'),
          Tuplet(
            id: const TupletId(5),
            ratio: TupletRatio.triplet,
            unit: NoteValue.quarter,
            members: Seq([
              chordOf(1, 'F4'),
              rest(2, NoteValue.quarter),
              chordOf(3, 'A4'),
            ]),
          ),
          chordOf(6, 'D5'),
        ],
        [],
      ]);

      final next = applied(
        push(session, point(session.score, 0, at(1, 4) + len(1, 6))),
      );

      expect(bar(next.score, 0), [
        'C5/quarter',
        '3:2[F4/quarter, C5/quarter, A4/quarter]',
        'D5/quarter',
      ]);
      expect(next.score.measures[1], same(session.score.measures[1]));
    });

    test('refuses a note entered inside a tuplet with no room', () {
      final session = barsOf([
        [chordOf(4, 'C5'), tripletOfQuarters(), chordOf(6, 'D5')],
      ]);

      expect(
        refusal(push(session, point(session.score, 0, at(1, 4) + len(1, 6)))),
        isA<WouldSplitTuplet>(),
      );
    });

    test('a rest entered among notes pushes them too', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4'), []]);

      final next = applied(
        session.run(
          EnterRest(
            at: point(session.score, 0, Moment.zero),
            value: NoteValue.quarter,
            ripple: Ripple.part,
          ),
        ),
      );

      expect(bar(next.score, 0), [
        'rest/quarter',
        'F4/quarter',
        'G4/quarter',
        'A4/quarter',
      ]);
      expect(bar(next.score, 1), ['B4/quarter', 'rest/quarter', 'rest/half']);
    });

    test('an erased range pulls the music after it back', () {
      final session = barsOf([
        quarters(1, 'F4 G4 A4 B4'),
        quarters(5, 'C5 D5 E5 F5'),
      ]);
      final score = session.score;

      final next = applied(
        session.run(
          Erase(
            RangeSelection(
              from: pointAt(score, 0, at(1, 2)),
              to: pointAt(score, 1, at(1, 4)),
              top: score.staves.first.id,
              bottom: score.staves.first.id,
            ),
            ripple: Ripple.part,
          ),
        ),
      );

      expect(bar(next.score, 0), [
        'F4/quarter',
        'G4/quarter',
        'D5/quarter',
        'E5/quarter',
      ]);
      expect(bar(next.score, 1), ['F5/quarter', 'rest/quarter', 'rest/half']);
      expect(next.selection, isA<NoSelection>());
    });
  });

  group('Review regressions', () {
    test('clears the ties of other parts that a grown section cuts off', () {
      var score = blankScore(parts: const [morinKhuur, morinKhuur]);
      score = fill(score, 0, quarters(1, 'F4 G4 A4 B4'));
      score = fill(score, 0, [
        chordOf(11, 'C5', value: NoteValue.whole, tie: true),
      ], staff: 1);
      score = fill(score, 1, [
        chordOf(12, 'C5', value: NoteValue.whole),
      ], staff: 1);
      score = changeBar(
        score,
        0,
        (column) => column.copyWith(barline: Barline.doubleBar),
      );
      final session = EditSession.start(score);

      final next = applied(push(session, point(score, 0, at(1, 4))));

      expect(next.score.measures, hasLength(3));
      expect(staffBar(next.score, 0, 1), ['C5/whole']);
      expect(staffBar(next.score, 1, 1), ['measure-rest']);
      expect(staffBar(next.score, 2, 1), ['C5/whole']);
    });

    test('takes every picked event out whole', () {
      final session = barsOf([
        [
          chordOf(1, 'F4', value: NoteValue.eighth),
          chordOf(2, 'G4', value: NoteValue.eighth),
          ...quarters(3, 'A4 B4 C5'),
        ],
        [chordOf(6, 'D5', value: NoteValue.half), ...quarters(7, 'E5 F5')],
      ]);

      final next = applied(pull(session, [1, 6]));

      expect(bar(next.score, 0), [
        'G4/eighth',
        'A4/quarter',
        'B4/quarter',
        'C5/quarter',
        'E5/eighth~',
      ]);
      expect(bar(next.score, 1).take(2), ['E5/eighth', 'F5/quarter']);
    });

    test('keeps a mark on rests that a push takes up', () {
      var score = fill(blankScore(bars: 1), 0, [
        ...quarters(1, 'F4 G4'),
        rest(3, NoteValue.half),
      ]);
      score = changeBar(
        score,
        0,
        (column) => column.withStaff(
          column.staves.first.copyWith(
            directions: Seq([DynamicMark(at(3, 4), Dynamic.p)]),
          ),
        ),
      );
      final session = EditSession.start(score);

      final next = applied(
        push(session, point(score, 0, Moment.zero), value: NoteValue.half),
      );

      expect(bar(next.score, 0), ['C5/half', 'F4/quarter', 'G4/quarter']);
      expect(
        [
          for (final d in next.score.measures[0].staves.first.directions)
            mark(d),
        ],
        ['3/4 p'],
      );
    });

    test('grows no bar for blank time that runs past the section', () {
      var score = fill(blankScore(), 0, [
        ...quarters(1, 'F4 G4 A4'),
        rest(4, NoteValue.quarter),
      ]);
      score = fill(score, 1, quarters(5, 'C5 D5 E5 F5'));
      score = changeBar(
        score,
        0,
        (column) => column.copyWith(barline: Barline.doubleBar),
      );
      final session = EditSession.start(score);

      final next = applied(revalue(session, 4, NoteValue.half));

      expect(next.score.measures, hasLength(2));
      expect(bar(next.score, 0), bar(score, 0));
    });

    test('a range that is not erased follows the music of an erase', () {
      final session = barsOf([
        quarters(1, 'F4 G4 A4 B4'),
        quarters(5, 'C5 D5 E5 F5'),
      ]);
      final score = session.score;
      final ranged = session.select(
        RangeSelection(
          from: pointAt(score, 1, Moment.zero),
          to: pointAt(score, 1, at(1, 2)),
          top: score.staves.first.id,
          bottom: score.staves.first.id,
        ),
      );

      final next = applied(pull(ranged, [2]));
      final range = next.selection as RangeSelection;

      expect(range.from, pointAt(next.score, 0, at(3, 4)));
      expect(range.to, pointAt(next.score, 1, at(1, 4)));
    });
  });

  group('Marks a ripple moves stay loadable', () {
    test('of clef changes a pull brings together, the last one stays', () {
      final blank = blankScore();
      final staff = blank.staves.first.id;
      var session = EditSession.start(blank);
      for (final (offset, clef) in [
        (at(1, 2), Clef.bass),
        (at(3, 4), Clef.alto),
      ]) {
        session = applied(
          session.run(
            SetClef(staff: staff, at: pointAt(blank, 0, offset), clef: clef),
          ),
        );
      }

      final next = applied(
        session.run(
          Erase(
            RangeSelection(
              from: pointAt(blank, 0, at(1, 4)),
              to: pointAt(blank, 0, at(3, 4)),
              top: staff,
              bottom: staff,
            ),
            ripple: Ripple.part,
          ),
        ),
      );

      expect(saved(reloaded(next.score)), saved(next.score));
      expect(next.score.measures[0].staves.first.clefChanges.toList(), [
        ClefChange(at(1, 4), Clef.alto),
      ]);
    });

    test('drops a clef change a pull leaves on the clef in force', () {
      final blank = blankScore();
      final staff = blank.staves.first.id;
      var session = EditSession.start(blank);
      for (final (offset, clef) in [
        (at(1, 2), Clef.bass),
        (at(3, 4), Clef.treble),
      ]) {
        session = applied(
          session.run(
            SetClef(staff: staff, at: pointAt(blank, 0, offset), clef: clef),
          ),
        );
      }

      final next = applied(
        session.run(
          Erase(
            RangeSelection(
              from: pointAt(blank, 0, at(1, 4)),
              to: pointAt(blank, 0, at(3, 4)),
              top: staff,
              bottom: staff,
            ),
            ripple: Ripple.part,
          ),
        ),
      );

      expect(next.score.measures[0].staves.first.clef, Clef.treble);
      expect(next.score.measures[0].staves.first.clefChanges, isEmpty);
    });

    test('keeps directions in time order when a push passes one', () {
      final blank = blankScore(bars: 1);
      var session = applied(
        EditSession.start(blank).run(
          EnterNote(
            at: point(blank, 0, at(1, 4)),
            tone: f4,
            value: NoteValue.sixteenth,
          ),
        ),
      );
      session = applied(
        session.run(
          SetDirections(
            staff: blank.staves.first.id,
            measure: blank.measures[0].id,
            directions: Seq([
              DynamicMark(at(1, 2), Dynamic.p),
              DynamicMark(at(3, 4), Dynamic.f),
            ]),
          ),
        ),
      );
      final note = voiceOf(session.score, 0).items.whereType<ChordEvent>();

      final next = applied(
        revalue(session, note.single.id.value, NoteValue.half),
      );

      expect(saved(reloaded(next.score)), saved(next.score));
      expect(
        [
          for (final d in next.score.measures[0].staves.first.directions)
            mark(d),
        ],
        ['3/4 f', '15/16 p'],
      );
    });
  });

  group('A ripple and the session', () {
    test('a range selection follows the music', () {
      final session = barsOf([
        quarters(1, 'F4 G4 A4 B4'),
        quarters(5, 'C5 D5 E5 F5'),
      ]);
      final score = session.score;
      final ranged = session.select(
        RangeSelection(
          from: pointAt(score, 1, Moment.zero),
          to: pointAt(score, 1, at(1, 2)),
          top: score.staves.first.id,
          bottom: score.staves.first.id,
        ),
      );

      final next = applied(revalue(ranged, 2, NoteValue.half));

      final range = next.selection as RangeSelection;

      expect(range.from, pointAt(next.score, 1, at(1, 4)));
      expect(range.to, pointAt(next.score, 1, at(3, 4)));
    });

    test('the cursor follows the music it sat on', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4'), []]);
      final placed = session.placeCursor(point(session.score, 0, at(3, 4)));

      final next = applied(revalue(placed, 1, NoteValue.half));

      expect(next.cursor.at, pointAt(next.score, 1, Moment.zero));
    });

    test('is one undo step', () {
      final session = barsOf([quarters(1, 'F4 G4 A4 B4')]);

      final next = applied(push(session, point(session.score, 0, Moment.zero)));

      final undone = next.undo();

      expect(undone.canUndo, isFalse);
      expect(undone.score.measures, hasLength(1));
      expect(bar(undone.score, 0), bar(session.score, 0));
    });

    test('reports every bar it touched as changed', () {
      final session = barsOf([
        quarters(1, 'F4 G4 A4 B4'),
        quarters(5, 'C5 D5 E5 F5'),
        [],
        [],
      ]);

      final next = applied(push(session, point(session.score, 0, Moment.zero)));
      final changes = next.score.changesSince(session.score);

      expect(
        changes.relayout,
        containsAll([for (var i = 0; i < 3; i++) next.score.measures[i].id]),
      );
      expect(bar(next.score, 2), ['F5/quarter', 'rest/quarter', 'rest/half']);
      expect(next.score.measures[3], same(session.score.measures[3]));
    });
  });
}

int eventIdAt(EditSession session, int barIndex, int index) =>
    (voiceOf(session.score, barIndex).items[index] as Event).id.value;
