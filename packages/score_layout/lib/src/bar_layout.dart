/// One bar laid out alone, the unit of the layout cache. Not exported.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'beams.dart';
import 'chords.dart';
import 'geometry.dart';
import 'signatures.dart';
import 'spacing.dart';
import 'style.dart';
import 'text.dart';

/// A bar laid out without knowing which system it lands in.
///
/// Invariant: a BarLayout is a function of its bar's `MeasureView`, the
/// style and the text measurer, and of nothing else. [layoutBar] takes no
/// score. So it stays valid exactly as long as `Score.changesSince` leaves
/// its measure out of `relayout`, and it holds no bar number, no x on a
/// line and nothing about its neighbours.
///
/// It also keeps no view. Everything a system needs from the bar is here in
/// resolved form. Planning reads [widths], [staves] and [breakBefore].
/// Assembly reads the rest.
final class BarLayout {
  const BarLayout({
    required this.measure,
    required this.length,
    required this.breakBefore,
    required this.restOnly,
    required this.widths,
    required this.lead,
    required this.slices,
    required this.staves,
    required this.items,
    required this.edges,
    required this.beams,
  });

  final MeasureId measure;
  final Length length;

  /// `MeasureColumn.breakBefore`. A change of it makes a new column, so
  /// the bar is laid out again and line breaking sees a new object.
  final LayoutBreak? breakBefore;

  /// From `MeasureView.isRestOnly`. Such a bar can fold into a multi-measure
  /// rest.
  final bool restOnly;

  final BarWidths widths;

  /// Clear space from the end of the bar's head to its first slice. It is what
  /// the first slice reaches to the left, plus `SpacingPolicy.barPad`.
  final double lead;

  final List<Slice> slices;

  /// The visible staves, top to bottom, with how far the bar's content reaches
  /// outside each.
  final List<BarStaff> staves;

  /// Everything placed against one slice, in bar space.
  final List<BarItem> items;

  final BarEdges edges;
  final List<BeamPlan> beams;

  @override
  bool operator ==(Object other) =>
      other is BarLayout &&
      other.measure == measure &&
      other.length == length &&
      other.breakBefore == breakBefore &&
      other.restOnly == restOnly &&
      other.widths == widths &&
      other.lead == lead &&
      _same(other.slices, slices) &&
      _same(other.staves, staves) &&
      _same(other.items, items) &&
      other.edges == edges &&
      _same(other.beams, beams);

  @override
  int get hashCode =>
      Object.hash(measure, length, breakBefore, restOnly, widths, lead, edges);
}

bool _same<T>(List<T> a, List<T> b) =>
    a.length == b.length && a.indexed.every((item) => b[item.$1] == item.$2);

/// One visible staff of a bar, with how far content reaches above its top line
/// and below its bottom line, in staff spaces.
typedef BarStaff = ({StaffId staff, int lines, double above, double below});

/// A bar's body widths in staff spaces, known before its system is. The
/// widths of the bar's heads arrive with the unit that draws signatures.
final class BarWidths {
  const BarWidths({required this.body, required this.minBody});

  /// The lead and the slices at their ideal spacing, never below
  /// [minBody].
  final double body;

  /// The lead and the slices compressed to their rods.
  final double minBody;

  @override
  bool operator ==(Object other) =>
      other is BarWidths && other.body == body && other.minBody == minBody;

  @override
  int get hashCode => Object.hash(body, minBody);
}

/// Lays out [view] alone, for the cache.
///
/// The order is fixed by what each step reads. Chords are planned before
/// spacing, because spacing needs their reach. They are placed after it,
/// because marks stack against placed notes.
BarLayout layoutBar(
  MeasureView view,
  EngravingStyle style,
  TextMeasurer text,
) {
  final times = sliceTimes(view);
  final chords = <EventId, PlacedChord>{};
  final reach = List<SliceReach>.filled(times.length, noReach);
  for (final (staff, staffView) in view.staves.indexed) {
    for (final voice in staffView.voices) {
      final sides = beamStemSides(voice, staffView);
      for (final timed in voice.events) {
        final slice = times.indexOf(timed.onset);
        final event = timed.event;
        if (event is ChordEvent) {
          final plan = planChord(
            timed: timed,
            chord: event,
            staff: staffView,
            stem:
                sides[event.id] ??
                stemSideFor(event, staffView, voice.slot, at: timed.onset),
            beamed: sides.containsKey(event.id),
            style: style,
          );
          chords[event.id] = (plan: plan, slice: slice, staff: staff);
          reach[slice] = widest(reach[slice], plan.reach);
        } else {
          reach[slice] = widest(reach[slice], restReach(event, style));
        }
      }
    }
  }

  final column = view.column;
  final edges = (
    repeatStart: column.repeatStart,
    startJoins:
        !view.printsKey &&
        !view.printsMeter &&
        view.staves.every((staff) => !staff.clefChanged),
    end: column.barline,
    repeatEnd: column.repeatEnd,
  );
  final slices = spaceSlices(
    view,
    times,
    reach,
    style.spacing,
    end: endBarlineWidth(edges, style),
  );
  final xs = sliceXs(slices, 1, 0);

  final items = <BarItem>[];
  final beams = <BeamPlan>[];
  for (final (staff, staffView) in view.staves.indexed) {
    final lines = _linesOf(staffView);
    for (final voice in staffView.voices) {
      for (final timed in voice.events) {
        final placed = chords[timed.event.id];
        if (placed == null) {
          items.addAll(
            placeRest(
              timed: timed,
              slice: times.indexOf(timed.onset),
              lastSlice: times.length - 1,
              staff: staff,
              voiceCount: staffView.voices.length,
              lines: lines,
              xs: xs,
              style: style,
            ),
          );
        } else {
          items
            ..addAll(placeChord(placed.plan, slice: placed.slice, staff: staff))
            ..addAll(
              graceItems(placed.plan, slice: placed.slice, staff: staff),
            );
        }
      }
      for (final group in voice.beams) {
        beams.add(
          planBeam(
            group,
            [for (final id in group.events) chords[id]!],
            xs: xs,
            style: style,
          ),
        );
      }
    }
  }

  final above = List<double>.filled(view.staves.length, 0);
  final below = List<double>.filled(view.staves.length, 0);
  void cover(int staff, Box box) {
    above[staff] = math.max(above[staff], -box.top);
    below[staff] = math.max(below[staff], box.bottom - staffHeight);
  }

  for (final item in items) {
    cover(item.staff, item.drawable.bounds);
  }
  for (final beam in beams) {
    cover(beam.first.staff, beam.box);
  }

  final lead = reach.first.left + style.spacing.barPad;
  return BarLayout(
    measure: column.id,
    length: column.length,
    breakBefore: column.breakBefore,
    restOnly: view.isRestOnly,
    widths: BarWidths(
      body: lead + naturalWidth(slices),
      minBody: lead + rodWidth(slices),
    ),
    lead: lead,
    slices: slices,
    staves: [
      for (final (staff, staffView) in view.staves.indexed)
        (
          staff: staffView.source.staff,
          lines: _linesOf(staffView),
          above: above[staff],
          below: below[staff],
        ),
    ],
    items: items,
    edges: edges,
    beams: beams,
  );
}

int _linesOf(StaffView view) =>
    view.part.staves.firstWhere((s) => s.id == view.source.staff).lines;
