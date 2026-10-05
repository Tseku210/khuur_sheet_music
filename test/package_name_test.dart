import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/glyph_gate.dart';

void main() {
  test('the bundled music font is asked for under the family Flutter gives a '
      'font of this package, which holds the name in pubspec.yaml', () {
    final package = RegExp(
      r'^name: (\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(bravuraPainter().family, 'packages/$package/Bravura');
  });
}
