import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

MeasureView viewOf(Score score, int bar) =>
    score.measureView(score.measures[bar].id);

StaffView staffOf(Score score, int bar, {int staff = 0}) =>
    viewOf(score, bar).staves[staff];

VoiceView voiceView(Score score, int bar) => staffOf(
  score,
  bar,
).voices.firstWhere((voice) => voice.slot == VoiceSlot.one);

List<ChordEvent> run(
  int firstId,
  int count,
  NoteValue value, {
  Map<int, BeamMode> beams = const {},
}) => [
  for (var id = firstId; id < firstId + count; id++)
    chordOf(id, 'G4', value: value, beam: beams[id] ?? BeamMode.auto),
];

MeasureColumn retimed(MeasureColumn column, Meter meter) => MeasureColumn(
  id: column.id,
  meter: meter,
  key: column.key,
  staves: Seq([
    for (final staff in column.staves)
      StaffMeasure(
        staff: staff.staff,
        clef: staff.clef,
        voices: Seq([
          Voice(
            slot: VoiceSlot.one,
            items: Seq([
              MeasureRest(
                id: (staff.voices.first.items.first as Event).id,
                span: meter.length,
              ),
            ]),
          ),
        ]),
      ),
  ]),
);

/// Each head as printed, in voice then time order, graces first: written
/// pitch, then the accidental sign (`n` natural, parentheses cautionary).
List<String> printed(StaffView staff) => [
  for (final voice in staff.voices)
    for (final timed in voice.events)
      if (timed.event case ChordEvent(:final graces, :final notes))
        for (final note in [
          for (final grace in graces) ...grace.notes,
          ...notes,
        ])
          _head(staff, note),
];

String _head(StaffView staff, Note note) {
  final pitch = staff.writtenPitches[note.id];
  final mark = staff.accidentals[note.id];
  if (mark == null) {
    return '$pitch';
  }
  final sign = switch (mark.alter.quarterTones) {
    -4 => 'bb',
    -3 => 'db',
    -2 => 'b',
    -1 => 'd',
    0 => 'n',
    1 => '+',
    2 => '#',
    3 => '#+',
    _ => 'x',
  };
  return '$pitch ${mark.cautionary ? '($sign)' : sign}';
}

List<String> tiesOf(StaffView staff) => [
  for (final TieView(:from, :to, :crossesBarline) in staff.ties)
    [
      '${from.value} -> ${to?.note.value ?? 'none'}',
      if (crossesBarline) 'across',
    ].join(' '),
];

List<List<int>> beamsOf(Score score) => [
  for (final group in voiceView(score, 0).beams)
    [for (final event in group.events) event.value],
];

/// Each beam group of the first bar, with one entry per event that names
/// its join at every beam level, level 1 first.
List<List<String>> joinsOf(Score score) => [
  for (final group in voiceView(score, 0).beams)
    [
      for (final joins in group.joins)
        [for (final join in joins) join.name].join(' '),
    ],
];

Tuplet tripletOfSixteenths(int id, List<Content> members) => Tuplet(
  id: TupletId(id),
  ratio: TupletRatio.triplet,
  unit: NoteValue.sixteenth,
  members: Seq(members),
);

List<String> segmentsIn(Score score, int bar) => [
  for (final SpannerSegment(:from, :to, :startsHere, :endsHere) in viewOf(
    score,
    bar,
  ).spanners)
    [
      '${from.wholeNotes}-${to.wholeNotes}',
      if (startsHere) 'starts',
      if (endsHere) 'ends',
    ].join(' '),
];

void main() {
  group('Meter.beamBreaks', () {
    test('breaks a long even simple bar at the half', () {
      expect(Meter.fourFour.beamBreaks, [Moment.zero, at(1, 2)]);
      expect(Meter.cut.beamBreaks, [Moment.zero, at(1, 2)]);
    });

    test('beams a short simple bar whole', () {
      for (final meter in [
        Meter.threeFour,
        Meter.twoFour,
        Meter.simple(3, 8),
      ]) {
        expect(meter.beamBreaks, [Moment.zero], reason: '$meter');
      }
    });

    test('breaks a compound bar per dotted beat', () {
      expect(Meter.sixEight.beamBreaks, [Moment.zero, at(3, 8)]);
      expect(Meter.simple(12, 8).beamBreaks, [
        Moment.zero,
        at(3, 8),
        at(3, 4),
        at(9, 8),
      ]);
    });

    test('breaks an additive bar per group', () {
      expect(const Meter([3, 2, 2], 8).beamBreaks, [
        Moment.zero,
        at(3, 8),
        at(5, 8),
      ]);
    });

    test('breaks an odd simple bar per beat', () {
      expect(Meter.simple(5, 4).beamBreaks, [
        Moment.zero,
        at(1, 4),
        at(1, 2),
        at(3, 4),
        at(1, 1),
      ]);
    });
  });

  group('MeasureView bar facts', () {
    test('carries the bar and its position', () {
      final score = blankScore(bars: 3);
      final view = viewOf(score, 2);

      expect(view.index, 2);
      expect(view.column, same(score.measures[2]));
    });

    test('prints meter and key at the first bar and where they change', () {
      var score = blankScore(bars: 5);
      score = changeBar(score, 2, (c) => retimed(c, Meter.threeFour));
      score = changeBar(
        score,
        3,
        (c) => retimed(
          c,
          Meter.threeFour,
        ).copyWith(key: const KeySignature(-1)),
      );
      score = changeBar(
        score,
        4,
        (c) => retimed(
          c,
          Meter.threeFour,
        ).copyWith(key: const KeySignature(-1, KeyMode.minor)),
      );
      final views = [for (var i = 0; i < 5; i++) viewOf(score, i)];

      expect(
        [for (final view in views) view.meterChanged],
        [true, false, true, false, false],
      );
      expect(
        [for (final view in views) view.keyChanged],
        [true, false, false, true, false],
      );
      expect(
        [for (final view in views) view.previousKey],
        [
          null,
          KeySignature.cMajor,
          KeySignature.cMajor,
          KeySignature.cMajor,
          const KeySignature(-1),
        ],
      );
    });

    test('opens and closes volta brackets', () {
      var score = blankScore(bars: 5);
      for (final bar in [1, 2]) {
        score = changeBar(
          score,
          bar,
          (c) => c.copyWith(volta: () => const Volta([1])),
        );
      }
      score = changeBar(
        score,
        4,
        (c) => c.copyWith(volta: () => const Volta([2], open: true)),
      );
      final views = [for (var i = 0; i < 5; i++) viewOf(score, i)];

      expect(
        [for (final view in views) view.voltaStarts],
        [false, true, false, false, true],
      );
      expect(
        [for (final view in views) view.voltaEnds],
        [false, false, true, false, true],
      );
    });
  });

  group('MeasureView staves', () {
    test('lists visible staves in system order', () {
      final score = hidePart(
        blankScore(parts: const [piano, clarinet, drums]),
        1,
      );
      final staves = viewOf(score, 0).staves;

      expect(
        [for (final staff in staves) staff.source.staff],
        [
          score.staves[0].id,
          score.staves[1].id,
          score.staves[3].id,
        ],
      );
      expect(
        [for (final staff in staves) staff.part.name],
        [
          'Piano',
          'Piano',
          'Drums',
        ],
      );
      expect(staves[1].clef, Clef.bass);
    });

    test('prints a clef where it differs from the one in effect before', () {
      var score = blankScore(bars: 4);
      score = changeBar(
        score,
        0,
        (c) => c.withStaff(
          c.staves.first.copyWith(
            clefChanges: Seq([ClefChange(at(1, 2), Clef.bass)]),
          ),
        ),
      );
      score = changeBar(
        score,
        1,
        (c) => c.withStaff(c.staves.first.copyWith(clef: Clef.bass)),
      );

      expect(
        [for (var i = 0; i < 4; i++) staffOf(score, i).clefChanged],
        [true, false, true, false],
      );
    });

    test('reads the key as each part does', () {
      final score = blankScore(
        parts: const [clarinet, drums],
        key: const KeySignature(-1),
      );
      final staves = viewOf(score, 0).staves;

      expect(staves[0].writtenKey, const KeySignature(1));
      expect(staves[1].writtenKey, const KeySignature(0));
      expect(
        score
            .contextAt(score.staves[1].id, pointAt(score, 0, Moment.zero))
            .writtenKey,
        const KeySignature(0),
      );
    });

    test('prints a transposing part at written pitch', () {
      final score = fill(blankScore(parts: const [clarinet]), 0, [
        chordOf(100, 'F4', value: NoteValue.whole),
      ]);

      expect(staffOf(score, 0).writtenPitches[const NoteId(1000)], g4);
    });

    test('prints notes under an 8va line an octave lower', () {
      var score = blankScore();
      score = fill(score, 0, [
        for (var i = 0; i < 4; i++) chordOf(100 + i, 'E5'),
      ]);
      score = fill(score, 1, [
        for (var i = 0; i < 4; i++) chordOf(110 + i, 'E5'),
      ]);
      score = withOctaveLine(
        score,
        OctaveShift.up8,
        pointAt(score, 0, at(1, 2)),
        pointAt(score, 1, at(1, 4)),
      );

      expect(printed(staffOf(score, 0)), ['E5', 'E5', 'E4', 'E4']);
      expect(printed(staffOf(score, 1)), ['E4', 'E4', 'E5', 'E5']);
    });

    test('leaves other staves alone under an 8va line', () {
      var score = blankScore(parts: const [piano]);
      score = fill(score, 0, [
        chordOf(100, 'E3', value: NoteValue.whole),
      ], staff: 1);
      score = withOctaveLine(
        score,
        OctaveShift.up8,
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(3, 4)),
      );

      expect(printed(staffOf(score, 0, staff: 1)), ['E3']);
    });

    test('prints each drum at its kit position and head, with no key', () {
      final score = fill(
        blankScore(parts: const [drums], key: const KeySignature(2)),
        0,
        [
          hit(100, [bassDrum, sideStick], value: NoteValue.half),
          hit(101, [snare], value: NoteValue.half),
        ],
      );
      final staff = staffOf(score, 0);
      final heads = [
        for (final voice in staff.voices)
          for (final timed in voice.events)
            for (final note in (timed.event as ChordEvent).notes)
              staff.headOf(note),
      ];

      expect(printed(staff), ['F4', 'C5', 'C5']);
      expect(heads, [NoteHead.normal, NoteHead.cross, NoteHead.normal]);
      expect(staff.writtenKey, const KeySignature(0));
      expect(staff.accidentals, isEmpty);
    });
  });

  group('MeasureView voices', () {
    test('places each event in time', () {
      final score = fill(blankScore(), 0, [
        chordOf(100, 'F4'),
        rest(101, NoteValue.quarter),
        chordOf(102, 'G4', value: NoteValue.half),
      ]);
      final events = voiceView(score, 0).events;

      expect([for (final e in events) e.event.id.value], [100, 101, 102]);
      expect(
        [for (final e in events) e.onset],
        [
          Moment.zero,
          at(1, 4),
          at(1, 2),
        ],
      );
      expect(events.last.ref.measure, score.measures[0].id);
    });

    test('skips the gaps of a secondary voice', () {
      final score = fill(
        blankScore(),
        0,
        [Gap(len(1, 2)), chordOf(100, 'C5', value: NoteValue.half)],
        slot: VoiceSlot.two,
      );
      final voices = staffOf(score, 0).voices;

      expect(
        [for (final voice in voices) voice.slot],
        [
          VoiceSlot.one,
          VoiceSlot.two,
        ],
      );
      expect(
        [for (final e in voices[1].events) (e.event.id.value, e.onset)],
        [(100, at(1, 2))],
      );
    });

    test('names the event that opens the voice in the next bar, and none '
        'when that bar opens it with a gap or there is no next bar', () {
      var score = blankScore(bars: 3);
      score = fill(score, 1, [chordOf(110, 'F4', value: NoteValue.whole)]);
      score = fill(score, 0, [
        chordOf(100, 'C5', value: NoteValue.whole),
      ], slot: VoiceSlot.two);
      score = fill(score, 1, [
        Gap(len(1, 2)),
        chordOf(111, 'C5', value: NoteValue.half),
      ], slot: VoiceSlot.two);
      final voices = staffOf(score, 0).voices;

      expect(voices[0].nextOpening?.event.id, const EventId(110));
      expect(voices[0].nextOpening?.onset, Moment.zero);
      expect(voices[1].nextOpening, isNull);
      expect(voiceView(score, 2).nextOpening, isNull);
    });

    test('flattens nested tuplets outermost first', () {
      final inner = tripletOfEighths(2, [
        for (var id = 101; id <= 103; id++)
          chordOf(id, 'G4', value: NoteValue.eighth),
      ]);
      final outer = Tuplet(
        id: const TupletId(1),
        ratio: TupletRatio.triplet,
        unit: NoteValue.quarter,
        members: Seq([chordOf(100, 'G4'), inner, chordOf(104, 'G4')]),
      );
      final score = fill(blankScore(), 0, [outer, rest(105, NoteValue.half)]);
      final tuplets = voiceView(score, 0).tuplets;

      expect(
        [
          for (final t in tuplets)
            (t.tuplet.id.value, t.onset, t.duration, t.depth),
        ],
        [(1, Moment.zero, len(1, 2), 0), (2, at(1, 6), len(1, 6), 1)],
      );
      expect(
        [
          for (final t in tuplets) [for (final e in t.events) e.value],
        ],
        [
          [100, 101, 102, 103, 104],
          [101, 102, 103],
        ],
      );
    });
  });

  group('MeasureView ties', () {
    test('joins a tied note to the same pitch in the next event', () {
      final score = fill(blankScore(), 0, [
        chordOf(100, 'F4', tie: true),
        chordOf(101, 'F4'),
        rest(102, NoteValue.half),
      ]);
      final staff = staffOf(score, 0);

      expect(tiesOf(staff), ['1000 -> 1010']);
      expect(staff.ties.single.to!.event.measure, score.measures[0].id);
    });

    test('carries a tie across the barline', () {
      var score = blankScore();
      score = fill(score, 0, [
        rest(100, NoteValue.half),
        rest(101, NoteValue.quarter),
        chordOf(102, 'F4 A4', tie: true),
      ]);
      score = fill(score, 1, [
        chordOf(110, 'F4'),
        rest(111, NoteValue.quarter),
        rest(112, NoteValue.half),
      ]);

      expect(tiesOf(staffOf(score, 0)), [
        '1020 -> 1100 across',
        '1021 -> none',
      ]);
      expect(
        staffOf(score, 0).ties.first.to!.event.measure,
        score.measures[1].id,
      );
      expect(staffOf(score, 1).tiedIn, [const NoteId(1100)]);
      expect(staffOf(score, 0).tiedIn, isEmpty);
    });

    test('carries a tie from the last note of a tuplet that ends the bar', () {
      var score = blankScore();
      score = fill(score, 0, [
        rest(100, NoteValue.half),
        rest(101, NoteValue.quarter),
        tripletOfEighths(1, [
          chordOf(102, 'G4', value: NoteValue.eighth),
          chordOf(103, 'G4', value: NoteValue.eighth),
          chordOf(104, 'F4', value: NoteValue.eighth, tie: true),
        ]),
      ]);
      score = fill(score, 1, [
        chordOf(110, 'F4'),
        rest(111, NoteValue.quarter),
        rest(112, NoteValue.half),
      ]);

      expect(tiesOf(staffOf(score, 0)), ['1040 -> 1100 across']);
      expect(staffOf(score, 1).tiedIn, [const NoteId(1100)]);
    });

    test('lets a tie ring when no matching note follows', () {
      final score = fill(blankScore(bars: 1), 0, [
        chordOf(100, 'F4', value: NoteValue.half, tie: true),
        chordOf(101, 'G4'),
        chordOf(102, 'A4', tie: true),
      ]);

      expect(tiesOf(staffOf(score, 0)), ['1000 -> none', '1020 -> none']);
    });

    test('does not tie across a gap', () {
      var score = blankScore(bars: 3);
      for (final (bar, items) in [
        [
          chordOf(100, 'F4', tie: true),
          Gap(len(1, 4)),
          chordOf(101, 'F4', tie: true),
          Gap(len(1, 4)),
        ],
        [chordOf(110, 'F4'), Gap(len(1, 2)), chordOf(111, 'F4', tie: true)],
        [Gap(len(1, 4)), chordOf(120, 'F4'), Gap(len(1, 2))],
      ].indexed) {
        score = fill(score, bar, items, slot: VoiceSlot.two);
      }

      expect(tiesOf(staffOf(score, 0)), ['1000 -> none', '1010 -> none']);
      expect(staffOf(score, 1).tiedIn, isEmpty);
      expect(tiesOf(staffOf(score, 1)), ['1110 -> none']);
      expect(staffOf(score, 2).tiedIn, isEmpty);
    });
  });

  group('MeasureView accidentals', () {
    test('follow the key signature', () {
      final score = fill(blankScore(key: const KeySignature(2)), 0, [
        chordOf(100, 'F#4'),
        chordOf(101, 'F4'),
        chordOf(102, 'C#5'),
        chordOf(103, 'Bb4'),
      ]);

      expect(printed(staffOf(score, 0)), ['F#4', 'F4 n', 'C#5', 'Bb4 b']);
    });

    test('hold to the end of the bar', () {
      final score = fill(blankScore(), 0, [
        chordOf(100, 'F#4'),
        chordOf(101, 'F#4'),
        chordOf(102, 'F4'),
        chordOf(103, 'F4'),
      ]);

      expect(printed(staffOf(score, 0)), ['F#4 #', 'F#4', 'F4 n', 'F4']);
    });

    test('hold at their own octave only', () {
      final score = fill(blankScore(), 0, [
        chordOf(100, 'F#4'),
        chordOf(101, 'F#5'),
        chordOf(102, 'F5'),
        chordOf(103, 'F4'),
      ]);

      expect(printed(staffOf(score, 0)), ['F#4 #', 'F#5 #', 'F5 n', 'F4 n']);
    });

    test('reset at the barline', () {
      var score = blankScore();
      for (final bar in [0, 1]) {
        score = fill(score, bar, [
          chordOf(100 + bar, 'F#4', value: NoteValue.whole),
        ]);
      }

      expect(printed(staffOf(score, 1)), ['F#4 #']);
    });

    test('carry across the voices of a staff', () {
      var score = fill(blankScore(), 0, [
        chordOf(100, 'F#4', value: NoteValue.half),
        chordOf(101, 'F#4', value: NoteValue.half),
      ]);
      score = fill(
        score,
        0,
        [Gap(len(1, 4)), chordOf(110, 'F4'), Gap(len(1, 2))],
        slot: VoiceSlot.two,
      );

      expect(printed(staffOf(score, 0)), ['F#4 #', 'F#4 #', 'F4 n']);
    });

    test('are not repeated on a tied-in note, but are on the next', () {
      var score = blankScore();
      score = fill(score, 0, [
        rest(100, NoteValue.half),
        rest(101, NoteValue.quarter),
        chordOf(102, 'F#4', tie: true),
      ]);
      score = fill(score, 1, [
        chordOf(110, 'F#4'),
        chordOf(111, 'F#4'),
        rest(112, NoteValue.half),
      ]);

      expect(printed(staffOf(score, 1)), ['F#4', 'F#4 #']);
    });

    test('follow the request on the note', () {
      final score = fill(blankScore(), 0, [
        chordOf(100, 'F4', accidental: AccidentalRequest.always),
        chordOf(101, 'F4', accidental: AccidentalRequest.cautionary),
        chordOf(102, 'F#4', accidental: AccidentalRequest.never),
        chordOf(103, 'F#4'),
      ]);

      expect(printed(staffOf(score, 0)), ['F4 n', 'F4 (n)', 'F#4', 'F#4 #']);
    });

    test('are worked out at written pitch', () {
      final score = fill(blankScore(parts: const [clarinet]), 0, [
        chordOf(100, 'Eb4'),
        chordOf(101, 'Ab4'),
        chordOf(102, 'B4'),
        chordOf(103, 'G4'),
      ]);

      expect(printed(staffOf(score, 0)), ['F4 n', 'Bb4 b', 'C#5', 'A4']);
    });

    test('respell a written pitch past a double accidental', () {
      final score = fill(blankScore(parts: const [clarinet]), 0, [
        chordOf(100, 'Ex4'),
        chordOf(101, 'Ex4'),
        chordOf(102, 'Fx4'),
        chordOf(103, 'Bx4'),
      ]);

      expect(printed(staffOf(score, 0)), ['G#4 #', 'G#4', 'Gx4 x', 'D#5 #']);
    });

    test('respell past a double accidental in the written key', () {
      final score = fill(
        blankScore(parts: const [clarinet], key: const KeySignature(-4)),
        0,
        [chordOf(100, 'Ex4', value: NoteValue.whole)],
      );

      expect(printed(staffOf(score, 0)), ['Ab4 b']);
    });

    test('cover quarter tones', () {
      final score = fill(blankScore(), 0, [
        chordOf(100, 'F+4'),
        chordOf(101, 'F+4'),
        chordOf(102, 'F4'),
        chordOf(103, 'Fd4'),
      ]);

      expect(printed(staffOf(score, 0)), ['F+4 +', 'F+4', 'F4 n', 'Fd4 d']);
    });

    test('count grace notes before their chord', () {
      final grace = GraceChord(
        id: const EventId(99),
        kind: GraceKind.acciaccatura,
        value: NoteValue.eighth,
        notes: Seq([
          PitchedNote(id: const NoteId(990), pitch: Pitch.parse('F#4')),
        ]),
      );
      final score = fill(blankScore(), 0, [
        chordOf(100, 'F4', graces: [grace]),
        chordOf(101, 'F4', value: NoteValue.half.dotted),
      ]);

      expect(printed(staffOf(score, 0)), ['F#4 #', 'F4 n', 'F4']);
    });

    test('count a grace note before a chord in another voice', () {
      final grace = GraceChord(
        id: const EventId(99),
        kind: GraceKind.acciaccatura,
        value: NoteValue.eighth,
        notes: Seq([
          PitchedNote(id: const NoteId(990), pitch: Pitch.parse('F#4')),
        ]),
      );
      var score = fill(blankScore(), 0, [
        chordOf(100, 'F4', value: NoteValue.whole),
      ]);
      score = fill(score, 0, [
        chordOf(110, 'C5', value: NoteValue.whole, graces: [grace]),
      ], slot: VoiceSlot.two);

      expect(printed(staffOf(score, 0)), ['F4 n', 'F#4 #', 'C5']);
    });
  });

  group('MeasureView beams', () {
    test('break 4/4 eighths at the half bar', () {
      final score = fill(blankScore(), 0, run(100, 8, NoteValue.eighth));

      expect(beamsOf(score), [
        [100, 101, 102, 103],
        [104, 105, 106, 107],
      ]);
    });

    test('join a whole bar of 3/4 eighths', () {
      final score = fill(
        blankScore(meter: Meter.threeFour),
        0,
        run(100, 6, NoteValue.eighth),
      );

      expect(beamsOf(score), [
        [100, 101, 102, 103, 104, 105],
      ]);
    });

    test('group 6/8 eighths by dotted quarter', () {
      final score = fill(
        blankScore(meter: Meter.sixEight),
        0,
        run(100, 6, NoteValue.eighth),
      );

      expect(beamsOf(score), [
        [100, 101, 102],
        [103, 104, 105],
      ]);
    });

    test('group sixteenths by beat', () {
      final fourFour = fill(blankScore(), 0, [
        ...run(100, 2, NoteValue.eighth),
        ...run(102, 4, NoteValue.sixteenth),
        chordOf(106, 'G4', value: NoteValue.half),
      ]);
      final twoFour = fill(
        blankScore(meter: Meter.twoFour),
        0,
        run(100, 8, NoteValue.sixteenth),
      );

      expect(beamsOf(fourFour), [
        [100, 101],
        [102, 103, 104, 105],
      ]);
      expect(beamsOf(twoFour), [
        [100, 101, 102, 103],
        [104, 105, 106, 107],
      ]);
    });

    test('stop at notes a quarter or longer', () {
      final score = fill(blankScore(meter: Meter.threeFour), 0, [
        chordOf(100, 'G4', value: NoteValue.eighth),
        chordOf(101, 'G4'),
        ...run(102, 3, NoteValue.eighth),
      ]);

      expect(beamsOf(score), [
        [102, 103, 104],
      ]);
    });

    test('run over rests inside a beat only', () {
      final acrossBeats = fill(blankScore(), 0, [
        chordOf(100, 'G4', value: NoteValue.eighth),
        rest(101, NoteValue.eighth),
        ...run(102, 2, NoteValue.eighth),
        chordOf(104, 'G4', value: NoteValue.half),
      ]);
      final insideBeat = fill(blankScore(), 0, [
        chordOf(100, 'G4', value: NoteValue.sixteenth),
        rest(101, NoteValue.sixteenth),
        ...run(102, 2, NoteValue.sixteenth),
        ...run(104, 2, NoteValue.eighth),
        chordOf(106, 'G4', value: NoteValue.half),
      ]);

      expect(beamsOf(acrossBeats), [
        [102, 103],
      ]);
      expect(beamsOf(insideBeat), [
        [100, 102, 103],
        [104, 105],
      ]);
    });

    test('break at a tuplet', () {
      final score = fill(blankScore(meter: Meter.twoFour), 0, [
        ...run(100, 2, NoteValue.eighth),
        tripletOfEighths(1, run(102, 3, NoteValue.eighth)),
      ]);

      expect(beamsOf(score), [
        [100, 101],
        [102, 103, 104],
      ]);
    });

    test('follow the beam mode on the event', () {
      List<List<int>> beamed(int id, BeamMode mode) => beamsOf(
        fill(
          blankScore(),
          0,
          run(100, 8, NoteValue.eighth, beams: {id: mode}),
        ),
      );

      expect(beamed(101, BeamMode.none), [
        [102, 103],
        [104, 105, 106, 107],
      ]);
      expect(beamed(102, BeamMode.begin), [
        [100, 101],
        [102, 103],
        [104, 105, 106, 107],
      ]);
      expect(beamed(104, BeamMode.join), [
        [100, 101, 102, 103, 104, 105, 106, 107],
      ]);
    });

    test('join sixteenths across a beat, breaking the inner beams there', () {
      final score = fill(
        blankScore(meter: Meter.twoFour),
        0,
        run(100, 8, NoteValue.sixteenth, beams: {104: BeamMode.join}),
      );
      final group = voiceView(score, 0).beams.single;

      expect(group.events.length, 8);
      expect(group.secondaryBreaks, [4]);
    });

    test('break secondary beams at each 6/8 eighth', () {
      final score = fill(blankScore(meter: Meter.sixEight), 0, [
        ...run(100, 6, NoteValue.sixteenth),
        chordOf(106, 'G4', value: NoteValue.quarter.dotted),
      ]);
      final group = voiceView(score, 0).beams.single;

      expect(
        [for (final e in group.events) e.value],
        [
          100,
          101,
          102,
          103,
          104,
          105,
        ],
      );
      expect(group.secondaryBreaks, [2, 4]);
    });

    test('need no secondary break beside an eighth', () {
      final score = fill(blankScore(meter: Meter.sixEight), 0, [
        ...run(100, 2, NoteValue.sixteenth),
        chordOf(102, 'G4', value: NoteValue.eighth),
        ...run(103, 2, NoteValue.sixteenth),
        chordOf(105, 'G4', value: NoteValue.quarter.dotted),
      ]);
      final group = voiceView(score, 0).beams.single;

      expect(group.events.length, 5);
      expect(group.secondaryBreaks, isEmpty);
    });

    test('run one beam through plain eighths', () {
      final score = fill(blankScore(), 0, run(100, 8, NoteValue.eighth));

      expect(joinsOf(score), [
        ['begin', 'continued', 'continued', 'end'],
        ['begin', 'continued', 'continued', 'end'],
      ]);
    });

    test('end and begin the inner beams at a secondary break', () {
      final score = fill(
        blankScore(meter: Meter.twoFour),
        0,
        run(100, 8, NoteValue.sixteenth, beams: {104: BeamMode.join}),
      );

      expect(joinsOf(score), [
        [
          'begin begin',
          'continued continued',
          'continued continued',
          'continued end',
          'continued begin',
          'continued continued',
          'continued continued',
          'end end',
        ],
      ]);
    });

    test('hook a lone sixteenth toward the note it beams with', () {
      final dottedFirst = fill(blankScore(), 0, [
        chordOf(100, 'G4', value: NoteValue.eighth.dotted),
        chordOf(101, 'G4', value: NoteValue.sixteenth),
        chordOf(102, 'G4', value: NoteValue.half.dotted),
      ]);
      final dottedLast = fill(blankScore(), 0, [
        chordOf(100, 'G4', value: NoteValue.sixteenth),
        chordOf(101, 'G4', value: NoteValue.eighth.dotted),
        chordOf(102, 'G4', value: NoteValue.half.dotted),
      ]);

      expect(joinsOf(dottedFirst), [
        ['begin', 'end backwardHook'],
      ]);
      expect(joinsOf(dottedLast), [
        ['begin forwardHook', 'end'],
      ]);
    });

    test('hook forward after a secondary break and backward after an '
        'eighth', () {
      final score = fill(blankScore(meter: Meter.sixEight), 0, [
        ...run(100, 3, NoteValue.sixteenth),
        chordOf(103, 'G4', value: NoteValue.eighth),
        chordOf(104, 'G4', value: NoteValue.sixteenth),
        chordOf(105, 'G4', value: NoteValue.quarter.dotted),
      ]);

      expect(voiceView(score, 0).beams.single.secondaryBreaks, [2]);
      expect(joinsOf(score), [
        [
          'begin begin',
          'continued end',
          'continued forwardHook',
          'continued',
          'end backwardHook',
        ],
      ]);
    });

    test('hook back on the last event of a group, also after a secondary '
        'break', () {
      final score = fill(blankScore(meter: Meter.sixEight), 0, [
        ...run(100, 3, NoteValue.sixteenth),
        chordOf(103, 'G4'),
        chordOf(104, 'G4', value: NoteValue.eighth.dotted),
        chordOf(105, 'G4', value: NoteValue.eighth),
      ]);

      expect(voiceView(score, 0).beams.first.secondaryBreaks, [2]);
      expect(joinsOf(score).first, [
        'begin begin',
        'continued end',
        'end backwardHook',
      ]);
    });

    test('give an event a join for each beam of its value', () {
      final score = fill(blankScore(), 0, [
        chordOf(100, 'G4', value: NoteValue.eighth),
        chordOf(101, 'G4', value: NoteValue.sixteenth),
        ...run(102, 2, NoteValue.thirtySecond),
        chordOf(104, 'G4', value: NoteValue.half.dotted),
      ]);

      expect(joinsOf(score), [
        [
          'begin',
          'continued begin',
          'continued continued begin',
          'end end end',
        ],
      ]);
    });

    test('join inside a tuplet, and across its edge when asked to', () {
      final inside = fill(blankScore(meter: Meter.twoFour), 0, [
        ...run(100, 2, NoteValue.eighth),
        tripletOfEighths(1, run(102, 3, NoteValue.eighth)),
      ]);
      final across = fill(blankScore(meter: Meter.twoFour), 0, [
        chordOf(100, 'G4', value: NoteValue.eighth),
        tripletOfSixteenths(
          1,
          run(101, 3, NoteValue.sixteenth, beams: {101: BeamMode.join}),
        ),
        chordOf(104, 'G4'),
      ]);

      expect(joinsOf(inside), [
        ['begin', 'end'],
        ['begin', 'continued', 'end'],
      ]);
      expect(joinsOf(across), [
        ['begin', 'continued begin', 'continued continued', 'end end'],
      ]);
    });
  });

  group('MeasureView spanners', () {
    test('cut a spanner into one segment per bar', () {
      var score = blankScore(bars: 4);
      score = withSlur(
        score,
        pointAt(score, 0, at(1, 2)),
        pointAt(score, 2, at(1, 4)),
      );
      score = withSlur(
        score,
        pointAt(score, 3, at(1, 4)),
        pointAt(score, 3, at(3, 4)),
      );

      expect(
        [for (var i = 0; i < 4; i++) segmentsIn(score, i)],
        [
          ['1/2-1 starts'],
          ['0-1'],
          ['0-1/4 ends'],
          ['1/4-3/4 starts ends'],
        ],
      );
    });

    test('list the segments of a bar in the order of the score\'s '
        'spanners', () {
      var score = blankScore(bars: 3);
      score = withSlur(
        score,
        pointAt(score, 1, at(1, 2)),
        pointAt(score, 2, at(1, 4)),
      );
      score = withSlur(
        score,
        pointAt(score, 0, Moment.zero),
        pointAt(score, 1, at(1, 4)),
      );

      expect(
        [
          for (final segment
              in score.measureView(score.measures[1].id).spanners)
            segment.spanner.id,
        ],
        [for (final spanner in score.spanners) spanner.id],
      );
    });

    test('skip hidden staves', () {
      var score = blankScore(parts: const [morinKhuur, clarinet]);
      score = withSlur(
        score,
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(1, 2)),
        staff: 1,
      );

      expect(segmentsIn(score, 0), ['0-1/2 starts ends']);
      expect(segmentsIn(hidePart(score, 1), 0), isEmpty);
    });
  });

  group('MeasureView.isRestOnly', () {
    test('holds for a bar of measure rests with nothing printed', () {
      final score = blankScore(bars: 3);

      expect(
        [for (var i = 0; i < 3; i++) viewOf(score, i).isRestOnly],
        [false, true, true],
      );
    });

    test('fails on content, marks and printed changes', () {
      final base = blankScore(bars: 3);
      MeasureColumn onStaff(
        MeasureColumn c,
        StaffMeasure Function(StaffMeasure) change,
      ) => c.withStaff(change(c.staves.first));
      final variants = <String, Score>{
        'note': fill(base, 1, [chordOf(100, 'F4', value: NoteValue.whole)]),
        'meter change': changeBar(base, 1, (c) => retimed(c, Meter.threeFour)),
        'key change': changeBar(
          base,
          1,
          (c) => c.copyWith(key: const KeySignature(1)),
        ),
        'clef change': changeBar(
          base,
          1,
          (c) => onStaff(c, (s) => s.copyWith(clef: Clef.bass)),
        ),
        'mid-bar clef': changeBar(
          base,
          1,
          (c) => onStaff(
            c,
            (s) => s.copyWith(
              clefChanges: Seq([ClefChange(at(1, 2), Clef.bass)]),
            ),
          ),
        ),
        'dynamic': changeBar(
          base,
          1,
          (c) => onStaff(
            c,
            (s) => s.copyWith(
              directions: Seq([const DynamicMark(Moment.zero, Dynamic.p)]),
            ),
          ),
        ),
        'rehearsal': changeBar(
          base,
          1,
          (c) => c.copyWith(rehearsal: () => 'A'),
        ),
        'tempo': changeBar(
          base,
          1,
          (c) => c.copyWith(
            tempos: Seq([
              const TempoMark(offset: Moment.zero, tempo: Tempo(80)),
            ]),
          ),
        ),
        'double barline': changeBar(
          base,
          1,
          (c) => c.copyWith(barline: Barline.doubleBar),
        ),
        'repeat start': changeBar(
          base,
          1,
          (c) => c.copyWith(repeatStart: true),
        ),
        'repeat end': changeBar(
          base,
          1,
          (c) => c.copyWith(repeatEnd: () => const RepeatEnd()),
        ),
        'volta': changeBar(
          base,
          1,
          (c) => c.copyWith(volta: () => const Volta([1])),
        ),
        'segno': changeBar(
          base,
          1,
          (c) => c.copyWith(navigation: Seq([const Segno()])),
        ),
        'slur': withSlur(
          base,
          pointAt(base, 0, at(1, 2)),
          pointAt(base, 1, Moment.zero),
        ),
      };

      for (final MapEntry(:key, :value) in variants.entries) {
        expect(viewOf(value, 1).isRestOnly, isFalse, reason: key);
      }
    });

    test('ignores hidden parts', () {
      var score = blankScore(parts: const [morinKhuur, clarinet]);
      score = fill(score, 1, [
        chordOf(100, 'F4', value: NoteValue.whole),
      ], staff: 1);

      expect(viewOf(score, 1).isRestOnly, isFalse);
      expect(viewOf(hidePart(score, 1), 1).isRestOnly, isTrue);
    });
  });
}
