import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

RangeSelection range(
  Score score,
  (int, Moment) from,
  (int, Moment) to, {
  int bottom = 0,
}) => RangeSelection(
  from: pointAt(score, from.$1, from.$2),
  to: pointAt(score, to.$1, to.$2),
  top: score.staves.first.id,
  bottom: score.staves[bottom].id,
);

ScoreClip copyOf(EditSession session, (int, Moment) from, (int, Moment) to) =>
    session.select(range(session.score, from, to)).copy()!;

EditOutcome paste(
  EditSession session,
  ScoreClip clip,
  int bar,
  Moment offset, {
  int staff = 0,
  Overfill overfill = Overfill.splitAndTie,
}) => session.run(
  Paste(
    clip,
    at: VoicePoint(
      staff: session.score.staves[staff].id,
      voice: VoiceSlot.one,
      at: pointAt(session.score, bar, offset),
    ),
    overfill: overfill,
  ),
);

EditSession pasted(
  EditSession session,
  ScoreClip clip,
  int bar,
  Moment offset,
) => applied(paste(session, clip, bar, offset));

Set<Object> idsIn(Score score, int bar) => {
  for (final item in voiceOf(score, bar).items)
    ...switch (item) {
      Tuplet(:final id, :final members) => [
        id,
        for (final m in members)
          if (m is Event) m.id,
      ],
      ChordEvent(:final id, :final notes, :final graces) => [
        id,
        for (final n in notes) n.id,
        for (final g in graces) ...[g.id, for (final n in g.notes) n.id],
      ],
      Event(:final id) => [id],
      Gap() => const [],
    },
};

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
  group('copy', () {
    test('is null with nothing selected', () {
      expect(blank().copy(), isNull);
    });

    test('takes the smallest range covering the picked events', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4'),
          chordOf(2, 'G4'),
          chordOf(3, 'A4'),
          chordOf(4, 'C5'),
        ],
        [rest(5, NoteValue.whole)],
      ]);
      final clip = session
          .select(
            ItemSelection(
              Seq([
                eventRef(session, 3),
                NoteRef(eventRef(session, 2), const NoteId(20)),
                eventRef(session, 4),
              ]),
            ),
          )
          .copy()!;

      final next = pasted(session, clip, 1, Moment.zero);

      expect(clip.length, len(3, 4));
      expect(bar(next.score, 1), [
        'G4/quarter',
        'A4/quarter',
        'C5/quarter',
        'rest/quarter',
      ]);
    });

    test('is null for a range that is empty or leaves its bars', () {
      final session = sessionWith([
        [chordOf(1, 'F4'), chordOf(2, 'G4'), rest(3, NoteValue.half)],
        [rest(4, NoteValue.whole)],
      ]);
      for (final (from, to) in [
        ((0, at(1, 4)), (0, at(1, 4))),
        ((0, at(1, 2)), (0, at(1, 4))),
        ((0, Moment.zero), (0, at(5, 4))),
        ((0, at(-1, 4)), (0, at(1, 4))),
        ((0, at(5, 4)), (1, at(1, 2))),
        ((0, Moment.zero), (1, at(-1, 4))),
      ]) {
        expect(session.select(range(session.score, from, to)).copy(), isNull);
      }
    });

    test('covers the whole tuplet of a picked member', () {
      final session = sessionWith([
        triplet(),
        [rest(7, NoteValue.whole)],
      ]);
      final clip = session
          .select(Selection.event(eventRef(session, 2)))
          .copy()!;

      final next = pasted(session, clip, 1, Moment.zero);

      expect(clip.length, len(1, 2));
      expect(bar(next.score, 1), [
        '3:2[F4/quarter, G4/quarter, A4/quarter]',
        'rest/half',
      ]);
    });

    test('covers the staves of the picked events', () {
      var score = blankScore(parts: const [piano]);
      for (final staff in [0, 1]) {
        score = fill(score, 0, [
          chordOf(1 + staff, staff == 0 ? 'C5' : 'C3', value: NoteValue.whole),
        ], staff: staff);
      }
      final session = EditSession.start(score);
      final clip = session
          .select(
            ItemSelection(Seq([eventRef(session, 2), eventRef(session, 1)])),
          )
          .copy()!;

      expect(clip.staffCount, 2);
    });

    test('runs to the end of the last event it takes', () {
      final session = sessionWith([
        [chordOf(1, 'F4', value: NoteValue.half), rest(2, NoteValue.half)],
        [chordOf(3, 'C5'), chordOf(4, 'D5'), rest(5, NoteValue.half)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (0, at(1, 4)));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(clip.length, len(1, 2));
      expect(bar(next.score, 1), ['F4/half', 'rest/half']);
    });

    test('drops a tie into a tuplet it leaves out', () {
      final session = sessionWith([
        [
          chordOf(4, 'F4', tie: true),
          Tuplet(
            id: const TupletId(5),
            ratio: TupletRatio.triplet,
            unit: NoteValue.quarter,
            members: Seq([
              chordOf(1, 'F4'),
              chordOf(2, 'G4'),
              chordOf(3, 'A4'),
            ]),
          ),
          chordOf(6, 'D5'),
        ],
        [rest(7, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (0, at(1, 2)));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(bar(next.score, 1), ['F4/quarter', 'rest/quarter', 'rest/half']);
    });
  });

  group('Paste', () {
    test('clears a let-ring tie that a pasted head of its tone would '
        'end', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half, tie: true),
          chordOf(2, 'G4', value: NoteValue.half),
        ],
        [
          chordOf(3, 'F4', value: NoteValue.half),
          chordOf(4, 'A4', value: NoteValue.half),
        ],
      ]);
      final clip = copyOf(session, (1, Moment.zero), (1, at(1, 2)));

      final next = pasted(session, clip, 0, at(1, 2));

      expect(bar(next.score, 0), ['F4/half', 'F4/half']);
    });

    test('clears a let-ring tie in the bar before the paste', () {
      final session = sessionWith([
        [
          chordOf(1, 'G4', value: NoteValue.half),
          chordOf(2, 'F4', value: NoteValue.half, tie: true),
        ],
        [
          chordOf(3, 'G4', value: NoteValue.half),
          chordOf(4, 'A4', value: NoteValue.half),
        ],
        [
          chordOf(5, 'F4', value: NoteValue.half),
          chordOf(6, 'A4', value: NoteValue.half),
        ],
      ]);
      final clip = copyOf(session, (2, Moment.zero), (2, at(1, 2)));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(bar(next.score, 0), ['G4/half', 'F4/half']);
    });

    test('writes a copied bar over another with new ids', () {
      final grace = GraceChord(
        id: const EventId(5),
        kind: GraceKind.acciaccatura,
        value: NoteValue.eighth,
        notes: Seq([
          PitchedNote(id: const NoteId(50), pitch: Pitch.parse('C5')),
        ]),
      );
      final session = sessionWith([
        [
          chordOf(1, 'F4 A4', graces: [grace]),
          chordOf(2, 'G4'),
          rest(3, NoteValue.half),
        ],
        [chordOf(4, 'C5', value: NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (1, Moment.zero));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(bar(next.score, 1), bar(session.score, 0));
      expect(bar(next.score, 0), bar(session.score, 0));
      expect(idsIn(next.score, 1).intersection(idsIn(next.score, 0)), isEmpty);
    });

    test('keeps what each event carries', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4').copyWith(articulations: {Articulation.staccato}),
          const RestEvent(
            id: EventId(2),
            value: NoteValue.quarter,
            articulations: {Articulation.fermata},
          ),
          const RestEvent(id: EventId(3), value: NoteValue.half, hidden: true),
        ],
        [rest(4, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (1, Moment.zero));

      final next = pasted(session, clip, 1, Moment.zero);

      final items = voiceOf(next.score, 1).items.cast<Event>().toList();
      expect(bar(next.score, 1), bar(session.score, 0));
      expect(
        [for (final e in items) e.articulations],
        [
          {Articulation.staccato},
          {Articulation.fermata},
          <Articulation>{},
        ],
      );
      expect((items.last as RestEvent).hidden, isTrue);
    });

    test('mints ids again on every paste', () {
      final session = sessionWith([
        triplet(),
        [rest(7, NoteValue.whole)],
        [rest(8, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (1, Moment.zero));

      final once = pasted(session, clip, 1, Moment.zero);
      final twice = pasted(once, clip, 2, Moment.zero);

      final ids = [for (var i = 0; i < 3; i++) idsIn(twice.score, i)];
      expect(bar(twice.score, 2), bar(session.score, 0));
      expect(ids[1].intersection(ids[0]), isEmpty);
      expect(ids[2].intersection(ids[1]), isEmpty);
      expect(ids[2].intersection(ids[0]), isEmpty);
    });

    test('dissolves barlines and splits at the barlines it meets', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half),
          chordOf(2, 'G4', value: NoteValue.half),
        ],
        [
          chordOf(3, 'A4', value: NoteValue.half),
          chordOf(4, 'C5', value: NoteValue.half),
        ],
        [rest(5, NoteValue.whole)],
        [rest(6, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, at(1, 2)), (1, at(1, 2)));

      final next = pasted(session, clip, 2, at(1, 4));

      expect(bar(next.score, 2), ['rest/quarter', 'G4/half', 'A4/quarter~']);
      expect(bar(next.score, 3), ['A4/quarter', 'rest/quarter', 'rest/half']);
    });

    test('appends bars when it runs past the end of the score', () {
      final session = sessionWith([
        [chordOf(1, 'F4', value: NoteValue.whole)],
        [rest(2, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (1, Moment.zero));

      final next = pasted(session, clip, 1, at(1, 2));

      expect(next.score.measures, hasLength(3));
      expect(bar(next.score, 1), ['rest/half', 'F4/half~']);
      expect(bar(next.score, 2), ['F4/half', 'rest/half']);

      final both = copyOf(session, (0, Moment.zero), (1, at(1, 1)));
      final longer = pasted(session, both, 1, at(1, 2));

      expect(longer.score.measures, hasLength(4));
      expect(bar(longer.score, 3), ['rest/half', 'rest/half']);
    });

    test('ends exactly at the end of the score without a new bar', () {
      final session = sessionWith([
        [chordOf(1, 'F4', value: NoteValue.whole)],
        [rest(2, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (1, Moment.zero));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(next.score.measures, hasLength(2));
      expect(bar(next.score, 1), ['F4/whole']);
    });

    test('keeps ties inside the clip and drops one that leads out', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half, tie: true),
          chordOf(2, 'F4', value: NoteValue.half, tie: true),
        ],
        [
          chordOf(3, 'F4', value: NoteValue.half),
          rest(4, NoteValue.half),
        ],
        [rest(5, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (1, Moment.zero));

      final next = pasted(session, clip, 2, Moment.zero);

      expect(bar(next.score, 2), ['F4/half~', 'F4/half']);
    });

    test('keeps a let-ring tie', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half, tie: true),
          chordOf(2, 'G4', value: NoteValue.half),
        ],
        [rest(3, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (0, at(1, 2)));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(bar(next.score, 1), ['F4/half~', 'rest/half']);
    });

    test('drops a let-ring tie that would land on a head', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half, tie: true),
          chordOf(2, 'G4', value: NoteValue.half),
        ],
        [
          chordOf(3, 'C5', tie: true),
          chordOf(4, 'C5'),
          rest(5, NoteValue.half),
        ],
        [chordOf(6, 'F4', value: NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (0, at(1, 2)));

      final next = pasted(session, clip, 1, at(1, 2));

      expect(bar(next.score, 1), ['C5/quarter~', 'C5/quarter', 'F4/half']);
    });

    test('clears a tie into the music it writes', () {
      final session = sessionWith([
        [
          rest(1, NoteValue.half),
          chordOf(2, 'F4', value: NoteValue.half, tie: true),
        ],
        [chordOf(3, 'F4', value: NoteValue.whole)],
        [chordOf(4, 'F4'), rest(5, NoteValue.quarter), rest(6, NoteValue.half)],
      ]);
      final clip = copyOf(session, (2, Moment.zero), (2, at(1, 4)));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(tiesOf(next, 2), {'F4': false});
      expect(bar(next.score, 1), ['F4/quarter', 'rest/quarter', 'rest/half']);
    });

    test('replaces every voice of the staff for its length', () {
      var score = fill(blankScore(), 0, [
        chordOf(1, 'F4'),
        chordOf(2, 'G4'),
        rest(3, NoteValue.half),
      ]);
      score = fill(score, 1, [chordOf(4, 'A4', value: NoteValue.whole)]);
      score = fill(score, 1, [
        chordOf(5, 'C5'),
        chordOf(6, 'C5'),
        chordOf(7, 'C5', value: NoteValue.half),
      ], slot: VoiceSlot.two);
      final session = EditSession.start(score);
      final clip = copyOf(session, (0, Moment.zero), (0, at(1, 2)));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(bar(next.score, 1), ['F4/quarter', 'G4/quarter', 'rest/half']);
      expect(bar(next.score, 1, slot: VoiceSlot.two), ['gap 1/2', 'C5/half']);
    });

    test('writes a second voice with its gaps', () {
      var score = fill(blankScore(), 0, [
        Gap(len(1, 4)),
        chordOf(1, 'C5'),
        Gap(len(1, 4)),
        chordOf(3, 'D5'),
      ], slot: VoiceSlot.two);
      score = fill(score, 1, [
        chordOf(2, 'F4', value: NoteValue.whole),
      ], slot: VoiceSlot.two);
      final session = EditSession.start(score);
      final clip = copyOf(session, (0, Moment.zero), (1, Moment.zero));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(bar(next.score, 1, slot: VoiceSlot.two), [
        'gap 1/4',
        'C5/quarter',
        'gap 1/4',
        'D5/quarter',
      ]);
    });

    test('takes a tuplet wholly inside the range and none that it cuts', () {
      for (final (to, expected) in [
        (
          at(3, 4),
          [
            'C5/quarter',
            '3:2[F4/quarter, G4/quarter, A4/quarter]',
            'rest/quarter',
          ],
        ),
        (at(1, 2), ['C5/quarter', 'rest/quarter', 'rest/half']),
      ]) {
        final session = sessionWith([
          triplet(),
          [rest(7, NoteValue.whole)],
        ]);
        final clip = copyOf(session, (0, Moment.zero), (0, to));

        final next = pasted(session, clip, 1, Moment.zero);

        expect(bar(next.score, 1), expected);
      }
    });

    test('pastes an empty bar as a measure rest', () {
      final session = sessionWith([
        [rest(1, NoteValue.whole)],
        [chordOf(2, 'F4'), chordOf(3, 'G4'), rest(4, NoteValue.half)],
      ]);
      final empty = EditSession.start(blankScore(bars: 1));
      final clip = copyOf(empty, (0, Moment.zero), (0, at(1, 1)));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(bar(next.score, 1), ['measure-rest']);
    });

    test('carries the directions and spanners inside the range', () {
      Score withMarks(Score score, int bar, List<StaffDirection> marks) =>
          changeBar(
            score,
            bar,
            (column) => column.withStaff(
              column.staves.first.copyWith(directions: Seq(marks)),
            ),
          );
      var score = withMarks(blankScore(), 0, [
        const DynamicMark(Moment.zero, Dynamic.p),
        DynamicMark(at(1, 2), Dynamic.f),
      ]);
      score = withMarks(score, 1, [
        TextMark(at(1, 4), 'dolce'),
        TextMark(at(3, 4), 'rit.'),
      ]);
      score = fill(score, 0, [
        for (var i = 0; i < 4; i++) chordOf(100 + i, 'C5'),
      ]);
      for (final (first, last) in [
        ((0, Moment.zero), (0, at(1, 2))),
        ((0, at(1, 4)), (0, at(1, 2))),
        ((0, at(1, 2)), (1, Moment.zero)),
      ]) {
        score = withSlur(
          score,
          pointAt(score, first.$1, first.$2),
          pointAt(score, last.$1, last.$2),
          voice: VoiceSlot.one,
        );
      }
      final session = EditSession.start(score);
      final clip = copyOf(session, (0, at(1, 4)), (0, at(3, 4)));

      final next = pasted(session, clip, 1, Moment.zero);

      expect(
        [
          for (final d in next.score.measures[1].staves.first.directions)
            mark(d),
        ],
        ['1/4 f', '3/4 rit.'],
      );
      final added = next.score.spanners.last;
      expect(next.score.spanners, hasLength(4));
      expect(added.id, isNot(const SpannerId(900)));
      expect(added.kind, isA<Slur>());
      expect(added.voice, VoiceSlot.one);
      expect(added.first, pointAt(score, 1, Moment.zero));
      expect(added.last, pointAt(score, 1, at(1, 4)));
    });

    test('puts the clip on the staves from the one it is pasted at', () {
      var score = fill(blankScore(parts: const [piano]), 0, [
        chordOf(1, 'C5', value: NoteValue.half),
        chordOf(2, 'D5', value: NoteValue.half),
      ]);
      score = fill(score, 0, [
        chordOf(3, 'C3', value: NoteValue.half),
        chordOf(4, 'D3', value: NoteValue.half),
      ], staff: 1);
      score = changeBar(
        score,
        0,
        (column) => column.withStaff(
          column.staves[1].copyWith(
            directions: Seq([const DynamicMark(Moment.zero, Dynamic.p)]),
          ),
        ),
      );
      score = withSlur(
        score,
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(1, 2)),
        staff: 1,
      );
      final session = EditSession.start(score);
      final clip = session
          .select(
            range(score, (0, Moment.zero), (1, Moment.zero), bottom: 1),
          )
          .copy()!;
      final upper = copyOf(session, (0, Moment.zero), (1, Moment.zero));

      final next = applied(paste(session, clip, 1, Moment.zero, staff: 1));
      final alone = pasted(session, upper, 1, Moment.zero);

      List<String> staff(int index) => describe(
        next.score.measures[1].staves[index].voice(VoiceSlot.one)!.items,
      );
      expect(staff(0), ['measure-rest']);
      expect(staff(1), ['C5/half', 'D5/half']);
      expect(
        [
          for (final s in next.score.measures[1].staves) s.directions.length,
        ],
        [0, 0],
      );
      expect(next.score.spanners, hasLength(1));
      expect(alone.score.spanners, hasLength(1));
    });

    test('selects what it pasted and keeps the cursor', () {
      final session = sessionWith([
        [chordOf(1, 'F4'), chordOf(2, 'G4'), rest(3, NoteValue.half)],
        [rest(4, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (0, at(1, 2)));

      final next = pasted(session, clip, 1, at(1, 4));

      final selection = next.selection as RangeSelection;
      expect(selection.from, pointAt(session.score, 1, at(1, 4)));
      expect(selection.to, pointAt(session.score, 1, at(3, 4)));
      expect(selection.top, session.score.staves.first.id);
      expect(selection.bottom, session.score.staves.first.id);
      expect(next.cursor, session.cursor);
    });

    test('restores what a cut erased', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4'),
          chordOf(2, 'G4', value: NoteValue.half),
          chordOf(3, 'A4'),
        ],
        [chordOf(4, 'C5', value: NoteValue.whole)],
      ]);
      final selection = range(session.score, (0, at(1, 4)), (1, Moment.zero));
      final clip = session.select(selection).copy()!;
      final cut = applied(session.run(Erase(selection)));

      final next = pasted(cut, clip, 0, at(1, 4));

      expect(bar(cut.score, 0), ['F4/quarter', 'rest/half', 'rest/quarter']);
      expect(bar(next.score, 0), bar(session.score, 0));
      expect(
        (next.selection as RangeSelection).to,
        pointAt(next.score, 1, Moment.zero),
      );
    });

    test('pastes into another score', () {
      final source = sessionWith([
        [chordOf(1, 'F4'), chordOf(2, 'G4'), rest(3, NoteValue.half)],
      ]);
      final clip = copyOf(source, (0, Moment.zero), (0, at(1, 1)));
      final target = blank(meter: Meter.threeFour);

      final next = pasted(target, clip, 0, Moment.zero);

      expect(bar(next.score, 0), ['F4/quarter', 'G4/quarter', 'rest/quarter']);
      expect(bar(next.score, 1), [
        'rest/quarter',
        'rest/quarter',
        'rest/quarter',
      ]);
    });

    test('keeps a string only where the instrument has it', () {
      final session = EditSession.start(
        fill(blankScore(parts: const [morinKhuur, clarinet]), 0, [
          ChordEvent(
            id: const EventId(1),
            value: NoteValue.whole,
            notes: Seq([
              PitchedNote(id: const NoteId(10), pitch: f4, string: 0),
            ]),
          ),
        ]),
      );
      final clip = copyOf(session, (0, Moment.zero), (0, at(1, 1)));
      int? stringAt(int staff) {
        final next = applied(
          paste(session, clip, 1, Moment.zero, staff: staff),
        );
        final chord =
            next.score.measures[1].staves[staff].voices.first.items.first
                as ChordEvent;
        return (chord.notes.single as PitchedNote).string;
      }

      expect(stringAt(0), 0);
      expect(stringAt(1), isNull);
    });

    test('refuses to cross a barline when told to', () {
      final session = sessionWith([
        [chordOf(1, 'F4', value: NoteValue.half), rest(2, NoteValue.half)],
        [rest(3, NoteValue.whole)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (0, at(1, 2)));

      final outcome = paste(
        session,
        clip,
        0,
        at(3, 4),
        overfill: Overfill.refuse,
      );

      expect(refusal(outcome), isA<WouldCrossBarline>());
    });

    test('refuses a point that is gone or outside its bar', () {
      final session = sessionWith([
        [chordOf(1, 'F4'), chordOf(2, 'G4'), rest(3, NoteValue.half)],
      ]);
      final clip = copyOf(session, (0, Moment.zero), (0, at(1, 2)));

      final gone = session.run(
        Paste(
          clip,
          at: VoicePoint(
            staff: const StaffId(999),
            voice: VoiceSlot.one,
            at: pointAt(session.score, 0, Moment.zero),
          ),
        ),
      );

      final stale = session.run(
        Paste(
          clip,
          at: VoicePoint(
            staff: session.score.staves.first.id,
            voice: VoiceSlot.one,
            at: const ScorePoint(MeasureId(999), Moment.zero),
          ),
        ),
      );

      expect(refusal(gone), isA<StaleReference>());
      expect(refusal(stale), isA<StaleReference>());
      expect(
        refusal(paste(session, clip, 0, at(5, 4))),
        isA<OutsideMeasure>(),
      );
    });
  });
}
