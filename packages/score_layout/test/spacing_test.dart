import 'package:score_layout/src/spacing.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/bars.dart';

void main() {
  group('stretchFor and sliceXs', () {
    final slices = [
      Slice(at: at(0, 1), ideal: 2, rod: 1),
      Slice(at: at(1, 4), ideal: 4, rod: 3),
      Slice(at: at(1, 1), ideal: 0, rod: 0.5),
    ];
    double widthAt(double stretch) =>
        sliceXs(slices, stretch, 0).last + slices.last.rod;

    test('the stretch makes the slices exactly as wide as the room', () {
      for (final room in [5.2, 6.0, 10.0]) {
        expect(widthAt(stretchFor(slices, room)), closeTo(room, 1e-9));
      }
      expect(stretchFor(slices, 10), closeTo(9.5 / 6, 1e-9));
    });

    test('a slice on its rod keeps it while the others stretch', () {
      final stretch = stretchFor(slices, 4.8);
      expect(stretch, closeTo(0.65, 1e-9));
      expect(sliceXs(slices, stretch, 0), [0, closeTo(1.3, 1e-9), 4.3]);
      expect(widthAt(stretch), closeTo(4.8, 1e-9));
    });

    test('rods alone that fill the room give stretch 0', () {
      expect(stretchFor(slices, 4), 0);
      expect(stretchFor(slices, 4.5), 0);
      expect(sliceXs(slices, 0, 2), [2, 3, 6]);
    });

    test('natural width takes the larger of rod and ideal', () {
      expect(naturalWidth(slices), 2 + 4 + 0.5);
      expect(rodWidth(slices), 4.5);
    });
  });

  group('sliceTimes', () {
    test('every onset of every staff and voice, then the bar end', () {
      final view = viewOf(
        scoreOf([
          [
            staffOf(
              [
                chordOf(1, 'C4'),
                chordOf(2, 'D4', value: eighth),
                chordOf(3, 'E4', value: eighth),
                chordOf(4, 'F4', value: half),
              ],
              two: [
                chordOf(5, 'A3', value: dottedHalf),
                chordOf(6, 'G3'),
              ],
            ),
            staffOf([chordOf(7, 'C3', value: whole)], clef: Clef.bass),
          ],
        ]),
      );

      expect(sliceTimes(view), [
        at(0, 1),
        at(1, 4),
        at(3, 8),
        at(1, 2),
        at(3, 4),
        at(1, 1),
      ]);
    });

    test('a grace chord takes no slice', () {
      final view = barOf([
        chordOf(1, 'C4', graces: [graceOf(2, 'B3')]),
        chordOf(3, 'D4', value: dottedHalf),
      ]);

      expect(sliceTimes(view), [at(0, 1), at(1, 4), at(1, 1)]);
    });
  });

  group('spaceSlices', () {
    const policy = SpacingPolicy();
    List<Slice> space(MeasureView view) {
      final times = sliceTimes(view);
      final reach = List.filled(times.length, noReach);
      return spaceSlices(view, times, reach, policy, end: 0.16);
    }

    test('a quarter gets more room than an eighth and less than twice it', () {
      final slices = space(
        barOf([
          chordOf(1, 'C4'),
          chordOf(2, 'D4', value: eighth),
          chordOf(3, 'E4', value: eighth),
          chordOf(4, 'F4', value: half),
        ]),
      );
      final afterQuarter = slices[0].ideal;
      final afterEighth = slices[1].ideal;

      expect(afterQuarter, policy.quarterSpace);
      expect(afterQuarter, greaterThan(afterEighth));
      expect(afterQuarter, lessThan(2 * afterEighth));
      expect(slices[2].ideal, afterEighth);
      expect(
        slices[3].ideal,
        closeTo(policy.quarterSpace * policy.ratio, 1e-9),
      );
    });

    test('the shortest starting note decides, cut to the next slice', () {
      final view = barOf(
        [chordOf(1, 'C5', value: half), chordOf(2, 'D5', value: half)],
        two: [
          Gap(DurationBase.quarter.length),
          chordOf(3, 'E4'),
          chordOf(4, 'F4', value: half),
        ],
      );
      final slices = space(view);
      final halfSpace = slices[2].ideal;

      expect(slices.map((s) => s.at), [at(0, 1), at(1, 4), at(1, 2), at(1, 1)]);
      expect(halfSpace, closeTo(policy.quarterSpace * policy.ratio, 1e-9));
      expect(slices[0].ideal, closeTo(halfSpace / 2, 1e-9));
      expect(slices[1].ideal, closeTo(policy.quarterSpace, 1e-9));
    });

    test(
      'a rod keeps neighbouring reach apart and the last slice is the barline',
      () {
        final view = barOf([chordOf(1, 'C4', value: whole)]);
        final times = sliceTimes(view);
        final slices = spaceSlices(
          view,
          times,
          [(left: 1, right: 2), (left: 0.5, right: 0)],
          policy,
          end: 0.16,
        );

        expect(slices[0].rod, 2 + policy.minGap + 0.5);
        expect(slices.last, Slice(at: at(1, 1), ideal: 0, rod: 0.16));
      },
    );
  });
}
