import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

const _ringingFile = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Flute</part-name></score-part></part-list>
  <part id="P1"><measure number="1">
    <attributes>
      <divisions>1</divisions>
      <key><fifths>0</fifths></key>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>G</sign><line>2</line></clef>
    </attributes>
    <note>
      <pitch><step>C</step><octave>4</octave></pitch>
      <duration>2</duration><voice>1</voice><type>half</type>
      <notations><tied type="let-ring"/></notations>
    </note>
    <note>
      <pitch><step>C</step><octave>4</octave></pitch>
      <duration>2</duration><voice>1</voice><type>half</type>
    </note>
  </measure></part>
</score-partwise>
''';

/// Two half notes of C4, events 20 and 21.
EditSession twoCs({bool tie = false, bool letRing = false}) => sessionWith([
  [
    chordOf(20, 'C4', value: NoteValue.half, tie: tie, letRing: letRing),
    chordOf(21, 'C4', value: NoteValue.half),
  ],
]);

NoteRef headOf(EditSession session, int id, [int index = 0]) =>
    NoteRef(eventRef(session, id), NoteId(id * 10 + index));

EditSession setRing(EditSession session, int id, {int index = 0}) => applied(
  session.run(SetLetRing(headOf(session, id, index), letRing: true)),
);

EditSession clearRing(EditSession session, int id) =>
    applied(session.run(SetLetRing(headOf(session, id), letRing: false)));

List<String> tiesIn(Score score) => [
  for (final TieView(:from, :to)
      in score.measureView(score.measures.first.id).staves.first.ties)
    '${from.value} -> ${to?.note.value}',
];

List<(int, double, double)> played(Score score) => [
  for (final note
      in PlaybackCompiler().compile(score).notesBetween(0, double.infinity))
    (note.key, note.start, note.duration),
];

void main() {
  group('SetLetRing', () {
    test('marks an untied note, which then lands on nothing', () {
      final next = setRing(twoCs(), 20);

      expect(bar(next.score, 0), ['C4/half~lv', 'C4/half']);
      expect(tiesIn(next.score), ['200 -> null']);
    });

    test('clears the mark and leaves the note untied', () {
      final next = clearRing(twoCs(letRing: true), 20);

      expect(bar(next.score, 0), ['C4/half', 'C4/half']);
      expect(tiesIn(next.score), isEmpty);
    });

    test('marks one head of a chord', () {
      final session = sessionWith([
        [
          chordOf(20, 'D4 F4', value: NoteValue.half),
          chordOf(21, 'D4 F4', value: NoteValue.half),
        ],
      ]);

      final next = setRing(session, 20, index: 1);

      expect(
        {for (final n in chordIn(next, 20).notes) '${n.tone}': n.letRing},
        {'D4': false, 'F4': true},
      );
    });

    test('marks a drum note', () {
      final session = EditSession.start(
        fill(blankScore(parts: const [drums]), 0, [
          hit(1, [snare], value: NoteValue.whole),
        ]),
      );
      final note = NoteRef(
        eventRef(session, 1),
        chordIn(session, 1).notes.single.id,
      );

      final next = applied(session.run(SetLetRing(note, letRing: true)));

      expect(chordIn(next, 1).notes.single.letRing, isTrue);
    });

    test('marks a note that a tie ends on, and that tie stays', () {
      final session = sessionWith([
        [
          chordOf(20, 'C4', tie: true),
          chordOf(21, 'C4'),
          chordOf(22, 'C4', value: NoteValue.half),
        ],
      ]);

      final next = setRing(session, 21);

      expect(tiesIn(next.score), ['200 -> 210', '210 -> null']);
      const written = ['C4/quarter~', 'C4/quarter~lv', 'C4/half'];
      expect(bar(next.score, 0), written);
      expect(bar(reloaded(next.score), 0), written);
      expect(bar(scoreFromMusicXml(scoreToMusicXml(next.score)), 0), written);
    });

    test('changes nothing when the note is already as asked', () {
      final ringing = twoCs(letRing: true);
      final plain = twoCs();

      expect(
        changesNothing(
          ringing,
          SetLetRing(headOf(ringing, 20), letRing: true),
        ),
        isTrue,
      );
      expect(
        changesNothing(plain, SetLetRing(headOf(plain, 20), letRing: false)),
        isTrue,
      );
    });

    test('is refused for a note that is gone', () {
      final session = twoCs();
      final gone = NoteRef(eventRef(session, 20), const NoteId(999));

      expect(
        refusal(session.run(SetLetRing(gone, letRing: true))),
        isA<StaleReference>(),
      );
    });

    group('on a note that already has a tie, as in MuseScore 4', () {
      final landing = twoCs(tie: true);
      final pending = sessionWith([
        [
          chordOf(20, 'C4', value: NoteValue.half, tie: true),
          chordOf(21, 'D4', value: NoteValue.half),
        ],
      ]);

      for (final (name, session) in [
        ('a tie that lands', landing),
        ('a pending tie', pending),
      ]) {
        for (final letRing in [true, false]) {
          test('${letRing ? 'set' : 'clear'} leaves $name', () {
            expect(
              changesNothing(
                session,
                SetLetRing(headOf(session, 20), letRing: letRing),
              ),
              isTrue,
            );
          });
        }
      }
    });

    group('history', () {
      test('undo and redo a set', () {
        final session = twoCs();
        final next = setRing(session, 20);

        expect(next.undoLabel, 'Add let-ring tie');
        expect(bar(next.undo().score, 0), ['C4/half', 'C4/half']);
        expect(bar(next.undo().redo().score, 0), ['C4/half~lv', 'C4/half']);
      });

      test('undo and redo a clear', () {
        final next = clearRing(twoCs(letRing: true), 20);

        expect(next.undoLabel, 'Remove let-ring tie');
        expect(bar(next.undo().score, 0), ['C4/half~lv', 'C4/half']);
        expect(bar(next.undo().redo().score, 0), ['C4/half', 'C4/half']);
      });

      test('an edit that changes nothing adds no undo step', () {
        final session = twoCs(tie: true);

        final next = applied(
          session.run(SetLetRing(headOf(session, 20), letRing: true)),
        );

        expect(next.canUndo, isFalse);
      });
    });

    group('round trips', () {
      final marked = setRing(twoCs(), 20);
      final cleared = clearRing(marked, 20);

      test('JSON keeps a set mark', () {
        final back = reloaded(marked.score);

        expect(bar(back, 0), ['C4/half~lv', 'C4/half']);
        expect(tiesIn(back), ['200 -> null']);
      });

      test('JSON keeps a cleared mark', () {
        final back = reloaded(cleared.score);

        expect(bar(back, 0), ['C4/half', 'C4/half']);
        expect(tiesIn(back), isEmpty);
      });

      test('MusicXML keeps a set mark', () {
        final xml = scoreToMusicXml(marked.score);
        final back = scoreFromMusicXml(xml);

        expect(xml, contains('<tied type="let-ring"/>'));
        expect(bar(back, 0), ['C4/half~lv', 'C4/half']);
        expect(tiesIn(back), hasLength(1));
        expect(played(back), played(marked.score));
      });

      test('MusicXML keeps a cleared mark', () {
        final xml = scoreToMusicXml(cleared.score);
        final back = scoreFromMusicXml(xml);

        expect(xml, isNot(contains('let-ring"/></notations>')));
        expect(bar(back, 0), ['C4/half', 'C4/half']);
        expect(tiesIn(back), isEmpty);
      });
    });

    test('plays as a let-ring tie read from a file', () {
      final edited = setRing(twoCs(), 20).score;
      final read = scoreFromMusicXml(_ringingFile.trim());

      expect(bar(read, 0), bar(edited, 0));
      expect(played(edited), hasLength(2));
      expect(played(edited), played(read));
    });
  });
}
