import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'random_edits.dart';
import 'showcase.dart';
import 'support.dart';

Score reloaded(Score score) =>
    scoreFromJson(jsonDecode(jsonEncode(scoreToJson(score))));

String saved(Score score) =>
    '${const JsonEncoder.withIndent('  ').convert(scoreToJson(score))}\n';

List<String> views(Score score) => [
  for (final column in score.measures)
    describeView(score.measureView(column.id)),
];

final golden = File('test/golden/showcase.json');

/// Marks a member to remove in [put].
const missing = Object();

/// [root] with the value at [path] (as in `$.parts[0].name`) set to
/// [value], or removed when [value] is [missing].
Object? put(Object? root, String path, Object? value) {
  if (path == r'$') {
    return value;
  }
  final steps = [
    for (final match in RegExp(r'\.(\w+)|\[(\d+)\]').allMatches(path))
      match[1] ?? int.parse(match[2]!),
  ];
  var node = root;
  for (final step in steps.take(steps.length - 1)) {
    node = step is String
        ? (node! as Map<String, Object?>)[step]
        : (node! as List<Object?>)[step as int];
  }
  final last = steps.last;
  if (last is String) {
    final map = node! as Map<String, Object?>;
    if (identical(value, missing)) {
      map.remove(last);
    } else {
      map[last] = value;
    }
  } else {
    (node! as List<Object?>)[last as int] = value;
  }
  return root;
}

typedef Broken = ({Map<String, Object?> set, String at, String rule});

/// The file with [value] at [at], refused there for [rule].
Broken bad(String at, Object? value, String rule) =>
    (set: {at: value}, at: at, rule: rule);

/// The file with each of [set], refused at [at] for [rule].
Broken badAt(String at, String rule, Map<String, Object?> set) =>
    (set: set, at: at, rule: rule);

const bar0 = r'$.measures[0].staves[0]';
const chord0 = '$bar0.voices[0].items[0]';
const drums0 = r'$.measures[0].staves[2].voices[0].items[0]';
const tuplet1 = r'$.measures[1].staves[0].voices[0].items[0]';

final broken = <Broken>[
  bad(r'$', <Object?>[], 'expected an object'),
  bad(r'$.schema', 2, 'written by a newer version'),
  bad(r'$.schema', 0, 'no such version'),
  bad(r'$.schema', missing, 'missing'),
  bad(r'$.parts', <String, Object?>{}, 'expected a list'),
  bad(r'$.parts', <Object?>[], 'a score has at least one part'),
  badAt(r'$.parts', 'a score shows at least one part', {
    r'$.parts[0].hidden': true,
    r'$.parts[2].hidden': true,
  }),
  bad(r'$.parts[0].id', '1', 'expected an integer'),
  bad(r'$.parts[0].name', 3, 'expected a string'),
  bad(r'$.parts[1].hidden', 'yes', 'expected true or false'),
  bad(r'$.parts[1].id', 1, 'id 1 is used twice'),
  bad(r'$.parts[2].staves[0].id', 2, 'id 2 is used twice'),
  bad(r'$.parts[0].staves', <Object?>[], 'a part has at least one staff'),
  bad(r'$.parts[0].staves[0].lines', 0, 'a staff has at least one line'),
  bad(r'$.parts[0].instrument.program', 128, 'a MIDI number is 0 to 127'),
  bad(r'$.parts[0].instrument.program', -1, 'a MIDI number is 0 to 127'),
  bad(r'$.parts[2].instrument.bank', -1, 'a bank is 0 or more'),
  bad(
    r'$.parts[0].instrument.clef',
    'violin',
    'expected one of treble, treble8vb, treble8va, bass, bass8vb, soprano, mezzoSoprano, alto, tenor, baritoneC, baritoneF, percussion',
  ),
  for (final interval in [
    [1],
    [1, 2, 3],
  ])
    bad(
      r'$.parts[1].instrument.transposition',
      interval,
      'a transposition is [steps, semitones]',
    ),
  bad(
    r'$.parts[2].instrument.drums[1].name',
    'Snare',
    'the kit names Snare twice',
  ),
  bad(r'$.measures', <Object?>[], 'a score has at least one measure'),
  bad(r'$.measures[1].id', 10, 'id 10 is used twice'),
  bad(r'$.measures[0].meter', missing, 'missing'),
  bad(r'$.measures[0].meter', '4', 'expected a meter such as "3+2+2/8"'),
  bad(r'$.measures[0].meter', '0/4', 'expected a meter such as "3+2+2/8"'),
  bad(r'$.measures[0].meter', '4/3', 'the unit is a power of two up to 128'),
  bad(r'$.measures[0].meter', '4/256', 'the unit is a power of two up to 128'),
  bad(r'$.measures[0].meter', '65/1', 'a bar lasts at most 64 whole notes'),
  bad(r'$.measures[0].length', '129/2', 'a bar lasts at most 64 whole notes'),
  bad(r'$.measures[0].key', 8, 'a key has 7 flats to 7 sharps'),
  bad(r'$.measures[0].key', -8, 'a key has 7 flats to 7 sharps'),
  bad(r'$.measures[2].mode', 'dorian', 'expected one of none, major, minor'),
  bad(
    r'$.measures[0].length',
    '1/384',
    'a bar holds a whole number of 128th notes',
  ),
  bad(
    r'$.measures[0].length',
    '0',
    'a bar holds a whole number of 128th notes',
  ),
  for (final count in [2, 4])
    bad(r'$.measures[0].staves', [
      for (var i = 0; i < count; i++) <String, Object?>{},
    ], 'expected 3, one per staff'),
  bad(r'$.measures[1].repeatEnd', 1, 'a repeat plays twice or more'),
  for (final (at, endings) in [
    ('', <Object?>[]),
    ('[0]', [0]),
    ('[1]', [2, 2]),
  ])
    badAt(
      '\$.measures[2].volta.endings$at',
      'an ending lists its passes from 1, in order',
      {r'$.measures[2].volta.endings': endings},
    ),
  bad(
    r'$.measures[0].navigation[0]',
    'dal segno',
    'expected segno, coda, toCoda, fine or a jump',
  ),
  for (final bpm in [0, double.infinity])
    bad(
      r'$.measures[0].tempos[0].bpm',
      bpm,
      'a tempo is a finite number above 0',
    ),
  badAt(
    r'$.measures[2].tempos[1]',
    'tempo marks are in time order, one at a time',
    {r'$.measures[2].tempos[1].at': '0'},
  ),
  bad(r'$.measures[2].tempos[1].at', '3/4', 'not inside the bar'),
  bad(r'$.measures[0].key', missing, 'missing'),
  bad(r'$.measures[0].staves[0].clef', missing, 'missing'),
  bad(
    r'$.measures[1].staves[0].clefChanges[0].at',
    '0',
    'a clef change comes after the bar starts',
  ),
  for (final second in ['1/4', '1/2'])
    badAt(
      r'$.measures[1].staves[0].clefChanges[1]',
      'clef changes are in time order, one at a time',
      {
        r'$.measures[1].staves[0].clefChanges': [
          {'at': '1/2', 'clef': 'alto'},
          {'at': second, 'clef': 'bass'},
        ],
      },
    ),
  bad('$bar0.directions[0].at', '1/4', 'not inside the bar'),
  badAt('$bar0.directions[1]', 'directions are in time order', {
    '$bar0.directions[0].at': '1/8',
  }),
  bad(
    '$bar0.directions[0].dynamic',
    'loud',
    'expected one of pppp, ppp, pp, p, mp, mf, f, ff, fff, ffff, sf, sfz, fp, rfz',
  ),
  bad('$bar0.directions[2].chord', 'H', 'expected a pitch name such as "F#"'),
  bad('$bar0.directions[2].bass', 'Eb4', 'expected a pitch name such as "F#"'),
  badAt(
    '$bar0.voices[0].items',
    'spans 0, bar is 1/4',
    {'$bar0.voices[0].items': <Object?>[]},
  ),
  badAt('$bar0.voices', 'voice one comes first', {
    '$bar0.voices': [
      {
        'voice': 2,
        'items': [
          {'rest': 99, 'value': 'quarter'},
        ],
      },
    ],
  }),
  badAt('$bar0.voices[1]', 'voices are in order, each once', {
    '$bar0.voices[0].voice': 2,
  }),
  bad('$bar0.voices[1].voice', 5, 'a voice is 1 to 4'),
  badAt('$bar0.voices[0].items[0]', 'voice one has no gaps', {
    '$bar0.voices[0].items': [
      {'gap': '1/4'},
    ],
  }),
  badAt(
    '$bar0.voices[1].items',
    'a voice other than one holds more than gaps',
    {
      '$bar0.voices[1].items': [
        {'gap': '1/4'},
      ],
    },
  ),
  bad('$bar0.voices[1].items[0].gap', '0', 'expected a length above 0'),
  bad(
    '$bar0.voices[1].items[0].gap',
    '1/0',
    'expected a fraction such as "3/8"',
  ),
  badAt(
    r'$.measures[0].staves[1].voices[0].items[1]',
    'a measure rest is alone in its voice',
    {
      r'$.measures[0].staves[1].voices[0].items': [
        {'rest': 99, 'value': 'eighth'},
        {'measureRest': 17},
      ],
    },
  ),
  bad(
    r'$.measures[0].staves[1].voices[0].items[0].articulations',
    ['accent'],
    'a rest holds only a fermata',
  ),
  for (final (key, value) in [('rest', 99), ('chord', missing)])
    badAt(
      chord0,
      'expected exactly one of gap, measureRest, chord, rest, tuplet',
      {
        '$chord0.$key': value,
      },
    ),
  bad(
    '$chord0.value',
    'quarter....',
    'expected a note value such as "quarter."',
  ),
  bad('$chord0.value', 'crotchet', 'expected a note value such as "quarter."'),
  bad('$chord0.notes', <Object?>[], 'a chord has at least one note'),
  badAt('$chord0.notes[1]', 'a chord lists its notes in order, each once', {
    '$chord0.notes[1].pitch': 'F#4',
  }),
  bad('$chord0.notes[0].pitch', 'H4', 'expected a pitch such as "F#4"'),
  for (final pitch in ['G#9', 'C-2'])
    bad(
      '$chord0.notes[0].pitch',
      pitch,
      'a pitch lies within MIDI keys 0 to 127',
    ),
  bad(
    '$chord0.value',
    'oneTwentyEighth.',
    'a value lasts a whole number of 128th notes',
  ),
  bad('$chord0.notes[0].pitch', 'F#', 'expected a pitch such as "F#4"'),
  badAt('$chord0.notes[0]', 'a pitched staff takes pitches', {
    '$chord0.notes[0]': {'id': 12, 'drum': 'Snare'},
  }),
  bad('$chord0.notes[0].string', 4, 'the instrument has no such string'),
  bad('$chord0.notes[0].string', -1, 'the instrument has no such string'),
  bad('$chord0.notes[0].fingering', -1, 'a finger number is 0 or more'),
  bad('$chord0.notes[1].id', 12, 'id 12 is used twice'),
  bad('$chord0.graces[0].id', 11, 'id 11 is used twice'),
  bad('$chord0.graces[0].notes[0].id', 12, 'id 12 is used twice'),
  bad('$chord0.tremolo', 5, 'tremolo strokes are 0 to 4'),
  bad('$chord0.lyrics[0].verse', 0, 'verses count from 1'),
  badAt('$chord0.lyrics[1]', 'a chord has one lyric per verse, in order', {
    '$chord0.lyrics[1].verse': 1,
  }),
  badAt('$drums0.notes[0]', 'a percussion staff takes drums', {
    '$drums0.notes[0]': {'id': 19, 'pitch': 'F4'},
  }),
  bad('$drums0.notes[0].drum', 'Cowbell', 'the kit has no Cowbell'),
  bad('$drums0.graces[0].notes[0].drum', 'Cowbell', 'the kit has no Cowbell'),
  bad(
    '$tuplet1.members[1]',
    {'gap': '1/8'},
    'expected exactly one of chord, rest, tuplet',
  ),
  badAt('$tuplet1.members', 'members span 1/2, expected 3/8', {
    '$tuplet1.members[1]': {'rest': 34, 'value': 'quarter'},
  }),
  for (final ratio in [
    [3],
    [3, 2, 1],
  ])
    bad('$tuplet1.ratio', ratio, 'a ratio is [actual, normal]'),
  bad('$tuplet1.ratio[1]', 0, 'ratio terms are above 0'),
  badAt('$tuplet1.members[2].tuplet', 'id 35 is used twice', {
    '$tuplet1.tuplet': 35,
  }),
  badAt(r'$.spanners[1].id', 'id 81 is used twice', {r'$.spanners[0].id': 81}),
  bad(r'$.spanners[0].staff', 99, 'no such staff'),
  bad(
    r'$.spanners[0].kind',
    'tie',
    'expected one of slur, crescendo, diminuendo, octave, trill, tempo, pedal, glissando',
  ),
  bad(r'$.spanners[0].from.measure', 99, 'no such bar'),
  bad(r'$.spanners[0].from.at', '1', 'not inside the bar'),
  bad(
    r'$.spanners[3].shift',
    'up9',
    'expected one of up8, down8, up15, down15, up22, down22',
  ),
  bad(r'$.spanners[5].factor', 0, 'a factor is a finite number above 0'),
  bad(r'$.spanners[0].voice', missing, 'a slur or glissando names its voice'),
  bad(r'$.spanners[1].voice', 2, 'only a slur or glissando names a voice'),
  for (final at in ['0', '1/16'])
    badAt(r'$.spanners[0].to', 'a slur or glissando ends after it starts', {
      r'$.spanners[0].to': {'measure': 30, 'at': at},
    }),
  badAt(r'$.spanners[1].to', 'a line cannot end before it starts', {
    r'$.spanners[1].from': {'measure': 60, 'at': '0'},
  }),
];

void main() {
  group('JSON save format', () {
    test('writes every field as the golden file shows', () {
      if (Platform.environment['UPDATE_GOLDEN'] == '1') {
        golden.writeAsStringSync(saved(showcase()));
      }

      expect(saved(showcase()), golden.readAsStringSync());
    });

    test('reads the golden file back to the score it was saved from', () {
      final loaded = scoreFromJson(jsonDecode(golden.readAsStringSync()));

      expect(saved(loaded), golden.readAsStringSync());
      expect(views(loaded), views(showcase()));
    });

    test('fills meter, key and clef into bars that leave them out', () {
      final loaded = reloaded(showcase());

      expect(
        [for (final c in loaded.measures) '${c.meter} ${c.meter.symbol.name}'],
        ['4/4 common', '4/4 common', '6/8 numeric', '3+2+2/8 numeric'],
      );
      expect(
        [for (final c in loaded.measures) '${c.key} ${c.key.mode.name}'],
        ['2# major', '2# major', '3b minor', '3b minor'],
      );
      expect(
        [for (final c in loaded.measures) c.staves.first.clef],
        [Clef.treble, Clef.treble, Clef.alto, Clef.treble],
      );
    });

    test('leaves out every value at its default', () {
      expect(scoreToJson(plain()), {
        'schema': 1,
        'parts': [
          {
            'id': 1,
            'name': 'Flute',
            'instrument': {'key': 'flute', 'program': 73},
            'staves': [
              {'id': 2},
            ],
          },
        ],
        'measures': [
          {
            'id': 3,
            'meter': '4/4',
            'key': 0,
            'staves': [
              {
                'clef': 'treble',
                'directions': [
                  {'at': '0', 'chord': 'C'},
                ],
                'voices': [
                  {
                    'voice': 1,
                    'items': [
                      {'measureRest': 4},
                    ],
                  },
                ],
              },
            ],
          },
          {
            'id': 5,
            'navigation': [
              {'jump': 'start'},
            ],
            'staves': [
              {
                'voices': [
                  {
                    'voice': 1,
                    'items': [
                      {'measureRest': 6},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });
      expect(saved(reloaded(plain())), saved(plain()));
    });

    test('reads values at the ends of their ranges', () {
      Object? json = jsonDecode(golden.readAsStringSync());
      for (final (path, value) in [
        (r'$.parts[0].instrument.program', 127),
        (r'$.parts[2].instrument.bank', 0),
        (r'$.measures[0].key', 7),
        (r'$.measures[2].key', -7),
        (r'$.measures[1].repeatEnd', 2),
        (r'$.measures[0].tempos[0].beat', 'quarter...'),
        ('$chord0.tremolo', 4),
        ('$chord0.notes[0].fingering', 0),
        ('$chord0.notes[0].id', 11),
        (r'$.spanners[0].id', 10),
      ]) {
        json = put(json, path, value);
      }
      final loaded = scoreFromJson(json);
      final chord =
          loaded.measures[0].staves[0].voices[0].items[0] as ChordEvent;
      final note = chord.notes[0] as PitchedNote;

      expect(loaded.parts[0].instrument.program, 127);
      expect(loaded.parts[2].instrument.bank, 0);
      expect([for (final c in loaded.measures) c.key.fifths], [7, 7, -7, -7]);
      expect(loaded.measures[1].repeatEnd?.times, 2);
      expect(
        loaded.measures[0].tempos[0].tempo.beat,
        const NoteValue(DurationBase.quarter, dots: 3),
      );
      expect(chord.tremolo, 4);
      expect((note.id, note.fingering), (const NoteId(11), 0));
      expect(loaded.spanners[0].id, const SpannerId(10));
    });

    test('round-trips every score the edits make', () {
      for (final seed in [1, 2, 3]) {
        final random = Random(seed);
        var score = blankScore(parts: const [morinKhuur, clarinet], bars: 4);
        for (var step = 0; step < 100; step++) {
          score = randomEdit(score, random);
          final loaded = reloaded(score);
          final where = 'seed $seed, step $step';

          expect(saved(loaded), saved(score), reason: where);
          expect(views(loaded), views(score), reason: where);
        }
      }
    });

    group('refuses a broken file at its path', () {
      for (final (:set, :at, :rule) in broken) {
        test('$at: $rule', () {
          Object? json = jsonDecode(jsonEncode(scoreToJson(showcase())));
          for (final MapEntry(key: path, :value) in set.entries) {
            json = put(json, path, value);
          }

          expect(
            () => scoreFromJson(json),
            throwsA(
              isA<ScoreFormatException>()
                  .having((e) => e.path, 'path', at)
                  .having((e) => e.message, 'message', rule),
            ),
          );
        });
      }
    });
  });
}
