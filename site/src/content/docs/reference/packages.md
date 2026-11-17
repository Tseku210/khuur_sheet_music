---
title: Packages
description: The three packages of khuur_sheet_music, what each holds, its import line, and its API reference on pub.dev.
sidebar:
  order: 1
---

The repository is a pub workspace of three packages, all at version 0.3.3. The root package is the Flutter library. The two packages under `packages/` are pure Dart.

| Package | Kind | Holds | Depends on |
| --- | --- | --- | --- |
| `khuur_sheet_music` | Flutter | The view, the controller, the palette and the player | `khuur_score_model`, `khuur_score_layout`, `khuur_synth`, `material_ui` |
| `khuur_score_model` | Pure Dart | The score, its edits, saving and loading, and the playback script | `xml` |
| `khuur_score_layout` | Pure Dart | The layout engine, glyphs and hit testing | `khuur_score_model` |

## khuur_sheet_music

```dart
import 'package:khuur_sheet_music/khuur_sheet_music.dart';
```

The Flutter library. An app needs this import alone. API reference: [khuur_sheet_music library](https://pub.dev/documentation/khuur_sheet_music/latest/khuur_sheet_music/khuur_sheet_music-library.html).

The import exports the following names.

| From | Names |
| --- | --- |
| The library itself | `SheetView`, `SheetController`, `EntryHold`, `SheetPalette`, `SheetHighlight`, `SheetLine`, `ScorePlayer`, `PlayerStatus`, `PlaybackPosition`, `MidiOutput`, `SynthOutput`, and the `SmuflFontFamily` extension, which gives `SmuflFont.flutterFamily` |
| `khuur_score_model` | Every public name |
| `khuur_score_layout` | `ChordSymbolSpelling`, `ElementOwner`, `EngravingDefaults`, `EngravingStyle`, `Glyph`, `InkRole`, `NotePreview`, `Owner`, `QuarterToneGlyphs`, `SheetHit`, `SignatureHit`, `SignatureKind`, `SmuflFont`, `SpacingPolicy`, `SpannerOwner`, `StringNumbers`, `TextRole`, `TextSpec`, `accidentalGlyph`, `bowingGlyph`, `dynamicGlyph`, `fingeringGlyphs`, `keySignatureSteps`, `noteGlyph`, `restGlyph` |
| `khuur_synth` | `AssetSoundFont`, `AudioOutputFailed`, `AudioSessionPolicy`, `FileSoundFont`, `PresetNotFound`, `Reverb`, `SoundFont`, `SoundFontLoadFailed`, `Synth`, `SynthException`, `SynthUnavailable` |

Two names of the score model clash with names in Flutter. [Name clashes](/khuur_sheet_music/reference/name-clashes/) lists them.

## khuur_score_model

```dart
import 'package:khuur_score_model/khuur_score_model.dart';
```

The immutable score model. It holds `Score`, `EditSession` and the edits, JSON through `scoreToJson` and `scoreFromJson`, MusicXML through `scoreToMusicXml` and `scoreFromMusicXml`, MIDI files through `scoreToMidi`, and the timed playback script of `PlaybackCompiler`. It has no Flutter dependency, so it runs in a Dart server or command-line tool too. API reference: [khuur_score_model library](https://pub.dev/documentation/khuur_score_model/latest/khuur_score_model/khuur_score_model-library.html).

`khuur_sheet_music` exports all of this package.

## khuur_score_layout

```dart
import 'package:khuur_score_layout/khuur_score_layout.dart';
```

The layout engine. `SheetLayout` turns a `Score` into systems of positioned glyphs, lines and text, keeps them current across edits, and hit-tests points on them. All geometry is in staff spaces. The package knows nothing of pixels, Flutter or a platform, and takes text extents through a `TextMeasurer`. It holds the Bravura glyph table in `SmuflFont.bravura`. API reference: [khuur_score_layout library](https://pub.dev/documentation/khuur_score_layout/latest/khuur_score_layout/khuur_score_layout-library.html).

`khuur_sheet_music` exports the names that an app passes to `SheetView` or reads from it, listed in the table above. The rest, such as `SheetLayout`, needs this import.
