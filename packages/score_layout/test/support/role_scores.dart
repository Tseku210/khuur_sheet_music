import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';

import '../../../score_model/test/support.dart';

const multiRests = EngravingStyle(multiMeasureRests: true);
const roman = EngravingStyle(stringNumbers: StringNumbers.roman);

/// The scores of this file with the style each is laid out in. Between
/// them they draw every role.
final List<(Score, EngravingStyle)> roleSheets = [
  (chordScore(), EngravingStyle.standard),
  (restScore(), EngravingStyle.standard),
  (restScore(), multiRests),
  (markScore(), EngravingStyle.standard),
  (markScore(), roman),
  (lineScore(), EngravingStyle.standard),
  (lyricScore(), EngravingStyle.standard),
  (frameScore(), EngravingStyle.standard),
];

/// An unbeamed eighth, a dotted note above the fiddle's range with a
/// cautionary sharp, a beamed pair, a beam with a hook, a tremolo, a dotted
/// rest and an acciaccatura tied to its note.
Score chordScore() {
  final score = fill(blankScore(), 0, [
    chordOf(1, 'A4', value: NoteValue.eighth, beam: BeamMode.none),
    chordOf(
      2,
      'C#6',
      value: NoteValue.quarter.dotted,
      accidental: AccidentalRequest.cautionary,
    ),
    chordOf(3, 'G4', value: NoteValue.eighth),
    chordOf(4, 'A4', value: NoteValue.eighth),
    rest(5, NoteValue.quarter),
  ]);
  return fill(score, 1, [
    chordOf(6, 'G4', value: NoteValue.eighth.dotted),
    chordOf(7, 'A4', value: NoteValue.sixteenth),
    chordOf(8, 'B4').copyWith(tremolo: 2),
    rest(9, NoteValue.quarter.dotted),
    chordOf(
      10,
      'A4',
      value: NoteValue.eighth,
      graces: [
        GraceChord(
          id: const EventId(11),
          kind: GraceKind.acciaccatura,
          value: NoteValue.eighth,
          notes: Seq([
            PitchedNote(
              id: const NoteId(110),
              pitch: Pitch.parse('A4'),
              tie: true,
            ),
          ]),
        ),
      ],
    ),
  ]);
}

/// A bar of notes, then three bars of rest.
Score restScore() => fill(blankScore(bars: 4), 0, [
  for (var beat = 0; beat < 4; beat++) chordOf(1 + beat, 'A4'),
]);

/// Every kind of mark a chord or a bar carries, and a bracketed triplet.
Score markScore() {
  var score = fill(blankScore(), 0, [
    chordOf(1, 'A4').copyWith(
      articulations: {
        Articulation.staccato,
        Articulation.accent,
        Articulation.harmonic,
      },
    ),
    chordOf(2, 'A4').copyWith(articulations: {Articulation.fermata}),
    chordOf(
      3,
      'A4',
    ).copyWith(ornament: () => Ornament.mordent, bowing: () => Bowing.down),
    ChordEvent(
      id: const EventId(4),
      value: NoteValue.quarter,
      notes: Seq([
        PitchedNote(
          id: const NoteId(40),
          pitch: Pitch.parse('A4'),
          fingering: 2,
          string: 0,
        ),
      ]),
    ),
  ]);
  score = fill(score, 1, [
    Tuplet(
      id: const TupletId(5),
      ratio: TupletRatio.triplet,
      unit: NoteValue.eighth,
      bracket: TupletBracket.shown,
      members: Seq([
        for (var i = 0; i < 3; i++)
          chordOf(6 + i, 'A4', value: NoteValue.eighth),
      ]),
    ),
    rest(9, NoteValue.quarter),
    rest(10, NoteValue.half),
  ]);
  return changeBar(
    score,
    0,
    (column) => column
        .copyWith(
          rehearsal: () => 'A',
          navigation: Seq(const [Segno(), Fine()]),
          tempos: Seq(const [
            TempoMark(offset: Moment.zero, tempo: Tempo(120), text: 'Allegro'),
          ]),
        )
        .withStaff(
          column.staves.first.copyWith(
            directions: Seq([
              const DynamicMark(Moment.zero, Dynamic.f),
              TextMark(at(1, 4), 'dolce'),
              ChordSymbol(
                at(1, 2),
                root: const PitchName(Step.b, Alter.flat),
                quality: 'm7',
              ),
            ]),
          ),
        ),
  );
}

const slur = 900;
const hairpin = 901;
const octaveLine = 902;
const glissando = 903;
const pedal = 904;
const trillLine = 905;
const tempoLine = 906;

/// A tie, one spanner of each kind, and a volta over the third bar.
Score lineScore() {
  var score = blankScore(bars: 4);
  for (var bar = 0; bar < 4; bar++) {
    score = fill(score, bar, [
      chordOf(bar * 10 + 1, 'A4', tie: bar == 3),
      chordOf(bar * 10 + 2, bar == 3 ? 'A4' : 'B4'),
      chordOf(bar * 10 + 3, 'C5'),
      chordOf(bar * 10 + 4, 'D5'),
    ]);
  }
  ScorePoint beat(int bar, int beat) => pointAt(score, bar, at(beat, 4));
  for (final (kind, bar, from) in <(SpannerKind, int, int)>[
    (const Slur(), 0, 0),
    (const Hairpin(crescendo: true), 0, 2),
    (const OctaveLine(OctaveShift.up8), 1, 0),
    (const Glissando(), 1, 2),
    (const PedalLine(), 2, 0),
    (const TrillLine(), 2, 2),
    (TempoLine.ritardando, 3, 2),
  ]) {
    score = withSpanner(
      score,
      kind,
      beat(bar, from),
      beat(bar, from + 1),
      voice: kind.joinsNotes ? VoiceSlot.one : null,
    );
  }
  return changeBar(
    score,
    2,
    (column) => column.copyWith(volta: () => const Volta([1])),
  );
}

/// A word of two syllables, then a syllable held over the next note.
Score lyricScore() => fill(blankScore(), 0, [
  chordOf(1, 'A4').copyWith(
    lyrics: Seq(const [
      Lyric(verse: 1, text: 'Hal', syllabic: Syllabic.begin),
    ]),
  ),
  chordOf(2, 'A4').copyWith(
    lyrics: Seq(const [Lyric(verse: 1, text: 'le', syllabic: Syllabic.end)]),
  ),
  chordOf(
    3,
    'A4',
  ).copyWith(lyrics: Seq(const [Lyric(verse: 1, text: 'ah', extend: true)])),
  chordOf(4, 'B4'),
]);

/// A clarinet, a piano and drums under a full header, in two sharps. The
/// second bar is repeated and changes clef halfway. The third changes key
/// and time and ends the piece.
Score frameScore() {
  var score = blankScore(
    parts: const [clarinet, piano, drums],
    bars: 3,
    key: const KeySignature(2),
  );
  score = score.copyWith(
    meta: const ScoreMeta(
      title: 'A title',
      subtitle: 'A subtitle',
      composer: 'A composer',
      lyricist: 'A lyricist',
    ),
  );
  score = fill(score, 0, [
    for (var beat = 0; beat < 4; beat++) hit(1 + beat, const [snare]),
  ], staff: 3);
  score = changeBar(
    score,
    1,
    (column) => column
        .copyWith(repeatStart: true, repeatEnd: () => const RepeatEnd())
        .withStaff(
          column.staves[2].copyWith(
            clefChanges: Seq([ClefChange(at(1, 2), Clef.treble)]),
          ),
        ),
  );
  return changeBar(
    score,
    2,
    (column) => column.copyWith(
      key: const KeySignature(-1),
      meter: Meter.common,
      barline: Barline.finalBar,
    ),
  );
}
