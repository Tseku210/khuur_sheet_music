import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

void main() {
  group('a fraction', () {
    test('is kept in lowest terms over a positive denominator, so equal '
        'values are equal and hash alike', () {
      final built = Fraction(6, -4);
      expect((built.numerator, built.denominator), (-3, 2));
      for (final (unreduced, reduced) in [
        (Fraction(2, 4), Fraction(1, 2)),
        (Fraction(-1, -2), Fraction(1, 2)),
        (Fraction(1, -2), Fraction(-1, 2)),
        (Fraction(6, 3), Fraction(2)),
        (Fraction(0, -5), Fraction.zero),
        (-Fraction.zero, Fraction.zero),
      ]) {
        expect(unreduced, reduced);
        expect(unreduced.hashCode, reduced.hashCode);
      }
      expect(Fraction(1, 2), isNot(Fraction(1, 3)));
    });

    test('orders by value, across signs and denominators', () {
      final ascending = [
        Fraction(-1, 2),
        Fraction(-1, 3),
        Fraction.zero,
        Fraction(1, 3),
        Fraction(1, 2),
        Fraction(2, 3),
      ];

      expect(ascending.reversed.toList()..sort(), ascending);
      expect(Fraction(1, 3) < Fraction(1, 2), isTrue);
      expect(Fraction(1, 2) < Fraction(2, 4), isFalse);
      expect(Fraction(1, 2) <= Fraction(2, 4), isTrue);
      expect(Fraction(-1, 2) > Fraction(-1, 3), isFalse);
      expect(Fraction(2, 3) >= Fraction(2, 3), isTrue);
    });

    test('adds, subtracts, multiplies and divides into lowest terms', () {
      expect(Fraction(1, 3) + Fraction(1, 6), Fraction(1, 2));
      expect(Fraction(1, 6) - Fraction(1, 2), Fraction(-1, 3));
      expect(Fraction(1, 2) - Fraction(2, 4), Fraction.zero);
      expect(Fraction(2, 3) * Fraction(3, 4), Fraction(1, 2));
      expect(Fraction(1, 2) / Fraction(-1, 4), Fraction(-2));
    });

    test('has no zero denominator, built or divided by', () {
      expect(() => Fraction(1, 0), throwsArgumentError);
      expect(() => Fraction(1, 2) / Fraction.zero, throwsArgumentError);
    });
  });

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
