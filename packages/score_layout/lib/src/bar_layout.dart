/// One bar laid out alone, the unit of the layout cache. Not exported.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'beams.dart';
import 'chords.dart';
import 'signatures.dart';
import 'spacing.dart';
import 'spanners.dart';
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
/// resolved form, with the head for each place the bar can land. Planning
/// reads [widths], [staves] and [breakBefore]. Assembly reads the rest.
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
    required this.heads,
    required this.edges,
    required this.beams,
    required this.ties,
    required this.spanners,
    required this.volta,
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
  /// outside each. The reach covers the inline and the system head. The
  /// courtesy head is drawn on the system before, so planning counts it there.
  final List<BarStaff> staves;

  /// Everything placed against one slice, in bar space.
  final List<BarItem> items;

  final BarHeads heads;
  final BarEdges edges;
  final List<BeamPlan> beams;
  final List<TieEnd> ties;
  final List<SpannerPiece> spanners;
  final VoltaStub? volta;

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
      other.heads == heads &&
      other.edges == edges &&
      _same(other.beams, beams) &&
      _same(other.ties, ties) &&
      _same(other.spanners, spanners) &&
      other.volta == volta;

  @override
  int get hashCode =>
      Object.hash(measure, length, breakBefore, restOnly, widths, lead, edges);
}

bool _same<T>(List<T> a, List<T> b) =>
    a.length == b.length && a.indexed.every((item) => b[item.$1] == item.$2);

/// One visible staff of a bar, with how far content reaches above its top line
/// and below its bottom line, in staff spaces.
typedef BarStaff = ({StaffId staff, int lines, double above, double below});

/// A bar's widths in staff spaces, known before its system is.
///
/// A system from bar i to bar j is
/// `heads(i).system + sum(body) + sum(heads(i+1..j).inline) + courtesy(j+1)`
/// wide at its natural spacing. Line breaking reads nothing else, which is
/// why it can run without building a system.
final class BarWidths {
  const BarWidths({
    required this.inlineHead,
    required this.systemHead,
    required this.courtesy,
    required this.body,
    required this.minBody,
  });

  /// Clef, key and meter changes printed when the bar is not first on its
  /// system.
  final double inlineHead;

  /// Clef, key and meter printed when the bar starts a system.
  final double systemHead;

  /// Key and meter courtesy the previous system ends with when this bar
  /// starts a system. 0 when nothing changes or the change says noCourtesy.
  final double courtesy;

  /// The lead and the slices at their ideal spacing, never below
  /// [minBody].
  final double body;

  /// The lead and the slices compressed to their rods.
  final double minBody;

  @override
  bool operator ==(Object other) =>
      other is BarWidths &&
      other.inlineHead == inlineHead &&
      other.systemHead == systemHead &&
      other.courtesy == courtesy &&
      other.body == body &&
      other.minBody == minBody;

  @override
  int get hashCode =>
      Object.hash(inlineHead, systemHead, courtesy, body, minBody);
}

/// Lays out [view] alone, for the cache.
///
/// The order is fixed by what each step reads. Chords are planned before
/// spacing, because spacing needs their reach. They are placed after it,
/// because marks stack against placed notes. A clef change inside the bar is
/// placed before spacing, left of what its slice reaches, and then widens
/// that reach.
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
  for (final staffView in view.staves) {
    for (final (:slice, :right) in letRingReach(staffView, chords)) {
      reach[slice] = widest(reach[slice], (left: 0, right: right));
    }
  }
  for (final (:slice, :right) in lineStartReach(
    view,
    chords,
    times: times,
    style: style,
    text: text,
  )) {
    reach[slice] = widest(reach[slice], (left: 0, right: right));
  }

  final items = [
    for (final (staff, staffView) in view.staves.indexed)
      ...clefChangeItems(
        staffView,
        staff: staff,
        times: times,
        reach: reach,
        style: style,
      ),
  ];
  for (final clef in items) {
    reach[clef.slice] = widest(reach[clef.slice], (
      left: -clef.drawable.bounds.left,
      right: 0,
    ));
  }

  final column = view.column;
  final heads = barHeads(view, style);
  final edges = (
    repeatStart: column.repeatStart,
    startJoins: heads.inline.items.isEmpty,
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
              staff: staff,
              voiceCount: staffView.voices.length,
              lines: lines,
              style: style,
            ),
          );
        } else {
          items
            ..addAll(placeChord(placed.plan, slice: placed.slice, staff: staff))
            ..addAll(
              graceItems(
                placed.plan,
                slice: placed.slice,
                staff: staff,
                style: style,
              ),
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

  final skylines = [for (final _ in view.staves) Skyline()];
  for (final item in items) {
    final x = item.centred ? (xs[item.slice] + xs.last) / 2 : xs[item.slice];
    skylines[item.staff].add(item.drawable.bounds.shift(x, 0));
  }
  for (final beam in beams) {
    skylines[beam.first.staff].add(beam.box);
  }

  final lead = reach.first.left + style.spacing.barPad;
  final ties = [
    for (final (staff, staffView) in view.staves.indexed)
      ...tieEnds(
        staffView,
        chords,
        skylines[staff],
        staff: staff,
        xs: xs,
        left: -lead,
      ),
  ];
  final spanners = spannerPieces(
    view,
    skylines,
    chords,
    times: times,
    xs: xs,
    style: style,
    text: text,
  );
  final volta = skylines.isEmpty
      ? null
      : voltaStub(
          view,
          skylines.first,
          xs: xs,
          left: -lead,
          headAbove: math.max(
            headReach(heads.inline, 0).above,
            headReach(heads.system, 0).above,
          ),
          style: style,
          text: text,
        );
  return BarLayout(
    measure: column.id,
    length: column.length,
    breakBefore: column.breakBefore,
    restOnly: view.isRestOnly,
    widths: BarWidths(
      inlineHead: heads.inline.width,
      systemHead:
          heads.system.width +
          arrivingRoom(ties, spanners, xs: xs, lead: lead, style: style),
      courtesy: heads.courtesy.width,
      body: lead + naturalWidth(slices),
      minBody: lead + rodWidth(slices),
    ),
    lead: lead,
    slices: slices,
    staves: [
      for (final (staff, staffView) in view.staves.indexed)
        _staffOf(staffView, staff, skylines[staff], heads),
    ],
    items: items,
    heads: heads,
    edges: edges,
    beams: beams,
    ties: ties,
    spanners: spanners,
    volta: volta,
  );
}

BarStaff _staffOf(
  StaffView view,
  int staff,
  Skyline skyline,
  BarHeads heads,
) {
  var above = skyline.above;
  var below = skyline.below;
  for (final head in [heads.inline, heads.system]) {
    final reach = headReach(head, staff);
    above = math.max(above, reach.above);
    below = math.max(below, reach.below);
  }
  return (
    staff: view.source.staff,
    lines: _linesOf(view),
    above: above,
    below: below,
  );
}

int _linesOf(StaffView view) =>
    view.part.staves.firstWhere((s) => s.id == view.source.staff).lines;
