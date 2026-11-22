import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

final c4 = Pitch.parse('C4');

/// C4 half then D4 half, a glissando from the first to the second.
EditSession glided({bool fromFirst = true}) {
  final score = fill(blankScore(), 0, [
    chordOf(1, fromFirst ? 'C4' : 'D4', value: NoteValue.half),
    chordOf(2, fromFirst ? 'D4' : 'C4', value: NoteValue.half),
  ]);
  return EditSession.start(
    withSpanner(
      score,
      const Glissando(from: NoteId(10), to: NoteId(20)),
      pointAt(score, 0, Moment.zero),
      pointAt(score, 0, at(1, 2)),
      voice: VoiceSlot.one,
    ),
  );
}

/// C4 half tied to C4 half.
EditSession tied() => EditSession.start(
  fill(blankScore(), 0, [
    chordOf(1, 'C4', value: NoteValue.half, tie: true),
    chordOf(2, 'C4', value: NoteValue.half),
  ]),
);

/// Quarters in voice one over [low] in voice two, both in the first bar of
/// two.
EditSession under(List<VoiceItem> low) {
  final score = fill(blankScore(), 0, [
    chordOf(1, 'E5'),
    chordOf(2, 'F5'),
    chordOf(3, 'G5'),
    chordOf(4, 'A5'),
  ]);
  return EditSession.start(fill(score, 0, low, slot: VoiceSlot.two));
}

EditSession erased(EditSession session, int id) => applied(
  session.run(
    Erase(
      ItemSelection(Seq([eventRef(session, id)])),
      ripple: Ripple.part,
    ),
  ),
);

void main() {
  group('A note or rest entered over part of a chord', () {
    test('drops the glissando that starts on the chord', () {
      final session = glided();
      final onBeatTwo = point(session.score, 0, at(1, 4));

      final note = applied(enter(session, onBeatTwo, tone: g4));
      final rest = applied(
        session.run(EnterRest(at: onBeatTwo, value: NoteValue.eighth)),
      );

      expect(bar(note.score, 0), ['C4/quarter', 'G4/quarter', 'D4/half']);
      expect(note.score.spanners, isEmpty);
      expect(note.undo().score.spanners, session.score.spanners);
      expect(rest.score.spanners, isEmpty);
    });

    test('keeps the glissando that ends on the chord', () {
      final session = glided();

      final next = applied(
        enter(session, point(session.score, 0, at(3, 4)), tone: g4),
      );

      expect(bar(next.score, 0), ['C4/half', 'D4/quarter', 'G4/quarter']);
      expect(next.score.spanners, session.score.spanners);
    });

    test('drops the tie from the chord into a new note of its tone', () {
      final session = tied();

      final next = applied(
        enter(session, point(session.score, 0, at(1, 4)), tone: c4),
      );

      expect(bar(next.score, 0), [
        'C4/quarter',
        'C4/quarter',
        'C4/half',
      ]);
    });

    test('keeps the tie into the chord', () {
      final session = sessionWith([
        [
          chordOf(1, 'C4', value: NoteValue.half, tie: true),
          chordOf(2, 'C4', value: NoteValue.half),
        ],
      ]);

      final next = applied(
        enter(session, point(session.score, 0, at(3, 4)), tone: g4),
      );

      expect(bar(next.score, 0), ['C4/half~', 'C4/quarter', 'G4/quarter']);
    });

    test('drops the glissando from a chord in a tuplet', () {
      final score = fill(blankScore(), 0, [
        tripletOfEighths(5, [
          chordOf(1, 'C4'),
          chordOf(2, 'D4', value: NoteValue.eighth),
        ]),
        rest(3, NoteValue.quarter),
        rest(4, NoteValue.half),
      ]);
      final session = EditSession.start(
        withSpanner(
          score,
          const Glissando(from: NoteId(10), to: NoteId(20)),
          pointAt(score, 0, Moment.zero),
          pointAt(score, 0, at(1, 6)),
          voice: VoiceSlot.one,
        ),
      );

      final next = applied(
        enter(
          session,
          point(session.score, 0, at(1, 12)),
          tone: g4,
          value: NoteValue.eighth,
        ),
      );

      expect(bar(next.score, 0).first, '3:2[C4/eighth, G4/eighth, D4/eighth]');
      expect(next.score.spanners, isEmpty);
    });
  });

  group('A note entered with a ripple inside a chord', () {
    EditOutcome pushed(EditSession session, Moment offset) => session.run(
      EnterNote(
        at: point(session.score, 0, offset),
        tone: g4,
        value: NoteValue.eighth,
        ripple: Ripple.part,
      ),
    );

    test('drops the glissando that starts on the chord', () {
      final session = glided();

      final next = applied(pushed(session, at(1, 4)));

      expect(bar(next.score, 0).take(4), [
        'C4/quarter',
        'G4/eighth',
        'C4/eighth~',
        'C4/eighth',
      ]);
      expect(next.score.spanners, isEmpty);
    });

    test('drops the glissando that ends on the chord', () {
      final session = glided(fromFirst: false);

      final next = applied(pushed(session, at(3, 4)));

      expect(bar(next.score, 0), [
        'D4/half',
        'C4/quarter',
        'G4/eighth',
        'C4/eighth~',
      ]);
      expect(next.score.spanners, isEmpty);
    });

    test('drops the ties into and out of the chord', () {
      final session = EditSession.start(
        fill(blankScore(), 0, [
          chordOf(1, 'C4', tie: true),
          chordOf(2, 'C4', value: NoteValue.half, tie: true),
          chordOf(3, 'C4'),
        ]),
      );

      final next = applied(pushed(session, at(1, 2)));

      expect(bar(next.score, 0), [
        'C4/quarter',
        'C4/quarter',
        'G4/eighth',
        'C4/eighth~',
        'C4/eighth',
        'C4/eighth~',
      ]);
      expect(bar(next.score, 1).first, 'C4/eighth');
    });

    test('drops the ties and glissandi of a chord another voice holds '
        'across it', () {
      final base = under([
        chordOf(5, 'C4', tie: true),
        chordOf(6, 'C4', value: NoteValue.half, tie: true),
        chordOf(7, 'C4'),
      ]);
      final score = base.score;
      final session = EditSession.start(
        withSpanner(
          score,
          const Glissando(),
          pointAt(score, 0, at(1, 4)),
          pointAt(score, 0, at(3, 4)),
          voice: VoiceSlot.two,
        ),
      );

      final next = applied(pushed(session, at(1, 2)));

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'C4/quarter',
        'C4/quarter~',
        'C4/quarter.',
        'C4/eighth~',
      ]);
      expect(next.score.spanners, isEmpty);
    });
  });

  group('SetValue', () {
    test('shorter drops a tie that ends on no note', () {
      final session = sessionWith([
        [
          chordOf(1, 'C4', value: NoteValue.half, tie: true),
          chordOf(2, 'D4', value: NoteValue.half),
        ],
      ]);

      final next = applied(
        session.run(SetValue(eventRef(session, 1), NoteValue.quarter)),
      );

      expect(bar(next.score, 0), ['C4/quarter', 'rest/quarter', 'D4/half']);
    });

    test('shorter with a ripple drops the tie from the note', () {
      final session = tied();

      final next = applied(
        session.run(
          SetValue(
            eventRef(session, 1),
            NoteValue.quarter,
            ripple: Ripple.part,
          ),
        ),
      );

      expect(bar(next.score, 0), ['C4/quarter', 'C4/half', 'rest/quarter']);
      expect(tiesOf(next.undo(), 1), {'C4': true});
    });

    test('longer with a ripple keeps the ties of a chord another voice '
        'holds across it', () {
      final session = under([
        chordOf(5, 'C4', value: NoteValue.half, tie: true),
        chordOf(6, 'C4', value: NoteValue.half),
      ]);

      final next = applied(
        session.run(
          SetValue(eventRef(session, 1), NoteValue.half, ripple: Ripple.part),
        ),
      );

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'C4/half.~',
        'C4/quarter~',
      ]);
    });
  });

  group('A rippled erase', () {
    test('drops the tie from a note that loses its end', () {
      final session = under([
        chordOf(5, 'C4', value: NoteValue.half, tie: true),
        chordOf(6, 'C4', value: NoteValue.half),
      ]);

      final next = erased(session, 2);

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'C4/quarter',
        'C4/half',
        'gap 1/4',
      ]);
    });

    test('drops the tie from a note that loses its middle, and keeps the '
        'tie into it', () {
      final session = under([
        chordOf(5, 'C4', tie: true),
        chordOf(6, 'C4', value: NoteValue.half.dotted, tie: true),
      ]);
      final score = fill(session.score, 1, [
        chordOf(7, 'C4', value: NoteValue.whole),
      ], slot: VoiceSlot.two);

      final next = erased(EditSession.start(score), 3);

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'C4/quarter~',
        'C4/half',
        'C4/quarter~',
      ]);
    });

    test('drops the ties into and out of a note that loses its start', () {
      final session = under([
        chordOf(5, 'C4', tie: true),
        chordOf(6, 'C4', value: NoteValue.half, tie: true),
        chordOf(7, 'C4'),
      ]);

      final next = erased(session, 2);

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'C4/quarter',
        'C4/quarter',
        'C4/quarter',
        'gap 1/4',
      ]);
    });

    test('drops the tie from the section before into a note that loses '
        'its start', () {
      var score = fill(blankScore(), 0, [
        rest(1, NoteValue.half.dotted),
        chordOf(2, 'C4', tie: true),
      ]);
      score = changeBar(
        score,
        0,
        (column) => column.copyWith(barline: Barline.doubleBar),
      );
      score = fill(score, 1, [
        chordOf(3, 'C4', value: NoteValue.half),
        rest(4, NoteValue.half),
      ]);
      score = fill(score, 1, [
        chordOf(5, 'A4'),
        Gap(len(3, 4)),
      ], slot: VoiceSlot.two);

      final next = erased(EditSession.start(score), 5);

      expect(bar(next.score, 0).last, 'C4/quarter');
      expect(bar(next.score, 1).first, 'C4/quarter');
    });
  });
}
