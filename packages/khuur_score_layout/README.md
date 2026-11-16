# khuur_score_layout

A layout engine for sheet music, in pure Dart. It takes a `Score` from [`khuur_score_model`](https://pub.dev/packages/khuur_score_model) and breaks it into systems of positioned glyphs, lines and text, ready to draw. It also answers where a tap on the sheet lands.

It has no Flutter dependency. [`khuur_sheet_music`](https://pub.dev/packages/khuur_sheet_music) draws its output on a Flutter `Canvas`. Another renderer, such as SVG or PDF, can draw the same output.

## Features

- `SheetLayout` lays a score out at a given width and breaks it into systems. It assembles a system only when something asks for it, so a long score costs only the systems on screen.
- `SheetLayout.update` lays out only the bars that an edit changed.
- `SystemLayout` holds a system's `Drawable`s: glyphs of the Bravura font, lines, beams, curves and text, positioned in staff spaces.
- `hitTest` and `entryAt` turn a point on the sheet into a note, a mark or the place where a new note would go. `caretOf`, `selectionBoxes` and `playingIn` give the boxes that an editor and a player highlight.
- `EngravingStyle` sets the engraving defaults, and `TextMeasurer` lets the host measure text with its own fonts.

## Install

```bash
dart pub add khuur_score_layout khuur_score_model
```

## Use

```dart
import 'package:khuur_score_layout/khuur_score_layout.dart';
import 'package:khuur_score_model/khuur_score_model.dart';

/// Measures text as if every character were 0.6 of the font size wide.
final class MonospaceMeasurer implements TextMeasurer {
  const MonospaceMeasurer();

  @override
  TextExtent measure(String text, TextSpec spec) => TextExtent(
    width: text.runes.length * 0.6 * spec.size,
    ascent: 0.8 * spec.size,
    descent: 0.2 * spec.size,
  );
}

void main() {
  final score = Score.blank(
    parts: [
      const PartTemplate(
        name: 'Flute',
        instrument: Instrument(key: 'flute', program: 73),
      ),
    ],
    measureCount: 12,
  );
  final layout = SheetLayout(
    score,
    width: 100,
    text: const MonospaceMeasurer(),
  );
  for (var index = 0; index < layout.systemCount; index++) {
    final system = layout.systemAt(index);
    print('System $index: ${system.bars.length} bars');
  }
}
```

All lengths are in staff spaces, the distance between two lines of a staff. Multiply by the size of a staff space on your page to draw. The [example](example/khuur_score_layout_example.dart) enters notes and prints where each system lands.

## More

The [repository](https://github.com/Tseku210/khuur_sheet_music) has the guides, the architecture and the issue tracker. The package is part of `khuur_sheet_music` and is released with it.

## Licence

The code is MIT. See [LICENSE](LICENSE). The glyph table `lib/src/bravura.g.dart` holds numbers from the metadata of Bravura, Steinberg's music font, under the SIL Open Font License 1.1. See [OFL.txt](OFL.txt).
