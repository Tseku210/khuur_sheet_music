import 'dart:math';

import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'random_edits.dart';
import 'support.dart';

Set<MeasureId> bars(Score score, List<int> indices) => {
  for (final i in indices) score.measures[i].id,
};

/// An empty bar with [like]'s meter, key and closing clefs.
MeasureColumn emptyLike(MeasureColumn like, int id) => MeasureColumn(
  id: MeasureId(id),
  meter: like.meter,
  key: like.key,
  staves: Seq([
    for (final (k, staff) in like.staves.indexed)
      StaffMeasure(
        staff: staff.staff,
        clef: staff.clefAtEnd,
        voices: Seq([
          Voice(
            slot: VoiceSlot.one,
            items: Seq([
              MeasureRest(id: EventId(id * 10 + k), span: like.meter.length),
            ]),
          ),
        ]),
      ),
  ]),
);

/// Whether layout would draw bar [id] differently in [after] than in
/// [before]. The bar number ([MeasureView.index]) is left out.
bool drawsDifferently(Score before, Score after, MeasureId id) {
  final a = before.measureView(id);
  final b = after.measureView(id);
  bool sameObjects(List<Object> x, List<Object> y) =>
      x.length == y.length &&
      Iterable<int>.generate(x.length).every((i) => identical(x[i], y[i]));
  return !identical(a.column, b.column) ||
      !sameObjects(
        [for (final s in a.spanners) s.spanner],
        [for (final s in b.spanners) s.spanner],
      ) ||
      !sameObjects(
        [for (final s in a.staves) s.part],
        [for (final s in b.staves) s.part],
      ) ||
      describeView(a) != describeView(b);
}

String breaks(Score score) => [
  for (final column in score.measures) column.breakBefore,
].join(',');

void main() {
  group('Score.changesSince', () {
    test('reports nothing for the same score', () {
      final score = blankScore(bars: 3);

      expect(score.changesSince(score).isEmpty, isTrue);
    });

    test('relays out an edited bar and both neighbours', () {
      final before = blankScore(bars: 20);
      final after = enterAt(EditSession.start(before), 5, Moment.zero).score;
      final changes = after.changesSince(before);

      expect(changes.relayout, bars(after, [4, 5, 6]));
      expect(changes.removed, isEmpty);
      expect(changes.reflow, isFalse);
    });

    test('stops at the ends of the score', () {
      final before = EditSession.start(blankScore(bars: 20));

      expect(
        enterAt(
          before,
          0,
          Moment.zero,
        ).score.changesSince(before.score).relayout,
        bars(before.score, [0, 1]),
      );
      expect(
        enterAt(
          before,
          19,
          Moment.zero,
        ).score.changesSince(before.score).relayout,
        bars(before.score, [18, 19]),
      );
    });

    test('does not cascade past the neighbours', () {
      final start = EditSession.start(blankScore(bars: 20));
      final after = enterAt(enterAt(start, 3, Moment.zero), 10, Moment.zero);

      expect(
        after.score.changesSince(start.score).relayout,
        bars(start.score, [2, 3, 4, 9, 10, 11]),
      );
    });

    test('sees through undo to the columns it restores', () {
      final start = EditSession.start(blankScore(bars: 6));
      final edited = enterAt(start, 2, Moment.zero);
      final undone = edited.undo();

      expect(
        undone.score.changesSince(edited.score).relayout,
        bars(start.score, [1, 2, 3]),
      );
      expect(undone.score.changesSince(start.score).isEmpty, isTrue);
    });

    test('relays out an inserted bar and its neighbours', () {
      final before = blankScore(bars: 5);
      final after = before.copyWith(
        measures: before.measures.insertAt(
          2,
          emptyLike(before.measures[1], 90),
        ),
      );
      final changes = after.changesSince(before);

      expect(changes.relayout, bars(after, [1, 2, 3]));
      expect(changes.removed, isEmpty);
      expect(changes.reflow, isTrue);
    });

    test('reports a deleted bar and relays out its neighbours', () {
      final before = blankScore(bars: 5);
      final after = before.copyWith(measures: before.measures.removeAt(2));
      final changes = after.changesSince(before);

      expect(changes.relayout, bars(after, [1, 2]));
      expect(changes.removed, {before.measures[2].id});
      expect(changes.reflow, isTrue);
    });

    test('relays out every bar when the parts change', () {
      final before = blankScore(parts: const [morinKhuur, clarinet], bars: 4);
      final changes = hidePart(before, 1).changesSince(before);

      expect(changes.relayout, bars(before, [0, 1, 2, 3]));
      expect(changes.reflow, isTrue);
    });

    test('relays out the bars an added or removed spanner covers', () {
      final plain = blankScore(bars: 6);
      final slurred = withSlur(
        plain,
        pointAt(plain, 1, at(1, 2)),
        pointAt(plain, 3, Moment.zero),
      );

      expect(slurred.changesSince(plain).relayout, bars(plain, [1, 2, 3]));
      expect(plain.changesSince(slurred).relayout, bars(plain, [1, 2, 3]));
      expect(slurred.changesSince(plain).reflow, isFalse);
    });

    test('leaves out bars a removed spanner covered that are gone', () {
      final plain = blankScore(bars: 6);
      final slurred = withSlur(
        plain,
        pointAt(plain, 1, Moment.zero),
        pointAt(plain, 3, Moment.zero),
      );
      final after = plain.copyWith(measures: plain.measures.removeAt(3));
      final changes = after.changesSince(slurred);

      expect(changes.relayout, bars(after, [1, 2, 3]));
      expect(changes.removed, {plain.measures[3].id});
    });

    test('relays out every bar when bars change order', () {
      final plain = blankScore(bars: 5);
      final slurred = withSlur(
        plain,
        pointAt(plain, 0, Moment.zero),
        pointAt(plain, 4, Moment.zero),
      );
      final m = slurred.measures;
      final moved = slurred.copyWith(
        measures: Seq([m[1], m[2], m[3], m[0], m[4]]),
      );
      final changes = moved.changesSince(slurred);

      expect(drawsDifferently(slurred, moved, m[2].id), isTrue);
      expect(changes.relayout, bars(moved, [0, 1, 2, 3, 4]));
      expect(changes.reflow, isTrue);
    });

    test('never misses a bar that draws differently', () {
      for (final seed in [1, 2, 3]) {
        final random = Random(seed);
        var score = blankScore(parts: const [morinKhuur, clarinet], bars: 4);
        for (var step = 0; step < 150; step++) {
          final before = score;
          score = randomEdit(before, random);
          final changes = score.changesSince(before);
          final beforeIds = barIds(before);
          final afterIds = barIds(score);
          final where = 'seed $seed, step $step';

          expect(
            changes.removed,
            beforeIds.toSet().difference(afterIds.toSet()),
            reason: where,
          );
          expect(
            changes.reflow,
            !identical(before.parts, score.parts) ||
                beforeIds.join(',') != afterIds.join(',') ||
                breaks(before) != breaks(score),
            reason: where,
          );
          for (final id in afterIds) {
            if (!before.contains(id) || drawsDifferently(before, score, id)) {
              expect(
                changes.relayout,
                contains(id),
                reason: '$where, bar ${afterIds.indexOf(id)}',
              );
            }
          }
          expect(
            changes.relayout.difference(afterIds.toSet()),
            isEmpty,
            reason: where,
          );
        }
      }
    });
  });
}
