import 'dart:math';

import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/bar_space.dart';
import 'package:score_layout/src/beams.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/spacing.dart';
import 'package:score_layout/src/style.dart';
import 'package:test/test.dart';

import '../../score_model/test/random_edits.dart';
import '../../score_model/test/support.dart';
import 'support/fake_measurer.dart';

const EngravingStyle style = EngravingStyle.standard;

bool finite(Box box) =>
    box.left.isFinite &&
    box.top.isFinite &&
    box.right.isFinite &&
    box.bottom.isFinite;

void main() {
  test('every bar of seeded random scores lays out, with finite boxes and '
      'slices in time order', () {
    for (final seed in [1, 2, 3, 4, 5, 6]) {
      final random = Random(seed);
      var score = blankScore(parts: const [clarinet, piano, drums], bars: 4);
      for (var step = 0; step < 150; step++) {
        final before = score;
        score = randomEdit(before, random);
        for (final id in score.changesSince(before).relayout) {
          final where = 'seed $seed, step $step, bar ${score.indexOf(id)}';
          final layout = layoutBar(
            score.measureView(id),
            style,
            const FakeMeasurer(),
          );

          for (final stretch in [1.0, 3.0]) {
            final xs = sliceXs(layout.slices, stretch, layout.lead);
            for (var i = 1; i < xs.length; i++) {
              expect(xs[i], greaterThan(xs[i - 1]), reason: '$where, slice $i');
            }
            final frame = BarFrame(
              left: 0,
              xs: xs,
              tops: [for (final (i, _) in layout.staves.indexed) i * 20.0],
            );
            for (final item in layout.items) {
              expect(finite(frame.place(item).bounds), isTrue, reason: where);
            }
            for (final beam in layout.beams) {
              for (final drawable in placeBeam(beam, frame, style)) {
                expect(finite(drawable.bounds), isTrue, reason: where);
              }
            }
          }
          expect(
            layout.widths.body,
            greaterThanOrEqualTo(layout.widths.minBody),
            reason: where,
          );
        }
      }
    }
  });
}
