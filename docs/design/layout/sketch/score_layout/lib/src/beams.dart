/// Beams. One slope per group, stems that meet it, secondary beams and hooks.
/// Not exported.
///
/// The model says which events beam together (`BeamGroup`) and how each
/// joins every level (`BeamGroup.joins`, model addition B2b). Layout
/// decides the geometry. A beam never crosses a barline, so it belongs to
/// one bar, but its stems depend on the system's stretch. So the bar keeps
/// a plan in bar space and the system draws it.
library;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'chords.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'model_additions.dart';
import 'style.dart';

/// A beam decided in bar space.
final class BeamPlan {
  const BeamPlan({
    required this.stem,
    required this.events,
    required this.stems,
    required this.first,
    required this.last,
    required this.joins,
    required this.boxes,
  });

  final StemSide stem;

  /// The group's events in time order. Each owns its stem and its hooks. A
  /// beam between two stems belongs to no one event, so it has no owner.
  final List<EventRef> events;

  /// Where each event's stem leaves its outer head, in time order.
  final List<BarAnchor> stems;

  /// Ends of the primary beam's outer edge, at the first and last stem.
  final BarAnchor first;
  final BarAnchor last;

  /// Per event, per level, how it joins.
  final List<List<BeamJoin>> joins;

  /// What the beam and its stems cover at stretch 1, x from the bar's
  /// first slice and y from the staff's top line. The first box is the
  /// beam's own, and one box per stem follows, from its head to the far
  /// edge of the beam. The bar's skyline takes them, so what stands over one
  /// note of the group is that note's stem and not the group's tallest
  /// note. A stretch moves the stems apart and keeps both end heights, so
  /// the vertical range holds at any stretch.
  final List<Box> boxes;

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();
}

/// The stem side of every beamed chord of [voice]. A group takes one side, the
/// side most of its chords want by `stemSideFor`, and on a tie the side of the
/// chord farthest from the middle line. Decided before the chords are planned,
/// because the stem side decides which heads flip.
Map<EventId, StemSide> beamStemSides(VoiceView voice, StaffView staff) =>
    throw UnimplementedError();

/// Plans the beam of [group] over [chords], its chords in time order.
///
/// The slope follows the first and last outer heads, capped at half a
/// space in all, and is flat when the inner notes do not follow it. Each
/// end stem is at least 3.5 spaces long plus half a space per extra level,
/// and the beam is moved so it never floats inside a staff space. [xs]
/// holds the slices' x at stretch 1, where the slope is decided. The ends
/// are stored as offsets from their slices, so a stretched system flattens
/// the beam and keeps its end heights.
BeamPlan planBeam(
  BeamGroup group,
  List<PlacedChord> chords, {
  required List<double> xs,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The beam and its stems at their final place.
///
/// The end stems run from their heads to the beam's ends. Each inner stem
/// runs to the line between the ends at its own final x, so every stem
/// touches the beam at any stretch. Each level is a polygon
/// `beamThickness` thick, `beamSpacing` from the next, and a hook is one
/// notehead wide.
List<Drawable> placeBeam(BeamPlan plan, BarFrame frame, EngravingStyle style) =>
    throw UnimplementedError();
