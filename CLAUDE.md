# simple_sheet_music

Flutter package that renders sheet music on a `Canvas` and plays it back over MIDI. It is a fork of [tomoyu719/simple_sheet_music](https://github.com/tomoyu719/simple_sheet_music), maintained for the [Khuur](https://github.com/Tseku210/khuur_app) app.

## Commands

```bash
flutter pub get          # also resolves example/
flutter analyze          # library, tests, and example; must report no issues
flutter test             # library unit tests in test/
cd example && flutter run -d macos -t lib/midi_example.dart   # MIDI demo
```

## Layout

- `lib/simple_sheet_music.dart` is the public export list. Anything not exported there is internal.
- `lib/src/simple_sheet_music.dart` holds the `SimpleSheetMusic` widget. It loads SMuFL glyphs (`assets/*.svg`, `assets/*_metadata.json`) and mixes in `MidiPlaybackMixin`.
- Rendering flows from `SheetMusicLayout` to `SheetMusicRenderer`, then `StaffRenderer`, `MeasureRenderer`, and each `MusicalSymbolRenderer`. Metrics classes (`*_metrics.dart`) compute sizes before render.
- `lib/src/music_objects/` holds the domain types: notes, chords, rests, clefs, key and time signatures, barlines. Each symbol has a model, a metrics class, and a renderer.
- `lib/src/midi/midi_player.dart` sequences measures with a `Timer` and plays notes through `flutter_midi_pro` (Android, iOS, macOS only).
- `test/mock/` holds hand-written fakes. Tests do not use a mocking package.

## Conventions

- Lints come from `pedantic_mono`. Keep `flutter analyze` clean.
- Asset paths that code loads at runtime must use the `packages/simple_sheet_music/` prefix. A bare `assets/...` path only resolves inside this package, not in a consuming app.
- `assets/soundfonts/*.sf2` is stored in Git LFS. Run `git lfs install && git lfs pull` before you run MIDI playback. Without it the file is a text pointer, and the macOS sampler aborts the app on load.
- Commit messages use Conventional Commits: `type(scope): description`.
