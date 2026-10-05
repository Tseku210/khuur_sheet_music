part of 'session.dart';

// Each edit here touches one column, except [SetTone] on a tie chain and
// [RemoveNote] when it clears a tie from the bar before. An edit that
// changes nothing returns the same score.

_Result _setNoteTone(Score score, NoteRef note, Tone tone) {
  _checkTone(score, note.event.staff, tone);
  return _Result(_setTone(score, _targetHead(score, note), tone));
}

_Result _setTie(Score score, NoteRef note, bool tied) {
  final head = _targetHead(score, note);
  return _changeNote(
    score,
    head,
    head.note.tie == tied ? head.note : head.note.copyWith(tie: tied),
  );
}

_Result _setFingering(Score score, NoteRef note, int? finger) {
  if (finger != null) {
    _check(fingerProblem(finger));
  }
  final head = _targetHead(score, note);
  final pitched = _pitchedOnly(head, 'fingering');
  return _changeNote(
    score,
    head,
    pitched.fingering == finger
        ? pitched
        : pitched.copyWith(fingering: () => finger),
  );
}

_Result _setString(Score score, NoteRef note, int? string) {
  final head = _targetHead(score, note);
  final pitched = _pitchedOnly(head, 'string');
  final strings = score.partOf(head.timed.ref.staff).instrument.strings;
  if (string != null && (string < 0 || string >= strings.length)) {
    throw const _Refuse(InvalidValue('the instrument has no such string'));
  }
  return _changeNote(
    score,
    head,
    pitched.string == string ? pitched : pitched.copyWith(string: () => string),
  );
}

_Result _setAccidental(Score score, NoteRef note, AccidentalRequest request) {
  final head = _targetHead(score, note);
  final pitched = _pitchedOnly(head, 'accidental');
  return _changeNote(
    score,
    head,
    pitched.accidental == request
        ? pitched
        : pitched.copyWith(accidental: request),
  );
}

_Result _addGrace(
  Score score,
  EventRef event,
  Tone tone,
  GraceKind kind,
  NoteValue value,
  _Ids ids,
) {
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
            value: _checked(value),
            notes: Seq([_noteOn(score, event.staff, ids.note(), tone)]),
          ),
        ),
      ),
    ),
  );
}

_Result _setArticulation(
  Score score,
  EventRef event,
  Articulation articulation,
  bool present,
) {
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
}

_Result _setOrnament(Score score, EventRef event, Ornament? ornament) {
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
}

_Result _setBowing(Score score, EventRef event, Bowing? bowing) {
  final timed = _target(score, event);
  return _changeEvent(
    score,
    timed,
    _chordOnly(
      timed.event,
      clears: bowing == null,
      change: (chord) =>
          chord.bowing == bowing ? chord : chord.copyWith(bowing: () => bowing),
    ),
  );
}

_Result _setBeam(Score score, EventRef event, BeamMode mode) {
  final timed = _target(score, event);
  return _changeEvent(
    score,
    timed,
    _chordOnly(
      timed.event,
      clears: mode == BeamMode.auto,
      change: (chord) =>
          chord.beam == mode ? chord : chord.copyWith(beam: mode),
    ),
  );
}

_Result _setLyric(Score score, EventRef event, int verse, Lyric? lyric) {
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
}

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
    (n) => n.tie && n.tone == note.tone,
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

/// Moves [head] and every head tied to it to [tone], keeping each chord in
/// tone order. Refused when a chord in the chain already has [tone].
Score _setTone(Score score, _Head head, Tone tone) {
  if (head.note.tone == tone) {
    return score;
  }
  var moved = score;
  for (final (:timed, :chord, :note) in _tieChain(score, head)) {
    if (chord.notes.any((n) => n.tone == tone)) {
      throw _Refuse(InvalidValue('the chord already has $tone'));
    }
    final notes = [
      for (final n in chord.notes) n.id == note.id ? _retoned(n, tone) : n,
    ]..sort((a, b) => a.tone.compareTo(b.tone));
    moved = _replace(moved, timed, chord.copyWith(notes: Seq(notes)));
  }
  return moved;
}

/// Adds [tone] to the event [ref] names, which keeps its id. A rest
/// becomes a chord of its value, and a measure rest becomes chords that
/// fill the bar, tied.
_Result _addToChord(Score score, EventRef ref, Tone tone, _Ids ids) {
  final timed = _target(score, ref);
  switch (timed.event) {
    case ChordEvent(:final notes) when notes.any((n) => n.tone == tone):
      return _Result(score);
    case final ChordEvent chord:
      final note = _noteOn(
        score,
        ref.staff,
        ids.note(),
        tone,
        tie:
            chord.notes.any((n) => n.tie) &&
            _headWhere(_next(score, timed), (n) => n.tone == tone) != null,
      );
      final above = chord.notes.indexWhere((n) => n.tone.compareTo(tone) > 0);
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
          notes: Seq([_noteOn(score, ref.staff, ids.note(), tone)]),
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
                  _noteOn(
                    score,
                    ref.staff,
                    ids.note(),
                    tone,
                    tie: k < values.length - 1,
                  ),
                ]),
              ),
          ],
        ),
      );
  }
}

/// [note] playing [tone] instead, which [_checkTone] has matched to it.
Note _retoned(Note note, Tone tone) => switch ((note, tone)) {
  (final PitchedNote note, final Pitch pitch) => note.copyWith(pitch: pitch),
  (final DrumNote note, final Drum drum) => note.copyWith(drum: drum),
  _ => throw StateError('$tone on a ${note.runtimeType}'),
};

/// [head]'s note, refused when it is a drum note, which has no [what].
PitchedNote _pitchedOnly(_Head head, String what) => switch (head.note) {
  final PitchedNote note => note,
  DrumNote() => throw _Refuse(InvalidValue('a drum note has no $what')),
};
