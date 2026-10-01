part of 'session.dart';

// Key and clef propagate forward through the run of bars that carried the
// old value. See [_propagate] and [_setClef].

_Result _setKey(Score score, MeasureId from, KeySignature key) {
  _check(keyProblem(key.fifths));
  final start = _barIndex(score, from);
  final old = score.measures[start].key;
  if (old == key) {
    return _Result(score);
  }
  return _Result(
    score.copyWith(
      measures: _propagate(
        score.measures,
        start,
        carries: (column) => column.key == old,
        update: (column) => column.copyWith(key: key),
      ),
    ),
  );
}

/// [score] with [clef] on [staff] from [at]. The clef the bar now ends in
/// replaces the old one on each following bar that carried it on, and the
/// run stops at a bar that opens in another clef or ends in the same one as
/// before.
Score _setClef(Score score, StaffId staff, ScorePoint at, Clef clef) {
  final index = _barIndex(score, at.measure);
  _staff(score, staff);
  final column = score.measures[index];
  _inside(column, at);
  final measure = column.staff(staff);
  final set = at.offset.isZero
      ? _withClefs(measure, clef, measure.clefChanges)
      : _withClefs(measure, measure.clef, [
          for (final c in measure.clefChanges)
            if (c.offset < at.offset) c,
          ClefChange(at.offset, clef),
          for (final c in measure.clefChanges)
            if (c.offset > at.offset) c,
        ]);
  if (identical(set, measure)) {
    return score;
  }
  final columns = [column.withStaff(set)];
  var (old, now) = (measure.clefAtEnd, set.clefAtEnd);
  for (var i = index + 1; i < score.measures.length && old != now; i++) {
    final next = score.measures[i].staff(staff);
    if (next.clef != old) {
      break;
    }
    final carried = _withClefs(next, now, next.clefChanges);
    columns.add(score.measures[i].withStaff(carried));
    (old, now) = (next.clefAtEnd, carried.clefAtEnd);
  }
  return score.copyWith(
    measures: score.measures.replaceRange(
      index,
      index + columns.length,
      columns,
    ),
  );
}

/// [measure] opening in [clef] with [changes], less each change to the
/// clef already in effect. The same object when that is what it had.
StaffMeasure _withClefs(
  StaffMeasure measure,
  Clef clef,
  Iterable<ClefChange> changes,
) {
  final kept = <ClefChange>[];
  var current = clef;
  for (final change in changes) {
    if (change.clef != current) {
      kept.add(change);
      current = change.clef;
    }
  }
  return clef == measure.clef && _same(kept, measure.clefChanges)
      ? measure
      : measure.copyWith(clef: clef, clefChanges: Seq(kept));
}

/// [score] with bar [measure]'s tempo marks replaced by [marks] in time
/// order. Refused when a mark lies outside the bar or two share a time.
Score _setTempoMarks(Score score, MeasureId measure, Seq<TempoMark> marks) {
  final index = _barIndex(score, measure);
  final column = score.measures[index];
  for (final mark in marks) {
    _inside(column, ScorePoint(measure, mark.offset));
    _check(tempoMarkProblem(mark.tempo));
  }
  final sorted = [...marks]..sort((a, b) => a.offset.compareTo(b.offset));
  for (var k = 1; k < sorted.length; k++) {
    if (sorted[k].offset == sorted[k - 1].offset) {
      throw _Refuse(
        InvalidValue('two tempo marks at ${sorted[k].offset.wholeNotes}'),
      );
    }
  }
  if (_same(sorted, column.tempos)) {
    return score;
  }
  return score.copyWith(
    measures: score.measures.replaceAt(
      index,
      column.copyWith(tempos: Seq(sorted)),
    ),
  );
}

/// Replaces the value carried by a run of bars: bar [start] and every
/// following bar for which [carries] holds, stopping at the first that does
/// not. This is how "a change applies until the next change" works when each
/// bar stores its own context. One `replaceRange` over the run.
Seq<MeasureColumn> _propagate(
  Seq<MeasureColumn> measures,
  int start, {
  required bool Function(MeasureColumn column) carries,
  required MeasureColumn Function(MeasureColumn column) update,
}) {
  var end = start + 1;
  while (end < measures.length && carries(measures[end])) {
    end++;
  }
  return measures.replaceRange(start, end, [
    for (var i = start; i < end; i++) update(measures[i]),
  ]);
}
