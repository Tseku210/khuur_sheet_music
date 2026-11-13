part of 'session.dart';

/// [score] with a part made from [template] at part [index], or at the
/// bottom, and a measure rest on each of its staves in every bar.
Score _addPart(Score score, PartTemplate template, int? index, _Ids ids) {
  final at = index ?? score.parts.length;
  if (at < 0 || at > score.parts.length) {
    throw _Refuse(InvalidValue('no part place $at'));
  }
  _check(templateProblem(template));
  final PartTemplate(:instrument, :staves, :clefs) = template;
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
