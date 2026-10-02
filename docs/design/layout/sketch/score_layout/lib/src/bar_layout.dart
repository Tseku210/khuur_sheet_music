/// One bar laid out alone, the unit of the layout cache. Not exported.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'beams.dart';
import 'chords.dart';
import 'lyrics.dart';
import 'marks.dart';
import 'signatures.dart';
import 'spacing.dart';
import 'spanners.dart';
import 'style.dart';
import 'system_layout.dart';
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
/// resolved form. That is the head for each place the bar can land, tie ends,
/// spanner pieces, the volta stub, tuplet stubs and the flow of each lyric
/// lane. Planning reads [widths], [staves], [lyrics] and [breakBefore].
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
    required this.heads,
    required this.edges,
    required this.beams,
    required this.tuplets,
    required this.ties,
    required this.spanners,
    required this.volta,
    required this.lyrics,
    required this.voices,
  });

  final MeasureId measure;
  final Length length;

  /// `MeasureColumn.breakBefore`. A change of it makes a new column, so
  /// the bar is laid out again and line breaking sees a new object.
  final LayoutBreak? breakBefore;

  /// Whether the bar can fold into a multi-measure rest. It is
  /// `MeasureView.isRestOnly`, less a bar whose rest carries a fermata,
  /// which the model lets through and a fold would hide.
  final bool restOnly;

  final BarWidths widths;

  /// Clear space from the end of the bar's head to its first slice. It is what
  /// the first slice reaches to the left, plus `SpacingPolicy.barPad`.
  final double lead;

  final List<Slice> slices;

  /// The visible staves, top to bottom, with how far the bar's content reaches
  /// outside each. The reach includes the room of every piece that crosses the
  /// bar, which is tie ends, spanner pieces and the volta bracket. Lyric rows
  /// are not in it. Planning adds them from [lyrics], because a row's height
  /// belongs to the system.
  final List<BarStaff> staves;

  /// Everything placed against one slice, in bar space.
  final List<BarItem> items;

  final BarHeads heads;
  final BarEdges edges;
  final List<BeamPlan> beams;
  final List<TupletStub> tuplets;
  final List<TieEnd> ties;
  final List<SpannerPiece> spanners;
  final VoltaStub? volta;
  final BarLyrics lyrics;

  /// Each voice's events and tuplets in time, for hit testing.
  final Map<(StaffId, VoiceSlot), VoiceTimes> voices;
}

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
/// because marks stack against placed notes. The marks widen the reach
/// last, since what they need depends on the rods the notes already give.
///
/// Ties reserve their room first. A tie keeps to its heads and reads nothing
/// from the skyline, so every mark after it stands clear of it. Each mark
/// then takes the next free room in its staff's skyline, in this order. Per
/// staff, every event's articulations, ornament, string marks and fermata,
/// voice by voice. Then the tuplets of each voice, then the staff's
/// directions. Slurs and lines reserve their room after these. The system
/// marks then stack over the top staff, outside what a slur or a line needs
/// there, and the volta goes outermost.
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
  final lyrics = lyricsOf(view, times, chords, style, text);
  for (final syllable in lyrics.syllables) {
    reach[syllable.slice] = widest(reach[syllable.slice], syllable.reach);
  }
  // A clef change sits left of everything its slice reaches, so it is
  // placed against the finished reach and then widens it.
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
  final trills = trillLineStarts(view);
  reach.setAll(
    0,
    markReach(
      view,
      chords,
      reach,
      times: times,
      trills: trills,
      style: style,
      text: text,
    ),
  );

  final column = view.column;
  final heads = barHeads(view, style);
  final edges = (
    repeatStart: column.repeatStart,
    startJoins: heads.inline.items.isEmpty,
    end: column.barline,
    repeatEnd: column.repeatEnd,
  );
  final lead = reach.first.left + style.spacing.barPad;
  final label = voltaLabel(view, style, text);
  final slices = widenedTo(
    spaceSlices(
      view,
      times,
      reach,
      style.spacing,
      end: endBarlineWidth(edges, style),
    ),
    voltaLabelRoom(view, label) - lead,
  );
  final xs = sliceXs(slices, 1, 0);

  final beams = <BeamPlan>[];
  for (final (staff, staffView) in view.staves.indexed) {
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
              lines: staffView.part.staves
                  .firstWhere((s) => s.id == staffView.source.staff)
                  .lines,
              xs: xs,
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
    skylines[item.staff].add(item.drawable.bounds.shift(xs[item.slice], 0));
  }
  for (final beam in beams) {
    beam.boxes.forEach(skylines[beam.first.staff].add);
  }

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
  final tuplets = <TupletStub>[];
  for (final (staff, staffView) in view.staves.indexed) {
    final skyline = skylines[staff];
    final voices = staffView.voices.length;
    for (final voice in staffView.voices) {
      for (final timed in voice.events) {
        final placed = chords[timed.event.id];
        if (placed != null) {
          items
            ..addAll(
              articulationItems(
                placed,
                skyline,
                voices: voices,
                xs: xs,
                style: style,
              ),
            )
            ..addAll(
              ornamentItems(
                placed,
                skyline,
                voices: voices,
                lineStarts: trills.contains(timed.event.id),
                xs: xs,
                style: style,
              ),
            )
            ..addAll(
              stringMarkItems(
                placed,
                skyline,
                voices: voices,
                strings: staffView.part.instrument.strings.length,
                xs: xs,
                style: style,
                text: text,
              ),
            );
        }
        items.addAll(
          fermataItems(
            timed,
            skyline,
            chord: placed,
            slice: times.indexOf(timed.onset),
            staff: staff,
            voices: voices,
            xs: xs,
            style: style,
          ),
        );
      }
    }
    for (final voice in staffView.voices) {
      tuplets.addAll(
        tupletStubs(
          voice,
          chords,
          skyline,
          staff: staff,
          times: times,
          xs: xs,
          style: style,
        ),
      );
    }
    items.addAll(
      directionItems(
        staffView,
        skyline,
        staff: staff,
        times: times,
        xs: xs,
        style: style,
        text: text,
      ),
    );
  }
  final top = skylines.firstOrNull;
  final spanners = spannerPieces(
    view,
    skylines,
    chords,
    times: times,
    xs: xs,
    style: style,
    text: text,
  );
  if (top != null) {
    items.addAll(
      systemMarkItems(
        view,
        top,
        times: times,
        xs: xs,
        left: -lead,
        style: style,
        text: text,
      ),
    );
  }
  final volta = top == null
      ? null
      : voltaStub(
          view,
          top,
          xs: xs,
          left: -lead,
          headAbove: math.max(
            headReach(heads.inline, 0).above,
            headReach(heads.system, 0).above,
          ),
          label: label,
          style: style,
        );

  return BarLayout(
    measure: column.id,
    length: column.length,
    breakBefore: column.breakBefore,
    restOnly:
        view.isRestOnly &&
        !view.staves.any(
          (staff) => staff.voices.any(
            (voice) => voice.events.any(
              (timed) =>
                  timed.event.articulations.contains(Articulation.fermata),
            ),
          ),
        ),
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
    tuplets: tuplets,
    ties: ties,
    spanners: spanners,
    volta: volta,
    lyrics: lyrics,
    voices: {
      for (final staffView in view.staves)
        for (final voice in staffView.voices)
          (staffView.source.staff, voice.slot): _timesOf(voice),
    },
  );
}

/// The staff's reach. It is its skyline, widened by whichever head the bar may
/// print. The courtesy head is drawn on the system before, so planning counts
/// it there (`headReach` of the next bar).
BarStaff _staffOf(StaffView view, int staff, Skyline skyline, BarHeads heads) {
  var above = skyline.above;
  var below = skyline.below;
  for (final head in [heads.inline, heads.system]) {
    final reach = headReach(head, staff);
    above = math.max(above, reach.above);
    below = math.max(below, reach.below);
  }
  final id = view.source.staff;
  return (
    staff: id,
    lines: view.part.staves.firstWhere((s) => s.id == id).lines,
    above: above,
    below: below,
  );
}

VoiceTimes _timesOf(VoiceView voice) => VoiceTimes(
  events: [for (final timed in voice.events) timed.event.id],
  onsets: [for (final timed in voice.events) timed.onset],
  tuplets: [
    for (final view in voice.tuplets)
      (
        onset: view.onset,
        duration: view.duration,
        written: view.tuplet.unit.length * Fraction(view.tuplet.ratio.actual),
        depth: view.depth,
      ),
  ],
);
