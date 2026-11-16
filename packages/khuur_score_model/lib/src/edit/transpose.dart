part of 'session.dart';

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
