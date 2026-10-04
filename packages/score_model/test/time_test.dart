import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

void main() {
  test('each duration base lasts half the one before it, from a breve of two '
      'whole notes, as a fraction in lowest terms', () {
    expect(
      [for (final base in DurationBase.values) base.length],
      [
        for (final denominator in [1, 2, 4, 8, 16, 32, 64, 128, 256])
          Length(Fraction(2, denominator)),
      ],
    );
  });

  test('each dot adds half of what the one before it added', () {
    expect(
      [
        for (var dots = 0; dots <= 3; dots++)
          NoteValue(DurationBase.quarter, dots: dots).length,
      ],
      [
        Length(Fraction(1, 4)),
        Length(Fraction(3, 8)),
        Length(Fraction(7, 16)),
        Length(Fraction(15, 32)),
      ],
    );
  });
}
