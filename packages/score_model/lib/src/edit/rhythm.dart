part of 'session.dart';

_Result _enterTuplet(
  Score score,
  VoicePoint at,
  TupletRatio ratio,
  NoteValue unit,
  _Ids ids,
) {
  _check(
    ratioTermProblem(ratio.actual) ??
        ratioTermProblem(ratio.normal) ??
        valueProblem(unit),
  );
  final tuplet = Tuplet(
    id: ids.tuplet(),
    ratio: ratio,
    unit: unit,
    members: Seq([
      for (var k = 0; k < ratio.actual; k++)
        RestEvent(id: ids.event(), value: unit),
    ]),
  );
  final write = _overwrite(score, at, [tuplet], ids, Overfill.refuse);
  return _Result(
    _untieInto(write.score, at, const {}),
    cursor: at,
    selection: Selection.event(write.first),
  );
}

/// [timed] rewritten at [value] from its onset. It keeps its ids, its marks
/// and the ties into it. A tie out of it stays only while it ends on the
/// head it ended on before, or on none.
Score _setValue(Score score, TimedEvent timed, NoteValue value, _Ids ids) {
  final unchanged = switch (timed.event) {
    ChordEvent(value: final old) || RestEvent(value: final old) => old == value,
    MeasureRest() => false,
  };
  if (unchanged) {
    return score;
  }
  final write = _overwrite(
    score,
    VoicePoint(
      staff: timed.ref.staff,
      voice: timed.voice,
      at: ScorePoint(timed.ref.measure, timed.onset),
    ),
    [_piece(timed.event, value, ids, first: true, tied: false)],
    ids,
    Overfill.splitAndTie,
  );
  final last = write.score.lookup(write.last)!;
  final chord = last.event;
  final before = _next(score, timed);
  final after = _next(write.score, last);
  bool moves(Note note) => _tieMoves(note, before, after);
  return chord is ChordEvent && chord.notes.any(moves)
      ? _replace(write.score, last, _untied(chord, moves))
      : write.score;
}
