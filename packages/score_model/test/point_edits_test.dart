import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

final a4 = Pitch.parse('A4');

/// Head [index] of the chord [id], as `chordOf` numbers it.
NoteRef head(EditSession session, int id, [int index = 0]) =>
    NoteRef(eventRef(session, id), NoteId(id * 10 + index));

/// Built at run time, so equal lyrics are never the same object.
Lyric lyric(int verse, String text, {Syllabic syllabic = Syllabic.single}) =>
    Lyric(verse: verse, text: text, syllabic: syllabic);

void main() {
  group('RemoveNote', () {
    test('removes one head and keeps the chord', () {
      final session = sessionWith([
        [chordOf(20, 'D4 F4 A4', value: NoteValue.whole)],
      ]);

      final next = applied(session.run(RemoveNote(head(session, 20, 1))));

      expect(bar(next.score, 0), ['D4+A4/whole']);
      expect(chordIn(next, 20).notes.map((n) => n.id), [
        const NoteId(200),
        const NoteId(202),
      ]);
    });

    test('turns a lone head into a rest that keeps only a fermata', () {
      final session = sessionWith([
        [
          ChordEvent(
            id: const EventId(20),
            value: NoteValue.half,
            notes: Seq([Note(id: const NoteId(200), pitch: f4)]),
            articulations: const {Articulation.staccato, Articulation.fermata},
            ornament: Ornament.trill,
            bowing: Bowing.up,
            lyrics: Seq([lyric(1, 'хөг')]),
            graces: Seq([
              GraceChord(
                id: const EventId(30),
                kind: GraceKind.acciaccatura,
                value: NoteValue.eighth,
                notes: Seq([Note(id: const NoteId(300), pitch: g4)]),
              ),
            ]),
          ),
          rest(21, NoteValue.half),
        ],
      ]);

      final next = applied(session.run(RemoveNote(head(session, 20))));

      expect(bar(next.score, 0), ['rest/half', 'rest/half']);
      expect(eventOf(next, 20).articulations, {Articulation.fermata});
    });

    test('clears the tie into the removed head only', () {
      final session = sessionWith([
        [
          rest(20, NoteValue.half),
          rest(21, NoteValue.quarter),
          chordOf(22, 'D4 F4', tie: true),
        ],
        [
          chordOf(23, 'D4 F4'),
          rest(24, NoteValue.quarter),
          rest(25, NoteValue.half),
        ],
      ]);

      final next = applied(session.run(RemoveNote(head(session, 23, 1))));

      expect(tiesOf(next, 22), {'D4': true, 'F4': false});
      expect(bar(next.score, 1), ['D4/quarter', 'rest/quarter', 'rest/half']);
    });
  });

  group('SetPitch', () {
    test('moves a head and keeps the chord in pitch order', () {
      final session = sessionWith([
        [chordOf(20, 'D4 F4 A4', value: NoteValue.whole)],
      ]);

      final next = applied(
        session.run(SetPitch(head(session, 20, 1), Pitch.parse('B4'))),
      );

      expect(bar(next.score, 0), ['D4+A4+B4/whole']);
      expect(chordIn(next, 20).notes.last.id, const NoteId(201));
    });

    test('moves the whole tie chain across the barline', () {
      final session = sessionWith([
        [
          chordOf(20, 'F4'),
          chordOf(21, 'F4', tie: true),
          chordOf(22, 'F4', tie: true),
          chordOf(23, 'F4', tie: true),
        ],
        [
          chordOf(24, 'F4', tie: true),
          chordOf(25, 'F4'),
          chordOf(26, 'F4', value: NoteValue.half),
        ],
      ]);

      final next = applied(session.run(SetPitch(head(session, 22), g4)));

      expect(bar(next.score, 0), [
        'F4/quarter',
        'G4/quarter~',
        'G4/quarter~',
        'G4/quarter~',
      ]);
      expect(bar(next.score, 1), ['G4/quarter~', 'G4/quarter', 'F4/half']);
    });

    test('moves only the tied pitch of a chord chain', () {
      final session = sessionWith([
        [
          chordOf(20, 'D4 F4', value: NoteValue.half, tie: true),
          chordOf(21, 'D4 F4', value: NoteValue.half),
        ],
      ]);

      final next = applied(session.run(SetPitch(head(session, 21, 1), g4)));

      expect(bar(next.score, 0), ['D4+G4/half~', 'D4+G4/half']);
    });

    test('does not follow a tie across a gap', () {
      final session = EditSession.start(
        fill(
          blankScore(bars: 1),
          0,
          [
            chordOf(20, 'F4', tie: true),
            Gap(len(1, 4)),
            chordOf(21, 'F4', value: NoteValue.half),
          ],
          slot: VoiceSlot.two,
        ),
      );

      final first = applied(session.run(SetPitch(head(session, 20), g4)));
      final last = applied(session.run(SetPitch(head(session, 21), g4)));

      expect(bar(first.score, 0, slot: VoiceSlot.two), [
        'G4/quarter~',
        'gap 1/4',
        'F4/half',
      ]);
      expect(bar(last.score, 0, slot: VoiceSlot.two), [
        'F4/quarter~',
        'gap 1/4',
        'G4/half',
      ]);
    });

    test('refuses a pitch a chord in the chain already has', () {
      final session = sessionWith([
        [
          chordOf(20, 'F4', tie: true),
          chordOf(21, 'F4 G4'),
          rest(22, NoteValue.half),
        ],
      ]);

      expect(
        refusal(session.run(SetPitch(head(session, 20), g4))),
        isA<InvalidValue>(),
      );
      expect(
        refusal(session.run(SetPitch(head(session, 21), g4))),
        isA<InvalidValue>(),
      );
    });

    test('changes nothing for the pitch the head has', () {
      final session = sessionWith([
        [chordOf(20, 'F4', value: NoteValue.whole)],
      ]);

      expect(changesNothing(session, SetPitch(head(session, 20), f4)), isTrue);
    });
  });

  group('SetTie', () {
    test('sets and clears one head, and a re-set changes nothing', () {
      final session = sessionWith([
        [
          chordOf(20, 'D4 F4', value: NoteValue.half),
          chordOf(21, 'D4 F4', value: NoteValue.half),
        ],
      ]);

      final tied = applied(
        session.run(SetTie(head(session, 20, 1), tied: true)),
      );
      final untied = applied(
        tied.run(SetTie(head(tied, 20, 1), tied: false)),
      );

      expect(tiesOf(tied, 20), {'D4': false, 'F4': true});
      expect(tiesOf(untied, 20), {'D4': false, 'F4': false});
      expect(
        changesNothing(tied, SetTie(head(tied, 20, 1), tied: true)),
        isTrue,
      );
      expect(
        changesNothing(session, SetTie(head(session, 20, 1), tied: false)),
        isTrue,
      );
    });
  });

  group('AddGrace', () {
    test('adds a grace chord next to the principal with new ids', () {
      final session = sessionWith([
        [
          chordOf(
            20,
            'F4',
            value: NoteValue.whole,
            graces: [
              GraceChord(
                id: const EventId(30),
                kind: GraceKind.acciaccatura,
                value: NoteValue.eighth,
                notes: Seq([Note(id: const NoteId(300), pitch: g4)]),
              ),
            ],
          ),
        ],
      ]);

      final next = applied(
        session.run(
          AddGrace(
            event: eventRef(session, 20),
            pitch: a4,
            kind: GraceKind.appoggiatura,
            value: NoteValue.sixteenth,
          ),
        ),
      );

      final graces = chordIn(next, 20).graces;
      expect(graces.map((g) => g.notes.single.pitch), [g4, a4]);
      final added = graces.last;
      expect(added.kind, GraceKind.appoggiatura);
      expect(added.value, NoteValue.sixteenth);
      expect(added.id.value, greaterThan(300));
      expect(added.notes.single.id.value, greaterThan(300));
      expect(added.notes.single.id.value, isNot(added.id.value));
    });

    test('refuses a rest', () {
      final session = sessionWith([
        [rest(20, NoteValue.whole)],
      ]);

      expect(
        refusal(
          session.run(AddGrace(event: eventRef(session, 20), pitch: g4)),
        ),
        isA<InvalidValue>(),
      );
    });
  });

  group('SetArticulation', () {
    test('adds and removes in one bar, and a re-set changes nothing', () {
      final session = sessionWith([
        [chordOf(20, 'F4', value: NoteValue.whole)],
        [rest(21, NoteValue.whole)],
      ]);
      final ref = eventRef(session, 20);

      final accented = applied(
        session.run(SetArticulation(ref, Articulation.accent, present: true)),
      );
      final plain = applied(
        accented.run(SetArticulation(ref, Articulation.accent, present: false)),
      );

      expect(eventOf(accented, 20).articulations, {Articulation.accent});
      expect(eventOf(plain, 20).articulations, isEmpty);
      expect(
        identical(accented.score.measures[1], session.score.measures[1]),
        isTrue,
      );
      expect(
        changesNothing(
          accented,
          SetArticulation(ref, Articulation.accent, present: true),
        ),
        isTrue,
      );
      expect(
        changesNothing(
          session,
          SetArticulation(ref, Articulation.accent, present: false),
        ),
        isTrue,
      );
    });

    test('puts only a fermata on a rest', () {
      final session = sessionWith([
        [
          rest(20, NoteValue.half),
          const RestEvent(
            id: EventId(21),
            value: NoteValue.half,
            hidden: true,
          ),
        ],
        [MeasureRest(id: const EventId(22), span: len(1, 1))],
      ]);

      final held = applied(
        session.run(
          SetArticulation(
            eventRef(session, 21),
            Articulation.fermata,
            present: true,
          ),
        ),
      );
      final wholeBar = applied(
        session.run(
          SetArticulation(
            eventRef(session, 22),
            Articulation.fermata,
            present: true,
          ),
        ),
      );

      expect(
        eventOf(held, 21),
        isA<RestEvent>().having((r) => r.hidden, 'hidden', isTrue).having(
          (r) => r.articulations,
          'articulations',
          {
            Articulation.fermata,
          },
        ),
      );
      expect(bar(held.score, 0), ['rest/half', 'rest/half']);
      expect(
        eventOf(wholeBar, 22),
        isA<MeasureRest>().having((r) => r.articulations, 'articulations', {
          Articulation.fermata,
        }),
      );
      expect(
        refusal(
          session.run(
            SetArticulation(
              eventRef(session, 20),
              Articulation.staccato,
              present: true,
            ),
          ),
        ),
        isA<InvalidValue>(),
      );
      expect(
        changesNothing(
          session,
          SetArticulation(
            eventRef(session, 20),
            Articulation.staccato,
            present: false,
          ),
        ),
        isTrue,
      );
    });

    test('reaches an event inside a tuplet', () {
      final session = sessionWith([
        [
          tripletOfEighths(40, [
            chordOf(20, 'F4', value: NoteValue.eighth),
            chordOf(21, 'G4', value: NoteValue.eighth),
            chordOf(22, 'A4', value: NoteValue.eighth),
          ]),
          rest(23, NoteValue.quarter),
          rest(24, NoteValue.half),
        ],
      ]);

      final next = applied(
        session.run(
          SetArticulation(
            eventRef(session, 21),
            Articulation.staccato,
            present: true,
          ),
        ),
      );

      expect(eventOf(next, 21).articulations, {Articulation.staccato});
      expect(eventOf(next, 20).articulations, isEmpty);
    });
  });

  group('SetOrnament and SetBowing', () {
    final session = sessionWith([
      [
        chordOf(20, 'F4', value: NoteValue.half),
        rest(21, NoteValue.half),
      ],
    ]);
    final chord = eventRef(session, 20);
    final rested = eventRef(session, 21);

    test('set, replace and clear an ornament; a rest takes none', () {
      final trill = applied(session.run(SetOrnament(chord, Ornament.trill)));
      final mordent = applied(trill.run(SetOrnament(chord, Ornament.mordent)));
      final cleared = applied(mordent.run(SetOrnament(chord, null)));

      expect(chordIn(trill, 20).ornament, Ornament.trill);
      expect(chordIn(mordent, 20).ornament, Ornament.mordent);
      expect(chordIn(cleared, 20).ornament, isNull);
      expect(changesNothing(trill, SetOrnament(chord, Ornament.trill)), isTrue);
      expect(
        refusal(session.run(SetOrnament(rested, Ornament.trill))),
        isA<InvalidValue>(),
      );
      expect(changesNothing(session, SetOrnament(rested, null)), isTrue);
    });

    test('set, replace and clear a bowing; a rest takes none', () {
      final up = applied(session.run(SetBowing(chord, Bowing.up)));
      final down = applied(up.run(SetBowing(chord, Bowing.down)));
      final cleared = applied(down.run(SetBowing(chord, null)));

      expect(chordIn(up, 20).bowing, Bowing.up);
      expect(chordIn(down, 20).bowing, Bowing.down);
      expect(chordIn(cleared, 20).bowing, isNull);
      expect(changesNothing(up, SetBowing(chord, Bowing.up)), isTrue);
      expect(
        refusal(session.run(SetBowing(rested, Bowing.up))),
        isA<InvalidValue>(),
      );
      expect(changesNothing(session, SetBowing(rested, null)), isTrue);
    });
  });

  group('Note marks', () {
    final session = sessionWith([
      [chordOf(20, 'D4 F4', value: NoteValue.whole)],
    ]);
    final upper = head(session, 20, 1);

    Note upperOf(EditSession session) => chordIn(session, 20).notes.last;

    test('sets and clears a fingering; a negative finger is refused', () {
      final fingered = applied(session.run(SetFingering(upper, 0)));
      final cleared = applied(fingered.run(SetFingering(upper, null)));

      expect(upperOf(fingered).fingering, 0);
      expect(chordIn(fingered, 20).notes.first.fingering, isNull);
      expect(upperOf(cleared).fingering, isNull);
      expect(changesNothing(fingered, SetFingering(upper, 0)), isTrue);
      expect(
        refusal(session.run(SetFingering(upper, -1))),
        isA<InvalidValue>(),
      );
    });

    test('takes only a string the instrument has', () {
      final inner = applied(session.run(SetString(upper, 1)));
      final cleared = applied(inner.run(SetString(upper, null)));

      expect(upperOf(inner).string, 1);
      expect(upperOf(cleared).string, isNull);
      expect(changesNothing(inner, SetString(upper, 1)), isTrue);
      for (final string in [-1, 2]) {
        expect(
          refusal(session.run(SetString(upper, string))),
          isA<InvalidValue>(),
          reason: '$string',
        );
      }
    });

    test('sets an accidental request', () {
      final shown = applied(
        session.run(SetAccidental(upper, AccidentalRequest.cautionary)),
      );

      expect(upperOf(shown).accidental, AccidentalRequest.cautionary);
      expect(
        changesNothing(
          shown,
          SetAccidental(upper, AccidentalRequest.cautionary),
        ),
        isTrue,
      );
      expect(
        changesNothing(session, SetAccidental(upper, AccidentalRequest.auto)),
        isTrue,
      );
    });
  });

  group('SetLyric', () {
    List<String> lyricsOf(EditSession session) => [
      for (final l in chordIn(session, 20).lyrics)
        '${l.verse} ${l.text} ${l.syllabic.name}',
    ];

    test('keeps one lyric per verse, in verse order', () {
      final session = sessionWith([
        [chordOf(20, 'F4', value: NoteValue.whole)],
      ]);
      final ref = eventRef(session, 20);

      var next = applied(session.run(SetLyric(ref, 2, lyric(2, 'нар'))));
      next = applied(next.run(SetLyric(ref, 1, lyric(1, 'сар'))));
      final bothVerses = lyricsOf(next);
      next = applied(
        next.run(SetLyric(ref, 2, lyric(2, 'ус', syllabic: Syllabic.begin))),
      );
      final cleared = applied(next.run(SetLyric(ref, 1, null)));

      expect(bothVerses, ['1 сар single', '2 нар single']);
      expect(lyricsOf(next), ['1 сар single', '2 ус begin']);
      expect(lyricsOf(cleared), ['2 ус begin']);
      expect(
        changesNothing(
          next,
          SetLyric(ref, 2, lyric(2, 'ус', syllabic: Syllabic.begin)),
        ),
        isTrue,
      );
      expect(changesNothing(cleared, SetLyric(ref, 1, null)), isTrue);
    });

    test('refuses a verse that does not match, verse 0 and a rest', () {
      final session = sessionWith([
        [
          chordOf(20, 'F4', value: NoteValue.half),
          rest(21, NoteValue.half),
        ],
      ]);
      final chord = eventRef(session, 20);

      for (final edit in [
        SetLyric(chord, 1, lyric(2, 'нар')),
        SetLyric(chord, 0, lyric(0, 'нар')),
        SetLyric(chord, 0, null),
        SetLyric(eventRef(session, 21), 1, lyric(1, 'нар')),
      ]) {
        expect(refusal(session.run(edit)), isA<InvalidValue>());
      }
      expect(
        changesNothing(session, SetLyric(eventRef(session, 21), 1, null)),
        isTrue,
      );
    });
  });

  test('every point edit refuses a head or event that is gone', () {
    final session = sessionWith([
      [
        chordOf(20, 'F4', value: NoteValue.half),
        rest(21, NoteValue.half),
      ],
    ]);
    final gone = EventRef(
      measure: session.score.measures.first.id,
      staff: session.score.staves.first.id,
      id: const EventId(99),
    );
    final heads = [
      NoteRef(gone, const NoteId(990)),
      NoteRef(eventRef(session, 20), const NoteId(299)),
      NoteRef(eventRef(session, 21), const NoteId(210)),
    ];

    for (final edit in [
      for (final note in heads) ...[
        RemoveNote(note),
        SetPitch(note, g4),
        SetTie(note, tied: true),
        SetFingering(note, 1),
        SetString(note, 0),
        SetAccidental(note, AccidentalRequest.always),
      ],
      AddGrace(event: gone, pitch: g4),
      SetArticulation(gone, Articulation.accent, present: true),
      SetOrnament(gone, Ornament.trill),
      SetBowing(gone, Bowing.up),
      SetLyric(gone, 1, lyric(1, 'нар')),
    ]) {
      expect(
        refusal(session.run(edit)),
        isA<StaleReference>(),
        reason: edit.label,
      );
    }
  });
}
