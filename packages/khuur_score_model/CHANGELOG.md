## Unreleased
* `ChordEvent.ornamentAbove` and `ornamentBelow` hold the accidentals of an ornament's upper and lower notes. Playback plays those notes with them, `ChordEvent.ornamentNote` names them, and each is null unless the chord has an ornament. `SetOrnament` clears them when the sign changes, and `Transpose` moves them with the notes.
* JSON writes them as `ornamentAbove` and `ornamentBelow` when set. Readers before this release skip the keys and play the key's notes.
* `scoreFromMusicXml` reads the `<accidental-mark>` after an ornament's sign, by its `placement`, and `scoreToMusicXml` writes it.

## 0.3.1
* `scoreFromMusicXml` reads a note that ends nested tuplets whatever order it lists their `<tuplet type="stop">` elements in. A file that stopped the outer tuplet first was refused with "stops a tuplet that is not open".
* `scoreFromMusicXml` gives a chord the `<duration>` of its first note and ignores the durations of its other notes, as MuseScore and music21 do. A chord note with a different duration was refused with "a chord note lasts as long as its chord". Sibelius writes those durations without the notes' dots or tuplets.

## 0.3.0
* First release on pub.dev. Earlier versions were part of [`khuur_sheet_music`](https://github.com/Tseku210/khuur_sheet_music), as `score_model`. Its CHANGELOG lists their changes.
* Every public member has a doc comment, so the API reference covers the whole package. The `public_member_api_docs` lint keeps it that way.
