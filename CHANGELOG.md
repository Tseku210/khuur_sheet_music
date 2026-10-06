## Unreleased
* **Breaking:** The package is renamed `khuur_sheet_music`. Name it so in `pubspec.yaml` and import `package:khuur_sheet_music/khuur_sheet_music.dart`. Its assets are under `packages/khuur_sheet_music/`.
* **Breaking:** The library is rewritten on an immutable score model. `SheetView` shows a `Score` and replaces `SimpleSheetMusic`. `ScorePlayer` replaces `MidiPlayer` and the playback methods of `SimpleSheetMusicState`. The old engine and every type it exported are deleted. The README shows the new API, and this table names what replaces each old name.

  | Before | Now |
  |---|---|
  | `SimpleSheetMusic(measures, width, height, ...)` | `SheetView(score: ...)`, sized by constraints, scrolling |
  | `Measure([...], isNewLine:)` | A `Score` built with `Score.blank` and edits, or loaded with `scoreFromJson`. `isNewLine` becomes `SetBreak(id, LayoutBreak.system)` |
  | `Clef.treble()`, `KeySignature.dMajor()`, `TimeSignature.fourFour()` | `SetClef`, `SetKey`, `SetMeter`, or `Score.blank(key:, meter:)` |
  | `initialClefType` | `PartTemplate.clefs`, or the `clef` of the part's `Instrument` |
  | `initialKeySignatureType`, `initialTimeSignatureType` | `Score.blank(key:, meter:)`. The meter is 4/4 unless given, where it was 2/4 |
  | `ClefType` | `Clef`, as in `Clef.treble`. `Clef` is now the enum of clefs |
  | `KeySignature.dMajor()` and the other keys by name | `KeySignature(2, KeyMode.major)`. The number counts sharps, and flats below zero. Only `KeySignature.cMajor` has a name |
  | `TimeSignatureType` | `Meter`, as in `Meter.fourFour` or `Meter.simple(5, 4)` |
  | `Note(Pitch.a4, ...)`, `ChordNote`, `Rest` | `EnterNote`, `AddToChord`, `EnterRest` |
  | `Pitch.a4`, a value of an enum | `Pitch(Step.a, 4)` or `Pitch.parse('A4')`. `Pitch` is now a class, and it holds the pitch that sounds |
  | `Accidental` | `Alter`, the third argument of `Pitch`, as in `Pitch(Step.f, 4, Alter.sharp)`. Write it also for a note that the key signature sharpens or flattens. The sheet prints the sign where the key and the bar call for one, and `SetAccidental` overrides that for a note |
  | `NoteDuration`, `RestType` | `NoteValue`, as in `NoteValue.quarter` or `NoteValue(DurationBase.sixtyFourth)` |
  | `ChordNotePart` | Nothing by that name. `EnterNote` writes the first note of a chord, and `AddToChord(event:, tone:)` adds each further `Pitch` |
  | `GlobalKey<SimpleSheetMusicState>` with `playMidi`, `pauseMidi`, `stopMidi`, `setTempo(int)` | `ScorePlayer.play`, `pause`, `resume`, `stop`, `tempoScale`, `status` |
  | `setTempo(bpm)`, in beats per minute | `tempoScale`, a ratio of the written tempo, where 1 plays as written. Divide the beats per minute by the tempo the score is marked with, as in `tempoScale = 90 / 120` |
  | `tempo` | The score holds its tempo. Pass `Score.blank(tempo: Tempo(120))`, or change the marks of a bar with `SetTempoMarks`. The tempo is 100 unless given, where it was 120 |
  | `highlightColor` | `SheetPalette.playback`, a `SheetHighlight` whose `ink` is that colour |
  | `lineColor` | `SheetPalette.staffLines` for the staff lines. `SheetPalette.inks` colours the barlines and the ledger lines, under `InkRole.barline` and `InkRole.ledgerLine` |
  | `onTap(symbol, offset)` | `onTap(SheetHit)` |
  | `FontType` | `EngravingStyle.font` (`SmuflFont`) |
  | `MidiPlayer`, `MidiPlayerStatus` | `ScorePlayer`, `PlayerStatus` |
  | `MidiPlayerStatus.stopped` | `PlayerStatus.idle`. `PlayerStatus.loading` is new |
  | `MidiPlayer.isPlaying` | `status.value == PlayerStatus.playing`. `status` is now a `ValueListenable` |
  | `MidiPlayer.highlightedSymbolId` | `position.value?.sounding`, the `EventRef`s that sound now. `SheetView(playback: player.position)` highlights them |
  | `MidiPlayer.loadMeasures` | Nothing. `play(score)` takes the score each time |
  | `MidiPlayer.jumpToMeasure(index)` | Nothing that seeks. `play(score, startAt: ScorePoint(score.measures[index].id, Moment.zero))` starts at that bar |
  | `SoundFont`, `AssetSoundFont`, `FileSoundFont` | Unchanged |
  | Per-symbol `color` | `SheetView.tints` |
  | Per-symbol `margin` | Nothing for one symbol. `EngravingStyle.spacing`, a `SpacingPolicy`, sets the spacing of the whole score |
  | The `debug` parameter, and the `GlyphMetadata`, `GlyphPaths` and `MeasureMetrics` exports | Deleted with nothing in their place |

* **Breaking:** The package no longer bundles a SoundFont. The 261 MB `touhou.sf2` added that much to every app using the package, even with MIDI off. Pass `AssetSoundFont(...)` or `FileSoundFont(...)` to `ScorePlayer` instead. This replaces `enableMidi`, `soundFontType` and `customSoundFontPath`. `SoundFontType` is removed.
* **Breaking:** The package no longer bundles Petaluma, or any font as SVG. It draws music with `fonts/Bravura.otf`.
* Replace the unmaintained `flutter_midi` with `flutter_midi_pro` 4.x. `flutter_midi` used the removed v1 Android plugin API and no longer builds on current Flutter.
* Require Dart 3.13 and Flutter 3.47 or later. The floors were Dart 3.6 and Flutter 3.27.
* Remove the `svg_path_parser` and `uuid` dependencies, the unused `async` and the discontinued `golden_toolkit`. `xml` stays. The `score_model` package depends on it to read and write MusicXML. It now needs `xml` 7.1 or later, where 6.5 was enough.
