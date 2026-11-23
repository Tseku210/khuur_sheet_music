import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

String endOf(Score score, {bool last = true}) {
  final on = score.anchorOf(score.spanners.single, last: last)!;
  final tones = switch (on.event) {
    ChordEvent(:final notes) => notes.map((note) => '${note.tone}'),
    _ => const ['rest'],
  };
  return '${on.voice.name} ${tones.join(' ')}';
}

String glissandoOf(Score score) {
  final (:from, :to) = score.glissandoNotes(score.spanners.single);
  return '${from?.tone} ${to?.tone}';
}

Score run(Score score, Edit edit) =>
    applied(EditSession.start(score).run(edit)).score;

Score added(
  Score score,
  SpannerKind kind,
  Moment first,
  Moment last, {
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

EnterNote enter(
  Score score,
  VoiceSlot voice,
  Moment offset,
  String tone,
  NoteValue value,
) => EnterNote(
  at: VoicePoint(
    staff: score.staves.first.id,
    voice: voice,
    at: pointAt(score, 0, offset),
  ),
  tone: Pitch.parse(tone),
  value: value,
  appendBar: false,
);

void main() {
  group('A slur end that sits on a note voice one started after the slur', () {
    Score held() {
      final score = fill(blankScore(bars: 1), 0, [
        chordOf(1, 'C5'),
        chordOf(2, 'D5', value: NoteValue.half),
        chordOf(3, 'E5'),
      ]);
      return fill(score, 0, [
        chordOf(5, 'E4'),
        Gap(len(3, 4)),
      ], slot: VoiceSlot.two);
    }

    final made = {
      'made by AddSpanner': added(
        held(),
        const Slur(),
        Moment.zero,
        at(1, 2),
        voice: VoiceSlot.two,
      ),
      'built directly': withSpanner(
        held(),
        const Slur(),
        pointAt(held(), 0, Moment.zero),
        pointAt(held(), 0, at(1, 2)),
        voice: VoiceSlot.two,
      ),
      'loaded from a file that names no end voice': reloaded(
        withSpanner(
          held(),
          const Slur(),
          pointAt(held(), 0, Moment.zero),
          pointAt(held(), 0, at(1, 2)),
          voice: VoiceSlot.two,
        ),
      ),
    };

    for (final MapEntry(key: how, value: score) in made.entries) {
      test('$how stays on that note when voice one starts a note under its '
          'end', () {
        final split = run(
          score,
          enter(score, VoiceSlot.one, at(3, 8), 'B4', NoteValue.eighth),
        );

        expect(endOf(score), 'one D5');
        expect(endOf(split), 'one D5');
        expect(endOf(reloaded(split)), 'one D5');
      });

      test('$how stays on that note when its own voice starts a note at its '
          'end', () {
        final filled = run(
          score,
          enter(score, VoiceSlot.two, at(1, 2), 'A4', NoteValue.quarter),
        );

        expect(endOf(filled), 'one D5');
        expect(endOf(reloaded(filled)), 'one D5');
        expect(endOf(scoreFromMusicXml(scoreToMusicXml(filled))), 'one D5');
      });
    }

    test('loaded from a file that names no end voice ends where it did before '
        'any edit', () {
      final score = made['loaded from a file that names no end voice']!;

      expect(score.spanners.single.kind, const Slur());
      expect(endOf(score), 'one D5');
    });

    test('an edit that changes nothing leaves the score as it was, with no '
        'step to undo', () {
      final score = made['built directly']!;
      final outcome = applied(
        EditSession.start(score).run(
          SetTie(
            NoteRef(score.locate(const EventId(5))!, const NoteId(50)),
            tied: false,
          ),
        ),
      );

      expect(outcome.score, same(score));
      expect(outcome.canUndo, isFalse);
    });

    test('undo after the first edit gives back the slur as it was built', () {
      final score = made['built directly']!;
      final session = applied(
        EditSession.start(score).run(
          enter(score, VoiceSlot.two, at(1, 2), 'A4', NoteValue.quarter),
        ),
      );

      expect(session.undo().score.spanners, score.spanners);
    });
  });

  test('A slur that starts inside a rest of its voice and ends on a note '
      'voice one starts there still stands after an edit', () {
    final notes = fill(blankScore(bars: 1), 0, [
      chordOf(1, 'C5'),
      chordOf(2, 'D5', value: NoteValue.half),
      chordOf(3, 'E5'),
    ]);
    final score = withSpanner(
      fill(notes, 0, [
        rest(5, NoteValue.half),
        Gap(len(1, 2)),
      ], slot: VoiceSlot.two),
      const Slur(),
      pointAt(notes, 0, at(1, 4)),
      pointAt(notes, 0, at(5, 8)),
      voice: VoiceSlot.two,
    );

    final edited = run(
      score,
      enter(score, VoiceSlot.one, at(3, 4), 'G5', NoteValue.quarter),
    );

    expect(endOf(score), 'one D5');
    expect(endOf(edited), 'one D5');
  });

  group('A glissando that names no note', () {
    Score between(String start, String end) => fill(blankScore(bars: 1), 0, [
      chordOf(1, start),
      chordOf(2, end),
      chordOf(3, 'C5', value: NoteValue.half),
    ]);

    Map<String, Score> made(String start, String end, Glissando kind) => {
      'made by AddSpanner': added(
        between(start, end),
        kind,
        Moment.zero,
        at(1, 4),
      ),
      'loaded from a file': reloaded(
        withSpanner(
          between(start, end),
          kind,
          pointAt(between(start, end), 0, Moment.zero),
          pointAt(between(start, end), 0, at(1, 4)),
          voice: VoiceSlot.one,
        ),
      ),
    };

    AddToChord adding(Score score, int event, String tone) => AddToChord(
      event: score.locate(EventId(event))!,
      tone: Pitch.parse(tone),
    );

    for (final MapEntry(key: how, value: score) in made(
      'C4',
      'E4',
      const Glissando(),
    ).entries) {
      test('$how keeps the note it ends on when a lower note joins that '
          'chord', () {
        expect(glissandoOf(score), 'C4 E4');
        expect(glissandoOf(run(score, adding(score, 2, 'C4'))), 'C4 E4');
      });
    }

    for (final MapEntry(key: how, value: score) in made(
      'C4',
      'E4 G4 C5',
      const Glissando(),
    ).entries) {
      test('$how keeps both its notes when a lower note joins the chord it '
          'starts on', () {
        expect(glissandoOf(score), 'C4 E4');
        expect(glissandoOf(run(score, adding(score, 1, 'A3'))), 'C4 E4');
      });

      test('$how keeps both its notes when a higher note joins the chord it '
          'starts on', () {
        expect(glissandoOf(run(score, adding(score, 1, 'G4'))), 'C4 E4');
      });
    }

    for (final MapEntry(key: how, value: score) in made(
      'C4 E4',
      'D4 F4 A4',
      const Glissando(from: NoteId(11)),
    ).entries) {
      test('$how keeps the note it ends on when a note leaves the chord it '
          'starts on', () {
        final removed = run(
          score,
          RemoveNote(
            NoteRef(score.locate(const EventId(1))!, const NoteId(10)),
          ),
        );

        expect(glissandoOf(score), 'E4 F4');
        expect(glissandoOf(removed), 'E4 F4');
        expect(glissandoOf(reloaded(removed)), 'E4 F4');
        expect(
          glissandoOf(scoreFromMusicXml(scoreToMusicXml(removed))),
          'E4 F4',
        );
      });
    }
  });
}
