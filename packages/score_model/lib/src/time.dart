/// Notated time: exact rationals, note values, tuplet ratios, meters, tempo.
///
/// All musical time in the model is a [Fraction] of a whole note, wrapped
/// in one of two types: a [Moment] is a point, a [Length] is a span. There is no
/// `double` anywhere in notated time, so a triplet eighth is exactly 1/12 and
/// measure fill is an exact equality. Seconds appear only in playback output.
library;

import 'spelling.dart';

/// An exact rational number, always normalized (lowest terms, positive
/// denominator). Used for durations and offsets in whole-note units.
final class Fraction implements Comparable<Fraction> {
  factory Fraction(int numerator, [int denominator = 1]) {
    if (denominator == 0) {
      throw ArgumentError.value(denominator, 'denominator', 'must not be 0');
    }
    var n = numerator;
    var d = denominator;
    if (d < 0) {
      n = -n;
      d = -d;
    }
    final g = _gcd(n.abs(), d);
    return Fraction._(n ~/ g, d ~/ g);
  }

  const Fraction._(this.numerator, this.denominator);

  static const zero = Fraction._(0, 1);
  static const one = Fraction._(1, 1);

  final int numerator;
  final int denominator;

  bool get isZero => numerator == 0;
  bool get isNegative => numerator < 0;
  bool get isPositive => numerator > 0;

  Fraction operator +(Fraction other) => Fraction(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  Fraction operator -(Fraction other) => this + -other;

  Fraction operator -() => Fraction._(-numerator, denominator);

  Fraction operator *(Fraction other) =>
      Fraction(numerator * other.numerator, denominator * other.denominator);

  Fraction operator /(Fraction other) =>
      Fraction(numerator * other.denominator, denominator * other.numerator);

  bool operator <(Fraction other) => compareTo(other) < 0;
  bool operator <=(Fraction other) => compareTo(other) <= 0;
  bool operator >(Fraction other) => compareTo(other) > 0;
  bool operator >=(Fraction other) => compareTo(other) >= 0;

  double toDouble() => numerator / denominator;

  @override
  int compareTo(Fraction other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  @override
  bool operator ==(Object other) =>
      other is Fraction &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() =>
      denominator == 1 ? '$numerator' : '$numerator/$denominator';

  static Fraction sum(Iterable<Fraction> values) =>
      values.fold(zero, (total, value) => total + value);
}

/// A point in notated time: whole notes from the start of the bar that
/// holds it (or of the clip, for copied music). Adding two moments does not
/// compile; a moment plus a [Length] is a moment, and the distance between
/// two moments is a [Length].
extension type const Moment(Fraction wholeNotes) {
  static const zero = Moment(Fraction.zero);

  bool get isZero => wholeNotes.isZero;
  bool get isNegative => wholeNotes.isNegative;
  bool get isPositive => wholeNotes.isPositive;

  Moment operator +(Length length) => Moment(wholeNotes + length.wholeNotes);
  Moment operator -(Length length) => Moment(wholeNotes - length.wholeNotes);

  /// Signed distance from this moment to [later].
  Length until(Moment later) => Length(later.wholeNotes - wholeNotes);

  bool operator <(Moment other) => wholeNotes < other.wholeNotes;
  bool operator <=(Moment other) => wholeNotes <= other.wholeNotes;
  bool operator >(Moment other) => wholeNotes > other.wholeNotes;
  bool operator >=(Moment other) => wholeNotes >= other.wholeNotes;
  int compareTo(Moment other) => wholeNotes.compareTo(other.wholeNotes);
}

/// A span of notated time in whole notes: a note's length, a bar's
/// capacity, a gap. A quarter note is 1/4.
extension type const Length(Fraction wholeNotes) {
  static const zero = Length(Fraction.zero);
  static const whole = Length(Fraction.one);

  bool get isZero => wholeNotes.isZero;
  bool get isNegative => wholeNotes.isNegative;
  bool get isPositive => wholeNotes.isPositive;

  Length operator +(Length other) => Length(wholeNotes + other.wholeNotes);
  Length operator -(Length other) => Length(wholeNotes - other.wholeNotes);

  /// Scales by an exact factor, such as [TupletRatio.scale].
  Length operator *(Fraction factor) => Length(wholeNotes * factor);

  /// How many times [unit] fits in this length, exactly.
  Fraction operator /(Length unit) => wholeNotes / unit.wholeNotes;

  bool operator <(Length other) => wholeNotes < other.wholeNotes;
  bool operator <=(Length other) => wholeNotes <= other.wholeNotes;
  bool operator >(Length other) => wholeNotes > other.wholeNotes;
  bool operator >=(Length other) => wholeNotes >= other.wholeNotes;
  int compareTo(Length other) => wholeNotes.compareTo(other.wholeNotes);

  static Length sum(Iterable<Length> lengths) =>
      lengths.fold(zero, (total, length) => total + length);
}

int _gcd(int a, int b) {
  var x = a;
  var y = b;
  while (y != 0) {
    final t = y;
    y = x % y;
    x = t;
  }
  return x == 0 ? 1 : x;
}

/// The undotted shape of a note or rest.
enum DurationBase {
  breve(2, 1),
  whole(1, 1),
  half(1, 2),
  quarter(1, 4),
  eighth(1, 8),
  sixteenth(1, 16),
  thirtySecond(1, 32),
  sixtyFourth(1, 64),
  oneTwentyEighth(1, 128);

  DurationBase(this._numerator, this._denominator);

  final int _numerator;
  final int _denominator;

  Length get length => Length(Fraction(_numerator, _denominator));

  /// Number of beams (or flags) this value carries. Zero for quarter and up.
  int get beams => index <= DurationBase.quarter.index
      ? 0
      : index - DurationBase.quarter.index;
}

/// A written duration: a base value plus up to three dots. What the composer
/// picks from the palette. Its sounding length inside a tuplet is scaled by
/// the tuplet ratio; see [TupletRatio.scale].
final class NoteValue {
  const NoteValue(this.base, {this.dots = 0})
    : assert(dots >= 0 && dots <= 3, 'at most three dots');

  static const whole = NoteValue(DurationBase.whole);
  static const half = NoteValue(DurationBase.half);
  static const quarter = NoteValue(DurationBase.quarter);
  static const eighth = NoteValue(DurationBase.eighth);
  static const sixteenth = NoteValue(DurationBase.sixteenth);
  static const thirtySecond = NoteValue(DurationBase.thirtySecond);

  final DurationBase base;
  final int dots;

  /// Written length: base × (2 − 1/2^dots).
  Length get length {
    final p = 1 << dots;
    return base.length * Fraction(2 * p - 1, p);
  }

  NoteValue get dotted => NoteValue(base, dots: dots + 1);

  @override
  bool operator ==(Object other) =>
      other is NoteValue && other.base == base && other.dots == dots;

  @override
  int get hashCode => Object.hash(base, dots);

  @override
  String toString() => '${base.name}${'.' * dots}';
}

/// `actual` notes in the time of `normal`: a triplet is 3:2.
final class TupletRatio {
  const TupletRatio(this.actual, this.normal)
    : assert(actual > 0 && normal > 0, 'ratio terms are positive');

  static const duplet = TupletRatio(2, 3);
  static const triplet = TupletRatio(3, 2);
  static const quintuplet = TupletRatio(5, 4);

  final int actual;
  final int normal;

  /// Multiply a written length by this to get the sounding length.
  Fraction get scale => Fraction(normal, actual);

  @override
  bool operator ==(Object other) =>
      other is TupletRatio && other.actual == actual && other.normal == normal;

  @override
  int get hashCode => Object.hash(actual, normal);

  @override
  String toString() => '$actual:$normal';
}

enum MeterSymbol { numeric, common, cut }

/// A time signature. [groups] are additive numerators (`[3, 2, 2]` is 7/8
/// grouped 3+2+2; `[4]` is plain 4/4) so beaming and rest splitting follow
/// the composer's grouping instead of a guess.
final class Meter {
  /// [groups] must be non-empty; `scoreFromJson` rejects an empty list.
  const Meter(this.groups, this.unit, {this.symbol = MeterSymbol.numeric});

  Meter.simple(int beats, int unit) : this([beats], unit);

  static const fourFour = Meter([4], 4);
  static const threeFour = Meter([3], 4);
  static const twoFour = Meter([2], 4);
  static const sixEight = Meter([6], 8);
  static const common = Meter([4], 4, symbol: MeterSymbol.common);
  static const cut = Meter([2], 2, symbol: MeterSymbol.cut);

  final List<int> groups;

  /// Denominator. A power of two.
  final int unit;

  final MeterSymbol symbol;

  int get numerator => groups.fold(0, (a, b) => a + b);

  /// Nominal bar length. A column's actual capacity can differ only through
  /// an explicit `MeasureColumn.irregularLength` (pickups, cadenzas).
  Length get length => Length(Fraction(numerator, unit));

  /// True for 6/8, 9/8, 12/8, 6/4 and similar: the beat is a dotted unit.
  bool get isCompound =>
      groups.length == 1 && numerator % 3 == 0 && numerator > 3 && unit >= 4;

  /// Offsets from the bar start where a beat begins. Used by beaming, by the
  /// cursor's beat-snap, and by [spell].
  List<Moment> get beatOffsets {
    final step = isCompound ? 3 : 1;
    final beats = groups.length > 1
        ? groups
        : List.filled(numerator ~/ step, step);
    final offsets = <Moment>[];
    var at = Moment.zero;
    for (final beat in beats) {
      offsets.add(at);
      at += Length(Fraction(beat, unit));
    }
    return offsets;
  }

  /// Offsets where default beams break. 4/4 breaks at the half bar, 3/4
  /// beams the whole bar, 6/8 breaks per dotted quarter, additive meters
  /// break per group.
  List<Moment> get beamBreaks => throw UnimplementedError();

  /// Splits a span that starts at [offset] into note values that can be
  /// written, respecting the beat structure. Used whenever the model must
  /// write a length that no single note value has: tie splits at a barline,
  /// rest fills after an overwrite, re-barring. Rests split more eagerly
  /// than notes (a rest never crosses a beat in simple meter).
  ///
  /// Invariant: the lengths of the result sum to [length].
  List<NoteValue> spell(
    Moment offset,
    Length length, {
    required bool rest,
  }) => spellOnGrid(BeatGrid.meter(this), offset, length, rest: rest);

  @override
  bool operator ==(Object other) =>
      other is Meter &&
      other.unit == unit &&
      other.symbol == symbol &&
      _listEquals(other.groups, groups);

  @override
  int get hashCode => Object.hash(unit, symbol, Object.hashAll(groups));

  @override
  String toString() => '${groups.join('+')}/$unit';
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Metronome tempo: [bpm] beats of [beat] per minute.
final class Tempo {
  const Tempo(this.bpm, {this.beat = NoteValue.quarter})
    : assert(bpm > 0, 'tempo is positive');

  /// The tempo of music before its first tempo mark.
  static const unmarked = Tempo(100);

  final double bpm;
  final NoteValue beat;

  /// Seconds that [length] (whole-note units) lasts at this tempo.
  double secondsFor(Length length) =>
      (length / beat.length).toDouble() * 60 / bpm;

  @override
  bool operator ==(Object other) =>
      other is Tempo && other.bpm == bpm && other.beat == beat;

  @override
  int get hashCode => Object.hash(bpm, beat);
}
