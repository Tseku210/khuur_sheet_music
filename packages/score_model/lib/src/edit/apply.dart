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
    EnterNote(:final at, :final pitch, :final value, :final overfill) => _enter(
      score,
      at,
      ChordEvent(
        id: ids.event(),
        value: value,
        notes: Seq([Note(id: ids.note(), pitch: pitch)]),
      ),
      ids,
      overfill,
    ),
    EnterRest(:final at, :final value, :final overfill) => _enter(
      score,
      at,
      RestEvent(id: ids.event(), value: value),
      ids,
      overfill,
    ),
    SetValue() || EnterTuplet() => _rhythm(score, edit, ids),
    AddToChord() ||
    RemoveNote() ||
    SetPitch() ||
    AddGrace() ||
    SetTie() ||
    SetArticulation() ||
    SetOrnament() ||
    SetBowing() ||
    SetFingering() ||
    SetString() ||
    SetAccidental() ||
    SetLyric() => _pointEdit(score, edit, ids),
    Erase(:final selection) => _erase(score, selection),
    SetDirections() ||
    AddSpanner() ||
    RemoveSpanner() => _marks(score, edit, ids),
    SetMeter() => _setMeter(score, edit, ids, session),
    SetKey() || SetClef() || SetTempoMarks() => _context(score, edit),
    InsertMeasures() ||
    DeleteMeasures() ||
    SetBarline() ||
    SetRepeatStart() ||
    SetRepeatEnd() ||
    SetVolta() ||
    SetNavigation() ||
    SetRehearsal() ||
    SetBarLength() => _bars(score, edit, ids),
    Paste(:final clip, :final at, :final overfill) => _paste(
      score,
      clip,
      at,
      ids,
      overfill,
    ),
    Transpose(:final selection, :final by) => _transpose(score, selection, by),
    AddPart() || RemovePart() || SetPartHidden() => _parts(score, edit, ids),
    Batch(:final edits) => _batch(edits, ids, session),
  };
}

/// Edits that change one event in place: resolve the reference, rebuild
/// that event, and walk back up. Touches one column, except [SetPitch] on a
/// tie chain and [RemoveNote] when it clears a tie from the bar before. An
/// edit that changes nothing returns the same score.
_Result _pointEdit(Score score, Edit edit, _Ids ids) {
  switch (edit) {
    case AddToChord(:final event, :final pitch):
      return _addToChord(score, event, pitch, ids);
    case RemoveNote(:final note):
      return _Result(_removeNote(score, _targetHead(score, note)));
    case SetPitch(:final note, :final pitch):
      return _Result(_setPitch(score, _targetHead(score, note), pitch));
    case SetTie(:final note, :final tied):
      final head = _targetHead(score, note);
      return _changeNote(
        score,
        head,
        head.note.tie == tied ? head.note : head.note.copyWith(tie: tied),
      );
    case SetFingering(:final note, :final finger):
      if (finger != null && finger < 0) {
        throw const _Refuse(InvalidValue('a finger number is 0 or more'));
      }
      final head = _targetHead(score, note);
      return _changeNote(
        score,
        head,
        head.note.fingering == finger
            ? head.note
            : head.note.copyWith(fingering: () => finger),
      );
    case SetString(:final note, :final string):
      final head = _targetHead(score, note);
      final strings = score.partOf(head.timed.ref.staff).instrument.strings;
      if (string != null && (string < 0 || string >= strings.length)) {
        throw const _Refuse(InvalidValue('the instrument has no such string'));
      }
      return _changeNote(
        score,
        head,
        head.note.string == string
            ? head.note
            : head.note.copyWith(string: () => string),
      );
    case SetAccidental(:final note, :final request):
      final head = _targetHead(score, note);
      return _changeNote(
        score,
        head,
        head.note.accidental == request
            ? head.note
            : head.note.copyWith(accidental: request),
      );
    case AddGrace(:final event, :final pitch, :final kind, :final value):
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
                value: value,
                notes: Seq([Note(id: ids.note(), pitch: pitch)]),
              ),
            ),
          ),
        ),
      );
    case SetArticulation(:final event, :final articulation, :final present):
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
    case SetOrnament(:final event, :final ornament):
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
    case SetBowing(:final event, :final bowing):
      final timed = _target(score, event);
      return _changeEvent(
        score,
        timed,
        _chordOnly(
          timed.event,
          clears: bowing == null,
          change: (chord) => chord.bowing == bowing
              ? chord
              : chord.copyWith(bowing: () => bowing),
        ),
      );
    case SetLyric(:final event, :final verse, :final lyric):
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
    default:
      throw StateError('not a point edit: $edit');
  }
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
bool _tieMoves(Note note, TimedEvent? before, TimedEvent? after) =>
    note.tie &&
    _headWhere(before, (n) => n.pitch == note.pitch)?.note.id !=
        _headWhere(after, (n) => n.pitch == note.pitch)?.note.id;

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
    (n) => n.tie && n.pitch == note.pitch,
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

/// Moves [head] and every head tied to it to [pitch], keeping each chord in
/// pitch order. Refused when a chord in the chain already has [pitch].
Score _setPitch(Score score, _Head head, Pitch pitch) {
  if (head.note.pitch == pitch) {
    return score;
  }
  var moved = score;
  for (final (:timed, :chord, :note) in _tieChain(score, head)) {
    if (chord.notes.any((n) => n.pitch == pitch)) {
      throw _Refuse(InvalidValue('the chord already has $pitch'));
    }
    final notes = [
      for (final n in chord.notes)
        n.id == note.id ? n.copyWith(pitch: pitch) : n,
    ]..sort((a, b) => a.pitch.compareTo(b.pitch));
    moved = _replace(moved, timed, chord.copyWith(notes: Seq(notes)));
  }
  return moved;
}

/// [head] and every head tied to it, in time order. A tie joins a head to
/// the head of the same pitch in the adjacent event of its voice, as
/// `measureView` draws it.
List<_Head> _tieChain(Score score, _Head head) {
  bool samePitch(Note note) => note.pitch == head.note.pitch;
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

/// Adds [pitch] to the event [ref] names, which keeps its id. A rest
/// becomes a chord of its value, and a measure rest becomes chords that
/// fill the bar, tied.
_Result _addToChord(Score score, EventRef ref, Pitch pitch, _Ids ids) {
  final timed = _target(score, ref);
  switch (timed.event) {
    case ChordEvent(:final notes) when notes.any((n) => n.pitch == pitch):
      return _Result(score);
    case final ChordEvent chord:
      final note = Note(
        id: ids.note(),
        pitch: pitch,
        tie:
            chord.notes.any((n) => n.tie) &&
            _headWhere(_next(score, timed), (n) => n.pitch == pitch) != null,
      );
      final above = chord.notes.indexWhere((n) => n.pitch.compareTo(pitch) > 0);
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
          notes: Seq([Note(id: ids.note(), pitch: pitch)]),
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
                  Note(
                    id: ids.note(),
                    pitch: pitch,
                    tie: k < values.length - 1,
                  ),
                ]),
              ),
          ],
        ),
      );
  }
}

/// Edits that rewrite a lane's rhythm through the lane writer.
_Result _rhythm(Score score, Edit edit, _Ids ids) {
  switch (edit) {
    case SetValue(:final event, :final value):
      return _Result(_setValue(score, _target(score, event), value, ids));
    case EnterTuplet(:final at, :final ratio, :final unit):
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
    default:
      throw StateError('not a rhythm edit: $edit');
  }
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

_Result _erase(Score score, Selection selection) {
  // TODO: voice one: events → rests of the same value, then merge a bar of
  // only rests into one MeasureRest. Voices 2–4: events → Gaps, merge
  // adjacent gaps, drop the voice if only gaps remain. RangeSelection also
  // clears directions whose offset is in range and spanners wholly inside.
  throw UnimplementedError();
}

/// Directions and spanners. Directions are replaced per staff and bar;
/// spanners are added or removed whole.
_Result _marks(Score score, Edit edit, _Ids ids) {
  switch (edit) {
    case SetDirections(:final staff, :final measure, :final directions):
      return _Result(_setDirections(score, staff, measure, directions));
    case AddSpanner(
      :final kind,
      :final staff,
      :final voice,
      :final first,
      :final last,
    ):
      _staff(score, staff);
      for (final end in [first, last]) {
        _inside(score.measures[_barIndex(score, end.measure)], end);
      }
      if (!_fits(score, kind, first, last)) {
        throw _Refuse(
          InvalidValue(
            kind.joinsNotes
                ? 'a ${kind.runtimeType} must end after it starts'
                : 'a ${kind.runtimeType} cannot end before it starts',
          ),
        );
      }
      return _Result(
        score.copyWith(
          spanners: score.spanners.append(
            Spanner(
              id: ids.spanner(),
              kind: kind,
              staff: staff,
              voice: kind.joinsNotes ? voice ?? VoiceSlot.one : null,
              first: first,
              last: last,
            ),
          ),
        ),
      );
    case RemoveSpanner(:final spanner):
      final index = score.spanners.indexWhere((s) => s.id == spanner);
      if (index < 0) {
        throw _Refuse(StaleReference(spanner));
      }
      return _Result(
        score.copyWith(spanners: score.spanners.removeAt(index)),
      );
    default:
      throw StateError('not a mark edit: $edit');
  }
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

/// Key, clef and tempo. Key and clef propagate forward through the run of
/// bars that carried the old value; see [_propagate] and [_setClef].
_Result _context(Score score, Edit edit) {
  switch (edit) {
    case SetKey(:final from, :final key):
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
    case SetClef(:final staff, :final at, :final clef):
      return _Result(_setClef(score, staff, at, clef));
    case SetTempoMarks(:final measure, :final marks):
      return _Result(_setTempoMarks(score, measure, marks));
    default:
      throw StateError('not a context edit: $edit');
  }
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

_Result _paste(
  Score score,
  Clip clip,
  VoicePoint at,
  _Ids ids,
  Overfill overfill,
) {
  // TODO: for each lane: target staff = staves[indexOf(at.staff) + lane.staff]
  // (skip if beyond bottom); re-mint every id inside lane.items (events,
  // notes, tuplets); _overwrite(score, VoicePoint(staff, lane.voice, at.at),
  // items, ids, overfill), the same barline rule as note entry, then
  // _untieInto with the pitches the lane starts with. Gaps in a lane need a
  // rule of their own, since _overwrite writes only content. Then
  // directions and spanners, with offsets mapped through the same bar walk.
  // Selection = RangeSelection covering the pasted span.
  throw UnimplementedError();
}

_Result _transpose(Score score, Selection selection, Transposition by) {
  // TODO: collect notes (range: every note head whose event onset is inside
  // the range on the selected staves; items: the listed heads/events).
  // Extend to whole tie chains. For each note:
  //   ByInterval(i): pitch.transpose(i)
  //   ByScaleSteps(n): key = column.key at the note; move the letter n
  //     steps; alteration = key.alterFor(newStep) + (pitch.alter -
  //     key.alterFor(oldStep)) so chromatic colour is kept.
  //   BySemitones(n): midi + n, spelled from the key's preferred spelling
  //     (sharps for fifths >= 0, flats otherwise).
  // Refuse InvalidValue if an alteration leaves -4..4. Chord symbols in a
  // range move with the same rule. Rebuild each touched column once.
  throw UnimplementedError();
}

_Result _parts(Score score, Edit edit, _Ids ids) => throw UnimplementedError();

/// A refusal escapes the fold, so the batch is all or nothing.
_Result _batch(List<Edit> edits, _Ids ids, EditSession session) {
  final end = edits.fold(session, (now, edit) => now._advance(edit, ids));
  return _Result(end.score, cursor: end.cursor, selection: end.selection);
}
