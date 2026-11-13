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

_Result _setInstrument(
  Score score,
  PartId part,
  PartTemplate template,
  _Ids ids,
  VoicePoint cursor,
) {
  final at = _partIndex(score, part);
  _check(templateProblem(template));
  final old = score.parts[at];
  final PartTemplate(:instrument, :staves, :clefs) = template;
  if (instrument.isPercussion != old.instrument.isPercussion) {
    throw const _Refuse(
      InvalidValue('a drum kit and a pitched instrument do not swap'),
    );
  }
  final kept = old.staves.take(staves).toList();
  final row = {for (final (i, staff) in kept.indexed) staff.id: i};
  final gone = {for (final staff in old.staves.skip(staves)) staff.id};
  final added = [
    for (var i = kept.length; i < staves; i++) Staff(id: ids.staff()),
  ];
  Clef clef(int i) => clefs?[i] ?? instrument.clef;
  int? restring(int string) {
    final to = instrument.strings.indexOf(old.instrument.strings[string]);
    return to < 0 ? null : to;
  }

  StaffMeasure moved(StaffMeasure measure, int i) => measure.copyWith(
    clef: clef(i),
    clefChanges: const Seq.empty(),
    voices: Seq([
      for (final voice in measure.voices)
        Voice(
          slot: voice.slot,
          items: Seq([
            for (final item in voice.items)
              if (item is Content)
                _restrung(_inKit(item, instrument), restring)
              else
                item,
          ]),
        ),
    ]),
  );

  return _Result(
    score.copyWith(
      parts: score.parts.replaceAt(
        at,
        Part(
          id: old.id,
          name: template.name,
          shortName: template.shortName,
          instrument: instrument,
          staves: Seq([...kept, ...added]),
          hidden: old.hidden,
        ),
      ),
      measures: Seq([
        for (final column in score.measures)
          column.copyWith(
            staves: Seq([
              for (final measure in column.staves)
                if (row[measure.staff] case final i?) ...[
                  moved(measure, i),
                  if (i == kept.length - 1)
                    for (final (j, staff) in added.indexed)
                      _restStaff(
                        staff.id,
                        clef(kept.length + j),
                        column.length,
                        ids,
                      ),
                ] else if (!gone.contains(measure.staff))
                  measure,
            ]),
          ),
      ]),
      spanners: Seq([
        for (final spanner in score.spanners)
          if (!gone.contains(spanner.staff)) spanner,
      ]),
    ),
    cursor: gone.contains(cursor.staff)
        ? VoicePoint(staff: kept.last.id, voice: cursor.voice, at: cursor.at)
        : null,
  );
}

/// [item], refused with [InvalidValue] when it holds a drum that
/// [instrument]'s kit lacks.
Content _inKit(Content item, Instrument instrument) {
  for (final event in _eventsIn(item)) {
    if (event case ChordEvent(:final notes, :final graces)) {
      for (final note in [...notes, for (final g in graces) ...g.notes]) {
        if (note case DrumNote(:final drum)
            when instrument.soundOf(drum) == null) {
          throw _Refuse(InvalidValue('the kit has no $drum'));
        }
      }
    }
  }
  return item;
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
