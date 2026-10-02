/// One-bar scores built through the model's public constructors, for the
/// bar layout tests.
library;

import 'package:score_model/score_model.dart';

const piano = Instrument(key: 'piano', program: 0);

/// A kit with two sounds at one position, one of them with a cross head.
const drumKit = Instrument(
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
);

const snare = Drum('Snare');
const sideStick = Drum('Side stick');
const bassDrum = Drum('Bass drum');

typedef StaffSpec = ({
  Clef clef,
  List<List<VoiceItem>> voices,
  int lines,
  Instrument instrument,
});

StaffSpec staffOf(
  List<VoiceItem> one, {
  List<VoiceItem> two = const [],
  Clef clef = Clef.treble,
  int lines = 5,
  Instrument instrument = piano,
}) => (
  clef: clef,
  voices: [one, if (two.isNotEmpty) two],
  lines: lines,
  instrument: instrument,
);

/// A score with one bar per entry of [bars], each a list of staves in
/// system order. Staff `s` is the only staff of part `s`. Parts take ids
/// from 1000, staves from 2000 and measures from 3000, so event ids below
/// 1000 never collide. A voice shorter than the bar is filled to its end,
/// voice one with hidden rests (ids from 900 up, one bar's worth per
/// staff), the others with a gap.
Score scoreOf(
  List<List<StaffSpec>> bars, {
  Meter meter = Meter.fourFour,
  KeySignature key = KeySignature.cMajor,
}) {
  List<VoiceItem> filled(List<VoiceItem> items, int slot) {
    final used = items.fold(
      Length.zero,
      (used, item) => used + item.span,
    );
    final left = meter.length - used;
    if (!left.isPositive) {
      return items;
    }
    if (slot > 0) {
      return [...items, Gap(left)];
    }
    final fill = meter.spell(Moment.zero + used, left, rest: true);
    return [
      ...items,
      for (final (i, value) in fill.indexed)
        RestEvent(id: EventId(900 + i), value: value, hidden: true),
    ];
  }

  return Score(
    meta: const ScoreMeta(),
    parts: Seq([
      for (final (s, spec) in bars.first.indexed)
        Part(
          id: PartId(1000 + s),
          name: 'Part $s',
          instrument: spec.instrument,
          staves: Seq([Staff(id: StaffId(2000 + s), lines: spec.lines)]),
        ),
    ]),
    measures: Seq([
      for (final (b, bar) in bars.indexed)
        MeasureColumn(
          id: MeasureId(3000 + b),
          meter: meter,
          key: key,
          staves: Seq([
            for (final (s, spec) in bar.indexed)
              StaffMeasure(
                staff: StaffId(2000 + s),
                clef: spec.clef,
                voices: Seq([
                  for (final (v, items) in spec.voices.indexed)
                    Voice(
                      slot: VoiceSlot.values[v],
                      items: Seq(filled(items, v)),
                    ),
                ]),
              ),
          ]),
        ),
    ]),
  );
}

MeasureView viewOf(Score score, [int bar = 0]) =>
    score.measureView(score.measures[bar].id);

/// The view of a one-bar, one-staff score.
MeasureView barOf(
  List<VoiceItem> one, {
  List<VoiceItem> two = const [],
  Clef clef = Clef.treble,
  int lines = 5,
  Instrument instrument = piano,
  Meter meter = Meter.fourFour,
  KeySignature key = KeySignature.cMajor,
}) => viewOf(
  scoreOf(
    [
      [
        staffOf(
          one,
          two: two,
          clef: clef,
          lines: lines,
          instrument: instrument,
        ),
      ],
    ],
    meter: meter,
    key: key,
  ),
);

/// A chord of space-separated [pitches]. Note `i` has id `id * 10 + i`.
ChordEvent chordOf(
  int id,
  String pitches, {
  NoteValue value = NoteValue.quarter,
  StemDirection stem = StemDirection.auto,
  BeamMode beam = BeamMode.auto,
  List<GraceChord> graces = const [],
  AccidentalRequest accidental = AccidentalRequest.auto,
  int tremolo = 0,
}) {
  final names = pitches.split(' ');
  return ChordEvent(
    id: EventId(id),
    value: value,
    stem: stem,
    beam: beam,
    tremolo: tremolo,
    graces: Seq(graces),
    notes: Seq([
      for (final (i, name) in names.indexed)
        PitchedNote(
          id: NoteId(id * 10 + i),
          pitch: Pitch.parse(name),
          accidental: accidental,
        ),
    ]),
  );
}

GraceChord graceOf(
  int id,
  String pitches, {
  GraceKind kind = GraceKind.acciaccatura,
  NoteValue value = NoteValue.eighth,
}) => GraceChord(
  id: EventId(id),
  kind: kind,
  value: value,
  notes: Seq([
    for (final (i, name) in pitches.split(' ').indexed)
      PitchedNote(id: NoteId(id * 10 + i), pitch: Pitch.parse(name)),
  ]),
);

RestEvent restOf(int id, NoteValue value, {bool hidden = false}) =>
    RestEvent(id: EventId(id), value: value, hidden: hidden);

/// A chord of [drums]. Drum `i` has id `id * 10 + i`.
ChordEvent hitOf(
  int id,
  List<Drum> drums, {
  NoteValue value = NoteValue.quarter,
}) => ChordEvent(
  id: EventId(id),
  value: value,
  notes: Seq([
    for (final (i, drum) in drums.indexed)
      DrumNote(id: NoteId(id * 10 + i), drum: drum),
  ]),
);

Moment at(int numerator, int denominator) =>
    Moment(Fraction(numerator, denominator));

const NoteValue eighth = NoteValue.eighth;
const NoteValue sixteenth = NoteValue.sixteenth;
const NoteValue half = NoteValue.half;
const NoteValue whole = NoteValue.whole;
const NoteValue dottedHalf = NoteValue(DurationBase.half, dots: 1);
