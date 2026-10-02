import 'dart:math';

import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/random_edits.dart';
import '../../score_model/test/support.dart';
import 'support/fake_measurer.dart';
import 'support/sheets.dart';

const seeds = [1, 2, 3, 4, 5, 6, 7, 8];
const edits = 400;
const text = FakeMeasurer();

/// Narrow enough at its least to press a system to its rods, where a bar
/// is laid out at stretch 0.
double randomWidth(Random random) => 12 + 138 * random.nextDouble();

void walk(
  EngravingStyle style,
  void Function(SheetLayout layout, Score score, double width) check,
) {
  for (final seed in seeds) {
    final random = Random(seed);
    var score = blankScore(parts: const [clarinet, piano, drums], bars: 24);
    var width = randomWidth(random);
    var layout = SheetLayout(score, width: width, text: text, style: style);

    for (var step = 0; step < edits; step++) {
      score = randomEdit(score, random);
      if (random.nextInt(3) == 0) {
        final id = score.measures[random.nextInt(score.measures.length)].id;
        score = edited(
          score,
          pick(random, [
            SetKey(from: id, key: KeySignature(random.nextInt(9) - 4)),
            SetKeyDisplay(id, pick(random, SignatureDisplay.values)),
            SetMeterDisplay(id, pick(random, SignatureDisplay.values)),
          ]),
        );
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
}

const syllableTexts = ['a', 'dolce', 'Тайван', '月', 'Lie-', '\u0938\u0902'];

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

/// How many marks [view] holds on its events, its staves and its column.
int marksIn(MeasureView view) {
  final column = view.column;
  var marks =
      column.tempos.length +
      column.navigation.length +
      (column.rehearsal == null ? 0 : 1);
  for (final staff in view.staves) {
    marks += staff.source.directions.length;
    for (final voice in staff.voices) {
      for (final TimedEvent(:event) in voice.events) {
        marks += event.articulations.length;
        if (event is ChordEvent) {
          marks +=
              (event.ornament == null ? 0 : 1) +
              (event.bowing == null ? 0 : 1) +
              event.notes
                  .whereType<PitchedNote>()
                  .where((note) => note.fingering != null)
                  .length +
              event.notes
                  .whereType<PitchedNote>()
                  .where((note) => note.string != null)
                  .length;
        }
      }
    }
  }
  return marks;
}

void main() {
  for (final rests in [false, true]) {
    final style = EngravingStyle(multiMeasureRests: rests);
    final walked =
        'over seeded random edits and sheet widths, with multi-measure '
        'rests ${rests ? 'on' : 'off'}';

    test('an updated sheet equals a fresh one in header, tops, starts, bar '
        'numbers and drawables, $walked', () {
      var systems = 0;
      var kept = 0;
      var ties = 0;
      var voltaBars = 0;
      var marks = 0;
      var tuplets = 0;
      var syllables = 0;
      var hyphenated = 0;
      var extended = 0;
      final lanes = <(StaffId, VoiceSlot, int)>{};
      final spanners = <Type, int>{};

      walk(style, (layout, score, width) {
        expectSameSheet(
          layout,
          SheetLayout(score, width: width, text: text, style: style),
        );
        systems += layout.systemCount;
        kept += layout.systemCount - layout.delta.rekeyed.length;
        for (final measure in score.measures) {
          final view = score.measureView(measure.id);
          ties += view.staves.fold(0, (n, staff) => n + staff.ties.length);
          marks += marksIn(view);
          for (final staff in view.staves) {
            tuplets += staff.voices.fold(
              0,
              (n, voice) => n + voice.tuplets.length,
            );
            for (final voice in staff.voices) {
              for (final TimedEvent(:event) in voice.events) {
                if (event is! ChordEvent) {
                  continue;
                }
                for (final lyric in event.lyrics) {
                  syllables++;
                  if (lyric.syllabic == Syllabic.begin ||
                      lyric.syllabic == Syllabic.middle) {
                    hyphenated++;
                  }
                  if (lyric.extend) {
                    extended++;
                  }
                  lanes.add((staff.source.staff, voice.slot, lyric.verse));
                }
              }
            }
          }
          if (measure.volta != null) {
            voltaBars++;
          }
        }
        for (final spanner in score.spanners) {
          spanners.update(
            spanner.kind.runtimeType,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
      });

      expect(systems, greaterThan(seeds.length * edits));
      expect(kept, greaterThan(0));
      expect(ties, greaterThan(0));
      expect(voltaBars, greaterThan(0));
      expect(marks, greaterThan(50000));
      expect(tuplets, greaterThan(3000));
      expect(syllables, greaterThan(20000));
      expect(hyphenated, greaterThan(10000));
      expect(extended, greaterThan(10000));
      expect(lanes.length, greaterThan(50));
      for (final kind in [
        Slur,
        Hairpin,
        OctaveLine,
        PedalLine,
        TrillLine,
        TempoLine,
        Glissando,
      ]) {
        expect(spanners[kind], greaterThan(0), reason: '$kind');
      }
    });

    test('every drawable and bar number of every system stays inside its '
        'band, $walked', () {
      walk(style, (layout, _, _) => expectInsideBands(layout));
    });
  }
}
