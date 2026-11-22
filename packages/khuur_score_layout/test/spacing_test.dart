import 'package:khuur_score_layout/src/sheet_layout.dart';
import 'package:khuur_score_layout/src/spacing.dart';
import 'package:khuur_score_layout/src/style.dart';
import 'package:khuur_score_layout/src/system_layout.dart';
import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'support/bars.dart';
import 'support/fake_measurer.dart';

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

  group('fitXs', () {
    final slices = [
      Slice(at: at(0, 1), ideal: 4, rod: 3, pad: 1, left: 0.5, right: 1),
      Slice(at: at(1, 4), ideal: 4, rod: 3, pad: 1, left: 1, right: 1.5),
      Slice(at: at(1, 2), ideal: 4, rod: 2.5, pad: 1, right: 1.5),
      Slice(at: at(1, 1), ideal: 0, rod: 0.5),
    ];
    const lead = 1.5;
    List<double> xsAt(Fit fit, {double markRoom = 0}) =>
        fitXs(slices, fit, 10, lead: lead, markRoom: markRoom);
    double widthAt(Fit fit, {double markRoom = 0}) =>
        squeezedWidth(slices, fit, lead: lead, markRoom: markRoom);

    test('a stretched unit is its slices from the end of its lead', () {
      for (final stretch in [0.0, 1.0, 1.7]) {
        expect(
          xsAt(Fit.stretched(stretch)),
          sliceXs(slices, stretch, 10 + lead),
        );
      }
    });

    test('a unit that gives up half its padding keeps its lead and loses '
        'half a pad from each rod', () {
      const fit = Fit.squeezed(pad: 0.5, crush: 1);

      expect(xsAt(fit), [11.5, 14, 16.5, 18.5]);
      expect(widthAt(fit), 8.5);
    });

    test('a crushed unit scales every gap by one factor, keeps its last '
        'reach whole and ends at its width from its head', () {
      const fit = Fit.squeezed(pad: 0, crush: 0.8);

      expect(widthAt(fit), closeTo(lead + 0.8 * 4 + 1.5, 1e-9));
      expect(xsAt(fit), [
        11.5,
        closeTo(11.5 + 0.8 * 2, 1e-9),
        closeTo(11.5 + 0.8 * 4, 1e-9),
        closeTo(10 + widthAt(fit), 1e-9),
      ]);
    });

    test('however hard a unit is crushed, its slices stay in order, each '
        'on its own x, and none reaches out of it', () {
      for (final crush in [0.9, 0.5, 0.1, 0.01]) {
        final fit = Fit.squeezed(pad: 0, crush: crush);
        final xs = xsAt(fit);

        expect(xs.first, 10 + lead);
        expect(xs.last, 10 + widthAt(fit));
        for (final (index, slice) in slices.indexed) {
          expect(xs[index] - slice.left, greaterThanOrEqualTo(10));
          expect(xs[index] + slice.right, lessThanOrEqualTo(xs.last));
          if (index > 0 && index < slices.length - 1) {
            expect(xs[index], greaterThan(xs[index - 1]));
          }
        }
      }
    });

    test('a unit crushed to nothing is as wide as its lead and its widest '
        'reach', () {
      expect(widthAt(const Fit.squeezed(pad: 0, crush: 0)), lead + 1.5);
    });

    test('a slice that reaches far left is held clear of the head, and the '
        'slices after it follow it', () {
      final wide = [
        slices[0],
        Slice(at: at(1, 4), ideal: 4, rod: 3, pad: 1, left: 4, right: 1),
        ...slices.skip(2),
      ];
      final xs = fitXs(
        wide,
        const Fit.squeezed(pad: 0, crush: 0.1),
        10,
        lead: lead,
        markRoom: 0,
      );

      expect(xs[1], 14);
      expect(xs[2], closeTo(14.2, 1e-9));
      expect(xs.last, closeTo(15.7, 1e-9));
    });

    test('a mark wider than the crushed slices widens the unit and moves '
        'no slice', () {
      const fit = Fit.squeezed(pad: 0, crush: 0.8);

      expect(widthAt(fit, markRoom: 9), lead + 9);
      expect(xsAt(fit, markRoom: 9), [
        ...xsAt(fit).take(3),
        10 + lead + 9,
      ]);
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
        expect(
          slices.first,
          Slice(
            at: at(0, 1),
            ideal: slices.first.ideal,
            rod: 2 + policy.minGap + 0.5,
            pad: policy.minGap,
            left: 1,
            right: 2,
          ),
        );
        expect(
          slices.last,
          Slice(at: at(1, 1), ideal: 0, rod: 0.16, left: 0.5),
        );
      },
    );
  });

  group('a bar that holds only a bar rest', () {
    /// A justified system of a bar of beats, a bar rest and a bar of beats
    /// again, every beat a note of [meter]'s lower number, before a system
    /// of one more bar of beats.
    SystemLayout restBetweenBeats(Meter meter) {
      final value = NoteValue(
        DurationBase.values.firstWhere(
          (base) => base.length == Length(Fraction(1, meter.unit)),
        ),
      );
      StaffSpec beats(int bar) => staffOf([
        for (var k = 0; k < meter.numerator; k++)
          chordOf(bar * 20 + k + 1, 'B4', value: value),
      ]);
      final score = after(
        scoreOf([
          [beats(0)],
          [
            staffOf([MeasureRest(id: const EventId(19), span: meter.length)]),
          ],
          [beats(2)],
          [beats(3)],
        ], meter: meter),
        [SetBreak(barId(3), LayoutBreak.system)],
      );
      final layout = SheetLayout(score, width: 80, text: const FakeMeasurer());
      expect(layout.systemCount, 2);
      return layout.systemAt(0);
    }

    for (final meter in [Meter.fourFour, Meter.sixEight]) {
      test('in ${meter.numerator}/${meter.unit} takes the room and spaces the '
          'time of the bar filled with its beats', () {
        final system = restBetweenBeats(meter);
        final rest = system.barOf(barId(1))!;
        final beats = system.barOf(barId(2))!;

        expect(
          rest.right - rest.left,
          closeTo(beats.right - beats.left, 1e-9),
        );
        for (var k = 0; k <= meter.numerator; k++) {
          final offset = at(k, meter.unit);
          expect(
            rest.time.xAt(offset) - rest.left,
            closeTo(beats.time.xAt(offset) - beats.left, 1e-9),
          );
        }
      });
    }
  });
}
