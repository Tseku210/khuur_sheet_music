part of 'session.dart';

/// [after], an edit of [before], without the ties the edit moved. Each tie
/// [before] had in a lane the edit wrote keeps its mark only while it lands
/// where it did: on the same head, or on no head where it landed on none.
/// A tie that now lands on a head the edit made in the tie's own voice
/// keeps its mark too, since that head is the edit's own, as a note it
/// entered of the tie's tone. A tie lands where [tieLanding] says, and a
/// tie that lands on a tied head the edit made, such as the next piece of
/// a chord the edit cut in two, lands where that head's tie lands. The
/// last tie of such a chain is the one cleared. A tie the edit set or
/// made is its own and is left alone.
Score _withTiesSettled(Score before, Score after) {
  if (identical(before, after) || identical(before.measures, after.measures)) {
    return after;
  }
  final written = _written(before, after);
  final clears = <NoteId>{};
  _forEachTie(after, written.lanes, (timed, note) {
    final old = written.headOf(timed, note.id);
    if (old == null || !old.note.tie) {
      return;
    }
    final landed = _landing(before, old.timed, old.note)?.note.id;
    var tied = (timed: timed, note: note);
    final seen = {note.id};
    while (true) {
      final lands = _landing(after, tied.timed, tied.note);
      final keeps = switch (lands) {
        null => landed == null,
        _ when written.headOf(lands.timed, lands.note.id) != null =>
          lands.note.id == landed,
        _ when lands.timed.voice != tied.timed.voice => false,
        _ when lands.note.tie && seen.add(lands.note.id) => null,
        _ => true,
      };
      if (keeps == null) {
        tied = (timed: lands!.timed, note: lands.note);
        continue;
      }
      if (!keeps) {
        clears.add(tied.note.id);
      }
      return;
    }
  });
  return clears.isEmpty
      ? after
      : _untieWhere(
          after,
          written.lanes,
          (_, _, note) => clears.contains(note.id),
        );
}

/// Calls [visit] with each tied head of [score] in [lanes].
void _forEachTie(
  Score score,
  Iterable<(int bar, StaffId staff)> lanes,
  void Function(TimedEvent timed, Note note) visit,
) {
  for (final (bar, staff) in lanes) {
    final column = score.measures[bar];
    for (final voice in column.staff(staff).voices) {
      for (final timed in timedEvents(
        voice,
        measure: column.id,
        staff: staff,
      )) {
        if (timed.event case ChordEvent(:final notes)) {
          for (final note in notes) {
            if (note.tie) {
              visit(timed, note);
            }
          }
        }
      }
    }
  }
}

/// The head that a tie from [note] of [timed] lands on in [score], as
/// [tieLanding] says, or null when it lands on none.
_Head? _landing(Score score, TimedEvent timed, Note note) {
  final bar = score.indexOf(timed.ref.measure);
  final column = score.measures[bar];
  final staff = timed.ref.staff;
  final end = timed.onset + timed.duration;
  final List<VoiceAround> voices;
  if (end == _barEnd(column)) {
    if (bar + 1 == score.measures.length) {
      return null;
    }
    voices = voicesAtBarline(column, score.measures[bar + 1], staff);
  } else {
    voices = voicesInside([
      for (final voice in column.staff(staff).voices)
        (voice, timedEvents(voice, measure: column.id, staff: staff).toList()),
    ], end);
  }
  final to = tieLandingAround(note, timed.voice, voices);
  if (to == null) {
    return null;
  }
  for (final (:starting, slot: _, ending: _) in voices) {
    if (starting != null && starting.ref == to.event) {
      return _headWhere(starting, (head) => head.id == to.note);
    }
  }
  return null;
}

/// A head of a score as an edit found it.
typedef _Tied = ({TimedEvent timed, Note note});

/// What an edit of [before] into [after] wrote: its lanes, the (bar
/// index, staff) lanes of [after] whose staff measure [before] did not
/// hold there, and the lane before each, and a lookup that finds a head of
/// [after] in [before], or answers null for a head the edit made.
({
  Set<(int, StaffId)> lanes,
  _Tied? Function(TimedEvent timed, NoteId note) headOf,
})
_written(Score before, Score after) {
  final lanes = <(int, StaffId)>{};
  void write(int bar, StaffId staff) {
    lanes.add((bar, staff));
    if (bar > 0) {
      lanes.add((bar - 1, staff));
    }
  }

  final (was, now) = (before.measures, after.measures);
  final gone = <MeasureColumn>[];
  if (was.length == now.length) {
    for (final bar in now.indexesNotIn(was)) {
      final (old, column) = (was[bar], now[bar]);
      gone.add(old);
      for (final staff in column.staves) {
        if (old.id != column.id ||
            !identical(staff, _measureOf(old, staff.staff))) {
          write(bar, staff.staff);
        }
      }
    }
  } else {
    final shorter = min(was.length, now.length);
    var start = 0;
    while (start < shorter && identical(was[start], now[start])) {
      start++;
    }
    var end = 0;
    while (end < shorter - start &&
        identical(was[was.length - 1 - end], now[now.length - 1 - end])) {
      end++;
    }
    gone.addAll([
      for (var bar = start; bar < was.length - end; bar++) was[bar],
    ]);
    for (var bar = start; bar < now.length - end; bar++) {
      for (final staff in now[bar].staves) {
        write(bar, staff.staff);
      }
    }
  }
  Map<NoteId, _Tied>? moved;
  return (
    lanes: lanes,
    headOf: (timed, note) {
      if (_headWhere(before.inItsBar(timed.ref), (n) => n.id == note)
          case final head?) {
        return (timed: head.timed, note: head.note);
      }
      return (moved ??= {
        for (final column in gone)
          for (final staff in column.staves)
            for (final voice in staff.voices)
              for (final timed in timedEvents(
                voice,
                measure: column.id,
                staff: staff.staff,
              ))
                if (timed.event case ChordEvent(:final notes))
                  for (final note in notes) note.id: (timed: timed, note: note),
      })[note];
    },
  );
}

/// [column]'s measure of [staff], or null when it has none.
StaffMeasure? _measureOf(MeasureColumn column, StaffId staff) {
  for (final measure in column.staves) {
    if (measure.staff == staff) {
      return measure;
    }
  }
  return null;
}
