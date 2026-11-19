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
  /// A view from already resolved parts. [Score.measureView] builds the
  /// view of a bar of a score.
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

  /// The meter differs from the previous bar's, or this is the first bar.
  final bool meterChanged;

  /// The key differs from the previous bar's, or this is the first bar.
  final bool keyChanged;

  /// The key being cancelled, for naturals on a key change. Null at the
  /// first bar.
  final KeySignature? previousKey;

  /// This bar opens a volta bracket. It has a volta, and the bar before has
  /// none or a different one.
  final bool voltaStarts;

  /// This bar closes a volta bracket. It has a volta, and the bar after has
  /// none or a different one, or this is the last bar.
  final bool voltaEnds;

  /// Visible staves only, in system order.
  final List<StaffView> staves;

  /// Pieces of spanners that touch this bar, on visible staves only, in the
  /// order of [Score.spanners].
  final List<SpannerSegment> spanners;

  /// Print a time signature at the start of this bar, because the meter
  /// changes here or the bar restates it.
  bool get printsMeter =>
      meterChanged || column.meterDisplay == SignatureDisplay.restated;

  /// Print a key signature at the start of this bar, because the key
  /// changes here or the bar restates it. Layout also prints one at the
  /// start of every system.
  bool get printsKey =>
      keyChanged || column.keyDisplay == SignatureDisplay.restated;

  /// When this bar starts a system, print a courtesy time signature at the
  /// end of the system before.
  bool get meterCourtesy =>
      index > 0 &&
      meterChanged &&
      column.meterDisplay != SignatureDisplay.noCourtesy;

  /// When this bar starts a system, print a courtesy key signature at the
  /// end of the system before.
  bool get keyCourtesy =>
      index > 0 &&
      keyChanged &&
      column.keyDisplay != SignatureDisplay.noCourtesy;

  /// Layout may fold a run of these bars into a multi-measure rest. Every
  /// voice of every visible staff is a single [MeasureRest] with no fermata,
  /// and nothing is printed in or around the bar: no spanner, direction,
  /// clef, key or meter change, measure-repeat sign, tempo, rehearsal
  /// mark, repeat, volta, navigation mark or special barline. Conservative:
  /// a mark that would not actually break the rest still does. A run also
  /// ends before a bar with a [MeasureColumn.breakBefore].
  bool get isRestOnly =>
      !printsMeter &&
      !printsKey &&
      spanners.isEmpty &&
      column.irregularLength == null &&
      column.barline == Barline.regular &&
      !column.repeatStart &&
      column.repeatEnd == null &&
      column.volta == null &&
      column.navigation.isEmpty &&
      column.rehearsal == null &&
      column.tempos.isEmpty &&
      staves.every(
        (staff) =>
            !staff.clefChanged &&
            staff.source.measureRepeat == null &&
            staff.source.clefChanges.isEmpty &&
            staff.source.directions.isEmpty &&
            staff.source.voices.every(
              (voice) => switch (voice.items.singleOrNull) {
                MeasureRest(:final articulations) => !articulations.contains(
                  Articulation.fermata,
                ),
                _ => false,
              },
            ),
      );
}

/// One staff of one bar, resolved for drawing.
final class StaffView {
  /// A view from already resolved parts. [Score.measureView] builds one for
  /// each visible staff of a bar.
  const StaffView({
    required this.source,
    required this.part,
    required this.clefChanged,
    required this.writtenKey,
    required this.voices,
    required this.accidentals,
    required this.ties,
    required this.tiedIn,
    required this.writtenPitches,
  });

  /// The staff's bar as stored: its clef, voices, clef changes and
  /// directions.
  final StaffMeasure source;

  /// The part the staff belongs to.
  final Part part;

  /// Clef in effect at the bar start.
  Clef get clef => source.clef;

  /// Print the clef at the start of this bar.
  final bool clefChanged;

  /// Key as this part reads it (concert key moved by the instrument's
  /// transposition).
  final KeySignature writtenKey;

  /// One view per voice the bar holds, voice one first and the rest in
  /// slot order.
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

  /// The pitch each note head prints at, graces included: concert pitch
  /// moved by the instrument's transposition and by any 8va line covering
  /// the note. A drum note prints at its kit position.
  final Map<NoteId, Pitch> writtenPitches;

  /// The head [note] is drawn with. A drum note takes its kit sound's.
  NoteHead headOf(Note note) => switch (note) {
    PitchedNote(:final head) => head,
    DrumNote(:final drum) => part.instrument.soundOf(drum)!.head,
  };
}

/// One voice of one staff in one bar, resolved for drawing.
final class VoiceView {
  /// A view from already resolved parts.
  const VoiceView({
    required this.slot,
    required this.events,
    required this.beams,
    required this.tuplets,
    required this.nextOpening,
  });

  /// Which voice of the staff this is.
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

  /// The event that opens this voice in the next bar. Null on the last bar,
  /// and when the next bar opens the voice with a gap or lacks it. What
  /// crosses the barline, a tie or a lyric extender, ends on it.
  final TimedEvent? nextOpening;
}

/// An event placed in time.
final class TimedEvent {
  /// [event] of [voice] at [onset] for [duration], outside any tuplet unless
  /// [tuplets] says otherwise.
  const TimedEvent({
    required this.ref,
    required this.voice,
    required this.event,
    required this.onset,
    required this.duration,
    this.tuplets = const [],
  });

  /// A reference to [event] that names the bar and staff holding it.
  final EventRef ref;

  /// The voice lane the event is in.
  final VoiceSlot voice;

  /// The event as stored.
  final Event event;

  /// Sounding offset from the bar start.
  final Moment onset;

  /// Sounding length (written length scaled by every enclosing tuplet).
  final Length duration;

  /// Enclosing tuplets, outermost first.
  final List<TupletId> tuplets;
}

/// One tuplet of a voice in one bar, placed in time for drawing its bracket
/// and number.
final class TupletView {
  /// A view from already resolved parts.
  const TupletView({
    required this.tuplet,
    required this.onset,
    required this.duration,
    required this.events,
    required this.depth,
  });

  /// The tuplet as stored, with its ratio and members.
  final Tuplet tuplet;

  /// Sounding offset of the tuplet's start from the bar start.
  final Moment onset;

  /// Sounding length of the whole tuplet.
  final Length duration;

  /// The events inside the tuplet, those of nested tuplets included, in
  /// time order.
  final List<EventId> events;

  /// 0 for an outermost tuplet.
  final int depth;
}

/// Chord events of one voice in one bar joined by beams.
final class BeamGroup {
  /// A group over [events], with no secondary breaks unless
  /// [secondaryBreaks] lists some.
  const BeamGroup(
    this.events, {
    required this.joins,
    this.secondaryBreaks = const [],
  });

  /// At least two chord events, in time order.
  final List<EventId> events;

  /// Indices into [events] before which beams beyond the first are broken
  /// (sixteenths grouped by eighth-note beat, for example).
  final List<int> secondaryBreaks;

  /// How each of [events] joins each of its beams, one list per event, with
  /// the first beam first. An event has as many beams as its value has
  /// flags. The first beam runs through the group. A deeper beam joins
  /// neighbours that share it, stops at a secondary break, and is a hook
  /// where it joins neither neighbour. A hook points forward on the first
  /// event and on an event after a secondary break, and back elsewhere. On
  /// the last event it always points back, because no event follows.
  final List<List<BeamJoin>> joins;
}

/// How an event joins one beam of its group.
enum BeamJoin {
  /// The beam starts here and runs to the next event.
  begin,

  /// The beam comes from the event before and runs on to the next.
  continued,

  /// The beam comes from the event before and stops here.
  end,

  /// A stub that points forward. The beam joins neither neighbour.
  forwardHook,

  /// A stub that points back. The beam joins neither neighbour.
  backwardHook,
}

/// A tie from a note head of this bar.
final class TieView {
  /// A view from already resolved parts.
  const TieView({
    required this.from,
    required this.to,
    required this.crossesBarline,
  });

  /// The tied head, in this bar.
  final NoteId from;

  /// Where the tie lands, possibly in the next bar. Null when no matching
  /// note follows: draw a short let-ring tie.
  final NoteRef? to;

  /// The tie lands on a head in the next bar. False for a let-ring tie,
  /// even at the end of the bar.
  final bool crossesBarline;
}

/// An accidental to print before a note head.
final class AccidentalMark {
  /// A sign for [alter], plain unless [cautionary].
  const AccidentalMark(this.alter, {this.cautionary = false});

  /// The alteration the sign shows, the note's written alteration.
  /// [Alter.natural] prints a natural sign.
  final Alter alter;

  /// Print in parentheses.
  final bool cautionary;
}

/// The part of a spanner inside one bar. [from] and [to] are offsets in
/// this bar; a spanner that continues past the barline has `endsHere` false
/// and `to` equal to the bar length.
final class SpannerSegment {
  /// A view from already resolved parts.
  const SpannerSegment({
    required this.spanner,
    required this.from,
    required this.to,
    required this.startsHere,
    required this.endsHere,
  });

  /// The whole spanner this segment is a piece of.
  final Spanner spanner;

  /// Where the segment starts: the spanner's first offset in its first bar,
  /// zero in a later bar.
  final Moment from;

  /// Where the segment stops: [Score.endOf] in the spanner's last bar, the
  /// bar length in an earlier bar.
  final Moment to;

  /// The spanner's first point is in this bar.
  final bool startsHere;

  /// The spanner's last point is in this bar.
  final bool endsHere;
}

/// What changed between two score values, for incremental layout.
final class ScoreChanges {
  /// A change set from its parts. [Score.changesSince] builds the real ones.
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

  /// Nothing changed, as between a score and itself.
  static const none = ScoreChanges(relayout: {}, removed: {}, reflow: false);

  /// Measures whose [MeasureView] may differ in anything but
  /// [MeasureView.index]. Conservative. It never misses a change and may
  /// include a neighbour that turns out identical.
  final Set<MeasureId> relayout;

  /// Measures of the earlier score that the later one lacks. Layout can
  /// drop what it cached for them.
  final Set<MeasureId> removed;

  /// The sequence of measures changed (insert, delete, re-bar), the parts
  /// changed or a bar's [MeasureColumn.breakBefore] changed. Line breaking
  /// must run again over cached measure widths, and bar numbers may have
  /// moved. It reports structural changes only. A bar in [relayout] may come
  /// out wider or narrower, and that change is layout's to detect.
  final bool reflow;

  /// Nothing needs laying out again.
  bool get isEmpty => relayout.isEmpty && removed.isEmpty && !reflow;
}

/// Everything in effect at one point of one staff.
final class ScoreContext {
  /// A context from its parts. [Score.contextAt] builds the real ones.
  const ScoreContext({
    required this.clef,
    required this.key,
    required this.writtenKey,
    required this.meter,
    required this.tempo,
    required this.octaveShift,
  });

  /// The clef in effect at the point, counting a clef change of the bar
  /// that falls at or before it.
  final Clef clef;

  /// Concert key.
  final KeySignature key;

  /// Key as the staff's part reads it: [key] moved by the instrument's
  /// transposition, and no sharps or flats for percussion.
  final KeySignature writtenKey;

  /// The meter of the bar the point is in.
  final Meter meter;

  /// The last tempo mark written at or before the point. A tempo line
  /// changes only what playback hears.
  final Tempo tempo;

  /// Octaves an octave line in effect adds to printed pitch to give the
  /// sounding pitch. It is 1, 2 or 3 under 8va, 15ma or 22ma, the negative
  /// of those under 8vb, 15mb or 22mb, and 0 with no line.
  final int octaveShift;
}
