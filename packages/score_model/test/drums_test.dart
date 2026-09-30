import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

const cowbell = Drum('Cowbell');

/// A drum staff over a morin khuur staff. Bar one holds a whole snare
/// (event 1) and a whole F4 (event 2).
EditSession band() {
  var score = blankScore(parts: const [drums, morinKhuur]);
  score = fill(score, 0, [
    hit(1, [snare], value: NoteValue.whole),
  ]);
  score = fill(score, 0, [chordOf(2, 'F4', value: NoteValue.whole)], staff: 1);
  return EditSession.start(score);
}

VoicePoint on(EditSession session, int staff, int bar, Moment offset) =>
    VoicePoint(
      staff: session.score.staves[staff].id,
      voice: VoiceSlot.one,
      at: pointAt(session.score, bar, offset),
    );

NoteRef noteOf(EditSession session, int event, [int index = 0]) => NoteRef(
  eventRef(session, event),
  chordIn(session, event).notes[index].id,
);

String refused(EditOutcome outcome) =>
    (refusal(outcome) as InvalidValue).message;

void main() {
  group('Drum notes', () {
    test('enter as drums on a percussion staff', () {
      final session = band();

      final next = applied(
        session.run(
          EnterNote(
            at: on(session, 0, 1, Moment.zero),
            tone: sideStick,
            value: NoteValue.half,
          ),
        ),
      );

      expect(bar(next.score, 1).first, 'Side stick/half');
      expect(voiceOf(next.score, 1).items.first, isA<ChordEvent>());
      expect(
        (voiceOf(next.score, 1).items.first as ChordEvent).notes.single,
        isA<DrumNote>(),
      );
    });

    test('refuse a tone that does not suit the staff', () {
      final session = band();
      List<Edit> edits(int staff, int event, Tone tone) => [
        EnterNote(
          at: on(session, staff, 1, Moment.zero),
          tone: tone,
          value: NoteValue.quarter,
        ),
        AddToChord(event: eventRef(session, event), tone: tone),
        AddGrace(event: eventRef(session, event), tone: tone),
        SetTone(noteOf(session, event), tone),
      ];

      for (final (staff, event, tone, message) in [
        (0, 1, f4, 'a percussion staff takes drums'),
        (0, 1, cowbell, 'the kit has no Cowbell'),
        (1, 2, snare, 'a pitched staff takes pitches'),
      ]) {
        for (final edit in edits(staff, event, tone)) {
          expect(
            refused(session.run(edit)),
            message,
            reason: '${edit.label} $tone',
          );
        }
      }
    });

    test('keep a chord in name order', () {
      final session = band();

      final added = applied(
        session.run(AddToChord(event: eventRef(session, 1), tone: bassDrum)),
      );
      final swapped = applied(
        added.run(SetTone(noteOf(added, 1), sideStick)),
      );

      expect(bar(added.score, 0), ['Bass drum+Snare/whole']);
      expect(bar(swapped.score, 0), ['Side stick+Snare/whole']);
      expect(
        refused(added.run(SetTone(noteOf(added, 1), snare))),
        'the chord already has Snare',
      );
    });

    test('tie a drum added to a chord that ties onto it', () {
      final session = EditSession.start(
        fill(blankScore(parts: const [drums]), 0, [
          hit(1, [snare], value: NoteValue.half, tie: true),
          hit(2, [bassDrum, snare], value: NoteValue.half),
        ]),
      );

      final next = applied(
        session.run(AddToChord(event: eventRef(session, 1), tone: bassDrum)),
      );

      expect(bar(next.score, 0), [
        'Bass drum+Snare/half~',
        'Bass drum+Snare/half',
      ]);
      expect(tiesOf(next, 1), {'Bass drum': true, 'Snare': true});
    });

    test('never share a chord with pitched notes', () {
      const drum = DrumNote(id: NoteId(1), drum: snare);
      final pitched = PitchedNote(id: const NoteId(2), pitch: f4);

      expect(
        () => ChordEvent(
          id: const EventId(1),
          value: NoteValue.quarter,
          notes: Seq([pitched, drum]),
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ChordEvent(
          id: const EventId(1),
          value: NoteValue.quarter,
          notes: Seq([drum]),
          graces: Seq([
            GraceChord(
              id: const EventId(2),
              kind: GraceKind.acciaccatura,
              value: NoteValue.eighth,
              notes: Seq([pitched]),
            ),
          ]),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('refuse marks only a pitched note has', () {
      final session = band();
      final note = noteOf(session, 1);

      expect(
        refused(session.run(SetAccidental(note, AccidentalRequest.always))),
        'a drum note has no accidental',
      );
      expect(
        refused(session.run(SetFingering(note, 1))),
        'a drum note has no fingering',
      );
      expect(
        refused(session.run(SetString(note, 0))),
        'a drum note has no string',
      );
    });

    test('split at a barline into tied drums', () {
      final session = band();

      final next = applied(
        session.run(
          EnterNote(
            at: on(session, 0, 0, at(1, 4)),
            tone: bassDrum,
            value: NoteValue.whole,
          ),
        ),
      );

      expect(bar(next.score, 0), [
        'Snare/quarter',
        'Bass drum/quarter~',
        'Bass drum/half~',
      ]);
      expect(bar(next.score, 1).first, 'Bass drum/quarter');
    });

    test('play a tie as one stroke held through', () {
      final score = fill(blankScore(parts: const [drums], bars: 1), 0, [
        hit(1, [snare], value: NoteValue.half, tie: true),
        hit(2, [bassDrum, snare], value: NoteValue.half),
      ]);

      expect(
        [
          for (final note
              in PlaybackCompiler().compile(score).notesBetween(0, 10))
            (note.key, note.source.id.value),
        ],
        [(38, 1), (36, 2)],
      );
    });

    test('paste only onto a staff of their kind', () {
      final session = band();
      Clip copied(int staff) => session
          .select(
            RangeSelection(
              from: pointAt(session.score, 0, Moment.zero),
              to: pointAt(session.score, 1, Moment.zero),
              top: session.score.staves[staff].id,
              bottom: session.score.staves[staff].id,
            ),
          )
          .copy()!;

      expect(
        refused(
          session.run(Paste(copied(0), at: on(session, 1, 1, Moment.zero))),
        ),
        'a pitched staff takes pitches',
      );
      expect(
        refused(
          session.run(Paste(copied(1), at: on(session, 0, 1, Moment.zero))),
        ),
        'a percussion staff takes drums',
      );
      expect(
        bar(
          applied(
            session.run(Paste(copied(0), at: on(session, 0, 1, Moment.zero))),
          ).score,
          1,
        ),
        ['Snare/whole'],
      );
    });

    test('need a kit that names each sound once', () {
      final session = band();
      const doubled = PartTemplate(
        name: 'Doubled',
        instrument: Instrument(
          key: 'doubled',
          program: 0,
          clef: Clef.percussion,
          drums: [
            DrumSound(name: 'Tom', position: Pitch(Step.e, 5), midiKey: 50),
            DrumSound(name: 'Tom', position: Pitch(Step.d, 5), midiKey: 48),
          ],
        ),
      );

      expect(
        refused(session.run(const AddPart(doubled))),
        'the kit names Tom twice',
      );
    });
  });
}
