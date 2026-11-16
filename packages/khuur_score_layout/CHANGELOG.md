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
