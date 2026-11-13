part of 'playback.dart';

_Fragment _compileBar(MeasureColumn column) {
  final chords = <_Chord>[];
  final holds = <(Moment, Moment)>[];
  for (final measure in column.staves) {
    for (final voice in measure.voices) {
      for (final timed in timedEvents(
        voice,
        measure: column.id,
        staff: measure.staff,
      )) {
        final TimedEvent(:event, :onset, :duration) = timed;
        if (event.articulations.contains(Articulation.fermata)) {
          holds.add((onset, onset + duration));
        }
        if (event is ChordEvent) {
          chords.add(_Chord(timed, event, _attacks(timed, event, column.key)));
        }
      }
    }
  }
  return _Fragment(chords, holds);
}

/// What [chord] plays, in whole-note time from the bar's downbeat. Its
/// graces play first, on the beat. Acciaccaturas take a 32nd each and any
/// appoggiatura takes half the chord, and together they take at most half.
/// Its notes then play the figure of its ornament, or of a trill when
/// [trill] and it has none, or of its tremolo. A note whose ornament
/// reaches past MIDI keys 0 to 127 plays without it.
List<_Attack> _attacks(
  TimedEvent timed,
  ChordEvent chord,
  KeySignature key, {
  bool trill = false,
}) {
  final TimedEvent(:onset, :duration, :ref) = timed;
  final graces = chord.graces;
  final half = duration * Fraction(1, 2);
  final steal = graces.isEmpty
      ? Length.zero
      : graces.any((g) => g.kind == GraceKind.appoggiatura)
      ? half
      : _shorter(_thirtySecond * Fraction(graces.length), half);
  final attacks = [
    for (final (i, grace) in graces.indexed)
      for (final note in grace.notes)
        _Attack(
          onset: onset + steal * Fraction(i, graces.length),
          length: steal * Fraction(1, graces.length),
          note: note,
          stress: 1,
          gate: _gate(const {}),
          source: EventRef(
            measure: ref.measure,
            staff: ref.staff,
            id: grace.id,
          ),
        ),
  ];
  final figure = _figure(
    chord.ornament ?? (trill ? Ornament.trill : null),
    chord,
    duration - steal,
  );
  for (final note in chord.notes) {
    final pieces = _canPlay(note, figure, key)
        ? figure
        : _figure(null, chord, duration - steal);
    var at = onset + steal;
    for (final (i, (steps, length)) in pieces.indexed) {
      final last = i == pieces.length - 1;
      attacks.add(
        _Attack(
          onset: at,
          length: length,
          note: switch (note) {
            PitchedNote(:final pitch) when steps != 0 => note.copyWith(
              pitch: _neighbour(pitch, steps, key),
              tie: false,
            ),
            _ => note.copyWith(tie: last && note.tie),
          },
          stress: i == 0 ? _stress(chord.articulations) : 1,
          gate: _gate(last ? chord.articulations : const {}),
          source: ref,
        ),
      );
      at += length;
    }
  }
  return attacks;
}

/// How a chord plays over [length], as each piece's scale steps from the
/// written note and its length. A trill alternates with the note above in
/// 32nds. Mordents and turns play their notes in 32nds, or in equal shares
/// of a shorter chord, and hold the last. A tremolo repeats in the value
/// its strokes add to the chord's own flags.
List<(int, Length)> _figure(
  Ornament? ornament,
  ChordEvent chord,
  Length length,
) {
  List<(int, Length)> repeat(List<int> steps, Length span, Length each) {
    final ratio = span / each;
    final count = max(1, ratio.numerator ~/ ratio.denominator);
    return [
      for (var i = 0; i < count; i++)
        (steps[i % steps.length], length * Fraction(1, count)),
    ];
  }

  List<(int, Length)> quick(List<int> steps) {
    final each = _shorter(
      _thirtySecond,
      length * Fraction(1, steps.length + 1),
    );
    return [
      for (final step in steps) (step, each),
      (0, length - each * Fraction(steps.length)),
    ];
  }

  return switch (ornament) {
    Ornament.trill => repeat([0, 1], length, _thirtySecond),
    Ornament.mordent => quick([0, -1]),
    Ornament.invertedMordent => quick([0, 1]),
    Ornament.turn => quick([1, 0, -1]),
    Ornament.invertedTurn => quick([-1, 0, 1]),
    null when chord.tremolo > 0 => repeat(
      [0],
      chord.value.length,
      _shorter(chord.value.base.length, NoteValue.quarter.length) *
          Fraction(1, 1 << chord.tremolo),
    ),
    null => [(0, length)],
  };
}

final Length _thirtySecond = NoteValue.thirtySecond.length;

Length _shorter(Length a, Length b) => a < b ? a : b;

/// The note [steps] scale steps from [pitch] in [key].
Pitch _neighbour(Pitch pitch, int steps, KeySignature key) {
  final diatonic = pitch.diatonic + steps;
  final step = Step.values[diatonic % 7];
  return Pitch(step, (diatonic - step.index) ~/ 7, key.alterFor(step));
}

/// Whether every neighbour [figure] asks of [note] in [key] is a MIDI key.
bool _canPlay(Note note, List<(int, Length)> figure, KeySignature key) =>
    note is! PitchedNote ||
    figure.every(
      (piece) =>
          piece.$1 == 0 ||
          pitchProblem(_neighbour(note.pitch, piece.$1, key)) == null,
    );

/// The share of its time a note sounds, by the marks on the last note of
/// its chain. A staccato under a tenuto is a portato.
double _gate(Set<Articulation> marks) => switch ((
  marks.contains(Articulation.staccatissimo),
  marks.contains(Articulation.staccato),
  marks.contains(Articulation.tenuto),
)) {
  (true, _, _) => 0.25,
  (_, true, true) => 0.75,
  (_, true, _) => 0.5,
  (_, _, true) => 1,
  _ => 0.9,
};

/// How much harder than its dynamic a note strikes, by the marks on the
/// first note of its chain.
double _stress(Set<Articulation> marks) =>
    (marks.contains(Articulation.accent) ? 1.25 : 1) *
    (marks.contains(Articulation.marcato) ? 1.5 : 1);
