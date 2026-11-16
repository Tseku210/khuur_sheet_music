---
title: Read and write MusicXML, MIDI and JSON
description: Import a score from MusicXML, export it as MusicXML or a MIDI file, and save and load it as JSON.
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

`scoreFromMusicXml` reads a `score-partwise` document. It reads everything that `scoreToMusicXml` writes, and the common notation of files from other programs. What the model has no place for is left out. It takes the text of the document, so it does not open a compressed `.mxl` archive.

### Handle a file that does not import

`scoreFromMusicXml` throws a `ScoreFormatException` for a file that it cannot read. It never guesses. The exception's `path` names the element, such as `/score-partwise/part/measure[3]/note[2]`, and its `message` says why.

```dart
try {
  return scoreFromMusicXml(text);
} on ScoreFormatException catch (error) {
  // error.path names the element, error.message the problem.
}
```

Import refuses these files, among others:

- A document that is not well-formed XML.
- A `score-timewise` document.
- A score whose parts have different numbers of bars, or disagree on a meter.
- A note whose duration matches no note value.
- A note that overlaps the note before it in its voice.
- A tuplet that never stops in its bar.

A score that import returns always saves, because import saves and loads its own result before it returns it.

## Write a MusicXML file

`scoreToMusicXml` returns the score as a MusicXML 4.0 `score-partwise` document.

```dart
File('study.musicxml').writeAsStringSync(scoreToMusicXml(score));
```

Pitches are written as the part reads them, so a transposing part carries `<transpose>`. A hidden part is kept, with its staves marked as not printed. A few values of the model have no place in MusicXML, and export leaves them out. They are an instrument's key, range and clef, a tempo line's factor, and `SignatureDisplay.noCourtesy`.

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
