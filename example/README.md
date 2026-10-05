# khuur_sheet_music example

One page that shows a score, edits it and plays it. `lib/main.dart` is the page. `lib/selection_actions.dart` holds the selection and the table of the actions on it. `lib/demo_score.dart` builds the tune, the opening of Beethoven's "Für Elise", and the empty sheet.

- Tap a staff to enter a note of the value picked under the sheet. The note starts on a beat of its own value, so a whole note starts its bar and a quarter starts on a quarter. A tap on a rest enters a note too, where the finger is, since a rest is the room its bar has left. So an empty bar takes a note wherever it is tapped, on its bar rest as beside it.
- Press and hold on the sheet to see where a note will go. A glass shows the note that letting go enters, with its stem and its flag, and the sheet around it at twice its size. Slide the finger to move the note, and lift it to enter the note. Slide the finger off the sheet and lift it there to enter nothing. The glass stands over the finger, or beside it where the sheet has no room above.
- Auto bars decides whether entry adds bars by itself. With it on, a note longer than the rest of its bar is cut at the bar line and tied, and a note that ends the score gets an empty bar after it. With it off, the long note is refused with a message, and the page says when a note ends the score. Add bar puts one bar at the end.
- Auto beams decides whether entered notes beam by the meter. With it off, each entered note stands alone.
- Tap a note to select it. A note that is entered is selected too. A row of named buttons then takes the place of the hint under the sheet. It deletes, widens and narrows the selection, moves the pitch by a step of the scale or by an octave, adds a tie, a slur, a beam or a hairpin, and copies and pastes. A second press of Slur, Crescendo or Decrescendo takes the line away. Unbeam keeps the selected notes out of a beam, and Auto beam hands them back to the meter. Delete turns a note into a rest of its length, and a bar left with only rests shows one bar rest. A rest is not removed, as every bar stays full, so Delete is off on a rest alone. The row scrolls sideways to the rest of its buttons.
- New sheet, in the app bar, starts over with the tune or with an empty sheet of four bars of 4/4 on one staff. The player stops, and the undo history goes with the old sheet.
- The other buttons in the app bar undo the last edit and zoom the sheet.
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

`test/example_app_test.dart` drives the page with a fake MIDI output. It opens the page over the tune of `test/support/eight_bars.dart`, so what it edits and plays does not hang on the tune the app ships with. `ExampleApp(score: ...)` opens the page over any score. To write a picture of the page, set `SNAPSHOT_DIR` to a directory before the run.

`integration_test/glyph_gate_test.dart` checks glyph placement on a device. The comment at its top gives the two commands.

## The tune

The tune is the opening of "Für Elise", WoO 59, by Ludwig van Beethoven. It is a pickup and eight bars of 3/8, and the last bar repeats from the pickup. The work is in the public domain. Its notes were entered by hand for this example and come from no edition.

The pedal is down under each bar of the left hand's notes, so they ring on. It lifts at the barline, or before the two notes of the right hand that lead into the next bar. Where it lifts is this example's choice and comes from no edition.

Editions beam each run of sixteenths whole. The meter alone starts a new beam at every eighth of 3/8, so `demo_score.dart` enters those notes with `BeamMode.join`.

## The SoundFont

`assets/soundfonts/piano.sf2` is Upright Piano KW from FreePats, in its full version of 2022-02-21, released under CC0. It is 57 MB. Its readme and its licence are beside it.

The page plays through a reverb, `_reverb` in `lib/main.dart`. On iOS and macOS its numbers pick the medium hall and make the reverb three tenths of the sound. Nobody has listened to it on Android.
