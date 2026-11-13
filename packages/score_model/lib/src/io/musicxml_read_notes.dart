part of 'musicxml_read.dart';

/// What the bar's last note that was not a grace left for a `<chord/>` note
/// to join.
sealed class _Last {
  const _Last();
}

final class _LastChord extends _Last {
  const _LastChord(this.record, this.raw);

  final ChordRecord record;

  /// The `<duration>` its first note writes.
  final Fraction raw;
}

final class _LastRest extends _Last {
  const _LastRest();
}

final class _LastCue extends _Last {
  const _LastCue();
}

/// A grace chord waiting for its principal chord. Its line ends wait with
/// it, since they attach to that chord.
final class _PendingGrace {
  _PendingGrace(this.record);

  final GraceRecord record;
  final marks = <void Function(EventRecord)>[];
}

/// A tuplet whose members are still being read.
final class _Frame {
  _Frame({
    required this.id,
    required this.ratio,
    required this.unit,
    required this.bracket,
    required this.onset,
    required this.source,
    required this.number,
    required this.scale,
  });

  final TupletId id;
  final TupletRatio ratio;

  /// Null until the members show it, when the file does not state it.
  final NoteValue? unit;

  final TupletBracket bracket;
  final Moment onset;

  /// The `<tuplet>` that opened it, or the `<time-modification>` of its
  /// first note when none did.
  final Source source;

  /// The number its stop must name, or null when the file marks no start
  /// and it closes once full.
  final String? number;

  /// Sounding length over written length inside it, enclosing tuplets
  /// included.
  final Fraction scale;

  final members = <LaneItem>[];

  /// The written length of [members].
  Length written = Length.zero;

  bool get implicit => number == null;
}

typedef _Modification = ({TupletRatio ratio, NoteValue? unit, Source source});

final List<NoteValue> _values = [
  for (final base in DurationBase.values)
    for (var dots = 0; dots <= 3; dots++)
      if (valueProblem(NoteValue(base, dots: dots)) == null)
        NoteValue(base, dots: dots),
];

NoteValue? _valueOf(Length length) =>
    _values.where((value) => value.length == length).firstOrNull;

extension on _BarReader {
  void _note(XmlElement note) {
    final index = part.notes++;
    if (note.getElement('grace') case final grace?) {
      _grace(note, grace, index);
      return;
    }
    lastGrace = null;
    final duration = _duration(note);
    final chord = note.getElement('chord');
    if (note.getElement('cue') != null) {
      if (chord == null) {
        final staff = _staff(note);
        lanes[_voice(note, staff)]?.graces.clear();
        _advance(duration.length, Source(duration.element));
      }
      last = const _LastCue();
      return;
    }
    if (chord != null) {
      switch (last) {
        case _LastCue():
          return;
        case _LastRest():
          Source(chord).refuse('a chord note follows a rest');
        case _LastChord(:final record, :final raw):
          if (duration.raw != raw) {
            Source(
              duration.element,
            ).refuse('a chord note lasts as long as its chord');
          }
          if (note.getElement('rest') == null) {
            _addNote(record, note, index);
          }
          return;
        case null:
          break;
      }
    }
    _event(note, index, duration);
  }

  void _event(
    XmlElement note,
    int index,
    ({XmlElement element, Fraction raw, Length length}) duration,
  ) {
    final staff = _staff(note);
    final lane = _lane(
      _voice(note, staff),
      staff,
      Source(note.getElement('voice') ?? note),
    );
    final record = lane.record;
    final onset = cursor;
    if (onset < record.end) {
      Source(note).refuse('overlaps the previous note in its voice');
    }
    final modification = _modification(note);
    final marks = _notations(note);
    final starts = [
      for (final mark in marks)
        if (mark.name.local == 'tuplet' && mark.getAttribute('type') == 'start')
          mark,
    ];
    if (lane.frames.lastOrNull case _Frame(implicit: true, :final ratio)
        when onset > record.end ||
            modification?.ratio != ratio ||
            starts.isNotEmpty) {
      _closeImplicit(lane);
    }
    if (onset > record.end && lane.frames.isNotEmpty) {
      Source(note).refuse('a gap inside a tuplet');
    }
    for (final start in starts) {
      _open(lane, start, modification, onset);
    }
    final scale =
        lane.frames.lastOrNull?.scale ??
        modification?.ratio.scale ??
        Fraction.one;
    final inTuplet = lane.frames.isNotEmpty || modification != null;

    final rest = note.getElement('rest');
    final type = note.getElement('type');
    final at = Source(duration.element);
    var value = type == null
        ? _valueOf(Length(duration.length.wholeNotes / scale))
        : _value(type, note.findElements('dot').length);
    var end = cursor + duration.length;
    if (type != null && value != null) {
      final exact = value.length.wholeNotes * scale;
      if (!storable(exact)) {
        at.refuse(unstorable);
      }
      if (inTuplet
          ? _near(duration.raw, exact)
          : exact == duration.length.wholeNotes) {
        end = cursor + Length(exact);
      } else if (rest != null && !inTuplet) {
        value = null;
      } else {
        at.refuse('the duration does not match the written value');
      }
    }
    if (value == null) {
      if (rest == null || inTuplet) {
        at.refuse('no note value has this duration');
      }
    } else if (lane.frames.isEmpty && modification != null) {
      lane.frames.add(
        _Frame(
          id: TupletId(part.ids.take()),
          ratio: modification.ratio,
          unit: modification.unit ?? value,
          bracket: TupletBracket.auto,
          onset: onset,
          source: modification.source,
          number: null,
          scale: scale,
        ),
      );
    }

    end = _storable(end, at);
    final id = EventId(part.ids.take());
    final EventRecord event;
    if (rest != null) {
      lane.graces.clear();
      event = RestRecord(
        onset: onset,
        end: end,
        id: id,
        note: Source(note),
        lane: record,
        value: value,
        typed: type != null,
        hidden: note.getAttribute('print-object') == 'no',
        measure: rest.getAttribute('measure') == 'yes',
        rest: Source(rest),
        durationSource: at,
      )..fermata = marks.any((mark) => mark.name.local == 'fermata');
      for (final emit in _lineMarks(marks, index)) {
        emit(event);
      }
      last = const _LastRest();
    } else {
      final chord = ChordRecord(
        onset: onset,
        end: end,
        id: id,
        note: Source(note),
        lane: record,
        value: value!,
        graces: [for (final grace in lane.graces) grace.record],
      );
      for (final grace in lane.graces) {
        for (final emit in grace.marks) {
          emit(chord);
        }
      }
      lane.graces.clear();
      if (part.joins case final joins?) {
        final beam = note
            .findElements('beam')
            .where((beam) => (beam.getAttribute('number') ?? '1') == '1')
            .firstOrNull
            ?.innerText
            .trim();
        joins[id] = beam == 'continue' || beam == 'end';
      }
      _addNote(chord, note, index);
      last = _LastChord(chord, duration.raw);
      event = chord;
    }

    final frame = lane.frames.lastOrNull;
    if (frame == null) {
      record.items.add(event);
    } else {
      frame
        ..members.add(event)
        ..written += value!.length;
    }
    cursor = end;
    if (cursor > furthest) {
      furthest = cursor;
    }
    record.end = end;
    if (frame
        case _Frame(implicit: true, :final unit?, :final written, :final ratio)
        when written == unit.length * Fraction(ratio.actual)) {
      _close(lane, unit);
    }
    for (final mark in marks) {
      if (mark.name.local == 'tuplet' && mark.getAttribute('type') == 'stop') {
        _stop(lane, mark);
      }
    }
  }

  /// Whether [raw] divisions are less than one division from [exact] whole
  /// notes, which is as close as a file can write a tuplet's length when
  /// its divisions do not divide it.
  bool _near(Fraction raw, Fraction exact) {
    final expected = exact * part.perWhole!;
    if (!storable(expected)) {
      return false;
    }
    final off = raw - expected;
    return (off.isNegative ? -off : off) < Fraction.one;
  }

  NoteValue _value(XmlElement type, int dots) {
    final base =
        baseByTypeName[type.innerText.trim()] ??
        Source(type).refuse('no such note type');
    if (dots > 3) {
      Source(type).refuse('a value has at most 3 dots');
    }
    final value = NoteValue(base, dots: dots);
    if (valueProblem(value) case final problem?) {
      Source(type).refuse(problem);
    }
    return value;
  }

  _Modification? _modification(XmlElement note) {
    final element = note.getElement('time-modification');
    if (element == null) {
      return null;
    }
    final type = element.getElement('normal-type');
    return (
      ratio: TupletRatio(
        _term(element.getElement('actual-notes'), element, 'actual-notes'),
        _term(element.getElement('normal-notes'), element, 'normal-notes'),
      ),
      unit: type == null
          ? null
          : _value(type, element.findElements('normal-dot').length),
      source: Source(element),
    );
  }

  /// One term of a tuplet ratio, from [parent]'s child [element].
  int _term(XmlElement? element, XmlElement parent, String name) {
    if (element == null) {
      Source(parent).missing(name);
    }
    final term =
        integerOf(element.innerText) ??
        Source(element).refuse('expected an integer');
    if (ratioTermProblem(term) case final problem?) {
      Source(element).refuse(problem);
    }
    return term;
  }

  void _open(
    _Lane lane,
    XmlElement tuplet,
    _Modification? modification,
    Moment onset,
  ) {
    final at = Source(tuplet);
    if (tupletDepthProblem(lane.frames.length + 1) case final problem?) {
      at.refuse(problem);
    }
    final actual = tuplet.getElement('tuplet-actual');
    final normal = tuplet.getElement('tuplet-normal');
    final TupletRatio ratio;
    if ((
          actual?.getElement('tuplet-number'),
          normal?.getElement('tuplet-number'),
        )
        case (final actualNumber?, final normalNumber?)) {
      ratio = TupletRatio(
        _term(actualNumber, actual!, 'tuplet-number'),
        _term(normalNumber, normal!, 'tuplet-number'),
      );
    } else if (modification == null) {
      at.missing('tuplet-actual');
    } else {
      ratio = _within(modification.ratio, lane.frames, at);
    }
    final scale = (lane.frames.lastOrNull?.scale ?? Fraction.one) * ratio.scale;
    if (!storable(scale)) {
      at.refuse(unstorable);
    }
    final type = actual?.getElement('tuplet-type');
    lane.frames.add(
      _Frame(
        id: TupletId(part.ids.take()),
        ratio: ratio,
        unit: type == null
            ? null
            : _value(type, actual!.findElements('tuplet-dot').length),
        bracket: switch (tuplet.getAttribute('bracket')) {
          'yes' => TupletBracket.shown,
          'no' => TupletBracket.hidden,
          _ => TupletBracket.auto,
        },
        onset: onset,
        source: at,
        number: tuplet.getAttribute('number') ?? '1',
        scale: scale,
      ),
    );
  }

  /// The ratio of a tuplet inside [frames] whose notes carry [whole], the
  /// ratio of every enclosing tuplet multiplied together.
  TupletRatio _within(TupletRatio whole, List<_Frame> frames, Source at) {
    var actual = 1;
    var normal = 1;
    for (final frame in frames) {
      actual *= frame.ratio.actual;
      normal *= frame.ratio.normal;
      if (!storable(Fraction(actual)) || !storable(Fraction(normal))) {
        at.refuse(unstorable);
      }
    }
    if (whole.actual % actual == 0 && whole.normal % normal == 0) {
      return TupletRatio(whole.actual ~/ actual, whole.normal ~/ normal);
    }
    final scale = whole.scale / Fraction(normal, actual);
    return TupletRatio(scale.denominator, scale.numerator);
  }

  void _stop(_Lane lane, XmlElement stop) {
    final frame = lane.frames.lastOrNull;
    if (frame == null || frame.number != (stop.getAttribute('number') ?? '1')) {
      Source(stop).refuse('stops a tuplet that is not open');
    }
    final filled = Fraction(frame.ratio.actual);
    final stated = frame.unit;
    if (stated != null && stated.length * filled != frame.written) {
      frame.source.refuse("the tuplet's notes do not fill it");
    }
    _close(
      lane,
      stated ??
          _values
              .where((value) => value.length * filled == frame.written)
              .firstOrNull ??
          frame.source.refuse('no note value fits the tuplet'),
    );
  }

  /// Closes the tuplet the file never marked, taking as its unit the value
  /// its members add up to a whole number of.
  void _closeImplicit(_Lane lane) {
    final frame = lane.frames.last;
    final filled = Fraction(frame.ratio.actual);
    _close(
      lane,
      _values
              .where((value) => value.length * filled == frame.written)
              .firstOrNull ??
          frame.source.refuse('the tuplet never stops in its bar'),
    );
  }

  void _close(_Lane lane, NoteValue unit) {
    final frame = lane.frames.removeLast();
    final span = unit.length * Fraction(frame.ratio.normal);
    if (!storable(span.wholeNotes)) {
      frame.source.refuse(unstorable);
    }
    final tuplet = TupletRecord(
      onset: frame.onset,
      end: lane.record.end,
      id: frame.id,
      ratio: frame.ratio,
      unit: unit,
      members: frame.members,
      bracket: frame.bracket,
    );
    final parent = lane.frames.lastOrNull;
    if (parent == null) {
      lane.record.items.add(tuplet);
    } else {
      parent
        ..members.add(tuplet)
        ..written += span;
    }
  }

  void _grace(XmlElement note, XmlElement grace, int index) {
    if (note.getElement('cue') != null || note.getElement('rest') != null) {
      return;
    }
    final marks = _notations(note);
    var pending = note.getElement('chord') == null ? null : lastGrace;
    if (pending == null) {
      final staff = _staff(note);
      final lane = _lane(
        _voice(note, staff),
        staff,
        Source(note.getElement('voice') ?? note),
      );
      final type = note.getElement('type');
      pending = _PendingGrace(
        GraceRecord(
          id: EventId(part.ids.take()),
          kind: grace.getAttribute('slash') == 'yes'
              ? GraceKind.acciaccatura
              : GraceKind.appoggiatura,
          value: type == null
              ? NoteValue.eighth
              : _value(type, note.findElements('dot').length),
        ),
      );
      lane.graces.add(pending);
      lastGrace = pending;
    }
    pending.record.notes.add(_tone(note, marks));
    pending.marks.addAll(_lineMarks(marks, index));
  }

  List<XmlElement> _notations(XmlElement note) => [
    for (final notations in note.findElements('notations'))
      ...notations.childElements,
  ];

  /// Reads [note] into [chord]: its tone, and the marks the chord holds
  /// once, where the first note to state one decides.
  void _addNote(ChordRecord chord, XmlElement note, int index) {
    final marks = _notations(note);
    chord.notes.add(_tone(note, marks));
    final ornaments = [
      for (final mark in marks)
        if (mark.name.local == 'ornaments') ...mark.childElements,
    ];
    // A trill-mark beside the start of a wavy line is that line's sign.
    final lined = ornaments.any(
      (ornament) =>
          ornament.name.local == 'wavy-line' &&
          ornament.getAttribute('type') == 'start',
    );
    for (final ornament in ornaments) {
      final name = ornament.name.local;
      if (name == 'tremolo') {
        if ((ornament.getAttribute('type') ?? 'single') != 'single') {
          continue;
        }
        final strokes =
            integerOf(ornament.innerText) ??
            Source(ornament).refuse('expected an integer');
        if (strokes > 4) {
          Source(ornament).refuse('more than 4 tremolo strokes');
        }
        if (chord.tremolo == 0 && strokes > 0) {
          chord.tremolo = strokes;
        }
      } else if (!(lined && name == 'trill-mark')) {
        chord.ornament ??= ornamentByName[name];
      }
    }
    for (final mark in marks) {
      switch (mark.name.local) {
        case 'fermata':
          chord.articulations.add(Articulation.fermata);
        case 'articulations':
          chord.articulations.addAll(
            mark.childElements
                .map((child) => articulationByName[child.name.local])
                .nonNulls,
          );
        case 'technical':
          for (final child in mark.childElements) {
            switch (child.name.local) {
              case 'up-bow':
                chord.bowing ??= Bowing.up;
              case 'down-bow':
                chord.bowing ??= Bowing.down;
              case 'harmonic':
                chord.articulations.add(Articulation.harmonic);
            }
          }
      }
    }
    if (chord.stem == StemDirection.auto) {
      chord.stem = switch (note.getElement('stem')?.innerText.trim()) {
        'up' => StemDirection.up,
        'down' => StemDirection.down,
        _ => StemDirection.auto,
      };
    }
    for (final (i, lyric) in note.findElements('lyric').indexed) {
      final texts = [
        for (final text in lyric.findElements('text')) text.innerText,
      ];
      final number = integerOf(lyric.getAttribute('number'));
      final verse = number != null && number >= 1 ? number : i + 1;
      if (texts.isEmpty || chord.lyrics.any((lyric) => lyric.verse == verse)) {
        continue;
      }
      chord.lyrics.add(
        Lyric(
          verse: verse,
          text: texts.join('‿'),
          syllabic:
              Syllabic.values.asNameMap()[lyric
                  .getElement('syllabic')
                  ?.innerText
                  .trim()] ??
              Syllabic.single,
          extend: lyric
              .findElements('extend')
              .any((extend) => extend.getAttribute('type') != 'stop'),
        ),
      );
    }
    for (final emit in _lineMarks(marks, index)) {
      emit(chord);
    }
  }

  /// The pitch or drum of [note], with the marks each note of a chord
  /// holds for itself among its notation [marks].
  NoteRecord _tone(XmlElement note, List<XmlElement> marks) {
    final id = NoteId(part.ids.take());
    final NoteRecord record;
    if (note.getElement('pitch') case final pitch?) {
      if (part.kit.isNotEmpty) {
        Source(pitch).refuse('a pitched note in a percussion part');
      }
      record = _pitched(id, note, pitch, marks);
    } else {
      final unpitched =
          note.getElement('unpitched') ?? Source(note).missing('pitch');
      record = DrumRecord(id: id, drum: _drum(note, unpitched));
    }
    for (final tie in [
      ...note.findElements('tie'),
      ...marks.where((mark) => mark.name.local == 'tied'),
    ]) {
      switch (tie.getAttribute('type')) {
        case 'start':
          record.tieStart = true;
        case 'stop':
          record.tieStop = true;
        case 'let-ring':
          record.letRing = true;
      }
    }
    return record;
  }

  PitchedRecord _pitched(
    NoteId id,
    XmlElement note,
    XmlElement pitch,
    List<XmlElement> marks,
  ) {
    final record = PitchedRecord(
      id: id,
      written: _pitch(pitch),
      source: Source(pitch),
      head:
          headByName[note.getElement('notehead')?.innerText.trim()] ??
          NoteHead.normal,
    );
    if (note.getElement('accidental') case final accidental?) {
      part.printed[id] =
          accidental.getAttribute('parentheses') == 'yes' ||
          accidental.getAttribute('cautionary') == 'yes';
    }
    for (final mark in marks) {
      if (mark.name.local != 'technical') {
        continue;
      }
      for (final child in mark.childElements) {
        final number = integerOf(child.innerText);
        if (number == null) {
          continue;
        }
        switch (child.name.local) {
          case 'fingering' when fingerProblem(number) == null:
            record.fingering ??= number;
          case 'string' when number >= 1 && number <= part.strings.length:
            record.string ??= number;
        }
      }
    }
    return record;
  }

  Drum _drum(XmlElement note, XmlElement unpitched) {
    final at = Source(unpitched);
    if (part.kit.isEmpty) {
      at.refuse('no drum instrument for this part');
    }
    final instrument = note.getElement('instrument');
    final drum =
        (instrument == null
            ? (part.kit.length == 1 ? part.kit.single : null)
            : part.kit
                  .where((drum) => drum.id == instrument.getAttribute('id'))
                  .firstOrNull) ??
        at.refuse('the note names no drum of the kit');
    if (drum.position == null) {
      final step = unpitched.getElement('display-step');
      final octave = unpitched.getElement('display-octave');
      final position = Pitch(
        step == null ? Step.b : _step(step),
        octave == null ? 4 : _octave(octave),
      );
      if (pitchProblem(position) case final problem?) {
        at.refuse(problem);
      }
      drum
        ..position = position
        ..head =
            headByName[note.getElement('notehead')?.innerText.trim()] ??
            NoteHead.normal;
    }
    return Drum(drum.name);
  }

  /// The slur, glissando and trill line ends among a note's notation
  /// [marks], each waiting for the event its note belongs to. [index] is
  /// the note's place among the part's notes.
  List<void Function(EventRecord)> _lineMarks(
    List<XmlElement> marks,
    int index,
  ) => [
    for (final mark in marks)
      for (final line
          in mark.name.local == 'ornaments'
              ? mark.findElements('wavy-line')
              : [mark])
        ?_lineMark(line, index),
  ];

  void Function(EventRecord)? _lineMark(XmlElement line, int index) {
    final name = line.name.local;
    final number = line.getAttribute('number') ?? '1';
    final kind = switch (name) {
      'slur' => Slur(dashed: line.getAttribute('line-type') == 'dashed'),
      'glissando' => const Glissando(),
      'wavy-line' => const TrillLine(),
      _ => null,
    };
    if (kind == null) {
      return null;
    }
    return switch (line.getAttribute('type')) {
      'start' => (event) => part.start(
        name,
        number,
        kind,
        EventAnchor(bar, event, index),
      ),
      'stop' => (event) => part.stop(
        name,
        number,
        EventAnchor(bar, event, index),
      ),
      _ => null,
    };
  }
}
