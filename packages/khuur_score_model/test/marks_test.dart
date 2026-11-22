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

    group('a glissando between two voices', () {
      final score = fill(
        fill(
          fill(blankScore(), 0, [
            chordOf(1, 'D5', value: NoteValue.half),
            chordOf(4, 'G5', value: NoteValue.half),
          ]),
          0,
          [chordOf(2, 'E4'), chordOf(3, 'F4'), rest(7, NoteValue.half)],
          slot: VoiceSlot.two,
        ),
        1,
        [chordOf(5, 'A5', value: NoteValue.whole)],
      );
      EditOutcome glide(
        int from,
        int to,
        ScorePoint first,
        ScorePoint last,
      ) => addSpanner(
        score,
        Glissando(from: NoteId(from), to: NoteId(to)),
        first,
        last,
        voice: VoiceSlot.two,
      );

      test('is refused when the note it ends on starts before the note it '
          'starts on', () {
        final outcome = glide(
          30,
          10,
          pointAt(score, 0, at(1, 4)),
          pointAt(score, 0, at(3, 8)),
        );

        expect(
          refusal(outcome),
          isA<InvalidValue>().having(
            (refused) => refused.message,
            'message',
            'a glissando must end after it starts',
          ),
        );
      });

      test('is refused when its two notes start together', () {
        final outcome = glide(
          20,
          10,
          pointAt(score, 0, Moment.zero),
          pointAt(score, 0, at(1, 4)),
        );

        expect(refusal(outcome), isA<InvalidValue>());
      });

      test('is refused when the one note it names starts after the chord it '
          'ends on', () {
        final held = fill(score, 0, [
          chordOf(2, 'E4', value: NoteValue.half),
          rest(7, NoteValue.half),
        ], slot: VoiceSlot.two);

        final outcome = addSpanner(
          held,
          const Glissando(from: NoteId(40)),
          pointAt(held, 0, at(1, 2)),
          pointAt(held, 1, Moment.zero),
          voice: VoiceSlot.two,
        );
        final back = addSpanner(
          fill(held, 0, [
            chordOf(1, 'D5'),
            chordOf(4, 'G5'),
            chordOf(6, 'B5', value: NoteValue.half),
          ]),
          const Glissando(from: NoteId(40)),
          pointAt(held, 0, at(1, 4)),
          pointAt(held, 0, at(3, 8)),
          voice: VoiceSlot.two,
        );

        expect(applied(outcome).score.spanners, hasLength(1));
        expect(refusal(back), isA<InvalidValue>());
      });

      test('joins a later note of the other voice, in its bar or the next', () {
        for (final (to, last) in [
          (40, pointAt(score, 0, at(1, 2))),
          (50, pointAt(score, 1, Moment.zero)),
        ]) {
          final joined = applied(
            glide(30, to, pointAt(score, 0, at(1, 4)), last),
          );

          expect(
            joined.score.glissandoNotes(joined.score.spanners.single).to?.id,
            NoteId(to),
          );
        }
      });

      test('that names a note its end lacks is refused for that note', () {
        final outcome = glide(
          40,
          99,
          pointAt(score, 0, at(1, 2)),
          pointAt(score, 0, at(3, 4)),
        );

        expect(refusal(outcome), isA<StaleReference>());
      });
    });

    group('a slur or glissando of voice two that ends in a gap', () {
      Score voices(List<VoiceItem> one, List<VoiceItem> two) =>
          fill(fill(blankScore(), 0, one), 0, two, slot: VoiceSlot.two);
      final held = [chordOf(1, 'D5', value: NoteValue.whole)];
      final start = [
        Gap(len(1, 8)),
        chordOf(2, 'E4', value: NoteValue.eighth),
      ];

      test('is refused when the note of voice one there has sounded since '
          'before it starts', () {
        final score = voices(held, [...start, Gap(len(3, 4))]);

        for (final (kind, name) in const [
          (Glissando(), 'a glissando'),
          (Slur(), 'a slur'),
        ]) {
          final outcome = addSpanner(
            score,
            kind,
            pointAt(score, 0, at(1, 8)),
            pointAt(score, 0, at(3, 4)),
            voice: VoiceSlot.two,
          );

          expect(
            refusal(outcome),
            isA<InvalidValue>().having(
              (refused) => refused.message,
              'message',
              '$name must end after it starts',
            ),
          );
        }
      });

      test('joins a note of voice one that starts with its first note as a '
          'slur, not as a glissando', () {
        final score = voices(
          [
            chordOf(1, 'D5', value: NoteValue.eighth),
            chordOf(3, 'C5', value: NoteValue.half),
            chordOf(4, 'B4', value: NoteValue.eighth),
            chordOf(5, 'A4'),
          ],
          [...start, Gap(len(3, 4))],
        );
        EditOutcome joining(SpannerKind kind) => addSpanner(
          score,
          kind,
          pointAt(score, 0, at(1, 8)),
          pointAt(score, 0, at(1, 4)),
          voice: VoiceSlot.two,
        );

        expect(applied(joining(const Slur())).score.spanners, hasLength(1));
        expect(refusal(joining(const Glissando())), isA<InvalidValue>());
      });

      test('ends on the note another voice starts there, not on the note of '
          'voice one that has sounded since before it starts', () {
        final score = fill(
          voices(held, [...start, Gap(len(3, 4))]),
          0,
          [Gap(len(3, 4)), chordOf(6, 'G4')],
          slot: VoiceSlot.three,
        );

        for (final kind in const [Glissando(), Slur()]) {
          final joined = applied(
            addSpanner(
              score,
              kind,
              pointAt(score, 0, at(1, 8)),
              pointAt(score, 0, at(3, 4)),
              voice: VoiceSlot.two,
            ),
          ).score;

          final end = joined.anchorOf(joined.spanners.single, last: true)!;
          expect(end.event.id, const EventId(6), reason: '$kind');
          expect(end.voice, VoiceSlot.three, reason: '$kind');
        }
      });

      test('ends on the event voice one starts there before a note a third '
          'voice starts there, and on no rest of a third voice', () {
        final together = fill(
          voices(
            [
              chordOf(1, 'D5', value: NoteValue.half),
              chordOf(7, 'C5', value: NoteValue.half),
            ],
            [...start, Gap(len(3, 4))],
          ),
          0,
          [Gap(len(1, 2)), chordOf(6, 'G4', value: NoteValue.half)],
          slot: VoiceSlot.three,
        );
        final resting = fill(
          voices(held, [...start, Gap(len(3, 4))]),
          0,
          [Gap(len(3, 4)), rest(6, NoteValue.quarter)],
          slot: VoiceSlot.three,
        );
        TimedEvent endAt(Score score, Moment offset) {
          final joined = withSpanner(
            score,
            const Slur(),
            pointAt(score, 0, at(1, 8)),
            pointAt(score, 0, offset),
            voice: VoiceSlot.two,
          );
          return joined.anchorOf(joined.spanners.single, last: true)!;
        }

        expect(endAt(together, at(1, 2)).event.id, const EventId(7));
        expect(endAt(resting, at(3, 4)).event.id, const EventId(1));
        expect(
          refusal(
            addSpanner(
              resting,
              const Slur(),
              pointAt(resting, 0, at(1, 8)),
              pointAt(resting, 0, at(3, 4)),
              voice: VoiceSlot.two,
            ),
          ),
          isA<InvalidValue>(),
        );
      });

      test('ends on the note voice one holds there, not on the note a third '
          'voice starts there, when the held note starts no sooner than its '
          'first note', () {
        final third = [Gap(len(1, 2)), chordOf(6, 'G4'), Gap(len(1, 4))];
        final together = fill(
          voices(
            [
              chordOf(1, 'C5'),
              chordOf(
                3,
                'D5',
                value: const NoteValue(DurationBase.half, dots: 1),
              ),
            ],
            [Gap(len(1, 4)), chordOf(2, 'F4'), Gap(len(1, 2))],
          ),
          0,
          third,
          slot: VoiceSlot.three,
        );
        var later = blankScore();
        later = fill(later, 0, [chordOf(7, 'C5', value: NoteValue.whole)]);
        later = fill(later, 0, [
          Gap(len(3, 4)),
          chordOf(2, 'F4'),
        ], slot: VoiceSlot.two);
        later = fill(later, 1, [chordOf(3, 'D5', value: NoteValue.whole)]);
        later = fill(later, 1, third, slot: VoiceSlot.three);

        for (final (score, first, last) in [
          (
            together,
            pointAt(together, 0, at(1, 4)),
            pointAt(together, 0, at(1, 2)),
          ),
          (later, pointAt(later, 0, at(3, 4)), pointAt(later, 1, at(1, 2))),
        ]) {
          final joined = applied(
            addSpanner(score, const Slur(), first, last, voice: VoiceSlot.two),
          ).score;

          expect(
            joined.anchorOf(joined.spanners.single, last: true)!.event.id,
            const EventId(3),
          );
        }
      });

      test('starts on the note voice one holds there, not on the note a '
          'third voice starts there', () {
        final score = fill(
          voices(held, [
            Gap(len(1, 2)),
            chordOf(2, 'E4', value: NoteValue.half),
          ]),
          0,
          [Gap(len(1, 4)), chordOf(6, 'G4'), Gap(len(1, 2))],
          slot: VoiceSlot.three,
        );

        for (final kind in const [Glissando(), Slur()]) {
          final joined = applied(
            addSpanner(
              score,
              kind,
              pointAt(score, 0, at(1, 4)),
              pointAt(score, 0, at(1, 2)),
              voice: VoiceSlot.two,
            ),
          ).score;

          expect(
            joined.anchorOf(joined.spanners.single, last: false)!.event.id,
            const EventId(1),
            reason: '$kind',
          );
        }
      });

      test('goes when an erase leaves its end in such a gap, and undo brings '
          'it back', () {
        final score = voices(held, [
          ...start,
          chordOf(3, 'F4', value: NoteValue.half),
          chordOf(4, 'G4'),
        ]);
        final end = EventRef(
          measure: score.measures.first.id,
          staff: score.staves.first.id,
          id: const EventId(4),
        );

        for (final kind in const [Glissando(), Slur()]) {
          final lined = applied(
            addSpanner(
              score,
              kind,
              pointAt(score, 0, at(1, 8)),
              pointAt(score, 0, at(3, 4)),
              voice: VoiceSlot.two,
            ),
          );

          final erased = applied(lined.run(Erase(ItemSelection(Seq([end])))));

          expect(erased.score.spanners, isEmpty, reason: '$kind');
          expect(erased.undo().score.spanners, hasLength(1), reason: '$kind');
        }
      });
    });

    group('a slur of voice two that ends on a note of voice three, under a '
        'note voice one has held since before it', () {
      String end(Score score, Spanner slur) {
        final on = score.anchorOf(slur, last: true)!;
        final tones = switch (on.event) {
          ChordEvent(:final notes) => notes.map((note) => '${note.tone}'),
          _ => const ['rest'],
        };
        return '${on.voice.name} ${tones.join(' ')}';
      }

      List<String> ends(Score score) => [
        for (final slur in score.spanners) end(score, slur),
      ];

      Score under(List<VoiceItem> one) {
        var score = fill(blankScore(), 0, one);
        score = fill(score, 0, [
          chordOf(2, 'E4'),
          chordOf(3, 'F4'),
          Gap(len(1, 2)),
        ], slot: VoiceSlot.two);
        return fill(score, 0, [
          Gap(len(1, 2)),
          chordOf(6, 'G4'),
          Gap(len(1, 4)),
        ], slot: VoiceSlot.three);
      }

      EditSession slurred(Score score, ScorePoint first, ScorePoint last) =>
          applied(
            addSpanner(score, const Slur(), first, last, voice: VoiceSlot.two),
          );

      test('stays on that note when SetMeter, a ripple insert or a paste '
          'splits the held note into tied parts', () {
        final score = under([chordOf(1, 'C5', value: NoteValue.whole)]);
        final session = slurred(
          score,
          pointAt(score, 0, at(1, 4)),
          pointAt(score, 0, at(1, 2)),
        );
        final staff = score.staves.first.id;
        VoicePoint inVoiceOne(int bar, Moment offset) => VoicePoint(
          staff: staff,
          voice: VoiceSlot.one,
          at: pointAt(score, bar, offset),
        );
        EnterNote insert(NoteValue value) => EnterNote(
          at: inVoiceOne(0, Moment.zero),
          tone: Pitch.parse('B4'),
          value: value,
          appendBar: false,
          ripple: Ripple.part,
        );
        final clip = session
            .select(
              RangeSelection(
                from: pointAt(score, 0, Moment.zero),
                to: pointAt(score, 1, Moment.zero),
                top: staff,
                bottom: staff,
              ),
            )
            .copy()!;

        expect(ends(session.score), ['three G4']);
        for (final (edit, slurs) in [
          (SetMeter(from: score.measures.first.id, meter: Meter.twoFour), 1),
          (insert(NoteValue.quarter), 1),
          (insert(NoteValue.eighth), 1),
          (Paste(clip, at: inVoiceOne(1, at(1, 8))), 2),
        ]) {
          expect(
            ends(applied(session.run(edit)).score),
            List.filled(slurs, 'three G4'),
            reason: '${edit.runtimeType}',
          );
        }
      });

      test('ends on that note in the bar after its first, not on the part of '
          'the held note that is tied over the barline', () {
        Score across(
          List<VoiceItem> one,
          List<VoiceItem> two,
          Moment start,
        ) {
          var score = fill(blankScore(), 0, one);
          score = fill(score, 0, two, slot: VoiceSlot.two);
          score = fill(score, 1, [chordOf(7, 'C5', value: NoteValue.whole)]);
          score = fill(score, 1, [
            chordOf(8, 'E4'),
            Gap(len(3, 4)),
          ], slot: VoiceSlot.two);
          score = fill(score, 1, [
            Gap(len(1, 2)),
            chordOf(6, 'G4'),
            Gap(len(1, 4)),
          ], slot: VoiceSlot.three);
          return slurred(
            score,
            pointAt(score, 0, start),
            pointAt(score, 1, at(1, 2)),
          ).score;
        }

        final before = across(
          [chordOf(1, 'C5', value: NoteValue.whole, tie: true)],
          [Gap(len(3, 4)), chordOf(3, 'F4')],
          at(3, 4),
        );
        final after = across(
          [
            chordOf(1, 'D5', value: NoteValue.half),
            chordOf(4, 'C5', value: NoteValue.half, tie: true),
          ],
          [Gap(len(1, 4)), chordOf(3, 'F4'), Gap(len(1, 2))],
          at(1, 4),
        );

        expect(ends(before), ['three G4']);
        expect(ends(after), ['one C5']);
      });
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

  group('A glissando whose notes stay', () {
    /// Voice one plays C5 and D5. Voice two plays [own], and its line runs
    /// from its E4 to that D5.
    Score crossing(List<VoiceItem> own) {
      final score = fill(
        fill(blankScore(), 0, [
          chordOf(1, 'C5'),
          chordOf(2, 'D5'),
          rest(3, NoteValue.half),
        ]),
        0,
        own,
        slot: VoiceSlot.two,
      );
      return withSpanner(
        score,
        const Glissando(from: NoteId(40), to: NoteId(20)),
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(1, 4)),
        voice: VoiceSlot.two,
      );
    }

    (String, String) joined(Score score) =>
        switch (score.glissandoNotes(score.spanners.single)) {
          (:final from, :final to) => ('${from?.tone}', '${to?.tone}'),
        };

    Moment lastOf(Score score) => score.spanners.single.last.offset;

    test('ends on the voice-one note it names while its own voice plays '
        'under that note', () {
      final score = crossing([
        chordOf(4, 'E4'),
        chordOf(5, 'F4'),
        rest(60, NoteValue.half),
      ]);

      expect(joined(score), ('E4', 'D5'));
      expect(joined(reloaded(score)), ('E4', 'D5'));
      expect(
        joined(
          applied(
            EditSession.start(score).run(
              SetTone(
                NoteRef(
                  score.locate(const EventId(1))!,
                  const NoteId(10),
                ),
                Pitch.parse('B4'),
              ),
            ),
          ).score,
        ),
        ('E4', 'D5'),
      );
    });

    test('keeps its voice-one note when a note is entered under that note '
        'in its own voice, and when the new note is erased', () {
      final session = EditSession.start(
        crossing([
          chordOf(4, 'E4'),
          Gap(len(1, 4)),
          rest(60, NoteValue.half),
        ]),
      );

      final entered = applied(
        session.run(
          EnterNote(
            at: point(session.score, 0, at(1, 4), voice: VoiceSlot.two),
            tone: f4,
            value: NoteValue.quarter,
          ),
        ),
      );
      final under = entered.score
          .laneOf(entered.score.staves.first.id, VoiceSlot.two)
          .elementAt(1);
      final erased = applied(
        entered.run(Erase(ItemSelection(Seq([under.ref])))),
      );

      expect(joined(session.score), ('E4', 'D5'));
      expect(joined(entered.score), ('E4', 'D5'));
      expect(joined(erased.score), ('E4', 'D5'));
    });

    test('joins a note to a voice-one note that it sounds over', () {
      final score = crossing([
        chordOf(4, 'E4', value: NoteValue.half),
        rest(60, NoteValue.half),
      ]);
      final Spanner(:kind, :first, :last, :voice) = score.spanners.single;

      final added = applied(
        addSpanner(
          score.copyWith(spanners: const Seq.empty()),
          kind,
          first,
          last,
          voice: voice,
        ),
      );

      expect(joined(added.score), ('E4', 'D5'));
      expect(joined(reloaded(added.score)), ('E4', 'D5'));
    });

    test('follows its last note when new music takes the time its end '
        'stood at inside that note', () {
      final score = fill(blankScore(), 0, [
        chordOf(1, 'C4 G4'),
        chordOf(2, 'D4'),
        chordOf(3, 'E4 C5', value: NoteValue.half),
      ]);
      final session = EditSession.start(
        withSpanner(
          score,
          const Glissando(from: NoteId(20), to: NoteId(31)),
          pointAt(score, 0, at(1, 4)),
          pointAt(score, 0, at(3, 4)),
          voice: VoiceSlot.one,
        ),
      );
      final end = point(session.score, 0, at(3, 4));

      for (final edit in [
        EnterNote(at: end, tone: f4, value: NoteValue.quarter),
        EnterTuplet(
          at: end,
          ratio: TupletRatio.triplet,
          unit: NoteValue.eighth,
        ),
      ]) {
        final next = applied(session.run(edit)).score;

        expect(bar(next, 0)[2], 'E4+C5/quarter', reason: '$edit');
        expect(joined(next), ('D4', 'C5'), reason: '$edit');
        expect(lastOf(next), at(1, 2), reason: '$edit');
      }
    });

    test('follows the chord it ends on when a rippled erase moves it, and '
        'goes when the erase removes the start of that chord', () {
      final quarterThenHalf = [
        chordOf(1, 'C4 G4'),
        chordOf(2, 'D4 C5'),
        chordOf(3, 'E4', value: NoteValue.half),
      ];
      final quarters = [
        chordOf(1, 'C4 G4'),
        chordOf(2, 'D4'),
        chordOf(3, 'E4 C5'),
        chordOf(4, 'F4'),
      ];
      const second = Glissando(from: NoteId(11), to: NoteId(20));
      const third = Glissando(from: NoteId(11), to: NoteId(31));
      for (final (items, line, last, range, kept) in [
        (
          quarterThenHalf,
          second,
          at(1, 4),
          (at(1, 8), at(1, 4)),
          (('G4', 'D4'), at(1, 8)),
        ),
        (quarterThenHalf, second, at(1, 4), (at(1, 8), at(3, 8)), null),
        (
          quarters,
          third,
          at(1, 2),
          (at(3, 8), at(1, 2)),
          (('G4', 'C5'), at(3, 8)),
        ),
        (quarters, third, at(1, 2), (at(3, 8), at(5, 8)), null),
      ]) {
        final score = fill(blankScore(), 0, items);
        final staff = score.staves.first.id;
        final session = EditSession.start(
          withSpanner(
            score,
            line,
            pointAt(score, 0, Moment.zero),
            pointAt(score, 0, last),
            voice: VoiceSlot.one,
          ),
        );

        final next = applied(
          session.run(
            Erase(
              RangeSelection(
                from: pointAt(score, 0, range.$1),
                to: pointAt(score, 0, range.$2),
                top: staff,
                bottom: staff,
              ),
              ripple: Ripple.staff,
            ),
          ),
        ).score;

        expect(
          next.spanners.isEmpty ? null : (joined(next), lastOf(next)),
          kept,
          reason: '$line $range',
        );
      }
    });

    test('stays in the scores the edits make while both its notes do', () {
      Score lined() {
        var score = blankScore(parts: const [morinKhuur, clarinet], bars: 4);
        for (var bar = 0; bar < 4; bar++) {
          final id = 1000 + bar * 10;
          score = fill(score, bar, [
            chordOf(id, 'C4 G4'),
            chordOf(id + 1, 'D4 C5', value: NoteValue.half),
            chordOf(id + 2, 'E4'),
          ]);
          score = withSpanner(
            score,
            Glissando(
              from: NoteId(id * 10 + bar % 2),
              to: NoteId((id + 1) * 10 + bar ~/ 2),
            ),
            pointAt(score, bar, Moment.zero),
            pointAt(score, bar, at(1 + bar % 2, 4)),
            voice: bar < 2 ? VoiceSlot.one : VoiceSlot.two,
          );
        }
        return score;
      }

      var kept = 0;
      for (var seed = 0; seed < 300; seed++) {
        final random = Random(seed);
        var score = lined();
        for (var step = 0; step < 40; step++) {
          score = randomEdit(score, random);
          kept += score.spanners
              .where((spanner) => spanner.id.value < 904)
              .length;
        }
      }

      expect(kept, greaterThan(1000));
    });
  });
}
