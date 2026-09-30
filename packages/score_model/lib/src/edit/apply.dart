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
          _Piece.chord([pitch], value),
        ],
        ids,
        overfill,
      ).asResult(),
    EnterRest(:final at, :final value, :final overfill) => _overwrite(
      score,
      at,
      [_Piece.rest(value)],
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
    SetMeter() => _setMeter(score, edit, ids),
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

/// Edits that change one event in place: resolve the [EventRef], rebuild
/// that event, and walk back up. Touches exactly one column, except
/// [SetPitch] on a tie chain and [SetTie], which may touch the next column.
_Result _pointEdit(Score score, Edit edit, _Ids ids) {
  // TODO: per case:
  //   AddToChord: rest → ChordEvent(same id, rest's value, [new Note]);
  //     chord → insert Note in pitch order; no-op if pitch present.
  //   RemoveNote: last head → RestEvent(same id, value).
  //   SetPitch: follow the tie chain forward (next event, same voice, maybe
  //     next bar) and backward, changing every linked head.
  //   AddGrace, SetTie, SetArticulation, SetOrnament, SetBowing (chords
  //     only; refuse InvalidValue on a rest), SetFingering, SetString (validate
  //     index against instrument.strings), SetAccidental, SetLyric.
  throw UnimplementedError();
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

_Result _bars(Score score, Edit edit, _Ids ids) {
  // TODO: InsertMeasures copies meter/key/clefAtEnd from the bar before,
  // volta membership if both neighbours share it, MeasureRest per staff;
  // spanners whose first < insertion point <= last are untouched (anchors
  // are by measure id, so they stretch automatically).
  // DeleteMeasures: refuse WouldEmptyScore; clear `tie` on notes whose tie
  // target was in the range; drop spanners wholly inside; clip crossing
  // ones to the nearest surviving event onset.
  // SetBarLength: cut or pad voices; a pickup is its own re-bar section.
  throw UnimplementedError();
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
