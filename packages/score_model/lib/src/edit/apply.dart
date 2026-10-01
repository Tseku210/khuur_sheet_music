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

/// Pure core of the edit engine: one switch, one case per edit.
///
/// Every case follows the same path: resolve targets (throwing
/// [StaleReference] if gone), rebuild the touched columns bottom-up
/// (event → voice → staff measure → column), and splice them into the
/// column list with one `Seq.replaceRange`. Untouched columns are shared.
_Result _apply(Score score, Edit edit, _Ids ids, EditSession session) {
  return switch (edit) {
    EnterNote(:final at, :final tone, :final value, :final overfill) => _enter(
      score,
      at,
      ChordEvent(
        id: ids.event(),
        value: _checked(value),
        notes: Seq([_noteOn(score, at.staff, ids.note(), tone)]),
      ),
      ids,
      overfill,
    ),
    EnterRest(:final at, :final value, :final overfill) => _enter(
      score,
      at,
      RestEvent(id: ids.event(), value: _checked(value)),
      ids,
      overfill,
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

// Edits that change one event in place: resolve the reference, rebuild
// that event, and walk back up. Touches one column, except [SetTone] on a
// tie chain and [RemoveNote] when it clears a tie from the bar before. An
// edit that changes nothing returns the same score.

_Result _setNoteTone(Score score, NoteRef note, Tone tone) {
  _checkTone(score, note.event.staff, tone);
  return _Result(_setTone(score, _targetHead(score, note), tone));
}

_Result _setTie(Score score, NoteRef note, bool tied) {
  final head = _targetHead(score, note);
  return _changeNote(
    score,
    head,
    head.note.tie == tied ? head.note : head.note.copyWith(tie: tied),
  );
}

_Result _setFingering(Score score, NoteRef note, int? finger) {
  if (finger != null) {
    _check(fingerProblem(finger));
  }
  final head = _targetHead(score, note);
  final pitched = _pitchedOnly(head, 'fingering');
  return _changeNote(
    score,
    head,
    pitched.fingering == finger
        ? pitched
        : pitched.copyWith(fingering: () => finger),
  );
}

_Result _setString(Score score, NoteRef note, int? string) {
  final head = _targetHead(score, note);
  final pitched = _pitchedOnly(head, 'string');
  final strings = score.partOf(head.timed.ref.staff).instrument.strings;
  if (string != null && (string < 0 || string >= strings.length)) {
    throw const _Refuse(InvalidValue('the instrument has no such string'));
  }
  return _changeNote(
    score,
    head,
    pitched.string == string ? pitched : pitched.copyWith(string: () => string),
  );
}

_Result _setAccidental(Score score, NoteRef note, AccidentalRequest request) {
  final head = _targetHead(score, note);
  final pitched = _pitchedOnly(head, 'accidental');
  return _changeNote(
    score,
    head,
    pitched.accidental == request
        ? pitched
        : pitched.copyWith(accidental: request),
  );
}

_Result _addGrace(
  Score score,
  EventRef event,
  Tone tone,
  GraceKind kind,
  NoteValue value,
  _Ids ids,
) {
  final timed = _target(score, event);
  return _changeEvent(
    score,
    timed,
    _chordOnly(
      timed.event,
      clears: false,
      change: (chord) => chord.copyWith(
        graces: chord.graces.append(
          GraceChord(
            id: ids.event(),
            kind: kind,
            value: _checked(value),
            notes: Seq([_noteOn(score, event.staff, ids.note(), tone)]),
          ),
        ),
      ),
    ),
  );
}

_Result _setArticulation(
  Score score,
  EventRef event,
  Articulation articulation,
  bool present,
) {
  final timed = _target(score, event);
  final marks = timed.event.articulations;
  if (marks.contains(articulation) == present) {
    return _Result(score);
  }
  if (present &&
      timed.event is! ChordEvent &&
      !_restMarks.contains(articulation)) {
    throw const _Refuse(InvalidValue('a rest holds only a fermata'));
  }
  return _changeEvent(
    score,
    timed,
    _withArticulations(
      timed.event,
      present ? {...marks, articulation} : marks.difference({articulation}),
    ),
  );
}

_Result _setOrnament(Score score, EventRef event, Ornament? ornament) {
  final timed = _target(score, event);
  return _changeEvent(
    score,
    timed,
    _chordOnly(
      timed.event,
      clears: ornament == null,
      change: (chord) => chord.ornament == ornament
          ? chord
          : chord.copyWith(ornament: () => ornament),
    ),
  );
}

_Result _setBowing(Score score, EventRef event, Bowing? bowing) {
  final timed = _target(score, event);
  return _changeEvent(
    score,
    timed,
    _chordOnly(
      timed.event,
      clears: bowing == null,
      change: (chord) =>
          chord.bowing == bowing ? chord : chord.copyWith(bowing: () => bowing),
    ),
  );
}

_Result _setLyric(Score score, EventRef event, int verse, Lyric? lyric) {
  if (verse < 1 || (lyric != null && lyric.verse != verse)) {
    throw const _Refuse(
      InvalidValue('a lyric is set in its own verse, counted from 1'),
    );
  }
  final timed = _target(score, event);
  return _changeEvent(
    score,
    timed,
    _chordOnly(
      timed.event,
      clears: lyric == null,
      change: (chord) => _withLyric(chord, verse, lyric),
    ),
  );
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

_Result _changeEvent(Score score, TimedEvent timed, Event changed) => _Result(
  identical(changed, timed.event) ? score : _replace(score, timed, changed),
);

_Result _changeNote(Score score, _Head head, Note changed) => _changeEvent(
  score,
  head.timed,
  identical(changed, head.note) ? head.chord : _withHead(head.chord, changed),
);

/// [chord] with [note] in place of the head with its id.
ChordEvent _withHead(ChordEvent chord, Note note) => chord.copyWith(
  notes: chord.notes.replaceAt(
    chord.notes.indexWhere((n) => n.id == note.id),
    note,
  ),
);

/// [change] applied to [event] when it is a chord. A rest refuses, unless
/// the edit [clears] something a rest never holds, which changes nothing.
Event _chordOnly(
  Event event, {
  required bool clears,
  required Event Function(ChordEvent chord) change,
}) => switch (event) {
  final ChordEvent chord => change(chord),
  _ when clears => event,
  _ => throw const _Refuse(InvalidValue('only a note can hold this')),
};

Event _withArticulations(Event event, Set<Articulation> marks) {
  final articulations = Set<Articulation>.unmodifiable(marks);
  return switch (event) {
    ChordEvent() => event.copyWith(articulations: articulations),
    RestEvent(:final id, :final value, :final hidden) => RestEvent(
      id: id,
      value: value,
      hidden: hidden,
      articulations: articulations,
    ),
    MeasureRest(:final id, :final span) => MeasureRest(
      id: id,
      span: span,
      articulations: articulations,
    ),
  };
}

/// [chord] with verse [verse] set to [lyric], or cleared when null. Lyrics
/// stay in verse order.
ChordEvent _withLyric(ChordEvent chord, int verse, Lyric? lyric) {
  final at = chord.lyrics.indexWhere((l) => l.verse == verse);
  if (at == -1 ? lyric == null : chord.lyrics[at] == lyric) {
    return chord;
  }
  return chord.copyWith(
    lyrics: Seq(
      [
        for (final l in chord.lyrics)
          if (l.verse != verse) l,
        ?lyric,
      ]..sort((a, b) => a.verse - b.verse),
    ),
  );
}

/// Removes [head]. The last head leaves a rest of the chord's value, which
/// keeps only a fermata of what the chord carried. A tie into the head from
/// the event before is cleared, as note entry clears one.
Score _removeNote(Score score, _Head head) {
  final (:timed, :chord, :note) = head;
  final left = chord.notes.length > 1
      ? chord.copyWith(
          notes: chord.notes.removeAt(
            chord.notes.indexWhere((n) => n.id == note.id),
          ),
        )
      : RestEvent(
          id: chord.id,
          value: chord.value,
          articulations: Set.unmodifiable(
            chord.articulations.intersection(_restMarks),
          ),
        );
  final into = _headWhere(
    _previous(score, timed),
    (n) => n.tie && n.tone == note.tone,
  );
  final untied = into == null
      ? score
      : _replace(
          score,
          into.timed,
          _withHead(into.chord, into.note.copyWith(tie: false)),
        );
  return _replace(untied, timed, left);
}

/// Moves [head] and every head tied to it to [tone], keeping each chord in
/// tone order. Refused when a chord in the chain already has [tone].
Score _setTone(Score score, _Head head, Tone tone) {
  if (head.note.tone == tone) {
    return score;
  }
  var moved = score;
  for (final (:timed, :chord, :note) in _tieChain(score, head)) {
    if (chord.notes.any((n) => n.tone == tone)) {
      throw _Refuse(InvalidValue('the chord already has $tone'));
    }
    final notes = [
      for (final n in chord.notes) n.id == note.id ? _retoned(n, tone) : n,
    ]..sort((a, b) => a.tone.compareTo(b.tone));
    moved = _replace(moved, timed, chord.copyWith(notes: Seq(notes)));
  }
  return moved;
}

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
    end = Moment.zero + score.measures[index].length;
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

/// Adds [tone] to the event [ref] names, which keeps its id. A rest
/// becomes a chord of its value, and a measure rest becomes chords that
/// fill the bar, tied.
_Result _addToChord(Score score, EventRef ref, Tone tone, _Ids ids) {
  final timed = _target(score, ref);
  switch (timed.event) {
    case ChordEvent(:final notes) when notes.any((n) => n.tone == tone):
      return _Result(score);
    case final ChordEvent chord:
      final note = _noteOn(
        score,
        ref.staff,
        ids.note(),
        tone,
        tie:
            chord.notes.any((n) => n.tie) &&
            _headWhere(_next(score, timed), (n) => n.tone == tone) != null,
      );
      final above = chord.notes.indexWhere((n) => n.tone.compareTo(tone) > 0);
      return _changeEvent(
        score,
        timed,
        chord.copyWith(
          notes: chord.notes.insertAt(
            above == -1 ? chord.notes.length : above,
            note,
          ),
        ),
      );
    case RestEvent(:final id, :final value, :final articulations):
      return _changeEvent(
        score,
        timed,
        ChordEvent(
          id: id,
          value: value,
          articulations: articulations,
          notes: Seq([_noteOn(score, ref.staff, ids.note(), tone)]),
        ),
      );
    case MeasureRest(:final id, :final span, :final articulations):
      final values = score
          .column(timed.ref.measure)
          .meter
          .spell(Moment.zero, span, rest: false);
      return _Result(
        _rewriteVoice(
          score,
          timed,
          (_) => [
            for (final (k, value) in values.indexed)
              ChordEvent(
                id: k == 0 ? id : ids.event(),
                value: value,
                articulations: k == 0 ? articulations : const {},
                notes: Seq([
                  _noteOn(
                    score,
                    ref.staff,
                    ids.note(),
                    tone,
                    tie: k < values.length - 1,
                  ),
                ]),
              ),
          ],
        ),
      );
  }
}

// Edits that rewrite a lane's rhythm through the lane writer.

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
    _untieInto(write.score, at, const {}, ids),
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

Score _erase(Score score, Selection selection, _Ids ids) => switch (selection) {
  NoSelection() => score,
  ItemSelection(:final items) => _eraseItems(score, items, ids),
  final RangeSelection range => _eraseRange(score, range, ids),
};

/// Erases the picked events whole, and the picked heads of a chord that
/// keeps another head. Picking every head of a chord picks the chord.
Score _eraseItems(Score score, Seq<ElementRef> items, _Ids ids) {
  final targets = <EventId, TimedEvent>{};
  final whole = <EventId>{};
  final heads = <EventId, Set<NoteId>>{};
  for (final item in items) {
    switch (item) {
      case EventRef(:final id):
        targets[id] = _target(score, item);
        whole.add(id);
      case NoteRef(:final event, :final note):
        targets[event.id] = _targetHead(score, item).timed;
        (heads[event.id] ??= {}).add(note);
    }
  }
  var trimmed = score;
  for (final MapEntry(key: id, value: notes) in heads.entries) {
    final timed = targets[id]!;
    final chord = timed.event as ChordEvent;
    if (chord.notes.every((n) => notes.contains(n.id))) {
      whole.add(id);
    } else {
      trimmed = _replace(
        trimmed,
        timed,
        chord.copyWith(
          notes: Seq([
            for (final n in chord.notes)
              if (!notes.contains(n.id)) n,
          ]),
        ),
      );
    }
  }
  final lanes = {
    for (final timed in targets.values)
      (score.indexOf(timed.ref.measure), timed.ref.staff),
  };
  final cleared = _clear(
    trimmed,
    lanes,
    (_) =>
        (item, _, _) => item is Event && whole.contains(item.id),
    ids,
  );
  return _retie(score, cleared, lanes);
}

/// Erases every voice of the staves from [RangeSelection.top] to
/// [RangeSelection.bottom], from [RangeSelection.from] up to
/// [RangeSelection.to]: the events that start in it, the tuplets wholly
/// inside it, its directions, and the spanners that start and end in it.
Score _eraseRange(Score score, RangeSelection range, _Ids ids) {
  final (:lanes, :staves, :inRange) = _covers(score, range);
  final to = range.to;
  final cleared = _clear(
    score,
    lanes,
    (measure) =>
        (item, onset, duration) =>
            inRange(ScorePoint(measure, onset)) &&
            (item is! Tuplet ||
                !_precedes(score, to, ScorePoint(measure, onset + duration))),
    ids,
  );
  var measures = cleared.measures;
  for (final (bar, staff) in lanes) {
    final column = measures[bar];
    final old = column.staff(staff);
    final kept = [
      for (final d in old.directions)
        if (!inRange(ScorePoint(column.id, d.offset))) d,
    ];
    if (kept.length != old.directions.length) {
      measures = measures.replaceAt(
        bar,
        column.withStaff(old.copyWith(directions: Seq(kept))),
      );
    }
  }
  final spanners = [
    for (final s in score.spanners)
      if (!staves.contains(s.staff) || !inRange(s.first) || !inRange(s.last)) s,
  ];
  final unchanged =
      identical(measures, cleared.measures) &&
      spanners.length == score.spanners.length;
  return _retie(
    score,
    unchanged
        ? cleared
        : cleared.copyWith(measures: measures, spanners: Seq(spanners)),
    lanes,
  );
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

/// Whether an erase takes [item], which sounds from [onset] for
/// [duration] in its bar, whole.
typedef _Pick = bool Function(Content item, Moment onset, Length duration);

/// [score] with what [pickIn] picks in each bar cleared from every voice
/// of the (bar index, staff) [lanes]. A voice one left with only plain
/// rests becomes one [MeasureRest]; the other voices merge their gaps and
/// go when only gaps are left.
Score _clear(
  Score score,
  Set<(int, StaffId)> lanes,
  _Pick Function(MeasureId measure) pickIn,
  _Ids ids,
) {
  var measures = score.measures;
  for (final (bar, staff) in lanes) {
    final column = measures[bar];
    final old = column.staff(staff);
    var cleared = old;
    for (final voice in old.voices) {
      final gaps = voice.slot != VoiceSlot.one;
      final items = _cleared(
        voice.items,
        Moment.zero,
        Fraction.one,
        BeatGrid.meter(column.meter),
        pickIn(column.id),
        ids,
        gaps: gaps,
      );
      if (_same(items, voice.items)) {
        continue;
      }
      cleared = cleared.withVoice(
        Voice(
          slot: voice.slot,
          items: Seq(
            gaps
                ? _mergeGaps(items)
                : _onlyRests(items)
                ? [
                    MeasureRest(
                      id: _eventsIn(items.first as Content).first.id,
                      span: column.length,
                    ),
                  ]
                : items,
          ),
        ),
      );
    }
    if (!identical(cleared, old)) {
      measures = measures.replaceAt(bar, column.withStaff(cleared));
    }
  }
  return identical(measures, score.measures)
      ? score
      : score.copyWith(measures: measures);
}

/// [items], one frame sounding from [onset] at [scale], with what [pick]
/// takes cleared. Taken content leaves a gap when [gaps] is set and rests
/// on [grid] otherwise; a chord's rest keeps its id and a fermata. A tuplet
/// in a gapped frame that is left with only rests becomes a gap.
List<VoiceItem> _cleared(
  Iterable<VoiceItem> items,
  Moment onset,
  Fraction scale,
  BeatGrid grid,
  _Pick pick,
  _Ids ids, {
  required bool gaps,
}) {
  final cleared = <VoiceItem>[];
  var at = onset;
  var written = Moment.zero;
  for (final item in items) {
    final duration = item.span * scale;
    switch (item) {
      case Content() when pick(item, at, duration):
        cleared.addAll(switch (item) {
          _ when gaps => [Gap(item.span)],
          ChordEvent(:final id, :final value, :final articulations) => [
            RestEvent(
              id: id,
              value: value,
              articulations: Set.unmodifiable(
                articulations.intersection(_restMarks),
              ),
            ),
          ],
          RestEvent() || MeasureRest() => [item],
          Tuplet() => _rests(grid, written, item.span, ids),
        });
      case Tuplet(:final ratio, :final unit, :final members):
        final inner = _cleared(
          members,
          at,
          scale * ratio.scale,
          BeatGrid.single(unit.length * Fraction(ratio.actual)),
          pick,
          ids,
          gaps: false,
        );
        cleared.add(
          _same(inner, members)
              ? item
              : gaps && _onlyRests(inner)
              ? Gap(item.span)
              : _refill(item, inner.cast()),
        );
      case Gap() || Event():
        cleared.add(item);
    }
    at += duration;
    written += item.span;
  }
  return cleared;
}

/// Whether [items] hold only rests that print plainly, in tuplets or not.
bool _onlyRests(Iterable<VoiceItem> items) => items.every(
  (item) => switch (item) {
    RestEvent(:final hidden, :final articulations) =>
      !hidden && articulations.isEmpty,
    Tuplet(:final members) => _onlyRests(members),
    _ => false,
  },
);

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

// Directions and spanners. Directions are replaced per staff and bar;
// spanners are added or removed whole.

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

/// Refuses [staff] when the score no longer has it.
void _staff(Score score, StaffId staff) {
  if (!score.staves.any((s) => s.id == staff)) {
    throw _Refuse(StaleReference(staff));
  }
}

/// Refuses [point] when it does not lie inside [column].
void _inside(MeasureColumn column, ScorePoint point) {
  if (point.offset.isNegative || point.offset >= Moment.zero + column.length) {
    throw _Refuse(OutsideMeasure(point));
  }
}

// Key, clef and tempo. Key and clef propagate forward through the run of
// bars that carried the old value; see [_propagate] and [_setClef].

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

/// Moves the picked heads, each with its whole tie chain as the chain's
/// first head moves in that head's key. A picked event moves its graces,
/// and a range moves the graces and chord symbols in it. Drum notes have no
/// pitch, so they stay. A tie left leading onto a head it did not reach
/// before is cleared.
_Result _transpose(Score score, Selection selection, Transposition by) {
  final heads = <_Head>[];
  final graced = <TimedEvent>[];
  void pick(TimedEvent timed) {
    if (timed.event case final ChordEvent chord) {
      heads.addAll([
        for (final note in chord.notes)
          (timed: timed, chord: chord, note: note),
      ]);
      graced.add(timed);
    }
  }

  var symbols = score;
  switch (selection) {
    case NoSelection():
      return _Result(score);
    case ItemSelection(:final items):
      for (final item in items) {
        switch (item) {
          case EventRef():
            pick(_target(score, item));
          case NoteRef():
            heads.add(_targetHead(score, item));
        }
      }
    case final RangeSelection range:
      final (:lanes, staves: _, :inRange) = _covers(score, range);
      for (final (bar, staff) in lanes) {
        final column = score.measures[bar];
        final measure = column.staff(staff);
        for (final voice in measure.voices) {
          timedEvents(voice, measure: column.id, staff: staff)
              .where((timed) => inRange(ScorePoint(column.id, timed.onset)))
              .forEach(pick);
        }
        final directions = [
          for (final d in measure.directions)
            d is ChordSymbol && inRange(ScorePoint(column.id, d.offset))
                ? _movedSymbol(d, by, column.key)
                : d,
        ];
        if (!_same(directions, measure.directions)) {
          symbols = symbols.copyWith(
            measures: symbols.measures.replaceAt(
              bar,
              symbols.measures[bar].withStaff(
                measure.copyWith(directions: Seq(directions)),
              ),
            ),
          );
        }
      }
  }
  final moved = <NoteId, Pitch>{};
  final touched = <EventId, TimedEvent>{};
  for (final head in heads) {
    if (head.note case PitchedNote(:final pitch)) {
      final chain = _tieChain(score, head);
      final to = _moved(
        pitch,
        by,
        score.column(chain.first.timed.ref.measure).key,
      );
      for (final (:timed, :note, chord: _) in chain) {
        moved[note.id] = to;
        if (to != note.tone) {
          touched[timed.event.id] = timed;
        }
      }
    }
  }
  final graces = <EventId, Seq<GraceChord>>{};
  for (final timed in graced) {
    final chord = timed.event as ChordEvent;
    final key = score.column(timed.ref.measure).key;
    final repitched = [
      for (final grace in chord.graces)
        switch (_pitched(grace.notes, (note) => _moved(note.pitch, by, key))) {
          final notes when identical(notes, grace.notes) => grace,
          final notes => GraceChord(
            id: grace.id,
            kind: grace.kind,
            value: grace.value,
            notes: notes,
          ),
        },
    ];
    if (!_same(repitched, chord.graces)) {
      graces[chord.id] = Seq(repitched);
      touched[chord.id] = timed;
    }
  }
  var transposed = symbols;
  for (final timed in touched.values) {
    final chord = timed.event as ChordEvent;
    transposed = _replace(
      transposed,
      timed,
      chord.copyWith(
        notes: _pitched(chord.notes, (note) => moved[note.id] ?? note.pitch),
        graces: graces[chord.id],
      ),
    );
  }
  return _Result(
    _retie(score, transposed, {
      for (final timed in touched.values)
        (score.indexOf(timed.ref.measure), timed.ref.staff),
    }),
  );
}

Pitch _moved(Pitch pitch, Transposition by, KeySignature key) {
  final moved =
      by.apply(pitch, key) ??
      (throw _Refuse(InvalidValue('$pitch moves past a double accidental')));
  _check(pitchProblem(moved));
  return moved;
}

ChordSymbol _movedSymbol(
  ChordSymbol symbol,
  Transposition by,
  KeySignature key,
) {
  PitchName move(PitchName name) =>
      _moved(Pitch(name.step, 4, name.alter), by, key).name;
  final ChordSymbol(:offset, :root, :quality, :bass) = symbol;
  return ChordSymbol(
    offset,
    root: move(root),
    quality: quality,
    bass: bass == null ? null : move(bass),
  );
}

/// [notes] each at the pitch [to] gives it, in pitch order; the same
/// object when none moves, as for drums. Refused when two would share a
/// pitch.
Seq<Note> _pitched(Seq<Note> notes, Pitch Function(PitchedNote note) to) {
  if (notes.every((note) => note is! PitchedNote || to(note) == note.pitch)) {
    return notes;
  }
  final sorted = [
    for (final note in notes)
      if (note case final PitchedNote pitched)
        pitched.copyWith(pitch: to(pitched))
      else
        note,
  ]..sort((a, b) => a.tone.compareTo(b.tone));
  for (var k = 1; k < sorted.length; k++) {
    if (sorted[k].tone == sorted[k - 1].tone) {
      throw _Refuse(
        InvalidValue('the chord would have ${sorted[k].tone} twice'),
      );
    }
  }
  return Seq(sorted);
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

/// [note] playing [tone] instead, which [_checkTone] has matched to it.
Note _retoned(Note note, Tone tone) => switch ((note, tone)) {
  (final PitchedNote note, final Pitch pitch) => note.copyWith(pitch: pitch),
  (final DrumNote note, final Drum drum) => note.copyWith(drum: drum),
  _ => throw StateError('$tone on a ${note.runtimeType}'),
};

/// [head]'s note, refused when it is a drum note, which has no [what].
PitchedNote _pitchedOnly(_Head head, String what) => switch (head.note) {
  final PitchedNote note => note,
  DrumNote() => throw _Refuse(InvalidValue('a drum note has no $what')),
};

/// [score] with a part made from [template] at part [index], or at the
/// bottom, and a measure rest on each of its staves in every bar.
Score _addPart(Score score, PartTemplate template, int? index, _Ids ids) {
  final at = index ?? score.parts.length;
  if (at < 0 || at > score.parts.length) {
    throw _Refuse(InvalidValue('no part place $at'));
  }
  final PartTemplate(:instrument, :staves, :clefs) = template;
  if (staves < 1 || (clefs != null && clefs.length != staves)) {
    throw const _Refuse(InvalidValue('a part needs a staff and a clef each'));
  }
  _check(instrumentProblem(instrument));
  final part = Part(
    id: ids.part(),
    name: template.name,
    shortName: template.shortName,
    instrument: instrument,
    staves: Seq([for (var i = 0; i < staves; i++) Staff(id: ids.staff())]),
  );
  final row = score.parts.take(at).fold(0, (n, p) => n + p.staves.length);
  return score.copyWith(
    parts: score.parts.insertAt(at, part),
    measures: Seq([
      for (final column in score.measures)
        column.copyWith(
          staves: column.staves.insertAllAt(row, [
            for (final (i, staff) in part.staves.indexed)
              StaffMeasure(
                staff: staff.id,
                clef: clefs?[i] ?? instrument.clef,
                voices: Seq([
                  Voice(
                    slot: VoiceSlot.one,
                    items: Seq([
                      MeasureRest(id: ids.event(), span: column.length),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
    ]),
  );
}

_Result _removePart(Score score, PartId part, VoicePoint cursor) {
  final at = _shownOther(score, part);
  final gone = {for (final staff in score.parts[at].staves) staff.id};
  return _Result(
    score.copyWith(
      parts: score.parts.removeAt(at),
      measures: Seq([
        for (final column in score.measures)
          column.copyWith(
            staves: Seq([
              for (final measure in column.staves)
                if (!gone.contains(measure.staff)) measure,
            ]),
          ),
      ]),
      spanners: Seq([
        for (final spanner in score.spanners)
          if (!gone.contains(spanner.staff)) spanner,
      ]),
    ),
    cursor: _cursorOff(score, at, cursor),
  );
}

_Result _setPartHidden(
  Score score,
  PartId part,
  bool hidden,
  VoicePoint cursor,
) {
  final at = hidden ? _shownOther(score, part) : _partIndex(score, part);
  if (score.parts[at].hidden == hidden) {
    return _Result(score);
  }
  return _Result(
    score.copyWith(
      parts: score.parts.replaceAt(
        at,
        score.parts[at].copyWith(hidden: hidden),
      ),
    ),
    cursor: hidden ? _cursorOff(score, at, cursor) : null,
  );
}

int _partIndex(Score score, PartId part) {
  final at = score.parts.indexWhere((p) => p.id == part);
  return at < 0 ? throw _Refuse(StaleReference(part)) : at;
}

/// The index of [part], refused with [WouldEmptyScore] when no other part
/// is shown.
int _shownOther(Score score, PartId part) {
  final at = _partIndex(score, part);
  if (score.parts.every((p) => p.hidden || p.id == part)) {
    throw const _Refuse(WouldEmptyScore());
  }
  return at;
}

/// [cursor] moved off part [at] of [score] to the same point on the first
/// shown staff below it, or else the last one above. Null when the cursor
/// is on another part.
VoicePoint? _cursorOff(Score score, int at, VoicePoint cursor) {
  final part = score.parts[at];
  if (!part.staves.any((staff) => staff.id == cursor.staff)) {
    return null;
  }
  bool shown(Part p) => !p.hidden;
  final staff =
      score.parts.skip(at + 1).where(shown).firstOrNull?.staves.first ??
      score.parts.take(at).where(shown).last.staves.last;
  return VoicePoint(staff: staff.id, voice: cursor.voice, at: cursor.at);
}

/// A refusal escapes the fold, so the batch is all or nothing.
_Result _batch(List<Edit> edits, _Ids ids, EditSession session) {
  final end = edits.fold(session, (now, edit) => now._advance(edit, ids));
  return _Result(end.score, cursor: end.cursor, selection: end.selection);
}
