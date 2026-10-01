part of 'session.dart';

_Result _addSpanner(
  Score score,
  SpannerKind kind,
  StaffId staff,
  VoiceSlot? voice,
  ScorePoint first,
  ScorePoint last,
  _Ids ids,
) {
  _staff(score, staff);
  if (kind case TempoLine(:final factor)) {
    _check(factorProblem(factor));
  }
  for (final end in [first, last]) {
    _inside(score.measures[_barIndex(score, end.measure)], end);
  }
  final spanner = Spanner(
    id: ids.spanner(),
    kind: kind,
    staff: staff,
    voice: kind.joinsNotes ? voice ?? VoiceSlot.one : null,
    first: first,
    last: last,
  );
  if (!_fits(score, spanner)) {
    throw _Refuse(
      InvalidValue(
        kind.joinsNotes
            ? 'a ${kind.runtimeType} must end after it starts'
            : 'a ${kind.runtimeType} cannot end before it starts',
      ),
    );
  }
  return _Result(score.copyWith(spanners: score.spanners.append(spanner)));
}

_Result _removeSpanner(Score score, SpannerId spanner) {
  final index = score.spanners.indexWhere((s) => s.id == spanner);
  if (index < 0) {
    throw _Refuse(StaleReference(spanner));
  }
  return _Result(score.copyWith(spanners: score.spanners.removeAt(index)));
}

/// [score] with [staff]'s directions in bar [measure] replaced by
/// [directions] in time order, keeping the given order at one time.
Score _setDirections(
  Score score,
  StaffId staff,
  MeasureId measure,
  Seq<StaffDirection> directions,
) {
  final index = _barIndex(score, measure);
  _staff(score, staff);
  final column = score.measures[index];
  for (final direction in directions) {
    _inside(column, ScorePoint(measure, direction.offset));
  }
  final order = [...directions.indexed]
    ..sort((a, b) {
      final byTime = a.$2.offset.compareTo(b.$2.offset);
      return byTime != 0 ? byTime : a.$1 - b.$1;
    });
  final sorted = [for (final (_, direction) in order) direction];
  final old = column.staff(staff);
  if (_same(sorted, old.directions)) {
    return score;
  }
  return score.copyWith(
    measures: score.measures.replaceAt(
      index,
      column.withStaff(old.copyWith(directions: Seq(sorted))),
    ),
  );
}
