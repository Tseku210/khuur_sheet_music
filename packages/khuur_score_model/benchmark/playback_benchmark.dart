// Checks that a playback compile costs in step with the size of the score. It
// compiles each of three scores, then one four times as long, and compares
// the two times: a slur and a trill line in every bar, one long run of
// measure-repeat signs, and short runs of signs among dynamics and hairpins.
//
// Run it compiled, from packages/khuur_score_model. A JIT run measures the
// compiler as much as the code. The compiler does not create `build`, which
// git ignores.
//
//   mkdir -p build && dart compile exe benchmark/playback_benchmark.dart -o build/playback_benchmark
//   build/playback_benchmark
//
// It prints the time of each score and the growth of each pair, and exits
// with 1 when a longer score costs more than [_mostGrowth] times its shorter
// one.

import 'dart:io';

import 'package:khuur_score_model/khuur_score_model.dart';

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

/// [lined] with no spanners and the bars that [covered] picks under one-bar
/// measure-repeat signs.
Score _underSigns(int bars, bool Function(int bar) covered) {
  final score = lined(bars);
  return score.copyWith(
    spanners: const Seq.empty(),
    measures: Seq([
      for (final (bar, column) in score.measures.indexed)
        if (covered(bar))
          column.withStaff(
            column.staves.first.copyWith(
              voices: Seq([
                Voice(
                  slot: VoiceSlot.one,
                  items: Seq([
                    MeasureRest(
                      id: EventId(4 * bars + bar),
                      span: column.length,
                    ),
                  ]),
                ),
              ]),
              measureRepeat: () => MeasureRepeat.oneBar,
            ),
          )
        else
          column,
    ]),
  );
}

/// A score of [bars] bars in one run of signs after the first bar.
Score repeated(int bars) => _underSigns(bars, (bar) => bar > 0);

/// A score of [bars] bars where every second bar is under a sign and every
/// other bar has a dynamic and a hairpin.
Score markedRepeats(int bars) {
  final score = _underSigns(bars, (bar) => bar.isOdd);
  final staff = score.staves.first.id;
  final last = Moment.zero + NoteValue.quarter.length * Fraction(3);
  return score.copyWith(
    measures: Seq([
      for (final (bar, column) in score.measures.indexed)
        if (bar.isOdd)
          column
        else
          column.withStaff(
            column.staves.first.copyWith(
              directions: Seq([
                DynamicMark(Moment.zero, bar % 4 == 0 ? Dynamic.p : Dynamic.f),
              ]),
            ),
          ),
    ]),
    spanners: Seq([
      for (final (bar, column) in score.measures.indexed)
        if (bar.isEven)
          Spanner(
            id: SpannerId(bar),
            kind: Hairpin(crescendo: bar % 4 == 0),
            staff: staff,
            first: ScorePoint(column.id, Moment.zero),
            last: ScorePoint(column.id, last),
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
  const repeatNotesPerBar = 4;
  final kinds = <(String, Score Function(int), int, int)>[
    ('lines', lined, 1000, notesPerBar),
    ('repeats', repeated, 2000, repeatNotesPerBar),
    ('marked repeats', markedRepeats, 2000, repeatNotesPerBar),
  ];
  var failed = false;
  for (final (name, build, shorter, perBar) in kinds) {
    final times = [
      for (final bars in [shorter, 4 * shorter])
        (bars, compileTime(build(bars), notes: bars * perBar)),
    ];
    for (final (bars, time) in times) {
      stdout.writeln(
        'playback compile of $name: $bars bars, median '
        '${(time.inMicroseconds / 1000).toStringAsFixed(3)} ms',
      );
    }
    final growth = times.last.$2.inMicroseconds / times.first.$2.inMicroseconds;
    final over = growth > _mostGrowth;
    failed = failed || over;
    stdout.writeln(
      'four times the bars of $name cost ${growth.toStringAsFixed(2)} times '
      'as much, bound $_mostGrowth${over ? ', FAILED' : ''}',
    );
  }
  exitCode = failed ? 1 : 0;
}
