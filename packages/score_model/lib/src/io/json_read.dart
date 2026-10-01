part of 'json.dart';

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
    final spanners = json.maybe('spanners')?.list ?? const <_In>[];
    final score = Score(
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
        for (final spanner in spanners)
          _spanner(spanner, measures, bars, {for (final (id, _) in staves) id}),
      ]),
    );
    for (final (i, spanner) in score.spanners.indexed) {
      if (score.isCollapsed(spanner)) {
        spanners[i]['to'].fail('a slur or glissando ends after it starts');
      }
    }
    return score;
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
      bank: json.maybe('bank')?.kept(bankProblem) ?? 0,
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
            json['key'].kept(keyProblem),
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
          : RepeatEnd(times: repeatEnd.kept(repeatProblem)),
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
              mark['bpm'].number(tempoProblem),
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
    final meter = Meter(
      [for (final group in match[1]!.split('+')) int.parse(group)],
      int.parse(match[2]!),
      symbol:
          column.maybe('meterSymbol')?.name(MeterSymbol.values) ??
          MeterSymbol.numeric,
    );
    return text.check(meter, meterProblem);
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
        _ => _content(json, instrument, 0),
      };

  /// [around] is how many tuplets hold the content.
  Content _content(_In json, Instrument instrument, int around) =>
      switch (json.oneOf(const ['chord', 'rest', 'tuplet'])) {
        'chord' => _chord(json, instrument),
        'rest' => RestEvent(
          id: _event(json['rest']),
          value: json['value'].noteValue,
          articulations: _restMarks(json),
          hidden: json.maybe('hidden')?.flag ?? false,
        ),
        _ => _tuplet(json, instrument, around),
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
      fingering: json.maybe('fingering')?.kept(fingerProblem),
      string: json
          .maybe('string')
          ?.integerWhere(
            (n) => n >= 0 && n < instrument.strings.length,
            'the instrument has no such string',
          ),
    );
  }

  Tuplet _tuplet(_In json, Instrument instrument, int around) {
    if (tupletDepthProblem(around + 1) case final problem?) {
      json.fail(problem);
    }
    final id = TupletId(_claim(_tuplets, json['tuplet']));
    final terms = [
      for (final term in json['ratio'].list) term.kept(ratioTermProblem),
    ];
    if (terms.length != 2) {
      json['ratio'].fail('a ratio is [actual, normal]');
    }
    final unit = json['unit'].noteValue;
    final members = [
      for (final member in json['members'].list)
        _content(member, instrument, around + 1),
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
        factor: json['factor'].number(factorProblem),
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
    final voice = json.maybe('voice')?.voice;
    if (kind.joinsNotes != (voice != null)) {
      json['voice'].fail(
        kind.joinsNotes
            ? 'a slur or glissando names its voice'
            : 'only a slur or glissando names a voice',
      );
    }
    return Spanner(
      id: id,
      kind: kind,
      staff: staff,
      voice: voice,
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

  /// [value], read from this member, refused with the rule it breaks.
  T check<T>(T value, String? Function(T value) rule) => switch (rule(value)) {
    final problem? => fail(problem),
    null => value,
  };

  int kept(String? Function(int value) rule) => check(integer, rule);

  double number(String? Function(double value) rule) =>
      check(_as<num>('a number').toDouble(), rule);

  int get midi => kept(midiProblem);

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

  Length get barLength => check(Length(fraction), barLengthProblem);

  NoteValue get noteValue {
    final text = string;
    final base = DurationBase.values
        .asNameMap()[text.replaceFirst(RegExp(r'\.{1,3}$'), '')];
    return base == null
        ? fail('expected a note value such as "quarter."')
        : check(
            NoteValue(base, dots: text.length - base.name.length),
            valueProblem,
          );
  }

  Pitch get pitch => switch (_spelled) {
    (final name, final octave?) => check(
      Pitch(name.step, octave, name.alter),
      pitchProblem,
    ),
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
