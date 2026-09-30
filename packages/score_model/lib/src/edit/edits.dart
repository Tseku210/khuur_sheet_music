/// Edits: the only way a score changes.
///
/// Every edit is plain data naming its targets explicitly (no hidden "current
/// cursor"), so an edit means the same thing whenever it runs. `EditSession`
/// applies them; each applied edit is one undo step.
///
/// Policies that shape the whole model are stated on the edits that carry
/// them:
/// - Note entry overwrites; it never pushes music forward. See [EnterNote].
/// - Overfill splits at the barline and ties into the next bar. See
///   [EnterNote].
/// - A meter change re-bars the music up to the next meter change, section
///   by section. See [SetMeter].
/// - Key and clef changes keep sounding pitches. See [SetKey], [SetClef].
library;

import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../refs.dart';
import '../score.dart';
import '../seq.dart';
import '../time.dart';
import 'session.dart' show Clip, Selection;

sealed class Edit {
  const Edit();

  /// Short English label for the undo menu. The app localizes by edit type.
  String get label;
}

// --- Note entry -----------------------------------------------------------

/// Writes a note of [value] (written) with [pitch] at [at], replacing
/// whatever sounded in that voice from `at` for the note's length.
///
/// Overwrite policy: the span `[at, at + length)` of the voice is cleared
/// and the note put there. A note or rest cut at the start keeps its head
/// (re-spelled with `Meter.spell`); whatever remains after the end becomes
/// rests. Nothing moves in time and no other voice or staff is touched.
///
/// Overfill policy (access pattern 9) is [overfill]. With the default,
/// [Overfill.splitAndTie], a note longer than the room left in the bar is
/// split at the barline and the pieces are tied, and the write continues
/// into the next bar under the same rule. Past the last bar, bars are
/// appended with the last bar's meter, key and clefs. With
/// [Overfill.refuse] the edit returns `Refused(WouldCrossBarline)` instead,
/// which the app shows as Maestro's "need a bar line". Either way the bar
/// is never overfull and never grows.
///
/// Inside a tuplet, [value] is read in the tuplet's time (entering an eighth
/// inside a triplet writes a triplet eighth), and the note must end inside
/// that tuplet or the edit returns `Refused(WouldSplitTuplet)`. A write that
/// would cover only part of a tuplet from outside replaces the whole tuplet
/// with rests first.
///
/// Afterwards the cursor sits at the end of the note (offset 0 of the next
/// bar if it ended on a barline, with an empty bar appended if it ended the
/// score) and the new event is selected.
final class EnterNote extends Edit {
  const EnterNote({
    required this.at,
    required this.pitch,
    required this.value,
    this.overfill = Overfill.splitAndTie,
  });

  final VoicePoint at;
  final Pitch pitch;
  final NoteValue value;
  final Overfill overfill;

  @override
  String get label => 'Enter note';
}

/// [EnterNote] for a rest. In voices two to four, a rest can be turned into
/// a gap with [Erase].
final class EnterRest extends Edit {
  const EnterRest({
    required this.at,
    required this.value,
    this.overfill = Overfill.splitAndTie,
  });

  final VoicePoint at;
  final NoteValue value;
  final Overfill overfill;

  @override
  String get label => 'Enter rest';
}

/// What note entry and paste do with music that runs past the barline.
enum Overfill {
  /// Split at the barline, tie the pieces, continue in the next bar.
  splitAndTie,

  /// Refuse with `WouldCrossBarline`.
  refuse,
}

/// Adds [pitch] to [event] (access pattern 2). A single note becomes a
/// chord; a rest becomes a note of the rest's value. Adding a pitch the
/// chord already has is a no-op (idempotent). If the chord is tied into
/// the next event, the new note is tied too when the next event has the
/// same pitch.
final class AddToChord extends Edit {
  const AddToChord({required this.event, required this.pitch});

  final EventRef event;
  final Pitch pitch;

  @override
  String get label => 'Add note to chord';
}

/// Removes one head from a chord. Removing the last head leaves a rest of
/// the same value.
final class RemoveNote extends Edit {
  const RemoveNote(this.note);

  final NoteRef note;

  @override
  String get label => 'Delete note';
}

/// Changes one head's pitch. If the note is part of a tie chain, the whole
/// chain changes so the tie stays valid.
final class SetPitch extends Edit {
  const SetPitch(this.note, this.pitch);

  final NoteRef note;
  final Pitch pitch;

  @override
  String get label => 'Change pitch';
}

/// Changes an event's written value. Shorter: the freed time becomes rests.
/// Longer: overwrites what follows, with the same barline rule as
/// [EnterNote].
final class SetValue extends Edit {
  const SetValue(this.event, this.value);

  final EventRef event;
  final NoteValue value;

  @override
  String get label => 'Change duration';
}

/// Creates a tuplet at [at] filled with rests of [unit], overwriting like
/// [EnterNote]. A tuplet never crosses a barline: refused with
/// [WouldSplitTuplet] if it does not fit in the bar.
final class EnterTuplet extends Edit {
  const EnterTuplet({
    required this.at,
    required this.ratio,
    required this.unit,
  });

  final VoicePoint at;
  final TupletRatio ratio;
  final NoteValue unit;

  @override
  String get label => 'Enter tuplet';
}

final class AddGrace extends Edit {
  const AddGrace({
    required this.event,
    required this.pitch,
    this.kind = GraceKind.acciaccatura,
    this.value = NoteValue.eighth,
  });

  final EventRef event;
  final Pitch pitch;
  final GraceKind kind;
  final NoteValue value;

  @override
  String get label => 'Add grace note';
}

/// Sets or clears the tie from [note] to the same pitch in the next event.
/// Idempotent.
final class SetTie extends Edit {
  const SetTie(this.note, {required this.tied});

  final NoteRef note;
  final bool tied;

  @override
  String get label => tied ? 'Add tie' : 'Remove tie';
}

/// Clears what is selected: events in voice one become rests (a bar left
/// with only rests becomes one [MeasureRest]); in voices two to four they
/// become gaps, and a voice left with only gaps disappears. A range also
/// clears directions and spanners inside it. Bars are never removed; see
/// [DeleteMeasures].
final class Erase extends Edit {
  const Erase(this.selection);

  final Selection selection;

  @override
  String get label => 'Delete';
}

// --- Marks ------------------------------------------------------------------

/// Adds or removes one articulation. Idempotent, so "toggle" is decided by
/// the caller from what it sees.
final class SetArticulation extends Edit {
  const SetArticulation(this.event, this.articulation, {required this.present});

  final EventRef event;
  final Articulation articulation;
  final bool present;

  @override
  String get label => 'Articulation';
}

/// Sets or clears the ornament sign on a chord. Idempotent.
final class SetOrnament extends Edit {
  const SetOrnament(this.event, this.ornament);

  final EventRef event;
  final Ornament? ornament;

  @override
  String get label => 'Ornament';
}

/// Sets or clears the bow direction on a chord. Idempotent.
final class SetBowing extends Edit {
  const SetBowing(this.event, this.bowing);

  final EventRef event;
  final Bowing? bowing;

  @override
  String get label => 'Bowing';
}

final class SetFingering extends Edit {
  const SetFingering(this.note, this.finger);

  final NoteRef note;
  final int? finger;

  @override
  String get label => 'Fingering';
}

/// Which string plays [note]: an index into the instrument's `strings`.
final class SetString extends Edit {
  const SetString(this.note, this.string);

  final NoteRef note;
  final int? string;

  @override
  String get label => 'String';
}

final class SetAccidental extends Edit {
  const SetAccidental(this.note, this.request);

  final NoteRef note;
  final AccidentalRequest request;

  @override
  String get label => 'Accidental';
}

/// Sets or clears (null) verse [verse] of [event]'s lyrics.
final class SetLyric extends Edit {
  const SetLyric(this.event, this.verse, this.lyric);

  final EventRef event;
  final int verse;
  final Lyric? lyric;

  @override
  String get label => 'Lyric';
}

/// Replaces the directions (dynamics, text, chord symbols) of one staff in
/// one bar. Adding, removing and moving are all this one idempotent edit.
/// They are stored in time order, keeping the given order at one time.
/// Refused with [StaleReference] for a bar or staff that is gone and
/// [OutsideMeasure] for a direction outside the bar.
final class SetDirections extends Edit {
  const SetDirections({
    required this.staff,
    required this.measure,
    required this.directions,
  });

  final StaffId staff;
  final MeasureId measure;
  final Seq<StaffDirection> directions;

  @override
  String get label => 'Directions';
}

/// Adds a spanner from [first] to [last] on [staff], with a new id, at the
/// end of `Score.spanners`. A slur or glissando belongs to [voice], voice
/// one when it names none, and must end after it starts. A line or hairpin
/// belongs to the staff, so [voice] is ignored, and may start and end on
/// one event. Refused with [StaleReference] for a bar or staff that is
/// gone, [OutsideMeasure] for an end outside its bar, and [InvalidValue]
/// for ends out of order.
final class AddSpanner extends Edit {
  const AddSpanner({
    required this.kind,
    required this.staff,
    required this.first,
    required this.last,
    this.voice,
  });

  final SpannerKind kind;
  final StaffId staff;
  final VoiceSlot? voice;
  final ScorePoint first;
  final ScorePoint last;

  @override
  String get label => 'Add line';
}

/// Removes one spanner. Refused with [StaleReference] when it is gone.
final class RemoveSpanner extends Edit {
  const RemoveSpanner(this.spanner);

  final SpannerId spanner;

  @override
  String get label => 'Remove line';
}

// --- Context ----------------------------------------------------------------

/// Changes the meter from bar [from] onward (access pattern 8).
///
/// Scope: [from] and every following bar that carried the same meter as
/// [from], up to the next different meter. Bars after that keep theirs. A
/// meter of the same length, such as common time for 4/4, only replaces
/// the meter.
///
/// Re-bar policy: inside the scope the music is re-barred, one *section* at
/// a time. A section ends at a barline the composer gave meaning: a repeat
/// sign, a volta boundary, a key change, a rehearsal or navigation mark, or
/// any barline other than a plain one. A pickup or other irregular bar is a
/// section of its own and keeps its content. Those barlines never move.
/// Within a section, each voice's content is laid end to end and cut into
/// bars of the new length; a note crossing a new barline is split and tied
/// (as in [EnterNote]); the section's last bar is padded with rests in
/// voice one and gaps in the others. Trailing rests and gaps are elastic:
/// they are dropped before cutting, so a section never gains bars just
/// because it held rests, and a section never loses bars (surplus bars
/// stay, filled with rests). A rest with a fermata is music, not elastic.
/// Bars keep their ids in order; extra bars get new ids. A tie whose end
/// now meets a different head is cleared.
///
/// Tempo marks, directions, clef changes, spanner anchors, the cursor and a
/// range selection keep their absolute time within the section and move to
/// whichever new bar holds that time. Marks in dropped trailing time are
/// dropped. A start or the cursor there moves on to the bar after the
/// section, and an end moves back to the section's last bar.
///
/// Refused with [WouldSplitTuplet] if a new barline would cut a tuplet.
/// Setting the meter a bar already has is a no-op.
///
/// With [MeterContent.keepBars] nothing is re-barred: each bar in scope
/// keeps its own content under the new meter. Trailing rests are dropped
/// first; a bar that is still too long refuses the edit with
/// [WouldCrossBarline], and a short bar is padded.
final class SetMeter extends Edit {
  const SetMeter({
    required this.from,
    required this.meter,
    this.content = MeterContent.rebar,
  });

  final MeasureId from;
  final Meter meter;
  final MeterContent content;

  @override
  String get label => 'Time signature';
}

/// What a meter change does to the music already in the bars.
enum MeterContent {
  /// Lay the music end to end and cut it into bars of the new length.
  rebar,

  /// Keep every bar's content where it is.
  keepBars,
}

/// Changes the key from bar [from] up to the next bar whose key differed
/// from [from]'s. Notes keep their spelled, sounding pitch; only printed
/// accidentals change. Idempotent.
final class SetKey extends Edit {
  const SetKey({required this.from, required this.key});

  final MeasureId from;
  final KeySignature key;

  @override
  String get label => 'Key signature';
}

/// Puts [clef] on [staff] at [at]. At offset 0 it becomes the bar's starting
/// clef. Mid-bar it adds a [ClefChange], or replaces the one at that time.
/// A change to the clef already in effect is dropped, so setting the clef
/// in effect removes a change. When the bar now ends in another clef, that
/// clef replaces the old one on each following bar that carried it on,
/// stopping at a bar that opens in another clef or ends as it did before.
/// Notes keep their pitch; they move on the staff. Refused with
/// [StaleReference] for a bar or staff that is gone and [OutsideMeasure]
/// for a time outside the bar. Idempotent.
final class SetClef extends Edit {
  const SetClef({required this.staff, required this.at, required this.clef});

  final StaffId staff;
  final ScorePoint at;
  final Clef clef;

  @override
  String get label => 'Clef';
}

/// Replaces the tempo marks of one bar, stored in time order. Refused with
/// [OutsideMeasure] for a mark outside the bar and [InvalidValue] for two
/// marks at one time. Idempotent.
final class SetTempoMarks extends Edit {
  const SetTempoMarks(this.measure, this.marks);

  final MeasureId measure;
  final Seq<TempoMark> marks;

  @override
  String get label => 'Tempo';
}

// --- Bars -------------------------------------------------------------------

/// Inserts [count] empty bars before [before] (at the end when null). New
/// bars copy meter, key and closing clefs from the bar before the insertion
/// point (the first bar's opening clefs at the start) and hold one
/// [MeasureRest] per staff. A bar inserted inside a volta joins it. Spanners
/// that cross the insertion point stretch over the new bars. A tie into the
/// bar at the insertion point is cleared, since it would lead into rests.
final class InsertMeasures extends Edit {
  const InsertMeasures({this.before, this.count = 1})
    : assert(count > 0, 'count > 0');

  final MeasureId? before;
  final int count;

  @override
  String get label => 'Insert measures';
}

/// Deletes bars [first] to [last] inclusive, in either order. A tie into
/// the range is cleared when it would land on a different note, or on one
/// where it landed on none. Spanners wholly inside are removed. One that
/// starts inside moves to the start of the bar after, and one that ends
/// inside moves to the last onset before the range. Deleting every bar is
/// refused with [WouldEmptyScore].
final class DeleteMeasures extends Edit {
  const DeleteMeasures(this.first, this.last);

  final MeasureId first;
  final MeasureId last;

  @override
  String get label => 'Delete measures';
}

final class SetBarline extends Edit {
  const SetBarline(this.measure, this.barline);

  final MeasureId measure;
  final Barline barline;

  @override
  String get label => 'Barline';
}

final class SetRepeatStart extends Edit {
  const SetRepeatStart(this.measure, {required this.start});

  final MeasureId measure;
  final bool start;

  @override
  String get label => 'Start repeat';
}

final class SetRepeatEnd extends Edit {
  const SetRepeatEnd(this.measure, this.end);

  final MeasureId measure;
  final RepeatEnd? end;

  @override
  String get label => 'End repeat';
}

/// Puts bars [first]..[last] under [volta], or clears them (null). Refused
/// with [InvalidValue] unless the endings count passes from 1, ascending.
final class SetVolta extends Edit {
  const SetVolta(this.first, this.last, this.volta);

  final MeasureId first;
  final MeasureId last;
  final Volta? volta;

  @override
  String get label => 'Ending';
}

final class SetNavigation extends Edit {
  const SetNavigation(this.measure, this.marks);

  final MeasureId measure;
  final Seq<NavigationMark> marks;

  @override
  String get label => 'Repeat sign';
}

/// Sets the rehearsal mark of [measure]. Null or empty text clears it.
final class SetRehearsal extends Edit {
  const SetRehearsal(this.measure, this.text);

  final MeasureId measure;
  final String? text;

  @override
  String get label => 'Rehearsal mark';
}

/// Makes [measure] a pickup (or irregular) bar of [length], or restores the
/// meter's length (null). Content beyond a shortened length is cut from the
/// end, with the event crossing the new end keeping its head, and so are
/// clef changes, directions and tempo marks there. Spanner ends in the cut
/// move as for [DeleteMeasures]. A lengthened bar is padded with rests in
/// voice one and a gap in the other voices. Ties at the bar's end follow the
/// [DeleteMeasures] rule. Refused with [WouldSplitTuplet] when the new end
/// cuts a tuplet, and with [InvalidValue] for a length that is not a whole
/// number of 128th notes.
final class SetBarLength extends Edit {
  const SetBarLength(this.measure, this.length);

  final MeasureId measure;
  final Length? length;

  @override
  String get label => 'Pickup measure';
}

// --- Clipboard and bulk -----------------------------------------------------

/// Pastes [clip] with its top staff at [at]'s staff and its time origin at
/// [at]'s point. Each lane overwrites like [EnterNote], crossing barlines by
/// split-and-tie and appending bars at the end if needed. Every pasted
/// entity gets a new id. Voices keep their slots. Staves beyond the bottom of
/// the score are dropped. The pasted range becomes the selection.
final class Paste extends Edit {
  const Paste(
    this.clip, {
    required this.at,
    this.overfill = Overfill.splitAndTie,
  });

  final Clip clip;
  final VoicePoint at;
  final Overfill overfill;

  @override
  String get label => 'Paste';
}

/// Transposes every note in [selection] (and chord symbols in a range).
/// Diatonic and chromatic transpositions read the key in effect at each
/// note. A tie chain is transposed as a whole even if only part of it is
/// selected. Key signatures are not changed.
final class Transpose extends Edit {
  const Transpose(this.selection, this.by);

  final Selection selection;
  final Transposition by;

  @override
  String get label => 'Transpose';
}

// --- Parts ------------------------------------------------------------------

/// Adds a part at [index] (bottom when null). Every bar gets a
/// [MeasureRest] on each new staff.
final class AddPart extends Edit {
  const AddPart(this.template, {this.index});

  final PartTemplate template;
  final int? index;

  @override
  String get label => 'Add instrument';
}

/// Removes a part and its staves from every bar, with its spanners.
/// Removing the last part is refused with [WouldEmptyScore].
final class RemovePart extends Edit {
  const RemovePart(this.part);

  final PartId part;

  @override
  String get label => 'Remove instrument';
}

final class SetPartHidden extends Edit {
  const SetPartHidden(this.part, {required this.hidden});

  final PartId part;
  final bool hidden;

  @override
  String get label => hidden ? 'Hide instrument' : 'Show instrument';
}

// --- Grouping ---------------------------------------------------------------

/// Runs [edits] in order as one undo step. Each edit sees the score, cursor
/// and selection the one before it left. All or nothing: if any edit is
/// refused, the batch is refused and the score is unchanged.
///
/// Ids are minted as the batch runs, so an edit cannot name a bar, event or
/// spanner that an earlier edit in the same batch created.
final class Batch extends Edit {
  const Batch(this.edits, {this.label = 'Edit'});

  final List<Edit> edits;

  @override
  final String label;
}

// --- Refusals ---------------------------------------------------------------

/// Why an edit did not apply. Expected outcomes, not errors: the app shows
/// them as a message and the session is unchanged.
sealed class EditRefusal {
  const EditRefusal();
}

/// The target no longer exists in the current score (a stale selection).
final class StaleReference extends EditRefusal {
  const StaleReference(this.target);

  final Object target;
}

/// The edit would cut a tuplet with a barline or cover part of it.
final class WouldSplitTuplet extends EditRefusal {
  const WouldSplitTuplet(this.tuplet, this.measure);

  final TupletId tuplet;
  final MeasureId measure;
}

/// A point that does not lie inside its measure.
final class OutsideMeasure extends EditRefusal {
  const OutsideMeasure(this.at);

  final ScorePoint at;
}

/// A write under [Overfill.refuse] would run past the end of [measure].
/// [excess] is how much sounding time did not fit.
final class WouldCrossBarline extends EditRefusal {
  const WouldCrossBarline(this.measure, this.excess);

  final MeasureId measure;
  final Length excess;
}

/// The edit would leave the score with no bars or no parts.
final class WouldEmptyScore extends EditRefusal {
  const WouldEmptyScore();
}

/// The edit needs a selection and there is none, or it is the wrong kind.
final class NeedsSelection extends EditRefusal {
  const NeedsSelection();
}

/// A value the model cannot hold: a zero-length pickup, a string index the
/// instrument does not have, a pitch outside the alteration range after
/// transposition.
final class InvalidValue extends EditRefusal {
  const InvalidValue(this.message);

  final String message;
}
