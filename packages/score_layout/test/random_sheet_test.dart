import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/random_walk.dart';
import 'support/sheets.dart';

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
