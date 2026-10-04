import 'package:example/demo_score.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';

// What each bar should sound, written apart from the demo's own tables so a
// slip in either shows. The right hand is one string of pitches per bar, the
// left hand one string per chord.
const _melody = [
  'E4 G4 C5 B4 C5',
  'A4 A4 B4 C5 E5',
  'D5 C5 A4 F4 A4',
  'G4 A4 B4 C5 D5 G4',
  'E5 D5 C5 G4 E4',
  'F4 G4 A4 C5 A4 F4',
  'D5 B4 G4 B4 D5',
  'E5 D5 C5',
];

const _chords = [
  ['C3 E3 G3', 'C3 E3 G3'],
  ['A2 C3 E3', 'A2 C3 E3'],
  ['F2 A2 C3', 'F2 A2 C3', 'F2 A2 C3', 'F2 A2 C3'],
  ['G2 B2 D3', 'G2 B2 D3', 'G2 B2 D3', 'G2 B2 D3'],
  ['C3 E3 G3', 'C3 E3 G3'],
  ['F2 A2 C3', 'F2 A2 C3'],
  ['G2 B2 D3', 'G2 B2 D3 F3'],
  ['C3 E3 G3'],
];

/// The bars in the order they play, as (index, pass). Bars 3 and 4 repeat.
const _played = [
  (0, 1),
  (1, 1),
  (2, 1),
  (3, 1),
  (2, 2),
  (3, 2),
  (4, 1),
  (5, 1),
  (6, 1),
  (7, 1),
];

List<int> _keys(String pitches) => [
      for (final name in pitches.split(' ')) Pitch.parse(name).midiKey,
    ];

void main() {
  final score = buildDemoScore();
  final script = PlaybackCompiler().compile(score);
  final treble = score.staves.first.id;

  Iterable<PlaybackNote> notesIn(PlayedBar bar) =>
      script.notesBetween(bar.start, bar.end);

  test('is eight bars of one piano part on two staves', () {
    expect(score.measures.length, 8);
    expect(score.parts.length, 1);
    expect(score.staves.length, 2);
    expect(script.channels.map((c) => (c.program, c.bank)), [(0, 0)]);
  });

  test('plays bars 3 and 4 twice and the rest once', () {
    expect([
      for (final bar in script.bars) (score.indexOf(bar.measure), bar.pass),
    ], _played);
  });

  test('runs at 96 beats a minute, 2.5 seconds a bar', () {
    expect(script.totalSeconds, closeTo(25, 1e-9));
    for (final (i, bar) in script.bars.indexed) {
      expect(bar.start, closeTo(2.5 * i, 1e-9));
    }
  });

  test('sounds the melody and the chords it was written with', () {
    for (final bar in script.bars) {
      final index = score.indexOf(bar.measure);
      final reason = 'bar ${index + 1}, pass ${bar.pass}';

      final right = [
        for (final note in notesIn(bar))
          if (note.source.staff == treble) note.key,
      ];
      expect(right, _keys(_melody[index]), reason: 'right hand, $reason');

      final byStart = <double, List<int>>{};
      for (final note in notesIn(bar)) {
        if (note.source.staff != treble) {
          (byStart[note.start] ??= []).add(note.key);
        }
      }
      final left = [
        for (final start in byStart.keys.toList()..sort())
          (byStart[start]!..sort()),
      ];
      expect(left, _chords[index].map(_keys), reason: 'left hand, $reason');
    }
  });
}
