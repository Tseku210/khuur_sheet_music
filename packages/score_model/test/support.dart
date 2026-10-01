import 'package:score_model/score_model.dart';

/// One token per item: `F4/quarter`, `F4/quarter~` (tied), `rest/half`,
/// `measure-rest`, `gap 1/4`, and `3:2[...]` for a tuplet's members.
List<String> describe(Iterable<VoiceItem> items) => [
  for (final item in items) _token(item),
];

String _token(VoiceItem item) => switch (item) {
  ChordEvent(:final notes, :final value) =>
    '${notes.map((n) => n.tone).join('+')}/$value'
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

/// A two-string fiddle tuned F3 and B♭3.
const fiddle = Instrument(
  key: 'morin-khuur',
  program: 110,
  strings: [Pitch(Step.f, 3), Pitch(Step.b, 3, Alter.flat)],
  lowest: Pitch(Step.f, 3),
  highest: Pitch(Step.b, 5, Alter.flat),
);

const morinKhuur = PartTemplate(name: 'Морин хуур', instrument: fiddle);

/// A one-staff score whose single bar holds [items] in voice one. Ids in
/// [items] must stay below 100; the scaffolding uses 100 and up.
Score scoreWith(List<VoiceItem> items) => Score(
  meta: const ScoreMeta(),
  parts: Seq([
    Part(
      id: const PartId(100),
      name: 'Морин хуур',
      instrument: fiddle,
      staves: Seq([const Staff(id: StaffId(101))]),
    ),
  ]),
  measures: Seq([
    MeasureColumn(
      id: const MeasureId(102),
      meter: Meter.fourFour,
      key: KeySignature.cMajor,
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
  Tone? tone,
  NoteValue value = NoteValue.quarter,
  Overfill overfill = Overfill.splitAndTie,
}) => session.run(
  EnterNote(at: at, tone: tone ?? f4, value: value, overfill: overfill),
);

EditSession enterAt(
  EditSession session,
  int barIndex,
  Moment offset, {
  Tone? tone,
  NoteValue value = NoteValue.quarter,
  VoiceSlot voice = VoiceSlot.one,
}) => applied(
  enter(
    session,
    point(session.score, barIndex, offset, voice: voice),
    tone: tone,
    value: value,
  ),
);

ChordEvent chord(int id, Pitch pitch, NoteValue value) => ChordEvent(
  id: EventId(id),
  value: value,
  notes: Seq([PitchedNote(id: NoteId(id + 50), pitch: pitch)]),
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
    bank: 128,
    clef: Clef.percussion,
    drums: [
      DrumSound(name: 'Snare', position: Pitch(Step.c, 5), midiKey: 38),
      DrumSound(
        name: 'Side stick',
        position: Pitch(Step.c, 5),
        midiKey: 37,
        head: NoteHead.cross,
      ),
      DrumSound(name: 'Bass drum', position: Pitch(Step.f, 4), midiKey: 36),
    ],
  ),
);

const snare = Drum('Snare');
const sideStick = Drum('Side stick');
const bassDrum = Drum('Bass drum');

/// A chord of [drums], which the caller lists in name order.
ChordEvent hit(
  int id,
  List<Drum> drums, {
  NoteValue value = NoteValue.quarter,
  bool tie = false,
  List<GraceChord> graces = const [],
}) => ChordEvent(
  id: EventId(id),
  value: value,
  graces: Seq(graces),
  notes: Seq([
    for (final (i, drum) in drums.indexed)
      DrumNote(id: NoteId(id * 10 + i), drum: drum, tie: tie),
  ]),
);

MeasureId idOf(EditSession session, int bar) => session.score.measures[bar].id;

List<MeasureId> barIds(Score score) => [for (final c in score.measures) c.id];

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
Score hidePart(Score score, int index) => applied(
  EditSession.start(
    score,
  ).run(SetPartHidden(score.parts[index].id, hidden: true)),
).score;

Score blankScore({
  List<PartTemplate> parts = const [morinKhuur],
  int bars = 2,
  Meter meter = Meter.fourFour,
  KeySignature key = KeySignature.cMajor,
}) => Score.blank(parts: parts, measureCount: bars, meter: meter, key: key);

Score withSlur(
  Score score,
  ScorePoint first,
  ScorePoint last, {
  int staff = 0,
  VoiceSlot? voice,
}) => score.copyWith(
  spanners: Seq([
    ...score.spanners,
    Spanner(
      id: SpannerId(900 + score.spanners.length),
      kind: const Slur(),
      staff: score.staves[staff].id,
      voice: voice,
      first: first,
      last: last,
    ),
  ]),
);

Score fill(
  Score score,
  int bar,
  List<VoiceItem> items, {
  int staff = 0,
  VoiceSlot slot = VoiceSlot.one,
}) => changeBar(score, bar, (column) {
  final measure = column.staves[staff];
  return column.withStaff(
    measure.withVoice(Voice(slot: slot, items: Seq(items))),
  );
});

/// A chord of space-separated [pitches]. Note `i` has id `id * 10 + i`.
ChordEvent chordOf(
  int id,
  String pitches, {
  NoteValue value = NoteValue.quarter,
  bool tie = false,
  AccidentalRequest accidental = AccidentalRequest.auto,
  BeamMode beam = BeamMode.auto,
  List<GraceChord> graces = const [],
}) {
  final names = pitches.split(' ');
  return ChordEvent(
    id: EventId(id),
    value: value,
    beam: beam,
    graces: Seq(graces),
    notes: Seq([
      for (var i = 0; i < names.length; i++)
        PitchedNote(
          id: NoteId(id * 10 + i),
          pitch: Pitch.parse(names[i]),
          tie: tie,
          accidental: accidental,
        ),
    ]),
  );
}

/// A session over one bar per entry of [bars], each holding its items in
/// voice one of a morin khuur staff.
EditSession sessionWith(List<List<VoiceItem>> bars) {
  var score = blankScore(bars: bars.length);
  for (final (i, items) in bars.indexed) {
    score = fill(score, i, items);
  }
  return EditSession.start(score);
}

EventRef eventRef(EditSession session, int id) =>
    session.score.locate(EventId(id))!;

Event eventOf(EditSession session, int id) =>
    session.score.lookup(eventRef(session, id))!.event;

ChordEvent chordIn(EditSession session, int id) =>
    eventOf(session, id) as ChordEvent;

Map<String, bool> tiesOf(EditSession session, int id) => {
  for (final note in chordIn(session, id).notes) '${note.tone}': note.tie,
};

EditRefusal refusal(EditOutcome outcome) => switch (outcome) {
  Refused(:final reason) => reason,
  Applied() => throw StateError('applied'),
};

/// Whether [edit] applies to [session] and leaves its score as it was.
bool changesNothing(EditSession session, Edit edit) =>
    identical(applied(session.run(edit)).score, session.score);

/// A staff direction as `offset kind`, for comparing.
String mark(StaffDirection direction) =>
    '${direction.offset.wholeNotes} ${switch (direction) {
      DynamicMark(:final level) => level.name,
      TextMark(:final text, :final above) => '$text${above ? '' : ' below'}',
      ChordSymbol(:final root, :final quality, :final bass) => '${root.step.name}$quality${bass == null ? '' : '/${bass.step.name}'}',
    }}';
