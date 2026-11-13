/// The rules a stored value keeps. Each function returns why its value
/// breaks the rule, or null. The edits refuse with that message and the
/// file readers fail with it at the value's path, so every way into a score
/// accepts the same values.
library;

import 'events.dart';
import 'pitch.dart';
import 'score.dart';
import 'time.dart';

const _units = {1, 2, 4, 8, 16, 32, 64, 128};

/// The longest bar. Filling a bar with rests costs time in proportion to
/// its length, so the length is capped.
final _longest = Length(Fraction(64));

/// The deepest tuplets nest. Reading a voice recurses once per level of
/// nesting, so the depth is capped.
const _deepest = 16;

String? midiProblem(int number) =>
    number >= 0 && number <= 127 ? null : 'a MIDI number is 0 to 127';

String? bankProblem(int bank) => bank >= 0 ? null : 'a bank is 0 or more';

String? keyProblem(int fifths) =>
    fifths >= -7 && fifths <= 7 ? null : 'a key has 7 flats to 7 sharps';

String? repeatProblem(int times) =>
    times >= 2 ? null : 'a repeat plays twice or more';

String? tempoProblem(double bpm) =>
    bpm > 0 && bpm.isFinite ? null : 'a tempo is a finite number above 0';

String? factorProblem(double factor) => factor > 0 && factor.isFinite
    ? null
    : 'a factor is a finite number above 0';

String? fingerProblem(int finger) =>
    finger >= 0 ? null : 'a finger number is 0 or more';

String? ratioTermProblem(int term) =>
    term > 0 ? null : 'ratio terms are above 0';

/// [depth] counts a tuplet and every tuplet around it.
String? tupletDepthProblem(int depth) =>
    depth <= _deepest ? null : 'tuplets nest at most $_deepest deep';

String? unitProblem(int unit) =>
    _units.contains(unit) ? null : 'the unit is a power of two up to 128';

String? meterProblem(Meter meter) =>
    meter.groups.isEmpty || meter.groups.any((beats) => beats < 1)
    ? 'a meter has groups of 1 or more beats'
    : unitProblem(meter.unit) ?? barLengthProblem(meter.length);

String? barLengthProblem(Length length) {
  if (!length.isPositive || !_onGrid(length)) {
    return 'a bar holds a whole number of 128th notes';
  }
  return length > _longest ? 'a bar lasts at most 64 whole notes' : null;
}

String? valueProblem(NoteValue value) => _onGrid(value.length)
    ? null
    : 'a value lasts a whole number of 128th notes';

String? startProblem(Moment at) => _onGrid(Moment.zero.until(at))
    ? null
    : 'a note starts a whole number of 128th notes into its bar or tuplet';

bool _onGrid(Length length) =>
    (length / DurationBase.oneTwentyEighth.length).isInteger;

String? pitchProblem(Pitch pitch) => pitch.midiKey >= 0 && pitch.midiKey <= 127
    ? null
    : 'a pitch lies within MIDI keys 0 to 127';

/// Whether [instrument] takes a tone of the kind a note offers: a drum on a
/// percussion staff, a pitch on a pitched one.
String? toneKindProblem(Instrument instrument, {required bool isDrum}) {
  if (isDrum == instrument.isPercussion) {
    return null;
  }
  return isDrum
      ? 'a pitched staff takes pitches'
      : 'a percussion staff takes drums';
}

/// A pitch in the MIDI range on a pitched staff, or a drum of the part's
/// kit on a percussion staff.
String? toneProblem(Instrument instrument, Tone tone) => switch (tone) {
  Pitch() => toneKindProblem(instrument, isDrum: false) ?? pitchProblem(tone),
  Drum() =>
    toneKindProblem(instrument, isDrum: true) ??
        (instrument.soundOf(tone) == null ? 'the kit has no $tone' : null),
};

String? stringProblem(Instrument instrument, int string) =>
    string >= 0 && string < instrument.strings.length
    ? null
    : 'the instrument has no such string';

/// The only articulations a rest can carry.
const Set<Articulation> restMarks = {Articulation.fermata};

String? restMarksProblem(Set<Articulation> marks) =>
    restMarks.containsAll(marks) ? null : 'a rest holds only a fermata';

/// A spanner that joins notes ends after it starts; any other ends no
/// sooner than it starts. The ends are bar indices and offsets so the rule
/// needs no [Score].
String? spannerOrderProblem({
  required bool joinsNotes,
  required int firstBar,
  required Moment firstOffset,
  required int lastBar,
  required Moment lastOffset,
}) {
  final order = firstBar != lastBar
      ? firstBar.compareTo(lastBar)
      : firstOffset.compareTo(lastOffset);
  if (joinsNotes) {
    return order < 0 ? null : 'a slur or glissando ends after it starts';
  }
  return order <= 0 ? null : 'a line cannot end before it starts';
}

String? tempoMarkProblem(Tempo tempo) =>
    tempoProblem(tempo.bpm) ?? valueProblem(tempo.beat);

String? instrumentProblem(Instrument instrument) {
  final names = <String>{};
  return midiProblem(instrument.program) ??
      bankProblem(instrument.bank) ??
      [
        for (final DrumSound(:name, :midiKey, :position) in instrument.drums)
          (names.add(name) ? null : 'the kit names $name twice') ??
              midiProblem(midiKey) ??
              pitchProblem(position),
        for (final pitch in [
          ...instrument.strings,
          ?instrument.lowest,
          ?instrument.highest,
        ])
          pitchProblem(pitch),
      ].nonNulls.firstOrNull;
}

String? templateProblem(PartTemplate template) {
  final PartTemplate(:instrument, :staves, :clefs) = template;
  return staves < 1 || (clefs != null && clefs.length != staves)
      ? 'a part needs a staff and a clef each'
      : instrumentProblem(instrument);
}
