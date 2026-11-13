/// The glyph that engraves each value of the score model on its own: a note,
/// a rest, an accidental, a dynamic, a bowing and a fingering. Layout takes
/// these values' glyphs from here, so an app that draws one of the same
/// values in its own controls, as a palette does, shows what the sheet shows.
///
/// A glyph is drawn as the one character `String.fromCharCode(codepoint)` in
/// the music font, whose em is four staff spaces.
library;

import 'package:score_model/score_model.dart';

import 'glyphs.dart';
import 'style.dart';

/// The note of [base] as one glyph, stem up, with its flags: the note a
/// tempo mark prints. A dotted value follows it with one
/// [Glyph.metAugmentationDot] per dot.
///
/// A note on a staff is engraved from a head, a stem and a flag instead,
/// since its stem and beams depend on its neighbours.
Glyph noteGlyph(DurationBase base) => switch (base) {
  DurationBase.breve => Glyph.metNoteDoubleWhole,
  DurationBase.whole => Glyph.metNoteWhole,
  DurationBase.half => Glyph.metNoteHalfUp,
  DurationBase.quarter => Glyph.metNoteQuarterUp,
  DurationBase.eighth => Glyph.metNote8thUp,
  DurationBase.sixteenth => Glyph.metNote16thUp,
  DurationBase.thirtySecond => Glyph.metNote32ndUp,
  DurationBase.sixtyFourth => Glyph.metNote64thUp,
  DurationBase.oneTwentyEighth => Glyph.metNote128thUp,
};

/// The rest of [base]. A dotted rest is followed by one
/// [Glyph.augmentationDot] per dot.
Glyph restGlyph(DurationBase base) => switch (base) {
  DurationBase.breve => Glyph.restDoubleWhole,
  DurationBase.whole => Glyph.restWhole,
  DurationBase.half => Glyph.restHalf,
  DurationBase.quarter => Glyph.restQuarter,
  DurationBase.eighth => Glyph.rest8th,
  DurationBase.sixteenth => Glyph.rest16th,
  DurationBase.thirtySecond => Glyph.rest32nd,
  DurationBase.sixtyFourth => Glyph.rest64th,
  DurationBase.oneTwentyEighth => Glyph.rest128th,
};

/// The accidental of [alter]. [family] picks the glyphs of the quarter-tone
/// alters and leaves the others alone. A sheet uses its style's
/// `quarterTones`.
Glyph accidentalGlyph(Alter alter, QuarterToneGlyphs family) {
  final stein = family == QuarterToneGlyphs.steinZimmermann;
  return switch (alter.quarterTones) {
    -4 => Glyph.accidentalDoubleFlat,
    -3 =>
      stein
          ? Glyph.accidentalThreeQuarterTonesFlatZimmermann
          : Glyph.accidentalThreeQuarterTonesFlatArrowDown,
    -2 => Glyph.accidentalFlat,
    -1 =>
      stein
          ? Glyph.accidentalQuarterToneFlatStein
          : Glyph.accidentalQuarterToneFlatNaturalArrowDown,
    0 => Glyph.accidentalNatural,
    1 =>
      stein
          ? Glyph.accidentalQuarterToneSharpStein
          : Glyph.accidentalQuarterToneSharpNaturalArrowUp,
    2 => Glyph.accidentalSharp,
    3 =>
      stein
          ? Glyph.accidentalThreeQuarterTonesSharpStein
          : Glyph.accidentalThreeQuarterTonesSharpArrowUp,
    4 => Glyph.accidentalDoubleSharp,
    _ => throw ArgumentError.value(alter, 'alter', 'outside two sharps'),
  };
}

/// The glyph of a dynamic level. Each level is one glyph of the font, `fp`
/// and `sfz` included.
Glyph dynamicGlyph(Dynamic level) => switch (level) {
  Dynamic.pppp => Glyph.dynamicPPPP,
  Dynamic.ppp => Glyph.dynamicPPP,
  Dynamic.pp => Glyph.dynamicPP,
  Dynamic.p => Glyph.dynamicPiano,
  Dynamic.mp => Glyph.dynamicMP,
  Dynamic.mf => Glyph.dynamicMF,
  Dynamic.f => Glyph.dynamicForte,
  Dynamic.ff => Glyph.dynamicFF,
  Dynamic.fff => Glyph.dynamicFFF,
  Dynamic.ffff => Glyph.dynamicFFFF,
  Dynamic.sf => Glyph.dynamicSforzando1,
  Dynamic.sfz => Glyph.dynamicSforzato,
  Dynamic.fp => Glyph.dynamicFortePiano,
  Dynamic.rfz => Glyph.dynamicRinforzando2,
};

/// The up-bow or down-bow mark.
Glyph bowingGlyph(Bowing bowing) => switch (bowing) {
  Bowing.up => Glyph.stringsUpBow,
  Bowing.down => Glyph.stringsDownBow,
};

/// The digits of [finger], left to right, as a fingering prints them. 0 is
/// an open string. A negative number, which no `PitchedNote.fingering`
/// holds, is refused by an assert.
List<Glyph> fingeringGlyphs(int finger) {
  assert(finger >= 0, 'a finger number is not negative');
  return [for (final unit in '$finger'.codeUnits) _fingerings[unit - 0x30]];
}

const List<Glyph> _fingerings = [
  Glyph.fingering0,
  Glyph.fingering1,
  Glyph.fingering2,
  Glyph.fingering3,
  Glyph.fingering4,
  Glyph.fingering5,
  Glyph.fingering6,
  Glyph.fingering7,
  Glyph.fingering8,
  Glyph.fingering9,
];
