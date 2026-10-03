import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/random_walk.dart';

/// Every [stride]th layout of the walk is queried. A query reads every
/// drawable of every system, so the walk's cost is in the queries.
const stride = 5;

/// Where a finger taps [drawable], the middle of its box, or the middle of
/// its line for a curve, which is hit near its line only.
SpPoint tapOn(Drawable drawable) => switch (drawable) {
  CurveDraw() => drawable.pointAt(0.5),
  _ => SpPoint(
    (drawable.bounds.left + drawable.bounds.right) / 2,
    (drawable.bounds.top + drawable.bounds.bottom) / 2,
  ),
};

/// The order a tap prefers, a notehead first.
int rankOf(Owner owner) => switch (owner) {
  ElementOwner(ref: NoteRef()) => 0,
  ElementOwner() => 1,
  SpannerOwner() => 2,
};

Tone toneFor(Score score, StaffId staff) {
  final drums = score.partOf(staff).instrument.drums;
  return drums.isEmpty ? const Pitch(Step.c, 4) : Drum(drums.first.name);
}

void main() {
  for (final rests in [false, true]) {
    final style = EngravingStyle(multiMeasureRests: rests);
    final walked =
        'over seeded random edits and sheet widths, with multi-measure '
        'rests ${rests ? 'on' : 'off'}';

    test('a tap on every owned drawable hits its owner or one drawn over it, '
        'and in a bar with tuplets gives a time where a sixteenth enters, '
        '$walked', () {
      var step = 0;
      var layouts = 0;
      var taps = 0;
      var overdrawn = 0;
      var entries = 0;

      walk(style, (layout, score, width) {
        if (step++ % stride != 0) {
          return;
        }
        layouts++;
        for (var index = 0; index < layout.systemCount; index++) {
          final system = layout.systemAt(index);
          final tupleted = {
            for (final bar in system.bars)
              if (bar.voices.values.any((voice) => voice.tuplets.isNotEmpty))
                bar.measure,
          };
          for (final drawable in system.drawables) {
            final owner = drawable.owner;
            if (owner == null) {
              continue;
            }
            final local = tapOn(drawable);
            final hit = layout.hitTest(local.shift(0, layout.tops[index]));
            final target = hit?.target;
            expect(target, isNotNull, reason: 'tap on $owner at $local');
            taps++;
            if (target != owner) {
              overdrawn++;
              expect(
                rankOf(target!),
                lessThanOrEqualTo(rankOf(owner)),
                reason: '$target over $owner at $local',
              );
              expect(
                system.drawablesOf(target).any((d) => d.hits(local, 0)),
                isTrue,
                reason: '$target is not under $local',
              );
            }
            if (!tupleted.contains(hit!.at.measure)) {
              continue;
            }
            final entered = EditSession.start(score).run(
              EnterNote(
                at: VoicePoint(staff: hit.staff, voice: hit.voice, at: hit.at),
                tone: toneFor(score, hit.staff),
                value: NoteValue.sixteenth,
              ),
            );
            expect(
              entered,
              isA<Applied>(),
              reason:
                  'a sixteenth at ${hit.at} in ${hit.voice} of ${hit.staff}'
                  ' after a tap on $owner',
            );
            entries++;
          }
        }
      });

      expect(layouts, seeds.length * (edits / stride).ceil());
      expect(taps, greaterThan(100000));
      expect(overdrawn, greaterThan(1000));
      expect(entries, greaterThan(10000));
    });

    test('the caret for every event sits on the x of its onset in the bar, '
        'system and staff that hold it, and nowhere for a hidden staff, '
        '$walked', () {
      var step = 0;
      var carets = 0;
      var hidden = 0;

      walk(style, (layout, score, width) {
        if (step++ % stride != 0) {
          return;
        }
        for (final measure in score.measures) {
          final index = layout.systemOf(measure.id)!;
          final system = layout.systemAt(index);
          final view = score.measureView(measure.id);
          final shown = {for (final staff in view.staves) staff.source.staff};
          for (final staff in score.staves) {
            if (shown.contains(staff.id)) {
              continue;
            }
            expect(system.staffOf(staff.id), isNull);
            expect(
              layout.caretOf(
                VoicePoint(
                  staff: staff.id,
                  voice: VoiceSlot.one,
                  at: ScorePoint(measure.id, Moment.zero),
                ),
              ),
              isNull,
            );
            hidden++;
          }
          for (final staff in view.staves) {
            final id = staff.source.staff;
            final placed = system.staffOf(id)!;
            for (final voice in staff.voices) {
              for (final timed in voice.events) {
                final box = layout.caretOf(
                  VoicePoint(
                    staff: id,
                    voice: voice.slot,
                    at: ScorePoint(measure.id, timed.onset),
                  ),
                );
                final bar = system.barOf(measure.id)!;
                final top = layout.tops[index] + placed.top;
                expect(box, isNotNull, reason: '${timed.ref} on $id');
                expect(box!.left, box.right);
                expect(box.left, greaterThanOrEqualTo(bar.left));
                expect(box.left, lessThanOrEqualTo(bar.right));
                expect(box.top, closeTo(top, 1e-9));
                expect(box.bottom, closeTo(top + staffHeight, 1e-9));
                carets++;
              }
            }
          }
        }
      });

      expect(carets, greaterThan(60000));
      expect(hidden, greaterThan(1000));
    });
  }
}
