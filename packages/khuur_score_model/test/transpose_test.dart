import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

String? moved(Transposition by, String pitch, [int fifths = 0]) =>
    by.apply(Pitch.parse(pitch), Alterations(KeySignature(fifths)))?.toString();

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
  int bottom = 0,
}) => RangeSelection(
  from: pointAt(session.score, from.$1, from.$2),
  to: pointAt(session.score, to.$1, to.$2),
  top: session.score.staves.first.id,
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
  test('Pitch.parse reads every spelling Pitch writes', () {
    for (var quarterTones = -4; quarterTones <= 4; quarterTones++) {
      final pitch = Pitch(Step.e, 4, Alter.fromQuarterTones(quarterTones));
      expect(Pitch.parse('$pitch'), pitch);
    }
  });

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

    test('steps onto the alteration in force at the new position', () {
      const step = Transposition.diatonic(1);
      expect(moved(step, 'A4', -1), 'Bb4');
      expect(moved(step, 'F#4', -1), 'G4');
      expect(moved(step, 'B3'), 'C4');
      expect(moved(const Transposition.diatonic(-1), 'C4'), 'B3');
      expect(moved(const Transposition.diatonic(7), 'Eb4', -3), 'Eb5');
      expect(moved(const Transposition.diatonic(7), 'F#4'), 'F5');
      expect(moved(const Transposition.diatonic(2), 'F#4', 1), 'A4');
      expect(moved(const Transposition.diatonic(-1), 'Fbb4', 1), 'E4');
      expect(moved(const Transposition.diatonic(0), 'F#4', -1), 'F#4');

      const f = Alterations(KeySignature(-1));
      final afterNatural = f.after(Pitch.parse('B4'));
      expect(step.apply(Pitch.parse('A4'), afterNatural), Pitch.parse('B4'));
      expect(step.apply(Pitch.parse('A3'), afterNatural), Pitch.parse('Bb3'));
      expect(
        step.apply(Pitch.parse('A4'), afterNatural.after(Pitch.parse('Bb4'))),
        Pitch.parse('Bb4'),
      );
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
          const Alterations(KeySignature.cMajor),
        ),
        isNull,
      );
      expect(
        moved(const Transposition.interval(Interval(0, 1)), 'Bx4'),
        isNull,
      );
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

    group('by a staff step', () {
      const step = Transposition.diatonic(1);
      EditSession inF() => EditSession.start(
        withKey(
          sessionWith([
            [
              chordOf(1, 'F#4'),
              chordOf(2, 'B4'),
              chordOf(3, 'A4'),
              chordOf(4, 'E4'),
            ],
          ]).score,
          0,
          -1,
        ),
      );

      test('lands on what the key and the bar give the new line', () {
        final session = inF();
        List<String> stepped(int id) =>
            bar(transposed(session, events(session, [id]), step).score, 0);

        expect(stepped(1).first, 'G4/quarter');
        expect(stepped(2)[1], 'C5/quarter');
        expect(stepped(3)[2], 'B4/quarter', reason: 'the bar has a B natural');
        expect(stepped(4)[3], 'F#4/quarter', reason: 'the bar has an F sharp');
      });

      test('reads the notes before it as the edit leaves them', () {
        final session = inF();

        final next = transposed(
          session,
          range(session, (0, Moment.zero), (0, at(1, 1))),
          step,
        );

        expect(bar(next.score, 0), [
          'G4/quarter',
          'C5/quarter',
          'Bb4/quarter',
          'F4/quarter',
        ]);
      });

      test('reads the written staff of a transposing part under 8va', () {
        var score = fill(blankScore(parts: const [clarinet]), 0, [
          chordOf(1, 'Bb4', value: NoteValue.half),
          chordOf(2, 'A4', value: NoteValue.half),
        ]);
        score = withOctaveLine(
          score,
          OctaveShift.up8,
          pointAt(score, 0, Moment.zero),
          pointAt(score, 0, at(1, 2)),
        );
        final session = EditSession.start(score);

        final next = transposed(session, events(session, [2]), step);

        // The clarinet reads D major, and the B flat is its C natural.
        expect(bar(next.score, 0), ['Bb4/half', 'Bb4/half']);
        final view = next.score.measureView(idOf(next, 0)).staves.single;
        expect(view.accidentals.keys, [const NoteId(10)]);
      });

      test('steps a note of a hidden part', () {
        var score = blankScore(parts: const [morinKhuur, clarinet]);
        score = hidePart(
          fill(score, 0, [chordOf(1, 'E4', value: NoteValue.whole)], staff: 1),
          1,
        );
        final session = EditSession.start(score);

        final next = transposed(session, events(session, [1]), step);

        expect(chordIn(next, 1).notes.single.tone, Pitch.parse('F4'));
      });

      test('does not read the notes that start with it', () {
        final session = sessionWith([
          [
            chordOf(
              1,
              'E4',
              value: NoteValue.whole,
              graces: [graceOf(9, 'F#4')],
            ),
          ],
        ]);

        final next = transposed(session, head(session, 1, 10), step);

        expect(bar(next.score, 0), ['F4/whole']);
      });

      test('takes off the accidental a moved note asked for', () {
        final session = sessionWith([
          [
            chordOf(
              1,
              'F#4',
              value: NoteValue.whole,
              accidental: AccidentalRequest.always,
            ),
          ],
        ]);
        AccidentalRequest asked(Transposition by) =>
            (chordIn(
                      transposed(session, events(session, [1]), by),
                      1,
                    ).notes.single
                    as PitchedNote)
                .accidental;

        expect(asked(step), AccidentalRequest.auto);
        expect(asked(up), AccidentalRequest.always);
      });

      test('takes off the accidentals of an ornament', () {
        final session = sessionWith([
          [
            chordOf(1, 'C5', value: NoteValue.whole).copyWith(
              ornament: () => Ornament.turn,
              ornamentAbove: () => Alter.flat,
              ornamentBelow: () => Alter.sharp,
            ),
          ],
        ]);

        final next = chordIn(
          transposed(session, events(session, [1]), step),
          1,
        );

        expect((next.ornamentAbove, next.ornamentBelow), (null, null));
      });

      test('moves a chord symbol onto the key', () {
        var score = withKey(
          sessionWith([
            [chordOf(1, 'C4', value: NoteValue.whole)],
          ]).score,
          0,
          -1,
        );
        score = changeBar(
          score,
          0,
          (column) => column.withStaff(
            column.staves.first.copyWith(
              directions: Seq([
                const ChordSymbol(
                  Moment.zero,
                  root: PitchName(Step.f, Alter.sharp),
                  quality: 'm',
                ),
              ]),
            ),
          ),
        );
        final session = EditSession.start(score);

        final next = transposed(
          session,
          range(session, (0, Moment.zero), (0, at(1, 1))),
          step,
        );

        expect(
          (next.score.measures[0].staves.first.directions.single as ChordSymbol)
              .root,
          const PitchName(Step.g),
        );
      });

      test('by no steps changes nothing', () {
        final session = inF();

        expect(
          changesNothing(
            session,
            Transpose(
              range(session, (0, Moment.zero), (0, at(1, 1))),
              const Transposition.diatonic(0),
            ),
          ),
          isTrue,
        );
      });
    });

    group('with keys', () {
      const fourth = Transposition.interval(Interval.perfectFourth);
      EditSession rekeyed(
        EditSession session,
        Selection selection,
        Transposition by,
      ) => applied(session.run(Transpose(selection, by, keys: true)));
      List<int> fifths(Score score) => [
        for (final column in score.measures) column.key.fifths,
      ];
      RangeSelection whole(EditSession session, {int bottom = 0}) => range(
        session,
        (0, Moment.zero),
        (session.score.measures.length - 1, at(1, 1)),
        bottom: bottom,
      );
      List<NoteId> marked(Score score) => [
        for (final column in score.measures)
          for (final staff in score.measureView(column.id).staves)
            ...staff.accidentals.keys,
      ];
      EditSession scale() => sessionWith([
        [
          chordOf(1, 'C4'),
          chordOf(2, 'D4'),
          chordOf(3, 'E4'),
          chordOf(4, 'F4'),
        ],
        [
          chordOf(5, 'G4'),
          chordOf(6, 'A4'),
          chordOf(7, 'B4'),
          chordOf(8, 'C5'),
        ],
      ]);
      EditSession halves(int bars, {List<PartTemplate>? parts}) {
        var score = blankScore(parts: parts ?? const [morinKhuur], bars: bars);
        for (var i = 0; i < bars; i++) {
          score = fill(score, i, [
            chordOf(i * 2 + 1, 'C4', value: NoteValue.half),
            chordOf(i * 2 + 2, 'C4', value: NoteValue.half),
          ]);
        }
        return EditSession.start(score);
      }

      test('moves the key of a range with its notes in one undo step', () {
        final session = scale();

        final next = rekeyed(session, whole(session), fourth);

        expect(fifths(next.score), [-1, -1]);
        expect(next.score.measures.first.key.mode, KeyMode.major);
        expect(bar(next.score, 0), [
          'F4/quarter',
          'G4/quarter',
          'A4/quarter',
          'Bb4/quarter',
        ]);
        expect(bar(next.score, 1), [
          'C5/quarter',
          'D5/quarter',
          'E5/quarter',
          'F5/quarter',
        ]);
        expect(marked(next.score), isEmpty);
        expect(saved(next.undo().score), saved(session.score));
        expect(next.undo().canUndo, isFalse);
      });

      test('moves the key down with a downward interval', () {
        final session = scale();

        final next = rekeyed(
          session,
          whole(session),
          Transposition.interval(-Interval.perfectFourth),
        );

        expect(fifths(next.score), [1, 1]);
        expect(bar(next.score, 1), [
          'D4/quarter',
          'E4/quarter',
          'F#4/quarter',
          'G4/quarter',
        ]);
        expect(marked(next.score), isEmpty);
      });

      test('writes a key past seven sharps or flats as the one that sounds '
          'the same, and its notes and chord symbols with it', () {
        EditSession from(int key, String pitches, PitchName symbol) {
          var score = sessionWith([
            [
              for (final (i, p) in pitches.split(' ').indexed)
                chordOf(i + 1, p),
            ],
          ]).score;
          score = changeBar(
            withKey(score, 0, key),
            0,
            (column) => column.withStaff(
              column.staves.first.copyWith(
                directions: Seq([ChordSymbol(Moment.zero, root: symbol)]),
              ),
            ),
          );
          return EditSession.start(score);
        }

        PitchName symbol(Score score) =>
            (score.measures[0].staves.first.directions.single as ChordSymbol)
                .root;

        final sharp = from(5, 'B3 C#4 D#4 E4', const PitchName(Step.b));
        final up = rekeyed(
          sharp,
          whole(sharp),
          const Transposition.interval(Interval.majorThird),
        );
        final flat = from(
          -5,
          'Db4 Eb4 F4 Gb4',
          const PitchName(Step.d, Alter.flat),
        );
        final down = rekeyed(
          flat,
          whole(flat),
          Transposition.interval(-Interval.majorThird),
        );

        expect(fifths(up.score), [-3]);
        expect(bar(up.score, 0), [
          'Eb4/quarter',
          'F4/quarter',
          'G4/quarter',
          'Ab4/quarter',
        ]);
        expect(symbol(up.score), const PitchName(Step.e, Alter.flat));
        expect(marked(up.score), isEmpty);
        expect(fifths(down.score), [3]);
        expect(bar(down.score, 0), [
          'A3/quarter',
          'B3/quarter',
          'C#4/quarter',
          'D4/quarter',
        ]);
        expect(symbol(down.score), const PitchName(Step.a));
        expect(marked(down.score), isEmpty);
      });

      test('moves to the nearest key for a chromatic transposition', () {
        final session = scale();

        final next = rekeyed(
          session,
          whole(session),
          const Transposition.chromatic(1),
        );

        expect(fifths(next.score), [-5, -5]);
        expect(bar(next.score, 0), [
          'Db4/quarter',
          'Eb4/quarter',
          'F4/quarter',
          'Gb4/quarter',
        ]);
        expect(marked(next.score), isEmpty);
      });

      test('gives each key and move its new key', () {
        KeySignature after(KeySignature key, Transposition by) {
          final session = EditSession.start(
            fill(blankScore(bars: 1, key: key), 0, [rest(1, NoteValue.whole)]),
          );
          return rekeyed(session, whole(session), by).score.measures[0].key;
        }

        int moved(int key, Transposition by) =>
            after(KeySignature(key), by).fifths;

        expect(moved(0, const Transposition.chromatic(-1)), 5);
        expect(moved(0, const Transposition.chromatic(6)), 6);
        expect(moved(-2, const Transposition.chromatic(8)), -6);
        expect(moved(7, const Transposition.chromatic(12)), 7);
        expect(moved(7, const Transposition.chromatic(-24)), 7);
        expect(moved(-7, const Transposition.chromatic(1)), 0);
        expect(moved(7, const Transposition.interval(Interval(0, 1))), 2);
        expect(moved(4, const Transposition.interval(Interval.octave)), 4);
        expect(moved(4, const Transposition.diatonic(2)), 4);
        expect(
          after(
            const KeySignature(0, KeyMode.minor),
            const Transposition.interval(Interval.minorThird),
          ),
          const KeySignature(-3, KeyMode.minor),
        );
      });

      test('moves only the keys of the bars the range holds whole', () {
        final session = halves(3);
        List<int> keys((int, Moment) from, (int, Moment) to) =>
            fifths(rekeyed(session, range(session, from, to), up).score);

        expect(keys((0, at(1, 2)), (1, at(1, 1))), [0, 2, 0]);
        expect(keys((0, Moment.zero), (2, Moment.zero)), [2, 2, 0]);
        expect(keys((0, Moment.zero), (1, at(1, 2))), [2, 0, 0]);
        expect(keys((1, Moment.zero), (2, at(1, 1))), [0, 2, 2]);
        expect(
          bar(
            rekeyed(
              session,
              range(session, (0, Moment.zero), (1, at(1, 2))),
              up,
            ).score,
            1,
          ),
          ['D4/half', 'C4/half'],
        );
      });

      test('moves a key only when every staff that reads it is in the '
          'range', () {
        final grand = halves(1, parts: const [piano]);
        final kit = halves(1, parts: const [morinKhuur, drums]);
        final hidden = EditSession.start(
          hidePart(
            halves(1, parts: const [morinKhuur, clarinet]).score,
            1,
          ),
        );

        final top = rekeyed(grand, whole(grand), up);

        expect(fifths(top.score), [0]);
        expect(bar(top.score, 0), ['D4/half', 'D4/half']);
        expect(fifths(rekeyed(grand, whole(grand, bottom: 1), up).score), [2]);
        expect(fifths(rekeyed(kit, whole(kit), up).score), [2]);
        expect(fifths(rekeyed(hidden, whole(hidden), up).score), [0]);
        expect(
          fifths(rekeyed(hidden, whole(hidden, bottom: 1), up).score),
          [2],
        );
      });

      test('moves no key for a staff step or for picked items', () {
        final session = scale();
        const step = Transposition.diatonic(1);

        final stepped = rekeyed(session, whole(session), step);
        final picked = rekeyed(session, events(session, [1, 2, 3, 4]), fourth);

        expect(fifths(stepped.score), [0, 0]);
        expect(
          bar(stepped.score, 0),
          bar(transposed(session, whole(session), step).score, 0),
        );
        expect(fifths(picked.score), [0, 0]);
        expect(bar(picked.score, 0), [
          'F4/quarter',
          'G4/quarter',
          'A4/quarter',
          'Bb4/quarter',
        ]);
      });

      test('changes nothing for a unison, and no key for an octave', () {
        final session = scale();

        final octave = rekeyed(
          session,
          whole(session),
          const Transposition.interval(Interval.octave),
        );

        expect(
          changesNothing(
            session,
            Transpose(
              whole(session),
              const Transposition.interval(Interval.unison),
              keys: true,
            ),
          ),
          isTrue,
        );
        expect(fifths(octave.score), [0, 0]);
        expect(bar(octave.score, 0).first, 'C5/quarter');
      });

      test('moves the key of a range with no notes', () {
        final session = sessionWith([
          [rest(1, NoteValue.whole)],
          [rest(2, NoteValue.whole)],
        ]);

        final next = rekeyed(session, whole(session), fourth);

        expect(fifths(next.score), [-1, -1]);
        expect(saved(next.undo().score), saved(session.score));
        expect(next.undo().canUndo, isFalse);
      });

      test('moves a tie chain in the key its first head is in', () {
        final session = sessionWith([
          [
            chordOf(1, 'C4', value: NoteValue.half),
            chordOf(2, 'A4', value: NoteValue.half, tie: true),
          ],
          [
            chordOf(3, 'A4', value: NoteValue.half),
            chordOf(4, 'G4', value: NoteValue.half),
          ],
        ]);

        final next = rekeyed(
          session,
          range(session, (1, Moment.zero), (1, at(1, 1))),
          const Transposition.chromatic(1),
        );

        expect(fifths(next.score), [0, -5]);
        expect(bar(next.score, 0), ['C4/half', 'A#4/half~']);
        expect(bar(next.score, 1), ['A#4/half', 'Ab4/half']);
      });

      test('spells an ornament\'s accidental in the new key', () {
        final session = sessionWith([
          [
            chordOf(1, 'B4', value: NoteValue.whole).copyWith(
              ornament: () => Ornament.turn,
              ornamentAbove: () => Alter.natural,
            ),
          ],
        ]);
        const semitone = Transposition.chromatic(1);

        final kept = transposed(session, whole(session), semitone);
        final moved = rekeyed(session, whole(session), semitone);

        expect(chordIn(kept, 1).ornamentAbove, isNull);
        expect(chordIn(moved, 1).ornamentAbove, Alter.flat);
      });
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

    test('moves an ornament\'s accidentals with the notes they alter', () {
      final session = EditSession.start(
        withKey(
          sessionWith([
            [
              chordOf(1, 'C5', value: NoteValue.whole).copyWith(
                ornament: () => Ornament.turn,
                ornamentAbove: () => Alter.flat,
                ornamentBelow: () => Alter.natural,
              ),
            ],
          ]).score,
          0,
          -3,
        ),
      );
      ChordEvent moved(Transposition by) =>
          chordIn(transposed(session, events(session, [1]), by), 1);

      final second = moved(up);
      final third = moved(const Transposition.interval(Interval.minorThird));

      expect((second.ornamentAbove, second.ornamentBelow), (
        Alter.flat,
        Alter.sharp,
      ));
      expect((third.ornamentAbove, third.ornamentBelow), (
        Alter.flat,
        Alter.natural,
      ));
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
