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

  final EventId id;

  /// Stackable marks; order does not matter. Includes fermata, which is
  /// valid on rests. Unmodifiable. Marks that exclude each other (bowing,
  /// ornaments) are single fields on [ChordEvent] instead.
  final Set<Articulation> articulations;
}

/// One or more simultaneous note heads sharing a stem and a duration.
final class ChordEvent extends Event {
  ChordEvent({
    required super.id,
    required this.value,
    required this.notes,
    super.articulations,
    this.ornament,
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
       assert(tremolo >= 0 && tremolo <= 4, 'tremolo strokes in 0..4');

  final NoteValue value;

  /// At most one ornament sign per chord. A trill that continues over
  /// several notes is a `TrillLine` spanner, not this field.
  final Ornament? ornament;

  /// Bow direction for this stroke. One field, so up-bow and down-bow
  /// cannot both be set.
  final Bowing? bowing;

  /// All pitched or all drums, sorted by [Tone.compareTo]: lowest to highest
  /// sounding pitch, or drums by name. No two notes share a tone, but a
  /// unison of different spellings (E♯/F) is allowed.
  final Seq<Note> notes;

  /// Grace chords played before this chord, in order.
  final Seq<GraceChord> graces;

  final StemDirection stem;
  final BeamMode beam;

  /// Single-note tremolo strokes through the stem. 0 for none.
  final int tremolo;

  /// One entry per verse.
  final Seq<Lyric> lyrics;

  @override
  Length get span => value.length;

  Note? note(NoteId id) {
    for (final note in notes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  ChordEvent copyWith({
    EventId? id,
    NoteValue? value,
    Seq<Note>? notes,
    Set<Articulation>? articulations,
    Ornament? Function()? ornament,
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
  const RestEvent({
    required super.id,
    required this.value,
    super.articulations,
    this.hidden = false,
  });

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

  final TupletId id;
  final TupletRatio ratio;

  /// The value the ratio counts in: a triplet of eighths has unit eighth.
  final NoteValue unit;

  final Seq<Content> members;
  final TupletBracket bracket;

  @override
  Length get span => unit.length * Fraction(ratio.normal);
}

enum TupletBracket { auto, shown, hidden }

/// One note head.
sealed class Note {
  const Note({required this.id, this.tie = false});

  final NoteId id;

  /// Tied to the head of the same [tone] in the next event of the same
  /// staff and voice, which may be in the next measure. The tie's end is
  /// derived, never stored, so it cannot dangle. If no matching head
  /// follows, the tie is drawn as a short let-ring tie and playback ends the
  /// note normally.
  final bool tie;

  /// What it plays. A chord never holds one tone twice.
  Tone get tone;

  Note copyWith({NoteId? id, bool? tie});
}

/// A head on a pitched staff.
final class PitchedNote extends Note {
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

  final AccidentalRequest accidental;
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
  const DrumNote({required super.id, required this.drum, super.tie});

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
/// the principal: a 32nd for each acciaccatura, or half the principal when
/// any is an appoggiatura, and never more than half.
final class GraceChord {
  GraceChord({
    required this.id,
    required this.kind,
    required this.value,
    required this.notes,
  }) : assert(notes.isNotEmpty, 'a grace chord has at least one note');

  final EventId id;
  final GraceKind kind;
  final NoteValue value;
  final Seq<Note> notes;
}

enum GraceKind { acciaccatura, appoggiatura }

/// Whether to print an accidental. [auto] defers to
/// `StaffView.accidentals`, which applies key, bar and tie rules.
enum AccidentalRequest { auto, always, cautionary, never }

enum NoteHead { normal, cross, diamond, slash, triangle, circleCross }

enum StemDirection { auto, up, down }

/// Per-event override of default beaming (which comes from the meter).
enum BeamMode {
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
enum Articulation {
  staccato,
  staccatissimo,
  accent,
  marcato,
  tenuto,
  fermata,
  harmonic,
}

enum Ornament { trill, mordent, invertedMordent, turn, invertedTurn }

enum Bowing { up, down }

final class Lyric {
  const Lyric({
    required this.verse,
    required this.text,
    this.syllabic = Syllabic.single,
    this.extend = false,
  });

  /// 1-based verse number.
  final int verse;
  final String text;
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

enum Syllabic { single, begin, middle, end }
