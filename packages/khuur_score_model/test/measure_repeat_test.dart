import 'dart:convert';

import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

List<MeasureRepeat?> signs(Score score) => [
  for (final column in score.measures) column.staves.first.measureRepeat,
];

EditSession withNotes(int bars) {
  var session = blank(bars: bars);
  for (var bar = 0; bar < bars; bar++) {
    session = applied(
      session.run(
        EnterNote(
          at: point(session.score, bar, Moment.zero),
          tone: f4,
          value: NoteValue.whole,
          appendBar: false,
        ),
      ),
    );
  }
  return session;
}

/// [bars] bars of quarter notes, each bar on its own pitches, filled for
/// [beats] beats and rests after them.
EditSession tune(int bars, {int beats = 4}) {
  var session = blank(bars: bars);
  for (var b = 0; b < bars; b++) {
    for (var beat = 0; beat < beats; beat++) {
      session = enterAt(
        session,
        b,
        at(beat, 4),
        tone: Pitch.parse('${'CDEFGAB'[(b + beat) % 7]}4'),
      );
    }
  }
  return session;
}

/// Each note the score plays, as (start, duration, key), in milliseconds.
List<(int, int, int)> heard(Score score) => [
  for (final note
      in PlaybackCompiler()
          .compile(score)
          .notesBetween(
            0,
            double.infinity,
          ))
    (
      (note.start * 1000).round(),
      (note.duration * 1000).round(),
      note.key,
    ),
];

void main() {
  group('SetMeasureRepeat', () {
    test('puts a bar under a one-bar repeat in place of its notes', () {
      final session = withNotes(3);

      final set = applied(
        session.run(SetMeasureRepeat(idOf(session, 1), bars: 1)),
      );

      expect(signs(set.score), [null, MeasureRepeat.oneBar, null]);
      expect(bar(set.score, 1), ['measure-rest']);
      expect(bar(set.score, 0), bar(session.score, 0));
      expect(set.undoLabel, 'Measure repeat');
      expect(saved(set.undo().score), saved(session.score));
    });

    test('puts two bars under a two-bar repeat', () {
      final session = withNotes(4);

      final set = applied(
        session.run(SetMeasureRepeat(idOf(session, 2), bars: 2)),
      );

      expect(signs(set.score), [
        null,
        null,
        MeasureRepeat.twoBarsFirst,
        MeasureRepeat.twoBarsSecond,
      ]);
      expect(bar(set.score, 3), ['measure-rest']);
    });

    test('clears both halves of a two-bar repeat from either one', () {
      final session = applied(
        blank(bars: 4).run(SetMeasureRepeat(idOf(blank(bars: 4), 2), bars: 2)),
      );

      for (final half in [2, 3]) {
        final cleared = applied(
          session.run(SetMeasureRepeat(idOf(session, half), bars: null)),
        );
        expect(signs(cleared.score), everyElement(isNull), reason: '$half');
        expect(bar(cleared.score, 3), ['measure-rest']);
      }
    });

    test('changes nothing when the sign is set again or nothing clears', () {
      final session = blank(bars: 3);
      final set = applied(
        session.run(SetMeasureRepeat(idOf(session, 1), bars: 1)),
      );

      expect(
        changesNothing(set, SetMeasureRepeat(idOf(set, 1), bars: 1)),
        isTrue,
      );
      expect(
        changesNothing(session, SetMeasureRepeat(idOf(session, 2), bars: null)),
        isTrue,
      );
    });

    test('refuses where there are no bars to repeat', () {
      final session = blank(bars: 3);
      final refusals = {
        'first bar': SetMeasureRepeat(idOf(session, 0), bars: 1),
        'second bar, two bars': SetMeasureRepeat(idOf(session, 1), bars: 2),
        'last bar, two bars': SetMeasureRepeat(idOf(session, 2), bars: 2),
        'three bars': SetMeasureRepeat(idOf(session, 2), bars: 3),
      };
      for (final MapEntry(key: why, value: edit) in refusals.entries) {
        expect(
          refusal(session.run(edit)),
          isA<InvalidValue>(),
          reason: why,
        );
      }
    });

    test('refuses to repeat a bar of another length', () {
      final session = applied(
        blank(bars: 3).run(
          SetBarLength(idOf(blank(bars: 3), 0), len(3, 4)),
        ),
      );

      expect(
        refusal(session.run(SetMeasureRepeat(idOf(session, 1), bars: 1))),
        isA<InvalidValue>(),
      );
    });

    test('goes on every staff, or on the one named', () {
      final session = EditSession.start(
        Score.blank(parts: const [piano], measureCount: 2),
      );
      final [upper, lower] = session.score.staves;

      final one = applied(
        session.run(
          SetMeasureRepeat(idOf(session, 1), bars: 1, staff: lower.id),
        ),
      );
      final every = applied(
        session.run(SetMeasureRepeat(idOf(session, 1), bars: 1)),
      );

      expect(one.score.measures[1].staff(upper.id).measureRepeat, isNull);
      expect(
        one.score.measures[1].staff(lower.id).measureRepeat,
        MeasureRepeat.oneBar,
      );
      expect(
        [for (final s in every.score.measures[1].staves) s.measureRepeat],
        [MeasureRepeat.oneBar, MeasureRepeat.oneBar],
      );
    });

    test('clears a tie into the bar it covers', () {
      final session = enterAt(
        blank(bars: 3),
        0,
        at(3, 4),
        value: NoteValue.half,
      );
      final tied = session.score.measures[0].staves.first.voices.first.items
          .whereType<ChordEvent>()
          .last;
      expect(tied.notes.single.tie, isTrue);

      final set = applied(
        session.run(SetMeasureRepeat(idOf(session, 1), bars: 1)),
      );

      final untied = set.score.lookup(
        EventRef(
          measure: idOf(set, 0),
          staff: set.score.staves.first.id,
          id: tied.id,
        ),
      );
      expect((untied!.event as ChordEvent).notes.single.tie, isFalse);
    });
  });

  group('a measure-repeat sign', () {
    test('clears when a note is written into its bar', () {
      final session = applied(
        blank(bars: 4).run(SetMeasureRepeat(idOf(blank(bars: 4), 2), bars: 2)),
      );

      final written = enterAt(session, 3, Moment.zero);

      expect(signs(written.score), everyElement(isNull));
    });

    test('clears when the bars it repeats are deleted', () {
      final session = applied(
        blank(bars: 3).run(SetMeasureRepeat(idOf(blank(bars: 3), 1), bars: 1)),
      );

      final deleted = applied(
        session.run(DeleteMeasures(idOf(session, 0), idOf(session, 0))),
      );

      expect(signs(deleted.score), [null, null]);
    });

    test('clears a half when a bar comes between the halves', () {
      final session = applied(
        blank(bars: 4).run(SetMeasureRepeat(idOf(blank(bars: 4), 2), bars: 2)),
      );

      final inserted = applied(
        session.run(InsertMeasures(before: idOf(session, 3))),
      );

      expect(signs(inserted.score), everyElement(isNull));
    });

    test('clears a two-bar repeat when a break comes between its bars, '
        'and refuses one over a break', () {
      final session = applied(
        blank(bars: 4).run(SetMeasureRepeat(idOf(blank(bars: 4), 2), bars: 2)),
      );

      final broken = applied(
        session.run(SetBreak(idOf(session, 3), LayoutBreak.system)),
      );

      expect(signs(broken.score), everyElement(isNull));
      expect(
        refusal(broken.run(SetMeasureRepeat(idOf(broken, 2), bars: 2))),
        isA<InvalidValue>(),
      );
    });

    test('stays through an edit that leaves its bar alone', () {
      final session = applied(
        withNotes(3).run(SetMeasureRepeat(idOf(withNotes(3), 2), bars: 1)),
      );

      final edited = enterAt(session, 1, Moment.zero, tone: g4);

      expect(signs(edited.score), [null, null, MeasureRepeat.oneBar]);
    });

    test('stays through a meter change that keeps every bar', () {
      final session = applied(
        blank(bars: 3).run(SetMeasureRepeat(idOf(blank(bars: 3), 1), bars: 1)),
      );

      final kept = applied(
        session.run(
          SetMeter(
            from: idOf(session, 0),
            meter: Meter.threeFour,
            content: MeterContent.keepBars,
          ),
        ),
      );

      expect(signs(kept.score), [null, MeasureRepeat.oneBar, null]);
    });

    test('writes its notes out where a meter change re-bars it', () {
      for (final (sign, at) in [(1, 2), (2, 2)]) {
        final tuned = tune(4);
        final session = applied(
          tuned.run(SetMeasureRepeat(idOf(tuned, at), bars: sign)),
        );

        final changed = applied(
          session.run(
            SetMeter(
              from: idOf(session, 0),
              meter: Meter.threeFour,
            ),
          ),
        );

        expect(signs(changed.score), everyElement(isNull), reason: '$sign');
        expect(heard(changed.score), heard(session.score), reason: '$sign');
        expect(heard(changed.score), hasLength(16), reason: '$sign');
      }
    });

    test('writes its notes out where a meter change keeps bars from '
        'between it and the bar it repeats', () {
      for (final (sign, at, from) in [(1, 1, 1), (2, 2, 3)]) {
        final tuned = tune(at + sign, beats: 3);
        final session = applied(
          tuned.run(SetMeasureRepeat(idOf(tuned, at), bars: sign)),
        );

        final changed = applied(
          session.run(
            SetMeter(
              from: idOf(session, from),
              meter: Meter.threeFour,
              content: MeterContent.keepBars,
            ),
          ),
        );

        expect(signs(changed.score), everyElement(isNull), reason: '$sign');
        expect(
          [for (final (_, _, key) in heard(changed.score)) key],
          [for (final (_, _, key) in heard(session.score)) key],
          reason: '$sign',
        );
        expect(heard(changed.score), hasLength(3 * (at + sign)));
      }
    });

    test('clears where a meter change leaves it a bar of another length '
        'and it repeats a rest', () {
      final session = applied(
        blank(bars: 3).run(SetMeasureRepeat(idOf(blank(bars: 3), 1), bars: 1)),
      );

      final changed = applied(
        session.run(
          SetMeter(
            from: idOf(session, 1),
            meter: Meter.threeFour,
            content: MeterContent.keepBars,
          ),
        ),
      );

      expect(signs(changed.score), everyElement(isNull));
      expect(bar(changed.score, 1), ['measure-rest']);
    });

    test('refuses a bar with notes under it', () {
      expect(
        () => StaffMeasure(
          staff: const StaffId(1),
          clef: Clef.treble,
          voices: Seq([voiceOf(withNotes(1).score, 0)]),
          measureRepeat: MeasureRepeat.oneBar,
        ),
        throwsArgumentError,
      );
    });
  });

  group('JSON', () {
    test('round-trips one-bar and two-bar repeats', () {
      final score = [
        SetMeasureRepeat(idOf(blank(bars: 5), 1), bars: 1),
        SetMeasureRepeat(idOf(blank(bars: 5), 3), bars: 2),
      ].fold(blank(bars: 5), (s, edit) => applied(s.run(edit))).score;

      final json = jsonEncode(scoreToJson(score));

      expect(signs(reloaded(score)), [
        null,
        MeasureRepeat.oneBar,
        null,
        MeasureRepeat.twoBarsFirst,
        MeasureRepeat.twoBarsSecond,
      ]);
      expect(json, contains('"measureRepeat":"twoBarsFirst"'));
      expect(
        jsonEncode(scoreToJson(blank(bars: 3).score)),
        isNot(contains('measureRepeat')),
      );
    });

    Object? withSign(int bar, String sign) {
      final json = jsonDecode(jsonEncode(scoreToJson(blank(bars: 3).score)));
      final measures = (json as Map<String, Object?>)['measures']! as List;
      final staff =
          ((measures[bar] as Map<String, Object?>)['staves']! as List).first
              as Map<String, Object?>;
      staff['measureRepeat'] = sign;
      return json;
    }

    test('refuses a sign with no bar to repeat', () {
      expect(
        () => scoreFromJson(withSign(0, 'oneBar')),
        throwsA(
          isA<ScoreFormatException>().having(
            (e) => e.path,
            'path',
            r'$.measures[0].staves[0].measureRepeat',
          ),
        ),
      );
    });

    test('refuses half of a two-bar repeat', () {
      expect(
        () => scoreFromJson(withSign(2, 'twoBarsFirst')),
        throwsA(isA<ScoreFormatException>()),
      );
      expect(
        () => scoreFromJson(withSign(2, 'twoBarsSecond')),
        throwsA(isA<ScoreFormatException>()),
      );
    });
  });
}
