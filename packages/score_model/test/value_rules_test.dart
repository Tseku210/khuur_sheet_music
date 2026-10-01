import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The message [edit] is refused with as an invalid value, or a description
/// of whatever else happened.
String invalid(EditSession session, Edit edit) => switch (session.run(edit)) {
  Refused(reason: InvalidValue(:final message)) => message,
  Refused(:final reason) => 'refused as $reason',
  Applied() => 'applied',
};

const grid = 'a value lasts a whole number of 128th notes';
const range = 'a pitch lies within MIDI keys 0 to 127';
const midi = 'a MIDI number is 0 to 127';
const longest = 'a bar lasts at most 64 whole notes';

const offGrid = [
  NoteValue(DurationBase.oneTwentyEighth, dots: 1),
  NoteValue(DurationBase.sixtyFourth, dots: 2),
  NoteValue(DurationBase.thirtySecond, dots: 3),
];

PartTemplate partOf(Instrument instrument) =>
    PartTemplate(name: 'Test', instrument: instrument);

void main() {
  group('Edits refuse values the save format refuses', () {
    final session = enterAt(blank(), 0, Moment.zero);
    final start = point(session.score, 0, Moment.zero);
    final second = point(session.score, 0, at(1, 4));
    final note = firstEvent(session.score, 0);
    final ref = session.score.locate(note.id)!;
    final bar = session.score.measures[0].id;

    for (final value in offGrid) {
      test('a $value note, rest, tuplet unit or grace', () {
        expect(
          [
            invalid(session, EnterNote(at: second, tone: f4, value: value)),
            invalid(session, EnterRest(at: second, value: value)),
            invalid(session, SetValue(ref, value)),
            invalid(
              session,
              EnterTuplet(at: second, ratio: TupletRatio.triplet, unit: value),
            ),
            invalid(session, AddGrace(event: ref, tone: g4, value: value)),
            invalid(
              session,
              SetTempoMarks(
                bar,
                Seq([
                  TempoMark(
                    offset: Moment.zero,
                    tempo: Tempo(60, beat: value),
                  ),
                ]),
              ),
            ),
          ],
          List.filled(6, grid),
        );
      });
    }

    test('a pitch outside the MIDI range, entered or transposed to', () {
      final top = enterAt(blank(), 0, Moment.zero, tone: Pitch.parse('G9'));
      final topRef = top.score.locate(firstEvent(top.score, 0).id)!;

      expect(
        [
          invalid(
            session,
            EnterNote(
              at: second,
              tone: Pitch.parse('A9'),
              value: NoteValue.quarter,
            ),
          ),
          invalid(
            session,
            EnterNote(
              at: second,
              tone: const Pitch(Step.b, -2),
              value: NoteValue.quarter,
            ),
          ),
          invalid(session, AddToChord(event: ref, tone: Pitch.parse('C-2'))),
          invalid(
            session,
            SetTone(
              NoteRef(ref, (note as ChordEvent).notes.single.id),
              Pitch.parse('A9'),
            ),
          ),
          invalid(
            top,
            Transpose(
              Selection.event(topRef),
              const ByInterval(Interval(0, 1)),
            ),
          ),
        ],
        List.filled(5, range),
      );
    });

    test('a meter the save format cannot hold', () {
      expect(
        [
          for (final meter in const [
            Meter([4], 3),
            Meter([4], 0),
            Meter([4], 256),
            Meter([], 4),
            Meter([3, 0], 4),
            Meter([65], 1),
          ])
            invalid(session, SetMeter(from: bar, meter: meter)),
        ],
        [
          'the unit is a power of two up to 128',
          'the unit is a power of two up to 128',
          'the unit is a power of two up to 128',
          'a meter has groups of 1 or more beats',
          'a meter has groups of 1 or more beats',
          longest,
        ],
      );
    });

    test('a bar longer than 64 whole notes', () {
      expect(
        invalid(session, SetBarLength(bar, len(129, 2))),
        longest,
      );
    });

    test('an infinite tempo or tempo factor', () {
      expect(
        [
          invalid(
            session,
            SetTempoMarks(
              bar,
              Seq([
                const TempoMark(
                  offset: Moment.zero,
                  tempo: Tempo(double.infinity),
                ),
              ]),
            ),
          ),
          invalid(
            session,
            AddSpanner(
              kind: const TempoLine(text: 'rit.', factor: double.infinity),
              staff: start.staff,
              first: start.at,
              last: second.at,
            ),
          ),
        ],
        [
          'a tempo is a finite number above 0',
          'a factor is a finite number above 0',
        ],
      );
    });

    test('an instrument outside the MIDI and pitch ranges', () {
      const position = Pitch(Step.c, 5);
      expect(
        [
          for (final instrument in [
            const Instrument(key: 'x', program: 200),
            const Instrument(key: 'x', program: 0, bank: -1),
            const Instrument(
              key: 'x',
              program: 0,
              drums: [
                DrumSound(name: 'Snare', position: position, midiKey: 300),
              ],
            ),
            const Instrument(
              key: 'x',
              program: 0,
              drums: [
                DrumSound(
                  name: 'Snare',
                  position: Pitch(Step.c, 10),
                  midiKey: 38,
                ),
              ],
            ),
            const Instrument(
              key: 'x',
              program: 0,
              strings: [Pitch(Step.c, 10)],
            ),
            const Instrument(key: 'x', program: 0, highest: Pitch(Step.c, 10)),
          ])
            invalid(session, AddPart(partOf(instrument))),
        ],
        [midi, 'a bank is 0 or more', midi, range, range, range],
      );
    });

    test('a blank score refuses an unwritable meter', () {
      expect(
        () =>
            Score.blank(parts: const [morinKhuur], meter: const Meter([4], 3)),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'the unit is a power of two up to 128',
          ),
        ),
      );
    });
  });

  group('Edits on a staff that no longer exists are stale', () {
    final session = enterAt(blank(), 0, Moment.zero);
    final bar = session.score.measures[0].id;
    final chord = firstEvent(session.score, 0) as ChordEvent;
    const gone = StaffId(999);

    test('EnterNote, AddToChord and SetTone', () {
      final stale = EventRef(measure: bar, staff: gone, id: chord.id);
      expect(
        [
          refusal(
            session.run(
              EnterNote(
                at: VoicePoint(
                  staff: gone,
                  voice: VoiceSlot.one,
                  at: ScorePoint(bar, Moment.zero),
                ),
                tone: f4,
                value: NoteValue.quarter,
              ),
            ),
          ),
          refusal(session.run(AddToChord(event: stale, tone: g4))),
          refusal(
            session.run(SetTone(NoteRef(stale, chord.notes.single.id), g4)),
          ),
        ],
        everyElement(isA<StaleReference>()),
      );
    });
  });
}
