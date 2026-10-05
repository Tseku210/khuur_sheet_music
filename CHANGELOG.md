## 0.0.1
* initial release.

## 0.0.2
* fix README.md.

## 0.0.3
* add Rests.

## 0.0.4-dev.1
* add key signatures.

## 1.0.0-dev.1
* add chord 
* switching rendering methods

## 1.0.0 - 2024/07/09
* add chord 
* switching rendering method

## Unreleased
* **Breaking:** The package is renamed `khuur_sheet_music`. Name it so in `pubspec.yaml` and import `package:khuur_sheet_music/khuur_sheet_music.dart`. Its assets are under `packages/khuur_sheet_music/`.
* **Breaking:** The library is rewritten on an immutable score model. `SheetView` shows a `Score` and replaces `SimpleSheetMusic`. `ScorePlayer` replaces `MidiPlayer` and the playback methods of `SimpleSheetMusicState`. The old engine and every type it exported are deleted. The README shows the new API, and this table names what replaces each old name.

  | Before | Now |
  |---|---|
  | `SimpleSheetMusic(measures, width, height, ...)` | `SheetView(score: ...)`, sized by constraints, scrolling |
  | `Measure([...], isNewLine:)` | A `Score` built with `Score.blank` and edits, or loaded with `scoreFromJson`. `isNewLine` becomes `SetBreak(id, LayoutBreak.system)` |
  | `Clef.treble()`, `KeySignature.dMajor()`, `TimeSignature.fourFour()` | `SetClef`, `SetKey`, `SetMeter`, or `Score.blank(key:, meter:)` |
  | `Note(Pitch.a4, ...)`, `ChordNote`, `Rest` | `EnterNote`, `AddToChord`, `EnterRest` |
  | `GlobalKey<SimpleSheetMusicState>` with `playMidi`, `pauseMidi`, `stopMidi`, `setTempo(int)` | `ScorePlayer.play`, `pause`, `resume`, `stop`, `tempoScale`, `status` |
  | `highlightColor` | `SheetPalette.playback`, a `SheetHighlight` whose `ink` is that colour |
  | `onTap(symbol, offset)` | `onTap(SheetHit)` |
  | `FontType` | `EngravingStyle.font` (`SmuflFont`) |
  | `MidiPlayer`, `MidiPlayerStatus` | `ScorePlayer`, `PlayerStatus` |
  | `SoundFont`, `AssetSoundFont`, `FileSoundFont` | Unchanged |
  | Per-symbol `color` | `SheetView.tints` |
  | `debug`, `GlyphMetadata`, `GlyphPath`, `MeasureMetrics` exports | Deleted with nothing in their place |

* **Breaking:** The package no longer bundles a SoundFont. The 261 MB `touhou.sf2` added that much to every app using the package, even with MIDI off. Pass `AssetSoundFont(...)` or `FileSoundFont(...)` to `ScorePlayer` instead. This replaces `enableMidi`, `soundFontType` and `customSoundFontPath`. `SoundFontType` is removed.
* **Breaking:** The package no longer bundles Petaluma, or any font as SVG. It draws music with `fonts/Bravura.otf`.
* Replace the unmaintained `flutter_midi` with `flutter_midi_pro` 4.x. `flutter_midi` used the removed v1 Android plugin API and no longer builds on current Flutter.
* Require Dart 3.13 or later.
* Remove the `svg_path_parser`, `uuid` and `xml` dependencies, the unused `async` and the discontinued `golden_toolkit`.
