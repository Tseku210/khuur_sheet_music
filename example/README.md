# simple_sheet_music example

One page that shows a score, edits it and plays it. `lib/main.dart` is the page. `lib/selection_actions.dart` holds the selection and the table of the actions on it. `lib/demo_score.dart` builds the tune of eight bars.

- Tap a staff to enter a note of the value picked under the sheet.
- Auto bars decides whether entry adds bars by itself. With it on, a note longer than the rest of its bar is cut at the bar line and tied, and a note that ends the score gets an empty bar after it. With it off, the long note is refused with a message, and the page says when the last bar is full. Add bar puts one bar at the end.
- Auto beams decides whether entered notes beam by the meter. With it off, each entered note stands alone.
- Tap a note to select it. A row of actions then takes the place of the hint under the sheet. It widens and narrows the selection, copies, pastes and deletes, moves the pitch by a step of the scale or by an octave, and adds a tie, a slur, a hairpin or a beam. The row scrolls sideways to the rest of its buttons.
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
