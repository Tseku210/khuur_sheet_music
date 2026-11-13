import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

List<int> numbers(Score score) => [
  for (final column in score.measures) score.barNumberOf(column.id),
];

/// [score] with its bar [bar], counted from 0, made [length] long.
Score withBarLength(Score score, int bar, Length length) => applied(
  EditSession.start(score).run(SetBarLength(score.measures[bar].id, length)),
).score;

const jumps = [
  (Jump(JumpTarget.start), 'D.C.'),
  (Jump(JumpTarget.start, then: JumpThen.toFine), 'D.C. al Fine'),
  (Jump(JumpTarget.start, then: JumpThen.toCoda), 'D.C. al Coda'),
  (Jump(JumpTarget.segno), 'D.S.'),
  (Jump(JumpTarget.segno, then: JumpThen.toFine), 'D.S. al Fine'),
  (Jump(JumpTarget.segno, then: JumpThen.toCoda), 'D.S. al Coda'),
  (Jump(JumpTarget.segno, then: JumpThen.toCoda, text: 'Da capo'), 'Da capo'),
];

void main() {
  group('Score.barNumberOf', () {
    test('counts from 1', () {
      expect(numbers(blankScore(bars: 3)), [1, 2, 3]);
    });

    test('numbers a pickup 0 and the bars after it from 1', () {
      final score = withBarLength(blankScore(bars: 3), 0, len(1, 4));

      expect(numbers(score), [0, 1, 2]);
    });

    test('takes only a short first bar for a pickup', () {
      final shortLater = withBarLength(blankScore(bars: 3), 1, len(1, 4));
      final longFirst = withBarLength(blankScore(bars: 3), 0, len(5, 4));

      expect(numbers(shortLater), [1, 2, 3]);
      expect(numbers(longFirst), [1, 2, 3]);
    });

    test('refuses a bar the score lacks', () {
      expect(
        () => blankScore().barNumberOf(const MeasureId(999)),
        throwsArgumentError,
      );
    });
  });

  group('Jump.label', () {
    test('names where the jump goes and where it then ends, or is its '
        'own text', () {
      expect(
        [for (final (jump, _) in jumps) jump.label],
        [for (final (_, label) in jumps) label],
      );
    });
  });
}
