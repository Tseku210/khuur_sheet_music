// Checks how the cost of one erase grows with the length of the score. It
// erases the second chord of every bar of a score with a glissando in every
// bar, then of a score four times as long, and compares the two times. It
// does so once with no ripple, once with `Ripple.part`, and once with
// `Ripple.part` on a score that a rehearsal mark every eight bars cuts into
// sections, whose glissandi name their notes. In sections it also erases
// the same chords of a score whose first note of every bar is tied, and a
// range that takes all but the last three chords of the score.
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

/// The shorter of the two scores in sections. An erase that copies the bar
/// list once for each section still grows within the bound from 4000 bars
/// to 16000, and grows about 30 times from 16000 to 64000.
const int _sectionedBars = 16000;

/// The shorter of the two tied scores. With an index of every event built
/// once for each section, the erase grows about 18 times from 1000 bars to
/// 4000, and takes over 30 seconds a run at 16000.
const int _tiedBars = 1000;

/// The shorter of the two scores a range is erased from. With every
/// glissando of the score read once for each section, the erase grows about
/// 14 times from 4000 bars to 16000.
const int _rangeBars = 4000;

/// The erase of the second chord of every bar of [score].
Erase chordABar(Score score, Ripple ripple) => Erase(
  ItemSelection(
    Seq([
      for (var bar = 0; bar < score.measures.length; bar++)
        score.locate(EventId(4 * bar + 1))!,
    ]),
  ),
  ripple: ripple,
);

/// The rippled erase of [score] from its start to a quarter into its last
/// bar, which leaves the last three chords.
Erase allButThreeChords(Score score) {
  final staff = score.staves.first.id;
  return Erase(
    RangeSelection(
      from: ScorePoint(score.measures.first.id, Moment.zero),
      to: ScorePoint(
        score.measures.last.id,
        Moment.zero + NoteValue.quarter.length,
      ),
      top: staff,
      bottom: staff,
    ),
    ripple: Ripple.part,
  );
}

/// The median time of [runs] runs of [erase] on [score], after [warmUps]
/// that do not count. Fails when the erase is refused, leaves another count
/// of chords than [chordsLeft], leaves a tied note, or leaves a glissando
/// that named a note.
Duration eraseTime(
  Score score,
  Erase erase, {
  required int chordsLeft,
  int warmUps = 2,
  int runs = 7,
}) {
  final staff = score.staves.first.id;
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
    final kept = [
      for (final timed in left.laneOf(staff, VoiceSlot.one))
        if (timed.event case final ChordEvent chord) chord,
    ];
    if (kept.length != chordsLeft) {
      throw StateError(
        'the erase left ${kept.length} chords, not $chordsLeft',
      );
    }
    if (kept.any((chord) => chord.notes.any((note) => note.tie))) {
      throw StateError('the erase left a tie into another note');
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
Score sectioned(Score score) => score.copyWith(
  measures: Seq([
    for (final (bar, column) in score.measures.indexed)
      bar > 0 && bar % 8 == 0
          ? column.copyWith(rehearsal: () => '$bar')
          : column,
  ]),
);

/// [score] with the first note of every bar tied. The note after it has
/// another pitch, so each tie ends on no note.
Score tied(Score score) => score.copyWith(
  measures: Seq([
    for (final column in score.measures)
      column.withStaff(
        column.staves.first.withVoice(
          Voice(
            slot: VoiceSlot.one,
            items: Seq([
              for (final (at, item)
                  in column.staves.first.voices.first.items.indexed)
                if (at == 0 && item is ChordEvent)
                  ChordEvent(
                    id: item.id,
                    value: item.value,
                    notes: Seq([
                      for (final note in item.notes.cast<PitchedNote>())
                        PitchedNote(id: note.id, pitch: note.pitch, tie: true),
                    ]),
                  )
                else
                  item,
            ]),
          ),
        ),
      ),
  ]),
);

String _ms(Duration time) => (time.inMicroseconds / 1000).toStringAsFixed(3);

int _threeABar(int bars) => 3 * bars;

/// Whether the erase called [what] of [of] grows by no more than
/// [_mostGrowth] from [bars] bars to four times as many.
bool _growsWithinBound(
  String what,
  int bars,
  Score Function(int bars) score, {
  required Erase Function(Score score) erase,
  String of = 'a chord a bar',
  int Function(int bars) chordsLeft = _threeABar,
}) {
  Duration time(int length) {
    final built = score(length);
    return eraseTime(built, erase(built), chordsLeft: chordsLeft(length));
  }

  final times = [time(bars), time(4 * bars)];
  for (final (i, time) in times.indexed) {
    stdout.writeln(
      '$what of $of: ${i == 0 ? bars : 4 * bars} bars, '
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
      4000,
      (bars) => glided(bars, named: false),
      erase: (score) => chordABar(score, Ripple.none),
    ),
    _growsWithinBound(
      'rippled erase',
      4000,
      (bars) => glided(bars, named: false),
      erase: (score) => chordABar(score, Ripple.part),
    ),
    _growsWithinBound(
      'rippled erase in sections',
      _sectionedBars,
      (bars) => sectioned(glided(bars, named: true)),
      erase: (score) => chordABar(score, Ripple.part),
    ),
    _growsWithinBound(
      'rippled erase in sections under ties',
      _tiedBars,
      (bars) => sectioned(tied(glided(bars, named: false))),
      erase: (score) => chordABar(score, Ripple.part),
    ),
    _growsWithinBound(
      'rippled range erase in sections',
      _rangeBars,
      (bars) => sectioned(glided(bars, named: true)),
      erase: allButThreeChords,
      of: 'all but three chords',
      chordsLeft: (_) => 3,
    ),
  ];
  exitCode = held.every((held) => held) ? 0 : 1;
}
