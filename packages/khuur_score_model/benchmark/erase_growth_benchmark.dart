// Checks how the cost of erasing a chord from every bar in one edit grows
// with the length of the score. It erases the second chord of every bar of
// a score with a glissando in every bar, then of a score four times as
// long, and compares the two times. It does so once with no ripple, once
// with `Ripple.part`, and once with `Ripple.part` on a score that a
// rehearsal mark every eight bars cuts into sections, whose glissandi name
// their notes.
//
// Run it compiled, from packages/khuur_score_model. A JIT run measures the
// compiler as much as the code. The compiler does not create `build`, which
// git ignores.
//
//   mkdir -p build && dart compile exe benchmark/erase_growth_benchmark.dart -o build/erase_growth_benchmark
//   build/erase_growth_benchmark
//
// It prints one line per score and one per erase, and exits with 1 when
// the longer score costs more than the erase's bound times the shorter.

import 'dart:io';

import 'package:khuur_score_model/khuur_score_model.dart';

import 'erase_benchmark.dart' show glided;

/// Four times the bars cost four times the time when the erase is linear
/// and sixteen times when it is quadratic. The bound sits between, clear of
/// the noise of a busy machine.
const double _mostGrowth = 8;

/// The median time of [runs] erases of the second chord of every bar of
/// [score] in one edit, after [warmUps] that do not count. Fails when the
/// erase is refused, leaves another count of chords than three a bar, or
/// leaves a glissando that named the note it ended on.
Duration eraseTime(
  Score score,
  Ripple ripple, {
  int warmUps = 2,
  int runs = 7,
}) {
  final bars = score.measures.length;
  final staff = score.staves.first.id;
  final erase = Erase(
    ItemSelection(
      Seq([
        for (var bar = 0; bar < bars; bar++)
          score.locate(EventId(4 * bar + 1))!,
      ]),
    ),
    ripple: ripple,
  );
  final watch = Stopwatch();
  final times = <Duration>[];
  for (var i = 0; i < warmUps + runs; i++) {
    final session = EditSession.start(score);
    watch
      ..reset()
      ..start();
    final outcome = session.run(erase);
    watch.stop();
    final left = switch (outcome) {
      Applied(:final session) => session.score,
      _ => throw StateError('the erase was refused'),
    };
    final chords = left
        .laneOf(staff, VoiceSlot.one)
        .where((timed) => timed.event is ChordEvent)
        .length;
    if (chords != 3 * bars) {
      throw StateError('the erase left $chords chords in $bars bars');
    }
    if (left.spanners.any((line) => line.kind != const Glissando())) {
      throw StateError('the erase left a glissando without its note');
    }
    if (i >= warmUps) {
      times.add(watch.elapsed);
    }
  }
  return (times..sort())[times.length ~/ 2];
}

/// [score] with a rehearsal mark on every eighth bar, so that a ripple
/// moves music within eight bars at a time.
Score sectioned(Score score) {
  var session = EditSession.start(score);
  for (var bar = 8; bar < score.measures.length; bar += 8) {
    session = switch (session.run(
      SetRehearsal(score.measures[bar].id, '$bar'),
    )) {
      Applied(:final session) => session,
      _ => throw StateError('the rehearsal mark was refused'),
    };
  }
  return session.score;
}

String _ms(Duration time) => (time.inMicroseconds / 1000).toStringAsFixed(3);

/// Whether the erase called [what], with [ripple] on the score that
/// [score] builds, grows by no more than [_mostGrowth] from [bars] bars to
/// four times as many.
bool _growsWithinBound(
  String what,
  Ripple ripple,
  int bars,
  Score Function(int) score,
) {
  final times = [
    for (final length in [bars, 4 * bars]) eraseTime(score(length), ripple),
  ];
  for (final (i, time) in times.indexed) {
    stdout.writeln(
      '$what of a chord a bar: ${i == 0 ? bars : 4 * bars} bars, '
      'median ${_ms(time)} ms',
    );
  }
  final growth = times.last.inMicroseconds / times.first.inMicroseconds;
  final over = growth > _mostGrowth;
  stdout.writeln(
    '$what: 4 times the bars cost ${growth.toStringAsFixed(2)} times the '
    'time, bound $_mostGrowth${over ? ', FAILED' : ''}',
  );
  return !over;
}

void main() {
  final held = [
    _growsWithinBound(
      'erase',
      Ripple.none,
      4000,
      (bars) => glided(bars, named: false),
    ),
    _growsWithinBound(
      'rippled erase',
      Ripple.part,
      1000,
      (bars) => glided(bars, named: false),
    ),
    _growsWithinBound(
      'rippled erase in sections',
      Ripple.part,
      1000,
      (bars) => sectioned(glided(bars, named: true)),
    ),
  ];
  exitCode = held.every((held) => held) ? 0 : 1;
}
