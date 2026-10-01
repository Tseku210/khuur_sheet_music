/// The Read stage of MusicXML import: walks a `score-partwise` document into
/// the records assembly builds a score from. Only this stage touches the
/// XML. Internal to the package.
library;

import 'package:xml/xml.dart';

import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../refs.dart';
import '../rules.dart';
import '../score.dart';
import '../stable_sort.dart';
import '../time.dart';
import 'musicxml_names.dart';
import 'musicxml_records.dart';

part 'musicxml_read_marks.dart';
part 'musicxml_read_notes.dart';

DocumentRecord readDocument(XmlElement root) {
  final ids = Ids();
  final identification = root.getElement('identification');
  bool supports(String element) =>
      identification
          ?.getElement('encoding')
          ?.findElements('supports')
          .any(
            (supports) =>
                supports.getAttribute('element') == element &&
                supports.getAttribute('type') == 'yes',
          ) ??
      false;
  final declared = <String?, XmlElement>{};
  for (final scorePart
      in root.getElement('part-list')?.findElements('score-part') ??
          const <XmlElement>[]) {
    declared.putIfAbsent(scorePart.getAttribute('id'), () => scorePart);
  }
  final elements = root.findElements('part').toList();
  if (elements.isEmpty) {
    Source(root).missing('part');
  }
  final printed = <NoteId, bool>{};
  final statesBeams =
      supports('beam') ||
      root.descendantElements.any((element) => element.name.local == 'beam');
  final joins = statesBeams ? <EventId, bool>{} : null;
  final readers = <_PartReader>[];
  for (final element in elements) {
    final id = element.getAttributeNode('id') ?? Source(element).missing('@id');
    final scorePart =
        declared[id.value] ?? Source(id).refuse('no score-part ${id.value}');
    final measures = element.findElements('measure').toList();
    final bars = readers.firstOrNull?.measures.length;
    if (measures.isEmpty && bars == null) {
      Source(element).missing('measure');
    }
    if (bars != null && measures.length != bars) {
      Source(element).refuse(
        'has ${measures.length} bars where the first part has $bars',
      );
    }
    readers.add(
      _header(scorePart, measures, ids: ids, printed: printed, joins: joins),
    );
  }
  final measures = <MeasureId>[];
  for (final (p, reader) in readers.indexed) {
    for (final (bar, measure) in reader.measures.indexed) {
      if (p == 0) {
        measures.add(MeasureId(ids.take()));
      }
      reader.bars.add(_BarReader(reader, bar).read(measure));
    }
  }
  return DocumentRecord(
    meta: _meta(root),
    parts: [for (final reader in readers) reader.record()],
    measures: measures,
    printed: printed,
    supportsAccidentals: supports('accidental'),
    joins: joins,
    ids: ids,
  );
}

ScoreMeta _meta(XmlElement root) {
  String? credit(String type) => root
      .findElements('credit')
      .where(
        (credit) => credit
            .findElements('credit-type')
            .any((element) => element.innerText.trim() == type),
      )
      .map(
        (credit) => credit
            .findElements('credit-words')
            .map((words) => words.innerText)
            .join(),
      )
      .firstOrNull;
  final identification = root.getElement('identification');
  String creator(String type) =>
      identification
          ?.findElements('creator')
          .where((creator) => creator.getAttribute('type') == type)
          .firstOrNull
          ?.innerText ??
      '';
  return ScoreMeta(
    title:
        root.getElement('work')?.getElement('work-title')?.innerText ??
        root.getElement('movement-title')?.innerText ??
        credit('title') ??
        '',
    subtitle: credit('subtitle') ?? '',
    composer: creator('composer'),
    lyricist: creator('lyricist'),
    copyright: identification?.getElement('rights')?.innerText ?? '',
  );
}

/// One drum of a part's kit. Its staff position and head come from the
/// first note that plays it, since the file states them nowhere else.
final class _KitDrum {
  _KitDrum({required this.id, required this.name, required this.midiKey});

  final String? id;
  final String name;
  final int midiKey;
  Pitch? position;
  NoteHead head = NoteHead.normal;

  DrumSound get sound => DrumSound(
    name: name,
    position: position ?? const Pitch(Step.b, 4),
    midiKey: midiKey,
    head: head,
  );
}

/// A part's header, and what reading its bars carries from one to the next.
final class _PartReader {
  _PartReader({
    required this.ids,
    required this.printed,
    required this.joins,
    required this.measures,
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
    required this.kit,
  });

  final Ids ids;
  final Map<NoteId, bool> printed;
  final Map<EventId, bool>? joins;
  final List<XmlElement> measures;
  final PartId id;
  final List<StaffId> staves;
  final String name;
  final String shortName;
  final int program;
  final int bank;
  final Interval transposition;
  final List<Pitch> strings;
  final List<int> lines;
  final bool hidden;
  final List<_KitDrum> kit;

  final bars = <BarRecord>[];
  final marks = <(String, String), List<LineMark>>{};
  var _marks = 0;

  /// Divisions of a whole note, once the part has declared them.
  Fraction? perWhole;

  /// How many `<note>`s have been read.
  int notes = 0;

  /// A start of [element] and [number]. With no [kind] it opens nothing
  /// the model keeps.
  void start(String element, String number, SpannerKind? kind, Anchor anchor) =>
      marks
          .putIfAbsent((element, number), () => [])
          .add(LineMark.start(kind, anchor, _marks++));

  void stop(String element, String number, Anchor anchor) => marks
      .putIfAbsent((element, number), () => [])
      .add(LineMark.stop(anchor, _marks++));

  PartRecord record() => PartRecord(
    id: id,
    staves: staves,
    name: name,
    shortName: shortName,
    program: program,
    bank: bank,
    transposition: transposition,
    strings: strings,
    lines: lines,
    hidden: hidden,
    drums: [for (final drum in kit) drum.sound],
    bars: bars,
    marks: marks,
  );
}

_PartReader _header(
  XmlElement scorePart,
  List<XmlElement> measures, {
  required Ids ids,
  required Map<NoteId, bool> printed,
  required Map<EventId, bool>? joins,
}) {
  final name =
      scorePart.getElement('part-name') ??
      Source(scorePart).missing('part-name');
  final midi = scorePart.findElements('midi-instrument').toList();
  final program = switch (midi.firstOrNull?.getElement('midi-program')) {
    final element? => _midiNumber(element, most: 128),
    null => 0,
  };
  final bank = switch (midi.firstOrNull?.getElement('midi-bank')) {
    final element? => _midiNumber(element),
    null => 0,
  };
  final keys = {
    for (final instrument in midi)
      if (instrument.getElement('midi-unpitched') case final element?)
        instrument.getAttribute('id'): _midiNumber(element, most: 128),
  };
  final kit = <_KitDrum>[];
  for (final instrument in scorePart.findElements('score-instrument')) {
    final id = instrument.getAttribute('id');
    final midiKey = keys[id];
    if (midiKey == null) {
      continue;
    }
    final drumName = instrument.getElement('instrument-name');
    kit.add(
      _KitDrum(id: id, name: drumName?.innerText ?? '', midiKey: midiKey),
    );
    final problem = instrumentProblem(
      Instrument(
        key: '',
        program: program,
        bank: bank,
        drums: [for (final drum in kit) drum.sound],
      ),
    );
    if (problem != null) {
      Source(drumName ?? instrument).refuse(problem);
    }
  }

  Iterable<XmlElement> attributes(String name) => measures
      .expand((measure) => measure.findElements('attributes'))
      .expand((attributes) => attributes.findElements(name));
  int? count;
  for (final staves in attributes('staves')) {
    final stated = integerOf(staves.innerText);
    if (stated == null || stated < 1 || stated > 99) {
      Source(staves).refuse('a part has 1 to 99 staves');
    }
    if (count != null && stated != count) {
      Source(staves).refuse('a part keeps one staff count');
    }
    count = stated;
  }
  final staves = count ?? 1;

  final lines = List.filled(staves, 5);
  final lined = <int>{};
  List<Pitch>? strings;
  for (final details in attributes('staff-details')) {
    final staff = _staffNumber(details.getAttributeNode('number'), staves);
    final staffLines = details.getElement('staff-lines');
    if (staffLines != null && lined.add(staff)) {
      final stated = integerOf(staffLines.innerText);
      if (stated == null || stated < 1) {
        Source(staffLines).refuse('a staff has 1 or more lines');
      }
      lines[staff] = stated;
    }
    final tunings = details.findElements('staff-tuning').toList();
    if (strings == null && tunings.isNotEmpty) {
      final byLine = stableSorted([
        for (final (i, tuning) in tunings.indexed)
          (integerOf(tuning.getAttribute('line')) ?? i + 1, tuning),
      ], (a, b) => a.$1 - b.$1);
      strings = [
        for (final (_, tuning) in byLine)
          _soundingPitch(tuning, prefix: 'tuning-'),
      ];
    }
  }

  final unprinted = {
    for (final attributes in measures.first.findElements('attributes'))
      for (final details in attributes.findElements('staff-details'))
        if (details.getAttribute('print-object') == 'no')
          _staffNumber(details.getAttributeNode('number'), staves),
  };

  Interval? transposition;
  for (final child in measures.first.childElements) {
    if (const {'note', 'backup', 'forward'}.contains(child.name.local)) {
      break;
    }
    if (child.name.local == 'attributes') {
      transposition ??= child
          .findElements('transpose')
          .map(_interval)
          .firstOrNull;
    }
  }

  return _PartReader(
    ids: ids,
    printed: printed,
    joins: joins,
    measures: measures,
    id: PartId(ids.take()),
    staves: [for (var i = 0; i < staves; i++) StaffId(ids.take())],
    name: name.innerText,
    shortName: scorePart.getElement('part-abbreviation')?.innerText ?? '',
    program: program,
    bank: bank,
    transposition: transposition ?? Interval.unison,
    strings: strings ?? const [],
    lines: lines,
    hidden: unprinted.length == staves,
    kit: kit,
  );
}

/// A MIDI number written from 1, as the model's number from 0.
int _midiNumber(XmlElement element, {int? most}) {
  final value = integerOf(element.innerText);
  if (value == null || value < 1 || (most != null && value > most)) {
    Source(element).refuse('outside 1..128');
  }
  return value - 1;
}

/// The staff, from 0, that a `number` attribute or `<staff>` names among
/// [staves]. Without one it is the first.
int _staffNumber(XmlNode? number, int staves) {
  if (number == null) {
    return 0;
  }
  final value = integerOf(switch (number) {
    XmlAttribute(:final value) => value,
    _ => number.innerText,
  });
  if (value == null || value < 1 || value > staves) {
    Source(number).refuse('no such staff');
  }
  return value - 1;
}

Interval _interval(XmlElement transpose) {
  int number(XmlElement? element) {
    if (element == null) {
      return 0;
    }
    return integerOf(element.innerText) ??
        Source(element).refuse('expected an integer');
  }

  final diatonic = transpose.getElement('diatonic');
  final octaves = number(transpose.getElement('octave-change'));
  final semitones =
      number(
        transpose.getElement('chromatic') ??
            Source(transpose).missing('chromatic'),
      ) +
      12 * octaves;
  final interval = Interval(
    diatonic == null
        ? (semitones * 7 / 12).round()
        : number(diatonic) + 7 * octaves,
    semitones,
  );
  // KeySignature.transpose has no key for a tonic that needs a double
  // sharp or flat, which is what an interval like a doubly augmented unison
  // asks of it.
  for (final way in [interval, -interval]) {
    final tonic = const Pitch(Step.c, 4).transpose(way);
    if (tonic.alter.quarterTones.abs() > 2) {
      Source(transpose).refuse('no key signature fits this transposition');
    }
  }
  return interval;
}

Step _step(XmlElement element) {
  final name = element.innerText.trim();
  return Step.values
          .where((step) => step.name.toUpperCase() == name)
          .firstOrNull ??
      Source(element).refuse('no such step');
}

Alter _alter(XmlElement? element) {
  if (element == null) {
    return Alter.natural;
  }
  final semitones = decimalOf(element.innerText);
  final quarters = semitones == null ? null : semitones * Fraction(2);
  if (quarters == null ||
      quarters.denominator != 1 ||
      quarters.numerator.abs() > 4) {
    Source(element).refuse('not a quarter-tone alteration in -2..2');
  }
  return Alter.fromQuarterTones(quarters.numerator);
}

int _octave(XmlElement element) {
  final octave = integerOf(element.innerText);
  if (octave == null || octave < 0 || octave > 9) {
    Source(element).refuse('an octave is 0 to 9');
  }
  return octave;
}

/// The pitch [element] spells with its `step`, `alter` and `octave`
/// children, each named after [prefix].
Pitch _pitch(XmlElement element, {String prefix = ''}) => Pitch(
  _step(
    element.getElement('${prefix}step') ??
        Source(element).missing('${prefix}step'),
  ),
  _octave(
    element.getElement('${prefix}octave') ??
        Source(element).missing('${prefix}octave'),
  ),
  _alter(element.getElement('${prefix}alter')),
);

/// A pitch that is stored as it is written, so it must be one MIDI plays.
Pitch _soundingPitch(XmlElement element, {required String prefix}) {
  final pitch = _pitch(element, prefix: prefix);
  if (pitchProblem(pitch) case final problem?) {
    Source(element).refuse(problem);
  }
  return pitch;
}

PitchName? _pitchName(XmlElement? element, String prefix) {
  final step = element?.getElement('$prefix-step');
  return step == null
      ? null
      : PitchName(_step(step), _alter(element?.getElement('$prefix-alter')));
}

/// One part's reader state while a voice of a bar is being read.
final class _Lane {
  _Lane(this.record);

  final LaneRecord record;

  /// Open tuplets, outermost first.
  final frames = <_Frame>[];

  /// Graces waiting for the voice's next chord.
  final graces = <_PendingGrace>[];
}

/// Reads one `<measure>` of one part.
final class _BarReader {
  _BarReader(this.part, this.bar);

  final _PartReader part;
  final int bar;

  Moment cursor = Moment.zero;
  Moment furthest = Moment.zero;
  final lanes = <int, _Lane>{};

  /// What a `<chord/>` note joins.
  _Last? last;
  _PendingGrace? lastGrace;

  ({KeySignature key, bool printed})? key;
  ({Meter meter, Source source})? meter;
  final clefs = <({int staff, Moment at, Clef clef})>[];
  final directions = <({int staff, StaffDirection direction})>[];
  final tempos = <TempoMark>[];
  final rehearsals = <({Moment at, String text})>[];
  final navigation = <NavigationMark>[];
  String? style;
  bool repeatStart = false;
  RepeatEnd? repeatEnd;
  List<int>? endingStart;
  String? endingStop;
  LayoutBreak? breakBefore;

  BarRecord read(XmlElement measure) {
    for (final child in measure.childElements) {
      switch (child.name.local) {
        case 'note':
          _note(child);
        case 'backup':
          final (:element, raw: _, :length) = _duration(child);
          final target = cursor - length;
          if (target.isNegative) {
            Source(element).refuse('backs up past the bar start');
          }
          cursor = _storable(target, Source(element));
        case 'forward':
          final (:element, raw: _, :length) = _duration(child);
          final voice = child.getElement('voice');
          if (voice != null) {
            final staff = _staff(child);
            _lane(
              _voice(child, staff),
              staff,
              Source(voice),
            ).record.lastForward = Source(
              child,
            );
          }
          _advance(length, Source(element));
        case 'attributes':
          _attributes(child);
        case 'direction':
          _direction(child);
        case 'harmony':
          _harmony(child);
        case 'sound':
          _marks(child, at: cursor);
        case 'barline':
          _barline(child);
        case 'print':
          breakBefore = child.getAttribute('new-page') == 'yes'
              ? LayoutBreak.page
              : child.getAttribute('new-system') == 'yes'
              ? LayoutBreak.system
              : breakBefore;
      }
    }
    return BarRecord(
      source: Source(measure),
      end: furthest,
      lanes: _finishedLanes(),
      key: key,
      meter: meter,
      clefs: clefs,
      directions: directions,
      tempos: tempos,
      rehearsals: rehearsals,
      navigation: navigation,
      barline: BarlineRecord(
        style: style,
        repeatStart: repeatStart,
        repeatEnd: repeatEnd,
        endingStart: endingStart,
        endingStop: endingStop,
      ),
      breakBefore: breakBefore,
    );
  }

  Moment _storable(Moment time, Source at) =>
      storable(time.wholeNotes) ? time : at.refuse(unstorable);

  void _advance(Length length, Source at) {
    cursor = _storable(cursor + length, at);
    if (cursor > furthest) {
      furthest = cursor;
    }
  }

  /// The `<duration>` of [parent], as written and in whole notes.
  ({XmlElement element, Fraction raw, Length length}) _duration(
    XmlElement parent,
  ) {
    final element =
        parent.getElement('duration') ?? Source(parent).missing('duration');
    final perWhole =
        part.perWhole ??
        Source(element).refuse('a duration before any divisions');
    final raw = decimalOf(element.innerText);
    if (raw == null || raw.isNegative) {
      Source(element).refuse('a duration is a number of divisions from 0');
    }
    final length = raw / perWhole;
    if (!storable(length)) {
      Source(element).refuse(unstorable);
    }
    return (element: element, raw: raw, length: Length(length));
  }

  int _staff(XmlElement parent) =>
      _staffNumber(parent.getElement('staff'), part.staves.length);

  /// The voice [parent] names. Without one it is the first voice of its
  /// [staff], as export numbers voices.
  int _voice(XmlElement parent, int staff) {
    final voice = parent.getElement('voice');
    if (voice == null) {
      return voiceNumber(staff, VoiceSlot.one);
    }
    final number = integerOf(voice.innerText);
    if (number == null || number < 1) {
      Source(voice).refuse('a voice is a number from 1');
    }
    return number;
  }

  _Lane _lane(int voice, int staff, Source source) => lanes.putIfAbsent(
    voice,
    () => _Lane(LaneRecord(voice: voice, staff: staff, voiceSource: source)),
  );

  /// The lanes that hold events, once their tuplets are closed and no two
  /// of them claim one voice slot.
  List<LaneRecord> _finishedLanes() {
    final kept = <LaneRecord>[];
    for (final lane in lanes.values) {
      while (lane.frames.isNotEmpty) {
        final frame = lane.frames.last;
        if (!frame.implicit) {
          frame.source.refuse('the tuplet never stops in its bar');
        }
        _closeImplicit(lane);
      }
      final record = lane.record;
      final events = eventsIn(record.items).toList();
      if (events.length > 1) {
        for (final event in events) {
          if (event case RestRecord(measure: true, :final rest)) {
            rest.refuse('a measure rest shares its voice');
          }
        }
      }
      if (events.isEmpty) {
        continue;
      }
      for (final other in kept) {
        if (other.staff == record.staff && other.slot == record.slot) {
          record.voiceSource.refuse(
            'voices ${other.voice} and ${record.voice} share a slot on '
            'staff ${record.staff + 1}',
          );
        }
      }
      kept.add(record);
    }
    return kept;
  }

  void _attributes(XmlElement attributes) {
    for (final child in attributes.childElements) {
      switch (child.name.local) {
        case 'divisions':
          final divisions = decimalOf(child.innerText);
          final perWhole = divisions == null ? null : divisions * Fraction(4);
          if (perWhole == null || !perWhole.isPositive) {
            Source(child).refuse('divisions are a number above 0');
          }
          if (!storable(perWhole)) {
            Source(child).refuse(unstorable);
          }
          part.perWhole = perWhole;
        case 'key':
          key ??= (
            key: _key(child),
            printed: child.getAttribute('print-object') != 'no',
          );
        case 'time':
          meter ??= (meter: _time(child), source: Source(child));
        case 'clef':
          clefs.add((
            staff: _staffNumber(
              child.getAttributeNode('number'),
              part.staves.length,
            ),
            at: cursor,
            clef: _clef(child),
          ));
        case 'transpose':
          if (_interval(child) != part.transposition) {
            Source(child).refuse('a part keeps one transposition');
          }
      }
    }
  }

  KeySignature _key(XmlElement key) {
    if (cursor.isPositive) {
      Source(key).refuse('a key changes at a bar start');
    }
    final fifths =
        key.getElement('fifths') ??
        Source(key).refuse('only a key of fifths is read');
    final stated = integerOf(fifths.innerText);
    if (stated == null || keyProblem(stated) != null) {
      Source(fifths).refuse('fifths outside -7..7');
    }
    return KeySignature(
      stated,
      switch (key.getElement('mode')?.innerText.trim()) {
        'major' => KeyMode.major,
        'minor' => KeyMode.minor,
        _ => KeyMode.none,
      },
    );
  }

  Meter _time(XmlElement time) {
    if (cursor.isPositive) {
      Source(time).refuse('a meter changes at a bar start');
    }
    if (time.getElement('senza-misura') != null) {
      Source(time).refuse('senza-misura is not supported');
    }
    final beats = time.findElements('beats').toList();
    final beatTypes = time.findElements('beat-type').toList();
    if (beats.length > 1 || beatTypes.length > 1) {
      Source(time).refuse('several meters at once are not supported');
    }
    final groups = beats.firstOrNull ?? Source(time).missing('beats');
    final beatType = beatTypes.firstOrNull ?? Source(time).missing('beat-type');
    final unit = integerOf(beatType.innerText);
    if (unit == null || unitProblem(unit) != null) {
      Source(beatType).refuse('not a power of two up to 128');
    }
    final meter = Meter(
      [for (final group in groups.innerText.split('+')) integerOf(group) ?? 0],
      unit,
      symbol: switch (time.getAttribute('symbol')) {
        'common' => MeterSymbol.common,
        'cut' => MeterSymbol.cut,
        _ => MeterSymbol.numeric,
      },
    );
    if (meterProblem(meter) case final problem?) {
      Source(time).refuse(problem);
    }
    return meter;
  }

  Clef _clef(XmlElement clef) {
    final sign = clefSignByName[clef.getElement('sign')?.innerText.trim()];
    final line = switch (clef.getElement('line')) {
      final element? => integerOf(element.innerText),
      null => switch (sign) {
        ClefSign.g => 2,
        ClefSign.f => 4,
        ClefSign.c => 3,
        ClefSign.percussion || null => null,
      },
    };
    final octave = switch (clef.getElement('clef-octave-change')) {
      final element? => integerOf(element.innerText),
      null => 0,
    };
    return Clef.values
            .where(
              (known) =>
                  known.sign == sign &&
                  known.octave == octave &&
                  (sign == ClefSign.percussion || known.line == line),
            )
            .firstOrNull ??
        Source(clef).refuse('no such clef');
  }
}
