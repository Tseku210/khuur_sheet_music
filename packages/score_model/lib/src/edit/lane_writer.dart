part of 'session.dart';

/// Music to write into a lane, before it is cut to bars. A piece is a chord
/// (one or more pitches), a rest, or a copied item from a clip.
final class _Piece {
  const _Piece._(this.pitches, this.value, this.copied);

  _Piece.chord(List<Pitch> pitches, NoteValue value)
    : this._(pitches, value, null);

  _Piece.rest(NoteValue value) : this._(const [], value, null);

  /// A clip item, already re-minted. Used by `_paste`.
  // ignore: unused_element
  _Piece.copied(Content item) : this._(const [], null, item);

  final List<Pitch> pitches;
  final NoteValue? value;
  final Content? copied;
}

final class _LaneWrite {
  const _LaneWrite(this.score, this.end, this.first);

  final Score score;

  /// Where the written music ends, normalized to offset 0 of the next bar
  /// when it ends on a barline.
  final VoicePoint end;

  /// The first event written, for the selection.
  final EventRef? first;

  _Result asResult() => _Result(
    score,
    cursor: end,
    selection: first == null ? null : Selection.event(first!),
  );
}

/// Writes [pieces] into one voice lane from [at], overwriting whatever
/// sounded there. The single implementation of the overwrite and overfill
/// policies: note entry, rest entry, lengthening, and paste all go through
/// it, so they cannot disagree about barlines.
///
/// Touches only the bars the written span covers (usually one, two when a
/// note crosses the barline), plus appended bars at the end of the score.
_LaneWrite _overwrite(
  Score score,
  VoicePoint at,
  List<_Piece> pieces,
  _Ids ids,
  Overfill overfill,
) {
  // TODO:
  //   i = score.indexOf(at.at.measure); o = at.at.offset
  //   if o is outside [0, column.length): throw _Refuse(OutsideMeasure)
  //   touched = <int, MeasureColumn>{}   // index → rebuilt column
  //   for piece in pieces:
  //     remaining = piece sounding length (value.length, or copied.span;
  //                 scaled by the tuplet ratio if `o` is inside a tuplet)
  //     firstPart = true
  //     while remaining > 0:
  //       if i == measures.length: append a blank bar (meter, key, clefAtEnd
  //         of the last bar; MeasureRest per staff) with fresh ids
  //       col = touched[i] ?? measures[i]; room = col.length - o
  //       if remaining > room and overfill == Overfill.refuse:
  //         throw _Refuse(WouldCrossBarline(col.id, remaining - room))
  //       take = min(remaining, room)
  //       // Split and tie across the barline (overfill policy):
  //       values = col.meter.spell(o, take, rest: piece is rest)
  //       parts = one event per value, the first keeping a fresh id for the
  //         piece and the rest getting fresh ids; every note tied except
  //         the notes of the very last part of the piece
  //       voice = staff measure's voice(at.voice)
  //         ?? Voice(slot, [Gap(col.length)])   // secondary voice appears
  //       voice' = _replaceSpan(voice, o, take, parts, col.meter, ids)
  //       touched[i] = col.withStaff(staffMeasure.withVoice(voice'))
  //       remaining -= take; o += take
  //       if o == col.length: i++; o = 0
  //   // A tie from the event just before `at` now points at new music; if
  //   // the first written pitch set does not contain the tied pitch, clear
  //   // that tie flag (its column joins `touched`).
  //   measures' = one replaceRange over min(touched)..max(touched) + appended
  //   return _LaneWrite(Score(..., measures: measures'), end, firstRef)
  throw UnimplementedError();
}

/// Replaces the sounding span `[offset, offset + length)` of [voice] with
/// [parts]. Items wholly inside are dropped. An item straddling the start is
/// cut to its head (re-spelled, same id for the first piece). An item
/// straddling the end leaves its tail as rests (voice one) or a gap. A tuplet
/// straddling either edge is first replaced by rests. Recurses into a
/// tuplet that wholly contains the span, scaling by its ratio.
// Called from `_overwrite` once its body is written.
// ignore: unused_element
Voice _replaceSpan(
  Voice voice,
  Moment offset,
  Length length,
  List<Content> parts,
  Meter meter,
  _Ids ids,
) => throw UnimplementedError();
