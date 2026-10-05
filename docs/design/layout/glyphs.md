# SMuFL glyphs for the layout engine

This table lists every SMuFL glyph the score model can need, with its codepoint, grouped by model feature. It was built for the layout engine design in [grounding.md](grounding.md).

The repo has no SMuFL name-to-codepoint table, since `glyphnames.json` is absent and the metadata gives codepoints only for optional glyphs, ligatures and alternates. Each codepoint below was verified two ways. In Bravura, `glyphAdvanceWidths[name] × 250` equals the glyph's `horiz-adv-x` exactly for all 222. In both fonts, the SVG path's extent matches `glyphBBoxes[name] × 250`, to 0.0 units for most glyphs and within 18 units (of 250 per staff space) for the rest, where curve control points lie outside the curve.

## The SVG fonts

The repository does not keep the two SVG fonts. They were assets of the old engine, `assets/Bravura.svg` and `assets/Petaluma.svg`. The rewrite deleted them with that engine, and with them `assets/petaluma_metadata.json` and the `GlyphPaths` and `Constants.staffSpace` that this section cites. Both SVG files are in the repository's history, unchanged since commit `1620e25` added them. `Bravura.svg` is the SVG build of Bravura, from the Bravura release at https://github.com/steinbergmedia/bravura. Bravura's metadata is now `packages/score_layout/tool/bravura_metadata.json`, and the package draws from `fonts/Bravura.otf`.

**Bravura.svg**
- FontForge, 2021-01-29. `units-per-em="1000"`, ascent 800, descent −200, `unicode-range` U+0020–1D1E8.
- 3693 `<glyph>` elements with unique names:
  - 3452 named `uniXXXX`
  - 231 named `uXXXXX` (Unicode Musical Symbols, U+1D100 block)
  - 9 others (`.notdef`, `space`, `CR`, `onehalf`, …) and one `uniEE20.001`.
- 225 `uniXXXX` glyphs have a `unicode` attribute that is a component sequence. These are ligatures: `uniE527` = U+E520 ×6. They are only reachable by name.
- 43 glyphs have no `d` attribute, for example `uniE0A5` (noteheadNull), `uniE07F`, `uniE09E`/`uniE09F`, `uniE8E0`–`E8E7`. `GlyphPaths` would throw on them, because of the `!` at `glyph_path.dart:31`.
- All 518 optional glyphs (U+F4xx–F6xx), 201 ligatures and 317 alternates listed in the metadata are present.

**Petaluma.svg**
- 2021-01-27, "By convertio": an online converter, not FontForge. `units-per-em="1000"`, `unicode-range` U+0020–F52A.
- 1524 glyphs, all `uniXXXX` apart from `.notdef`, `space` and `uni0X20`. 33 glyphs have no `d`.
- Only 151 of the 500 `optionalGlyphs` exist in the SVG. None of the 201 metadata `ligatures` exist, since everything above U+F52A is absent. Only 151 of 299 alternates exist.
- Small grace/cue glyphs:
  - missing: `accidentalFlatSmall`/`SharpSmall`/`NaturalSmall`, `noteheadBlackSmall`/`HalfSmall`/`WholeSmall`;
  - present: `flag8thUpSmall`/`DownSmall`, `g`/`f`/`cClefSmall`.
  - Bravura has all of these.

**Scale.** 1 em = 1000 units = 4 staff spaces, so 1 staff space = 250 units. That matches `Constants.staffSpace`.

## Coverage

**Result**, for the two SVG fonts described above:
- Bravura.svg plus its metadata has all 222 glyphs below, each with a `d` path.
- Petaluma.svg lacks only `legerLine` (U+E022). Its metadata has that entry, but the SVG has no glyph.

**Fingering codepoints.** E120 is note clusters, not fingering. `fingering0`–`5` are ED10–ED15 and `fingering6`–`9` are ED24–ED27. EA50+ holds figured-bass digits with the same shapes.

## Glyphs by model feature

**Clefs** (12-value `Clef` enum in `pitch.dart`)
- gClef E050, gClef8vb E052, gClef8va E053
- cClef E05C, used for soprano, mezzo-soprano, alto, tenor and baritoneC
- fClef E062, used for bass and baritoneF; fClef8vb E064
- unpitchedPercussionClef1 E069
- Mid-bar clef changes: gClefChange E07A, cClefChange E07B, fClefChange E07C

**Accidentals** (`Alter` −4..+4)
- accidentalFlat E260, Natural E261, Sharp E262, DoubleSharp E263, DoubleFlat E264
- Cautionary: accidentalParensLeft E26A, accidentalParensRight E26B
- Quarter tones, Stein–Zimmermann: QuarterToneFlatStein E280, ThreeQuarterTonesFlatZimmermann E281, QuarterToneSharpStein E282, ThreeQuarterTonesSharpStein E283, NarrowReversedFlatAndFlat E285
- Quarter tones, Gould arrows: E270, E271, E274, E275

**Noteheads** (`NoteHead` × breve, whole, half, black)
- normal: E0A0, E0A1 (square breve), E0A2, E0A3, E0A4
- cross: E0A6–E0A9
- circleCross: E0B0–E0B3
- triangle (up): E0BA, E0BB, E0BC, E0BE
- diamond: E0D7, E0D8, E0D9, E0DB, and noteheadDiamondWhite E0DD
- slash: E10A (breve), E102 (whole), E103 (half), E101 (black)

**Dots, stems, tremolos, flags, grace notes**
- augmentationDot E1E7
- stem E210 (metadata only)
- tremolo1–4 E220–E223 (`ChordEvent.tremolo` 0..4)
- flag8thUp through flag128thDown: E240–E249
- graceNoteSlashStemUp E564, graceNoteSlashStemDown E565
- graceNoteAcciaccaturaStemUp E560, graceNoteAcciaccaturaStemDown E561

**Rests** (`DurationBase` includes breve; `MeasureRest`; multi-measure rests from `MeasureView.isRestOnly`)
- restDoubleWhole E4E2 through rest128th E4EA
- Leger-line variants: E4F3, E4F4, E4F5
- H-bar: restHBar E4EE, Left E4EF, Middle E4F0, Right E4F1

**Time signatures** (`Meter` groups and `MeterSymbol`)
- timeSig0–9 E080–E089
- timeSigCommon E08A, timeSigCutCommon E08B
- timeSigPlus E08C, timeSigPlusSmall E08D, for additive groups

**Tuplets**
- tuplet0–9 E880–E889, tupletColon E88A

**Dynamics** (`Dynamic` enum)
- Letters: p E520, m E521, f E522, r E523, s E524, z E525
- pppp E529, ppp E52A, pp E52B, mp E52C, mf E52D, ff E52F, fff E530, ffff E531
- fp `dynamicFortePiano` E534
- sf `dynamicSforzando1` E536
- sfz `dynamicSforzato` E539
- rfz `dynamicRinforzando2` E53D

**Articulations** (`Articulation`)
- Accent E4A0/E4A1, staccato E4A2/E4A3, tenuto E4A4/E4A5, staccatissimo E4A6/E4A7, marcato E4AC/E4AD
- fermataAbove E4C0, fermataBelow E4C1
- harmonic: stringsHarmonic E614

**Ornaments** (`Ornament`)
- ornamentTrill E566, ornamentTurn E567, ornamentTurnInverted E568
- ornamentShortTrill E56C (inverted mordent), ornamentMordent E56D
- Lines: wiggleTrill EAA4 (`TrillLine`), wiggleGlissando EAAF

**String marks**
- Bowing: stringsDownBow E610, stringsUpBow E612
- Fingering: ED10–ED15 and ED24–ED27
- String numbers: guitarString0–9 E833–E83C

**Pedal**
- keyboardPedalPed E650, keyboardPedalUp E655, keyboardPedalUpNotch E657

**Octave lines** (`OctaveShift`): E510–E51E
- ottava, ottavaAlta, ottavaBassa, ottavaBassaBa
- quindicesima, quindicesimaAlta, quindicesimaBassa
- ventiduesima, ventiduesimaAlta, ventiduesimaBassa
- octaveParensLeft and octaveParensRight
- ottavaBassaVb, quindicesimaBassaMb, ventiduesimaBassaMb

**Repeats and navigation**
- repeatLeft E040, repeatRight E041, repeatRightLeft E042, repeatDots E043, repeatDot E044
- dalSegno E045, daCapo E046, segno E047, coda E048, codaSquare E049

**Barlines** (all present, though the current engine draws barlines as lines)
- barlineSingle E030, barlineDouble E031, barlineFinal E032, barlineHeavy E034, barlineDashed E036, barlineDotted E037

**Systems**
- brace E000, bracket E002, bracketTop E003, bracketBottom E004
- legerLine E022

**Tempo marks** (`Tempo.beat` is a `NoteValue` with dots)
- metNoteWhole ECA2, metNoteHalfUp ECA3, metNoteQuarterUp ECA5, metNote8thUp ECA7, metNote16thUp ECA9, metAugmentationDot ECB7

**Chord symbols**
- csymAccidentalFlat ED60, csymAccidentalSharp ED62

**Not in the model, but present in both fonts**
- breathMarkComma E4CE, caesura E4D1
- The model has no breath mark, caesura, arpeggio or pizzicato type. Nothing in `packages/score_model/lib` names one.

## Notes

- Model `PitchedNote.string` is an index, lowest-tuned string first (`events.dart`). Printed string numbers conventionally count from the highest string, so layout must convert.
- Multi-digit fingering, tuplet numbers, numerators above 9 and multi-rest counts must be composed from the single digits.

**Text the model holds that has no glyph.** It covers lyrics, tempo text, rehearsal marks, `TextMark`, chord-symbol quality, the volta "1., 2.", `Jump` text ("D.C. al Fine"), Fine and To Coda, title, composer and lyricist, part names and bar numbers.
- No text font is bundled. Bravura's `textFontFamily` recommendation (Academico and others) is not shipped.
- Lyrics in any script must render, Mongolian Cyrillic included (`docs/design/score-model/grounding.md`).
