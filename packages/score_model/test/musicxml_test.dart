import 'dart:io';
import 'dart:math';

import 'package:score_model/score_model.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'random_edits.dart';
import 'showcase.dart';
import 'support.dart';

final golden = File('test/golden/showcase.musicxml');

/// The export of [score], parsed, without the whitespace between elements
/// that pretty printing adds.
XmlDocument exported(Score score) {
  final xml = XmlDocument.parse(scoreToMusicXml(score));
  for (final text in [...xml.descendants.whereType<XmlText>()]) {
    if (text.value.trim().isEmpty) {
      text.remove();
    }
  }
  return xml;
}

/// A child of a `<measure>` at the time a MusicXML reader gives it, in
/// whole notes from the start of the bar.
typedef Placed = ({
  String part,
  int bar,
  Fraction at,
  Fraction length,
  XmlElement element,
});

/// Every child of every measure of [xml], placed by walking the bar's time
/// cursor through `<backup>`, `<forward>`, `<chord/>` and each note's
/// duration, as a reader does. Also the length of each bar, the furthest
/// the cursor reaches.
({List<Placed> children, List<String> bars}) read(XmlDocument xml) {
  final children = <Placed>[];
  final bars = <String>[];
  for (final part in xml.rootElement.findElements('part')) {
    final id = part.getAttribute('id')!;
    var divisions = 0;
    for (final (bar, measure) in part.findElements('measure').indexed) {
      if (measure.findAllElements('divisions').firstOrNull case final value?) {
        divisions = int.parse(value.innerText);
      }
      var cursor = 0;
      var onset = 0;
      var furthest = 0;
      for (final child in measure.childElements) {
        final name = child.name.local;
        final duration = int.parse(
          child.getElement('duration')?.innerText ?? '0',
        );
        final chordTone = child.getElement('chord') != null;
        if (name == 'backup') {
          cursor -= duration;
          expect(cursor, isNonNegative, reason: '$id bar $bar backs up');
        }
        if (name == 'note' && !chordTone) {
          onset = cursor;
        }
        children.add((
          part: id,
          bar: bar,
          at: Fraction(name == 'note' ? onset : cursor, divisions * 4),
          length: Fraction(duration, divisions * 4),
          element: child,
        ));
        if (name == 'forward' || (name == 'note' && !chordTone)) {
          cursor += duration;
        }
        furthest = max(furthest, cursor);
      }
      bars.add('$id m$bar ${Fraction(furthest, divisions * 4)}');
    }
  }
  return (children: children, bars: bars);
}

String sounding(XmlElement note) {
  if (note.getElement('pitch') case final pitch?) {
    final alter = double.parse(pitch.getElement('alter')?.innerText ?? '0');
    return Pitch(
      Step.values.byName(pitch.getElement('step')!.innerText.toLowerCase()),
      int.parse(pitch.getElement('octave')!.innerText),
      Alter.fromQuarterTones((alter * 2).round()),
    ).toString();
  }
  if (note.getElement('unpitched') case final unpitched?) {
    return 'unpitched ${unpitched.getElement('display-step')!.innerText}'
        '${unpitched.getElement('display-octave')!.innerText}';
  }
  final rest = note.getElement('rest')!;
  return rest.getAttribute('measure') == 'yes' ? 'measure rest' : 'rest';
}

String noteLine(
  String part,
  int bar,
  int staff,
  int voice,
  Fraction at,
  Object length,
  String written,
) => '$part m$bar s$staff v$voice @$at $length $written';

/// Each note as `P1 m0 s1 v1 @0 1/4 F#4`: part, bar, staff, voice, onset,
/// length (or `grace`) and what is written.
List<String> notesIn(List<Placed> children) => [
  for (final (:part, :bar, :at, :length, :element) in children)
    if (element.name.local == 'note')
      noteLine(
        part,
        bar,
        int.parse(element.getElement('staff')?.innerText ?? '1'),
        int.parse(element.getElement('voice')!.innerText),
        at,
        element.getElement('grace') != null ? 'grace' : length,
        sounding(element),
      ),
];

/// The same lines as [notesIn] reads, made from the model.
List<String> notesOf(Score score) {
  final shown = showAll(score);
  String written(Part part, Event event, Note? note) => switch ((note, event)) {
    (PitchedNote(:final pitch), _) =>
      '${pitch.transpose(-part.instrument.transposition)}',
    (DrumNote(:final drum), _) =>
      'unpitched ${part.instrument.soundOf(drum)!.position}',
    (_, MeasureRest()) => 'measure rest',
    _ => 'rest',
  };
  List<(bool, Note?)> heads(Event event) => switch (event) {
    ChordEvent(:final graces, :final notes) => [
      for (final grace in graces)
        for (final note in grace.notes) (true, note),
      for (final note in notes) (false, note),
    ],
    _ => [(false, null)],
  };
  return [
    for (final (p, part) in shown.parts.indexed)
      for (final (bar, column) in shown.measures.indexed)
        for (final staff in shown.measureView(column.id).staves)
          if (staff.part.id == part.id)
            for (final voice in staff.voices)
              for (final timed in voice.events)
                for (final (grace, note) in heads(timed.event))
                  noteLine(
                    'P${p + 1}',
                    bar,
                    part.staves.indexWhere((s) => s.id == staff.source.staff) +
                        1,
                    part.staves.indexWhere((s) => s.id == staff.source.staff) *
                            4 +
                        voice.slot.index +
                        1,
                    timed.onset.wholeNotes,
                    grace ? 'grace' : timed.duration.wholeNotes,
                    written(part, timed.event, note),
                  ),
  ];
}

List<String> barsOf(Score score) => [
  for (final (p, _) in score.parts.indexed)
    for (final (bar, column) in score.measures.indexed)
      'P${p + 1} m$bar ${column.length.wholeNotes}',
];

Score showAll(Score score) => score.copyWith(
  parts: Seq([for (final part in score.parts) part.copyWith(hidden: false)]),
);

/// Each measure child named [name], or element of that name inside one, as
/// `P1 m0 @0 <wedge type="crescendo" number="1"/>`.
List<String> placedAs(List<Placed> children, String name) => [
  for (final (:part, :bar, :at, length: _, :element) in children)
    for (final found in [element, ...element.descendantElements])
      if (found.name.local == name) '$part m$bar @$at ${found.toXmlString()}',
];

/// Checks that each start of spanner element [name] meets a stop of the
/// same number later in its part's document, before that number starts
/// again. A reader pairs them in that order.
void expectPaired(List<Placed> children, String name, {String reason = ''}) {
  final open = <String, String>{};
  final found = [
    for (final child in children)
      for (final element in child.element.findAllElements(name))
        (child, element),
  ];
  for (final (child, found) in found) {
    final key = '${child.part} ${found.getAttribute('number')}';
    final where = '$reason, $name $key in bar ${child.bar} @${child.at}';
    if (found.getAttribute('type') == 'stop') {
      expect(open.remove(key), isNotNull, reason: '$where stops unopened');
    } else {
      expect(open[key], isNull, reason: '$where starts while open');
      open[key] = where;
    }
  }
  expect(open.values, isEmpty, reason: '$reason, never stopped');
}

int startsOf(List<Placed> children, String name, String part) => [
  for (final child in children)
    if (child.part == part)
      for (final found in child.element.findAllElements(name))
        if (found.getAttribute('type') != 'stop') found,
].length;

XmlElement measure(XmlDocument xml, String part, int bar) => xml.rootElement
    .findElements('part')
    .firstWhere((e) => e.getAttribute('id') == part)
    .findElements('measure')
    .elementAt(bar);

String compact(XmlElement element) => element.toXmlString();

/// [lines] trimmed and joined, for writing long XML across lines.
String joined(String lines) =>
    lines.split('\n').map((line) => line.trim()).join();

/// Each element named [name] among the children of [parent], compact.
List<String> each(XmlElement parent, String name) => [
  for (final found in parent.findAllElements(name)) compact(found),
];

void main() {
  group('scoreToMusicXml', () {
    test('writes every mapped field as the golden file shows', () {
      if (Platform.environment['UPDATE_GOLDEN'] == '1') {
        golden.writeAsStringSync(scoreToMusicXml(showcase()));
      }

      expect(scoreToMusicXml(showcase()), golden.readAsStringSync());
    });

    test('declares a MusicXML 4.0 partwise document', () {
      final xml = exported(showcase());

      expect(xml.declaration?.toXmlString(), contains('encoding="UTF-8"'));
      expect(xml.doctypeElement?.name, 'score-partwise');
      expect(
        xml.doctypeElement?.externalId?.publicId,
        '-//Recordare//DTD MusicXML 4.0 Partwise//EN',
      );
      expect(
        xml.doctypeElement?.externalId?.systemId,
        'http://www.musicxml.org/dtds/partwise.dtd',
      );
      expect(xml.rootElement.name.local, 'score-partwise');
      expect(xml.rootElement.getAttribute('version'), '4.0');
    });

    test('places every note and rest where the model has it', () {
      final (:children, :bars) = read(exported(showcase()));

      expect(notesIn(children), notesOf(showcase()));
      expect(bars, barsOf(showcase()));
    });

    test('writes the header and one score-part per part', () {
      final root = exported(showcase()).rootElement;

      expect(
        root.getElement('work')?.getElement('work-title')?.innerText,
        'Showcase',
      );
      expect(each(root.getElement('identification')!, 'creator'), [
        '<creator type="composer">Anon.</creator>',
        '<creator type="lyricist">Anon.</creator>',
      ]);
      expect(each(root, 'rights'), ['<rights>CC0</rights>']);
      expect(each(root, 'credit'), [
        joined('''
          <credit page="1"><credit-type>subtitle</credit-type>
          <credit-words>for testing</credit-words></credit>
        '''),
      ]);
      expect(each(root.getElement('part-list')!, 'score-part'), [
        joined('''
          <score-part id="P1"><part-name>Violin</part-name>
          <part-abbreviation>Vln.</part-abbreviation>
          <score-instrument id="P1-I1"><instrument-name>Violin</instrument-name></score-instrument>
          <midi-instrument id="P1-I1"><midi-program>41</midi-program></midi-instrument>
          </score-part>
        '''),
        joined('''
          <score-part id="P2"><part-name>Clarinet in B♭</part-name>
          <score-instrument id="P2-I1"><instrument-name>Clarinet in B♭</instrument-name></score-instrument>
          <midi-instrument id="P2-I1"><midi-program>72</midi-program></midi-instrument>
          </score-part>
        '''),
        joined('''
          <score-part id="P3"><part-name>Drums</part-name>
          <score-instrument id="P3-I1"><instrument-name>Snare</instrument-name></score-instrument>
          <score-instrument id="P3-I2"><instrument-name>Side stick</instrument-name></score-instrument>
          <score-instrument id="P3-I3"><instrument-name>Bass drum</instrument-name></score-instrument>
          <midi-instrument id="P3-I1"><midi-channel>10</midi-channel><midi-bank>129</midi-bank>
          <midi-program>1</midi-program><midi-unpitched>39</midi-unpitched></midi-instrument>
          <midi-instrument id="P3-I2"><midi-channel>10</midi-channel><midi-bank>129</midi-bank>
          <midi-program>1</midi-program><midi-unpitched>38</midi-unpitched></midi-instrument>
          <midi-instrument id="P3-I3"><midi-channel>10</midi-channel><midi-bank>129</midi-bank>
          <midi-program>1</midi-program><midi-unpitched>37</midi-unpitched></midi-instrument>
          </score-part>
        '''),
      ]);
    });

    test('leaves out the header fields a score leaves empty', () {
      final root = exported(plain()).rootElement;

      expect(root.getElement('work'), isNull);
      expect(root.findAllElements('creator'), isEmpty);
      expect(root.findAllElements('rights'), isEmpty);
      expect(root.findAllElements('credit'), isEmpty);
      expect(root.findAllElements('part-abbreviation'), isEmpty);
    });

    test('numbers bars from a pickup at 0', () {
      final xml = exported(showcase());
      final bars = xml.rootElement.getElement('part')!.findElements('measure');

      expect(
        [for (final bar in bars) bar.getAttribute('number')],
        [
          '0',
          '1',
          '2',
          '3',
        ],
      );
      expect(
        [for (final bar in bars) bar.getAttribute('implicit')],
        [
          'yes',
          null,
          null,
          null,
        ],
      );
      expect(
        [
          for (final bar in exported(
            plain(),
          ).rootElement.findAllElements('measure'))
            bar.getAttribute('number'),
        ],
        ['1', '2'],
      );
    });

    test('writes signatures where they print and clefs where they change', () {
      final xml = exported(showcase());

      expect(each(measure(xml, 'P1', 0), 'attributes'), [
        joined('''
          <attributes><divisions>18</divisions>
          <key><fifths>2</fifths><mode>major</mode></key>
          <time symbol="common"><beats>4</beats><beat-type>4</beat-type></time>
          <clef><sign>G</sign><line>2</line></clef>
          <staff-details>
          <staff-tuning line="1"><tuning-step>G</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
          <staff-tuning line="2"><tuning-step>D</tuning-step><tuning-octave>4</tuning-octave></staff-tuning>
          <staff-tuning line="3"><tuning-step>A</tuning-step><tuning-octave>4</tuning-octave></staff-tuning>
          <staff-tuning line="4"><tuning-step>E</tuning-step><tuning-octave>5</tuning-octave></staff-tuning>
          </staff-details></attributes>
        '''),
      ]);
      expect(each(measure(xml, 'P1', 1), 'attributes'), [
        '<attributes><time symbol="common"><beats>4</beats><beat-type>4</beat-type></time></attributes>',
        '<attributes><clef><sign>C</sign><line>3</line></clef></attributes>',
      ]);
      expect(each(measure(xml, 'P1', 2), 'attributes'), [
        joined('''
          <attributes><key><fifths>-3</fifths><mode>minor</mode></key>
          <time><beats>6</beats><beat-type>8</beat-type></time></attributes>
        '''),
      ]);
      expect(each(measure(xml, 'P1', 3), 'attributes'), [
        joined('''
          <attributes><key><fifths>-3</fifths><mode>minor</mode></key>
          <time><beats>3+2+2</beats><beat-type>8</beat-type></time>
          <clef><sign>G</sign><line>2</line></clef></attributes>
        '''),
      ]);
      expect(each(measure(xml, 'P3', 0), 'attributes'), [
        joined('''
          <attributes><divisions>18</divisions>
          <key><fifths>0</fifths></key>
          <time symbol="common"><beats>4</beats><beat-type>4</beat-type></time>
          <clef><sign>percussion</sign></clef>
          <staff-details><staff-lines>1</staff-lines></staff-details></attributes>
        '''),
      ]);
      expect(
        placedAs(read(xml).children, 'clef').where((c) => c.startsWith('P1')),
        [
          'P1 m0 @0 <clef><sign>G</sign><line>2</line></clef>',
          'P1 m1 @1/2 <clef><sign>C</sign><line>3</line></clef>',
          'P1 m3 @0 <clef><sign>G</sign><line>2</line></clef>',
        ],
      );
    });

    test('writes cut time, an octave clef and the staves of a grand staff', () {
      var score = blankScore(parts: const [piano], bars: 1);
      score = changeBar(
        score,
        0,
        (column) => column
            .withStaff(column.staves[1].copyWith(clef: Clef.bass8vb))
            .copyWith(meter: Meter.cut),
      );
      final attributes = each(measure(exported(score), 'P1', 0), 'attributes');

      expect(attributes, [
        joined('''
          <attributes><divisions>1</divisions>
          <key><fifths>0</fifths><mode>major</mode></key>
          <time symbol="cut"><beats>2</beats><beat-type>2</beat-type></time>
          <staves>2</staves>
          <clef number="1"><sign>G</sign><line>2</line></clef>
          <clef number="2"><sign>F</sign><line>4</line>
          <clef-octave-change>-1</clef-octave-change></clef></attributes>
        '''),
      ]);
      expect(notesIn(read(exported(score)).children), [
        'P1 m0 s1 v1 @0 1 measure rest',
        'P1 m0 s2 v5 @0 1 measure rest',
      ]);
    });

    test('writes a transposing part at written pitch with its interval', () {
      const bassClarinet = PartTemplate(
        name: 'Bass clarinet',
        instrument: Instrument(
          key: 'bass-clarinet',
          program: 71,
          transposition: Interval(-8, -14),
        ),
      );
      var score = blankScore(parts: const [clarinet, bassClarinet], bars: 1);
      score = fill(score, 0, [chordOf(1, 'C4', value: NoteValue.whole)]);
      score = fill(score, 0, staff: 1, [
        chordOf(2, 'Bb2', value: NoteValue.whole),
      ]);
      final xml = exported(score);

      expect(each(measure(xml, 'P1', 0), 'pitch'), [
        '<pitch><step>D</step><octave>4</octave></pitch>',
      ]);
      expect(each(measure(xml, 'P1', 0), 'key'), [
        '<key><fifths>2</fifths><mode>major</mode></key>',
      ]);
      expect(each(measure(xml, 'P1', 0), 'transpose'), [
        '<transpose><diatonic>-1</diatonic><chromatic>-2</chromatic></transpose>',
      ]);
      expect(each(measure(xml, 'P2', 0), 'pitch'), [
        '<pitch><step>C</step><octave>4</octave></pitch>',
      ]);
      expect(each(measure(xml, 'P2', 0), 'transpose'), [
        joined('''
          <transpose><diatonic>-1</diatonic><chromatic>-2</chromatic>
          <octave-change>-1</octave-change></transpose>
        '''),
      ]);
    });

    test('respells a written pitch past a double accidental', () {
      var score = blankScore(parts: const [clarinet], bars: 1);
      score = fill(score, 0, [chordOf(1, 'Ex4', value: NoteValue.whole)]);

      expect(each(measure(exported(score), 'P1', 0), 'pitch'), [
        '<pitch><step>G</step><alter>1</alter><octave>4</octave></pitch>',
      ]);
    });

    test('names every accidental the staff prints', () {
      ChordEvent note(int id, Pitch pitch, {bool cautionary = false}) =>
          ChordEvent(
            id: EventId(id),
            value: NoteValue.eighth,
            beam: BeamMode.none,
            notes: Seq([
              PitchedNote(
                id: NoteId(id + 1),
                pitch: pitch,
                accidental: cautionary
                    ? AccidentalRequest.cautionary
                    : AccidentalRequest.auto,
              ),
            ]),
          );
      final score = fill(blankScore(bars: 1, meter: const Meter([9], 8)), 0, [
        note(1, const Pitch(Step.c, 4, Alter.doubleFlat)),
        note(3, const Pitch(Step.d, 4, Alter.threeQuarterFlat)),
        note(5, const Pitch(Step.e, 4, Alter.flat)),
        note(7, const Pitch(Step.f, 4, Alter.quarterFlat)),
        note(9, const Pitch(Step.g, 4), cautionary: true),
        note(11, const Pitch(Step.a, 4, Alter.quarterSharp)),
        note(13, const Pitch(Step.b, 4, Alter.sharp)),
        note(15, const Pitch(Step.c, 5, Alter.threeQuarterSharp)),
        note(17, const Pitch(Step.d, 5, Alter.doubleSharp)),
      ]);
      final xml = exported(score);

      expect(each(xml.rootElement, 'accidental'), [
        '<accidental>flat-flat</accidental>',
        '<accidental>three-quarters-flat</accidental>',
        '<accidental>flat</accidental>',
        '<accidental>quarter-flat</accidental>',
        '<accidental parentheses="yes">natural</accidental>',
        '<accidental>quarter-sharp</accidental>',
        '<accidental>sharp</accidental>',
        '<accidental>three-quarters-sharp</accidental>',
        '<accidental>double-sharp</accidental>',
      ]);
      expect(each(xml.rootElement, 'alter'), [
        '<alter>-2</alter>',
        '<alter>-1.5</alter>',
        '<alter>-1</alter>',
        '<alter>-0.5</alter>',
        '<alter>0.5</alter>',
        '<alter>1</alter>',
        '<alter>1.5</alter>',
        '<alter>2</alter>',
      ]);
    });

    test('writes each mark of a chord on its notes', () {
      final notes = measure(
        exported(showcase()),
        'P1',
        0,
      ).findElements('note').map(compact);

      expect(notes.take(3), [
        joined('''
          <note><grace/><pitch><step>E</step><octave>4</octave></pitch>
          <voice>1</voice><type>eighth</type></note>
        '''),
        joined('''
          <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch>
          <duration>18</duration><voice>1</voice><type>quarter</type>
          <stem>up</stem>
          <notations><ornaments><trill-mark/><tremolo type="single">2</tremolo></ornaments>
          <technical><down-bow/><fingering>1</fingering><string>3</string></technical>
          <articulations><staccato/><accent/></articulations></notations>
          <lyric number="1"><syllabic>begin</syllabic><text>la</text><extend/></lyric>
          <lyric number="2"><syllabic>single</syllabic><text>Тай</text></lyric></note>
        '''),
        joined('''
          <note><chord/><pitch><step>A</step><octave>4</octave></pitch>
          <duration>18</duration><tie type="start"/><voice>1</voice><type>quarter</type>
          <accidental parentheses="yes">natural</accidental>
          <stem>up</stem><notehead>diamond</notehead>
          <notations><tied type="start"/></notations></note>
        '''),
      ]);
    });

    test('writes grace chords, note heads, articulations and dots', () {
      PitchedNote note(
        int id,
        String pitch, [
        NoteHead head = NoteHead.normal,
      ]) => PitchedNote(id: NoteId(id), pitch: Pitch.parse(pitch), head: head);
      final xml = exported(
        sessionWith([
          [
            ChordEvent(
              id: const EventId(1),
              value: NoteValue.quarter.dotted.dotted,
              notes: Seq([
                note(2, 'F4', NoteHead.cross),
                note(3, 'A4', NoteHead.slash),
              ]),
              articulations: const {
                Articulation.tenuto,
                Articulation.marcato,
                Articulation.staccatissimo,
              },
              graces: Seq([
                GraceChord(
                  id: const EventId(4),
                  kind: GraceKind.appoggiatura,
                  value: NoteValue.sixteenth,
                  notes: Seq([note(5, 'D4'), note(6, 'F4')]),
                ),
              ]),
            ),
            ChordEvent(
              id: const EventId(7),
              value: NoteValue.sixteenth,
              notes: Seq([note(8, 'C5', NoteHead.triangle)]),
            ),
            ChordEvent(
              id: const EventId(9),
              value: NoteValue.half,
              notes: Seq([note(10, 'E5', NoteHead.circleCross)]),
            ),
          ],
        ]).score,
      );
      const shown = {
        'grace',
        'chord',
        'type',
        'dot',
        'notehead',
        'articulations',
      };
      String shape(XmlElement note) => [
        for (final element in note.descendantElements)
          if (shown.contains(element.name.local)) compact(element),
      ].join();

      expect(xml.findAllElements('note').map(shape), [
        '<grace/><type>16th</type>',
        '<grace/><chord/><type>16th</type>',
        joined('''
          <type>quarter</type><dot/><dot/><notehead>x</notehead>
          <articulations><staccatissimo/><strong-accent/><tenuto/></articulations>
        '''),
        '<chord/><type>quarter</type><dot/><dot/><notehead>slash</notehead>',
        '<type>16th</type><notehead>triangle</notehead>',
        '<type>half</type><notehead>circle-x</notehead>',
      ]);
    });

    test('writes directions before the note they share a time with', () {
      final bar = measure(exported(showcase()), 'P1', 0);

      expect(
        [for (final child in bar.childElements) child.name.local],
        [
          'barline',
          'attributes',
          for (var i = 0; i < 7; i++) 'direction',
          'note',
          'note',
          'note',
          'backup',
          'harmony',
          'backup',
          'forward',
          'note',
        ],
      );
    });

    test('writes drum notes as unpitched with their kit sound', () {
      final notes = measure(
        exported(showcase()),
        'P3',
        0,
      ).findElements('note').map(compact);

      expect(notes, [
        joined('''
          <note><grace slash="yes"/><unpitched><display-step>C</display-step>
          <display-octave>5</display-octave></unpitched>
          <instrument id="P3-I1"/><voice>1</voice><type>16th</type></note>
        '''),
        joined('''
          <note><unpitched><display-step>F</display-step>
          <display-octave>4</display-octave></unpitched>
          <duration>18</duration><instrument id="P3-I3"/><voice>1</voice>
          <type>quarter</type></note>
        '''),
        joined('''
          <note><chord/><unpitched><display-step>C</display-step>
          <display-octave>5</display-octave></unpitched>
          <duration>18</duration><instrument id="P3-I1"/><voice>1</voice>
          <type>quarter</type></note>
        '''),
      ]);
      expect(
        each(measure(exported(showcase()), 'P3', 1), 'notehead'),
        ['<notehead>x</notehead>'],
      );
    });

    test('writes rests, hidden rests and measure rests', () {
      final xml = exported(showcase());

      expect(
        measure(xml, 'P1', 0).findElements('note').skip(3).map(compact),
        [
          joined('''
            <note print-object="no"><rest/><duration>9</duration>
            <voice>2</voice><type>eighth</type></note>
          '''),
        ],
      );
      expect(each(measure(xml, 'P1', 0), 'forward'), [
        '<forward><duration>9</duration><voice>2</voice></forward>',
      ]);
      expect(measure(xml, 'P2', 0).findElements('note').map(compact), [
        joined('''
          <note><rest measure="yes"/><duration>18</duration><voice>1</voice>
          <notations><fermata/></notations></note>
        '''),
      ]);
    });

    test('ties a note to the next and lets a tie with no target ring', () {
      final xml = exported(
        sessionWith([
          [chordOf(1, 'F4', value: NoteValue.whole, tie: true)],
          [
            chordOf(2, 'F4', value: NoteValue.half, tie: true),
            rest(3, NoteValue.half),
          ],
        ]).score,
      );
      String ties(XmlElement note) => [
        for (final tie in note.findElements('tie'))
          'tie ${tie.getAttribute('type')}',
        for (final tied in note.findAllElements('tied'))
          'tied ${tied.getAttribute('type')}',
      ].join(', ');

      expect(
        [for (final note in xml.findAllElements('note')) ties(note)],
        [
          'tie start, tied start',
          'tie stop, tied stop, tied let-ring',
          '',
        ],
      );
    });

    test('beams eighths and sixteenths with hooks', () {
      final xml = exported(
        sessionWith([
          [
            chordOf(1, 'F4 A4', value: NoteValue.eighth),
            chordOf(2, 'G4', value: NoteValue.sixteenth),
            chordOf(3, 'A4', value: NoteValue.sixteenth),
            chordOf(4, 'B4'),
            chordOf(5, 'C5', value: NoteValue.eighth.dotted),
            chordOf(6, 'D5', value: NoteValue.sixteenth),
            chordOf(7, 'E5', value: NoteValue.sixteenth),
            chordOf(8, 'F5', value: NoteValue.eighth.dotted),
          ],
          [
            for (var i = 0; i < 8; i++)
              chordOf(
                10 + i,
                'G4',
                value: NoteValue.sixteenth,
                beam: i == 4 ? BeamMode.join : BeamMode.auto,
              ),
            chordOf(20, 'A4', value: NoteValue.half),
          ],
        ]).score,
      );

      expect(
        [
          for (final note in xml.findAllElements('note'))
            [
              for (final beam in note.findElements('beam'))
                '${beam.getAttribute('number')} ${beam.innerText}',
            ].join(', '),
        ],
        [
          '1 begin',
          '',
          '1 continue, 2 begin',
          '1 end, 2 end',
          '',
          '1 begin',
          '1 end, 2 backward hook',
          '1 begin, 2 forward hook',
          '1 end',
          '1 begin, 2 begin',
          '1 continue, 2 continue',
          '1 continue, 2 continue',
          '1 continue, 2 end',
          '1 continue, 2 begin',
          '1 continue, 2 continue',
          '1 continue, 2 continue',
          '1 end, 2 end',
          '',
        ],
      );
    });

    test('scales notes in tuplets and brackets each tuplet', () {
      final xml = exported(showcase());
      String scaled(XmlElement note) => [
        for (final modification in note.findElements('time-modification'))
          [
            for (final child in modification.childElements) child.innerText,
          ].join(' '),
        for (final tuplet in note.findAllElements('tuplet')) compact(tuplet),
      ].join(', ');

      expect(measure(xml, 'P1', 1).findElements('note').take(6).map(scaled), [
        joined('''
          3 2, <tuplet type="start" number="1" bracket="yes">
          <tuplet-actual><tuplet-number>3</tuplet-number><tuplet-type>eighth</tuplet-type></tuplet-actual>
          <tuplet-normal><tuplet-number>2</tuplet-number><tuplet-type>eighth</tuplet-type></tuplet-normal>
          </tuplet>
        '''),
        '3 2',
        joined('''
          9 4, <tuplet type="start" number="2">
          <tuplet-actual><tuplet-number>3</tuplet-number><tuplet-type>16th</tuplet-type></tuplet-actual>
          <tuplet-normal><tuplet-number>2</tuplet-number><tuplet-type>16th</tuplet-type></tuplet-normal>
          </tuplet>
        '''),
        '9 4',
        '9 4, <tuplet type="stop" number="2"/>, <tuplet type="stop" number="1"/>',
        '',
      ]);

      final quarterInEighths = exported(
        sessionWith([
          [
            Tuplet(
              id: const TupletId(1),
              ratio: TupletRatio.triplet,
              unit: NoteValue.eighth,
              bracket: TupletBracket.hidden,
              members: Seq([
                chordOf(2, 'F4 A4'),
                chordOf(3, 'G4', value: NoteValue.eighth),
              ]),
            ),
            chordOf(4, 'A4', value: NoteValue.half.dotted),
          ],
        ]).score,
      );
      expect(quarterInEighths.findAllElements('note').take(3).map(scaled), [
        joined('''
          3 2 eighth, <tuplet type="start" number="1" bracket="no">
          <tuplet-actual><tuplet-number>3</tuplet-number><tuplet-type>eighth</tuplet-type></tuplet-actual>
          <tuplet-normal><tuplet-number>2</tuplet-number><tuplet-type>eighth</tuplet-type></tuplet-normal>
          </tuplet>
        '''),
        '3 2 eighth',
        '3 2, <tuplet type="stop" number="1"/>',
      ]);
    });

    test('writes the directions of each bar in time order', () {
      final (:children, bars: _) = read(exported(showcase()));
      List<String> directions(int bar) => [
        for (final (:part, bar: b, :at, length: _, :element) in children)
          if (part == 'P1' &&
              b == bar &&
              {'direction', 'harmony'}.contains(element.name.local))
            '@$at ${compact(element)}',
      ];

      expect(directions(0), [
        joined('''
          @0 <direction placement="above"><direction-type><rehearsal>A</rehearsal>
          </direction-type></direction>
        '''),
        joined('''
          @0 <direction placement="above"><direction-type><segno/></direction-type>
          <sound segno="segno"/></direction>
        '''),
        joined('''
          @0 <direction placement="above"><direction-type><words>Allegro</words>
          </direction-type><direction-type><metronome><beat-unit>quarter</beat-unit>
          <per-minute>120</per-minute></metronome></direction-type>
          <sound tempo="120"/></direction>
        '''),
        joined('''
          @0 <direction placement="below"><direction-type><dynamics><mf/></dynamics>
          </direction-type><sound dynamics="71.111"/></direction>
        '''),
        joined('''
          @0 <direction placement="below"><direction-type><words>dolce</words>
          </direction-type></direction>
        '''),
        joined('''
          @0 <direction placement="below"><direction-type>
          <wedge type="crescendo" number="1"/></direction-type></direction>
        '''),
        joined('''
          @0 <direction placement="below"><direction-type>
          <pedal type="start" line="yes" number="1"/></direction-type></direction>
        '''),
        joined('''
          @1/8 <harmony><root><root-step>D</root-step></root>
          <kind text="maj7">major-seventh</kind>
          <bass><bass-step>E</bass-step><bass-alter>-2</bass-alter></bass></harmony>
        '''),
      ]);
      expect(directions(1), [
        joined('''
          @0 <direction placement="above"><direction-type><words>pizz.</words>
          </direction-type></direction>
        '''),
        joined('''
          @1/2 <direction placement="below"><direction-type>
          <wedge type="diminuendo" number="2"/></direction-type></direction>
        '''),
        joined('''
          @1 <direction placement="below"><direction-type>
          <wedge type="stop" number="1"/></direction-type></direction>
        '''),
        joined('''
          @1 <direction placement="below"><direction-type>
          <wedge type="stop" number="2"/></direction-type></direction>
        '''),
        joined('''
          @1 <direction placement="below"><direction-type>
          <pedal type="stop" line="yes" number="1"/></direction-type></direction>
        '''),
        joined('''
          @1 <direction placement="above"><direction-type><words>To Coda</words>
          </direction-type><sound tocoda="coda"/></direction>
        '''),
        joined('''
          @1 <direction placement="above"><direction-type><words>D.S. al Coda</words>
          </direction-type><sound dalsegno="segno"/></direction>
        '''),
      ]);
      expect(directions(2), [
        joined('''
          @0 <direction placement="above"><direction-type>
          <metronome print-object="no"><beat-unit>quarter</beat-unit><beat-unit-dot/>
          <per-minute>60</per-minute></metronome></direction-type>
          <sound tempo="90"/></direction>
        '''),
        joined('''
          @0 <direction placement="below"><direction-type><dynamics><p/></dynamics>
          </direction-type><sound dynamics="46.667"/></direction>
        '''),
        joined('''
          @0 <direction placement="above"><direction-type>
          <octave-shift type="down" size="8" number="1"/></direction-type></direction>
        '''),
        joined('''
          @0 <direction placement="above"><direction-type><words>poco rit.</words>
          </direction-type><direction-type><dashes type="start" number="1"/>
          </direction-type></direction>
        '''),
        joined('''
          @3/8 <direction placement="above"><direction-type><metronome>
          <beat-unit>quarter</beat-unit><beat-unit-dot/><per-minute>66.5</per-minute>
          </metronome></direction-type><sound tempo="99.75"/></direction>
        '''),
      ]);
      expect(directions(3), [
        joined('''
          @0 <direction placement="above"><direction-type><coda/></direction-type>
          <sound coda="coda"/></direction>
        '''),
        joined('''
          @3/4 <direction placement="above"><direction-type>
          <octave-shift type="stop" size="8" number="1"/></direction-type></direction>
        '''),
        joined('''
          @7/8 <direction placement="above"><direction-type>
          <dashes type="stop" number="1"/></direction-type></direction>
        '''),
        joined('''
          @7/8 <direction placement="above"><direction-type><words>Fine</words>
          </direction-type><sound fine="yes"/></direction>
        '''),
      ]);
      expect(placedAs(read(exported(plain())).children, 'harmony'), [
        joined('''
          P1 m0 @0 <harmony><root><root-step>C</root-step></root>
          <kind text="">major</kind></harmony>
        '''),
      ]);
    });

    test('writes score marks once, in the first shown part', () {
      List<String> marks(Score score) => [
        for (final name in ['rehearsal', 'segno', 'coda', 'metronome', 'sound'])
          for (final line in placedAs(read(exported(score)).children, name))
            if (!line.contains('dynamics')) line.substring(0, 2),
      ];

      expect(marks(showcase()), List.filled(14, 'P1'));
      expect(marks(hidePart(showcase(), 0)), List.filled(14, 'P3'));
    });

    test('names a jump by where it goes and then where it ends', () {
      String jump(Jump jump) {
        final score = changeBar(
          blankScore(bars: 1),
          0,
          (column) => column.copyWith(navigation: Seq([jump])),
        );
        return placedAs(
          read(exported(score)).children,
          'direction',
        ).where((line) => line.contains('<words>')).single;
      }

      expect(
        jump(const Jump(JumpTarget.start)),
        joined('''
          P1 m0 @1 <direction placement="above"><direction-type><words>D.C.</words>
          </direction-type><sound dacapo="yes"/></direction>
        '''),
      );
      expect(
        jump(const Jump(JumpTarget.start, then: JumpThen.toFine)),
        contains('<words>D.C. al Fine</words>'),
      );
      expect(
        jump(const Jump(JumpTarget.start, then: JumpThen.toCoda)),
        contains('<words>D.C. al Coda</words>'),
      );
      expect(
        jump(const Jump(JumpTarget.segno)),
        joined('''
          P1 m0 @1 <direction placement="above"><direction-type><words>D.S.</words>
          </direction-type><sound dalsegno="segno"/></direction>
        '''),
      );
      expect(
        jump(const Jump(JumpTarget.segno, then: JumpThen.toFine)),
        contains('<words>D.S. al Fine</words>'),
      );
      expect(
        jump(const Jump(JumpTarget.start, text: 'Da capo')),
        contains('<words>Da capo</words>'),
      );
    });

    test('writes repeats, endings and barlines', () {
      final xml = exported(showcase());

      expect(
        [
          for (final (bar, measure)
              in xml.rootElement
                  .getElement('part')!
                  .findElements('measure')
                  .indexed)
            for (final barline in measure.findElements('barline'))
              '$bar ${compact(barline)}',
        ],
        [
          joined('''
            0 <barline location="left"><bar-style>heavy-light</bar-style>
            <repeat direction="forward"/></barline>
          '''),
          '1 <barline location="left"><ending number="1" type="start">1.</ending></barline>',
          joined('''
            1 <barline location="right"><bar-style>light-light</bar-style>
            <ending number="1" type="stop"/><repeat direction="backward" times="3"/></barline>
          '''),
          '2 <barline location="left"><ending number="2, 3" type="start">2, 3.</ending></barline>',
          '2 <barline location="right"><ending number="2, 3" type="discontinue"/></barline>',
          '3 <barline location="right"><bar-style>light-heavy</bar-style></barline>',
        ],
      );
      final repeat = changeBar(
        blankScore(bars: 1),
        0,
        (column) => column.copyWith(repeatEnd: () => const RepeatEnd()),
      );
      expect(each(exported(repeat).rootElement, 'barline'), [
        joined('''
          <barline location="right"><bar-style>light-heavy</bar-style>
          <repeat direction="backward"/></barline>
        '''),
      ]);
    });

    test('names every barline style', () {
      String? style(Barline barline) => measure(
        exported(
          changeBar(
            blankScore(bars: 1),
            0,
            (column) => column.copyWith(barline: barline),
          ),
        ),
        'P1',
        0,
      ).getElement('barline')?.getElement('bar-style')?.innerText;

      expect(
        [for (final barline in Barline.values) style(barline)],
        [
          null,
          'light-light',
          'light-heavy',
          'dashed',
          'dotted',
          'heavy',
          'none',
        ],
      );
    });

    test('writes system and page breaks in every part', () {
      final xml = exported(showcase());

      expect(
        [
          for (final part in ['P1', 'P2', 'P3'])
            for (final bar in [0, 1, 2, 3])
              for (final print in measure(xml, part, bar).findElements('print'))
                '$part $bar ${compact(print)}',
        ],
        [
          'P1 1 <print new-system="yes"/>',
          'P1 3 <print new-page="yes"/>',
          'P2 1 <print new-system="yes"/>',
          'P2 3 <print new-page="yes"/>',
          'P3 1 <print new-system="yes"/>',
          'P3 3 <print new-page="yes"/>',
        ],
      );
    });

    test('keeps a hidden part and marks its staves unprinted', () {
      final xml = exported(showcase());

      expect(each(measure(xml, 'P2', 0), 'staff-details'), [
        '<staff-details print-object="no"/>',
      ]);
      expect(
        [
          for (final details in measure(xml, 'P1', 0).findAllElements(
            'staff-details',
          ))
            details.getAttribute('print-object'),
        ],
        [null],
      );
    });

    test('writes the open strings of a string instrument, lowest first', () {
      final xml = exported(blankScore());

      expect(each(measure(xml, 'P1', 0), 'staff-details'), [
        joined('''
          <staff-details>
            <staff-tuning line="1">
              <tuning-step>F</tuning-step>
              <tuning-octave>3</tuning-octave>
            </staff-tuning>
            <staff-tuning line="2">
              <tuning-step>B</tuning-step>
              <tuning-alter>-1</tuning-alter>
              <tuning-octave>3</tuning-octave>
            </staff-tuning>
          </staff-details>'''),
      ]);
      expect(each(measure(xml, 'P1', 1), 'staff-details'), isEmpty);
    });

    test('attaches slurs, glissandi and trill lines to notes', () {
      final (:children, bars: _) = read(exported(showcase()));

      expect(
        [
          for (final name in ['slur', 'glissando', 'wavy-line'])
            ...placedAs(children, name),
        ],
        [
          'P1 m1 @0 <slur type="start" number="1" line-type="dashed"/>',
          'P1 m1 @1/4 <slur type="stop" number="1"/>',
          'P3 m2 @0 <slur type="start" number="1"/>',
          'P3 m2 @3/8 <slur type="stop" number="1"/>',
          'P1 m1 @1/2 <glissando type="start" number="1"/>',
          'P1 m3 @0 <glissando type="stop" number="1"/>',
          'P1 m1 @1/4 <wavy-line type="start" number="1"/>',
          'P1 m1 @1/4 <wavy-line type="stop" number="1"/>',
        ],
      );
      expect(
        placedAs(
          children,
          'ornaments',
        ).where((line) => line.startsWith('P1 m1')),
        [
          joined('''
            P1 m1 @1/4 <ornaments><trill-mark/>
            <wavy-line type="start" number="1"/>
            <wavy-line type="stop" number="1"/></ornaments>
          '''),
        ],
      );
    });

    test('reuses a spanner number once its spanner stops', () {
      final quarters = [
        for (final id in [1, 2, 3, 4]) chordOf(id, 'G4'),
      ];
      var score = sessionWith([
        quarters,
        [
          for (final chord in quarters)
            chord.copyWith(id: EventId(chord.id.value + 10)),
        ],
      ]).score;
      ScorePoint beat(int bar, int quarter) =>
          pointAt(score, bar, at(quarter, 4));
      score = withSlur(score, beat(0, 0), beat(0, 1));
      score = withSlur(score, beat(0, 1), beat(0, 2));
      score = withSlur(score, beat(0, 3), beat(1, 0));

      expect(placedAs(read(exported(score)).children, 'slur'), [
        'P1 m0 @0 <slur type="start" number="1"/>',
        'P1 m0 @1/4 <slur type="stop" number="1"/>',
        'P1 m0 @1/4 <slur type="start" number="2"/>',
        'P1 m0 @1/2 <slur type="stop" number="2"/>',
        'P1 m0 @3/4 <slur type="start" number="1"/>',
        'P1 m1 @0 <slur type="stop" number="1"/>',
      ]);
    });

    test('reuses a number its spanner freed in an earlier bar', () {
      var score = sessionWith([
        for (final bar in [0, 1])
          [
            for (final i in [1, 2, 3, 4]) chordOf(bar * 10 + i, 'G4'),
          ],
      ]).score;
      score = withSlur(
        score,
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(3, 4)),
      );
      score = withSlur(
        score,
        pointAt(score, 1, Moment.zero),
        pointAt(score, 1, at(3, 4)),
      );

      expect(placedAs(read(exported(score)).children, 'slur'), [
        'P1 m0 @0 <slur type="start" number="1"/>',
        'P1 m0 @3/4 <slur type="stop" number="1"/>',
        'P1 m1 @0 <slur type="start" number="1"/>',
        'P1 m1 @3/4 <slur type="stop" number="1"/>',
      ]);
    });

    test('keeps a number until its stop is written', () {
      var score = blankScore(parts: const [piano]);
      score = fill(score, 1, staff: 1, [
        for (var i = 0; i < 4; i++) chordOf(10 + i, 'C3'),
      ]);
      Spanner hairpin(int id, int staff, ScorePoint first, ScorePoint last) =>
          Spanner(
            id: SpannerId(id),
            kind: const Hairpin(crescendo: true),
            staff: score.staves[staff].id,
            first: first,
            last: last,
          );
      score = score.copyWith(
        spanners: Seq([
          hairpin(
            1,
            1,
            pointAt(score, 0, Moment.zero),
            pointAt(score, 1, Moment.zero),
          ),
          hairpin(
            2,
            0,
            pointAt(score, 1, at(1, 2)),
            pointAt(score, 1, at(3, 4)),
          ),
        ]),
      );

      expectPaired(read(exported(score)).children, 'wedge');
    });

    test('writes an octave line with its size and direction', () {
      List<String> lines(OctaveShift shift) {
        var score = blankScore(bars: 1);
        score = withOctaveLine(
          score,
          shift,
          pointAt(score, 0, Moment.zero),
          pointAt(score, 0, Moment.zero),
        );
        return placedAs(
          read(exported(score)).children,
          'direction',
        ).where((line) => line.contains('octave-shift')).toList();
      }

      expect(lines(OctaveShift.up15), [
        joined('''
          P1 m0 @0 <direction placement="above"><direction-type>
          <octave-shift type="down" size="15" number="1"/></direction-type></direction>
        '''),
        joined('''
          P1 m0 @1 <direction placement="above"><direction-type>
          <octave-shift type="stop" size="15" number="1"/></direction-type></direction>
        '''),
      ]);
      expect(lines(OctaveShift.down8), [
        joined('''
          P1 m0 @0 <direction placement="below"><direction-type>
          <octave-shift type="up" size="8" number="1"/></direction-type></direction>
        '''),
        joined('''
          P1 m0 @1 <direction placement="below"><direction-type>
          <octave-shift type="stop" size="8" number="1"/></direction-type></direction>
        '''),
      ]);
    });

    test('keeps every note, bar and spanner through random edits', () {
      for (final seed in [1, 2, 3]) {
        final random = Random(seed);
        var score = blankScore(parts: const [morinKhuur, clarinet], bars: 4);
        for (var step = 0; step < 100; step++) {
          score = randomEdit(score, random);
          final (:children, :bars) = read(exported(score));
          final where = 'seed $seed, step $step';

          expect(notesIn(children), notesOf(score), reason: where);
          expect(bars, barsOf(score), reason: where);
          for (final (name, isKind) in [
            ('slur', (SpannerKind kind) => kind is Slur),
            ('octave-shift', (SpannerKind kind) => kind is OctaveLine),
          ]) {
            expectPaired(children, name, reason: where);
            for (final (p, part) in score.parts.indexed) {
              expect(
                startsOf(children, name, 'P${p + 1}'),
                score.spanners
                    .where(
                      (s) =>
                          isKind(s.kind) &&
                          part.staves.any((staff) => staff.id == s.staff),
                    )
                    .length,
                reason: '$where, $name in P${p + 1}',
              );
            }
          }
        }
      }
    });
  });
}
