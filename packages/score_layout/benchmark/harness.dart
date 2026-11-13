/// Timing and judging for the layout benchmark.
library;

/// One timed piece of work, with the budget it is judged against.
final class Measurement {
  const Measurement({
    required this.name,
    required this.bars,
    required this.median,
    this.budget,
  });

  final String name;

  /// How many bars the work laid out.
  final int bars;

  final Duration median;

  /// Null when the design names no budget. The measurement is then reported
  /// and not judged.
  final Duration? budget;

  bool get isOverBudget => switch (budget) {
    final budget? => median > budget,
    null => false,
  };

  @override
  String toString() {
    final judged = switch (budget) {
      final budget? =>
        'budget ${_milliseconds(budget)}'
            '${isOverBudget ? ', OVER BUDGET' : ''}',
      null => 'no budget',
    };
    return '$name: $bars bars, median ${_milliseconds(median)}, $judged';
  }
}

String _milliseconds(Duration duration) =>
    '${(duration.inMicroseconds / 1000).toStringAsFixed(3)} ms';

/// The middle of [runs], or the mean of the two middle ones.
Duration medianOf(List<Duration> runs) {
  final sorted = [...runs]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) ~/ 2;
}

/// Times [run] on a fresh input from [prepare], [warmUps] times unrecorded
/// and then [runs] times. Only [run] is timed. It returns the number of bars
/// it laid out.
Measurement measure<T>(
  String name, {
  required T Function() prepare,
  required int Function(T input) run,
  Duration? budget,
  int warmUps = 5,
  int runs = 31,
}) {
  final watch = Stopwatch();
  final times = <Duration>[];
  var bars = 0;
  for (var i = 0; i < warmUps + runs; i++) {
    final input = prepare();
    watch
      ..reset()
      ..start();
    bars = run(input);
    watch.stop();
    if (i >= warmUps) {
      times.add(watch.elapsed);
    }
  }
  return Measurement(
    name: name,
    bars: bars,
    median: medianOf(times),
    budget: budget,
  );
}

/// Writes one line per measurement to [out] and returns the exit code. It
/// is 1 when a measurement is over its budget, and a last line names each.
int report(List<Measurement> measurements, StringSink out) {
  measurements.forEach(out.writeln);
  final over = [
    for (final measurement in measurements)
      if (measurement.isOverBudget) measurement.name,
  ];
  if (over.isEmpty) {
    return 0;
  }
  out.writeln('FAILED, over budget: ${over.join(', ')}');
  return 1;
}
