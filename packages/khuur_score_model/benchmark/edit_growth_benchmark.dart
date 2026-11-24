// Checks how the cost of one entered note grows with the length of the
// score. It enters an eighth note on the third beat of the middle bar of a
// score with a glissando in every bar, does the same on a score four times
// as long and compares the two times. It does so once writing over the
// chord there, once with `Ripple.part`, once with `Ripple.part` on a score
// that a rehearsal mark every eight bars cuts into sections, and once on
// such a score whose first note of every bar is tied.
//
// Run it compiled, from packages/khuur_score_model. A JIT run measures the
// compiler as much as the code. The compiler does not create `build`, which
// git ignores.
//
//   mkdir -p build && dart compile exe benchmark/edit_growth_benchmark.dart -o build/edit_growth_benchmark
//   build/edit_growth_benchmark
//
// It prints one line per score and one per entry, and exits with 1 when
// the longer score costs more than the bound times the shorter.

import 'dart:io';

import 'package:khuur_score_model/khuur_score_model.dart';

import 'erase_benchmark.dart' show glided;
import 'erase_growth_benchmark.dart' show sectioned, tied;

/// Four times the bars cost four times the time when the entry is linear
/// and sixteen times when it is quadratic. The bound sits between, clear of
/// the noise of a busy machine.
const double _mostGrowth = 8;

/// The shorter of the two scores.
const int _bars = 2000;

final Pitch _entered = Pitch.parse('E4');

/// The entry of an eighth note on the third beat of the middle bar of
/// [score].
EnterNote noteMidScore(Score score, Ripple ripple) => EnterNote(
  at: VoicePoint(
    staff: score.staves.first.id,
    voice: VoiceSlot.one,
    at: ScorePoint(
      score.measures[score.measures.length ~/ 2].id,
      Moment.zero + NoteValue.half.length,
    ),
  ),
  tone: _entered,
  value: NoteValue.eighth,
  ripple: ripple,
);

/// The median time of [runs] runs of [entry] on [score], after [warmUps]
/// that do not count. Fails when the entry is refused or leaves the score
/// without the note.
Duration entryTime(
  Score score,
  EnterNote entry, {
  int warmUps = 2,
  int runs = 7,
}) {
  final watch = Stopwatch();
  final times = <Duration>[];
  for (var i = 0; i < warmUps + runs; i++) {
    final session = EditSession.start(score);
    watch
      ..reset()
      ..start();
    final outcome = session.run(entry);
    watch.stop();
    final left = switch (outcome) {
      Applied(:final session) => session.score,
      _ => throw StateError('the entry was refused'),
    };
    final entered = left
        .laneOf(entry.at.staff, entry.at.voice)
        .where(
          (timed) => switch (timed.event) {
            ChordEvent(:final notes) => notes.any(
              (note) => note is PitchedNote && note.pitch == _entered,
            ),
            _ => false,
          },
        );
    if (entered.length != 1) {
      throw StateError('the entry left ${entered.length} of its note, not 1');
    }
    if (i >= warmUps) {
      times.add(watch.elapsed);
    }
  }
  return (times..sort())[times.length ~/ 2];
}

String _ms(Duration time) => (time.inMicroseconds / 1000).toStringAsFixed(3);

/// Whether the entry called [what] grows by no more than [_mostGrowth] from
/// [_bars] bars to four times as many.
bool _growsWithinBound(
  String what,
  Score Function(int bars) score,
  Ripple ripple,
) {
  Duration time(int length) {
    final built = score(length);
    return entryTime(built, noteMidScore(built, ripple));
  }

  final times = [time(_bars), time(4 * _bars)];
  for (final (i, time) in times.indexed) {
    stdout.writeln(
      '$what: ${i == 0 ? _bars : 4 * _bars} bars, median ${_ms(time)} ms',
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
      'entered note',
      (bars) => glided(bars, named: false),
      Ripple.none,
    ),
    _growsWithinBound(
      'rippled entered note',
      (bars) => glided(bars, named: false),
      Ripple.part,
    ),
    _growsWithinBound(
      'rippled entered note in sections',
      (bars) => sectioned(glided(bars, named: true)),
      Ripple.part,
    ),
    _growsWithinBound(
      'rippled entered note in sections under ties',
      (bars) => sectioned(tied(glided(bars, named: false))),
      Ripple.part,
    ),
  ];
  exitCode = held.every((held) => held) ? 0 : 1;
}
