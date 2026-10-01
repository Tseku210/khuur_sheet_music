/// MusicXML 4.0 export, as a `score-partwise` document.
///
/// Each part is written bar by bar. Inside a bar, each staff is written
/// voice by voice, with `<backup>` to the bar start before each voice and a
/// secondary voice's [Gap]s as `<forward>`. Directions, chord symbols and
/// mid-bar clef changes go in voice one's stream at their times, reached
/// with `<forward>` and `<backup>` when they fall inside a note.
///
/// Pitches are written as the part reads them, so a transposing part
/// carries `<transpose>`. Accidentals, ties, beams and tuplet brackets come
/// from the measure views, as layout draws them. Tempo, rehearsal and
/// navigation marks are written once, on the top staff of the first shown
/// part. A hidden part is kept, with its staves marked unprinted.
///
/// A slur, glissando or trill line is written on the notes at its ends. A
/// hairpin, octave line, pedal line or tempo line is a direction at its
/// first point and a stop after the event its last point falls in. Numbers
/// are reused once a spanner of the same element in the part has stopped.
///
/// A string instrument's open strings are its staves' tunings.
///
/// Some of the model has no MusicXML home and is left out: an instrument's
/// key, range and clef, a tempo line's factor, a
/// [SignatureDisplay.noCourtesy], and an [AccidentalRequest.never].
library;

import 'package:xml/xml.dart';

import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../refs.dart';
import '../score.dart';
import '../seq.dart';
import '../time.dart';
import '../views.dart';
import 'musicxml_names.dart';

/// [score] as a MusicXML 4.0 partwise document.
String scoreToMusicXml(Score score) {
  final root = _Export(score).document();
  final text = root.toXmlString(
    pretty: true,
    indent: '  ',
    preserveWhitespace: (node) =>
        node is XmlElement && node.children.every((child) => child is XmlText),
  );
  return '$_prologue$text\n';
}

const _prologue =
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE score-partwise PUBLIC '
    '"-//Recordare//DTD MusicXML 4.0 Partwise//EN" '
    '"http://www.musicxml.org/dtds/partwise.dtd">\n';

/// A time in the score: bar index and offset in that bar.
/// A spanner end: its bar, its time there, and the stream it is written in
/// within the bar's part, staff by staff and voice by voice.
typedef _At = ({int bar, int stream, Moment at});

int _compare(_At a, _At b) =>
    a.bar != b.bar ? a.bar - b.bar : a.at.compareTo(b.at);

bool _writtenBefore(_At a, _At b) => a.bar != b.bar
    ? a.bar < b.bar
    : a.stream != b.stream
    ? a.stream < b.stream
    : a.at < b.at;

/// Where a spanner's ends are written. A spanner written on notes has the
/// events that carry its ends in `from` and `to`; a direction spanner has
/// neither.
typedef _Ends = ({
  Spanner spanner,
  _At start,
  _At stop,
  EventId? from,
  EventId? to,
});

final class _Export {
  _Export(this.score)
    : shown = score.copyWith(
        parts: Seq([
          for (final part in score.parts) part.copyWith(hidden: false),
        ]),
      );

  final Score score;

  /// [score] with every part shown, so the views hold every staff.
  final Score shown;

  late final List<MeasureView> views = [
    for (final column in shown.measures) shown.measureView(column.id),
  ];
  late final List<_Ends> ends = [
    for (final spanner in score.spanners) _endsOf(spanner),
  ];
  late final Map<SpannerId, int> numbers = _numbers();

  /// Divisions of a quarter note that make every time and length a whole
  /// number.
  late final int divisions = _divisions();

  /// Notes a tie lands on.
  late final Set<NoteId> tieStops = {
    for (final view in views)
      for (final staff in view.staves)
        for (final tie in staff.ties) ?tie.to?.note,
  };

  /// The part that carries tempo, rehearsal and navigation marks.
  late final PartId marksPart =
      (score.parts.where((part) => !part.hidden).firstOrNull ??
              score.parts.first)
          .id;

  /// The first bar is short, so it is numbered 0.
  late final bool pickup =
      score.measures.first.length < score.measures.first.meter.length;

  XmlElement document() {
    final meta = score.meta;
    return _el(
      'score-partwise',
      [
        if (meta.title.isNotEmpty)
          _el('work', [_text('work-title', meta.title)]),
        _el('identification', [
          if (meta.composer.isNotEmpty)
            _text('creator', meta.composer, {'type': 'composer'}),
          if (meta.lyricist.isNotEmpty)
            _text('creator', meta.lyricist, {'type': 'lyricist'}),
          if (meta.copyright.isNotEmpty) _text('rights', meta.copyright),
          _el('encoding', [
            _text('software', 'simple_sheet_music'),
            _el('supports', const [], {'element': 'accidental', 'type': 'yes'}),
            _el('supports', const [], {'element': 'beam', 'type': 'yes'}),
            for (final attribute in ['new-page', 'new-system'])
              _el('supports', const [], {
                'element': 'print',
                'attribute': attribute,
                'type': 'yes',
                'value': 'yes',
              }),
          ]),
        ]),
        if (meta.subtitle.isNotEmpty)
          _el(
            'credit',
            [
              _text('credit-type', 'subtitle'),
              _text('credit-words', meta.subtitle),
            ],
            {'page': '1'},
          ),
        _el('part-list', [
          for (final (p, part) in score.parts.indexed) _scorePart(part, _id(p)),
        ]),
        for (final p in Iterable<int>.generate(score.parts.length))
          _el(
            'part',
            [
              for (final bar in Iterable<int>.generate(views.length))
                _measure(p, bar),
            ],
            {'id': _id(p)},
          ),
      ],
      {'version': '4.0'},
    );
  }

  static String _id(int part) => 'P${part + 1}';

  XmlElement _scorePart(Part part, String id) {
    final instrument = part.instrument;
    final sounds = instrument.isPercussion
        ? [for (final drum in instrument.drums) (drum.name, drum.midiKey)]
        : [(part.name, null)];
    return _el(
      'score-part',
      [
        _text('part-name', part.name),
        if (part.shortName.isNotEmpty)
          _text('part-abbreviation', part.shortName),
        for (final (i, (name, _)) in sounds.indexed)
          _el(
            'score-instrument',
            [
              _text('instrument-name', name),
            ],
            {'id': '$id-I${i + 1}'},
          ),
        for (final (i, (_, key)) in sounds.indexed)
          _el(
            'midi-instrument',
            [
              if (key != null) _text('midi-channel', '10'),
              if (instrument.bank != 0)
                _text('midi-bank', '${instrument.bank + 1}'),
              _text('midi-program', '${instrument.program + 1}'),
              if (key != null) _text('midi-unpitched', '${key + 1}'),
            ],
            {'id': '$id-I${i + 1}'},
          ),
      ],
      {'id': id},
    );
  }

  XmlElement _measure(int p, int bar) {
    final part = shown.parts[p];
    final view = views[bar];
    final staves = [
      for (final staff in part.staves)
        view.staves.firstWhere((s) => s.source.staff == staff.id),
    ];
    return _el(
      'measure',
      [
        if (view.column.breakBefore case final LayoutBreak layoutBreak)
          _el('print', const [], {
            layoutBreak == LayoutBreak.page ? 'new-page' : 'new-system': 'yes',
          }),
        ?_leftBarline(view),
        ?_attributes(p, bar, view, staves),
        ..._music(p, bar, view, staves),
        ?_rightBarline(view),
      ],
      {
        'number': '${pickup ? bar : bar + 1}',
        'implicit': pickup && bar == 0 ? 'yes' : null,
      },
    );
  }

  XmlElement? _attributes(
    int p,
    int bar,
    MeasureView view,
    List<StaffView> staves,
  ) {
    final part = score.parts[p];
    final multi = part.staves.length > 1;
    final transposition = part.instrument.transposition;
    final strings = part.instrument.strings;
    final children = [
      if (bar == 0) _text('divisions', '$divisions'),
      if (view.printsKey)
        _key(staves.first.writtenKey)
      else if (bar > 0 &&
          score.measures[bar - 1].key.mode != view.column.key.mode)
        _key(staves.first.writtenKey, printed: false),
      if (view.printsMeter) _time(view.column.meter),
      if (bar == 0 && multi) _text('staves', '${part.staves.length}'),
      for (final (k, staff) in staves.indexed)
        if (staff.clefChanged) _clef(staff.clef, multi ? k + 1 : null),
      if (bar == 0)
        for (final (k, staff) in part.staves.indexed)
          if (staff.lines != 5 || part.hidden || strings.isNotEmpty)
            _el(
              'staff-details',
              [
                if (staff.lines != 5) _text('staff-lines', '${staff.lines}'),
                for (final (i, string) in strings.indexed)
                  _el(
                    'staff-tuning',
                    [
                      _text('tuning-step', string.step.name.toUpperCase()),
                      if (string.alter != Alter.natural)
                        _text(
                          'tuning-alter',
                          _number(string.alter.quarterTones / 2),
                        ),
                      _text('tuning-octave', '${string.octave}'),
                    ],
                    {'line': '${i + 1}'},
                  ),
              ],
              {
                'number': multi ? '${k + 1}' : null,
                'print-object': part.hidden ? 'no' : null,
              },
            ),
      if (bar == 0 && transposition != Interval.unison)
        _transpose(transposition),
    ];
    return children.isEmpty ? null : _el('attributes', children);
  }

  /// The staves of one bar of part [p], in time order per voice, with each
  /// staff's directions woven into voice one.
  List<XmlNode> _music(
    int p,
    int bar,
    MeasureView view,
    List<StaffView> staves,
  ) {
    final nodes = <XmlNode>[];
    var cursor = Moment.zero;
    void moveTo(Moment target, [List<XmlElement> gap = const []]) {
      if (target > cursor) {
        nodes.add(_el('forward', [_duration(cursor.until(target)), ...gap]));
      } else if (target < cursor) {
        nodes.add(_el('backup', [_duration(target.until(cursor))]));
      }
      cursor = target;
    }

    for (final (k, staff) in staves.indexed) {
      final items = _staffItems(p, bar, view, staff, k);
      var next = 0;
      void flush(Moment until) {
        for (; next < items.length && items[next].$1 <= until; next++) {
          moveTo(items[next].$1);
          nodes.add(items[next].$2);
        }
      }

      for (final voice in staff.voices) {
        final write = _writer(p, staff, k, voice);
        moveTo(Moment.zero);
        for (final timed in voice.events) {
          if (voice.slot == VoiceSlot.one) {
            flush(timed.onset);
            moveTo(timed.onset);
          } else {
            moveTo(timed.onset, [
              _text('voice', '${_voice(k, voice)}'),
              ?_staff(staff, k),
            ]);
          }
          nodes.addAll(write(timed));
          cursor = timed.onset + timed.duration;
        }
        if (voice.slot == VoiceSlot.one) {
          flush(Moment.zero + view.column.length);
        }
      }
    }
    return nodes;
  }

  static int _voice(int staffIndex, VoiceView voice) =>
      staffIndex * 4 + voice.slot.index + 1;

  static XmlElement? _staff(StaffView staff, int k) =>
      staff.part.staves.length > 1 ? _text('staff', '${k + 1}') : null;

  /// What staff [k] of part [p] shows at times of its own in [bar]: spanner
  /// stops, clef changes, score marks, directions and spanner starts, in
  /// that order where they share a time.
  List<(Moment, XmlElement)> _staffItems(
    int p,
    int bar,
    MeasureView view,
    StaffView staff,
    int k,
  ) {
    final column = view.column;
    final marks = k == 0 && score.parts[p].id == marksPart;
    final lines = [
      for (final line in ends)
        if (line.from == null && line.spanner.staff == staff.source.staff) line,
    ];
    final items = [
      for (final line in lines)
        if (line.stop.bar == bar)
          (line.stop.at, _line(line, start: false, staff: _staff(staff, k))),
      for (final change in staff.source.clefChanges)
        (
          change.offset,
          _el('attributes', [
            _clef(change.clef, staff.part.staves.length > 1 ? k + 1 : null),
          ]),
        ),
      if (marks) ...[
        if (column.rehearsal case final String text)
          (
            Moment.zero,
            _direction(
              [_text('rehearsal', text)],
              above: true,
              staff: _staff(staff, k),
            ),
          ),
        for (final mark in column.navigation)
          if (_opensBar(mark))
            (Moment.zero, _navigation(mark, _staff(staff, k))),
        for (final tempo in column.tempos)
          (tempo.offset, _tempo(tempo, _staff(staff, k))),
      ],
      for (final direction in staff.source.directions)
        (direction.offset, _staffDirection(direction, _staff(staff, k))),
      for (final line in lines)
        if (line.start.bar == bar)
          (line.start.at, _line(line, start: true, staff: _staff(staff, k))),
      if (marks)
        for (final mark in column.navigation)
          if (!_opensBar(mark))
            (Moment.zero + column.length, _navigation(mark, _staff(staff, k))),
    ];
    final ordered = [...items.indexed]
      ..sort((a, b) {
        final byTime = a.$2.$1.compareTo(b.$2.$1);
        return byTime != 0 ? byTime : a.$1 - b.$1;
      });
    return [for (final (_, item) in ordered) item];
  }

  /// Writes the `<note>`s of each event of [voice] on staff [k] of part
  /// [p].
  List<XmlElement> Function(TimedEvent) _writer(
    int p,
    StaffView staff,
    int k,
    VoiceView voice,
  ) {
    final part = staff.part;
    final number = '${_voice(k, voice)}';
    final beams = _beams(voice);
    final tuplets = {for (final view in voice.tuplets) view.tuplet.id: view};
    final tupletMarks = <EventId, List<XmlElement>>{};
    for (final view in [...voice.tuplets]..sort((a, b) => a.depth - b.depth)) {
      (tupletMarks[view.events.first] ??= []).add(_tuplet(view, start: true));
    }
    for (final view in [...voice.tuplets]..sort((a, b) => b.depth - a.depth)) {
      (tupletMarks[view.events.last] ??= []).add(_tuplet(view, start: false));
    }
    final ties = {for (final tie in staff.ties) tie.from: tie};

    List<XmlElement> head(Note note) => switch (note) {
      PitchedNote(:final pitch) => [
        _pitch(
          pitch.transpose(
            -part.instrument.transposition,
            key: staff.writtenKey,
          ),
        ),
      ],
      DrumNote(:final drum) => [
        _el('unpitched', [
          _text(
            'display-step',
            part.instrument.soundOf(drum)!.position.step.name.toUpperCase(),
          ),
          _text(
            'display-octave',
            '${part.instrument.soundOf(drum)!.position.octave}',
          ),
        ]),
      ],
    };

    XmlElement? instrument(Note note) => switch (note) {
      PitchedNote() => null,
      DrumNote(:final drum) => _el('instrument', const [], {
        'id':
            '${_id(p)}-I'
            '${part.instrument.drums.indexOf(part.instrument.soundOf(drum)!) + 1}',
      }),
    };

    XmlElement? modification(TimedEvent timed, NoteValue value) {
      if (timed.tuplets.isEmpty) {
        return null;
      }
      final enclosing = [for (final id in timed.tuplets) tuplets[id]!.tuplet];
      final unit = enclosing.last.unit;
      return _el('time-modification', [
        _text(
          'actual-notes',
          '${enclosing.fold(1, (n, t) => n * t.ratio.actual)}',
        ),
        _text(
          'normal-notes',
          '${enclosing.fold(1, (n, t) => n * t.ratio.normal)}',
        ),
        if (unit != value) ...[
          _text('normal-type', typeName(unit.base)),
          for (var i = 0; i < unit.dots; i++) _el('normal-dot'),
        ],
      ]);
    }

    /// Notations on the first note of [event] (or on a rest) and on each
    /// note of a chord.
    XmlElement? notations(Event event, {Note? note, required bool first}) {
      final chord = event is ChordEvent ? event : null;
      final tie = note == null ? null : ties[note.id];
      final onEvent = first ? _onEvent(event.id) : const <_Mark>[];
      final trillStarts = onEvent.any(
        (mark) => mark.$1.kind is TrillLine && mark.$2,
      );
      final ornaments = [
        if (chord?.ornament case final Ornament ornament when first)
          _el(ornamentName(ornament)),
        if (trillStarts && chord?.ornament != Ornament.trill) _el('trill-mark'),
        for (final (spanner, start) in onEvent)
          if (spanner.kind is TrillLine) _spannerMark(spanner, start: start),
        if (first && chord != null && chord.tremolo > 0)
          _text('tremolo', '${chord.tremolo}', {'type': 'single'}),
      ];
      final technical = [
        if (chord?.bowing case final Bowing bowing when first)
          _el(bowing == Bowing.up ? 'up-bow' : 'down-bow'),
        if (first && event.articulations.contains(Articulation.harmonic))
          _el('harmonic'),
        if (note case PitchedNote(:final fingering?))
          _text('fingering', '$fingering'),
        if (note case PitchedNote(:final string?))
          _text('string', '${part.instrument.strings.length - string}'),
      ];
      final articulations = [
        if (first)
          for (final articulation in Articulation.values)
            if (event.articulations.contains(articulation))
              if (articulationName(articulation) case final String name)
                _el(name),
      ];
      final children = [
        if (note != null && tieStops.contains(note.id))
          _el('tied', const [], {'type': 'stop'}),
        if (tie != null)
          _el('tied', const [], {
            'type': tie.to == null ? 'let-ring' : 'start',
          }),
        for (final (spanner, start) in onEvent)
          if (spanner.kind is Slur) _spannerMark(spanner, start: start),
        if (first) ...?tupletMarks[event.id],
        for (final (spanner, start) in onEvent)
          if (spanner.kind is Glissando) _spannerMark(spanner, start: start),
        if (ornaments.isNotEmpty) _el('ornaments', ornaments),
        if (technical.isNotEmpty) _el('technical', technical),
        if (articulations.isNotEmpty) _el('articulations', articulations),
        if (first && event.articulations.contains(Articulation.fermata))
          _el('fermata'),
      ];
      return children.isEmpty ? null : _el('notations', children);
    }

    return (timed) => switch (timed.event) {
      final ChordEvent chord => [
        for (final grace in chord.graces)
          for (final (i, note) in grace.notes.indexed)
            _el('note', [
              _el('grace', const [], {
                'slash': grace.kind == GraceKind.acciaccatura ? 'yes' : null,
              }),
              if (i > 0) _el('chord'),
              ...head(note),
              ?instrument(note),
              _text('voice', number),
              ..._type(grace.value),
              ?_accidental(staff.accidentals[note.id]),
              ?_notehead(staff.headOf(note)),
              ?_staff(staff, k),
            ]),
        for (final (i, note) in chord.notes.indexed)
          _el('note', [
            if (i > 0) _el('chord'),
            ...head(note),
            _duration(timed.duration),
            if (tieStops.contains(note.id))
              _el('tie', const [], {'type': 'stop'}),
            if (ties[note.id]?.to != null)
              _el('tie', const [], {'type': 'start'}),
            ?instrument(note),
            _text('voice', number),
            ..._type(chord.value),
            ?_accidental(staff.accidentals[note.id]),
            ?modification(timed, chord.value),
            if (chord.stem != StemDirection.auto)
              _text('stem', chord.stem.name),
            ?_notehead(staff.headOf(note)),
            ?_staff(staff, k),
            if (i == 0)
              for (final (level, type)
                  in beams[chord.id] ?? const <(int, String)>[])
                _text('beam', type, {'number': '$level'}),
            ?notations(chord, note: note, first: i == 0),
            if (i == 0) ...chord.lyrics.map(_lyric),
          ]),
      ],
      final RestEvent rest => [
        _el(
          'note',
          [
            _el('rest'),
            _duration(timed.duration),
            _text('voice', number),
            ..._type(rest.value),
            ?modification(timed, rest.value),
            ?_staff(staff, k),
            ?notations(rest, first: true),
          ],
          {'print-object': rest.hidden ? 'no' : null},
        ),
      ],
      final MeasureRest rest => [
        _el('note', [
          _el('rest', const [], {'measure': 'yes'}),
          _duration(timed.duration),
          _text('voice', number),
          ?_staff(staff, k),
          ?notations(rest, first: true),
        ]),
      ],
    };
  }

  /// The slur, glissando and trill line ends on [event], each spanner's
  /// start before its stop.
  List<_Mark> _onEvent(EventId event) => [
    for (final line in ends) ...[
      if (line.from == event) (line.spanner, true),
      if (line.to == event) (line.spanner, false),
    ],
  ];

  XmlElement _spannerMark(Spanner spanner, {required bool start}) {
    final type = start ? 'start' : 'stop';
    final number = '${numbers[spanner.id]}';
    return switch (spanner.kind) {
      Slur(:final dashed) => _el('slur', const [], {
        'type': type,
        'number': number,
        'line-type': start && dashed ? 'dashed' : null,
      }),
      Glissando() => _el('glissando', const [], {
        'type': type,
        'number': number,
      }),
      TrillLine() => _el('wavy-line', const [], {
        'type': type,
        'number': number,
      }),
      Hairpin(:final crescendo) => _el('wedge', const [], {
        'type': start ? (crescendo ? 'crescendo' : 'diminuendo') : 'stop',
        'number': number,
      }),
      OctaveLine(:final shift) => _el('octave-shift', const [], {
        'type': start ? (shift.octaves > 0 ? 'down' : 'up') : 'stop',
        'size': '${shift.octaves.abs() * 7 + 1}',
        'number': number,
      }),
      PedalLine() => _el('pedal', const [], {
        'type': type,
        'line': 'yes',
        'number': number,
      }),
      TempoLine() => _el('dashes', const [], {
        'type': type,
        'number': number,
      }),
    };
  }

  /// A hairpin, octave line, pedal line or tempo line end, as a direction.
  XmlElement _line(_Ends line, {required bool start, XmlElement? staff}) {
    final kind = line.spanner.kind;
    return _direction(
      [
        if (kind case TempoLine(:final text) when start) _text('words', text),
        _spannerMark(line.spanner, start: start),
      ],
      above: switch (kind) {
        OctaveLine(:final shift) => shift.octaves > 0,
        TempoLine() => true,
        _ => false,
      },
      staff: staff,
    );
  }

  _Ends _endsOf(Spanner spanner) {
    final staves = score.partOf(spanner.staff).staves;
    final staffIndex = staves.indexWhere((staff) => staff.id == spanner.staff);
    int stream(VoiceSlot voice) => staffIndex * 4 + voice.index;
    (TimedEvent, int) eventAt(VoiceSlot voice, ScorePoint point) =>
        switch (score.eventAt(
          VoicePoint(staff: spanner.staff, voice: voice, at: point),
        )) {
          final timed? => (timed, stream(voice)),
          null => (
            score.anchorAt(spanner.staff, VoiceSlot.one, point)!,
            stream(VoiceSlot.one),
          ),
        };
    final firstBar = score.indexOf(spanner.first.measure);
    final lastBar = score.indexOf(spanner.last.measure);
    switch (spanner.kind) {
      case Slur() || Glissando() || TrillLine():
        final voice = spanner.voice ?? VoiceSlot.one;
        final (from, fromStream) = eventAt(voice, spanner.first);
        final (to, toStream) = eventAt(voice, spanner.last);
        return (
          spanner: spanner,
          start: (bar: firstBar, stream: fromStream, at: from.onset),
          stop: (bar: lastBar, stream: toStream, at: to.onset),
          from: from.event.id,
          to: to.event.id,
        );
      case Hairpin() || OctaveLine() || PedalLine() || TempoLine():
        final (last, _) = eventAt(VoiceSlot.one, spanner.last);
        return (
          spanner: spanner,
          start: (
            bar: firstBar,
            stream: stream(VoiceSlot.one),
            at: spanner.first.offset,
          ),
          stop: (
            bar: lastBar,
            stream: stream(VoiceSlot.one),
            at: last.onset + last.duration,
          ),
          from: null,
          to: null,
        );
    }
  }

  /// Numbers each spanner with the lowest number no overlapping spanner of
  /// the same kind in its part holds. Spanners overlap when one stops at or
  /// after the other starts.
  Map<SpannerId, int> _numbers() {
    final numbers = <SpannerId, int>{};
    final groups = <(PartId, Type), List<_Ends>>{};
    for (final line in ends) {
      final part = score.partOf(line.spanner.staff).id;
      (groups[(part, line.spanner.kind.runtimeType)] ??= []).add(line);
    }
    for (final group in groups.values) {
      final ordered = [...group.indexed]
        ..sort((a, b) {
          final byStart = _compare(a.$2.start, b.$2.start);
          return byStart != 0 ? byStart : a.$1 - b.$1;
        });
      final open = <_Ends>[];
      for (final (_, line) in ordered) {
        open.removeWhere(
          (other) =>
              _compare(other.stop, line.start) < 0 &&
              _writtenBefore(other.stop, line.start),
        );
        var number = 1;
        while (open.any((other) => numbers[other.spanner.id] == number)) {
          number++;
        }
        numbers[line.spanner.id] = number;
        open.add(line);
      }
    }
    return numbers;
  }

  int _divisions() {
    var divisions = 1;
    void fit(Fraction wholeNotes) {
      final denominator = (wholeNotes * Fraction(4)).denominator;
      divisions = divisions * denominator ~/ divisions.gcd(denominator);
    }

    for (final view in views) {
      fit(view.column.length.wholeNotes);
      for (final tempo in view.column.tempos) {
        fit(tempo.offset.wholeNotes);
      }
      for (final staff in view.staves) {
        for (final change in staff.source.clefChanges) {
          fit(change.offset.wholeNotes);
        }
        for (final direction in staff.source.directions) {
          fit(direction.offset.wholeNotes);
        }
        for (final voice in staff.voices) {
          for (final timed in voice.events) {
            fit(timed.onset.wholeNotes);
            fit(timed.duration.wholeNotes);
          }
        }
      }
    }
    for (final line in ends) {
      fit(line.start.at.wholeNotes);
      fit(line.stop.at.wholeNotes);
    }
    return divisions;
  }

  XmlElement _duration(Length length) {
    final quarters = length.wholeNotes * Fraction(4 * divisions);
    return _text('duration', '${quarters.numerator}');
  }
}

/// A slur, glissando or trill line end on an event: the spanner, and
/// whether it starts there.
typedef _Mark = (Spanner, bool);

bool _opensBar(NavigationMark mark) => mark is Segno || mark is Coda;

XmlElement _navigation(NavigationMark mark, XmlElement? staff) {
  final (types, sound) = switch (mark) {
    Segno() => ([_el('segno')], {'segno': 'segno'}),
    Coda() => ([_el('coda')], {'coda': 'coda'}),
    ToCoda() => ([_text('words', 'To Coda')], {'tocoda': 'coda'}),
    Fine() => ([_text('words', 'Fine')], {'fine': 'yes'}),
    Jump(:final target, :final then, :final text) => (
      [
        _text(
          'words',
          text ??
              '${target == JumpTarget.start ? 'D.C.' : 'D.S.'}'
                  '${switch (then) {
                    JumpThen.toEnd => '',
                    JumpThen.toFine => ' al Fine',
                    JumpThen.toCoda => ' al Coda',
                  }}',
        ),
      ],
      target == JumpTarget.start ? {'dacapo': 'yes'} : {'dalsegno': 'segno'},
    ),
  };
  return _direction(
    types,
    above: true,
    staff: staff,
    sound: _el('sound', const [], sound),
  );
}

XmlElement _tempo(TempoMark mark, XmlElement? staff) {
  final beat = mark.tempo.beat;
  final quarters = beat.length.wholeNotes * Fraction(4);
  return _direction(
    [
      if (mark.text case final String text) _text('words', text),
      _el(
        'metronome',
        [
          _text('beat-unit', typeName(beat.base)),
          for (var i = 0; i < beat.dots; i++) _el('beat-unit-dot'),
          _text('per-minute', _number(mark.tempo.bpm)),
        ],
        {'print-object': mark.showMetronome ? null : 'no'},
      ),
    ],
    above: true,
    staff: staff,
    sound: _el('sound', const [], {
      'tempo': _number(mark.tempo.bpm * quarters.toDouble()),
    }),
  );
}

XmlElement _staffDirection(StaffDirection direction, XmlElement? staff) =>
    switch (direction) {
      DynamicMark(:final level) => _direction(
        [
          _el('dynamics', [_el(level.name)]),
        ],
        above: false,
        staff: staff,
        sound: _el('sound', const [], {
          'dynamics': _number(level.velocity / 90 * 100),
        }),
      ),
      TextMark(:final text, :final above) => _direction(
        [_text('words', text)],
        above: above,
        staff: staff,
      ),
      ChordSymbol(:final root, :final quality, :final bass) => _el('harmony', [
        _el('root', [
          _text('root-step', root.step.name.toUpperCase()),
          if (root.alter != Alter.natural)
            _text('root-alter', _number(root.alter.quarterTones / 2)),
        ]),
        _text('kind', chordKinds[quality] ?? 'other', {'text': quality}),
        if (bass != null)
          _el('bass', [
            _text('bass-step', bass.step.name.toUpperCase()),
            if (bass.alter != Alter.natural)
              _text('bass-alter', _number(bass.alter.quarterTones / 2)),
          ]),
        ?staff,
      ]),
    };

XmlElement _direction(
  List<XmlElement> types, {
  required bool above,
  XmlElement? staff,
  XmlElement? sound,
}) => _el(
  'direction',
  [
    for (final type in types) _el('direction-type', [type]),
    ?staff,
    ?sound,
  ],
  {'placement': above ? 'above' : 'below'},
);

XmlElement? _leftBarline(MeasureView view) {
  final column = view.column;
  final children = [
    if (column.repeatStart) _text('bar-style', 'heavy-light'),
    if (column.volta case final Volta volta when view.voltaStarts)
      _text('ending', '${volta.endings.join(', ')}.', {
        'number': volta.endings.join(', '),
        'type': 'start',
      }),
    if (column.repeatStart) _el('repeat', const [], {'direction': 'forward'}),
  ];
  return children.isEmpty
      ? null
      : _el('barline', children, {'location': 'left'});
}

XmlElement? _rightBarline(MeasureView view) {
  final column = view.column;
  final style = barStyleName(
    column.barline,
    repeats: column.repeatEnd != null,
  );
  final children = [
    if (style != null) _text('bar-style', style),
    if (column.volta case final Volta volta when view.voltaEnds)
      _el('ending', const [], {
        'number': volta.endings.join(', '),
        'type': volta.open ? 'discontinue' : 'stop',
      }),
    if (column.repeatEnd case final RepeatEnd repeat)
      _el('repeat', const [], {
        'direction': 'backward',
        'times': repeat.times > 2 ? '${repeat.times}' : null,
      }),
  ];
  return children.isEmpty
      ? null
      : _el('barline', children, {'location': 'right'});
}

/// A key that is not [printed] changes the mode alone, which draws no new
/// signature.
XmlElement _key(KeySignature key, {bool printed = true}) => _el(
  'key',
  [
    _text('fifths', '${key.fifths}'),
    if (key.mode != KeyMode.none) _text('mode', key.mode.name),
  ],
  {'print-object': printed ? null : 'no'},
);

XmlElement _time(Meter meter) => _el(
  'time',
  [
    _text('beats', meter.groups.join('+')),
    _text('beat-type', '${meter.unit}'),
  ],
  {
    'symbol': switch (meter.symbol) {
      MeterSymbol.numeric => null,
      MeterSymbol.common => 'common',
      MeterSymbol.cut => 'cut',
    },
  },
);

XmlElement _clef(Clef clef, int? number) => _el(
  'clef',
  [
    _text('sign', clefSignName(clef.sign)),
    if (clef.sign != ClefSign.percussion) _text('line', '${clef.line}'),
    if (clef.octave != 0) _text('clef-octave-change', '${clef.octave}'),
  ],
  {'number': number?.toString()},
);

/// Written to sounding, as MusicXML splits it: steps and semitones within
/// an octave, and whole octaves apart.
XmlElement _transpose(Interval interval) {
  final octaves = interval.steps ~/ 7;
  return _el('transpose', [
    _text('diatonic', '${interval.steps - 7 * octaves}'),
    _text('chromatic', '${interval.semitones - 12 * octaves}'),
    if (octaves != 0) _text('octave-change', '$octaves'),
  ]);
}

XmlElement _pitch(Pitch pitch) => _el('pitch', [
  _text('step', pitch.step.name.toUpperCase()),
  if (pitch.alter != Alter.natural)
    _text('alter', _number(pitch.alter.quarterTones / 2)),
  _text('octave', '${pitch.octave}'),
]);

List<XmlElement> _type(NoteValue value) => [
  _text('type', typeName(value.base)),
  for (var i = 0; i < value.dots; i++) _el('dot'),
];

XmlElement? _accidental(AccidentalMark? mark) => mark == null
    ? null
    : _text('accidental', accidentalNames[mark.alter.quarterTones + 4], {
        'parentheses': mark.cautionary ? 'yes' : null,
      });

XmlElement? _notehead(NoteHead head) => switch (noteheadName(head)) {
  final String name => _text('notehead', name),
  null => null,
};

XmlElement _tuplet(TupletView view, {required bool start}) {
  final tuplet = view.tuplet;
  final number = '${view.depth + 1}';
  if (!start) {
    return _el('tuplet', const [], {'type': 'stop', 'number': number});
  }
  List<XmlElement> unit() => [
    _text('tuplet-type', typeName(tuplet.unit.base)),
    for (var i = 0; i < tuplet.unit.dots; i++) _el('tuplet-dot'),
  ];
  return _el(
    'tuplet',
    [
      _el('tuplet-actual', [
        _text('tuplet-number', '${tuplet.ratio.actual}'),
        ...unit(),
      ]),
      _el('tuplet-normal', [
        _text('tuplet-number', '${tuplet.ratio.normal}'),
        ...unit(),
      ]),
    ],
    {
      'type': 'start',
      'number': number,
      'bracket': switch (tuplet.bracket) {
        TupletBracket.auto => null,
        TupletBracket.shown => 'yes',
        TupletBracket.hidden => 'no',
      },
    },
  );
}

XmlElement _lyric(Lyric lyric) => _el(
  'lyric',
  [
    _text('syllabic', lyric.syllabic.name),
    _text('text', lyric.text),
    if (lyric.extend) _el('extend'),
  ],
  {'number': '${lyric.verse}'},
);

/// Beam elements by event, as (level, type): level 1 spans each group, and
/// deeper levels join neighbours that share them and end in hooks where
/// they have none.
Map<EventId, List<(int, String)>> _beams(VoiceView voice) {
  final counts = {
    for (final timed in voice.events)
      if (timed.event case ChordEvent(:final id, :final value))
        id: value.base.beams,
  };
  final beams = <EventId, List<(int, String)>>{};
  for (final group in voice.beams) {
    final levels = [for (final id in group.events) counts[id]!];
    final breaks = group.secondaryBreaks;
    final last = levels.length - 1;
    for (final (i, id) in group.events.indexed) {
      beams[id] = [
        (1, i == 0 ? 'begin' : (i == last ? 'end' : 'continue')),
        for (var level = 2; level <= levels[i]; level++)
          (
            level,
            switch ((
              i > 0 && levels[i - 1] >= level && !breaks.contains(i),
              i < last && levels[i + 1] >= level && !breaks.contains(i + 1),
            )) {
              (true, true) => 'continue',
              (true, false) => 'end',
              (false, true) => 'begin',
              (false, false) =>
                i == 0 || breaks.contains(i) ? 'forward hook' : 'backward hook',
            },
          ),
      ];
    }
  }
  return beams;
}

/// [value] with at most three decimals and no trailing zeros.
String _number(num value) =>
    value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

XmlElement _el(
  String name, [
  Iterable<XmlNode> children = const [],
  Map<String, String?> attributes = const {},
]) => XmlElement(
  XmlName.qualified(name),
  [
    for (final MapEntry(:key, :value) in attributes.entries)
      if (value != null) XmlAttribute(XmlName.qualified(key), value),
  ],
  children,
);

XmlElement _text(
  String name,
  String text, [
  Map<String, String?> attributes = const {},
]) => _el(name, [XmlText(text)], attributes);
