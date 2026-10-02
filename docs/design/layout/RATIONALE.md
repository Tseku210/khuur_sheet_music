# Layout engine and painter

The synthesized design. Its base is candidate C, with grafts from candidates A and B (see "Synthesis decision"). The sketch is in [sketch/](sketch/). It is two sibling packages that type-check. [sketch/score_layout/](sketch/score_layout/) is the pure-Dart engine and mirrors `packages/score_layout`. [sketch/simple_sheet_music/](sketch/simple_sheet_music/) is the Flutter shell and mirrors the rewritten `lib/`. [sketch/simple_sheet_music/example/usage.dart](sketch/simple_sheet_music/example/usage.dart) holds the call sites below.

## Problem

The rewrite needs a layout engine and painter that read the immutable `score_model` and replace the fused engine in `lib/`. The old engine computes layout during build, scales the score to fit a box, mixes pixel and font units, records positions while painting, and lays out again on every highlight tick ([grounding.md](grounding.md), "Old engine: what to keep and what to drop").

The new engine has to meet several demands at once.
- A one-note edit in a 500-bar, 4-staff score must not lay out the whole score.
- Line breaking needs every bar's width before any system exists. Courtesy and system-start signatures change those widths.
- Painting, hit testing, the cursor, the selection and playback all need the same geometry. Cursor moves and playback ticks must not cause a relayout.

These constraints from the grounding shape the design:
- `Score.changesSince` diffs by identity. It reports bars to relay out, but it never reports a width change, because the model cannot know widths. Detecting width changes is layout's job (grounding A15, B4).
- Only `dart:ui` can measure text. Glyph metrics are pure numbers in staff spaces.
- Fonts are SIL OFL 1.1 with a Reserved Font Name. Every package asset ships to every consuming app.
- Targets are Android, iOS and macOS. `flutter analyze` must stay clean.
- The old public API is replaced. `score_model` gains three small read helpers (see Model additions) and is otherwise unchanged.

## Usage (caller's view)

### README quickstart

```dart
import 'package:simple_sheet_music/simple_sheet_music.dart';

// One import gives the score model and the view.
SheetView(score: scoreFromJson(jsonDecode(saved)))
```

`SheetView` takes its width from its constraints and scrolls vertically. It draws at 8 logical pixels per staff space times the zoom. Its colours come from the ambient `Theme`. Give it a new `Score` after each edit, and it lays out only what the edit touched.

### Call site 1: an editor

The app owns the `EditSession`. A tap on a note selects it. A tap anywhere else enters a note there.

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
      setState(() => _session = session);   // the sheet relays out 3 bars
    case Refused(:final reason):
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$reason')));
  }
}

SheetView(
  score: _session.score,
  cursor: _session.cursor,          // caret; scrolled into view when it moves
  selection: _session.selection,
  controller: _sheet,               // _sheet.zoom *= 1.25
  onTap: _onTap,
)
```

The hit names the voice, so the app does not look it up. The view asks the hit test about the cursor's voice.

### Call site 2: playback

The player publishes its position. The sheet highlights the sounding events and moves a playhead. The play button reads the player's status, so the app tracks no play state of its own.

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

Slider(value: _player.tempoScale, onChanged: (v) => setState(() => _player.tempoScale = v))
```

### Call site 3: the app's own overlay, and export

The controller reports geometry in the view's local pixels, with scrolling applied. An app can place its own widgets over the sheet, such as a loupe or a delete badge.

```dart
ListenableBuilder(
  listenable: _sheet,
  builder: (context, child) {
    final rect = switch (session.selection.singleEvent) {
      final event? => _sheet.rectOf(event),
      null => null,
    };
    return Stack(children: [
      child!,
      if (rect != null)
        Positioned(left: rect.right, top: rect.top - 32, child: deleteButton),
    ]);
  },
  child: SheetView(score: session.score, selection: session.selection, controller: _sheet),
)

final image = await _sheet.toImage(pixelRatio: 3);
```

### What replaces the API the example app uses today

| Today | Replacement |
|---|---|
| `SimpleSheetMusic(measures, width, height, ...)` | `SheetView(score: ...)`, sized by constraints, scrolling |
| `Measure([...], isNewLine:)` | A `Score` built with `Score.blank` and edits, or loaded with `scoreFromJson`. `isNewLine` becomes `SetBreak(id, LayoutBreak.system)` |
| `Clef.treble()`, `KeySignature.dMajor()`, `TimeSignature.fourFour()` | `SetClef`, `SetKey`, `SetMeter`, or `Score.blank(key:, meter:)` |
| `Note(Pitch.a4, ...)`, `ChordNote`, `Rest` | `EnterNote`, `AddToChord`, `EnterRest` |
| `GlobalKey<SimpleSheetMusicState>` with `playMidi`, `pauseMidi`, `stopMidi`, `setTempo(int)` | `ScorePlayer.play`, `pause`, `resume`, `stop`, `tempoScale`, `status` |
| `highlightColor` | `SheetPalette.playback` |
| `onTap(symbol, offset)` | `onTap(SheetHit)` |
| `FontType` | `EngravingStyle.font` (`SmuflFont`) |
| `MidiPlayer`, `MidiPlayerStatus` | `ScorePlayer`, `PlayerStatus` |
| `SoundFont`, `AssetSoundFont`, `FileSoundFont` | Unchanged |
| Per-symbol `color` | `SheetView.tints` |
| `debug`, `GlyphMetadata`, `GlyphPath`, `MeasureMetrics` exports | Deleted with nothing in their place |

The example app's `midi_example.dart` is rewritten against the table. It builds its tune from `Score.blank` and a list of edits.

## Shape

### Module map

```
packages/score_model/        gains the additions B1, B2b, B2c, B3 and B4 below
packages/score_layout/       pure Dart, no Flutter; depends on score_model
  sheet_layout.dart          SheetLayout: the entry point, the cache, all geometry queries; LayoutDelta
  bar_layout.dart            BarLayout, BarWidths, layoutBar (internal)
  breaking.dart              BreakUnit, foldBars, SystemKey, SystemPlan, breakSystems, planSystem (internal)
  assembly.dart              assembleSystem, frameUnits (internal)
  spacing.dart               Slice, sliceTimes, spaceSlices, stretchFor, sliceXs (internal)
  chords.dart                planChord, placeChord, graceItems, placeRest, placeRestRun (internal)
  beams.dart                 beamStemSides, planBeam, placeBeam (internal)
  marks.dart                 markReach, articulationItems, ornamentItems, stringMarkItems,
                             directionItems, systemMarkItems, tupletStubs, placeTuplet (internal)
  signatures.dart            barHeads, clefChangeItems, placeBarlines, braceWidth, systemLead, placeLead
                             (internal)
  spanners.dart              tieEnds, placeTies, spannerPieces, pieceStart, pieceEnd, curveSide, placeSpanners,
                             voltaStub, placeVoltas, curveBetween (internal)
  lyrics.dart                lyricsOf, BarLyrics, LyricCarry, lyricRows, placeLyrics (internal)
  bar_space.dart             BarAnchor, BarItem, BarFrame, Skyline, Side (internal)
  system_layout.dart         SystemLayout, PlacedBar, PlacedStaff, TimeAxis, VoiceTimes
  drawable.dart              Drawable (sealed), Owner (sealed), InkRole
  hit.dart                   SheetHit; entryPoints, snapTime (internal)
  glyphs.dart                Glyph (222 values), GlyphAnchor, GlyphMetrics, EngravingDefaults
  smufl_font.dart            SmuflFont
  smufl_metadata.dart        readSmuflMetadata, the one reader of a font's metadata (internal)
  bravura.g.dart             generated: the Bravura metrics table and engraving defaults
  geometry.dart              SpPoint, Box, yOfStep, stepAtY, staffHeight
  style.dart                 EngravingStyle, SpacingPolicy, the policy enums
  text.dart                  TextMeasurer (port), TextSpec, TextRole
  model_additions.dart       sketch only: stand-ins for B1, B2b and B2c. The package never has this file
  tool/generate_bravura.dart writes bravura.g.dart from the font's metadata
lib/ (simple_sheet_music)    Flutter shell; depends on both packages and flutter_midi_pro
  sheet_view.dart            SheetView, SheetController
  sheet_palette.dart         SheetPalette
  painting.dart              SheetScale, GlyphPainter, HeaderPainter, SystemPainter, OverlayPainter (internal)
  paragraph_measurer.dart    ParagraphMeasurer implements TextMeasurer (internal)
  score_player.dart          ScorePlayer, PlayerStatus, PlaybackPosition
  midi_output.dart           MidiOutput, FlutterMidiOutput (internal)
  sound_font.dart            unchanged
fonts/Bravura.otf, fonts/OFL.txt
```

Everything in `lib/src/` today is deleted in the same change that adds this, along with the old tests in `test/`, the four SVG and JSON assets, and the `svg_path_parser`, `xml` and `uuid` dependencies (per `outcome-oriented-execution`). The root `pubspec.yaml` raises its SDK floor to ^3.13.0, adds `packages/score_layout` to the workspace, and declares the font.

The engine's files are split by notation concern, not by stage. Each concern file owns both halves of its notation, which are what a bar decides alone and what a system draws from it. `layoutBar` and `assembleSystem` only call them in order.

### Data structures

The engine is built around five immutable values. Each has one owner and one reason to change.

- **`BarLayout`**, one per `MeasureId`. This is the unit of the cache. `layoutBar(view, style, text)` builds it from the bar's `MeasureView`, the style and the text measurer, and from nothing else. It takes no `Score` and keeps no view. So it stays valid exactly as long as `changesSince` leaves its bar out of `relayout`. It holds:
  - time slices with spring ideals and rods;
  - items fixed to a slice and a staff;
  - three head variants (inline, system start, courtesy);
  - beam plans and tuplet stubs;
  - a stub for every piece that crosses the bar (tie ends, spanner pieces and the volta flag), each with resolved anchors and the room it reserved;
  - per staff, how far the bar reaches above and below, cross-bar pieces included;
  - per lyric lane, what the lane does at the bar's first event and what it leaves open at its end.
  It holds no bar number, x offset or neighbour. The line-dependent choices are stored in every variant and chosen later. This is the invariant the cache rests on, and the type has no field that could break it.
- **`BarWidths`**. Five numbers per bar, compared by value. They are the only thing line breaking reads.
- **`SystemPlan`**, one per system, made at breaking time. It holds the system's `SystemKey`, its stretch, its staff tops, its lyric rows and its height. Everything in it comes from the bars' widths and extents. No drawable is needed to make one, so the sheet knows every system's place before any system is assembled.
- **`SystemLayout`**. Drawables in system space, placed bars with a `TimeAxis`, and placed staves. It is assembled from a plan the first time someone asks for the system, and kept by the plan's key. It is shared by painting, hit testing and every overlay. Identity is the painter's cache key.
- **`SheetLayout`**. The plans, their y offsets by prefix sum, the header, a `LayoutDelta` and the memo of assembled systems. It is the one entry point (`SheetLayout(...)` and `update(score, {width})`) and the one place geometry queries live. It has no public list of systems. It has `systemCount`, `tops`, `heightOf(i)` and `systemAt(i)`.

Drawables form a sealed set of `GlyphDraw`, `LineDraw`, `PolygonDraw`, `CurveDraw`, `GlyphRunDraw` and `TextDraw`. The painter's switch over them is exhaustive, so a new kind fails compilation until it is painted (per `type-system-discipline`). Each drawable carries an `Owner?`, which is `ElementOwner(ElementRef)` or `SpannerOwner(SpannerId)`, plus an `InkRole`. Ownership is a sum type, not two optional fields, so a drawable cannot belong to a note and a spanner at once. Drawables are values and compare by value, which the tests and the painter's label comparison rely on.

### Data flow

```
EditSession.run ─► Score ─► SheetView ─► SheetLayout.update(score, width:)
   changesSince ─► layoutBar for the relayout ids                       (L1)
   ─► breakSystems: starts resumed from the first dirty bar             (L2)
                    one SystemPlan per system, reused by SystemKey      (L3)
   ─► tops by prefix sum of planned heights, delta       no system is assembled
SheetView ─► header tile, then a SliverVariedExtentList of system tiles (extent from the plan)
   tile = Stack
   ├─ RepaintBoundary ─ CustomPaint(SystemPainter)   systemAt(i): assembled on first use, kept by key
   └─ CustomPaint(OverlayPainter)                    cursor, selection, tints as values; listens to playback
tap ─► SheetScale.toSheet ─► SheetLayout.hitTest ─► SheetHit ─► onTap
```

### Decision 1. Where layout lives

Layout lives in a new pure-Dart workspace package, `packages/score_layout`. The Flutter package `lib/` is a thin shell around it. The shell holds the widget, slivers, painters, gestures, the paragraph-backed text measurer and the player.

The reasons:
- The engine is pure functions over immutable values (per `boundary-discipline`). Tests run with `dart test` on any host, with no widget binding and no device.
- The package boundary also enforces the units decision. The engine cannot name `Offset`, `Rect`, `Paint` or a pixel, because it does not depend on Flutter. The sketch proves this, since `sketch/score_layout` resolves and analyzes without Flutter.
- The only thing the engine needs from the platform is text extents. They come through a one-method port, `TextMeasurer.measure(String, TextSpec)`.

A render-object tree and an in-`lib/` Flutter-typed engine were both considered (see Alternatives).

### Decision 2. The glyph source

The package ships the unmodified Bravura 1.392 OTF as a package font (`fonts/Bravura.otf`, 512,924 bytes, recovered with `git show 1620e25^:assets/Bravura.otf`). It ships `OFL.txt` beside it and registers the license with `LicenseRegistry`. Glyphs are drawn as text. Metrics come from a const Dart table that `tool/generate_bravura.dart` writes from `bravura_metadata.json`.

The reasons:
- **License.** Shipping the unmodified file avoids the Modified Version reading that the converted SVGs carry under OFL clause 3. A scratch probe confirmed the font's facts:
  - version 1.392, matching the metadata the repo already has;
  - "Bravura" in name IDs 1 and 4;
  - the OFL URL in name ID 14;
  - CFF outlines;
  - all 222 codepoints of the `Glyph` enum present in its cmap.
  The generated metrics table is not the font. It holds numbers from the metadata, so the font itself stays unmodified.
- **Size.** Package assets drop from 4,251,157 bytes (two SVGs, two JSONs) to about 517 KB (the OTF plus the license). The metadata JSON is a build input in `tool/`, not a runtime asset.
- **Cost.** There is no runtime parse. A declared package font loads before the first frame. Metrics are const Dart, so the first layout is synchronous. The old engine parsed the SVG in 59 ms cold on every widget instance (grounding, Glyph sources).
- **Placement.** A glyph is a `dart:ui` paragraph, cached per codepoint, pixel size and colour. It is drawn at `origin.y - paragraph.alphabeticBaseline` with a font size of 4 staff spaces. The SMuFL origin is the baseline, so there is no magic offset. This is the piece upstream never tried before `1620e25`, because the metadata arrived in that same commit.
- **Petaluma** is dropped. Its SVG is a convertio conversion missing 349 optional glyphs, every ligature, and the small glyphs graces need. An app that wants another SMuFL font declares it and passes `SmuflFont.fromMetadata(family:, metadata:)`. That parse happens at the boundary, applies the generator's checks, and lists every failure at once.

**The pipeline.** The sketch holds the real thing, not a sample.
- `Glyph` is an enum of 222 values. Each value's name is its SMuFL name and each carries its codepoint.
- `GlyphAnchor` has the 19 anchors the metadata uses on those glyphs. `EngravingDefaults` has the 28 numeric engraving defaults.
- `tool/generate_bravura.dart` writes `bravura.g.dart`. It fails when a `Glyph` has no box, when a `Glyph` has no advance, when a glyph carries an anchor `GlyphAnchor` lacks, and when the metadata's numeric engraving defaults do not match `EngravingDefaults` field for field. So the enum, the class and the font cannot drift apart silently.
- The metadata is in staff spaces already. The generator flips y once, into the y-down layout frame.
- The table was generated in this worktree and is committed. A rerun reproduces it byte for byte.

**213 and 222.** Candidate C wrote "213 single codepoints" where [glyphs.md](glyphs.md) says 222. Both numbers count single codepoints, and no glyph in either is a ligature or an alternate.
- glyphs.md names 222 codepoints. The model can need 220 of them. The other two, `breathMarkComma` (U+E4CE) and `caesura` (U+E4D1), are listed under "Not in the model".
- C's 213 came from a pattern that read one codepoint per mention. It missed the seven rests from U+E4E3 to U+E4E9, which glyphs.md writes as "restDoubleWhole E4E2 through rest128th E4EA". With them the count is 220.
- The `Glyph` enum has 222 values. They are those 220 plus U+E272 and U+E273, the naturals with an arrow, which complete the Gould arrow family that `QuarterToneGlyphs.gouldArrows` (C4) selects. That this equals glyphs.md's total is a coincidence.
- Every one of the 222 is one codepoint in SMuFL's primary range, U+E000 to U+F3FF. The probe found all 222 in the unmodified OTF's cmap, and the generator found a box and an advance for each. So every `Glyph` is drawn the same way, as one codepoint of text.
- glyphs.md's remark that ligatures are "only reachable by name" is about the SVG font, where a ligature's `unicode` attribute is a component sequence. The metadata gives every ligature and alternate its own private-use codepoint, and the probe found all 201 ligature codepoints and all 518 optional codepoints in the OTF's cmap. So the cmap can be assumed to hold them, and a ligature or alternate added to `Glyph` later is still one codepoint. The enum needs none today. Grace notes are the normal glyphs at `graceScale`, not the small alternates.
- The placement gate iterates `Glyph.values`, so it covers whatever the enum holds.

**The placement gate.** Drawing music glyphs through the text stack is the one unproven piece every candidate shared. So it is proved first (decision 10, gate 1). Every `Glyph` is drawn from the unmodified OTF through `GlyphPainter`, at the sizes the view draws at, and its painted ink box is compared with its box in the generated table. Nothing else in the engine gets a body until that passes on the host, on Android and on iOS. `GlyphPainter` is the whole seam for the glyph source. If the gate fails, a path painter replaces that one class. A probe has already run the gate's measurement on the host for six glyphs. It found a rounded baseline in the paragraph, which the painter now corrects, and a whole-pixel snap in the rasteriser, which stays (decision 10).

### Decision 3. Units and coordinate spaces

The engine works only in staff spaces, with y down. There are three origins, and every stored value says which one it uses:
- **Bar space.** x is relative to a slice. y is relative to the staff's top line, with `y = (8 - step) / 2`. That formula is in one function, `yOfStep`, which the bar layout, `PlacedStaff` and the hit test all call.
- **System space.** The origin is the system band's top-left.
- **Sheet space.** Systems are stacked below the header.

Font units never reach runtime code. The metadata is in staff spaces, and the generator flips y once, so no runtime code negates y. Text sizes are in staff spaces too (`TextSpec.size`). So a bar's layout is the same at every zoom, and zoom never invalidates a `BarLayout`.

Pixels exist only in the Flutter shell. The single conversion is `SheetScale`, with `px = origin + sp * spacePx`, where `spacePx = SheetView.staffSpace * controller.zoom` and `origin` folds in padding and scroll. Every pixel value comes from it. The old engine's unit mix-up, pixel margins added to font-unit widths, would need a second conversion site, and there is none.

### Decision 4. The cache

| Level | What | Key | Invalidated by |
|---|---|---|---|
| L1 | `BarLayout` per bar | `MeasureId` | `ScoreChanges.relayout` rebuilds it, `removed` drops it, a style change or a late font drops all |
| L2 | System starts (`List<MeasureId>`) | the previous starts and the units' `BarWidths` | a dirty unit (re-run from the system that could see it until the starts resync), a width change in staff spaces or a new part list (full re-run over cached widths) |
| L3 | `SystemPlan`, and the `SystemLayout` assembled from it on first use | `SystemKey`, which holds its bars by identity, the next system's first bar by identity, the width, the lead by identity, first, last, and the lyric carry at both ends by value | any key field. A memo entry is dropped when no system of the new layout has its key |
| L4 | `SheetLayout` | none. It is recomputed per update | tops are O(systems). A bar-number label is made when its tile asks and is compared by value. The header is reused while the width and `score.meta` are unchanged, since `changesSince` ignores meta |
| L5 | Each system's raster | a `RepaintBoundary` around the system's `CustomPaint` | `SystemPainter.shouldRepaint`, on the system's identity, the label's value, the glyph painter's identity, the palette and the scale |

Building or updating a layout assembles nothing. A system's height and staff tops come from its bars' extents (`planSystem`), never from assembled drawables. `systemAt(i)` assembles system i the first time it is asked for and memoizes it by `SystemKey`. `update` carries the memo over for every key that is still some system's key, so a kept system is the same object and the painter keeps its picture. A query on a system that is not assembled (`hitTest`, `boundsOf`, `caretOf`) assembles that one system. There is no eviction. The memo holds at most one assembled system per system of the current layout.

The overlay is its own layer. Each system tile is a `Stack`. Its first child is `RepaintBoundary(CustomPaint(painter: SystemPainter))`. Its second child is `CustomPaint(painter: OverlayPainter)`. A repaint of the overlay composites the base layer as it is. Candidate C put the overlay in `foregroundPainter` of the base's own `CustomPaint`. A `CustomPaint` paints both of its painters together, so there every cursor move and every playback tick re-recorded every visible system.

Per event:
- **Resize.** The width in staff spaces changes. Every L1 entry is reused. L2 runs fully over cached widths. Every key holds the width, so every plan is made again, which is sums and maxima over cached bars. The memo empties. Only the systems on screen are assembled, as their tiles ask.
- **Zoom.** Same as a resize, since the width in staff spaces is the pixel width over `spacePx`. Every new `controller.zoom` breaks lines again at the next frame, and scroll anchoring keeps the anchor bar in place. The view has no pinch gesture of its own. An app that zooms by pinch sets the zoom when its gesture ends (see "Left out of the first version").
- **Theme.** The palette changes. Visible systems re-record their picture. Nothing is laid out.
- **Cursor move or selection.** The app rebuilds the view with a new cursor. `update` returns the same layout. Each visible `OverlayPainter` repaints, because the cursor is one of its values. No `SystemPainter` repaints. With `followCursor`, the view scrolls if needed.
- **Playback tick.** No build runs. The visible `OverlayPainter`s listen to the playback listenable and repaint. No `SystemPainter` repaints.
- **Scroll.** A tile entering the viewport asks `systemAt(i)`, which assembles the system once. A tile that left and comes back gets the memoized system and re-records its picture. The view itself builds nothing on a scroll. It listens to the controller's zoom only, and a scroll notifies the app's listeners of the controller.
- **Style change.** A fresh `SheetLayout` and a fresh `GlyphPainter` replace the old ones. Everything is laid out again, and scroll anchoring keeps the anchor bar in place.
- **Late font.** Flutter reports every font registered at run time, whoever loaded it. The view handles a burst of them once, after the frame. A fresh measurer measures again every text the old one was asked for. Only when an extent differs does a fresh `SheetLayout` replace the old one. The glyph painter is replaced either way, which repaints the systems on screen and lays nothing out.

**Trace of one note entered in bar 250 of a 500-bar, 4-staff score.** Assume four bars per system, so 125 systems. Counting from 0, system 62 holds m249 to m252 and system 61 ends with m248.
1. `session.run(EnterNote(...))` returns `Applied`. The app calls `setState` with the new session.
2. `SheetView` records its scroll anchor and calls `layout.update(newScore, width: sameWidth)`.
3. `newScore.changesSince(oldScore)` walks 500 columns by identity. It returns `relayout {m249, m250, m251}`, `removed {}` and `reflow false`. The neighbours are included because a view reads them.
4. L1. 497 `BarLayout`s are reused by reference. Three `measureView` calls and three `layoutBar` calls run, each reading one bar of 4 staves. All three results are new objects. m249 and m251 usually come out with the same content as before, but a key compares bars by identity, so they count as changed.
5. L2. Each bar's `BarWidths` is compared with its old value.
   - If all are equal, which is typical when a note replaces a rest of the same length, no unit is dirty. `breakSystems` returns the old list of starts, the same object. Nothing is rebroken.
   - If m250 grew, m250 is dirty. Greedy resumes at the start of the system that holds m249, the bar before the first dirty one, and stops at the first new start past m250 that was an old start. Systems 0 to 61 cannot move.
6. L3. 125 keys are built and looked up among the old plans. Two keys are new. System 62 holds the three new bars. System 61 names m249 as its `next`, because m249 starts the system after it. Two plans are made, and 123 are reused by reference. In general up to three systems hold one of the three bars, when the bars straddle system ends, and one more key changes when m249 starts its system. If a lyric lane's carry-out changed, later keys change too, until the first system whose carry-in is equal again.
7. L4. The header is reused. 125 tops are recomputed by prefix sum. The memo keeps every assembled system whose key survived. `delta` reports `relaid {m249, m250, m251}`, `rekeyed {61, 62}` and `rebroke false`.
8. The view restores its scroll anchor. No top above it moved, so the scroll stays.
9. L5. The visible tiles rebuild. `systemAt(62)` assembles system 62, and `systemAt(61)` assembles system 61 if it is on screen. Every other visible tile gets the same `SystemLayout` object as before and a label equal to the one before, so its `shouldRepaint` is false. If neither system is on screen, nothing is assembled and no base layer repaints.

The total is 3 bar layouts, 2 system plans, at most 2 system assemblies, and work linear in the bar count that only compares. That is about 500 identity checks, 500 width comparisons and 125 key lookups. No other bar is measured.

### Decision 5. Spacing and line breaking

**Spacing** is a spring and rod model inside each bar (`spacing.dart`, `SpacingPolicy`).
- Slices are the union of onsets over every visible staff and voice (`sliceTimes`). Graces get a slot before their principal. The last slice is the bar's end, whose rod is the end barline's width.
- The spring after slice i follows the shortest note d sounding at that slice, on an absolute scale (`spaceSlices`). Its ideal is `quarterSpace * ratio^log2(d / quarter) * (Δt / d)`. This is Gourlay's rule, with the shortest-note reference made local and absolute. It depends on nothing outside the bar, which is what makes a bar cacheable alone.
- Rods are the right reach of a slice plus the left reach of the next (accidentals, dots, flags, lyrics, chord symbols) plus `minGap`. Each concern reports its reach, through `ChordPlan.reach`, `restReach`, `letRingReach`, `lineStartReach`, `markReach` and `Syllable.reach`.
- Justification solves one stretch factor s per system, so that the sum over slices of `max(rod, ideal * s)` fills the width (`stretchFor`, real code). Items move with their slice and never stretch. The last system stays ragged when its natural width is under `justifyLastSystemFrom` (0.75) of the width.

**Line breaking** is greedy first-fit over `BarWidths`, chosen over optimal breaking for stability. With greedy, a system's start depends only on the start before it and on the widths from there. So an edit can never move an earlier system, and the re-run after an edit stops at the first resync. An optimal breaker can reflow the whole score for one wider bar, which defeats the incremental goal and makes the page jump while someone is writing.
- `breakBefore` forces a break. A page break is a system break, because the view has no pages.
- A bar wider than the sheet sits alone and is compressed to its rods.
- With `multiMeasureRests`, a run of rest-only bars is one unit. It is off by default, because an editor needs every bar visible to write into.

`breakSystems` is real code in the sketch.
- **The unit.** Breaking works on a sealed `BreakUnit`. It is a `SingleBar`, or a `RestRun` of rest-only bars that `foldBars` folds when `multiMeasureRests` is on. A unit exposes the same widths, slices, staff extents and edges as a bar, so breaking and planning never ask which kind they hold.
- **Starts are `MeasureId`s, never indices.** An index shifts under an insertion. An id does not.
- **Dirty units.** A unit is dirty when the old layout has no unit starting at its first bar, or when its last bar, its `BarWidths`, its `breakBefore`, the bar before it, the bar after it, or the courtesy width after it differs from before. A bar laid out again with equal widths is not dirty.
- **Resume.** With no dirty unit the old starts stand, as the same list object. Otherwise every old system before the one that holds the unit before the first dirty unit is kept. Greedy resumes at that system's start, because that system is the earliest one whose end decision could read a dirty unit.
- **Stop.** Greedy stops at the first new start that lies past the last dirty unit and was an old start. From there the units, their widths and the start are what they were, so greedy would repeat the old starts, and they are copied.
- **Full re-run.** A new width or a new system lead (a changed part list) skips the resume. Every bar's cached widths are still valid.

The dirty rule had to be made that precise. A scratch run compared resumed breaking with fresh breaking over 12,000 random updates (replace, insert, delete, toggle `breakBefore`, relay with equal widths) and found them equal in starts, keys, stretches and heights. The same run with the courtesy clause removed from the dirty rule failed, because a system's end decision reads the courtesy width of the bar after it. That run becomes test 6.

**Planning** is real code too (`planSystem`). For each system it:
- sums the fixed widths (indent, system head, inline heads, leads, the next bar's courtesy) and solves the stretch for the rest;
- takes, per staff, the largest reach above and below over the system's bars, and widens it by the next bar's courtesy head;
- adds the bar number's measured height above the top staff when `barNumbers` is on;
- adds a lyric row per lane with a syllable in the system or an open carry-in (`lyricRows`);
- stacks the staves and returns the tops and the height.

**A bar's width is known before its system** because a bar stores every width it could take (`BarWidths`):
- `inlineHead`, the changes printed mid-system;
- `systemHead`, the clef, key and meter printed at a system start;
- `courtesy`, the key and meter courtesy the previous system ends with when this bar starts a system;
- `body` and `minBody`.

A system from bar i to bar j is `systemHead(i) + Σ body + Σ inlineHead(i+1..j) + courtesy(j+1) + indent` wide. Breaking reads these sums and never builds a system. That is also why a courtesy width belongs to the system before its bar, and why the resume starts one unit early.

### Decision 6. Cross-bar and cross-system layout

A piece that crosses a barline is decided by the bar and drawn by the system. Each `BarLayout` stores a stub for every piece that passes through it, resolved from its own view alone. `assembleSystem` joins the stubs of consecutive bars and draws each piece inside its own system. Nothing reads another system. Everything a system depends on is in its `SystemKey`.

**The band invariant.** Assembly never draws outside the band its plan reserved, which is the box from (0, 0) to (`plan.width`, `plan.height`). The sheet stacks systems by planned height alone, so a breach would overlap the next system. Three rules keep it:
- A bar reserves room in its staff's `Skyline` for every piece that crosses it. So the bar's extents, and through them the planned height, already hold the piece. The order is fixed. Ties come first, before any mark, since a tie keeps to its heads and reads nothing from the skyline. Then come the marks of each staff, then slurs, then lines by kind, then the system marks over the top staff, then the volta.
- A stub stores both edges of the room it reserved (`SpannerPiece.clear` and `limit`, and for a tie its side and `tieRise`). Assembly reads that room. It does not work it out again.
- A slur has one side for its whole length (`curveSide`, real code). The side comes from the spanner alone. It is above, and below in voices two and four. A side taken from the stems would differ between bars, because a bar sees only its own stems. A slur over a barline between a stems-up bar and a stems-down bar would then have room reserved on neither side (open question C11).
- A curve is fitted into its room (`curveBetween`). A slur's arc is raised until its middle half lies outside the outermost `clear` of its pieces, so it passes over the notes under it. It never passes their outermost `limit`. A tie rises `tieRise` at most. A long slur is therefore flatter than an engraver would draw it.

`assembleSystem` asserts the invariant on every drawable, and test 7 checks it over random scores. Both allow `bandTolerance`, a millionth of a staff space. A slice's x is a sum of stretched springs, so the last barline meets the plan's width only to rounding. A scratch run over 200,000 random systems found the sum past the width in 25.9% of them, by at most 5.7e-14 staff spaces.

- **Ties** (`tieEnds`, `placeTies`). A bar's ties are a sealed set:
  - `TieWithin` has both heads in the bar and is one whole tie;
  - `TieLeaving` has its target in the next bar. The system draws a whole tie when the next bar is on it, and a half tie to its end otherwise;
  - `TieArriving` comes from `StaffView.tiedIn`. It draws only when the bar starts a system, as the incoming half;
  - `TieOpen` has a null `to` and is a let-ring stub.
  A grace tie is drawn inside its own column by `graceItems` (see B5 under Model additions).
- **Slurs, glissandi, trill lines, hairpins, octave, pedal and tempo lines** (`spannerPieces`, `placeSpanners`).
  - A bar makes one `SpannerPiece` per `SpannerSegment`, with `startsHere` and `endsHere`.
  - A piece ends where `pieceEnd` says (real code). It applies the model's two rules to the bar's own view. A slur, glissando or trill line ends on the event sounding at `to` in its voice, as `Score.anchorAt` finds it. A line ends at the end of the voice-one event `to` falls in, as `Score.lineEnd` finds it. So an 8va whose last segment is `from 0, to 0` still runs over the dotted half that starts there, and the bar needs no `Score` to know it.
  - Pieces of one spanner in consecutive bars of a system form one run. A run starts at its anchor when its first piece `startsHere`, and at the system's content start otherwise. It ends the same way.
  - A line is straight across its run, at the outermost baseline its pieces ask for.
  - Octave lines restate "(8va)" on a continuation. Pedal lines use pedal glyphs. Tempo lines print `TempoLine.text`.
- **Voltas** (`voltaStub`, `placeVoltas`). Each bar under a bracket stores a stub with the label and whether the bracket starts, ends or stays open there. The label prints only at the start. A continuation is open at the left.
- **Tuplets** (`tupletStubs`, `placeTuplet`). A tuplet lies inside one bar. The bar stores the number, the bracket's end anchors and its side, and the system draws them at the stretched x.
- **Beams** (`planBeam`, `placeBeam`). The model has no beams across a barline or across staves, so beams stay inside a bar. The bar fixes the end stems and the slope. Assembly places the end stems at their final x and draws inner stems to the line between them, so a stretched system keeps every stem on its beam.
- **Lyric hyphens and extenders** (`lyricsOf`, `lyricRows`, `placeLyrics`). The open state per lane (staff, voice, verse) is a fold over bars, not over assembled systems.
  - A bar stores, per lane, a `LaneStart` (syllable, rest or held note at its first event), a `LaneEnd` (closed, hyphen, extender, or unchanged from before) and whether its first syllable joins a word (`joins`, for `Syllabic.middle` and `Syllabic.end`).
  - `BarLyrics.after(carry)` is the forward step. `breakSystems` folds it over the bars in order, which gives what every bar leaves open.
  - A hyphen joins two syllables of one word. So a second pass, backward, finds the lanes whose next syllable joins a word, and `LyricCarry.closing` drops every hyphen that nothing joins. A word left unfinished draws one hyphen after its syllable and is carried nowhere.
  - Without that pass a `begin` syllable with no successor kept its hyphen open to the end of the score, and that is every state between two typed syllables. A probe put one such syllable in bar 10 of 200. It rekeyed 48 of 50 systems and added a lyric row to 47 of them.
  - Each system's key holds the carry at its start and at its end, compared by value. So a system's lyrics need no other system to be assembled, and a change in one lane rekeys exactly the systems whose carry differs.
  - A one-bar lookahead (`key.next`, each lane's `LaneStart`) decides whether an open extender stops at the system's last note or continues.
  - An extender ends at the last note before the verse's next syllable or a rest (`ExtenderEnd.beforeNextSyllable`, open question C3). It needs no syllable to end at, so with neither after it, it runs to the end of the score. That is right for a final melisma. It also means an extender typed over notes already entered underlines all of them until the next syllable is typed.

### Where each element is drawn

"Bar" means `layoutBar` calls the function and the result is cached with the bar. "System" means `assembleSystem` calls it for an assembled system.

| Element | Stage and function | Source in the model |
|---|---|---|
| Heads, drum heads, ledger lines, accidentals, dots, flags, stems, tremolo strokes | Bar, in `planChord` and `placeChord` | `VoiceView.events`, `StaffView.accidentals`, `NoteHead` |
| Grace notes and grace ties | Bar, in `graceItems` | `ChordEvent.graces`, `GraceChord.notes[i].tie` |
| Rests, measure rests | Bar, in `placeRest` | `RestEvent`, `MeasureRest` |
| Multi-measure rests | Breaking, in `foldBars`. System, in `placeRestRun` | `MeasureView.isRestOnly` |
| Articulations, fermatas | Bar, in `articulationItems` | `ChordEvent` fields |
| Ornaments | Bar, in `ornamentItems` | `ChordEvent` fields |
| Bowing, fingering, string numbers | Bar, in `stringMarkItems` | `ChordEvent` and `PitchedNote` fields |
| Dynamics, text marks, chord symbols | Bar, in `directionItems` | `StaffDirection` |
| Tempo marks, rehearsal marks, segno, coda, fine, jumps | Bar, above the top staff, in `systemMarkItems` | `TempoMark`, `rehearsal`, `NavigationMark`, B2c |
| Lyrics | Bar, in `lyricsOf`. Planning, in `lyricRows`. System, in `placeLyrics`, with hyphens and extenders | `Lyric`, `LyricCarry` |
| Clefs, keys, meters, courtesy signatures | Bar, in `barHeads` (three head variants). System, in `assembleSystem`, which draws the variant its place calls for | `MeasureView` signature fields |
| Clef changes inside a bar | Bar, in `clefChangeItems` | `StaffView.clefChanged`, clef changes |
| Barlines, repeat signs, repeat counts | Bar, as `BarEdges`. System, in `placeBarlines` | `Barline`, `repeatStart`, `RepeatEnd` |
| Beams | Bar, in `beamStemSides` and `planBeam`. System, in `placeBeam` | `BeamGroup`, B2b |
| Tuplet brackets and numbers | Bar, in `tupletStubs`. System, in `placeTuplet` | `TupletView`, `TupletBracket` |
| Ties | Bar, in `tieEnds`. System, in `placeTies` | `TieView`, `StaffView.tiedIn` |
| Slurs, glissandi, trill lines, hairpins, octave, pedal and tempo lines | Bar, in `spannerPieces` and `pieceEnd`. System, in `placeSpanners` | `SpannerSegment`, `StaffView.voices` |
| Voltas | Bar, in `voltaStub`. System, in `placeVoltas` | `voltaStarts`, `voltaEnds`, `Volta` |
| Staff lines | System, in `assembleSystem` | `Staff.lines` |
| Braces, systemic barline, part names | Once per part list, in `systemLead`. System, in `placeLead` | `Part.staves`, `Part.name` |
| Bar numbers | Sheet, in `SheetLayout.labelOf` | B2c |
| Title, subtitle, credits | Sheet, as `SheetLayout.header` | `ScoreMeta` |

### Decision 7. Shared geometry and the hit type

Every reader uses `SystemLayout`:
- `drawables` for painting;
- `bars` (a `TimeAxis` maps any `Moment` to x, piecewise linearly between slices, with the bar end included);
- `staves` (`PlacedStaff.yOf(step)` and `stepAt(y)`);
- `drawablesOf(Owner)`, where an event's drawables include its notes'.

`SheetLayout` answers the queries in sheet space, which are `hitTest`, `boundsOf`, `caretOf`, `selectionBoxes` and `playheadAt`. Each has a per-system form (`caretIn`, `selectionIn`, `playheadIn`) that a system tile's overlay asks for its own system. Nothing records positions while painting. Hit testing and overlay geometry live with the layout that owns the placement, not in separate modules that would repeat the system and bar lookup.

```dart
final class SheetHit {
  final StaffId staff;     // the visible staff nearest the tap
  final VoiceSlot voice;   // the voice of the event under the tap, else the asked voice
  final ScorePoint at;     // a start the model allows in `voice`
  final int staffStep;     // Score.toneForStaffStep convention; 0 = bottom line
  final Owner? target;     // ElementOwner(NoteRef | EventRef) or SpannerOwner
}
```

`voice` is the voice of the note or event under the tap when there is one. Otherwise it is the voice the caller asked about. So a tap on a voice-two note selects in voice two, and the app looks nothing up. `at` is snapped in that same voice. So `VoicePoint(staff: hit.staff, voice: hit.voice, at: hit.at)` is one consistent place, also for a tap on a voice-two rest inside a triplet that voice one does not have.

Snapping works per voice, in this order (`snapTime`, real code):
1. An onset of the hit's voice within one staff space of the tap wins. A tap on a note lands on that note whatever the grid.
2. Otherwise the nearest grid point wins (`entryPoints`, real code). Outside a tuplet the grid is the multiples of `tapGrid` in the bar. Inside a tuplet it is the multiples of `tapGrid` in the tuplet's written time, mapped to sounding time by `duration / written`. A triplet of eighths on a sixteenth grid has six points, a twenty-fourth of a whole note apart. Where a tuplet holds a deeper one, the deeper one's points replace its own.
3. It is never the bar end.

The tuplet rule follows the model. `EnterNote` checks `startProblem` in the tuplet's written time (`lane_writer.dart:324`, `rules.dart:68`), so a start is legal when it lies a whole number of 128ths into the written time. All three candidates snapped to existing tuplet onsets or to the bar's own grid. The first cannot split a triplet member, and the second is refused.

`at` is a legal start. It is not a promise about a note value. Inside a tuplet `EnterNote` refuses a value that runs past the tuplet's end (`WouldSplitTuplet`), at this point as at any other. A scratch run entered seven values at every entry point of four scores. Every point accepted some value. In a triplet of eighths on a sixteenth grid, a sixteenth was accepted at all six points, and a half note at none.

`tapGrid` is a `DurationBase` and defaults to a sixteenth. Its type has no value finer than a 128th, which is the finest start the model accepts.

A one-line staff keeps the five-line step map, with its line at step 4 (C1). `Clef.naturalAt` never reads `Staff.lines`, so a step means the same on every staff.

The target follows the drawable under the point:
- a notehead gives a `NoteRef`;
- a rest, stem or flag gives an `EventRef`;
- a grace head gives its principal's `EventRef`, since graces have no ref;
- an element wins over a spanner;
- a drawable is hit within a finger's reach of its box (`reach`, the view's touch slop in staff spaces), so a stem a tenth of a staff space wide can be hit;
- a slur or a tie is hit near its line, not anywhere in its box. Its box covers every note under the arc, and a tap on the staff there has no target and enters a note.

A point in the gap between two systems belongs to the nearer one. A point up to half a system gap above the first system or below the last belongs to that system, because a band ends where its content does and a ledger position can lie outside it. Only the header above that and the paper below give no hit. A tap on a clef, a key or a time signature snaps to its bar's first point, like a tap on empty staff.

A selection tap reads `target` and never `at`, so it is not snapped to anything.

### Decision 8. The public surface

The app sees five things:
- `SheetView`, a widget that takes the values `score`, `cursor`, `selection`, `tints`, `playback`, `onTap`, `controller`, `style`, `palette`, `staffSpace`, `tapGrid`, `followCursor`, `followPlayback` and `padding`;
- `SheetController`, with zoom, `hitTest(Offset)`, `rectOf`, `caretOf`, `rectsOf`, `ensureVisible`, `systemCount` and `toImage(from:, to:)`, all in the view's local pixels;
- `SheetPalette`, derived from the theme by default;
- `EngravingStyle`, for everything that changes layout;
- `ScorePlayer`.

`simple_sheet_music.dart` re-exports `score_model` and the few `score_layout` types an app names. So one import is enough. `SheetLayout`, `SystemLayout` and `LayoutDelta` are not among them.

**How an app runs an edit and sees the relayout.** It calls `session.run(edit)`. On `Applied` it stores the session with `setState`. `SheetView` receives the new `score` and calls `layout.update(score)`. That call returns the same object when the score is identical, so an unrelated rebuild costs nothing. The app never sees `ScoreChanges`, a cache or a relayout call.

**Scroll anchoring.** An update can move what the user is looking at, through a rebreak or a system above the viewport that changed height. The view keeps one bar in place across every update (`_SheetViewState._anchorIn` and `_keepInPlace`).
- Before the update it records an anchor bar and where the top of that bar's system sits. With `followCursor` on, the anchor is the cursor's bar when any part of its system is in the viewport. Otherwise it is the first bar of the system at the top of the viewport. A cursor the user scrolled away from is no anchor, because holding it still would move what they are reading. `SheetLayout.firstBarOf` names the bar without assembling anything.
- After the update it finds the system that now holds the anchor bar. If that system's top moved, the scroll moves by the same amount, so the system keeps its offset from the viewport top. This covers `delta.rebroke`, a zoom, a resize and a changed height above the viewport with one rule.
- The correction runs before the viewport lays out and does not notify, so the frame paints at the corrected offset.
- The correction holds while the scroll is idle, dragged or flung. A scroll the view animates itself, for `ensureVisible` or to follow playback, writes its own offsets on the next tick. A probe saw a 250 pixel correction undone one frame later. So the view remembers the bar such a scroll is going to and starts it again after a correction.
- A deleted anchor bar leaves the scroll alone.
- The scroll extent is the layout's height from the first frame. A sliver list guesses its extent from the tiles laid out so far, even when every tile's extent is known. A probe saw 9,450 reported for a true 27,450. The tiles' delegate (`_SystemTiles`) reports the sum, and the same probe then reads 27,450 at the top.

Theming is split by effect:
- `SheetPalette` maps each `InkRole` to a colour and holds the overlay colours. It only repaints.
- `EngravingStyle` holds layout policy. It compares by value, and a different style relays out. Its font compares by `SmuflFont ==`, which is the family and the identity of the metrics tables. The bundled Bravura is a const, so it equals itself everywhere. A font from `SmuflFont.fromMetadata` equals only itself, so an app parses once and keeps the font.

The interface is deep. Behind `SheetView(score:)` sit identity diffing, three cache levels, line breaking, justification, cross-system spanners, lazy assembly, scroll anchoring and picture reuse. The controller exists because some app needs (overlays, other gestures, export) cannot be callbacks. Its methods add the pixel and scroll conversion that only the view knows, so none of them is a pass-through.

The controller notifies the app's listeners when a scroll, a zoom or a new layout moves the geometry. The view is not one of those listeners. It listens to the zoom alone, so a scroll frame builds nothing in the view.

`toImage` renders a range of systems. One image cannot hold a long score. A hundred systems at pixel ratio 3 are over 100,000 device pixels tall, far past a GPU texture. A range taller than `SheetController.maxImageHeight` (8,192 device pixels) throws an `ArgumentError`, and an app exports a long score as several images.

### Decision 9. Playback position on screen

The sheet shows both an event highlight and a moving playhead, and follows playback by scrolling (`followPlayback`).
- `ScorePlayer` has one script clock and two readers of it. The clock maps wall time to script seconds from one anchor (`_ScriptClock`). A one-shot timer sleeps until the next note of `notesBetween` and sends it. It needs no frame, so sound goes on when nothing repaints. It does run on the UI isolate, because the plugin's `playNote` takes no timestamp, so a note is late by as long as the isolate is busy when the note is due (see Tradeoffs). The timer also ends playback and wraps a loop, because a ticker is muted while the app's tickers are off. A `Ticker` publishes `PlaybackPosition(seconds, point, sounding)` once per frame. A new `tempoScale`, a pause, a resume and a loop's wrap each move the anchor to the present first. So the position never jumps, the note timer is set again from the same anchor, and the sound and the playhead cannot drift apart.
- Each visible `OverlayPainter` listens to that listenable directly, as its `repaint` argument. A tick marks only the overlays for paint. No widget builds, no state changes, and nothing notifies during a build.
- `sounding` comes from `PlaybackScript.sourcesAt`. The overlay redraws those events' drawables in the playback colour over the base layer. A ref with no drawables is skipped, which covers hidden staves (B3). The base ink stays under the highlight (see Tradeoffs).
- `point` comes from the new `PlaybackScript.pointAt` (B1). The overlay draws the playhead at `TimeAxis.xAtWholeNotes(point.offset)` in the bar of `point.bar`. Its `pass` lets an app show "2nd time".
- The cursor, the selection and the tints are values of the painter and are compared in `shouldRepaint`. They change through a build, not through a notifier.

Neither path lays anything out. A tick costs one overlay repaint per visible system and composites the base layers.

### Decision 10. Gates and first tests

Two gates come before any layout code.

- **Gate 1. Glyph placement.** A `flutter test` on the host draws every value of `Glyph.values` through `GlyphPainter` into an image and compares the painted ink with the glyph's box in the generated table.
  - **The font.** `flutter test` registers no font from a pubspec. A scratch test measured a package font's text at the fallback's width under the bare family, under the `packages/` family and under a family that does not exist. So the test loads the unmodified `Bravura.otf` with a `FontLoader` under exactly the family `GlyphPainter.family` asks for. Every other test that paints a `SheetView` does the same.
  - **The sizes.** 8 and 16 logical pixels per staff space, each at device pixel ratios 1, 2 and 3. Those are the sizes the view draws at. One more run at 64 pixels per staff space checks the table itself.
  - **The origins.** Each glyph is drawn at origins an eighth of a device pixel apart in both directions, because where the origin falls inside a pixel decides the error.
  - **The ink.** The ink box is read by coverage. An edge is the outermost row or column the ink touches, moved in by the part of that pixel the ink leaves empty. The same reader gives 0.00 on every edge of a rectangle drawn with `drawRect`, so it adds no error of its own.
  - **What is checked.** Placement and size, apart, in device pixels.
    - The centre of the ink box is within 1 device pixel of the centre of the table's box vertically, and within 0.5 horizontally.
    - The ink box's width and height are each within 1 device pixel of the table's.
    - At 64 pixels per staff space every edge is within 0.05 staff spaces, which checks the table and the generator's one y flip.

    A rasteriser thickens ink by a fraction of a pixel on every side. That moves edges and leaves the centre. So the centre says where the glyph is, and the size says what the rasteriser did to it. One tolerance on edges cannot tell the two apart.
  - **What a probe already found.** The measurement ran on the macOS host for six glyphs, which were the half and whole rests, the black and whole noteheads, the sharp and the G clef.
    - As first sketched, the painter failed. At the default size the vertical centre was off by 1.07, 1.59 and 1.95 device pixels at ratios 1, 2 and 3, which is up to 0.13 staff spaces.
    - One cause is the paragraph. It draws a line's baseline on the nearest whole logical pixel and reports the baseline unrounded. Bravura's ascent is 2.012 em, so at the default size the reported baseline is 64.38 and the drawn one is 64. Nine font sizes all showed the drawn baseline at the reported one, rounded. `GlyphPainter` now rounds what it subtracts.
    - The other cause is the rasteriser. Glyph ink lands on whole device pixels vertically. Horizontally it is placed to a fraction of a pixel, and the centre is within 0.04.
    - With the rounding, the vertical centre is within 0.83 device pixels and the size within 0.62, at both sizes and all three ratios. At 300 device pixels of font size and above, the engine fills outlines and every edge is within 0.3.
    - So a tolerance of 0.05 staff spaces at the view's sizes could never pass on a text stack. One device pixel is 0.125 staff spaces at ratio 1 and 0.04 at ratio 3.
  - **What the full run found.** Unit 1 ran the gate for all 222 glyphs, under `flutter test` and as a macOS app that takes the font from the package's own declaration.
    - Every glyph passes. The vertical centre is within 1.00 device pixels and the size within 0.77, at the view's sizes. At 64 pixels per staff space every edge is within 0.02 staff spaces.
    - The vertical bound has no margin. The worst glyph, a narrow double flat at 8 pixels per staff space and ratio 3, is 0.998 pixels off. The engine puts ink on whole device pixels, and an origin half way between two can go either way, so the worst case moves by hundredths with where on the canvas the glyph sits. An earlier run with the same glyphs elsewhere in the image read 0.91. A device may read a hair over 1 for the same reason.
    - The horizontal centre is within 0.34 device pixels, not the 0.04 of the six probe glyphs, so that bound is 0.5 and not 0.25. The worst are glyphs pointed on one side, such as the arrow accidentals and the p of a dynamic. The offset is the same number of pixels at 8 and at 300 pixels per staff space, so it is the ink reading and not the placement. A pointed end covers little of its last pixel and reads short.
    - The reader is exact where the ink is at least a pixel wide at its edge, which is what its `drawRect` control checks.
    - A stretched brace keeps its centre and its width. Its height is off by up to its stretch in pixels, because the rasteriser's thickening is stretched with it.
    - A frame of 3,000 glyphs under a repainting overlay rasters in 4.3 ms at the median and 4.6 ms at the 90th percentile, in a profile build on the development Mac. The budget is judged on the 90th percentile. That is over half the budget on a fast machine, so the device runs decide it.
  - **The staff line.** A staff line is geometry and is not snapped. So the centre check is also the distance between a head and its line, and that alignment is what a reader sees (see Tradeoffs).
  - **The table.** The test reads the generated table, not the JSON.
  - **The devices.** The same test then runs as an integration test on an Android device and an iOS device (`example/integration_test/glyph_gate_test.dart`). It loads no font, so it also proves that an app gets the font from the package's declaration under the family the painter asks for. There it also reports the raster time of a frame that shows 3,000 glyphs while an overlay repaints over them (`FrameTiming.rasterDuration`). Every glyph is its own `drawParagraph`, the engine replays them whenever the frame changes, and nothing else measures raster cost before the widget exists. The rounded baseline is in the text layout every platform shares. The pixel snap and the thickening belong to each platform's rasteriser, so the probe's numbers are the host's only.
  Nothing else in the engine gets a body until the gate passes on all three. If it fails, or if that raster time is over 8 ms on a device, which is half a frame at 60 Hz, the fallback is a path painter behind the same `GlyphPainter` seam.
- **Gate 2. First layout cost.** A benchmark lays out a 500-bar, 4-staff score with the fake measurer. Every bar has notes, with beams, two voices on one staff, a lyric verse, dynamics and slurs, because a score of whole-bar rests would meet any budget. It is compiled ahead of time with `dart compile exe`, warmed up, and reports the median of its runs, because a JIT run measures the compiler as much as the code. The budget on the development host is 50 ms for `SheetLayout(score, ...)`, which is 100 microseconds per bar of four staves, and 1 ms for the update after one entered note. A mid-range phone is taken as four times slower, which gives 200 ms once when a large score opens and 4 ms per edit.
  - A second fixture has 2,000 bars and 2,500 spanners, with four times the first-layout budget. `Score.measureView` reads `spannersTouching`, which is linear in the spanner count, so a first layout is bars times spanners. A scratch run measured 500 `measureView` calls on empty bars at 2.2 ms with no spanner and 13.5 ms with 2,500. If this fixture misses, the model indexes its spanners by bar.
  - **What the harness found.** Unit 2 measured the floor under any engine, which is the model reads a layout has to make. They are one `measureView` per bar for a first layout, and `changesSince` plus a `measureView` per bar to lay out again for an update. Medians on the development Mac, compiled:
    - the dense score reads in 13 ms of its 50, and an update in 0.09 ms of its 1;
    - the spanner score reads in 95 ms of its 200, and an update in 0.19 ms;
    - the scan of every spanner for every bar is 56 ms of those 95, at 11 ns per pair, which agrees with the scratch run's 9;
    - a bar of real music costs 18 microseconds to read against 3 for an empty one, which the scratch run on empty bars could not see.
    So the engine has 37 ms for the dense score and 105 ms for the spanner score, which is 74 and 52 microseconds per bar. The spanner score is the tighter one. Indexing spanners by bar in the model would give it back about 55 ms.
  - **The index landed after unit 4.** The fixture did not miss, but unit 4 took the spanner score to 134 ms of its 200 with notes alone, and five units of drawing were still to come. So the model now builds the list of spanners per bar once per score, on first use, and `spannersTouching` reads it. On the development Mac the spanner score's first layout went from 134 to 79 ms and its update from 0.25 to 0.22 ms. The dense score went from 22.8 to 19.5 ms and its update from 0.147 to 0.141 ms. An edit makes a new score, which builds the list again on its first view, and the update medians include that.
  - Every engine unit reruns the benchmark and must stay inside the budget. So the cost of spanners, marks and lyrics is counted when each lands, not assumed from an engine that lacks them.
  - The fake measurer leaves out the one platform call a layout makes, which is a paragraph per distinct text. So unit 11 measures the first layout once on a device with `ParagraphMeasurer` and 1,500 distinct syllables, against the phone's 200 ms.
  - The widget is not built until the complete engine meets the budget. If it misses, bars are laid out in visible order, with widths for the rest computed first.

Tests 1 to 8 run with `dart test` in `packages/score_layout`. They use the generated Bravura table and a fixed-pitch fake `TextMeasurer`, so results are identical on every host. They assert work through `delta.relaid`, `delta.rekeyed`, `delta.rebroke`, the identity of `systemAt(i)` and the identity of `update`'s result. There are no counters.

1. **Incremental equals fresh.** Build a 500-bar, 4-staff score and lay it out. Enter a note in bar 250 through `EditSession`. Then:
   - `layout.update(next)` equals `SheetLayout(next)` in system starts, stretches, tops and, system by system, drawables by value;
   - `delta.relaid` is exactly `{m249, m250, m251}`;
   - for every index outside `delta.rekeyed`, `systemAt(i)` is `identical` to the object the layout before gave for that system;
   - `layout.update(layout.score)` is `identical` to `layout`.
   Repeat after `InsertMeasures` and after `SetBreak` to cover `reflow`.
2. **Breaking.**
   - A bar with `breakBefore` starts a system.
   - No system's natural width exceeds the sheet width unless it holds a single bar.
   - Each system is first-fit, so adding its next bar would overflow.
   - A key change at a system's first bar puts the courtesy key at the end of the previous system, and `noCourtesy` removes it.
   - A wider bar mid-score leaves every earlier system's start unchanged, and `delta.rebroke` is false when no width changed.
3. **Alignment and proportion.**
   - Events with the same onset on different staves and voices share an x.
   - x is strictly increasing in onset within a staff.
   - In a bar of one quarter and two eighths, the space after the quarter exceeds the space after an eighth, and is less than twice it.
4. **Hit round trip.** On single-staff scores with treble, bass, alto, percussion and one-line percussion staves, on the first, a middle and the last system, for each step from -6 to 14, hit-test the y of `PlacedStaff.yOf(step)` and check:
   - `staffStep == step`, with the one-line staff's line at step 4;
   - `toneForStaffStep(hit.staff, hit.at, step)` equals the tone whose head layout drew at that y (treble step 0 is E4, bass step 0 is G2);
   - a tap on a notehead gives its `NoteRef`, a tap on a voice-two note gives `voice == VoiceSlot.two`, and a tap on a grace head gives the principal's `EventRef`;
   - a tap inside a triplet of eighths, at an x that is no existing onset, gives an `at` at which `EnterNote` of a sixteenth returns `Applied`;
   - a tap on a voice-two rest, in a bar where only voice two has a triplet, gives `voice == VoiceSlot.two` and an `at` on the triplet's grid;
   - a tap on the staff under a slur's arc has no target, and a tap within reach of a stem gives its `EventRef`;
   - a tap in the gap between two systems gives a hit on the nearer one;
   - between two staves of one system, a tap nearer the lower staff's middle line gives the lower staff.
5. **Overlays need no layout.**
   - `caretOf`, `selectionBoxes` and `playheadAt` return boxes for a cursor, an item selection and a range whose `to` is a bar end, and leave the layout `identical`.
   - A range across a system break gives one box per system.
   - A sounding ref on a hidden staff gives no box.
   - A range whose `to` is offset 0 of the first bar of the next system gives no box on that system.
   - A ref made before `SetMeter` moved its event to another bar, on another system, still gives the event's box.
6. **Seeded random edits.** Over seeded random edits (reusing `packages/score_model/test/random_edits.dart`) and random widths, the layout reached by `update` equals a fresh one in system starts, stretches and drawables. It runs with `multiMeasureRests` off and on, since rest runs are off by default and nothing else would fold a bar.
7. **The band.** Over the scores of test 6, every drawable of every assembled system lies inside the box from (0, 0) to its plan's width and height, within `bandTolerance`, with `multiMeasureRests` off and on. The scores include a slur over a barline between a stems-up bar and a stems-down bar, and a slur over a note higher than both of its ends. That slur's curve lies outside the high note's box.
8. **One assertion per notation.** Tests 6 and 7 are properties that a notation drawing nothing passes. So each notation has one named assertion on its drawables, and its unit is not done without it:
   - a grace head is drawn at `graceScale` to the left of its principal, and an acciaccatura has its slash;
   - a two-staff part has a brace over both staves, `braceWidth` wide on a short system and on a tall one, and barlines that join them;
   - a hidden part draws no staff, no name and no brace;
   - a `DrumNote` head sits at its step on a one-line staff, with the line at step 4;
   - a quarter-tone note draws the glyph of the style's `QuarterToneGlyphs`;
   - a volta has its label and both hooks, and its continuation after a system break has neither a left hook nor a label;
   - a `RestRun` of n bars draws the number n over an H-bar;
   - a system that starts with a pickup bar is labelled 0;
   - every stem of a beamed group ends on its beam at stretches 1, 2 and 3;
   - in a chord, no accidental's box overlaps a head's box, and the heads of a second do not overlap;
   - no two mark boxes of one bar overlap;
   - a new syllable that joins a word several systems back rekeys exactly the systems between them, by `delta.rekeyed`;
   - a `begin` syllable with no later syllable in its lane rekeys only its own system and draws one hyphen after its text.

Three widget tests run with `flutter test` in the shell. Each loads the font as gate 1 does.

9. **The base layer repaints only for what changed.** Pump a `SheetView` with a `ValueNotifier` for playback and bar numbers on. Count `SystemPainter.paint` calls. The count is unchanged, and the `OverlayPainter` count grew, after each of:
   - a new playback position;
   - a new cursor;
   - an edit in a bar outside the viewport, which makes a new layout and a new label object for every tile.
   A scroll calls `build` on the view zero times.
10. **The anchor bar stays.** An edit above the viewport that changes a system's height leaves the anchor bar's offset from the viewport's top unchanged. So does a new zoom. With the cursor's system scrolled out of view, a new zoom keeps the system at the top of the viewport in place. A correction during `ensureVisible` still ends with the target system in view. `maxScrollExtent` equals the layout's height on the first frame.
11. **One clock.** With a fake MIDI output and fake time, `position.seconds` is continuous across a new `tempoScale`, a pause and a resume, and every note is sent at its own script second after each of them. With tickers muted, playback still ends and the status goes idle.

### Model additions

Each addition is proposed for `score_model`, with its exact signature. The sketch declares stand-ins in [model_additions.dart](sketch/score_layout/lib/src/model_additions.dart) so it type-checks. The additions land before the engine package needs them (unit 3), so the package never has that file.

**B1. `PlaybackScript.pointAt`.**

```dart
final class PlaybackPoint {
  const PlaybackPoint({required this.bar, required this.offset});
  final PlayedBar bar;   // measure and pass
  final double offset;   // whole notes into the bar, continuous
}
PlaybackPoint? pointAt(double seconds);   // null outside [0, totalSeconds)
```

It inverts the bar's `_ClockStep`:
- a steady pace gives `wholes = seconds * rate`;
- a moving pace gives `wholes = rate * (exp(slope * seconds) - 1) / slope`;
- a fermata's stretch divides the seconds first;
- `_Bar.from` is added back for range playback.

Could layout compute it? No. `_Clock` is private. Interpolating between `PlayedBar.start` and `end` is wrong under fermatas, tempo lines and mid-bar tempo marks, and `secondsAt` covers only the first pass. Without B1 the playhead would be wrong, not just approximate. So B1 lands before the playhead does, and the event highlight works without it.

**B2a is withdrawn.** The synthesis proposed `SpannerSegment.until`, a field for where a piece ends in its bar, on the premise that layout could compute it only with the `Score`. The review found the premise false.
- `Score.lineEnd` reads one thing, the voice-one event that the spanner's last point falls in. `Score.anchorAt` reads the event sounding at a point in a voice, else in voice one. Both events are in the last bar, and `StaffView.voices` holds every event of that bar with its onset and duration.
- So `pieceEnd` in `spanners.dart` applies the two rules to the bar's own view. It is real code in the sketch and it type-checks against the model.
- The proposed field's text was also wrong for slurs. It said a slur's `until` is `to`. The exporter uses the onset of the event `anchorAt` finds, which differs whenever `to` is not an onset.
- The rule now has two homes, the model's two methods and `pieceEnd`. A test holds them together. Over the scores of test 6, `pieceEnd` agrees with `Score.lineEnd` and `Score.anchorAt` for every spanner.

**B2b. `BeamGroup.joins`.**

```dart
enum BeamJoin { begin, continued, end, forwardHook, backwardHook }
final List<List<BeamJoin>> joins;   // per event, per level, level 1 first
```

This is the exporter's `_beams`. Could layout compute it? Yes, from durations and `secondaryBreaks`. It is proposed for the model for the same single-rule reason. It is low cost, because the model already computes it privately.

**B2c. `Jump.label` and `Score.barNumberOf`.**

```dart
String get label;                 // on Jump: text ?? "D.C." / "D.S." + " al Fine" / " al Coda"
int barNumberOf(MeasureId id);    // on Score: a short first bar is the pickup, numbered 0
```

Layout could compute both easily. They are proposed for the model so export and display agree. If the owner declines, layout implements them, and nothing else changes.

**B3. `sourcesAt` documentation.** The doc should say the result includes events on hidden staves. Layout does not need a filter, because a ref with no drawables is skipped. Only the contract changes.

**B4. `ScoreChanges.reflow` documentation.** The doc should say `reflow` reports structural changes only, and that width changes are layout's to detect. Layout already compares `BarWidths`. Only the contract changes.

**B5 is withdrawn.** C proposed listing grace ties in `StaffView.ties`. That cannot work. A `GraceChord` has an `EventId` and its notes have ids, but no `ElementRef` resolves to a grace, so `TieView.to` cannot name the next grace. A grace tie joins heads inside one event's column, so `graceItems` in `chords.dart` draws it from `GraceChord.notes[i].tie`. The matching rule is that a tied grace note joins the note with the same `Note.tone` in the next grace chord of the same principal, or in the principal when the grace chord is the last one. With no such note it is a let-ring stub.

Layout computes the rest itself, because no other consumer needs them:
- where a spanner's piece ends in its last bar (`pieceEnd`);
- the written previous key (`part.instrument.writtenKey(view.previousKey!)`);
- the order of sharps and flats;
- stem directions, collisions and skylines.

### Red-flag screen

Each design red flag, and what changed because of it. The first entries under each flag are candidate C's. The entries marked "Synthesis" were found when the grafted result was screened again.

- **Shallow module.**
  - The first draft exposed the stages as public types for the shell to coordinate, namely a bar cache, a breaker and an assembler. It now exposes `SheetLayout` with two entry points, and `changesSince` is called inside `update`.
  - `update` first returned a `(layout, report)` record, which every caller had to destructure. The report became the `delta` field.
  - A separate `resize(width)` merged into `update(score, {width})`.
  - Synthesis. `SheetLayout.systems` and `labels` were public raw lists, which a lazy layout cannot honour and which let a reader depend on eager assembly. They became `systemCount`, `systemAt(i)`, `heightOf(i)` and `labelOf(i)`.
  - Synthesis. `SheetOverlay` was a notifier whose only job was to carry the view's values to the painters. The painters now take the values, and the class is gone.
  - Synthesis. `entryPoints` and `snapTime` are not exported. An app sees `SheetHit` only.
- **Information leakage.**
  - `SmuflFont` first carried the Flutter package name where the bundled OTF lives. That put an asset-layout fact of the shell into the pure engine. Now `GlyphPainter`, in the package that bundles the font, maps the bundled Bravura to its package-prefixed family, and `SmuflFont` holds only a family.
  - The staff-step formula is one function, used by bar layout, placed staves and the hit test.
  - Text sizes live once, in `TextSpec`. `TextDraw` carries its measured bounds, so the painter never measures again.
  - The beam-join, jump-label and bar-number rules are shared with the exporter (B2b, B2c), not copied. The spanner-end rule is the model's `anchorAt` and `lineEnd`, applied to a bar's view by `pieceEnd` and held to them by a test.
  - Synthesis. `BarLayout.view` carried the whole `MeasureView` into assembly, and `layoutBar` took the `Score`. Both are gone. The bar stores resolved stubs, and assembly reads no model fact through the layout type.
  - Synthesis. The room of a cross-bar piece was about to be known twice, by the bar that reserves it and by the system that draws in it. The stub now carries the reserved edge (`SpannerPiece.limit`), so the rule has one home in `spannerPieces` and assembly only reads the result.
  - Synthesis. That a text font loaded late is a fact of the Flutter shell. It stays there. The engine's `TextMeasurer` port gained no font key.
  - Synthesis. The lyric carry rule is one method, `BarLyrics.after`. Planning folds it, and assembly reads the result from the key.
- **Temporal decomposition.**
  - The cache levels follow execution order, so each was checked for repeated knowledge.
  - Bar layout owns notation inside a bar. Breaking owns only the fit policy, and reads only `BarWidths`. Planning owns justification and vertical room. Assembly owns placement on the line. `SheetLayout` owns stacking and queries.
  - Hit testing and overlay geometry were first planned as their own modules after assembly. They moved into `SheetLayout`, because they would repeat its system and bar lookup.
  - Synthesis. `layoutBar` was one eight-step list and `assembleSystems` one five-step list, both organised by stage. The code is now split by notation concern. `spanners.dart` owns `spannerPieces` and `placeSpanners`, `lyrics.dart` owns `lyricsOf`, `lyricRows` and `placeLyrics`, and so on. The two functions that run at different times and protect the same decision sit in one file.
  - Synthesis. The lyric carry was a fold over assembled systems, so system n needed system n - 1 assembled first. It is now a fold over bars.
- **Pass-through method.**
  - `SheetController`'s geometry methods forward to `SheetLayout`, but each adds the pixel and scroll conversion only the view knows, so they stay.
  - `ScorePlayer.play` wraps `PlaybackCompiler.compile` with loading, scheduling and the ticker, so it stays.
  - `BarLayout.build`, a factory that only forwarded its arguments, became the internal function `layoutBar`.
  - Synthesis. `SheetOverlay.set` and `play` forwarded their arguments to fields the painter then read. They went with the class.
  - Synthesis. `SheetLayout.caretOf`, `selectionBoxes` and `playheadAt` call the per-system forms and add the system's top. They stay, because the sheet-space form is what the controller needs and the per-system form is what a tile needs.

## Synthesis decision

**The base is candidate C.** Two judges on different models and the picker chose it independently. It has the deepest public surface, made of one widget, one controller that returns rects, one style, one palette and one player. It has the most precise cache contract, with a `SystemKey` of bars by identity, the next bar and the lyric carry, bar numbers outside the systems, and a `delta` the view and the tests read. Its model additions survived checking against the model's code. Its weaknesses were mechanical and each had a graft.

All three candidates independently chose a Flutter-free core, the unmodified OTF drawn as text, greedy breaking and a per-bar cache with role widths. Those four choices are taken as settled by agreement.

**Grafts.**

| Graft | From | The defect it fixes |
|---|---|---|
| G1. The generated metrics pipeline, which is the generator with its four failure checks, the 222-value `Glyph` enum, 19 anchors, 28 engraving defaults and the real table | A | C sketched two table entries and a generator that did not exist. Its count of 213 was unreconciled with glyphs.md's 222 |
| G2. Lazy assembly with heights known at planning | B | C assembled every system before the first frame and on every resize. Its lyric carry-out was stored nowhere, so the fold needed assembled systems |
| G3. Real code for breaking, with resume, stop and a sealed break unit | A | C's resync rule was prose. Writing it as code and testing it showed the rule needs the courtesy width after a unit in its dirty test |
| G4. The overlay as its own layer per tile | B's goal, the picker's shape | C and A painted the overlay in `foregroundPainter` of the base's `CustomPaint`, so a playback tick re-recorded every visible system. C's `painting.dart` and decision 4 claimed otherwise. `SheetOverlay.set` also notified during build |
| G5. Per-concern modules with named functions | A | C's `layoutBar` and `assembleSystems` were two step lists organised by stage, with no named home for any notation |
| G6. A bar built from its view alone | the judges | C's `layoutBar` took the `Score` and `BarLayout` kept the view, against its own invariant |
| G7. The hit's voice, and snapping in the tuplet's written time | B for `voice` and the one-space column radius | C's hit test took a voice and returned none. All three candidates snapped inside tuplets in a way the model refuses or that cannot split a member |
| G8. `SmuflFont ==` over family and metrics identity | the judges | `EngravingStyle ==` used `identical(font)` |
| G9. Late fonts handled in the shell | the picker | C required every font to be loaded before the first `SheetView` |
| G10. The glyph-placement gate first, then a first-layout benchmark with a budget | A's test 5, B's next step | Text-drawn glyphs were unproven on every platform in all three, and nobody had measured a first layout |
| G11. Scroll anchoring specified | none | All three left it as a TODO |
| G12. `LayoutDelta.rekeyed` | the picker | `rebuilt` has no meaning when nothing is built eagerly |
| G13. The seeded incremental-equals-fresh test | B | C's tests had no random coverage of the resume rule |

The synthesis also fixed one defect no judge listed. C's `SheetScale` had no `==`, and `SystemPainter.shouldRepaint` compared scales, so every build repainted every visible system. `SheetScale` now compares by value.

**Declined.**
- B's affine `X` (a natural x plus a per-stretch part). It cannot express `max(rod, ideal * s)`, so rods would stretch.
- A's reading of the next bar's view for a bar's closing. The model puts the courtesy flag on the bar that starts the system, and C's `SystemKey.next` already covers it.
- A's `OpenSpan` threading between systems. C draws every piece inside its own system from bar stubs, so no system depends on another's geometry.
- B's core in `lib/src` by convention, its runtime metadata JSON, Petaluma kept, its exported second tier, and its title block as Flutter widgets. The package boundary is the proof of purity, the const table has no runtime parse, and the header is engine drawables so `toImage` includes it.
- B's single marks layer above the scroll view. It repaints on every scroll frame. The per-tile overlay repaints only when an overlay input changes.
- B's LRU of 64 assembled systems. A memo by `SystemKey` that `update` prunes is simpler and bounded by the system count.
- A's `Sp` and B's `Ss` unit brands. The engine package cannot name a pixel, points and boxes are already typed (`SpPoint`, `Box`), and the shell converts at one site (`SheetScale`).
- A's `LineBreaker` interface with one implementation, and A's `HitSnap` modes. A selection tap reads `target`, not `at`.
- B's `LayoutStats` counters. Tests assert through `delta` and identity (G12).
- A's `TextMeasurer.fontKey`. The shell owns the measurer and replaces it (G9).
- B's fixed `curveAllowance` and its accepted collisions. A bar reserves the real room of each piece in its skyline, and curves clamp to it.

**Conflicts settled.**
- Overlay placement. One judge preferred B's single layer and the other a nested repaint boundary. The per-tile `Stack` won, because it leaves the base rasters alone and does not repaint on scroll.
- Late fonts. Both judges proposed A's `fontKey`. The shell listener won, because the engine's port stays one method and pure.
- Work counters. Both judges proposed B's `LayoutStats`. `delta` and identity won, because they are not mutable state on a value type.
- Spanner ends. `Score.spannerEnds` (C), `SpannerSegment.until` (A) and `SpannerSegment.lineEnd` (B) became one field, `until`, on the segment. The review then withdrew the field (see "Changed by review").
- The lyric carry-out. One judge proposed storing it on the assembled system. A fold over bars won, because lazy assembly has no assembled system to read.
- System plans. A's item indices lost to `MeasureId` starts, which do not shift under insertion.
- The tap grid. A sixteenth by default (B, C), a 128th floor (A), and B's column radius applied first.
- The one-line staff. A and C's fixed step map won over B's `yOfStep(lines:)`, because `Clef.naturalAt` ignores `Staff.lines`.

**Changed by review.** Three reviewers on different models read the synthesis against the model's code and ran their own probes. What held under test: resumed breaking against fresh breaking over 120,000, 48,000 and 12,000 random edit steps, with rest runs off and on, and with three mutants of the rule each caught; `stretchFor` and `sliceXs` by brute force; `changesSince` covering every bar whose view differs; `entryPoints` against the real lane writer; and both sketch packages against the current model. What changed:

| Change | The defect it fixes |
|---|---|
| A slur's side comes from the spanner (`curveSide`) | The side was taken per bar from that bar's stems. A slur over a barline between a stems-up and a stems-down bar had two sides and room on neither |
| A piece stores `clear` beside `limit`, and `curveBetween` raises the arc outside `clear` | The curve was only clamped from outside. Nothing kept it off the notes under it |
| B2a withdrawn, `pieceEnd` in layout | Its premise was false and its text for slurs contradicted the exporter |
| Drawables compare by value | The doc said they did and no class had `==`. A bar-number label is made per layout, so every visible system repainted after every edit, and tests 1 and 6 could not compare drawables |
| The view listens to the zoom only | It listened to its own controller, which notified on every scroll tick and after every layout. Every scroll frame rebuilt the view |
| Live pinch zoom removed | It was promised with no mechanism, no unit and no test. Slivers cannot be scaled in place |
| One script clock in `ScorePlayer` | Two clocks had no shared anchor, and `start + scale * elapsed` jumps when the scale changes |
| Late fonts are handled once per frame, and relay out only when a measured extent changed | Any font any package registered relaid the whole score, once per registration |
| The glyph painter is replaced, not cleared, its cache is bounded, and painters compare it | The cache grew with every zoom and tint, and a cleared cache did not repaint |
| The hit's `at` is snapped in the hit's `voice` | `voice` came from the target and `at` from the asked voice, so the documented `VoicePoint` mixed two voices |
| Targets are hit within a finger's reach, and curves near their line | A stem was one pixel wide, and a slur's box swallowed every tap under its arc |
| A tap in a system gap belongs to the nearer system, and one just above the first system or below the last to that system | 48 pixels under every system gave no hit, and a ledger position outside a band could not be tapped |
| `bandTolerance` in the band assert and test 7 | The right edge equals the plan's width only to rounding, and the strict comparison failed in a fifth to a quarter of random systems |
| `LineDraw.bounds` is the line's ink, and a staff's reach is at least half a staff line | The bounds were not defined. With ink bounds, the outer lines of a staff with no reach left its band |
| `toImage` takes a range and has a height limit | One image cannot hold a long score |
| Gate 1 names its sizes, origins, ink reading and font loading, checks placement and size apart in device pixels, and measures raster time on devices | 0.05 staff spaces is 0.4 pixels at the default size, `flutter test` registers no pubspec font, and nothing measured paint cost |
| `GlyphPainter` rounds the baseline it subtracts | The paragraph draws its baseline on a whole pixel and reports it unrounded. Glyphs sat up to 0.13 staff spaces off their lines at the default size |
| Gate 2 runs compiled, has a large fixture with spanners, and is rerun with a budget by every engine unit | It ran under JIT, could not see the bars-times-spanners cost of `measureView`, and passed before spanners, marks and lyrics existed |
| Test 8, one assertion per notation, and tests 10 and 11 | Graces, braces, drum heads, quarter tones, voltas, rest runs, pickup numbers, beams and the player had no check that a notation drawing nothing would fail |
| A hyphen is carried only to a syllable that joins its word, and the key holds the carry at both ends | An unfinished word kept its hyphen open to the end of the score, so typing one syllable rekeyed every later system and gave each a lyric row |
| The cursor is the scroll anchor only while its system is on screen, an animated scroll is started again after a correction, and the tiles report their true extent | A zoom moved what the user was reading to hold an off-screen cursor still, a correction was undone by the next tick of `ensureVisible`, and the scroll extent was a guess a third of the truth |
| A brace has one width and is stretched to its part (`GlyphDraw.stretch`, `braceWidth`) | Scaled evenly, a brace was as wide as its part was tall, and the lead's indent is one value for every system |
| `pieceStart` beside `pieceEnd` | A spanner's first point can lie inside an event too, once an overwrite lengthens the note under it |
| A ref is resolved by `Score.lookup` (`systemOfRef`), and a tint by its event's id | A ref's measure is a hint. After `SetMeter` a held ref named the old bar, and its tint and its box vanished |
| A range that ends at the start of a system shades nothing of it | It shaded that system's clef and key |
| What a line starts with is in its slice's reach (`lineStartReach`) | A tempo line that started on a system's last beat drew its text past the right edge |
| The player's timer owns the end and the loop, and a note's lateness is stated | "Sound never waits for a frame" was false for a timer on the UI isolate, and a muted ticker never ended playback |
| Units reordered and split | Gate 1 needed the glyph table of a later unit, a unit's test could not reach `layoutBar` past functions of later units, the shell and the player shared one unit, and the last unit's check did not run the packages' tests |

The review also raised points that stay as they are, each recorded where it belongs. The highlight's fringe, the bar number's placement, the glyph snap and the timer on the UI isolate are under Tradeoffs. A tall note beside a slur's low end is under Risks. An octave line drawn to the end of its last event while `toneForStaffStep` shifts by onset is consistent, because an entry inside that event shortens the event and the line with it.

## Tradeoffs accepted

- We accept greedy breaking, which can leave one system looser than an optimal breaker would, in exchange for edits that never move earlier systems and a re-break that stops at the first resync.
- We accept spacing on an absolute duration scale per bar, so a bar of whole notes beside a bar of sixteenths is less uniform than Gourlay over a whole system, in exchange for bars that are laid out and cached alone.
- We accept beam slopes fixed at natural spacing, so justification flattens them slightly, in exchange for beams that never force a bar to be laid out again for a new system width.
- We accept three head variants and the courtesy items stored in every bar, in exchange for widths that are known before line breaking.
- We accept that every bar reserves vertical room for the pieces that cross it, at stretch 1 and without seeing its neighbours, so a system can be a little taller than a whole-system solve would make it, in exchange for heights that are known before any system is assembled.
- We accept slurs clamped to the room their bars reserved, so a long slur is flatter than an engraver would draw it, in exchange for the band invariant.
- We accept a slur's side taken from its voice alone, so a slur over stems-up notes in a single voice lies above them where an engraver would put it below, in exchange for one side per slur and room that every bar reserves on that side (C11).
- We accept a highlighted or tinted glyph drawn over its base ink, so an anti-aliased edge keeps a thin dark fringe under a light colour, in exchange for a playback tick and a new tint that repaint no base layer. If the fringe shows on a device, the base layer skips the tinted owners, at the cost of one base repaint per change of the sounding set.
- We accept the bar number placed against its own bar's reach, so a bracket or a line that a later bar pushed outward can cross it, in exchange for a number that stays beside its staff.
- We accept glyph ink that the rasteriser puts on whole device pixels vertically, beside staff lines that are not snapped. On the host a head sits up to 0.83 device pixels from its line, which at the default size is 0.1 staff spaces at device pixel ratio 1 and 0.035 at ratio 3. When half a staff space is not a whole number of device pixels, heads on different steps can differ by a pixel. In exchange the unmodified font is drawn as text. If it shows, the staff space is fitted to the pixel grid in the shell (`SheetScale`), with no engine change.
- We accept notes sent from a timer on the UI isolate, so a note is late by the build or the layout that is running when it is due. That is about 4 ms for an edit on the reference phone, and a full break when the sheet is resized during playback. In exchange a tempo change is immediate, any range loops, parts are muted per note, and no MIDI file stands between the script and the sound. `flutter_midi_pro` also has a native sequencer that plays a Standard MIDI File (`loadMidiData`, `playMidi`, `setMidiTempo`). Feeding it is the alternative if the lateness is audible.
- We accept a memo inside a `SheetLayout` that is otherwise immutable. The memo is not observable, because `systemAt(i)` returns an equal system whether or not it was cached. In exchange only visible systems are assembled.
- We accept work linear in the bar count on every update (identity checks, width comparisons, key lookups, one map copy), in exchange for code with no index bookkeeping. For the trace score that is about 500 comparisons.
- We accept text measured with the platform's font, so lyric widths and line breaks may differ between iOS and Android, in exchange for bundling no text font. An app that wants identical breaks sets `TextSpec.family` to a font it bundles.
- We accept glyphs drawn through the text stack, with no outlines in Dart, so hit testing uses metadata boxes rather than outlines, in exchange for an unmodified font, a 3.7 MB smaller bundle and no runtime parse.
- We accept that a system scrolled back into view re-records its picture, in exchange for relying on `RepaintBoundary` and keeping no picture cache of our own. Its assembled drawables are still in the memo.
- We accept that re-exporting `score_model` makes `Interval` and `Step` ambiguous with Flutter's when an app uses both, in exchange for one import.
- We accept layout on the UI isolate, synchronously, in exchange for no async gap between an edit and its picture. The first layout of a large score is the cost to watch (gate 2).
- `LayoutDelta` may look like test scaffolding. It also tells the tests what an update touched without counters, and `rebroke` names the case scroll anchoring exists for.

## Alternatives considered

**Flutter render objects as the layout** (`RenderSheet`, then `RenderSystem`, then `RenderBar`). Flutter would give relayout boundaries, `markNeedsLayout`, repaint boundaries and semantics for free.
- It lost because invalidation here comes from the model diff, not from constraints. Each `changesSince` would have to be translated into `markNeedsLayout` calls on render objects found by `MeasureId`, which is a second reconciliation.
- Line breaking needs every bar's width before systems exist. That inverts the parent-gives-constraints protocol and pushes the engine onto intrinsic-size passes.
- Interface depth is worse. The engine would expose a render object per bar and the Flutter lifecycle to its own tests, and hit results would come back in render-box coordinates.
- What it hides well (repaint boundaries) this design gets anyway, with one boundary per system.

**A galley.** Lay the whole score out as one infinite line with a global time-to-x map, then cut it into systems and re-justify each.
- It gives the most even spacing, since one spacing solve sees every bar.
- It lost on incrementality. One wider note shifts every later x. Cut points are re-found on every edit. Courtesy and system-start widths depend on where the cuts fall, which makes cutting iterative.
- It hides spacing well, but it exposes O(score) work to every keystroke.

**Bars baked to pictures and composed by translation only.** Each bar is recorded once at natural width, and systems are bars placed side by side, ragged right.
- It is the cheapest incremental shape.
- It lost on quality and on cross-bar notation. Without justification every system is ragged. Ties, slurs and hairpins across bars would need a separate layer that knows bar positions anyway, which recreates system assembly.

Also weighed, as variations and not whole shapes:
- An engine in `lib/src` typed with `Offset` and `Rect`. It lost the pure-Dart tests and the unit boundary.
- Layout on a background isolate. `dart:ui` paragraphs cannot be measured there, and the incremental update is small enough for the UI isolate. Revisit only if gate 2 fails.

## Implementation reconciliation

Deviations accepted while implementing, by unit. The owner of each is the implementing session, checked by that unit's tests.

**Unit 1.**
- `GlyphPainter.paint` takes the glyph, its origin, the scale, the colour, a size and a stretch. The sketch passed a `GlyphDraw`, and `drawable.dart` arrives with a later unit. `paintDrawable` will unpack a `GlyphDraw` into the same call, so the painter stays the one seam and knows no drawable.
- One reader, `smufl_metadata.dart`, serves the generator and `SmuflFont.fromMetadata`, as the sketch's TODO asked. `EngravingDefaults.read` ties each SMuFL name to its field once, and `engravingDefaultNames` is derived from it, so the generator's hand-copied list of 28 names is gone.
- The metadata JSON stays in `assets/` until unit 13, because the old engine still loads it. The generator reads it from there.
- The root package depends on `packages/score_layout` by path and is marked `publish_to: none`, which the analyzer requires of a package with a path dependency. The SDK floor is raised in unit 13 with the old engine's deletion, since nothing in unit 1 needs the newer syntax.
- `fonts/OFL.txt` is the licence text the font carries in its own name table (record 13, with Steinberg's copyright line), written out unchanged. Nothing was fetched. The OFL accepts the copy inside the font file as the notice, so an app that ships the OTF ships its licence. The `LicenseRegistry` entry waits for the widget, which is where an app's licence page is fed (C6).
- Gate 1's horizontal bound is 0.5 device pixels, and the raster budget is judged on the 90th percentile (decision 10).
- The reader also refuses a box whose corners are inverted, which `Box` would otherwise reject with an assertion and no glyph name.
- `assets/petaluma_metadata.json` does not pass the reader. It has no `glyphAdvanceWidths` table, no `hBarThickness` and no box for `legerLine`. A font with a numeric engraving default the engine does not know is refused too. Both follow from the checks the design gave the reader, and both bear on C6.
- The gate's images are one row of origins each, so no image is taller than a glyph. One image of all 64 origins reached 4,160 pixels at 64 pixels per staff space, which is past the texture size of an old phone.
- The device runs on Android and iOS are open. The macOS run passes.
- The pure-Dart units, 3 to 10, go ahead before the device runs. Decision 10 held every engine body until the gate passed on all three platforms. No Android device is attached to the development machine, and the engine's geometry reads the font's table, not the painter, so a path painter behind the same seam would change none of it. The device runs must pass before unit 11 builds the view.

**Unit 2.**
- The benchmark is `packages/score_layout/benchmark/layout_benchmark.dart`. Its two functions, `firstLayout` and `update`, hold the floor today. The unit that adds `SheetLayout` replaces their bodies and nothing else.
- The spanner score is the dense score's music for 2,000 bars, with a slur in every bar and a hairpin over every fourth barline. The design gave it four times the budget for four times the bars, which only holds for the same content. The dense score so has 625 spanners.
- The model has no instrument catalogue, so the fixtures name three plain instruments themselves, a voice, a violin and a piano.
- The fixtures are built with the model's public constructors, not through edits. Both build in under 40 ms, and each is checked by a save and a load, which is the model's own validity check.
- Bar 250 is the bar's number, counted from 1. The entered note changes bars 249, 250 and 251, as test 1 expects.
- Every timed first layout gets a fresh copy of the score. A score builds its indexes on first use, and a first layout pays for them.
- The fake measurer makes a character 0.6 of the size wide, with an ascent of 0.8 and a descent of 0.2. Nothing measures text yet, so the benchmark does not use it until lyrics land.
- The design names no update budget for the spanner score, so that number is reported and not judged.

**Unit 3.**
- The signatures of B1, B2b and B2c are the ones under "Model additions". B3 and B4 are the two doc comments.
- `BeamGroup` takes `joins` as a required named parameter. The design showed the field and not the constructor. Only the model's beaming code builds a group.
- `pointAt` gives the instant a bar starts to that bar, on its pass. It shares the search for the bar being played with `sourcesAt`, so a playhead and a highlight never name different bars.
- `secondsAt` covers the first pass only, so the round trip of the check reaches a later pass by the start of that pass's `PlayedBar`. A second test finds every note of every pass at its event's onset, which needs no such shift.
- The exporter's `_beams` and its pickup field are gone, and so is `jumpWords` from the table of names. Import reads `Jump.label` to tell whether a jump has text of its own. The names of the beam types stay private to the exporter, because the Read stage of import does not see the view types.
- Moving the three rules changed no export. The exports of the showcase and of 360 scores made by random edits, with 7,461 beam elements, were byte for byte the same with the old and the new code. The hook fix below came after that run, and it changes one `<beam>` text in the case it names.
- A hook on the last event of a group points back. The exporter's rule pointed it forward after a secondary break, at no event. The second-model review found it, and the rule is fixed in the model, so export now writes `backward hook` there and layout draws what `joins` says.
- `ToCoda.label` and `Fine.label` join `Jump.label`, so the unit that draws system marks reads every printed word from the model. The design named only the jump.
- The unit has 21 new tests, where the design asked for three. The model has 767. Two tests that compared the model's rule with an export that now calls the same rule were removed after the review, because they could not fail.
- `joins` is built with the groups inside `measureView`, which the benchmark times. The four medians moved by less than the spread between runs. Dense first layout went from 12.4 to 12.6 ms, dense update from 0.084 to 0.086 ms, spanner first layout from 92.6 to 93.1 ms and spanner update from 0.182 to 0.184 ms.

**Unit 4.**
- `stemSideFor` takes the chord's onset as `at`. A head's step follows the clef in force at the chord, and `StaffMeasure.clefAt` wants the moment.
- `planChord` takes `beamed`, and a plan carries its own drawables, built once. The sketch had `placeChord` build them from the plan and the style, which made the same ink three times per chord, for the reach, the beam and the items. The profile of check 6 named those three. So `placeChord` and `graceItems` take only the slice and the staff, `stemOf(plan)` takes no style, and `ChordPlan` and `GracePlan` are built by `planChord` alone. `GracePlan.x` is the grace's slice line against the principal's.
- `placeRest` takes the staff's line count and the slices' x at stretch 1. The whole rest hangs from the line of a one-line staff, and a measure rest is centred between its first and last slice, which only the bar knows. The centre holds at stretch 1 and drifts under stretch. The system unit recentres it when it places the bar.
- `BarLayout` holds the fields this unit produces, which are the measure, its length, the break before it, `restOnly`, the widths, the lead, the slices, the staves, the items, the edges and the beams. It has value equality, so the purity check can compare two layouts. `BarWidths` holds `body` and `minBody`. The head widths, ties, spanners, tuplets, volta, lyrics and voice times arrive with their units.
- `signatures.dart` lands with `BarEdges` and `endBarlineWidth` only, because the last slice's rod is the end barline's width. The clefs, keys and meters follow in unit 5.
- `drawable.dart` lands without `SpannerOwner`, `CurveDraw`, `GlyphRunDraw` and `TextDraw`, whose producers are later units.
- A staff's reach above and below its lines is the union of its items' bounds and its beams' boxes. The skyline waits for the system.
- `BeamPlan.box`, which unit 7's review replaced with `BeamPlan.boxes`, is computed from the beam's ends, its levels and its stem starts, not by drawing the beam. `BeamPlan` has value equality.
- `sliceTimes` sorts the onsets and drops repeats instead of filling a `SplayTreeSet`. It was the cheaper of the two in the benchmark. It collects event onsets and the bar's end today. Directions, tempo, clef changes and spanner ends join it with their units.
- A tremolo on a flagged note lengthens the stem until the flag clears the strokes by the half space the stem tip keeps. The design put the strokes two spaces from the far head and said nothing about the flag, and the picture of check 7 showed the flag crossing them.
- An accidental clears a ledger line's extension as it clears a head. The ledger lines are placed before the accidentals, so the columns start from the chord's leftmost ink.
- A whole note or a breve has no stem. The sketch's wording, "an unbeamed chord also gets its stem", left the value out, and the picture of check 7 showed a stem on a whole note before the test was added. The tremolo strokes of a stemless chord are centred on its heads, where the stem would be.
- A ledger line spans the heads on it or beyond it, not a head in the space next to it. The first version also served that head, so the line through A3 ran under a flipped B3, and the line through A5 ran over a G5 that needs no line.
- Dots that a flag would reach move past the flag. The dot of an upstem dotted eighth on a line sits in the space above, where the eighth flag's tail ends.
- A beam keeps clear of a chord's tremolo strokes. `stemOf` returns `keep`, the y a beam's inner edge must stay beyond, and `planBeam` lengthens the end stems to it. The design cleared the strokes for a flag and said nothing about a beam.
- The acciaccatura slash is placed from the eighth flag's `graceNoteSlash` anchors against the stem tip, for a grace of any value. Only Bravura's eighth flags carry those anchors, so reading them off the grace's own flag crashed on a sixteenth grace. Every acciaccatura is slashed, not only the first, because graces are not beamed. Grace ties wait for unit 7 with the other ties.
- A grace head is owned by its principal's `EventRef`, like the rest of the grace, as the design says. The first version gave it a `NoteRef` of a note that was not in the principal.
- The picture test paints each drawable alone on a transparent canvas and checks that its ink lies inside its bounds. The first version looked for ink in the composite on a white background, which every box had.
- The root package takes `score_model` as a dev dependency by path, so the picture test can build bars. `test/support/draw.dart` paints drawables with `GlyphPainter`, and `loadBravura` moved there from the placement test.
- The bar fixtures in `packages/score_layout/test/support/bars.dart` fill a voice shorter than its bar, voice one with hidden rests and the others with a gap, because the model refuses a short voice.
- A test lays out every bar that changes over six seeded runs of 150 random edits, 1,944 bars with graces, drum notes, tuplets and second voices. It checks that nothing throws, that every box is finite and that the slices stay in time order at stretch 1 and 3. The review added it, because the first review had found a crash on a sixteenth grace that no fixture reached.
- The benchmark's `firstLayout` and `update` call `layoutBar` for every bar and for every bar in `relayout`. Dense first layout went from 12.6 to 22.1 ms, dense update from 0.087 to 0.146 ms, spanner first layout from 91.9 to 133.9 ms and spanner update from 0.181 to 0.246 ms. The first profile put a third of the time in chord ink made three times, which the second bullet above removed, and the rest in `sliceTimes`, head planning and the beam box, each of which was cut once. The four medians are inside the design's budgets.

**Unit 5.**
- `breaking.dart` is the sketch's file without what later units produce. `SystemKey` has no `carry` and `carryOut`, `PlannedStaff` holds only `top`, and `breakSystems` has no carry passes, because lyrics are unit 9. `RestRun` takes no `rise`, because unit 6 draws the count over a rest run, and its room joins `RestRun.staves` with that function. Until then a rest run keeps no room for its count.
- The dirty rule, the resume point and the stop rule are the sketch's, unchanged. No test proved one wrong. With nothing dirty the old list of starts is returned as the same object, which is how a caller sees that nothing was broken again. The rule's clause on a unit's last bar moves no break, because a rest run whose last bar changed has another width or another neighbour, or breaks where it did. It is kept as the sketch has it.
- `breakSystems` reuses a plan by its key, and a key holds neither the style nor the text measurer. So `previous` has to come from the same style and text, and the function's comment says so. The design makes a style change a fresh `SheetLayout`, which keeps that true.
- The last system stays ragged when its bars at their natural spacing fill less than `justifyLastSystemFrom` of the room that the indent and the signatures leave them. That is the sketch's code. The design's sentence says "of the width", which counts the indent and the signatures on both sides, and the two differ for a system that fills about three quarters of the sheet. The code's rule bounds the stretch of a justified last system at 1 / 0.75, which is what a ragged system is for. So it stands, a test pins it, and `style.dart` says it. The owner has not decided this.
- `planSystem` keeps the bar number's room and `labelAt`. They read the style and the text measurer, not `SheetLayout`.
- `EngravingStyle` gained what this unit reads, which is `text` with `specOf`, `staffGap`, `multiMeasureRests`, `meterEverySystem`, `courtesySignatures`, `justifyLastSystemFrom`, `barNumbers`, and `spacing.restRunWidth`.
- `clefGlyph` returns the glyph and a scale. SMuFL has a `Change` glyph for the G, C and F clefs only. An octave clef or a percussion clef that changes is its full glyph at two thirds.
- The inline head prints the small clef. The design said only that it holds the clef. A clef change at a barline is the same sign as one inside a bar.
- `keySignatureSteps` reads the top of the octave its accidentals lie in from a table, by where the clef puts C. The sketch said the pattern moves with the clef's line. That is wrong for the tenor clef, whose sharps start low while its flats do not. The treble, bass, alto and tenor rows are tested against the conventional positions. The review after the unit checked all seven rows against the `sharp-positions` and `flat-positions` defaults of LilyPond's key signature, and they match. MuseScore places the soprano, mezzo-soprano and baritone rows differently, so those three follow one of two published conventions.
- A key change prints a natural for each letter the old key altered and the new key alters differently or not at all. So a change from seven sharps to seven flats cancels all seven sharps before it prints the flats. The unit first cancelled only the letters the new key leaves natural, and the review after it found the enharmonic case. The naturals print in the inline head and in the courtesy. The system head prints them only when no courtesy did, which is when the change says `noCourtesy` or the style has `courtesySignatures` off. The design did not say which head cancels.
- A natural is followed by a gap of 0.3 and a sharp or a flat by 0.15. The picture of check 7 showed a natural reading as one sign with its neighbour at the narrow gap.
- `meterItems` takes no `lines`. Both rows meet on the middle line, which is also the line of a one-line staff (C1), so the count changes nothing. An additive meter joins its groups with plus signs.
- `clefChangeItems` takes `reach`. The clef sits half a space left of everything its slice reaches on any staff, and `layoutBar` then widens that slice's left reach, so the rod before it makes room. The design said "just left of the slice", which put the clef under an accidental or a ledger line. Clefs on two staves at one moment end at one x.
- A clef change's offset joins `sliceTimes`, as the design listed. A slice where nothing starts takes the shortest duration of the slice before it, so the note the clef falls in keeps its space, split in two.
- A head's width has one gap of 0.75 before each group and one after the last. The sketch said one gap between groups, which left the first group on the barline. Room for a start repeat is the head's last group, and it needs no gap when it is the only one, because the sign stands in for the barline.
- `startRepeatWidth` is a function of its own. `endBarlineWidth` uses it for an end repeat, which is the mirror image, and `barHeads` for the room in a head.
- `placeBarlines` in the sketch gets each bar's edges and frame. Neither says how wide the placed head is, and a start repeat sits in the head's last group. Unit 6 has to pass that width. The sketch's comment says so.
- A bar that ends a repeat keeps the sign's width in its last rod, and a bar that starts one keeps it in its head. Where the second follows the first inside a system, the widths hold room for two signs, about 4 staff spaces, and the design draws one joined sign there. A bar's widths cannot read its neighbour, so the room stays. Unit 6 draws the joined sign in it.
- An indent of `systemLead` is the widest name and a gap of 1 when any part has a name, and `braceWidth` when any part has two staves or more. The sketch gave the rule and no gap.
- `BarLayout`'s equality includes `heads`, and `BarHead` and `BarHeads` have value equality for it. A bar's reach covers its inline and system heads. The courtesy is drawn on the system before, so `planSystem` reads its reach from the next bar.
- The design has no courtesy clef. When a bar changes clef and key at the start of a system, the courtesy key at the end of the system before lies on the new clef's steps with no clef before it. The picture of check 7 shows it. The owner has not decided this.
- The random check of test 6 runs 8 seeds of 400 edits on a score of three parts, with multi-measure rests off and on. It draws a sheet width between 40 and 150 at random, draws a new one after one edit in 25, and adds a key, key display or meter display edit after one edit in three. Five fixed widths did not catch the dirty rule without its courtesy clause. The random widths and the signature edits do, and one named test does too.
- The picture test snaps each staff top to a whole pixel. The text engine puts glyph ink on whole pixels vertically, and a clef's reach is not a whole number of pixels, so the ink check failed by a fraction of a pixel on a staff between pixels. This bears on the view of unit 11, which has to place staves on whole pixels to keep glyphs on their lines.
- The benchmark's `firstLayout` keeps every bar and breaks the score at a sheet width of 100 staff spaces, and `update` keeps or relays each bar and resumes the breaks. Dense first layout went from 22.3 to 30.4 ms, dense update from 0.148 to 0.262 ms, spanner first layout from 133.7 to 171.8 ms and spanner update from 0.247 to 0.676 ms. The spanner first layout passed 160 ms, so it was profiled. Laying out the bars and dropping them costs what it did before the unit. The heads cost 0.3 ms on the dense score and 1.8 ms on the spanner score, and breaking and planning 0.5 and 1.7 ms. The rest, about 8 and 40 ms, appears when the bars are kept, and falls to 2 and 18 ms with a larger new generation. So it is the collector copying the kept bar layouts, which unit 4 built and no benchmark kept before. Nothing in this unit was changed for it. The medians are inside the budgets of 50 and 200 ms, and the spanner score has 28 ms left for units 6 to 10. The review ran the benchmark while other work used the machine and measured 181 ms, so the margin is thinner than it reads.
- The unit has 93 new tests in the layout package, which now has 214, and one in the root, which now has 96. 224 defects were planted one at a time, and every new test was failed by at least one of them. 220 were caught. The four that were not change no result. A bar's reach that also covers its courtesy is the same reach, because a courtesy's signs are in the inline head too. Resuming two units back instead of one, and never stopping early, cost time and break the same. The fourth is the dirty rule without its clause on a unit's last bar, above.
- The review found no crash and no case where resumed breaks differ from fresh ones, over 240,000 steps on made-up bar widths and 18,000 edits on a score of three parts. It found the last system's rule, the two repeat signs, the plan reuse across styles and the last-bar clause, each recorded above. It also found defects that the tests of the time let through, at the exact fit of a system, in the ragged rule, in the dirty rule's clauses on a unit's neighbours and in `startJoins`. Each has a test now.

**Unit 6.**
- `assembly.dart`, `system_layout.dart` and `sheet_layout.dart` are the sketch's files without what later units produce. Left out are ties, spanners, voltas and tuplets (units 7 and 8), lyrics with `SystemKey.carry`, `carryOut`, `staff.rows` and `lyricBaselines` (unit 9), and the hit testing of unit 10, which is `PlacedBar.voices` with `VoiceTimes`, `voiceOf` and `TupletSpan`, `SystemLayout.drawablesOf`, `boundsOf`, `staffNear`, `barAt` and `targetAt`, `TimeAxis.nearest`, `SpannerOwner`, `SheetLayout.hitTest`, `systemOfRef`, `boundsOf`, `caretOf`, `caretIn`, `selectionBoxes`, `selectionIn`, `playheadAt` and `playheadIn`, with `hit.dart` and `model_additions.dart`. `TextDraw` lands without `enclosed`, which the marks of unit 8 produce. The export list is the sketch's less those two files.
- `placeBarlines` takes `Framed<PlacedEdges>`, a bar's edges with the width of its placed head, as the unit 5 list said it would have to. A start repeat is drawn in the head's last group, which ends one head gap before the bar's first slice. When the head holds nothing else and the bar before ends in a regular barline, that barline is not drawn, since the sign stands in for it, as the unit 5 list said. The bar's last slice keeps the barline's rod. `startJoins` reads the inline head's items, not `printsKey`, `printsMeter` and `clefChanged` as the sketch did, because a restated C major and a key change under a percussion clef print nothing and left the barline against the sign. A double, final or other barline before a start repeat is still drawn. Whether it should be is not decided.
- A barline is a list of pieces, thin, thick, dashed, dotted or dots, and one function draws any list left to right with the font's separations. `endBarlineWidth` and `startRepeatWidth` read the same lists, so the room a bar keeps and the sign drawn in it cannot differ. The dots stand on every staff and the lines run over each group.
- The joined sign of an end repeat and a start repeat at one barline is centred on the boundary between the two bars, so its thick line stands where the barline would. The room of two signs that the unit 5 list recorded lies around it.
- A measure rest is centred by `BarItem.centred`. `BarFrame.xOf` gives a centred item the middle between its slice and the bar's end at the stretched xs, so the centre holds at every stretch, and `placeRest` no longer takes the slices' xs or the last slice. The unit 4 list said the system unit recentres it. This is how.
- `RestRun` takes `countRise`, the `rise` the sketch had and unit 5 left out. The count stands two spaces above the top line, and `restRunRise` is the digits' reach above that. The H-bar is the font's two end glyphs joined by a line as thick as its middle glyph, inset by a bar pad at each end, so it is as long as the system makes it.
- The bars of a rest run share the run's content evenly, from its first slice to its end, and the first bar keeps the head as a single bar does. The sketch shared the frame from its left edge, which put the first bar's time zero under the clef when the run started a system.
- `assembleSystem` takes no text measurer. Nothing it places is measured there. The lead's names are measured when the lead is built and bar numbers by the sheet. The sketch keeps the parameter for the lyrics of unit 9.
- There is no bracket. The model has no part group, so the lead draws a brace for a part of two staves or more and nothing over a group of parts. `SystemLead.braceRoom` is the room the braces take, and `placeLead` ends the names before it.
- The header is the title, the subtitle, then the lyricist at the left and the composer at the right on one line, each line one space under the one before, and the first system one system gap under the header. `ScoreMeta.copyright` is not printed. It belongs at the foot of a page, and the engine has no pages. The owner has not decided this.
- `LayoutDelta.rebroke` is true when the list of system starts differs from the one before. A blank bar inserted into a system's slack changes no start, so it relays its neighbours and rekeys its system without a rebreak.
- Two band limits are not asserted. A part name is centred on its part, and the plan keeps no room above the first staff for it, so a `partName` spec taller than the part's reach leaves the band, where the debug assert throws. Header text wider than the sheet starts at x 0 and overruns the width, and a lyricist and a composer that together are wider overlap. The default specs do neither.
- The benchmark's `firstLayout` is `SheetLayout(...)` alone, and `update` is `layout.update(next)`. Neither assembles a system, because the design budgets a first layout and a view assembles what it shows. Two unbudgeted lines report assembling every system after a first layout and assembling the rekeyed systems after an update. Dense first layout went from 25.994 to 28.031 ms, dense update from 0.249 to 0.347 ms, spanner first layout from 116.733 to 118.224 ms and spanner update from 0.647 to 1.062 ms. Assembling every system costs 2.4 ms on the dense score and 10.0 ms on the spanner score, and the rekeyed systems after an update cost less than the spread between runs.
- The root picture test measures text with `UiMeasurer`, which lays out a `dart:ui` paragraph at a probe size and divides, and loads the system's Arial for the text family when the file is there. No text font is bundled. `paintDrawables` draws a `TextDraw` with the paragraph's baseline on the drawable's origin. The test snaps each system's top to a whole pixel, as unit 5 snapped staff tops. The root package's SDK floor is 3.6, so its tests cannot use the null-aware elements the packages use until unit 13 raises it.
- The random check of test 6 runs 8 seeds of 400 edits on a score of three parts at a width between 12 and 150, drawn again after one edit in 25, with multi-measure rests off and on. It compares an updated sheet with a fresh one by width, header, tops, heights, labels and every system's drawables, bars and staves, and checks that every drawable and label lies in its band.
- The unit has 46 new tests in the layout package, which now has 260, and one in the root, which now has 149. 46 defects were planted one at a time, and every new test was failed by at least one. Two tests let a defect through at first, a courtesy drawn at the last slice and a count drawn without its rise, and both were strengthened until they caught it. A review on another model found the start repeat drawn beside the barline it stands in for, the shares of a rest run starting under the clef, and a last-bar test that could not fail. A second found the barline still drawn against the sign when the key the bar prints has no glyphs, and that no test pinned which barlines the sign replaces. Each is fixed, and a planted defect for each is caught. The first bar of a score prints its meter and so is never rest only, which is why the rest run tests start their run at the second bar.
- A review on a third model, after the unit landed, found a measure rest leaving its band on a sheet too narrow to space its bar. The rest is centred between its slice and the bar's end and had no reach, so a system pressed to its rods kept only the barline's room for it. `restReach` now gives a measure rest its glyph's width, which the spacing at stretch 1 already exceeds. The random check drew widths from 40, where no system is pressed. It now draws them from 12, and it fails on the old reach. The layout package has 262 tests.
- `SheetLayout.update` returns the same layout when nothing changed, as test 1 asks, and that layout keeps the delta it was built with. A view compares the two layouts before it reads `delta`. The field's comment says so.
- The test of the courtesy key found that a clarinet in B flat writes A major as B major, five sharps for three. The courtesy prints the written key, which is right, and the test says so.

**Unit 7.**
- `Skyline` and `Side` live in `bar_space.dart`, since this unit is their first producer. The sketch had them in `marks.dart`, which keeps `markReach` for unit 8. A skyline is a list of boxes scanned per query. `freeAbove` and `freeBelow` give the first free y outside everything placed over an x range, with the staff lines as the floor, and `above` and `below` are the outline's extremes, never negative. A box meets a range when the two x ranges touch.
- The bar measures every text a cross-bar piece prints. `SpannerPiece.textExtent` holds a tempo line's text and `VoltaStub.extent` the volta's label, so `placeSpanners` and `placeVoltas` take no measurer and `assembleSystem` keeps the signature unit 6 gave it. `TextExtent` gained value equality, because a stub holding one is compared by value. The sketch's `assembleSystem` still takes a measurer for the lyrics of unit 9.
- `headAnchors` does not land. The chord ink records each head's box as it is built, and `ChordPlan.headBoxes`, `ChordPlan.headsBox` and `GracePlan.headBoxes` expose them against the slice line. Ties, slurs and glissandi read their ends off those boxes, so a head's edge and a tie's end come from one box.
- B5 stays withdrawn, and `graceItems` draws the grace tie from `GraceChord.notes[i].tie` by the rule its withdrawal records. The tie joins the head of the same tone in the next grace chord, or in the principal after the last grace, and lets ring with no such head. It is a bar item of the principal's slice, owned by the principal's event, below the heads at the grace scale, since grace stems are up. `graceItems` takes the style for the font's tie thicknesses, and `graceTie` in `spanners.dart` builds the curve through the same `_tie` that `placeTies` uses.
- A tie over a barline takes its side from the leaving chord's stem, as a tie inside a bar does. A single head curves away from the stem. In a chord the lower half of the heads curve below, the upper half above, and an odd middle head away from the stem. The arriving bar cannot see the leaving chord, so `TieArriving` reserves `tieRise` on both sides from the bar's content start to its head, and the system draws the joined tie on the leaving side in room that is there either way. A tie whose target is in the bar but whose chord holds no head of that note lets ring, like a tie with no target.
- A let-ring tie is content right of its chord, like a dot or a flag. `letRingReach` widens its slice's reach before spacing, so the stub fits before the next slice or the barline. Test 6's band check found the case where it did not, a let-ring tie on a bar's last chord, which ran 1.5 spaces past the barline.
- A tie or slur arriving on a new system gets a stub at least `letRingLength` long before the head it lands on. The bar asks for the room through `arrivingRoom`, added to its system head, since that width counts only when the bar starts a system, and `assembleSystem` starts the stubs where the head glyphs end rather than at the content. The picture showed why. A bar whose first head sits at its lead left the arriving half of a tie 0.64 spaces long, a speck beside the note.
- `curveBetween` puts the control points a quarter and three quarters of the way along, each the same distance outward from its own end. The rise grows with the span up to `rise`. The raise then lifts the arc until its inner edge at a quarter and three quarters lies outside `clear`, and the clamp keeps its outer edge, read against the outer end, inside `limit`. The clamp wins. Only the middle half is raised, since the ends must come down to their notes, so a tall note beside a low end note can still touch a slur. The outward coordinate is `s * y` with s minus one above and one below, so both bounds read the same way on either side.
- A run cut by the system's end stops inside the band by half its ink's thickness, and a half tie does the same, so the curve's grown bounds stay inside the band. Every x of a run is clamped to the system's content start and right. The thin barline's rod equals the tie's inset, so a half tie ends exactly on the barline. A hairpin cut by the system's end is half open at the cut.
- `sliceTimes` adds the start of every hairpin, octave, pedal or tempo line that starts in the bar on a visible staff, so a line can start where nothing sounds. A slur, glissando or trill line starts on an event and needs no slice. A hidden staff's line adds no slice, since nothing of that staff is spaced.
- Every piece of a line kind reserves one height, computed from everything the kind can draw. A hairpin reserves its opening plus the hairpin's thickness. An octave line reserves the union of its glyph and both parentheses, and a pedal line the `Ped.` glyph, each plus the line's thickness, which the line needs where it runs at the glyph's baseline. A trill line reserves the union of the trill sign and the wiggle, and a tempo line its text's ascent and descent. So a continuation has room for the restated sign, and a run drawn at the outermost baseline of its pieces lies inside every piece's room.
- What a line starts with is content right of its start, like a dot or a flag. `lineStartReach` gives its slice the width of a tempo line's text, a pedal line's `Ped.`, an octave line's glyph or a trill line's sign, measured from the chord's centre when the line anchors on a chord, and the bar merges it with the chord reach before spacing, as it merges `letRingReach`. So a line that starts on a system's last beat has room for its text inside the system, and a start row or a text is drawn at its start and never moved. An octave line arriving on a new system asks for its restated row through `arrivingRoom`, as an arriving tie asks for its stub, so the row ends at or before the bar's first slice. The line after a row or a text is drawn only when it starts before its end, and a tempo line with empty text draws no text. The unit first landed with none of this. A row or a text moved left as one to fit, and the list claimed the band held. It did not. The random check at widths from 12 found a tempo text 4.85 spaces and a restated octave row 1.07 spaces past the right edge, where the content room was narrower than the row and the clamp's left bound won. Two tests now hold each case without the walk, a tempo, pedal, octave and trill line starting on a narrow sheet's last beat, and an octave line continuing onto a system whose clef and seven sharps leave less room than the row. Five defects were planted one at a time in the fix, and each test was failed by at least two. The layout package has 284 tests. Unit 8's `markReach` adds the reach of chord symbols, text directions, dynamics, tempo marks and the rehearsal mark beside `lineStartReach`, which stays in `spanners.dart` because it needs the planned chords for a trill's centre.
- A trill line starts with `ornamentTrill`, then `wiggleTrill` repeated to its end as one `GlyphRunDraw`. The count is the number of wiggles whose ink ends before the end x, and none is drawn when the first does not fit. The sketch drew the wiggle alone, and a wiggle alone does not read as a trill.
- `CurveDraw.dashed` is a flag on the curve, for `Slur.dashed`. The painter strokes the centreline instead of filling it. `pointAt` evaluates the cubic, `bounds` is the cubic's extremum box grown by the ink's allowance, and `hits` measures to a polyline of 17 points, so a curve is hit near its line and not anywhere in its box.
- `GlyphRunDraw` carries `count` and `bounds`. The producer sets `to` from the count and the glyph's advance and `bounds` from the glyph's box over the run, so the painter draws `count` copies evenly from `from` to `to` and measures nothing.
- `voltaStub` takes `headAbove`, the larger reach of the inline and system heads above the top staff, because the heads are not in the skyline and the label sits where a clef reaches. The bracket's free y is the lesser of the skyline's and that reach. The stub holds the label and its extent, whether the bracket starts, ends or is open there, the line's y and the hook's length, which is at least two spaces and enough for the label. The hooks are inset by half the line's thickness, so their outer edges are flush with the bracket's ends. The bracket's line and a barline share `repeatEndingLineThickness`, which is why the volta tests tell them apart by their height above the staff.
- `assembleSystem` collects the single bars with their frames and adds `placeTies`, `placeSpanners` and `placeVoltas` after the barlines, with the stubs' left at the first frame's left plus the width of the system head's glyphs. `sheet_layout.dart` and `signatures.dart` did not change. A test's `BarLayout` copy names the three new fields.
- The Flutter shell paints a curve as the crescent between two cubics whose control points sit `midThickness / 1.5` above and below the centreline's, filled and outlined `endThickness` wide with round joins. Moving both control points by `s` moves any point of the cubic by at most `0.75 s`, so the ink is `midThickness + endThickness` thick at the middle and stays inside `CurveDraw.bounds`. A dashed curve is its centreline stroked `midThickness` wide. One `dashPath` dashes lines and curves along the path's length, with the gap widened so the last dash ends where the path does, and a path too short for two dashes is stroked whole. Before it a dashed line could end on a sliver. `GlyphPainter.paintRun` draws the run's copies evenly from `from` to `to`. The picture test renders each curve, run and dashed line alone and measures its ink.
- The benchmark went from dense first layout 28.070 to 31.365 ms, dense update 0.352 to 0.375 ms, spanner first layout 119.514 to 135.053 ms and spanner update 1.071 to 1.092 ms. Every system assembled went from 2.323 to 2.650 ms on the dense score and from 10.281 to 11.066 ms on the spanner score. All are under budget, and under the 42 and 170 ms at which the unit would have been profiled before any change. The fix for what a line starts with measures a tempo line's text once more per bar and finds each line's start once more, and left every median within three percent of these, with dense first layout at 30.9 and 31.9 ms and spanner first layout at 133.5 and 136.7 ms over two runs.
- The unit has 20 new tests in `spanners_test.dart`, and the layout package now has 281. The model package has 768 and did not change, except that `withSlur` in its test support now delegates to `withSpanner`. `random_sheet_test.dart` also counts the `TieView`s, the spanners by kind and the bars under a volta it visits, and asserts each count is positive. Over 8 seeds of 400 edits with rests off it saw 20416 systems, 9330 `TieView`s and 4299 tied-in notes, 139988 spanner segments, 20451 bars under a volta and spanners of every kind, and with rests on 20114 systems and the same counts. The `pieceStart` and `pieceEnd` check compared 32026 segments over 4 seeds of 200 edits with the model's `anchorAt` and `lineEnd`. 27 defects were planted one at a time in the package, and every new test was failed by at least one. One got through at first. A grace tie that lost its principal fell back to a let-ring stub that ended 0.04 spaces short of where the joined tie ends, which the test's one-sided bound allowed. The test now asks for the same gap at both heads, and catches it. The root package has 152 tests, three of them new in `sheet_picture_test.dart`. Of 20 defects planted in its painters 19 were caught. The one that got through is a mitred stroke join at a curve's tip, whose overshoot is under the picture's one-pixel tolerance.
- A tie, a slur or a line that leaves a system stops at the end of the system's last barline, not at the system's right edge. `assembleSystem` passes `courtesyLeft` as the right of `placeTies` and `placeSpanners`. The first version passed the right edge, so a leaving tie, slur and hairpin ran across a courtesy key signature. A test holds a tie, a slur and a hairpin before the courtesy sharps. Twenty defects planted by the reviewer after the unit found seven behaviours no test pinned. They now have tests: a grace tie to the next grace chord, a tie's room under the lowest note on both sides of a system break, a slur's ends at the middle of its heads, a hairpin between the staff and a pedal line, an open volta without its right hook, two voltas side by side, and a volta clear of the clef. The layout package has 291 tests.
- A second-model review of the unit found three defects, each now held by a test. `BeamPlan.box` was one box round a whole beamed group, so a slur over a group with one far higher note ended over that note's height at both ends. It is now `BeamPlan.boxes`, the beam's own box and one box per stem, so the skyline over a note is that note's stem. A volta label wider than its bar left the band. `voltaLabelRoom` gives the least width of the bar a volta starts in, and `layoutBar` grows the bar's rods to it by equal shares with `widenedTo`, so `minBody` and line breaking see the room and the label always starts one pad after the left hook. The bar number stood inside a volta bracket that a later bar had raised. `planSystem` now sets the number over the highest bar of the bracket above the system's first bar. A fourth test pins the side of each tie in a chord. `SpannerPiece.voice` had no reader and is gone. One limit stays. `curveBetween` checks the curve against the room at a quarter and three quarters of its length, so a slur can still cross a tall note that stands right beside one of its ends. Lifting the nearer end is a design change and is left for the engraving pass. The layout package has 295 tests.

**Unit 8.**
- `markReach` runs last and takes the planned chords and the reach so far. The sketch called it first, with the view alone. A mark of an event is centred on its head, which only a planned chord knows, and what a wide mark still needs depends on the rods the notes already give. It returns the reach widened, and the bar merges it after the clef changes. Its `trills` are the events `trillLineStarts` finds.
- A wide mark does not widen its own slice alone. A direction or a tempo mark needs the rods from its slice to the next mark of its lane, or to the bar's end, to hold what it reaches to the right, and the rods before its slice to hold what it reaches to the left. What is missing is shared evenly by the slices in between. A lane is a staff's dynamics, its text above, its text below, its chord symbols, or the tempo marks. A segno, a coda, a rehearsal mark or a label is held at the bar's start or end and needs the whole bar. Giving one slice the whole width opened a gap as wide as the text after the mark's note. So a system of one bar pressed to its rods holds every mark between its content start and its end, the band holds at width 12, and assembly clamps nothing.
- `sliceTimes` adds the offset of every direction of a visible staff and of every tempo mark, so a mark can stand where nothing sounds, as unit 7 did for the start of a line.
- The fermata has its own function, `fermataItems`. The sketch drew it in `articulationItems`. It stands outside every other mark of its event, the ornament and the string marks included, so the bar calls it after them. A rest carries one too, and `articulationItems` reads a placed chord. A measure rest's fermata is a centred item like its rest and reserves the whole bar's width, since a stretch moves it against the slices. A hidden rest draws none.
- `BarLayout.restOnly` is false for a bar whose measure rest carries a fermata. `MeasureView.isRestOnly` lets such a bar through, and a multi-measure rest would hide the fermata. Any other articulation on a rest draws nothing and does not stop the fold. The rule belongs in the model's getter, which this unit does not change.
- Every function for the marks of an event takes `voices`, the number of voices on its staff. With two or more, every mark of an event stacks outside the staff on its voice's side, which is the stem side, and a fermata there is inverted. The sketch put articulations on the head side and everything else above, which puts the marks of a lower voice into the upper voice.
- Staccato and tenuto of a voice alone sit in the first space clear of the head. That is the next space for a head in a space and the one after it for a head on a line, as long as that space is inside the staff or between the staff and the head. The first mark that does not fit, and every mark after it, stacks outside the staff by the skyline. Accent, marcato and staccatissimo always stack outside the staff, on the head side, and the harmonic above. For a note whose head side faces into the staff, as a high note under a stems-up beam, outside is the far side of the staff. A nearer place for those is left to the engraving pass.
- `ornamentItems` takes `lineStarts`. Unit 7's trill line starts with the trill sign, so a chord with a trill that starts a trill line draws no sign of its own. The sketch left only the wiggle to the spanner, which would print the sign twice.
- `stringMarkItems` takes `strings`, the number of strings of the staff's instrument, because a string number counts from the highest string and a chord does not know its instrument. A string the instrument does not have draws nothing. A number above 9 prints as a roman numeral under either style, since the font has circled digits for 0 to 9 only. `TextRole.stringNumber` is new, 1.6 spaces. The marks stack as fingerings, then string numbers, then the bowing, and the marks of several heads keep head order with the highest head's on top.
- `dynamicGlyph` returns one glyph. The sketch's `dynamicGlyphs` returned a list and built `fp` from forte and piano. The font has `dynamicFortePiano`, and every `Dynamic` has a glyph of its own.
- A chord symbol is one row of text and `csym` glyphs scaled to the text. The generated table has the `csym` flat and sharp only. A double flat prints as two flats, and any other alteration prints the staff's accidental glyph on the baseline at the text's size.
- Each direction takes its own free room. Two chord symbols or two dynamics of one bar stand at different heights when the notes under them differ, and bars of one system do not share a baseline. A common baseline needs the system stage and is left to the engraving pass.
- A tempo mark is one row, its words, its metronome note, then `= ` and the number. The number is set at the tempo size without the bold. The note is a `metNote` glyph scaled to the text and lifted to stand on the baseline. `metronomeGlyphs` is empty for a breve and for a value shorter than a sixteenth, which the table has no glyph for, and a mark with such a beat prints its words alone. A whole number of beats per minute prints without a fraction.
- `systemMarkItems` takes `left`, the bar's content start. Segno, coda and the rehearsal mark start there, which is left of the first slice by the bar's lead. A label of `ToCoda`, `Fine` or `Jump` ends half a space before the bar's end. The picture showed why. A "To Coda" that ended on the barline touched the hook of an ending that started in the next bar. The marks stack as tempo marks, then signs, then labels, then the rehearsal mark outermost.
- `TextDraw.enclosed` is the sketch's flag. Its `bounds` are the box's outer edge, the text's extent grown by 0.3 spaces and the font's `textEnclosureThickness`, so the skyline and the band check hold the box. `paintEnclosure` in the Flutter shell strokes the line half its width inside the bounds.
- `tupletStubs` takes `staff` and `times`, which its anchors need. A tuplet goes on the side most of its chords' stems point to, above when the sides are even, and on its voice's side when it holds rests alone. The sketch said the beam side or the stem side, which a tuplet of mixed stems does not have. The bracket is level. Both anchors are at one height, the line through the middle of the number, and the stub reserves one row from its first event to its last, as high as its number. A sloped bracket is left to the engraving pass. `placeTuplet` leaves the bracket out when there is no room for a line on each side of the number. A tuplet under `TupletBracket.auto` has a bracket unless its events are exactly one beam group. `TupletStub` compares by value, as every stub of a `BarLayout` does, and its owner is the tuplet's first event.
- A tuplet prints its number alone when its ratio is the usual one for the number, and both numbers round `tupletColon` otherwise. The usual one is the largest power of two below the number, as 3:2, 5:4 and 6:4. A power of two is a tuplet only in compound time, so two stand for three and any other for three quarters of itself, as 4:3 and 8:6. The sketch named no rule. The rods between a tuplet's ends hold its number, and a tuplet of one event holds it in that event's reach and keeps the number's whole width clear in the skyline.
- Directions and system marks have no owner. `Owner` is an element or a spanner, and neither names a direction, a tempo mark, a rehearsal mark or a navigation mark. Unit 10 decides how they are hit.
- Decision 6 had every cross-bar piece reserve its room after the marks of its staff, and this unit is the first to put marks under one. Two reviews changed the order. System marks now stack after the slurs and lines. A blank score has a tempo mark in its first bar, so with the first order every slur from a score's first note started above the tempo, and a slur arriving on a new system floated above a rehearsal mark. Ties now reserve before every mark. A tie reads nothing from the skyline, and a mark that met no head of the tied chord sat at the staff's edge, so the tie ran through a chord symbol, a dynamic or a label over a held note. The order in `layoutBar` is ties, the marks of each staff, slurs and lines, system marks, the volta, and decision 6 says so now. A slur still starts above a text or a bowing that stands over its first note. One test holds a tempo and a rehearsal mark above a slur and an octave line, one holds a chord symbol, a dynamic and a label clear of a tie, and the unit 7 test that measures a slur's end from its head runs on a score with its tempo mark again.
- Marks stack at stretch 1, so in a bar pressed below it two marks of neighbouring slices can still meet. Such a bar is already wider than its system. Sideways every mark stays inside its bar at any stretch.
- The benchmark went from dense first layout 31.5 to 32.7 ms, dense update 0.378 to 0.392 ms, spanner first layout 142.4 to 147.3 ms and spanner update 1.093 to 1.165 ms. Every system assembled went from 2.86 to 2.87 ms on the dense score and from 11.6 to 12.4 ms on the spanner score. All are under budget. The unit first cost 36.8 ms on the dense first layout, 17 percent more than before. Skipping one call at a time showed 3 ms of that in the four mark functions, called for every event whether it carries a mark or not. `layoutBar` now asks `carriesMarks` first, as `markReach` does. The unbudgeted assembly line read 3.9 ms before that change. The systems held 1.1 percent more drawables and assembled in the same time once the young generation was large enough to keep a garbage collection out of the run, so that line moves with where a collection lands.
- The unit has 69 tests in `marks_test.dart`, and the layout package now has 366. The root has 154, two of them new in `sheet_picture_test.dart`, whose score now carries every mark of this unit. The seeded check lays out every bar that 1500 edited scores relaid, 4266 bars, at stretch 1 and 3 and pressed to its rods. It saw 25000 mark boxes, 430 tuplets, 3049 events with three or more mark parts and 158 staves with marks in two voices. No two boxes of a staff overlapped and every box stayed inside its bar. Every tuplet of the walk had a bracket, so a number alone is held by the named tests only. `random_sheet_test.dart` counts the marks and tuplets of the scores it lays out, 54473 marks and 3753 tuplets over 8 seeds of 400 edits with rests off and the same with rests on, and its band check holds them at widths from 12.
- 106 defects were planted one at a time, and every test of the unit was failed by at least one. Thirteen got through at first, and twelve now fail a test. They were the staff bound of an in-staff staccato, a measure rest's fermata reserving its own box alone, the side of a tuplet with even stems, the ratio rule at four and at a power of two, a bracket's start at a chord with a second, a bracket kept without room, a one-note tuplet reserving its head alone, a tuplet's number missing from the rods, a measure rest's fermata and a one-note tuplet's number missing from the reach, and `BarLayout` equality without its tuplets. The reach defects show only in a style with no padding at the bar's ends, which the pressed-bar test now also runs. The one still not caught removes the skyline entry of a staccato or tenuto placed in the staff. Such a mark is inside the staff or under its head, where the outline does not change, except for the 0.09 spaces by which a tenuto is wider than its head on each side. The review of the unit planted 28 more. Two got through, a lane whose marks were set with no space between them and a wide mark that gave every slice it spans the whole missing width, and each fails a test now.
- A second-model review read the unit without running it. It found the tie that ran through a mark, the fold rule that any articulation stopped, and an unreachable measure-rest arm in `_inkOf`. All three are fixed. Four of its notes are left. A fermata on a tuplet member stands inside the tuplet's bracket, where an engraver puts it outside. A text mark with no text still takes a slice. A dynamic is centred as under a black head, so it stands a little off under a whole note or a chord with a second. On a one-line staff a mark hangs from the five-line band, as ties and slurs do.

**Unit 12.**
- The unit ran before unit 11. That is safe because the player reads only `score_model` and publishes `position` as a `ValueListenable`, which is all `SheetView.playback` takes. It uses nothing of `SheetView` or `SheetLayout`, and its file does not import `score_layout`.
- The constructor takes two optional seams, `output` and `now`. A test passes the fake `MidiOutput` of `test/mock/` and a wall time it controls. An app passes neither and gets `FlutterMidiOutput` and a `Stopwatch`. The timer is a `dart:async` timer, which a widget test already fakes, so it needs no seam of its own.
- `MidiOutput` is in `lib/src/midi_output.dart` and is not exported, so an app cannot yet bring its own synthesizer. It has `load`, `program`, `noteOn`, `noteOff`, `allNotesOff` and `dispose`. Whether to export it is the owner's call.
- The note timer also sends the note offs. The design had it send each note, but the plugin holds a key until `stopNote`. So the timer sleeps until the next start or end of a note, and the player keeps the script second at which each sounding key ends.
- A timer set for a script second treats that second as reached when it fires. The wall time of a script second is rounded to a microsecond, and a platform's timer can be coarser than that, so a timer can fire a moment early. Reading the clock alone then sent nothing and set a timer of no length, again and again.
- A note that both starts and ends while the isolate is busy is not sent. A note that started in the stall and still sounds is sent late and ends on time.
- A note that began before `startAt` and still sounds there is not struck.
- A key that is struck again on its channel while it sounds is let go first and then held to the later of the two ends. Two voices of one part share a channel, and MIDI cannot hold one key twice. So every note on has exactly one note off.
- `stop` lets go of what sounds and then cuts all sound on every channel. The end of the script, `pause` and a new `play` only let go, so a release tail rings out.
- A loop wraps to the start of what `options` selects, wherever `startAt` began. A note that the end of the range cuts short is let go at the wrap. A script of no length does not loop.
- `position` is also published when playback starts and when it pauses, not only once per frame. So the first position waits for no frame, and a paused playhead stands where the sound stopped. Nothing is published at or past the script's end.
- A `play` replaces what is playing, and a `play` during loading takes the place of the one before it. Its future completes when playback has started, or when a later `play`, `stop` or `dispose` took its place. A call that was replaced does not fail, whatever becomes of the load or the programs it waited for. A failed load fails the future and leaves the player idle, and the next `play` loads again. A program that cannot be set does the same without a new load. A script of no length goes from loading to playing to idle at once.
- `play` compiles before it changes anything. A range that names a measure the score does not have fails the future with the compiler's `ArgumentError`, and what was playing plays on.
- The player is in one of four phases, idle, loading, playing or paused, and `status` shows which. At every change the status is written before the position, so a listener of `status` still reads the position from before the change. A listener of either may call `play`, `pause`, `resume` or `stop`, and the player then leaves its own change where the listener's call took over.
- Every `play` sets the program of every channel again and waits for all of them before the first note. They are all asked for at once, so the programs of an older call cannot land after those of a newer one. What that costs per `play` on iOS, where the plugin reads the SoundFont for each select, is not measured.
- A program the SoundFont lacks does not fail `play`. macOS reports it as `SOUND_FONT_LOAD_FAILED`, iOS as `SOUND_FONT_LOAD_FAILED2`, and Android not at all. The adapter swallows those two codes, so the three agree. Whether the channel then keeps its old sound or goes silent on iOS and macOS was not heard.
- The model's `bank` goes to the plugin unchanged, so a drum kit asks for bank 128 on channel 9.
- A quarter tone is a pitch bend of its whole channel, sent before its note and taken back by the next note that is not one. It assumes the default bend range of two semitones. A note held on the same channel bends with it. A channel is put at rest before its program is set unless the adapter itself last left it at rest. The adapter does not know whether a synthesizer keeps a bend across a new program. And on Android one synthesizer serves every SoundFont, so a new output can be given a channel that an output before it left bent.
- A `startAt` outside what is played starts at the beginning. `tempoScale` throws an `ArgumentError` unless it is positive and finite. `pause` does nothing unless playing, and `resume` nothing unless paused. `dispose` notifies no listener, and is not to be called from a listener of `status` or `position`, because a notifier cannot be disposed while it notifies.
- `score_model` moved from the root's dev dependencies to its dependencies. No other dependency changed. The player test builds its scores with the fixtures of `packages/score_model/test/support.dart`, by a relative import, the way the picture test reaches the fixtures of the layout package.
- The old `MidiPlayer`, its mixin and its tests are untouched and still exported. The doc of `SoundFont` still says that playback uses bank 0, program 0, which is true of the old player only. Unit 13 deletes the old player and corrects it.
- The player does not pause itself when the app goes to the background. The design does not ask for it, and an app can call `pause` from its own lifecycle observer.
- The wrap of a loop moves the clock back by the loop's length and keeps its anchor, where the sketch re-anchored at the loop's start. A timer wakes late when the isolate is busy, and up to a millisecond early because `dart:async` cuts a duration to whole milliseconds. Neither changes the loop's period, and a stall across the wrap is treated like a stall anywhere else. The first note of a pass can still sound that millisecond early.
- The player has 45 tests and the adapter has 7. Each of 81 defects was put into the code alone, and the tests caught all 81. One defect, a timer that fires early and sends nothing, shows as a test that never ends, because the fake timers then spin. A second review then put in 12 more. One got through, a position cleared on a frame just before a late loop wrap, and it has a test now. That review also found the bent channel on Android and the early wrap above, and added the tests of a listener that pauses or resumes from inside a change of status.
- A note, a note off or a bend that the plugin refuses is not waited for, so its error goes to the zone and not to the caller of `play`. The seam says nothing about a failed note.
- No sound was heard. The tests run against the fake output, and against a fake of the plugin's platform for the adapter. Nothing ran on a device.


## Open questions and risks

**Owner decisions of 2026-10-02.** The owner accepted every default below, C1 to C11, and the model additions B1, B2b, B2c, B3 and B4. `publish_to: none` on the root package is accepted too. The questions stay here as the record of what each default is.

Owner questions. Each is a parameter with a default, so the architecture does not wait:
- **C1.** Is a one-line staff's line the middle line (step 4) of a five-line staff? That is the default, and it keeps taps and heads on one step convention. It puts the showcase snare at C5, above the line, and the bass drum at F4, below it.
- **C2.** Should chord symbols on a transposing staff print as stored (`ChordSymbolSpelling.asStored`, the default) or as written?
- **C3.** Should an extender run to the last note before the next syllable or rest (`ExtenderEnd.beforeNextSyllable`, the default) or over ties and slurs only? The answer defines `Lyric.extend` for MusicXML import too. With the default, an extender typed over notes already entered underlines every later note up to the next rest until the next syllable is typed, and each system it crosses gains a lyric row meanwhile.
- **C4.** Should quarter tones use Stein-Zimmermann (the default, MusicXML's mapping) or Gould arrows?
- **C5.** Is the platform text font acceptable for lyrics and text, given that breaks may then differ by platform? Mongolian Cyrillic renders with platform fonts. Should BravuraText be used for inline metronome marks?
- **C6.** May Petaluma be dropped, with Bravura the only bundled font and `SmuflFont.fromMetadata` for others? The repository's Petaluma metadata is refused by `fromMetadata` as it stands (see the unit 1 reconciliation), so an app that wants Petaluma needs the font's full metadata. Is the unmodified OTF plus `OFL.txt` and a `LicenseRegistry` entry the license posture the owner accepts?
- **C7.** Should restating the meter on every system be offered? It is offered as `meterEverySystem`, off by default.
- **C8.** Should string numbers be circled digits (the default) or Roman numerals?
- **C9.** Is a brace per multi-staff part with a systemic barline, and no brackets across parts, acceptable until the model has staff groups?
- **C10.** Should spanners become selectable through a new `ElementRef` case? `SheetHit.target` can already report `SpannerOwner`, so the hit type does not change either way. Should a tap read earlier accidentals in the bar? That belongs in `toneForStaffStep`, not in layout.
- **C11.** Is a slur always above its notes, and below them in voices two and four, acceptable until the model can carry a slur's placement? An engraver puts a slur on the head side of stems-up notes.
- Are model additions B1, B2b, B2c, B3 and B4 accepted? B1 is needed for the playhead. B2b and B2c can fall back to layout-side rules with no change to this shape.

Left out of the first version, on purpose:
- **No semantics tree.** A canvas-drawn score is invisible to screen readers. A `Semantics` label per system tile is the cheap first step. Is that enough for the first release?
- **A grace note cannot be removed by a tap.** A hit on a grace head reports its principal, and the model has `AddGrace` but no edit that removes one grace. This is a model unit to add later, not a layout change.
- **No print or PDF path.** `toImage` renders a range of systems of the scrolling sheet. Pages would be a second breaker over system heights, which the plans already give.
- **No pinch gesture.** The controller's zoom is the size control, and each new zoom breaks lines again. A live pinch needs a transform above the viewport during the gesture, a scale recogniser that shares the arena with the scroll drag, a focal-point anchor and one relayout when the gesture ends. That is its own unit with its own test, after the view exists.

Risks:
- **Glyph placement through text on each platform.** Text layout of private-use codepoints and the baseline must agree on Android, iOS and macOS. The host passes with the rounded baseline. Android's and iOS's rasterisers are unmeasured. Gate 1 proves it before any layout code exists. If it fails, a path painter replaces `GlyphPainter`. That brings back an outline asset and the Reserved Font Name question.
- **Raster cost.** Every glyph is its own `drawParagraph`, and the engine replays a visible system's glyphs on every frame that changes, such as a scroll frame or a playback tick. Gate 1 measures it on the devices against a stated budget.
- **First layout of a large score.** It is unmeasured, and `Score.measureView` alone costs bars times spanners. Gate 2 measures both fixtures against a stated budget before the widget is built. If the small one misses, bars are laid out in visible order, with widths for the rest computed first. If the large one misses, the model indexes spanners by bar.
- **Text measurer purity.** A text font that loads after the first measurement would leave fallback widths in the measurer's cache and in every bar. The shell handles it, because the shell owns the measurer. `_SheetViewState` listens to `PaintingBinding.instance.systemFonts`, which fires for every font registered at run time, whichever package loaded it. The listener runs once per frame. It measures again every text the old measurer was asked for, and replaces the measurer and the layout only when an extent differs (`_afterFontsChanged` in the sketch). The cost is one pass of measurements per frame with a registration, and one full layout per late font the sheet's text uses.
- **Platform text font.** Lyrics and text use the platform font, so line breaks may differ per platform (C5). On-device goldens need a bundled text font.
- **Memo growth.** The memo holds every system that was ever looked at and still exists. After a full scroll through a long score that is every system. It is bounded by the system count and pruned on update, but it is not bounded by the viewport. Measure it on the 500-bar score before adding an eviction rule.
- **Limits of the band.** A bar reserves room without seeing its neighbours. Two lines over one staff can cross when one is pushed outward by a bar the other does not cover. A slur is raised over the notes under its middle half only, so a tall note beside a low end note can touch it. A system holding one bar wider than the sheet has a plan wider than the sheet. All of these stay inside the band. Are they acceptable until a system-level pass is worth its cost?
- **Publishing.** `score_layout` and `score_model` would have to be published before `simple_sheet_music` could go on pub.dev.

## Next implementation step

Prove glyph placement with gate 1 before writing any layout body.

The units, in order. Each ends in a check. No unit adds a function without its body. `layoutBar` and `assembleSystem` gain the call to a concern in the unit that implements it, so a test never has to pass a function that throws.

1. **Gate 1, glyph placement.** Create `packages/score_layout` with `geometry.dart`, `glyphs.dart`, `smufl_font.dart`, the generator and the generated table. Add `fonts/Bravura.otf`, and `SheetScale` and `GlyphPainter` with bodies. The check is that the generator reproduces the committed table byte for byte, and that gate 1's test passes for all 222 glyphs under `flutter test` on the host, then on an Android device and an iOS device, with the raster time reported.
2. **Gate 2, the benchmark harness.** Build both fixtures, the fake measurer and the compiled benchmark. The check is that it reports the floor that exists today (`changesSince` and the `measureView` calls) for both fixtures, and that it fails above the budget of decision 10.
3. **Model additions B1, B2b, B2c and the two doc changes.** The check is that `dart test` in `packages/score_model` passes with the exporter's tests unchanged and three new ones. `pointAt(secondsAt(p))` gives back p on every pass of a score with a repeat, a fermata, a tempo line and a tempo mark inside a bar. `barNumberOf` is 0 for a pickup. `Jump.label` is what the exporter writes.
4. **Spacing and chords.** `spacing.dart`, `chords.dart`, `beams.dart`, and `layoutBar` for notes and rests. The check is test 3 and test 8's lines for graces, drum heads, quarter tones, chords and beams.
5. **Signatures and breaking.** `signatures.dart`, `breaking.dart`. The check is test 2 and test 6's comparison of starts and stretches, both run on `breakSystems` with and without `previous`, since `SheetLayout` arrives in the next unit, and gate 2.
6. **Assembly.** `assembly.dart`, `SheetLayout` with the memo. The check is tests 1 and 7, test 8's lines for braces, hidden parts, rest runs and pickup numbers, and gate 2.
7. **Spanners.** Ties, spanner pieces, `pieceStart` and `pieceEnd`, voltas, the skyline reservations. The check is test 7 with its two slur cases, test 6 on drawables, test 8's volta line, the agreement of `pieceStart` and `pieceEnd` with the model, and gate 2.
8. **Marks.** Articulations, ornaments, string marks, directions, system marks, tuplets. The check is test 8's line for marks, test 7 and gate 2.
9. **Lyrics.** Syllables, rows, the two carry passes, hyphens and extenders. The check is test 8's two lines for the carry, and gate 2 on the now complete engine.
10. **Hit and overlay queries.** The check is tests 4 and 5.
11. **The view.** `SheetView`, the painters, the measurer, scroll anchoring, the font listener and `toImage`. The check is tests 9 and 10 and gate 1 still passing, plus two more widget tests. A late font the sheet's text uses replaces the layout once, and one it does not use leaves the layout identical. `toImage` of a range has the planned height times the pixel ratio, and a range over the limit throws. The first layout is measured once on a device with `ParagraphMeasurer` (gate 2).
12. **The player.** `ScorePlayer` over a MIDI output seam, with a hand-written fake in `test/mock/`. The check is test 11.
13. **The example app rewrite and the deletion of the old engine.** The check is that `flutter analyze` at the root reports no issues, that `flutter test` at the root and `dart test` in `packages/score_model` and `packages/score_layout` pass, that both gates pass, and that the example runs on macOS. `CLAUDE.md` gains the new package's commands and layout in the same change.
