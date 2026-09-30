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
    EnterNote(:final at, :final pitch, :final value, :final overfill) =>
      _overwrite(
        score,
        at,
        [
          _Entry([pitch], value),
        ],
        ids,
        overfill,
      ).asResult(),
    EnterRest(:final at, :final value, :final overfill) => _overwrite(
      score,
      at,
      [_Entry.rest(value)],
      ids,
      overfill,
    ).asResult(),
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
    Batch(:final edits) => _batch(score, edits, ids, session),
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

_Result _rhythm(Score score, Edit edit, _Ids ids) {
  // TODO: SetValue shorter → replace the event with a shorter copy plus
  // rests (Meter.spell) for the freed time. Longer → _overwrite from the
  // event's onset with the event's content at the new value (keeps id).
  // EnterTuplet → refuse WouldSplitTuplet if onset + span crosses the
  // barline; otherwise _overwrite with a Tuplet of `ratio.actual` rests.
  throw UnimplementedError();
}

_Result _erase(Score score, Selection selection) {
  // TODO: voice one: events → rests of the same value, then merge a bar of
  // only rests into one MeasureRest. Voices 2–4: events → Gaps, merge
  // adjacent gaps, drop the voice if only gaps remain. RangeSelection also
  // clears directions whose offset is in range and spanners wholly inside.
  throw UnimplementedError();
}

_Result _marks(Score score, Edit edit, _Ids ids) => throw UnimplementedError();

/// Key, clef and tempo. Key and clef propagate forward through the run of
/// bars that carried the old value; see [_propagate].
_Result _context(Score score, Edit edit) {
  switch (edit) {
    case SetKey(:final from, :final key):
      final start = score.indexOf(from);
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
    case SetClef():
      // TODO: at offset 0: old = the staff measure's clef; propagate over
      // following bars whose staff measure starts with `old`, replacing it
      // (a bar starting with a different clef is an explicit change and
      // stops the run). Mid-bar: insert a ClefChange, then propagate from
      // the next bar with old = the previous clefAtEnd.
      throw UnimplementedError();
    case SetTempoMarks():
      // TODO: replace the column's tempos (validated by the constructor).
      throw UnimplementedError();
    default:
      throw StateError('not a context edit: $edit');
  }
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
  // pieces, ids, overfill), the same barline rule as note entry. Then
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

_Result _batch(Score score, List<Edit> edits, _Ids ids, EditSession session) {
  // TODO: fold _apply over edits, threading the score and the same _Ids.
  // A _Refuse from any edit propagates, so the batch is all or nothing.
  throw UnimplementedError();
}
