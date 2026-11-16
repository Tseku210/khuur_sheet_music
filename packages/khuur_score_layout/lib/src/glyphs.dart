/// The glyph vocabulary and the shape of a font's metrics. The generator
/// imports this file and nothing generated, so it can run before its own
/// output exists.
library;

import 'geometry.dart';

/// A SMuFL glyph the engine draws, named as SMuFL names it.
///
/// The 226 values are the 224 glyphs the score model can need, plus the two
/// Gould arrow accidentals E272 and E273 that complete the quarter-tone family
/// of `QuarterToneGlyphs`. Each is one private-use codepoint in the cmap of the
/// unmodified Bravura OTF. None is a ligature or a stylistic alternate, so the
/// painter draws every glyph as a one-character string and needs no font
/// feature.
///
/// `tool/generate_bravura.dart` fails when a name here has no box or no
/// advance in the metadata, so the enum and the table cannot drift apart.
enum Glyph {
  // Clefs
  /// Treble clef (G clef).
  gClef(0xE050),

  /// Treble clef with an 8 below, sounding an octave lower.
  gClef8vb(0xE052),

  /// Treble clef with an 8 above, sounding an octave higher.
  gClef8va(0xE053),

  /// C clef, the alto or tenor clef by the line it sits on.
  cClef(0xE05C),

  /// Bass clef (F clef).
  fClef(0xE062),

  /// Bass clef with an 8 below, sounding an octave lower.
  fClef8vb(0xE064),

  /// Percussion clef for unpitched instruments.
  unpitchedPercussionClef1(0xE069),

  /// Smaller treble clef for a clef change within a staff.
  gClefChange(0xE07A),

  /// Smaller C clef for a clef change within a staff.
  cClefChange(0xE07B),

  /// Smaller bass clef for a clef change within a staff.
  fClefChange(0xE07C),

  // Accidentals
  /// Flat accidental.
  accidentalFlat(0xE260),

  /// Natural accidental.
  accidentalNatural(0xE261),

  /// Sharp accidental.
  accidentalSharp(0xE262),

  /// Double sharp accidental.
  accidentalDoubleSharp(0xE263),

  /// Double flat accidental.
  accidentalDoubleFlat(0xE264),

  /// Left parenthesis around a cautionary accidental.
  accidentalParensLeft(0xE26A),

  /// Right parenthesis around a cautionary accidental.
  accidentalParensRight(0xE26B),

  /// Quarter-tone flat, a reversed flat (Stein).
  accidentalQuarterToneFlatStein(0xE280),

  /// Three-quarter-tones flat, a reversed flat and a flat (Zimmermann).
  accidentalThreeQuarterTonesFlatZimmermann(0xE281),

  /// Quarter-tone sharp, a half sharp (Stein).
  accidentalQuarterToneSharpStein(0xE282),

  /// Three-quarter-tones sharp, one and a half sharps (Stein).
  accidentalThreeQuarterTonesSharpStein(0xE283),

  /// Three-quarter-tones flat, a narrow reversed flat and a flat.
  accidentalNarrowReversedFlatAndFlat(0xE285),

  /// Quarter-tone flat, a flat with an up arrow (Gould).
  accidentalQuarterToneFlatArrowUp(0xE270),

  /// Three-quarter-tones flat, a flat with a down arrow (Gould).
  accidentalThreeQuarterTonesFlatArrowDown(0xE271),

  /// Quarter-tone sharp, a natural with an up arrow (Gould).
  accidentalQuarterToneSharpNaturalArrowUp(0xE272),

  /// Quarter-tone flat, a natural with a down arrow (Gould).
  accidentalQuarterToneFlatNaturalArrowDown(0xE273),

  /// Three-quarter-tones sharp, a sharp with an up arrow (Gould).
  accidentalThreeQuarterTonesSharpArrowUp(0xE274),

  /// Quarter-tone sharp, a sharp with a down arrow (Gould).
  accidentalQuarterToneSharpArrowDown(0xE275),

  // Noteheads
  /// Double whole (breve) notehead.
  noteheadDoubleWhole(0xE0A0),

  /// Square double whole (breve) notehead.
  noteheadDoubleWholeSquare(0xE0A1),

  /// Whole (semibreve) notehead.
  noteheadWhole(0xE0A2),

  /// Half (minim) notehead.
  noteheadHalf(0xE0A3),

  /// Black notehead, for a quarter note or shorter.
  noteheadBlack(0xE0A4),

  /// X notehead for a double whole note.
  noteheadXDoubleWhole(0xE0A6),

  /// X notehead for a whole note.
  noteheadXWhole(0xE0A7),

  /// X notehead for a half note.
  noteheadXHalf(0xE0A8),

  /// X notehead for a quarter note or shorter.
  noteheadXBlack(0xE0A9),

  /// Circled X notehead for a double whole note.
  noteheadCircleXDoubleWhole(0xE0B0),

  /// Circled X notehead for a whole note.
  noteheadCircleXWhole(0xE0B1),

  /// Circled X notehead for a half note.
  noteheadCircleXHalf(0xE0B2),

  /// Circled X notehead for a quarter note or shorter.
  noteheadCircleX(0xE0B3),

  /// Upward triangle notehead for a double whole note.
  noteheadTriangleUpDoubleWhole(0xE0BA),

  /// Upward triangle notehead for a whole note.
  noteheadTriangleUpWhole(0xE0BB),

  /// Upward triangle notehead for a half note.
  noteheadTriangleUpHalf(0xE0BC),

  /// Black upward triangle notehead, for a quarter note or shorter.
  noteheadTriangleUpBlack(0xE0BE),

  /// Diamond notehead for a double whole note.
  noteheadDiamondDoubleWhole(0xE0D7),

  /// Diamond notehead for a whole note.
  noteheadDiamondWhole(0xE0D8),

  /// Diamond notehead for a half note.
  noteheadDiamondHalf(0xE0D9),

  /// Black diamond notehead, for a quarter note or shorter.
  noteheadDiamondBlack(0xE0DB),

  /// White diamond notehead.
  noteheadDiamondWhite(0xE0DD),

  /// White slash notehead for a double whole note.
  noteheadSlashWhiteDoubleWhole(0xE10A),

  /// White slash notehead for a whole note.
  noteheadSlashWhiteWhole(0xE102),

  /// White slash notehead for a half note.
  noteheadSlashWhiteHalf(0xE103),

  /// Black slash notehead with horizontal ends, for a quarter note or shorter.
  noteheadSlashHorizontalEnds(0xE101),

  // Dots, stems, tremolos, flags, grace slashes
  /// Augmentation dot after a note or rest.
  augmentationDot(0xE1E7),

  /// Note stem.
  stem(0xE210),

  /// Tremolo with one stroke across the stem.
  tremolo1(0xE220),

  /// Tremolo with two strokes across the stem.
  tremolo2(0xE221),

  /// Tremolo with three strokes across the stem.
  tremolo3(0xE222),

  /// Tremolo with four strokes across the stem.
  tremolo4(0xE223),

  /// Eighth-note flag on an up stem.
  flag8thUp(0xE240),

  /// Eighth-note flag on a down stem.
  flag8thDown(0xE241),

  /// 16th-note flag on an up stem.
  flag16thUp(0xE242),

  /// 16th-note flag on a down stem.
  flag16thDown(0xE243),

  /// 32nd-note flag on an up stem.
  flag32ndUp(0xE244),

  /// 32nd-note flag on a down stem.
  flag32ndDown(0xE245),

  /// 64th-note flag on an up stem.
  flag64thUp(0xE246),

  /// 64th-note flag on a down stem.
  flag64thDown(0xE247),

  /// 128th-note flag on an up stem.
  flag128thUp(0xE248),

  /// 128th-note flag on a down stem.
  flag128thDown(0xE249),

  /// Slash across the stem of an up-stem grace note.
  graceNoteSlashStemUp(0xE564),

  /// Slash across the stem of a down-stem grace note.
  graceNoteSlashStemDown(0xE565),

  /// Acciaccatura, a small eighth note with a slashed up stem.
  graceNoteAcciaccaturaStemUp(0xE560),

  /// Acciaccatura, a small eighth note with a slashed down stem.
  graceNoteAcciaccaturaStemDown(0xE561),

  // Rests
  /// Double whole (breve) rest.
  restDoubleWhole(0xE4E2),

  /// Whole (semibreve) rest.
  restWhole(0xE4E3),

  /// Half (minim) rest.
  restHalf(0xE4E4),

  /// Quarter (crotchet) rest.
  restQuarter(0xE4E5),

  /// Eighth (quaver) rest.
  rest8th(0xE4E6),

  /// 16th (semiquaver) rest.
  rest16th(0xE4E7),

  /// 32nd (demisemiquaver) rest.
  rest32nd(0xE4E8),

  /// 64th (hemidemisemiquaver) rest.
  rest64th(0xE4E9),

  /// 128th (semihemidemisemiquaver) rest.
  rest128th(0xE4EA),

  /// Multiple measure rest, drawn as one H-bar.
  restHBar(0xE4EE),

  /// Left end of a multiple measure rest H-bar.
  restHBarLeft(0xE4EF),

  /// Middle segment of a multiple measure rest H-bar.
  restHBarMiddle(0xE4F0),

  /// Right end of a multiple measure rest H-bar.
  restHBarRight(0xE4F1),

  /// Double whole (breve) rest with leger lines, for a rest outside the staff.
  restDoubleWholeLegerLine(0xE4F3),

  /// Whole rest with a leger line, for a rest outside the staff.
  restWholeLegerLine(0xE4F4),

  /// Half rest with a leger line, for a rest outside the staff.
  restHalfLegerLine(0xE4F5),

  // Time signatures
  /// Time signature digit 0.
  timeSig0(0xE080),

  /// Time signature digit 1.
  timeSig1(0xE081),

  /// Time signature digit 2.
  timeSig2(0xE082),

  /// Time signature digit 3.
  timeSig3(0xE083),

  /// Time signature digit 4.
  timeSig4(0xE084),

  /// Time signature digit 5.
  timeSig5(0xE085),

  /// Time signature digit 6.
  timeSig6(0xE086),

  /// Time signature digit 7.
  timeSig7(0xE087),

  /// Time signature digit 8.
  timeSig8(0xE088),

  /// Time signature digit 9.
  timeSig9(0xE089),

  /// Common time, a C.
  timeSigCommon(0xE08A),

  /// Cut time, a C with a vertical stroke.
  timeSigCutCommon(0xE08B),

  /// Plus sign between the parts of an additive time signature.
  timeSigPlus(0xE08C),

  /// Smaller plus sign between the parts of an additive numerator.
  timeSigPlusSmall(0xE08D),

  // Tuplets
  /// Tuplet number digit 0.
  tuplet0(0xE880),

  /// Tuplet number digit 1.
  tuplet1(0xE881),

  /// Tuplet number digit 2.
  tuplet2(0xE882),

  /// Tuplet number digit 3.
  tuplet3(0xE883),

  /// Tuplet number digit 4.
  tuplet4(0xE884),

  /// Tuplet number digit 5.
  tuplet5(0xE885),

  /// Tuplet number digit 6.
  tuplet6(0xE886),

  /// Tuplet number digit 7.
  tuplet7(0xE887),

  /// Tuplet number digit 8.
  tuplet8(0xE888),

  /// Tuplet number digit 9.
  tuplet9(0xE889),

  /// Colon in a tuplet ratio such as 3:2.
  tupletColon(0xE88A),

  // Dynamics
  /// Dynamic letter p (piano).
  dynamicPiano(0xE520),

  /// Dynamic letter m (mezzo).
  dynamicMezzo(0xE521),

  /// Dynamic letter f (forte).
  dynamicForte(0xE522),

  /// Dynamic letter r (rinforzando).
  dynamicRinforzando(0xE523),

  /// Dynamic letter s (sforzando).
  dynamicSforzando(0xE524),

  /// Dynamic letter z.
  dynamicZ(0xE525),

  /// Dynamic pppp.
  dynamicPPPP(0xE529),

  /// Dynamic ppp.
  dynamicPPP(0xE52A),

  /// Dynamic pp (pianissimo).
  dynamicPP(0xE52B),

  /// Dynamic mp (mezzo piano).
  dynamicMP(0xE52C),

  /// Dynamic mf (mezzo forte).
  dynamicMF(0xE52D),

  /// Dynamic ff (fortissimo).
  dynamicFF(0xE52F),

  /// Dynamic fff.
  dynamicFFF(0xE530),

  /// Dynamic ffff.
  dynamicFFFF(0xE531),

  /// Dynamic fp (forte-piano), loud then at once soft.
  dynamicFortePiano(0xE534),

  /// Dynamic sf (sforzando).
  dynamicSforzando1(0xE536),

  /// Dynamic sfz (sforzato).
  dynamicSforzato(0xE539),

  /// Dynamic rfz (rinforzando).
  dynamicRinforzando2(0xE53D),

  // Articulations
  /// Accent above the note.
  articAccentAbove(0xE4A0),

  /// Accent below the note.
  articAccentBelow(0xE4A1),

  /// Staccato dot above the note.
  articStaccatoAbove(0xE4A2),

  /// Staccato dot below the note.
  articStaccatoBelow(0xE4A3),

  /// Tenuto line above the note.
  articTenutoAbove(0xE4A4),

  /// Tenuto line below the note.
  articTenutoBelow(0xE4A5),

  /// Staccatissimo wedge above the note.
  articStaccatissimoAbove(0xE4A6),

  /// Staccatissimo wedge below the note.
  articStaccatissimoBelow(0xE4A7),

  /// Marcato above the note.
  articMarcatoAbove(0xE4AC),

  /// Marcato below the note.
  articMarcatoBelow(0xE4AD),

  /// Fermata above the note.
  fermataAbove(0xE4C0),

  /// Fermata below the note.
  fermataBelow(0xE4C1),

  /// Harmonic, a small circle over the note.
  stringsHarmonic(0xE614),

  // Ornaments and wiggles
  /// Trill sign (tr).
  ornamentTrill(0xE566),

  /// Turn.
  ornamentTurn(0xE567),

  /// Inverted turn.
  ornamentTurnInverted(0xE568),

  /// Short trill, also read as an inverted mordent.
  ornamentShortTrill(0xE56C),

  /// Mordent.
  ornamentMordent(0xE56D),

  /// One segment of the wavy line after a trill sign.
  wiggleTrill(0xEAA4),

  /// One segment of a wavy glissando line.
  wiggleGlissando(0xEAAF),

  // String marks
  /// Down-bow mark.
  stringsDownBow(0xE610),

  /// Up-bow mark.
  stringsUpBow(0xE612),

  /// Fingering digit 0, also an open string.
  fingering0(0xED10),

  /// Fingering digit 1.
  fingering1(0xED11),

  /// Fingering digit 2.
  fingering2(0xED12),

  /// Fingering digit 3.
  fingering3(0xED13),

  /// Fingering digit 4.
  fingering4(0xED14),

  /// Fingering digit 5.
  fingering5(0xED15),

  /// Fingering digit 6.
  fingering6(0xED24),

  /// Fingering digit 7.
  fingering7(0xED25),

  /// Fingering digit 8.
  fingering8(0xED26),

  /// Fingering digit 9.
  fingering9(0xED27),

  /// Circled string number 0.
  guitarString0(0xE833),

  /// Circled string number 1.
  guitarString1(0xE834),

  /// Circled string number 2.
  guitarString2(0xE835),

  /// Circled string number 3.
  guitarString3(0xE836),

  /// Circled string number 4.
  guitarString4(0xE837),

  /// Circled string number 5.
  guitarString5(0xE838),

  /// Circled string number 6.
  guitarString6(0xE839),

  /// Circled string number 7.
  guitarString7(0xE83A),

  /// Circled string number 8.
  guitarString8(0xE83B),

  /// Circled string number 9.
  guitarString9(0xE83C),

  // Pedal
  /// Sustain pedal mark (Ped.).
  keyboardPedalPed(0xE650),

  /// Pedal release mark, an asterisk.
  keyboardPedalUp(0xE655),

  /// Notch in a pedal line where the pedal lifts and goes down again.
  keyboardPedalUpNotch(0xE657),

  // Octave lines
  /// Octave sign 8, an octave up or down by its placement.
  ottava(0xE510),

  /// Octave sign 8va, an octave higher.
  ottavaAlta(0xE511),

  /// Octave sign 8va for use below the staff, an octave lower.
  ottavaBassa(0xE512),

  /// Octave sign 8ba, an octave lower.
  ottavaBassaBa(0xE513),

  /// Octave sign 15, two octaves up or down by its placement.
  quindicesima(0xE514),

  /// Octave sign 15ma, two octaves higher.
  quindicesimaAlta(0xE515),

  /// Octave sign 15ma for use below the staff, two octaves lower.
  quindicesimaBassa(0xE516),

  /// Octave sign 22, three octaves up or down by its placement.
  ventiduesima(0xE517),

  /// Octave sign 22ma, three octaves higher.
  ventiduesimaAlta(0xE518),

  /// Octave sign 22ma for use below the staff, three octaves lower.
  ventiduesimaBassa(0xE519),

  /// Left parenthesis around an octave sign repeated after a line break.
  octaveParensLeft(0xE51A),

  /// Right parenthesis around an octave sign repeated after a line break.
  octaveParensRight(0xE51B),

  /// Octave sign 8vb, an octave lower.
  ottavaBassaVb(0xE51C),

  /// Octave sign 15mb, two octaves lower.
  quindicesimaBassaMb(0xE51D),

  /// Octave sign 22mb, three octaves lower.
  ventiduesimaBassaMb(0xE51E),

  // Repeats and navigation
  /// Start repeat sign, a heavy and a thin barline with dots.
  repeatLeft(0xE040),

  /// End repeat sign, dots with a thin and a heavy barline.
  repeatRight(0xE041),

  /// End and start repeat signs back to back.
  repeatRightLeft(0xE042),

  /// Pair of repeat dots.
  repeatDots(0xE043),

  /// Single repeat dot.
  repeatDot(0xE044),

  /// Dal segno sign (D.S.).
  dalSegno(0xE045),

  /// Da capo sign (D.C.).
  daCapo(0xE046),

  /// Segno sign.
  segno(0xE047),

  /// Coda sign.
  coda(0xE048),

  /// Square coda sign.
  codaSquare(0xE049),

  // Barlines
  /// Single barline.
  barlineSingle(0xE030),

  /// Double barline, two thin lines.
  barlineDouble(0xE031),

  /// Final barline, a thin and a heavy line.
  barlineFinal(0xE032),

  /// Heavy barline.
  barlineHeavy(0xE034),

  /// Dashed barline.
  barlineDashed(0xE036),

  /// Dotted barline.
  barlineDotted(0xE037),

  // Systems
  /// Brace joining the staves of one instrument, such as a piano.
  brace(0xE000),

  /// Bracket joining a group of staves.
  bracket(0xE002),

  /// Top hook of a bracket.
  bracketTop(0xE003),

  /// Bottom hook of a bracket.
  bracketBottom(0xE004),

  /// Leger line for a note above or below the staff.
  legerLine(0xE022),

  // Metronome marks
  /// Double whole (breve) note for a metronome mark.
  metNoteDoubleWhole(0xECA0),

  /// Whole note for a metronome mark.
  metNoteWhole(0xECA2),

  /// Half note with an up stem for a metronome mark.
  metNoteHalfUp(0xECA3),

  /// Quarter note with an up stem for a metronome mark.
  metNoteQuarterUp(0xECA5),

  /// Eighth note with an up stem for a metronome mark.
  metNote8thUp(0xECA7),

  /// 16th note with an up stem for a metronome mark.
  metNote16thUp(0xECA9),

  /// 32nd note with an up stem for a metronome mark.
  metNote32ndUp(0xECAB),

  /// 64th note with an up stem for a metronome mark.
  metNote64thUp(0xECAD),

  /// 128th note with an up stem for a metronome mark.
  metNote128thUp(0xECAF),

  /// Augmentation dot after a metronome mark note.
  metAugmentationDot(0xECB7),

  // Chord symbols
  /// Flat sign in a chord symbol.
  csymAccidentalFlat(0xED60),

  /// Sharp sign in a chord symbol.
  csymAccidentalSharp(0xED62);

  Glyph(this.codepoint);

  /// The codepoint in the SMuFL private-use range. The painter draws
  /// `String.fromCharCode(codepoint)` in the music font.
  final int codepoint;
}

/// The SMuFL anchors Bravura 1.392 puts on the glyphs in [Glyph].
///
/// Stems attach at `stemUpSE` and `stemDownNW` of a notehead, flags at
/// `stemUpNW` and `stemDownSW`. The acciaccatura slash uses the flag's
/// `graceNoteSlash*` points, and `opticalCenter` centres a dynamic on its
/// slice. The generator fails on an anchor name missing here, so this list
/// is exactly what a table can hold.
enum GlyphAnchor {
  /// On a notehead, where the bottom right corner of an up stem starts.
  stemUpSE,

  /// On a notehead, where the top left corner of a down stem starts.
  stemDownNW,

  /// On a flag, where the top left corner of its up stem ends.
  stemUpNW,

  /// On a flag, where the bottom left corner of its down stem ends.
  stemDownSW,

  /// Bottom right corner of an angled up stem that joins this notehead to a
  /// vertical stem.
  splitStemUpSE,

  /// Bottom left corner of an angled up stem that joins this notehead to a
  /// vertical stem.
  splitStemUpSW,

  /// Top right corner of an angled down stem that joins this notehead to a
  /// vertical stem.
  splitStemDownNE,

  /// Top left corner of an angled down stem that joins this notehead to a
  /// vertical stem.
  splitStemDownNW,

  /// Inner corner of the empty area at the top right of the box.
  cutOutNE,

  /// Inner corner of the empty area at the top left of the box.
  cutOutNW,

  /// Inner corner of the empty area at the bottom right of the box.
  cutOutSE,

  /// Inner corner of the empty area at the bottom left of the box.
  cutOutSW,

  /// On an up-stem flag, the lower left end of a grace slash.
  graceNoteSlashSW,

  /// On an up-stem flag, the upper right end of a grace slash.
  graceNoteSlashNE,

  /// On a down-stem flag, the upper left end of a grace slash.
  graceNoteSlashNW,

  /// On a down-stem flag, the lower right end of a grace slash.
  graceNoteSlashSE,

  /// The point the eye reads as the glyph's centre.
  opticalCenter,

  /// Left edge of a notehead whose ink starts right of the origin.
  noteheadOrigin,

  /// Where the next copy of a repeating line segment starts.
  repeatOffset,
}

/// One glyph's metrics in staff spaces, y down, relative to the glyph
/// origin on the baseline. SMuFL metadata is y up. The generator and
/// `SmuflFont.fromMetadata` flip it once, so nothing downstream negates y.
final class GlyphMetrics {
  /// Metrics for one glyph. [anchors] defaults to none.
  const GlyphMetrics({
    required this.box,
    required this.advance,
    this.anchors = const {},
  });

  /// The ink's bounding box.
  final Box box;

  /// How far the next glyph's origin sits right of this one's.
  final double advance;

  /// The anchors the font gives this glyph. Most glyphs have none.
  final Map<GlyphAnchor, SpPoint> anchors;
}

/// The 28 numeric SMuFL `engravingDefaults`, in staff spaces. Every line
/// the engine draws takes its thickness from here.
///
/// The generator and `SmuflFont.fromMetadata` fail when the metadata's
/// numeric defaults and these fields differ in either direction.
///
/// Two are equal when every default is, so an app may make its own in
/// `build` without a new layout each time.
///
/// Every default is a length. One under zero, or one that is no finite
/// number, is refused by an assert.
final class EngravingDefaults {
  /// Defaults with every value given. An assert refuses a negative or
  /// non-finite one.
  const EngravingDefaults({
    required this.arrowShaftThickness,
    required this.barlineSeparation,
    required this.beamSpacing,
    required this.beamThickness,
    required this.bracketThickness,
    required this.dashedBarlineDashLength,
    required this.dashedBarlineGapLength,
    required this.dashedBarlineThickness,
    required this.hBarThickness,
    required this.hairpinThickness,
    required this.legerLineExtension,
    required this.legerLineThickness,
    required this.lyricLineThickness,
    required this.octaveLineThickness,
    required this.pedalLineThickness,
    required this.repeatBarlineDotSeparation,
    required this.repeatEndingLineThickness,
    required this.slurEndpointThickness,
    required this.slurMidpointThickness,
    required this.staffLineThickness,
    required this.stemThickness,
    required this.subBracketThickness,
    required this.textEnclosureThickness,
    required this.thickBarlineThickness,
    required this.thinBarlineThickness,
    required this.tieEndpointThickness,
    required this.tieMidpointThickness,
    required this.tupletBracketThickness,
  }) : assert(
         arrowShaftThickness >= 0 && arrowShaftThickness < double.infinity,
       ),
       assert(barlineSeparation >= 0 && barlineSeparation < double.infinity),
       assert(beamSpacing >= 0 && beamSpacing < double.infinity),
       assert(beamThickness >= 0 && beamThickness < double.infinity),
       assert(bracketThickness >= 0 && bracketThickness < double.infinity),
       assert(
         dashedBarlineDashLength >= 0 &&
             dashedBarlineDashLength < double.infinity,
       ),
       assert(
         dashedBarlineGapLength >= 0 &&
             dashedBarlineGapLength < double.infinity,
       ),
       assert(
         dashedBarlineThickness >= 0 &&
             dashedBarlineThickness < double.infinity,
       ),
       assert(hBarThickness >= 0 && hBarThickness < double.infinity),
       assert(hairpinThickness >= 0 && hairpinThickness < double.infinity),
       assert(legerLineExtension >= 0 && legerLineExtension < double.infinity),
       assert(legerLineThickness >= 0 && legerLineThickness < double.infinity),
       assert(lyricLineThickness >= 0 && lyricLineThickness < double.infinity),
       assert(
         octaveLineThickness >= 0 && octaveLineThickness < double.infinity,
       ),
       assert(pedalLineThickness >= 0 && pedalLineThickness < double.infinity),
       assert(
         repeatBarlineDotSeparation >= 0 &&
             repeatBarlineDotSeparation < double.infinity,
       ),
       assert(
         repeatEndingLineThickness >= 0 &&
             repeatEndingLineThickness < double.infinity,
       ),
       assert(
         slurEndpointThickness >= 0 && slurEndpointThickness < double.infinity,
       ),
       assert(
         slurMidpointThickness >= 0 && slurMidpointThickness < double.infinity,
       ),
       assert(staffLineThickness >= 0 && staffLineThickness < double.infinity),
       assert(stemThickness >= 0 && stemThickness < double.infinity),
       assert(
         subBracketThickness >= 0 && subBracketThickness < double.infinity,
       ),
       assert(
         textEnclosureThickness >= 0 &&
             textEnclosureThickness < double.infinity,
       ),
       assert(
         thickBarlineThickness >= 0 && thickBarlineThickness < double.infinity,
       ),
       assert(
         thinBarlineThickness >= 0 && thinBarlineThickness < double.infinity,
       ),
       assert(
         tieEndpointThickness >= 0 && tieEndpointThickness < double.infinity,
       ),
       assert(
         tieMidpointThickness >= 0 && tieMidpointThickness < double.infinity,
       ),
       assert(
         tupletBracketThickness >= 0 &&
             tupletBracketThickness < double.infinity,
       );

  /// The defaults whose values [valueOf] gives by SMuFL name.
  ///
  /// This is the one place a name is tied to its field. Reading with a
  /// function that records its argument lists the names
  /// ([engravingDefaultNames]), so no second list can drift from it.
  factory EngravingDefaults.read(double Function(String name) valueOf) =>
      EngravingDefaults(
        arrowShaftThickness: valueOf('arrowShaftThickness'),
        barlineSeparation: valueOf('barlineSeparation'),
        beamSpacing: valueOf('beamSpacing'),
        beamThickness: valueOf('beamThickness'),
        bracketThickness: valueOf('bracketThickness'),
        dashedBarlineDashLength: valueOf('dashedBarlineDashLength'),
        dashedBarlineGapLength: valueOf('dashedBarlineGapLength'),
        dashedBarlineThickness: valueOf('dashedBarlineThickness'),
        hBarThickness: valueOf('hBarThickness'),
        hairpinThickness: valueOf('hairpinThickness'),
        legerLineExtension: valueOf('legerLineExtension'),
        legerLineThickness: valueOf('legerLineThickness'),
        lyricLineThickness: valueOf('lyricLineThickness'),
        octaveLineThickness: valueOf('octaveLineThickness'),
        pedalLineThickness: valueOf('pedalLineThickness'),
        repeatBarlineDotSeparation: valueOf('repeatBarlineDotSeparation'),
        repeatEndingLineThickness: valueOf('repeatEndingLineThickness'),
        slurEndpointThickness: valueOf('slurEndpointThickness'),
        slurMidpointThickness: valueOf('slurMidpointThickness'),
        staffLineThickness: valueOf('staffLineThickness'),
        stemThickness: valueOf('stemThickness'),
        subBracketThickness: valueOf('subBracketThickness'),
        textEnclosureThickness: valueOf('textEnclosureThickness'),
        thickBarlineThickness: valueOf('thickBarlineThickness'),
        thinBarlineThickness: valueOf('thinBarlineThickness'),
        tieEndpointThickness: valueOf('tieEndpointThickness'),
        tieMidpointThickness: valueOf('tieMidpointThickness'),
        tupletBracketThickness: valueOf('tupletBracketThickness'),
      );

  /// Thickness of an arrow's shaft.
  final double arrowShaftThickness;

  /// Gap between the lines of a double or final barline.
  final double barlineSeparation;

  /// Gap between one beam and the next.
  final double beamSpacing;

  /// Thickness of a beam.
  final double beamThickness;

  /// Thickness of the vertical line of a staff bracket.
  final double bracketThickness;

  /// Length of one dash of a dashed barline.
  final double dashedBarlineDashLength;

  /// Gap between the dashes of a dashed barline.
  final double dashedBarlineGapLength;

  /// Thickness of a dashed barline.
  final double dashedBarlineThickness;

  /// Thickness of the crossbar of a multiple measure rest.
  final double hBarThickness;

  /// Thickness of a crescendo or diminuendo hairpin.
  final double hairpinThickness;

  /// How far a leger line reaches past each side of a notehead.
  final double legerLineExtension;

  /// Thickness of a leger line.
  final double legerLineThickness;

  /// Thickness of a lyric extender line.
  final double lyricLineThickness;

  /// Thickness of an octave line.
  final double octaveLineThickness;

  /// Thickness of a pedal line.
  final double pedalLineThickness;

  /// Gap between the dots of a repeat sign and the line next to them.
  final double repeatBarlineDotSeparation;

  /// Thickness of a repeat ending bracket.
  final double repeatEndingLineThickness;

  /// Thickness of a slur at its ends.
  final double slurEndpointThickness;

  /// Thickness of a slur at its middle.
  final double slurMidpointThickness;

  /// Thickness of a staff line.
  final double staffLineThickness;

  /// Thickness of a stem.
  final double stemThickness;

  /// Thickness of the vertical line of a sub-bracket inside a bracket.
  final double subBracketThickness;

  /// Thickness of the box around enclosed text, such as a rehearsal mark.
  final double textEnclosureThickness;

  /// Thickness of a heavy barline.
  final double thickBarlineThickness;

  /// Thickness of a thin barline.
  final double thinBarlineThickness;

  /// Thickness of a tie at its ends.
  final double tieEndpointThickness;

  /// Thickness of a tie at its middle.
  final double tieMidpointThickness;

  /// Thickness of a tuplet bracket.
  final double tupletBracketThickness;

  /// These defaults with the given ones replaced, for an app that wants
  /// other lines than the font's. A font takes them in `SmuflFont.copyWith`.
  EngravingDefaults copyWith({
    double? arrowShaftThickness,
    double? barlineSeparation,
    double? beamSpacing,
    double? beamThickness,
    double? bracketThickness,
    double? dashedBarlineDashLength,
    double? dashedBarlineGapLength,
    double? dashedBarlineThickness,
    double? hBarThickness,
    double? hairpinThickness,
    double? legerLineExtension,
    double? legerLineThickness,
    double? lyricLineThickness,
    double? octaveLineThickness,
    double? pedalLineThickness,
    double? repeatBarlineDotSeparation,
    double? repeatEndingLineThickness,
    double? slurEndpointThickness,
    double? slurMidpointThickness,
    double? staffLineThickness,
    double? stemThickness,
    double? subBracketThickness,
    double? textEnclosureThickness,
    double? thickBarlineThickness,
    double? thinBarlineThickness,
    double? tieEndpointThickness,
    double? tieMidpointThickness,
    double? tupletBracketThickness,
  }) => EngravingDefaults(
    arrowShaftThickness: arrowShaftThickness ?? this.arrowShaftThickness,
    barlineSeparation: barlineSeparation ?? this.barlineSeparation,
    beamSpacing: beamSpacing ?? this.beamSpacing,
    beamThickness: beamThickness ?? this.beamThickness,
    bracketThickness: bracketThickness ?? this.bracketThickness,
    dashedBarlineDashLength:
        dashedBarlineDashLength ?? this.dashedBarlineDashLength,
    dashedBarlineGapLength:
        dashedBarlineGapLength ?? this.dashedBarlineGapLength,
    dashedBarlineThickness:
        dashedBarlineThickness ?? this.dashedBarlineThickness,
    hBarThickness: hBarThickness ?? this.hBarThickness,
    hairpinThickness: hairpinThickness ?? this.hairpinThickness,
    legerLineExtension: legerLineExtension ?? this.legerLineExtension,
    legerLineThickness: legerLineThickness ?? this.legerLineThickness,
    lyricLineThickness: lyricLineThickness ?? this.lyricLineThickness,
    octaveLineThickness: octaveLineThickness ?? this.octaveLineThickness,
    pedalLineThickness: pedalLineThickness ?? this.pedalLineThickness,
    repeatBarlineDotSeparation:
        repeatBarlineDotSeparation ?? this.repeatBarlineDotSeparation,
    repeatEndingLineThickness:
        repeatEndingLineThickness ?? this.repeatEndingLineThickness,
    slurEndpointThickness: slurEndpointThickness ?? this.slurEndpointThickness,
    slurMidpointThickness: slurMidpointThickness ?? this.slurMidpointThickness,
    staffLineThickness: staffLineThickness ?? this.staffLineThickness,
    stemThickness: stemThickness ?? this.stemThickness,
    subBracketThickness: subBracketThickness ?? this.subBracketThickness,
    textEnclosureThickness:
        textEnclosureThickness ?? this.textEnclosureThickness,
    thickBarlineThickness: thickBarlineThickness ?? this.thickBarlineThickness,
    thinBarlineThickness: thinBarlineThickness ?? this.thinBarlineThickness,
    tieEndpointThickness: tieEndpointThickness ?? this.tieEndpointThickness,
    tieMidpointThickness: tieMidpointThickness ?? this.tieMidpointThickness,
    tupletBracketThickness:
        tupletBracketThickness ?? this.tupletBracketThickness,
  );

  List<double> get _values => [
    arrowShaftThickness,
    barlineSeparation,
    beamSpacing,
    beamThickness,
    bracketThickness,
    dashedBarlineDashLength,
    dashedBarlineGapLength,
    dashedBarlineThickness,
    hBarThickness,
    hairpinThickness,
    legerLineExtension,
    legerLineThickness,
    lyricLineThickness,
    octaveLineThickness,
    pedalLineThickness,
    repeatBarlineDotSeparation,
    repeatEndingLineThickness,
    slurEndpointThickness,
    slurMidpointThickness,
    staffLineThickness,
    stemThickness,
    subBracketThickness,
    textEnclosureThickness,
    thickBarlineThickness,
    thinBarlineThickness,
    tieEndpointThickness,
    tieMidpointThickness,
    tupletBracketThickness,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) {
      return true;
    }
    if (other is! EngravingDefaults) {
      return false;
    }
    final theirs = other._values;
    return _values.indexed.every((value) => theirs[value.$1] == value.$2);
  }

  @override
  int get hashCode => Object.hashAll(_values);
}

/// The SMuFL names of the fields of [EngravingDefaults], in their order.
final List<String> engravingDefaultNames = () {
  final names = <String>[];
  EngravingDefaults.read((name) {
    names.add(name);
    return 0;
  });
  return List<String>.unmodifiable(names);
}();
