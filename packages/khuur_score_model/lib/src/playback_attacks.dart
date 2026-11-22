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
          chords.add(_Chord(timed, event, _attacks(timed, event, column)));
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
/// keys 0 to 127 plays without it.
List<_Attack> _attacks(
  TimedEvent timed,
  ChordEvent chord,
  MeasureColumn column, {
  bool trill = false,
  bool graces = true,
  _Chord? closing,
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
  final figure = _figure(
    chord.ornament ?? (trill ? Ornament.trill : null),
    chord,
    span,
    trillEnd: closing == null ? null : _trillEnd(chord, ending),
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
/// 32nds, and ends on step [trillEnd] when one is given, a note fewer when
/// it must. Mordents and turns play their notes in 32nds, or in equal shares
/// of a shorter chord, and hold the last. A tremolo repeats in the value
/// its strokes add to the chord's own flags.
List<(int, Length)> _figure(
  Ornament? ornament,
  ChordEvent chord,
  Length length, {
  int? trillEnd,
}) {
  List<(int, Length)> repeat(
    List<int> steps,
    Length span,
    Length each, {
    int? last,
  }) {
    final ratio = span / each;
    var count = max(1, ratio.floor());
    if (last != null &&
        count > 1 &&
        steps[(count - 1) % steps.length] != last) {
      count--;
    }
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
    Ornament.trill => repeat([0, 1], length, _thirtySecond, last: trillEnd),
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

/// The step a trill on [chord] ends on before [graces] end it: its main
/// note, so a turn below it leads on, or the note above when the graces
/// start on the main note, which would otherwise strike twice.
int _trillEnd(ChordEvent chord, Seq<GraceChord> graces) =>
    switch ((chord.notes.first, graces.first.notes.first)) {
      (PitchedNote(:final pitch), PitchedNote(pitch: final grace))
          when pitch.midiKey == grace.midiKey =>
        1,
      _ => 0,
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
/// its chain, or null where no mark sets it. A staccato under a tenuto is a
/// portato.
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
