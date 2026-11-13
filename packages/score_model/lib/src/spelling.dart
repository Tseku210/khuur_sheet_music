/// Turning a span of time into note values. Internal to the package.
library;

import 'time.dart';

/// A beat grid: the beat starts inside one [period], repeated.
final class BeatGrid {
  BeatGrid({required this.period, required this.beats, required this.strict})
    : assert(beats.isNotEmpty && beats.first.isZero, 'first beat at zero');

  /// The beats of [meter]. Compound and additive meters are strict.
  BeatGrid.meter(Meter meter)
    : this(
        period: meter.length,
        beats: meter.beatOffsets,
        strict: meter.isCompound || meter.groups.length > 1,
      );

  /// A tuplet's frame: one beat across its written length, so any value
  /// that fits is written whole.
  BeatGrid.single(Length period)
    : this(period: period, beats: const [Moment.zero], strict: false);

  /// One bar of the meter, or the written length of a tuplet.
  final Length period;

  /// Beat starts in `[0, period)`, ascending.
  final List<Moment> beats;

  /// True for compound and additive meters. A value that crosses a beat
  /// must then start and end on beats, so a 6/8 bar never shows a plain
  /// half note across its two dotted-quarter beats.
  final bool strict;

  bool isBeat(Moment m) => beats.contains(m - _periodStart(m));

  /// The first beat strictly after [m].
  Moment nextBeat(Moment m) {
    final start = Moment.zero + _periodStart(m);
    for (final beat in beats) {
      final candidate = start + Moment.zero.until(beat);
      if (candidate > m) {
        return candidate;
      }
    }
    return start + period;
  }

  /// Distance from zero to the start of the period holding [m] (m >= 0).
  Length _periodStart(Moment m) {
    final ratio = m.wholeNotes / period.wholeNotes;
    return period * Fraction(ratio.numerator ~/ ratio.denominator);
  }
}

/// Every writable value, longest first: each base plain and single-dotted.
final List<NoteValue> _candidates = [
  for (final base in DurationBase.values)
    for (final dots in const [0, 1]) NoteValue(base, dots: dots),
]..sort((a, b) => b.length.compareTo(a.length));

/// Greedy spelling of `[offset, offset + length)` on [grid]. Each step takes
/// the longest value that fits and either stays inside one beat or crosses
/// beats in a way that keeps the beat visible:
/// - on a strict grid it starts and ends on beats;
/// - otherwise it starts on its own value's grid (a half on a half-bar, a
///   dotted value on the grid of the next longer value), and a rest takes
///   no dot.
///
/// Throws [ArgumentError] when no note value can write the span, such as
/// 1/12 of a whole note outside a tuplet.
List<NoteValue> spellOnGrid(
  BeatGrid grid,
  Moment offset,
  Length length, {
  required bool rest,
}) {
  final end = offset + length;
  final values = <NoteValue>[];
  var at = offset;
  while (at < end) {
    final value = _candidates.firstWhere(
      (v) => _fits(grid, at, end, v, rest: rest),
      orElse: () => throw ArgumentError(
        'no note value writes ${at.until(end).wholeNotes} '
        'from ${at.wholeNotes}',
      ),
    );
    values.add(value);
    at += value.length;
  }
  return values;
}

bool _fits(
  BeatGrid grid,
  Moment at,
  Moment end,
  NoteValue value, {
  required bool rest,
}) {
  final stop = at + value.length;
  if (stop > end) {
    return false;
  }
  if (grid.nextBeat(at) >= stop) {
    return true;
  }
  if (grid.strict) {
    return grid.isBeat(at) && grid.isBeat(stop);
  }
  if (value.dots == 0) {
    return _isMultiple(at, value.length);
  }
  return !rest && _isMultiple(at, value.base.length * Fraction(2));
}

bool _isMultiple(Moment at, Length unit) =>
    (at.wholeNotes / unit.wholeNotes).denominator == 1;
