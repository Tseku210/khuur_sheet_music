---
title: Draw the sheet's glyphs in your own widgets
description: Show a note value, a rest, an accidental, a dynamic, a bowing or a fingering in a toolbar or a palette with the same glyph the sheet engraves.
sidebar:
  order: 10
---

This guide draws a value of the score in your own widget, such as a button in a note palette, with the glyph that the sheet engraves it with.

## Get the glyph of a value

Each function below returns the `Glyph` of a value. The sheet takes its glyph for that value from the same function, so your widget and the sheet always agree.

| Function | Glyph |
| --- | --- |
| `noteGlyph(DurationBase)` | The note as one glyph, stem up with its flags, as a tempo mark prints it. |
| `restGlyph(DurationBase)` | The rest. |
| `accidentalGlyph(Alter, QuarterToneGlyphs)` | The accidental. The `QuarterToneGlyphs` family changes only the quarter-tone accidentals. |
| `dynamicGlyph(Dynamic)` | The dynamic, `fp` and `sfz` included. |
| `bowingGlyph(Bowing)` | The up-bow or down-bow mark. |
| `fingeringGlyphs(int)` | The digits of a finger number, left to right, as a list. |

## Draw the glyph as text

Draw the glyph's `codepoint` as one character in the font family that `flutterFamily` names. That is the family the sheet draws in.

```dart
Text(
  String.fromCharCode(restGlyph(DurationBase.quarter).codepoint),
  style: TextStyle(
    fontFamily: SmuflFont.bravura.flutterFamily,
    fontSize: 24,
  ),
)
```

A glyph's origin is on the text's baseline, and one em is four staff spaces. To draw a glyph at the size the sheet draws it, give a font size of four times the view's `staffSpace`, times the zoom.

## Add the dots of a dotted value

`noteGlyph` and `restGlyph` take a `DurationBase`, which has no dots. Draw one `Glyph.metAugmentationDot` after a note for each dot, and one `Glyph.augmentationDot` after a rest.

```dart
Widget valueLabel(NoteValue value, {double staffSpace = 8}) {
  final glyphs = [
    noteGlyph(value.base),
    for (var dot = 0; dot < value.dots; dot++) Glyph.metAugmentationDot,
  ];
  return Text(
    String.fromCharCodes([for (final glyph in glyphs) glyph.codepoint]),
    style: TextStyle(
      fontFamily: SmuflFont.bravura.flutterFamily,
      fontSize: 4 * staffSpace,
    ),
  );
}
```

## Match the sheet's style

The sheet spells quarter-tone accidentals with its style's `quarterTones`, and draws with its style's `font`. Pass the same style to your widget, so that it shows what the sheet shows.

```dart
Widget sharpButton(EngravingStyle style) => Text(
  String.fromCharCode(
    accidentalGlyph(Alter.sharp, style.quarterTones).codepoint,
  ),
  style: TextStyle(fontFamily: style.font.flutterFamily, fontSize: 24),
);
```

For the bundled Bravura, and for a copy of it with other engraving defaults, `flutterFamily` is the family with the prefix that Flutter gives a package's font. For a font that your app declares, it is the font's own `family`.

## Measure a glyph

`SmuflFont.bravura[glyph]` gives the glyph's metrics in staff spaces. `box` is the bounding box of its ink, and `advance` is how far the next glyph's origin sits to the right. The y axis points down from the baseline. Multiply by the staff space in pixels to size a widget around the glyph.

```dart
double glyphWidth(Glyph glyph, double staffSpace) =>
    SmuflFont.bravura[glyph].box.width * staffSpace;
```

## Related pages

- [Change the look of the sheet](/khuur_sheet_music/guides/change-the-look/)
- [Fonts and licences](/khuur_sheet_music/reference/fonts-and-licences/)
- [How the layout engine works](/khuur_sheet_music/explanation/layout-engine/)
