/// Versioned JSON persistence (access pattern 7).
///
/// The wire format mirrors the tree. `measures` is a list of columns, each
/// with its bar facts and one entry per staff in system order, each with
/// voices of items. Ids are written as integers and read back unchanged.
/// Values at their defaults are left out.
///
/// Meter, key and clef are the one adaptation at the boundary. They are
/// written only where they change, as a composer reads them, and decoding
/// fills them into every column again. The file stays small and
/// hand-readable, and the in-memory score stays self-describing per bar.
///
/// Wire types never cross this boundary. Callers see [Score] in and out.
library;

import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../refs.dart';
import '../score.dart';
import '../seq.dart';
import '../time.dart';

/// Bumped on any incompatible change. A file from a newer version is
/// refused. When the version moves on, a migration from each older one
/// runs before decoding.
const int scoreSchemaVersion = 1;

/// Encodes [score] as JSON-compatible maps and lists.
///
/// Shape (abridged):
/// ```json
/// {"schema": 1, "meta": {"title": "Jasmine"},
///  "parts": [{"id": 1, "name": "Violin",
///             "instrument": {"key": "violin", "program": 40},
///             "staves": [{"id": 2}]}],
///  "measures": [{"id": 3, "meter": "4/4", "key": -1,
///                "staves": [{"clef": "treble",
///                            "voices": [{"voice": 1, "items": [
///                              {"chord": 4, "value": "quarter",
///                               "notes": [{"id": 5, "pitch": "F4"}]}]}]}]}],
///  "spanners": [{"id": 6, "kind": "slur", "staff": 2, "voice": 1,
///                "from": {"measure": 3, "at": "0"},
///                "to": {"measure": 3, "at": "3/4"}}]}
/// ```
Map<String, Object?> scoreToJson(Score score) {
  final meta = {
    for (final (key, value) in [
      ('title', score.meta.title),
      ('subtitle', score.meta.subtitle),
      ('composer', score.meta.composer),
      ('lyricist', score.meta.lyricist),
      ('copyright', score.meta.copyright),
    ])
      if (value.isNotEmpty) key: value,
  };
  return {
    'schema': scoreSchemaVersion,
    if (meta.isNotEmpty) 'meta': meta,
    'parts': [for (final part in score.parts) _part(part)],
    'measures': [
      for (final (i, column) in score.measures.indexed)
        _column(column, i == 0 ? null : score.measures[i - 1]),
    ],
    if (score.spanners.isNotEmpty)
      'spanners': [for (final spanner in score.spanners) _spanner(spanner)],
  };
}

/// Decodes a score, refusing a file from a newer schema version.
///
/// This is the one place where untrusted structure becomes a [Score], so it
/// checks every invariant the constructors assume and the rules the edits
/// rely on. Those are bar fill, voice order and gaps, tuplet fill, ids
/// unique per kind across the whole score, notes that suit their staff,
/// marks inside their bars in time order, and spanner anchors that exist.
/// Throws [ScoreFormatException] naming the JSON path of the first problem.
Score scoreFromJson(Object? json) => _Decoder().score(_In(json, r'$'));

final class ScoreFormatException implements Exception {
  const ScoreFormatException(this.path, this.message);

  /// JSON path of the offending value, such as `$.measures[12].staves[0]`.
  final String path;
  final String message;

  @override
  String toString() => 'ScoreFormatException at $path: $message';
}

Map<String, Object?> _part(Part part) => {
  'id': part.id.value,
  'name': part.name,
  if (part.shortName.isNotEmpty) 'shortName': part.shortName,
  if (part.hidden) 'hidden': true,
  'instrument': _instrument(part.instrument),
  'staves': [
    for (final staff in part.staves)
      {'id': staff.id.value, if (staff.lines != 5) 'lines': staff.lines},
  ],
};

Map<String, Object?> _instrument(Instrument instrument) => {
  'key': instrument.key,
  'program': instrument.program,
  if (instrument.bank != 0) 'bank': instrument.bank,
  if (instrument.transposition case final interval
      when interval != Interval.unison)
    'transposition': [interval.steps, interval.semitones],
  if (instrument.clef != Clef.treble) 'clef': instrument.clef.name,
  if (instrument.strings.isNotEmpty)
    'strings': [for (final pitch in instrument.strings) _pitch(pitch)],
  if (instrument.drums.isNotEmpty)
    'drums': [
      for (final sound in instrument.drums)
        {
          'name': sound.name,
          'position': _pitch(sound.position),
          'midiKey': sound.midiKey,
          if (sound.head != NoteHead.normal) 'head': sound.head.name,
        },
    ],
  if (instrument.lowest case final lowest?) 'lowest': _pitch(lowest),
  if (instrument.highest case final highest?) 'highest': _pitch(highest),
};

/// [column], with its meter, key and clefs left out where they are the
/// same as at the end of [previous].
Map<String, Object?> _column(MeasureColumn column, MeasureColumn? previous) => {
  'id': column.id.value,
  if (column.meter != previous?.meter) ...{
    'meter': '${column.meter.groups.join('+')}/${column.meter.unit}',
    if (column.meter.symbol != MeterSymbol.numeric)
      'meterSymbol': column.meter.symbol.name,
  },
  if (column.key != previous?.key) ...{
    'key': column.key.fifths,
    if (column.key.mode != KeyMode.none) 'mode': column.key.mode.name,
  },
  if (column.irregularLength case final length?)
    'length': _fraction(length.wholeNotes),
  if (column.barline != Barline.regular) 'barline': column.barline.name,
  if (column.repeatStart) 'repeatStart': true,
  if (column.repeatEnd case final end?) 'repeatEnd': end.times,
  if (column.volta case final volta?)
    'volta': {'endings': volta.endings, if (volta.open) 'open': true},
  if (column.navigation.isNotEmpty)
    'navigation': [for (final mark in column.navigation) _navigation(mark)],
  'rehearsal': ?column.rehearsal,
  if (column.tempos.isNotEmpty)
    'tempos': [
      for (final mark in column.tempos)
        {
          'at': _fraction(mark.offset.wholeNotes),
          'bpm': mark.tempo.bpm,
          if (mark.tempo.beat != NoteValue.quarter)
            'beat': _value(mark.tempo.beat),
          'text': ?mark.text,
          if (!mark.showMetronome) 'metronome': false,
        },
    ],
  if (column.breakBefore case final layoutBreak?) 'break': layoutBreak.name,
  if (column.keyDisplay != SignatureDisplay.auto)
    'keyDisplay': column.keyDisplay.name,
  if (column.meterDisplay != SignatureDisplay.auto)
    'meterDisplay': column.meterDisplay.name,
  'staves': [
    for (final (k, staff) in column.staves.indexed)
      _staffMeasure(staff, previous?.staves[k].clefAtEnd),
  ],
};

Object _navigation(NavigationMark mark) => switch (mark) {
  Segno() => 'segno',
  Coda() => 'coda',
  ToCoda() => 'toCoda',
  Fine() => 'fine',
  Jump(:final target, :final then, :final text) => {
    'jump': target.name,
    if (then != JumpThen.toEnd) 'then': then.name,
    'text': ?text,
  },
};

Map<String, Object?> _staffMeasure(StaffMeasure staff, Clef? before) => {
  if (staff.clef != before) 'clef': staff.clef.name,
  if (staff.clefChanges.isNotEmpty)
    'clefChanges': [
      for (final change in staff.clefChanges)
        {
          'at': _fraction(change.offset.wholeNotes),
          'clef': change.clef.name,
        },
    ],
  if (staff.directions.isNotEmpty)
    'directions': [
      for (final direction in staff.directions)
        {
          'at': _fraction(direction.offset.wholeNotes),
          ...switch (direction) {
            DynamicMark(:final level) => {'dynamic': level.name},
            TextMark(:final text, :final above) => {
              'text': text,
              if (!above) 'above': false,
            },
            ChordSymbol(:final root, :final quality, :final bass) => {
              'chord': _pitchName(root),
              if (quality.isNotEmpty) 'quality': quality,
              if (bass != null) 'bass': _pitchName(bass),
            },
          },
        },
    ],
  'voices': [
    for (final voice in staff.voices)
      {
        'voice': voice.slot.index + 1,
        'items': [for (final item in voice.items) _item(item)],
      },
  ],
};

Map<String, Object?> _item(VoiceItem item) => switch (item) {
  Gap(:final span) => {'gap': _fraction(span.wholeNotes)},
  ChordEvent() => _chord(item),
  RestEvent(:final id, :final value, :final hidden, :final articulations) => {
    'rest': id.value,
    'value': _value(value),
    if (hidden) 'hidden': true,
    ..._articulations(articulations),
  },
  MeasureRest(:final id, :final articulations) => {
    'measureRest': id.value,
    ..._articulations(articulations),
  },
  Tuplet(
    :final id,
    :final ratio,
    :final unit,
    :final bracket,
    :final members,
  ) =>
    {
      'tuplet': id.value,
      'ratio': [ratio.actual, ratio.normal],
      'unit': _value(unit),
      if (bracket != TupletBracket.auto) 'bracket': bracket.name,
      'members': [for (final member in members) _item(member)],
    },
};

Map<String, Object?> _chord(ChordEvent chord) => {
  'chord': chord.id.value,
  'value': _value(chord.value),
  'notes': [for (final note in chord.notes) _note(note)],
  ..._articulations(chord.articulations),
  if (chord.ornament case final ornament?) 'ornament': ornament.name,
  if (chord.bowing case final bowing?) 'bowing': bowing.name,
  if (chord.graces.isNotEmpty)
    'graces': [
      for (final grace in chord.graces)
        {
          'id': grace.id.value,
          'kind': grace.kind.name,
          'value': _value(grace.value),
          'notes': [for (final note in grace.notes) _note(note)],
        },
    ],
  if (chord.stem != StemDirection.auto) 'stem': chord.stem.name,
  if (chord.beam != BeamMode.auto) 'beam': chord.beam.name,
  if (chord.tremolo != 0) 'tremolo': chord.tremolo,
  if (chord.lyrics.isNotEmpty)
    'lyrics': [
      for (final lyric in chord.lyrics)
        {
          'verse': lyric.verse,
          'text': lyric.text,
          if (lyric.syllabic != Syllabic.single)
            'syllabic': lyric.syllabic.name,
          if (lyric.extend) 'extend': true,
        },
    ],
};

/// [marks] in [Articulation] order, so a set saves the same every time.
Map<String, Object?> _articulations(Set<Articulation> marks) => {
  if (marks.isNotEmpty)
    'articulations': [
      for (final mark in Articulation.values)
        if (marks.contains(mark)) mark.name,
    ],
};

Map<String, Object?> _note(Note note) => switch (note) {
  PitchedNote() => {
    'id': note.id.value,
    'pitch': _pitch(note.pitch),
    if (note.tie) 'tie': true,
    if (note.accidental != AccidentalRequest.auto)
      'accidental': note.accidental.name,
    if (note.head != NoteHead.normal) 'head': note.head.name,
    'fingering': ?note.fingering,
    'string': ?note.string,
  },
  DrumNote() => {
    'id': note.id.value,
    'drum': note.drum.name,
    if (note.tie) 'tie': true,
  },
};

Map<String, Object?> _spanner(Spanner spanner) => {
  'id': spanner.id.value,
  ...switch (spanner.kind) {
    Slur(:final dashed) => {'kind': 'slur', if (dashed) 'dashed': true},
    Hairpin(:final crescendo) => {
      'kind': crescendo ? 'crescendo' : 'diminuendo',
    },
    OctaveLine(:final shift) => {'kind': 'octave', 'shift': shift.name},
    TrillLine() => {'kind': 'trill'},
    TempoLine(:final text, :final factor) => {
      'kind': 'tempo',
      'text': text,
      'factor': factor,
    },
    PedalLine() => {'kind': 'pedal'},
    Glissando() => {'kind': 'glissando'},
  },
  'staff': spanner.staff.value,
  if (spanner.voice case final voice?) 'voice': voice.index + 1,
  for (final (key, point) in [('from', spanner.first), ('to', spanner.last)])
    key: {
      'measure': point.measure.value,
      'at': _fraction(point.offset.wholeNotes),
    },
};

String _fraction(Fraction fraction) => '$fraction';

String _value(NoteValue value) => '${value.base.name}${'.' * value.dots}';

String _pitch(Pitch pitch) => '${_pitchName(pitch.name)}${pitch.octave}';

String _pitchName(PitchName name) =>
    '${name.step.name.toUpperCase()}${_alterNames[name.alter]}';

/// How the file spells each alteration after the letter.
const Map<String, Alter> _alters = {
  'bb': Alter.doubleFlat,
  'db': Alter.threeQuarterFlat,
  'b': Alter.flat,
  'd': Alter.quarterFlat,
  '': Alter.natural,
  '+': Alter.quarterSharp,
  '#': Alter.sharp,
  '#+': Alter.threeQuarterSharp,
  'x': Alter.doubleSharp,
};

final Map<Alter, String> _alterNames = {
  for (final MapEntry(:key, :value) in _alters.entries) value: key,
};

/// A letter, an alteration and, for a pitch, an octave, as in `F#4`.
final _spelling = RegExp(
  '^([A-G])(${[
    for (final name in _alters.keys)
      if (name.isNotEmpty) RegExp.escape(name),
  ].join('|')})?(-?\\d)?\$',
);

/// Reads a file, keeping the ids it has seen so that each is used once.
final class _Decoder {
  final _parts = <int>{};
  final _staves = <int>{};
  final _measures = <int>{};
  final _events = <int>{};
  final _notes = <int>{};
  final _tuplets = <int>{};
  final _spanners = <int>{};

  Score score(_In json) {
    final schema = json['schema'];
    if (schema.integer != scoreSchemaVersion) {
      schema.fail(
        schema.integer > scoreSchemaVersion
            ? 'written by a newer version'
            : 'no such version',
      );
    }
    final parts = [for (final part in json['parts'].list) _part(part)];
    if (parts.isEmpty) {
      json['parts'].fail('a score has at least one part');
    }
    if (parts.every((part) => part.hidden)) {
      json['parts'].fail('a score shows at least one part');
    }
    final staves = [
      for (final part in parts)
        for (final staff in part.staves) (staff.id, part.instrument),
    ];
    final measures = <MeasureColumn>[];
    for (final column in json['measures'].list) {
      measures.add(_column(column, measures.lastOrNull, staves));
    }
    if (measures.isEmpty) {
      json['measures'].fail('a score has at least one measure');
    }
    final bars = {for (final (i, column) in measures.indexed) column.id: i};
    final meta = json.maybe('meta');
    String text(String key) => meta?.maybe(key)?.string ?? '';
    return Score(
      meta: ScoreMeta(
        title: text('title'),
        subtitle: text('subtitle'),
        composer: text('composer'),
        lyricist: text('lyricist'),
        copyright: text('copyright'),
      ),
      parts: Seq(parts),
      measures: Seq(measures),
      spanners: Seq([
        for (final spanner in json.maybe('spanners')?.list ?? const <_In>[])
          _spanner(spanner, measures, bars, {for (final (id, _) in staves) id}),
      ]),
    );
  }

  Part _part(_In json) {
    final id = PartId(_claim(_parts, json['id']));
    final staves = [
      for (final staff in json['staves'].list)
        Staff(
          id: StaffId(_claim(_staves, staff['id'])),
          lines:
              staff
                  .maybe('lines')
                  ?.integerWhere(
                    (n) => n >= 1,
                    'a staff has at least one line',
                  ) ??
              5,
        ),
    ];
    if (staves.isEmpty) {
      json['staves'].fail('a part has at least one staff');
    }
    return Part(
      id: id,
      name: json['name'].string,
      shortName: json.maybe('shortName')?.string ?? '',
      hidden: json.maybe('hidden')?.flag ?? false,
      instrument: _instrument(json['instrument']),
      staves: Seq(staves),
    );
  }

  Instrument _instrument(_In json) {
    final drums = <DrumSound>[];
    for (final sound in json.maybe('drums')?.list ?? const <_In>[]) {
      final name = sound['name'];
      if (drums.any((drum) => drum.name == name.string)) {
        name.fail('the kit names ${name.string} twice');
      }
      drums.add(
        DrumSound(
          name: name.string,
          position: sound['position'].pitch,
          midiKey: sound['midiKey'].midi,
          head: sound.maybe('head')?.name(NoteHead.values) ?? NoteHead.normal,
        ),
      );
    }
    final transposition = json.maybe('transposition');
    final interval = [
      for (final term in transposition?.list ?? const <_In>[]) term.integer,
    ];
    if (transposition != null && interval.length != 2) {
      transposition.fail('a transposition is [steps, semitones]');
    }
    return Instrument(
      key: json['key'].string,
      program: json['program'].midi,
      bank:
          json
              .maybe('bank')
              ?.integerWhere((n) => n >= 0, 'a bank is 0 or more') ??
          0,
      transposition: transposition == null
          ? Interval.unison
          : Interval(interval[0], interval[1]),
      clef: json.maybe('clef')?.name(Clef.values) ?? Clef.treble,
      strings: [
        for (final string in json.maybe('strings')?.list ?? const <_In>[])
          string.pitch,
      ],
      drums: drums,
      lowest: json.maybe('lowest')?.pitch,
      highest: json.maybe('highest')?.pitch,
    );
  }

  /// A column whose meter, key and clefs default to where [previous] ends.
  MeasureColumn _column(
    _In json,
    MeasureColumn? previous,
    List<(StaffId, Instrument)> staves,
  ) {
    final id = MeasureId(_claim(_measures, json['id']));
    final meter = previous != null && json.maybe('meter') == null
        ? previous.meter
        : _meter(json);
    final key = previous != null && json.maybe('key') == null
        ? previous.key
        : KeySignature(
            json['key'].integerWhere(
              (fifths) => fifths >= -7 && fifths <= 7,
              'a key has 7 flats to 7 sharps',
            ),
            json.maybe('mode')?.name(KeyMode.values) ?? KeyMode.none,
          );
    final irregular = json.maybe('length')?.barLength;
    final length = irregular ?? meter.length;
    final entries = json['staves'].list;
    if (entries.length != staves.length) {
      json['staves'].fail('expected ${staves.length}, one per staff');
    }
    final repeatEnd = json.maybe('repeatEnd');
    final volta = json.maybe('volta');
    return MeasureColumn(
      id: id,
      meter: meter,
      key: key,
      irregularLength: irregular,
      barline: json.maybe('barline')?.name(Barline.values) ?? Barline.regular,
      repeatStart: json.maybe('repeatStart')?.flag ?? false,
      repeatEnd: repeatEnd == null
          ? null
          : RepeatEnd(
              times: repeatEnd.integerWhere(
                (n) => n >= 2,
                'a repeat plays twice or more',
              ),
            ),
      volta: volta == null ? null : _volta(volta),
      navigation: Seq([
        for (final mark in json.maybe('navigation')?.list ?? const <_In>[])
          _navigation(mark),
      ]),
      rehearsal: json.maybe('rehearsal')?.string,
      tempos: Seq(
        _ordered(
          json.maybe('tempos')?.list ?? const [],
          (mark) => TempoMark(
            offset: mark['at'].inside(length),
            tempo: Tempo(
              mark['bpm'].positive,
              beat: mark.maybe('beat')?.noteValue ?? NoteValue.quarter,
            ),
            text: mark.maybe('text')?.string,
            showMetronome: mark.maybe('metronome')?.flag ?? true,
          ),
          (before, after) => before.offset < after.offset,
          'tempo marks are in time order, one at a time',
        ),
      ),
      breakBefore: json.maybe('break')?.name(LayoutBreak.values),
      keyDisplay:
          json.maybe('keyDisplay')?.name(SignatureDisplay.values) ??
          SignatureDisplay.auto,
      meterDisplay:
          json.maybe('meterDisplay')?.name(SignatureDisplay.values) ??
          SignatureDisplay.auto,
      staves: Seq([
        for (final (k, (staff, instrument)) in staves.indexed)
          _staffMeasure(
            entries[k],
            staff,
            instrument,
            previous?.staves[k].clefAtEnd,
            length,
          ),
      ]),
    );
  }

  Meter _meter(_In column) {
    final text = column['meter'];
    final match =
        RegExp(r'^([1-9]\d{0,2}(?:\+[1-9]\d{0,2})*)/(\d{1,3})$')
            .firstMatch(text.string) ??
        text.fail('expected a meter such as "3+2+2/8"');
    final unit = int.parse(match[2]!);
    if (!const {1, 2, 4, 8, 16, 32, 64, 128}.contains(unit)) {
      text.fail('the unit is a power of two up to 128');
    }
    return Meter(
      [for (final group in match[1]!.split('+')) int.parse(group)],
      unit,
      symbol:
          column.maybe('meterSymbol')?.name(MeterSymbol.values) ??
          MeterSymbol.numeric,
    );
  }

  Volta _volta(_In json) {
    const rule = 'an ending lists its passes from 1, in order';
    final endings = _ordered(
      json['endings'].list,
      (pass) => pass.integerWhere((n) => n >= 1, rule),
      (before, after) => before < after,
      rule,
    );
    if (endings.isEmpty) {
      json['endings'].fail(rule);
    }
    return Volta(endings, open: json.maybe('open')?.flag ?? false);
  }

  NavigationMark _navigation(_In json) {
    if (json.value is Map) {
      return Jump(
        json['jump'].name(JumpTarget.values),
        then: json.maybe('then')?.name(JumpThen.values) ?? JumpThen.toEnd,
        text: json.maybe('text')?.string,
      );
    }
    return switch (json.string) {
      'segno' => const Segno(),
      'coda' => const Coda(),
      'toCoda' => const ToCoda(),
      'fine' => const Fine(),
      _ => json.fail('expected segno, coda, toCoda, fine or a jump'),
    };
  }

  /// [staff]'s slice of a bar [length] long, whose clef defaults to
  /// [before].
  StaffMeasure _staffMeasure(
    _In json,
    StaffId staff,
    Instrument instrument,
    Clef? before,
    Length length,
  ) {
    final voices = _ordered(
      json['voices'].list,
      (voice) => _voice(voice, instrument, length),
      (before, after) => before.slot.index < after.slot.index,
      'voices are in order, each once',
    );
    if (voices.firstOrNull?.slot != VoiceSlot.one) {
      json['voices'].fail('voice one comes first');
    }
    return StaffMeasure(
      staff: staff,
      clef: before != null && json.maybe('clef') == null
          ? before
          : json['clef'].name(Clef.values),
      clefChanges: Seq(
        _ordered(
          json.maybe('clefChanges')?.list ?? const [],
          (change) {
            final at = change['at'].inside(length);
            if (at.isZero) {
              change['at'].fail('a clef change comes after the bar starts');
            }
            return ClefChange(at, change['clef'].name(Clef.values));
          },
          (before, after) => before.offset < after.offset,
          'clef changes are in time order, one at a time',
        ),
      ),
      directions: Seq(
        _ordered(
          json.maybe('directions')?.list ?? const [],
          (direction) => _direction(direction, length),
          (before, after) => before.offset <= after.offset,
          'directions are in time order',
        ),
      ),
      voices: Seq(voices),
    );
  }

  StaffDirection _direction(_In json, Length length) {
    final at = json['at'].inside(length);
    return switch (json.oneOf(const ['dynamic', 'text', 'chord'])) {
      'dynamic' => DynamicMark(at, json['dynamic'].name(Dynamic.values)),
      'text' => TextMark(
        at,
        json['text'].string,
        above: json.maybe('above')?.flag ?? true,
      ),
      _ => ChordSymbol(
        at,
        root: json['chord'].pitchName,
        quality: json.maybe('quality')?.string ?? '',
        bass: json.maybe('bass')?.pitchName,
      ),
    };
  }

  Voice _voice(_In json, Instrument instrument, Length length) {
    final slot = json['voice'].voice;
    final entries = json['items'].list;
    final items = [for (final item in entries) _item(item, instrument, length)];
    for (final (i, item) in items.indexed) {
      if (item is Gap && slot == VoiceSlot.one) {
        entries[i].fail('voice one has no gaps');
      }
      if (item is MeasureRest && items.length > 1) {
        entries[i].fail('a measure rest is alone in its voice');
      }
    }
    if (slot != VoiceSlot.one && items.every((item) => item is Gap)) {
      json['items'].fail('a voice other than one holds more than gaps');
    }
    final span = Length.sum(items.map((item) => item.span));
    if (span != length) {
      json['items'].fail(
        'spans ${span.wholeNotes}, bar is ${length.wholeNotes}',
      );
    }
    return Voice(slot: slot, items: Seq(items));
  }

  VoiceItem _item(_In json, Instrument instrument, Length length) =>
      switch (json.oneOf(const [
        'gap',
        'measureRest',
        'chord',
        'rest',
        'tuplet',
      ])) {
        'gap' => Gap(json['gap'].positiveLength),
        'measureRest' => MeasureRest(
          id: _event(json['measureRest']),
          span: length,
          articulations: _restMarks(json),
        ),
        _ => _content(json, instrument),
      };

  Content _content(_In json, Instrument instrument) =>
      switch (json.oneOf(const ['chord', 'rest', 'tuplet'])) {
        'chord' => _chord(json, instrument),
        'rest' => RestEvent(
          id: _event(json['rest']),
          value: json['value'].noteValue,
          articulations: _restMarks(json),
          hidden: json.maybe('hidden')?.flag ?? false,
        ),
        _ => _tuplet(json, instrument),
      };

  ChordEvent _chord(_In json, Instrument instrument) => ChordEvent(
    id: _event(json['chord']),
    value: json['value'].noteValue,
    notes: _heads(json['notes'], instrument),
    articulations: _articulationsOf(json),
    ornament: json.maybe('ornament')?.name(Ornament.values),
    bowing: json.maybe('bowing')?.name(Bowing.values),
    graces: Seq([
      for (final grace in json.maybe('graces')?.list ?? const <_In>[])
        GraceChord(
          id: _event(grace['id']),
          kind: grace['kind'].name(GraceKind.values),
          value: grace['value'].noteValue,
          notes: _heads(grace['notes'], instrument),
        ),
    ]),
    stem: json.maybe('stem')?.name(StemDirection.values) ?? StemDirection.auto,
    beam: json.maybe('beam')?.name(BeamMode.values) ?? BeamMode.auto,
    tremolo:
        json
            .maybe('tremolo')
            ?.integerWhere(
              (n) => n >= 0 && n <= 4,
              'tremolo strokes are 0 to 4',
            ) ??
        0,
    lyrics: Seq(
      _ordered(
        json.maybe('lyrics')?.list ?? const [],
        (lyric) => Lyric(
          verse: lyric['verse'].integerWhere(
            (n) => n >= 1,
            'verses count from 1',
          ),
          text: lyric['text'].string,
          syllabic:
              lyric.maybe('syllabic')?.name(Syllabic.values) ?? Syllabic.single,
          extend: lyric.maybe('extend')?.flag ?? false,
        ),
        (before, after) => before.verse < after.verse,
        'a chord has one lyric per verse, in order',
      ),
    ),
  );

  Seq<Note> _heads(_In json, Instrument instrument) {
    final notes = _ordered(
      json.list,
      (note) => _note(note, instrument),
      (before, after) => before.tone.compareTo(after.tone) < 0,
      'a chord lists its notes in order, each once',
    );
    if (notes.isEmpty) {
      json.fail('a chord has at least one note');
    }
    return Seq(notes);
  }

  Note _note(_In json, Instrument instrument) {
    final id = NoteId(_claim(_notes, json['id']));
    final tie = json.maybe('tie')?.flag ?? false;
    if (instrument.isPercussion) {
      final drum =
          json.maybe('drum') ?? json.fail('a percussion staff takes drums');
      if (instrument.soundOf(Drum(drum.string)) == null) {
        drum.fail('the kit has no ${drum.string}');
      }
      return DrumNote(id: id, drum: Drum(drum.string), tie: tie);
    }
    return PitchedNote(
      id: id,
      pitch: (json.maybe('pitch') ?? json.fail('a pitched staff takes pitches'))
          .pitch,
      tie: tie,
      accidental:
          json.maybe('accidental')?.name(AccidentalRequest.values) ??
          AccidentalRequest.auto,
      head: json.maybe('head')?.name(NoteHead.values) ?? NoteHead.normal,
      fingering: json
          .maybe('fingering')
          ?.integerWhere((n) => n >= 0, 'a finger number is 0 or more'),
      string: json
          .maybe('string')
          ?.integerWhere(
            (n) => n >= 0 && n < instrument.strings.length,
            'the instrument has no such string',
          ),
    );
  }

  Tuplet _tuplet(_In json, Instrument instrument) {
    final id = TupletId(_claim(_tuplets, json['tuplet']));
    final terms = [
      for (final term in json['ratio'].list)
        term.integerWhere((n) => n > 0, 'ratio terms are above 0'),
    ];
    if (terms.length != 2) {
      json['ratio'].fail('a ratio is [actual, normal]');
    }
    final unit = json['unit'].noteValue;
    final members = [
      for (final member in json['members'].list) _content(member, instrument),
    ];
    final written = Length.sum(members.map((member) => member.span));
    final expected = unit.length * Fraction(terms[0]);
    if (written != expected) {
      json['members'].fail(
        'members span ${written.wholeNotes}, expected ${expected.wholeNotes}',
      );
    }
    return Tuplet(
      id: id,
      ratio: TupletRatio(terms[0], terms[1]),
      unit: unit,
      members: Seq(members),
      bracket:
          json.maybe('bracket')?.name(TupletBracket.values) ??
          TupletBracket.auto,
    );
  }

  Set<Articulation> _articulationsOf(_In json) => Set.unmodifiable({
    for (final mark in json.maybe('articulations')?.list ?? const <_In>[])
      mark.name(Articulation.values),
  });

  Set<Articulation> _restMarks(_In json) {
    final marks = _articulationsOf(json);
    if (marks.any((mark) => mark != Articulation.fermata)) {
      json['articulations'].fail('a rest holds only a fermata');
    }
    return marks;
  }

  /// A spanner whose ends lie in [measures], which [bars] indexes by id.
  Spanner _spanner(
    _In json,
    List<MeasureColumn> measures,
    Map<MeasureId, int> bars,
    Set<StaffId> staves,
  ) {
    final id = SpannerId(_claim(_spanners, json['id']));
    final name = json['kind'];
    final kind = switch (name.string) {
      'slur' => Slur(dashed: json.maybe('dashed')?.flag ?? false),
      'crescendo' => const Hairpin(crescendo: true),
      'diminuendo' => const Hairpin(crescendo: false),
      'octave' => OctaveLine(json['shift'].name(OctaveShift.values)),
      'trill' => const TrillLine(),
      'tempo' => TempoLine(
        text: json['text'].string,
        factor: json['factor'].positive,
      ),
      'pedal' => const PedalLine(),
      'glissando' => const Glissando(),
      _ => name.fail(
        'expected one of slur, crescendo, diminuendo, octave, trill, tempo, '
        'pedal, glissando',
      ),
    };
    final staff = StaffId(json['staff'].integer);
    if (!staves.contains(staff)) {
      json['staff'].fail('no such staff');
    }
    final first = _point(json['from'], measures, bars);
    final last = _point(json['to'], measures, bars);
    bool precedes((int, ScorePoint) a, (int, ScorePoint) b) =>
        a.$1 < b.$1 || a.$1 == b.$1 && a.$2.offset < b.$2.offset;
    if (kind.joinsNotes && !precedes(first, last)) {
      json['to'].fail('a slur or glissando ends after it starts');
    }
    if (!kind.joinsNotes && precedes(last, first)) {
      json['to'].fail('a line cannot end before it starts');
    }
    return Spanner(
      id: id,
      kind: kind,
      staff: staff,
      voice: json.maybe('voice')?.voice,
      first: first.$2,
      last: last.$2,
    );
  }

  /// A point and the index of its bar.
  (int, ScorePoint) _point(
    _In json,
    List<MeasureColumn> measures,
    Map<MeasureId, int> bars,
  ) {
    final measure = MeasureId(json['measure'].integer);
    final bar = bars[measure] ?? json['measure'].fail('no such bar');
    return (bar, ScorePoint(measure, json['at'].inside(measures[bar].length)));
  }

  EventId _event(_In id) => EventId(_claim(_events, id));
}

/// [id]'s value, which must not be in [taken] yet.
int _claim(Set<int> taken, _In id) {
  final value = id.integer;
  return taken.add(value) ? value : id.fail('id $value is used twice');
}

/// [items] read one by one, refused for [rule] at the first that does not
/// come after the one before it by [inOrder].
List<T> _ordered<T>(
  List<_In> items,
  T Function(_In item) read,
  bool Function(T before, T after) inOrder,
  String rule,
) {
  final values = <T>[];
  for (final item in items) {
    final value = read(item);
    if (values.isNotEmpty && !inOrder(values.last, value)) {
      item.fail(rule);
    }
    values.add(value);
  }
  return values;
}

/// A value read from a file, and where it sits there, for errors.
final class _In {
  const _In(this.value, this.path);

  final Object? value;

  /// The JSON path of [value], such as `$.measures[12].staves[0]`.
  final String path;

  Never fail(String message) => throw ScoreFormatException(path, message);

  T _as<T extends Object>(String what) => switch (value) {
    final T typed => typed,
    null => fail('missing'),
    _ => fail('expected $what'),
  };

  _In operator [](String key) =>
      _In(_as<Map<String, Object?>>('an object')[key], '$path.$key');

  /// The member [key], or null when it is missing.
  _In? maybe(String key) {
    final member = this[key];
    return member.value == null ? null : member;
  }

  /// The one of [keys] present, refused unless exactly one is.
  String oneOf(List<String> keys) {
    final present = [
      for (final key in keys)
        if (maybe(key) != null) key,
    ];
    return present.length == 1
        ? present.single
        : fail('expected exactly one of ${keys.join(', ')}');
  }

  int get integer => _as<int>('an integer');

  int integerWhere(bool Function(int value) test, String rule) {
    final value = integer;
    return test(value) ? value : fail(rule);
  }

  String get string => _as<String>('a string');

  bool get flag => _as<bool>('true or false');

  List<_In> get list => [
    for (final (i, item) in _as<List<Object?>>('a list').indexed)
      _In(item, '$path[$i]'),
  ];

  T name<T extends Enum>(List<T> values) =>
      values.asNameMap()[string] ??
      fail('expected one of ${values.map((value) => value.name).join(', ')}');

  double get positive {
    final number = _as<num>('a number').toDouble();
    return number > 0 && number.isFinite
        ? number
        : fail('expected a number above 0');
  }

  int get midi =>
      integerWhere((n) => n >= 0 && n <= 127, 'a MIDI number is 0 to 127');

  VoiceSlot get voice => VoiceSlot
      .values[integerWhere((n) => n >= 1 && n <= 4, 'a voice is 1 to 4') - 1];

  Fraction get fraction {
    final match =
        RegExp(r'^(\d{1,9})(?:/([1-9]\d{0,8}))?$').firstMatch(string) ??
        fail('expected a fraction such as "3/8"');
    return Fraction(int.parse(match[1]!), int.parse(match[2] ?? '1'));
  }

  /// A time inside a bar [length] long.
  Moment inside(Length length) {
    final at = Moment(fraction);
    return at < Moment.zero + length ? at : fail('not inside the bar');
  }

  Length get positiveLength {
    final length = Length(fraction);
    return length.isPositive ? length : fail('expected a length above 0');
  }

  Length get barLength {
    final length = Length(fraction);
    return length.isPositive &&
            (length / DurationBase.oneTwentyEighth.length).denominator == 1
        ? length
        : fail('a bar holds a whole number of 128th notes');
  }

  NoteValue get noteValue {
    final text = string;
    final base = DurationBase.values
        .asNameMap()[text.replaceFirst(RegExp(r'\.{1,3}$'), '')];
    return base == null
        ? fail('expected a note value such as "quarter."')
        : NoteValue(base, dots: text.length - base.name.length);
  }

  Pitch get pitch => switch (_spelled) {
    (final name, final octave?) => Pitch(name.step, octave, name.alter),
    _ => fail('expected a pitch such as "F#4"'),
  };

  PitchName get pitchName => switch (_spelled) {
    (final name, null) => name,
    _ => fail('expected a pitch name such as "F#"'),
  };

  (PitchName, int?)? get _spelled {
    final match = _spelling.firstMatch(string);
    if (match == null) {
      return null;
    }
    final name = PitchName(
      Step.values.byName(match[1]!.toLowerCase()),
      _alters[match[2] ?? '']!,
    );
    return (name, match[3] == null ? null : int.parse(match[3]!));
  }
}
