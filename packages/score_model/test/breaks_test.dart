import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Bar [bar]'s break and its key and meter display, as `break key meter`.
String display(Score score, int bar) {
  final column = score.measures[bar];
  return '${column.breakBefore?.name ?? '-'} ${column.keyDisplay.name} '
      '${column.meterDisplay.name}';
}

EditSession runAll(EditSession session, List<Edit> edits) =>
    edits.fold(session, (s, edit) => applied(s.run(edit)));

/// [session] with bar 1 starting a system, bar 2 restating its key and bar
/// 3 its meter.
EditSession laidOut(EditSession session) => runAll(session, [
  SetBreak(idOf(session, 1), LayoutBreak.system),
  SetKeyDisplay(idOf(session, 2), SignatureDisplay.restated),
  SetMeterDisplay(idOf(session, 3), SignatureDisplay.restated),
]);

/// [bars] bars of four quarter notes.
EditSession quarters(int bars) => sessionWith([
  for (var i = 0; i < bars; i++)
    [for (var j = 1; j <= 4; j++) chordOf(10 * i + j, 'F4')],
]);

void main() {
  group('Breaks and signature display', () {
    test('set and clear on one bar', () {
      final session = blank(bars: 3);
      final m = idOf(session, 1);

      final set = runAll(session, [
        SetBreak(m, LayoutBreak.page),
        SetKeyDisplay(m, SignatureDisplay.restated),
        SetMeterDisplay(m, SignatureDisplay.noCourtesy),
      ]);
      final cleared = runAll(set, [
        SetBreak(m, null),
        SetKeyDisplay(m, SignatureDisplay.auto),
        SetMeterDisplay(m, SignatureDisplay.auto),
      ]);

      expect(display(set.score, 1), 'page restated noCourtesy');
      expect(display(cleared.score, 1), '- auto auto');
      for (final i in [0, 2]) {
        expect(
          identical(set.score.measures[i], session.score.measures[i]),
          isTrue,
        );
      }
      expect(display(set.undo().score, 1), 'page restated auto');
    });

    test('change nothing when set again', () {
      final start = blank();
      final m = idOf(start, 1);
      final session = applied(start.run(SetBreak(m, LayoutBreak.system)));

      for (final edit in <Edit>[
        SetBreak(m, LayoutBreak.system),
        SetKeyDisplay(m, SignatureDisplay.auto),
        SetMeterDisplay(m, SignatureDisplay.auto),
      ]) {
        expect(changesNothing(session, edit), isTrue, reason: edit.label);
      }
    });

    test('refuse a bar that is gone', () {
      final session = blank();
      const gone = MeasureId(999);

      for (final edit in <Edit>[
        const SetBreak(gone, LayoutBreak.system),
        const SetKeyDisplay(gone, SignatureDisplay.restated),
        const SetMeterDisplay(gone, SignatureDisplay.restated),
      ]) {
        expect(
          refusal(session.run(edit)),
          isA<StaleReference>(),
          reason: edit.label,
        );
      }
    });

    test('are named for undo', () {
      const m = MeasureId(1);

      expect(const SetBreak(m, LayoutBreak.system).label, 'System break');
      expect(const SetBreak(m, null).label, 'System break');
      expect(const SetBreak(m, LayoutBreak.page).label, 'Page break');
    });

    test('print a signature where it changes or is restated', () {
      final start = blank(bars: 4);
      final score = runAll(start, [
        SetKey(from: idOf(start, 1), key: const KeySignature(2)),
        SetMeter(
          from: idOf(start, 1),
          meter: Meter.threeFour,
          content: MeterContent.keepBars,
        ),
        SetKeyDisplay(idOf(start, 2), SignatureDisplay.restated),
        SetMeterDisplay(idOf(start, 2), SignatureDisplay.noCourtesy),
        SetMeterDisplay(idOf(start, 3), SignatureDisplay.restated),
      ]).score;
      final views = [for (final c in score.measures) score.measureView(c.id)];

      expect([for (final v in views) v.printsKey], [true, true, true, false]);
      expect([for (final v in views) v.printsMeter], [true, true, false, true]);
    });

    test('print a courtesy before a change unless the bar turns it off', () {
      final start = blank(bars: 4);
      final score = runAll(start, [
        for (final (bar, meter) in [
          (1, Meter.threeFour),
          (2, Meter.twoFour),
          (3, Meter.simple(5, 4)),
        ]) ...[
          SetKey(from: idOf(start, bar), key: KeySignature(bar)),
          SetMeter(
            from: idOf(start, bar),
            meter: meter,
            content: MeterContent.keepBars,
          ),
        ],
        SetKeyDisplay(idOf(start, 2), SignatureDisplay.noCourtesy),
        SetMeterDisplay(idOf(start, 2), SignatureDisplay.restated),
        SetKeyDisplay(idOf(start, 3), SignatureDisplay.restated),
        SetMeterDisplay(idOf(start, 3), SignatureDisplay.noCourtesy),
      ]).score;
      final plain = runAll(blank(), [
        SetKeyDisplay(idOf(start, 1), SignatureDisplay.restated),
        SetMeterDisplay(idOf(start, 1), SignatureDisplay.restated),
      ]).score;
      final views = [for (final c in score.measures) score.measureView(c.id)];
      final unchanged = plain.measureView(plain.measures[1].id);

      expect(
        [for (final v in views) v.keyCourtesy],
        [false, true, false, true],
      );
      expect(
        [for (final v in views) v.meterCourtesy],
        [
          false,
          true,
          true,
          false,
        ],
      );
      expect([unchanged.keyCourtesy, unchanged.meterCourtesy], [false, false]);
    });

    test('never fold a restated signature into a multi-measure rest', () {
      final score = laidOut(blank(bars: 4)).score;

      expect(
        [for (final c in score.measures) score.measureView(c.id).isRestOnly],
        [false, true, false, false],
      );
    });

    test('reflow when a break changes', () {
      final session = blank(bars: 3);
      final broken = applied(
        session.run(SetBreak(idOf(session, 1), LayoutBreak.system)),
      );
      final paged = applied(
        broken.run(SetBreak(idOf(session, 1), LayoutBreak.page)),
      );
      final restated = applied(
        paged.run(SetKeyDisplay(idOf(session, 1), SignatureDisplay.restated)),
      );

      expect(broken.score.changesSince(session.score).reflow, isTrue);
      expect(paged.score.changesSince(broken.score).reflow, isTrue);
      expect(restated.score.changesSince(paged.score).reflow, isFalse);
      expect(
        restated.score.changesSince(paged.score).relayout,
        {
          for (final i in [0, 1, 2]) idOf(session, i),
        },
      );
    });

    test('stay on their bars through inserts and deletes', () {
      final session = laidOut(blank(bars: 4));
      final ids = barIds(session.score);

      final inserted = applied(
        session.run(InsertMeasures(before: ids[1], count: 2)),
      );
      final deleted = applied(inserted.run(DeleteMeasures(ids[2], ids[2])));

      expect(
        [for (var i = 0; i < 6; i++) display(inserted.score, i)],
        [
          '- auto auto',
          '- auto auto',
          '- auto auto',
          'system auto auto',
          '- restated auto',
          '- auto restated',
        ],
      );
      expect(
        [for (var i = 0; i < 5; i++) display(deleted.score, i)],
        [
          '- auto auto',
          '- auto auto',
          '- auto auto',
          'system auto auto',
          '- auto restated',
        ],
      );
    });

    test('stay where a re-barred bar still starts', () {
      final session = laidOut(quarters(4));

      final halves = applied(
        session.run(SetMeter(from: idOf(session, 0), meter: Meter.twoFour)),
      );
      final threes = applied(
        session.run(SetMeter(from: idOf(session, 0), meter: Meter.threeFour)),
      );
      final kept = applied(
        session.run(
          SetMeter(
            from: idOf(session, 0),
            meter: Meter.simple(5, 4),
            content: MeterContent.keepBars,
          ),
        ),
      );
      final common = applied(
        session.run(SetMeter(from: idOf(session, 0), meter: Meter.common)),
      );

      expect(
        [
          for (var i = 0; i < halves.score.measures.length; i++)
            display(halves.score, i),
        ],
        [
          '- auto auto',
          '- auto auto',
          'system auto auto',
          '- auto auto',
          '- restated auto',
          '- auto auto',
          '- auto restated',
          '- auto auto',
        ],
      );
      expect(
        [
          for (var i = 0; i < threes.score.measures.length; i++)
            display(threes.score, i),
        ],
        [
          '- auto auto',
          '- auto auto',
          '- auto auto',
          '- auto auto',
          '- auto restated',
          '- auto auto',
        ],
      );
      for (final score in [kept.score, common.score]) {
        expect(
          [for (var i = 0; i < 4; i++) display(score, i)],
          [
            '- auto auto',
            'system auto auto',
            '- restated auto',
            '- auto restated',
          ],
        );
      }
    });
  });
}
