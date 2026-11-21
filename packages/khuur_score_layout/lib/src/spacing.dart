/// Horizontal spacing. Time slices, springs and rods, and the one [Fit] of
/// a system. Not exported.
///
/// Every staff and voice of a bar shares one list of slices, so events at
/// the same moment align down the system by construction.
library;

import 'dart:math' as math;

import 'package:khuur_score_model/khuur_score_model.dart';

import 'style.dart';

/// One column of time in a bar. Every staff's events at [at] share its x.
///
/// The last slice of a bar is the bar's end, where the barline sits. Its
/// rod is the barline's width and it has no spring.
final class Slice {
  /// Makes a slice at [at].
  const Slice({
    required this.at,
    required this.ideal,
    required this.rod,
    this.pad = 0,
    this.left = 0,
    this.right = 0,
  });

  /// The slice's onset, from the bar's start.
  final Moment at;

  /// Ideal distance to the next slice at stretch 1.
  final double ideal;

  /// Least distance to the next slice in a system that fits its sheet.
  final double rod;

  /// The part of [rod] that is clear space and not content. A system
  /// wider than its sheet gives it up first.
  final double pad;

  /// How far what cannot leave the slice's line reaches left of it. That
  /// is its notes and rests with what they carry, a clef change and a
  /// syllable. A mark is not in it.
  final double left;

  /// How far what cannot leave the slice's line reaches right of it. 0 at
  /// the bar's end.
  final double right;

  @override
  bool operator ==(Object other) =>
      other is Slice &&
      other.at == at &&
      other.ideal == ideal &&
      other.rod == rod &&
      other.pad == pad &&
      other.left == left &&
      other.right == right;

  @override
  int get hashCode => Object.hash(at, ideal, rod, pad, left, right);
}

/// How far a slice's content reaches left and right of the slice line:
/// accidentals and grace notes to the left, dots, flags, flipped heads and
/// wide text to the right.
typedef SliceReach = ({double left, double right});

/// The reach of a slice with nothing outside its line.
const SliceReach noReach = (left: 0, right: 0);

/// The larger of [a] and [b] on each side.
SliceReach widest(SliceReach a, SliceReach b) =>
    (left: math.max(a.left, b.left), right: math.max(a.right, b.right));

/// The distinct moments of the bar, sorted. They are every event onset in
/// every voice of every visible staff, every clef change inside the bar,
/// every direction of a visible staff, every tempo mark, the start of every
/// hairpin, octave, pedal or tempo line that starts in the bar on a visible
/// staff, and the bar's end. Grace chords take no slice. They sit left of
/// their principal and widen its reach. A slur, glissando or trill line
/// starts on an event, so it needs no slice of its own. A bar with no
/// visible staff has its end alone, since nothing of it is spaced.
List<Moment> sliceTimes(MeasureView view) {
  final onsets = [
    for (final staff in view.staves) ...[
      for (final voice in staff.voices)
        for (final timed in voice.events) timed.onset,
      for (final change in staff.source.clefChanges) change.offset,
      for (final direction in staff.source.directions) direction.offset,
      for (final segment in view.spanners)
        if (segment.startsHere &&
            segment.spanner.staff == staff.source.staff &&
            _startsSlice(segment.spanner.kind))
          segment.from,
    ],
    if (view.staves.isNotEmpty)
      for (final tempo in view.column.tempos) tempo.offset,
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

bool _startsSlice(SpannerKind kind) => switch (kind.reach) {
  SpannerReach.time => true,
  SpannerReach.events => false,
};

/// The slices of [view] at [times], with the reach each one's content has.
///
/// The spring after slice i follows the shortest duration d starting there
/// in any voice. Its ideal is `quarterSpace * ratio^log2(d / quarter)`,
/// scaled by `(times[i+1] - times[i]) / d` when the next slice comes sooner
/// than d. A slice where nothing starts, which a clef change or a mark
/// makes, takes d from the slice before it. A bar where every voice of
/// every visible staff holds only a `MeasureRest` is spaced as if notes of
/// its meter's lower number filled it, so d is that note and every spring
/// scales by `(times[i+1] - times[i]) / d`, longer or shorter. The bar then
/// takes the room of its beats, and its time runs as evenly across it as
/// theirs. The rod is `reach[i].right + minGap + reach[i+1].left`. The
/// scale is absolute, so a bar's spacing never depends on another bar. The
/// last slice is the bar's end, with no spring and a rod of [end], the
/// width of the bar's end barline.
///
/// [firm] is the part of [reach] that cannot leave its slice's line, which
/// is all of it unless given. Each slice keeps it as its own reach, for a
/// squeezed system to read.
List<Slice> spaceSlices(
  MeasureView view,
  List<Moment> times,
  List<SliceReach> reach,
  SpacingPolicy policy, {
  required double end,
  List<SliceReach>? firm,
}) {
  final own = firm ?? reach;
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
  for (var i = 1; i < times.length - 1; i++) {
    shortest[i] ??= shortest[i - 1];
  }
  final beat = _restBeat(view);
  double idealAt(int i) {
    final toNext = times[i].until(times[i + 1]);
    final d = beat ?? shortest[i]!;
    return _ideal(d, beat == null && toNext > d ? d : toNext, policy);
  }

  return [
    for (var i = 0; i < times.length - 1; i++)
      Slice(
        at: times[i],
        ideal: idealAt(i),
        rod: reach[i].right + policy.minGap + reach[i + 1].left,
        pad: policy.minGap,
        left: own[i].left,
        right: own[i].right,
      ),
    Slice(at: times.last, ideal: 0, rod: end, left: own.last.left),
  ];
}

/// The note of the meter's lower number when every voice of [view] holds
/// only bar rests, and null otherwise.
Length? _restBeat(MeasureView view) {
  final restsOnly = view.staves.every(
    (staff) => staff.voices.every(
      (voice) => voice.events.every((timed) => timed.event is MeasureRest),
    ),
  );
  return restsOnly ? Length(Fraction(1, view.column.meter.unit)) : null;
}

/// The ideal room of [span] filled with notes of duration [d].
double _ideal(Length d, Length span, SpacingPolicy policy) {
  final quarters = (d / DurationBase.quarter.length).toDouble();
  return policy.quarterSpace *
      math.pow(policy.ratio, math.log(quarters) / math.ln2) *
      (span / d).toDouble();
}

/// [slices] with every rod before the bar's end grown by an equal share, so
/// that the bar is at least [least] wide from its first slice to its end at
/// any stretch. Unchanged when its first slice already reaches [least].
///
/// The first slice's reach grows to [least] too. What the bar is widened
/// for starts at the bar's start, and a squeezed system keeps every reach
/// inside its bar.
List<Slice> widenedTo(List<Slice> slices, double least) {
  final springs = slices.length - 1;
  final short = least - (rodWidth(slices) - slices.last.rod);
  if (least <= slices.first.right) {
    return slices;
  }
  return [
    for (final (index, slice) in slices.take(springs).indexed)
      Slice(
        at: slice.at,
        ideal: slice.ideal,
        rod: slice.rod + math.max(0, short) / springs,
        pad: slice.pad,
        left: slice.left,
        right: index == 0 ? least : slice.right,
      ),
    slices.last,
  ];
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

/// How a system's slices take their room.
///
/// A system whose rods fit its sheet is stretched, and only its springs
/// change. One whose rods are wider is squeezed in two stages, as MuseScore's
/// `squeezeSystemToFit` does. It first gives up its padding, and nothing
/// overlaps. If that is not enough, every gap between two slices is scaled
/// down by one factor and the notes collide, since a bar that runs off the
/// sheet cannot be read at all.
final class Fit {
  /// The fit of a system whose rods fit, with every spring scaled by
  /// [stretch].
  const Fit.stretched(this.stretch) : pad = 1, crush = 1;

  /// The fit of a system whose rods are wider than its sheet.
  const Fit.squeezed({required this.pad, required this.crush}) : stretch = 0;

  /// The one factor every spring of the system is scaled by. 0 and unread
  /// when the system is [squeezed].
  final double stretch;

  /// The share of its padding the system keeps, from 1 down to 0.
  final double pad;

  /// The scale of every gap between two slices once its padding is gone,
  /// from 1 down to 0. Below 1 only when [pad] is 0.
  final double crush;

  /// Whether the system sits below its rods.
  bool get squeezed => pad < 1 || crush < 1;

  @override
  bool operator ==(Object other) =>
      other is Fit &&
      other.stretch == stretch &&
      other.pad == pad &&
      other.crush == crush;

  @override
  int get hashCode => Object.hash(stretch, pad, crush);
}

/// The width of a squeezed unit from its head to its end, under [fit].
///
/// Each slice stands its rod, less the padding given up, scaled by the
/// crush, after the slice before it. So the gaps of a system all shrink by
/// one factor, and two slices that hold ink share an x only at a crush of
/// 0. A slice that holds only padding can end on the next one. The unit's
/// [lead] is never given up, because what arrives from the system before
/// is drawn in it. A slice also keeps its left reach clear of the unit's
/// head. The unit ends where every slice's right reach has ended, and no
/// sooner than [markRoom] after its lead.
///
/// [markRoom] is the width of the unit's widest mark. A mark is not part of
/// any slice's reach here. In a squeezed unit it gives way and its notes do
/// not, see `BarFrame.xOf`.
double squeezedWidth(
  List<Slice> slices,
  Fit fit, {
  required double lead,
  required double markRoom,
}) => _squeeze(slices, fit, lead, markRoom, null);

double _squeeze(
  List<Slice> slices,
  Fit fit,
  double lead,
  double markRoom,
  List<double>? xs,
) {
  var x = lead;
  var end = lead + markRoom;
  for (final (index, slice) in slices.indexed) {
    if (index > 0) {
      x = math.max(x, slice.left);
    }
    xs?.add(x);
    end = math.max(end, x + slice.right);
    x += fit.crush * (slice.rod - (1 - fit.pad) * slice.pad);
  }
  return end;
}

/// The x of each slice of a unit whose head ends at [from], under [fit].
///
/// A stretched unit is [sliceXs] from the end of its [lead]. A squeezed
/// one is placed as [squeezedWidth] says, and its last slice, the bar's
/// end, is that width from [from].
List<double> fitXs(
  List<Slice> slices,
  Fit fit,
  double from, {
  required double lead,
  required double markRoom,
}) {
  if (!fit.squeezed) {
    return sliceXs(slices, fit.stretch, from + lead);
  }
  final xs = <double>[];
  final width = _squeeze(slices, fit, lead, markRoom, xs);
  return [
    for (final x in xs.take(xs.length - 1)) from + x,
    from + width,
  ];
}

/// [slices] with each one's reach grown to hold [held], which cannot leave
/// its line either. The rods stand, so only a squeezed system reads the
/// reach that grew.
List<Slice> holding(List<Slice> slices, List<SliceReach> held) => [
  for (final (index, slice) in slices.indexed)
    if (held[index].left <= slice.left && held[index].right <= slice.right)
      slice
    else
      Slice(
        at: slice.at,
        ideal: slice.ideal,
        rod: slice.rod,
        pad: slice.pad,
        left: math.max(slice.left, held[index].left),
        right: math.max(slice.right, held[index].right),
      ),
];
