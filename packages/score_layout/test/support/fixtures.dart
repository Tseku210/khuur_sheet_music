/// The scores gate 2 measures, built through the score model's public
/// constructors.
library;

import 'package:score_model/score_model.dart';

/// Gate 2's first fixture, 500 bars of four staves.
///
/// A voice, a violin and a piano repeat one bar of 4/4, moved up a step from
/// bar to bar and back down every fifth. Every bar holds beamed eighths and
/// sixteenths, a second voice on the piano's upper staff, a syllable of one
/// verse under every sung note, a dynamic and a slur. A hairpin crosses
/// every fourth barline, so the score has 500 slurs and 125 hairpins.
Score denseScore() => _ensemble(bars: 500);

/// Gate 2's second fixture, the music of [denseScore] for 2,000 bars. That
/// gives 2,000 slurs and 500 hairpins, which is 2,500 spanners.
Score spannerScore() => _ensemble(bars: 2000);

/// The note gate 2 enters. It is a quarter at the start of bar [bar],
/// counted from 1, in voice one of the top staff.
EnterNote noteInBar(Score score, int bar) => EnterNote(
  at: VoicePoint(
    staff: score.staves.first.id,
    voice: VoiceSlot.one,
    at: ScorePoint(score.measures[bar - 1].id, Moment.zero),
  ),
  tone: const Pitch(Step.a, 4),
  value: NoteValue.quarter,
);

/// The score [session] holds after [edit]. Throws when the model refuses
/// the edit.
Score scoreAfter(EditSession session, Edit edit) => switch (session.run(edit)) {
  Applied(:final session) => session.score,
  Refused(:final reason) => throw StateError('refused: $reason'),
};

const _voiceStaff = StaffId(2);
const _violinStaff = StaffId(4);
const _upperStaff = StaffId(6);
const _lowerStaff = StaffId(7);

/// One counter for every id, as an edit session keeps. The parts and their
/// staves hold 1 to 7.
final class _Ids {
  int _next = 8;

  int take() => _next++;
}

const NoteValue _half = NoteValue.half;
const NoteValue _quarter = NoteValue.quarter;
const NoteValue _eighth = NoteValue.eighth;
const NoteValue _sixteenth = NoteValue.sixteenth;

/// One bar of a line, as each chord's value and its heads, lowest first. A
/// head is a step of the diatonic ladder, where C4 is 28.
typedef _Line = List<(NoteValue, List<int>)>;

const _Line _melody = [
  (_quarter, [28]),
  (_eighth, [29]),
  (_eighth, [30]),
  (_quarter, [32]),
  (_eighth, [31]),
  (_eighth, [30]),
];

const _Line _violin = [
  (_sixteenth, [35]),
  (_sixteenth, [36]),
  (_sixteenth, [37]),
  (_sixteenth, [38]),
  (_eighth, [39]),
  (_eighth, [37]),
  (_quarter, [36]),
  (_eighth, [37]),
  (_eighth, [35]),
];

const _Line _upperOne = [
  (_eighth, [32]),
  (_eighth, [33]),
  (_eighth, [34]),
  (_eighth, [35]),
  (_eighth, [34]),
  (_eighth, [33]),
  (_eighth, [32]),
  (_eighth, [30]),
];

const _Line _upperTwo = [
  (_half, [28]),
  (_half, [27]),
];

const _Line _lower = [
  (_quarter, [21, 25]),
  (_quarter, [23, 25]),
  (_quarter, [19, 23]),
  (_quarter, [21, 23]),
];

const _solfege = ['do', 're', 'mi', 'fa', 'sol', 'la', 'ti'];

const List<Dynamic> _dynamics = [Dynamic.p, Dynamic.mf, Dynamic.f, Dynamic.mp];

Score _ensemble({required int bars}) {
  final ids = _Ids();
  final measures = Seq([for (var bar = 0; bar < bars; bar++) _bar(bar, ids)]);
  return Score(
    meta: const ScoreMeta(),
    parts: Seq([
      Part(
        id: const PartId(1),
        name: 'Voice',
        instrument: const Instrument(key: 'voice', program: 52),
        staves: Seq(const [Staff(id: _voiceStaff)]),
      ),
      Part(
        id: const PartId(3),
        name: 'Violin',
        instrument: const Instrument(key: 'violin', program: 40),
        staves: Seq(const [Staff(id: _violinStaff)]),
      ),
      Part(
        id: const PartId(5),
        name: 'Piano',
        instrument: const Instrument(key: 'piano', program: 0),
        staves: Seq(const [Staff(id: _upperStaff), Staff(id: _lowerStaff)]),
      ),
    ]),
    measures: measures,
    spanners: Seq([
      for (var bar = 0; bar < bars; bar++) ...[
        Spanner(
          id: SpannerId(ids.take()),
          kind: const Slur(),
          staff: _violinStaff,
          voice: VoiceSlot.one,
          first: ScorePoint(measures[bar].id, Moment.zero),
          last: ScorePoint(measures[bar].id, Moment(Fraction(3, 16))),
        ),
        if (bar % 4 == 0)
          Spanner(
            id: SpannerId(ids.take()),
            kind: Hairpin(crescendo: bar % 8 == 0),
            staff: _violinStaff,
            first: ScorePoint(measures[bar].id, Moment(Fraction(1, 2))),
            last: ScorePoint(measures[bar + 1].id, Moment.zero),
          ),
      ],
    ]),
  );
}

MeasureColumn _bar(int bar, _Ids ids) {
  final up = bar % 5;
  return MeasureColumn(
    id: MeasureId(ids.take()),
    meter: Meter.fourFour,
    key: KeySignature.cMajor,
    staves: Seq([
      StaffMeasure(
        staff: _voiceStaff,
        clef: Clef.treble,
        voices: Seq([_voice(VoiceSlot.one, _melody, up, ids, sung: true)]),
      ),
      StaffMeasure(
        staff: _violinStaff,
        clef: Clef.treble,
        directions: Seq([
          DynamicMark(Moment.zero, _dynamics[bar % _dynamics.length]),
        ]),
        voices: Seq([_voice(VoiceSlot.one, _violin, up, ids)]),
      ),
      StaffMeasure(
        staff: _upperStaff,
        clef: Clef.treble,
        voices: Seq([
          _voice(VoiceSlot.one, _upperOne, up, ids),
          _voice(VoiceSlot.two, _upperTwo, up, ids),
        ]),
      ),
      StaffMeasure(
        staff: _lowerStaff,
        clef: Clef.bass,
        voices: Seq([_voice(VoiceSlot.one, _lower, up, ids)]),
      ),
    ]),
  );
}

Voice _voice(
  VoiceSlot slot,
  _Line line,
  int up,
  _Ids ids, {
  bool sung = false,
}) => Voice(
  slot: slot,
  items: Seq([
    for (final (value, heads) in line)
      ChordEvent(
        id: EventId(ids.take()),
        value: value,
        notes: Seq([
          for (final head in heads)
            PitchedNote(id: NoteId(ids.take()), pitch: _pitch(head + up)),
        ]),
        lyrics: Seq([
          if (sung) Lyric(verse: 1, text: _solfege[(heads.first + up) % 7]),
        ]),
      ),
  ]),
);

Pitch _pitch(int diatonic) => Pitch(Step.values[diatonic % 7], diatonic ~/ 7);
