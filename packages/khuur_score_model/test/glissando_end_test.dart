import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

Score run(Score score, Edit edit) =>
    applied(EditSession.start(score).run(edit)).score;

Score added(
  Score score,
  Moment first,
  Moment last, {
  Glissando kind = const Glissando(),
  VoiceSlot? voice,
}) => run(
  score,
  AddSpanner(
    kind: kind,
    staff: score.staves.first.id,
    first: pointAt(score, 0, first),
    last: pointAt(score, 0, last),
    voice: voice,
  ),
);

Score built(
  Score score,
  Moment first,
  Moment last, {
  Glissando kind = const Glissando(),
  VoiceSlot? voice,
}) => withSpanner(
  score,
  kind,
  pointAt(score, 0, first),
  pointAt(score, 0, last),
  voice: voice,
);

String notesOf(Score score) {
  final (:from, :to) = score.glissandoNotes(score.spanners.single);
  return '${from?.tone} ${to?.tone}';
}

String namesOf(Score score) => switch (score.spanners.single.kind) {
  Glissando(:final from, :final to) => '${from?.value} ${to?.value}',
  _ => 'not a glissando',
};

String endOf(Score score) {
  final on = score.anchorOf(score.spanners.single, last: true)!;
  return switch (on.event) {
    ChordEvent(:final notes) => '${on.voice.name} ${notes.first.tone}',
    _ => '${on.voice.name} rest',
  };
}

/// The glissando marks MusicXML export writes, each as the note it is on
/// and its type.
List<String> exported(Score score) => [
  for (final note in RegExp(
    '<note>((?:(?!</note>).)*)</note>',
    dotAll: true,
  ).allMatches(scoreToMusicXml(score)))
    for (final mark in RegExp(
      '<glissando type="(\\w+)"',
    ).allMatches(note[1]!))
      '${_written(note[1]!)} ${mark[1]}',
];

String _written(String note) {
  if (note.contains('<rest')) {
    return 'rest';
  }
  String? text(String tag) =>
      RegExp('<$tag>([^<]*)</$tag>').firstMatch(note)?[1];
  final alter = switch (text('alter')) {
    '-1' => 'b',
    '1' => '#',
    _ => '',
  };
  return '${text('step')}$alter${text('octave')}';
}

List<(double, int, int)> attacks(Score score) {
  final script = PlaybackCompiler().compile(
    changeBar(
      score,
      0,
      (column) => column.copyWith(
        tempos: Seq([const TempoMark(offset: Moment.zero, tempo: Tempo(60))]),
      ),
    ),
  );
  return [
    for (final note in script.notesBetween(0, double.infinity))
      ((note.start * 1000).round() / 1000, note.key, note.source.id.value),
  ];
}

void main() {
  group('A glissando whose last end names no note and falls on a rest of '
      'its own voice', () {
    /// Voice one plays C4, rests, then plays C5. Voice two plays E4 at the
    /// rest's onset.
    Score shape() => fill(
      fill(blankScore(), 0, [
        chordOf(1, 'C4'),
        rest(2, NoteValue.quarter),
        chordOf(3, 'C5', value: NoteValue.half),
      ]),
      0,
      [Gap(len(1, 4)), chordOf(5, 'E4'), Gap(len(1, 2))],
      slot: VoiceSlot.two,
    );

    test('ends on the chord another voice starts there', () {
      final score = built(shape(), Moment.zero, at(1, 4));

      expect(endOf(score), 'two E4');
      expect(notesOf(score), 'C4 E4');
    });

    test('is stored on that note by AddSpanner, and keeps it in a file', () {
      final score = added(shape(), Moment.zero, at(1, 4));

      expect(namesOf(score), '10 50');
      expect(notesOf(reloaded(score)), 'C4 E4');
    });

    test('keeps that end in a file that saves no end note', () {
      final score = built(
        shape(),
        Moment.zero,
        at(1, 4),
        voice: VoiceSlot.one,
      );

      expect(notesOf(reloaded(score)), 'C4 E4');
    });

    test('glides toward that note', () {
      expect(attacks(built(shape(), Moment.zero, at(1, 4))), [
        (0.0, 60, 1),
        (0.25, 61, 1),
        (0.5, 62, 1),
        (0.75, 63, 1),
        (1.0, 64, 5),
        (2.0, 72, 3),
      ]);
    });

    test('exports its stop on that note', () {
      expect(exported(built(shape(), Moment.zero, at(1, 4))), [
        'C4 start',
        'E4 stop',
      ]);
    });

    test('goes when that note is removed, as MuseScore 4 removes a '
        'glissando with its note', () {
      final score = added(shape(), Moment.zero, at(1, 4));
      final removed = run(
        score,
        RemoveNote(
          NoteRef(
            EventRef(
              measure: score.measures.first.id,
              staff: score.staves.first.id,
              id: const EventId(5),
            ),
            const NoteId(50),
          ),
        ),
      );

      expect(removed.spanners, isEmpty);
    });

    test('takes the first voice in order that starts a chord there, voice '
        'one included', () {
      var score = fill(blankScore(), 0, [
        rest(1, NoteValue.quarter),
        chordOf(2, 'G4'),
        rest(3, NoteValue.half),
      ]);
      score = fill(score, 0, [
        Gap(len(1, 4)),
        chordOf(5, 'E4'),
        Gap(len(1, 2)),
      ], slot: VoiceSlot.two);
      score = fill(score, 0, [
        chordOf(7, 'C4'),
        rest(8, NoteValue.quarter),
        Gap(len(1, 2)),
      ], slot: VoiceSlot.three);

      final line = built(score, Moment.zero, at(1, 4), voice: VoiceSlot.three);

      expect(endOf(line), 'one G4');
      expect(notesOf(line), 'C4 G4');
    });

    test('stays on the rest when no voice starts a chord there', () {
      final held = fill(
        fill(blankScore(), 0, [
          chordOf(1, 'C4'),
          rest(2, NoteValue.quarter),
          chordOf(3, 'C5', value: NoteValue.half),
        ]),
        0,
        [chordOf(5, 'E4', value: NoteValue.half), Gap(len(1, 2))],
        slot: VoiceSlot.two,
      );
      final score = built(held, Moment.zero, at(1, 4));

      expect(endOf(score), 'one rest');
      expect(notesOf(score), 'C4 null');
    });
  });
}
