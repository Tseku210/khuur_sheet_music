import 'dart:convert';

import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

EditSession edited(EditSession session, Edit edit) =>
    applied(session.run(edit));

List<String> names(Score score) => [for (final part in score.parts) part.name];

void expectStavesInOrder(Score score) {
  final order = [for (final staff in score.staves) staff.id];
  for (final column in score.measures) {
    expect([for (final measure in column.staves) measure.staff], order);
  }
}

EditSession withCursor(Score score, int staff) =>
    EditSession.start(score).placeCursor(
      VoicePoint(
        staff: score.staves[staff].id,
        voice: VoiceSlot.two,
        at: pointAt(score, 1, at(1, 4)),
      ),
    );

/// Where [session]'s cursor is, as (staff index, bar index, offset, voice).
(int, int, Moment, VoiceSlot) cursorOf(EditSession session) {
  final VoicePoint(:staff, :voice, :at) = session.cursor;
  return (
    session.score.staves.indexWhere((s) => s.id == staff),
    session.score.indexOf(at.measure),
    at.offset,
    voice,
  );
}

const violin = PartTemplate(
  name: 'Violin',
  shortName: 'Vln.',
  instrument: Instrument(key: 'violin', program: 40),
);

const strung = PartTemplate(
  name: 'Violin',
  instrument: Instrument(
    key: 'violin',
    program: 40,
    strings: [
      Pitch(Step.g, 3),
      Pitch(Step.d, 4),
      Pitch(Step.a, 4),
      Pitch(Step.e, 5),
    ],
  ),
);

const viola = PartTemplate(
  name: 'Viola',
  instrument: Instrument(
    key: 'viola',
    program: 41,
    clef: Clef.alto,
    strings: [
      Pitch(Step.c, 3),
      Pitch(Step.g, 3),
      Pitch(Step.d, 4),
      Pitch(Step.a, 4),
    ],
  ),
);

const cello = PartTemplate(
  name: 'Cello',
  instrument: Instrument(
    key: 'cello',
    program: 42,
    clef: Clef.bass,
    strings: [
      Pitch(Step.c, 2),
      Pitch(Step.g, 2),
      Pitch(Step.d, 3),
      Pitch(Step.a, 3),
    ],
  ),
);

/// A quarter of [pitch] with id [id], its head [id] + 50 on [string].
ChordEvent onString(int id, Pitch pitch, int? string) => ChordEvent(
  id: EventId(id),
  value: NoteValue.quarter,
  notes: Seq([PitchedNote(id: NoteId(id + 50), pitch: pitch, string: string)]),
);

/// The chords of voice one on staff [staff] of bar [bar], each as its id
/// and sounding tones.
List<String> soundOf(Score score, int bar, {int staff = 0}) => [
  for (final item in score.measures[bar].staves[staff].voices.first.items)
    if (item case ChordEvent(:final id, :final notes))
      '$id ${notes.map((note) => note.tone).join(' ')}',
];

List<int?> stringsOf(Score score) => [
  for (final item in score.measures[0].staves[0].voices.first.items)
    if (item case ChordEvent(:final notes))
      (notes.single as PitchedNote).string,
];

Score reloaded(Score score) =>
    scoreFromJson(jsonDecode(jsonEncode(scoreToJson(score))));

String saved(Score score) => jsonEncode(scoreToJson(score));

void main() {
  group('AddPart', () {
    test('adds a part at the bottom with a measure rest in every bar', () {
      final session = EditSession.start(blankScore());

      final score = edited(session, const AddPart(piano)).score;

      expect(names(score), ['Морин хуур', 'Piano']);
      expect(score.parts.last.staves.length, 2);
      expectStavesInOrder(score);
      for (final column in score.measures) {
        final added = column.staves.skip(1);
        expect(
          [for (final measure in added) measure.clef],
          [
            Clef.treble,
            Clef.bass,
          ],
        );
        expect(
          [
            for (final measure in added)
              describe(measure.voice(VoiceSlot.one)!.items),
          ],
          [
            ['measure-rest'],
            ['measure-rest'],
          ],
        );
        expect(
          identical(
            column.staves.first,
            session.score.column(column.id).staves.first,
          ),
          isTrue,
        );
      }
    });

    test('adds a part at an index with its name and instrument', () {
      final session = EditSession.start(
        blankScore(parts: const [piano, drums]),
      );

      final first = edited(session, const AddPart(violin, index: 0)).score;
      final middle = edited(session, const AddPart(clarinet, index: 1)).score;
      final last = edited(session, const AddPart(clarinet, index: 2)).score;

      expect(names(first), ['Violin', 'Piano', 'Drums']);
      expect(names(middle), ['Piano', 'Clarinet in B♭', 'Drums']);
      expect(names(last), ['Piano', 'Drums', 'Clarinet in B♭']);
      expect(first.parts.first.shortName, 'Vln.');
      expect(middle.parts[1].instrument, clarinet.instrument);
      expect(middle.measures.first.staves[2].clef, Clef.treble);
      expect(middle.measures.first.staves[3].clef, Clef.percussion);
      expectStavesInOrder(first);
      expectStavesInOrder(middle);
      expectStavesInOrder(last);
    });

    test('fills a short bar', () {
      final session = edited(
        blank(),
        SetBarLength(idOf(blank(), 0), len(1, 4)),
      );

      final score = edited(session, const AddPart(violin)).score;

      final rest =
          score.measures.first.staves.last.voice(VoiceSlot.one)!.items.single
              as MeasureRest;
      expect(rest.span, len(1, 4));
    });

    test('mints new ids for the part, its staves and its rests', () {
      final session = EditSession.start(blankScore(bars: 3));

      final twice = edited(
        edited(session, const AddPart(piano)),
        const AddPart(piano),
      ).score;

      final staves = [for (final staff in twice.staves) staff.id];
      expect(staves.toSet().length, 5);
      expect({for (final part in twice.parts) part.id}.length, 3);
      for (final (k, staff) in staves.indexed) {
        for (final column in twice.measures) {
          final rest =
              column.staves[k].voice(VoiceSlot.one)!.items.single
                  as MeasureRest;
          expect(twice.locate(rest.id)?.staff, staff);
        }
      }
    });

    test('keeps the cursor and the selection', () {
      final score = blankScore(parts: const [morinKhuur, piano]);
      final session = withCursor(score, 1).select(
        RangeSelection(
          from: pointAt(score, 0, Moment.zero),
          to: pointAt(score, 1, Moment.zero),
          top: score.staves[0].id,
          bottom: score.staves[2].id,
        ),
      );

      final next = edited(session, const AddPart(violin, index: 1));

      expect(next.cursor, session.cursor);
      expect(identical(next.selection, session.selection), isTrue);
    });

    test('refuses a place outside the parts or a malformed template', () {
      final session = EditSession.start(blankScore());

      for (final edit in [
        const AddPart(violin, index: -1),
        const AddPart(violin, index: 2),
        AddPart(
          PartTemplate(name: 'None', instrument: violin.instrument, staves: 0),
        ),
        AddPart(
          PartTemplate(
            name: 'Organ',
            instrument: violin.instrument,
            staves: 3,
            clefs: const [Clef.treble, Clef.bass],
          ),
        ),
      ]) {
        expect(refusal(session.run(edit)), isA<InvalidValue>());
      }
    });
  });

  group('RemovePart', () {
    test('removes its staves from every bar, with their spanners', () {
      var score = blankScore(parts: const [morinKhuur, piano]);
      for (final staff in [0, 1, 2]) {
        score = withSlur(
          score,
          pointAt(score, 0, Moment.zero),
          pointAt(score, 1, Moment.zero),
          staff: staff,
        );
      }
      final session = EditSession.start(score);

      final next = edited(session, RemovePart(score.parts[1].id)).score;

      expect(names(next), ['Морин хуур']);
      expectStavesInOrder(next);
      expect([for (final s in next.spanners) s.staff], [score.staves[0].id]);
      for (final column in next.measures) {
        expect(
          identical(
            column.staves.single,
            score.column(column.id).staves.first,
          ),
          isTrue,
        );
      }
    });

    test('moves a cursor on it to the nearest shown staff', () {
      final score = hidePart(
        hidePart(
          blankScore(parts: const [piano, morinKhuur, clarinet, piano]),
          1,
        ),
        2,
      );

      final below = edited(
        withCursor(score, 0),
        RemovePart(score.parts[0].id),
      );
      final above = edited(
        withCursor(score, 5),
        RemovePart(score.parts[3].id),
      );
      final elsewhere = edited(
        withCursor(score, 0),
        RemovePart(score.parts[3].id),
      );

      expect(below.cursor.staff, score.staves[4].id);
      expect(above.cursor.staff, score.staves[1].id);
      expect(
        (below.cursor.voice, below.cursor.at),
        (
          VoiceSlot.two,
          pointAt(score, 1, at(1, 4)),
        ),
      );
      expect(elsewhere.cursor, withCursor(score, 0).cursor);
    });

    test('drops a selection on it', () {
      final score = blankScore(parts: const [morinKhuur, piano]);
      final session = EditSession.start(score).select(
        RangeSelection(
          from: pointAt(score, 0, Moment.zero),
          to: pointAt(score, 1, Moment.zero),
          top: score.staves[0].id,
          bottom: score.staves[1].id,
        ),
      );

      final next = edited(session, RemovePart(score.parts[1].id));

      expect(next.selection.isEmpty, isTrue);
    });

    test('refuses the last shown part or a stale part', () {
      final score = hidePart(blankScore(parts: const [morinKhuur, piano]), 1);
      final session = EditSession.start(score);

      expect(
        refusal(
          EditSession.start(blankScore()).run(RemovePart(score.parts[0].id)),
        ),
        isA<WouldEmptyScore>(),
      );
      expect(
        refusal(session.run(RemovePart(score.parts[0].id))),
        isA<WouldEmptyScore>(),
      );
      expect(names(edited(session, RemovePart(score.parts[1].id)).score), [
        'Морин хуур',
      ]);
      expect(
        refusal(session.run(const RemovePart(PartId(999)))),
        isA<StaleReference>(),
      );
    });
  });

  group('SetPartHidden', () {
    test('hides and shows a part and keeps the rest of it', () {
      final score = blankScore(parts: const [morinKhuur, violin]);
      final session = EditSession.start(score);

      final hidden = edited(
        session,
        SetPartHidden(score.parts[1].id, hidden: true),
      );
      final shown = edited(
        hidden,
        SetPartHidden(score.parts[1].id, hidden: false),
      );

      final part = hidden.score.parts[1];
      expect(part.hidden, isTrue);
      expect(shown.score.parts[1].hidden, isFalse);
      expect(
        (part.id, part.name, part.shortName),
        (
          score.parts[1].id,
          'Violin',
          'Vln.',
        ),
      );
      expect(identical(part.instrument, score.parts[1].instrument), isTrue);
      expect(identical(part.staves, score.parts[1].staves), isTrue);
      expect(identical(hidden.score.parts[0], score.parts[0]), isTrue);
      expect(identical(hidden.score.measures, score.measures), isTrue);
      expect(hidden.undoLabel, 'Hide instrument');
      expect(shown.undoLabel, 'Show instrument');
    });

    test('changes nothing when the part already is so', () {
      final score = hidePart(blankScore(parts: const [morinKhuur, piano]), 1);
      final session = EditSession.start(score);

      expect(
        changesNothing(session, SetPartHidden(score.parts[1].id, hidden: true)),
        isTrue,
      );
      expect(
        changesNothing(
          session,
          SetPartHidden(score.parts[0].id, hidden: false),
        ),
        isTrue,
      );
    });

    test('moves a cursor off a part it hides', () {
      final score = blankScore(parts: const [morinKhuur, piano]);

      final hidden = edited(
        withCursor(score, 2),
        SetPartHidden(score.parts[1].id, hidden: true),
      );
      final other = edited(
        withCursor(score, 0),
        SetPartHidden(score.parts[1].id, hidden: true),
      );
      final shown = edited(
        EditSession.start(
          hidePart(score, 1),
        ).placeCursor(withCursor(score, 2).cursor),
        SetPartHidden(score.parts[1].id, hidden: false),
      );

      expect(cursorOf(hidden), (0, 1, at(1, 4), VoiceSlot.two));
      expect(cursorOf(other), (0, 1, at(1, 4), VoiceSlot.two));
      expect(cursorOf(shown), (2, 1, at(1, 4), VoiceSlot.two));
    });

    test('refuses hiding the last shown part or a stale part', () {
      final score = hidePart(blankScore(parts: const [morinKhuur, piano]), 1);
      final session = EditSession.start(score);

      expect(
        refusal(session.run(SetPartHidden(score.parts[0].id, hidden: true))),
        isA<WouldEmptyScore>(),
      );
      expect(
        refusal(session.run(const SetPartHidden(PartId(999), hidden: true))),
        isA<StaleReference>(),
      );
    });
  });

  group('SetInstrument', () {
    test('turns a khuur part into a piano part and back', () {
      final khuur = fill(blankScore(), 0, [
        chord(1, const Pitch(Step.f, 3), NoteValue.half),
        chord(2, const Pitch(Step.c, 4), NoteValue.half),
      ]);
      final session = applied(
        EditSession.start(khuur).run(
          SetClef(
            staff: khuur.staves[0].id,
            at: pointAt(khuur, 0, at(1, 2)),
            clef: Clef.bass,
          ),
        ),
      );
      final part = khuur.parts[0].id;

      final asPiano = edited(session, SetInstrument(part, piano));
      final back = edited(asPiano, SetInstrument(part, morinKhuur));

      final score = asPiano.score;
      expect(asPiano.undoLabel, 'Change instrument');
      expect(
        (score.parts.single.id, score.parts.single.name),
        (part, 'Piano'),
      );
      expect(score.parts.single.instrument.key, 'piano');
      expect(score.staves.first.id, khuur.staves[0].id);
      expectStavesInOrder(score);
      for (final column in score.measures) {
        expect(
          [for (final measure in column.staves) measure.clef],
          [Clef.treble, Clef.bass],
        );
        expect(column.staves.every((m) => m.clefChanges.isEmpty), isTrue);
        expect(
          [for (final v in column.staves[1].voices) ...v.items],
          [isA<MeasureRest>()],
        );
      }
      expect(soundOf(score, 0), soundOf(khuur, 0));
      expect(back.score.staves.map((s) => s.id), [khuur.staves[0].id]);
      expect(back.score.parts.single.name, 'Морин хуур');
      expect(soundOf(back.score, 0), soundOf(khuur, 0));
      expect(back.score.measures.first.staves.single.clef, Clef.treble);
    });

    test('keeps a string mark on the string tuned the same', () {
      final score = fill(
        blankScore(parts: const [strung]),
        0,
        [
          onString(1, const Pitch(Step.a, 4), 1),
          onString(2, const Pitch(Step.a, 4), 2),
          onString(3, const Pitch(Step.e, 5), 3),
          onString(4, const Pitch(Step.e, 5), null),
        ],
      );

      final next = edited(
        EditSession.start(score),
        SetInstrument(score.parts[0].id, viola),
      ).score;

      expect(stringsOf(next), [2, 3, null, null]);
      expect(next.measures.first.staves.single.clef, Clef.alto);
    });

    test('clears a cello string the khuur lacks, so the piece loads', () {
      final score = fill(blankScore(parts: const [cello]), 0, [
        onString(1, const Pitch(Step.c, 2), 0),
        onString(2, const Pitch(Step.a, 3), 3),
        onString(3, const Pitch(Step.f, 3), 2),
        onString(4, const Pitch(Step.b, 3, Alter.flat), 3),
      ]);

      final next = edited(
        EditSession.start(score),
        SetInstrument(score.parts[0].id, morinKhuur),
      ).score;

      expect(stringsOf(next), [null, null, null, null]);
      expect(stringsOf(reloaded(next)), [null, null, null, null]);
      expect(saved(reloaded(next)), saved(next));
    });

    test('drops the music and spanners of a dropped staff', () {
      var score = fill(
        blankScore(parts: const [piano, violin]),
        0,
        [chord(1, const Pitch(Step.c, 3), NoteValue.whole)],
        staff: 1,
      );
      for (final staff in [0, 1, 2]) {
        score = withSlur(
          score,
          pointAt(score, 0, Moment.zero),
          pointAt(score, 1, Moment.zero),
          staff: staff,
          voice: VoiceSlot.one,
        );
      }

      final next = edited(
        withCursor(score, 1),
        SetInstrument(score.parts[0].id, morinKhuur),
      );

      expect(next.score.staves.map((s) => s.id), [
        score.staves[0].id,
        score.staves[2].id,
      ]);
      expectStavesInOrder(next.score);
      expect(
        [for (final s in next.score.spanners) s.staff],
        [
          score.staves[0].id,
          score.staves[2].id,
        ],
      );
      expect(
        [
          for (final column in next.score.measures)
            for (final measure in column.staves)
              for (final voice in measure.voices) ...voice.items,
        ].whereType<ChordEvent>(),
        isEmpty,
      );
      expect(cursorOf(next), (0, 1, at(1, 4), VoiceSlot.two));
      expect(saved(reloaded(next.score)), saved(next.score));
    });

    test('undoes to the old score', () {
      final score = fill(blankScore(parts: const [cello]), 0, [
        for (var i = 1; i <= 4; i++) onString(i, const Pitch(Step.c, 2), 0),
      ]);
      final session = EditSession.start(score);

      final next = edited(session, SetInstrument(score.parts[0].id, piano));

      expect(saved(next.undo().score), saved(score));
    });

    test('refuses a swap with a drum kit, a missing drum or a gone part', () {
      final pitched = EditSession.start(blankScore());
      final kit = applied(
        EditSession.start(blankScore(parts: const [drums])).run(
          EnterNote(
            at: point(blankScore(parts: const [drums]), 0, Moment.zero),
            tone: snare,
            value: NoteValue.quarter,
          ),
        ),
      );
      const noSnare = PartTemplate(
        name: 'Toms',
        instrument: Instrument(
          key: 'toms',
          program: 0,
          bank: 128,
          clef: Clef.percussion,
          drums: [
            DrumSound(name: 'Tom', position: Pitch(Step.e, 5), midiKey: 45),
          ],
        ),
      );
      String refused(EditSession session, PartTemplate template) => (refusal(
        session.run(
          SetInstrument(session.score.parts[0].id, template),
        ),
      ) as InvalidValue).message;

      expect(
        refused(pitched, drums),
        'a drum kit and a pitched instrument do not swap',
      );
      expect(
        refused(kit, piano),
        'a drum kit and a pitched instrument do not swap',
      );
      expect(refused(kit, noSnare), 'the kit has no Snare');
      expect(
        refused(
          pitched,
          const PartTemplate(name: 'x', instrument: fiddle, staves: 0),
        ),
        'a part needs a staff and a clef each',
      );
      expect(
        refusal(pitched.run(const SetInstrument(PartId(999), piano))),
        isA<StaleReference>(),
      );
    });
  });
}
