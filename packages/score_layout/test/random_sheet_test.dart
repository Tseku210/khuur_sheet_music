import 'dart:math';

import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/random_edits.dart';
import '../../score_model/test/support.dart';
import 'support/fake_measurer.dart';
import 'support/sheets.dart';

const seeds = [1, 2, 3, 4, 5, 6, 7, 8];
const edits = 400;
const text = FakeMeasurer();

/// Narrow enough at its least to press a system to its rods, where a bar
/// is laid out at stretch 0.
double randomWidth(Random random) => 12 + 138 * random.nextDouble();

void walk(
  EngravingStyle style,
  void Function(SheetLayout layout, Score score, double width) check,
) {
  for (final seed in seeds) {
    final random = Random(seed);
    var score = blankScore(parts: const [clarinet, piano, drums], bars: 24);
    var width = randomWidth(random);
    var layout = SheetLayout(score, width: width, text: text, style: style);

    for (var step = 0; step < edits; step++) {
      score = randomEdit(score, random);
      if (random.nextInt(3) == 0) {
        final id = score.measures[random.nextInt(score.measures.length)].id;
        score = edited(
          score,
          pick(random, [
            SetKey(from: id, key: KeySignature(random.nextInt(9) - 4)),
            SetKeyDisplay(id, pick(random, SignatureDisplay.values)),
            SetMeterDisplay(id, pick(random, SignatureDisplay.values)),
          ]),
        );
      }
      if (random.nextInt(25) == 0) {
        width = randomWidth(random);
      }
      layout = layout.update(score, width: width);
      check(layout, score, width);
    }
  }
}

void main() {
  for (final rests in [false, true]) {
    final style = EngravingStyle(multiMeasureRests: rests);
    final walked =
        'over seeded random edits and sheet widths, with multi-measure '
        'rests ${rests ? 'on' : 'off'}';

    test('an updated sheet equals a fresh one in header, tops, starts, bar '
        'numbers and drawables, $walked', () {
      var systems = 0;
      var kept = 0;
      var ties = 0;
      var voltaBars = 0;
      final spanners = <Type, int>{};

      walk(style, (layout, score, width) {
        expectSameSheet(
          layout,
          SheetLayout(score, width: width, text: text, style: style),
        );
        systems += layout.systemCount;
        kept += layout.systemCount - layout.delta.rekeyed.length;
        for (final measure in score.measures) {
          final view = score.measureView(measure.id);
          ties += view.staves.fold(0, (n, staff) => n + staff.ties.length);
          if (measure.volta != null) {
            voltaBars++;
          }
        }
        for (final spanner in score.spanners) {
          spanners.update(
            spanner.kind.runtimeType,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
      });

      expect(systems, greaterThan(seeds.length * edits));
      expect(kept, greaterThan(0));
      expect(ties, greaterThan(0));
      expect(voltaBars, greaterThan(0));
      for (final kind in [
        Slur,
        Hairpin,
        OctaveLine,
        PedalLine,
        TrillLine,
        TempoLine,
        Glissando,
      ]) {
        expect(spanners[kind], greaterThan(0), reason: '$kind');
      }
    });

    test('every drawable and bar number of every system stays inside its '
        'band, $walked', () {
      walk(style, (layout, _, _) => expectInsideBands(layout));
    });
  }
}
