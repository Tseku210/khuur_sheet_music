part of 'playback.dart';

_Fragment _compileBar(MeasureColumn column) {
  final events = <TimedEvent>[];
  final chords = <_Chord>[];
  final holds = <(Moment, Moment)>[];
  for (final measure in column.staves) {
    for (final voice in measure.voices) {
      for (final timed in timedEvents(
        voice,
        measure: column.id,
        staff: measure.staff,
      )) {
        events.add(timed);
        final TimedEvent(:event, :onset, :duration) = timed;
        if (event.articulations.contains(Articulation.fermata)) {
          holds.add((onset, onset + duration));
        }
        if (event is ChordEvent) {
          chords.add(
            _Chord(
              timed,
              event,
              event.ornament == Ornament.trill
                  ? null
                  : _attacks(timed, event, column),
            ),
          );
        }
      }
    }
  }
  return _Fragment(events, chords, holds);
}

/// What [chord] of [column] plays, in whole-note time from the bar's
/// downbeat. Its graces play first, on the beat, in the time `_graceTime`
/// gives them, each its written share, unless [graces] is false because the
/// chord before it played them. Its notes then play the figure of its
/// ornament, or of a trill when [trill] and it has none, or of its tremolo.
/// The graces of [closing], the chord after it, play at its end instead,
/// quick, as the end of its trill. A note whose ornament reaches past MIDI
/// keys 0 to 127 plays without it. [played] is the bar as it plays, which
/// times a trill.
List<_Attack> _attacks(
  TimedEvent timed,
  ChordEvent chord,
  MeasureColumn column, {
  bool trill = false,
  bool graces = true,
  _Chord? closing,
  _Bar? played,
}) {
  final TimedEvent(:onset, :duration, :ref) = timed;
  final key = column.key;
  final attacks = <_Attack>[];
  void play(Seq<GraceChord> graces, Moment from, Length time, EventRef of) {
    final written = _written(graces);
    var at = from;
    for (final grace in graces) {
      final length = grace.value.length * (time / written);
      for (final note in grace.notes) {
        attacks.add(
          _Attack(
            onset: at,
            length: length,
            note: note,
            stress: 1,
            gate: _gate(const {}),
            joined: false,
            source: EventRef(
              measure: of.measure,
              staff: of.staff,
              id: grace.id,
            ),
          ),
        );
      }
      at += length;
    }
  }

  final own = graces ? chord.graces : const Seq<GraceChord>.empty();
  final steal = own.isEmpty
      ? Length.zero
      : _shorter(_written(own), _graceTime(own, duration, column.meter));
  play(own, onset, steal, ref);
  final ending = closing?.event.graces ?? const Seq<GraceChord>.empty();
  final close = ending.isEmpty
      ? Length.zero
      : _shorter(_written(ending), _quick(ending.length, duration - steal));
  final span = duration - steal - close;
  final ornament = chord.ornament ?? (trill ? Ornament.trill : null);
  final figure = _figure(
    ornament,
    chord,
    span,
    trillNotes: ornament == Ornament.trill
        ? _trillNotes(
            played!.secondsAt(onset + steal + span) -
                played.secondsAt(onset + steal),
            onMain: closing != null && _endsOnMain(chord, ending),
          )
        : 1,
  );
  for (final note in chord.notes) {
    final pieces = _canPlay(note, chord, figure, key)
        ? figure
        : _figure(null, chord, span);
    var at = onset + steal;
    for (final (i, (steps, length)) in pieces.indexed) {
      final last = i == pieces.length - 1;
      attacks.add(
        _Attack(
          onset: at,
          length: length,
          note: switch (note) {
            PitchedNote(:final pitch) when steps != 0 => note.copyWith(
              pitch: chord.ornamentNote(pitch, steps, key),
              tie: false,
            ),
            _ => note.copyWith(tie: last && note.tie),
          },
          stress: i == 0 ? _stress(chord.articulations) : 1,
          gate: _gate(last ? chord.articulations : const {}),
          joined: !last,
          source: ref,
        ),
      );
      at += length;
    }
  }
  if (closing != null) {
    play(ending, onset + span + steal, close, closing.timed.ref);
  }
  return attacks;
}

Length _written(Seq<GraceChord> graces) =>
    graces.fold(Length.zero, (sum, g) => sum + g.value.length);

/// How a chord plays over [length], as each piece's scale steps from the
/// written note and its length. A trill alternates with the note above in
/// [trillNotes] equal notes. Mordents and turns play their notes in 32nds,
/// or in equal shares of a shorter chord, and hold the last. A tremolo
/// repeats in the value its strokes add to the chord's own flags.
List<(int, Length)> _figure(
  Ornament? ornament,
  ChordEvent chord,
  Length length, {
  int trillNotes = 1,
}) {
  List<(int, Length)> repeat(List<int> steps, int times) => [
    for (var i = 0; i < times; i++)
      (steps[i % steps.length], length * Fraction(1, times)),
  ];

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
    Ornament.trill => repeat([0, 1], trillNotes),
    Ornament.mordent => quick([0, -1]),
    Ornament.invertedMordent => quick([0, 1]),
    Ornament.turn => quick([1, 0, -1]),
    Ornament.invertedTurn => quick([-1, 0, 1]),
    null when chord.tremolo > 0 => repeat(const [0], _tremoloNotes(chord)),
    null => [(0, length)],
  };
}

final Length _thirtySecond = NoteValue.thirtySecond.length;

/// How many times a tremolo strikes [chord]: once for each note of the
/// value its strokes add to the chord's own flags.
int _tremoloNotes(ChordEvent chord) {
  final each =
      _shorter(chord.value.base.length, NoteValue.quarter.length) *
      Fraction(1, 1 << chord.tremolo);
  return max(1, (chord.value.length / each).floor());
}

/// Seconds one note of a trill lasts at the least where its chord has the
/// room. A trill is not measured against the beat, so its speed is set in
/// time and holds at any tempo. This is 13 notes a second, the speed of a
/// 32nd at 100 quarters a minute.
const _trillNote = 0.075;

/// Seconds a trill note stays under, so no trill is slower than 8 notes a
/// second.
const _slowTrillNote = 0.125;

/// Seconds a trill note lasts at the least, a 32nd at 200 quarters a minute.
const _quickTrillNote = 0.0375;

/// How many notes a trill plays in [seconds]: an odd count when it ends
/// [onMain], on its main note, and an even one to end on the note above. It
/// is the most that last [_trillNote] each, or two more when those would
/// last [_slowTrillNote]. A chord too short for that plays the fewest that
/// alternate, or its one note when they would be shorter than
/// [_quickTrillNote].
int _trillNotes(double seconds, {required bool onMain}) {
  final least = onMain ? 3 : 2;
  final time = seconds + _sameInstant;
  if (time / least < _quickTrillNote) {
    return 1;
  }
  final fit = least + 2 * ((time / _trillNote - least) / 2).floor();
  if (fit < least) {
    return least;
  }
  return time / fit >= _slowTrillNote ? fit + 2 : fit;
}

/// Whether a trill on [chord] ends on its main note before [graces] end it,
/// so a turn below it leads on. It ends on the note above when the graces
/// start on the main note, which would otherwise strike twice.
bool _endsOnMain(ChordEvent chord, Seq<GraceChord> graces) =>
    switch ((chord.notes.first, graces.first.notes.first)) {
      (PitchedNote(:final pitch), PitchedNote(pitch: final grace)) =>
        pitch.midiKey != grace.midiKey,
      _ => true,
    };

/// The most time [graces] may take from a principal of [duration] in
/// [meter], as MuseScore 4 plays them. A lone appoggiatura may lean on
/// half its principal, or two thirds of one longer than an eighth in a
/// compound meter, where the principal is dotted. Any other graces are
/// quick, a 64th each, and together at most half the principal. Graces
/// written shorter than that take their written length.
Length _graceTime(Seq<GraceChord> graces, Length duration, Meter meter) =>
    graces.length == 1 && graces.single.kind == GraceKind.appoggiatura
    ? duration *
          (meter.isCompound && duration > NoteValue.eighth.length
              ? Fraction(2, 3)
              : Fraction(1, 2))
    : _quick(graces.length, duration);

/// The most time [count] quick graces may take from a principal of
/// [duration]: a 64th each, and together at most half the principal.
Length _quick(int count, Length duration) =>
    _shorter(_sixtyFourth * Fraction(count), duration * Fraction(1, 2));

final Length _sixtyFourth = DurationBase.sixtyFourth.length;

Length _shorter(Length a, Length b) => a < b ? a : b;

/// Whether every neighbour [figure] asks of [note] of [chord] in [key] is
/// a MIDI key.
bool _canPlay(
  Note note,
  ChordEvent chord,
  List<(int, Length)> figure,
  KeySignature key,
) =>
    note is! PitchedNote ||
    figure.every(
      (piece) =>
          piece.$1 == 0 ||
          pitchProblem(chord.ornamentNote(note.pitch, piece.$1, key)) == null,
    );

/// The share of its time a note sounds, by the marks on the last note of
/// its chain, or null where no mark sets it and it sounds [_unmarkedGate].
/// A staccato under a tenuto is a portato.
double? _gate(Set<Articulation> marks) => switch ((
  marks.contains(Articulation.staccatissimo),
  marks.contains(Articulation.staccato),
  marks.contains(Articulation.tenuto),
)) {
  (true, _, _) => 0.25,
  (_, true, true) => 0.75,
  (_, true, _) => 0.5,
  (_, _, true) => 1,
  _ => null,
};

/// How much harder than its dynamic a note strikes, by the marks on the
/// first note of its chain.
double _stress(Set<Articulation> marks) =>
    (marks.contains(Articulation.accent) ? 1.25 : 1) *
    (marks.contains(Articulation.marcato) ? 1.5 : 1);

/// The share of its time a note with no staccato or tenuto sounds. It stops
/// just short of the note after it, as in MuseScore 4, whose strings, winds
/// and voices sound an unmarked note for 99% of its time.
const _unmarkedGate = 0.99;
