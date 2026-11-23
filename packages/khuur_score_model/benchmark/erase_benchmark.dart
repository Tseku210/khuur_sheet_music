// Checks that a glissando costs an edit little for losing the note it
// names. It builds a score with a glissando in every bar that names both its
// notes, and erases every chord a glissando ends on in one edit. Each line
// then looks for the note it has lost, and goes with it. It times an erase
// of the chord after each of those on the same score, where no line loses a
// note or looks for one, and compares the two times, at one length and at
// four times that length.
//
// Run it compiled, from packages/khuur_score_model. A JIT run measures the
// compiler as much as the code. The compiler does not create `build`, which
// git ignores.
//
//   mkdir -p build && dart compile exe benchmark/erase_benchmark.dart -o build/erase_benchmark
//   build/erase_benchmark
//
// It prints one line per score and exits with 1 when the erase of the
// chords the lines end on costs more than [_mostCost] times the other erase
// on the longer score.

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

Erase _eraseBeat(Score score, int beat) => Erase(
  ItemSelection(
    Seq([
      for (var bar = 0; bar < score.measures.length; bar++)
        score.locate(EventId(4 * bar + beat))!,
    ]),
  ),
);

/// The median times of [runs] erases of every chord a glissando of [score]
/// ends on, and of the chord after each of those, which no glissando starts
/// or ends on, each in one edit, after [warmUps] rounds that do not count.
/// Fails when an erase is refused, when the first leaves a glissando, or
/// when the second leaves fewer glissandi than bars.
({Duration lost, Duration kept}) eraseTimes(
  Score score, {
  int warmUps = 3,
  int runs = 11,
}) {
  final bars = score.measures.length;
  final watch = Stopwatch();
  final lost = <Duration>[];
  final kept = <Duration>[];
  for (var i = 0; i < warmUps + runs; i++) {
    for (final (beat, times, left) in [(1, lost, 0), (2, kept, bars)]) {
      final session = EditSession.start(score);
      final erase = _eraseBeat(score, beat);
      watch
        ..reset()
        ..start();
      final outcome = session.run(erase);
      watch.stop();
      final lines = switch (outcome) {
        Applied(:final session) => session.score.spanners.length,
        _ => throw StateError('the erase was refused'),
      };
      if (lines != left) {
        throw StateError(
          'the erase of beat $beat left $lines glissandi in $bars bars',
        );
      }
      if (i >= warmUps) {
        times.add(watch.elapsed);
      }
    }
  }
  Duration median(List<Duration> times) => (times..sort())[times.length ~/ 2];
  return (lost: median(lost), kept: median(kept));
}

String _ms(Duration time) => (time.inMicroseconds / 1000).toStringAsFixed(3);

void main() {
  var cost = 0.0;
  for (final bars in [_bars, 4 * _bars]) {
    final (:lost, :kept) = eraseTimes(glided(bars, named: true));
    cost = lost.inMicroseconds / kept.inMicroseconds;
    stdout.writeln(
      'erase of glissando ends: $bars bars, median ${_ms(lost)} ms where '
      'every line loses its end note, ${_ms(kept)} ms where none does, '
      '${cost.toStringAsFixed(2)} times',
    );
  }
  final over = cost > _mostCost;
  stdout.writeln(
    'lost end notes cost ${cost.toStringAsFixed(2)} times as much on the '
    'longer score, bound $_mostCost${over ? ', FAILED' : ''}',
  );
  exitCode = over ? 1 : 0;
}
