/// Scores that exercise every stored field, shared by the save format
/// tests.
library;

import 'package:score_model/score_model.dart';

import 'support.dart';

Pitch p(String name) => Pitch.parse(name);

PitchedNote head(int id, Pitch pitch) =>
    PitchedNote(id: NoteId(id), pitch: pitch);

ChordEvent single(int id, Pitch pitch, NoteValue value) => ChordEvent(
  id: EventId(id),
  value: value,
  notes: Seq([head(id + 1, pitch)]),
);

StaffMeasure lane(
  int staff,
  Clef clef,
  List<VoiceItem> one, {
  List<VoiceItem> two = const [],
  List<ClefChange> clefChanges = const [],
  List<StaffDirection> directions = const [],
}) => StaffMeasure(
  staff: StaffId(staff),
  clef: clef,
  clefChanges: Seq(clefChanges),
  directions: Seq(directions),
  voices: Seq([
    Voice(slot: VoiceSlot.one, items: Seq(one)),
    if (two.isNotEmpty) Voice(slot: VoiceSlot.two, items: Seq(two)),
  ]),
);

ScorePoint where(int measure, int numerator, int denominator) =>
    ScorePoint(MeasureId(measure), at(numerator, denominator));

/// A score that holds every stored field away from its default at least
/// once: three parts (violin, a hidden clarinet, a one-line drum kit), a
/// pickup, meter, key and clef changes, nested tuplets, every accidental,
/// and one spanner of each kind.
Score showcase() => Score(
  meta: const ScoreMeta(
    title: 'Showcase',
    subtitle: 'for testing',
    composer: 'Anon.',
    lyricist: 'Anon.',
    copyright: 'CC0',
  ),
  parts: Seq([
    Part(
      id: const PartId(1),
      name: 'Violin',
      shortName: 'Vln.',
      instrument: Instrument(
        key: 'violin',
        program: 40,
        strings: [p('G3'), p('D4'), p('A4'), p('E5')],
        lowest: p('G3'),
        highest: p('A7'),
      ),
      staves: Seq([const Staff(id: StaffId(2))]),
    ),
    Part(
      id: const PartId(3),
      name: 'Clarinet in B♭',
      hidden: true,
      instrument: clarinet.instrument,
      staves: Seq([const Staff(id: StaffId(4))]),
    ),
    Part(
      id: const PartId(5),
      name: 'Drums',
      instrument: drums.instrument,
      staves: Seq([const Staff(id: StaffId(6), lines: 1)]),
    ),
  ]),
  measures: Seq([
    MeasureColumn(
      id: const MeasureId(10),
      meter: Meter.common,
      key: const KeySignature(2, KeyMode.major),
      irregularLength: len(1, 4),
      repeatStart: true,
      rehearsal: 'A',
      navigation: Seq(const [Segno()]),
      tempos: Seq([
        const TempoMark(
          offset: Moment.zero,
          tempo: Tempo(120),
          text: 'Allegro',
        ),
      ]),
      staves: Seq([
        lane(
          2,
          Clef.treble,
          [
            ChordEvent(
              id: const EventId(11),
              value: NoteValue.quarter,
              notes: Seq([
                PitchedNote(
                  id: const NoteId(12),
                  pitch: p('F#4'),
                  fingering: 1,
                  string: 1,
                ),
                PitchedNote(
                  id: const NoteId(13),
                  pitch: p('A4'),
                  tie: true,
                  accidental: AccidentalRequest.cautionary,
                  head: NoteHead.diamond,
                ),
              ]),
              articulations: const {Articulation.accent, Articulation.staccato},
              ornament: Ornament.trill,
              bowing: Bowing.down,
              graces: Seq([
                GraceChord(
                  id: const EventId(14),
                  kind: GraceKind.appoggiatura,
                  value: NoteValue.eighth,
                  notes: Seq([head(15, p('E4'))]),
                ),
              ]),
              stem: StemDirection.up,
              beam: BeamMode.begin,
              tremolo: 2,
              lyrics: Seq(const [
                Lyric(
                  verse: 1,
                  text: 'la',
                  syllabic: Syllabic.begin,
                  extend: true,
                ),
                Lyric(verse: 2, text: 'Тай'),
              ]),
            ),
          ],
          two: [
            Gap(len(1, 8)),
            const RestEvent(
              id: EventId(16),
              value: NoteValue.eighth,
              hidden: true,
            ),
          ],
          directions: [
            const DynamicMark(Moment.zero, Dynamic.mf),
            const TextMark(Moment.zero, 'dolce', above: false),
            ChordSymbol(
              at(1, 8),
              root: const PitchName(Step.d),
              quality: 'maj7',
              bass: const PitchName(Step.e, Alter.doubleFlat),
            ),
          ],
        ),
        lane(4, Clef.treble, [
          MeasureRest(
            id: const EventId(17),
            span: len(1, 4),
            articulations: const {Articulation.fermata},
          ),
        ]),
        lane(6, Clef.percussion, [
          hit(
            18,
            [bassDrum, snare],
            graces: [
              GraceChord(
                id: const EventId(21),
                kind: GraceKind.acciaccatura,
                value: NoteValue.sixteenth,
                notes: Seq([const DrumNote(id: NoteId(22), drum: snare)]),
              ),
            ],
          ),
        ]),
      ]),
    ),
    MeasureColumn(
      id: const MeasureId(30),
      meter: Meter.common,
      key: const KeySignature(2, KeyMode.major),
      barline: Barline.doubleBar,
      repeatEnd: const RepeatEnd(times: 3),
      volta: const Volta([1]),
      navigation: Seq(const [
        ToCoda(),
        Jump(JumpTarget.segno, then: JumpThen.toCoda, text: 'D.S. al Coda'),
      ]),
      breakBefore: LayoutBreak.system,
      keyDisplay: SignatureDisplay.noCourtesy,
      meterDisplay: SignatureDisplay.restated,
      staves: Seq([
        lane(
          2,
          Clef.treble,
          [
            Tuplet(
              id: const TupletId(31),
              ratio: TupletRatio.triplet,
              unit: NoteValue.eighth,
              bracket: TupletBracket.shown,
              members: Seq([
                single(32, p('A4'), NoteValue.eighth),
                const RestEvent(
                  id: EventId(34),
                  value: NoteValue.eighth,
                  articulations: {Articulation.fermata},
                ),
                Tuplet(
                  id: const TupletId(35),
                  ratio: TupletRatio.triplet,
                  unit: NoteValue.sixteenth,
                  members: Seq([
                    single(36, p('Bb4'), NoteValue.sixteenth),
                    single(38, p('C+5'), NoteValue.sixteenth),
                    rest(40, NoteValue.sixteenth),
                  ]),
                ),
              ]),
            ),
            ChordEvent(
              id: const EventId(41),
              value: NoteValue.half.dotted,
              notes: Seq([
                head(42, p('Bd4')),
                head(43, const Pitch(Step.c, 5, Alter.threeQuarterSharp)),
              ]),
            ),
          ],
          two: [
            Gap(len(1, 2)),
            ChordEvent(
              id: const EventId(45),
              value: NoteValue.half,
              notes: Seq([head(46, p('G4'))]),
              stem: StemDirection.down,
              beam: BeamMode.none,
            ),
          ],
          clefChanges: [ClefChange(at(1, 2), Clef.alto)],
          directions: [const TextMark(Moment.zero, 'pizz.')],
        ),
        lane(4, Clef.treble, [
          const MeasureRest(id: EventId(47), span: Length.whole),
        ]),
        lane(6, Clef.percussion, [
          hit(48, [sideStick], value: NoteValue.half),
          rest(50, NoteValue.half),
        ]),
      ]),
    ),
    MeasureColumn(
      id: const MeasureId(60),
      meter: Meter.sixEight,
      key: const KeySignature(-3, KeyMode.minor),
      volta: const Volta([2, 3], open: true),
      tempos: Seq([
        TempoMark(
          offset: Moment.zero,
          tempo: Tempo(60, beat: NoteValue.quarter.dotted),
          showMetronome: false,
        ),
        TempoMark(
          offset: at(3, 8),
          tempo: Tempo(66.5, beat: NoteValue.quarter.dotted),
        ),
      ]),
      staves: Seq([
        lane(
          2,
          Clef.alto,
          [MeasureRest(id: const EventId(61), span: len(3, 4))],
          directions: [const DynamicMark(Moment.zero, Dynamic.p)],
        ),
        lane(4, Clef.treble, [
          MeasureRest(id: const EventId(62), span: len(3, 4)),
        ]),
        lane(6, Clef.percussion, [
          hit(63, [bassDrum], value: NoteValue.quarter.dotted),
          hit(65, [snare], value: NoteValue.quarter.dotted),
        ]),
      ]),
    ),
    MeasureColumn(
      id: const MeasureId(70),
      meter: const Meter([3, 2, 2], 8),
      key: const KeySignature(-3, KeyMode.minor),
      barline: Barline.finalBar,
      navigation: Seq(const [Coda(), Fine()]),
      breakBefore: LayoutBreak.page,
      keyDisplay: SignatureDisplay.restated,
      staves: Seq([
        lane(2, Clef.treble, [
          ChordEvent(
            id: const EventId(71),
            value: NoteValue.half.dotted,
            notes: Seq([
              head(72, p('Fx4')),
              head(73, const Pitch(Step.a, 4, Alter.threeQuarterFlat)),
            ]),
          ),
          rest(74, NoteValue.eighth),
        ]),
        lane(4, Clef.treble, [
          MeasureRest(id: const EventId(75), span: len(7, 8)),
        ]),
        lane(6, Clef.percussion, [
          MeasureRest(id: const EventId(76), span: len(7, 8)),
        ]),
      ]),
    ),
  ]),
  spanners: Seq([
    Spanner(
      id: const SpannerId(80),
      kind: const Slur(dashed: true),
      staff: const StaffId(2),
      voice: VoiceSlot.one,
      first: where(30, 0, 1),
      last: where(30, 1, 4),
    ),
    Spanner(
      id: const SpannerId(81),
      kind: const Hairpin(crescendo: true),
      staff: const StaffId(2),
      first: where(10, 0, 1),
      last: where(30, 1, 2),
    ),
    Spanner(
      id: const SpannerId(82),
      kind: const Hairpin(crescendo: false),
      staff: const StaffId(2),
      first: where(30, 1, 2),
      last: where(30, 1, 2),
    ),
    Spanner(
      id: const SpannerId(83),
      kind: const OctaveLine(OctaveShift.up8),
      staff: const StaffId(2),
      first: where(60, 0, 1),
      last: where(70, 0, 1),
    ),
    Spanner(
      id: const SpannerId(84),
      kind: const TrillLine(),
      staff: const StaffId(2),
      first: where(30, 1, 4),
      last: where(30, 1, 4),
    ),
    Spanner(
      id: const SpannerId(85),
      kind: const TempoLine(text: 'poco rit.', factor: 0.9),
      staff: const StaffId(2),
      first: where(60, 0, 1),
      last: where(70, 3, 4),
    ),
    Spanner(
      id: const SpannerId(86),
      kind: const PedalLine(),
      staff: const StaffId(2),
      first: where(10, 0, 1),
      last: where(30, 3, 4),
    ),
    Spanner(
      id: const SpannerId(87),
      kind: const Glissando(),
      staff: const StaffId(2),
      voice: VoiceSlot.two,
      first: where(30, 1, 2),
      last: where(70, 0, 1),
    ),
    Spanner(
      id: const SpannerId(88),
      kind: const Slur(),
      staff: const StaffId(6),
      voice: VoiceSlot.one,
      first: where(60, 0, 1),
      last: where(60, 3, 8),
    ),
  ]),
);

/// A score with every optional value at its default, including a jump's
/// and a chord symbol's.
Score plain() => Score(
  meta: const ScoreMeta(),
  parts: Seq([
    Part(
      id: const PartId(1),
      name: 'Flute',
      instrument: const Instrument(key: 'flute', program: 73),
      staves: Seq([const Staff(id: StaffId(2))]),
    ),
  ]),
  measures: Seq([
    MeasureColumn(
      id: const MeasureId(3),
      meter: Meter.fourFour,
      key: const KeySignature(0),
      staves: Seq([
        lane(
          2,
          Clef.treble,
          [const MeasureRest(id: EventId(4), span: Length.whole)],
          directions: [
            const ChordSymbol(Moment.zero, root: PitchName(Step.c)),
          ],
        ),
      ]),
    ),
    MeasureColumn(
      id: const MeasureId(5),
      meter: Meter.fourFour,
      key: const KeySignature(0),
      navigation: Seq(const [Jump(JumpTarget.start)]),
      staves: Seq([
        lane(2, Clef.treble, [
          const MeasureRest(id: EventId(6), span: Length.whole),
        ]),
      ]),
    ),
  ]),
);
