## Unreleased
* `scoreFromMusicXmlBytes` reads a `Score` from the bytes of a file, a compressed `.mxl` file or an uncompressed `.musicxml` file. It finds the score through `META-INF/container.xml`, and reads an archive without a container when it holds one `.musicxml` or `.xml` file. It decodes UTF-8, with or without a byte order mark, and UTF-16 after a byte order mark, so an app no longer decodes the text itself.
* `musicXmlFromBytes` returns the text of the document in those bytes, by the same rules, for an app that changes the document before `scoreFromMusicXml` reads it.
* `scoreFromMusicXmlBytes` reads a document of at most `maxScoreBytes`, 64 MiB by default, counted once inflated. An archive entry that declares a larger size is refused before any of it is inflated, and an entry that inflates past the size it declares is refused at that point, on the web too. Every problem with the file throws `ScoreFormatException`.
* `scoreToMxl` writes a score as a MusicXML 4.0 compressed file.
* The package depends on `archive` 4.7, through `package:archive/archive.dart` only, so it still compiles for the web.

## 0.3.3
* `ChordEvent.ornamentAbove` and `ornamentBelow` hold the accidentals of an ornament's upper and lower notes. Playback plays those notes with them, `ChordEvent.ornamentNote` names them, and each is null unless the chord has an ornament. `SetOrnament` clears them when the sign changes, and `Transpose` moves them with the notes.
* JSON writes them as `ornamentAbove` and `ornamentBelow` when set. Readers before this release skip the keys and play the key's notes.
* `scoreFromMusicXml` reads the `<accidental-mark>` after an ornament's sign, by its `placement`, and `scoreToMusicXml` writes it.

## 0.3.2
* `Score.measureView` times a voice's events and tuplets in one walk of the voice, where it walked it twice. The view it returns does not change.

## 0.3.1
* `scoreFromMusicXml` reads a note that ends nested tuplets whatever order it lists their `<tuplet type="stop">` elements in. A file that stopped the outer tuplet first was refused with "stops a tuplet that is not open".
* `scoreFromMusicXml` gives a chord the `<duration>` of its first note and ignores the durations of its other notes, as MuseScore and music21 do. A chord note with a different duration was refused with "a chord note lasts as long as its chord". Sibelius writes those durations without the notes' dots or tuplets.

## 0.3.0
* First release on pub.dev. Earlier versions were part of [`khuur_sheet_music`](https://github.com/Tseku210/khuur_sheet_music), as `score_model`. Its CHANGELOG lists their changes.
* Every public member has a doc comment, so the API reference covers the whole package. The `public_member_api_docs` lint keeps it that way.
