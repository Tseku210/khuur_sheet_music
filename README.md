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

`EnterNote`, `AddToChord` and `EnterRest` write music. `SetClef`, `SetKey` and `SetMeter` change the clef, the key and the meter. `SetBreak(measure, LayoutBreak.system)` starts a new system at a bar. `example/lib/demo_score.dart` builds the opening of Beethoven's "Für Elise" from these edits, with a pickup bar from `SetBarLength` and pedal lines from `AddSpanner`.

A note longer than the rest of its bar is cut at the barline and tied, and a note that ends the score gets an empty bar after it. `EnterNote(overfill: Overfill.refuse, appendBar: false, ...)` turns both off. The long note is then refused with `WouldCrossBarline`, and the app adds bars with `InsertMeasures`. Beams follow the meter. `EnterNote(beam: BeamMode.none, ...)` enters a note that takes no beam, and `SetBeam` sets how a note beams afterwards.

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
  tapGrid: _value.base,
  onTap: _onTap,
)
```

The hit names the staff, the voice, the time and the staff step under the tap, so the app looks nothing up.

`tapGrid` is the grid a tap off a note snaps to, a sixteenth unless given. With the base of the value being entered, a note starts on a beat of its own value. On a finer grid a whole note tapped in the middle of a bar starts there, and the model cuts it at the beats and the barline and ties the pieces.

The view draws the cursor as a caret. It opens with the cursor's system in view and scrolls that system into view when the cursor moves. To move the cursor from a button, call `_session.moveCursor(CursorMove.nextEvent)`.

`_sheet` is a `SheetController`. To zoom, set its `zoom`, as in `_sheet.zoom *= 1.25`.

## Show where a note will go

A finger hides the place it points at. So a touch editor shows the note under a held finger before it enters one. `SheetView.preview` draws a note that is not in the score, which is its head and the ledger lines it needs. Nothing in the sheet moves for it. `SheetController.entryAt` tells where a note entered at a point would go.

```dart
SheetHit? _held;

void _hold(Offset at) => setState(
  () => _held = _sheet.entryAt(at, voice: _session.cursor.voice),
);

GestureDetector(
  onLongPressStart: (details) => _hold(details.localPosition),
  onLongPressMoveUpdate: (details) => _hold(details.localPosition),
  onLongPressEnd: (_) {
    final hit = _held;
    setState(() => _held = null);
    if (hit != null) _enter(hit);
  },
  child: SheetView(
    score: _session.score,
    controller: _sheet,
    tapGrid: _value.base,
    preview: switch (_held) {
      final hit? => NotePreview.at(hit, base: _value.base),
      null => null,
    },
  ),
)
```

`_enter` is `_onTap` above without its first lines, the ones that select a note.

`entryAt` gives the hit of `hitTest` without a target. It looks at nothing that is drawn, where `hitTest` at a note or a rest gives the time of that note or rest. A bar rest is drawn in the middle of its bar and starts at the bar's start, so a preview from `hitTest` would stand a long way from the finger.

The preview has the head of its `base`, so a whole note, a half note and a shorter one each look like themselves. It is drawn in the palette's `preview` colour.

A long press that has started gets no call when the system takes its pointer away. So the app also clears `_held` in the `onPointerCancel` of a `Listener` around the detector.

The package has no magnifying glass. The example app puts Flutter's `RawMagnifier` over the sheet beside the finger, in `example/lib/main.dart`.

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

A `PedalLine` plays as the sustain pedal. The notes of its part, on every staff, ring until the line ends. Add one with `AddSpanner(kind: const PedalLine(), staff: ..., first: ..., last: ...)`.

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

`toImage` draws the sheet without the cursor, the selection and the playhead. The background is the palette's `paper`, or transparent when the palette has none. One image holds at most `SheetController.maxImageSide` device pixels on a side, which is 8192. To export a longer score, pass `from` and `to` and make one image per range of systems. `systemCount` gives the number of systems.

## Change the look

The look of a sheet is set by three values of `SheetView`. Each has a default, so an app changes only what it wants to.

| Value | What it holds | A change |
| --- | --- | --- |
| `palette` | Colours, one for each kind of mark if the app wants that, and the styles of the selection, the cursor, the playhead and the sounding notes. | Repaints. Nothing is laid out again. |
| `style` | Fonts, text sizes, spacing, the thickness of the lines and what is printed. | Lays the score out again. |
| `tints` | A colour for one note or one event. | Repaints. |

### The palette

When `palette` is null the view derives one from the theme with `SheetPalette.of`, so the sheet follows light and dark mode. `copyWith` changes some parts of it and keeps the others.

```dart
SheetView(
  score: score,
  palette: SheetPalette.of(context).copyWith(
    selection: const SheetHighlight(
      fill: Color(0x332962FF),
      border: Color(0xFF2962FF),
      radius: 0.5,
      padding: 0.3,
    ),
    cursor: const SheetLine(color: Color(0xFFD81B60), width: 0.35),
  ),
)
```

The theme's ink is light in dark mode. So a paper of a fixed colour needs an ink of a fixed colour with it, or the notes do not show on it.

```dart
SheetPalette.of(context).copyWith(
  paper: const Color(0xFFFFF8E1),
  ink: const Color(0xFF2B2118),
  staffLines: const Color(0xFF8A7B6A),
)
```

`inks` gives one kind of mark a colour of its own. `InkRole` lists the kinds, such as the stems, the beams, the barlines, the clefs, the lyrics and the dynamics. A kind that is not in the map takes `ink`. The staff lines take `staffLines` and a note out of range takes `outOfRange`, unless the map has a colour for them.

```dart
SheetPalette.of(context).copyWith(
  inks: const {
    InkRole.barline: Color(0xFF9E9E9E),
    InkRole.lyric: Color(0xFF1565C0),
    InkRole.dynamics: Color(0xFFC62828),
  },
)
```

`copyWith(inks:)` replaces the whole map. The palette compares two maps by what they hold, so a map built in `build` repaints nothing while its colours stay the same. A new colour for one kind of mark repaints the systems that show that kind and no other.

| Part | Type | What it sets |
| --- | --- | --- |
| `ink` | `Color` | Every mark that has no colour of its own. |
| `staffLines` | `Color` | The staff lines. |
| `outOfRange` | `Color` | A note its instrument cannot play. |
| `inks` | `Map<InkRole, Color>` | A colour for one kind of mark, in place of the three above. |
| `paper` | `Color?` | The colour behind the sheet, on screen and in an image from `toImage`. Null draws none. |
| `selection` | `SheetHighlight` | The selected notes and ranges. |
| `playback` | `SheetHighlight` | The notes that sound now. |
| `cursor` | `SheetLine` | The caret at the edit cursor. |
| `preview` | `Color?` | The note of `SheetView.preview`. Null draws it in the cursor's colour. |
| `playhead` | `SheetLine` | The line that moves while the score plays. |

A `SheetHighlight` draws a box, a border around the box and the marked item again in another ink. Each is drawn when it is given, so a style may mix them. The box and its border lie under the notes and the staff lines, so a fill of any colour leaves the music to read. Boxes that overlap make one shape with one border around it.

| Part | What it sets |
| --- | --- |
| `fill` | The colour of the box. |
| `border`, `borderWidth` | The colour and the width of the line around the box. The line lies inside the box. A width of zero draws none. |
| `radius` | How round the corners are. |
| `padding` | How far the box reaches past the notes. Under zero it makes the box smaller than the notes. |
| `ink` | The colour the marked item is drawn in. A selected or sounding event is the whole chord or rest, with its stem, accidentals and dots. One selected note of a chord is its head alone. A selected range has a box and no ink. |

A `SheetLine` has a `color` and a `width`, and a width of zero draws no line. Every length is in staff spaces, so a box and a line grow with the zoom. A width or a radius under zero is refused.

`SheetHighlight` and `SheetLine` have a `copyWith` too. It replaces a part and cannot take a colour away, so a style without its fill is built anew.

Where a note has several of them, the ink of the selection covers a tint, and the ink of playback covers both.

### The engraving style

`EngravingStyle` holds what changes the layout. Every part has a default, so `EngravingStyle(staffGap: 6)` changes one, and `copyWith` changes some parts of a style an app already has.

| Part | What it sets |
| --- | --- |
| `text` | A `TextSpec` for each `TextRole`, with a size in staff spaces, `italic`, `bold` and a font `family`. The roles are the lyrics, chord symbols, expressions, tempo marks, rehearsal marks, navigation marks, volta numbers, string numbers, bar numbers, part names, the title, the subtitle and the credits. |
| `spacing` | A `SpacingPolicy`, which is the space after a quarter note, the ratio between a note and one twice as long, the least gap between glyphs, the padding at the start of a bar and the width of a run of empty bars. |
| `staffGap`, `lyricGap`, `systemGap` | The clear space between staves, above a row of lyrics and between systems. |
| `graceScale` | The size of grace notes. |
| `barNumbers`, `courtesySignatures`, `meterEverySystem`, `multiMeasureRests` | What is printed. |
| `justifyLastSystemFrom` | How full the last system must be before it is stretched to the full width. |
| `quarterTones`, `stringNumbers`, `chordSymbols` | Which glyphs and spellings these marks use. |
| `font` | The music font, with the thickness of every line the engine draws. The package bundles Bravura. |

The thickness of the stems, the beams, the barlines, the staff lines and the other lines comes from the font's `EngravingDefaults`, in staff spaces. A copy of the font holds other ones.

```dart
const font = SmuflFont.bravura;

SheetView(
  score: score,
  style: EngravingStyle(
    font: font.copyWith(
      defaults: font.defaults.copyWith(
        stemThickness: 0.16,
        staffLineThickness: 0.1,
      ),
    ),
  ),
)
```

The defaults are compared by value, so a style built in `build` lays nothing out again while its numbers stay the same. A thickness of zero draws no line. A default under zero, or one that is no finite number, is refused by an assert. The engine draws nothing with `arrowShaftThickness`, `bracketThickness`, `dashedBarlineDashLength`, `dashedBarlineGapLength`, `hBarThickness` and `subBracketThickness`, so a change to one of those changes nothing.

### Sizes and single notes

- `staffSpace` is the number of logical pixels per staff space at zoom 1, and `SheetController.zoom` scales it.
- `padding` is the room around the sheet.
- `tints` maps a note or an event to a colour, for marks such as practice feedback, a colour per voice or a colour per pitch. A tint on an event colours the whole chord or rest. A tint on one note colours its head alone.

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

The example is one page, `example/lib/main.dart`. It shows the tune of `demo_score.dart`, enters a note on a tap, selects a note on a tap on it, zooms through the controller, and plays through `ScorePlayer` with a tempo slider. Two switches under the sheet turn off the bars and the beams that entry adds by itself. A row of actions works on the selected notes, and `example/lib/selection_actions.dart` builds it as one table.

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
