/// Edits: the only way a score changes.
///
/// Every edit is plain data naming its targets explicitly (no hidden "current
/// cursor"), so an edit means the same thing whenever it runs. `EditSession`
/// applies them; each applied edit is one undo step.
///
/// Policies that shape the whole model are stated on the edits that carry
/// them:
/// - Note entry overwrites unless it is asked to ripple. See [EnterNote].
/// - A ripple moves the later music of one part or of one staff, inside
///   one section. See [Ripple].
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
import 'session.dart' show ScoreClip, Selection;

/// One change to a score, as plain data. `EditSession.run` applies it as one
/// undo step, or refuses it with an [EditRefusal].
sealed class Edit {
  /// Lets every edit be a const value.
  const Edit();

  /// Short English label for the undo menu. The app localizes by edit type.
  String get label;
}

/// Writes a note of [value] (written) playing [tone] at [at], replacing
/// whatever sounded in that voice from `at` for the note's length.
///
/// Overwrite policy: the span `[at, at + length)` of the voice is cleared
/// and the note put there. A note or rest cut at the start keeps its head
/// (re-spelled with `Meter.spell`); whatever remains after the end becomes
/// rests, or a gap in voices two to four outside a tuplet. Nothing moves in
/// time and no other voice or staff is touched.
///
/// Overfill policy (access pattern 9) is [overfill]. With the default,
/// [Overfill.splitAndTie], a note longer than the room left in the bar is
/// split at the barline and the pieces are tied, and the write continues
/// into the next bar under the same rule. Past the last bar, bars are
/// appended with the last bar's meter, key and clefs. With
/// [Overfill.refuse] the edit returns `Refused(WouldCrossBarline)` instead,
/// which an app can show as "needs a bar line". Either way the bar is never
/// overfull and never grows.
///
/// Inside a tuplet, [value] is read in the tuplet's time (entering an eighth
/// inside a triplet writes a triplet eighth), and the note must end inside
/// that tuplet or the edit returns `Refused(WouldSplitTuplet)`. A write that
/// would cover only part of a tuplet from outside replaces the whole tuplet
/// with rests first.
///
/// The note starts a whole number of 128th notes into its bar, or into the
/// written time of the tuplet that holds it, or the edit is refused with
/// [InvalidValue]. An eighth into a duplet of quarters is a twelfth of a
/// whole note in written time, so no note can start there.
///
/// Afterwards the cursor sits at the end of the note (offset 0 of the next
/// bar if it ended on a barline) and the new event is selected. A note that
/// ends the score has no next bar. With [appendBar], the default, an empty
/// bar is appended for the cursor. Without it the score keeps its bars and
/// the cursor stays at [at]. The bars the overfill policy needs are appended
/// either way.
///
/// With [ripple] set to [Ripple.part] or [Ripple.staff] the note makes room
/// for itself instead of writing over what follows. It first takes the time
/// of the plain rests and gaps that start at [at], up to its own length, and
/// pushes the music after them later by the time it still needs, in every
/// staff of the part or in the note's staff alone (see [Ripple]).
/// Entered onto a rest at least as long as itself, it pushes nothing and
/// the edit is the overwriting one. Entered inside a note, it splits that
/// note: the head stays before the new note and the rest of it moves after.
/// Inside a tuplet it only fills rests: the edit is refused with
/// [WouldSplitTuplet] when the tuplet has music where the note would go.
/// At the start of a tuplet that begins with music, the whole tuplet moves.
/// [Overfill.refuse] still refuses a new note longer than the rest of its
/// bar, but the music it pushes is cut and tied at barlines, and the
/// section grows by whole bars to hold it, whatever [overfill] and
/// [appendBar] say. The tie into [at], the cursor, the selection and
/// [appendBar] for the bar after the score's end work as they do for
/// overwriting entry.
final class EnterNote extends Edit {
  /// Enters [tone] at [at] as a note of [value].
  const EnterNote({
    required this.at,
    required this.tone,
    required this.value,
    this.overfill = Overfill.splitAndTie,
    this.beam = BeamMode.auto,
    this.appendBar = true,
    this.ripple = Ripple.none,
  });

  /// Where the note starts: the staff, the voice and the point in the bar.
  final VoicePoint at;

  /// A pitch on a pitched staff, or a drum of the part's kit on a
  /// percussion staff. Anything else is refused with [InvalidValue].
  final Tone tone;
  /// The written value. Inside a tuplet it is read in the tuplet's time.
  final NoteValue value;
  /// What happens when the note runs past the barline. See [EnterNote].
  final Overfill overfill;

  /// How the chord beams. Every piece of a note split at a barline carries
  /// it. [SetBeam] changes it later.
  final BeamMode beam;

  /// Whether a note that ends the score gets an empty bar after it.
  final bool appendBar;

  /// Whether the music after the note moves to make room for it.
  final Ripple ripple;

  @override
  String get label => 'Enter note';
}

/// [EnterNote] for a rest. In voices two to four, a rest can be turned into
/// a gap with [Erase]. A rest that ripples pushes later music as a note
/// does.
final class EnterRest extends Edit {
  /// Enters a rest of [value] at [at].
  const EnterRest({
    required this.at,
    required this.value,
    this.overfill = Overfill.splitAndTie,
    this.appendBar = true,
    this.ripple = Ripple.none,
  });

  /// Where the rest starts: the staff, the voice and the point in the bar.
  final VoicePoint at;
  /// The written value. Inside a tuplet it is read in the tuplet's time.
  final NoteValue value;
  /// What happens when the rest runs past the barline, as for
  /// [EnterNote.overfill].
  final Overfill overfill;
  /// Whether a rest that ends the score gets an empty bar after it, as for
  /// [EnterNote.appendBar].
  final bool appendBar;
  /// Whether the music after the rest moves to make room for it. See [Ripple].
  final Ripple ripple;

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

/// Whether an edit that adds or removes time moves the music after it.
///
/// Ripple policy, for [Ripple.part] and [Ripple.staff]. An editor that
/// works like a line of text uses one of them: new music makes room for
/// itself, and deleted music closes the gap it leaves.
///
/// - Scope: with [Ripple.part], every voice of every staff of the part that
///   holds the edit moves together, so the part's voices stay aligned.
///   With [Ripple.staff], every voice of the staff that holds the edit
///   moves together, and the part's other staves stay where they are, so
///   one hand of a piano part is edited without the other. Other parts
///   stay where they are under both. The rest of this policy holds for the
///   staves that move.
/// - Sections: music moves only inside the section that holds the edit.
///   That is the run of bars [SetMeter] re-bars together, also ended by a
///   change of meter. The section's trailing rests and gaps give way
///   first, as in [SetMeter]. A push that still overfills the section adds
///   whole bars before its closing barline, and the barline, its repeat
///   sign and its end-of-bar navigation move to the new last bar. Every
///   staff that does not move rests in the new bars. Music never crosses
///   that barline, so a push into the last section adds bars at the end of
///   the score. A pull leaves rests at the end of the section and removes
///   no bars. A pickup or other irregular bar is a section that cannot
///   grow, and a push that overfills it is refused with
///   [WouldCrossBarline].
/// - Moving: the music after the edit point moves by the time added or
///   removed. In the other voices, an event that sounds across the point
///   where time is added becomes longer by that time, an event that
///   overlaps removed time becomes shorter by the overlap, and an event
///   inside removed time goes. A note that ends up across a barline is
///   split there and tied. Adding or removing time inside a tuplet is
///   refused with [WouldSplitTuplet].
/// - Ties: a tie stays while it ends on the head it ended on before, on the
///   next piece of its own note, or on a new note of its tone, and while it
///   ends on no head where it ended on none. Otherwise it is cleared.
/// - Marks: articulations, fingerings and lyrics travel on their notes.
///   The directions and clef changes of the staves that move, the ends of
///   their spanners, a cursor on one of them and a range selection over one
///   keep their place in the music. A direction in removed time is
///   dropped, as [DeleteMeasures] drops it. A clef change there moves to
///   where the time was removed, so the clef that follows is kept. A
///   spanner start there moves to the music after it and an end to the
///   last onset before it.
///   Tempo marks, breaks and signature displays belong to every part, so
///   they stay with their bars.
enum Ripple {
  /// Nothing moves: new music writes over what follows, and music made
  /// shorter or deleted leaves rests.
  none,

  /// The later music of the edited part moves, in all its staves.
  part,

  /// The later music of the edited staff moves, and no other staff.
  staff,
}

/// Adds [tone] to [event] (access pattern 2). A single note becomes a
/// chord; a rest becomes a note of the rest's value. Adding a tone the
/// chord already has is a no-op (idempotent). If the chord is tied into
/// the next event, the new note is tied too when the next event has the
/// same tone. The tone must suit the staff, as for [EnterNote].
final class AddToChord extends Edit {
  /// Adds [tone] to [event].
  const AddToChord({required this.event, required this.tone});

  /// The chord or rest that gets the new head.
  final EventRef event;
  /// What the new head plays.
  final Tone tone;

  @override
  String get label => 'Add note to chord';
}

/// Removes one head from a chord. Removing the last head leaves a rest of
/// the same value.
final class RemoveNote extends Edit {
  /// Removes [note] from its chord.
  const RemoveNote(this.note);

  /// The head to remove.
  final NoteRef note;

  @override
  String get label => 'Delete note';
}

/// Changes what one head plays, its pitch or its drum. If the note is part
/// of a tie chain, the whole chain changes so the tie stays valid. The tone
/// must suit the staff, as for [EnterNote].
final class SetTone extends Edit {
  /// Makes [note] play [tone].
  const SetTone(this.note, this.tone);

  /// The head to change. The tie chain through it changes with it.
  final NoteRef note;
  /// The new pitch or drum.
  final Tone tone;

  @override
  String get label => 'Change note';
}

/// Changes an event's written value from its onset. The event keeps its
/// ids, its marks and the ties into it, and a measure rest becomes a rest.
/// Shorter: the freed time becomes rests, or a gap in voices two to four.
/// Longer: overwrites what follows, split and tied at a barline, with bars
/// appended past the end of the score; inside a tuplet it must still end in
/// the tuplet. A tie out of the event stays only while it ends on the head
/// it ended on before, or on none. The cursor and selection stay.
/// Idempotent.
///
/// With [ripple] set to [Ripple.part] or [Ripple.staff], the music after
/// the event moves by the change instead, in every staff of the part or in
/// the event's staff alone (see [Ripple]). A longer event pushes it later
/// and a shorter one pulls it back, so nothing after the event is written
/// over or turned into rests. An event in a tuplet cannot change its length
/// this way, and the edit is refused with [WouldSplitTuplet]. The cursor
/// and a range selection on the staves that move follow the music.
final class SetValue extends Edit {
  /// Changes [event]'s written value to [value].
  const SetValue(this.event, this.value, {this.ripple = Ripple.none});

  /// The chord, rest or measure rest to change.
  final EventRef event;
  /// The new written value. It must last a whole number of 128th notes, or the
  /// edit is refused with [InvalidValue].
  final NoteValue value;
  /// Whether the music after the event moves by the change. See [Ripple].
  final Ripple ripple;

  @override
  String get label => 'Change duration';
}

/// Creates a tuplet at [at] filled with rests of [unit], overwriting like
/// [EnterNote]. A tuplet never crosses a barline: refused with
/// [WouldSplitTuplet] if it does not fit in the bar. Inside a tuplet it
/// nests, and must fit in that tuplet. Tuplets nest at most 16 deep, and
/// one more is refused with [InvalidValue]. The cursor stays at [at] and
/// the first rest is selected, so the notes entered next fill the tuplet.
final class EnterTuplet extends Edit {
  /// Enters a tuplet of [ratio] at [at], filled with rests of [unit].
  const EnterTuplet({
    required this.at,
    required this.ratio,
    required this.unit,
  });

  /// Where the tuplet starts: the staff, the voice and the point in the bar.
  final VoicePoint at;
  /// How many notes the tuplet holds in the time of how many.
  /// [TupletRatio.triplet] is 3 in the time of 2. A term of 0 or less is
  /// refused with [InvalidValue].
  final TupletRatio ratio;
  /// The written value of each rest, and the value the ratio counts in. The
  /// tuplet holds `ratio.actual` rests of it and lasts `ratio.normal` of it.
  final NoteValue unit;

  @override
  String get label => 'Enter tuplet';
}

/// Adds a grace chord of [tone] before [event], nearest the principal. The
/// tone must suit the staff, as for [EnterNote]; a drum grace is a flam.
final class AddGrace extends Edit {
  /// Adds a grace chord of [tone] before [event].
  const AddGrace({
    required this.event,
    required this.tone,
    this.kind = GraceKind.acciaccatura,
    this.value = NoteValue.eighth,
  });

  /// The principal chord the grace leads into. A rest is refused with
  /// [InvalidValue].
  final EventRef event;
  /// What the grace plays.
  final Tone tone;
  /// An acciaccatura, the default, or an appoggiatura. Playback times the two
  /// differently. See [GraceChord].
  final GraceKind kind;
  /// The grace's written value, an eighth by default. It must last a whole
  /// number of 128th notes, or the edit is refused with [InvalidValue].
  final NoteValue value;

  @override
  String get label => 'Add grace note';
}

/// Sets or clears the tie from [note] to the same tone in the next event.
/// Idempotent.
final class SetTie extends Edit {
  /// Sets the tie from [note] when [tied] is true and clears it when false.
  const SetTie(this.note, {required this.tied});

  /// The head the tie starts on.
  final NoteRef note;
  /// Whether the tie is there after the edit.
  final bool tied;

  @override
  String get label => tied ? 'Add tie' : 'Remove tie';
}

/// Clears what is selected. An event in voice one or in a tuplet becomes a
/// rest of its value that keeps its id and a fermata, and a bar left with
/// only plain rests becomes one [MeasureRest]. In voices two to four an
/// event becomes a gap, a tuplet left with only rests becomes a gap, and a
/// voice left with only gaps disappears. Picked heads of a chord that keeps
/// another head are removed. A picked spanner is removed, and the notes
/// under it stay. A selection of notes and spanners does both, and leaves
/// any spanner it does not pick, even over the notes it clears. A range
/// takes the events that start in it and the tuplets wholly inside it, its
/// directions, and the spanners that start and end in it. A tie into what
/// is cleared is cleared too. Bars are never removed; see [DeleteMeasures].
/// Refused with [StaleReference] for a picked spanner that is gone.
///
/// With [ripple] set to [Ripple.part] or [Ripple.staff], what is deleted
/// gives back its time (see [Ripple]). A picked event goes, a measure rest
/// included, and the later music of its part, or of its staff alone, moves
/// back to close the gap. Picked heads of a chord that keeps another head
/// are removed as they are without a ripple. With [Ripple.part] a range
/// takes its time out of every part that has a staff in it, all of that
/// part's staves, section by section. With [Ripple.staff] it takes its
/// time out of the staves in it and no others. An event in a tuplet, or a
/// range end inside one, is refused with [WouldSplitTuplet].
final class Erase extends Edit {
  /// Clears [selection].
  const Erase(this.selection, {this.ripple = Ripple.none});

  /// What to clear: picked events, heads and spanners, or a range.
  final Selection selection;
  /// Whether the time of what is deleted is taken out. See [Ripple].
  final Ripple ripple;

  @override
  String get label => 'Delete';
}

/// Adds or removes one articulation. Idempotent, so "toggle" is decided by
/// the caller from what it sees.
final class SetArticulation extends Edit {
  /// Adds [articulation] to [event] when [present] is true and removes it when
  /// false.
  const SetArticulation(this.event, this.articulation, {required this.present});

  /// The chord or rest that carries the mark. A rest holds only a fermata, and
  /// adding another mark to one is refused with [InvalidValue].
  final EventRef event;
  /// The mark to add or remove.
  final Articulation articulation;
  /// Whether the mark is there after the edit.
  final bool present;

  @override
  String get label => 'Articulation';
}

/// Sets or clears the ornament sign on a chord. Idempotent. A new sign, or
/// none, takes off the accidentals of the old one.
final class SetOrnament extends Edit {
  /// Sets [event]'s ornament to [ornament].
  const SetOrnament(this.event, this.ornament);

  /// The chord that carries the sign. Setting a sign on a rest is refused with
  /// [InvalidValue], and clearing one there changes nothing.
  final EventRef event;
  /// The sign to set, or null to clear it.
  final Ornament? ornament;

  @override
  String get label => 'Ornament';
}

/// Sets or clears the bow direction on a chord. Idempotent.
final class SetBowing extends Edit {
  /// Sets [event]'s bow direction to [bowing].
  const SetBowing(this.event, this.bowing);

  /// The chord that carries the bowing. Setting a bowing on a rest is refused
  /// with [InvalidValue], and clearing one there changes nothing.
  final EventRef event;
  /// The bow direction to set, or null to clear it.
  final Bowing? bowing;

  @override
  String get label => 'Bowing';
}

/// Sets how a chord beams. [BeamMode.auto] hands it back to the meter.
/// Idempotent.
final class SetBeam extends Edit {
  /// Sets how [event] beams.
  const SetBeam(this.event, this.mode);

  /// The chord to change. Setting a mode other than [BeamMode.auto] on a rest
  /// is refused with [InvalidValue].
  final EventRef event;
  /// The beam mode to set.
  final BeamMode mode;

  @override
  String get label => 'Beam';
}

/// Sets or clears the finger number of one head. Idempotent.
/// Refused with [InvalidValue] on a drum note, as are [SetString] and
/// [SetAccidental].
final class SetFingering extends Edit {
  /// Sets [note]'s finger number to [finger].
  const SetFingering(this.note, this.finger);

  /// The head to mark.
  final NoteRef note;
  /// The finger number, 0 for an open string, or null to clear it. A negative
  /// number is refused with [InvalidValue].
  final int? finger;

  @override
  String get label => 'Fingering';
}

/// Which string plays [note]: an index into the instrument's `strings`.
final class SetString extends Edit {
  /// Sets the string that plays [note] to [string].
  const SetString(this.note, this.string);

  /// The head to mark.
  final NoteRef note;
  /// The index into the instrument's `strings`, lowest-tuned string first, or
  /// null to clear it. An index the instrument does not have is refused with
  /// [InvalidValue].
  final int? string;

  @override
  String get label => 'String';
}

/// Sets when one head prints its accidental. Idempotent.
final class SetAccidental extends Edit {
  /// Sets [note]'s accidental request to [request].
  const SetAccidental(this.note, this.request);

  /// The head to change.
  final NoteRef note;
  /// When the accidental prints. [AccidentalRequest.auto] leaves it to the key,
  /// bar and tie rules.
  final AccidentalRequest request;

  @override
  String get label => 'Accidental';
}

/// Sets or clears (null) verse [verse] of [event]'s lyrics.
final class SetLyric extends Edit {
  /// Sets verse [verse] of [event]'s lyrics to [lyric].
  const SetLyric(this.event, this.verse, this.lyric);

  /// The chord that carries the lyric. Setting a lyric on a rest is refused
  /// with [InvalidValue], and clearing one there changes nothing.
  final EventRef event;
  /// The verse number, counted from 1. It must match [Lyric.verse] of [lyric],
  /// or the edit is refused with [InvalidValue].
  final int verse;
  /// The syllable to set, or null to clear the verse.
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
  /// Replaces [staff]'s directions in [measure] with [directions].
  const SetDirections({
    required this.staff,
    required this.measure,
    required this.directions,
  });

  /// The staff that holds the directions.
  final StaffId staff;
  /// The bar that holds the directions.
  final MeasureId measure;
  /// The staff's complete directions for the bar, each at its offset in the
  /// bar. An empty list removes them all.
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
  /// Adds a spanner of [kind] from [first] to [last] on [staff].
  const AddSpanner({
    required this.kind,
    required this.staff,
    required this.first,
    required this.last,
    this.voice,
  });

  /// What the spanner draws: a slur, hairpin, octave line, trill line, tempo
  /// line, pedal line or glissando.
  final SpannerKind kind;
  /// The staff the spanner is drawn on.
  final StaffId staff;
  /// The voice a slur or glissando joins, voice one when null. Ignored for the
  /// other kinds.
  final VoiceSlot? voice;
  /// Where the spanner starts.
  final ScorePoint first;
  /// Where the spanner ends.
  final ScorePoint last;

  @override
  String get label => 'Add line';
}

/// Removes one spanner. Refused with [StaleReference] when it is gone.
final class RemoveSpanner extends Edit {
  /// Removes [spanner].
  const RemoveSpanner(this.spanner);

  /// The id of the spanner to remove.
  final SpannerId spanner;

  @override
  String get label => 'Remove line';
}

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
  /// Sets [meter] from bar [from] onward.
  const SetMeter({
    required this.from,
    required this.meter,
    this.content = MeterContent.rebar,
  });

  /// The first bar that takes the new meter.
  final MeasureId from;
  /// The new meter.
  final Meter meter;
  /// Whether the music is re-barred or each bar keeps its content. See
  /// [SetMeter].
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
  /// Sets [key] from bar [from] onward.
  const SetKey({required this.from, required this.key});

  /// The first bar that takes the new key.
  final MeasureId from;
  /// The new key signature.
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
  /// Puts [clef] on [staff] at [at].
  const SetClef({required this.staff, required this.at, required this.clef});

  /// The staff that gets the clef.
  final StaffId staff;
  /// The bar and offset where the clef takes effect. Offset 0 sets the bar's
  /// starting clef.
  final ScorePoint at;
  /// The new clef.
  final Clef clef;

  @override
  String get label => 'Clef';
}

/// Replaces the tempo marks of one bar, stored in time order. Refused with
/// [OutsideMeasure] for a mark outside the bar and [InvalidValue] for two
/// marks at one time. Idempotent.
final class SetTempoMarks extends Edit {
  /// Replaces [measure]'s tempo marks with [marks].
  const SetTempoMarks(this.measure, this.marks);

  /// The bar that holds the marks.
  final MeasureId measure;
  /// The bar's complete tempo marks, each at its offset in the bar. An empty
  /// list removes them all.
  final Seq<TempoMark> marks;

  @override
  String get label => 'Tempo';
}

/// Inserts [count] empty bars before [before] (at the end when null). New
/// bars copy meter, key and closing clefs from the bar before the insertion
/// point (the first bar's opening clefs at the start) and hold one
/// [MeasureRest] per staff. A bar inserted inside a volta joins it. Spanners
/// that cross the insertion point stretch over the new bars. A tie into the
/// bar at the insertion point is cleared, since it would lead into rests.
/// At the start, the first bar's opening tempo marks move to the first new
/// bar, so every old bar starts under the tempo mark it started under.
/// Refused with
/// [InvalidValue] for a [count] under 1.
final class InsertMeasures extends Edit {
  /// Inserts [count] bars before [before].
  const InsertMeasures({this.before, this.count = 1});

  /// The bar the new bars go before, or null to append them at the end of the
  /// score.
  final MeasureId? before;
  /// How many bars to insert, 1 by default.
  final int count;

  @override
  String get label => 'Insert measures';
}

/// Deletes bars [first] to [last] inclusive, in either order. A tie into
/// the range is cleared when it would land on a different note, or on one
/// where it landed on none. Spanners wholly inside are removed. One that
/// starts inside moves to the start of the bar after, and one that ends
/// inside moves to the last onset before the range. The bars left play at
/// the tempo they played at, tempo lines counted. Without an opening tempo
/// mark of its own, the bar after the range gains one for the tempo it
/// started at, a copy of the last mark the range held when that one gives
/// it. A tempo line cut by the range reaches the tempo it had reached where
/// it is cut, and one still moving the tempo past the range goes on from
/// the bar after, split in two when it started before the range. The one
/// change is a line that now ends just as the bar after starts at another
/// tempo: it reaches that tempo, as a line does that ends on a tempo mark.
/// Deleting every bar is refused with [WouldEmptyScore].
final class DeleteMeasures extends Edit {
  /// Deletes the bars from [first] to [last].
  const DeleteMeasures(this.first, this.last);

  /// One end of the range, inclusive.
  final MeasureId first;
  /// The other end of the range, inclusive.
  final MeasureId last;

  @override
  String get label => 'Delete measures';
}

/// Sets the barline at the end of [measure]. Idempotent.
final class SetBarline extends Edit {
  /// Sets [measure]'s closing barline to [barline].
  const SetBarline(this.measure, this.barline);

  /// The bar whose closing barline changes.
  final MeasureId measure;
  /// The new barline.
  final Barline barline;

  @override
  String get label => 'Barline';
}

/// Sets or clears the start-repeat sign at the start of [measure]. Idempotent.
final class SetRepeatStart extends Edit {
  /// Shows the start-repeat sign on [measure] when [start] is true and removes
  /// it when false.
  const SetRepeatStart(this.measure, {required this.start});

  /// The bar the repeated section starts at.
  final MeasureId measure;
  /// Whether the bar starts a repeat after the edit.
  final bool start;

  @override
  String get label => 'Start repeat';
}

/// Sets or clears the end-repeat sign at the end of [measure]. Refused with
/// [InvalidValue] for a repeat of fewer than two passes. Idempotent.
final class SetRepeatEnd extends Edit {
  /// Sets [measure]'s end repeat to [end].
  const SetRepeatEnd(this.measure, this.end);

  /// The bar the repeated section ends at.
  final MeasureId measure;
  /// The repeat and its pass count, or null to clear it.
  final RepeatEnd? end;

  @override
  String get label => 'End repeat';
}

/// Puts bars [first]..[last] under [volta], or clears them (null). Refused
/// with [InvalidValue] unless the endings count passes from 1, ascending.
final class SetVolta extends Edit {
  /// Puts bars [first] to [last] under [volta].
  const SetVolta(this.first, this.last, this.volta);

  /// One end of the range, inclusive. The ends may come in either order.
  final MeasureId first;
  /// The other end of the range, inclusive.
  final MeasureId last;
  /// The ending bracket, or null to clear it from the bars.
  final Volta? volta;

  @override
  String get label => 'Ending';
}

/// Replaces the navigation marks of [measure], such as segno, coda, fine and
/// jumps. Idempotent.
final class SetNavigation extends Edit {
  /// Replaces [measure]'s navigation marks with [marks].
  const SetNavigation(this.measure, this.marks);

  /// The bar that holds the marks.
  final MeasureId measure;
  /// The bar's complete navigation marks. An empty list removes them all.
  final Seq<NavigationMark> marks;

  @override
  String get label => 'Repeat sign';
}

/// Sets the rehearsal mark of [measure]. Null or empty text clears it.
final class SetRehearsal extends Edit {
  /// Sets [measure]'s rehearsal mark to [text].
  const SetRehearsal(this.measure, this.text);

  /// The bar the mark sits on.
  final MeasureId measure;
  /// The text of the mark, such as "A". Null or empty clears it.
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
  /// Sets [measure]'s length to [length].
  const SetBarLength(this.measure, this.length);

  /// The bar to resize.
  final MeasureId measure;
  /// The bar's new length, or null to restore the meter's length. It must be
  /// above zero and at most 64 whole notes.
  final Length? length;

  @override
  String get label => 'Pickup measure';
}

/// Makes [measure] start a new system or page, or lets layout choose
/// (null). Idempotent.
final class SetBreak extends Edit {
  /// Sets the break before [measure] to [layoutBreak].
  const SetBreak(this.measure, this.layoutBreak);

  /// The bar that starts the new system or page.
  final MeasureId measure;
  /// The break layout must make before the bar, or null to let layout choose.
  final LayoutBreak? layoutBreak;

  @override
  String get label =>
      layoutBreak == LayoutBreak.page ? 'Page break' : 'System break';
}

/// Sets how [measure] prints its key signature. The display stays with the
/// bar when keys change around it, so a courtesy turned off applies again
/// whenever the key changes there. Idempotent.
final class SetKeyDisplay extends Edit {
  /// Sets how [measure] prints its key signature.
  const SetKeyDisplay(this.measure, this.display);

  /// The bar whose key signature display changes.
  final MeasureId measure;
  /// How the key signature prints at the bar.
  final SignatureDisplay display;

  @override
  String get label => 'Key signature display';
}

/// Sets how [measure] prints its time signature, as [SetKeyDisplay] does
/// for the key. Idempotent.
final class SetMeterDisplay extends Edit {
  /// Sets how [measure] prints its time signature.
  const SetMeterDisplay(this.measure, this.display);

  /// The bar whose time signature display changes.
  final MeasureId measure;
  /// How the time signature prints at the bar.
  final SignatureDisplay display;

  @override
  String get label => 'Time signature display';
}

/// Replaces the music from [at] for the clip's length with [clip], on the
/// staves from [at]'s staff down. What was there goes as [Erase] clears a
/// range: every voice, the directions and the spanners inside. Each voice
/// of the clip is then written like [EnterNote]. A note crosses a barline
/// by split-and-tie, or is refused with [WouldCrossBarline] under
/// [Overfill.refuse], and a tuplet that would cross one is refused with
/// [WouldSplitTuplet]. Bars are appended first when the score is too short.
///
/// Every pasted entity gets a new id. Voices keep their slots, and staves
/// beyond the bottom of the score are dropped. A head keeps its string only
/// when the instrument it lands on has that string. A tie into the pasted music,
/// or out of it onto a head, is cleared. So is the tie of a note the paste
/// cuts short, when it ended on a head. The pasted range becomes the
/// selection and the cursor stays. Refused with [StaleReference] for a gone
/// bar or staff, [OutsideMeasure] for a point outside its bar, and
/// [InvalidValue] for a note that does not suit the staff it lands on, as
/// for [EnterNote], or for a tuplet that would nest more than 16 deep.
final class Paste extends Edit {
  /// Pastes [clip] at [at].
  const Paste(
    this.clip, {
    required this.at,
    this.overfill = Overfill.splitAndTie,
  });

  /// The music to paste, as `EditSession.copy` made it.
  final ScoreClip clip;
  /// Where the clip's start and its top staff land. Each voice of the clip
  /// keeps its own slot.
  final VoicePoint at;
  /// What happens when a pasted note runs past a barline. See [Paste].
  final Overfill overfill;

  @override
  String get label => 'Paste';
}

/// Transposes the picked heads, or every head that starts in a range. A
/// tie chain moves whole, even when only part of it is picked, as its first
/// head moves in that head's key. A picked event also moves its graces, and
/// a range moves its graces and chord symbols. Diatonic and chromatic
/// transpositions read the key in effect at each note. Drum notes, which
/// have no pitch, picked spanners and key signatures are left alone. A tie
/// left leading onto a head it did not reach before is cleared. The cursor
/// and selection stay. Refused with [InvalidValue] when a note would need
/// more than a double sharp or flat or a chord would hold one pitch twice,
/// with [StaleReference] for a gone event, head, bar or staff, and with
/// [OutsideMeasure] for a range end outside its bar.
final class Transpose extends Edit {
  /// Transposes [selection] by [by].
  const Transpose(this.selection, this.by);

  /// The picked heads, or a range whose heads all move.
  final Selection selection;
  /// How far the pitches move, and by which kind of step.
  final Transposition by;

  @override
  String get label => 'Transpose';
}

/// Adds a part made from [template] at part [index], or at the bottom when
/// null, with a [MeasureRest] on each new staff in every bar. The cursor
/// and selection stay. Refused with [InvalidValue] for an index outside 0
/// to the part count, a template with no staff or a clef list of another
/// length, or a kit that names a sound twice.
final class AddPart extends Edit {
  /// Adds a part made from [template] at [index].
  const AddPart(this.template, {this.index});

  /// The instrument, name and staves of the new part.
  final PartTemplate template;
  /// The new part's position among the parts, from 0 at the top, or null for
  /// the bottom.
  final int? index;

  @override
  String get label => 'Add instrument';
}

/// Removes a part and its staves from every bar, with its spanners. A
/// cursor on it moves to the same point on the nearest shown staff below
/// it, or else above it. Refused with [WouldEmptyScore] when no other part
/// is shown, and with [StaleReference] for a gone part.
final class RemovePart extends Edit {
  /// Removes [part].
  const RemovePart(this.part);

  /// The part to remove.
  final PartId part;

  @override
  String get label => 'Remove instrument';
}

/// Hides or shows a part. A hidden part stays in the score and plays, but
/// layout and staff moves skip it. Hiding moves a cursor on the part as
/// [RemovePart] does. Refused with [WouldEmptyScore] when hiding the last
/// shown part, and with [StaleReference] for a gone part.
final class SetPartHidden extends Edit {
  /// Hides [part] when [hidden] is true and shows it when false.
  const SetPartHidden(this.part, {required this.hidden});

  /// The part to hide or show.
  final PartId part;
  /// Whether the part is hidden after the edit.
  final bool hidden;

  @override
  String get label => hidden ? 'Hide instrument' : 'Show instrument';
}

/// Gives a part the instrument, name and staff count of [template]. The
/// music keeps its sounding pitches, so only the written view follows the
/// new transposition. Each staff takes the template's clef in every bar,
/// and its clef changes go. Music stays on the staves the part keeps, from
/// the top. A new staff gets a [MeasureRest] in every bar, as for
/// [AddPart]. A dropped staff goes with its music and spanners, as for
/// [RemovePart], and a cursor on it moves to the same point on the part's
/// last staff. A string mark moves to the new instrument's string tuned
/// the same, and is cleared where there is none. A selection loses what
/// lay on a dropped staff, and a range that reaches one is cleared. Giving
/// a part the template it already has changes nothing.
/// Refused with [InvalidValue] for a change between a pitched instrument
/// and a drum kit, a kit that lacks a drum the part plays, or a template
/// [AddPart] refuses, and with [StaleReference] for a gone part.
final class SetInstrument extends Edit {
  /// Gives [part] the instrument of [template].
  const SetInstrument(this.part, this.template);

  /// The part to change.
  final PartId part;
  /// The instrument, name and staff count the part takes.
  final PartTemplate template;

  @override
  String get label => 'Change instrument';
}

/// Runs [edits] in order as one undo step. Each edit sees the score, cursor
/// and selection the one before it left. All or nothing: if any edit is
/// refused, the batch is refused and the score is unchanged.
///
/// Ids are minted as the batch runs, so an edit cannot name a bar, event or
/// spanner that an earlier edit in the same batch created.
final class Batch extends Edit {
  /// Groups [edits] into one undo step named [label].
  const Batch(this.edits, {this.label = 'Edit'});

  /// The edits to run, in order.
  final List<Edit> edits;

  @override
  final String label;
}

/// Why an edit did not apply. Expected outcomes, not errors: the app shows
/// them as a message and the session is unchanged.
sealed class EditRefusal {
  /// Lets every refusal be a const value.
  const EditRefusal();
}

/// The target no longer exists in the current score (a stale selection).
final class StaleReference extends EditRefusal {
  /// Names the [target] that is gone.
  const StaleReference(this.target);

  /// The ref, id or point that no longer resolves.
  final Object target;
}

/// The edit would cut a tuplet with a barline or cover part of it.
final class WouldSplitTuplet extends EditRefusal {
  /// Names the [tuplet] the edit would cut and its [measure].
  const WouldSplitTuplet(this.tuplet, this.measure);

  /// The tuplet the edit would cut.
  final TupletId tuplet;
  /// The bar that holds the tuplet.
  final MeasureId measure;
}

/// A point that does not lie inside its measure.
final class OutsideMeasure extends EditRefusal {
  /// Names the point [at] that lies outside its bar.
  const OutsideMeasure(this.at);

  /// The point that lies outside its bar.
  final ScorePoint at;
}

/// Music would run past the end of [measure]: a write under
/// [Overfill.refuse], or a bar too full for the new meter under
/// [MeterContent.keepBars]. [excess] is how much sounding time did not fit.
final class WouldCrossBarline extends EditRefusal {
  /// Names the [measure] the music would run past and the [excess].
  const WouldCrossBarline(this.measure, this.excess);

  /// The bar the music would run past.
  final MeasureId measure;
  /// How much sounding time did not fit.
  final Length excess;
}

/// The edit would leave the score with no bars or no shown parts.
final class WouldEmptyScore extends EditRefusal {
  /// Makes the refusal, which carries no detail.
  const WouldEmptyScore();
}

/// A value the model cannot hold: a zero-length pickup, a string index the
/// instrument does not have, a pitch outside the alteration range after
/// transposition.
final class InvalidValue extends EditRefusal {
  /// Carries the [message] that names the broken rule.
  const InvalidValue(this.message);

  /// The rule the value broke, in short English for developers, such as 'a bar
  /// count is 1 or more'.
  final String message;
}
