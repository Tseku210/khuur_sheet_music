import 'package:simple_sheet_music/simple_sheet_music.dart';

/// The tune the page's tests edit and play. Eight bars of 4/4 in C major at
/// 96 beats a minute for one piano on two staves. The right hand has a
/// melody and the left hand chords. Bars 3 and 4 repeat, so the script plays
/// ten bars and those two report a second pass.
Score eightBars() {
  var session = EditSession.start(
    Score.blank(
      parts: const [_piano],
      title: 'Eight bars in C',
      measureCount: 8,
    ),
  );
  final [treble, bass] = [for (final staff in session.score.staves) staff.id];
  session = _enterHand(session, treble, _melody);
  session = _enterHand(session, bass, _chords);

  // Writing the last note of bar 8 puts the cursor in a bar of its own, and
  // the score appends one to hold it.
  final bars = [for (final column in session.score.measures) column.id];
  session = _apply(session, DeleteMeasures(bars.last, bars.last));

  return _apply(
    session,
    Batch([
      SetTempoMarks(
        bars[0],
        Seq([
          const TempoMark(
            offset: Moment.zero,
            tempo: Tempo(96),
            text: 'Andante',
          ),
        ]),
      ),
      SetRepeatStart(bars[2], start: true),
      SetRepeatEnd(bars[3], const RepeatEnd()),
    ], label: 'Tempo and repeat'),
  ).score;
}

const _piano = PartTemplate(
  name: 'Piano',
  instrument: Instrument(key: 'piano', program: 0),
  staves: 2,
  clefs: [Clef.treble, Clef.bass],
);

/// One chord of space-separated pitches, held for a written value.
typedef _Entry = (String pitches, NoteValue value);

const _q = NoteValue.quarter;
const _e = NoteValue.eighth;
const _h = NoteValue.half;
const _w = NoteValue.whole;

/// The right hand, one list per bar.
const List<List<_Entry>> _melody = [
  [('E4', _q), ('G4', _q), ('C5', _e), ('B4', _e), ('C5', _q)],
  [('A4', _q), ('A4', _e), ('B4', _e), ('C5', _q), ('E5', _q)],
  [('D5', _q), ('C5', _e), ('A4', _e), ('F4', _q), ('A4', _q)],
  [('G4', _e), ('A4', _e), ('B4', _e), ('C5', _e), ('D5', _q), ('G4', _q)],
  [('E5', _q), ('D5', _e), ('C5', _e), ('G4', _q), ('E4', _q)],
  [('F4', _e), ('G4', _e), ('A4', _e), ('C5', _e), ('A4', _q), ('F4', _q)],
  [('D5', _q), ('B4', _e), ('G4', _e), ('B4', _q), ('D5', _q)],
  [('E5', _q), ('D5', _q), ('C5', _h)],
];

/// The left hand, one list per bar: C, Am, F, G, C, F, G with a seventh, C.
const List<List<_Entry>> _chords = [
  [('C3 E3 G3', _h), ('C3 E3 G3', _h)],
  [('A2 C3 E3', _h), ('A2 C3 E3', _h)],
  [('F2 A2 C3', _q), ('F2 A2 C3', _q), ('F2 A2 C3', _q), ('F2 A2 C3', _q)],
  [('G2 B2 D3', _q), ('G2 B2 D3', _q), ('G2 B2 D3', _q), ('G2 B2 D3', _q)],
  [('C3 E3 G3', _h), ('C3 E3 G3', _h)],
  [('F2 A2 C3', _h), ('F2 A2 C3', _h)],
  [('G2 B2 D3', _h), ('G2 B2 D3 F3', _h)],
  [('C3 E3 G3', _w)],
];

/// Enters [bars] in voice one of [staff] from the start of the score. The
/// cursor moves on by the length of each chord, so the bars follow each other.
EditSession _enterHand(
  EditSession session,
  StaffId staff,
  List<List<_Entry>> bars,
) {
  final start = ScorePoint(session.score.measures.first.id, Moment.zero);
  var entered = session.placeCursor(
    VoicePoint(staff: staff, voice: VoiceSlot.one, at: start),
  );
  for (final (pitches, value) in bars.expand((bar) => bar)) {
    final [first, ...above] = [
      for (final name in pitches.split(' ')) Pitch.parse(name),
    ];
    entered = _apply(
      entered,
      EnterNote(at: entered.cursor, tone: first, value: value),
    );
    final chord = entered.selection.singleEvent!;
    for (final tone in above) {
      entered = _apply(entered, AddToChord(event: chord, tone: tone));
    }
  }
  return entered;
}

EditSession _apply(EditSession session, Edit edit) =>
    switch (session.run(edit)) {
      Applied(:final session) => session,
      Refused(:final reason) => throw StateError(
        '${edit.label}: ${reason.runtimeType}',
      ),
    };
