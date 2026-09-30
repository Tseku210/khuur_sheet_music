import 'package:score_model/score_model.dart';

/// One token per item: `F4/quarter`, `F4/quarter~` (tied), `rest/half`,
/// `measure-rest`, `gap 1/4`, and `3:2[...]` for a tuplet's members.
List<String> describe(Iterable<VoiceItem> items) => [
  for (final item in items) _token(item),
];

String _token(VoiceItem item) => switch (item) {
  ChordEvent(:final notes, :final value) =>
    '${notes.map((n) => n.pitch).join('+')}/$value'
        '${notes.any((n) => n.tie) ? '~' : ''}',
  RestEvent(:final value) => 'rest/$value',
  MeasureRest() => 'measure-rest',
  Gap(:final span) => 'gap ${span.wholeNotes}',
  Tuplet(:final ratio, :final members) =>
    '$ratio[${describe(members).join(', ')}]',
};

Voice voiceOf(Score score, int bar, {VoiceSlot slot = VoiceSlot.one}) =>
    score.measures[bar].staves.first.voice(slot)!;

List<String> bar(Score score, int bar, {VoiceSlot slot = VoiceSlot.one}) =>
    describe(voiceOf(score, bar, slot: slot).items);

Moment at(int numerator, int denominator) =>
    Moment(Fraction(numerator, denominator));

VoicePoint point(
  Score score,
  int bar,
  Moment offset, {
  VoiceSlot voice = VoiceSlot.one,
}) => VoicePoint(
  staff: score.staves.first.id,
  voice: voice,
  at: ScorePoint(score.measures[bar].id, offset),
);

EditSession applied(EditOutcome outcome) => switch (outcome) {
  Applied(:final session) => session,
  Refused(:final reason) => throw StateError('refused: $reason'),
};

final f4 = Pitch.parse('F4');
final g4 = Pitch.parse('G4');

const morinKhuur = PartTemplate(
  name: 'Морин хуур',
  instrument: Instrument.morinKhuur,
);

/// A one-staff score whose single bar holds [items] in voice one. Ids in
/// [items] must stay below 100; the scaffolding uses 100 and up.
Score scoreWith(
  List<VoiceItem> items, {
  Meter meter = Meter.fourFour,
  KeySignature key = KeySignature.cMajor,
}) => Score(
  meta: const ScoreMeta(),
  parts: Seq([
    Part(
      id: const PartId(100),
      name: 'Морин хуур',
      instrument: Instrument.morinKhuur,
      staves: Seq([const Staff(id: StaffId(101))]),
    ),
  ]),
  measures: Seq([
    MeasureColumn(
      id: const MeasureId(102),
      meter: meter,
      key: key,
      staves: Seq([
        StaffMeasure(
          staff: const StaffId(101),
          clef: Clef.treble,
          voices: Seq([Voice(slot: VoiceSlot.one, items: Seq(items))]),
        ),
      ]),
    ),
  ]),
);

RestEvent rest(int id, NoteValue value) =>
    RestEvent(id: EventId(id), value: value);

Tuplet tripletOfEighths(int id, List<Content> members) => Tuplet(
  id: TupletId(id),
  ratio: TupletRatio.triplet,
  unit: NoteValue.eighth,
  members: Seq(members),
);

Length len(int numerator, int denominator) =>
    Length(Fraction(numerator, denominator));

EditSession blank({int bars = 2, Meter meter = Meter.fourFour}) =>
    EditSession.start(
      Score.blank(parts: const [morinKhuur], measureCount: bars, meter: meter),
    );

EditOutcome enter(
  EditSession session,
  VoicePoint at, {
  Pitch? pitch,
  NoteValue value = NoteValue.quarter,
  Overfill overfill = Overfill.splitAndTie,
}) => session.run(
  EnterNote(at: at, pitch: pitch ?? f4, value: value, overfill: overfill),
);

EditSession enterAt(
  EditSession session,
  int barIndex,
  Moment offset, {
  Pitch? pitch,
  NoteValue value = NoteValue.quarter,
  VoiceSlot voice = VoiceSlot.one,
}) => applied(
  enter(
    session,
    point(session.score, barIndex, offset, voice: voice),
    pitch: pitch,
    value: value,
  ),
);

ChordEvent chord(int id, Pitch pitch, NoteValue value, {bool tie = false}) =>
    ChordEvent(
      id: EventId(id),
      value: value,
      notes: Seq([Note(id: NoteId(id + 50), pitch: pitch, tie: tie)]),
    );

Event firstEvent(Score score, int barIndex) =>
    voiceOf(score, barIndex).items.first as Event;

const piano = PartTemplate(
  name: 'Piano',
  instrument: Instrument(key: 'piano', program: 0),
  staves: 2,
  clefs: [Clef.treble, Clef.bass],
);

const clarinet = PartTemplate(
  name: 'Clarinet in B♭',
  instrument: Instrument(
    key: 'clarinet-b-flat',
    program: 71,
    transposition: Interval(-1, -2),
  ),
);

const drums = PartTemplate(
  name: 'Drums',
  instrument: Instrument(
    key: 'drums',
    program: 0,
    clef: Clef.percussion,
    drums: [
      DrumSound(name: 'Snare', position: Pitch(Step.c, 5), midiKey: 38),
    ],
  ),
);

ScorePoint pointAt(Score score, int bar, Moment offset) =>
    ScorePoint(score.measures[bar].id, offset);

Score changeBar(
  Score score,
  int bar,
  MeasureColumn Function(MeasureColumn column) change,
) => score.copyWith(
  measures: score.measures.replaceAt(bar, change(score.measures[bar])),
);

Score withOctaveLine(
  Score score,
  OctaveShift shift,
  ScorePoint first,
  ScorePoint last,
) => score.copyWith(
  spanners: Seq([
    Spanner(
      id: const SpannerId(900),
      kind: OctaveLine(shift),
      staff: score.staves.first.id,
      first: first,
      last: last,
    ),
  ]),
);

/// [score] with part [index] hidden.
Score hidePart(Score score, int index) {
  final part = score.parts[index];
  return score.copyWith(
    parts: score.parts.replaceAt(
      index,
      Part(
        id: part.id,
        name: part.name,
        instrument: part.instrument,
        staves: part.staves,
        hidden: true,
      ),
    ),
  );
}

Score blankScore({
  List<PartTemplate> parts = const [morinKhuur],
  int bars = 2,
  Meter meter = Meter.fourFour,
  KeySignature key = KeySignature.cMajor,
}) => Score.blank(parts: parts, measureCount: bars, meter: meter, key: key);
