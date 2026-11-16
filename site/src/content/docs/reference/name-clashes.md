---
title: Name clashes
description: The two names that the score model and Flutter both declare, the error they cause, and the import that avoids it.
sidebar:
  order: 3
---

`package:khuur_sheet_music/khuur_sheet_music.dart` exports all of the score model. Two of the model's names are also names in Flutter.

| Name | In the score model | In Flutter |
| --- | --- | --- |
| `Interval` | The distance between two pitches, such as `Interval.majorThird` | The curve of `package:flutter/animation.dart` |
| `Step` | The letter of a pitch, `Step.c` to `Step.b` | One step of a `Stepper` |

`package:material_ui/material_ui.dart` exports both of Flutter's names, as `package:flutter/material.dart` does.

## The error

A file that imports both libraries compiles while it uses neither name. A file that uses either name does not compile. The analyzer reports `ambiguous_import` at each use.

## Imports that compile

A `hide` on one of the two imports leaves one declaration of each name. A file that uses Flutter's names hides the model's.

```dart
import 'package:khuur_sheet_music/khuur_sheet_music.dart' hide Interval, Step;
import 'package:material_ui/material_ui.dart';
```

A file that uses the model's names hides Flutter's.

```dart
import 'package:khuur_sheet_music/khuur_sheet_music.dart';
import 'package:material_ui/material_ui.dart' hide Interval, Step;
```
