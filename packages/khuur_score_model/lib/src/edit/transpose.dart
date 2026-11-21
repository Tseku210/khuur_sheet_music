part of 'session.dart';

/// Moves the picked heads, each with its whole tie chain as the chain's
/// first head moves in that head's key. A picked event moves its graces,
/// and a range moves the graces and chord symbols in it. Drum notes have no
/// pitch, so they stay. A tie left leading onto a head it did not reach
/// before is cleared. A staff step goes through [_stepped].
_Result _transpose(
  Score score,
  Selection selection,
  Transposition by, {
  required bool keys,
}) {
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
  var rekeyed = const <int, _Rekey>{};
  Transposition byIn(int bar) => rekeyed[bar]?.by ?? by;
  KeySignature keyIn(int bar) => rekeyed[bar]?.key ?? score.measures[bar].key;
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
      final (:lanes, :staves, :inRange) = _covers(score, range);
      if (keys) {
        rekeyed = _rekeyed(score, range, staves, by);
        for (final MapEntry(key: bar, value: to) in rekeyed.entries) {
          if (score.measures[bar].key != to.key) {
            symbols = symbols.copyWith(
              measures: symbols.measures.replaceAt(
                bar,
                symbols.measures[bar].copyWith(key: to.key),
              ),
            );
          }
        }
      }
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
                ? _movedSymbol(d, byIn(bar), keyIn(bar))
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
        final bar = score.indexOf(chain.first.timed.ref.measure);
        final to = _moved(pitch, byIn(bar), keyIn(bar));
        for (final link in chain) {
          moved[link.note.id] = to;
        }
      }
    }
    for (final timed in graced) {
      final bar = score.indexOf(timed.ref.measure);
      for (final note in _graceNotes(timed)) {
        moved[note.id] = _moved(note.pitch, byIn(bar), keyIn(bar));
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
    final bar = score.indexOf(timed.ref.measure);
    transposed = _replace(
      transposed,
      timed,
      _ornamentMoved(
        chord,
        chord.copyWith(
          notes: pitched(chord.notes),
          graces: graces[chord.id],
        ),
        byIn(bar),
        key: score.measures[bar].key,
        movedKey: keyIn(bar),
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
/// its lowest head, read in [key] and spelled in [movedKey]. An accidental
/// whose note would no longer be the next scale step is taken off, and a
/// staff step takes both off, as it leaves the head with none.
ChordEvent _ornamentMoved(
  ChordEvent from,
  ChordEvent to,
  Transposition by, {
  required KeySignature key,
  required KeySignature movedKey,
}) {
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
      Alterations(movedKey),
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

/// A bar's key after a transpose, and the move that spells its notes in
/// that key.
typedef _Rekey = ({KeySignature key, Transposition by});

/// The bars of [range] whose key moves with their notes, by index. A key
/// is one for every staff, so a bar's key moves only when the range holds
/// the whole bar on every staff that reads a key. A staff step moves none.
Map<int, _Rekey> _rekeyed(
  Score score,
  RangeSelection range,
  Set<StaffId> staves,
  Transposition by,
) {
  if (by is ByScaleSteps ||
      score.staves.any(
        (staff) =>
            !staves.contains(staff.id) &&
            !score.partOf(staff.id).instrument.isPercussion,
      )) {
    return const {};
  }
  final RangeSelection(:from, :to) = range;
  final first = score.indexOf(from.measure) + (from.offset.isZero ? 0 : 1);
  final last =
      score.indexOf(to.measure) -
      (to.offset < _barEnd(score.column(to.measure)) ? 1 : 0);
  return {
    for (var bar = first; bar <= last; bar++)
      bar: _rekey(score.measures[bar].key, by),
  };
}

_Rekey _rekey(KeySignature key, Transposition by) {
  switch (by) {
    case ByInterval(:final interval):
      final exact = key.fifths + 7 * interval.semitones - 12 * interval.steps;
      // A key past seven sharps or flats is written as the key that sounds
      // the same, twelve fifths back and one letter over, and so are its
      // notes.
      final turns = exact.sign * ((exact.abs() + 4) ~/ 12);
      return (
        key: KeySignature(exact - 12 * turns, key.mode),
        by: ByInterval(interval + Interval(turns, 0)),
      );
    case BySemitones(:final semitones) when semitones % 12 != 0:
      // The key with the fewest sharps or flats, and of two with six, the
      // one on the old key's side.
      final near = (key.fifths + 7 * semitones + 6) % 12 - 6;
      return (
        key: KeySignature(
          near == -6 && key.fifths >= 0 ? 6 : near,
          key.mode,
        ),
        by: by,
      );
    case BySemitones() || ByScaleSteps():
      return (key: key, by: by);
  }
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
