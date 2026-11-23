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
  final spanner = _withChosenEnd(
    score,
    Spanner(
      id: ids.spanner(),
      kind: kind,
      staff: staff,
      voice: kind.joinsNotes ? voice ?? VoiceSlot.one : null,
      first: first,
      last: last,
    ),
  );
  if (spannerProblem(score, spanner) != null) {
    final name = _spannerName(kind);
    throw _Refuse(
      InvalidValue(
        kind.joinsNotes
            ? '$name must end after it starts'
            : '$name cannot end before it starts',
      ),
    );
  }
  if (lostGlissandoNote(score, spanner) case final note?) {
    throw _Refuse(StaleReference(note));
  }
  return _Result(
    score.copyWith(spanners: score.spanners.append(endsHeld(score, spanner))),
  );
}

/// [spanner] with the last end of a new glissando chosen. A line from a note
/// that names no last note and would end on a rest names a note of the first
/// chord a voice of its staff starts there, in voice order from voice one.
Spanner _withChosenEnd(Score score, Spanner spanner) {
  final line = spanner.kind;
  if (line is! Glissando || line.to != null) {
    return spanner;
  }
  final start = score.anchorOf(spanner, last: false)?.event;
  final end = score.anchorOf(spanner, last: true)?.event;
  if (start is! ChordEvent || end == null || end is ChordEvent) {
    return spanner;
  }
  for (final voice in VoiceSlot.values) {
    final timed = score.eventAt(
      VoicePoint(staff: spanner.staff, voice: voice, at: spanner.last),
    );
    if (timed != null &&
        timed.onset == spanner.last.offset &&
        timed.event is ChordEvent) {
      final to = line
          .notesOn(
            start,
            timed.event,
            instrument: score.partOf(spanner.staff).instrument,
          )
          .to;
      return Spanner(
        id: spanner.id,
        kind: Glissando(from: line.from, to: to?.id),
        staff: spanner.staff,
        voice: spanner.voice,
        first: spanner.first,
        last: spanner.last,
      );
    }
  }
  return spanner;
}

/// [kind] as a refusal names it. A class name read at run time is mangled
/// in an obfuscated build.
String _spannerName(SpannerKind kind) => switch (kind) {
  Slur() => 'a slur',
  Hairpin() => 'a hairpin',
  OctaveLine() => 'an octave line',
  TrillLine() => 'a trill line',
  TempoLine() => 'a tempo line',
  PedalLine() => 'a pedal line',
  Glissando() => 'a glissando',
};

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
  final sorted = stableSorted(
    directions,
    (a, b) => a.offset.compareTo(b.offset),
  );
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
