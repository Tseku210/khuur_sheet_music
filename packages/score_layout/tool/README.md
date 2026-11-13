# The Bravura metadata and the glyph table

`bravura_metadata.json` is the SMuFL metadata of Bravura 1.392, Steinberg's music font. It comes from the Bravura release at https://github.com/steinbergmedia/bravura.

Steinberg licenses Bravura and its metadata under the SIL Open Font License 1.1. The licence text, with Steinberg's copyright line, is in [`fonts/OFL.txt`](../../../fonts/OFL.txt).

`generate_bravura.dart` reads the metadata and writes `lib/src/bravura.g.dart`. That file is the const table of the font's engraving defaults and of the box, the advance width and the anchors of each glyph the engine draws. Its numbers are Bravura's, so the same licence covers them. Do not edit it by hand.

To write the table again, run the generator.

```bash
cd packages/score_layout && dart run tool/generate_bravura.dart
```

A run over unchanged metadata leaves the table as it is.
