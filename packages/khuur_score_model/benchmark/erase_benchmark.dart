// Checks that a glissando costs an edit no more for naming its notes. It
// builds a score with a glissando in every bar that names both its notes,
// and erases every chord a glissando ends on in one edit. Each line then
// looks for the note it has lost. It times the same erase on the same score
// with glissandi that name no notes, which have nothing to look for, and
// compares the two times, at one length and at four times that length.
//
// Run it compiled, from packages/khuur_score_model. A JIT run measures the
// compiler as much as the code. The compiler does not create `build`, which
// git ignores.
//
//   mkdir -p build && dart compile exe benchmark/erase_benchmark.dart -o build/erase_benchmark
//   build/erase_benchmark
//
// It prints one line per score and exits with 1 when the erase under named
// lines costs more than [_mostCost] times the erase under unnamed ones on
// the longer score.

import 'dart:io';

import 'package:khuur_score_model/khuur_score_model.dart';

const int _bars = 250;

/// A search for the lost notes that reads the staff once adds little to the
/// erase. One that reads the staff for each line costs many times the
/// erase, and more the longer the score. The bound sits between, clear of
/// the noise of a busy machine.
const double _mostCost = 3;

/// A score of [bars] bars of four quarters, each bar with a glissando from
/// its first note to its second, which names both when [named].
Score glided(int bars, {required bool named}) {
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
                      pitch: Pitch.parse(beat.isEven ? 'C4' : 'D4'),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
  ];
  return blank.copyWith(
    measures: Seq(measures),
    spanners: Seq([
      for (final (bar, column) in measures.indexed)
        Spanner(
          id: SpannerId(bar),
          kind: named
              ? Glissando(from: NoteId(4 * bar), to: NoteId(4 * bar + 1))
              : const Glissando(),
          staff: staff,
          voice: VoiceSlot.one,
          first: ScorePoint(column.id, Moment.zero),
          last: ScorePoint(column.id, Moment.zero + NoteValue.quarter.length),
        ),
    ]),
  );
}

/// The median times of [runs] erases of every chord a glissando ends on,
/// in one edit, on [scores] in turn, after [warmUps] rounds that do not
/// count. Fails when an erase is refused, or leaves a glissando that named
/// the note it ended on.
List<Duration> eraseTimes(
  List<Score> scores, {
  int warmUps = 3,
  int runs = 11,
}) {
  final watch = Stopwatch();
  final times = [for (final _ in scores) <Duration>[]];
  for (var i = 0; i < warmUps + runs; i++) {
    for (final (at, score) in scores.indexed) {
      final session = EditSession.start(score);
      final erase = Erase(
        ItemSelection(
          Seq([
            for (var bar = 0; bar < score.measures.length; bar++)
              score.locate(EventId(4 * bar + 1))!,
          ]),
        ),
      );
      watch
        ..reset()
        ..start();
      final outcome = session.run(erase);
      watch.stop();
      final left = switch (outcome) {
        Applied(:final session) => session.score.spanners,
        _ => throw StateError('the erase was refused'),
      };
      if (left.any((line) => line.kind != const Glissando())) {
        throw StateError('the erase left a glissando without its note');
      }
      if (i >= warmUps) {
        times[at].add(watch.elapsed);
      }
    }
  }
  return [for (final each in times) (each..sort())[each.length ~/ 2]];
}

String _ms(Duration time) => (time.inMicroseconds / 1000).toStringAsFixed(3);

void main() {
  var cost = 0.0;
  for (final bars in [_bars, 4 * _bars]) {
    final [named, unnamed] = eraseTimes([
      glided(bars, named: true),
      glided(bars, named: false),
    ]);
    cost = named.inMicroseconds / unnamed.inMicroseconds;
    stdout.writeln(
      'erase of glissando ends: $bars bars, median ${_ms(named)} ms under '
      'named lines, ${_ms(unnamed)} ms under unnamed, '
      '${cost.toStringAsFixed(2)} times',
    );
  }
  final over = cost > _mostCost;
  stdout.writeln(
    'named lines cost ${cost.toStringAsFixed(2)} times as much on the longer '
    'score, bound $_mostCost${over ? ', FAILED' : ''}',
  );
  exitCode = over ? 1 : 0;
}
