---
title: Read and write MusicXML, MIDI and JSON
description: Import a score from MusicXML or a compressed .mxl file, export it as MusicXML, .mxl or a MIDI file, and save and load it as JSON.
sidebar:
  order: 11
---

This guide reads a `Score` from MusicXML, writes it as MusicXML and MIDI, and saves and loads it as JSON.

The functions are in `khuur_score_model`, which `package:khuur_sheet_music/khuur_sheet_music.dart` exports. The score model is pure Dart, so a server or a command-line tool can import `package:khuur_score_model/khuur_score_model.dart` alone and use the same functions.

## Read a MusicXML file

Pass the text of the document to `scoreFromMusicXml`. It returns a `Score`.

```dart
final score = scoreFromMusicXml(File(path).readAsStringSync());
```

To read a file that your app bundles, load it as a string first.

```dart
final score = scoreFromMusicXml(
  await rootBundle.loadString('assets/scores/minuet.musicxml'),
);
```

`scoreFromMusicXml` reads a `score-partwise` document. It reads everything that `scoreToMusicXml` writes, and the common notation of files from other programs. What the model has no place for is left out. It takes the text of the document. To open a compressed `.mxl` file, pass its bytes to `scoreFromMusicXmlBytes`.

### Read the bytes of a `.mxl` or `.musicxml` file

`scoreFromMusicXmlBytes` takes the bytes of a file, compressed or not, and returns a `Score`. Use it for a file that a user picks, where the app does not know which kind it is. MuseScore, Dorico, Sibelius and Finale export `.mxl` by default.

```dart
final score = scoreFromMusicXmlBytes(File(path).readAsBytesSync());
```

It tells a `.mxl` file by the zip signature at its start. In the archive, `META-INF/container.xml` names the score in its first `<rootfile>`. An archive without a container is read only when it holds exactly one `.musicxml` or `.xml` file outside `META-INF/`.

The text of the document is UTF-16 when it starts with a UTF-16 byte order mark, and UTF-8 otherwise. A UTF-8 byte order mark is dropped, and bytes that are not valid UTF-8 are refused. The text then goes to `scoreFromMusicXml`.

`maxScoreBytes` is the largest document it reads. The default, 64 MiB, is meant to leave room for a long orchestral score. In a `.mxl` file the limit counts the score once inflated, and an entry that the archive declares larger is refused before any of it is inflated. An entry is refused as soon as it inflates past the size its archive declares, on the web as on Android, iOS and the desktop, so a hostile archive cannot fill the app's memory. Lower the limit for files from untrusted sources on a small device.

```dart
final score = scoreFromMusicXmlBytes(bytes, maxScoreBytes: 16 << 20);
```

To change the document before it is read, call `musicXmlFromBytes`. It returns the text that `scoreFromMusicXmlBytes` would pass on, under the same rules and the same limit.

```dart
final score = scoreFromMusicXml(withoutCues(musicXmlFromBytes(bytes)));
```

Here `withoutCues` stands for the app's own change to the text.

### Handle a file that does not import

`scoreFromMusicXml` throws a `ScoreFormatException` for a file that it cannot read. It never guesses. The exception's `path` names the element, such as `/score-partwise/part/measure[3]/note[2]`, and its `message` says why.

```dart
try {
  return scoreFromMusicXml(text);
} on ScoreFormatException catch (error) {
  // error.path names the element, error.message the problem.
}
```

`scoreFromMusicXmlBytes` throws only `ScoreFormatException` too. Its `path` is `/` for a damaged archive or text that does not decode, `META-INF/container.xml` for a container that names no score, and the name of the score's entry for an entry that is too large or damaged.

Import refuses these files, among others:

- A document that is not well-formed XML.
- A `score-timewise` document.
- A score whose parts have different numbers of bars, or disagree on a meter.
- A note with no `<type>` whose duration matches no note value.
- A note in a tuplet whose duration is a division or more from its written value.
- A note that overlaps the note before it in its voice.
- A tuplet that never stops in its bar.

A score that import returns always saves, because import saves and loads its own result before it returns it.

## Write a MusicXML file

`scoreToMusicXml` returns the score as a MusicXML 4.0 `score-partwise` document.

```dart
File('study.musicxml').writeAsStringSync(scoreToMusicXml(score));
```

Pitches are written as the part reads them, so a transposing part carries `<transpose>`. A hidden part is kept, with its staves marked as not printed. A few values of the model have no place in MusicXML, and export leaves them out. They are an instrument's key, range and clef, a tempo line's factor, and `SignatureDisplay.noCourtesy`. Export also leaves out a glissando from a note to a rest, because MuseScore 4 reads a glissando mark only on a note and would close that line on the next glissando.

To write a compressed `.mxl` file, call `scoreToMxl`. It returns the bytes of a MusicXML 4.0 compressed file that holds the same document as `score.musicxml`.

```dart
File('study.mxl').writeAsBytesSync(scoreToMxl(score));
```

## Write a MIDI file

`scoreToMidi` returns the bytes of a Standard MIDI File of the score as it plays.

```dart
File('study.mid').writeAsBytesSync(scoreToMidi(score));
```

The file holds what `ScorePlayer` plays, so repeats, endings, jumps, ties, slurs, dynamics, ornaments and the pedal come out as they sound. Every part is in the file, hidden parts included. The file is format 1 at 960 ticks a quarter:

- The first track holds the tempo, the time signature and the key signature.
- Each part has a track after it, in score order, on the channel that playback gives it, with its bank and program.
- A quarter tone is a pitch bend before the note, with the bend range set to two semitones.
- The pedal is in the lengths of the notes it holds, and not a controller.
- Each track sets its channel's expression, controller 11, at its start and wherever it changes, so a held note of a part that swells follows a hairpin. A part that swells keeps its soft levels in controller 11 and strikes them at velocity 84, so a tool that reads dynamics from velocity alone sees them flat. MuseScore's own export keeps the level on velocity instead.
- A bank under 128 is written as a bank select. A larger bank, such as the drum bank 128 of a SoundFont, is left to the channel.

The package does not read MIDI files.

## Save and load a score as JSON

`scoreToJson` encodes a score as JSON-compatible maps and lists, with every id kept. `scoreFromJson` decodes it.

```dart
final saved = jsonEncode(scoreToJson(score));

final loaded = scoreFromJson(jsonDecode(saved));
```

`scoreFromJson` checks every rule of a score, so a damaged or hand-edited file does not load as a broken score. It throws a `ScoreFormatException` whose `path` is the JSON path of the first problem, such as `$.measures[12].staves[0]`.

Each file records `scoreSchemaVersion`. A file from a newer version is refused.

## Related pages

- [Show a score](/khuur_sheet_music/guides/show-a-score/)
- [Play a score](/khuur_sheet_music/guides/play-a-score/)
- [The score model](/khuur_sheet_music/explanation/score-model/)
- [Packages](/khuur_sheet_music/reference/packages/)
