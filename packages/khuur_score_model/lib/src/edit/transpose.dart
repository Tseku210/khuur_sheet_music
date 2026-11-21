part of 'session.dart';

/// Moves the picked heads, each with its whole tie chain as the chain's
/// first head moves in that head's key. A picked event moves its graces,
/// and a range moves the graces and chord symbols in it. Drum notes have no
/// pitch, so they stay. A tie left leading onto a head it did not reach
/// before is cleared. A staff step goes through [_stepped].
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
  final step = by is ByScaleSteps;
  final moved = step ? _stepped(score, heads, graced, by) : <NoteId, Pitch>{};
  if (!step) {
    for (final head in heads) {
      if (head.note case PitchedNote(:final pitch)) {
        final chain = _tieChain(score, head);
        final to = _moved(
          pitch,
          by,
          score.column(chain.first.timed.ref.measure).key,
        );
        for (final link in chain) {
          moved[link.note.id] = to;
        }
      }
    }
    for (final timed in graced) {
      final key = score.column(timed.ref.measure).key;
      for (final note in _graceNotes(timed)) {
        moved[note.id] = _moved(note.pitch, by, key);
      }
    }
  }
  Seq<Note> pitched(Seq<Note> notes) => _pitched(
    notes,
    (note) => moved[note.id] ?? note.pitch,
    dropAccidentals: step,
  );
  final touched = <EventId, TimedEvent>{};
  for (final head in heads) {
    if (head.note is PitchedNote) {
      for (final (:timed, :note, chord: _) in _tieChain(score, head)) {
        if (moved[note.id] != note.tone) {
          touched[timed.event.id] = timed;
        }
      }
    }
  }
  final graces = <EventId, Seq<GraceChord>>{};
  for (final timed in graced) {
    final chord = timed.event as ChordEvent;
    final repitched = [
      for (final grace in chord.graces)
        switch (pitched(grace.notes)) {
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
      _ornamentMoved(
        chord,
        chord.copyWith(
          notes: pitched(chord.notes),
          graces: graces[chord.id],
        ),
        by,
        score.column(timed.ref.measure).key,
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

/// [to], the moved [from], with the accidentals of its ornament moved as
/// the notes they alter move, so the ornament plays the same notes against
/// its lowest head. An accidental whose note would no longer be the next
/// scale step is taken off, and a staff step takes both off, as it leaves
/// the head with none.
ChordEvent _ornamentMoved(
  ChordEvent from,
  ChordEvent to,
  Transposition by,
  KeySignature key,
) {
  final (before, after) = (_lowestPitch(from), _lowestPitch(to));
  if ((from.ornamentAbove == null && from.ornamentBelow == null) ||
      before == null ||
      after == null ||
      before == after) {
    return to;
  }
  Alter? moved(Alter? alter, int steps) {
    if (alter == null || by is ByScaleSteps) {
      return null;
    }
    final note = by.apply(
      from.ornamentNote(before, steps, key),
      Alterations(key),
    );
    return note != null && note.diatonic == after.diatonic + steps
        ? note.alter
        : null;
  }

  return to.copyWith(
    ornamentAbove: () => moved(from.ornamentAbove, 1),
    ornamentBelow: () => moved(from.ornamentBelow, -1),
  );
}

Pitch? _lowestPitch(ChordEvent chord) => switch (chord.notes.first) {
  PitchedNote(:final pitch) => pitch,
  _ => null,
};

Iterable<PitchedNote> _graceNotes(TimedEvent timed) => [
  if (timed.event case ChordEvent(:final graces))
    for (final grace in graces) ...grace.notes.whereType<PitchedNote>(),
];

/// Where a staff step of [by] puts each picked head and each grace of the
/// [graced] events, in concert pitch. A head lands on the alteration its
/// staff reads at the new position, from the written key and the notes at
/// earlier times in the bar as this edit leaves them. A tie chain lands as
/// its first head does.
Map<NoteId, Pitch> _stepped(
  Score score,
  List<_Head> heads,
  List<TimedEvent> graced,
  ByScaleSteps by,
) {
  final chains = <NoteId, List<_Head>>{};
  final lanes = <(int, StaffId)>{};
  void lead(NoteId id, TimedEvent timed, List<_Head> chain) {
    chains[id] = chain;
    lanes.add((score.indexOf(timed.ref.measure), timed.ref.staff));
  }

  for (final head in heads) {
    if (head.note is PitchedNote) {
      final chain = _tieChain(score, head);
      lead(chain.first.note.id, chain.first.timed, chain);
    }
  }
  for (final timed in graced) {
    for (final note in _graceNotes(timed)) {
      lead(note.id, timed, const []);
    }
  }
  final withHiddenParts = score.copyWith(
    parts: Seq([for (final part in score.parts) part.copyWith(hidden: false)]),
  );
  final moved = <NoteId, Pitch>{};
  for (final (bar, staff) in stableSorted(
    lanes.toList(),
    (a, b) => a.$1.compareTo(b.$1),
  )) {
    final column = score.measures[bar];
    final view = withHiddenParts
        .measureView(column.id)
        .staves
        .firstWhere((view) => view.source.staff == staff);
    final tiedIn = view.tiedIn.toSet();
    Interval writtenToConcert(Moment onset) =>
        Interval.octave *
            score.contextAt(staff, ScorePoint(column.id, onset)).octaveShift +
        score.partOf(staff).instrument.transposition;
    final ordered = stableSorted(
      accidentalHeads([for (final voice in view.voices) voice.events]),
      (a, b) => a.onset.compareTo(b.onset),
    );
    var inForce = Alterations(view.writtenKey);
    for (var from = 0; from < ordered.length;) {
      var to = from;
      while (to < ordered.length && ordered[to].onset == ordered[from].onset) {
        to++;
      }
      final together = ordered.sublist(from, to);
      for (final (:onset, :note, grace: _) in together) {
        final chain = chains[note.id];
        if (chain == null) {
          continue;
        }
        final landed = by
            .apply(view.writtenPitches[note.id]!, inForce)!
            .transpose(writtenToConcert(onset), key: column.key);
        _check(pitchProblem(landed));
        moved[note.id] = landed;
        for (final link in chain) {
          moved[link.note.id] = landed;
        }
      }
      for (final (:onset, :note, grace: _) in together) {
        if (note is! PitchedNote) {
          continue;
        }
        final landed = moved[note.id];
        final stays = landed == null || landed == note.pitch;
        if (holdsAlteration(
          stays ? note.accidental : AccidentalRequest.auto,
          tiedIn: tiedIn.contains(note.id),
        )) {
          inForce = inForce.after(
            stays
                ? view.writtenPitches[note.id]!
                : landed.transpose(
                    -writtenToConcert(onset),
                    key: view.writtenKey,
                  ),
          );
        }
      }
      from = to;
    }
  }
  return moved;
}

Pitch _moved(Pitch pitch, Transposition by, KeySignature key) {
  final moved =
      by.apply(pitch, Alterations(key)) ??
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
Seq<Note> _pitched(
  Seq<Note> notes,
  Pitch Function(PitchedNote note) to, {
  bool dropAccidentals = false,
}) {
  if (notes.every((note) => note is! PitchedNote || to(note) == note.pitch)) {
    return notes;
  }
  final sorted = [
    for (final note in notes)
      if (note case final PitchedNote pitched)
        pitched.copyWith(
          pitch: to(pitched),
          accidental: dropAccidentals && to(pitched) != pitched.pitch
              ? AccidentalRequest.auto
              : null,
        )
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
