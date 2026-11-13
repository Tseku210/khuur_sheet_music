import 'package:score_layout/score_layout.dart';
import 'package:test/test.dart';

import 'support/fake_measurer.dart';

List<double> extentOf(String text, TextSpec spec) {
  final extent = const FakeMeasurer().measure(text, spec);
  return [extent.width, extent.ascent, extent.descent];
}

void main() {
  test('text is 0.6 of its size wide per character, 0.8 up and 0.2 down', () {
    expect(extentOf('sol', const TextSpec(size: 2)), [
      closeTo(3.6, 1e-12),
      closeTo(1.6, 1e-12),
      closeTo(0.4, 1e-12),
    ]);
    expect(extentOf('', const TextSpec(size: 5)).first, 0);
  });

  test('the style and the family do not change the extent', () {
    expect(
      extentOf(
        'sol',
        const TextSpec(size: 2, italic: true, bold: true, family: 'Serif'),
      ),
      extentOf('sol', const TextSpec(size: 2)),
    );
  });

  test('a character outside the basic plane counts once', () {
    expect(
      extentOf('\u{1D11E}', const TextSpec(size: 2)).first,
      extentOf('a', const TextSpec(size: 2)).first,
    );
  });
}
