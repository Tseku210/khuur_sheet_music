/// The glyph vocabulary and the shape of a font's metrics. The generator
/// imports this file and nothing generated, so it can run before its own
/// output exists.
library;

import 'geometry.dart';

/// A SMuFL glyph the engine draws, named as SMuFL names it.
///
/// The 222 values are the 220 glyphs `docs/design/layout/glyphs.md` says
/// the score model can need, plus the two Gould arrow accidentals E272 and
/// E273 that complete the quarter-tone family of `QuarterToneGlyphs`. Each
/// is one private-use codepoint in the cmap of the unmodified Bravura OTF.
/// None is a ligature or a stylistic alternate, so the painter draws every
/// glyph as a one-character string and needs no font feature.
///
/// `tool/generate_bravura.dart` fails when a name here has no box or no
/// advance in the metadata, so the enum and the table cannot drift apart.
enum Glyph {
  // Clefs
  gClef(0xE050),
  gClef8vb(0xE052),
  gClef8va(0xE053),
  cClef(0xE05C),
  fClef(0xE062),
  fClef8vb(0xE064),
  unpitchedPercussionClef1(0xE069),
  gClefChange(0xE07A),
  cClefChange(0xE07B),
  fClefChange(0xE07C),

  // Accidentals
  accidentalFlat(0xE260),
  accidentalNatural(0xE261),
  accidentalSharp(0xE262),
  accidentalDoubleSharp(0xE263),
  accidentalDoubleFlat(0xE264),
  accidentalParensLeft(0xE26A),
  accidentalParensRight(0xE26B),
  accidentalQuarterToneFlatStein(0xE280),
  accidentalThreeQuarterTonesFlatZimmermann(0xE281),
  accidentalQuarterToneSharpStein(0xE282),
  accidentalThreeQuarterTonesSharpStein(0xE283),
  accidentalNarrowReversedFlatAndFlat(0xE285),
  accidentalQuarterToneFlatArrowUp(0xE270),
  accidentalThreeQuarterTonesFlatArrowDown(0xE271),
  accidentalQuarterToneSharpNaturalArrowUp(0xE272),
  accidentalQuarterToneFlatNaturalArrowDown(0xE273),
  accidentalThreeQuarterTonesSharpArrowUp(0xE274),
  accidentalQuarterToneSharpArrowDown(0xE275),

  // Noteheads
  noteheadDoubleWhole(0xE0A0),
  noteheadDoubleWholeSquare(0xE0A1),
  noteheadWhole(0xE0A2),
  noteheadHalf(0xE0A3),
  noteheadBlack(0xE0A4),
  noteheadXDoubleWhole(0xE0A6),
  noteheadXWhole(0xE0A7),
  noteheadXHalf(0xE0A8),
  noteheadXBlack(0xE0A9),
  noteheadCircleXDoubleWhole(0xE0B0),
  noteheadCircleXWhole(0xE0B1),
  noteheadCircleXHalf(0xE0B2),
  noteheadCircleX(0xE0B3),
  noteheadTriangleUpDoubleWhole(0xE0BA),
  noteheadTriangleUpWhole(0xE0BB),
  noteheadTriangleUpHalf(0xE0BC),
  noteheadTriangleUpBlack(0xE0BE),
  noteheadDiamondDoubleWhole(0xE0D7),
  noteheadDiamondWhole(0xE0D8),
  noteheadDiamondHalf(0xE0D9),
  noteheadDiamondBlack(0xE0DB),
  noteheadDiamondWhite(0xE0DD),
  noteheadSlashWhiteDoubleWhole(0xE10A),
  noteheadSlashWhiteWhole(0xE102),
  noteheadSlashWhiteHalf(0xE103),
  noteheadSlashHorizontalEnds(0xE101),

  // Dots, stems, tremolos, flags, grace slashes
  augmentationDot(0xE1E7),
  stem(0xE210),
  tremolo1(0xE220),
  tremolo2(0xE221),
  tremolo3(0xE222),
  tremolo4(0xE223),
  flag8thUp(0xE240),
  flag8thDown(0xE241),
  flag16thUp(0xE242),
  flag16thDown(0xE243),
  flag32ndUp(0xE244),
  flag32ndDown(0xE245),
  flag64thUp(0xE246),
  flag64thDown(0xE247),
  flag128thUp(0xE248),
  flag128thDown(0xE249),
  graceNoteSlashStemUp(0xE564),
  graceNoteSlashStemDown(0xE565),
  graceNoteAcciaccaturaStemUp(0xE560),
  graceNoteAcciaccaturaStemDown(0xE561),

  // Rests
  restDoubleWhole(0xE4E2),
  restWhole(0xE4E3),
  restHalf(0xE4E4),
  restQuarter(0xE4E5),
  rest8th(0xE4E6),
  rest16th(0xE4E7),
  rest32nd(0xE4E8),
  rest64th(0xE4E9),
  rest128th(0xE4EA),
  restHBar(0xE4EE),
  restHBarLeft(0xE4EF),
  restHBarMiddle(0xE4F0),
  restHBarRight(0xE4F1),
  restDoubleWholeLegerLine(0xE4F3),
  restWholeLegerLine(0xE4F4),
  restHalfLegerLine(0xE4F5),

  // Time signatures
  timeSig0(0xE080),
  timeSig1(0xE081),
  timeSig2(0xE082),
  timeSig3(0xE083),
  timeSig4(0xE084),
  timeSig5(0xE085),
  timeSig6(0xE086),
  timeSig7(0xE087),
  timeSig8(0xE088),
  timeSig9(0xE089),
  timeSigCommon(0xE08A),
  timeSigCutCommon(0xE08B),
  timeSigPlus(0xE08C),
  timeSigPlusSmall(0xE08D),

  // Tuplets
  tuplet0(0xE880),
  tuplet1(0xE881),
  tuplet2(0xE882),
  tuplet3(0xE883),
  tuplet4(0xE884),
  tuplet5(0xE885),
  tuplet6(0xE886),
  tuplet7(0xE887),
  tuplet8(0xE888),
  tuplet9(0xE889),
  tupletColon(0xE88A),

  // Dynamics
  dynamicPiano(0xE520),
  dynamicMezzo(0xE521),
  dynamicForte(0xE522),
  dynamicRinforzando(0xE523),
  dynamicSforzando(0xE524),
  dynamicZ(0xE525),
  dynamicPPPP(0xE529),
  dynamicPPP(0xE52A),
  dynamicPP(0xE52B),
  dynamicMP(0xE52C),
  dynamicMF(0xE52D),
  dynamicFF(0xE52F),
  dynamicFFF(0xE530),
  dynamicFFFF(0xE531),
  dynamicFortePiano(0xE534),
  dynamicSforzando1(0xE536),
  dynamicSforzato(0xE539),
  dynamicRinforzando2(0xE53D),

  // Articulations
  articAccentAbove(0xE4A0),
  articAccentBelow(0xE4A1),
  articStaccatoAbove(0xE4A2),
  articStaccatoBelow(0xE4A3),
  articTenutoAbove(0xE4A4),
  articTenutoBelow(0xE4A5),
  articStaccatissimoAbove(0xE4A6),
  articStaccatissimoBelow(0xE4A7),
  articMarcatoAbove(0xE4AC),
  articMarcatoBelow(0xE4AD),
  fermataAbove(0xE4C0),
  fermataBelow(0xE4C1),
  stringsHarmonic(0xE614),

  // Ornaments and wiggles
  ornamentTrill(0xE566),
  ornamentTurn(0xE567),
  ornamentTurnInverted(0xE568),
  ornamentShortTrill(0xE56C),
  ornamentMordent(0xE56D),
  wiggleTrill(0xEAA4),
  wiggleGlissando(0xEAAF),

  // String marks
  stringsDownBow(0xE610),
  stringsUpBow(0xE612),
  fingering0(0xED10),
  fingering1(0xED11),
  fingering2(0xED12),
  fingering3(0xED13),
  fingering4(0xED14),
  fingering5(0xED15),
  fingering6(0xED24),
  fingering7(0xED25),
  fingering8(0xED26),
  fingering9(0xED27),
  guitarString0(0xE833),
  guitarString1(0xE834),
  guitarString2(0xE835),
  guitarString3(0xE836),
  guitarString4(0xE837),
  guitarString5(0xE838),
  guitarString6(0xE839),
  guitarString7(0xE83A),
  guitarString8(0xE83B),
  guitarString9(0xE83C),

  // Pedal
  keyboardPedalPed(0xE650),
  keyboardPedalUp(0xE655),
  keyboardPedalUpNotch(0xE657),

  // Octave lines
  ottava(0xE510),
  ottavaAlta(0xE511),
  ottavaBassa(0xE512),
  ottavaBassaBa(0xE513),
  quindicesima(0xE514),
  quindicesimaAlta(0xE515),
  quindicesimaBassa(0xE516),
  ventiduesima(0xE517),
  ventiduesimaAlta(0xE518),
  ventiduesimaBassa(0xE519),
  octaveParensLeft(0xE51A),
  octaveParensRight(0xE51B),
  ottavaBassaVb(0xE51C),
  quindicesimaBassaMb(0xE51D),
  ventiduesimaBassaMb(0xE51E),

  // Repeats and navigation
  repeatLeft(0xE040),
  repeatRight(0xE041),
  repeatRightLeft(0xE042),
  repeatDots(0xE043),
  repeatDot(0xE044),
  dalSegno(0xE045),
  daCapo(0xE046),
  segno(0xE047),
  coda(0xE048),
  codaSquare(0xE049),

  // Barlines
  barlineSingle(0xE030),
  barlineDouble(0xE031),
  barlineFinal(0xE032),
  barlineHeavy(0xE034),
  barlineDashed(0xE036),
  barlineDotted(0xE037),

  // Systems
  brace(0xE000),
  bracket(0xE002),
  bracketTop(0xE003),
  bracketBottom(0xE004),
  legerLine(0xE022),

  // Metronome marks
  metNoteWhole(0xECA2),
  metNoteHalfUp(0xECA3),
  metNoteQuarterUp(0xECA5),
  metNote8thUp(0xECA7),
  metNote16thUp(0xECA9),
  metAugmentationDot(0xECB7),

  // Chord symbols
  csymAccidentalFlat(0xED60),
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
  stemUpSE,
  stemDownNW,
  stemUpNW,
  stemDownSW,
  splitStemUpSE,
  splitStemUpSW,
  splitStemDownNE,
  splitStemDownNW,
  cutOutNE,
  cutOutNW,
  cutOutSE,
  cutOutSW,
  graceNoteSlashSW,
  graceNoteSlashNE,
  graceNoteSlashNW,
  graceNoteSlashSE,
  opticalCenter,
  noteheadOrigin,
  repeatOffset,
}

/// One glyph's metrics in staff spaces, y down, relative to the glyph
/// origin on the baseline. SMuFL metadata is y up. The generator and
/// `SmuflFont.fromMetadata` flip it once, so nothing downstream negates y.
final class GlyphMetrics {
  const GlyphMetrics({
    required this.box,
    required this.advance,
    this.anchors = const {},
  });

  final Box box;
  final double advance;
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
final class EngravingDefaults {
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
  });

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

  final double arrowShaftThickness;
  final double barlineSeparation;
  final double beamSpacing;
  final double beamThickness;
  final double bracketThickness;
  final double dashedBarlineDashLength;
  final double dashedBarlineGapLength;
  final double dashedBarlineThickness;
  final double hBarThickness;
  final double hairpinThickness;
  final double legerLineExtension;
  final double legerLineThickness;
  final double lyricLineThickness;
  final double octaveLineThickness;
  final double pedalLineThickness;
  final double repeatBarlineDotSeparation;
  final double repeatEndingLineThickness;
  final double slurEndpointThickness;
  final double slurMidpointThickness;
  final double staffLineThickness;
  final double stemThickness;
  final double subBracketThickness;
  final double textEnclosureThickness;
  final double thickBarlineThickness;
  final double thinBarlineThickness;
  final double tieEndpointThickness;
  final double tieMidpointThickness;
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
