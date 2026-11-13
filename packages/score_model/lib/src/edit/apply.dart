part of 'session.dart';

/// Mints ids for one edit, starting at the session's counter. Mutable, but
/// scoped to a single `run` call; the session keeps [next] afterwards.
final class _Ids {
  _Ids(this.next);

  int next;

  EventId event() => EventId(next++);
  NoteId note() => NoteId(next++);
  MeasureId measure() => MeasureId(next++);
  TupletId tuplet() => TupletId(next++);
  SpannerId spanner() => SpannerId(next++);
  PartId part() => PartId(next++);
  StaffId staff() => StaffId(next++);
}

/// Thrown inside the engine to abandon an edit; caught only by
/// [EditSession.run], which turns it into [Refused]. Never escapes the
/// library.
final class _Refuse implements Exception {
  const _Refuse(this.reason);

  final EditRefusal reason;
}

/// What an applied edit produced. Null cursor or selection means "keep the
/// session's, revalidated against the new score".
final class _Result {
  const _Result(this.score, {this.cursor, this.selection});

  final Score score;
  final VoicePoint? cursor;
  final Selection? selection;
}

_Result _apply(Score score, Edit edit, _Ids ids, EditSession session) {
  return switch (edit) {
    EnterNote(
      :final at,
      :final tone,
      :final value,
      :final overfill,
      :final beam,
      :final appendBar,
      ripple: Ripple.none,
    ) =>
      _enter(
        score,
        at,
        ChordEvent(
          id: ids.event(),
          value: _checked(value),
          beam: beam,
          notes: Seq([_noteOn(score, at.staff, ids.note(), tone)]),
        ),
        ids,
        overfill,
        appendBar: appendBar,
      ),
    EnterNote(
      :final at,
      :final tone,
      :final value,
      :final overfill,
      :final beam,
      :final appendBar,
      ripple: Ripple.part,
    ) =>
      _enterRippled(
        score,
        at,
        ChordEvent(
          id: ids.event(),
          value: _checked(value),
          beam: beam,
          notes: Seq([_noteOn(score, at.staff, ids.note(), tone)]),
        ),
        ids,
        overfill,
        appendBar: appendBar,
        session: session,
      ),
    EnterRest(
      :final at,
      :final value,
      :final overfill,
      :final appendBar,
      ripple: Ripple.none,
    ) =>
      _enter(
        score,
        at,
        RestEvent(id: ids.event(), value: _checked(value)),
        ids,
        overfill,
        appendBar: appendBar,
      ),
    EnterRest(
      :final at,
      :final value,
      :final overfill,
      :final appendBar,
      ripple: Ripple.part,
    ) =>
      _enterRippled(
        score,
        at,
        RestEvent(id: ids.event(), value: _checked(value)),
        ids,
        overfill,
        appendBar: appendBar,
        session: session,
      ),
    AddToChord(:final event, :final tone) => _addToChord(
      score,
      event,
      tone,
      ids,
    ),
    RemoveNote(:final note) => _Result(
      _removeNote(score, _targetHead(score, note)),
    ),
    SetTone(:final note, :final tone) => _setNoteTone(score, note, tone),
    SetValue(:final event, :final value, ripple: Ripple.none) => _Result(
      _setValue(score, _target(score, event), _checked(value), ids),
    ),
    SetValue(:final event, :final value, ripple: Ripple.part) =>
      _setValueRippled(score, event, _checked(value), ids, session),
    EnterTuplet(:final at, :final ratio, :final unit) => _enterTuplet(
      score,
      at,
      ratio,
      unit,
      ids,
    ),
    AddGrace(:final event, :final tone, :final kind, :final value) => _addGrace(
      score,
      event,
      tone,
      kind,
      value,
      ids,
    ),
    SetTie(:final note, :final tied) => _setTie(score, note, tied),
    Erase(:final selection, ripple: Ripple.none) => _Result(
      _erase(_unspanned(score, selection), selection, ids),
    ),
    Erase(:final selection, ripple: Ripple.part) => _eraseRippled(
      _unspanned(score, selection),
      selection,
      ids,
      session,
    ),
    SetArticulation(:final event, :final articulation, :final present) =>
      _setArticulation(score, event, articulation, present),
    SetOrnament(:final event, :final ornament) => _setOrnament(
      score,
      event,
      ornament,
    ),
    SetBowing(:final event, :final bowing) => _setBowing(score, event, bowing),
    SetBeam(:final event, :final mode) => _setBeam(score, event, mode),
    SetFingering(:final note, :final finger) => _setFingering(
      score,
      note,
      finger,
    ),
    SetString(:final note, :final string) => _setString(score, note, string),
    SetAccidental(:final note, :final request) => _setAccidental(
      score,
      note,
      request,
    ),
    SetLyric(:final event, :final verse, :final lyric) => _setLyric(
      score,
      event,
      verse,
      lyric,
    ),
    SetDirections(:final staff, :final measure, :final directions) => _Result(
      _setDirections(score, staff, measure, directions),
    ),
    AddSpanner(
      :final kind,
      :final staff,
      :final voice,
      :final first,
      :final last,
    ) =>
      _addSpanner(score, kind, staff, voice, first, last, ids),
    RemoveSpanner(:final spanner) => _removeSpanner(score, spanner),
    SetMeter() => _setMeter(score, edit, ids, session),
    SetKey(:final from, :final key) => _setKey(score, from, key),
    SetClef(:final staff, :final at, :final clef) => _Result(
      _setClef(score, staff, at, clef),
    ),
    SetTempoMarks(:final measure, :final marks) => _Result(
      _setTempoMarks(score, measure, marks),
    ),
    InsertMeasures(:final before, :final count) => _insertMeasuresBefore(
      score,
      before,
      count,
      ids,
    ),
    DeleteMeasures(:final first, :final last) => _deleteMeasuresBetween(
      score,
      first,
      last,
      ids,
    ),
    SetBarline(:final measure, :final barline) => _setBarline(
      score,
      measure,
      barline,
    ),
    SetRepeatStart(:final measure, :final start) => _setRepeatStart(
      score,
      measure,
      start,
    ),
    SetRepeatEnd(:final measure, :final end) => _setRepeatEnd(
      score,
      measure,
      end,
    ),
    SetVolta(:final first, :final last, :final volta) => _setVolta(
      score,
      first,
      last,
      volta,
    ),
    SetNavigation(:final measure, :final marks) => _setNavigation(
      score,
      measure,
      marks,
    ),
    SetRehearsal(:final measure, :final text) => _setRehearsal(
      score,
      measure,
      text,
    ),
    SetBarLength(:final measure, :final length) => _Result(
      _setBarLength(score, _barIndex(score, measure), length, ids),
    ),
    SetBreak(:final measure, :final layoutBreak) => _setBreak(
      score,
      measure,
      layoutBreak,
    ),
    SetKeyDisplay(:final measure, :final display) => _setKeyDisplay(
      score,
      measure,
      display,
    ),
    SetMeterDisplay(:final measure, :final display) => _setMeterDisplay(
      score,
      measure,
      display,
    ),
    Paste(:final clip, :final at, :final overfill) => _paste(
      score,
      clip,
      at,
      ids,
      overfill,
    ),
    Transpose(:final selection, :final by) => _transpose(score, selection, by),
    AddPart(:final template, :final index) => _Result(
      _addPart(score, template, index, ids),
    ),
    RemovePart(:final part) => _removePart(score, part, session.cursor),
    SetPartHidden(:final part, :final hidden) => _setPartHidden(
      score,
      part,
      hidden,
      session.cursor,
    ),
    Batch(:final edits) => _batch(edits, ids, session),
  };
}

/// A resolved note head: the event holding it, as a chord, and the head.
typedef _Head = ({TimedEvent timed, ChordEvent chord, Note note});

TimedEvent _target(Score score, EventRef ref) =>
    score.lookup(ref) ?? (throw _Refuse(StaleReference(ref)));

_Head _targetHead(Score score, NoteRef ref) =>
    _headWhere(_target(score, ref.event), (note) => note.id == ref.note) ??
    (throw _Refuse(StaleReference(ref)));

/// Whether [note]'s tie would end on another head, or on none where it
/// ended on one, if the event after it were [after] instead of [before].
/// [from] is the tone [note] had before, when it changed.
bool _tieMoves(
  Note note,
  TimedEvent? before,
  TimedEvent? after, {
  Tone? from,
}) =>
    note.tie &&
    headOfTone(before?.event, from ?? note.tone)?.id !=
        headOfTone(after?.event, note.tone)?.id;

/// The head of [timed] that [matches], or null when [timed] is null, a
/// rest, or has no such head.
_Head? _headWhere(TimedEvent? timed, bool Function(Note note) matches) {
  if (timed case TimedEvent(event: final ChordEvent chord)) {
    for (final note in chord.notes) {
      if (matches(note)) {
        return (timed: timed, chord: chord, note: note);
      }
    }
  }
  return null;
}

/// The head of [timed] with [tone], as [headOfTone] finds it, or null when
/// [timed] is null, a rest, or has no head of that tone.
_Head? _headOfTone(TimedEvent? timed, Tone tone) {
  if (timed case TimedEvent(event: final ChordEvent chord)) {
    if (headOfTone(chord, tone) case final note?) {
      return (timed: timed, chord: chord, note: note);
    }
  }
  return null;
}

/// [score] with [timed]'s voice rewritten by [write]. Rebuilds one column.
Score _rewriteVoice(
  Score score,
  TimedEvent timed,
  List<VoiceItem> Function(Seq<VoiceItem> items) write,
) {
  final column = score.column(timed.ref.measure);
  final staff = column.staff(timed.ref.staff);
  return score.copyWith(
    measures: score.measures.replaceAt(
      score.indexOf(column.id),
      column.withStaff(
        staff.withVoice(
          Voice(
            slot: timed.voice,
            items: Seq(write(staff.voice(timed.voice)!.items)),
          ),
        ),
      ),
    ),
  );
}

/// [score] with [replacement] in place of the event with its id in
/// [timed]'s voice.
Score _replace(Score score, TimedEvent timed, Event replacement) =>
    _rewriteVoice(
      score,
      timed,
      (items) => [
        for (final item in items)
          item is Content ? _replaceEvent(item, replacement) : item,
      ],
    );

/// [head] and every head tied to it, in time order. A tie joins a head to
/// the head of the same tone in the adjacent event of its voice, as
/// `measureView` draws it.
List<_Head> _tieChain(Score score, _Head head) {
  final tone = head.note.tone;
  final chain = [head];
  while (true) {
    final back = _headOfTone(_previous(score, chain.first.timed), tone);
    if (back == null || !back.note.tie) {
      break;
    }
    chain.insert(0, back);
  }
  while (chain.last.note.tie) {
    final ahead = _headOfTone(_next(score, chain.last.timed), tone);
    if (ahead == null) {
      break;
    }
    chain.add(ahead);
  }
  return chain;
}

/// The event of [timed]'s voice that starts where [timed] ends, later in
/// its bar or at the start of the next. Null at a gap or the end of the
/// score.
TimedEvent? _next(Score score, TimedEvent timed) {
  final end = _normalize(
    score,
    ScorePoint(timed.ref.measure, timed.onset + timed.duration),
  );
  return end == null
      ? null
      : score.eventAt(
          VoicePoint(staff: timed.ref.staff, voice: timed.voice, at: end),
        );
}

/// The event of [timed]'s voice that ends where [timed] starts, earlier in
/// its bar or at the end of the one before. Null at a gap or the start of
/// the score.
TimedEvent? _previous(Score score, TimedEvent timed) {
  var index = score.indexOf(timed.ref.measure);
  var end = timed.onset;
  if (end.isZero) {
    if (index == 0) {
      return null;
    }
    index--;
    end = _barEnd(score.measures[index]);
  }
  final column = score.measures[index];
  final voice = column.staff(timed.ref.staff).voice(timed.voice);
  if (voice == null) {
    return null;
  }
  return timedEvents(
    voice,
    measure: column.id,
    staff: timed.ref.staff,
  ).where((e) => e.onset + e.duration == end).firstOrNull;
}

/// The (bar index, staff) lanes [range] spans, its staves, and whether a
/// point lies in it. Refused with [StaleReference] for a gone bar or staff
/// and [OutsideMeasure] for an end outside its bar.
({
  Set<(int, StaffId)> lanes,
  Set<StaffId> staves,
  bool Function(ScorePoint point) inRange,
})
_covers(Score score, RangeSelection range) {
  final RangeSelection(:from, :to, :top, :bottom) = range;
  final first = _barIndex(score, from.measure);
  final last = _barIndex(score, to.measure);
  if (_outsideBar(score, range) case final point?) {
    throw _Refuse(OutsideMeasure(point));
  }
  final staves =
      (score.stavesBetween(top, bottom) ??
              (throw _Refuse(
                StaleReference(
                  score.staves.any((staff) => staff.id == top) ? bottom : top,
                ),
              )))
          .toSet();
  return (
    lanes: {
      for (var bar = first; bar <= last; bar++)
        for (final staff in staves) (bar, staff),
    },
    staves: staves,
    inRange: (point) =>
        score.compare(point, from) >= 0 && score.compare(point, to) < 0,
  );
}

/// The end of [range] that lies outside its bar, or null when neither does.
/// The start lies before the end of its bar and the end may sit on it.
ScorePoint? _outsideBar(Score score, RangeSelection range) {
  final RangeSelection(:from, :to) = range;
  if (from.offset.isNegative ||
      from.offset >= _barEnd(score.column(from.measure))) {
    return from;
  }
  if (to.offset.isNegative || to.offset > _barEnd(score.column(to.measure))) {
    return to;
  }
  return null;
}

/// [after] without the ties, in [lanes] and the bars before them, that end
/// on another head than they did in [before], or on none where they ended
/// on one.
Score _retie(Score before, Score after, Set<(int, StaffId)> lanes) {
  final checked = {
    for (final (bar, staff) in lanes) ...[
      (bar, staff),
      if (bar > 0) (bar - 1, staff),
    ],
  };
  bool moves(TimedEvent timed, ChordEvent chord, Note note) {
    final old = before.lookup(timed.ref)!;
    final tones = {
      if (old.event case ChordEvent(:final notes))
        for (final note in notes) note.id: note.tone,
    };
    return _tieMoves(
      note,
      _next(before, old),
      _next(after, timed),
      from: tones[note.id],
    );
  }

  return _untieWhere(after, checked, moves);
}

/// [after] with every tie cleared that [moves] picks, in each voice of
/// each lane, a bar and staff of [after]. [moves] is asked of each tied
/// head with the event and chord that hold it, and reads only the scores
/// it was built over, never the partly untied one.
Score _untieWhere(
  Score after,
  Iterable<(int bar, StaffId staff)> lanes,
  bool Function(TimedEvent timed, ChordEvent chord, Note note) moves,
) {
  var untied = after;
  for (final (bar, staff) in lanes) {
    final column = after.measures[bar];
    for (final voice in column.staff(staff).voices) {
      for (final timed in timedEvents(
        voice,
        measure: column.id,
        staff: staff,
      )) {
        final chord = timed.event;
        if (chord is! ChordEvent || !chord.notes.any((n) => n.tie)) {
          continue;
        }
        bool clears(Note note) => moves(timed, chord, note);
        if (chord.notes.any(clears)) {
          untied = _replace(untied, timed, _untied(chord, clears));
        }
      }
    }
  }
  return untied;
}

/// Refuses [staff] when the score no longer has it.
void _staff(Score score, StaffId staff) {
  if (!score.staves.any((s) => s.id == staff)) {
    throw _Refuse(StaleReference(staff));
  }
}

/// Refuses [point] when it does not lie inside [column].
void _inside(MeasureColumn column, ScorePoint point) {
  if (point.offset.isNegative || point.offset >= _barEnd(column)) {
    throw _Refuse(OutsideMeasure(point));
  }
}

/// A new head playing [tone] on [staff]. Refused unless the tone suits the
/// staff.
Note _noteOn(
  Score score,
  StaffId staff,
  NoteId id,
  Tone tone, {
  bool tie = false,
}) {
  _checkTone(score, staff, tone);
  return switch (tone) {
    Pitch() => PitchedNote(id: id, pitch: tone, tie: tie),
    Drum() => DrumNote(id: id, drum: tone, tie: tie),
  };
}

/// Refuses [tone] unless it suits [staff]: a pitch in the MIDI range on a
/// pitched staff, or a drum of the part's kit on a percussion staff.
void _checkTone(Score score, StaffId staff, Tone tone) {
  _staff(score, staff);
  _check(toneProblem(score.partOf(staff).instrument, tone));
}

void _check(String? problem) {
  if (problem != null) {
    throw _Refuse(InvalidValue(problem));
  }
}

NoteValue _checked(NoteValue value) {
  _check(valueProblem(value));
  return value;
}

/// A refusal escapes the fold, so the batch is all or nothing.
_Result _batch(List<Edit> edits, _Ids ids, EditSession session) {
  final end = edits.fold(session, (now, edit) => now._advance(edit, ids));
  return _Result(end.score, cursor: end.cursor, selection: end.selection);
}
