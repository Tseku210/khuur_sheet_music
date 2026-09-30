import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

final a4 = Pitch.parse('A4');
final c5 = Pitch.parse('C5');

Score withClefChange(Score score, Moment offset, Clef clef) =>
    changeBar(score, 0, (column) {
      final staff = column.staves.first;
      return column.withStaff(
        staff.copyWith(clefChanges: Seq([ClefChange(offset, clef)])),
      );
    });

Pitch tap(Score score, int step, {int staff = 0, Moment? offset}) =>
    score.pitchForStaffStep(
      score.staves[staff].id,
      pointAt(score, 0, offset ?? Moment.zero),
      step,
    );

EventRef refTo(Score score, int bar, EventId id) => EventRef(
  measure: score.measures[bar].id,
  staff: score.staves.first.id,
  id: id,
);

EditOutcome addTo(EditSession session, EventRef event, Pitch pitch) =>
    session.run(AddToChord(event: event, pitch: pitch));

Map<String, bool> ties(ChordEvent chord) => {
  for (final note in chord.notes) '${note.pitch}': note.tie,
};

(int, Moment) spot(EditSession session) => (
  session.score.indexOf(session.cursor.at.measure),
  session.cursor.at.offset,
);

List<EditSession> walk(EditSession session, CursorMove move, int steps) {
  final seen = <EditSession>[];
  var current = session;
  for (var i = 0; i < steps; i++) {
    current = current.moveCursor(move);
    seen.add(current);
  }
  return seen;
}

EditSession cursorAt(
  EditSession session,
  int bar,
  Moment offset, {
  VoiceSlot voice = VoiceSlot.one,
}) => session.placeCursor(point(session.score, bar, offset, voice: voice));

void main() {
  group('KeySignature.transpose', () {
    test('gives the key a transposing part reads', () {
      const bFlatClarinet = Interval(-1, -2);
      const eFlatAltoSax = Interval(-5, -9);

      expect(
        KeySignature.cMajor.transpose(bFlatClarinet),
        const KeySignature(2, KeyMode.major),
      );
      expect(
        const KeySignature(-1).transpose(bFlatClarinet),
        const KeySignature(1),
      );
      expect(
        KeySignature.cMajor.transpose(eFlatAltoSax),
        const KeySignature(3, KeyMode.major),
      );
      expect(
        const KeySignature(-2).transpose(Interval.unison),
        const KeySignature(-2),
      );
    });

    test('respells a key past seven accidentals enharmonically', () {
      expect(
        const KeySignature(7).transpose(const Interval(-1, -2)),
        const KeySignature(-3),
      );
      expect(
        const KeySignature(-7).transpose(Interval.majorSecond),
        const KeySignature(3),
      );
    });
  });

  group('Score.contextAt', () {
    test('reads clef, key and meter from the bar', () {
      final score = blankScore(
        meter: Meter.threeFour,
        key: const KeySignature(-1),
      );

      final context = score.contextAt(
        score.staves.first.id,
        pointAt(score, 1, at(1, 4)),
      );

      expect(context.clef, Clef.treble);
      expect(context.key, const KeySignature(-1));
      expect(context.writtenKey, const KeySignature(-1));
      expect(context.meter, Meter.threeFour);
      expect(context.octaveShift, 0);
    });

    test('reads the clef in effect at the offset', () {
      final score = withClefChange(blankScore(), at(1, 2), Clef.bass);
      Clef clefAt(Moment offset) => score
          .contextAt(score.staves.first.id, pointAt(score, 0, offset))
          .clef;

      expect(clefAt(at(1, 4)), Clef.treble);
      expect(clefAt(at(1, 2)), Clef.bass);
      expect(clefAt(at(3, 4)), Clef.bass);
    });

    test('takes the nearest tempo mark at or before the point', () {
      final score = changeBar(
        blankScore(bars: 3),
        1,
        (column) => column.copyWith(
          tempos: Seq([TempoMark(offset: at(1, 2), tempo: const Tempo(60))]),
        ),
      );
      Tempo tempoAt(int bar, Moment offset) => score
          .contextAt(score.staves.first.id, pointAt(score, bar, offset))
          .tempo;

      expect(tempoAt(1, at(1, 4)), Tempo.unmarked);
      expect(tempoAt(1, at(1, 2)), const Tempo(60));
      expect(tempoAt(2, Moment.zero), const Tempo(60));
    });

    test('falls back to the unmarked tempo before any mark', () {
      final score = scoreWith([rest(1, NoteValue.whole)]);

      final context = score.contextAt(
        score.staves.first.id,
        pointAt(score, 0, Moment.zero),
      );

      expect(context.tempo, Tempo.unmarked);
    });

    test('applies an octave line on its staff from first to last anchor', () {
      final base = blankScore(parts: const [piano]);
      final score = withOctaveLine(
        base,
        OctaveShift.up8,
        pointAt(base, 0, at(1, 4)),
        pointAt(base, 1, at(1, 4)),
      );
      int shift(int staff, int bar, Moment offset) => score
          .contextAt(score.staves[staff].id, pointAt(score, bar, offset))
          .octaveShift;

      expect(shift(0, 0, Moment.zero), 0);
      expect(shift(0, 0, at(1, 4)), 1);
      expect(shift(0, 1, Moment.zero), 1);
      expect(shift(0, 1, at(1, 4)), 1);
      expect(shift(0, 1, at(1, 2)), 0);
      expect(shift(1, 0, at(1, 2)), 0);
    });

    test('derives the written key from the instrument transposition', () {
      final score = blankScore(
        parts: const [clarinet],
        key: const KeySignature(-1),
      );

      final context = score.contextAt(
        score.staves.first.id,
        pointAt(score, 0, Moment.zero),
      );

      expect(context.key, const KeySignature(-1));
      expect(context.writtenKey, const KeySignature(1));
    });
  });

  group('Score.pitchForStaffStep', () {
    test('reads the natural pitch from the clef', () {
      final score = blankScore(parts: const [piano]);

      expect(tap(score, 0), Pitch.parse('E4'));
      expect(tap(score, -2), Pitch.parse('C4'));
      expect(tap(score, 8), Pitch.parse('F5'));
      expect(tap(score, 0, staff: 1), Pitch.parse('G2'));
      expect(tap(score, 8, staff: 1), Pitch.parse('A3'));
    });

    test('applies the key signature', () {
      final score = blankScore(key: const KeySignature(-1));

      expect(tap(score, 4), Pitch.parse('Bb4'));
      expect(tap(score, 0), Pitch.parse('E4'));
    });

    test('uses the clef in effect at the tap', () {
      final score = withClefChange(blankScore(), at(1, 2), Clef.bass);

      expect(tap(score, 0, offset: at(1, 4)), Pitch.parse('E4'));
      expect(tap(score, 0, offset: at(1, 2)), Pitch.parse('G2'));
    });

    test('sounds an octave up under 8va and down under 8vb', () {
      final base = blankScore();
      ScorePoint start(Score score) => pointAt(score, 0, Moment.zero);
      final up = withOctaveLine(
        base,
        OctaveShift.up8,
        start(base),
        start(base),
      );
      final down = withOctaveLine(
        base,
        OctaveShift.down8,
        start(base),
        start(base),
      );

      expect(tap(up, 0), Pitch.parse('E5'));
      expect(tap(down, 0), Pitch.parse('E3'));
    });

    test('turns written pitch into concert pitch for a transposing part', () {
      final score = blankScore(parts: const [clarinet]);

      expect(tap(score, 1), Pitch.parse('E4'));
      expect(tap(score, 2), Pitch.parse('F4'));
    });

    test('gives the plain display position on a percussion staff', () {
      final score = blankScore(
        parts: const [drums],
        key: const KeySignature(2),
      );

      expect(tap(score, 1), Pitch.parse('F4'));
      expect(tap(score, 5), Pitch.parse('C5'));
    });
  });

  group('AddToChord', () {
    test('adds pitches in pitch order and keeps the event selected', () {
      var session = enterAt(blank(), 0, Moment.zero);
      final event = session.selection.singleEvent!;

      session = applied(addTo(session, event, a4));
      session = applied(addTo(session, event, Pitch.parse('D4')));

      expect(bar(session.score, 0), [
        'D4+F4+A4/quarter',
        'rest/quarter',
        'rest/half',
      ]);
      final chord = firstEvent(session.score, 0) as ChordEvent;
      expect(chord.id, event.id);
      expect(chord.notes.map((n) => n.id).toSet(), hasLength(3));
      expect(session.selection.singleEvent, event);
      expect(session.undoLabel, 'Add note to chord');
    });

    test('changes nothing and records no step for a pitch it has', () {
      final entered = enterAt(blank(), 0, Moment.zero);

      final session = applied(
        addTo(entered, entered.selection.singleEvent!, f4),
      );

      expect(identical(session.score, entered.score), isTrue);
      expect(bar(session.undo().score, 0), ['measure-rest']);
    });

    test('turns a rest into a note of its value with the same id', () {
      final session = EditSession.start(
        scoreWith([rest(1, NoteValue.half), rest(2, NoteValue.half)]),
      );

      final next = applied(
        addTo(session, refTo(session.score, 0, const EventId(1)), f4),
      );

      expect(bar(next.score, 0), ['F4/half', 'rest/half']);
      expect(firstEvent(next.score, 0).id, const EventId(1));
    });

    test('turns a measure rest into notes that fill the bar', () {
      for (final (meter, expected) in [
        (Meter.fourFour, ['F4/whole']),
        (Meter.threeFour, ['F4/half.']),
        (Meter.simple(5, 4), ['F4/whole~', 'F4/quarter']),
      ]) {
        final session = blank(meter: meter);
        final measureRest = firstEvent(session.score, 0);

        final next = applied(
          addTo(session, refTo(session.score, 0, measureRest.id), f4),
        );

        expect(bar(next.score, 0), expected, reason: '$meter');
        expect(firstEvent(next.score, 0).id, measureRest.id, reason: '$meter');
      }
    });

    test('adds a note to a rest inside a tuplet', () {
      final session = EditSession.start(
        scoreWith([
          tripletOfEighths(10, [
            rest(11, NoteValue.eighth),
            rest(12, NoteValue.eighth),
            rest(13, NoteValue.eighth),
          ]),
          rest(14, NoteValue.quarter),
          rest(15, NoteValue.half),
        ]),
      );

      final next = applied(
        addTo(session, refTo(session.score, 0, const EventId(12)), f4),
      );

      expect(bar(next.score, 0), [
        '3:2[rest/eighth, F4/eighth, rest/eighth]',
        'rest/quarter',
        'rest/half',
      ]);
    });

    test('writes into the voice that holds the event', () {
      final session = enterAt(
        blank(),
        0,
        Moment.zero,
        pitch: g4,
        voice: VoiceSlot.two,
      );

      final next = applied(
        addTo(session, session.selection.singleEvent!, Pitch.parse('B4')),
      );

      expect(bar(next.score, 0, slot: VoiceSlot.two), [
        'G4+B4/quarter',
        'gap 3/4',
      ]);
      expect(bar(next.score, 0), ['measure-rest']);
    });

    test('ties the new note when the chord ties into that pitch', () {
      var session = enterAt(blank(), 0, at(3, 4), value: NoteValue.half);
      final head = session.selection.singleEvent!;
      final tail = refTo(session.score, 1, firstEvent(session.score, 1).id);

      session = applied(addTo(session, tail, a4));
      session = applied(addTo(session, head, a4));
      session = applied(addTo(session, head, c5));

      final chord = voiceOf(session.score, 0).items.last as ChordEvent;
      expect(ties(chord), {'F4': true, 'A4': true, 'C5': false});
      expect(ties(firstEvent(session.score, 1) as ChordEvent), {
        'F4': false,
        'A4': false,
      });
    });

    test('leaves the new note untied when the chord is not tied', () {
      final session = EditSession.start(
        scoreWith([
          chord(1, f4, NoteValue.quarter),
          chord(2, a4, NoteValue.quarter),
          rest(3, NoteValue.half),
        ]),
      );

      final next = applied(
        addTo(session, refTo(session.score, 0, const EventId(1)), a4),
      );

      expect(ties(firstEvent(next.score, 0) as ChordEvent), {
        'F4': false,
        'A4': false,
      });
    });

    test('refuses a reference to an event that is gone', () {
      final session = blank();
      final gone = refTo(session.score, 0, const EventId(999));

      final outcome = addTo(session, gone, f4);

      expect(
        outcome,
        isA<Refused>().having(
          (refused) => refused.reason,
          'reason',
          isA<StaleReference>().having((r) => r.target, 'target', gone),
        ),
      );
    });
  });

  group('EditSession.placeCursor', () {
    test('moves the cursor and leaves score, selection and history', () {
      final entered = enterAt(blank(), 0, Moment.zero);
      final target = point(entered.score, 1, at(1, 4));

      final moved = entered.placeCursor(target);

      expect(moved.cursor, target);
      expect(identical(moved.score, entered.score), isTrue);
      expect(moved.selection, same(entered.selection));
      expect(moved.undoLabel, 'Enter note');
    });

    test('snaps the end of a bar to the start of the next', () {
      final session = blank();

      final moved = session.placeCursor(point(session.score, 0, at(1, 1)));

      expect(moved.cursor, point(session.score, 1, Moment.zero));
    });

    test('rejects a point outside the score', () {
      final session = blank();
      final score = session.score;

      for (final outside in [
        point(score, 0, at(-1, 4)),
        point(score, 0, at(5, 4)),
        point(score, 1, at(1, 1)),
        VoicePoint(
          staff: const StaffId(999),
          voice: VoiceSlot.one,
          at: pointAt(score, 0, Moment.zero),
        ),
        VoicePoint(
          staff: score.staves.first.id,
          voice: VoiceSlot.one,
          at: const ScorePoint(MeasureId(999), Moment.zero),
        ),
      ]) {
        expect(() => session.placeCursor(outside), throwsArgumentError);
      }
    });
  });

  group('EditSession.moveCursor', () {
    EditSession twoNotes() => enterAt(
      enterAt(blank(), 0, Moment.zero),
      0,
      at(1, 4),
      value: NoteValue.half,
    );

    test('steps forward through onsets and across the barline', () {
      final session = cursorAt(twoNotes(), 0, Moment.zero);

      final steps = walk(session, CursorMove.nextEvent, 4);

      expect(steps.map(spot), [
        (0, at(1, 4)),
        (0, at(3, 4)),
        (1, Moment.zero),
        (1, Moment.zero),
      ]);
      expect(identical(steps.last.score, session.score), isTrue);
      expect(steps.last.selection, same(session.selection));
      expect(steps.last.undoLabel, session.undoLabel);
    });

    test('steps back through onsets and across the barline', () {
      final session = cursorAt(twoNotes(), 1, Moment.zero);

      expect(walk(session, CursorMove.previousEvent, 4).map(spot), [
        (0, at(3, 4)),
        (0, at(1, 4)),
        (0, Moment.zero),
        (0, Moment.zero),
      ]);
    });

    test('leaves the middle of an event for its neighbours', () {
      final session = cursorAt(twoNotes(), 0, at(1, 2));

      expect(spot(session.moveCursor(CursorMove.nextEvent)), (0, at(3, 4)));
      expect(spot(session.moveCursor(CursorMove.previousEvent)), (0, at(1, 4)));
    });

    test('steps through tuplet members', () {
      final session = EditSession.start(
        scoreWith([
          tripletOfEighths(10, [
            rest(11, NoteValue.eighth),
            rest(12, NoteValue.eighth),
            rest(13, NoteValue.eighth),
          ]),
          rest(14, NoteValue.quarter),
          rest(15, NoteValue.half),
        ]),
      );

      expect(walk(session, CursorMove.nextEvent, 5).map(spot), [
        (0, at(1, 12)),
        (0, at(1, 6)),
        (0, at(1, 4)),
        (0, at(1, 2)),
        (0, at(1, 2)),
      ]);
    });

    test('stops at bar starts and events in a voice with gaps', () {
      final entered = enterAt(
        blank(),
        0,
        at(1, 4),
        pitch: g4,
        value: NoteValue.eighth,
        voice: VoiceSlot.two,
      );

      final forward = walk(
        cursorAt(entered, 0, Moment.zero, voice: VoiceSlot.two),
        CursorMove.nextEvent,
        3,
      );
      final back = walk(forward.last, CursorMove.previousEvent, 3);

      expect(forward.map(spot), [
        (0, at(1, 4)),
        (1, Moment.zero),
        (1, Moment.zero),
      ]);
      expect(back.map(spot), [
        (0, at(1, 4)),
        (0, Moment.zero),
        (0, Moment.zero),
      ]);
      expect(back.last.cursor.voice, VoiceSlot.two);
    });

    test('moves by bars', () {
      final session = cursorAt(blank(bars: 3), 0, at(1, 2));

      final forward = walk(session, CursorMove.nextMeasure, 3);
      final back = walk(
        cursorAt(session, 2, at(1, 4)),
        CursorMove.previousMeasure,
        4,
      );

      expect(forward.map(spot), [
        (1, Moment.zero),
        (2, Moment.zero),
        (2, Moment.zero),
      ]);
      expect(back.map(spot), [
        (2, Moment.zero),
        (1, Moment.zero),
        (0, Moment.zero),
        (0, Moment.zero),
      ]);
    });

    test('moves between visible staves and keeps time and voice', () {
      final base = Score.blank(
        parts: const [piano, morinKhuur, morinKhuur],
        measureCount: 1,
      );
      final score = hidePart(base, 1);
      final start = EditSession.start(score).placeCursor(
        VoicePoint(
          staff: score.staves.first.id,
          voice: VoiceSlot.two,
          at: pointAt(score, 0, at(1, 4)),
        ),
      );
      int staffIndex(EditSession session) =>
          score.staves.indexWhere((s) => s.id == session.cursor.staff);

      final down = walk(start, CursorMove.staffDown, 3);
      final up = walk(down.last, CursorMove.staffUp, 3);

      expect(down.map(staffIndex), [1, 3, 3]);
      expect(up.map(staffIndex), [1, 0, 0]);
      expect(up.last.cursor.at, pointAt(score, 0, at(1, 4)));
      expect(up.last.cursor.voice, VoiceSlot.two);
    });
  });
}
