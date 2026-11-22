// Checks that a playback compile costs in step with the size of the score. It
// compiles a score with a slur and a trill line in every bar, then one four
// times as long, and compares the two times.
//
// Run it compiled, from packages/khuur_score_model. A JIT run measures the
// compiler as much as the code. The compiler does not create `build`, which
// git ignores.
//
//   mkdir -p build && dart compile exe benchmark/playback_benchmark.dart -o build/playback_benchmark
//   build/playback_benchmark
//
// It prints one line per score and exits with 1 when the longer score costs
// more than [_mostGrowth] times the shorter.

import 'dart:io';

import 'package:khuur_score_model/khuur_score_model.dart';

const int _bars = 1000;

/// Four times the bars cost four times the time when the compile is linear
/// and sixteen times when it is quadratic. The bound sits between, clear of
/// the noise of a busy machine.
const double _mostGrowth = 8;

/// A score of [bars] bars of four quarters, each bar under a slur and with a
/// trill line over its last two notes.
Score lined(int bars) {
  final blank = Score.blank(
    parts: const [
      PartTemplate(
        name: 'Violin',
        instrument: Instrument(key: 'violin', program: 40),
      ),
    ],
    measureCount: bars,
  );
  final staff = blank.staves.first.id;
  final measures = [
    for (final (bar, column) in blank.measures.indexed)
      column.withStaff(
        column.staves.first.withVoice(
          Voice(
            slot: VoiceSlot.one,
            items: Seq([
              for (var beat = 0; beat < 4; beat++)
                ChordEvent(
                  id: EventId(4 * bar + beat),
                  value: NoteValue.quarter,
                  notes: Seq([
                    PitchedNote(
                      id: NoteId(4 * bar + beat),
                      pitch: Pitch.parse('C4'),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
  ];
  final quarter = NoteValue.quarter.length;
  return blank.copyWith(
    measures: Seq(measures),
    spanners: Seq([
      for (final (bar, column) in measures.indexed)
        for (final (kind, from, to) in [
          (const Slur(), 0, 3),
          (const TrillLine(), 2, 3),
        ])
          Spanner(
            id: SpannerId(2 * bar + (kind is Slur ? 0 : 1)),
            kind: kind,
            staff: staff,
            first: ScorePoint(
              column.id,
              Moment.zero + quarter * Fraction(from),
            ),
            last: ScorePoint(column.id, Moment.zero + quarter * Fraction(to)),
          ),
    ]),
  );
}

/// The median time of [runs] compiles of [score], each by a new compiler,
/// after [warmUps] that do not count. Fails when a compile plays a number of
/// notes other than [notes].
Duration compileTime(
  Score score, {
  required int notes,
  int warmUps = 3,
  int runs = 11,
}) {
  final watch = Stopwatch();
  final times = <Duration>[];
  for (var i = 0; i < warmUps + runs; i++) {
    watch
      ..reset()
      ..start();
    final script = PlaybackCompiler().compile(score);
    watch.stop();
    final played = script.notesBetween(0, double.infinity).length;
    if (played != notes) {
      throw StateError('compiled $played notes, not $notes');
    }
    if (i >= warmUps) {
      times.add(watch.elapsed);
    }
  }
  times.sort();
  return times[times.length ~/ 2];
}

void main() {
  // Each bar plays two slurred quarters and two trilled ones, which play
  // eight notes each at the unmarked tempo.
  const notesPerBar = 2 + 2 * 8;
  final times = [
    for (final bars in [_bars, 4 * _bars])
      (bars, compileTime(lined(bars), notes: bars * notesPerBar)),
  ];
  for (final (bars, time) in times) {
    stdout.writeln(
      'playback compile: $bars bars, median '
      '${(time.inMicroseconds / 1000).toStringAsFixed(3)} ms',
    );
  }
  final growth = times.last.$2.inMicroseconds / times.first.$2.inMicroseconds;
  final over = growth > _mostGrowth;
  stdout.writeln(
    'four times the bars cost ${growth.toStringAsFixed(2)} times as much, '
    'bound $_mostGrowth${over ? ', FAILED' : ''}',
  );
  exitCode = over ? 1 : 0;
}
