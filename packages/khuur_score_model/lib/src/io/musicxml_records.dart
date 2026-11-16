/// What MusicXML import reads before it builds a score: plain records that
/// keep a light reference to the element each came from, so a refusal can
/// name it. Internal to the package.
library;

import 'package:xml/xml.dart';

import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../refs.dart';
import '../score.dart';
import '../time.dart';
import 'json.dart';
import 'musicxml_names.dart';

/// The element or attribute a record came from. Its path is built only
/// when a refusal names it.
extension type const Source(XmlNode node) {
  /// A refusal of this element for [message], thrown as a
  /// [ScoreFormatException] at its path.
  Never refuse(String message) =>
      throw ScoreFormatException(_path(node), message);

  /// A refusal of this element for lacking its child [name].
  Never missing(String name) =>
      throw ScoreFormatException('${_path(node)}/$name', 'missing');
}

String _path(XmlNode node) => switch (node) {
  XmlAttribute(:final parent?, :final name) =>
    '${_path(parent)}/@${name.local}',
  XmlElement(:final parent?, :final name) =>
    '${parent is XmlElement ? _path(parent) : ''}/${name.local}'
        '${_index(node, parent)}',
  _ => '/',
};

/// `[n]` when [element] has siblings of its name, counted from 1.
String _index(XmlElement element, XmlNode parent) {
  final named = [
    for (final sibling in parent.children)
      if (sibling is XmlElement && sibling.name.local == element.name.local)
        sibling,
  ];
  return named.length > 1 ? '[${named.indexOf(element) + 1}]' : '';
}

/// One counter for every id, so reading a file twice gives the same ids.
final class Ids {
  var _next = 1;

  /// The next id, counting from 1.
  int take() => _next++;
}

/// The file as read: its meta, what its encoding declares, and its parts.
final class DocumentRecord {
  /// Makes the record of a whole file.
  DocumentRecord({
    required this.meta,
    required this.parts,
    required this.measures,
    required this.printed,
    required this.supportsAccidentals,
    required this.joins,
    required this.ids,
  });

  /// The title, subtitle, composer, lyricist and copyright, from `<work>`,
  /// `<movement-title>`, `<credit>` and `<identification>`.
  final ScoreMeta meta;
  /// One record per `<part>`, in document order.
  final List<PartRecord> parts;

  /// One id per bar, minted while the first part was read.
  final List<MeasureId> measures;

  /// The pitched notes that print an accidental in the file, and whether
  /// it is cautionary.
  final Map<NoteId, bool> printed;

  /// The encoding declares that every accidental is written out.
  final bool supportsAccidentals;

  /// Whether each chord's beam joins the chord before, or null when the
  /// file leaves beams to the meter.
  final Map<EventId, bool>? joins;

  /// The counter the reader used, which assembly continues.
  final Ids ids;
}

/// One `<part>`, with what its `<score-part>` declares.
final class PartRecord {
  /// Makes the record of one part.
  PartRecord({
    required this.id,
    required this.staves,
    required this.name,
    required this.shortName,
    required this.program,
    required this.bank,
    required this.transposition,
    required this.strings,
    required this.lines,
    required this.hidden,
    required this.drums,
    required this.bars,
    required this.marks,
  });

  /// The id minted for the part.
  final PartId id;
  /// One id per staff, as many as `<staves>` states, or one.
  final List<StaffId> staves;
  /// The `<part-name>`.
  final String name;
  /// The `<part-abbreviation>`, or empty.
  final String shortName;
  /// The first `<midi-instrument>`'s `<midi-program>`, counted from 0, or 0
  /// when none is given.
  final int program;
  /// The first `<midi-instrument>`'s `<midi-bank>`, counted from 0, or 0 when
  /// none is given.
  final int bank;
  /// The `<transpose>` stated before the first note of the first bar, or a
  /// unison. It runs from written to sounding pitch, as in MusicXML, and
  /// becomes the part's `Instrument.transposition`.
  final Interval transposition;
  /// The open strings that `<staff-tuning>` states, in `line` order, or empty
  /// when the part states none.
  final List<Pitch> strings;

  /// Lines of each staff.
  final List<int> lines;

  /// The first bar marks every staff unprinted.
  final bool hidden;

  /// The kit, empty for a pitched part.
  final List<DrumSound> drums;

  /// One record per `<measure>`, in order.
  final List<BarRecord> bars;

  /// The spanner marks, in document order under their element and number.
  final Map<(String, String), List<LineMark>> marks;

  /// Whether the part has a kit, so that its notes are drums.
  bool get isPercussion => drums.isNotEmpty;
}

/// One bar of one part. Times are whole notes from the bar start.
final class BarRecord {
  /// Makes the record of one bar.
  BarRecord({
    required this.source,
    required this.end,
    required this.lanes,
    required this.key,
    required this.meter,
    required this.clefs,
    required this.directions,
    required this.tempos,
    required this.rehearsals,
    required this.navigation,
    required this.barline,
    required this.breakBefore,
  });

  /// The `<measure>`.
  final Source source;

  /// The furthest time the bar's elements reach.
  final Moment end;

  /// The voices that hold events, in the order the bar first names them.
  final List<LaneRecord> lanes;

  /// The written key stated at the bar start, and whether the file prints
  /// its signature.
  final ({KeySignature key, bool printed})? key;

  /// The first `<time>` of the bar and its element, or null when the bar states
  /// none.
  final ({Meter meter, Source source})? meter;
  /// Each `<clef>`, with its staff from 0 and the time it takes effect.
  final List<({int staff, Moment at, Clef clef})> clefs;
  /// Dynamics, words and chord symbols, each with its staff from 0.
  final List<({int staff, StaffDirection direction})> directions;
  /// The tempo marks a `<metronome>` or a `tempo` attribute of `<sound>`
  /// states.
  final List<TempoMark> tempos;
  /// Each `<rehearsal>`, with its text and time.
  final List<({Moment at, String text})> rehearsals;
  /// The segno, coda, fine and jump marks, in document order.
  final List<NavigationMark> navigation;
  /// What the bar's `<barline>` elements state.
  final BarlineRecord barline;
  /// The page or system break a `<print>` in the bar asks for before it, or
  /// null.
  final LayoutBreak? breakBefore;
}

/// The repeat, ending and right barline marks of one bar.
final class BarlineRecord {
  /// Makes the barline record of one bar.
  BarlineRecord({
    required this.style,
    required this.repeatStart,
    required this.repeatEnd,
    required this.endingStart,
    required this.endingStop,
  });

  /// The right barline's `<bar-style>`.
  final String? style;

  /// A forward `<repeat>` opens a repeat at this bar.
  final bool repeatStart;
  /// The backward `<repeat>` that closes a repeat at this bar, which plays
  /// `times` times, 2 when unstated. Null when there is none.
  final RepeatEnd? repeatEnd;

  /// The endings of a bracket that opens at this bar.
  final List<int>? endingStart;

  /// How a bracket closes at this bar: `stop` or `discontinue`.
  final String? endingStop;
}

/// One voice of one bar, as the file numbers it.
final class LaneRecord {
  /// Makes an empty lane for [voice] on [staff].
  LaneRecord({
    required this.voice,
    required this.staff,
    required this.voiceSource,
  }) : slot = slotOfVoice(voice);

  /// The `<voice>` number, from 1. A note without one is the first voice of its
  /// staff.
  final int voice;

  /// The staff, from 0, of the voice's first note or forward.
  final int staff;

  /// The slot [voice] maps to on its staff, by [slotOfVoice].
  final VoiceSlot slot;

  /// The `<voice>` that first named this voice, or its note.
  final Source voiceSource;

  /// Events and tuplets, in time order.
  final List<LaneItem> items = [];

  /// The first event that starts at each time, once the lane is read.
  late final Map<Moment, EventRecord> startingAt = {
    for (final event in eventsIn(items).toList().reversed) event.onset: event,
  };

  /// Where the last item ends.
  Moment end = Moment.zero;

  /// The last `<forward>` of this voice, where a gap after the last note is
  /// refused.
  Source? lastForward;
}

/// What a voice holds in the file, before assembly fills its gaps.
sealed class LaneItem {
  LaneItem({required this.onset, required this.end});

  /// Sounding times in the bar.
  final Moment onset;
  /// Where it stops sounding, in whole notes from the bar start.
  final Moment end;
}

/// The events of [items] in time order, those inside tuplets included.
Iterable<EventRecord> eventsIn(Iterable<LaneItem> items) sync* {
  for (final item in items) {
    switch (item) {
      case EventRecord():
        yield item;
      case TupletRecord(:final members):
        yield* eventsIn(members);
    }
  }
}

/// A chord or a rest of one voice.
sealed class EventRecord extends LaneItem {
  EventRecord({
    required super.onset,
    required super.end,
    required this.id,
    required this.note,
    required this.lane,
  });

  /// The id minted for the event.
  final EventId id;

  /// The event's first `<note>`.
  final Source note;

  /// The voice it belongs to.
  final LaneRecord lane;
}

/// A chord, read from one `<note>` and the `<chord/>` notes that join it.
final class ChordRecord extends EventRecord {
  /// Makes a chord with no notes yet. The reader adds them.
  ChordRecord({
    required super.onset,
    required super.end,
    required super.id,
    required super.note,
    required super.lane,
    required this.value,
    required this.graces,
  });

  /// The written value, from `<type>` and `<dot>`, or the value that fits the
  /// duration when the file gives no type.
  final NoteValue value;
  /// The notes, in document order.
  final List<NoteRecord> notes = [];
  /// The grace chords that lead into it in its voice, in order.
  final List<GraceRecord> graces;
  /// The articulations any of its notes state, a `<fermata>` and a `<harmonic>`
  /// included.
  final Set<Articulation> articulations = {};
  /// The first ornament a note states, or null. A `trill-mark` beside the start
  /// of a `wavy-line` does not count.
  Ornament? ornament;
  /// The first up-bow or down-bow a note states, or null.
  Bowing? bowing;
  /// The first `<stem>` of up or down a note states, else auto.
  StemDirection stem = StemDirection.auto;
  /// The strokes, 1 to 4, of the first single-note `<tremolo>` a note states,
  /// or 0 for none.
  int tremolo = 0;
  /// One lyric per verse. The first note to state a verse decides it.
  final List<Lyric> lyrics = [];
}

/// A rest, read from a `<note>` with a `<rest>`.
final class RestRecord extends EventRecord {
  /// Makes a rest.
  RestRecord({
    required super.onset,
    required super.end,
    required super.id,
    required super.note,
    required super.lane,
    required this.value,
    required this.typed,
    required this.hidden,
    required this.measure,
    required this.rest,
    required this.durationSource,
  });

  /// The value its duration is written as, or null when none is: a whole
  /// bar of 5/4, or a `<type>` that does not match the duration.
  final NoteValue? value;

  /// The file gives a `<type>`.
  final bool typed;

  /// The `<note>` is marked `print-object="no"`.
  final bool hidden;

  /// The file marks it `measure="yes"`.
  final bool measure;

  /// The `<rest>`.
  final Source rest;

  /// The `<duration>`, where a rest whose value cannot be written is refused.
  final Source durationSource;
  /// The rest carries a `<fermata>`.
  bool fermata = false;
}

/// A tuplet and the items inside it.
final class TupletRecord extends LaneItem {
  /// Makes a tuplet once its members are read.
  TupletRecord({
    required super.onset,
    required super.end,
    required this.id,
    required this.ratio,
    required this.unit,
    required this.members,
    required this.bracket,
  });

  /// The id minted for the tuplet.
  final TupletId id;
  /// Actual notes over normal notes, from `<tuplet-actual>` and
  /// `<tuplet-normal>`, else from the notes' `<time-modification>`.
  final TupletRatio ratio;
  /// The value the ratio counts in, as the file states it or as the members add
  /// up to.
  final NoteValue unit;
  /// Events and nested tuplets, in time order.
  final List<LaneItem> members;
  /// From the `bracket` attribute of `<tuplet>`, or auto.
  final TupletBracket bracket;
}

/// A grace chord, read from a `<note>` with a `<grace>` and the `<chord/>`
/// grace notes that join it.
final class GraceRecord {
  /// Makes a grace chord with no notes yet.
  GraceRecord({required this.id, required this.kind, required this.value});

  /// The id minted for the grace chord.
  final EventId id;
  /// An acciaccatura when the `<grace>` has `slash="yes"`, else an
  /// appoggiatura.
  final GraceKind kind;
  /// The written `<type>` and `<dot>`s, or an eighth when the file gives no
  /// type.
  final NoteValue value;
  /// The notes, in document order.
  final List<NoteRecord> notes = [];
}

/// One note of a chord, a pitch or a drum, with its ties.
sealed class NoteRecord {
  NoteRecord({required this.id});

  /// The id minted for the note.
  final NoteId id;
  /// A `<tie>` or `<tied>` of type `start` is on the note.
  bool tieStart = false;
  /// A `<tie>` or `<tied>` of type `stop` is on the note.
  bool tieStop = false;
  /// A `<tie>` or `<tied>` of type `let-ring` is on the note.
  bool letRing = false;
}

/// A note with a `<pitch>`.
final class PitchedRecord extends NoteRecord {
  /// Makes a pitched note.
  PitchedRecord({
    required super.id,
    required this.written,
    required this.source,
    required this.head,
  });

  /// The pitch as the file writes it.
  final Pitch written;

  /// The `<pitch>`.
  final Source source;

  /// From `<notehead>`, normal when it is missing or unknown.
  final NoteHead head;
  /// The first `<fingering>` that is a finger number, or null.
  int? fingering;

  /// The `<string>` number, 1 for the highest string.
  int? string;
}

/// A note with an `<unpitched>`, played on a drum of the part's kit.
final class DrumRecord extends NoteRecord {
  /// Makes a drum note.
  DrumRecord({required super.id, required this.drum});

  /// The kit drum the note's `<instrument>` names, or the kit's only drum when
  /// it names none.
  final Drum drum;
}

/// Where a spanner end sits in the file.
sealed class Anchor {
  const Anchor(this.bar);

  /// The index of the bar in its part, from 0.
  final int bar;
}

/// An end written on an event's note.
final class EventAnchor extends Anchor {
  /// An end on a note of [event]. [note] is that note's place among the part's
  /// notes.
  const EventAnchor(super.bar, this.event, this.note);

  /// The event the note belongs to.
  final EventRecord event;

  /// Which `<note>` of the part carries it, counted in document order.
  final int note;
}

/// An end written as a direction on a staff at a time.
final class TimeAnchor extends Anchor {
  /// An end on [staff] at [at] in the bar.
  const TimeAnchor(super.bar, this.staff, this.at);

  /// The staff, from 0.
  final int staff;
  /// The time in the bar, in whole notes from its start.
  final Moment at;
}

/// A start or stop of a spanner, as the file writes it.
final class LineMark {
  /// A start of [kind] at [anchor]. [index] is its place among its part's
  /// marks.
  LineMark.start(this.kind, this.anchor, this.index) : starts = true;

  /// A stop at [anchor]. [index] is its place among its part's marks.
  LineMark.stop(this.anchor, this.index) : starts = false, kind = null;

  /// Whether it starts a spanner rather than stops one.
  final bool starts;

  /// What a start opens. Null for a stop, and for a start of something the
  /// model has no spanner for.
  final SpannerKind? kind;

  /// Where the end sits.
  final Anchor anchor;

  /// Where it comes among its part's marks.
  final int index;
}

const _limit = 1000000000;

/// What a time that is not [storable] is refused with.
const unstorable = 'a time too fine or too long to store';

/// Whether both terms of [value] stay under a billion, so that one more
/// operation on it cannot overflow and the JSON form can hold it.
bool storable(Fraction value) =>
    value.numerator.abs() < _limit && value.denominator < _limit;

final _integer = RegExp(r'^-?[0-9]+$');
final _decimal = RegExp(r'^(-?)([0-9]+)(?:\.([0-9]+))?$');

/// The integer [text] writes, or null when it writes none or one of a
/// billion or more.
int? integerOf(String? text) {
  final trimmed = text?.trim() ?? '';
  final value = _integer.hasMatch(trimmed) ? int.tryParse(trimmed) : null;
  return value != null && value.abs() < _limit ? value : null;
}

/// The plain decimal number [text] writes, exactly, or null when it writes
/// none or one that is not [storable].
Fraction? decimalOf(String? text) {
  final match = _decimal.firstMatch(text?.trim() ?? '');
  if (match == null) {
    return null;
  }
  final whole = match[2]!.replaceFirst(RegExp('^0+(?=.)'), '');
  final places = (match[3] ?? '').replaceFirst(RegExp(r'0+$'), '');
  if (whole.length > 9 || places.length > 9) {
    return null;
  }
  var scale = 1;
  for (var i = 0; i < places.length; i++) {
    scale *= 10;
  }
  final units = int.parse(whole) * scale + int.parse('0$places');
  final value = Fraction(match[1] == '-' ? -units : units, scale);
  return storable(value) ? value : null;
}
