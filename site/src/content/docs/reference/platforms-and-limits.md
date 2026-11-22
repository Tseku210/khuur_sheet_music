---
title: Platforms and limits
description: The platforms the sheet and playback run on, the version floors of each package, and what the library does not do.
sidebar:
  order: 2
---

## Platforms

| Platform | Sheet and editing | Playback through `SynthOutput` |
| --- | --- | --- |
| Android | Yes | Yes, on API 24 (Android 7.0) or later |
| iOS | Yes | Yes, on iOS 15 or later, with Swift Package Manager |
| macOS | Yes | No |
| Linux, Windows | Not tested | No |
| Web | Yes | No |

Playback runs through FluidSynth from [`khuur_synth`](https://github.com/Tseku210/khuur_synth). On a platform other than Android and iOS, the future of `ScorePlayer.play` fails with `SynthUnavailable`. A `ScorePlayer` that is given a `MidiOutput` of the app's own plays through that output instead.

On the web the library builds with both compilers, dart2js and dart2wasm. CI builds the example app with each, and runs the tests in `test/web/` in Chrome.

`khuur_score_model` and `khuur_score_layout` are pure Dart. They run anywhere Dart runs, the web included.

## Version floors

| Package | Version | Dart | Flutter |
| --- | --- | --- | --- |
| `khuur_sheet_music` | 0.5.0 | 3.13 | 3.47.5 |
| `khuur_score_model` | 0.5.0 | 3.13 | Not used |
| `khuur_score_layout` | 0.5.0 | 3.13 | Not used |

`khuur_sheet_music` depends on `khuur_synth` 0.2.0 or a later 0.2 release, and on `material_ui` 1.11.0 or a later 1.x release. An app made with `flutter create` on Flutter 3.47.5 meets the Android and iOS floors of `khuur_synth` with no change.

## Limits

- A staff draws five lines, or one line when its `lines` is 1. A staff of 2, 3, 4 or 6 lines loads and keeps its count, and draws as five lines.
- Tablature is not drawn.
- The sheet is one scrolling column of systems. It has no pages and no PDF export. `SheetController.toImage` draws a range of systems.
- One image from `toImage` holds at most `SheetController.maxImageSide` device pixels on a side, which is 8192.
- The sheet scrolls up and down only. A bar wider than the view is squeezed to fit it. Its notes may then overlap, but they keep their order, and a mark moves left to stay inside the bar. A bar is cut at the view's edge only when its widest mark or its widest note, with the part names and brace, clef and signatures before the bar, is wider than the view.
- The sheet never scales a score to fit a box. It breaks lines at its width and draws at `staffSpace` times the zoom.
- The zoom is the controller's `zoom`. The view has no pinch gesture.
- `ScoreMeta.copyright` is not printed on the sheet.
- The sheet takes its colours from the `Theme` of `material_ui`. Under a `MaterialApp` of `package:flutter/material.dart` it finds no theme and draws in the light default colours.
- The package bundles no SoundFont. The app supplies every SoundFont it plays.
- Each SoundFont takes 16 of FluidSynth's 256 channels, so one `SynthOutput` plays from at most 16 SoundFonts.
- On iOS only SF2 files load. FluidSynth's iOS build has no SF3 support.
