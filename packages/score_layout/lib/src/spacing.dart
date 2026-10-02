/// Horizontal spacing. Time slices, springs and rods, and the one stretch
/// factor of a system. Not exported.
///
/// Every staff and voice of a bar shares one list of slices, so events at
/// the same moment align down the system by construction.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'style.dart';

/// One column of time in a bar. Every staff's events at [at] share its x.
///
/// The last slice of a bar is the bar's end, where the barline sits. Its
/// rod is the barline's width and it has no spring.
final class Slice {
  const Slice({required this.at, required this.ideal, required this.rod});

  final Moment at;

  /// Ideal distance to the next slice at stretch 1.
  final double ideal;

  /// Least distance to the next slice.
  final double rod;

  @override
  bool operator ==(Object other) =>
      other is Slice &&
      other.at == at &&
      other.ideal == ideal &&
      other.rod == rod;

  @override
  int get hashCode => Object.hash(at, ideal, rod);
}

/// How far a slice's content reaches left and right of the slice line:
/// accidentals and grace notes to the left, dots, flags, flipped heads and
/// wide text to the right.
typedef SliceReach = ({double left, double right});

const SliceReach noReach = (left: 0, right: 0);

SliceReach widest(SliceReach a, SliceReach b) =>
    (left: math.max(a.left, b.left), right: math.max(a.right, b.right));

/// The distinct moments of the bar, sorted. They are every event onset in
/// every voice of every visible staff, and the bar's end. Grace chords take
/// no slice. They sit left of their principal and widen its reach.
List<Moment> sliceTimes(MeasureView view) {
  final onsets = [
    for (final staff in view.staves)
      for (final voice in staff.voices)
        for (final timed in voice.events) timed.onset,
    Moment.zero + view.column.length,
  ]..sort((a, b) => a.compareTo(b));
  final times = <Moment>[];
  for (final onset in onsets) {
    if (times.isEmpty || times.last.compareTo(onset) != 0) {
      times.add(onset);
    }
  }
  return times;
}

/// The slices of [view] at [times], with the reach each one's content has.
///
/// The spring after slice i follows the shortest duration d starting there
/// in any voice. Its ideal is `quarterSpace * ratio^log2(d / quarter)`,
/// scaled by `(times[i+1] - times[i]) / d` when the next slice comes sooner
/// than d. The rod is `reach[i].right + minGap + reach[i+1].left`. The
/// scale is absolute, so a bar's spacing never depends on another bar. The
/// last slice is the bar's end, with no spring and a rod of [end], the
/// width of the bar's end barline.
List<Slice> spaceSlices(
  MeasureView view,
  List<Moment> times,
  List<SliceReach> reach,
  SpacingPolicy policy, {
  required double end,
}) {
  final shortest = List<Length?>.filled(times.length, null);
  for (final staff in view.staves) {
    for (final voice in staff.voices) {
      for (final timed in voice.events) {
        final i = times.indexOf(timed.onset);
        final known = shortest[i];
        if (known == null || timed.duration < known) {
          shortest[i] = timed.duration;
        }
      }
    }
  }
  return [
    for (var i = 0; i < times.length - 1; i++)
      Slice(
        at: times[i],
        ideal: _ideal(shortest[i]!, times[i].until(times[i + 1]), policy),
        rod: reach[i].right + policy.minGap + reach[i + 1].left,
      ),
    Slice(at: times.last, ideal: 0, rod: end),
  ];
}

double _ideal(Length shortest, Length toNext, SpacingPolicy policy) {
  final quarters = (shortest / DurationBase.quarter.length).toDouble();
  final ideal =
      policy.quarterSpace *
      math.pow(policy.ratio, math.log(quarters) / math.ln2);
  return toNext < shortest ? ideal * (toNext / shortest).toDouble() : ideal;
}

/// Width at stretch 1, with each slice at its ideal and never below its rod.
double naturalWidth(Iterable<Slice> slices) => slices.fold(
  0,
  (width, slice) => width + math.max(slice.rod, slice.ideal),
);

/// Width with every slice compressed to its rod.
double rodWidth(Iterable<Slice> slices) =>
    slices.fold(0, (width, slice) => width + slice.rod);

/// The stretch s at which [slices] are [room] wide, where the width is
/// `sum(max(rod, ideal * s))`. 0 when the rods alone fill [room] or more.
///
/// A slice sits on its rod until s passes `rod / ideal` and grows as
/// `ideal * s` after that. So the width is piecewise linear in s, and
/// walking the slices in order of that threshold finds the piece that
/// holds the answer. Rods never stretch, which is why one affine map from
/// natural x to final x cannot stand in for this.
double stretchFor(List<Slice> slices, double room) {
  final springs = [
    for (final slice in slices)
      if (slice.ideal > 0) slice,
  ]..sort((a, b) => (a.rod / a.ideal).compareTo(b.rod / b.ideal));
  var rods = rodWidth(slices);
  var ideals = 0.0;
  for (final slice in springs) {
    if (rods + ideals * (slice.rod / slice.ideal) >= room) {
      break;
    }
    rods -= slice.rod;
    ideals += slice.ideal;
  }
  return ideals == 0 ? 0 : (room - rods) / ideals;
}

/// The x of each slice when the first is at [from] and the stretch is
/// [stretch].
List<double> sliceXs(List<Slice> slices, double stretch, double from) {
  final xs = <double>[];
  var x = from;
  for (final slice in slices) {
    xs.add(x);
    x += math.max(slice.rod, slice.ideal * stretch);
  }
  return xs;
}
