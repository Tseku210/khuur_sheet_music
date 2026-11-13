import 'package:example/demo_score.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khuur_sheet_music/khuur_sheet_music.dart';

// What each bar should hold, written apart from the demo's own tables so a
// slip in either shows. One string for each hand of each bar, the pickup
// first. `s`, `e` and `q` are a sixteenth, an eighth and a quarter, and `r`
// is a rest.
const _right = [
  's:E5 s:D#5',
  's:E5 s:D#5 s:E5 s:B4 s:D5 s:C5',
  'e:A4 s:r s:C4 s:E4 s:A4',
  'e:B4 s:r s:E4 s:G#4 s:B4',
  'e:C5 s:r s:E4 s:E5 s:D#5',
  's:E5 s:D#5 s:E5 s:B4 s:D5 s:C5',
  'e:A4 s:r s:C4 s:E4 s:A4',
  'e:B4 s:r s:E4 s:C5 s:B4',
  'q:A4',
];

const _left = [
  'bar rest',
  'bar rest',
  's:A2 s:E3 s:A3 s:r e:r',
  's:E2 s:E3 s:G#3 s:r e:r',
  's:A2 s:E3 s:A3 s:r e:r',
  'bar rest',
  's:A2 s:E3 s:A3 s:r e:r',
  's:E2 s:E3 s:G#3 s:r e:r',
  's:A2 s:E3 s:A3 s:r',
];

/// How long each bar is, in eighths.
const _eighths = [1, 3, 3, 3, 3, 3, 3, 3, 2];

/// The sixteenth the pedal lifts on, for each bar that has a pedal. It goes
/// down with the bar. It lifts at the barline, or before the two notes of
/// the right hand that lead into the next bar.
const _lifts = {2: 6, 3: 6, 4: 4, 6: 6, 7: 4, 8: 4};

const _values = {
  's': NoteValue.sixteenth,
  'e': NoteValue.eighth,
  'q': NoteValue.quarter,
};

/// The value and the pitch of each note and rest of [bar], a null pitch for
/// a rest.
List<(NoteValue, String?)> _events(String bar) => [
  if (bar != 'bar rest')
    for (final [value, pitch] in bar.split(' ').map((e) => e.split(':')))
      (_values[value]!, pitch == 'r' ? null : pitch),
];

/// The onset and the length of each note of [bar], in sixteenths.
List<(int, int)> _spans(String bar) {
  final spans = <(int, int)>[];
  var onset = 0;
  for (final (value, pitch) in _events(bar)) {
    final length = (value.length / NoteValue.sixteenth.length).numerator;
    if (pitch != null) {
      spans.add((onset, length));
    }
    onset += length;
  }
  return spans;
}

List<int> _keys(String bar) => [
  for (final (_, pitch) in _events(bar))
    if (pitch != null) Pitch.parse(pitch).midiKey,
];

void main() {
  final score = buildDemoScore();
  final script = PlaybackCompiler().compile(score);
  final [treble, bass] = [for (final staff in score.staves) staff.id];

  VoiceView voiceOne(int staff, int bar) =>
      score.measureView(score.measures[bar].id).staves[staff].voices.first;

  List<int> keysIn(PlayedBar bar, StaffId staff) => [
    for (final note in script.notesBetween(bar.start, bar.end))
      if (note.source.staff == staff) note.key,
  ];

  test('is a pickup and eight bars in 3/8 for one piano on two staves', () {
    expect(score.meta.title, 'Für Elise');
    expect(score.meta.composer, 'Ludwig van Beethoven');
    expect(score.parts.length, 1);
    expect(score.staves.length, 2);
    expect(script.channels.map((c) => (c.program, c.bank)), [(0, 0)]);
    expect([
      for (final column in score.measures)
        column.length.wholeNotes * Fraction(8),
    ], _eighths.map(Fraction.new));
    expect(score.measures.map((column) => column.meter).toSet(), {
      const Meter([3], 8),
    });
  });

  test('holds each hand note for note and rest for rest', () {
    for (final (staff, hand) in [_right, _left].indexed) {
      for (final (bar, written) in hand.indexed) {
        expect(
          [
            for (final timed in voiceOne(staff, bar).events)
              switch (timed.event) {
                ChordEvent(:final value, :final notes) => (
                  value,
                  notes.map((note) => '${note.tone}').join(' '),
                ),
                RestEvent(:final value) => (value, null),
                MeasureRest() => null,
              },
          ],
          written == 'bar rest' ? [null] : _events(written),
          reason: 'staff $staff, bar $bar',
        );
      }
    }
  });

  test('plays every bar twice, the pickup with them', () {
    expect(
      [for (final bar in script.bars) (score.indexOf(bar.measure), bar.pass)],
      [
        for (final pass in [1, 2])
          for (var bar = 0; bar < 9; bar++) (bar, pass),
      ],
    );
  });

  test('runs at 120 eighths a minute, half a second an eighth', () {
    var eighths = 0;
    for (final bar in script.bars) {
      expect(bar.start, closeTo(eighths / 2, 1e-9));
      eighths += _eighths[score.indexOf(bar.measure)];
    }
    expect(eighths, 48);
    expect(script.totalSeconds, closeTo(24, 1e-9));
  });

  test('sounds the notes of both hands in both passes', () {
    for (final bar in script.bars) {
      final index = score.indexOf(bar.measure);
      final reason = 'bar $index, pass ${bar.pass}';
      expect(
        keysIn(bar, treble),
        _keys(_right[index]),
        reason: 'right, $reason',
      );
      expect(keysIn(bar, bass), _keys(_left[index]), reason: 'left, $reason');
    }
  });

  test("has a pedal line under each bar of the left hand's notes", () {
    expect(
      {
        for (final spanner in score.spanners)
          if (spanner.kind is PedalLine)
            score.indexOf(spanner.first.measure): (
              spanner.staff,
              spanner.first.offset,
              spanner.last.measure == spanner.first.measure,
              score.lineEnd(spanner),
            ),
      },
      {
        for (final MapEntry(key: bar, value: lift) in _lifts.entries)
          bar: (bass, Moment.zero, true, Moment(Fraction(lift, 16))),
      },
    );
  });

  test('rings each note let go under the pedal until the pedal lifts, in '
      'both passes, and sounds the others their own length', () {
    const sixteenth = 0.25;
    for (final bar in script.bars) {
      final index = score.indexOf(bar.measure);
      final lift = _lifts[index];
      for (final (staff, hand) in [(treble, _right), (bass, _left)]) {
        final sounded = [
          for (final note in script.notesBetween(bar.start, bar.end))
            if (note.source.staff == staff) note,
        ];
        for (final (i, (onset, length)) in _spans(hand[index]).indexed) {
          // A key is let go after nine tenths of its note.
          final let = onset + length * 0.9;
          final end = lift != null && let < lift ? lift : let;
          expect(
            sounded[i].duration,
            closeTo((end - onset) * sixteenth, 1e-9),
            reason: 'bar $index, pass ${bar.pass}, note $i of $staff',
          );
        }
      }
    }
  });

  test('beams each run of sixteenths whole, as the score does', () {
    List<int> beamed(int staff) => [
      for (var bar = 0; bar < score.measures.length; bar++)
        ...voiceOne(staff, bar).beams.map((group) => group.events.length),
    ];

    expect(beamed(0), [2, 6, 3, 3, 3, 6, 3, 3]);
    expect(beamed(1), [3, 3, 3, 3, 3, 3]);
  });

  test('is marked pianissimo and Poco moto at its first note', () {
    final first = score.measures.first;
    expect(first.tempos.single.text, 'Poco moto');
    expect(first.tempos.single.offset, Moment.zero);
    expect(
      first.tempos.single.showMetronome,
      isFalse,
      reason: 'the composer gave no metronome mark',
    );
    expect(first.staves.first.directions, [
      const DynamicMark(Moment.zero, Dynamic.pp),
    ]);
  });
}
