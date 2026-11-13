import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

List<String> marksIn(Score score, int bar) => [
  for (final d in score.measures[bar].staves.first.directions) mark(d),
];

EditOutcome setDirections(
  Score score,
  int bar,
  List<StaffDirection> directions,
) => EditSession.start(score).run(
  SetDirections(
    staff: score.staves.first.id,
    measure: score.measures[bar].id,
    directions: Seq(directions),
  ),
);

EditOutcome addSpanner(
  Score score,
  SpannerKind kind,
  ScorePoint first,
  ScorePoint last, {
  VoiceSlot? voice,
}) => EditSession.start(score).run(
  AddSpanner(
    kind: kind,
    staff: score.staves.first.id,
    first: first,
    last: last,
    voice: voice,
  ),
);

void main() {
  group('SetDirections', () {
    test('replaces the directions, in time order', () {
      final score = blankScore(parts: const [piano]);

      final next = applied(
        setDirections(score, 1, [
          TextMark(at(1, 2), 'b'),
          const DynamicMark(Moment.zero, Dynamic.p),
          TextMark(at(1, 2), 'a', above: false),
        ]),
      ).score;

      expect(marksIn(next, 1), ['0 p', '1/2 b', '1/2 a below']);
      expect(identical(next.measures[0], score.measures[0]), isTrue);
      expect(
        identical(next.measures[1].staves[1], score.measures[1].staves[1]),
        isTrue,
      );
    });

    test('changes nothing for equal directions', () {
      List<StaffDirection> marks() => [
        DynamicMark(at(0, 4), Dynamic.p),
        ChordSymbol(
          at(1, 4),
          root: const PitchName(Step.d),
          quality: 'm',
          bass: const PitchName(Step.a),
        ),
        TextMark(at(1, 2), 'dolce', above: false),
      ];
      final score = applied(setDirections(blankScore(), 0, marks())).score;

      final outcome = setDirections(score, 0, marks());

      expect(identical(applied(outcome).score, score), isTrue);
    });

    test('replaces a direction that differs in one field', () {
      final chord = ChordSymbol(
        at(1, 4),
        root: const PitchName(Step.d),
        quality: 'm',
        bass: const PitchName(Step.a),
      );
      final dynamic = DynamicMark(at(1, 4), Dynamic.p);
      final text = TextMark(at(1, 4), 'dolce');
      for (final (before, after) in <(StaffDirection, StaffDirection)>[
        (dynamic, DynamicMark(at(1, 2), Dynamic.p)),
        (dynamic, DynamicMark(at(1, 4), Dynamic.f)),
        (text, TextMark(at(1, 4), 'cresc.')),
        (text, TextMark(at(1, 4), 'dolce', above: false)),
        (text, TextMark(at(1, 2), 'dolce')),
        (
          chord,
          ChordSymbol(
            at(1, 2),
            root: const PitchName(Step.d),
            quality: 'm',
            bass: const PitchName(Step.a),
          ),
        ),
        (
          chord,
          ChordSymbol(
            at(1, 4),
            root: const PitchName(Step.e),
            quality: 'm',
            bass: const PitchName(Step.a),
          ),
        ),
        (
          chord,
          ChordSymbol(
            at(1, 4),
            root: const PitchName(Step.d),
            bass: const PitchName(Step.a),
          ),
        ),
        (
          chord,
          ChordSymbol(at(1, 4), root: const PitchName(Step.d), quality: 'm'),
        ),
        (text, dynamic),
      ]) {
        final score = applied(setDirections(blankScore(), 0, [before])).score;

        final next = applied(setDirections(score, 0, [after])).score;

        expect(marksIn(next, 0), [mark(after)], reason: mark(after));
      }
    });

    test('refuses a direction outside the bar', () {
      final score = blankScore(meter: Meter.threeFour);

      expect(
        refusal(setDirections(score, 0, [TextMark(at(3, 4), 'a')])),
        isA<OutsideMeasure>().having(
          (r) => r.at,
          'at',
          pointAt(score, 0, at(3, 4)),
        ),
      );
      expect(
        refusal(
          setDirections(score, 0, [TextMark(Moment(Fraction(-1, 4)), 'a')]),
        ),
        isA<OutsideMeasure>(),
      );
    });

    test('refuses a bar or staff that is gone', () {
      final score = blankScore();
      final session = EditSession.start(score);

      expect(
        refusal(
          session.run(
            SetDirections(
              staff: score.staves.first.id,
              measure: const MeasureId(999),
              directions: const Seq.empty(),
            ),
          ),
        ),
        isA<StaleReference>().having(
          (r) => r.target,
          'target',
          const MeasureId(999),
        ),
      );
      expect(
        refusal(
          session.run(
            SetDirections(
              staff: const StaffId(999),
              measure: score.measures.first.id,
              directions: const Seq.empty(),
            ),
          ),
        ),
        isA<StaleReference>().having(
          (r) => r.target,
          'target',
          const StaffId(999),
        ),
      );
    });
  });

  group('AddSpanner', () {
    test('adds the spanner with a fresh id', () {
      final score = withSlur(
        blankScore(bars: 3),
        pointAt(blankScore(bars: 3), 0, Moment.zero),
        pointAt(blankScore(bars: 3), 1, Moment.zero),
      );
      final first = pointAt(score, 0, at(1, 4));
      final last = pointAt(score, 2, at(1, 2));

      final next = applied(
        addSpanner(score, const Hairpin(crescendo: true), first, last),
      );

      final added = next.score.spanners.last;
      expect(next.score.spanners.length, 2);
      expect(added.id, isNot(score.spanners.single.id));
      expect(
        (added.kind, added.staff, added.first, added.last),
        (
          const Hairpin(crescendo: true),
          score.staves.first.id,
          first,
          last,
        ),
      );
      expect(identical(next.score.measures, score.measures), isTrue);
    });

    test('puts a slur in voice one unless it names a voice', () {
      final score = blankScore();
      final first = pointAt(score, 0, Moment.zero);
      final last = pointAt(score, 1, Moment.zero);

      final plain = applied(addSpanner(score, const Slur(), first, last));
      final second = applied(
        addSpanner(score, const Glissando(), first, last, voice: VoiceSlot.two),
      );

      expect(plain.score.spanners.single.voice, VoiceSlot.one);
      expect(second.score.spanners.single.voice, VoiceSlot.two);
    });

    test('puts a line or hairpin on the staff, in no voice', () {
      final score = blankScore();

      final next = applied(
        addSpanner(
          score,
          const Hairpin(crescendo: false),
          pointAt(score, 0, Moment.zero),
          pointAt(score, 1, Moment.zero),
          voice: VoiceSlot.two,
        ),
      );

      expect(next.score.spanners.single.voice, isNull);
    });

    test('lets a line cover one event, but not a slur', () {
      final score = blankScore();
      final point = pointAt(score, 0, at(1, 2));

      final line = applied(
        addSpanner(score, const OctaveLine(OctaveShift.up8), point, point),
      );

      expect(line.score.spanners.single.first, point);
      for (final kind in const [Slur(), Glissando()]) {
        expect(
          refusal(addSpanner(score, kind, point, point)),
          isA<InvalidValue>(),
        );
      }
    });

    test('names the kind whose ends it refuses', () {
      final score = blankScore();
      final half = pointAt(score, 0, at(1, 2));
      String refused(SpannerKind kind, ScorePoint last) => (refusal(
        addSpanner(score, kind, half, last),
      ) as InvalidValue).message;

      expect(
        [
          for (final kind in const [Slur(), Glissando()]) refused(kind, half),
        ],
        [
          'a slur must end after it starts',
          'a glissando must end after it starts',
        ],
      );
      expect(
        [
          for (final kind in const [
            Hairpin(crescendo: true),
            OctaveLine(OctaveShift.up8),
            TrillLine(),
            TempoLine(text: 'rit.', factor: 0.5),
            PedalLine(),
          ])
            refused(kind, pointAt(score, 0, Moment.zero)),
        ],
        [
          'a hairpin cannot end before it starts',
          'an octave line cannot end before it starts',
          'a trill line cannot end before it starts',
          'a tempo line cannot end before it starts',
          'a pedal line cannot end before it starts',
        ],
      );
    });

    test('refuses a slur or glissando inside one note', () {
      final score = fill(blankScore(), 0, [
        chordOf(100, 'C5', value: NoteValue.half),
        chordOf(101, 'D5', value: NoteValue.half),
      ]);
      final first = pointAt(score, 0, Moment.zero);
      final last = pointAt(score, 0, at(1, 4));

      for (final kind in const [Slur(), Glissando()]) {
        expect(
          refusal(addSpanner(score, kind, first, last)),
          isA<InvalidValue>(),
        );
      }
      expect(
        applied(addSpanner(score, const TrillLine(), first, last))
            .score
            .spanners,
        hasLength(1),
      );
    });

    test('lets a slur join two notes of its voice over one note in voice '
        'one', () {
      var score = fill(blankScore(), 0, [
        chordOf(100, 'C5', value: NoteValue.whole),
      ]);
      score = fill(score, 0, [
        chordOf(110, 'E4'),
        chordOf(111, 'F4'),
        chordOf(112, 'G4', value: NoteValue.half),
      ], slot: VoiceSlot.two);

      final next = applied(
        addSpanner(
          score,
          const Slur(),
          pointAt(score, 0, Moment.zero),
          pointAt(score, 0, at(1, 4)),
          voice: VoiceSlot.two,
        ),
      );

      expect(next.score.spanners.single.voice, VoiceSlot.two);
    });

    test('refuses ends in the wrong order', () {
      final score = blankScore();

      expect(
        refusal(
          addSpanner(
            score,
            const TrillLine(),
            pointAt(score, 1, Moment.zero),
            pointAt(score, 0, at(3, 4)),
          ),
        ),
        isA<InvalidValue>(),
      );
    });

    test('refuses a bar, staff or time that is not there', () {
      final score = blankScore(meter: Meter.threeFour);
      final here = pointAt(score, 0, Moment.zero);
      const gone = ScorePoint(MeasureId(999), Moment.zero);
      final late = pointAt(score, 1, at(3, 4));
      final session = EditSession.start(score);

      for (final (first, last) in [(gone, here), (here, gone)]) {
        expect(
          refusal(addSpanner(score, const PedalLine(), first, last)),
          isA<StaleReference>().having(
            (r) => r.target,
            'target',
            const MeasureId(999),
          ),
        );
      }
      expect(
        refusal(addSpanner(score, const PedalLine(), here, late)),
        isA<OutsideMeasure>().having((r) => r.at, 'at', late),
      );
      expect(
        refusal(
          session.run(
            AddSpanner(
              kind: const PedalLine(),
              staff: const StaffId(999),
              first: here,
              last: here,
            ),
          ),
        ),
        isA<StaleReference>().having(
          (r) => r.target,
          'target',
          const StaffId(999),
        ),
      );
    });
  });

  group('RemoveSpanner', () {
    test('removes the spanner and keeps the others', () {
      var score = blankScore();
      for (final bar in [0, 1]) {
        score = fill(score, bar, [
          for (var i = 0; i < 4; i++) chordOf(100 + 10 * bar + i, 'C5'),
        ]);
      }
      for (final (first, last) in [
        (pointAt(score, 0, Moment.zero), pointAt(score, 0, at(1, 2))),
        (pointAt(score, 0, at(1, 2)), pointAt(score, 0, at(3, 4))),
        (pointAt(score, 1, Moment.zero), pointAt(score, 1, at(1, 2))),
      ]) {
        score = withSlur(score, first, last);
      }

      final next = applied(
        EditSession.start(score).run(const RemoveSpanner(SpannerId(901))),
      ).score;

      expect([for (final s in next.spanners) s.id.value], [900, 902]);
      expect(identical(next.spanners.last, score.spanners.last), isTrue);
    });

    test('refuses a spanner that is gone', () {
      expect(
        refusal(
          EditSession.start(
            blankScore(),
          ).run(const RemoveSpanner(SpannerId(900))),
        ),
        isA<StaleReference>().having(
          (r) => r.target,
          'target',
          const SpannerId(900),
        ),
      );
    });
  });

  group('A spanner left on one event', () {
    test('goes when a longer note swallows a slur', () {
      var score = fill(blankScore(), 0, [
        for (var i = 0; i < 4; i++) chordOf(100 + i, 'C5'),
      ]);
      score = withSlur(
        score,
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(1, 4)),
      );
      final ref = EventRef(
        staff: score.staves.first.id,
        measure: score.measures.first.id,
        id: const EventId(100),
      );

      final next = applied(
        EditSession.start(score).run(SetValue(ref, NoteValue.half)),
      ).score;

      expect(next.spanners, isEmpty);
    });

    test('stays when it is a line and goes when it is a slur', () {
      var score = blankScore(bars: 4);
      final first = pointAt(score, 1, Moment.zero);
      final last = pointAt(score, 3, Moment.zero);
      score = withSlur(score, first, last);
      score = score.copyWith(
        spanners: score.spanners.append(
          Spanner(
            id: const SpannerId(950),
            kind: const Hairpin(crescendo: true),
            staff: score.staves.first.id,
            first: first,
            last: last,
          ),
        ),
      );
      final session = EditSession.start(score);

      final next = applied(
        session.run(DeleteMeasures(idOf(session, 1), idOf(session, 2))),
      ).score;

      final hairpin = next.spanners.single;
      expect(hairpin.id, const SpannerId(950));
      expect((hairpin.first, hairpin.last), (last, last));
    });
  });
}
