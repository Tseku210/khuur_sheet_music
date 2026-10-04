# simple_sheet_music

Sheet music for Flutter. `SheetView` shows a `Score` as a scrolling sheet. An app edits the score through an `EditSession`, and `ScorePlayer` plays it over MIDI while the sheet follows the sound.

One import gives the score model, the view and the player.

```dart
import 'package:simple_sheet_music/simple_sheet_music.dart';
```

The package is not on pub.dev. Depend on a checkout by path, as `example/pubspec.yaml` does. It needs Dart 3.13 or later.

## Show a score

```dart
SheetView(score: scoreFromJson(jsonDecode(saved)))
```

`SheetView` takes its width from its constraints and scrolls vertically. It draws at 8 logical pixels per staff space times the zoom. Its colours come from the ambient `Theme`. Give it a new `Score` after each edit, and it lays out only what the edit touched.

Put the view where its width and its height are bounded, as for any scroll view. It breaks lines at its width and never scales a score to fit a box.

## Build a score

A `Score` is immutable. Start one with `Score.blank` and change it through an `EditSession`. An edit that applies gives a new session, which holds the new score.

```dart
var session = EditSession.start(
  Score.blank(
    parts: const [
      PartTemplate(
        name: 'Piano',
        instrument: Instrument(key: 'piano', program: 0),
        staves: 2,
        clefs: [Clef.treble, Clef.bass],
      ),
    ],
    measureCount: 8,
  ),
);

final edit = EnterNote(
  at: session.cursor,
  tone: Pitch.parse('E4'),
  value: NoteValue.quarter,
);
if (session.run(edit) case Applied(session: final next)) {
  session = next;
}
```

`EnterNote`, `AddToChord` and `EnterRest` write music. `SetClef`, `SetKey` and `SetMeter` change the clef, the key and the meter. `SetBreak(measure, LayoutBreak.system)` starts a new system at a bar. `example/lib/demo_score.dart` builds an eight-bar tune from these edits.

`scoreToJson` and `scoreFromJson` save and load a score. `scoreToMusicXml` and `scoreFromMusicXml` write and read MusicXML.

## Edit by tap

The app owns the `EditSession`. In this handler a tap on a note selects it, and a tap anywhere else enters a note there.

```dart
void _onTap(SheetHit hit) {
  if (hit.target case ElementOwner(:final ref)) {
    setState(() => _session = _session.select(ItemSelection(Seq([ref]))));
    return;
  }
  final tone = _session.score.toneForStaffStep(hit.staff, hit.at, hit.staffStep);
  if (tone == null) return;
  _run(EnterNote(
    at: VoicePoint(staff: hit.staff, voice: hit.voice, at: hit.at),
    tone: tone,
    value: _value,
  ));
}

void _run(Edit edit) {
  switch (_session.run(edit)) {
    case Applied(:final session):
      setState(() => _session = session);
    case Refused(:final reason):
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$reason')));
  }
}

SheetView(
  score: _session.score,
  cursor: _session.cursor,
  selection: _session.selection,
  controller: _sheet,
  onTap: _onTap,
)
```

The hit names the staff, the voice, the time and the staff step under the tap, so the app looks nothing up.

The view draws the cursor as a caret. It opens with the cursor's system in view and scrolls that system into view when the cursor moves. To move the cursor from a button, call `_session.moveCursor(CursorMove.nextEvent)`.

`_sheet` is a `SheetController`. To zoom, set its `zoom`, as in `_sheet.zoom *= 1.25`.

## Play the score

```dart
late final _player = ScorePlayer(
  soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
  vsync: this,
);

SheetView(score: widget.score, playback: _player.position)

ValueListenableBuilder(
  valueListenable: _player.status,
  builder: (context, status, _) => IconButton(
    icon: Icon(status == PlayerStatus.playing ? Icons.pause : Icons.play_arrow),
    onPressed: switch (status) {
      PlayerStatus.playing => _player.pause,
      PlayerStatus.paused => _player.resume,
      PlayerStatus.idle => () => _player.play(widget.score, startAt: widget.from),
      PlayerStatus.loading => null,
    },
  ),
)

Slider(
  value: _player.tempoScale,
  min: 0.25,
  max: 1.5,
  onChanged: (value) => setState(() => _player.tempoScale = value),
)
```

The player publishes its position. The sheet highlights the events that sound and moves a playhead. The play button reads the player's status, so the app keeps no play state of its own.

`tempoScale` is the speed against the written tempo, and a new value applies at once. `stop` silences the output and takes the playhead away. The future of `play` fails when the SoundFont does not load. Call `dispose` when the widget's state is disposed.

Playback runs on Android, iOS and macOS, through `flutter_midi_pro`.

### Supply a SoundFont

The package bundles no SoundFont, because Flutter ships every asset of a package to every app that uses the package. Declare an `.sf2` file in your app's `pubspec.yaml` and pass its asset key as an `AssetSoundFont`. For a file your app downloaded, pass `FileSoundFont('/absolute/path.sf2')`.

Each part plays the program and the bank of its `Instrument`, so the SoundFont needs every program the score names.

The example app ships a 9.5 MB piano, `example/assets/soundfonts/piano.sf2`. It is [Upright Piano KW (small)](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html#UprightKW) from FreePats, a sampled Kawai upright released under CC0. Its readme and license are next to it.

## Place widgets over the sheet

The controller reports geometry in the view's local pixels, with scrolling applied. It notifies when a scroll, a zoom or a new layout moves that geometry. So an app can place its own widgets over the sheet, such as a delete badge at the selected note.

```dart
ListenableBuilder(
  listenable: _sheet,
  builder: (context, child) {
    final rect = switch (_session.selection.singleEvent) {
      final event? => _sheet.rectOf(event),
      null => null,
    };
    return Stack(children: [
      child!,
      if (rect != null)
        Positioned(left: rect.right, top: rect.top - 32, child: deleteButton),
    ]);
  },
  child: SheetView(
    score: _session.score,
    selection: _session.selection,
    controller: _sheet,
  ),
)
```

## Export an image

```dart
final image = await _sheet.toImage(pixelRatio: 3);
```

`toImage` draws the sheet without the cursor, the selection and the playhead, on a transparent background. One image holds at most `SheetController.maxImageSide` device pixels on a side, which is 8192. To export a longer score, pass `from` and `to` and make one image per range of systems. `systemCount` gives the number of systems.

## Change the colours and the engraving

- `palette` takes a `SheetPalette`. When it is null, the view derives one from the theme with `SheetPalette.of`, so the sheet follows light and dark mode.
- `tints` maps a note or an event to a colour, for marks such as practice feedback.
- `style` takes an `EngravingStyle`. Its `text` map sets the size and the font family of each `TextRole`.
- `staffSpace` is the number of logical pixels per staff space at zoom 1.

## Names that Flutter also declares

The library exports all of the score model, and two of the model's names are also names in Flutter. They are `Interval` and `Step`. A file that imports both libraries and uses either name does not compile. The analyzer reports `ambiguous_import`.

In a file that needs Flutter's names, hide the model's.

```dart
import 'package:simple_sheet_music/simple_sheet_music.dart' hide Interval, Step;
```

## Limits

- A staff draws five lines, or one line when its `lines` is 1. A staff of 2, 3, 4 or 6 lines loads and keeps its count, and draws as five lines. Tablature is not drawn.
- The sheet is one scrolling column of systems. It has no pages and no PDF export. `toImage` draws a range of systems.
- The zoom is the controller's. The view has no pinch gesture.
- `ScoreMeta.copyright` is not printed on the sheet.

## Fonts and licences

The package draws music with Bravura, Steinberg's music font, which it ships as `fonts/Bravura.otf` under the SIL Open Font License 1.1. `SheetView` registers `fonts/OFL.txt` with Flutter's `LicenseRegistry`, so the font's licence is on the page that `showLicensePage` opens.

Titles, lyrics and other text use the platform's default font. To get the same text on every platform, bundle a font in your app and name it in `TextSpec.family`.

The code is under the MIT License. See [LICENSE](LICENSE).

## Run the example

```bash
cd example
flutter run -d macos
```

The example is one page, `example/lib/main.dart`. It shows the tune of `demo_score.dart`, enters a note on a tap, selects a note on a tap on it, zooms through the controller, and plays through `ScorePlayer` with a tempo slider.

## Work on the package

The repository is a pub workspace of three packages. `packages/score_model` is the score model, `packages/score_layout` is the layout engine, and the root package is the Flutter view and the player. Both packages under `packages/` are pure Dart. The designs are in [docs/design/score-model/RATIONALE.md](docs/design/score-model/RATIONALE.md) and [docs/design/layout/RATIONALE.md](docs/design/layout/RATIONALE.md).

Run these checks from the repository root before you send a change. `flutter test` at the root runs neither the tests of the two packages nor the tests of the example.

```bash
flutter pub get
flutter analyze
flutter test
(cd packages/score_model && dart test)
(cd packages/score_layout && dart test)
(cd example && flutter test)
```

`packages/score_layout/benchmark/layout_benchmark.dart` measures the cost of layout against a budget. After a change to the layout engine, compile the benchmark and run it. It exits with code 1 when a layout is over its budget.

```bash
cd packages/score_layout
mkdir -p build
dart compile exe benchmark/layout_benchmark.dart -o build/layout_benchmark
build/layout_benchmark
```

## Acknowledgments

The package began as a fork of [simple_sheet_music](https://github.com/tomoyu719/simple_sheet_music) by [@tomoyu719](https://github.com/tomoyu719). The model, the layout engine, the view and the player have since been rewritten.

[Khuur](https://github.com/Tseku210/khuur_app) is the first app that uses the library.
