import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The import is what is tested. A name it exports hides the same name of
// `dart:ui` with no message.
// ignore: unused_import
import 'package:simple_sheet_music/simple_sheet_music.dart';

void main() {
  test("Clip is still Flutter's in a file that imports the library", () {
    expect(const Stack(clipBehavior: Clip.none).clipBehavior, Clip.none);
  });
}
