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
    EnterRest(:final at, :final value, :final overfill, :final appendBar) =>
      _enter(
        score,
        at,
        RestEvent(id: ids.event(), value: _checked(value)),
        ids,
        overfill,
        appendBar: appendBar,
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
    SetValue(:final event, :final value) => _Result(
      _setValue(score, _target(score, event), _checked(value), ids),
    ),
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
    Erase(:final selection) => _Result(_erase(score, selection, ids)),
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

/// The only articulation a rest can carry.
const Set<Articulation> _restMarks = {Articulation.fermata};

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
    _headWhere(before, (n) => n.tone == (from ?? note.tone))?.note.id !=
        _headWhere(after, (n) => n.tone == note.tone)?.note.id;

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
  bool samePitch(Note note) => note.tone == head.note.tone;
  final chain = [head];
  while (true) {
    final back = _headWhere(_previous(score, chain.first.timed), samePitch);
    if (back == null || !back.note.tie) {
      break;
    }
    chain.insert(0, back);
  }
  while (chain.last.note.tie) {
    final ahead = _headWhere(_next(score, chain.last.timed), samePitch);
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
  _inside(score.measures[first], from);
  if (to.offset.isNegative || to.offset > _barEnd(score.measures[last])) {
    throw _Refuse(OutsideMeasure(to));
  }
  final order = [for (final staff in score.staves) staff.id];
  final ends = [
    for (final staff in [top, bottom])
      order.contains(staff)
          ? order.indexOf(staff)
          : throw _Refuse(StaleReference(staff)),
  ];
  final staves = order.sublist(ends.reduce(min), ends.reduce(max) + 1).toSet();
  return (
    lanes: {
      for (var bar = first; bar <= last; bar++)
        for (final staff in staves) (bar, staff),
    },
    staves: staves,
    inRange: (point) =>
        !_precedes(score, point, from) && _precedes(score, point, to),
  );
}

/// [after] without the ties, in [lanes] and the bars before them, that end
/// on another head than they did in [before], or on none where they ended
/// on one.
Score _retie(Score before, Score after, Set<(int, StaffId)> lanes) {
  var retied = after;
  final checked = {
    for (final (bar, staff) in lanes) ...[
      (bar, staff),
      if (bar > 0) (bar - 1, staff),
    ],
  };
  for (final (bar, staff) in checked) {
    final column = after.measures[bar];
    for (final voice in column.staff(staff).voices) {
      for (final timed in timedEvents(
        voice,
        measure: column.id,
        staff: staff,
      )) {
        final event = timed.event;
        if (event is! ChordEvent) {
          continue;
        }
        final old = before.lookup(timed.ref)!;
        final tones = {
          if (old.event case ChordEvent(:final notes))
            for (final note in notes) note.id: note.tone,
        };
        final was = _next(before, old);
        final now = _next(after, timed);
        bool moves(Note note) =>
            _tieMoves(note, was, now, from: tones[note.id]);
        if (event.notes.any(moves)) {
          retied = _replace(retied, timed, _untied(event, moves));
        }
      }
    }
  }
  return retied;
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
  final instrument = score.partOf(staff).instrument;
  _check(switch (tone) {
    Pitch() when instrument.isPercussion => 'a percussion staff takes drums',
    Drum() when !instrument.isPercussion => 'a pitched staff takes pitches',
    Drum() when instrument.soundOf(tone) == null => 'the kit has no $tone',
    Pitch() => pitchProblem(tone),
    Drum() => null,
  });
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
