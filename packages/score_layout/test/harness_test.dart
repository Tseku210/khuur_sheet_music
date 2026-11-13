import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/harness.dart';

const Duration ms = Duration(milliseconds: 1);

Measurement measured(String name, Duration median, {Duration? budget}) =>
    Measurement(name: name, bars: 500, median: median, budget: budget);

void main() {
  test('the median is the middle run, whatever order they came in', () {
    expect(medianOf([ms * 9, ms * 2, ms * 40, ms * 3, ms * 5]), ms * 5);
  });

  test('the median of an even count is the mean of the two middle runs', () {
    expect(medianOf([ms * 8, ms * 2, ms * 100, ms * 4]), ms * 6);
  });

  test('a measurement over its budget fails the benchmark and is named', () {
    final out = StringBuffer();

    final code = report([
      measured('first layout', ms * 49, budget: ms * 50),
      measured('update', ms * 2, budget: ms),
    ], out);

    expect(code, 1);
    expect('$out'.trim().split('\n'), [
      'first layout: 500 bars, median 49.000 ms, budget 50.000 ms',
      'update: 500 bars, median 2.000 ms, budget 1.000 ms, OVER BUDGET',
      'FAILED, over budget: update',
    ]);
  });

  test('a measurement at its budget passes', () {
    final out = StringBuffer();

    expect(report([measured('update', ms, budget: ms)], out), 0);
    expect('$out', isNot(contains('OVER')));
  });

  test('a measurement with no budget is reported and not judged', () {
    final out = StringBuffer();

    expect(report([measured('update', ms * 900)], out), 0);
    expect('$out'.trim(), 'update: 500 bars, median 900.000 ms, no budget');
  });

  test('measure times the run and not its preparation', () {
    const pause = Duration(milliseconds: 20);

    final prepared = measure(
      'slow to prepare',
      prepare: () => sleep(pause),
      run: (_) => 3,
      warmUps: 0,
      runs: 3,
    );
    final ran = measure(
      'slow to run',
      prepare: () {},
      run: (_) {
        sleep(pause);
        return 3;
      },
      warmUps: 0,
      runs: 3,
    );

    expect(prepared.median, lessThan(pause));
    expect(ran.median, greaterThanOrEqualTo(pause));
    expect(ran.bars, 3);
  });

  test('measure leaves the warm-up runs out of the median', () {
    var calls = 0;

    final measurement = measure(
      'slow at first',
      prepare: () => calls++,
      run: (call) {
        if (call < 2) {
          sleep(const Duration(milliseconds: 20));
        }
        return 1;
      },
      warmUps: 2,
      runs: 1,
    );

    expect(calls, 3);
    expect(measurement.median, lessThan(const Duration(milliseconds: 20)));
  });
}
