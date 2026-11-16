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
  return score.copyWith(
    parts: score.parts.insertAt(at, part),
    measures: _withRestStaves(score.measures, _rowOf(score, at), [
      for (final (i, staff) in part.staves.indexed)
        (staff.id, clefs?[i] ?? instrument.clef),
    ], ids),
  );
}

_Result _removePart(Score score, PartId part, VoicePoint cursor) {
  final at = _shownOther(score, part);
  return _Result(
    _withoutStaves(score, score.parts.removeAt(at), {
      for (final staff in score.parts[at].staves) staff.id,
    }),
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
  Clef clef(int i) => clefs?[i] ?? instrument.clef;
  final same =
      identical(instrument, old.instrument) &&
      (template.name, template.shortName) == (old.name, old.shortName) &&
      staves == old.staves.length &&
      score.measures.every(
        (column) => column.staves.every(
          (measure) => switch (row[measure.staff]) {
            null => true,
            final i => measure.clef == clef(i) && measure.clefChanges.isEmpty,
          },
        ),
      );
  if (same) {
    return _Result(score);
  }
  if (instrument.isPercussion) {
    for (final column in score.measures) {
      for (final measure in column.staves) {
        if (row.containsKey(measure.staff)) {
          _checkKit(measure, instrument);
        }
      }
    }
  }
  final added = [
    for (var i = kept.length; i < staves; i++) Staff(id: ids.staff()),
  ];
  final strings = [
    for (final open in old.instrument.strings) instrument.strings.indexOf(open),
  ];
  Note restring(Note note) => switch (note) {
    PitchedNote(:final string?) => note.copyWith(
      string: () => strings[string] < 0 ? null : strings[string],
    ),
    _ => note,
  };

  final gone = {for (final staff in old.staves.skip(staves)) staff.id};
  final restrung = score.copyWith(
    measures: Seq([
      for (final column in score.measures)
        column.copyWith(
          staves: Seq([
            for (final measure in column.staves)
              switch (row[measure.staff]) {
                null => measure,
                final i => measure.copyWith(
                  clef: clef(i),
                  clefChanges: const Seq.empty(),
                  voices: Seq([
                    for (final voice in measure.voices)
                      Voice(
                        slot: voice.slot,
                        items: Seq([
                          for (final item in voice.items)
                            if (item is Content)
                              _withHeads(item, restring)
                            else
                              item,
                        ]),
                      ),
                  ]),
                ),
              },
          ]),
        ),
    ]),
  );
  final parts = score.parts.replaceAt(
    at,
    Part(
      id: old.id,
      name: template.name,
      shortName: template.shortName,
      instrument: instrument,
      staves: Seq([...kept, ...added]),
      hidden: old.hidden,
    ),
  );
  return _Result(
    added.isEmpty
        ? _withoutStaves(restrung, parts, gone)
        : restrung.copyWith(
            parts: parts,
            measures: _withRestStaves(
              restrung.measures,
              _rowOf(score, at) + kept.length,
              [
                for (final (j, staff) in added.indexed)
                  (staff.id, clef(kept.length + j)),
              ],
              ids,
            ),
          ),
    cursor: gone.contains(cursor.staff)
        ? VoicePoint(staff: kept.last.id, voice: cursor.voice, at: cursor.at)
        : null,
  );
}

/// Refused with [InvalidValue] when [measure] holds a drum that
/// [instrument]'s kit lacks.
void _checkKit(StaffMeasure measure, Instrument instrument) {
  for (final voice in measure.voices) {
    for (final item in voice.items.whereType<Content>()) {
      for (final note in _headsIn(item)) {
        if (note case DrumNote(:final drum)
            when instrument.soundOf(drum) == null) {
          throw _Refuse(InvalidValue('the kit has no $drum'));
        }
      }
    }
  }
}

/// The row of part [at]'s first staff among all of [score]'s staves.
int _rowOf(Score score, int at) =>
    score.parts.take(at).fold(0, (n, p) => n + p.staves.length);

/// [measures] with a staff of a [MeasureRest] in every bar for each of
/// [staves], inserted from staff row [row] down.
Seq<MeasureColumn> _withRestStaves(
  Seq<MeasureColumn> measures,
  int row,
  List<(StaffId, Clef)> staves,
  _Ids ids,
) => Seq([
  for (final column in measures)
    column.copyWith(
      staves: column.staves.insertAllAt(row, [
        for (final (staff, clef) in staves)
          _restStaff(staff, clef, column.length, ids),
      ]),
    ),
]);

/// [score] with [parts], without the bars and spanners of the [gone]
/// staves.
Score _withoutStaves(Score score, Seq<Part> parts, Set<StaffId> gone) =>
    score.copyWith(
      parts: parts,
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
    );

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
