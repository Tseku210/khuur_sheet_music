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
  /// The fraction [numerator]/[denominator], reduced to lowest terms with a
  /// positive denominator. Throws [ArgumentError] when [denominator] is 0.
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

  /// Zero, as 0/1.
  static const zero = Fraction._(0, 1);

  /// One, as 1/1.
  static const one = Fraction._(1, 1);

  /// The numerator in lowest terms. Carries the sign.
  final int numerator;

  /// The denominator in lowest terms. Always positive.
  final int denominator;

  /// Whether this fraction is 0.
  bool get isZero => numerator == 0;

  /// Whether this fraction is below 0.
  bool get isNegative => numerator < 0;

  /// Whether this fraction is above 0.
  bool get isPositive => numerator > 0;

  /// Whether this fraction is a whole number.
  bool get isInteger => denominator == 1;

  /// The greatest integer not above this fraction; rounds negatives down.
  int floor() => numerator >= 0
      ? numerator ~/ denominator
      : -((-numerator + denominator - 1) ~/ denominator);

  /// The exact sum, reduced.
  Fraction operator +(Fraction other) => Fraction(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  /// The exact difference, reduced.
  Fraction operator -(Fraction other) => this + -other;

  /// This fraction with its sign flipped.
  Fraction operator -() => Fraction._(-numerator, denominator);

  /// The exact product, reduced.
  Fraction operator *(Fraction other) =>
      Fraction(numerator * other.numerator, denominator * other.denominator);

  /// The exact quotient, reduced. Throws [ArgumentError] when [other] is 0.
  Fraction operator /(Fraction other) =>
      Fraction(numerator * other.denominator, denominator * other.numerator);

  /// Whether this fraction is less than [other].
  bool operator <(Fraction other) => compareTo(other) < 0;

  /// Whether this fraction is less than or equal to [other].
  bool operator <=(Fraction other) => compareTo(other) <= 0;

  /// Whether this fraction is greater than [other].
  bool operator >(Fraction other) => compareTo(other) > 0;

  /// Whether this fraction is greater than or equal to [other].
  bool operator >=(Fraction other) => compareTo(other) >= 0;

  /// This fraction as a `double`, which may round. Notated time stays exact;
  /// this is for output such as playback seconds.
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
  String toString() => isInteger ? '$numerator' : '$numerator/$denominator';

  /// The exact sum of [values], or [zero] when there are none.
  static Fraction sum(Iterable<Fraction> values) =>
      values.fold(zero, (total, value) => total + value);
}

/// A point in notated time: whole notes from the start of the bar that
/// holds it (or of the clip, for copied music). Adding two moments does not
/// compile; a moment plus a [Length] is a moment, and the distance between
/// two moments is a [Length].
extension type const Moment(Fraction wholeNotes) {
  /// The start of the bar or clip.
  static const zero = Moment(Fraction.zero);

  /// Whether this moment is the start.
  bool get isZero => wholeNotes.isZero;

  /// Whether this moment is before the start.
  bool get isNegative => wholeNotes.isNegative;

  /// Whether this moment is after the start.
  bool get isPositive => wholeNotes.isPositive;

  /// The moment [length] later.
  Moment operator +(Length length) => Moment(wholeNotes + length.wholeNotes);

  /// The moment [length] earlier.
  Moment operator -(Length length) => Moment(wholeNotes - length.wholeNotes);

  /// Signed distance from this moment to [later].
  Length until(Moment later) => Length(later.wholeNotes - wholeNotes);

  /// Whether this moment is earlier than [other].
  bool operator <(Moment other) => wholeNotes < other.wholeNotes;

  /// Whether this moment is earlier than or at [other].
  bool operator <=(Moment other) => wholeNotes <= other.wholeNotes;

  /// Whether this moment is later than [other].
  bool operator >(Moment other) => wholeNotes > other.wholeNotes;

  /// Whether this moment is later than or at [other].
  bool operator >=(Moment other) => wholeNotes >= other.wholeNotes;

  /// Orders moments by time, earliest first.
  int compareTo(Moment other) => wholeNotes.compareTo(other.wholeNotes);
}

/// A span of notated time in whole notes: a note's length, a bar's
/// capacity, a gap. A quarter note is 1/4.
extension type const Length(Fraction wholeNotes) {
  /// No time.
  static const zero = Length(Fraction.zero);

  /// One whole note.
  static const whole = Length(Fraction.one);

  /// Whether this length is 0.
  bool get isZero => wholeNotes.isZero;

  /// Whether this length is negative.
  bool get isNegative => wholeNotes.isNegative;

  /// Whether this length is positive.
  bool get isPositive => wholeNotes.isPositive;

  /// The two lengths end to end.
  Length operator +(Length other) => Length(wholeNotes + other.wholeNotes);

  /// This length minus [other]. Can be negative.
  Length operator -(Length other) => Length(wholeNotes - other.wholeNotes);

  /// This length scaled by [factor], as a [TupletRatio.scale] scales a
  /// written length.
  Length operator *(Fraction factor) => Length(wholeNotes * factor);

  /// How many times [unit] fits in this length, as an exact ratio. Throws
  /// [ArgumentError] when [unit] is 0.
  Fraction operator /(Length unit) => wholeNotes / unit.wholeNotes;

  /// Whether this length is shorter than [other].
  bool operator <(Length other) => wholeNotes < other.wholeNotes;

  /// Whether this length is shorter than or equal to [other].
  bool operator <=(Length other) => wholeNotes <= other.wholeNotes;

  /// Whether this length is longer than [other].
  bool operator >(Length other) => wholeNotes > other.wholeNotes;

  /// Whether this length is longer than or equal to [other].
  bool operator >=(Length other) => wholeNotes >= other.wholeNotes;

  /// Orders lengths shortest first.
  int compareTo(Length other) => wholeNotes.compareTo(other.wholeNotes);

  /// The total of [lengths], or [zero] when there are none.
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
  return x;
}

/// The undotted shape of a note or rest. Each length is written in lowest
/// terms, the form every [Fraction] is kept in.
enum DurationBase {
  /// A breve, two whole notes.
  breve(Length(Fraction._(2, 1))),

  /// A whole note, 1.
  whole(Length.whole),

  /// A half note, 1/2.
  half(Length(Fraction._(1, 2))),

  /// A quarter note, 1/4.
  quarter(Length(Fraction._(1, 4))),

  /// An eighth note, 1/8.
  eighth(Length(Fraction._(1, 8))),

  /// A sixteenth note, 1/16.
  sixteenth(Length(Fraction._(1, 16))),

  /// A thirty-second note, 1/32.
  thirtySecond(Length(Fraction._(1, 32))),

  /// A sixty-fourth note, 1/64.
  sixtyFourth(Length(Fraction._(1, 64))),

  /// A 128th note, 1/128.
  oneTwentyEighth(Length(Fraction._(1, 128)));

  DurationBase(this.length);

  /// The undotted length in whole notes.
  final Length length;

  /// Number of beams (or flags) this value carries. Zero for quarter and up.
  int get beams => index <= DurationBase.quarter.index
      ? 0
      : index - DurationBase.quarter.index;
}

/// A written duration: a base value plus up to three dots. What the composer
/// picks from the palette. Its sounding length inside a tuplet is scaled by
/// the tuplet ratio; see [TupletRatio.scale].
final class NoteValue {
  /// A [base] with [dots] dots. Asserts that [dots] is 0 to 3.
  const NoteValue(this.base, {this.dots = 0})
    : assert(dots >= 0 && dots <= 3, 'at most three dots');

  /// An undotted whole note.
  static const whole = NoteValue(DurationBase.whole);

  /// An undotted half note.
  static const half = NoteValue(DurationBase.half);

  /// An undotted quarter note.
  static const quarter = NoteValue(DurationBase.quarter);

  /// An undotted eighth note.
  static const eighth = NoteValue(DurationBase.eighth);

  /// An undotted sixteenth note.
  static const sixteenth = NoteValue(DurationBase.sixteenth);

  /// An undotted thirty-second note.
  static const thirtySecond = NoteValue(DurationBase.thirtySecond);

  /// The undotted shape.
  final DurationBase base;

  /// Number of dots, 0 to 3. The first dot adds half the base length, and
  /// each later dot adds half of what the one before it added.
  final int dots;

  /// Written length: base × (2 − 1/2^dots).
  Length get length {
    if (dots == 0) {
      return base.length;
    }
    final p = 1 << dots;
    return base.length * Fraction(2 * p - 1, p);
  }

  /// This value with one more dot. Asserts when it already has three.
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
  /// The ratio [actual]:[normal]. Asserts that both terms are positive.
  const TupletRatio(this.actual, this.normal)
    : assert(actual > 0 && normal > 0, 'ratio terms are positive');

  /// Two notes in the time of three (2:3), as in compound meter.
  static const duplet = TupletRatio(2, 3);

  /// Three notes in the time of two (3:2).
  static const triplet = TupletRatio(3, 2);

  /// Five notes in the time of four (5:4).
  static const quintuplet = TupletRatio(5, 4);

  /// How many notes the tuplet holds.
  final int actual;

  /// How many notes of the same written value take the same time outside
  /// the tuplet.
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

/// How a time signature is drawn.
enum MeterSymbol {
  /// Digits, the numerator over the unit.
  numeric,

  /// The common-time C, for 4/4.
  common,

  /// The cut-time C with a vertical stroke, for 2/2.
  cut,
}

/// A time signature. [groups] are additive numerators (`[3, 2, 2]` is 7/8
/// grouped 3+2+2; `[4]` is plain 4/4) so beaming and rest splitting follow
/// the composer's grouping instead of a guess.
final class Meter {
  /// [groups] must be non-empty; `scoreFromJson` rejects an empty list.
  const Meter(this.groups, this.unit, {this.symbol = MeterSymbol.numeric});

  /// [beats] over [unit] in one group, such as 3/4.
  Meter.simple(int beats, int unit) : this([beats], unit);

  /// 4/4, written in digits.
  static const fourFour = Meter([4], 4);

  /// 3/4.
  static const threeFour = Meter([3], 4);

  /// 2/4.
  static const twoFour = Meter([2], 4);

  /// 6/8, compound, two dotted-quarter beats.
  static const sixEight = Meter([6], 8);

  /// 4/4, drawn as the common-time symbol.
  static const common = Meter([4], 4, symbol: MeterSymbol.common);

  /// 2/2, drawn as the cut-time symbol.
  static const cut = Meter([2], 2, symbol: MeterSymbol.cut);

  /// The additive numerators, in order. See [Meter].
  final List<int> groups;

  /// Denominator. A power of two.
  final int unit;

  /// How the signature is drawn. [MeterSymbol.numeric] unless set.
  final MeterSymbol symbol;

  /// The top number, the sum of [groups].
  int get numerator => groups.fold(0, (a, b) => a + b);

  /// Nominal bar length. A column's actual capacity can differ only through
  /// an explicit `MeasureColumn.irregularLength` (pickups, cadenzas).
  Length get length => Length(Fraction(numerator, unit));

  /// True for 6/8, 9/8, 12/8, 6/4 and similar: the beat is a dotted unit.
  bool get isCompound =>
      groups.length == 1 && numerator % 3 == 0 && numerator > 3 && unit >= 4;

  /// Offsets from the bar start where a beat begins.
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

  /// Offsets where default beams break. A simple bar up to 3/4 beams whole,
  /// a longer one with an even numerator breaks at the half bar (4/4, 2/2),
  /// and anything else breaks per beat: per dotted quarter in 6/8, per group
  /// in 3+2+2/8, per quarter in 5/4. An ungrouped 7/8 therefore beams per
  /// eighth, which is why a meter carries its grouping.
  List<Moment> get beamBreaks {
    if (groups.length > 1 || isCompound) {
      return beatOffsets;
    }
    if (length <= const Length(Fraction._(3, 4))) {
      return const [Moment.zero];
    }
    if (numerator.isEven) {
      return [Moment.zero, Moment(Fraction(numerator, 2 * unit))];
    }
    return beatOffsets;
  }

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
  /// [bpm] beats of [beat] per minute, a quarter note by default. Asserts
  /// that [bpm] is positive.
  const Tempo(this.bpm, {this.beat = NoteValue.quarter})
    : assert(bpm > 0, 'tempo is positive');

  /// The tempo of music before its first tempo mark.
  static const unmarked = Tempo(100);

  /// Beats per minute. Can be fractional.
  final double bpm;

  /// The note value that counts as one beat, such as a dotted quarter in
  /// 6/8.
  final NoteValue beat;

  /// Seconds that [length] lasts at this tempo.
  double secondsFor(Length length) =>
      (length / beat.length).toDouble() * 60 / bpm;

  @override
  bool operator ==(Object other) =>
      other is Tempo && other.bpm == bpm && other.beat == beat;

  @override
  int get hashCode => Object.hash(bpm, beat);
}
