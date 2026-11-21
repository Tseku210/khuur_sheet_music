---
title: The layout engine
description: How khuur_score_layout turns a Score into positioned drawables, and why it spaces, breaks, caches and measures the way it does.
sidebar:
  order: 3
---

`khuur_score_layout` turns a `Score` into systems of glyphs, lines, curves and text, each placed in staff spaces. `SheetLayout` is its entry point. You build one with `SheetLayout(score, width:, text:)` and call `update(score, width:)` with every new score value. The Flutter shell draws what the engine places and sends taps back to it. [The architecture page](/khuur_sheet_music/explanation/architecture/) shows where the engine sits between the model and the screen.

The engine is pure Dart. Its tests run with `dart test`, with no widget binding, and it cannot name `Offset`, `Rect` or `Paint` because it cannot import them. The one thing it needs from the platform is the size of a piece of text. That comes through a port with one method, `TextMeasurer.measure(String, TextSpec)`, which the shell implements with `dart:ui` paragraphs.

## Every length is in staff spaces

A staff space is the distance between two lines of a staff. Every length the engine stores is in staff spaces, with y growing downward, from one of three origins:

- bar space, with x from a slice of the bar and y from the top line of a staff;
- system space, from the top-left corner of a system's band;
- sheet space, from the top-left corner of the header, with the systems stacked below it.

A staff step maps to y in one function, `yOfStep`, which is `(8 - step) / 2`. Step 8 is the top line of a five-line staff and step 0 the bottom one. Bar layout, `PlacedStaff` and the hit test all call it, so a drawn head and a tapped position cannot disagree.

Text sizes are in staff spaces too (`TextSpec.size`), so a bar lays out the same at every zoom. Pixels exist only in the shell's `SheetScale`, at `staffSpace × zoom` logical pixels per staff space. Zoom still changes the sheet's width in staff spaces, so a new zoom breaks lines again, over bars it already laid out.

## The pipeline runs in four stages

Each stage reads only what the stage before it produced.

1. Bar layout. `layoutBar` lays out each bar alone into a `BarLayout`.
2. Line breaking. `breakSystems` reads each bar's `BarWidths` and decides where each system starts.
3. Planning. `planSystem` fixes each system's stretch, staff tops and height. It draws nothing.
4. Assembly. `assembleSystem` places one system's drawables. `SheetLayout.systemAt(i)` runs it the first time someone asks for system `i`.

Stages 1 to 3 run on every `update`. Stage 4 runs only for the systems a reader asks for, so a view that shows five systems of a hundred assembles five. The sheet still knows every system's top and height, because planning gives them.

The source files follow notation, not stages. `chords.dart`, `beams.dart`, `marks.dart`, `spanners.dart`, `lyrics.dart` and `signatures.dart` each hold what a bar decides alone and what a system draws from it. To change how a notation is drawn, you change one file.

## A bar is laid out alone

`BarLayout` is the unit of the cache, one per `MeasureId`. It is a function of three inputs, the bar's `MeasureView`, the `EngravingStyle` and the `TextMeasurer`. `layoutBar` takes no `Score`, and a `BarLayout` holds no bar number, no x on a line and nothing about its neighbours.

That invariant makes the cache correct. `Score.changesSince` names the bars whose views may differ, which are the edited bars and their neighbours. Every other `BarLayout` stays valid, and `update` reuses it by reference.

A bar cannot know which system it lands on, so it stores every choice that depends on that. `BarHeads` holds an `inline` head for a bar in the middle of a system, a `system` head for a bar that starts one, and a `courtesy` head that the system before draws at its end. `BarWidths` holds the matching numbers, `inlineHead`, `systemHead`, `courtesy`, `body` and `minBody`. A system from bar i to bar j is this wide at natural spacing, plus its indent:

```text
systemHead(i) + sum of body(i..j) + sum of inlineHead(i+1..j) + courtesy(j+1)
```

A piece that crosses a barline, such as a tie, a slur, a hairpin or a volta, is decided by the bar too. The bar stores a stub with the piece's anchors and the room it reserved, and assembly joins the stubs of consecutive bars on one system.

## Spacing uses springs and rods

`spacing.dart` spaces a bar with springs and rods. The slices are the distinct moments of the bar, from every onset of every visible staff and voice, every clef change, direction and tempo mark, the start of each hairpin, octave, pedal or tempo line, and the bar's end. Every staff shares the slices, so events at the same moment line up down the system.

The spring after a slice follows the shortest duration `d` that starts there. Its ideal length is `quarterSpace × ratio^log2(d / quarter)`, scaled down when the next slice comes before `d` ends. With the default `SpacingPolicy`, a quarter note gets 3.5 staff spaces, and each doubling of duration multiplies that by 1.41. This is Gourlay's rule on an absolute scale instead of one set per system. A rod is the least distance between two slices, the right reach of one plus `minGap` (0.4) plus the left reach of the next.

Justification solves one stretch factor `s` per system, so that the sum over all slices of `max(rod, ideal × s)` fills the width (`stretchFor`). Rods never stretch, which is why one linear map from natural x to final x cannot replace this solve. The last system stays ragged when it fills less than `justifyLastSystemFrom` (0.75) of the width. With `justify` off, every system keeps its natural width, so a bar added at the end never respaces the bars before it. A system whose rods are wider than the sheet is squeezed either way.

A system whose rods are wider than the sheet is squeezed in two stages, as MuseScore's `squeezeSystemToFit` does (`Fit`). It first gives up the `minGap` in each rod, and nothing overlaps yet. If that is not enough, every gap between two slices is scaled down by one factor. The notes then overlap, but they stay in order, each on its own x while the system's head leaves room, because a bar that runs off the sheet cannot be read at all. Heads, barlines and the lead of each bar keep their width. A slice keeps the room of what cannot leave its line, which is its notes, rests, syllables and tie ends. A mark gives way instead. One that would pass the end of a squeezed bar moves left to end there (`BarFrame.hold`), and the bar is never narrower than its widest mark (`BarLayout.markRoom`). So the system is wider than the sheet only when the widest mark or the widest note of a bar, with the part names, the heads and the barlines, is wider than it. Where a note is what is too wide, the notes of that bar share one x.

The absolute scale has a cost. A bar of whole notes beside a bar of sixteenths spaces less evenly than one solve over the whole system would. In exchange, a bar's spacing depends on nothing outside the bar, so the bar can be cached alone.

## Line breaking is greedy so that edits stay local

`breakSystems` is greedy first-fit. A system takes bars while its natural width fits, and takes its first bar whatever that bar's width is. A bar with `breakBefore` starts a system, and a page break counts as one, because the view has no pages. A bar wider than the sheet gets a system to itself and is squeezed to the sheet. With `multiMeasureRests` on, a run of two or more rest-only bars becomes one `RestRun` unit. It is off by default, because an editor needs every bar visible to write into.

Greedy is a choice for stability. Where a system starts depends only on where the one before it started and on the widths from there, so an edit never moves an earlier system. An optimal breaker can reflow the whole score for one wider bar and make the page jump while someone writes. The cost is that a greedy system can be looser than an optimal one.

Stability also lets breaking resume. `_dirty` finds the units whose widths, `breakBefore`, last bar, neighbours or following courtesy changed. With none, the old starts stand, as the same list. Otherwise greedy resumes at the start of the system that holds the unit before the first dirty one, and stops at the first new start past the last dirty unit that was an old start. `BarWidths` compares by value, so a bar laid out again at the same widths changes no break. The courtesy clause is the subtle one, because a system's end reads the courtesy width of the bar after it. A seeded test in `packages/khuur_score_layout/test/random_breaks_test.dart` compares resumed breaking with breaking from scratch. Run it whenever you touch `_dirty` or the resume.

## Planning fixes each system's height before anything is drawn

`planSystem` solves the stretch and takes, per staff, the largest reach above and below over the system's bars, widened by the next bar's courtesy head. It adds room for the bar number, the lyric rows and a part name taller than its staves, and stacks the staves.

The sheet stacks systems by planned height alone, so assembly must draw nothing outside the band from (0, 0) to (`plan.width`, `plan.height`). `assembleSystem` asserts that on every drawable, within `bandTolerance`, a millionth of a staff space. Three rules keep cross-bar pieces inside:

- Each bar reserves room in its staff's `Skyline` for every piece that crosses it, in a fixed order. Ties come first. Then come each staff's marks, its tuplets and its directions, then slurs and lines, then the marks over the top staff, and the volta goes outermost. The reserved room is part of the bar's reach, so the plan already holds it.
- A stub stores both edges of the room it reserved, and assembly reads that room instead of working it out again.
- A slur takes one side for its whole length, from the spanner alone (`curveSide`). It is above, and below in voices two and four. A side taken from each bar's stems could differ between bars and leave the slur with room on neither side.

Assembly fits each curve into its room, so a long slur is flatter than an engraver would draw it. A bar reserves room without seeing its neighbours, so a system can be a little taller than a whole-system solve would make it. Both costs buy heights that are known before anything is drawn.

## An edit pays only for what it touches

Bars are cached by `MeasureId`, and breaks resume as above. Plans and assembled systems are cached by `SystemKey`, which holds everything a system is a function of. It holds the system's bars and the next system's first bar by identity, the width, the part list's lead, whether the system is first or last, and the lyric hyphens and extenders open at each end. `update` reuses a plan whose key is unchanged and carries over every assembled system whose key still exists, as the same object. The shell's system painter repaints only when it gets a different object.

Take one note entered in bar 250 of a 500-bar score of four staves. `changesSince` names bars 249, 250 and 251, so three `layoutBar` calls run. If their widths hold, breaking returns the old starts. Only the systems that hold those bars get new keys, along with the system before when one of them starts a system. If those systems are off screen, nothing is assembled. The rest is about 500 identity checks and width comparisons.

`update` returns the same layout when the score is the same object and the width is unchanged. `LayoutDelta` reports what an update did. `relaid` names the bars laid out again, `rekeyed` the systems with new keys, and `rebroke` whether the starts changed. Tests assert work through `delta` and object identity, with no counters. A change of style or of text measurer needs a new `SheetLayout`.

## Glyphs come from SMuFL metadata, generated into Dart

SMuFL, the Standard Music Font Layout, gives each music symbol a name and a codepoint. A SMuFL font ships metadata with each glyph's bounding box, advance and anchors, such as where a stem joins a notehead, and engraving defaults such as the thickness of a staff line, all in staff spaces.

The package ships Bravura 1.392, unmodified, as `fonts/Bravura.otf`, and draws each glyph as one character of text. One em is four staff spaces, and a glyph's origin is on the text baseline, as in SMuFL. Text keeps the font as its licence describes it, since the SIL Open Font License reads a converted file as a Modified Version that cannot keep the name. It also keeps the assets small, about 517 KB with the licence against about 4.25 MB for SVG outlines with JSON metadata, and every consuming app ships every package asset.

The metrics live in `lib/src/bravura.g.dart`, a const table that `tool/generate_bravura.dart` writes from `tool/bravura_metadata.json`, so nothing is parsed at run time. The generator and `SmuflFont.fromMetadata` share one reader, `readSmuflMetadata`. It flips y once into the engine's frame and throws one `FormatException` that lists every failure:

- a `Glyph` with no box, or an inverted one;
- a `Glyph` with no advance;
- an anchor that `GlyphAnchor` lacks;
- a numeric engraving default that is in the metadata but not in `EngravingDefaults`, or the other way round.

So the `Glyph` enum (226 values), `GlyphAnchor` (19 anchors), `EngravingDefaults` (28 lengths) and the font cannot drift apart without a failure. A new glyph is a new `Glyph` value and a rerun of the generator, which formats its output and leaves the table as it is when the metadata has not changed:

```bash
cd packages/khuur_score_layout && dart run tool/generate_bravura.dart
```

An app that wants another SMuFL font passes `SmuflFont.fromMetadata(family:, metadata:)` in its style. Two fonts are equal when they share a family, the same glyph table object and equal defaults. So parse the metadata once and keep the font, or every build makes a new style and a full layout.

The glyph gate proves that each glyph lands where its box says. `test/glyph_placement_test.dart` draws every `Glyph` through `GlyphPainter` and compares the painted ink with the table's box, and `example/integration_test/glyph_gate_test.dart` runs the same check on devices. The gate found that a paragraph draws its baseline on a whole pixel and reports it unrounded, which is why `GlyphPainter` rounds the baseline it subtracts.

## A drawable is a value with an ink role and an owner

A `SystemLayout` holds its `Drawable`s in system space, a `PlacedBar` with a `TimeAxis` for each bar, and a `PlacedStaff` for each staff. `Drawable` is sealed, with six kinds: `GlyphDraw`, `LineDraw`, `PolygonDraw` for beams, `CurveDraw` for ties and slurs, `GlyphRunDraw` for trill lines, and `TextDraw`, which carries the bounds the `TextMeasurer` gave, so the painter never measures. The shell's painter switches over the kinds exhaustively, so a new kind fails compilation until something paints it.

Each drawable has an `InkRole`, such as `notehead`, `slur` or `barNumber`. The shell's `SheetPalette` maps roles to colours, so a theme change only repaints. Each drawable also has an `Owner?`, either `ElementOwner(ElementRef)` or `SpannerOwner(SpannerId)`, so it cannot belong to a note and a spanner at once. Structure has no owner, which covers staff lines, barlines, clefs, signatures, a beam between stems and a tuplet's number and bracket. A grace head is owned by its principal's event, because a grace chord has no reference of its own.

Drawables compare by value. The incremental tests compare an updated layout with a fresh one drawable by drawable.

## Hit testing reads the same geometry as painting

Painting, hit testing, the caret, selection boxes and the playhead all read the same `SystemLayout`, and nothing records positions while painting. `SheetLayout.hitTest(point, voice:, grid:, reach:)` turns a point in sheet space into a `SheetHit` in five steps:

1. It finds the system by binary search of the tops. A point in the gap between two systems belongs to the nearer one.
2. It takes the owned drawable nearest the point within `reach`, by `Drawable.distanceTo`. At equal distance a notehead wins, then any other part of an event, then a spanner.
3. When that target is an element, the hit takes its event's staff, voice and onset from the score.
4. Otherwise it takes the bar under x, the staff with the nearest middle line, the asked voice, and a time from `snapTime`.
5. It takes the staff step nearest the point.

`distanceTo` measures to the box, except that a curve and a sloped line measure to their line, because a slur's box covers every note under its arc. The view passes a finger's reach, `kTouchSlop` over its pixels per staff space, so a stem about a tenth of a staff space wide can still be hit.

`snapTime` picks an onset of the voice within one staff space of the tap. Otherwise it picks the nearest grid point, and inside a tuplet the grid lies in written time, so a triplet of eighths on a sixteenth grid has six points. A snapped time is never the end of a bar. `entryAt` runs steps 1, 4 and 5 alone, for a finger held down to place a note, where a rest under it would otherwise pull the time to the rest's onset.

Clefs, key signatures, time signatures and tempo marks own no drawable, so `hitTest` gives them no target. Assembly records each of them in `SystemLayout.signatures` instead, as one box for each staff, kind and point, with the bar it takes effect from. That is the bar a head stands before, the next system's first bar for the courtesy signs at the end of a system, the bar and offset of a clef that changes inside a bar, and the bar and offset of a tempo mark, on the top staff it stands over. `SheetLayout.signatureAt(point, reach:)` finds the system as step 1 does and takes the box nearest the point within `reach`. It gives that sign only when no owned drawable lies as near, so a note beside a clef keeps its taps.

## The benchmark holds layout to a cost budget

Layout runs synchronously on the UI isolate, so an edit and its picture arrive in the same frame, and a user feels layout cost. `benchmark/layout_benchmark.dart` gates it on two fixtures. `denseScore` has 500 bars of four staves, with beamed eighths and sixteenths, a second voice, a lyric under every sung note, a dynamic and a slur in every bar, and a hairpin over every fourth barline. `spannerScore` has the same music for 2,000 bars, with 2,500 spanners. They are dense because a score of whole-bar rests would meet any budget.

| Measurement | Budget |
|---|---|
| First layout of the dense score | 50 ms, which is 100 µs per bar of four staves |
| Update after one entered note in the dense score | 1 ms |
| First layout of the spanner score | 200 ms |

The budgets assume a mid-range phone is four times slower than the development machine. That gives 200 ms once, when a large score opens, and 4 ms per edit, inside a 16 ms frame. The spanner score exists because `Score.measureView` reads the spanners that touch a bar, and a cost that grows with bars times spanners shows there first.

The benchmark also reports, without budgets, assembling every system, an update with its rekeyed systems assembled, `hitTest`, `caretOf` and `playheadAt`. Each first layout runs on a fresh copy of the score, so it pays for the indexes a newly loaded score builds. Each measurement is the median of 31 runs after 5 warm-ups. Run it compiled, because a JIT run measures the compiler as much as the code:

```bash
cd packages/khuur_score_layout && mkdir -p build && dart compile exe benchmark/layout_benchmark.dart -o build/layout_benchmark && build/layout_benchmark
```

It exits with code 1 when a measurement is over budget. CI does not run it, because the budgets are timed on the development machine. Rerun it after every change to the engine.

## What to keep true when you change the engine

These invariants carry the design. Breaking one breaks something far from the change.

- A `BarLayout` is a function of its `MeasureView`, the style and the text measurer. A fact a bar needs from its neighbour belongs in the view, so that `changesSince` relays the bar out when the fact changes.
- Line breaking reads only `BarWidths`. Anything that changes a system's width changes a bar's widths.
- A `SystemKey` holds everything a system is a function of. An input missing from the key gives stale systems after an update.
- Assembly draws inside the planned band. Room for a new mark is reserved in the bar's skyline, not found at assembly time.
- Lengths stay in staff spaces, and only `SheetScale` in the shell knows pixels.
- The benchmark stays inside its budget.

The seeded test in `random_sheet_test.dart` guards most of these. It compares an updated sheet with a fresh one in its header, tops, starts, bar numbers and drawables, and checks every drawable against its band. The benchmark guards the last.
