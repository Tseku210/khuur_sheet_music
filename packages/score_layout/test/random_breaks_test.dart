import 'dart:math';

import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/breaking.dart';
import 'package:score_layout/src/signatures.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/random_edits.dart';
import '../../score_model/test/support.dart';
import 'support/fake_measurer.dart';

const seeds = [1, 2, 3, 4, 5, 6, 7, 8];
const edits = 400;

void main() {
  for (final rests in [false, true]) {
    test('breaking resumed from the breaks before equals breaking afresh, '
        'over seeded random edits and sheet widths, with multi-measure rests '
        '${rests ? 'on' : 'off'}', () {
      final style = EngravingStyle(multiMeasureRests: rests);
      const text = FakeMeasurer();
      var kept = 0;
      var resumed = 0;
      var restarted = 0;
      var runs = 0;

      for (final seed in seeds) {
        final random = Random(seed);
        var score = blankScore(parts: const [clarinet, piano, drums], bars: 24);
        var lead = systemLead(score, style, text);
        var width = 40 + 110 * random.nextDouble();
        final cache = {
          for (final column in score.measures)
            column.id: layoutBar(score.measureView(column.id), style, text),
        };
        Breaks? previous;

        for (var step = 0; step < edits; step++) {
          final before = score;
          score = randomEdit(before, random);
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
          final changes = score.changesSince(before);
          changes.removed.forEach(cache.remove);
          for (final id in changes.relayout) {
            cache[id] = layoutBar(score.measureView(id), style, text);
          }
          if (!identical(score.parts, before.parts)) {
            lead = systemLead(score, style, text);
          }
          if (random.nextInt(25) == 0) {
            width = 40 + 110 * random.nextDouble();
          }
          final bars = [for (final column in score.measures) cache[column.id]!];

          final again = breakSystems(
            bars: bars,
            width: width,
            lead: lead,
            style: style,
            text: text,
            previous: previous,
          );
          final fresh = breakSystems(
            bars: bars,
            width: width,
            lead: lead,
            style: style,
            text: text,
          );

          final where = 'seed $seed, step $step, width $width';
          expect(again.starts, fresh.starts, reason: where);
          expect(
            [for (final plan in again.plans) plan.key],
            [for (final plan in fresh.plans) plan.key],
            reason: where,
          );
          expect(
            [for (final plan in again.plans) plan.stretch],
            [for (final plan in fresh.plans) plan.stretch],
            reason: where,
          );
          expect(
            [for (final plan in again.plans) plan.height],
            [for (final plan in fresh.plans) plan.height],
            reason: where,
          );

          if (previous != null) {
            if (identical(again.starts, previous.starts)) {
              kept++;
            } else if (previous.width == width &&
                identical(previous.lead, lead)) {
              resumed++;
            } else {
              restarted++;
            }
          }
          runs += again.units.whereType<RestRun>().length;
          previous = again;
        }
      }

      expect(kept, greaterThan(seeds.length * edits ~/ 4));
      expect(resumed, greaterThan(seeds.length * edits ~/ 10));
      expect(restarted, greaterThan(seeds.length * 4));
      expect(runs, rests ? greaterThan(seeds.length * edits ~/ 4) : 0);
    });
  }
}
