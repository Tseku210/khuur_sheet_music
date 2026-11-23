import 'dart:io';
import 'dart:math';

import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'random_edits.dart';
import 'support.dart';

final golden = File('test/golden/showcase.musicxml');

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
    'overlaps the previous note in its voice',
    [(c5, '$c5${backup(6)}${note('A4', 12, 'quarter')}')],
    at: '$bar0/note[2]',
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

    test('gives a chord the duration of its first note', () {
      final score = imported(
        flute([
          [
            opening(),
            note('G5', 12, 'half', '<dot/>'),
            note('C5', 8, 'half', '<chord/><dot/>'),
            note('D5', 4, 'quarter'),
            note('F5', 6, 'quarter', '<chord/>'),
          ],
        ]),
      );

      expect(items(score, 0), ['C5+G5/half.', 'D5+F5/quarter']);
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

    for (final (order, stops) in [
      ('inner first', ['2', '1']),
      ('outer first', ['1', '2']),
    ]) {
      test('reads nested tuplets whose stops list the $order', () {
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
                '$nine<notations>'
                    '${stops.map((n) => '<tuplet type="stop" number="$n"/>').join()}'
                    '</notations>',
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
    }

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

    test('gives a chord no beam mode that the mode of one before it makes '
        'needless', () {
      String beamed(String state) => '<beam number="1">$state</beam>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 1, '16th', beamed('begin')),
            note('D5', 1, '16th', beamed('end')),
            note('E5', 2, 'eighth', beamed('begin')),
            note('F5', 2, 'eighth', beamed('continue')),
            note('G5', 2, 'eighth', beamed('end')),
            note('rest', 2, 'eighth'),
            note('rest', 8, 'half'),
          ],
        ]),
      );

      // Without its sixteenths the run no longer splits at the beat, so F5
      // joins E5 by itself.
      expect(
        [for (final chord in chordsIn(score, 0)) chord.beam],
        [
          BeamMode.auto,
          BeamMode.auto,
          BeamMode.begin,
          BeamMode.auto,
          BeamMode.auto,
        ],
      );
      expect(beamsOf(score, 0), [
        [0, 1],
        [2, 3, 4],
      ]);
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

    test('drops a slur that stops on a note of voice one that starts before '
        'the note it starts on', () {
      const start = '<notations><slur type="start"/></notations>';
      const stop = '<notations><slur type="stop"/></notations>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 16, 'whole', '<voice>1</voice>$stop'),
            backup(16),
            note('E4', 4, 'quarter', '<voice>2</voice>'),
            note('F4', 4, 'quarter', '<voice>2</voice>$start'),
          ],
        ]),
      );

      expect(spannersOf(score), isEmpty);
    });

    test('ends a slur of a second voice on the note of a third voice its '
        'stop is on, where the second voice has a gap, and writes it back', () {
      const start = '<notations><slur type="start"/></notations>';
      const stop = '<notations><slur type="stop"/></notations>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 16, 'whole', '<voice>1</voice>'),
            backup(16),
            note('E4', 4, 'quarter', '<voice>2</voice>'),
            note('F4', 4, 'quarter', '<voice>2</voice>$start'),
            forward(8, '<voice>2</voice>'),
            backup(16),
            forward(8, '<voice>3</voice>'),
            note('G4', 4, 'quarter', '<voice>3</voice>$stop'),
            forward(4, '<voice>3</voice>'),
          ],
        ]),
      );

      expect(spannersOf(score), ['slur 0@1/4-0@1/2']);
      final slur = score.spanners.single;
      expect(slur.kind, const Slur(endVoice: VoiceSlot.three));
      final from = score.anchorOf(slur, last: false)!;
      final to = score.anchorOf(slur, last: true)!;
      expect((from.voice, from.onset), (VoiceSlot.two, at(1, 4)));
      expect((to.voice, to.onset), (VoiceSlot.three, at(1, 2)));
      expect('${(to.event as ChordEvent).notes.single.tone}', 'G4');
      final back = scoreFromMusicXml(scoreToMusicXml(score));
      expect(spannersOf(back), ['slur 0@1/4-0@1/2']);
      expect(back.spanners.single.kind, slur.kind);
    });

    test('starts a slur on the note of voice one its start is on, where the '
        'third voice its stop is in starts a note with that one', () {
      const start = '<notations><slur type="start"/></notations>';
      const stop = '<notations><slur type="stop"/></notations>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 4, 'quarter', '<voice>1</voice>$start'),
            note('D5', 4, 'quarter', '<voice>1</voice>'),
            note('E5', 8, 'half', '<voice>1</voice>'),
            backup(16),
            note('G4', 4, 'quarter', '<voice>3</voice>'),
            forward(4, '<voice>3</voice>'),
            note('A4', 4, 'quarter', '<voice>3</voice>$stop'),
            forward(4, '<voice>3</voice>'),
          ],
        ]),
      );

      expect(spannersOf(score), ['slur 0@0-0@1/2']);
      final slur = score.spanners.single;
      final from = score.anchorOf(slur, last: false)!;
      final to = score.anchorOf(slur, last: true)!;
      expect('${(from.event as ChordEvent).notes.single.tone}', 'C5');
      expect('${(to.event as ChordEvent).notes.single.tone}', 'A4');
      expect(slur.kind, const Slur(endVoice: VoiceSlot.three));
      final exported = scoreToMusicXml(score);
      expect(scoreToMusicXml(scoreFromMusicXml(exported)), exported);
    });

    test('reads back a slur that starts on a note of voice one and is named '
        'for the chord of a third voice, on the same two notes', () {
      String tone(TimedEvent on) =>
          '${on.voice.name} ${(on.event as ChordEvent).notes.single.tone}';
      String ends(Score score, Spanner slur) =>
          '${tone(score.anchorOf(slur, last: false)!)} to '
          '${tone(score.anchorOf(slur, last: true)!)}, '
          'named ${(slur.kind as Slur).endVoice?.name}';
      List<String> slursOf(Score score) => [
        for (final slur in score.spanners) ends(score, slur),
      ];

      var bar = blankScore(bars: 1);
      bar = fill(bar, 0, [
        chordOf(1, 'C5'),
        chordOf(2, 'D5'),
        chordOf(3, 'E5', value: NoteValue.half),
      ]);
      bar = fill(bar, 0, slot: VoiceSlot.three, [
        chordOf(4, 'G4'),
        Gap(len(1, 4)),
        chordOf(5, 'A4'),
        Gap(len(1, 4)),
      ]);
      // Voice one holds its note under both notes of the third voice.
      var held = blankScore(bars: 1);
      held = fill(held, 0, [chordOf(1, 'C5', value: NoteValue.whole)]);
      held = fill(held, 0, slot: VoiceSlot.three, [
        chordOf(2, 'G4'),
        chordOf(3, 'A4'),
        Gap(len(1, 2)),
      ]);
      // The slur's own voice has a gap where it starts, and the third voice
      // starts a note there.
      var bars = blankScore();
      bars = fill(bars, 0, [
        chordOf(1, 'C5'),
        chordOf(2, 'D5'),
        chordOf(3, 'E5', value: NoteValue.half),
      ]);
      bars = fill(bars, 0, slot: VoiceSlot.two, [
        chordOf(4, 'E4'),
        Gap(len(3, 4)),
      ]);
      bars = fill(bars, 0, slot: VoiceSlot.three, [
        Gap(len(1, 4)),
        chordOf(5, 'G4'),
        Gap(len(1, 2)),
      ]);
      bars = fill(bars, 1, [chordOf(6, 'F5', value: NoteValue.whole)]);
      bars = fill(bars, 1, slot: VoiceSlot.three, [
        Gap(len(1, 4)),
        chordOf(7, 'A4'),
        Gap(len(1, 2)),
      ]);
      const named = Slur(endVoice: VoiceSlot.three);
      final cases = [
        for (final voice in [VoiceSlot.one, VoiceSlot.two])
          (
            withSpanner(
              bar,
              named,
              pointAt(bar, 0, Moment.zero),
              pointAt(bar, 0, at(1, 2)),
              voice: voice,
            ),
            'one C5 to three A4',
          ),
        (
          withSpanner(
            held,
            named,
            pointAt(held, 0, Moment.zero),
            pointAt(held, 0, at(1, 4)),
            voice: VoiceSlot.one,
          ),
          'one C5 to three A4',
        ),
        (
          withSpanner(
            bars,
            named,
            pointAt(bars, 0, at(1, 4)),
            pointAt(bars, 1, at(1, 4)),
            voice: VoiceSlot.two,
          ),
          'one D5 to three A4',
        ),
      ];

      final made = [for (final (score, _) in cases) slursOf(score)];
      final back = [
        for (final (score, _) in cases)
          slursOf(scoreFromMusicXml(scoreToMusicXml(score))),
      ];

      expect(made, [
        for (final (_, on) in cases) ['$on, named three'],
      ]);
      expect(back, made);
    });

    test('ends a slur on the note its stop is on, in a fourth voice that '
        'starts with a third or under a note voice one starts in that bar, '
        'and keeps it there through a save and an export', () {
      const start = '<notations><slur type="start"/></notations>';
      const stop = '<notations><slur type="stop"/></notations>';
      String end(Score score) {
        final on = score.anchorOf(score.spanners.single, last: true)!;
        final tone = (on.event as ChordEvent).notes.single.tone;
        return '${on.voice.name} $tone';
      }

      List<SpannerKind> kindsOf(Score score) => [
        for (final spanner in score.spanners) spanner.kind,
      ];

      final together = imported(
        flute([
          [
            opening(),
            note('C5', 16, 'whole', '<voice>1</voice>'),
            backup(16),
            note('E4', 4, 'quarter', '<voice>2</voice>'),
            note('F4', 4, 'quarter', '<voice>2</voice>$start'),
            forward(8, '<voice>2</voice>'),
            backup(16),
            forward(8, '<voice>3</voice>'),
            note('G4', 4, 'quarter', '<voice>3</voice>'),
            forward(4, '<voice>3</voice>'),
            backup(16),
            forward(8, '<voice>4</voice>'),
            note('A4', 4, 'quarter', '<voice>4</voice>$stop'),
            forward(4, '<voice>4</voice>'),
          ],
        ]),
      );
      final later = imported(
        flute([
          [
            opening(),
            note('C5', 16, 'whole', '<voice>1</voice>'),
            backup(16),
            forward(12, '<voice>2</voice>'),
            note('F4', 4, 'quarter', '<voice>2</voice>$start'),
          ],
          [
            note('D5', 16, 'whole', '<voice>1</voice>'),
            backup(16),
            note('E4', 4, 'quarter', '<voice>2</voice>'),
            forward(12, '<voice>2</voice>'),
            backup(16),
            forward(8, '<voice>3</voice>'),
            note('G4', 4, 'quarter', '<voice>3</voice>$stop'),
            forward(4, '<voice>3</voice>'),
          ],
        ]),
      );

      expect(kindsOf(together), [const Slur(endVoice: VoiceSlot.four)]);
      expect(kindsOf(later), [const Slur(endVoice: VoiceSlot.three)]);
      for (final (score, on) in [(together, 'four A4'), (later, 'three G4')]) {
        expect(end(score), on);
        expect(end(reloaded(score)), on);
        final exported = scoreToMusicXml(score);
        final back = scoreFromMusicXml(exported);
        expect(end(back), on);
        expect(scoreToMusicXml(back), exported);
      }
      final halved = applied(
        EditSession.start(together).run(
          SetMeter(from: together.measures.first.id, meter: Meter.twoFour),
        ),
      ).score;
      expect(end(halved), 'four A4');
    });

    test('keeps a slur on the notes its marks are on, one of them a note of '
        'voice one, where a third voice starts a note as the second voice '
        'stops', () {
      const start = '<notations><slur type="start"/></notations>';
      const stop = '<notations><slur type="stop"/></notations>';
      final third = [
        backup(16),
        forward(8, '<voice>3</voice>'),
        note('G4', 4, 'quarter', '<voice>3</voice>'),
        forward(4, '<voice>3</voice>'),
      ];
      final ending = imported(
        flute([
          [
            opening(),
            note('C5', 4, 'quarter', '<voice>1</voice>'),
            note('D5', 8, 'half', '<voice>1</voice>$stop'),
            note('E5', 4, 'quarter', '<voice>1</voice>'),
            backup(16),
            note('E4', 4, 'quarter', '<voice>2</voice>'),
            note('F4', 4, 'quarter', '<voice>2</voice>$start'),
            forward(8, '<voice>2</voice>'),
            ...third,
          ],
        ]),
      );
      final starting = imported(
        flute([
          [
            opening(),
            note('C5', 16, 'whole', '<voice>1</voice>$start'),
            backup(16),
            note('E4', 8, 'half', '<voice>2</voice>'),
            forward(4, '<voice>2</voice>'),
            note('F4', 4, 'quarter', '<voice>2</voice>$stop'),
            ...third,
          ],
        ]),
      );
      String tones(Score score) => [
        for (final last in [false, true])
          (score.anchorOf(score.spanners.single, last: last)!.event
                  as ChordEvent)
              .notes
              .single
              .tone,
      ].join(' to ');

      expect(spannersOf(ending), ['slur 0@1/4-0@1/2']);
      expect(tones(ending), 'F4 to D5');
      expect(spannersOf(starting), ['slur 0@0-0@3/4']);
      expect(tones(starting), 'C5 to F4');
      expect(starting.spanners.single.voice, VoiceSlot.one);
      for (final score in [ending, starting]) {
        expect(
          spannersOf(scoreFromMusicXml(scoreToMusicXml(score))),
          spannersOf(score),
        );
      }
    });

    test('reads a slur in the voice of the note its start is on, where the '
        'voice of its stop is silent there, as MuseScore 4 writes and reads '
        'it', () {
      const stop = '<notations><slur type="stop" number="1"/></notations>';
      String read(String silence, [String side = '']) {
        final start =
            '<notations><slur type="start" number="1"$side/></notations>';
        final score = imported(
          flute([
            [
              opening(),
              note('C5', 8, 'half', '<voice>1</voice>$start'),
              note('D5', 8, 'half', '<voice>1</voice>'),
              backup(16),
              silence,
              note('E4', 4, 'quarter', '<voice>2</voice>$stop'),
              note('F4', 4, 'quarter', '<voice>2</voice>'),
            ],
          ]),
        );
        final slur = score.spanners.single;
        String on({required bool last}) {
          final timed = score.anchorOf(slur, last: last)!;
          return '${timed.voice.name} '
              '${(timed.event as ChordEvent).notes.single.tone}';
        }

        return '${slur.voice?.name} named '
            '${(slur.kind as Slur).endVoice?.name}, '
            '${on(last: false)} to ${on(last: true)}';
      }

      // MuseScore 4 writes the silence as a forward with no voice.
      expect(read(forward(8)), 'one named two, one C5 to two E4');
      expect(
        read('<note><rest/><duration>8</duration><voice>2</voice></note>'),
        'one named two, one C5 to two E4',
      );
      // MuseScore 4.2 and later write a slur's forced direction as both
      // attributes.
      expect(
        read(forward(8), ' orientation="under" placement="below"'),
        'one named two, one C5 to two E4',
      );
    });

    test('trusts a slur start with only a placement in a file this library '
        'wrote, as MuseScore 4.0 and 4.1 write one on every slur', () {
      String read(String? encoding) {
        final score = imported(
          partwise(
            '${encoding == null ? '' : '<identification><encoding>$encoding'
                      '</encoding></identification>'}'
            '<part-list>${scorePart('P1')}</part-list>'
            '${part('P1', [
              [
                opening(),
                note('C5', 8, 'half', '<voice>1</voice><notations>'
                    '<slur type="start" placement="below" number="1"/>'
                    '</notations>'),
                note('D5', 8, 'half', '<voice>1</voice>'),
                backup(16),
                forward(8),
                note('E4', 4, 'quarter', '<voice>2</voice><notations>'
                    '<slur type="stop" number="1"/></notations>'),
                note('F4', 4, 'quarter', '<voice>2</voice>'),
              ],
            ])}',
          ),
        );
        final slur = score.spanners.single;
        return '${slur.voice?.name} named '
            '${(slur.kind as Slur).endVoice?.name}';
      }

      const ours = '<software>khuur_sheet_music</software>';
      const theirs = '<software>MuseScore 4.1.1</software>';
      expect(read(null), 'one named two');
      expect(read(''), 'one named two');
      expect(read(theirs), 'one named two');
      expect(read('$ours$theirs'), 'one named two');
      expect(read(ours), 'two named null');
    });

    test('reads a slur with only a placement, between notes of voice one, '
        'in voice one', () {
      final score = imported(
        flute([
          [
            opening(),
            note(
              'C5',
              8,
              'half',
              '<notations><slur type="start" placement="below"/></notations>',
            ),
            note('D5', 8, 'half', '<notations><slur type="stop"/></notations>'),
          ],
        ]),
      );

      expect(score.spanners.single.voice, VoiceSlot.one);
    });

    test('leaves out a slur of a second voice whose stop is on a note of '
        'voice one that started before it, though a third voice starts a note '
        'as the second voice stops', () {
      const start = '<notations><slur type="start"/></notations>';
      const stop = '<notations><slur type="stop"/></notations>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 16, 'whole', '<voice>1</voice>$stop'),
            backup(16),
            note('E4', 4, 'quarter', '<voice>2</voice>'),
            note('F4', 4, 'quarter', '<voice>2</voice>$start'),
            forward(8, '<voice>2</voice>'),
            backup(16),
            forward(8, '<voice>3</voice>'),
            note('G4', 4, 'quarter', '<voice>3</voice>'),
            forward(4, '<voice>3</voice>'),
          ],
        ]),
      );

      expect(spannersOf(score), isEmpty);
    });

    test('leaves out a slur or glissando that stops on another staff where '
        'its own staff has only a note of voice one that started before '
        'it', () {
      for (final element in ['slur', 'glissando']) {
        String mark(String type) =>
            '<notations><$element type="$type"/></notations>';
        final score = imported(
          keyboard([
            [
              grand,
              note('C5', 16, 'whole', '<voice>1</voice><staff>1</staff>'),
              backup(16),
              note('E4', 4, 'quarter', '<voice>2</voice><staff>1</staff>'),
              note(
                'F4',
                4,
                'quarter',
                '<voice>2</voice><staff>1</staff>${mark('start')}',
              ),
              forward(8, '<voice>2</voice><staff>1</staff>'),
              backup(16),
              note('C3', 8, 'half', '<voice>5</voice><staff>2</staff>'),
              note(
                'D3',
                8,
                'half',
                '<voice>5</voice><staff>2</staff>${mark('stop')}',
              ),
            ],
          ]),
        );

        expect(spannersOf(score), isEmpty, reason: element);
      }
    });

    test('keeps a slur that stops on another staff, on the chord that a '
        'second voice of its own staff starts at the stop, where voice one '
        'holds its first note past that time', () {
      const start = '<notations><slur type="start"/></notations>';
      const stop = '<notations><slur type="stop"/></notations>';
      final score = imported(
        keyboard([
          [
            grand,
            note('C5', 16, 'whole', '<voice>1</voice><staff>1</staff>$start'),
            backup(16),
            forward(8),
            note('E4', 4, 'quarter', '<voice>2</voice><staff>1</staff>'),
            note('F4', 4, 'quarter', '<voice>2</voice><staff>1</staff>'),
            backup(16),
            note('C3', 16, 'whole', '<voice>5</voice><staff>2</staff>'),
            backup(16),
            forward(8),
            note('G2', 4, 'quarter', '<voice>6</voice><staff>2</staff>$stop'),
            note('A2', 4, 'quarter', '<voice>6</voice><staff>2</staff>'),
          ],
        ]),
      );

      expect(spannersOf(score), ['slur 0@0-0@1/2']);
      final slur = score.spanners.single;
      expect(slur.voice, VoiceSlot.two);
      expect((slur.kind as Slur).endVoice, isNull);
      Tone tone({required bool last}) =>
          (score.anchorOf(slur, last: last)!.event as ChordEvent)
              .notes
              .single
              .tone;
      expect('${tone(last: false)}', 'C5');
      expect('${tone(last: true)}', 'E4');
    });

    test('reads back a slur of voice one that ends on a note of a second '
        'voice, and a slur of the second voice that starts where that voice '
        'is silent, each in its own voice', () {
      var bar = blankScore(bars: 1);
      bar = fill(bar, 0, [
        chordOf(1, 'C5', value: NoteValue.half),
        chordOf(2, 'D5', value: NoteValue.half),
      ]);
      bar = fill(bar, 0, slot: VoiceSlot.two, [
        Gap(len(1, 2)),
        chordOf(3, 'E4'),
        chordOf(4, 'F4'),
      ]);
      Score slurred(SpannerKind kind, VoiceSlot voice) => withSpanner(
        bar,
        kind,
        pointAt(bar, 0, Moment.zero),
        pointAt(bar, 0, at(1, 2)),
        voice: voice,
      );
      String slurOf(Score score) {
        final slur = score.spanners.single;
        String on({required bool last}) {
          final timed = score.anchorOf(slur, last: last)!;
          return '${timed.voice.name} '
              '${(timed.event as ChordEvent).notes.single.tone}';
        }

        final named = (slur.kind as Slur).endVoice?.name;
        return '${slur.voice?.name} named $named, '
            '${on(last: false)} to ${on(last: true)}';
      }

      final ofOne = slurred(const Slur(endVoice: VoiceSlot.two), VoiceSlot.one);
      final ofTwo = slurred(const Slur(), VoiceSlot.two);

      for (final score in [ofOne, ofTwo]) {
        expect(
          slurOf(scoreFromMusicXml(scoreToMusicXml(score))),
          slurOf(score),
        );
      }
      // MuseScore 4 reads a slur in the voice of its start. When it imports
      // layout, it draws the second voice's slur below from its placement.
      expect(
        scoreToMusicXml(ofOne),
        contains('<slur type="start" number="1"/>'),
      );
      expect(
        scoreToMusicXml(ofTwo),
        contains('<slur type="start" number="1" placement="below"/>'),
      );
    });

    test('reads back two slurs of a second voice where the later one ends '
        'on a note of voice one', () {
      var score = blankScore(bars: 1);
      score = fill(score, 0, [
        chordOf(1, 'C4', value: NoteValue.half),
        chordOf(5, 'B3', value: NoteValue.half),
      ]);
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

    test('reads a slide as a glissando, apart from a glissando of the same '
        'number, and writes it back as a glissando', () {
      String mark(String name, String type) =>
          '<notations><$name type="$type" number="1"/></notations>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 4, 'quarter', mark('slide', 'start')),
            note('G5', 4, 'quarter', mark('glissando', 'start')),
            note('A5', 4, 'quarter', mark('slide', 'stop')),
            note('E5', 4, 'quarter', mark('glissando', 'stop')),
          ],
        ]),
      );
      final text = scoreToMusicXml(score);

      expect(spannersOf(score), [
        'glissando 0@0-0@1/2',
        'glissando 0@1/4-0@3/4',
      ]);
      expect(text, isNot(contains('<slide')));
      expect(spannersOf(scoreFromMusicXml(text)), spannersOf(score));
    });

    group('a glissando on a note of a chord', () {
      String chord(List<(String, String)> notes) => [
        for (final (i, (pitch, mark)) in notes.indexed)
          note(
            pitch,
            4,
            'quarter',
            '${i > 0 ? '<chord/>' : ''}'
                '${mark.isEmpty ? '' : '<notations>$mark</notations>'}',
          ),
      ].join();
      String line(String type, [int number = 1]) =>
          '<glissando type="$type" number="$number"/>';
      Score read(String from, String to) => imported(
        flute([
          [opening(), from, to, note('rest', 8, 'half')],
        ]),
      );
      List<int> keysOfFirstChord(Score score) {
        final first = chordsIn(score, 0).first.id;
        final notes = PlaybackCompiler()
            .compile(score)
            .notesBetween(
              0,
              double.infinity,
            );
        return [
          for (final note in notes)
            if (note.source.id == first) note.key,
        ]..sort();
      }

      List<String> written(Score score) => [
        for (final note in XmlDocument.parse(
          scoreToMusicXml(score),
        ).findAllElements('note'))
          for (final mark in note.findAllElements('glissando'))
            [
              note.getElement('pitch')!.getElement('step')!.innerText,
              note.getElement('pitch')!.getElement('octave')!.innerText,
              ' ${mark.getAttribute('type')}',
            ].join(),
      ];

      test('glides that note alone, toward the note the line ends on', () {
        final score = read(
          chord([('C4', ''), ('E4', ''), ('G4', line('start'))]),
          chord([('D4', ''), ('F4', ''), ('C5', line('stop'))]),
        );

        expect(keysOfFirstChord(score), [60, 64, 67, 68, 69, 70, 71]);
        expect(written(score), ['G4 start', 'C5 stop']);
      });

      test('falls to a lower note of the next chord when its line ends '
          'there', () {
        final score = read(
          chord([('C4', ''), ('G4', line('start'))]),
          chord([('D4', line('stop')), ('C5', '')]),
        );

        expect(keysOfFirstChord(score), [60, 63, 64, 65, 66, 67]);
        expect(written(score), ['G4 start', 'D4 stop']);
      });

      test('glides each note of a chord with two lines along its own', () {
        final score = read(
          chord([('C4', line('start')), ('G4', line('start', 2))]),
          chord([('D4', line('stop', 2)), ('C5', line('stop'))]),
        );

        expect(
          keysOfFirstChord(score),
          [
            ...[for (var key = 60; key < 72; key++) key],
            ...[63, 64, 65, 66, 67],
          ]..sort(),
        );
        expect(written(score), ['C4 start', 'G4 start', 'D4 stop', 'C5 stop']);
      });

      test('keeps a line into one note of a chord apart from a line out of '
          'another', () {
        final score = imported(
          flute([
            [
              opening(),
              chord([('C4', line('start'))]),
              chord([('D4', line('start', 2)), ('C5', line('stop'))]),
              chord([('E4', line('stop', 2))]),
              note('rest', 4, 'quarter'),
            ],
          ]),
        );
        List<(String, String)> joined(Score score) => [
          for (final spanner in score.spanners)
            switch (score.glissandoNotes(spanner)) {
              (:final from, :final to) => ('${from?.tone}', '${to?.tone}'),
            },
        ];

        expect(joined(score), [('C4', 'C5'), ('D4', 'E4')]);
        expect(
          joined(scoreFromMusicXml(scoreToMusicXml(score))),
          joined(score),
        );
      });

      group('between two voices', () {
        String voiced(
          int voice,
          String pitch, {
          String mark = '',
          String type = 'quarter',
        }) => note(
          pitch,
          type == 'half' ? 8 : 4,
          type,
          '<voice>$voice</voice>'
          '${mark.isEmpty ? '' : '<notations>$mark</notations>'}',
        );
        Score read(List<String> one, List<String> two) => imported(
          flute([
            [opening(), ...one, backup(16), ...two],
          ]),
        );
        List<(String, String)> joined(Score score) => [
          for (final spanner in score.spanners)
            switch (score.glissandoNotes(spanner)) {
              (:final from, :final to) => ('${from?.tone}', '${to?.tone}'),
            },
        ];
        final ending = [
          voiced(1, 'C5'),
          voiced(1, 'D5', mark: line('stop')),
          voiced(1, 'rest', type: 'half'),
        ];

        test('ends on a note of voice one, whatever its own voice plays '
            'under that note', () {
          for (final own in [
            [voiced(2, 'E4', mark: line('start')), forward(4)],
            [voiced(2, 'E4', mark: line('start')), voiced(2, 'F4')],
            [voiced(2, 'E4', mark: line('start'), type: 'half')],
          ]) {
            final score = read(ending, [
              ...own,
              voiced(2, 'rest', type: 'half'),
            ]);

            expect(joined(score), [('E4', 'D5')], reason: '$own');
            expect(written(score), ['D5 stop', 'E4 start'], reason: '$own');
            expect(
              joined(scoreFromMusicXml(scoreToMusicXml(score))),
              joined(score),
              reason: '$own',
            );
            expect(joined(reloaded(score)), joined(score), reason: '$own');
          }
        });

        test('drops a line that ends on a note that starts before the note '
            'it starts on', () {
          String eighth(String pitch, [String mark = '']) => note(
            pitch,
            2,
            'eighth',
            '<voice>2</voice>'
                '${mark.isEmpty ? '' : '<notations>$mark</notations>'}',
          );
          final held = [
            voiced(1, 'D5', mark: line('stop'), type: 'half'),
            voiced(1, 'rest', type: 'half'),
          ];

          final back = read(held, [
            eighth('E4'),
            eighth('F4', line('start')),
            forward(4),
            voiced(2, 'rest', type: 'half'),
          ]);
          final together = read(held, [
            voiced(2, 'E4', mark: line('start')),
            forward(4),
            voiced(2, 'rest', type: 'half'),
          ]);

          expect(joined(back), isEmpty);
          expect(joined(together), isEmpty);
        });

        test('starts on a note of voice one that a note of its last '
            'voice sounds under', () {
          final score = read(
            [
              voiced(1, 'C5', mark: line('start')),
              voiced(1, 'D5'),
              voiced(1, 'rest', type: 'half'),
            ],
            [
              voiced(2, 'E4'),
              voiced(2, 'F4', mark: line('stop')),
              voiced(2, 'rest', type: 'half'),
            ],
          );

          expect(joined(score), [('C5', 'F4')]);
          expect(
            joined(scoreFromMusicXml(scoreToMusicXml(score))),
            joined(score),
          );
        });

        test('reads back a line of a second voice that starts in a gap of '
            'its voice over a rest of voice one and names a note of a third '
            'voice, on that rest and that note', () {
          String end(TimedEvent on) => switch (on.event) {
            ChordEvent(:final notes) => '${on.voice.name} ${notes.single.tone}',
            _ => '${on.voice.name} rest',
          };
          String ends(Score score) {
            final line = score.spanners.single;
            return '${spannersOf(score).single}, '
                '${end(score.anchorOf(line, last: false)!)} to '
                '${end(score.anchorOf(line, last: true)!)}, '
                'to note ${score.glissandoNotes(line).to?.tone}';
          }

          var bar = blankScore(bars: 1);
          bar = fill(bar, 0, [
            chordOf(1, 'C5'),
            rest(2, NoteValue.half),
            chordOf(3, 'E5'),
          ]);
          bar = fill(bar, 0, slot: VoiceSlot.three, [
            Gap(len(1, 4)),
            chordOf(4, 'G4'),
            chordOf(5, 'A4'),
            Gap(len(1, 4)),
          ]);
          final score = withSpanner(
            bar,
            const Glissando(to: NoteId(50)),
            pointAt(bar, 0, at(1, 4)),
            pointAt(bar, 0, at(1, 2)),
            voice: VoiceSlot.two,
          );
          final exported = scoreToMusicXml(score);
          final back = scoreFromMusicXml(exported);

          expect(
            ends(score),
            'glissando 0@1/4-0@1/2, one rest to three A4, to note A4',
          );
          expect(ends(back), ends(score));
          expect(scoreToMusicXml(back), exported);
        });
      });

      test('ends a line to a note of another staff on the top note of its '
          'own staff, and names no note there', () {
        String staffed(int staff, String pitch, [String mark = '']) => note(
          pitch,
          pitch == 'rest' ? 8 : 4,
          pitch == 'rest' ? 'half' : 'quarter',
          '<voice>$staff</voice><staff>$staff</staff>'
          '${mark.isEmpty ? '' : '<notations>$mark</notations>'}',
        );
        final score = imported(
          keyboard([
            [
              grand,
              staffed(1, 'C5', line('start')),
              staffed(1, 'D5'),
              staffed(1, 'rest'),
              backup(16),
              staffed(2, 'C3'),
              staffed(2, 'E3', line('stop')),
              staffed(2, 'rest'),
            ],
          ]),
        );
        final spanner = score.spanners.single;

        expect((spanner.kind as Glissando).to, isNull);
        expect('${score.glissandoNotes(spanner).to?.tone}', 'D5');
        expect(reloaded(score).spanners, hasLength(1));
      });

      test('writes a line that names no notes on the top notes', () {
        final read = imported(
          flute([
            [
              opening(),
              chord([('C4', line('start')), ('G4', '')]),
              chord([('D4', line('stop')), ('C5', '')]),
              note('rest', 8, 'half'),
            ],
          ]),
        );
        final score = read.copyWith(
          spanners: Seq([
            for (final spanner in read.spanners)
              Spanner(
                id: spanner.id,
                kind: const Glissando(),
                staff: spanner.staff,
                voice: spanner.voice,
                first: spanner.first,
                last: spanner.last,
              ),
          ]),
        );

        expect(written(read), ['C4 start', 'D4 stop']);
        expect(written(score), ['G4 start', 'C5 stop']);
      });

      test('writes a line that names no end note on the note at its start '
          "note's place in the chord it ends on", () {
        final read = imported(
          flute([
            [
              opening(),
              chord([('C4', line('start')), ('G4', '')]),
              chord([('D4', ''), ('F4', ''), ('C5', line('stop'))]),
              note('rest', 8, 'half'),
            ],
          ]),
        );
        final spanner = read.spanners.single;
        final score = read.copyWith(
          spanners: Seq([
            Spanner(
              id: spanner.id,
              kind: Glissando(from: (spanner.kind as Glissando).from),
              staff: spanner.staff,
              voice: spanner.voice,
              first: spanner.first,
              last: spanner.last,
            ),
          ]),
        );

        expect(written(read), ['C4 start', 'C5 stop']);
        expect(written(score), ['C4 start', 'D4 stop']);
      });
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

    test('moves what a bar ends with to the next bar', () {
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
          [whole],
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

    test('moves a direction by its offset, and no further back than the '
        'start of its bar', () {
      String offset(int divisions) => '<offset>$divisions</offset>';
      final score = imported(
        flute([
          [
            opening(),
            direction(['<dynamics><mf/></dynamics>'], more: offset(-4)),
            note('C5', 4, 'quarter'),
            note('D5', 4, 'quarter'),
            direction(['<dynamics><f/></dynamics>'], more: offset(4)),
            note('E5', 4, 'quarter'),
            note('F5', 4, 'quarter'),
            direction(['<dynamics><p/></dynamics>'], more: offset(-12)),
            direction([metronome(90)], more: offset(-8)),
          ],
        ]),
      );

      expect(marksIn(score, 0), ['0 mf', '1/4 p', '3/4 f']);
      expect(
        [
          for (final mark in score.measures.single.tempos)
            (mark.offset.wholeNotes, mark.tempo.bpm),
        ],
        [(Fraction(1, 2), 90)],
      );
    });

    test('keeps a direction on its event when its offset reaches no '
        'other', () {
      String offset(int divisions) => '<offset>$divisions</offset>';
      String dynamic(String level, String more) =>
          direction(['<dynamics><$level/></dynamics>'], more: more);
      final score = imported(
        flute([
          [
            opening(),
            dynamic('f', offset(1)),
            note('C5', 8, 'half'),
            dynamic('p', offset(-1)),
            dynamic('mf', offset(-4)),
            note('D5', 8, 'half'),
            dynamic('ff', offset(-1)),
          ],
          [
            note('C5', 4, 'quarter'),
            note('D5', 4, 'quarter'),
            dynamic('pp', offset(3)),
            dynamic('mp', '<offset sound="yes">1</offset>'),
            note('E5', 4, 'quarter'),
            note('F5', 4, 'quarter'),
          ],
        ]),
      );

      expect(
        [marksIn(score, 0), marksIn(score, 1)],
        [
          ['0 f', '1/2 p', '1/2 mf'],
          ['0 ff', '9/16 mp', '3/4 pp'],
        ],
      );
      expect(heard(score).first.$4, Dynamic.f.velocity);
    });

    test('keeps a tempo mark on the nearest event of any staff of its '
        'part', () {
      const offset = '<offset>3</offset>';
      final score = imported(
        keyboard([
          [
            grand,
            direction(['<dynamics><f/></dynamics>'], more: offset),
            direction([metronome(90)], more: offset),
            direction(['<rehearsal>A</rehearsal>'], more: offset),
            note('C5', 16, 'whole', '<staff>1</staff>'),
            backup(16),
            for (final pitch in ['C3', 'D3', 'E3', 'F3'])
              note(pitch, 4, 'quarter', '<voice>2</voice><staff>2</staff>'),
          ],
        ]),
      );

      expect(marksIn(score, 0), ['0 f']);
      expect(
        [
          for (final mark in score.measures.single.tempos)
            (mark.offset.wholeNotes, mark.tempo.bpm),
        ],
        [(Fraction(1, 4), 90)],
      );
      expect(score.measures.single.rehearsal, 'A');
    });

    test('moves a dynamic or words written where their staff has no event '
        'to the event of another staff that the offset names', () {
      final score = imported(
        keyboard([
          [
            grand,
            direction(['<dynamics><f/></dynamics>'], more: '<staff>1</staff>'),
            note('C5', 16, 'whole', '<staff>1</staff>'),
            backup(16),
            for (final pitch in ['C3', 'D3', 'E3', 'F3'])
              note(pitch, 4, 'quarter', '<voice>2</voice><staff>2</staff>'),
            direction([
              '<dynamics><p/></dynamics>',
            ], more: '<offset>-12</offset><staff>1</staff>'),
            direction([
              '<words>dolce</words>',
            ], more: '<offset>-8</offset><staff>1</staff>'),
          ],
        ]),
      );

      expect(marksIn(score, 0), ['0 f', '1/4 p', '1/2 dolce']);
      expect(
        [for (final (_, _, key, loudness) in heard(score)) (key, loudness)],
        [
          (Pitch.parse('C5').midiKey, Dynamic.f.velocity),
          (Pitch.parse('C3').midiKey, Dynamic.f.velocity),
          (Pitch.parse('D3').midiKey, Dynamic.p.velocity),
          (Pitch.parse('E3').midiKey, Dynamic.p.velocity),
          (Pitch.parse('F3').midiKey, Dynamic.p.velocity),
        ],
      );
    });

    test('keeps a dynamic on the event it is written on when its offset '
        'lands on an event of another staff', () {
      final score = imported(
        keyboard([
          [
            grand,
            direction([
              '<dynamics><f/></dynamics>',
            ], more: '<offset>4</offset><staff>1</staff>'),
            note('C5', 16, 'whole', '<staff>1</staff>'),
            backup(16),
            for (final pitch in ['C3', 'D3', 'E3', 'F3'])
              note(pitch, 4, 'quarter', '<voice>2</voice><staff>2</staff>'),
          ],
        ]),
      );

      expect(marksIn(score, 0), ['0 f']);
      expect(heard(score).first.$4, Dynamic.f.velocity);
    });

    test('keeps a line end on its event when its offset reaches no other, '
        'and else where the offset puts it', () {
      String offset(int divisions) => '<offset>$divisions</offset>';
      const start = '<wedge type="crescendo"/>';
      const stop = '<wedge type="stop"/>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 4, 'quarter'),
            direction(['<dynamics><pp/></dynamics>', start], more: offset(-1)),
            note('D5', 4, 'quarter'),
            note('E5', 4, 'quarter'),
            direction([stop, '<dynamics><ff/></dynamics>'], more: offset(1)),
            note('F5', 4, 'quarter'),
          ],
          [
            direction([start]),
            note('C5', 8, 'half'),
            note('D5', 8, 'half'),
            direction([stop], more: offset(-6)),
          ],
        ]),
      );

      expect(spannersOf(score), [
        'crescendo 0@1/4-0@1/2',
        'crescendo 1@0-1@1/2',
      ]);
      expect(marksIn(score, 0), ['1/4 pp', '3/4 ff']);
    });

    test('holds what ends the last bar, or what an offset moves past its '
        'end, on the last event of the bar', () {
      String offset(int divisions) => '<offset>$divisions</offset>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 8, 'half'),
            direction(['<dynamics><f/></dynamics>'], more: offset(8)),
            note('D5', 8, 'half'),
          ],
          [
            note('C5', 4, 'quarter'),
            note('D5', 4, 'quarter'),
            direction(['<dynamics><ppp/></dynamics>'], more: offset(4)),
            note('E5', 4, 'quarter'),
            direction(['<dynamics><fff/></dynamics>'], more: offset(8)),
            note('F5', 4, 'quarter'),
            direction(['<words>dolce</words>']),
            direction(['<rehearsal>B</rehearsal>']),
            direction([metronome(90)], more: offset(4)),
          ],
        ]),
      );

      expect(
        [marksIn(score, 0), marksIn(score, 1)],
        [
          isEmpty,
          ['0 f', '3/4 ppp', '3/4 fff', '3/4 dolce'],
        ],
      );
      expect(
        [
          for (final mark in score.measures[1].tempos)
            (mark.offset.wholeNotes, mark.tempo.bpm),
        ],
        [(Fraction(3, 4), 90)],
      );
      expect(score.measures[1].rehearsal, 'B');
    });

    test('leaves an octave line over the notes written inside it, whatever '
        'its offset', () {
      Score lined(String offset) => imported(
        flute([
          [
            opening(),
            note('C5', 4, 'quarter'),
            direction(['<octave-shift type="down" size="8"/>'], more: offset),
            note('D6', 4, 'quarter'),
            note('E6', 4, 'quarter'),
            direction(['<octave-shift type="stop" size="8"/>'], more: offset),
            note('F5', 4, 'quarter'),
          ],
        ]),
      );

      final moved = lined('<offset>4</offset>');
      expect(spannersOf(moved), ['up8 0@1/4-0@1/2']);
      expect(items(moved, 0), items(lined(''), 0));
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

    test('keeps the written value of a note whose duration disagrees with '
        'it, and starts the next note where that value ends', () {
      final score = imported(
        flute([
          [
            opening(beats: 3),
            note('C5', 4, 'quarter'),
            note('D5', 4, 'quarter'),
            note('E5', 2, 'eighth'),
            note('F5', 2, '16th', '<dot/>'),
            note('G5', 1, '16th'),
          ],
        ]),
      );

      expect(items(score, 0), [
        'C5/quarter',
        'D5/quarter',
        'E5/eighth',
        'F5/sixteenth.',
        'G5/sixteenth',
      ]);
      expect(score.measures.single.length, Length(Fraction(25, 32)));
    });

    test('backs up by the durations of notes whose written values disagree '
        'with them', () {
      const one = '<voice>1</voice>';
      const two = '<voice>2</voice>';
      final shorter = imported(
        flute([
          [
            opening(beats: 3),
            note('C5', 4, 'quarter', one),
            note('D5', 4, 'quarter', one),
            note('E5', 2, 'eighth', one),
            note('F5', 2, '16th', '<dot/>$one'),
            backup(12),
            note('C4', 12, 'half', '<dot/>$two'),
          ],
        ]),
      );
      final longer = imported(
        flute([
          [
            opening(),
            note('C5', 2, 'quarter', one),
            note('D5', 4, 'quarter', one),
            note('E5', 4, 'quarter', one),
            backup(10),
            note('C4', 8, 'half', two),
            note('D4', 8, 'half', two),
          ],
        ]),
      );

      expect(items(shorter, 0, slot: VoiceSlot.two), ['C4/half.']);
      expect(shorter.measures.single.length, Length(Fraction(3, 4)));
      expect(items(longer, 0, slot: VoiceSlot.two), ['C4/half', 'D4/half']);
      expect(longer.measures.single.length, Length.whole);
    });

    test('stops a backup at the start of its bar', () {
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 16, 'whole', '<voice>1</voice>'),
            backup(20),
            note('C4', 16, 'whole', '<voice>2</voice>'),
          ],
        ]),
      );

      expect(items(score, 0, slot: VoiceSlot.two), ['C4/whole']);
      expect(score.measures.single.length, Length.whole);
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

      expect(items(score, 0), ['C5/half', 'D5/quarter', 'E5/quarter~lv']);
    });

    group('a let-ring tie before a note of its pitch', () {
      const letRing = '<notations><tied type="let-ring"/></notations>';

      final under = flute([
        [
          opening(divisions: 2),
          note('E5', 2, 'quarter', '<voice>1</voice>'),
          note('F5', 2, 'quarter', '<voice>1</voice>'),
          note('G5', 2, 'quarter', '<voice>1</voice>'),
          note('A5', 2, 'quarter', '<voice>1</voice>'),
          backup(8),
          note('A3', 3, 'quarter', '<dot/><voice>2</voice>'),
          note('C4', 3, 'quarter', '<dot/><voice>2</voice>$letRing'),
          note('D4', 1, 'eighth', '<voice>2</voice>'),
          note('C4', 1, 'eighth', '<voice>2</voice>'),
        ],
      ]);

      List<String> ties(Score score) {
        final staff = score.measureView(score.measures.first.id).staves.first;
        final pitches = {
          for (final voice in staff.voices)
            for (final timed in voice.events)
              if (timed.event case ChordEvent(:final notes))
                for (final note in notes) note.id: note.tone,
        };
        return [
          for (final TieView(:from, :to) in staff.ties)
            '${pitches[from]} -> ${to == null ? 'none' : pitches[to.note]}',
        ];
      }

      int struck(Score score, int key) => PlaybackCompiler()
          .compile(score)
          .notesBetween(0, double.infinity)
          .where((note) => note.key == key)
          .length;

      EventRef eventOf(Score score, String pitch) => [
        for (final staff in score.measureView(score.measures.first.id).staves)
          for (final voice in staff.voices)
            for (final timed in voice.events)
              if (timed.event case ChordEvent(:final notes)
                  when '${notes.first.tone}' == pitch)
                timed.ref,
      ].first;

      test('rings and does not tie to it', () {
        final score = imported(
          flute([
            [
              opening(),
              note('C5', 8, 'half', letRing),
              note('C5', 4, 'quarter'),
              note('D5', 4, 'quarter'),
            ],
          ]),
        );

        expect(ties(score), ['C5 -> none']);
        expect(struck(score, 72), 2);
        expect(
          XmlDocument.parse(
            scoreToMusicXml(score),
          ).findAllElements('tied').map((tied) => tied.getAttribute('type')),
          ['let-ring'],
        );
      });

      test('rings and does not tie to it under a sounding tie', () {
        final score = imported(
          flute([
            [
              opening(),
              note('C5', 8, 'half', '<tie type="start"/>$letRing'),
              note('C5', 4, 'quarter'),
              note('D5', 4, 'quarter'),
            ],
          ]),
        );

        expect(ties(score), ['C5 -> none']);
        expect(struck(score, 72), 2);
      });

      test('rings on after a rippled erase brings that note after it', () {
        final score = imported(under);
        expect(ties(score), ['C4 -> none']);

        final erased = applied(
          EditSession.start(score).run(
            Erase(
              ItemSelection(Seq([eventOf(score, 'F5'), eventOf(score, 'D4')])),
              ripple: Ripple.part,
            ),
          ),
        ).score;

        expect(items(erased, 0, slot: VoiceSlot.two).take(3), [
          'A3/quarter',
          'C4/quarter~lv',
          'C4/eighth',
        ]);
        expect(ties(erased), ['C4 -> none']);
        expect(struck(erased, 60), 2);
        expect(
          XmlDocument.parse(
            scoreToMusicXml(erased),
          ).findAllElements('tied').map((tied) => tied.getAttribute('type')),
          ['let-ring'],
        );
      });
    });

    group('a lone let-ring mark at the end of a repeat', () {
      const library = '<software>khuur_sheet_music</software>';
      const marked =
          '<supports element="tied" attribute="type" type="yes" '
          'value="let-ring"/>';
      const letRing = '<notations><tied type="let-ring"/></notations>';
      const repeatEnd =
          '<barline location="right"><repeat direction="backward"/>'
          '</barline>';
      final music = part('P1', [
        [
          opening(),
          note('F4', 8, 'half'),
          note('F4', 8, 'half', letRing),
          repeatEnd,
        ],
      ]);

      Score read(String encoding) => imported(
        partwise(
          '<identification><encoding>$encoding</encoding></identification>'
          '<part-list>${scorePart('P1')}</part-list>$music',
        ),
      );

      Note last(Score score) {
        final voice = score
            .measureView(score.measures.single.id)
            .staves
            .single
            .voices
            .single;
        return (voice.events.last.event as ChordEvent).notes.single;
      }

      int struck(Score score) => PlaybackCompiler()
          .compile(score)
          .notesBetween(0, double.infinity)
          .length;

      test('is a plain tie that joins the repeat in an older file of this '
          'library', () {
        final score = read(library);

        expect(last(score).tie, isTrue);
        expect(last(score).letRing, isFalse);
        expect(struck(score), 3);
      });

      for (final (writer, encoding) in [
        ('a file of this library that declares the mark', '$library$marked'),
        ('a file of another program', '<software>MuseScore 4.7.7</software>'),
        ('a file with no software', ''),
        (
          'a file that names a second program',
          '$library<software>MuseScore 4.7.7</software>',
        ),
      ]) {
        test('is a let-ring tie that joins nothing in $writer', () {
          final score = read(encoding);

          expect(last(score).tie, isFalse);
          expect(last(score).letRing, isTrue);
          expect(struck(score), 4);
        });
      }
    });

    test('ends a tie that no note stops on the same pitch in the next event '
        'of its voice', () {
      const start = '<tie type="start"/>';
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 8, 'half', start),
            note('C5', 4, 'quarter'),
            note('D5', 4, 'quarter', start),
          ],
          [
            note('D5', 8, 'half'),
            note('E5', 4, 'quarter', start),
            note('F5', 4, 'quarter'),
          ],
        ]),
      );

      expect(items(score, 0), ['C5/half~', 'C5/quarter', 'D5/quarter~']);
      expect(items(score, 1), ['D5/half', 'E5/quarter', 'F5/quarter']);
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

    test('keeps the trill mark of a trill line that never stops', () {
      String ornaments(String children) =>
          '<notations><ornaments>$children</ornaments></notations>';
      final lined = ornaments('<trill-mark/><wavy-line type="start"/>');
      final score = imported(
        flute([
          [
            opening(),
            note('C5', 4, 'quarter', lined),
            note('D5', 4, 'quarter', lined),
            note('E5', 4, 'quarter', ornaments('<wavy-line type="stop"/>')),
            note('F5', 4, 'quarter', lined),
          ],
        ]),
      );

      expect(spannersOf(score), ['trill 0@1/4-0@1/2']);
      expect(
        [for (final chord in chordsIn(score, 0)) chord.ornament],
        [Ornament.trill, null, null, Ornament.trill],
      );
    });

    test('reads the accidental marks that follow an ornament\'s sign', () {
      String ornaments(String children) =>
          '<notations><ornaments>$children</ornaments></notations>';
      final score = imported(
        flute([
          [
            opening(),
            note(
              'C5',
              4,
              'quarter',
              ornaments(
                '<turn/><accidental-mark>flat</accidental-mark>'
                '<accidental-mark placement="below">natural</accidental-mark>',
              ),
            ),
            note(
              'C5',
              4,
              'quarter',
              ornaments(
                '<accidental-mark>sharp</accidental-mark><mordent/>'
                '<accidental-mark placement="below">sharp-sharp</accidental-mark>',
              ),
            ),
            note(
              'C5',
              4,
              'quarter',
              ornaments(
                '<trill-mark/><wavy-line type="start"/>'
                '<accidental-mark>sharp</accidental-mark>'
                '<wavy-line type="stop"/>',
              ),
            ),
            note('C5', 4, 'quarter'),
          ],
        ]),
      );

      expect(
        [
          for (final chord in chordsIn(score, 0))
            (chord.ornament, chord.ornamentAbove, chord.ornamentBelow),
        ],
        [
          (Ornament.turn, Alter.flat, Alter.natural),
          (Ornament.mordent, null, Alter.doubleSharp),
          (null, null, null),
          (null, null, null),
        ],
      );
    });

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

    test("reads back a grace note's fingering and string", () {
      PitchedNote grace(int id, String pitch, {int? finger, int? string}) =>
          PitchedNote(
            id: NoteId(id),
            pitch: Pitch.parse(pitch),
            fingering: finger,
            string: string,
          );
      final score = scoreWith([
        ChordEvent(
          id: const EventId(1),
          value: NoteValue.whole,
          notes: Seq([grace(2, 'C5')]),
          graces: Seq([
            GraceChord(
              id: const EventId(3),
              kind: GraceKind.acciaccatura,
              value: NoteValue.eighth,
              notes: Seq([
                grace(4, 'D5', finger: 3, string: 1),
                grace(5, 'F5', finger: 0, string: 0),
              ]),
            ),
            GraceChord(
              id: const EventId(6),
              kind: GraceKind.appoggiatura,
              value: NoteValue.eighth,
              notes: Seq([grace(7, 'E5', string: 1), grace(8, 'G5')]),
            ),
          ]),
        ),
      ]);

      final back = scoreFromMusicXml(scoreToMusicXml(score));

      expect(
        [
          for (final grace in chordsIn(back, 0).single.graces)
            for (final note in grace.notes.cast<PitchedNote>())
              ('${note.pitch}', note.fingering, note.string),
        ],
        [('D5', 3, 1), ('F5', 0, 0), ('E5', null, 1), ('G5', null, null)],
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
