/// What a voice holds: events, tuplets and gaps.
///
/// The hierarchy encodes three rules in types:
/// - A voice holds [VoiceItem]s. A tuplet holds only [Content], so a gap can
///   never sit inside a tuplet.
/// - A single note is a [ChordEvent] with one [Note]. There is no separate
///   single-note type, so stem, flag and accidental logic exists once.
/// - Grace notes hang off the chord they ornament ([ChordEvent.graces]); they
///   take no time in the voice and cannot float free.
library;

import 'pitch.dart';
import 'refs.dart';
import 'seq.dart';
import 'time.dart';

/// Anything that occupies time in a voice.
sealed class VoiceItem {
  const VoiceItem();

  /// Time this item occupies in its parent, in whole notes, before any
  /// enclosing tuplet scaling. For an event this is its written length.
  Length get span;
}

/// Explicit absence of content in voices two to four ("nothing here in
/// this voice"). MusicXML calls this `<forward>`. Voice one never holds a gap;
/// it holds rests. Not selectable, not played, not drawn.
final class Gap extends VoiceItem {
  /// A gap of [span]. Asserts that [span] is positive.
  Gap(this.span) : assert(span.isPositive, 'gap is positive');

  @override
  final Length span;
}

/// Notated content: events and tuplets.
sealed class Content extends VoiceItem {
  const Content();
}

/// A selectable, playable item with identity.
sealed class Event extends Content {
  const Event({required this.id, this.articulations = const {}});

  /// Identity of this event, unique within the score.
  final EventId id;

  /// Stackable marks; order does not matter. Includes fermata, which is
  /// valid on rests. Unmodifiable. Marks that exclude each other (bowing,
  /// ornaments) are single fields on [ChordEvent] instead.
  final Set<Articulation> articulations;
}

/// One or more simultaneous note heads sharing a stem and a duration.
final class ChordEvent extends Event {
  /// Asserts that [notes] is not empty, that the chord and its graces are
  /// all pitched or all drums, that [ornamentAbove] and [ornamentBelow] are
  /// null without an [ornament], and that [tremolo] is in 0 to 4.
  ChordEvent({
    required super.id,
    required this.value,
    required this.notes,
    super.articulations,
    this.ornament,
    this.ornamentAbove,
    this.ornamentBelow,
    this.bowing,
    this.graces = const Seq.empty(),
    this.stem = StemDirection.auto,
    this.beam = BeamMode.auto,
    this.tremolo = 0,
    this.lyrics = const Seq.empty(),
  }) : assert(notes.isNotEmpty, 'a chord has at least one note'),
       assert(
         _oneKind([...notes, for (final grace in graces) ...grace.notes]),
         'a chord and its graces are all pitched or all drums',
       ),
       assert(
         ornament != null || (ornamentAbove == null && ornamentBelow == null),
         'an ornament accidental needs an ornament',
       ),
       assert(tremolo >= 0 && tremolo <= 4, 'tremolo strokes in 0..4');

  /// Written value. An enclosing [Tuplet] scales the time it sounds.
  final NoteValue value;

  /// At most one ornament sign per chord. A trill that continues over
  /// several notes is a `TrillLine` spanner, not this field.
  final Ornament? ornament;

  /// The alteration of the [ornament]'s upper note, from an accidental
  /// printed above the sign. Null where none is printed, and the note is the
  /// one the key gives. A trill and an inverted mordent use only this one.
  final Alter? ornamentAbove;

  /// The alteration of the [ornament]'s lower note, from an accidental
  /// printed below the sign. Null where none is printed. A mordent uses only
  /// this one.
  final Alter? ornamentBelow;

  /// The note [steps] scale steps from [pitch] in [key], one of the notes
  /// the [ornament] plays: above for a positive [steps], with
  /// [ornamentAbove] in place of the key's alteration, and below for a
  /// negative one, with [ornamentBelow].
  Pitch ornamentNote(Pitch pitch, int steps, KeySignature key) {
    final diatonic = pitch.diatonic + steps;
    final step = Step.values[diatonic % 7];
    final alter = switch (steps) {
      > 0 => ornamentAbove,
      < 0 => ornamentBelow,
      _ => null,
    };
    return Pitch(
      step,
      (diatonic - step.index) ~/ 7,
      alter ?? key.alterFor(step),
    );
  }

  /// Bow direction for this stroke. One field, so up-bow and down-bow
  /// cannot both be set.
  final Bowing? bowing;

  /// All pitched or all drums, sorted by [Tone.compareTo]: lowest to highest
  /// sounding pitch, or drums by name. No two notes share a tone, but a
  /// unison of different spellings (E♯/F) is allowed.
  final Seq<Note> notes;

  /// Grace chords played before this chord, in order.
  final Seq<GraceChord> graces;

  /// Stem direction. [StemDirection.auto] lets layout choose.
  final StemDirection stem;

  /// This event's override of the meter's default beaming.
  final BeamMode beam;

  /// Single-note tremolo strokes through the stem. 0 for none.
  final int tremolo;

  /// One entry per verse.
  final Seq<Lyric> lyrics;

  @override
  Length get span => value.length;

  /// The head in [notes] with [id], or null when there is none. Grace
  /// notes are not searched.
  Note? note(NoteId id) {
    for (final note in notes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  /// A copy with the given fields replaced. A nullable field takes a
  /// function so that it can be set to null.
  ChordEvent copyWith({
    EventId? id,
    NoteValue? value,
    Seq<Note>? notes,
    Set<Articulation>? articulations,
    Ornament? Function()? ornament,
    Alter? Function()? ornamentAbove,
    Alter? Function()? ornamentBelow,
    Bowing? Function()? bowing,
    Seq<GraceChord>? graces,
    StemDirection? stem,
    BeamMode? beam,
    int? tremolo,
    Seq<Lyric>? lyrics,
  }) => ChordEvent(
    id: id ?? this.id,
    value: value ?? this.value,
    notes: notes ?? this.notes,
    articulations: articulations ?? this.articulations,
    ornament: ornament == null ? this.ornament : ornament(),
    ornamentAbove: ornamentAbove == null ? this.ornamentAbove : ornamentAbove(),
    ornamentBelow: ornamentBelow == null ? this.ornamentBelow : ornamentBelow(),
    bowing: bowing == null ? this.bowing : bowing(),
    graces: graces ?? this.graces,
    stem: stem ?? this.stem,
    beam: beam ?? this.beam,
    tremolo: tremolo ?? this.tremolo,
    lyrics: lyrics ?? this.lyrics,
  );
}

bool _oneKind(List<Note> notes) =>
    notes.every((note) => note is PitchedNote) ||
    notes.every((note) => note is DrumNote);

/// A rest of a written value.
final class RestEvent extends Event {
  /// A rest of [value].
  const RestEvent({
    required super.id,
    required this.value,
    super.articulations,
    this.hidden = false,
  });

  /// Written value. An enclosing [Tuplet] scales the time it lasts.
  final NoteValue value;

  /// Present in the timeline but not printed.
  final bool hidden;

  @override
  Length get span => value.length;
}

/// A whole-bar rest. Its [span] equals the column's length whatever the
/// meter (5/4 has no single note value, so this cannot be a [RestEvent]).
/// A voice that holds a [MeasureRest] holds nothing else. A blank measure is
/// one [MeasureRest] per staff in voice one.
final class MeasureRest extends Event {
  /// A rest that spans [span], which the enclosing column checks against
  /// its length.
  const MeasureRest({
    required super.id,
    required this.span,
    super.articulations,
  });

  @override
  final Length span;
}

/// A tuplet: [members] are written as if they filled `ratio.actual` units
/// but sound in the time of `ratio.normal` units.
///
/// Invariant (checked in the constructor): the members' spans sum to exactly
/// `unit.length × ratio.actual`. A tuplet is created full of rests, so it is
/// never partially filled. Tuplets nest.
final class Tuplet extends Content {
  /// Throws [ArgumentError] unless [members] span exactly
  /// `unit.length × ratio.actual`.
  Tuplet({
    required this.id,
    required this.ratio,
    required this.unit,
    required this.members,
    this.bracket = TupletBracket.auto,
  }) {
    final written = Length.sum(members.map((m) => m.span));
    if (written != unit.length * Fraction(ratio.actual)) {
      throw ArgumentError(
        'tuplet members span $written, '
        'expected ${unit.length * Fraction(ratio.actual)}',
      );
    }
  }

  /// Identity of this tuplet, unique within the score.
  final TupletId id;

  /// Actual notes in the time of normal ones, as 3:2 for a triplet.
  final TupletRatio ratio;

  /// The value the ratio counts in: a triplet of eighths has unit eighth.
  final NoteValue unit;

  /// Events and nested tuplets in time order, at their written spans.
  final Seq<Content> members;

  /// Whether layout draws a bracket. See [TupletBracket].
  final TupletBracket bracket;

  @override
  Length get span => unit.length * Fraction(ratio.normal);
}

/// Whether a tuplet's bracket is drawn. Its number prints either way.
enum TupletBracket {
  /// Drawn unless the tuplet's events are exactly one beam group.
  auto,

  /// Always drawn.
  shown,

  /// Never drawn.
  hidden,
}

/// One note head.
sealed class Note {
  const Note({required this.id, this.tie = false});

  /// Identity of this head, unique within the score.
  final NoteId id;

  /// Tied to the head of the same [tone] in the next event of the same
  /// staff and voice, which may be in the next measure. The tie's end is
  /// derived, never stored, so it cannot dangle. If no matching head
  /// follows, the tie is drawn as a short let-ring tie and playback ends the
  /// note normally.
  final bool tie;

  /// What it plays. A chord never holds one tone twice.
  Tone get tone;

  /// A copy with [id] or [tie] replaced.
  Note copyWith({NoteId? id, bool? tie});
}

/// A head on a pitched staff.
final class PitchedNote extends Note {
  /// A head that sounds [pitch].
  const PitchedNote({
    required super.id,
    required this.pitch,
    super.tie,
    this.accidental = AccidentalRequest.auto,
    this.head = NoteHead.normal,
    this.fingering,
    this.string,
  });

  /// Concert (sounding) pitch. What is printed is derived per staff.
  final Pitch pitch;

  /// Whether an accidental prints on this head. See [AccidentalRequest].
  final AccidentalRequest accidental;

  /// Shape of the head.
  final NoteHead head;

  /// Finger number, 0 for an open string. The upper bound depends on the
  /// instrument, so any non-negative int is allowed.
  final int? fingering;

  /// Index into `Instrument.strings`, lowest-tuned string first. On a violin
  /// 0 is the G string and 3 the E string.
  final int? string;

  @override
  Pitch get tone => pitch;

  @override
  PitchedNote copyWith({
    NoteId? id,
    bool? tie,
    Pitch? pitch,
    AccidentalRequest? accidental,
    NoteHead? head,
    int? Function()? fingering,
    int? Function()? string,
  }) => PitchedNote(
    id: id ?? this.id,
    pitch: pitch ?? this.pitch,
    tie: tie ?? this.tie,
    accidental: accidental ?? this.accidental,
    head: head ?? this.head,
    fingering: fingering == null ? this.fingering : fingering(),
    string: string == null ? this.string : string(),
  );
}

/// A head on a percussion staff. It is drawn where its part's kit places
/// [drum], with the kit's head.
final class DrumNote extends Note {
  /// A head that plays [drum].
  const DrumNote({required super.id, required this.drum, super.tie});

  /// The drum it plays.
  final Drum drum;

  @override
  Drum get tone => drum;

  @override
  DrumNote copyWith({NoteId? id, bool? tie, Drum? drum}) => DrumNote(
    id: id ?? this.id,
    drum: drum ?? this.drum,
    tie: tie ?? this.tie,
  );
}

/// Grace notes attached before a principal chord. Zero duration in the
/// voice. Playback plays them on the beat, in time taken from the start of
/// the principal, as MuseScore 4 does: a lone appoggiatura takes its
/// written value, up to half the principal, or two thirds of one longer
/// than an eighth in a compound meter. Any other graces take a 64th each,
/// up to half the principal together, and each its written share. Graces
/// right after a trilled chord in their voice, other than a lone
/// appoggiatura, end its trill instead: they play at the end of that chord,
/// a 64th each and at most half of it, and the principal plays on its beat.
final class GraceChord {
  /// Asserts that [notes] is not empty.
  GraceChord({
    required this.id,
    required this.kind,
    required this.value,
    required this.notes,
  }) : assert(notes.isNotEmpty, 'a grace chord has at least one note');

  /// Identity of this grace chord, drawn from the same ids as events.
  final EventId id;

  /// Which kind of grace, which sets how long it plays.
  final GraceKind kind;

  /// Written value, which sets its flags and beams. Playback lets a lone
  /// appoggiatura take this long, up to its limit, and shares the time of
  /// several graces by it.
  final NoteValue value;

  /// Heads, all pitched or all drums like the principal chord's.
  final Seq<Note> notes;
}

/// How a grace chord is drawn and how much time it takes from its
/// principal. See [GraceChord].
enum GraceKind {
  /// A short grace, drawn with a slash through the stem. Each takes a 64th,
  /// and all of them together at most half the principal.
  acciaccatura,

  /// A leaning grace, drawn without the slash. Alone it takes its written
  /// value, up to half the principal. Among other graces it is as quick as
  /// an acciaccatura.
  appoggiatura,
}

/// Whether to print an accidental. [auto] defers to
/// `StaffView.accidentals`, which applies key, bar and tie rules.
enum AccidentalRequest {
  /// Prints where the key, bar and tie rules call for one.
  auto,

  /// Prints even where the rules would not.
  always,

  /// Prints in parentheses, even where the rules would not.
  cautionary,

  /// Never prints. The head also leaves the alteration in force at its
  /// staff position unchanged for later heads in the bar.
  never,
}

/// Shape of a pitched note head.
enum NoteHead {
  /// The usual oval.
  normal,

  /// An x.
  cross,

  /// A diamond, as for a harmonic.
  diamond,

  /// A slash, as for rhythm notation.
  slash,

  /// A triangle pointing up.
  triangle,

  /// An x inside a circle.
  circleCross,
}

/// Which way a chord's stem points.
enum StemDirection {
  /// Layout decides. With two or more voices on the staff it follows
  /// [VoiceSlot.stemsUp], and otherwise the heads' places on the staff.
  auto,

  /// Stem up.
  up,

  /// Stem down.
  down,
}

/// Per-event override of default beaming (which comes from the meter).
enum BeamMode {
  /// Follows the meter's default grouping.
  auto,

  /// Start a new beam group here.
  begin,

  /// Join the previous event's group across a default break.
  join,

  /// Never beamed.
  none,
}

/// Stackable event marks. A string note can still carry down-bow,
/// accent and trill at once, through [ChordEvent.bowing],
/// [Event.articulations] and [ChordEvent.ornament].
///
/// In a tie chain, the time a [staccato], [staccatissimo] or [tenuto] sets
/// runs from the note it is on to the end of the chain, and the last marked
/// note's mark counts.
enum Articulation {
  /// A dot. The note sounds for half its time, or three quarters under a
  /// [tenuto].
  staccato,

  /// A wedge. The note sounds for a quarter of its time.
  staccatissimo,

  /// An accent. The note strikes harder.
  accent,

  /// A marcato. The note strikes harder than under an [accent], and both
  /// together stack.
  marcato,

  /// A line. The note sounds for its full time.
  tenuto,

  /// A pause. Time under it passes at half speed in every part. The only
  /// mark a rest may carry.
  fermata,

  /// A small circle above the chord, for a string harmonic. Playback
  /// ignores it.
  harmonic,
}

/// An ornament sign on one chord. Playback plays its figure from scale
/// steps of the key, where an accidental above or below the sign
/// ([ChordEvent.ornamentAbove], [ChordEvent.ornamentBelow]) alters the note
/// on that side.
enum Ornament {
  /// Alternates with the note above, about 13 notes a second at any tempo.
  /// A short note fits its notes at 8 to 27 a second, and a note too short
  /// for that plays alone.
  trill,

  /// The note, the one below, then the note again.
  mordent,

  /// The note, the one above, then the note again.
  invertedMordent,

  /// The note above, the note, the note below, then the note.
  turn,

  /// The note below, the note, the note above, then the note.
  invertedTurn,
}

/// Bow direction for a string stroke.
enum Bowing {
  /// Up-bow.
  up,

  /// Down-bow.
  down,
}

/// One verse's syllable under a chord.
final class Lyric {
  /// The syllable [text] of [verse].
  const Lyric({
    required this.verse,
    required this.text,
    this.syllabic = Syllabic.single,
    this.extend = false,
  });

  /// 1-based verse number.
  final int verse;

  /// The syllable as it prints. Hyphens come from [syllabic].
  final String text;

  /// Where the syllable sits in its word, which decides the hyphens drawn
  /// after it.
  final Syllabic syllabic;

  /// Draw a melisma extender line after the syllable.
  final bool extend;

  @override
  bool operator ==(Object other) =>
      other is Lyric &&
      other.verse == verse &&
      other.text == text &&
      other.syllabic == syllabic &&
      other.extend == extend;

  @override
  int get hashCode => Object.hash(verse, text, syllabic, extend);
}

/// Where a [Lyric] syllable sits in its word.
enum Syllabic {
  /// A whole word.
  single,

  /// The first syllable. A hyphen follows it.
  begin,

  /// A syllable inside the word. A hyphen follows it.
  middle,

  /// The last syllable.
  end,
}
