import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Each bar's clefs on [staff]: the opening clef, then `offset clef` for
/// each change inside the bar.
List<String> clefLine(Score score, {int staff = 0}) => [
  for (final column in score.measures)
    [
      column.staves[staff].clef.name,
      for (final change in column.staves[staff].clefChanges)
        '${change.offset.wholeNotes} ${change.clef.name}',
    ].join(', '),
];

/// [score] with bar [bar] opening in [clef] on the first staff, with
/// [changes] inside it.
Score withClefs(
  Score score,
  int bar,
  Clef clef, [
  List<ClefChange> changes = const [],
]) => changeBar(
  score,
  bar,
  (c) => c.withStaff(
    c.staves.first.copyWith(clef: clef, clefChanges: Seq(changes)),
  ),
);

EditOutcome setClef(
  Score score,
  int bar,
  Moment offset,
  Clef clef, {
  int staff = 0,
}) => EditSession.start(score).run(
  SetClef(
    staff: score.staves[staff].id,
    at: pointAt(score, bar, offset),
    clef: clef,
  ),
);

Score clefSet(
  Score score,
  int bar,
  Moment offset,
  Clef clef, {
  int staff = 0,
}) => applied(setClef(score, bar, offset, clef, staff: staff)).score;

void main() {
  group('SetKey', () {
    test('refuses a bar that is gone', () {
      final session = blank();

      expect(
        refusal(
          session.run(
            const SetKey(from: MeasureId(999), key: KeySignature(2)),
          ),
        ),
        isA<StaleReference>().having(
          (r) => r.target,
          'target',
          const MeasureId(999),
        ),
      );
    });
  });

  group('SetClef at the start of a bar', () {
    test('replaces the clef up to the next clef change', () {
      final score = withClefs(
        withClefs(blankScore(bars: 4), 2, Clef.bass),
        3,
        Clef.bass,
      );

      final next = clefSet(score, 0, Moment.zero, Clef.alto);

      expect(clefLine(next), ['alto', 'alto', 'bass', 'bass']);
    });

    test('stops at a change inside a bar', () {
      var score = withClefs(blankScore(bars: 3), 1, Clef.treble, [
        ClefChange(at(1, 2), Clef.bass),
      ]);
      score = withClefs(score, 2, Clef.bass);

      final next = clefSet(score, 0, Moment.zero, Clef.alto);

      expect(clefLine(next), ['alto', 'alto, 1/2 bass', 'bass']);
    });

    test('stops after a bar that ends in the clef it ended in before', () {
      var score = withClefs(blankScore(bars: 3), 1, Clef.treble, [
        ClefChange(at(1, 4), Clef.bass),
        ClefChange(at(1, 2), Clef.treble),
      ]);
      score = withClefs(score, 2, Clef.treble);

      final next = clefSet(score, 0, Moment.zero, Clef.alto);

      expect(clefLine(next), [
        'alto',
        'alto, 1/4 bass, 1/2 treble',
        'treble',
      ]);
      expect(identical(next.measures[2], score.measures[2]), isTrue);
    });

    test('drops a change inside the bar that it makes redundant', () {
      var score = withClefs(blankScore(), 0, Clef.treble, [
        ClefChange(at(1, 2), Clef.bass),
      ]);
      score = withClefs(score, 1, Clef.bass);

      final next = clefSet(score, 0, Moment.zero, Clef.bass);

      expect(clefLine(next), ['bass', 'bass']);
      expect(identical(next.measures[1], score.measures[1]), isTrue);
    });

    test('changes only the staff it names', () {
      final score = blankScore(parts: const [piano]);

      final next = clefSet(score, 0, Moment.zero, Clef.tenor, staff: 1);

      expect(clefLine(next), ['treble', 'treble']);
      expect(clefLine(next, staff: 1), ['tenor', 'tenor']);
    });

    test('keeps the notes as they are', () {
      final score = fill(blankScore(), 0, [
        chordOf(20, 'F4', value: NoteValue.whole),
      ]);

      final next = clefSet(score, 0, Moment.zero, Clef.bass);

      expect(
        identical(
          next.measures[0].staves.first.voices,
          score.measures[0].staves.first.voices,
        ),
        isTrue,
      );
    });

    test('changes nothing for the clef already there', () {
      final score = blankScore();

      final outcome = setClef(score, 0, Moment.zero, Clef.treble);

      expect(identical(applied(outcome).score, score), isTrue);
    });
  });

  group('SetClef inside a bar', () {
    test('adds a change and carries the new clef on', () {
      final next = clefSet(blankScore(bars: 3), 0, at(1, 2), Clef.bass);

      expect(clefLine(next), ['treble, 1/2 bass', 'bass', 'bass']);
    });

    test('carries nothing on before a later change in the bar', () {
      var score = withClefs(blankScore(), 0, Clef.treble, [
        ClefChange(at(3, 4), Clef.alto),
      ]);
      score = withClefs(score, 1, Clef.alto);

      final next = clefSet(score, 0, at(1, 4), Clef.bass);

      expect(clefLine(next), ['treble, 1/4 bass, 3/4 alto', 'alto']);
    });

    test('replaces a change at the same time', () {
      var score = withClefs(blankScore(), 0, Clef.treble, [
        ClefChange(at(1, 2), Clef.bass),
      ]);
      score = withClefs(score, 1, Clef.bass);

      final next = clefSet(score, 0, at(1, 2), Clef.alto);

      expect(clefLine(next), ['treble, 1/2 alto', 'alto']);
    });

    test('removes a change when set to the clef before it', () {
      var score = withClefs(blankScore(), 0, Clef.treble, [
        ClefChange(at(1, 4), Clef.bass),
        ClefChange(at(1, 2), Clef.treble),
        ClefChange(at(3, 4), Clef.alto),
      ]);
      score = withClefs(score, 1, Clef.alto);

      final next = clefSet(score, 0, at(1, 4), Clef.treble);

      expect(clefLine(next), ['treble, 3/4 alto', 'alto']);
    });

    test('drops a later change that it makes redundant', () {
      var score = withClefs(blankScore(), 0, Clef.treble, [
        ClefChange(at(1, 2), Clef.bass),
      ]);
      score = withClefs(score, 1, Clef.bass);

      final next = clefSet(score, 0, at(1, 4), Clef.bass);

      expect(clefLine(next), ['treble, 1/4 bass', 'bass']);
    });

    test('changes nothing for the clef already in effect', () {
      final score = blankScore();

      final outcome = setClef(score, 0, at(1, 2), Clef.treble);

      expect(identical(applied(outcome).score, score), isTrue);
    });

    test('changes nothing for a change that is already there', () {
      var score = withClefs(blankScore(), 0, Clef.treble, [
        ClefChange(at(1, 2), Clef.bass),
      ]);
      score = withClefs(score, 1, Clef.bass);

      final outcome = setClef(score, 0, at(1, 2), Clef.bass);

      expect(identical(applied(outcome).score, score), isTrue);
    });
  });

  group('SetClef refuses', () {
    test('a bar that is gone', () {
      final score = blankScore();

      final outcome = EditSession.start(score).run(
        SetClef(
          staff: score.staves.first.id,
          at: const ScorePoint(MeasureId(999), Moment.zero),
          clef: Clef.bass,
        ),
      );

      expect(
        refusal(outcome),
        isA<StaleReference>().having(
          (r) => r.target,
          'target',
          const MeasureId(999),
        ),
      );
    });

    test('a staff that is gone', () {
      final score = blankScore();

      final outcome = EditSession.start(score).run(
        SetClef(
          staff: const StaffId(999),
          at: pointAt(score, 0, Moment.zero),
          clef: Clef.bass,
        ),
      );

      expect(
        refusal(outcome),
        isA<StaleReference>().having(
          (r) => r.target,
          'target',
          const StaffId(999),
        ),
      );
    });

    test('a time outside the bar', () {
      final score = blankScore(meter: Meter.threeFour);

      for (final offset in [at(3, 4), Moment(Fraction(-1, 4))]) {
        expect(
          refusal(setClef(score, 0, offset, Clef.bass)),
          isA<OutsideMeasure>().having(
            (r) => r.at,
            'at',
            pointAt(score, 0, offset),
          ),
        );
      }
    });
  });

  group('SetTempoMarks', () {
    const adagio = TempoMark(
      offset: Moment.zero,
      tempo: Tempo(60),
      text: 'Adagio',
    );
    final faster = TempoMark(offset: at(1, 2), tempo: const Tempo(90));

    EditOutcome setTempos(Score score, int bar, List<TempoMark> marks) =>
        EditSession.start(
          score,
        ).run(SetTempoMarks(score.measures[bar].id, Seq(marks)));

    test('replaces the marks of one bar, in time order', () {
      final score = blankScore();

      final next = applied(setTempos(score, 1, [faster, adagio])).score;

      expect(
        [for (final t in next.measures[1].tempos) t],
        [adagio, faster],
      );
      expect(identical(next.measures[0], score.measures[0]), isTrue);
    });

    test('changes nothing for equal marks', () {
      final score = applied(setTempos(blankScore(), 0, [adagio])).score;

      final outcome = setTempos(score, 0, [
        TempoMark(offset: at(0, 4), tempo: const Tempo(60), text: 'Adagio'),
      ]);

      expect(identical(applied(outcome).score, score), isTrue);
    });

    test('replaces a mark that differs only in its metronome', () {
      final score = applied(setTempos(blankScore(), 0, [adagio])).score;

      final next = applied(
        setTempos(score, 0, [
          const TempoMark(
            offset: Moment.zero,
            tempo: Tempo(60),
            text: 'Adagio',
            showMetronome: false,
          ),
        ]),
      ).score;

      expect(next.measures[0].tempos.single.showMetronome, isFalse);
    });

    test('refuses a mark outside the bar', () {
      final score = blankScore(meter: Meter.threeFour);
      final late = TempoMark(offset: at(3, 4), tempo: const Tempo(90));

      expect(
        refusal(setTempos(score, 0, [adagio, late])),
        isA<OutsideMeasure>().having(
          (r) => r.at,
          'at',
          pointAt(score, 0, at(3, 4)),
        ),
      );
    });

    test('refuses two marks at one time', () {
      final score = blankScore();

      expect(
        refusal(
          setTempos(score, 0, [
            adagio,
            const TempoMark(offset: Moment.zero, tempo: Tempo(90)),
          ]),
        ),
        isA<InvalidValue>(),
      );
    });

    test('refuses a bar that is gone', () {
      final outcome = EditSession.start(blankScore()).run(
        SetTempoMarks(const MeasureId(999), Seq([adagio])),
      );

      expect(refusal(outcome), isA<StaleReference>());
    });
  });
}
