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
* **Breaking:** The package no longer bundles a SoundFont. The 261 MB `touhou.sf2` added that much to every app using the package, even with MIDI off. Pass `soundFont: AssetSoundFont(...)` or `FileSoundFont(...)` to `SimpleSheetMusic` instead. This replaces `enableMidi`, `soundFontType` and `customSoundFontPath`, and a null `soundFont` means playback is off. `MidiPlayer` now requires `soundFont`, and `MidiPlayer.initialize` takes no arguments. `SoundFontType` is removed.
* Replace the unmaintained `flutter_midi` with `flutter_midi_pro` 4.x. `flutter_midi` used the removed v1 Android plugin API and no longer builds on current Flutter.
* `MidiPlayer` now sends note-off when a note's duration ends, and on pause, stop, and dispose.
* Fix the default soundfont path. It now uses the `packages/simple_sheet_music/` prefix, so consuming apps can load it.
* Require Dart 3.6 and Flutter 3.27 or later. Allow `xml` 7.x.
* Remove the unused `async` and discontinued `golden_toolkit` dependencies.
* Play notes at their real pitch. `Pitch.midiNoteNumber` now counts semitones, and playback applies accidentals and the key signature.
