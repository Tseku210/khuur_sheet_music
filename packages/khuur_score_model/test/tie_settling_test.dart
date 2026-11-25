import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The head of [id]'s chord, made by [chordOf], as a reference.
NoteRef headOf(EditSession session, int id) =>
    NoteRef(eventRef(session, id), NoteId(id * 10));

void main() {
  group('after an edit, a tie that landed on no head', () {
    test('goes when the edit gives its head the tone of the next one', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half, tie: true),
          chordOf(2, 'G4', value: NoteValue.half),
        ],
      ]);

      final next = applied(session.run(SetTone(headOf(session, 1), g4)));

      expect(bar(next.score, 0), ['G4/half', 'G4/half']);
    });

    test('goes when the edit enters its tone in another voice', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half, tie: true),
          rest(2, NoteValue.half),
        ],
      ]);

      final next = enterAt(session, 0, at(1, 2), voice: VoiceSlot.two);

      expect(bar(next.score, 0), ['F4/half', 'rest/half']);
    });

    test('stays when the edit enters its tone in its own voice', () {
      final session = sessionWith([
        [
          chordOf(1, 'F4', value: NoteValue.half, tie: true),
          rest(2, NoteValue.half),
        ],
      ]);

      final next = enterAt(session, 0, at(1, 2));

      expect(bar(next.score, 0), ['F4/half~', 'F4/quarter', 'rest/quarter']);
    });
  });

  test('a tie into another voice goes when the edit changes the tone of '
      'the head it landed on', () {
    var score = fill(blankScore(), 0, [
      chordOf(1, 'F4', value: NoteValue.half, tie: true),
      chordOf(2, 'G4', value: NoteValue.half),
    ]);
    score = fill(score, 0, [
      rest(3, NoteValue.half),
      chordOf(4, 'F4', value: NoteValue.half),
    ], slot: VoiceSlot.two);
    final session = EditSession.start(score);
    final tie = score.measureView(score.measures[0].id).staves.first.ties;
    expect(tie.single.to?.note, const NoteId(40));

    final next = applied(session.run(SetTone(headOf(session, 4), g4)));

    expect(bar(next.score, 0), ['F4/half', 'G4/half']);
  });

  group('a tie into another voice stays when the edit writes in the tie\'s '
      'own voice where it leads', () {
    EditSession crossVoice() {
      var score = fill(blankScore(), 0, [
        chordOf(1, 'F4', value: NoteValue.half, tie: true),
        rest(2, NoteValue.half),
      ]);
      score = fill(score, 0, [
        rest(3, NoteValue.half),
        chordOf(4, 'F4', value: NoteValue.half),
      ], slot: VoiceSlot.two);
      return EditSession.start(score);
    }

    for (final (name, edit) in <(String, Edit Function(VoicePoint))>[
      (
        'a note',
        (at) => EnterNote(at: at, tone: g4, value: NoteValue.quarter),
      ),
      ('a rest', (at) => EnterRest(at: at, value: NoteValue.quarter)),
      (
        'a tuplet',
        (at) => EnterTuplet(
          at: at,
          ratio: TupletRatio.triplet,
          unit: NoteValue.eighth,
        ),
      ),
    ]) {
      test(name, () {
        final session = crossVoice();

        final next = applied(
          session.run(edit(point(session.score, 0, at(1, 2)))),
        );

        final score = next.score;
        final ties = score.measureView(score.measures[0].id).staves.first.ties;
        expect([for (final tie in ties) tie.to?.note], [const NoteId(40)]);
      });
    }
  });
}
