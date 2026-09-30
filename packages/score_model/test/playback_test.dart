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

  group('timing', () {
    test('times bars at 100 quarters a minute before any tempo mark', () {
      final script = compiled(blankScore());

      expect(timings(blankScore()), [(0.0, 2.4), (2.4, 4.8)]);
      expect(script.totalSeconds, closeTo(4.8, 1e-9));
    });

    test('changes tempo at each mark, mid-bar included', () {
      final score = marked(2, {
        1: tempos([
          const TempoMark(
            offset: Moment.zero,
            tempo: Tempo(60, beat: NoteValue.half),
          ),
          TempoMark(offset: at(1, 2), tempo: const Tempo(150)),
        ]),
        2: tempos([TempoMark(offset: at(1, 2), tempo: const Tempo(75))]),
      });

      expect(timings(score), [(0.0, 1.8), (1.8, 4.2)]);
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
