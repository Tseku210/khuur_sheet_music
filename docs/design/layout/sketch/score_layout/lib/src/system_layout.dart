import 'package:score_model/score_model.dart';

import 'drawable.dart';
import 'geometry.dart';

/// One system. It is a line of bars across every visible staff, justified to
/// the sheet width, with every drawable placed in system space.
///
/// This is the geometry everything reads. The painter draws [drawables].
/// Hit testing, the caret, selection boxes and the playback highlight read
/// [bars], [staves] and [drawablesOf]. Nobody records positions while
/// painting.
///
/// Invariant: every drawable lies inside the box from (0, 0) to
/// ([width], [height]). The height was fixed when lines were broken,
/// before this system was assembled.
///
/// Immutable. The sheet hands out the same SystemLayout object for as long
/// as the system's key is unchanged, so identity is the painter's cache
/// key.
final class SystemLayout {
  const SystemLayout({
    required this.drawables,
    required this.bars,
    required this.staves,
    required this.width,
    required this.height,
  });

  final List<Drawable> drawables;

  /// In time order.
  final List<PlacedBar> bars;

  /// Visible staves, top to bottom.
  final List<PlacedStaff> staves;

  final double width;
  final double height;

  /// The drawables [owner] owns in this system. A note owns its head. An
  /// event owns its stem, flag, rest, accidentals, dots, ledger lines and
  /// all its notes' heads. A spanner owns its pieces.
  // The engine indexes drawables by owner once per system. A scan stands in.
  Iterable<Drawable> drawablesOf(Owner owner) =>
      drawables.where((d) => _covers(owner, d.owner));

  /// The union of [owner]'s drawables, or null when it has none here (a
  /// hidden staff, or another system).
  Box? boundsOf(Owner owner) => drawablesOf(
    owner,
  ).map((d) => d.bounds).fold<Box?>(null, (a, b) => a?.union(b) ?? b);

  PlacedBar? barOf(MeasureId measure) =>
      bars.where((bar) => bar.measure == measure).firstOrNull;

  PlacedStaff? staffOf(StaffId staff) =>
      staves.where((s) => s.staff == staff).firstOrNull;

  /// The staff whose middle line is nearest to [y].
  PlacedStaff staffNear(double y) => staves.reduce(
    (a, b) => (a.top + 2 - y).abs() <= (b.top + 2 - y).abs() ? a : b,
  );

  /// The bar that holds [x]. Left of the first bar gives the first, and
  /// right of the last gives the last.
  PlacedBar barAt(double x) =>
      bars.lastWhere((bar) => bar.left <= x, orElse: () => bars.first);

  /// What is drawn within [reach] of [point]. A notehead comes first, then
  /// any other part of an event, then a spanner. Null on structure and on
  /// empty paper.
  Owner? targetAt(SpPoint point, {double reach = 0}) {
    Owner? best;
    for (final drawable in drawables) {
      final owner = drawable.owner;
      if (owner == null || !drawable.hits(point, reach)) {
        continue;
      }
      if (best == null || _rank(owner) < _rank(best)) {
        best = owner;
      }
    }
    return best;
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

/// A bar as placed on its system.
final class PlacedBar {
  const PlacedBar({
    required this.measure,
    required this.left,
    required this.right,
    required this.time,
    required this.length,
    required this.voices,
  });

  final MeasureId measure;

  /// x of the barline before the bar, or of the system's content start.
  final double left;

  /// x of the barline after the bar.
  final double right;

  final TimeAxis time;

  /// The bar's length, so a tap can be snapped without the score.
  final Length length;

  /// What each voice of each visible staff holds, for snapping a tap to a
  /// point `EnterNote` accepts and for naming the voice of a tapped event.
  final Map<(StaffId, VoiceSlot), VoiceTimes> voices;

  /// The voice that holds [event] on [staff], or null when the event is
  /// not in this bar.
  VoiceSlot? voiceOf(StaffId staff, EventId event) {
    for (final MapEntry(key: (owner, slot), value: times) in voices.entries) {
      if (owner == staff && times.events.contains(event)) {
        return slot;
      }
    }
    return null;
  }
}

/// One voice of one bar in time, with its events and its tuplets.
final class VoiceTimes {
  const VoiceTimes({
    required this.events,
    required this.onsets,
    required this.tuplets,
  });

  /// In time order.
  final List<EventId> events;

  /// The onset of each of [events].
  final List<Moment> onsets;

  final List<TupletSpan> tuplets;
}

/// A tuplet in sounding time. It sounds from `onset` for `duration`, and
/// its members are written over `written`, which is
/// `unit.length * ratio.actual`.
typedef TupletSpan = ({
  Moment onset,
  Length duration,
  Length written,
  int depth,
});

/// Maps time in a bar to x in system space, and back.
///
/// [stops] holds each slice's onset and x, in time order, and ends with the
/// bar's length at the x where the bar's content ends. Between stops x is
/// linear in time, so every Moment has an x. The caret, a range end at the bar
/// end, a direction inside a held note and the playhead all use it.
final class TimeAxis {
  const TimeAxis(this.stops);

  final List<(Moment, double)> stops;

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

  /// The candidate whose x is nearest to [x].
  Moment nearest(Iterable<Moment> candidates, double x) => candidates.reduce(
    (a, b) => (xAt(a) - x).abs() <= (xAt(b) - x).abs() ? a : b,
  );
}

/// A staff as placed on its system.
final class PlacedStaff {
  const PlacedStaff({
    required this.staff,
    required this.top,
    required this.lines,
  });

  final StaffId staff;

  /// y of the top line of a five-line staff in system space. A one-line
  /// staff draws its line at step 4 below this.
  final double top;

  /// 5 or 1, from `Staff.lines`.
  final int lines;

  double yOf(int staffStep) => top + yOfStep(staffStep);

  int stepAt(double y) => stepAtY(y - top);
}
