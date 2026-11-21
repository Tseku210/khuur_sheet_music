## 0.5.0
* A slur is fitted over everything under it along its whole length, as MuseScore 4 does, where it was lifted only until the middle half of its curve cleared the notes. A high note, a stem or a beam near either end no longer cuts through it.
* A system whose bars are wider than the sheet is squeezed to the sheet's width, as MuseScore 4 squeezes a system to fit. It first gives up the clear space between notes, and then scales its bars down until notes may collide. A bar runs past the sheet's right edge only when its widest mark, or its widest note with the part names and brace, the clef, signatures and barlines before it, is wider than the sheet. Every gap shrinks by one factor, so the notes stay in time order. Systems that fit are laid out as before.
* A mark that would pass the end of a squeezed bar moves left to end there, and so do a tuplet number and the start of a line. A beam hook between stems closer than the hook is long stops at the stem it points to.
* `SpacingPolicy.ratio` defaults to 1.5, MuseScore 4's spacing ratio, where it was 1.41. A note twice as long gets 1.5 times the space, so a bar of sixteenths is about 3 staff spaces narrower and a half note 0.3 wider. Most layouts change. An app that wants the old spacing passes `SpacingPolicy(ratio: 1.41)`.
* Depends on `khuur_score_model` 0.5.0, whose `Transposition` changed.

## 0.4.0
* A bar under a measure-repeat sign draws `Glyph.repeat1Bar` centred in it, or `Glyph.repeat2Bars` over the barline between the two bars of a two-bar sign with a 2 above it in `timeSig` digits at a rest run's count height, in place of its whole-bar rest. The bar reaches the sign's width, so a pressed bar still holds it.
* `SheetLayout.playingIn` gives the width of the whole bar while a staff under a sign plays, on both bars of a two-bar sign, where the second bar had no column.
* Line breaking never ends a system between the two bars of a two-bar sign. A bar under a sign does not fold into a multi-measure rest.
* Depends on `khuur_score_model` 0.4.0, which holds the signs.

## 0.3.4
* `SheetLayout.signatureAt` and `SystemLayout.signatureAt` give the clef, key signature, time signature or tempo mark drawn nearest a point within a reach, as a `SignatureHit` of its staff, its `SignatureKind` and the `ScorePoint` it takes effect from. A tempo mark is `SignatureKind.tempo` at its bar and offset, as one box over its words, note and number, on the system's top staff. A note, an event or a spanner drawn at least as near wins, a tempo line's words stay the line's, and `hitTest` does not change. `SystemLayout.signatures` holds each sign's box as a `PlacedSignature`. What the sheet draws does not change.
* `keySignatureSteps` is exported. It gives the staff steps of a key's accidentals under a clef, in printing order.
* `timeSignatureRows` gives the rows of glyphs a meter is drawn in, each on its staff step, which the sheet's own time signatures now draw from.

## 0.3.3
* `ChordEvent.ornamentAbove` and `ornamentBelow` draw as small accidentals over and under the ornament's sign, centred on it. Above the staff the one below sits between the sign and the note. Below the staff the order flips.
* Depends on `khuur_score_model` 0.3.3, which holds those accidentals.

## 0.3.2
* `SheetLayout.playingIn` builds the column from the playing chords' heads, accidentals and dots, and from rests. It took the whole of what each event draws, so a grace note widened it to the left, and a tie or a mark widened it to the right, past the barline when the tie crossed it. Ledger lines, stems and flags are left out too.
* A first layout takes about 12% less time on the layout benchmark's 500-bar and 2000-bar scores, and an update after an edit about 4 to 9% less. Lyric rows and system plans no longer store records that hold records or lists, which compiled code checks with a slow type test on each store. The layout does not change.

## 0.3.1
* `SheetLayout.playingIn` takes the column's width from the playing events other than a `MeasureRest`, which is centred in its bar and not drawn at its onset. On a downbeat where one staff plays a note and another holds a bar rest, the column reached the bar's middle and covered notes that had not started. A bar rest still gives the column its width when nothing else started with it.

## 0.3.0
* First release on pub.dev. Earlier versions were part of [`khuur_sheet_music`](https://github.com/Tseku210/khuur_sheet_music), as `score_layout`. Its CHANGELOG lists their changes.
* Every public member has a doc comment, so the API reference covers the whole package. The `public_member_api_docs` lint keeps it that way.
