import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

List<String> spell(
  Meter meter,
  Moment offset,
  Length length, {
  bool rest = false,
}) => [
  for (final value in meter.spell(offset, length, rest: rest)) '$value',
];

const sevenEight = Meter([3, 2, 2], 8);
const twelveEight = Meter([12], 8);

void main() {
  group('beatOffsets', () {
    test('simple meters beat on every unit', () {
      expect(Meter.fourFour.beatOffsets, [
        Moment.zero,
        at(1, 4),
        at(1, 2),
        at(3, 4),
      ]);
      expect(Meter.cut.beatOffsets, [Moment.zero, at(1, 2)]);
    });

    test('compound meters beat on dotted units', () {
      expect(Meter.sixEight.beatOffsets, [Moment.zero, at(3, 8)]);
    });

    test('additive meters beat on each group', () {
      expect(sevenEight.beatOffsets, [Moment.zero, at(3, 8), at(5, 8)]);
    });
  });

  group('spell notes', () {
    test('a dotted half fills three beats from the downbeat', () {
      expect(spell(Meter.fourFour, Moment.zero, len(3, 4)), ['half.']);
    });

    test('three beats from beat two tie a quarter to a half', () {
      expect(spell(Meter.fourFour, at(1, 4), len(3, 4)), ['quarter', 'half']);
    });

    test('a half on beat two does not hide the middle of a 4/4 bar', () {
      expect(spell(Meter.fourFour, at(1, 4), len(1, 2)), [
        'quarter',
        'quarter',
      ]);
    });

    test('a dotted quarter on the downbeat stays whole', () {
      expect(spell(Meter.fourFour, Moment.zero, len(3, 8)), ['quarter.']);
    });

    test('syncopation inside one beat is one value', () {
      expect(spell(Meter.fourFour, at(1, 16), len(1, 8)), ['eighth']);
    });

    test('6/8 splits at the dotted-quarter beat', () {
      expect(spell(Meter.sixEight, Moment.zero, len(1, 2)), [
        'quarter.',
        'eighth',
      ]);
    });

    test('a full 6/8 bar is a dotted half', () {
      expect(spell(Meter.sixEight, Moment.zero, len(3, 4)), ['half.']);
    });

    test('a quarter after an eighth stays inside a 6/8 beat', () {
      expect(spell(Meter.sixEight, at(1, 8), len(1, 4)), ['quarter']);
    });

    test('12/8 covers whole beats before the remainder', () {
      expect(spell(twelveEight, Moment.zero, Length.whole), [
        'half.',
        'quarter',
      ]);
    });

    test('7/8 follows its 3+2+2 grouping', () {
      expect(spell(sevenEight, Moment.zero, len(7, 8)), ['quarter.', 'half']);
    });
  });

  group('spell rests', () {
    test('rests take no dot across a beat in simple meter', () {
      expect(spell(Meter.fourFour, Moment.zero, len(3, 4), rest: true), [
        'half',
        'quarter',
      ]);
    });

    test('rests after beat two start with the beat', () {
      expect(spell(Meter.fourFour, at(1, 4), len(3, 4), rest: true), [
        'quarter',
        'half',
      ]);
    });

    test('an offbeat rest fills to the beat first', () {
      expect(spell(Meter.fourFour, at(1, 8), len(3, 8), rest: true), [
        'eighth',
        'quarter',
      ]);
    });
  });

  test('every spelling sums to the length and fits the grid', () {
    const step = 32;
    for (final meter in [
      Meter.fourFour,
      Meter.threeFour,
      Meter.sixEight,
      sevenEight,
    ]) {
      final slots = (meter.length / len(1, step)).numerator;
      for (var start = 0; start < slots; start++) {
        for (var end = start + 1; end <= slots; end++) {
          for (final rest in [false, true]) {
            final offset = at(start, step);
            final length = len(end - start, step);
            final values = meter.spell(offset, length, rest: rest);
            expect(
              Length.sum(values.map((v) => v.length)),
              length,
              reason: '$meter from $start/$step for ${end - start}/$step',
            );
            expect(values.every((v) => v.dots <= 1), isTrue);
          }
        }
      }
    }
  });

  test('a length no note value can write is an error', () {
    expect(
      () => Meter.fourFour.spell(Moment.zero, len(1, 12), rest: false),
      throwsArgumentError,
    );
  });
}
