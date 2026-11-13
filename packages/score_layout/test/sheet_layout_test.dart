import 'package:score_layout/src/assembly.dart';
import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_layout/src/text.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/support.dart';
import 'support/fake_measurer.dart';
import 'support/fixtures.dart';
import 'support/sheets.dart';

const EngravingStyle style = EngravingStyle.standard;
const FakeMeasurer text = FakeMeasurer();

SheetLayout sheetOf(
  Score score, {
  double width = 120,
  EngravingStyle style = style,
}) => SheetLayout(score, width: width, text: text, style: style);

Score edit(Score score, Edit edit) =>
    applied(EditSession.start(score).run(edit)).score;

Score ensemble(int bars) {
  var score = blankScore(parts: const [clarinet, piano], bars: bars);
  for (var bar = 0; bar < bars; bar++) {
    score = fill(score, bar, [
      for (final (beat, pitch) in const ['C5', 'D5', 'E5', 'G5'].indexed)
        chordOf(10000 + bar * 10 + beat, pitch),
    ]);
  }
  return score;
}

double inkRightOf(SheetLayout layout, int index) => layout
    .systemAt(index)
    .drawables
    .map((drawable) => drawable.bounds.right)
    .reduce((a, b) => a > b ? a : b);

void main() {
  group('an update of the 500-bar score', () {
    final score = denseScore();
    const width = 100.0;
    late SheetLayout layout;

    setUpAll(() {
      layout = sheetOf(score, width: width);
      assembleAll(layout);
    });

    SheetLayout expectIncremental(
      Score next, {
      required Set<MeasureId> relaid,
      bool? rebroke,
    }) {
      final updated = layout.update(next);
      final fresh = sheetOf(next, width: width);

      expect(updated.delta.relaid, relaid);
      if (rebroke != null) {
        expect(updated.delta.rebroke, rebroke);
      }
      expect(updated.delta.rekeyed, isNotEmpty);
      expectSameSheet(updated, fresh);
      for (var i = 0; i < updated.systemCount; i++) {
        if (updated.delta.rekeyed.contains(i)) {
          continue;
        }
        final was = layout.systemOf(updated.firstBarOf(i))!;
        expect(
          identical(updated.systemAt(i), layout.systemAt(was)),
          isTrue,
          reason: 'system $i kept its key, so it keeps its assembly',
        );
      }
      return updated;
    }

    test('after a note entered in bar 250 relays bars 249 to 251 and rekeys '
        'only the systems around them', () {
      final next = scoreAfter(EditSession.start(score), noteInBar(score, 250));
      final relaid = {
        for (var bar = 248; bar <= 250; bar++) score.measures[bar].id,
      };

      final updated = expectIncremental(next, relaid: relaid);

      expect(
        updated.delta.rekeyed,
        everyElement(isIn(systemsTouchedBy(updated, relaid))),
      );
      expect(updated.delta.rekeyed.length, lessThanOrEqualTo(3));
    });

    test('with the same score and width is the same object', () {
      expect(identical(layout.update(score), layout), isTrue);
      expect(identical(layout.update(score, width: width), layout), isTrue);
    });

    test('after a bar inserted before bar 250 relays what the model names '
        'and rekeys the system holding the new bar', () {
      final next = edit(score, InsertMeasures(before: score.measures[249].id));

      final updated = expectIncremental(
        next,
        relaid: next.changesSince(score).relayout.toSet(),
      );

      expect(updated.systemCount, greaterThanOrEqualTo(layout.systemCount));
      expect(
        updated.delta.rekeyed,
        contains(updated.systemOf(next.measures[249].id)),
      );
    });

    test(
      'after a system break set mid-system relays that bar and rebreaks',
      () {
        var bar = 300;
        while (layout.firstBarOf(layout.systemOf(score.measures[bar].id)!) ==
            score.measures[bar].id) {
          bar++;
        }
        final id = score.measures[bar].id;
        final next = edit(score, SetBreak(id, LayoutBreak.system));

        final updated = expectIncremental(
          next,
          relaid: next.changesSince(score).relayout.toSet(),
          rebroke: true,
        );

        expect(updated.delta.relaid, contains(id));
        expect(updated.firstBarOf(updated.systemOf(id)!), id);
        expect(updated.systemCount, layout.systemCount + 1);
      },
    );
  });

  group('a sheet', () {
    final score = ensemble(12);

    test('assembles a system once and keeps it', () {
      final layout = sheetOf(score);

      expect(identical(layout.systemAt(0), layout.systemAt(0)), isTrue);
      expect(identical(layout.systemAt(1), layout.systemAt(1)), isTrue);
      expect(identical(layout.systemAt(0), layout.systemAt(1)), isFalse);
    });

    test('rebreaks on a width change and lays out no bar again', () {
      final layout = sheetOf(score);
      assembleAll(layout);

      final next = layout.update(score, width: 80);

      expect(next.delta.rebroke, isTrue);
      expect(next.delta.relaid, isEmpty);
      expect(next.delta.rekeyed, {
        for (var i = 0; i < next.systemCount; i++) i,
      });
      expect(next.systemCount, greaterThan(layout.systemCount));
      expectSameSheet(next, sheetOf(score, width: 80));
    });

    test('after a clef set at the start of a system relays that bar and its '
        'neighbours only, and the system before ends with the courtesy '
        'clef', () {
      final ids = barIds(score);
      final staff = score.staves.first.id;
      // The bar already ends in the bass clef, so the new clef does not
      // carry on into the bars after it.
      final before = [
        SetBreak(ids[8], LayoutBreak.system),
        SetClef(
          staff: staff,
          at: ScorePoint(ids[8], at(1, 2)),
          clef: Clef.bass,
        ),
      ].fold(score, edit);
      final layout = sheetOf(before);
      assembleAll(layout);
      final next = edit(
        before,
        SetClef(
          staff: staff,
          at: ScorePoint(ids[8], Moment.zero),
          clef: Clef.bass,
        ),
      );

      final updated = layout.update(next);
      final starting = updated.systemOf(ids[8])!;
      final ending = updated.systemAt(starting - 1);

      expect(layout.firstBarOf(layout.systemOf(ids[8])!), ids[8]);
      expect(next.changesSince(before).relayout, {ids[7], ids[8], ids[9]});
      expect(updated.delta.relaid, {ids[7], ids[8], ids[9]});
      expect(
        ending.drawables.whereType<GlyphDraw>().where(
          (glyph) =>
              glyph.glyph == Glyph.fClefChange &&
              glyph.bounds.left >= ending.bars.last.right - 1e-9,
        ),
        hasLength(1),
      );
      expectSameSheet(updated, sheetOf(next));
      for (var i = 0; i < updated.systemCount; i++) {
        if (!updated.delta.rekeyed.contains(i)) {
          expect(
            identical(
              updated.systemAt(i),
              layout.systemAt(layout.systemOf(updated.firstBarOf(i))!),
            ),
            isTrue,
            reason: 'system $i kept its key, so it keeps its assembly',
          );
        }
      }
    });

    test('justifies every system to the width but a short last one', () {
      final pinned = edit(
        score,
        SetBreak(score.measures[11].id, LayoutBreak.system),
      );
      final layout = sheetOf(pinned);
      final last = layout.systemCount - 1;

      expect(last, greaterThanOrEqualTo(1));
      for (var i = 0; i < last; i++) {
        expect(inkRightOf(layout, i), closeTo(layout.width, bandTolerance));
      }
      expect(layout.systemAt(last).bars, hasLength(1));
      expect(inkRightOf(layout, last), lessThan(layout.width / 2));
    });

    test('keeps a measure rest inside its bar on a sheet too narrow to space '
        'the bar', () {
      final layout = sheetOf(
        blankScore(parts: const [clarinet, piano, drums]),
        width: 30,
      );
      final system = layout.systemAt(0);
      final rests = system.drawables.whereType<GlyphDraw>().where(
        (draw) => draw.glyph == Glyph.restWhole,
      );

      expect(system.width, greaterThan(layout.width));
      expect(rests, hasLength(system.staves.length));
      for (final rest in rests) {
        expect(
          rest.bounds.right,
          lessThanOrEqualTo(system.bars.first.right + bandTolerance),
        );
      }
      expectInsideBands(layout);
    });

    test('stacks the systems one gap apart and reports the height', () {
      final layout = sheetOf(score);

      expect(layout.tops.first, 0);
      for (var i = 1; i < layout.systemCount; i++) {
        expect(
          layout.tops[i],
          closeTo(
            layout.tops[i - 1] + layout.heightOf(i - 1) + style.systemGap,
            1e-9,
          ),
        );
      }
      expect(
        layout.height,
        layout.tops.last + layout.heightOf(layout.systemCount - 1),
      );
      for (var i = 0; i < layout.systemCount; i++) {
        expect(layout.heightOf(i), layout.systemAt(i).height);
      }
    });

    test('names the system of every bar and the first bar of every system', () {
      final layout = sheetOf(score);
      final systems = [
        for (final column in score.measures) layout.systemOf(column.id)!,
      ];

      expect(systems.first, 0);
      expect(systems.last, layout.systemCount - 1);
      for (var i = 1; i < systems.length; i++) {
        expect(systems[i] - systems[i - 1], anyOf(0, 1));
      }
      for (var i = 0; i < layout.systemCount; i++) {
        expect(layout.systemOf(layout.firstBarOf(i)), i);
        expect(layout.systemAt(i).bars.first.measure, layout.firstBarOf(i));
      }
      expect(layout.systemOf(const MeasureId(424242)), isNull);
    });
  });

  group('the header', () {
    final titled = ensemble(12).copyWith(
      meta: const ScoreMeta(
        title: 'Sonata',
        subtitle: 'In C',
        composer: 'A. Composer',
        lyricist: 'A. Poet',
      ),
    );

    TextDraw textOf(SheetLayout layout, String string) => layout.header
        .whereType<TextDraw>()
        .singleWhere((text) => text.text == string);

    double centreOf(TextDraw text) =>
        (text.bounds.left + text.bounds.right) / 2;

    test('prints the title and subtitle centred, then the lyricist at the '
        'left and the composer at the right, and starts the first system a '
        'gap below', () {
      final layout = sheetOf(titled);
      final title = textOf(layout, 'Sonata');
      final subtitle = textOf(layout, 'In C');
      final lyricist = textOf(layout, 'A. Poet');
      final composer = textOf(layout, 'A. Composer');

      expect(layout.header, hasLength(4));
      expect(title.bounds.top, closeTo(0, 1e-9));
      expect(centreOf(title), closeTo(layout.width / 2, 1e-9));
      expect(title.spec, style.specOf(TextRole.title));
      expect(centreOf(subtitle), closeTo(layout.width / 2, 1e-9));
      expect(subtitle.bounds.top, greaterThan(title.bounds.bottom));
      expect(subtitle.spec, style.specOf(TextRole.subtitle));
      expect(lyricist.bounds.left, 0);
      expect(composer.bounds.right, closeTo(layout.width, 1e-9));
      expect(lyricist.origin.y, composer.origin.y);
      expect(lyricist.bounds.top, greaterThan(subtitle.bounds.bottom));
      expect(composer.spec, style.specOf(TextRole.credit));
      expect(
        layout.tops.first,
        closeTo(composer.bounds.bottom + style.systemGap, 1e-9),
      );
    });

    test('is empty without text, and then the first system starts at 0', () {
      final layout = sheetOf(ensemble(12));

      expect(layout.header, isEmpty);
      expect(layout.tops.first, 0);
    });

    test('is kept across an unrelated edit and laid out again for a new '
        'title or width', () {
      final layout = sheetOf(titled);
      final next = layout.update(
        edit(titled, SetBarline(titled.measures[3].id, Barline.doubleBar)),
      );
      final renamed = next.update(
        next.score.copyWith(meta: const ScoreMeta(title: 'Other')),
      );
      final narrower = renamed.update(renamed.score, width: 80);

      expect(identical(next.header, layout.header), isTrue);
      expect(renamed.header.whereType<TextDraw>().single.text, 'Other');
      expect(renamed.delta.relaid, isEmpty);
      expect(centreOf(textOf(narrower, 'Other')), closeTo(40, 1e-9));
    });
  });

  group('the bar number at the start of a system', () {
    final score = ensemble(12);

    test('is 0 on a system starting with a pickup', () {
      final pickup = edit(score, SetBarLength(score.measures[0].id, len(1, 4)));
      final layout = sheetOf(pickup);

      expect(layout.labelOf(0)!.text, '0');
      expect(
        layout.labelOf(1)!.text,
        '${pickup.barNumberOf(layout.firstBarOf(1))}',
      );
      expect(sheetOf(score).labelOf(0)!.text, '1');
    });

    test('is the number of its first bar, the same object on every ask, and '
        'renumbered after a bar is inserted before it', () {
      final pinned = edit(
        score,
        SetBreak(score.measures[8].id, LayoutBreak.system),
      );
      final layout = sheetOf(pinned);
      final index = layout.systemOf(pinned.measures[8].id)!;
      final inserted = edit(
        pinned,
        InsertMeasures(before: pinned.measures[0].id),
      );
      final next = layout.update(inserted);
      final moved = next.systemOf(pinned.measures[8].id)!;

      expect(layout.firstBarOf(index), pinned.measures[8].id);
      expect(layout.labelOf(index)!.text, '9');
      expect(identical(layout.labelOf(index), layout.labelOf(index)), isTrue);
      expect(next.firstBarOf(moved), pinned.measures[8].id);
      expect(next.labelOf(moved)!.text, '10');
    });

    test('is absent when the style prints none', () {
      final layout = sheetOf(
        score,
        style: const EngravingStyle(barNumbers: false),
      );

      expect(layout.labelOf(0), isNull);
      expect(layout.labelOf(1), isNull);
    });

    test('lies in the band of its system, above the top staff', () {
      final layout = sheetOf(score);

      for (var i = 0; i < layout.systemCount; i++) {
        final label = layout.labelOf(i)!;
        final system = layout.systemAt(i);

        expect(label.spec, style.specOf(TextRole.barNumber));
        expect(label.bounds.top, greaterThanOrEqualTo(-bandTolerance));
        expect(label.bounds.left, system.bars.first.left);
        expect(
          label.bounds.bottom,
          lessThanOrEqualTo(system.staves.first.top + bandTolerance),
        );
      }
    });
  });
}
