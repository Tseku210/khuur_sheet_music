part of 'session.dart';

/// [after], an edit of [before], without the ties the edit moved: a tie
/// that landed on a head and now lands on none, or on another head that
/// [before] had. A tie on a head the edit made, a tie that landed on no
/// head, and a tie that lands on a head the edit made keep their marks;
/// an edit that means to drop one of those drops it itself.
///
/// Only the lanes whose staff measures the edit wrote, or whose next bar
/// it changed, and the bars before them, are looked at.
Score _withTiesSettled(Score before, Score after) {
  if (identical(before, after) || identical(before.measures, after.measures)) {
    return after;
  }
  bool moves(TimedEvent timed, ChordEvent chord, Note note) {
    final old = _sameBar(before, timed.ref);
    final was = _headWhere(old, (n) => n.id == note.id)?.note;
    if (was == null || !was.tie) {
      return false;
    }
    final landed = _headOfTone(_next(before, old!), was.tone);
    if (landed == null) {
      return false;
    }
    final lands = _headOfTone(_next(after, timed), note.tone);
    if (lands == null) {
      return true;
    }
    return lands.note.id != landed.note.id &&
        _headWhere(
              _sameBar(before, lands.timed.ref),
              (n) => n.id == lands.note.id,
            ) !=
            null;
  }

  return _untieWhere(after, _writtenLanes(before, after), moves);
}

/// The (bar index, staff) lanes of [after] whose staff measure is not the
/// one [before] had in that bar, or whose bar is followed by another bar
/// than it was, and the lane before each.
Set<(int, StaffId)> _writtenLanes(Score before, Score after) {
  final lanes = <(int, StaffId)>{};
  final bars = after.measures;
  for (var bar = 0; bar < bars.length; bar++) {
    final column = bars[bar];
    final was = before.contains(column.id) ? before.indexOf(column.id) : null;
    final kept = was != null && _nextId(before, was) == _nextId(after, bar)
        ? before.measures[was]
        : null;
    for (final staff in column.staves) {
      if (kept != null && identical(staff, _measureOf(kept, staff.staff))) {
        continue;
      }
      lanes.add((bar, staff.staff));
      if (bar > 0) {
        lanes.add((bar - 1, staff.staff));
      }
    }
  }
  return lanes;
}

/// The id of the bar after bar [bar] of [score], or null at the end.
MeasureId? _nextId(Score score, int bar) =>
    bar + 1 < score.measures.length ? score.measures[bar + 1].id : null;

/// [column]'s measure of [staff], or null when it has none.
StaffMeasure? _measureOf(MeasureColumn column, StaffId staff) {
  for (final measure in column.staves) {
    if (measure.staff == staff) {
      return measure;
    }
  }
  return null;
}

/// The event of [score] that [ref] names, found only in [ref]'s own bar,
/// or null when that bar or the event is not there.
TimedEvent? _sameBar(Score score, EventRef ref) {
  if (!score.contains(ref.measure)) {
    return null;
  }
  final column = score.column(ref.measure);
  final staff = _measureOf(column, ref.staff);
  if (staff == null) {
    return null;
  }
  for (final voice in staff.voices) {
    for (final timed in timedEvents(
      voice,
      measure: column.id,
      staff: ref.staff,
    )) {
      if (timed.event.id == ref.id) {
        return timed;
      }
    }
  }
  return null;
}
