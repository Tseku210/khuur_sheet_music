---
title: Fonts and licences
description: The fonts the sheet draws with, the licences of the code and the bundled files, and the libraries that playback brings into an app.
sidebar:
  order: 4
---

## Fonts

| Text | Font |
| --- | --- |
| Music: notes, rests, clefs, accidentals, dynamics and other marks | Bravura, Steinberg's music font, bundled as `fonts/Bravura.otf` |
| Titles, lyrics and other text | The platform's default font, unless `TextSpec.family` names another |

The same text on every platform needs a font that the app bundles and names in `TextSpec.family`.

`SmuflFont.bravura.flutterFamily` names the Bravura family as Flutter knows it, for an app that draws the sheet's glyphs in its own widgets.

## Licences

| Part | Licence | File |
| --- | --- | --- |
| The code of all three packages | MIT License | `LICENSE` in each package |
| Bravura | SIL Open Font License 1.1 | `fonts/OFL.txt` |

`SheetView` registers `fonts/OFL.txt` with Flutter's `LicenseRegistry`, so the page that `showLicensePage` opens lists Bravura with its licence.

The package bundles no SoundFont. A SoundFont that an app plays is the app's own, under its own licence.

## Libraries that playback brings in

`khuur_sheet_music` depends on [`khuur_synth`](https://github.com/Tseku210/khuur_synth), so an Android or iOS app that uses the library ships it. `khuur_synth` is MIT. It bundles FluidSynth, under the GNU Lesser General Public License 2.1 or later, and on Android libsndfile, under the same licence, with other libraries under Apache-2.0 and BSD-3-Clause. Its `LICENSE` lists each of them, and `showLicensePage` shows them. The conditions that the LGPL puts on an app are in the [README of `khuur_synth`](https://github.com/Tseku210/khuur_synth#licences-and-the-lgpl).
