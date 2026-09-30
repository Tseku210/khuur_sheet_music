import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A blank 4/4 score of [bars] bars with [marks] applied, keyed by 1-based
/// bar number.
Score marked(
  int bars,
  Map<int, MeasureColumn Function(MeasureColumn column)> marks,
) {
  var score = blankScore(bars: bars);
  for (final MapEntry(key: number, value: change) in marks.entries) {
    score = changeBar(score, number - 1, change);
  }
  return score;
}

MeasureColumn Function(MeasureColumn) repeatStart() =>
    (c) => c.copyWith(repeatStart: true);

MeasureColumn Function(MeasureColumn) repeatEnd([int times = 2]) =>
    (c) => c.copyWith(repeatEnd: () => RepeatEnd(times: times));

MeasureColumn Function(MeasureColumn) ending(
  List<int> endings, {
  bool repeat = false,
}) =>
    (c) => c.copyWith(
      volta: () => Volta(endings),
      repeatEnd: repeat ? () => const RepeatEnd() : null,
    );

MeasureColumn Function(MeasureColumn) navigation(
  List<NavigationMark> marks,
) =>
    (c) => c.copyWith(navigation: Seq(marks));

MeasureColumn Function(MeasureColumn) tempos(List<TempoMark> marks) =>
    (c) => c.copyWith(tempos: Seq(marks));

PlaybackScript compiled(
  Score score, [
  PlaybackOptions options = const PlaybackOptions(),
]) => PlaybackCompiler().compile(score, options);

/// The play order as 1-based bar numbers, with `#pass` from the second
/// time a bar plays.
List<String> played(
  Score score, [
  PlaybackOptions options = const PlaybackOptions(),
]) => [
  for (final bar in compiled(score, options).bars)
    '${score.indexOf(bar.measure) + 1}${bar.pass == 1 ? '' : '#${bar.pass}'}',
];

/// Each played bar's (start, end) in seconds, rounded to milliseconds.
List<(double, double)> timings(
  Score score, [
  PlaybackOptions options = const PlaybackOptions(),
]) => [
  for (final bar in compiled(score, options).bars) (ms(bar.start), ms(bar.end)),
];

double ms(double seconds) => (seconds * 1000).roundToDouble() / 1000;

/// Each note in `[from, to)` as (start, duration, key, channel, source
/// event id), times rounded to milliseconds.
List<(double, double, int, int, int)> notes(
  PlaybackScript script, [
  double from = 0,
  double to = double.infinity,
]) => [
  for (final note in script.notesBetween(from, to))
    (
      ms(note.start),
      ms(note.duration),
      note.key,
      note.channel,
      note.source.id.value,
    ),
];

List<int> sources(PlaybackScript script, double seconds) => [
  for (final ref in script.sourcesAt(seconds)) ref.id.value,
];

ChordEvent quarters(int id, String pitches) => chordOf(id, pitches);

ChordEvent halves(int id, String pitches, {bool tie = false}) =>
    chordOf(id, pitches, value: NoteValue.half, tie: tie);

ChordEvent wholes(int id, String pitches, {bool tie = false}) =>
    chordOf(id, pitches, value: NoteValue.whole, tie: tie);

/// A score of [bars] bars of four C4 quarters on the first staff, with ids
/// 10 × bar + beat, both 1-based.
Score beats(int bars, {List<PartTemplate> parts = const [morinKhuur]}) {
  var score = blankScore(parts: parts, bars: bars);
  for (var i = 0; i < bars; i++) {
    score = fill(score, i, [
      for (var beat = 1; beat <= 4; beat++) quarters(10 * (i + 1) + beat, 'C4'),
    ]);
  }
  return score;
}

/// [score] with [marks] as the dynamics of one staff in bar [bar], counted
/// from 0.
Score withDynamics(
  Score score,
  int bar,
  Map<Moment, Dynamic> marks, {
  int staff = 0,
}) => changeBar(
  score,
  bar,
  (column) => column.withStaff(
    column.staves[staff].copyWith(
      directions: Seq([
        for (final MapEntry(key: offset, value: level) in marks.entries)
          DynamicMark(offset, level),
      ]),
    ),
  ),
);

/// [score] with a line or hairpin of [kind] on its first staff.
Score withLine(
  Score score,
  SpannerKind kind,
  ScorePoint first,
  ScorePoint last,
) => score.copyWith(
  spanners: Seq([
    ...score.spanners,
    Spanner(
      id: SpannerId(800 + score.spanners.length),
      kind: kind,
      staff: score.staves.first.id,
      first: first,
      last: last,
    ),
  ]),
);

List<int> velocities(PlaybackScript script) => [
  for (final note in script.notesBetween(0, double.infinity)) note.velocity,
];

/// Each source event id with the velocity it strikes at.
Map<int, int> loudness(PlaybackScript script) => {
  for (final note in script.notesBetween(0, double.infinity))
    note.source.id.value: note.velocity,
};

ChordEvent withMarks(ChordEvent chord, Set<Articulation> marks) =>
    chord.copyWith(articulations: marks);

/// A score of one bar per entry of [bars] at 80 quarters a minute, where a
/// 32nd lasts 0.09375 seconds.
Score at80(
  List<List<VoiceItem>> bars, {
  KeySignature key = KeySignature.cMajor,
}) {
  var score = blankScore(bars: bars.length, key: key);
  for (final (i, items) in bars.indexed) {
    score = fill(score, i, items);
  }
  return changeBar(
    score,
    0,
    tempos([const TempoMark(offset: Moment.zero, tempo: Tempo(80))]),
  );
}

/// Each note as (start, key, source event id), the start rounded to
/// milliseconds.
List<(double, int, int)> attacks(PlaybackScript script) => [
  for (final note in script.notesBetween(0, double.infinity))
    (ms(note.start), note.key, note.source.id.value),
];

GraceChord grace(
  int id,
  String pitch, {
  GraceKind kind = GraceKind.acciaccatura,
  bool tie = false,
}) => GraceChord(
  id: EventId(id),
  kind: kind,
  value: NoteValue.eighth,
  notes: Seq([
    PitchedNote(id: NoteId(id * 10), pitch: Pitch.parse(pitch), tie: tie),
  ]),
);

ChordEvent ornamented(ChordEvent chord, Ornament ornament) =>
    chord.copyWith(ornament: () => ornament);

ChordEvent tremolo(ChordEvent chord, int strokes) =>
    chord.copyWith(tremolo: strokes);

void main() {
  group('play order', () {
    test('plays the bars once in notated order', () {
      expect(played(blankScore(bars: 3)), ['1', '2', '3']);
    });

    test('repeats back to the start repeat, or the start of the score', () {
      expect(
        played(marked(4, {2: repeatStart(), 3: repeatEnd()})),
        ['1', '2', '3', '2#2', '3#2', '4'],
      );
      expect(
        played(marked(3, {2: repeatEnd(3)})),
        ['1', '2', '1#2', '2#2', '1#3', '2#3', '3'],
      );
    });

    test('a later repeat without a start returns after the one before', () {
      expect(
        played(marked(4, {1: repeatEnd(), 3: repeatEnd()})),
        ['1', '1#2', '2', '3', '2#2', '3#2', '4'],
      );
    });

    test('plays each ending on its passes', () {
      expect(
        played(
          marked(4, {
            2: ending([1], repeat: true),
            3: ending([2]),
          }),
        ),
        ['1', '2', '1#2', '3', '4'],
      );
      expect(
        played(
          marked(4, {
            2: (c) => ending([1, 2])(c).copyWith(
              repeatEnd: () => const RepeatEnd(times: 3),
            ),
            3: ending([3]),
          }),
        ),
        ['1', '2', '1#2', '2#2', '1#3', '3', '4'],
      );
    });

    test('starts a new section after the last ending', () {
      expect(
        played(
          marked(5, {
            2: ending([1], repeat: true),
            3: ending([2]),
            5: repeatEnd(),
          }),
        ),
        ['1', '2', '1#2', '3', '4', '5', '4#2', '5#2'],
      );
    });

    test('an end repeat after the endings returns to the section start', () {
      expect(
        played(
          marked(4, {
            2: ending([1]),
            3: ending([2]),
            4: repeatEnd(),
          }),
        ),
        ['1', '2', '4', '1#2', '3', '4#2'],
      );
    });

    test('D.C. al Fine stops at the Fine after the jump', () {
      expect(
        played(
          marked(4, {
            2: navigation([const Fine()]),
            4: navigation([
              const Jump(JumpTarget.start, then: JumpThen.toFine),
            ]),
          }),
        ),
        ['1', '2', '3', '4', '1#2', '2#2'],
      );
    });

    test('D.S. al Coda leaves for the coda after the jump', () {
      expect(
        played(
          marked(6, {
            2: navigation([const Segno()]),
            3: navigation([const ToCoda()]),
            5: navigation([
              const Jump(JumpTarget.segno, then: JumpThen.toCoda),
            ]),
            6: navigation([const Coda()]),
          }),
        ),
        ['1', '2', '3', '4', '5', '2#2', '3#2', '6'],
      );
    });

    test('a jump plays to the end unless it asks for the Fine or coda', () {
      expect(
        played(
          marked(5, {
            2: navigation([const Fine()]),
            3: navigation([const ToCoda()]),
            4: navigation([const Jump(JumpTarget.start)]),
            5: navigation([const Coda()]),
          }),
        ),
        ['1', '2', '3', '4', '1#2', '2#2', '3#2', '4#2', '5'],
      );
    });

    test('a jump is taken after the repeats of its bar, and only once', () {
      expect(
        played(
          marked(2, {
            2: (c) => repeatEnd()(c).copyWith(
              navigation: Seq(const [Jump(JumpTarget.start)]),
            ),
          }),
        ),
        ['1', '2', '1#2', '2#2', '1#3', '2#3'],
      );
    });

    test('after a jump, repeats are not taken and the last ending plays', () {
      expect(
        played(
          marked(4, {
            2: ending([1], repeat: true),
            3: ending([2]),
            4: navigation([const Jump(JumpTarget.start)]),
          }),
        ),
        ['1', '2', '1#2', '3', '4', '1#3', '3#2', '4#2'],
      );
    });

    test('a D.S. without a segno goes to the start', () {
      expect(
        played(
          marked(2, {
            2: navigation([const Jump(JumpTarget.segno)]),
          }),
        ),
        ['1', '2', '1#2', '2#2'],
      );
    });

    test('a to-coda without a coda plays on', () {
      expect(
        played(
          marked(3, {
            1: navigation([const ToCoda()]),
            2: navigation([
              const Jump(JumpTarget.start, then: JumpThen.toCoda),
            ]),
          }),
        ),
        ['1', '2', '1#2', '2#2', '3'],
      );
    });

    test('a coda before its to-coda is left only once', () {
      expect(
        played(
          marked(3, {
            1: navigation([const Coda()]),
            2: navigation([const ToCoda()]),
            3: navigation([
              const Jump(JumpTarget.start, then: JumpThen.toCoda),
            ]),
          }),
        ),
        ['1', '2', '3', '1#2', '2#2', '1#3', '2#3', '3#2'],
      );
    });

    test('stops a runaway repeat at 64 times the bar count', () {
      expect(
        compiled(marked(1, {1: repeatEnd(1000)})).bars,
        hasLength(64),
      );
    });

    test('a range plays its bars once in notated order', () {
      final score = marked(4, {2: repeatStart(), 3: repeatEnd()});

      expect(
        played(
          score,
          PlaybackOptions(
            from: pointAt(score, 1, at(1, 4)),
            to: pointAt(score, 2, at(1, 2)),
          ),
        ),
        ['2', '3'],
      );
      expect(
        played(score, PlaybackOptions(from: pointAt(score, 2, Moment.zero))),
        ['3', '4'],
      );
      expect(
        played(score, PlaybackOptions(to: pointAt(score, 1, Moment.zero))),
        ['1'],
      );
      expect(
        played(
          score,
          PlaybackOptions(
            from: pointAt(score, 2, Moment.zero),
            to: pointAt(score, 1, Moment.zero),
          ),
        ),
        isEmpty,
      );
    });
  });

  group('notes', () {
    test('plays each head at its time, 0.9 of its length, at mf', () {
      final score = sessionWith([
        [
          quarters(1, 'C4 E4'),
          rest(2, NoteValue.quarter),
          halves(3, 'G4'),
        ],
      ]).score;
      final script = compiled(score);

      expect(notes(script), [
        (0.0, 0.54, 60, 0, 1),
        (0.0, 0.54, 64, 0, 1),
        (1.2, 1.08, 67, 0, 3),
      ]);
      expect(
        {for (final note in script.notesBetween(0, 10)) note.velocity},
        {64},
      );
    });

    test('times tuplets, every voice and every staff', () {
      var score = blankScore(parts: const [piano], bars: 1);
      score = fill(score, 0, [
        tripletOfEighths(1, [
          chordOf(2, 'C4', value: NoteValue.eighth),
          chordOf(3, 'D4', value: NoteValue.eighth),
          chordOf(4, 'E4', value: NoteValue.eighth),
        ]),
        rest(5, NoteValue.quarter),
        rest(6, NoteValue.half),
      ]);
      score = fill(score, 0, [
        Gap(len(1, 2)),
        halves(7, 'A3'),
      ], slot: VoiceSlot.two);
      score = fill(score, 0, [wholes(8, 'C3')], staff: 1);

      expect(notes(compiled(score)), [
        (0.0, 0.18, 60, 0, 2),
        (0.0, 2.16, 48, 0, 8),
        (0.2, 0.18, 62, 0, 3),
        (0.4, 0.18, 64, 0, 4),
        (1.2, 1.08, 57, 0, 7),
      ]);
    });

    test('merges a tie chain into one note from its first event', () {
      final score = sessionWith([
        [
          chordOf(1, 'C4 E4', tie: true),
          quarters(2, 'C4'),
          halves(3, 'G4', tie: true),
        ],
        [wholes(4, 'G4')],
      ]).score;

      expect(notes(compiled(score)), [
        (0.0, 1.14, 60, 0, 1),
        (0.0, 0.54, 64, 0, 1),
        (1.2, 3.36, 67, 0, 3),
      ]);
    });

    test('a tie stays in its staff and voice', () {
      var score = blankScore(parts: const [piano], bars: 1);
      score = fill(score, 0, [
        chordOf(1, 'C4', tie: true),
        rest(2, NoteValue.quarter),
        rest(3, NoteValue.half),
      ]);
      score = fill(score, 0, [
        Gap(len(1, 4)),
        quarters(4, 'C4'),
        Gap(len(1, 2)),
      ], slot: VoiceSlot.two);
      score = fill(score, 0, [
        rest(5, NoteValue.quarter),
        quarters(6, 'C4'),
        rest(7, NoteValue.half),
      ], staff: 1);

      expect([for (final n in notes(compiled(score))) n.$5], [1, 4, 6]);
    });

    test('a tie that meets a gap, a rest or another pitch lets go', () {
      var score = sessionWith([
        [
          chordOf(1, 'E4', tie: true),
          rest(2, NoteValue.quarter),
          chordOf(3, 'E4', tie: true),
          quarters(4, 'F4'),
        ],
      ]).score;
      score = fill(score, 0, [
        chordOf(5, 'C4', tie: true),
        Gap(len(1, 4)),
        halves(6, 'C4'),
      ], slot: VoiceSlot.two);

      expect(notes(compiled(score)), [
        (0.0, 0.54, 64, 0, 1),
        (0.0, 0.54, 60, 0, 5),
        (1.2, 0.54, 64, 0, 3),
        (1.2, 1.08, 60, 0, 6),
        (1.8, 0.54, 65, 0, 4),
      ]);
    });

    test('a tie across a barline lands on the bar played next', () {
      final score = changeBar(
        changeBar(
          sessionWith([
            [wholes(1, 'E4')],
            [wholes(2, 'C4', tie: true)],
            [wholes(3, 'C4')],
          ]).score,
          1,
          ending([1], repeat: true),
        ),
        2,
        ending([2]),
      );

      expect(notes(compiled(score)), [
        (0.0, 2.16, 64, 0, 1),
        (2.4, 2.16, 60, 0, 2),
        (4.8, 2.16, 64, 0, 1),
        (7.2, 2.16, 60, 0, 3),
      ]);
    });

    test('gives quarter tones their cents', () {
      final score = sessionWith([
        [
          quarters(1, 'C+4 Ed4'),
          rest(2, NoteValue.quarter),
          rest(3, NoteValue.half),
        ],
      ]).score;

      expect(
        [
          for (final note in compiled(score).notesBetween(0, 10))
            (note.key, note.cents),
        ],
        [(60, 50), (63, 50)],
      );
    });

    test('plays a drum note as the kit sound it names', () {
      final score = fill(blankScore(parts: const [drums], bars: 1), 0, [
        hit(1, [snare]),
        hit(2, [sideStick]),
        hit(3, [bassDrum, snare]),
        hit(4, [bassDrum]),
      ]);
      final script = compiled(score);

      expect(notes(script), [
        (0.0, 0.54, 38, 9, 1),
        (0.6, 0.54, 37, 9, 2),
        (1.2, 0.54, 36, 9, 3),
        (1.2, 0.54, 38, 9, 3),
        (1.8, 0.54, 36, 9, 4),
      ]);
      expect({for (final note in script.notesBetween(0, 10)) note.cents}, {0});
    });

    test(
      'gives each part a channel past 9, drums 9, and skips muted parts',
      () {
        final score = blankScore(
          parts: const [piano, drums, clarinet, morinKhuur],
        );
        List<(int, int, int, int)> setups(Set<PartId> muted) => [
          for (final setup in compiled(
            score,
            PlaybackOptions(muted: muted),
          ).channels)
            (
              setup.channel,
              score.parts.indexWhere((p) => p.id == setup.part),
              setup.program,
              setup.bank,
            ),
        ];

        expect(setups(const {}), [
          (0, 0, 0, 0),
          (9, 1, 0, 128),
          (1, 2, 71, 0),
          (2, 3, 110, 0),
        ]);
        expect(setups({score.parts[2].id}), [
          (0, 0, 0, 0),
          (9, 1, 0, 128),
          (2, 3, 110, 0),
        ]);
        expect(
          [
            for (final setup in compiled(
              blankScore(parts: List.filled(17, morinKhuur)),
            ).channels)
              setup.channel,
          ],
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 0, 1],
        );
      },
    );

    test('notes that start together keep score order', () {
      var score = blankScore(parts: List.filled(17, morinKhuur), bars: 1);
      for (var staff = 0; staff < 17; staff++) {
        score = fill(score, 0, [wholes(staff + 1, 'C4 E4 G4')], staff: staff);
      }

      expect(
        [for (final n in notes(compiled(score))) (n.$5, n.$3)],
        [
          for (var id = 1; id <= 17; id++) ...[(id, 60), (id, 64), (id, 67)],
        ],
      );
    });

    test('leaves out muted parts and plays hidden ones', () {
      var score = blankScore(
        parts: const [morinKhuur, clarinet, piano],
        bars: 1,
      );
      score = fill(score, 0, [wholes(1, 'C4')]);
      score = fill(score, 0, [wholes(2, 'D4')], staff: 1);
      score = fill(score, 0, [wholes(3, 'E4')], staff: 2);
      score = hidePart(score, 1);

      expect(
        notes(compiled(score, PlaybackOptions(muted: {score.parts[2].id}))),
        [(0.0, 2.16, 60, 0, 1), (0.0, 2.16, 62, 1, 2)],
      );
    });

    test('a range plays the notes that start in it', () {
      final score = sessionWith([
        [
          chordOf(1, 'C4', tie: true),
          quarters(2, 'C4'),
          quarters(3, 'E4'),
          quarters(4, 'F4'),
        ],
        [
          quarters(5, 'G4'),
          quarters(6, 'A4'),
          quarters(7, 'B4'),
          quarters(8, 'C5'),
        ],
      ]).score;

      expect(
        notes(
          compiled(
            score,
            PlaybackOptions(
              from: pointAt(score, 0, at(1, 4)),
              to: pointAt(score, 1, at(1, 2)),
            ),
          ),
        ),
        [
          (0.0, 0.54, 60, 0, 2),
          (0.6, 0.54, 64, 0, 3),
          (1.2, 0.54, 65, 0, 4),
          (1.8, 0.54, 67, 0, 5),
          (2.4, 0.54, 69, 0, 6),
        ],
      );
    });

    test('returns the notes that start in a window', () {
      final script = compiled(
        sessionWith([
          [
            quarters(1, 'C4'),
            quarters(2, 'D4'),
            quarters(3, 'E4'),
            quarters(4, 'F4'),
          ],
        ]).score,
      );

      expect([for (final n in notes(script, 0.6, 1.8)) n.$5], [2, 3]);
      expect([for (final n in notes(script, 0.61, 1.81)) n.$5], [3, 4]);
      expect(notes(script, 0.6, 0.6), isEmpty);
      expect(notes(script, 2.4), isEmpty);
    });

    test('says which event sounds in each voice', () {
      var score = blankScore(parts: const [morinKhuur, clarinet]);
      score = fill(score, 0, [
        halves(1, 'C4 E4', tie: true),
        halves(2, 'C4'),
      ]);
      score = fill(score, 0, [
        Gap(len(1, 2)),
        rest(3, NoteValue.quarter),
        quarters(4, 'A3'),
      ], slot: VoiceSlot.two);
      score = fill(score, 0, [wholes(5, 'D4')], staff: 1);
      score = fill(score, 1, [wholes(6, 'E4')]);
      final script = compiled(
        score,
        PlaybackOptions(muted: {score.parts[1].id}),
      );

      expect(sources(script, 0.3), [1]);
      expect(sources(script, 1.5), [2]);
      expect(sources(script, 2.1), [2, 4]);
      expect(sources(script, 2.4), [6]);
      expect(sources(script, 4.8), isEmpty);
      expect(sources(compiled(score), 0.3), [1, 5]);
    });
  });

  group('expression', () {
    test("a dynamic sets its part's level from its time to the next", () {
      var score = beats(2, parts: const [piano, clarinet]);
      score = fill(score, 0, [wholes(31, 'C3')], staff: 1);
      score = fill(score, 1, [wholes(32, 'C3')], staff: 1);
      score = fill(score, 0, [wholes(41, 'D4')], staff: 2);
      score = fill(score, 1, [wholes(42, 'D4')], staff: 2);
      score = withDynamics(score, 0, {at(1, 2): Dynamic.p});
      score = withDynamics(score, 1, {at(3, 4): Dynamic.pp});
      score = withDynamics(score, 1, {at(1, 4): Dynamic.ff}, staff: 1);

      expect(loudness(compiled(score)), {
        11: 64,
        31: 64,
        41: 64,
        12: 64,
        13: 42,
        14: 42,
        21: 42,
        32: 42,
        42: 64,
        22: 96,
        23: 96,
        24: 31,
      });
    });

    test('a bar starts at the level written before it, not played', () {
      var score = changeBar(beats(2), 1, repeatEnd());
      score = withDynamics(score, 1, {Moment.zero: Dynamic.ff});

      expect(velocities(compiled(score)), [
        ...[64, 64, 64, 64, 96, 96, 96, 96],
        ...[64, 64, 64, 64, 96, 96, 96, 96],
      ]);
    });

    test('sf, sfz and rfz strike one chord, and fp strikes f and leaves p', () {
      var score = beats(2);
      score = withDynamics(score, 0, {
        Moment.zero: Dynamic.sfz,
        at(1, 2): Dynamic.fp,
      });
      score = withDynamics(score, 1, {
        Moment.zero: Dynamic.sf,
        at(1, 2): Dynamic.rfz,
      });

      expect(velocities(compiled(score)), [110, 64, 80, 42, 100, 42, 100, 42]);
    });

    test('a hairpin ramps from its start to the dynamic after it', () {
      var score = beats(2);
      score = withDynamics(score, 0, {Moment.zero: Dynamic.p});
      score = withDynamics(score, 1, {Moment.zero: Dynamic.f});
      score = withLine(
        score,
        const Hairpin(crescendo: true),
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(3, 4)),
      );

      expect(velocities(compiled(score)), [42, 52, 61, 71, 80, 80, 80, 80]);
    });

    test('a hairpin reaches a dynamic on its last chord', () {
      var score = beats(2);
      score = withDynamics(score, 0, {
        Moment.zero: Dynamic.p,
        at(3, 4): Dynamic.f,
      });
      score = withLine(
        score,
        const Hairpin(crescendo: true),
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(3, 4)),
      );

      expect(velocities(compiled(score)), [42, 55, 67, 80, 80, 80, 80, 80]);
    });

    test('a hairpin with no dynamic at its end moves one level', () {
      var score = withDynamics(beats(3), 2, {at(1, 2): Dynamic.ff});
      score = withLine(
        score,
        const Hairpin(crescendo: true),
        pointAt(score, 1, Moment.zero),
        pointAt(score, 1, Moment.zero),
      );
      score = withLine(
        score,
        const Hairpin(crescendo: false),
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(3, 4)),
      );

      expect(velocities(compiled(score)), [
        ...[64, 61, 59, 56],
        ...[53, 64, 64, 64],
        ...[64, 64, 96, 96],
      ]);
    });

    test('a hairpin stays within pppp and ffff', () {
      var score = withDynamics(beats(2), 0, {Moment.zero: Dynamic.ffff});
      score = withDynamics(score, 1, {Moment.zero: Dynamic.pppp});
      score = withLine(
        score,
        const Hairpin(crescendo: true),
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, Moment.zero),
      );
      score = withLine(
        score,
        const Hairpin(crescendo: false),
        pointAt(score, 1, Moment.zero),
        pointAt(score, 1, Moment.zero),
      );

      expect(velocities(compiled(score)), [127, 127, 127, 127, 12, 12, 12, 12]);
    });

    test('the later of two overlapping hairpins wins', () {
      var score = beats(2);
      score = withLine(
        score,
        const Hairpin(crescendo: true),
        pointAt(score, 0, Moment.zero),
        pointAt(score, 1, at(3, 4)),
      );
      score = withLine(
        score,
        const Hairpin(crescendo: false),
        pointAt(score, 1, Moment.zero),
        pointAt(score, 1, at(3, 4)),
      );

      expect(velocities(compiled(score)), [64, 66, 68, 70, 64, 61, 59, 56]);
    });

    test('a compiler plays a hairpin added since its last compile', () {
      final compiler = PlaybackCompiler();
      var score = beats(1, parts: const [morinKhuur, clarinet]);
      score = fill(score, 0, [
        rest(4, NoteValue.quarter),
        halves(5, 'D4'),
        rest(6, NoteValue.quarter),
      ], staff: 1);
      compiler.compile(score);
      score = withLine(
        score,
        const Hairpin(crescendo: true),
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(3, 4)),
      );

      expect(loudness(compiler.compile(score)), {
        11: 64,
        12: 68,
        5: 64,
        13: 72,
        14: 76,
      });
    });

    test('accent and marcato strike harder, up to 127', () {
      var score = blankScore();
      score = fill(score, 0, [
        withMarks(quarters(1, 'C4'), {Articulation.accent}),
        withMarks(quarters(2, 'C4'), {Articulation.marcato}),
        quarters(3, 'C4'),
        withMarks(quarters(4, 'C4'), {
          Articulation.accent,
          Articulation.marcato,
        }),
      ]);
      score = fill(score, 1, [
        withMarks(quarters(5, 'C4'), {Articulation.accent}),
        withMarks(quarters(6, 'C4'), {Articulation.marcato}),
        rest(7, NoteValue.half),
      ]);
      score = withDynamics(score, 1, {Moment.zero: Dynamic.ff});

      expect(velocities(compiled(score)), [80, 96, 64, 120, 120, 127]);
    });

    test('articulations set how long the last note of a chain sounds', () {
      var score = blankScore();
      score = fill(score, 0, [
        withMarks(quarters(1, 'C4'), {Articulation.staccato}),
        withMarks(quarters(2, 'D4'), {Articulation.staccatissimo}),
        withMarks(quarters(3, 'E4'), {Articulation.tenuto}),
        withMarks(quarters(4, 'F4'), {
          Articulation.staccato,
          Articulation.tenuto,
        }),
      ]);
      score = fill(score, 1, [
        withMarks(halves(5, 'G4', tie: true), {Articulation.tenuto}),
        withMarks(quarters(6, 'G4'), {
          Articulation.staccato,
          Articulation.accent,
        }),
        quarters(7, 'A4'),
      ]);
      final script = compiled(score);

      expect(notes(script), [
        (0.0, 0.3, 60, 0, 1),
        (0.6, 0.15, 62, 0, 2),
        (1.2, 0.6, 64, 0, 3),
        (1.8, 0.45, 65, 0, 4),
        (2.4, 1.5, 67, 0, 5),
        (4.2, 0.54, 69, 0, 7),
      ]);
      expect(loudness(script)[5], 64);
    });

    test('a fermata holds its event twice as long in every part', () {
      var score = blankScore(parts: const [morinKhuur, clarinet]);
      score = fill(score, 0, [
        withMarks(quarters(1, 'C4'), {Articulation.fermata}),
        quarters(2, 'D4'),
        halves(3, 'E4'),
      ]);
      score = fill(score, 0, [halves(4, 'C4'), halves(5, 'D4')], staff: 1);
      score = fill(score, 1, [
        const RestEvent(
          id: EventId(6),
          value: NoteValue.whole,
          articulations: {Articulation.fermata},
        ),
      ]);
      final muted = PlaybackOptions(muted: {score.parts.first.id});

      expect(timings(score), [(0.0, 3.0), (3.0, 7.8)]);
      expect(timings(score, muted), [(0.0, 3.0), (3.0, 7.8)]);
      expect(notes(compiled(score)), [
        (0.0, 1.08, 60, 0, 1),
        (0.0, 1.62, 60, 1, 4),
        (1.2, 0.54, 62, 0, 2),
        (1.8, 1.08, 64, 0, 3),
        (1.8, 1.08, 62, 1, 5),
      ]);
      expect(sources(compiled(score), 1), [1, 4]);
    });
  });

  group('ornaments', () {
    test('an acciaccatura takes a 32nd from the start of its chord', () {
      final score = at80([
        [
          withMarks(chordOf(1, 'C4', graces: [grace(5, 'D4')]), {
            Articulation.accent,
          }),
          chordOf(2, 'E4', graces: [grace(6, 'F4'), grace(7, 'G4')]),
          halves(3, 'C5'),
        ],
      ]);
      final script = compiled(score);

      expect(notes(script), [
        (0.0, 0.084, 62, 0, 5),
        (0.094, 0.591, 60, 0, 1),
        (0.75, 0.084, 65, 0, 6),
        (0.844, 0.084, 67, 0, 7),
        (0.938, 0.506, 64, 0, 2),
        (1.5, 1.35, 72, 0, 3),
      ]);
      expect(loudness(script), {5: 64, 1: 80, 6: 64, 7: 64, 2: 64, 3: 64});
      expect(sources(script, 0.05), [1]);
    });

    test('appoggiaturas take half their chord, and graces at most half', () {
      final score = at80([
        [
          halves(1, 'C5').copyWith(
            graces: Seq([grace(5, 'D5', kind: GraceKind.appoggiatura)]),
          ),
          withMarks(
            chordOf(
              2,
              'E4',
              graces: [
                grace(6, 'F4', kind: GraceKind.appoggiatura),
                grace(7, 'G4'),
              ],
            ),
            {Articulation.tenuto},
          ),
          chordOf(
            3,
            'D5',
            value: NoteValue.eighth,
            graces: [grace(8, 'A4'), grace(9, 'B4'), grace(10, 'C5')],
          ),
          rest(4, NoteValue.eighth),
        ],
      ]);

      expect(notes(compiled(score)), [
        (0.0, 0.675, 74, 0, 5),
        (0.75, 0.675, 72, 0, 1),
        (1.5, 0.169, 65, 0, 6),
        (1.688, 0.169, 67, 0, 7),
        (1.875, 0.375, 64, 0, 2),
        (2.25, 0.056, 69, 0, 8),
        (2.313, 0.056, 71, 0, 9),
        (2.375, 0.056, 72, 0, 10),
        (2.438, 0.169, 74, 0, 3),
      ]);
    });

    test('a tremolo repeats its chord in the value its strokes and flags '
        'make', () {
      final score = at80([
        [
          tremolo(quarters(1, 'C4'), 1),
          tremolo(chordOf(2, 'D4', value: NoteValue.eighth), 1),
          tremolo(chordOf(3, 'E4', value: NoteValue.eighth), 2),
          tremolo(halves(4, 'F4'), 1),
        ],
        [
          tripletOfEighths(20, [
            tremolo(chordOf(21, 'G4', value: NoteValue.eighth), 1),
            chordOf(22, 'A4', value: NoteValue.eighth),
            chordOf(23, 'B4', value: NoteValue.eighth),
          ]),
          tremolo(quarters(24, 'C5'), 3),
          rest(25, NoteValue.half),
        ],
      ]);
      final script = compiled(score);

      expect(attacks(script), [
        (0.0, 60, 1),
        (0.375, 60, 1),
        (0.75, 62, 2),
        (0.938, 62, 2),
        (1.125, 64, 3),
        (1.219, 64, 3),
        (1.313, 64, 3),
        (1.406, 64, 3),
        (1.5, 65, 4),
        (1.875, 65, 4),
        (2.25, 65, 4),
        (2.625, 65, 4),
        (3.0, 67, 21),
        (3.125, 67, 21),
        (3.25, 69, 22),
        (3.5, 71, 23),
        (3.75, 72, 24),
        (3.844, 72, 24),
        (3.938, 72, 24),
        (4.031, 72, 24),
        (4.125, 72, 24),
        (4.219, 72, 24),
        (4.313, 72, 24),
        (4.406, 72, 24),
      ]);
      expect(sources(script, 0.4), [1]);
    });

    test('a trill alternates with the note above in the key in 32nds', () {
      final score = at80([
        [
          withMarks(ornamented(quarters(1, 'E5'), Ornament.trill), {
            Articulation.accent,
            Articulation.staccato,
          }),
          rest(2, NoteValue.quarter),
          rest(3, NoteValue.half),
        ],
      ], key: const KeySignature(1));
      final script = compiled(score);

      expect(notes(script), [
        (0.0, 0.084, 76, 0, 1),
        (0.094, 0.084, 78, 0, 1),
        (0.188, 0.084, 76, 0, 1),
        (0.281, 0.084, 78, 0, 1),
        (0.375, 0.084, 76, 0, 1),
        (0.469, 0.084, 78, 0, 1),
        (0.563, 0.084, 76, 0, 1),
        (0.656, 0.047, 78, 0, 1),
      ]);
      expect(velocities(script), [80, 64, 64, 64, 64, 64, 64, 64]);
    });

    test('a trill stretches its 32nds to fit, and plays its note when '
        'none fit', () {
      final score = at80([
        [
          tripletOfEighths(20, [
            ornamented(
              chordOf(21, 'E5', value: NoteValue.eighth),
              Ornament.trill,
            ),
            chordOf(22, 'F5', value: NoteValue.eighth),
            chordOf(23, 'G5', value: NoteValue.eighth),
          ]),
          ornamented(
            chordOf(
              24,
              'E5',
              value: NoteValue.thirtySecond,
              graces: [grace(9, 'D5')],
            ),
            Ornament.trill,
          ),
          rest(25, NoteValue.thirtySecond),
          rest(26, NoteValue.sixteenth),
          rest(27, NoteValue.eighth),
          rest(28, NoteValue.half),
        ],
      ]);

      expect(attacks(compiled(score)), [
        (0.0, 76, 21),
        (0.125, 77, 21),
        (0.25, 77, 22),
        (0.5, 79, 23),
        (0.75, 74, 9),
        (0.797, 76, 24),
      ]);
    });

    test('mordents and turns play their neighbours in 32nds, then hold', () {
      final score = at80(
        [
          [
            ornamented(quarters(1, 'A4'), Ornament.mordent),
            ornamented(quarters(2, 'A4'), Ornament.invertedMordent),
            ornamented(quarters(3, 'A4'), Ornament.turn),
            rest(4, NoteValue.quarter),
          ],
          [
            ornamented(quarters(5, 'A4'), Ornament.invertedTurn),
            ornamented(
              chordOf(6, 'A4', value: NoteValue.sixteenth),
              Ornament.mordent,
            ),
            chordOf(7, 'C5', value: NoteValue.sixteenth),
            chordOf(8, 'D5', value: NoteValue.eighth),
            rest(9, NoteValue.half),
          ],
          [
            ornamented(quarters(10, 'C0'), Ornament.mordent),
            rest(11, NoteValue.quarter),
            rest(12, NoteValue.half),
          ],
        ],
        key: const KeySignature(-1),
      );
      final script = compiled(score);

      expect(attacks(script), [
        (0.0, 69, 1),
        (0.094, 67, 1),
        (0.188, 69, 1),
        (0.75, 69, 2),
        (0.844, 70, 2),
        (0.938, 69, 2),
        (1.5, 70, 3),
        (1.594, 69, 3),
        (1.688, 67, 3),
        (1.781, 69, 3),
        (3.0, 67, 5),
        (3.094, 69, 5),
        (3.188, 70, 5),
        (3.281, 69, 5),
        (3.75, 69, 6),
        (3.813, 67, 6),
        (3.875, 69, 6),
        (3.938, 72, 7),
        (4.125, 74, 8),
        (6.0, 12, 10),
        (6.094, 10, 10),
        (6.188, 12, 10),
      ]);
      expect(ms(script.notesBetween(0.1, 0.2).single.duration), 0.506);
    });

    test('a trill line trills the chords under it without an ornament', () {
      final compiler = PlaybackCompiler();
      var score = at80([
        [
          quarters(1, 'C4'),
          quarters(2, 'D4'),
          quarters(3, 'E4'),
          quarters(4, 'F4'),
        ],
        [
          quarters(5, 'G4'),
          ornamented(quarters(6, 'A4'), Ornament.mordent),
          quarters(7, 'B4'),
          quarters(8, 'C5'),
        ],
      ]);
      List<int> keys() => [
        for (final (_, key, _) in attacks(compiler.compile(score))) key,
      ];
      expect(keys(), [60, 62, 64, 65, 67, 69, 67, 69, 71, 72]);
      score = withLine(
        score,
        const TrillLine(),
        pointAt(score, 1, Moment.zero),
        pointAt(score, 1, at(1, 2)),
      );

      expect(keys(), [
        ...[60, 62, 64, 65],
        ...[67, 69, 67, 69, 67, 69, 67, 69],
        ...[69, 67, 69],
        ...[71, 72, 71, 72, 71, 72, 71, 72],
        72,
      ]);
    });

    test('a tie holds into the next attack of its pitch, from the last '
        'stroke of a tremolo or from a grace', () {
      final score = at80([
        [
          tremolo(chordOf(1, 'C4', tie: true), 1),
          quarters(2, 'C4'),
          chordOf(3, 'E4', tie: true),
          chordOf(4, 'E4', graces: [grace(9, 'F4')]),
        ],
        [
          ornamented(chordOf(5, 'C4', tie: true), Ornament.trill),
          ornamented(quarters(6, 'C4'), Ornament.turn),
          chordOf(7, 'G4', graces: [grace(11, 'G4', tie: true)]),
          rest(8, NoteValue.quarter),
        ],
      ]);
      final script = compiled(score);

      expect(attacks(script), [
        (0.0, 60, 1),
        (0.375, 60, 1),
        (1.5, 64, 3),
        (2.25, 65, 9),
        (2.344, 64, 4),
        (3.0, 60, 5),
        (3.094, 62, 5),
        (3.188, 60, 5),
        (3.281, 62, 5),
        (3.375, 60, 5),
        (3.469, 62, 5),
        (3.563, 60, 5),
        (3.656, 62, 5),
        (3.75, 62, 6),
        (3.844, 60, 6),
        (3.938, 59, 6),
        (4.031, 60, 6),
        (4.5, 67, 11),
      ]);
      expect(ms(script.notesBetween(0.3, 0.4).single.duration), 1.05);
      expect(ms(script.notesBetween(4.4, 4.6).single.duration), 0.684);
    });
  });

  group('timing', () {
    test('times bars at 100 quarters a minute before any tempo mark', () {
      final script = compiled(blankScore());

      expect(timings(blankScore()), [(0.0, 2.4), (2.4, 4.8)]);
      expect(script.totalSeconds, closeTo(4.8, 1e-9));
    });

    test('changes tempo at each mark, mid-bar included', () {
      final score = marked(4, {
        1: tempos([
          const TempoMark(
            offset: Moment.zero,
            tempo: Tempo(60, beat: NoteValue.half),
          ),
          TempoMark(offset: at(1, 2), tempo: const Tempo(150)),
        ]),
        2: tempos([TempoMark(offset: at(1, 2), tempo: const Tempo(75))]),
      });

      expect(timings(score), [
        (0.0, 1.8),
        (1.8, 4.2),
        (4.2, 7.4),
        (7.4, 10.6),
      ]);
      expect(
        compiled(score).secondsAt(pointAt(score, 1, at(1, 4))),
        closeTo(2.2, 1e-9),
      );
    });

    test('times a pickup by its length', () {
      final score = applied(
        blank().run(SetBarLength(idOf(blank(), 0), len(1, 4))),
      ).score;

      expect(timings(score), [(0.0, 0.6), (0.6, 3.0)]);
    });

    test('takes the tempo written before a bar, not the one played before', () {
      final score = marked(2, {
        2: (c) => c.copyWith(
          tempos: Seq(const [
            TempoMark(offset: Moment.zero, tempo: Tempo(200)),
          ]),
          navigation: Seq(const [Jump(JumpTarget.start)]),
        ),
      });

      expect(timings(score), [
        (0.0, 2.4),
        (2.4, 3.6),
        (3.6, 6.0),
        (6.0, 7.2),
      ]);
    });

    test('a range starts at zero from its first point', () {
      final score = blankScore(bars: 3);

      expect(
        timings(
          score,
          PlaybackOptions(
            from: pointAt(score, 0, at(1, 4)),
            to: pointAt(score, 1, at(1, 2)),
          ),
        ),
        [(0.0, 1.8), (1.8, 3.0)],
      );
    });

    test('says when a point is first reached', () {
      final score = marked(3, {2: repeatEnd()});
      final script = compiled(score);
      final range = compiled(
        score,
        PlaybackOptions(
          from: pointAt(score, 1, at(1, 4)),
          to: pointAt(score, 2, at(1, 2)),
        ),
      );

      expect(
        script.secondsAt(pointAt(score, 1, at(1, 4))),
        closeTo(3.0, 1e-9),
      );
      expect(
        script.secondsAt(pointAt(score, 2, Moment.zero)),
        closeTo(9.6, 1e-9),
      );
      expect(range.secondsAt(pointAt(score, 1, at(1, 2))), closeTo(0.6, 1e-9));
      expect(range.secondsAt(pointAt(score, 2, at(1, 4))), closeTo(2.4, 1e-9));
      expect(range.secondsAt(pointAt(score, 1, Moment.zero)), isNull);
      expect(range.secondsAt(pointAt(score, 2, at(1, 2))), isNull);
    });
  });
}
