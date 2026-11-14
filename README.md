# khuur_sheet_music

Sheet music for Flutter. `SheetView` shows a `Score` as a scrolling sheet. An app edits the score through an `EditSession`, and `ScorePlayer` plays it over MIDI while the sheet follows the sound.

One import gives the score model, the view and the player.

```dart
import 'package:khuur_sheet_music/khuur_sheet_music.dart';
```

The package is not on pub.dev. Depend on the `main` branch of the repository through git.

```yaml
dependencies:
  khuur_sheet_music:
    git:
      url: https://github.com/Tseku210/khuur_sheet_music
      ref: main
```

`pubspec.lock` keeps the commit that pub got, and `flutter pub upgrade khuur_sheet_music` moves it to the newest commit on `main`. To work on the package and an app together, depend on a checkout by path, as `example/pubspec.yaml` does. The package needs Dart 3.13 and Flutter 3.47 or later.

The sheet takes its colours from the `Theme` of [`material_ui`](https://pub.dev/packages/material_ui), the package that replaces `package:flutter/material.dart`. The two libraries keep separate themes. Under a `MaterialApp` of `flutter/material.dart` the sheet finds no theme and draws in the light default colours. To move an app to `material_ui`, follow the migration steps in the README of `material_ui`.

## Show a score

```dart
SheetView(score: scoreFromJson(jsonDecode(saved)))
```

`SheetView` takes its width from its constraints and scrolls vertically. It draws at 8 logical pixels per staff space times the zoom. Its colours come from the ambient `Theme` of `material_ui`. Give it a new `Score` after each edit, and it lays out only what the edit touched.

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

Entry overwrites by default. A note entered over other notes replaces them. To insert instead, pass `ripple: Ripple.part` to `EnterNote` or `EnterRest`. The new note fills any rest at the cursor first. Then the later music of the part moves forward by the rest of the note's length. `SetValue(event, value, ripple: Ripple.part)` moves the later music by the change in length, and `Erase(selection, ripple: Ripple.part)` pulls it back over what was deleted. A ripple moves every voice and staff of the edited part, and no other part. `Ripple.staff` in place of `Ripple.part` moves every voice of the edited staff and no other staff, so one hand of a piano part is edited without the other. Either ripple stays inside the section that holds the edit. A section ends at any barline but a regular one, a repeat sign, a volta, a rehearsal mark, a segno or coda, a key change or a meter change, and a bar of irregular length such as a pickup is a section of its own. Music pushed past the section's end adds bars before its closing barline, where every staff that did not move rests, and a push that would grow an irregular bar is refused with `WouldCrossBarline`. A pull leaves rests at the end and removes no bars. `Overfill.refuse` still refuses a new note longer than the rest of its bar, but the pushed music is always cut at barlines, and the section always grows to hold it. An app that offers both modes keeps the choice in its own state and passes it with each edit.

`scoreToJson` and `scoreFromJson` save and load a score. `scoreToMusicXml` and `scoreFromMusicXml` write and read MusicXML, and `scoreToMidi` writes a MIDI file of the score as it plays.

## Edit by tap

The app owns the `EditSession`. In this handler a tap on a note or a line selects it, and a tap anywhere else enters a note. A tap on a rest enters a note too. A rest of voice one is the room its bar has left, and `Erase` leaves it as it is, so an editor that selects a rest on a tap offers nothing to do with it and takes no note where a finger most often lands in an empty bar.

```dart
void _onTap(SheetHit hit) {
  final picked = switch (hit.target) {
    ElementOwner(:final ref)
        when _session.score.lookup(ref.event)?.event is ChordEvent =>
      ItemSelection(Seq([ref])),
    SpannerOwner(:final id) => Selection.spanner(id),
    _ => null,
  };
  if (picked != null) {
    setState(() => _session = _session.select(picked));
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

The hit names the staff, the voice, the time and the staff step under the tap, so the app works out none of them. On a note or a rest the time is the start of that note or rest. So this handler enters a note tapped on a rest at the start of the rest, and a note tapped on a bar rest at the start of the bar, though the bar rest is drawn in the middle of it. An app that wants the note where the finger is takes the tap in a `GestureDetector` of its own around the view and asks `SheetController.entryAt`, as the next section does for a held finger. The example app does that.

A line is a slur, a hairpin or another spanner, and `Selection.spanner(id)` selects one. An `ItemSelection` keeps its events and heads in `items` and its lines in `spanners`, so one selection can hold both. The view draws a selected line in the selection style. `Erase` on a selection removes the lines it names and leaves their notes. It clears the notes it names, and it keeps every line it does not name, even one over a cleared note. Undo brings a removed line back. `SheetController.rectsOf(selection)` gives the boxes of a selection, with a box for a line on each system it crosses.

`tapGrid` is the grid a tap snaps to, a sixteenth unless given. With the base of the value being entered, a note starts on a beat of its own value. A tap within a staff space of where a note or a rest of its voice starts takes that start, whatever the grid. A whole note that starts in the middle of a bar, on a finer grid or at such a start, is cut at the beats and the barline, and the model ties the pieces.

The view draws the cursor as a caret. It opens with the cursor's system in view and scrolls that system into view when the cursor moves. To move the cursor from a button, call `_session.moveCursor(CursorMove.nextEvent)`.

`_sheet` is a `SheetController`. To zoom, set its `zoom`, as in `_sheet.zoom *= 1.25`.

## Show where a note will go

A finger hides the place it points at. So a touch editor shows the note under a held finger before it enters one. `SheetView.preview` draws a note that is not in the score, with its head, its stem, its flag and the ledger lines it needs. Nothing in the sheet moves for it. `SheetController.entryAt` tells where a note entered at a point would go.

```dart
Offset? _held;

late final _sheet = SheetController()
  ..addListener(() {
    if (_held != null) setState(() {});
  });

SheetHit? get _heldEntry => switch (_held) {
  final at? => _sheet.entryAt(at, voice: _session.cursor.voice),
  null => null,
};

GestureDetector(
  onLongPressStart: (details) => setState(() => _held = details.localPosition),
  onLongPressMoveUpdate: (details) => setState(() => _held = details.localPosition),
  onLongPressCancel: () => setState(() => _held = null),
  onLongPressEnd: (_) {
    final hit = _heldEntry;
    setState(() => _held = null);
    if (hit != null) _enter(hit);
  },
  child: SheetView(
    score: _session.score,
    controller: _sheet,
    tapGrid: _value.base,
    preview: switch (_heldEntry) {
      final hit? => NotePreview.at(hit, base: _value.base),
      null => null,
    },
  ),
)
```

`_enter` is `_onTap` above without its first lines, the ones that select a note.

The app keeps the place of the finger and asks the controller for the hit each time it builds, and once more when the finger lifts. A hit it kept would go stale. A sheet that scrolls or zooms under a still finger has another place under it, and a new `tapGrid` snaps the same place to another beat. The controller tells its listeners of each, so the listener above builds again while a finger is held.

The controller answers for the sheet on screen, which is a frame behind a score the app has just changed. An app that can take a bar away under a held finger, with an undo say, checks `_session.score.contains(hit.at.measure)` before it enters the note.

`entryAt` gives the hit of `hitTest` without a target. `hitTest` at a note or a rest gives the time of that note or rest, and `entryAt` looks at no drawn mark. A bar rest is drawn in the middle of its bar and starts at the bar's start, so a preview from `hitTest` would stand a long way from the finger. Both snap to `tapGrid` by the same rule.

The preview is the note of its `base` as it stands alone in its bar. A whole note has no stem, a half note and a quarter have one, and an eighth and every shorter value have a flag. The stem goes up for a note under the middle line and down for every other. The preview has no dot and no accidental. A note that is entered may get a beam, or a stem from its voice, that the preview does not show. A drum's note has the head of its kit sound, which `NotePreview.at` takes as `head`. The preview is drawn in the palette's `preview` colour.

`onLongPressCancel` is called when the system takes the pointer of a long press away, also after the press has started. It is called for a tap and a scroll too, which never become a long press. So it clears the hold and enters nothing.

The package has no magnifying glass. The example app puts Flutter's `RawMagnifier` over the sheet beside the finger, in `example/lib/main.dart`. Its glass looks at the middle of `SheetController.rectOfPreview`, which is where the preview is drawn with its stem, its flag and its ledger lines. A long value starts on a beat that can be far from the finger, and a glass that looked at the finger would miss the note. A zoomed note can be taller than the glass shows, and the example then keeps the head in the glass.

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

Playback runs on Android and iOS, through FluidSynth from [`khuur_synth`](https://github.com/Tseku210/khuur_synth). On other platforms the future of `play` fails with `SynthUnavailable`.

### Supply a SoundFont

The package bundles no SoundFont, because Flutter ships every asset of a package to every app that uses the package. Declare an `.sf2` file in your app's `pubspec.yaml` and pass its asset key as an `AssetSoundFont`. For a file your app downloaded, pass `FileSoundFont('/absolute/path.sf2')`.

Each part plays the program and the bank of its `Instrument`, so the SoundFont needs every program the score names.

To play an instrument from a SoundFont of its own, pass `instrumentSoundFonts`, a map from `Instrument.key` to a SoundFont. A part whose instrument is not in the map plays from `soundFont`.

```dart
late final _player = ScorePlayer(
  soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
  instrumentSoundFonts: const {
    'cello': AssetSoundFont('assets/soundfonts/cello.sf2'),
  },
  vsync: this,
);
```

Here the piano part plays from `piano.sf2` and the cello part from `cello.sf2`. The player loads a SoundFont when the first `play` that needs it starts, and loads it only once, also when two instruments name it. A SoundFont that no unmuted part of the score needs is not loaded. If one SoundFont does not load, the future of `play` fails, and the next `play` tries that SoundFont again. The map is not part of the score, because a saved score keeps its instruments and not the files they play from.

The map can change between plays. Set `instrumentSoundFonts` to a new map, for example once a better SoundFont an app downloaded is on the device, and the next `play` plays from it.

The example app ships a 57 MB piano, `example/assets/soundfonts/piano.sf2`. It is [Upright Piano KW](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html#UprightKW) from FreePats, a Kawai upright sampled in stereo at two loudnesses and released under CC0. Its readme and license are next to it. FreePats also has a 9.5 MB version in mono at one loudness, for an app that has to stay small.

### Add reverb and set the gain

The player plays through a `SynthOutput` with no reverb. To play with one, pass the output yourself.

```dart
late final _player = ScorePlayer(
  soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
  vsync: this,
  output: SynthOutput(
    reverb: const Reverb(roomSize: 0.5, level: 0.3),
  ),
);
```

`Reverb` takes FluidSynth's own numbers, so they sound the same on Android and iOS. `Reverb()` is FluidSynth's default reverb.

The output also takes a `gain`, how loud FluidSynth plays, from 0 to 10. It is `SynthOutput.defaultGain`, 0.8, unless given. At 0.8 the piano of GeneralUser GS 2.0.3 measures about -24 LUFS. FluidSynth's own default, 0.2, plays it 12 dB quieter.

The reverb can change between plays. Keep the output, and set `reverb` on it. A new reverb sounds from the next note.

```dart
final _output = SynthOutput();
late final _player = ScorePlayer(
  soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
  vsync: this,
  output: _output,
);

void _playWet(Score score) {
  _output.reverb = const Reverb(roomSize: 0.5, level: 0.3);
  _player.play(score);
}
```

Each `SynthOutput` is a synthesizer of its own, so two outputs share no reverb, gain or channel. An output opens the device's audio as each play starts, and closes it once the last note has rung out after the score ends or the player stops. A pause keeps it open. On iOS the output sets the audio session to playback as it opens the audio, so it plays also after the app recorded.

To play while the app records, as when it listens to the microphone, open the synth with `AudioSessionPolicy.playAndRecord`, which the package exports. The synth then keeps the recording's `.playAndRecord` session, so the input stays open.

```dart
final _output = SynthOutput(
  open: () => Synth.open(session: AudioSessionPolicy.playAndRecord),
);
```

Each SoundFont takes 16 of FluidSynth's 256 channels, so one output plays from at most 16 SoundFonts.

`output` also takes your own `MidiOutput`, to play through another synthesizer. The player calls its `rest` when no note comes before the next `program`, which is when the score ends, the player stops or a play fails. An output that sounds through a device can let the device go there.

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
| `selection` | `SheetHighlight` | The selected notes, lines and ranges. |
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
| `ink` | The colour the marked item is drawn in. A selected or sounding event is the whole chord or rest, with its stem, accidentals and dots. One selected note of a chord is its head alone. A selected slur, hairpin or other line is the whole line. A selected range has a box and no ink. |

A `SheetLine` has a `color` and a `width`, and a width of zero draws no line. Every length is in staff spaces, so a box and a line grow with the zoom. A width or a radius under zero fails an `assert`, so only a debug build refuses it. In a release build a width under zero draws no line and no border. A radius under zero goes to Flutter's `RRect` as it is. Flutter checks it in a debug build only and gives it no meaning, so do not pass one.

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
| `justify`, `justifyLastSystemFrom` | Whether systems are stretched to the full width, and how full the last system must be before it is. With `justify: false` every system keeps its natural width, so a bar added at the end never moves the bars before it, as an editor needs. |
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

## Draw the sheet's glyphs in your own widgets

A palette or a toolbar can show a value with the glyph the sheet engraves it with. Each function below returns the `Glyph` of a value, and `fingeringGlyphs` returns a list of them. The sheet takes its glyph for that value from the same function. `flutterFamily` names the font the sheet draws in.

| Function | Glyph |
|---|---|
| `noteGlyph(DurationBase)` | The note as one glyph, stem up with its flags, as a tempo mark prints it. Each dot is a `Glyph.metAugmentationDot`. |
| `restGlyph(DurationBase)` | The rest. Each dot is a `Glyph.augmentationDot`. |
| `accidentalGlyph(Alter, QuarterToneGlyphs)` | The accidental. The family changes only the quarter-tone ones. |
| `dynamicGlyph(Dynamic)` | The dynamic. |
| `bowingGlyph(Bowing)` | The up-bow or down-bow mark. |
| `fingeringGlyphs(int)` | The digits of a finger number, left to right. |

```dart
Text(
  String.fromCharCode(restGlyph(DurationBase.quarter).codepoint),
  style: TextStyle(
    fontFamily: SmuflFont.bravura.flutterFamily,
    fontSize: 24,
  ),
)
```

A glyph's origin is on the text's baseline, and one em is four staff spaces. `SmuflFont.bravura[glyph]` gives the glyph's box and advance in staff spaces.

## Names that Flutter also declares

The library exports all of the score model, and two of the model's names are also names in Flutter. They are `Interval` and `Step`. A file that imports both libraries and uses either name does not compile. The analyzer reports `ambiguous_import`.

In a file that needs Flutter's names, hide the model's.

```dart
import 'package:khuur_sheet_music/khuur_sheet_music.dart' hide Interval, Step;
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
flutter run
```

The example runs on Android and iOS. It is one page, `example/lib/main.dart`. It shows the tune of `demo_score.dart`, enters a note on a tap, selects a note, a slur or a hairpin on a tap on it, zooms through the controller, and plays through `ScorePlayer` with a tempo slider. Two switches under the sheet turn off the bars and the beams that entry adds by itself. A row of actions works on the selected notes, and `example/lib/selection_actions.dart` builds it as one table.

## Work on the package

The repository is a pub workspace of three packages. `packages/score_model` is the score model, `packages/score_layout` is the layout engine, and the root package is the Flutter view and the player. Both packages under `packages/` are pure Dart.

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

## Used by

[Khuur](https://github.com/Tseku210/khuur_app) is the first app that uses the library.
