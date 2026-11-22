/// The rules a stored value keeps. Each function returns why its value
/// breaks the rule, or null. The edits refuse with that message and the
/// file readers fail with it at the value's path, so every way into a score
/// accepts the same values. [lostGlissandoNote] returns a note in place of
/// a message, and an edit or a reader leaves the line out with it.
library;

import 'events.dart';
import 'pitch.dart';
import 'refs.dart';
import 'score.dart';
import 'time.dart';

const _units = {1, 2, 4, 8, 16, 32, 64, 128};

/// The longest bar. Filling a bar with rests costs time in proportion to
/// its length, so the length is capped.
final _longest = Length(Fraction(64));

/// The deepest tuplets nest. Reading a voice recurses once per level of
/// nesting, so the depth is capped.
const _deepest = 16;

/// Refuses a MIDI [number], such as a key or a program, outside 0 to 127.
String? midiProblem(int number) =>
    number >= 0 && number <= 127 ? null : 'a MIDI number is 0 to 127';

/// Refuses a negative sound [bank].
String? bankProblem(int bank) => bank >= 0 ? null : 'a bank is 0 or more';

/// Refuses a key of more than 7 flats or 7 sharps, counted in [fifths].
String? keyProblem(int fifths) =>
    fifths >= -7 && fifths <= 7 ? null : 'a key has 7 flats to 7 sharps';

/// Refuses a repeat that plays fewer than 2 [times].
String? repeatProblem(int times) =>
    times >= 2 ? null : 'a repeat plays twice or more';

/// Refuses a [bpm] that is not a finite number above 0.
String? tempoProblem(double bpm) =>
    bpm > 0 && bpm.isFinite ? null : 'a tempo is a finite number above 0';

/// Refuses a tempo line [factor] that is not a finite number above 0.
String? factorProblem(double factor) => factor > 0 && factor.isFinite
    ? null
    : 'a factor is a finite number above 0';

/// Refuses a negative [finger] number.
String? fingerProblem(int finger) =>
    finger >= 0 ? null : 'a finger number is 0 or more';

/// Refuses a tuplet ratio [term] of 0 or less.
String? ratioTermProblem(int term) =>
    term > 0 ? null : 'ratio terms are above 0';

/// [depth] counts a tuplet and every tuplet around it.
String? tupletDepthProblem(int depth) =>
    depth <= _deepest ? null : 'tuplets nest at most $_deepest deep';

/// Refuses a meter [unit] that is not a power of two from 1 to 128.
String? unitProblem(int unit) =>
    _units.contains(unit) ? null : 'the unit is a power of two up to 128';

/// Refuses a [meter] with no groups, a group of no beats, a bad unit, or a bar
/// length that [barLengthProblem] refuses.
String? meterProblem(Meter meter) =>
    meter.groups.isEmpty || meter.groups.any((beats) => beats < 1)
    ? 'a meter has groups of 1 or more beats'
    : unitProblem(meter.unit) ?? barLengthProblem(meter.length);

/// Refuses a bar [length] that is not a whole number of 128th notes above 0, or
/// that is longer than 64 whole notes.
String? barLengthProblem(Length length) {
  if (!length.isPositive || !_onGrid(length)) {
    return 'a bar holds a whole number of 128th notes';
  }
  return length > _longest ? 'a bar lasts at most 64 whole notes' : null;
}

/// Refuses a note [value] that does not last a whole number of 128th notes, as
/// a dotted 128th does not.
String? valueProblem(NoteValue value) => _onGrid(value.length)
    ? null
    : 'a value lasts a whole number of 128th notes';

/// Refuses an onset [at] that is not a whole number of 128th notes into its bar
/// or tuplet.
String? startProblem(Moment at) => _onGrid(Moment.zero.until(at))
    ? null
    : 'a note starts a whole number of 128th notes into its bar or tuplet';

bool _onGrid(Length length) =>
    (length / DurationBase.oneTwentyEighth.length).isInteger;

/// Refuses a [pitch] whose MIDI key lies outside 0 to 127.
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

/// Refuses a [string] index, from 0, that [instrument] has no string for.
String? stringProblem(Instrument instrument, int string) =>
    string >= 0 && string < instrument.strings.length
    ? null
    : 'the instrument has no such string';

/// The only articulations a rest can carry.
const Set<Articulation> restMarks = {Articulation.fermata};

/// Refuses rest [marks] that hold anything but a fermata.
String? restMarksProblem(Set<Articulation> marks) =>
    restMarks.containsAll(marks) ? null : 'a rest holds only a fermata';

/// Refuses [spanner] where it cannot stand in [score]: its ends out of
/// order, or, for one that joins notes, both ends on one event.
String? spannerProblem(Score score, Spanner spanner) =>
    spannerOrderProblem(
      joinsNotes: spanner.kind.joinsNotes,
      firstBar: score.indexOf(spanner.first.measure),
      firstOffset: spanner.first.offset,
      lastBar: score.indexOf(spanner.last.measure),
      lastOffset: spanner.last.offset,
    ) ??
    (score.isCollapsed(spanner) ? _endsAfterStart : null);

const _endsAfterStart = 'a slur or glissando ends after it starts';

/// The note a glissando [spanner] names that is not in the chord at that
/// end of it in [score], or null when each note it names is there.
NoteId? lostGlissandoNote(Score score, Spanner spanner) {
  if (spanner.kind case Glissando(from: final first, to: final last)) {
    final (:from, :to) = score.glissandoNotes(spanner);
    if (first != null && from?.id != first) {
      return first;
    }
    if (last != null && to?.id != last) {
      return last;
    }
  }
  return null;
}

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
    return order < 0 ? null : _endsAfterStart;
  }
  return order <= 0 ? null : 'a line cannot end before it starts';
}

/// Refuses a [tempo] whose bpm [tempoProblem] refuses, or whose beat
/// [valueProblem] refuses.
String? tempoMarkProblem(Tempo tempo) =>
    tempoProblem(tempo.bpm) ?? valueProblem(tempo.beat);

/// Refuses an [instrument] whose program, bank, drum keys or pitches are out of
/// range, or whose kit names a drum twice.
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

/// Refuses a [template] with no staff, with a clef count that differs from its
/// staves, or with an instrument that [instrumentProblem] refuses.
String? templateProblem(PartTemplate template) {
  final PartTemplate(:instrument, :staves, :clefs) = template;
  return staves < 1 || (clefs != null && clefs.length != staves)
      ? 'a part needs a staff and a clef each'
      : instrumentProblem(instrument);
}
