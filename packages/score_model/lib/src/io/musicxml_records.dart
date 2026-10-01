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

/// The element or attribute a record came from. Its path is built only
/// when a refusal names it.
extension type const Source(XmlNode node) {
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

  int take() => _next++;
}

/// The file as read: its meta, what its encoding declares, and its parts.
final class DocumentRecord {
  DocumentRecord({
    required this.meta,
    required this.parts,
    required this.measures,
    required this.printed,
    required this.supportsAccidentals,
    required this.joins,
    required this.ids,
  });

  final ScoreMeta meta;
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

final class PartRecord {
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

  final PartId id;
  final List<StaffId> staves;
  final String name;
  final String shortName;
  final int program;
  final int bank;
  final Interval transposition;
  final List<Pitch> strings;

  /// Lines of each staff.
  final List<int> lines;

  /// The first bar marks every staff unprinted.
  final bool hidden;

  /// The kit, empty for a pitched part.
  final List<DrumSound> drums;

  final List<BarRecord> bars;

  /// The spanner marks, in document order under their element and number.
  final Map<(String, String), List<LineMark>> marks;

  bool get isPercussion => drums.isNotEmpty;
}

/// One bar of one part. Times are whole notes from the bar start.
final class BarRecord {
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

  final List<LaneRecord> lanes;

  /// The written key stated at the bar start, and whether the file prints
  /// its signature.
  final ({KeySignature key, bool printed})? key;

  final ({Meter meter, Source source})? meter;
  final List<({int staff, Moment at, Clef clef})> clefs;
  final List<({int staff, StaffDirection direction})> directions;
  final List<TempoMark> tempos;
  final List<({Moment at, String text})> rehearsals;
  final List<NavigationMark> navigation;
  final BarlineRecord barline;
  final LayoutBreak? breakBefore;
}

final class BarlineRecord {
  BarlineRecord({
    required this.style,
    required this.repeatStart,
    required this.repeatEnd,
    required this.endingStart,
    required this.endingStop,
  });

  /// The right barline's `<bar-style>`.
  final String? style;

  final bool repeatStart;
  final RepeatEnd? repeatEnd;

  /// The endings of a bracket that opens at this bar.
  final List<int>? endingStart;

  /// How a bracket closes at this bar: `stop` or `discontinue`.
  final String? endingStop;
}

/// One voice of one bar, as the file numbers it.
final class LaneRecord {
  LaneRecord({
    required this.voice,
    required this.staff,
    required this.voiceSource,
  }) : slot = VoiceSlot.values[(voice - 1) % 4];

  final int voice;

  /// The staff, from 0, of the voice's first note or forward.
  final int staff;

  final VoiceSlot slot;

  /// The `<voice>` that first named this voice, or its note.
  final Source voiceSource;

  /// Events and tuplets, in time order.
  final List<LaneItem> items = [];

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

sealed class EventRecord extends LaneItem {
  EventRecord({
    required super.onset,
    required super.end,
    required this.id,
    required this.note,
    required this.lane,
  });

  final EventId id;

  /// The event's first `<note>`.
  final Source note;

  final LaneRecord lane;
}

final class ChordRecord extends EventRecord {
  ChordRecord({
    required super.onset,
    required super.end,
    required super.id,
    required super.note,
    required super.lane,
    required this.value,
    required this.graces,
  });

  final NoteValue value;
  final List<NoteRecord> notes = [];
  final List<GraceRecord> graces;
  final Set<Articulation> articulations = {};
  Ornament? ornament;
  Bowing? bowing;
  StemDirection stem = StemDirection.auto;
  int tremolo = 0;
  final List<Lyric> lyrics = [];
}

final class RestRecord extends EventRecord {
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

  final bool hidden;

  /// The file marks it `measure="yes"`.
  final bool measure;

  /// The `<rest>`.
  final Source rest;

  final Source durationSource;
  bool fermata = false;
}

final class TupletRecord extends LaneItem {
  TupletRecord({
    required super.onset,
    required super.end,
    required this.id,
    required this.ratio,
    required this.unit,
    required this.members,
    required this.bracket,
  });

  final TupletId id;
  final TupletRatio ratio;
  final NoteValue unit;
  final List<LaneItem> members;
  final TupletBracket bracket;
}

final class GraceRecord {
  GraceRecord({required this.id, required this.kind, required this.value});

  final EventId id;
  final GraceKind kind;
  final NoteValue value;
  final List<NoteRecord> notes = [];
}

sealed class NoteRecord {
  NoteRecord({required this.id});

  final NoteId id;
  bool tieStart = false;
  bool tieStop = false;
  bool letRing = false;
}

final class PitchedRecord extends NoteRecord {
  PitchedRecord({
    required super.id,
    required this.written,
    required this.source,
    required this.head,
  });

  final Pitch written;

  /// The `<pitch>`.
  final Source source;

  final NoteHead head;
  int? fingering;

  /// The `<string>` number, 1 for the highest string.
  int? string;
}

final class DrumRecord extends NoteRecord {
  DrumRecord({required super.id, required this.drum});

  final Drum drum;
}

/// Where a spanner end sits in the file.
sealed class Anchor {
  const Anchor(this.bar);

  final int bar;
}

/// An end written on an event's note.
final class EventAnchor extends Anchor {
  const EventAnchor(super.bar, this.event, this.note);

  final EventRecord event;

  /// Which `<note>` of the part carries it, counted in document order.
  final int note;
}

/// An end written as a direction on a staff at a time.
final class TimeAnchor extends Anchor {
  const TimeAnchor(super.bar, this.staff, this.at);

  final int staff;
  final Moment at;
}

/// A start or stop of a spanner, as the file writes it.
final class LineMark {
  LineMark.start(this.kind, this.anchor, this.index) : starts = true;

  LineMark.stop(this.anchor, this.index) : starts = false, kind = null;

  final bool starts;

  /// What a start opens. Null for a stop, and for a start of something the
  /// model has no spanner for.
  final SpannerKind? kind;

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
