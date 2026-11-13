/// The seeded random walk of test 6, which the random sheet and random hit
/// tests run their properties over.
library;

import 'dart:math';

import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';

import '../../../score_model/test/random_edits.dart';
import '../../../score_model/test/support.dart';
import 'fake_measurer.dart';

const seeds = [1, 2, 3, 4, 5, 6, 7, 8];
const edits = 400;
const text = FakeMeasurer();

/// Narrow enough at its least to press a system to its rods, where a bar
/// is laid out at stretch 0.
double randomWidth(Random random) => 12 + 138 * random.nextDouble();

/// Runs [check] on the layout after each of [edits] random edits of a
/// three-part score, for each of [seeds], at a random width drawn again
/// after one edit in 25. Returns how many clef changes it set at a
/// barline.
int walk(
  EngravingStyle style,
  void Function(SheetLayout layout, Score score, double width) check,
) {
  var clefs = 0;
  for (final seed in seeds) {
    final random = Random(seed);
    var score = blankScore(parts: const [clarinet, piano, drums], bars: 24);
    var width = randomWidth(random);
    var layout = SheetLayout(score, width: width, text: text, style: style);

    for (var step = 0; step < edits; step++) {
      score = randomEdit(score, random);
      if (random.nextInt(3) == 0) {
        final before = score;
        final edit = signatureEdit(score, random);
        score = edited(score, edit);
        if (edit is SetClef && !identical(score, before)) {
          clefs++;
        }
      }
      if (random.nextInt(3) == 0) {
        score = sung(score, random);
      }
      if (random.nextInt(25) == 0) {
        width = randomWidth(random);
      }
      layout = layout.update(score, width: width);
      check(layout, score, width);
    }
  }
  return clefs;
}

/// A key, a key or meter display, or a clef change at a barline, set on a
/// random bar of [score]. [randomEdit] sets these too rarely for a walk to
/// meet them at system starts.
Edit signatureEdit(Score score, Random random) {
  final id = score.measures[random.nextInt(score.measures.length)].id;
  return pick(random, [
    SetKey(from: id, key: KeySignature(random.nextInt(9) - 4)),
    SetKeyDisplay(id, pick(random, SignatureDisplay.values)),
    SetMeterDisplay(id, pick(random, SignatureDisplay.values)),
    SetClef(
      staff: pick(random, score.staves).id,
      at: ScorePoint(id, Moment.zero),
      clef: pick(random, const [Clef.treble, Clef.bass, Clef.alto]),
    ),
  ]);
}

const syllableTexts = ['a', 'dolce', 'Тайван', '月', 'Lie-', 'सं'];

/// [score] with a syllable set, changed or cleared on a random chord, in
/// one of three verses. Lyric edits are rarer in [randomEdit] than a
/// vocal line needs to run words and melismas across systems.
Score sung(Score score, Random random) {
  final chords = <EventRef>[
    for (final measure in score.measures)
      for (final staff in score.measureView(measure.id).staves)
        for (final voice in staff.voices)
          for (final timed in voice.events)
            if (timed.event is ChordEvent) timed.ref,
  ];
  if (chords.isEmpty) {
    return score;
  }
  final verse = 1 + random.nextInt(3);
  return edited(
    score,
    SetLyric(
      pick(random, chords),
      verse,
      random.nextInt(4) == 0
          ? null
          : Lyric(
              verse: verse,
              text: pick(random, syllableTexts),
              syllabic: pick(random, Syllabic.values),
              extend: random.nextBool(),
            ),
    ),
  );
}
