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
/// and the ties into it. A tie out of a chord made longer stays only while
/// it ends on the head it ended on before, or on none. A chord made shorter
/// is [_Loss.shortened].
Score _setValue(Score score, TimedEvent timed, NoteValue value, _Ids ids) {
  final unchanged = switch (timed.event) {
    ChordEvent(value: final old) || RestEvent(value: final old) => old == value,
    MeasureRest() => false,
  };
  if (unchanged) {
    return score;
  }
  final cut = switch (timed.event) {
    ChordEvent(value: final old) when value.length < old.length => _lose(
      score,
      timed,
      _Loss.shortened,
    ),
    _ => score,
  };
  final write = _overwrite(
    cut,
    VoicePoint(
      staff: timed.ref.staff,
      voice: timed.voice,
      at: ScorePoint(timed.ref.measure, timed.onset),
    ),
    [
      _piece(
        _target(cut, timed.ref).event,
        value,
        ids,
        first: true,
        tied: false,
      ),
    ],
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

/// What an edit takes from a chord whose time it changes, as MuseScore 4
/// does.
enum _Loss {
  /// The chord is made shorter where it stands, so the ties out of it and
  /// the glissandi that start on it go, as in `Score::changeCRlen`.
  shortened,

  /// The chord is taken out and written again, so the ties into it and the
  /// glissandi that end on it go too. MuseScore does this to a chord that
  /// loses its start to a time delete and to one that sounds across the
  /// place where an insert adds time.
  rebuilt,
}

/// [score] without what [loss] takes from [timed]. It is [score] itself
/// when [timed] is no chord or has none of it.
Score _lose(Score score, TimedEvent timed, _Loss loss) {
  final chord = timed.event;
  if (chord is! ChordEvent) {
    return score;
  }
  final rebuilt = loss == _Loss.rebuilt;
  var now = score;
  if (chord.notes.any((note) => note.tie)) {
    now = _replace(now, timed, _untied(chord, (_) => true));
  }
  if (rebuilt) {
    final before = _previous(score, timed);
    bool into(Note note) => note.tie && headOfTone(chord, note.tone) != null;
    if (before case TimedEvent(event: final ChordEvent prior)
        when prior.notes.any(into)) {
      now = _replace(now, before, _untied(prior, into));
    }
  }
  bool lost(Spanner spanner) =>
      spanner.kind is Glissando &&
      spanner.staff == timed.ref.staff &&
      (score.anchorOf(spanner, last: false)?.event.id == chord.id ||
          (rebuilt &&
              score.anchorOf(spanner, last: true)?.event.id == chord.id));
  return score.spanners.any(lost)
      ? now.copyWith(
          spanners: Seq(score.spanners.where((line) => !lost(line))),
        )
      : now;
}
