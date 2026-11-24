import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:khuur_score_model/src/spanner_ends.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Four quarters in each of [bars] bars, ids 100, 101… in the first bar,
/// 110, 111… in the second and so on.
Score quarters({int bars = 1}) {
  var score = blankScore(bars: bars);
  for (var bar = 0; bar < bars; bar++) {
    score = fill(score, bar, [
      for (var beat = 0; beat < 4; beat++)
        chordOf(100 + bar * 10 + beat, 'C4 E4'),
    ]);
  }
  return score;
}

Spanner line(Score score, SpannerKind kind, (int, int) from, (int, int) to) =>
    Spanner(
      id: const SpannerId(1),
      kind: kind,
      staff: score.staves.first.id,
      voice: kind.joinsNotes ? VoiceSlot.one : null,
      first: pointAt(score, from.$1, at(from.$2, 4)),
      last: pointAt(score, to.$1, at(to.$2, 4)),
    );

void main() {
  group('A score answers the ends of a spanner', () {
    test('once for each score and spanner object', () {
      final score = quarters();
      final slur = line(score, const Slur(), (0, 0), (0, 2));
      final copy = score.copyWith();

      expect(identical(score.spannerEnds(slur), score.spannerEnds(slur)), true);
      expect(identical(copy.spannerEnds(slur), score.spannerEnds(slur)), false);
    });

    test('of the score it is asked in', () {
      final score = quarters();
      final slur = line(score, const Slur(), (0, 0), (0, 2));
      final longer = fill(score, 0, [
        chordOf(100, 'C4'),
        chordOf(101, 'D4', value: NoteValue.half),
        chordOf(103, 'F4'),
      ]);

      expect(score.spannerEnds(slur).endsOn?.event.id, const EventId(102));
      expect(longer.spannerEnds(slur).endsOn?.event.id, const EventId(101));
    });

    test('with the notes a glissando joins', () {
      final score = quarters();
      final ends = score.spannerEnds(
        line(score, const Glissando(from: NoteId(1000)), (0, 0), (0, 1)),
      );

      expect(ends.startNote?.id, const NoteId(1000));
      expect(ends.endNote?.id, const NoteId(1010));
      expect(ends.lostNote, isNull);
    });

    test('naming the first note a glissando has lost before its last', () {
      final score = quarters();
      final ends = score.spannerEnds(
        line(
          score,
          const Glissando(from: NoteId(9), to: NoteId(8)),
          (0, 0),
          (0, 1),
        ),
      );

      expect(ends.lostNote, const NoteId(9));
      expect(ends.endsTooSoon, false);
    });

    test('as collapsed when a slur starts and ends on one event', () {
      final score = quarters();
      final ends = score.spannerEnds(
        Spanner(
          id: const SpannerId(1),
          kind: const Slur(),
          staff: score.staves.first.id,
          first: pointAt(score, 0, Moment.zero),
          last: pointAt(score, 0, at(1, 8)),
        ),
      );

      expect(ends.collapsed, true);
      expect(ends.endsTooSoon, false);
    });

    test('as too soon when a slur ends on an event before its first', () {
      final score = quarters();
      final ends = score.spannerEnds(
        line(score, const Slur(), (0, 2), (0, 1)),
      );

      expect(ends.collapsed, false);
      expect(ends.endsTooSoon, true);
    });

    test('stopping at its last point, or at the end of the event a line of '
        'time ends in', () {
      final score = quarters();

      expect(
        score.spannerEnds(line(score, const Slur(), (0, 0), (0, 2))).stop,
        at(2, 4),
      );
      expect(
        score
            .spannerEnds(
              line(score, const Hairpin(crescendo: true), (0, 0), (0, 2)),
            )
            .stop,
        at(3, 4),
      );
    });
  });
}
