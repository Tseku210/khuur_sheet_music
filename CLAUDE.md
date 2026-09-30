# simple_sheet_music

Flutter package that renders sheet music on a `Canvas` and plays it back over MIDI. It is a fork of [tomoyu719/simple_sheet_music](https://github.com/tomoyu719/simple_sheet_music), maintained for the [Khuur](https://github.com/Tseku210/khuur_app) app.

## Commands

```bash
flutter pub get          # also resolves example/
flutter analyze          # library, tests, and example; must report no issues
flutter test             # library unit tests in test/
cd packages/score_model && dart test   # score model tests (not run by flutter test)
cd example && flutter run -d macos -t lib/midi_example.dart   # MIDI demo
```

## Layout

- `lib/simple_sheet_music.dart` is the public export list. Anything not exported there is internal.
- `lib/src/simple_sheet_music.dart` holds the `SimpleSheetMusic` widget. It loads SMuFL glyphs (`assets/*.svg`, `assets/*_metadata.json`) and mixes in `MidiPlaybackMixin`.
- Rendering flows from `SheetMusicLayout` to `SheetMusicRenderer`, then `StaffRenderer`, `MeasureRenderer`, and each `MusicalSymbolRenderer`. Metrics classes (`*_metrics.dart`) compute sizes before render.
- `lib/src/music_objects/` holds the domain types: notes, chords, rests, clefs, key and time signatures, barlines. Each symbol has a model, a metrics class, and a renderer.
- `lib/src/midi/midi_player.dart` sequences measures with a `Timer` and plays notes through `flutter_midi_pro` (Android, iOS, macOS only). It loads the `SoundFont` (`lib/src/midi/sound_font.dart`) that the app passes in.
- `test/mock/` holds hand-written fakes. Tests do not use a mocking package.
- `packages/score_model/` is the pure-Dart score model for the rewrite, a pub workspace member. Its design and the deviations accepted while implementing it are in `docs/design/score-model/RATIONALE.md`.

## Conventions

- Lints come from `pedantic_mono`. Keep `flutter analyze` clean.
- Asset paths that code loads at runtime must use the `packages/simple_sheet_music/` prefix. A bare `assets/...` path only resolves inside this package, not in a consuming app.
- The package bundles no SoundFont, because Flutter ships every package asset to every consuming app. The example app bundles `example/assets/soundfonts/piano.sf2`, FreePats' CC0 Upright Piano KW (small).
- Commit messages use Conventional Commits: `type(scope): description`.
- The library is open source and stays general. Khuur is its first consumer, not its target, so nothing Khuur-specific goes in `lib/` or `packages/`. Instruments, marks and examples are general, and Khuur's designs guide scope without being requirements.
