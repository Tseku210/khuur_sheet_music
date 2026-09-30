part of 'session.dart';

/// Access pattern 8: change the meter from a bar onward and re-bar.
///
/// Why re-bar instead of leaving bars over- or underfull: the column
/// invariant says every voice fills its bar exactly. Keeping old content in
/// bars of a new length would break it; relaxing the invariant would push
/// "is this bar valid?" into layout, playback and every edit. Re-barring
/// keeps the invariant and matches what MuseScore and Finale do.
///
/// Why sections: repeat signs, volta boundaries, key changes, double and
/// final barlines are the composer's structure. Re-barring across them
/// would move a repeat sign into the middle of a phrase. Each section is
/// re-barred on its own, so structural barlines stay where they are.
_Result _setMeter(Score score, SetMeter edit, _Ids ids) {
  // TODO:
  //   start = indexOf(edit.from); old = measures[start].meter
  //   if old == edit.meter: return _Result(score)          // idempotent
  //   end = first index > start with measures[end].meter != old (or length)
  //   if edit.content == MeterContent.keepBars:
  //     for each bar in [start, end):
  //       if bar.irregularLength != null: set the bar's meter only; continue
  //       drop each voice's trailing rests;
  //       if what is left is longer than edit.meter.length:
  //         throw _Refuse(WouldCrossBarline(bar.id, excess))
  //       pad voice one with rests (Meter.spell) and others with a gap;
  //       set the bar's meter
  //     return the score with those bars replaced; ids and anchors untouched
  //   sections = split [start, end) before every bar with repeatStart, a
  //     different volta or key than its predecessor, or irregularLength !=
  //     null, and after every bar with repeatEnd, doubleBar or finalBar
  //   rebuilt = []
  //   for section in sections:
  //     if section is a pickup bar: keep it, just set meter; continue
  //     // Lay each lane end to end, barlines dissolved.
  //     for each (staff, voice slot) present in any bar of the section:
  //       stream = concatenation of the lane's items across the section's
  //         bars, with absent voices contributing gaps
  //       trim trailing rests/gaps (elastic)
  //     needed = ceil(max stream length / meter.length)
  //     count = max(needed, section.length)              // never loses bars
  //     cut every stream at multiples of meter.length:
  //       a note crossing a cut → split + tie (Meter.spell per side)
  //       a tuplet crossing a cut → throw _Refuse(WouldSplitTuplet)
  //       pad the last bar with rests (voice one) or gaps (others)
  //     new bar k takes section's old id k (k < section.length) or a fresh
  //       id; key and clef-at-start follow the flow of the old bars; bar
  //       facts: first bar keeps the section's first bar's start facts
  //       (repeatStart, segno, coda, rehearsal), last bar keeps the end
  //       facts (barline, repeatEnd, toCoda, fine, jump); volta membership
  //       is uniform inside a section by construction
  //     re-anchor by absolute time within the section: tempo marks,
  //       directions, mid-bar clef changes, spanner endpoints on old ids
  //   measures' = measures.replaceRange(start, end, rebuilt)
  //   spanners' = remapped anchors
  //   cursor = VoicePoint at the start of `edit.from` (still a valid id)
  throw UnimplementedError();
}
