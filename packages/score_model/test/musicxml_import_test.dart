import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:score_model/score_model.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'random_edits.dart';
import 'support.dart';

final golden = File('test/golden/showcase.musicxml');

Score reloaded(Score score) =>
    scoreFromJson(jsonDecode(jsonEncode(scoreToJson(score))));

/// [xml] read from another app, checking that the score saves and that
/// reading its export gives the same export.
Score imported(String xml) {
  final score = scoreFromMusicXml(xml);
  final text = scoreToMusicXml(score);

  expect(scoreToMusicXml(scoreFromMusicXml(text)), text);
  expect(() => reloaded(score), returnsNormally);
  return score;
}

String partwise(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<score-partwise version="4.0">$body</score-partwise>';

String scorePart(String id, {String name = 'Flute', String more = ''}) =>
    '<score-part id="$id"><part-name>$name</part-name>$more</score-part>';

/// A `<part>` whose bars each join their fragments.
String part(String id, List<List<String>> measures) => [
  '<part id="$id">',
  for (final (i, fragments) in measures.indexed)
    '<measure number="${i + 1}">${fragments.join()}</measure>',
  '</part>',
].join();

/// Opening attributes, with a quarter as [divisions].
String opening({
  int divisions = 4,
  int fifths = 0,
  int beats = 4,
  String clef = '<clef><sign>G</sign><line>2</line></clef>',
  String more = '',
}) => [
  '<attributes><divisions>$divisions</divisions>',
  '<key><fifths>$fifths</fifths></key>',
  '<time><beats>$beats</beats><beat-type>4</beat-type></time>',
  '$clef$more</attributes>',
].join();

/// One flute whose bars join their fragments.
String flute(List<List<String>> measures) => partwise(
  '<part-list>${scorePart('P1')}</part-list>${part('P1', measures)}',
);

/// One two-staff keyboard part whose bars join their fragments.
String keyboard(List<List<String>> measures) => partwise(
  '<part-list>${scorePart('P1', name: 'Piano')}</part-list>'
  '${part('P1', measures)}',
);

/// Opening attributes of a two-staff part, with a quarter as 4 divisions.
final String grand = opening(
  clef:
      '<staves>2</staves>'
      '<clef number="1"><sign>G</sign><line>2</line></clef>'
      '<clef number="2"><sign>F</sign><line>4</line></clef>',
);

/// A `<note>` of [pitch], or a rest for `rest`, lasting [duration]
/// divisions and written as [type], with [more] children.
String note(String pitch, num duration, String type, [String more = '']) {
  final head = pitch == 'rest' ? '<rest/>' : _pitch(Pitch.parse(pitch));
  return '<note>$head<duration>$duration</duration>'
      '<type>$type</type>$more</note>';
}

/// An `<unpitched>` note at [step] and [octave].
String unpitched(String step, int octave, num duration, String type) =>
    '<note><unpitched><display-step>$step</display-step>'
    '<display-octave>$octave</display-octave></unpitched>'
    '<duration>$duration</duration><type>$type</type></note>';

String _pitch(Pitch pitch) {
  final quarterTones = pitch.alter.quarterTones;
  final alter = quarterTones.isEven
      ? '${quarterTones ~/ 2}'
      : '${quarterTones / 2}';
  return '<pitch><step>${pitch.step.name.toUpperCase()}</step>'
      '${quarterTones == 0 ? '' : '<alter>$alter</alter>'}'
      '<octave>${pitch.octave}</octave></pitch>';
}

String direction(List<String> types, {String more = ''}) => [
  '<direction>',
  for (final type in types) '<direction-type>$type</direction-type>',
  '$more</direction>',
].join();

String metronome(int bpm) =>
    '<metronome><beat-unit>quarter</beat-unit>'
    '<per-minute>$bpm</per-minute></metronome>';

String backup(num duration) =>
    '<backup><duration>$duration</duration></backup>';

String forward(num duration, [String more = '']) =>
    '<forward><duration>$duration</duration>$more</forward>';

String barline(String location, String children) =>
    '<barline location="$location">$children</barline>';

const triplet =
    '<time-modification><actual-notes>3</actual-notes>'
    '<normal-notes>2</normal-notes></time-modification>';

List<String> items(
  Score score,
  int bar, {
  int staff = 0,
  VoiceSlot slot = VoiceSlot.one,
}) => describe(score.measures[bar].staves[staff].voice(slot)!.items);

/// The bars [score] plays, in order, by their place in the score.
List<int> playOrder(Score score) => [
  for (final bar in PlaybackCompiler().compile(score).bars)
    score.indexOf(bar.measure),
];

/// The jump of [bar]: where it goes, where it ends and its own words.
(JumpTarget, JumpThen, String?) jumpIn(Score score, int bar) {
  final jump = score.measures[bar].navigation.whereType<Jump>().single;
  return (jump.target, jump.then, jump.text);
}

List<ChordEvent> chordsIn(Score score, int bar) => [
  for (final voice in score.measures[bar].staves.first.voices)
    for (final item in voice.items)
      if (item case final ChordEvent chord) chord,
];

/// The beam groups of the first voice of [bar], as event indexes.
List<List<int>> beamsOf(Score score, int bar) {
  final voice = score
      .measureView(score.measures[bar].id)
      .staves
      .first
      .voices
      .first;
  final ids = [for (final timed in voice.events) timed.event.id];
  return [
    for (final group in voice.beams)
      [for (final id in group.events) ids.indexOf(id)],
  ];
}

List<AccidentalRequest> requestsIn(Score score, int bar) => [
  for (final chord in chordsIn(score, bar))
    (chord.notes.single as PitchedNote).accidental,
];

List<String> marksIn(Score score, int bar) => [
  for (final direction in score.measures[bar].staves.first.directions)
    mark(direction),
];

String kindName(SpannerKind kind) => switch (kind) {
  Slur(:final dashed) => dashed ? 'dashed slur' : 'slur',
  Hairpin(:final crescendo) => crescendo ? 'crescendo' : 'diminuendo',
  OctaveLine(:final shift) => shift.name,
  TrillLine() => 'trill',
  TempoLine(:final text, :final factor) => '$text $factor',
  PedalLine() => 'pedal',
  Glissando() => 'glissando',
};

String pointName(Score score, ScorePoint point) =>
    '${score.indexOf(point.measure)}@${point.offset.wholeNotes}';

/// Every spanner as `kind bar@offset-bar@offset`.
List<String> spannersOf(Score score) => [
  for (final Spanner(:kind, :first, :last) in score.spanners)
    '${kindName(kind)} ${pointName(score, first)}-${pointName(score, last)}',
];

final String c5 = note('C5', 12, 'quarter');
final String d5 = note('D5', 12, 'quarter');
final String e5 = note('E5', 24, 'half');

/// A one-bar flute document every refusal edits: C5 and D5 quarters and an
/// E5 half, with a quarter as 12 divisions.
final String base = partwise(
  '<part-list>${scorePart('P1', more: '<score-instrument id="P1-I1"><instrument-name>Flute</instrument-name></score-instrument>'
      '<midi-instrument id="P1-I1"><midi-channel>1</midi-channel><midi-program>74</midi-program></midi-instrument>')}</part-list>'
  '${part('P1', [
    [opening(divisions: 12), c5, d5, e5],
  ])}',
);

const bar0 = '/score-partwise/part/measure';

typedef Refusal = ({
  String rule,
  List<(String, String)> edits,
  String at,
  Matcher message,
});

Refusal refuses(
  String rule,
  List<(String, String)> edits, {
  required String at,
  Matcher? message,
}) => (rule: rule, edits: edits, at: at, message: message ?? equals(rule));

final List<Refusal> refusals = [
  refuses(
    'malformed XML',
    [('</score-partwise>', '')],
    at: '/',
    message: startsWith('not well-formed XML: '),
  ),
  refuses(
    'only score-partwise documents are read, not score-timewise',
    [
      ('<score-partwise version="4.0">', '<score-timewise version="4.0">'),
      ('</score-partwise>', '</score-timewise>'),
    ],
    at: '/score-timewise',
  ),
  refuses(
    'expected a score-partwise document',
    [
      ('<score-partwise version="4.0">', '<opus>'),
      ('</score-partwise>', '</opus>'),
    ],
    at: '/opus',
  ),
  refuses(
    'missing',
    [('<part-name>Flute</part-name>', '')],
    at: '/score-partwise/part-list/score-part/part-name',
  ),
  refuses(
    'a duration before any divisions',
    [('<divisions>12</divisions>', '')],
    at: '$bar0/note[1]/duration',
  ),
  refuses(
    'backs up past the bar start',
    [(c5, '$c5${backup(20)}')],
    at: '$bar0/backup/duration',
  ),
  refuses(
    'overlaps the previous note in its voice',
    [(c5, '$c5${backup(6)}${note('A4', 12, 'quarter')}')],
    at: '$bar0/note[2]',
  ),
  refuses(
    'the duration does not match the written value',
    [(c5, note('C5', 11, 'quarter'))],
    at: '$bar0/note[1]/duration',
  ),
  refuses(
    'a part has 1 to 99 staves',
    [
      (
        '<divisions>12</divisions>',
        '<divisions>12</divisions><staves>100</staves>',
      ),
    ],
    at: '$bar0/attributes/staves',
  ),
  refuses(
    'fifths outside -7..7',
    [('<fifths>0</fifths>', '<fifths>8</fifths>')],
    at: '$bar0/attributes/key/fifths',
  ),
  refuses(
    'not a power of two up to 128',
    [('<beat-type>4</beat-type>', '<beat-type>3</beat-type>')],
    at: '$bar0/attributes/time/beat-type',
  ),
  refuses(
    'senza-misura is not supported',
    [
      (
        '<time><beats>4</beats><beat-type>4</beat-type></time>',
        '<time><senza-misura/></time>',
      ),
    ],
    at: '$bar0/attributes/time',
  ),
  refuses(
    'no such clef',
    [('<sign>G</sign>', '<sign>TAB</sign>')],
    at: '$bar0/attributes/clef',
  ),
  refuses(
    'not a quarter-tone alteration in -2..2',
    [('<step>C</step>', '<step>C</step><alter>3</alter>')],
    at: '$bar0/note[1]/pitch/alter',
  ),
  refuses(
    'more than 4 tremolo strokes',
    [
      (
        c5,
        note(
          'C5',
          12,
          'quarter',
          '<notations><ornaments><tremolo type="single">5</tremolo></ornaments></notations>',
        ),
      ),
    ],
    at: '$bar0/note[1]/notations/ornaments/tremolo',
  ),
  refuses(
    'no score-part P2',
    [('<part id="P1">', '<part id="P2">')],
    at: '/score-partwise/part/@id',
  ),
  refuses(
    'has 0 bars where the first part has 1',
    [
      ('</part-list>', '${scorePart('P2')}</part-list>'),
      (
        '</part></score-partwise>',
        '</part><part id="P2"></part></score-partwise>',
      ),
    ],
    at: '/score-partwise/part[2]',
  ),
  refuses(
    'stops a tuplet that is not open',
    [
      (
        c5,
        note(
          'C5',
          12,
          'quarter',
          '<notations><tuplet type="stop"/></notations>',
        ),
      ),
    ],
    at: '$bar0/note[1]/notations/tuplet',
  ),
  refuses(
    'the tuplet never stops in its bar',
    [
      (
        e5,
        note(
          'E5',
          16,
          'half',
          '$triplet<notations><tuplet type="start"/></notations>',
        ),
      ),
    ],
    at: '$bar0/note[3]/notations/tuplet',
  ),
  refuses(
    'a chord note follows a rest',
    [
      (c5, note('rest', 12, 'quarter')),
      (d5, note('D5', 12, 'quarter', '<chord/>')),
    ],
    at: '$bar0/note[2]/chord',
  ),
  refuses(
    'a measure rest shares its voice',
    [(c5, '<note><rest measure="yes"/><duration>12</duration></note>')],
    at: '$bar0/note[1]/rest',
  ),
  refuses(
    'voices 1 and 5 share a slot on staff 1',
    [(e5, '$e5${backup(48)}${note('rest', 48, 'whole', '<voice>5</voice>')}')],
    at: '$bar0/note[4]/voice',
  ),
  refuses(
    'ending numbers are integers from 1',
    [
      (
        '<attributes>',
        '${barline('left', '<ending number="0" type="start"/>')}<attributes>',
      ),
    ],
    at: '$bar0/barline/ending/@number',
  ),
  refuses(
    'size is 8, 15 or 22',
    [
      (c5, '${direction(['<octave-shift type="down" size="7"/>'])}$c5'),
    ],
    at: '$bar0/direction/direction-type/octave-shift/@size',
  ),
  refuses(
    'outside 1..128',
    [('<midi-program>74</midi-program>', '<midi-program>200</midi-program>')],
    at: '/score-partwise/part-list/score-part/midi-instrument/midi-program',
  ),
  refuses(
    'a pitched note in a percussion part',
    [
      (
        '<midi-program>74</midi-program>',
        '<midi-program>1</midi-program><midi-unpitched>39</midi-unpitched>',
      ),
    ],
    at: '$bar0/note[1]/pitch',
  ),
  refuses(
    'a midi-unpitched outside 1..128',
    [
      (
        '<midi-program>74</midi-program>',
        '<midi-program>1</midi-program><midi-unpitched>0</midi-unpitched>',
      ),
    ],
    at: '/score-partwise/part-list/score-part/midi-instrument/midi-unpitched',
    message: equals('outside 1..128'),
  ),
  refuses(
    'a midi-bank outside 1..128',
    [
      (
        '<midi-program>74</midi-program>',
        '<midi-bank>0</midi-bank><midi-program>74</midi-program>',
      ),
    ],
    at: '/score-partwise/part-list/score-part/midi-instrument/midi-bank',
    message: equals('outside 1..128'),
  ),
  refuses(
    'no drum instrument for this part',
    [(c5, unpitched('C', 5, 12, 'quarter'))],
    at: '$bar0/note[1]/unpitched',
  ),
  refuses(
    'the note names no drum of the kit',
    [
      (
        '<midi-program>74</midi-program>',
        '<midi-program>1</midi-program><midi-unpitched>39</midi-unpitched>',
      ),
      (
        '</score-instrument>',
        '</score-instrument><score-instrument id="P1-I2">'
            '<instrument-name>Kick</instrument-name></score-instrument>',
      ),
      (
        '</midi-instrument>',
        '</midi-instrument><midi-instrument id="P1-I2">'
            '<midi-program>1</midi-program><midi-unpitched>37</midi-unpitched>'
            '</midi-instrument>',
      ),
      (c5, unpitched('C', 5, 12, 'quarter')),
    ],
    at: '$bar0/note[1]/unpitched',
  ),
  refuses(
    'the kit names Snare twice',
    [
      (
        '<instrument-name>Flute</instrument-name>',
        '<instrument-name>Snare</instrument-name>',
      ),
      (
        '<midi-program>74</midi-program>',
        '<midi-program>1</midi-program><midi-unpitched>39</midi-unpitched>',
      ),
      (
        '</score-instrument>',
        '</score-instrument><score-instrument id="P1-I2">'
            '<instrument-name>Snare</instrument-name></score-instrument>',
      ),
      (
        '</midi-instrument>',
        '</midi-instrument><midi-instrument id="P1-I2">'
            '<midi-program>1</midi-program><midi-unpitched>38</midi-unpitched>'
            '</midi-instrument>',
      ),
    ],
    at: '/score-partwise/part-list/score-part/score-instrument[2]/instrument-name',
  ),
  refuses(
    'parts disagree on the meter',
    [
      ('</part-list>', '${scorePart('P2', name: 'Oboe')}</part-list>'),
      (
        '</part></score-partwise>',
        '</part>${part('P2', [
          [opening(divisions: 12, beats: 3), note('C5', 36, 'half', '<dot/>')],
        ])}</score-partwise>',
      ),
    ],
    at: '/score-partwise/part[2]/measure/attributes/time',
  ),
  refuses(
    'a part keeps one transposition',
    [
      (
        '</measure>',
        '</measure><measure number="2"><attributes><transpose>'
            '<diatonic>-1</diatonic><chromatic>-2</chromatic></transpose>'
            '</attributes>${note('C5', 48, 'whole')}</measure>',
      ),
    ],
    at: '/score-partwise/part/measure[2]/attributes/transpose',
  ),
  refuses(
    'a chord note lasts as long as its chord',
    [(d5, note('D5', 6, 'eighth', '<chord/>'))],
    at: '$bar0/note[2]/duration',
  ),
  refuses(
    'a bar holds a whole number of 128th notes',
    [(e5, '$e5${forward(1)}')],
    at: bar0,
  ),
  refuses(
    'a bar lasts at most 64 whole notes',
    [(e5, '$e5${forward(3072)}')],
    at: bar0,
  ),
  refuses(
    'no rest value fits the gap',
    [
      (c5, '$c5${forward(1)}'),
      (
        e5,
        '${note('E5', 12, 'quarter')}${backup(37)}'
            '${note('C4', 48, 'whole', '<voice>2</voice>')}',
      ),
    ],
    at: '$bar0/note[2]',
  ),
  refuses(
    'a tuplet note a whole division off',
    [
      (
        c5,
        '${note('C5', 5, 'eighth', '$triplet<notations><tuplet type="start"/></notations>')}'
            '${note('D5', 4, 'eighth', triplet)}'
            '${note('E5', 3, 'eighth', '$triplet<notations><tuplet type="stop"/></notations>')}',
      ),
    ],
    at: '$bar0/note[1]/duration',
    message: equals('the duration does not match the written value'),
  ),
];

/// [text] with each `(from, to)` edit made once, failing when `from` is
/// not in the text.
String edited(String text, List<(String, String)> edits) {
  var result = text;
  for (final (from, to) in edits) {
    expect(result, contains(from), reason: 'edit anchor $from');
    result = result.replaceFirst(from, to);
  }
  return result;
}

/// [xml] with one random element removed, emptied, given a strange value
/// or duplicated.
String damaged(String xml, Random random) {
  final document = XmlDocument.parse(xml);
  final elements = document.rootElement.descendantElements.toList();
  final target = elements[random.nextInt(elements.length)];
  final siblings = target.parent!.children;
  switch (random.nextInt(4)) {
    case 0:
      target.remove();
    case 1:
      target.children.clear();
    case 2:
      target.children
        ..clear()
        ..add(XmlText(pick(random, ['0', '-1', '3', '99', '1.5', 'x', ''])));
    default:
      siblings.insert(siblings.indexOf(target), target.copy());
  }
  return document.toXmlString();
}

void main() {
  group('scoreFromMusicXml', () {
    test('reads the golden file back to the same document', () {
      final text = golden.readAsStringSync();

      expect(scoreToMusicXml(scoreFromMusicXml(text)), text);
    });

    test('reads the showcase header, kit and bars', () {
      final score = scoreFromMusicXml(golden.readAsStringSync());
      final [violin, clarinetPart, kit] = score.parts.toList();

      expect(
        [
          score.meta.title,
          score.meta.subtitle,
          score.meta.composer,
          score.meta.lyricist,
          score.meta.copyright,
        ],
        ['Showcase', 'for testing', 'Anon.', 'Anon.', 'CC0'],
      );
      expect(
        [
          for (final part in score.parts)
            (part.name, part.shortName, part.hidden, part.instrument.key),
        ],
        [
          ('Violin', 'Vln.', false, ''),
          ('Clarinet in B♭', '', true, ''),
          ('Drums', '', false, ''),
        ],
      );
      expect(violin.instrument.program, 40);
      expect(violin.instrument.strings, [
        Pitch.parse('G3'),
        Pitch.parse('D4'),
        Pitch.parse('A4'),
        Pitch.parse('E5'),
      ]);
      expect(
        (violin.instrument.lowest, violin.instrument.highest),
        (null, null),
      );
      expect(clarinetPart.instrument.transposition, const Interval(-1, -2));
      expect(clarinetPart.instrument.program, 71);
      expect((kit.instrument.program, kit.instrument.bank), (0, 128));
      expect(kit.instrument.clef, Clef.percussion);
      expect(kit.staves.single.lines, 1);
      expect(
        [
          for (final drum in kit.instrument.drums)
            (drum.name, '${drum.position}', drum.midiKey, drum.head),
        ],
        [
          ('Snare', 'C5', 38, NoteHead.normal),
          ('Side stick', 'C5', 37, NoteHead.cross),
          ('Bass drum', 'F4', 36, NoteHead.normal),
        ],
      );
      expect(
        [
          for (final column in score.measures)
            (column.meter, column.key.fifths, column.length.wholeNotes),
        ],
        [
          (Meter.common, 2, Fraction(1, 4)),
          (Meter.common, 2, Fraction.one),
          (Meter.sixEight, -3, Fraction(3, 4)),
          (const Meter([3, 2, 2], 8), -3, Fraction(7, 8)),
        ],
      );
      expect(
        [
          for (final column in score.measures)
            (column.keyDisplay, column.meterDisplay),
        ],
        [
          (SignatureDisplay.auto, SignatureDisplay.auto),
          (SignatureDisplay.auto, SignatureDisplay.restated),
          (SignatureDisplay.auto, SignatureDisplay.auto),
          (SignatureDisplay.restated, SignatureDisplay.auto),
        ],
      );
      expect(
        spannersOf(score),
        containsAll([
          'poco rit. 0.75 2@0-3@3/4',
          'dashed slur 1@0-1@1/4',
          'glissando 1@1/2-3@0',
        ]),
      );
      final first = chordsIn(score, 0).first;
      expect(
        [
          for (final note in first.notes.cast<PitchedNote>())
            (note.accidental, note.head, note.fingering, note.string),
        ],
        [
          (AccidentalRequest.auto, NoteHead.normal, 1, 1),
          (AccidentalRequest.cautionary, NoteHead.diamond, null, null),
        ],
      );
      expect((first.ornament, first.bowing), (Ornament.trill, Bowing.down));
      expect(first.articulations, {
        Articulation.accent,
        Articulation.staccato,
      });
    });

    test('reads back every score the edits make', () {
      // Seed 102 plays a jump with words of its own to a Fine.
      for (final seed in [1, 2, 3, 22, 102]) {
        final random = Random(seed);
        var score = blankScore(
          parts: const [morinKhuur, clarinet, drums, piano],
          bars: 4,
        );
        for (var step = 0; step < 100; step++) {
          score = randomEdit(score, random);
          final text = scoreToMusicXml(score);
          final where = 'seed $seed, step $step';
          final back = scoreFromMusicXml(text);

          expect(scoreToMusicXml(back), text, reason: where);
          expect(playOrder(back), playOrder(score), reason: where);
          expect(() => reloaded(back), returnsNormally, reason: where);
        }
      }
    });

    test('throws only ScoreFormatException, and builds only valid scores', () {
      final text = golden.readAsStringSync();
      for (var seed = 0; seed < 300; seed++) {
        final xml = damaged(text, Random(seed));
        final Score score;
        try {
          score = scoreFromMusicXml(xml);
        } on ScoreFormatException {
          continue;
        } on Object catch (error, trace) {
          fail('seed $seed threw $error\n$trace');
        }
        expect(() => reloaded(score), returnsNormally, reason: 'seed $seed');
      }
    });

    test('fills a sparse file with defaults', () {
      final score = imported(
        flute([
          [
            '<attributes><divisions> 1 </divisions></attributes>',
            '<note><rest/><duration> 4 </duration></note>',
          ],
          [],
        ]),
      );
      final instrument = score.parts.single.instrument;

      expect(
        (score.parts.single.name, instrument.program, instrument.key),
        (
          'Flute',
          0,
          '',
        ),
      );
      expect(
        [
          for (final column in score.measures)
            (column.meter, column.key.fifths, column.irregularLength),
        ],
        [(Meter.fourFour, 0, null), (Meter.fourFour, 0, null)],
      );
      expect(score.measures[0].staves.single.clef, Clef.treble);
      expect(items(score, 0), ['measure-rest']);
      expect(items(score, 1), ['measure-rest']);
    });

    test('reads voices placed with backup and forward, and chords', () {
      final score = imported(
        flute([
          [
            opening(),
            note('G5', 8, 'half', '<voice>1</voice>'),
            note('C5', 8, 'half', '<chord/><voice>1</voice>'),
            note('C5', 8, 'half', '<chord/><voice>1</voice>'),
            note('D5', 8, 'half', '<voice>1</voice>'),
            backup(16),
            forward(4, '<voice>2</voice>'),
            note('E4', 4, 'quarter', '<voice>2</voice>'),
          ],
        ]),
      );

      expect(items(score, 0), ['C5+G5/half', 'D5/half']);
      expect(items(score, 0, slot: VoiceSlot.two), [
        'gap 1/4',
        'E4/quarter',
        'gap 1/2',
      ]);
    });

    test('fills a missing voice one with hidden rests', () {
      final score = imported(
        flute([
          [opening(), note('E4', 16, 'whole', '<voice>2</voice>')],
        ]),
      );
      final voiceOne = score.measures[0].staves.single.voices.first;

      expect(items(score, 0), ['rest/whole']);
      expect((voiceOne.items.single as RestEvent).hidden, isTrue);
      expect(items(score, 0, slot: VoiceSlot.two), ['E4/whole']);
    });

    test('reads nested tuplets as MuseScore writes them', () {
      const nine =
          '<time-modification><actual-notes>9</actual-notes>'
          '<normal-notes>4</normal-notes></time-modification>';
      final score = imported(
        flute([
          [
            opening(divisions: 9),
            note(
              'A4',
              3,
              'eighth',
              '$triplet<notations><tuplet type="start" bracket="yes"/></notations>',
            ),
            note('rest', 3, 'eighth', triplet),
            note(
              'Bb4',
              1,
              '16th',
              '$nine<notations><tuplet type="start" number="2"/></notations>',
            ),
            note('C5', 1, '16th', nine),
            note(
              'rest',
              1,
              '16th',
              '$nine<notations><tuplet type="stop" number="2"/>'
                  '<tuplet type="stop" number="1"/></notations>',
            ),
            note('C5', 27, 'half', '<dot/>'),
          ],
        ]),
      );
      final outer =
          score.measures[0].staves.single.voices.single.items.first as Tuplet;

      expect(items(score, 0), [
        '3:2[A4/eighth, rest/eighth, 3:2[Bb4/sixteenth, C5/sixteenth, rest/sixteenth]]',
        'C5/half.',
      ]);
      expect(
        (outer.bracket, (outer.members.last as Tuplet).bracket),
        (
          TupletBracket.shown,
          TupletBracket.auto,
        ),
      );
    });

    test('groups notes with only a time modification into tuplets', () {
      final score = imported(
        flute([
          [
            opening(divisions: 3, beats: 2),
            for (final pitch in ['C5', 'D5', 'E5', 'F5', 'G5', 'A5'])
              note(pitch, 1, 'eighth', triplet),
          ],
        ]),
      );

      expect(items(score, 0), [
        '3:2[C5/eighth, D5/eighth, E5/eighth]',
        '3:2[F5/eighth, G5/eighth, A5/eighth]',
      ]);
    });

    test('keeps one tempo mark per time when every part writes it', () {
      final andante = direction([
        '<words>Andante</words>',
        metronome(90),
      ], more: '<sound tempo="90"/>');
      final score = imported(
        partwise(
          '<part-list>${scorePart('P1')}${scorePart('P2', name: 'Oboe')}</part-list>'
          '${part('P1', [
            [opening(), andante, note('C5', 16, 'whole')],
          ])}'
          '${part('P2', [
            [
              opening(),
              andante,
              note('C5', 8, 'half'),
              direction([metronome(60)]),
              note('C5', 8, 'half'),
            ],
          ])}',
        ),
      );

      expect(
        [
          for (final mark in score.measures[0].tempos)
            (
              mark.offset.wholeNotes,
              mark.tempo.bpm,
              mark.text,
              mark.showMetronome,
            ),
        ],
        [
          (Fraction.zero, 90, 'Andante', true),
          (Fraction(1, 2), 60, null, true),
        ],
      );
    });

    test('keeps the tempo of the part above where two parts state one', () {
      List<String> bar(int bpm) => [
        opening(),
        direction([metronome(bpm)]),
        note('C5', 16, 'whole'),
      ];
      final score = imported(
        partwise(
          '<part-list>${scorePart('P1')}${scorePart('P2', name: 'Oboe')}</part-list>'
          '${part('P1', [bar(90)])}${part('P2', [bar(60)])}',
        ),
      );

      expect(
        [for (final mark in score.measures[0].tempos) mark.tempo.bpm],
        [
          90,
        ],
      );
    });

    test('reads endings and repeats', () {
      final whole = note('C5', 16, 'whole');
      final score = imported(
        flute([
          [
            barline(
              'left',
              '<bar-style>heavy-light</bar-style><repeat direction="forward"/>',
            ),
            opening(),
            whole,
          ],
          [
            barline(
              'left',
              '<ending number="1, 2" type="start">1, 2.</ending>',
            ),
            whole,
            barline(
              'right',
              '<bar-style>light-heavy</bar-style><ending number="1, 2" type="stop"/>'
                  '<repeat direction="backward"/>',
            ),
          ],
          [
            barline('left', '<ending number="3" type="start">3.</ending>'),
            whole,
          ],
          [
            whole,
            barline(
              'right',
              '<bar-style>light-heavy</bar-style>'
                  '<ending number="3" type="discontinue"/>',
            ),
          ],
        ]),
      );

      expect(
        [
          for (final column in score.measures)
            (
              column.repeatStart,
              column.volta,
              column.repeatEnd,
              column.barline,
            ),
        ],
        [
          (true, null, null, Barline.regular),
          (false, const Volta([1, 2]), const RepeatEnd(), Barline.regular),
          (false, const Volta([3], open: true), null, Barline.regular),
          (false, const Volta([3], open: true), null, Barline.finalBar),
        ],
      );
    });

    test('joins elided syllables and orders verses', () {
      final score = imported(
        flute([
          [
            opening(),
            note(
              'C5',
              16,
              'whole',
              '<lyric number="2"><syllabic>single</syllabic><text>o</text></lyric>'
                  '<lyric number="1"><syllabic>single</syllabic><text>a</text>'
                  '<elision> </elision><syllabic>single</syllabic><text>e</text>'
                  '<extend/></lyric>',
            ),
          ],
        ]),
      );

      expect(chordsIn(score, 0).single.lyrics.toList(), const [
        Lyric(verse: 1, text: 'a‿e', extend: true),
        Lyric(verse: 2, text: 'o'),
      ]);
    });

    test('reads a drum kit from its instruments', () {
      String hit(String step, int octave, String id, [String more = '']) =>
          '<note><unpitched><display-step>$step</display-step>'
          '<display-octave>$octave</display-octave></unpitched>'
          '<duration>8</duration><instrument id="$id"/><type>half</type>'
          '$more</note>';
      String drum(String id, String name, int key) =>
          '<score-instrument id="$id"><instrument-name>$name</instrument-name></score-instrument>'
          '<midi-instrument id="$id"><midi-channel>10</midi-channel>'
          '<midi-program>1</midi-program><midi-unpitched>$key</midi-unpitched></midi-instrument>';
      final score = imported(
        partwise(
          '<part-list>${scorePart('P1', name: 'Drum Set', more: '${drum('P1-I1', 'Snare', 39)}${drum('P1-I2', 'Bass drum', 37)}')}</part-list>'
          '${part('P1', [
            [
              opening(clef: '<clef><sign>percussion</sign></clef>', more: '<staff-details><staff-lines>1</staff-lines></staff-details>'),
              hit('C', 5, 'P1-I1', '<notehead>x</notehead>'),
              hit('F', 4, 'P1-I2'),
            ],
          ])}',
        ),
      );
      final instrument = score.parts.single.instrument;

      expect(
        [
          for (final drum in instrument.drums)
            (drum.name, '${drum.position}', drum.midiKey, drum.head),
        ],
        [
          ('Snare', 'C5', 38, NoteHead.cross),
          ('Bass drum', 'F4', 36, NoteHead.normal),
        ],
      );
      expect(
        (instrument.program, instrument.bank, instrument.clef),
        (
          0,
          0,
          Clef.percussion,
        ),
      );
      expect(score.parts.single.staves.single.lines, 1);
      expect(items(score, 0), ['Snare/half', 'Bass drum/half']);
    });

    test(
      'reads dashes and wedges as lines ending on the events they reach',
      () {
        final score = imported(
          flute([
            [
              opening(),
              direction(['<words>rit.</words>', '<dashes type="start"/>']),
              direction(['<wedge type="crescendo"/>']),
              for (final pitch in ['C5', 'D5', 'E5', 'F5'])
                note(pitch, 4, 'quarter'),
            ],
            [
              note('C5', 4, 'quarter'),
              note('D5', 4, 'quarter'),
              direction(['<wedge type="stop"/>']),
              note('E5', 4, 'quarter'),
              note('F5', 4, 'quarter'),
              direction(['<dashes type="stop"/>']),
            ],
          ]),
        );

        expect(
          spannersOf(score),
          unorderedEquals(['rit. 0.75 0@0-1@3/4', 'crescendo 0@0-1@1/4']),
        );
        expect(score.measures[0].staves.single.directions, isEmpty);
      },
    );

    test('reads a clef change inside a bar and one at its end', () {
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 4, 'quarter'),
            '<attributes><clef><sign>F</sign></clef></attributes>',
            note('C3', 4, 'quarter'),
            note('D3', 8, 'half'),
            '<attributes><clef><sign>C</sign><line>3</line></clef></attributes>',
          ],
          [note('C4', 16, 'whole')],
        ]),
      );
      final [first, second] = [
        for (final column in score.measures) column.staves.single,
      ];

      expect(first.clef, Clef.treble);
      expect(first.clefChanges.toList(), [ClefChange(at(1, 4), Clef.bass)]);
      expect(second.clef, Clef.alto);
      expect(second.clefChanges, isEmpty);
    });

    test('reads a key that does not print as a change of mode, not a restated '
        'signature', () {
      String key(String mode, [String attributes = '']) =>
          '<attributes><key$attributes><fifths>2</fifths><mode>$mode</mode>'
          '</key></attributes>';
      final whole = note('C5', 16, 'whole');
      final score = imported(
        flute([
          [opening(fifths: 2), whole],
          [key('minor', ' print-object="no"'), whole],
          [key('minor'), whole],
        ]),
      );

      expect(
        [
          for (final column in score.measures)
            (column.key.fifths, column.key.mode, column.keyDisplay),
        ],
        [
          (2, KeyMode.none, SignatureDisplay.auto),
          (2, KeyMode.minor, SignatureDisplay.auto),
          (2, KeyMode.minor, SignatureDisplay.restated),
        ],
      );
    });

    test('reads the concert key and pitches of a transposing part', () {
      const transpose =
          '<transpose><diatonic>-1</diatonic>'
          '<chromatic>-2</chromatic></transpose>';
      final score = imported(
        partwise(
          '<part-list>${scorePart('P1')}${scorePart('P2', name: 'Clarinet')}</part-list>'
          '${part('P1', [
            [opening(fifths: -1), note('C5', 16, 'whole')],
          ])}'
          '${part('P2', [
            [opening(fifths: 1, more: transpose), note('E4', 16, 'whole')],
          ])}',
        ),
      );

      expect(score.measures[0].key.fifths, -1);
      expect(score.parts[1].instrument.transposition, const Interval(-1, -2));
      expect(items(score, 0, staff: 1), ['D4/whole']);
    });

    test('reads the key from a transposing part alone', () {
      final score = imported(
        flute([
          [
            opening(
              fifths: 2,
              more:
                  '<transpose><diatonic>-1</diatonic>'
                  '<chromatic>-2</chromatic></transpose>',
            ),
            note('E4', 16, 'whole'),
          ],
        ]),
      );

      expect(score.measures[0].key.fifths, 0);
      expect(items(score, 0), ['D4/whole']);
    });

    test('keeps the accidentals the file prints', () {
      const sharp = '<accidental>sharp</accidental>';
      final score = imported(
        flute([
          [
            opening(),
            note('F#4', 2, 'eighth', sharp),
            note('F#4', 2, 'eighth', sharp),
            note(
              'Bb4',
              2,
              'eighth',
              '<accidental parentheses="yes">flat</accidental>',
            ),
            note('C5', 2, 'eighth'),
            note('C#5', 8, 'half'),
          ],
        ]),
      );

      expect(requestsIn(score, 0), [
        AccidentalRequest.auto,
        AccidentalRequest.always,
        AccidentalRequest.cautionary,
        AccidentalRequest.auto,
        AccidentalRequest.auto,
      ]);
    });

    test('keeps an accidental printed on a note tied in from the bar before', () {
      const sharp = '<accidental>sharp</accidental>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 12, 'half', '<dot/>'),
            note(
              'F#4',
              4,
              'quarter',
              '<tie type="start"/>$sharp<notations><tied type="start"/></notations>',
            ),
          ],
          [
            note(
              'F#4',
              4,
              'quarter',
              '<tie type="stop"/>$sharp<notations><tied type="stop"/></notations>',
            ),
            note('F#4', 12, 'half', '<dot/>'),
          ],
        ]),
      );
      final staff = score.measureView(score.measures[1].id).staves.single;
      final [tiedIn, after] = chordsIn(score, 1);

      expect(items(score, 0), ['C5/half.', 'F#4/quarter~']);
      expect(
        [
          staff.accidentals[tiedIn.notes.single.id]?.alter,
          staff.accidentals[after.notes.single.id]?.alter,
        ],
        [Alter.sharp, null],
      );
    });

    test('keeps the beams the file draws', () {
      String eighth(String pitch, [String? beam]) => note(
        pitch,
        2,
        'eighth',
        beam == null ? '' : '<beam number="1">$beam</beam>',
      );
      final score = imported(
        flute([
          [
            opening(),
            eighth('C5', 'begin'),
            eighth('D5', 'end'),
            eighth('E5', 'begin'),
            eighth('F5', 'end'),
            for (final pitch in ['G5', 'A5', 'B5', 'C6']) eighth(pitch),
          ],
        ]),
      );

      expect(beamsOf(score, 0), [
        [0, 1],
        [2, 3],
      ]);
    });

    test('skips a beam the model cannot draw', () {
      String beamed(String state) => '<beam number="1">$state</beam>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 2, 'eighth', beamed('begin')),
            note('D5', 4, 'quarter', beamed('end')),
            note('E5', 2, 'eighth'),
            note('rest', 8, 'half'),
          ],
          [
            note('C5', 2, 'eighth', beamed('end')),
            note('D5', 2, 'eighth'),
            note('rest', 4, 'quarter'),
            note('rest', 8, 'half'),
          ],
        ]),
      );

      expect(
        [
          for (final bar in [0, 1])
            for (final chord in chordsIn(score, bar)) chord.beam,
        ],
        [
          BeamMode.auto,
          BeamMode.auto,
          BeamMode.auto,
          BeamMode.auto,
          BeamMode.begin,
        ],
      );
      expect(beamsOf(score, 0), isEmpty);
      expect(beamsOf(score, 1), isEmpty);
    });

    test('leaves beams to the meter when the file draws none', () {
      final score = imported(
        flute([
          [
            opening(),
            for (final pitch in [
              'C5',
              'D5',
              'E5',
              'F5',
              'G5',
              'A5',
              'B5',
              'C6',
            ])
              note(pitch, 2, 'eighth'),
          ],
        ]),
      );

      expect(
        {for (final chord in chordsIn(score, 0)) chord.beam},
        {
          BeamMode.auto,
        },
      );
    });

    test('reads a missing accidental as never when the file declares '
        'accidentals', () {
      String document(String identification) => partwise(
        '$identification<part-list>${scorePart('P1')}</part-list>'
        '${part('P1', [
          [
            opening(),
            note('F#4', 4, 'quarter'),
            note('F#4', 4, 'quarter', '<accidental>sharp</accidental>'),
            note('G4', 8, 'half'),
          ],
        ])}',
      );
      const declared =
          '<identification><encoding>'
          '<supports element="accidental" type="yes"/>'
          '</encoding></identification>';

      expect(requestsIn(imported(document(declared)), 0), [
        AccidentalRequest.never,
        AccidentalRequest.auto,
        AccidentalRequest.auto,
      ]);
      expect(requestsIn(imported(document('')), 0), [
        AccidentalRequest.auto,
        AccidentalRequest.always,
        AccidentalRequest.auto,
      ]);
    });

    test('pairs a slur stop written before its start', () {
      const start = '<notations><slur type="start"/></notations>';
      const stop = '<notations><slur type="stop"/></notations>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 16, 'whole', '<voice>1</voice>$stop'),
            backup(16),
            note('E4', 4, 'quarter', '<voice>2</voice>$start'),
          ],
        ]),
      );

      expect(spannersOf(score), ['slur 0@0-0@1/4']);
      expect(score.spanners.single.voice, VoiceSlot.two);
    });

    test('reads back two slurs of a second voice where the later one ends '
        'on a note of voice one', () {
      var score = blankScore(bars: 1);
      score = fill(score, 0, [chordOf(1, 'C4', value: NoteValue.whole)]);
      score = fill(score, 0, slot: VoiceSlot.two, [
        chordOf(2, 'D4'),
        chordOf(3, 'E4'),
        chordOf(4, 'F4'),
        Gap(len(1, 4)),
      ]);
      score = withSlur(
        score,
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(1, 4)),
        voice: VoiceSlot.two,
      );
      score = withSlur(
        score,
        pointAt(score, 0, at(1, 2)),
        pointAt(score, 0, at(3, 4)),
        voice: VoiceSlot.two,
      );

      final back = scoreFromMusicXml(scoreToMusicXml(score));

      expect(spannersOf(back), ['slur 0@0-0@1/4', 'slur 0@1/2-0@3/4']);
    });

    test('reads its own file back to itself where a slur of a second voice '
        'starts in a gap, on the note of voice one another slur starts '
        'under', () {
      var score = blankScore();
      score = fill(score, 0, [chordOf(1, 'C4', value: NoteValue.whole)]);
      score = fill(score, 0, slot: VoiceSlot.two, [
        chordOf(2, 'D4'),
        chordOf(3, 'E4'),
        Gap(len(1, 2)),
      ]);
      score = fill(score, 1, [chordOf(4, 'C4', value: NoteValue.whole)]);
      score = fill(score, 1, slot: VoiceSlot.two, [
        chordOf(5, 'G4'),
        Gap(len(3, 4)),
      ]);
      score = withSlur(
        score,
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(1, 4)),
        voice: VoiceSlot.two,
      );
      score = withSlur(
        score,
        pointAt(score, 0, at(1, 2)),
        pointAt(score, 1, Moment.zero),
        voice: VoiceSlot.two,
      );
      final text = scoreToMusicXml(score);

      expect(scoreToMusicXml(scoreFromMusicXml(text)), text);
    });

    test('leaves a slur stop that nothing opened out of the next slur', () {
      const start = '<notations><slur type="start"/></notations>';
      const stop = '<notations><slur type="stop"/></notations>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 8, 'half', stop),
            note('D5', 8, 'half', start),
          ],
          [note('E5', 16, 'whole', stop)],
        ]),
      );

      expect(spannersOf(score), ['slur 0@1/2-1@0']);
    });

    test('reads any words with dashes as a tempo line', () {
      String line(String words) => direction([words, '<dashes type="start"/>']);
      final stop = direction(['<dashes type="stop"/>']);
      List<String> bar(String first, String second) => [
        line(first),
        note('C5', 4, 'quarter'),
        note('D5', 4, 'quarter'),
        stop,
        line(second),
        note('E5', 4, 'quarter'),
        note('F5', 4, 'quarter'),
        stop,
      ];
      final score = imported(
        flute([
          [
            opening(),
            ...bar('<words>Poco Rall.</words>', '<words>accel.</words>'),
          ],
          bar('<words>meno mosso</words>', '<words/>'),
        ]),
      );

      expect(spannersOf(score), [
        'Poco Rall. 0.75 0@0-0@1/4',
        'accel. ${4 / 3} 0@1/2-0@3/4',
        'meno mosso 1.0 1@0-1@1/4',
        ' 1.0 1@1/2-1@3/4',
      ]);
      expect([marksIn(score, 0), marksIn(score, 1)], [isEmpty, isEmpty]);
    });

    test("keeps a bar's own opening tempo over one the bar before ends "
        'with', () {
      final whole = note('C5', 16, 'whole');
      final score = imported(
        flute([
          [
            opening(),
            whole,
            direction([metronome(80)]),
          ],
          [
            direction([metronome(120)]),
            whole,
          ],
        ]),
      );

      expect(
        [for (final mark in score.measures[1].tempos) mark.tempo.bpm],
        [
          120,
        ],
      );
    });

    test('moves what a bar ends with to the next bar, and drops it after the '
        'last', () {
      final whole = note('C5', 16, 'whole');
      final score = imported(
        flute([
          [
            opening(),
            whole,
            direction(['<dynamics><f/></dynamics>']),
            direction(['<words>dolce</words>']),
            direction([
              '<metronome><beat-unit>quarter</beat-unit><per-minute>80</per-minute></metronome>',
            ]),
          ],
          [
            whole,
            direction(['<dynamics><p/></dynamics>']),
          ],
        ]),
      );

      expect(
        [marksIn(score, 0), marksIn(score, 1)],
        [
          isEmpty,
          ['0 f', '0 dolce'],
        ],
      );
      expect(
        [
          for (final column in score.measures)
            [
              for (final mark in column.tempos)
                (mark.offset.wholeNotes, mark.tempo.bpm),
            ],
        ],
        [
          isEmpty,
          [(Fraction.zero, 80)],
        ],
      );
    });

    test('keeps a voice on its staff when a note crosses to the other', () {
      final score = imported(
        keyboard([
          [
            grand,
            note('C5', 4, 'quarter', '<voice>1</voice><staff>1</staff>'),
            note('G3', 4, 'quarter', '<voice>1</voice><staff>2</staff>'),
            note('E5', 8, 'half', '<voice>1</voice><staff>1</staff>'),
            backup(16),
            note('C3', 16, 'whole', '<voice>5</voice><staff>2</staff>'),
          ],
        ]),
      );

      expect(items(score, 0), ['C5/quarter', 'G3/quarter', 'E5/half']);
      expect(items(score, 0, staff: 1), ['C3/whole']);
    });

    test('keeps the staves apart when the file numbers no voices', () {
      final score = imported(
        keyboard([
          [
            grand,
            note('C5', 16, 'whole', '<staff>1</staff>'),
            backup(16),
            note('C3', 16, 'whole', '<staff>2</staff>'),
          ],
        ]),
      );

      expect(
        [items(score, 0), items(score, 0, staff: 1)],
        [
          ['C5/whole'],
          ['C3/whole'],
        ],
      );
    });

    test('hides a part only by its first bar, and never every part', () {
      const hide = '<staff-details print-object="no"/>';
      final whole = note('C5', 16, 'whole');
      String document({required bool hideFirst, required bool hideSecond}) =>
          partwise(
            '<part-list>${scorePart('P1')}'
            '${scorePart('P2', name: 'Oboe')}</part-list>'
            '${part('P1', [
              [opening(more: hideFirst ? hide : ''), whole],
              ['<attributes>$hide</attributes>', whole],
            ])}'
            '${part('P2', [
              [opening(more: hideSecond ? hide : ''), whole],
              [whole],
            ])}',
          );
      List<bool> hidden(String xml) => [
        for (final part in imported(xml).parts) part.hidden,
      ];

      expect(hidden(document(hideFirst: false, hideSecond: true)), [
        false,
        true,
      ]);
      expect(hidden(document(hideFirst: true, hideSecond: true)), [
        false,
        false,
      ]);
    });

    test('accepts tuplet durations rounded to whole divisions', () {
      final score = imported(
        flute([
          [
            opening(),
            note(
              'C5',
              1,
              'eighth',
              '$triplet<notations><tuplet type="start"/></notations>',
            ),
            note('D5', 1, 'eighth', triplet),
            note(
              'E5',
              2,
              'eighth',
              '$triplet<notations><tuplet type="stop"/></notations>',
            ),
            note('F5', 4, 'quarter'),
            note('G5', 8, 'half'),
          ],
        ]),
      );

      expect(items(score, 0), [
        '3:2[C5/eighth, D5/eighth, E5/eighth]',
        'F5/quarter',
        'G5/half',
      ]);
    });

    test('closes a tuplet of mixed values where the time modification '
        'ends', () {
      final score = imported(
        flute([
          [
            opening(divisions: 3, beats: 2),
            note('C5', 2, 'quarter', triplet),
            note('D5', 1, 'eighth', triplet),
            note('E5', 3, 'quarter'),
          ],
        ]),
      );

      expect(items(score, 0), ['3:2[C5/quarter, D5/eighth]', 'E5/quarter']);
    });

    test('keeps a tie only where the model can end it', () {
      final score = imported(
        flute([
          [
            opening(),
            note(
              'C5',
              8,
              'half',
              '<tie type="start"/><voice>1</voice>'
                  '<notations><tied type="start"/></notations>',
            ),
            note('D5', 4, 'quarter', '<voice>1</voice>'),
            note(
              'E5',
              4,
              'quarter',
              '<voice>1</voice><notations><tied type="let-ring"/></notations>',
            ),
            backup(8),
            note(
              'C5',
              8,
              'half',
              '<tie type="stop"/><voice>2</voice>'
                  '<notations><tied type="stop"/></notations>',
            ),
          ],
        ]),
      );

      expect(items(score, 0), ['C5/half', 'D5/quarter', 'E5/quarter~']);
    });

    test(
      'reads a trill mark where a trill line starts as the line\'s sign',
      () {
        String ornaments(String children) =>
            '<notations><ornaments>$children</ornaments></notations>';
        final score = imported(
          flute([
            [
              opening(),
              note(
                'C5',
                8,
                'half',
                ornaments('<trill-mark/><wavy-line type="start"/>'),
              ),
              note('D5', 8, 'half', ornaments('<wavy-line type="stop"/>')),
            ],
          ]),
        );

        expect(spannersOf(score), ['trill 0@0-0@1/2']);
        expect(chordsIn(score, 0).first.ornament, isNull);
      },
    );

    test('gives the words of a jump to the jump, not to its tempo', () {
      final score = imported(
        flute([
          [
            opening(),
            direction([
              '<words>D.C. al Fine</words>',
            ], more: '<sound dacapo="yes" tempo="90"/>'),
            note('C5', 16, 'whole'),
          ],
        ]),
      );
      final column = score.measures.single;

      expect(column.navigation.toList(), const [
        Jump(JumpTarget.start, then: JumpThen.toFine),
      ]);
      expect(
        [for (final mark in column.tempos) (mark.tempo.bpm, mark.text)],
        [
          (90, null),
        ],
      );
    });

    test('plays a jump with words of its own to where it is set to end', () {
      var score = blankScore(bars: 4);
      score = changeBar(
        score,
        1,
        (column) => column.copyWith(navigation: Seq(const [Fine()])),
      );
      score = changeBar(
        score,
        3,
        (column) => column.copyWith(
          navigation: Seq(const [
            Jump(JumpTarget.start, then: JumpThen.toFine, text: 'Da Capo'),
          ]),
        ),
      );
      final back = scoreFromMusicXml(scoreToMusicXml(score));

      expect(playOrder(back), [0, 1, 2, 3, 0, 1]);
      expect(jumpIn(back, 3), (JumpTarget.start, JumpThen.toFine, 'Da Capo'));
    });

    test('keeps where a jump ends, whatever its words say', () {
      for (final target in JumpTarget.values) {
        for (final then in JumpThen.values) {
          for (final text in [
            null,
            'Da Capo',
            'Да капо',
            'D.C.',
            'D.C. al Fine',
            'D.S. al Coda',
            'dal segno AL FINE',
          ]) {
            final jump = Jump(target, then: then, text: text);
            final score = changeBar(
              blankScore(),
              1,
              (column) => column.copyWith(navigation: Seq([jump])),
            );
            final back =
                scoreFromMusicXml(
                      scoreToMusicXml(score),
                    ).measures[1].navigation.single
                    as Jump;

            expect(
              (back.target, back.then, back.label),
              (target, then, jump.label),
              reason: '$target, $then, $text',
            );
          }
        }
      }
    });

    test('reads where a jump ends from standard words beside its own', () {
      (JumpTarget, JumpThen, String?) jumpOf(
        String words,
        String other,
        String sound,
      ) => jumpIn(
        imported(
          flute([
            [
              opening(),
              note('C5', 16, 'whole'),
              direction([
                '<words>$words</words>',
                '<other-direction>$other</other-direction>',
              ], more: '<sound $sound/>'),
            ],
          ]),
        ),
        0,
      );

      expect(
        jumpOf('Da Capo', ' D.C. al Coda ', 'dacapo="yes"'),
        (JumpTarget.start, JumpThen.toCoda, 'Da Capo'),
      );
      expect(
        jumpOf('Dal Segno al Fine', 'Swing', 'dalsegno="s"'),
        (JumpTarget.segno, JumpThen.toFine, 'Dal Segno al Fine'),
      );
      expect(
        jumpOf('Dal Segno', 'D.C. al Fine', 'dalsegno="s"'),
        (JumpTarget.segno, JumpThen.toEnd, 'Dal Segno'),
      );
    });

    test('reads a navigation mark from its sound, once per bar', () {
      final whole = note('C5', 16, 'whole');
      final score = imported(
        partwise(
          '<part-list>${scorePart('P1')}'
          '${scorePart('P2', name: 'Oboe')}</part-list>'
          '${part('P1', [
            [
              opening(),
              direction(['<segno/>'], more: '<sound segno="s"/>'),
              whole,
            ],
            [
              whole,
              direction(['<coda/>'], more: '<sound tocoda="c"/>'),
            ],
            [
              direction(['<coda/>'], more: '<sound coda="c"/>'),
              whole,
            ],
          ])}'
          '${part('P2', [
            [
              opening(),
              direction(['<segno/>']),
              whole,
            ],
            [whole],
            [whole],
          ])}',
        ),
      );

      expect(
        [for (final column in score.measures) column.navigation.toList()],
        const [
          [Segno()],
          [ToCoda()],
          [Coda()],
        ],
      );
    });

    test('reads a lone rest that fills the bar as a measure rest, and cue '
        'notes as silence', () {
      final score = imported(
        flute([
          [opening(beats: 3), note('rest', 12, 'whole')],
          [
            '<note><grace/>${_pitch(Pitch.parse('C5'))}<type>eighth</type></note>',
            note('rest', 4, 'quarter'),
            note('D5', 4, 'quarter'),
            [
              '<note><cue/>${_pitch(Pitch.parse('E5'))}',
              '<duration>4</duration><type>quarter</type></note>',
            ].join(),
          ],
        ]),
      );

      expect(items(score, 0), ['measure-rest']);
      expect(items(score, 1), ['rest/quarter', 'D5/quarter', 'rest/quarter']);
      expect(chordsIn(score, 1).single.graces, isEmpty);
    });

    test('reads the base document every refusal edits', () {
      final score = imported(base);

      expect(items(score, 0), ['C5/quarter', 'D5/quarter', 'E5/half']);
      expect(score.parts.single.instrument.program, 73);
      expect(items(imported('\uFEFF$base'), 0), items(score, 0));
    });

    group('refuses', () {
      for (final (:rule, :edits, :at, :message) in refusals) {
        test(rule, () {
          final xml = edited(base, edits);

          expect(
            () => scoreFromMusicXml(xml),
            throwsA(
              isA<ScoreFormatException>()
                  .having((e) => e.path, 'path', at)
                  .having((e) => e.message, 'message', message),
            ),
          );
        });
      }
    });
  });
}
