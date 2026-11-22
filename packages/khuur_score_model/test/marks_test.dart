import 'dart:math';

import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'random_edits.dart';
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

    test('refuses a glissando that names a note its chord lacks', () {
      final score = fill(blankScore(), 0, [
        chordOf(1, 'C4 G4'),
        chordOf(2, 'D4 C5'),
        chordOf(3, 'C4', value: NoteValue.half),
      ]);
      final first = pointAt(score, 0, Moment.zero);
      final last = pointAt(score, 0, at(1, 4));

      final joined = applied(
        addSpanner(
          score,
          const Glissando(from: NoteId(10), to: NoteId(21)),
          first,
          last,
        ),
      );

      expect(
        joined.score.spanners.single.kind,
        const Glissando(from: NoteId(10), to: NoteId(21)),
      );
      for (final kind in const [
        Glissando(from: NoteId(20)),
        Glissando(to: NoteId(10)),
      ]) {
        expect(
          refusal(addSpanner(score, kind, first, last)),
          isA<StaleReference>(),
        );
      }
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

  group('A glissando whose note is gone', () {
    const line = Glissando(from: NoteId(11), to: NoteId(20));

    EditSession glided({
      Glissando kind = line,
      String first = 'C4 G4',
      String second = 'D4 C5',
    }) {
      final score = fill(blankScore(), 0, [
        chordOf(1, first),
        chordOf(2, second),
        chordOf(3, 'C4', value: NoteValue.half),
      ]);
      return EditSession.start(
        withSpanner(
          score,
          kind,
          pointAt(score, 0, Moment.zero),
          pointAt(score, 0, at(1, 4)),
          voice: VoiceSlot.one,
        ),
      );
    }

    NoteRef head(EditSession session, int note) =>
        NoteRef(eventRef(session, note ~/ 10), NoteId(note));

    test('goes with the note it starts on, and undo brings both back', () {
      final session = glided();

      final next = applied(session.run(RemoveNote(head(session, 11))));

      expect(bar(next.score, 0).first, 'C4/quarter');
      expect(next.score.spanners, isEmpty);
      expect(next.undo().score.spanners.single.kind, line);
      expect(bar(next.undo().score, 0).first, 'C4+G4/quarter');
      expect(next.undo().redo().score.spanners, isEmpty);
    });

    test('goes with the note it ends on', () {
      final session = glided();

      final next = applied(session.run(RemoveNote(head(session, 20))));

      expect(next.score.spanners, isEmpty);
    });

    test('stays when another note of its chord goes', () {
      final session = glided();

      final next = applied(
        session.run(
          Batch([RemoveNote(head(session, 10)), RemoveNote(head(session, 21))]),
        ),
      );

      expect(next.score.spanners.single.kind, line);
      final (:from, :to) = next.score.glissandoNotes(
        next.score.spanners.single,
      );
      expect((from!.id, to!.id), (const NoteId(11), const NoteId(20)));
    });

    test('goes when its chord becomes a rest', () {
      final session = glided(
        kind: const Glissando(from: NoteId(10), to: NoteId(20)),
        first: 'G4',
      );

      final next = applied(session.run(RemoveNote(head(session, 10))));

      expect(bar(next.score, 0).first, 'rest/quarter');
      expect(next.score.spanners, isEmpty);
    });

    test('goes when a new note replaces its chord', () {
      final session = glided();

      final next = enterAt(session, 0, Moment.zero, tone: g4);

      expect(bar(next.score, 0).first, 'G4/quarter');
      expect(next.score.spanners, isEmpty);
    });

    test('does not move to a note added in the same batch', () {
      final session = glided();

      final next = applied(
        session.run(
          Batch([
            RemoveNote(head(session, 11)),
            AddToChord(event: eventRef(session, 1), tone: g4),
          ]),
        ),
      );

      expect(bar(next.score, 0).first, 'C4+G4/quarter');
      expect(next.score.spanners, isEmpty);
    });

    test('goes with its note in the scores the edits make', () {
      Set<NoteId> notesOf(Score score) => {
        for (final staff in score.staves)
          for (final slot in VoiceSlot.values)
            for (final timed in score.laneOf(staff.id, slot))
              if (timed.event case ChordEvent(:final notes))
                for (final note in notes) note.id,
      };
      Score lined() {
        var score = blankScore(parts: const [morinKhuur, clarinet], bars: 4);
        for (var bar = 0; bar < 4; bar++) {
          final id = 1000 + bar * 10;
          score = fill(score, bar, [
            chordOf(id, 'C4 G4'),
            chordOf(id + 1, 'D4 C5'),
            chordOf(id + 2, 'E4', value: NoteValue.half),
          ]);
          score = withSpanner(
            score,
            Glissando(
              from: NoteId(id * 10 + bar % 2),
              to: NoteId((id + 1) * 10 + bar ~/ 2),
            ),
            pointAt(score, bar, Moment.zero),
            pointAt(score, bar, at(1, 4)),
            voice: VoiceSlot.one,
          );
        }
        return score;
      }

      Score withoutNamedNote(Score score, Random random) {
        final named = [
          for (final spanner in score.spanners)
            if (spanner.kind case Glissando(:final from, :final to))
              for (final (id, end) in [
                (from, spanner.first),
                (to, spanner.last),
              ])
                if (id != null)
                  NoteRef(
                    score.anchorAt(spanner.staff, spanner.voice!, end)!.ref,
                    id,
                  ),
        ];
        return named.isEmpty
            ? score
            : edited(score, RemoveNote(pick(random, named)));
      }

      var removed = 0;
      var gone = 0;
      for (var seed = 0; seed < 100; seed++) {
        final random = Random(seed);
        var score = lined();
        for (var step = 0; step < 60; step++) {
          final removes = step % 20 == 19;
          final next = removes
              ? withoutNamedNote(score, random)
              : randomEdit(score, random);
          final kept = {for (final spanner in next.spanners) spanner.id};
          final notes = notesOf(next);
          for (final spanner in score.spanners) {
            if (spanner.kind case Glissando(:final from, :final to)
                when !kept.contains(spanner.id) &&
                    [?from, ?to].any((id) => !notes.contains(id))) {
              removes ? removed++ : gone++;
            }
          }
          score = next;
        }
      }

      expect(removed, greaterThan(100), reason: 'by RemoveNote');
      expect(gone, greaterThan(100), reason: 'by the other edits');
    });

    test('stays on the top note when it names none', () {
      final session = glided(kind: const Glissando(to: NoteId(20)));

      final next = applied(session.run(RemoveNote(head(session, 11))));

      expect(
        next.score.glissandoNotes(next.score.spanners.single).from!.id,
        const NoteId(10),
      );
    });
  });
}
