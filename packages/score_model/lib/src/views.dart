/// Derived, read-only views for layout and editing.
///
/// Nothing here is stored or synchronized. Every value is a pure function of
/// a `Score`, computed on demand. Views hold the source objects they were
/// derived from ([MeasureView.column], [StaffView.source]) so a consumer can
/// read raw facts without a second lookup.
library;

import 'events.dart';
import 'measure.dart';
import 'pitch.dart';
import 'refs.dart';
import 'score.dart';
import 'time.dart';

/// Layout input for one bar across all staves (access pattern 5).
final class MeasureView {
  const MeasureView({
    required this.column,
    required this.index,
    required this.meterChanged,
    required this.keyChanged,
    required this.previousKey,
    required this.voltaStarts,
    required this.voltaEnds,
    required this.staves,
    required this.spanners,
  });

  /// The bar itself: meter, key, barline, repeats, volta, navigation,
  /// rehearsal mark, tempo marks.
  final MeasureColumn column;

  /// Zero-based position in the score.
  final int index;

  /// Print a time signature at the start of this bar.
  final bool meterChanged;

  /// Print a key signature at the start of this bar.
  final bool keyChanged;

  /// The key being cancelled, for naturals on a key change. Null at the
  /// first bar.
  final KeySignature? previousKey;

  final bool voltaStarts;
  final bool voltaEnds;

  /// Visible staves only, in system order.
  final List<StaffView> staves;

  /// Pieces of spanners that touch this bar.
  final List<SpannerSegment> spanners;

  /// Every voice is a single [MeasureRest] and no bar-level mark interrupts:
  /// layout may fold a run of these into a multi-measure rest.
  bool get isRestOnly => throw UnimplementedError();
}

/// One staff of one bar, resolved for drawing.
final class StaffView {
  const StaffView({
    required this.source,
    required this.part,
    required this.clefChanged,
    required this.writtenKey,
    required this.voices,
    required this.accidentals,
    required this.ties,
    required this.tiedIn,
  });

  final StaffMeasure source;
  final Part part;

  /// Clef in effect at the bar start (same as `source.clef`).
  Clef get clef => source.clef;

  /// Print the clef at the start of this bar.
  final bool clefChanged;

  /// Key as this part reads it (concert key moved by the instrument's
  /// transposition).
  final KeySignature writtenKey;

  final List<VoiceView> voices;

  /// Accidental to print per note head. A note absent from the map prints
  /// none. Resolved across all voices of the staff with the standard rules:
  /// key signature; an accidental holds to the end of the bar at that staff
  /// position and octave; a note tied in from the previous bar prints none;
  /// [AccidentalRequest] overrides. Quarter tones follow the same rules.
  final Map<NoteId, AccidentalMark> accidentals;

  /// Ties that start in this bar. A tie whose end is in the next bar has
  /// [TieView.crossesBarline] set.
  final List<TieView> ties;

  /// Notes in this bar that a tie from the previous bar ends on.
  final List<NoteId> tiedIn;

  /// The pitch as printed: concert pitch moved by the instrument's
  /// transposition and by any 8va line covering the note.
  Pitch writtenPitch(Note note) => throw UnimplementedError();
}

final class VoiceView {
  const VoiceView({
    required this.slot,
    required this.events,
    required this.beams,
    required this.tuplets,
  });

  final VoiceSlot slot;

  /// Every event in time order with its onset. Gaps are omitted; grace
  /// chords ride on their principal event.
  final List<TimedEvent> events;

  /// Beam groups from the meter's default breaks, the events' [BeamMode]s,
  /// and durations (only eighths and shorter beam; rests break beams unless
  /// surrounded by beamed notes in the same beat).
  final List<BeamGroup> beams;

  /// Tuplets flattened for drawing brackets and numbers.
  final List<TupletView> tuplets;
}

/// An event placed in time. Returned by the views and by `Score.lookup`.
final class TimedEvent {
  const TimedEvent({
    required this.ref,
    required this.voice,
    required this.event,
    required this.onset,
    required this.duration,
    this.tuplets = const [],
  });

  final EventRef ref;
  final VoiceSlot voice;
  final Event event;

  /// Sounding offset from the bar start.
  final Moment onset;

  /// Sounding length (written length scaled by every enclosing tuplet).
  final Length duration;

  /// Enclosing tuplets, outermost first.
  final List<TupletId> tuplets;
}

final class TupletView {
  const TupletView({
    required this.tuplet,
    required this.onset,
    required this.duration,
    required this.events,
    required this.depth,
  });

  final Tuplet tuplet;
  final Moment onset;
  final Length duration;
  final List<EventId> events;

  /// 0 for an outermost tuplet.
  final int depth;
}

final class BeamGroup {
  const BeamGroup(this.events, {this.secondaryBreaks = const []});

  /// At least two chord events, in time order.
  final List<EventId> events;

  /// Indices into [events] before which beams beyond the first are broken
  /// (sixteenths grouped by eighth-note beat, for example).
  final List<int> secondaryBreaks;
}

final class TieView {
  const TieView({
    required this.from,
    required this.to,
    required this.crossesBarline,
  });

  final NoteId from;

  /// Where the tie lands, possibly in the next bar. Null when no matching
  /// note follows: draw a short let-ring tie.
  final NoteRef? to;

  final bool crossesBarline;
}

final class AccidentalMark {
  const AccidentalMark(this.alter, {this.cautionary = false});

  final Alter alter;

  /// Print in parentheses.
  final bool cautionary;
}

/// The part of a spanner inside one bar. [from] and [to] are offsets in
/// this bar; a spanner that continues past the barline has `endsHere` false
/// and `to` equal to the bar length.
final class SpannerSegment {
  const SpannerSegment({
    required this.spanner,
    required this.from,
    required this.to,
    required this.startsHere,
    required this.endsHere,
  });

  final Spanner spanner;
  final Moment from;
  final Moment to;
  final bool startsHere;
  final bool endsHere;
}

/// What changed between two score values, for incremental layout.
final class ScoreChanges {
  const ScoreChanges({
    required this.relayout,
    required this.removed,
    required this.reflow,
  });

  /// Every measure of [score] must be laid out; used for the first layout.
  factory ScoreChanges.all(Score score) => ScoreChanges(
    relayout: {for (final column in score.measures) column.id},
    removed: const {},
    reflow: true,
  );

  static const none = ScoreChanges(relayout: {}, removed: {}, reflow: false);

  /// Measures whose [MeasureView] may differ. Conservative: never misses a
  /// change, may include a neighbour that turns out identical.
  final Set<MeasureId> relayout;

  /// Measures that no longer exist.
  final Set<MeasureId> removed;

  /// The sequence of measures changed (insert, delete, re-bar) or the parts
  /// changed: line breaking must run again over cached measure widths.
  final bool reflow;

  bool get isEmpty => relayout.isEmpty && removed.isEmpty && !reflow;
}

/// Everything in effect at one point of one staff.
final class ScoreContext {
  const ScoreContext({
    required this.clef,
    required this.key,
    required this.writtenKey,
    required this.meter,
    required this.tempo,
    required this.octaveShift,
  });

  final Clef clef;

  /// Concert key.
  final KeySignature key;
  final KeySignature writtenKey;
  final Meter meter;
  final Tempo tempo;

  /// Octaves an 8va/8vb line in effect adds to printed pitch. 0 for none.
  final int octaveShift;
}
