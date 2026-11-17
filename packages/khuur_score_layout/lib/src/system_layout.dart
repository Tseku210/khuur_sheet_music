import 'package:khuur_score_model/khuur_score_model.dart';

import 'drawable.dart';
import 'geometry.dart';
import 'hit.dart';

/// One system. It is a line of bars across every visible staff, justified to
/// the sheet width, with every drawable placed in system space.
///
/// This is the geometry everything reads. The painter draws [drawables].
/// Hit testing, the caret, selection boxes and the playback highlight read
/// [bars], [staves], [signatures] and [drawablesOf]. Nobody records
/// positions while painting.
///
/// Invariant: every drawable lies inside the box from (0, 0) to
/// ([width], [height]). The height was fixed when lines were broken,
/// before this system was assembled.
///
/// Immutable.
final class SystemLayout {
  /// Makes a system from placed parts. A sheet's systems come from
  /// `SheetLayout.systemAt`.
  const SystemLayout({
    required this.drawables,
    required this.bars,
    required this.staves,
    required this.width,
    required this.height,
    this.signatures = const [],
  });

  /// Everything the system draws, in system space.
  final List<Drawable> drawables;

  /// Each clef, key signature, time signature and tempo mark the system
  /// draws, one for each staff, kind and point, with the box of its glyphs.
  /// The naturals that cancel an old key are part of the new key's box, and
  /// a tempo mark's box spans its words and its metronome mark.
  final List<PlacedSignature> signatures;

  /// In time order.
  final List<PlacedBar> bars;

  /// Visible staves, top to bottom.
  final List<PlacedStaff> staves;

  /// The system's width in staff spaces. It is the sheet's width, or more
  /// when one bar alone is wider.
  final double width;

  /// The system's height in staff spaces, as planned when lines were broken.
  final double height;

  /// The drawables [owner] owns in this system. A note owns its head. An
  /// event owns its stem, flag, rest, accidentals, dots, ledger lines and
  /// all its notes' heads. A spanner owns its pieces.
  Iterable<Drawable> drawablesOf(Owner owner) =>
      drawables.where((d) => _covers(owner, d.owner));

  /// The union of [owner]'s drawables, or null when it has none here (a
  /// hidden staff, or another system).
  Box? boundsOf(Owner owner) =>
      drawablesOf(owner)
          .map((d) => d.bounds)
          .fold<Box?>(null, (a, b) => a?.union(b) ?? b);

  /// The placed bar of [measure], or null when the bar is not on this
  /// system.
  PlacedBar? barOf(MeasureId measure) =>
      bars.where((bar) => bar.measure == measure).firstOrNull;

  /// The placed staff of [staff], or null when it is not drawn here.
  PlacedStaff? staffOf(StaffId staff) =>
      staves.where((s) => s.staff == staff).firstOrNull;

  /// The share of the system's height that is [staff]'s, in system space.
  /// It reaches up halfway to the staff above and down halfway to the
  /// staff below, and to the system's edge where there is none. Null when
  /// [staff] is not drawn here.
  ({double top, double bottom})? bandOf(StaffId staff) {
    final index = staves.indexWhere((s) => s.staff == staff);
    if (index < 0) {
      return null;
    }
    double between(PlacedStaff upper, PlacedStaff lower) =>
        (upper.top + staffHeight + lower.top) / 2;
    return (
      top: index == 0 ? 0 : between(staves[index - 1], staves[index]),
      bottom: index == staves.length - 1
          ? height
          : between(staves[index], staves[index + 1]),
    );
  }

  /// The staff whose middle line is nearest to [y].
  PlacedStaff staffNear(double y) => staves.reduce(
    (a, b) => (a.top + 2 - y).abs() <= (b.top + 2 - y).abs() ? a : b,
  );

  /// The bar that holds [x]. Left of the first bar gives the first, and
  /// right of the last gives the last.
  PlacedBar barAt(double x) =>
      bars.lastWhere((bar) => bar.left <= x, orElse: () => bars.first);

  /// What is drawn nearest [point], within [reach]. Between owners as near
  /// as each other, a notehead comes first, then any other part of an
  /// event, then a spanner, so a tap inside a head under a slur takes the
  /// head. Null on structure and on empty paper.
  Owner? targetAt(SpPoint point, {double reach = 0}) {
    Owner? best;
    var nearest = double.infinity;
    for (final drawable in drawables) {
      final owner = drawable.owner;
      if (owner == null) {
        continue;
      }
      final distance = drawable.distanceTo(point);
      if (distance <= reach &&
          (distance < nearest ||
              distance == nearest && _rank(owner) < _rank(best!))) {
        best = owner;
        nearest = distance;
      }
    }
    return best;
  }

  /// The clef, key signature, time signature or tempo mark drawn nearest
  /// [point], within [reach]. Null when none is, and when a note, an event or a
  /// spanner is drawn at least as near, so the nearer of a sign and a note
  /// wins and the note wins a tie. A key signature counts as one box over
  /// all its accidentals, so a tap between two of them is on it.
  SignatureHit? signatureAt(SpPoint point, {double reach = 0}) {
    PlacedSignature? best;
    var nearest = double.infinity;
    for (final placed in signatures) {
      final distance = placed.bounds.distanceTo(point);
      if (distance <= reach && distance < nearest) {
        best = placed;
        nearest = distance;
      }
    }
    if (best == null || targetAt(point, reach: nearest) != null) {
      return null;
    }
    return best.signature;
  }
}

bool _covers(Owner owner, Owner? drawn) => switch ((owner, drawn)) {
  (ElementOwner(ref: final EventRef event), ElementOwner(:final ref)) =>
    ref.event == event,
  _ => owner == drawn,
};

int _rank(Owner owner) => switch (owner) {
  ElementOwner(ref: NoteRef()) => 0,
  ElementOwner() => 1,
  SpannerOwner() => 2,
};

/// Where one bar landed on its system, with its time axis.
final class PlacedBar {
  /// Makes a placed bar.
  const PlacedBar({
    required this.measure,
    required this.left,
    required this.right,
    required this.time,
    required this.length,
  });

  /// Which bar of the score this is.
  final MeasureId measure;

  /// x where the bar starts, after the barline before it or at the system's
  /// content start. A bar inside a rest run starts where its share of the
  /// run does.
  final double left;

  /// x where the bar's content ends, or where its share of a rest run ends.
  /// Its barline starts here, or after a clef that stands before it.
  final double right;

  /// Maps time in the bar to x in system space.
  final TimeAxis time;

  /// The bar's length, the end of [time].
  final Length length;
}

/// Maps time in a bar to x in system space, and back.
///
/// [stops] holds each slice's onset and x, in time order, and ends with the
/// bar's length at the x where the bar's content ends. Between stops x is
/// linear in time, so every Moment has an x. The caret, a range end at the
/// bar end, a direction inside a held note and the playhead all use it.
final class TimeAxis {
  /// Makes an axis through [stops].
  const TimeAxis(this.stops);

  /// Each slice's onset and x, ending with the bar's length. See [TimeAxis].
  final List<(Moment, double)> stops;

  /// The x of [offset] from the bar's start. An offset past the bar's
  /// length gives the x where the content ends.
  double xAt(Moment offset) => xAtWholeNotes(offset.wholeNotes.toDouble());

  /// For the playhead, whose position is continuous.
  double xAtWholeNotes(double offset) {
    for (var i = 1; i < stops.length; i++) {
      final (from, x0) = stops[i - 1];
      final (to, x1) = stops[i];
      final t0 = from.wholeNotes.toDouble();
      final t1 = to.wholeNotes.toDouble();
      if (offset <= t1) {
        return t1 == t0 ? x0 : x0 + (x1 - x0) * (offset - t0) / (t1 - t0);
      }
    }
    return stops.last.$2;
  }

  /// The candidate whose x is nearest to [x]. The earlier wins a tie.
  Moment nearest(Iterable<Moment> candidates, double x) => candidates.reduce(
    (a, b) => (xAt(a) - x).abs() <= (xAt(b) - x).abs() ? a : b,
  );
}

/// Where one clef, key signature, time signature or tempo mark landed on
/// its system.
final class PlacedSignature {
  /// Makes a placed sign.
  const PlacedSignature({required this.signature, required this.bounds});

  /// What the sign stands for.
  final SignatureHit signature;

  /// The box of the sign's glyphs in system space. A key signature's box
  /// spans all its accidentals, a time signature's both its rows, and a
  /// tempo mark's its words, its note and its number.
  final Box bounds;
}

/// Where one visible staff landed on its system.
final class PlacedStaff {
  /// Makes a placed staff.
  const PlacedStaff({
    required this.staff,
    required this.top,
    required this.lines,
  });

  /// Which staff of the score this is.
  final StaffId staff;

  /// y of the top line of a five-line staff in system space. A one-line
  /// staff draws its line at step 4 below this.
  final double top;

  /// 5 or 1, from `Staff.lines`.
  final int lines;

  /// The y of [staffStep] in system space, with steps as [yOfStep] counts
  /// them.
  double yOf(int staffStep) => top + yOfStep(staffStep);

  /// The staff step nearest to [y], a y in system space.
  int stepAt(double y) => stepAtY(y - top);
}
