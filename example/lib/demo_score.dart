import 'package:simple_sheet_music/simple_sheet_music.dart';

/// The opening of Beethoven's "Für Elise", WoO 59, for one piano on two
/// staves. It is a pickup of an eighth and eight bars of 3/8, at 120 eighths
/// a minute. The last bar is a quarter long and repeats from the pickup, so
/// the script plays every bar twice.
Score buildDemoScore() {
  final blank = Score.blank(
    parts: const [_piano],
    measureCount: _right.length,
    meter: const Meter([3], 8),
  );
  var session = EditSession.start(
    blank.copyWith(
      meta: const ScoreMeta(
        title: 'Für Elise',
        subtitle: 'The opening',
        composer: 'Ludwig van Beethoven',
      ),
    ),
  );
  final bars = [for (final column in session.score.measures) column.id];
  final [treble, bass] = [for (final staff in session.score.staves) staff.id];

  session = _apply(
    session,
    Batch([
      SetBarLength(bars.first, NoteValue.eighth.length),
      SetBarLength(bars.last, NoteValue.quarter.length),
    ], label: 'Pickup'),
  );
  session = _enterHand(session, treble, bars, _right);
  session = _enterHand(session, bass, bars, _left);

  return _apply(
    session,
    Batch([
      SetTempoMarks(
        bars.first,
        Seq([
          const TempoMark(
            offset: Moment.zero,
            tempo: Tempo(120, beat: NoteValue.eighth),
            text: 'Poco moto',
            showMetronome: false,
          ),
        ]),
      ),
      SetDirections(
        staff: treble,
        measure: bars.first,
        directions: Seq([const DynamicMark(Moment.zero, Dynamic.pp)]),
      ),
      SetRepeatEnd(bars.last, const RepeatEnd()),
    ], label: 'Marks and repeat'),
  ).score;
}

// A name would be printed before the first system, as for a part of an
// ensemble, and leave a phone's first system no room for bar 1.
const _piano = PartTemplate(
  name: '',
  instrument: Instrument(key: 'piano', program: 0),
  staves: 2,
  clefs: [Clef.treble, Clef.bass],
);

/// A note of a written value, or a rest where the pitch is null.
typedef _Entry = (String? pitch, NoteValue value);

const _s = NoteValue.sixteenth;
const _e = NoteValue.eighth;
const _q = NoteValue.quarter;

const List<_Entry> _turn = [
  ('E5', _s),
  ('D#5', _s),
  ('E5', _s),
  ('B4', _s),
  ('D5', _s),
  ('C5', _s),
];

/// The right hand, one list per bar, the pickup first.
const List<List<_Entry>> _right = [
  [('E5', _s), ('D#5', _s)],
  _turn,
  [('A4', _e), (null, _s), ('C4', _s), ('E4', _s), ('A4', _s)],
  [('B4', _e), (null, _s), ('E4', _s), ('G#4', _s), ('B4', _s)],
  [('C5', _e), (null, _s), ('E4', _s), ('E5', _s), ('D#5', _s)],
  _turn,
  [('A4', _e), (null, _s), ('C4', _s), ('E4', _s), ('A4', _s)],
  [('B4', _e), (null, _s), ('E4', _s), ('C5', _s), ('B4', _s)],
  [('A4', _q)],
];

const List<_Entry> _aMinor = [('A2', _s), ('E3', _s), ('A3', _s)];
const List<_Entry> _eMajor = [('E2', _s), ('E3', _s), ('G#3', _s)];

/// The left hand, one list per bar. A bar with nothing in it keeps its rest,
/// and so does the end of a bar after its last note.
const List<List<_Entry>> _left = [
  [],
  [],
  _aMinor,
  _eMajor,
  _aMinor,
  [],
  _aMinor,
  _eMajor,
  _aMinor,
];

/// Enters each list of [hand] in voice one of [staff], from the start of its
/// bar. No bar is added after a note that ends the score.
EditSession _enterHand(
  EditSession session,
  StaffId staff,
  List<MeasureId> bars,
  List<List<_Entry>> hand,
) {
  var entered = session;
  for (final (bar, entries) in hand.indexed) {
    entered = entered.placeCursor(
      VoicePoint(
        staff: staff,
        voice: VoiceSlot.one,
        at: ScorePoint(bars[bar], Moment.zero),
      ),
    );
    var afterNote = false;
    for (final (pitch, value) in entries) {
      entered = _apply(
        entered,
        pitch == null
            ? EnterRest(at: entered.cursor, value: value, appendBar: false)
            : EnterNote(
                at: entered.cursor,
                tone: Pitch.parse(pitch),
                value: value,
                // The score beams a run of sixteenths whole. The meter would
                // start a new beam at every eighth.
                beam: afterNote ? BeamMode.join : BeamMode.auto,
                appendBar: false,
              ),
      );
      afterNote = pitch != null;
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
