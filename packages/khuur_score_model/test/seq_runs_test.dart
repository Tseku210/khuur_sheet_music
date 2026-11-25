import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:khuur_score_model/src/seq.dart' show SeqRuns;
import 'package:test/test.dart';

void main() {
  group('a Seq in runs', () {
    // 4 and 16 fill their runs exactly, the others end in a shorter run.
    for (final length in [1, 2, 3, 4, 5, 7, 16, 17, 100]) {
      final items = [for (var i = 0; i < length; i++) i * 10];
      final plain = Seq(items);
      final runs = plain.inRuns;
      final where = 'length $length';

      test('reads as the same sequence, $where', () {
        expect(runs.toList(), items);
        expect(runs.length, length);
        expect(runs.isEmpty, isFalse);
        expect(runs.first, items.first);
        expect(runs.last, items.last);
        for (var i = 0; i < length; i++) {
          expect(runs[i], items[i]);
          expect(runs.elementAt(i), items[i]);
        }
        expect(() => runs[length], throwsRangeError);
        expect(() => runs[-1], throwsRangeError);
        expect(runs.indexWhere((x) => x == items.last), length - 1);
        expect(runs.indexWhere((x) => x < 0), -1);
        expect(runs.inRuns, same(runs));
        expect(runs.flat.toList(), items);
        expect(plain.flat, same(plain));
      });

      test('copies as the same sequence would, $where', () {
        for (var i = 0; i < length; i++) {
          expect(runs.replaceAt(i, -1).toList(), plain.replaceAt(i, -1));
          expect(runs.insertAt(i, -1).toList(), plain.insertAt(i, -1));
          expect(runs.removeAt(i).toList(), plain.removeAt(i));
          expect(
            runs.insertAllAt(i, [-1, -2]).toList(),
            plain.insertAllAt(i, [-1, -2]),
          );
          expect(
            runs.replaceRange(i, length, [-1]).toList(),
            plain.replaceRange(i, length, [-1]),
          );
        }
        expect(runs.append(-1).toList(), plain.append(-1));
        expect(runs.toList(), items, reason: 'a copy leaves it as it was');
      });

      test('replaces many items at once, $where', () {
        final values = {0: -1, length ~/ 2: -2, length - 1: -3};
        final expected = [...items];
        values.forEach((i, value) => expected[i] = value);

        expect(runs.replacingEach(values).toList(), expected);
        expect(plain.replacingEach(values).toList(), expected);
        expect(runs.replacingEach(values).replaceAt(0, 7).first, 7);
        expect(runs.toList(), items);
        expect(() => runs.replacingEach({length: 0}), throwsRangeError);
      });
    }

    test('is equal only to itself', () {
      final plain = Seq([1, 2, 3]);

      expect(plain.inRuns == plain, isFalse);
      expect(plain.inRuns == plain.inRuns, isFalse);
      expect(plain.inRuns.replacingEach({}), isNot(same(plain)));
    });
  });
}
