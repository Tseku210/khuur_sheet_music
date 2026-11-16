---
title: Export an image
description: Draw a SheetView's sheet into an image, save it as PNG, and export a long score in several images.
sidebar:
  order: 6
---

This guide draws the sheet of a `SheetView` into a `ui.Image` and saves it as a PNG file.

## Export the whole sheet

Ask the view's `SheetController` for the image. The view must be on screen and have drawn at least one frame.

```dart
final image = await _sheet.toImage(pixelRatio: 3);
```

`pixelRatio` is the number of device pixels per logical pixel. To save the image, encode it as PNG and write the bytes.

```dart
import 'dart:io';
import 'dart:ui' as ui;

Future<void> _export(String path) async {
  final image = await _sheet.toImage(pixelRatio: 3);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  await File(path).writeAsBytes(png!.buffer.asUint8List());
}
```

The image is the sheet as the view draws it, with these differences:

- It has no cursor, preview, selection, tints or playhead.
- It has no padding of the view.
- Its background is the palette's `paper`, or transparent when the palette has none. The palette the view takes from the theme has none.

The image has the view's width, zoom and palette. To export in other colours, give the view another palette, as [Change the look](/khuur_sheet_music/guides/change-the-look/) describes.

## Export a long score in several images

One image holds at most `SheetController.maxImageSide` device pixels on a side, which is 8192. To export a longer score, pass `from` and `to` and make one image for each range of systems. `systemCount` gives the number of systems.

```dart
Future<List<ui.Image>> _exportInParts({int perImage = 4}) async {
  final images = <ui.Image>[];
  final count = _sheet.systemCount;
  for (var from = 0; from < count; from += perImage) {
    final to = from + perImage < count ? from + perImage : count;
    images.add(await _sheet.toImage(from: from, to: to, pixelRatio: 2));
  }
  return images;
}
```

`to` is not in the range, so `from: 0, to: 4` draws the first four systems. The header, with the title, the subtitle, the composer and the lyricist, is in the image only when `from` is 0.

## Fix an export that throws

`toImage` throws in these cases:

- A range taller than `maxImageSide` throws an `ArgumentError`. Export fewer systems in each image.
- A sheet wider than `maxImageSide` throws an `ArgumentError`. Every range is as wide as the sheet, so lower `pixelRatio`.
- An empty range throws an `ArgumentError`, and a range outside the sheet throws a `RangeError`.
- A controller with no view that has laid out a sheet throws a `StateError`.

## Related pages

- [Change the look](/khuur_sheet_music/guides/change-the-look/) sets the palette and its paper.
- [Place widgets over the sheet](/khuur_sheet_music/guides/widgets-over-the-sheet/) covers the rest of what the controller reports.
- [Show a score](/khuur_sheet_music/guides/show-a-score/) puts the view on screen.
