import 'dart:math';

import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

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
      _describe(a) != _describe(b);
}

String _describe(MeasureView view) => [
  view.meterChanged,
  view.keyChanged,
  _key(view.previousKey),
  view.voltaStarts,
  view.voltaEnds,
  view.isRestOnly,
  for (final s in view.spanners)
    (s.spanner.id, s.from, s.to, s.startsHere, s.endsHere),
  for (final staff in view.staves) ...[
    staff.source.staff,
    staff.clefChanged,
    _key(staff.writtenKey),
    for (final MapEntry(:key, :value) in staff.accidentals.entries)
      (key, value.alter, value.cautionary),
    for (final tie in staff.ties)
      (
        tie.from,
        tie.to?.event.id,
        tie.to?.event.measure,
        tie.to?.note,
        tie.crossesBarline,
      ),
    staff.tiedIn,
    for (final MapEntry(:key, :value) in staff.writtenPitches.entries)
      (key, value),
    for (final voice in staff.voices) ...[
      voice.slot,
      for (final e in voice.events) (e.event.id, e.onset, e.duration),
      for (final b in voice.beams) (b.events, b.secondaryBreaks),
      for (final t in voice.tuplets)
        (t.tuplet.id, t.onset, t.duration, t.events, t.depth),
    ],
  ],
].join(' | ');

(int, KeyMode)? _key(KeySignature? key) =>
    key == null ? null : (key.fifths, key.mode);

T pick<T>(Random random, List<T> options) =>
    options[random.nextInt(options.length)];

Score edited(Score score, Edit edit) =>
    switch (EditSession.start(score).run(edit)) {
      Applied(:final session) => session.score,
      Refused() => score,
    };

/// One random edit of the kinds a composer makes: note entry (the common
/// case), voltas, keys, clefs, spanners, inserted and deleted bars, and
/// hiding a part. Clefs, keys, spanners and parts are rebuilt by hand the
/// way edits rebuild them, sharing everything they don't touch, until their
/// edits exist.
Score randomEdit(Score score, Random random, int Function() nextId) {
  final bar = random.nextInt(score.measures.length);
  final id = score.measures[bar].id;
  switch (random.nextInt(10)) {
    case 0 || 1 || 2:
      return edited(
        score,
        EnterNote(
          at: VoicePoint(
            staff: pick(random, score.staves).id,
            voice: pick(random, [VoiceSlot.one, VoiceSlot.two]),
            at: ScorePoint(id, at(random.nextInt(8), 8)),
          ),
          pitch: Pitch.parse(pick(random, ['F4', 'F#4', 'Bb4', 'E5'])),
          value: pick(random, [
            NoteValue.eighth,
            NoteValue.sixteenth,
            NoteValue.quarter,
            NoteValue.quarter.dotted,
            NoteValue.half,
          ]),
        ),
      );
    case 3:
      final last = score.measures[min(bar + 1, score.measures.length - 1)];
      return edited(
        score,
        SetVolta(
          id,
          last.id,
          pick(random, [
            null,
            const Volta([1]),
            const Volta([2]),
          ]),
        ),
      );
    case 4:
      return changeBar(
        score,
        bar,
        (c) => c.copyWith(key: KeySignature(random.nextInt(5) - 2)),
      );
    case 5:
      return changeBar(
        score,
        bar,
        (c) => c.withStaff(
          c.staves.first.copyWith(clef: pick(random, [Clef.treble, Clef.bass])),
        ),
      );
    case 6:
      if (score.spanners.isNotEmpty && random.nextBool()) {
        return score.copyWith(
          spanners: score.spanners.removeAt(
            random.nextInt(score.spanners.length),
          ),
        );
      }
      final ends = [
        (random.nextInt(score.measures.length), random.nextInt(4)),
        (random.nextInt(score.measures.length), random.nextInt(4)),
      ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
      return score.copyWith(
        spanners: Seq([
          ...score.spanners,
          Spanner(
            id: SpannerId(nextId()),
            kind: pick(random, const [
              Slur(),
              OctaveLine(OctaveShift.up8),
              OctaveLine(OctaveShift.down8),
            ]),
            staff: pick(random, score.staves).id,
            first: pointAt(score, ends[0].$1, at(ends[0].$2, 4)),
            last: pointAt(score, ends[1].$1, at(ends[1].$2, 4)),
          ),
        ]),
      );
    case 7:
      if (score.measures.length > 3 && random.nextBool()) {
        final last = score.measures[min(bar + 1, score.measures.length - 1)];
        return edited(score, DeleteMeasures(id, last.id));
      }
      return edited(
        score,
        InsertMeasures(
          before: random.nextBool() ? id : null,
          count: 1 + random.nextInt(2),
        ),
      );
    case 8:
      return edited(
        score,
        SetBarLength(id, pick(random, [null, len(1, 4), len(3, 8), len(5, 4)])),
      );
    default:
      return hidePart(score, 1, hidden: !score.parts[1].hidden);
  }
}

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
        // Negative, so they never meet the ids EditSession hands out above
        // the score's largest.
        var nextId = -1;
        var score = blankScore(parts: const [morinKhuur, clarinet], bars: 4);
        for (var step = 0; step < 150; step++) {
          final before = score;
          score = randomEdit(before, random, () => nextId--);
          final changes = score.changesSince(before);
          final beforeIds = [for (final c in before.measures) c.id];
          final afterIds = [for (final c in score.measures) c.id];
          final where = 'seed $seed, step $step';

          expect(
            changes.removed,
            beforeIds.toSet().difference(afterIds.toSet()),
            reason: where,
          );
          expect(
            changes.reflow,
            !identical(before.parts, score.parts) ||
                beforeIds.join(',') != afterIds.join(','),
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
