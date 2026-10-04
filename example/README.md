# simple_sheet_music example

One page that shows a score, edits it and plays it. `lib/main.dart` is the page, and `lib/demo_score.dart` builds its tune of eight bars.

- Tap a staff to enter a note of the value picked under the sheet.
- Tap a note to select it. The badge beside the note deletes it.
- The buttons in the app bar undo the last edit and zoom the sheet.
- The buttons under the sheet play, pause, resume and stop. The slider sets the speed from 25 to 150 percent of the written tempo.

## Run the app

```bash
flutter run -d macos
```

Playback runs on Android, iOS and macOS.

## Run the tests

```bash
flutter test
```

`test/example_app_test.dart` drives the page with a fake MIDI output. To write a picture of the page, set `SNAPSHOT_DIR` to a directory before the run.

`integration_test/glyph_gate_test.dart` checks glyph placement on a device. The comment at its top gives the two commands.

## The SoundFont

`assets/soundfonts/piano.sf2` is Upright Piano KW (small) from FreePats, released under CC0. Its readme and its licence are beside it.
