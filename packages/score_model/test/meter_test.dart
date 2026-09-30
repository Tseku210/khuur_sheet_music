import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

List<List<String>> bars(Score score, {int staff = 0}) => [
  for (final column in score.measures)
    describe(column.staves[staff].voice(VoiceSlot.one)!.items),
];

/// [score] with bar [bar] blank under [meter].
Score withMeter(Score score, int bar, Meter meter) => changeBar(
  score,
  bar,
  (c) => c.copyWith(
    meter: meter,
    staves: Seq([
      for (final s in c.staves)
        s.copyWith(
          voices: Seq([
            Voice(
              slot: VoiceSlot.one,
              items: Seq([
                MeasureRest(
                  id: (s.voices.first.items.first as Event).id,
                  span: meter.length,
                ),
              ]),
            ),
          ]),
        ),
    ]),
  ),
);

/// [score] with bar [bar] [length] long, holding [items].
Score irregular(Score score, int bar, Length length, List<VoiceItem> items) =>
    changeBar(
      score,
      bar,
      (c) => c.copyWith(
        irregularLength: () => length,
        staves: Seq([
          c.staves.first.copyWith(
            voices: Seq([Voice(slot: VoiceSlot.one, items: Seq(items))]),
          ),
        ]),
      ),
    );

EditSession rebarred(EditSession session, Meter meter, {int from = 0}) =>
    applied(session.run(SetMeter(from: idOf(session, from), meter: meter)));

final threeEight = Meter.simple(3, 8);
final fiveFour = Meter.simple(5, 4);

EditSession eightQuarters() => sessionWith([
  [chordOf(20, 'F4'), chordOf(21, 'G4'), chordOf(22, 'A4'), chordOf(23, 'B4')],
  [chordOf(30, 'C5'), chordOf(31, 'D5'), chordOf(32, 'E5'), chordOf(33, 'F5')],
]);

EditSession twoWholes() => sessionWith([
  [chordOf(20, 'F4', value: NoteValue.whole)],
  [chordOf(30, 'G4', value: NoteValue.whole)],
]);

void main() {
  group('SetMeter re-bars', () {
    test('lays the music end to end and cuts it into bars of the new '
        'length', () {
      final session = eightQuarters();
      final before = barIds(session.score);

      final next = rebarred(session, Meter.threeFour);

      final score = next.score;
      expect(bars(score), [
        ['F4/quarter', 'G4/quarter', 'A4/quarter'],
        ['B4/quarter', 'C5/quarter', 'D5/quarter'],
        ['E5/quarter', 'F5/quarter', 'rest/quarter'],
      ]);
      expect(
        [for (final c in score.measures) c.meter],
        [
          for (var i = 0; i < 3; i++) Meter.threeFour,
        ],
      );
      final after = barIds(score);
      expect(after.take(2), before);
      expect(before, isNot(contains(after[2])));
      expect(eventRef(next, 23).measure, after[1]);
      expect(eventRef(next, 32).measure, after[2]);
      expect([
        for (final c in score.measures) c.staves.first.clefChanges,
      ], everyElement(isEmpty));
    });

    test('splits and ties a note that crosses a new barline', () {
      final session = sessionWith([
        [
          chordOf(20, 'F4', value: NoteValue.half),
          chordOf(21, 'G4', value: NoteValue.half),
        ],
      ]);

      final next = rebarred(session, Meter.threeFour);

      expect(bars(next.score), [
        ['F4/half', 'G4/quarter~'],
        ['G4/quarter', 'rest/quarter', 'rest/quarter'],
      ]);
      expect(eventRef(next, 21).measure, idOf(session, 0));
      expect(chordIn(next, 21).notes.single.id, const NoteId(210));
    });

    test('splits a long note at every barline it crosses', () {
      final session = sessionWith([
        [chordOf(20, 'F4', value: NoteValue.whole)],
      ]);

      final next = rebarred(session, threeEight);

      expect(bars(next.score), [
        ['F4/quarter.~'],
        ['F4/quarter.~'],
        ['F4/quarter', 'rest/eighth'],
      ]);
    });

    test('drops trailing rests instead of making bars for them', () {
      final score = fill(blankScore(bars: 3), 0, [
        chordOf(20, 'F4'),
        rest(21, NoteValue.quarter),
        rest(22, NoteValue.half),
      ]);
      final session = EditSession.start(score);

      final next = rebarred(session, Meter.twoFour);

      expect(bars(next.score), [
        ['F4/quarter', 'rest/quarter'],
        ['measure-rest'],
        ['measure-rest'],
      ]);
      expect(barIds(next.score), barIds(score));
      expect(voiceOf(next.score, 2).items.single.span, len(1, 2));
    });

    test('never takes bars away from a section', () {
      final session = sessionWith([
        [chordOf(20, 'F4', value: NoteValue.whole)],
        [chordOf(30, 'G4', value: NoteValue.whole)],
        [rest(40, NoteValue.whole)],
      ]);

      final next = rebarred(session, fiveFour);

      expect(bars(next.score), [
        ['F4/whole', 'G4/quarter~'],
        ['G4/half.', 'rest/quarter', 'rest/quarter'],
        ['measure-rest'],
      ]);
      expect(barIds(next.score), barIds(session.score));
    });

    test('turns a measure rest between notes into rests', () {
      final session = sessionWith([
        [chordOf(20, 'F4', value: NoteValue.whole)],
        [rest(30, NoteValue.whole)],
        [chordOf(40, 'G4', value: NoteValue.whole)],
      ]);
      final blank = changeBar(
        session.score,
        1,
        (c) => c.withStaff(
          c.staves.first.copyWith(
            voices: Seq([
              Voice(
                slot: VoiceSlot.one,
                items: Seq([
                  const MeasureRest(
                    id: EventId(30),
                    span: Length.whole,
                    articulations: {Articulation.fermata},
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
      final start = EditSession.start(blank);

      final threeFour = rebarred(start, Meter.threeFour);
      final twoFour = rebarred(start, Meter.twoFour);

      expect(bars(threeFour.score), [
        ['F4/half.~'],
        ['F4/quarter', 'rest/quarter', 'rest/quarter'],
        ['rest/half', 'G4/quarter~'],
        ['G4/half.'],
      ]);
      expect(eventRef(threeFour, 30).measure, threeFour.score.measures[1].id);
      expect(eventOf(threeFour, 30).articulations, {Articulation.fermata});
      expect(bars(twoFour.score), [
        ['F4/half~'],
        ['F4/half'],
        ['measure-rest'],
        ['measure-rest'],
        ['G4/half~'],
        ['G4/half'],
      ]);
      expect(eventRef(twoFour, 30).measure, twoFour.score.measures[2].id);
      expect(eventOf(twoFour, 30).articulations, {Articulation.fermata});
      expect(eventOf(twoFour, 30), isA<MeasureRest>());
    });

    test('keeps a rest that carries a fermata', () {
      final held = sessionWith([
        [
          chordOf(20, 'F4', value: NoteValue.half),
          const RestEvent(
            id: EventId(21),
            value: NoteValue.half,
            articulations: {Articulation.fermata},
          ),
        ],
      ]);
      final plain = sessionWith([
        [chordOf(20, 'F4', value: NoteValue.half), rest(21, NoteValue.half)],
      ]);

      expect(bars(rebarred(held, Meter.twoFour).score), [
        ['F4/half'],
        ['rest/half'],
      ]);
      expect(bars(rebarred(plain, Meter.twoFour).score), [
        ['F4/half'],
      ]);
    });

    test('keeps every piece of a hidden rest hidden', () {
      final session = sessionWith([
        [
          chordOf(20, 'F4', value: NoteValue.half),
          const RestEvent(id: EventId(21), value: NoteValue.half, hidden: true),
        ],
        [chordOf(30, 'G4', value: NoteValue.whole)],
      ]);

      final next = rebarred(session, Meter.threeFour).score;

      expect(bar(next, 0), ['F4/half', 'rest/quarter']);
      expect(bar(next, 1).first, 'rest/quarter');
      expect(
        [
          for (final b in [0, 1])
            [
              for (final item in voiceOf(next, b).items)
                if (item is RestEvent) item.hidden,
            ],
        ],
        [
          [true],
          [true],
        ],
      );
    });

    test('re-bars a second voice and pads it with a gap', () {
      final score = fill(
        twoWholes().score,
        0,
        [Gap(len(1, 2)), chordOf(40, 'C4', value: NoteValue.half)],
        slot: VoiceSlot.two,
      );

      final next = rebarred(EditSession.start(score), Meter.threeFour).score;

      expect(bar(next, 0, slot: VoiceSlot.two), ['gap 1/2', 'C4/quarter~']);
      expect(bar(next, 1, slot: VoiceSlot.two), ['C4/quarter', 'gap 1/2']);
      expect(next.measures[2].staves.first.voice(VoiceSlot.two), isNull);
    });

    test('keeps a second voice\'s time through a bar that lacks it', () {
      final score = fill(twoWholes().score, 1, [
        chordOf(40, 'D4', value: NoteValue.whole),
      ], slot: VoiceSlot.two);

      final next = rebarred(EditSession.start(score), Meter.threeFour).score;

      expect(next.measures[0].staves.first.voice(VoiceSlot.two), isNull);
      expect(bar(next, 1, slot: VoiceSlot.two), [
        'gap 1/4',
        'D4/quarter~',
        'D4/quarter~',
      ]);
      expect(bar(next, 2, slot: VoiceSlot.two), ['D4/half', 'gap 1/4']);
    });

    test('merges the gaps that meet in a new bar', () {
      var score = fill(twoWholes().score, 0, [
        chordOf(40, 'C4'),
        Gap(len(3, 4)),
      ], slot: VoiceSlot.two);
      score = fill(score, 1, [
        Gap(len(1, 4)),
        chordOf(50, 'D4', value: NoteValue.half.dotted),
      ], slot: VoiceSlot.two);

      final next = rebarred(EditSession.start(score), Meter.threeFour).score;

      expect(bar(next, 0, slot: VoiceSlot.two), ['C4/quarter', 'gap 1/2']);
      expect(bar(next, 1, slot: VoiceSlot.two), ['gap 1/2', 'D4/quarter~']);
      expect(bar(next, 2, slot: VoiceSlot.two), ['D4/half', 'gap 1/4']);
    });

    test('drops a trailing gap like a trailing rest', () {
      final score = fill(
        sessionWith([
          [chordOf(20, 'F4', value: NoteValue.half), rest(21, NoteValue.half)],
        ]).score,
        0,
        [chordOf(40, 'C4'), Gap(len(3, 4))],
        slot: VoiceSlot.two,
      );

      final next = rebarred(EditSession.start(score), Meter.twoFour).score;

      expect(bars(next), [
        ['F4/half'],
      ]);
      expect(bar(next, 0, slot: VoiceSlot.two), ['C4/quarter', 'gap 1/4']);
    });

    test('gives every staff the same bars', () {
      final score = fill(blankScore(parts: const [piano], bars: 1), 0, [
        chordOf(20, 'F4', value: NoteValue.whole),
      ]);

      final next = rebarred(EditSession.start(score), Meter.threeFour).score;

      expect(bars(next), [
        ['F4/half.~'],
        ['F4/quarter', 'rest/quarter', 'rest/quarter'],
      ]);
      expect(bars(next, staff: 1), [
        ['measure-rest'],
        ['measure-rest'],
      ]);
      expect(
        [for (final c in next.measures) c.staves[1].clef],
        [
          Clef.bass,
          Clef.bass,
        ],
      );
    });

    test('refuses to cut a tuplet with a new barline', () {
      final triplet = tripletOfEighths(40, [
        chordOf(41, 'G4', value: NoteValue.eighth),
        chordOf(42, 'A4', value: NoteValue.eighth),
        chordOf(43, 'B4', value: NoteValue.eighth),
      ]);
      final cut = sessionWith([
        [chordOf(20, 'F4'), triplet, rest(50, NoteValue.half)],
      ]);
      final whole = sessionWith([
        [
          chordOf(20, 'F4', value: NoteValue.half),
          triplet,
          rest(50, NoteValue.quarter),
        ],
      ]);

      expect(
        refusal(
          cut.run(SetMeter(from: idOf(cut, 0), meter: threeEight)),
        ),
        isA<WouldSplitTuplet>()
            .having((r) => r.tuplet, 'tuplet', const TupletId(40))
            .having((r) => r.measure, 'measure', idOf(cut, 0)),
      );
      expect(bars(rebarred(whole, Meter.threeFour).score), [
        ['F4/half', '3:2[G4/eighth, A4/eighth, B4/eighth]'],
      ]);
    });

    test('stops at the next bar with a different meter', () {
      var score = withMeter(blankScore(bars: 4), 3, Meter.twoFour);
      score = fill(score, 0, [chordOf(20, 'F4', value: NoteValue.whole)]);
      score = fill(score, 1, [chordOf(30, 'G4', value: NoteValue.whole)]);
      score = fill(score, 2, [chordOf(40, 'A4', value: NoteValue.whole)]);
      final session = EditSession.start(score);

      final next = rebarred(session, Meter.threeFour, from: 1).score;

      expect(
        [for (final c in next.measures) c.meter],
        [
          Meter.fourFour,
          Meter.threeFour,
          Meter.threeFour,
          Meter.threeFour,
          Meter.twoFour,
        ],
      );
      expect(bars(next).sublist(1, 4), [
        ['G4/half.~'],
        ['G4/quarter', 'A4/quarter~', 'A4/quarter~'],
        ['A4/half', 'rest/quarter'],
      ]);
      expect(identical(next.measures[0], score.measures[0]), isTrue);
      expect(identical(next.measures[4], score.measures[3]), isTrue);
    });

    test('changes nothing for the meter the bar already has', () {
      final session = twoWholes();

      for (final content in MeterContent.values) {
        expect(
          changesNothing(
            session,
            SetMeter(
              from: idOf(session, 0),
              meter: Meter.fourFour,
              content: content,
            ),
          ),
          isTrue,
          reason: content.name,
        );
      }
    });

    test('only sets a meter of the same length', () {
      final session = twoWholes();

      for (final content in MeterContent.values) {
        final next = applied(
          session.run(
            SetMeter(
              from: idOf(session, 0),
              meter: Meter.cut,
              content: content,
            ),
          ),
        ).score;

        expect(barIds(next), barIds(session.score), reason: content.name);
        for (var i = 0; i < 2; i++) {
          expect(next.measures[i].meter, Meter.cut, reason: content.name);
          expect(
            identical(
              next.measures[i].staves,
              session.score.measures[i].staves,
            ),
            isTrue,
            reason: content.name,
          );
        }
      }
    });

    test('refuses a bar that is gone', () {
      expect(
        refusal(
          blank().run(
            const SetMeter(from: MeasureId(999), meter: Meter.threeFour),
          ),
        ),
        isA<StaleReference>(),
      );
    });
  });

  group('SetMeter sections', () {
    final base = twoWholes().score;
    final cases =
        <
          String,
          (
            MeasureColumn Function(MeasureColumn column),
            int bar,
            bool Function(MeasureColumn column) holds,
            List<int> where,
          )
        >{
          'a start repeat': (
            (c) => c.copyWith(repeatStart: true),
            1,
            (c) => c.repeatStart,
            [2],
          ),
          'a key change': (
            (c) => c.copyWith(key: const KeySignature(1)),
            1,
            (c) => c.key == const KeySignature(1),
            [2, 3],
          ),
          'an ending': (
            (c) => c.copyWith(volta: () => const Volta([2])),
            1,
            (c) => c.volta == const Volta([2]),
            [2, 3],
          ),
          'a rehearsal mark': (
            (c) => c.copyWith(rehearsal: () => 'B'),
            1,
            (c) => c.rehearsal == 'B',
            [2],
          ),
          'a segno': (
            (c) => c.copyWith(navigation: Seq(const [Segno()])),
            1,
            (c) => c.navigation.contains(const Segno()),
            [2],
          ),
          'a coda': (
            (c) => c.copyWith(navigation: Seq(const [Coda()])),
            1,
            (c) => c.navigation.contains(const Coda()),
            [2],
          ),
          'an end repeat': (
            (c) => c.copyWith(repeatEnd: () => const RepeatEnd()),
            0,
            (c) => c.repeatEnd != null,
            [1],
          ),
          'a double barline': (
            (c) => c.copyWith(barline: Barline.doubleBar),
            0,
            (c) => c.barline == Barline.doubleBar,
            [1],
          ),
          'a dashed barline': (
            (c) => c.copyWith(barline: Barline.dashed),
            0,
            (c) => c.barline == Barline.dashed,
            [1],
          ),
          'a fine': (
            (c) => c.copyWith(navigation: Seq(const [Fine()])),
            0,
            (c) => c.navigation.contains(const Fine()),
            [1],
          ),
          'a to coda': (
            (c) => c.copyWith(navigation: Seq(const [ToCoda()])),
            0,
            (c) => c.navigation.contains(const ToCoda()),
            [1],
          ),
          'a jump': (
            (c) => c.copyWith(navigation: Seq(const [Jump(JumpTarget.start)])),
            0,
            (c) => c.navigation.contains(const Jump(JumpTarget.start)),
            [1],
          ),
        };

    test('re-bar across a plain barline', () {
      final next = rebarred(EditSession.start(base), Meter.threeFour).score;

      expect(bars(next), [
        ['F4/half.~'],
        ['F4/quarter', 'G4/quarter~', 'G4/quarter~'],
        ['G4/half', 'rest/quarter'],
      ]);
    });

    for (final MapEntry(key: name, value: (change, bar, holds, where))
        in cases.entries) {
      test('end at $name, which stays on its barline', () {
        final score = changeBar(base, bar, change);

        final next = rebarred(EditSession.start(score), Meter.threeFour).score;

        expect(bars(next), [
          ['F4/half.~'],
          ['F4/quarter', 'rest/quarter', 'rest/quarter'],
          ['G4/half.~'],
          ['G4/quarter', 'rest/quarter', 'rest/quarter'],
        ]);
        expect([
          for (final (i, c) in next.measures.indexed)
            if (holds(c)) i,
        ], where);
        expect(barIds(next)[2], score.measures[1].id);
      });
    }

    test('keep a pickup or other irregular bar as it is', () {
      var score = irregular(blankScore(bars: 3), 0, len(1, 4), [
        chordOf(20, 'F4'),
      ]);
      score = fill(score, 1, [chordOf(30, 'G4', value: NoteValue.whole)]);
      score = irregular(score, 2, len(3, 4), [
        chordOf(40, 'A4', value: NoteValue.half.dotted),
      ]);

      final next = rebarred(EditSession.start(score), Meter.threeFour).score;

      expect(bars(next), [
        ['F4/quarter'],
        ['G4/half.~'],
        ['G4/quarter', 'rest/quarter', 'rest/quarter'],
        ['A4/half.'],
      ]);
      expect(
        [for (final c in next.measures) c.irregularLength],
        [
          len(1, 4),
          null,
          null,
          null,
        ],
      );
      expect(
        [for (final c in next.measures) c.meter],
        [
          for (var i = 0; i < 4; i++) Meter.threeFour,
        ],
      );
      expect(
        identical(next.measures[0].staves, score.measures[0].staves),
        isTrue,
      );
      expect(barIds(next).last, score.measures[2].id);
    });
  });

  group('SetMeter marks', () {
    test('move with the music to the bar that now holds their time', () {
      var score = eightQuarters().score;
      score = changeBar(
        score,
        0,
        (c) => c.withStaff(
          c.staves.first.copyWith(
            clefChanges: Seq([ClefChange(at(1, 2), Clef.alto)]),
            directions: Seq([const DynamicMark(Moment.zero, Dynamic.p)]),
          ),
        ),
      );
      score = changeBar(
        score,
        1,
        (c) => c
            .copyWith(
              tempos: Seq([
                TempoMark(
                  offset: at(1, 4),
                  tempo: const Tempo(60),
                  text: 'Adagio',
                  showMetronome: false,
                ),
              ]),
            )
            .withStaff(
              c.staves.first.copyWith(
                clef: Clef.bass,
                directions: Seq([
                  DynamicMark(at(1, 2), Dynamic.mf),
                  ChordSymbol(
                    at(3, 4),
                    root: const PitchName(Step.d),
                    quality: 'm',
                    bass: const PitchName(Step.a),
                  ),
                ]),
              ),
            ),
      );
      score = withSlur(
        score,
        pointAt(score, 0, at(3, 4)),
        pointAt(score, 1, at(1, 2)),
      );

      final next = rebarred(EditSession.start(score), Meter.threeFour).score;

      final columns = next.measures;
      expect(
        [
          for (final c in columns) [for (final t in c.tempos) t.offset],
        ],
        [
          [Moment.zero],
          [at(1, 2)],
          <Moment>[],
        ],
      );
      expect(
        identical(columns[0].tempos.single, score.measures[0].tempos.single),
        isTrue,
      );
      expect(
        identical(
          columns[0].staves.first.directions.single,
          score.measures[0].staves.first.directions.single,
        ),
        isTrue,
      );
      final tempo = columns[1].tempos.single;
      expect(
        (tempo.tempo, tempo.text, tempo.showMetronome),
        (const Tempo(60), 'Adagio', false),
      );
      expect(
        [
          for (final c in columns) c.staves.first.directions.map(mark),
        ],
        [
          ['0 p'],
          <String>[],
          ['0 mf', '1/4 dm/a'],
        ],
      );
      expect(
        [for (final c in columns) c.staves.first.clef],
        [
          Clef.treble,
          Clef.alto,
          Clef.bass,
        ],
      );
      expect(
        [
          for (final c in columns)
            [for (final k in c.staves.first.clefChanges) (k.offset, k.clef)],
        ],
        [
          [(at(1, 2), Clef.alto)],
          [(at(1, 4), Clef.bass)],
          <(Moment, Clef)>[],
        ],
      );
      final slur = next.spanners.single;
      expect(slur.first, pointAt(next, 1, Moment.zero));
      expect(slur.last, pointAt(next, 2, Moment.zero));
    });

    test('are dropped with time that is no longer there', () {
      var score = withMeter(blankScore(bars: 3), 2, Meter.threeFour);
      score = fill(score, 0, [
        chordOf(20, 'F4'),
        rest(21, NoteValue.quarter),
        rest(22, NoteValue.half),
      ]);
      score = changeBar(
        score,
        0,
        (c) => c.withStaff(
          c.staves.first.copyWith(
            directions: Seq([TextMark(at(3, 4), 'a', above: false)]),
          ),
        ),
      );
      score = changeBar(
        score,
        1,
        (c) => c
            .copyWith(
              tempos: Seq([
                TempoMark(offset: at(1, 2), tempo: const Tempo(60)),
              ]),
            )
            .withStaff(
              c.staves.first.copyWith(
                clef: Clef.bass,
                directions: Seq([const TextMark(Moment.zero, 'b')]),
              ),
            ),
      );
      for (final (first, last) in [
        (pointAt(score, 0, Moment.zero), pointAt(score, 1, at(1, 2))),
        (pointAt(score, 1, at(1, 2)), pointAt(score, 2, at(1, 4))),
        (pointAt(score, 1, Moment.zero), pointAt(score, 1, at(1, 2))),
      ]) {
        score = withSlur(score, first, last);
      }

      final next = rebarred(EditSession.start(score), Meter.twoFour).score;

      final columns = next.measures;
      expect(bars(next).take(2), [
        ['F4/quarter', 'rest/quarter'],
        ['measure-rest'],
      ]);
      expect(columns[1].tempos, isEmpty);
      expect(
        [
          for (final c in columns.take(2)) c.staves.first.directions.map(mark),
        ],
        [
          <String>[],
          ['1/4 a below'],
        ],
      );
      expect(
        [for (final c in columns) c.staves.first.clef],
        [
          Clef.treble,
          Clef.treble,
          Clef.treble,
        ],
      );
      expect([for (final s in next.spanners) s.id.value], [900, 901]);
      expect(
        [next.spanners[0].first, next.spanners[0].last],
        [pointAt(next, 0, Moment.zero), pointAt(next, 1, Moment.zero)],
      );
      expect(
        [next.spanners[1].first, next.spanners[1].last],
        [pointAt(next, 2, Moment.zero), pointAt(next, 2, at(1, 4))],
      );
    });
  });

  group('SetMeter ties', () {
    /// Bar 0 holds [items] in 4/4. Bar 1 is in [meter] and holds an F4
    /// [value] long.
    Score before(Meter meter, NoteValue value, List<VoiceItem> items) => fill(
      fill(withMeter(blankScore(), 1, meter), 0, items),
      1,
      [chordOf(30, 'F4', value: value)],
    );
    Score beforeThreeFour(List<VoiceItem> items) =>
        before(Meter.threeFour, NoteValue.half.dotted, items);

    test('clear a let-ring tie that now meets the same note', () {
      final score = beforeThreeFour([
        chordOf(20, 'F4 A4', value: NoteValue.half, tie: true),
        rest(21, NoteValue.half),
      ]);

      final next = rebarred(EditSession.start(score), Meter.twoFour);

      expect(bars(next.score).first, ['F4+A4/half~']);
      expect(tiesOf(next, 20), {'F4': false, 'A4': true});
    });

    test('clear a tie that now meets rests', () {
      final score = beforeThreeFour([
        chordOf(20, 'G4', value: NoteValue.half),
        chordOf(21, 'F4', value: NoteValue.half, tie: true),
      ]);

      final next = rebarred(EditSession.start(score), Meter.threeFour);

      expect(bars(next.score), [
        ['G4/half', 'F4/quarter~'],
        ['F4/quarter', 'rest/quarter', 'rest/quarter'],
        ['F4/half.'],
      ]);
    });

    test('keep a let-ring tie that still meets rests', () {
      final score = beforeThreeFour([
        chordOf(20, 'F4', value: NoteValue.half, tie: true),
        rest(21, NoteValue.half),
      ]);

      final next = rebarred(EditSession.start(score), Meter.threeFour);

      expect(bars(next.score).first, ['F4/half~', 'rest/quarter']);
    });

    test('keep a tie that still meets its note', () {
      final score = before(Meter.twoFour, NoteValue.half, [
        chordOf(20, 'G4', value: NoteValue.half),
        chordOf(21, 'F4', value: NoteValue.half, tie: true),
      ]);

      final next = rebarred(EditSession.start(score), Meter.twoFour);

      expect(bars(next.score), [
        ['G4/half'],
        ['F4/half~'],
        ['F4/half'],
      ]);
    });

    test('clear the tie on a tuplet\'s last note', () {
      final score = beforeThreeFour([
        chordOf(20, 'G4', value: NoteValue.half.dotted),
        tripletOfEighths(40, [
          chordOf(41, 'A4', value: NoteValue.eighth),
          chordOf(42, 'B4', value: NoteValue.eighth),
          chordOf(43, 'F4', value: NoteValue.eighth, tie: true),
        ]),
      ]);

      final next = rebarred(EditSession.start(score), Meter.threeFour);

      expect(bars(next.score), [
        ['G4/half.'],
        [
          '3:2[A4/eighth, B4/eighth, F4/eighth]',
          'rest/quarter',
          'rest/quarter',
        ],
        ['F4/half.'],
      ]);
    });
  });

  group('SetMeter keeping bars', () {
    EditOutcome keep(EditSession session, Meter meter, {int from = 0}) =>
        session.run(
          SetMeter(
            from: idOf(session, from),
            meter: meter,
            content: MeterContent.keepBars,
          ),
        );

    test('pads each bar where it is', () {
      final session = EditSession.start(
        fill(blankScore(), 0, [
          chordOf(20, 'F4', value: NoteValue.half),
          rest(21, NoteValue.half),
        ]),
      );

      final next = applied(keep(session, Meter.threeFour)).score;

      expect(bars(next), [
        ['F4/half', 'rest/quarter'],
        ['measure-rest'],
      ]);
      expect(barIds(next), barIds(session.score));
      expect(voiceOf(next, 1).items.single.span, len(3, 4));
    });

    test('fits music that fills the new bar exactly', () {
      final session = EditSession.start(
        fill(blankScore(), 0, [
          chordOf(20, 'F4', value: NoteValue.half.dotted),
          rest(21, NoteValue.quarter),
        ]),
      );

      final next = applied(keep(session, Meter.threeFour)).score;

      expect(bars(next), [
        ['F4/half.'],
        ['measure-rest'],
      ]);
    });

    test('refuses a bar that no longer fits', () {
      final session = twoWholes();

      expect(
        refusal(keep(session, Meter.threeFour)),
        isA<WouldCrossBarline>()
            .having((r) => r.measure, 'measure', idOf(session, 0))
            .having((r) => r.excess, 'excess', len(1, 4)),
      );
    });

    test('lengthens bars and clears a tie that now meets rests', () {
      final session = sessionWith([
        [chordOf(20, 'F4', value: NoteValue.whole, tie: true)],
        [chordOf(30, 'F4', value: NoteValue.whole)],
      ]);

      final next = applied(keep(session, fiveFour));

      expect(bars(next.score), [
        ['F4/whole', 'rest/quarter'],
        ['F4/whole', 'rest/quarter'],
      ]);
      expect(tiesOf(next, 20), {'F4': false});
    });
  });

  group('SetMeter cursor', () {
    test('follows the music, and so does a range', () {
      final start = eightQuarters();
      final staff = start.score.staves.first.id;
      final session = start
          .placeCursor(point(start.score, 1, at(1, 2)))
          .select(
            RangeSelection(
              from: pointAt(start.score, 0, at(1, 4)),
              to: pointAt(start.score, 1, at(3, 4)),
              top: staff,
              bottom: staff,
            ),
          );

      final next = rebarred(session, Meter.threeFour);

      expect(next.cursor.at, pointAt(next.score, 2, Moment.zero));
      final range = next.selection as RangeSelection;
      expect(range.from, pointAt(next.score, 0, at(1, 4)));
      expect(range.to, pointAt(next.score, 2, at(1, 4)));
    });

    test('leaves what comes before the changed bars where it is', () {
      final start = eightQuarters();
      final score = withSlur(
        start.score,
        pointAt(start.score, 0, Moment.zero),
        pointAt(start.score, 0, at(1, 2)),
      );
      final staff = score.staves.first.id;
      final session = EditSession.start(score)
          .placeCursor(point(score, 0, at(1, 4)))
          .select(
            RangeSelection(
              from: pointAt(score, 0, Moment.zero),
              to: pointAt(score, 0, at(1, 2)),
              top: staff,
              bottom: staff,
            ),
          );

      final next = rebarred(session, Meter.threeFour, from: 1);

      expect(next.score.measures.length, 3);
      expect(next.cursor.at, pointAt(score, 0, at(1, 4)));
      final range = next.selection as RangeSelection;
      expect(
        (range.from, range.to),
        (pointAt(score, 0, Moment.zero), pointAt(score, 0, at(1, 2))),
      );
      expect(identical(next.score.spanners, score.spanners), isTrue);
    });

    group('in time that is no longer there', () {
      final start = EditSession.start(
        fill(withMeter(blankScore(), 1, Meter.threeFour), 0, [
          chordOf(20, 'F4'),
          rest(21, NoteValue.quarter),
          rest(22, NoteValue.half),
        ]),
      );
      final staff = start.score.staves.first.id;
      RangeSelection range(Moment from, Moment to) => RangeSelection(
        from: pointAt(start.score, 0, from),
        to: pointAt(start.score, 0, to),
        top: staff,
        bottom: staff,
      );

      test('the cursor moves to the next bar', () {
        final next = rebarred(
          start.placeCursor(point(start.score, 0, at(3, 4))),
          Meter.twoFour,
        );

        expect(bars(next.score).first, ['F4/quarter', 'rest/quarter']);
        expect(next.cursor.at, pointAt(next.score, 1, Moment.zero));
      });

      test('a range ends where the bars now end', () {
        final next = rebarred(
          start.select(range(at(1, 4), at(3, 4))),
          Meter.twoFour,
        );

        final selected = next.selection as RangeSelection;
        expect(selected.from, pointAt(next.score, 0, at(1, 4)));
        expect(selected.to, pointAt(next.score, 0, at(1, 2)));
      });

      test('a range wholly inside it is dropped', () {
        final next = rebarred(
          start.select(range(at(1, 2), at(3, 4))),
          Meter.twoFour,
        );

        expect(next.selection, const Selection.none());
      });
    });
  });
}
