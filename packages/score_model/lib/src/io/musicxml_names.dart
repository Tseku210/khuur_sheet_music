/// The MusicXML names export writes and import reads, one table per concept,
/// so a name cannot be written one way and read another. Internal to the
/// package.
///
/// Each table is a switch from the model's value to its name. The reading
/// direction is derived from it. Where a name has no single inverse, the
/// reading is spelled out next to the table.
library;

import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../time.dart';

String typeName(DurationBase base) => switch (base) {
  DurationBase.breve => 'breve',
  DurationBase.whole => 'whole',
  DurationBase.half => 'half',
  DurationBase.quarter => 'quarter',
  DurationBase.eighth => 'eighth',
  DurationBase.sixteenth => '16th',
  DurationBase.thirtySecond => '32nd',
  DurationBase.sixtyFourth => '64th',
  DurationBase.oneTwentyEighth => '128th',
};

final Map<String, DurationBase> baseByTypeName = {
  for (final base in DurationBase.values) typeName(base): base,
};

/// Accidental names by alteration, from double flat up. Import reads a
/// note's alteration from its `<alter>`, so it only asks whether an
/// `<accidental>` is there, not which one.
const accidentalNames = [
  'flat-flat',
  'three-quarters-flat',
  'flat',
  'quarter-flat',
  'natural',
  'quarter-sharp',
  'sharp',
  'three-quarters-sharp',
  'double-sharp',
];

/// The `<notehead>` for [head], or null for the normal head, which export
/// leaves out.
String? noteheadName(NoteHead head) => switch (head) {
  NoteHead.normal => null,
  NoteHead.cross => 'x',
  NoteHead.diamond => 'diamond',
  NoteHead.slash => 'slash',
  NoteHead.triangle => 'triangle',
  NoteHead.circleCross => 'circle-x',
};

/// Reading: `normal` and MusicXML's separate `cross` head also read, as
/// [NoteHead.normal] and [NoteHead.cross]. Other heads read as normal.
final Map<String, NoteHead> headByName = {
  'normal': NoteHead.normal,
  'cross': NoteHead.cross,
  for (final head in NoteHead.values)
    if (noteheadName(head) case final String name) name: head,
};

String ornamentName(Ornament ornament) => switch (ornament) {
  Ornament.trill => 'trill-mark',
  Ornament.mordent => 'mordent',
  Ornament.invertedMordent => 'inverted-mordent',
  Ornament.turn => 'turn',
  Ornament.invertedTurn => 'inverted-turn',
};

/// Reading: a `trill-mark` beside a `wavy-line type="start"` is the trill
/// line's sign, not an ornament.
final Map<String, Ornament> ornamentByName = {
  for (final ornament in Ornament.values) ornamentName(ornament): ornament,
};

/// The `<articulations>` child for [articulation], or null for the two
/// written elsewhere: a fermata under `<notations>`, a harmonic under
/// `<technical>`.
String? articulationName(Articulation articulation) => switch (articulation) {
  Articulation.staccato => 'staccato',
  Articulation.staccatissimo => 'staccatissimo',
  Articulation.accent => 'accent',
  Articulation.marcato => 'strong-accent',
  Articulation.tenuto => 'tenuto',
  Articulation.fermata || Articulation.harmonic => null,
};

final Map<String, Articulation> articulationByName = {
  for (final articulation in Articulation.values)
    if (articulationName(articulation) case final String name)
      name: articulation,
};

/// MusicXML's `<kind>` for a chord quality, where it has one. Export writes
/// `other` for the rest, with the quality as the kind's text.
///
/// Reading: the kind's `text` attribute is the quality. Without it, a kind
/// reads back through this table, and `other` or an unknown kind reads as
/// `''`.
const chordKinds = {
  '': 'major',
  'm': 'minor',
  'aug': 'augmented',
  'dim': 'diminished',
  '7': 'dominant',
  'maj7': 'major-seventh',
  'm7': 'minor-seventh',
  'dim7': 'diminished-seventh',
  'aug7': 'augmented-seventh',
  'm7b5': 'half-diminished',
  'mMaj7': 'major-minor',
  '6': 'major-sixth',
  'm6': 'minor-sixth',
  '9': 'dominant-ninth',
  'maj9': 'major-ninth',
  'm9': 'minor-ninth',
  '11': 'dominant-11th',
  '13': 'dominant-13th',
  'sus2': 'suspended-second',
  'sus4': 'suspended-fourth',
  '5': 'power',
};

final Map<String, String> qualityByKind = {
  for (final MapEntry(:key, :value) in chordKinds.entries) value: key,
};

/// The `<bar-style>` of a bar's right barline, or null when it prints none.
/// A regular barline before a backward repeat prints light-heavy.
String? barStyleName(Barline barline, {required bool repeats}) =>
    switch (barline) {
      Barline.regular => repeats ? 'light-heavy' : null,
      Barline.doubleBar => 'light-light',
      Barline.finalBar => 'light-heavy',
      Barline.dashed => 'dashed',
      Barline.dotted => 'dotted',
      Barline.heavy => 'heavy',
      Barline.invisible => 'none',
    };

/// Reading: light-heavy before a backward repeat reads as
/// [Barline.regular], and as [Barline.finalBar] otherwise. Styles the model
/// has no barline for (heavy-light, heavy-heavy, tick, short) read as
/// regular.
Barline barlineByStyle(String style, {required bool repeats}) =>
    style == 'light-heavy' && repeats
    ? Barline.regular
    : Barline.values
              .where(
                (barline) => barStyleName(barline, repeats: false) == style,
              )
              .firstOrNull ??
          Barline.regular;

String clefSignName(ClefSign sign) => switch (sign) {
  ClefSign.g => 'G',
  ClefSign.f => 'F',
  ClefSign.c => 'C',
  ClefSign.percussion => 'percussion',
};

/// Reading: a sign the model has no clef for (TAB, jianpu, none) has no
/// entry. A percussion clef reads whatever its line, and a clef without a
/// line takes its sign's usual one.
final Map<String, ClefSign> clefSignByName = {
  for (final sign in ClefSign.values) clefSignName(sign): sign,
};
