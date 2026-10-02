import 'dart:math';

import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/spanners.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_layout/src/system_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/random_edits.dart';
import '../../score_model/test/support.dart';
import 'support/bars.dart' show graceOf, restOf;
import 'support/fake_measurer.dart';
import 'support/sheets.dart';

const EngravingStyle style = EngravingStyle.standard;
const FakeMeasurer text = FakeMeasurer();

/// Wide enough for two bars of quarters on one system.
const double wide = 120;

/// Room for one bar of quarters after the first system's part name, not
/// two, so the second bar starts a system.
const double narrow = 45;

/// The narrowest sheet the random walk lays out. A clef and seven sharps
/// leave a continuation system less room than a restated octave row.
const double tiny = 12;

SheetLayout sheetOf(
  Score score, {
  double width = wide,
  EngravingStyle style = style,
}) => SheetLayout(score, width: width, text: text, style: style);

/// A one-staff clarinet score with one bar per entry of [bars], each filled
/// with its items in voice one. An empty entry keeps the blank bar's rest.
Score scoreOf(List<List<VoiceItem>> bars) {
  var score = blankScore(parts: const [clarinet], bars: bars.length);
  for (final (index, items) in bars.indexed) {
    if (items.isNotEmpty) {
      score = fill(score, index, items);
    }
  }
  return score;
}

List<VoiceItem> quartersOf(int first, String pitch) => [
  for (var beat = 0; beat < 4; beat++) chordOf(first + beat, pitch),
];

EventRef eventRef(Score score, int bar, int event) => EventRef(
  measure: score.measures[bar].id,
  staff: score.staves.first.id,
  id: EventId(event),
);

/// The first note of [event], as `chordOf` numbers it.
NoteRef noteRef(Score score, int bar, int event) =>
    NoteRef(eventRef(score, bar, event), NoteId(event * 10));

const SpannerOwner spanner = SpannerOwner(SpannerId(900));

Iterable<CurveDraw> curvesOf(SystemLayout system) =>
    system.drawables.whereType<CurveDraw>();

Iterable<LineDraw> linesOf(SystemLayout system, {Owner? owner}) =>
    system.drawables.whereType<LineDraw>().where((line) => line.owner == owner);

Iterable<GlyphDraw> glyphsOf(SystemLayout system, {Owner? owner}) => system
    .drawables
    .whereType<GlyphDraw>()
    .where((glyph) => glyph.owner == owner);

Iterable<TextDraw> textsOf(SystemLayout system, String text) =>
    system.drawables.whereType<TextDraw>().where((draw) => draw.text == text);

Box headOf(SystemLayout system, NoteRef note) =>
    glyphsOf(system, owner: ElementOwner(note)).single.bounds;

double clefRightOf(SystemLayout system) => glyphsOf(
  system,
).firstWhere((glyph) => glyph.glyph == Glyph.gClef).bounds.right;

bool isVertical(LineDraw line) => line.from.x == line.to.x;

bool isHorizontal(LineDraw line) => line.from.y == line.to.y;

double topOf(SystemLayout system) => system.staves.single.top;

double bottomOf(SystemLayout system) => topOf(system) + staffHeight;

Iterable<double> ysOf(CurveDraw curve) => [
  for (var i = 0; i <= 20; i++) curve.pointAt(i / 20).y,
];

void main() {
  group('ties', () {
    test('a tie within a bar is one curve from the first head to the second, '
        'away from the stems and at most tieRise outside its ends', () {
      final score = scoreOf([
        [
          chordOf(1, 'C5', value: NoteValue.half, tie: true),
          chordOf(2, 'C5', value: NoteValue.half),
        ],
      ]);
      final system = sheetOf(score).systemAt(0);
      final tie = curvesOf(system).single;
      final from = headOf(system, noteRef(score, 0, 1));
      final to = headOf(system, noteRef(score, 0, 2));

      expect(tie.owner, ElementOwner(noteRef(score, 0, 1)));
      expect(tie.start.x, greaterThanOrEqualTo(from.right));
      expect(tie.end.x, lessThanOrEqualTo(to.left));
      expect(tie.start.y, tie.end.y);
      expect(
        tie.start.y - tie.pointAt(0.5).y,
        inInclusiveRange(tieRise / 2, tieRise + 1e-9),
      );
      for (final y in ysOf(tie)) {
        expect((y - tie.start.y).abs(), lessThanOrEqualTo(tieRise + 1e-9));
      }
    });

    test('a tie over a barline on one system joins the two heads', () {
      final score = scoreOf([
        [...quartersOf(1, 'C5').take(3), chordOf(4, 'C5', tie: true)],
        quartersOf(5, 'C5'),
      ]);
      final system = sheetOf(score).systemAt(0);
      final tie = curvesOf(system).single;
      final barline = system.bars[0].right;

      expect(tie.owner, ElementOwner(noteRef(score, 0, 4)));
      expect(
        tie.start.x,
        greaterThanOrEqualTo(headOf(system, noteRef(score, 0, 4)).right),
      );
      expect(
        tie.end.x,
        lessThanOrEqualTo(headOf(system, noteRef(score, 1, 5)).left),
      );
      expect(tie.start.x, lessThan(barline));
      expect(tie.end.x, greaterThan(barline));
    });

    test('a tie over a system break is a half tie on each system', () {
      final score = scoreOf([
        [...quartersOf(1, 'C5').take(3), chordOf(4, 'C5', tie: true)],
        quartersOf(5, 'C5'),
      ]);
      final sheet = sheetOf(score, width: narrow);
      expect(sheet.systemCount, 2);

      final first = sheet.systemAt(0);
      final leaving = curvesOf(first).single;
      expect(leaving.owner, ElementOwner(noteRef(score, 0, 4)));
      expect(
        leaving.start.x,
        greaterThanOrEqualTo(headOf(first, noteRef(score, 0, 4)).right),
      );
      expect(leaving.end.x, greaterThanOrEqualTo(first.bars.single.right));
      expect(leaving.bounds.right, lessThanOrEqualTo(first.width + 1e-9));

      final second = sheet.systemAt(1);
      final arriving = curvesOf(second).single;
      final head = headOf(second, noteRef(score, 1, 5));
      expect(arriving.owner, ElementOwner(noteRef(score, 1, 5)));
      expect(arriving.start.x, greaterThanOrEqualTo(clefRightOf(second)));
      expect(arriving.start.x, lessThan(head.left));
      expect(arriving.end.x, lessThanOrEqualTo(head.left));
      expect(
        arriving.end.x - arriving.start.x,
        greaterThanOrEqualTo(letRingLength - 1e-9),
        reason: 'the arriving half is at least a let-ring tie long',
      );
    });

    test(
      'a let-ring tie is letRingLength long and fits before the barline',
      () {
        final score = scoreOf([
          [...quartersOf(1, 'C5').take(3), chordOf(4, 'C5', tie: true)],
          quartersOf(5, 'D5'),
        ]);
        final system = sheetOf(score).systemAt(0);
        final tie = curvesOf(system).single;

        expect(tie.owner, ElementOwner(noteRef(score, 0, 4)));
        expect(
          tie.start.x,
          greaterThanOrEqualTo(headOf(system, noteRef(score, 0, 4)).right),
        );
        expect(tie.end.x - tie.start.x, closeTo(letRingLength, 1e-9));
        expect(tie.bounds.right, lessThanOrEqualTo(system.bars[0].right));
      },
    );

    test('a grace tie runs from the grace head to the principal head of its '
        'tone and belongs to the principal', () {
      final score = scoreOf([
        [
          chordOf(1, 'C5', graces: [graceOf(90, 'C5', tie: true)]),
          ...quartersOf(2, 'C5').take(3),
        ],
      ]);
      final system = sheetOf(score).systemAt(0);
      final tie = curvesOf(system).single;
      final principal = ElementOwner(eventRef(score, 0, 1));
      final graceHead = glyphsOf(
        system,
        owner: principal,
      ).where((glyph) => glyph.glyph == Glyph.noteheadBlack).single;

      final principalHead = headOf(system, noteRef(score, 0, 1));

      expect(tie.owner, principal);
      expect(graceHead.scale, style.graceScale);
      expect(tie.start.x, greaterThanOrEqualTo(graceHead.bounds.right));
      expect(
        principalHead.left - tie.end.x,
        closeTo(tie.start.x - graceHead.bounds.right, 1e-9),
        reason: 'the tie clears both heads by the same gap',
      );
    });
    test('a tied grace note joins the head of its tone in the next grace '
        'chord', () {
      final score = scoreOf([
        [
          chordOf(
            1,
            'D5',
            graces: [graceOf(90, 'C5', tie: true), graceOf(91, 'C5')],
          ),
          ...quartersOf(2, 'C5').take(3),
        ],
      ]);
      final system = sheetOf(score).systemAt(0);
      final tie = curvesOf(system).single;
      final [first, second] =
          glyphsOf(
              system,
              owner: ElementOwner(eventRef(score, 0, 1)),
            ).where((glyph) => glyph.glyph == Glyph.noteheadBlack).toList()
            ..sort((a, b) => a.origin.x.compareTo(b.origin.x));

      expect(tie.start.x, greaterThanOrEqualTo(first.bounds.right));
      expect(
        second.bounds.left - tie.end.x,
        closeTo(tie.start.x - first.bounds.right, 1e-9),
        reason: 'the tie clears both grace heads by the same gap',
      );
    });

    test('a tie under the lowest note of a system has its room in the band '
        'on both sides of a system break', () {
      final score = scoreOf([
        [...quartersOf(1, 'A3').take(3), chordOf(4, 'A3', tie: true)],
        quartersOf(5, 'A3'),
      ]);
      final sheet = sheetOf(score, width: narrow);
      expect(sheet.systemCount, 2);

      for (var index = 0; index < 2; index++) {
        final system = sheet.systemAt(index);
        final tie = curvesOf(system).single;
        final lowest = system.drawables
            .whereType<GlyphDraw>()
            .where((glyph) => glyph.glyph == Glyph.noteheadBlack)
            .map((glyph) => glyph.bounds.bottom)
            .reduce(max);
        expect(tie.bounds.bottom, greaterThan(lowest));
        expect(tie.bounds.bottom, lessThanOrEqualTo(system.height + 1e-9));
      }
    });
  });

  group('slurs', () {
    test('a slur belongs to its spanner and arches over every head it '
        'covers', () {
      final score = withSlur(
        scoreOf([
          [
            chordOf(1, 'C5'),
            chordOf(2, 'A5'),
            chordOf(3, 'C5'),
            restOf(4, NoteValue.quarter),
          ],
        ]),
        pointAt(blankScore(parts: const [clarinet]), 0, Moment.zero),
        pointAt(blankScore(parts: const [clarinet]), 0, at(2, 4)),
      );
      final system = sheetOf(score).systemAt(0);
      final slur = curvesOf(system).single;
      final first = headOf(system, noteRef(score, 0, 1));
      final high = headOf(system, noteRef(score, 0, 2));
      final last = headOf(system, noteRef(score, 0, 3));

      expect(slur.owner, spanner);
      expect(slur.start.x, closeTo((first.left + first.right) / 2, 1e-9));
      expect(slur.end.x, closeTo((last.left + last.right) / 2, 1e-9));
      expect(slur.start.y, lessThan(first.top));
      expect(slur.end.y, lessThan(last.top));
      for (var t = 0.25; t <= 0.75 + 1e-9; t += 0.05) {
        expect(slur.pointAt(t).y, lessThan(high.top), reason: 'at $t');
      }
    });

    test('a slur over a system break is one curve per system', () {
      final base = scoreOf([quartersOf(1, 'C5'), quartersOf(5, 'C5')]);
      final score = withSlur(
        base,
        pointAt(base, 0, at(2, 4)),
        pointAt(base, 1, at(1, 4)),
      );
      final sheet = sheetOf(score, width: narrow);
      expect(sheet.systemCount, 2);

      final first = sheet.systemAt(0);
      final leaving = curvesOf(first).single;
      final from = headOf(first, noteRef(score, 0, 3));
      expect(leaving.owner, spanner);
      expect(leaving.start.x, inInclusiveRange(from.left, from.right));
      expect(leaving.end.x, greaterThanOrEqualTo(first.bars.single.right));
      expect(leaving.bounds.right, lessThanOrEqualTo(first.width + 1e-9));

      final second = sheet.systemAt(1);
      final arriving = curvesOf(second).single;
      final to = headOf(second, noteRef(score, 1, 6));
      expect(arriving.owner, spanner);
      expect(arriving.start.x, greaterThanOrEqualTo(clefRightOf(second)));
      expect(
        arriving.start.x,
        lessThan(headOf(second, noteRef(score, 1, 5)).left),
      );
      expect(arriving.end.x, inInclusiveRange(to.left, to.right));
    });

    test(
      'a slur arriving on the first note of a system has a stub at least a '
      'let-ring tie long',
      () {
        final base = scoreOf([quartersOf(1, 'C5'), quartersOf(5, 'C5')]);
        final score = withSlur(
          base,
          pointAt(base, 0, at(2, 4)),
          pointAt(base, 1, Moment.zero),
        );
        final sheet = sheetOf(score, width: narrow);
        expect(sheet.systemCount, 2);

        final second = sheet.systemAt(1);
        final arriving = curvesOf(second).single;
        final to = headOf(second, noteRef(score, 1, 5));
        expect(arriving.owner, spanner);
        expect(arriving.start.x, greaterThanOrEqualTo(clefRightOf(second)));
        expect(arriving.end.x, inInclusiveRange(to.left, to.right));
        expect(
          arriving.end.x - arriving.start.x,
          greaterThanOrEqualTo(letRingLength - 1e-9),
        );
      },
    );

    for (final rests in [false, true]) {
      test('a slur over a barline between a stems-up bar and a stems-down bar '
          'stays inside the band, with multi-measure rests '
          '${rests ? 'on' : 'off'}', () {
        final base = scoreOf([quartersOf(1, 'G4'), quartersOf(5, 'D5')]);
        final score = withSlur(
          base,
          pointAt(base, 0, at(2, 4)),
          pointAt(base, 1, at(1, 4)),
        );
        for (final width in [wide, narrow]) {
          final sheet = sheetOf(
            score,
            width: width,
            style: EngravingStyle(multiMeasureRests: rests),
          );
          expectInsideBands(sheet);
          for (var i = 0; i < sheet.systemCount; i++) {
            expect(curvesOf(sheet.systemAt(i)), hasLength(1));
          }
        }
      });
    }
  });

  group('lines', () {
    final base = scoreOf([quartersOf(1, 'C5'), quartersOf(5, 'C5')]);

    for (final crescendo in [true, false]) {
      test('a ${crescendo ? 'crescendo' : 'diminuendo'} hairpin is two lines '
          'below the staff meeting at its ${crescendo ? 'start' : 'end'}', () {
        final score = withSpanner(
          base,
          Hairpin(crescendo: crescendo),
          pointAt(base, 0, Moment.zero),
          pointAt(base, 0, at(2, 4)),
        );
        final system = sheetOf(score).systemAt(0);
        final [a, b] = linesOf(system, owner: spanner).toList();
        final (point, open) = crescendo
            ? ((a.from, b.from), (a.to, b.to))
            : ((a.to, b.to), (a.from, b.from));

        expect(point.$1, point.$2);
        expect(open.$1.x, open.$2.x);
        expect(open.$1.y, isNot(open.$2.y));
        expect((open.$1.y + open.$2.y) / 2, closeTo(point.$1.y, 1e-9));
        expect(a.from.x, lessThan(a.to.x));
        expect(min(a.from.y, a.to.y), greaterThan(bottomOf(system)));
      });
    }

    test('an octave line restates its glyph in parentheses after a system '
        'break and hooks down at its end', () {
      final score = withSpanner(
        base,
        const OctaveLine(OctaveShift.up8),
        pointAt(base, 0, Moment.zero),
        pointAt(base, 1, at(3, 4)),
      );
      final sheet = sheetOf(score, width: narrow);
      expect(sheet.systemCount, 2);

      final first = sheet.systemAt(0);
      expect(
        [for (final g in glyphsOf(first, owner: spanner)) g.glyph],
        [Glyph.ottavaAlta],
      );
      final firstLines = linesOf(first, owner: spanner).toList();
      expect(firstLines, hasLength(1));
      expect(firstLines.single.dash, LineDash.dashed);
      expect(firstLines.single.to.x, lessThanOrEqualTo(first.width));

      final second = sheet.systemAt(1);
      final glyphs = glyphsOf(second, owner: spanner).toList()
        ..sort((a, b) => a.origin.x.compareTo(b.origin.x));
      expect(
        [for (final g in glyphs) g.glyph],
        [Glyph.octaveParensLeft, Glyph.ottavaAlta, Glyph.octaveParensRight],
      );
      final dashed = linesOf(second, owner: spanner).where(isHorizontal).single;
      final hook = linesOf(second, owner: spanner).where(isVertical).single;
      expect(dashed.dash, LineDash.dashed);
      expect(dashed.from.x, greaterThan(glyphs.last.bounds.right));
      expect(hook.from.x, dashed.to.x);
      expect(hook.from.y, dashed.from.y);
      expect(hook.to.y, greaterThan(hook.from.y));
      expect(hook.to.y, lessThan(topOf(second)));
    });

    test('a pedal line prints Ped., runs at its baseline below the staff and '
        'hooks up at its end', () {
      final score = withSpanner(
        base,
        const PedalLine(),
        pointAt(base, 0, Moment.zero),
        pointAt(base, 0, at(2, 4)),
      );
      final system = sheetOf(score).systemAt(0);
      final ped = glyphsOf(system, owner: spanner).single;
      final line = linesOf(system, owner: spanner).where(isHorizontal).single;
      final hook = linesOf(system, owner: spanner).where(isVertical).single;

      expect(ped.glyph, Glyph.keyboardPedalPed);
      expect(ped.bounds.top, greaterThan(bottomOf(system)));
      expect(line.from.y, ped.origin.y);
      expect(line.from.x, greaterThan(ped.bounds.right));
      expect(line.dash, LineDash.solid);
      expect(hook.from.x, line.to.x);
      expect(hook.from.y, line.from.y);
      expect(hook.to.y, lessThan(hook.from.y));
    });

    test('a trill line starts with the trill sign and wiggles to its last '
        'note', () {
      final score = withSpanner(
        base,
        const TrillLine(),
        pointAt(base, 0, Moment.zero),
        pointAt(base, 0, at(3, 4)),
      );
      final system = sheetOf(score).systemAt(0);
      final sign = glyphsOf(system, owner: spanner).single;
      final run = system.drawables.whereType<GlyphRunDraw>().single;
      final last = headOf(system, noteRef(score, 0, 4));

      expect(sign.glyph, Glyph.ornamentTrill);
      expect(sign.bounds.bottom, lessThanOrEqualTo(topOf(system)));
      expect(run.glyph, Glyph.wiggleTrill);
      expect(run.owner, spanner);
      expect(run.count, greaterThanOrEqualTo(1));
      expect(run.from.y, sign.origin.y);
      expect(run.bounds.left, greaterThan(sign.bounds.right));
      expect(run.to.x, greaterThan(last.left));
      expect(run.bounds.right, lessThanOrEqualTo((last.left + last.right) / 2));
    });

    test('a glissando slopes from the first head to the next', () {
      final low = scoreOf([
        [
          chordOf(1, 'C5'),
          chordOf(2, 'G5'),
          chordOf(3, 'C5'),
          chordOf(4, 'C5'),
        ],
      ]);
      final score = withSpanner(
        low,
        const Glissando(),
        pointAt(low, 0, Moment.zero),
        pointAt(low, 0, at(1, 4)),
      );
      final system = sheetOf(score).systemAt(0);
      final line = linesOf(system, owner: spanner).single;
      final from = headOf(system, noteRef(score, 0, 1));
      final to = headOf(system, noteRef(score, 0, 2));

      expect(line.from.x, greaterThanOrEqualTo(from.right));
      expect(line.to.x, lessThanOrEqualTo(to.left));
      expect(line.from.y, closeTo((from.top + from.bottom) / 2, 1e-9));
      expect(line.to.y, closeTo((to.top + to.bottom) / 2, 1e-9));
      expect(line.from.y, greaterThan(line.to.y));
    });

    test('a tempo line prints its text above the staff and dashes on from '
        'it', () {
      final score = withSpanner(
        base,
        const TempoLine(text: 'rit.', factor: 0.5),
        pointAt(base, 0, Moment.zero),
        pointAt(base, 0, at(2, 4)),
      );
      final system = sheetOf(score).systemAt(0);
      final label = textsOf(system, 'rit.').single;
      final line = linesOf(system, owner: spanner).single;

      expect(label.owner, spanner);
      expect(label.bounds.bottom, lessThanOrEqualTo(topOf(system)));
      expect(line.dash, LineDash.dashed);
      expect(line.from.x, greaterThanOrEqualTo(label.bounds.right));
      expect(line.from.x, lessThan(line.to.x));
      expect(
        line.from.y,
        inInclusiveRange(label.bounds.top, label.bounds.bottom),
      );
    });

    test("what a line starts with on a system's last beat starts at the beat "
        'and stays inside the system, which grows to hold it', () {
      const long = 'Allegro ma non troppo, con brio e sempre cantabile';
      var score = base;
      for (final kind in const <SpannerKind>[
        TempoLine(text: long, factor: 0.5),
        PedalLine(),
        OctaveLine(OctaveShift.up8),
        TrillLine(),
      ]) {
        score = withSpanner(
          score,
          kind,
          pointAt(score, 0, at(3, 4)),
          pointAt(score, 1, at(2, 4)),
        );
      }
      final sheet = sheetOf(score, width: narrow);
      final first = sheet.systemAt(0);
      final beat = headOf(first, noteRef(score, 0, 4));
      final signs = <Drawable>[
        textsOf(first, long).single,
        for (var id = 901; id <= 903; id++)
          glyphsOf(first, owner: SpannerOwner(SpannerId(id))).single,
      ];

      expect(first.width, greaterThan(narrow));
      for (final sign in signs) {
        expect(
          sign.bounds.left,
          greaterThanOrEqualTo(beat.left - 1e-9),
          reason: '$sign',
        );
        expect(
          sign.bounds.right,
          lessThanOrEqualTo(first.width + 1e-9),
          reason: '$sign',
        );
      }
    });

    test('an octave line restates its glyph before the first note of a '
        'system too narrow for the row, and the system grows to hold it', () {
      var score = blankScore(key: const KeySignature(7));
      for (final bar in [0, 1]) {
        score = fill(score, bar, [
          chordOf(bar + 1, 'C#5', value: NoteValue.whole),
        ]);
      }
      score = withSpanner(
        score,
        const OctaveLine(OctaveShift.up8),
        pointAt(score, 0, Moment.zero),
        pointAt(score, 1, at(2, 4)),
      );
      final sheet = sheetOf(score, width: tiny);
      expect(sheet.systemCount, 2);

      final second = sheet.systemAt(1);
      final row = glyphsOf(second, owner: spanner).toList()
        ..sort((a, b) => a.origin.x.compareTo(b.origin.x));
      final headEnd = glyphsOf(second).map((g) => g.bounds.right).reduce(max);
      final note = headOf(second, noteRef(score, 1, 2));

      expect(row, hasLength(3));
      expect(row.first.bounds.left, greaterThanOrEqualTo(headEnd));
      expect(row.last.bounds.right, lessThanOrEqualTo(note.left + 1e-9));
      expect(row.last.bounds.right, lessThanOrEqualTo(second.width + 1e-9));
    });
    test('a hairpin lies between the staff and a pedal line under the same '
        'notes', () {
      final pedalled = withSpanner(
        base,
        const PedalLine(),
        pointAt(base, 0, Moment.zero),
        pointAt(base, 0, at(2, 4)),
      );
      final score = withSpanner(
        pedalled,
        const Hairpin(crescendo: true),
        pointAt(base, 0, Moment.zero),
        pointAt(base, 0, at(2, 4)),
      );
      final system = sheetOf(score).systemAt(0);
      final hairpin = linesOf(
        system,
        owner: const SpannerOwner(SpannerId(901)),
      );
      final ped = glyphsOf(system, owner: spanner).single;

      expect(hairpin, hasLength(2));
      for (final line in hairpin) {
        expect(max(line.from.y, line.to.y), lessThan(ped.bounds.top));
        expect(min(line.from.y, line.to.y), greaterThan(bottomOf(system)));
      }
    });
  });

  group('voltas', () {
    final thickness = style.font.defaults.repeatEndingLineThickness;

    Iterable<LineDraw> bracketOf(SystemLayout system) => linesOf(system).where(
      (line) =>
          line.thickness == thickness &&
          max(line.from.y, line.to.y) <= topOf(system),
    );

    test('a volta has its label, its line over the bar and both hooks', () {
      final base = scoreOf([quartersOf(1, 'C5'), quartersOf(5, 'C5')]);
      final score = applied(
        EditSession.start(base).run(
          SetVolta(base.measures[0].id, base.measures[0].id, const Volta([1])),
        ),
      ).score;
      final system = sheetOf(score).systemAt(0);
      final bar = system.bars[0];
      final line = bracketOf(system).where(isHorizontal).single;
      final hooks = bracketOf(system).where(isVertical).toList()
        ..sort((a, b) => a.from.x.compareTo(b.from.x));
      final label = textsOf(system, '1.').single;

      expect(line.from.x, closeTo(bar.left, 1e-9));
      expect(line.to.x, closeTo(bar.right, 1e-9));
      expect(line.from.y, lessThan(topOf(system)));
      expect(hooks, hasLength(2));
      expect(hooks.first.from.x, closeTo(bar.left + thickness / 2, 1e-9));
      expect(hooks.last.from.x, closeTo(bar.right - thickness / 2, 1e-9));
      for (final hook in hooks) {
        expect(hook.from.y, line.from.y);
        expect(hook.to.y - hook.from.y, greaterThanOrEqualTo(2));
      }
      expect(label.bounds.left, greaterThanOrEqualTo(bar.left));
      expect(label.bounds.top, greaterThanOrEqualTo(line.from.y));
      expect(label.bounds.bottom, lessThanOrEqualTo(hooks.first.to.y));
    });

    test('a volta continued on the next system has neither label nor left '
        'hook', () {
      final base = scoreOf([
        quartersOf(1, 'C5'),
        quartersOf(5, 'C5'),
        quartersOf(9, 'C5'),
      ]);
      final score = applied(
        EditSession.start(base).run(
          SetVolta(base.measures[0].id, base.measures[1].id, const Volta([1])),
        ),
      ).score;
      final sheet = sheetOf(score, width: narrow);
      expect(sheet.systemOf(score.measures[1].id), 1);

      final first = sheet.systemAt(0);
      expect(textsOf(first, '1.'), hasLength(1));
      final opening = bracketOf(first).where(isVertical).single;
      expect(opening.from.x, closeTo(first.bars[0].left + thickness / 2, 1e-9));

      final second = sheet.systemAt(1);
      expect(textsOf(second, '1.'), isEmpty);
      final closing = bracketOf(second).where(isVertical).single;
      expect(
        closing.from.x,
        closeTo(second.bars[0].right - thickness / 2, 1e-9),
      );
      expect(
        bracketOf(second).where(isHorizontal).single.from.x,
        closeTo(second.bars[0].left, 1e-9),
      );
    });
    test('an open volta has no hook where it ends', () {
      final base = scoreOf([quartersOf(1, 'C5'), quartersOf(5, 'C5')]);
      final score = applied(
        EditSession.start(base).run(
          SetVolta(
            base.measures[1].id,
            base.measures[1].id,
            const Volta([2], open: true),
          ),
        ),
      ).score;
      final system = sheetOf(score).systemAt(0);
      final bar = system.bars[1];
      final hook = bracketOf(system).where(isVertical).single;

      expect(hook.from.x, closeTo(bar.left + thickness / 2, 1e-9));
      expect(
        bracketOf(system).where(isHorizontal).single.to.x,
        closeTo(bar.right, 1e-9),
      );
    });

    test('two voltas side by side are two brackets, each with its label', () {
      final base = scoreOf([quartersOf(1, 'C5'), quartersOf(5, 'C5')]);
      final first = applied(
        EditSession.start(base).run(
          SetVolta(base.measures[0].id, base.measures[0].id, const Volta([1])),
        ),
      );
      final score = applied(
        first.run(
          SetVolta(base.measures[1].id, base.measures[1].id, const Volta([2])),
        ),
      ).score;
      final system = sheetOf(score).systemAt(0);
      final lines = bracketOf(system).where(isHorizontal).toList()
        ..sort((a, b) => a.from.x.compareTo(b.from.x));

      expect(lines, hasLength(2));
      expect(lines.first.to.x, closeTo(system.bars[0].right, 1e-9));
      expect(lines.last.from.x, closeTo(system.bars[1].left, 1e-9));
      expect(bracketOf(system).where(isVertical), hasLength(4));
      expect(textsOf(system, '1.'), hasLength(1));
      expect(textsOf(system, '2.'), hasLength(1));
    });

    test('a volta over the first bar of a system clears the clef', () {
      final base = scoreOf([quartersOf(1, 'C5'), quartersOf(5, 'C5')]);
      final score = applied(
        EditSession.start(base).run(
          SetVolta(base.measures[0].id, base.measures[0].id, const Volta([1])),
        ),
      ).score;
      final system = sheetOf(score).systemAt(0);
      final clef = glyphsOf(
        system,
      ).firstWhere((glyph) => glyph.glyph == Glyph.gClef);
      final label = textsOf(system, '1.').single;
      final hook = bracketOf(system).where(isVertical).first;

      expect(clef.bounds.top, lessThan(topOf(system)));
      expect(label.bounds.bottom, lessThanOrEqualTo(clef.bounds.top));
      expect(hook.to.y, lessThanOrEqualTo(clef.bounds.top));
    });
  });

  group('a system that ends with a courtesy signature', () {
    test('a tie, a slur and a hairpin leaving the system stop before the '
        'courtesy key signature', () {
      var score = scoreOf([
        [...quartersOf(1, 'C5').take(3), chordOf(4, 'C5', tie: true)],
        quartersOf(5, 'C5'),
      ]);
      score = applied(
        EditSession.start(score).run(
          SetKey(from: score.measures[1].id, key: const KeySignature(3)),
        ),
      ).score;
      score = withSlur(
        score,
        pointAt(score, 0, at(1, 4)),
        pointAt(score, 1, at(1, 4)),
      );
      score = withSpanner(
        score,
        const Hairpin(crescendo: true),
        pointAt(score, 0, at(1, 4)),
        pointAt(score, 1, at(1, 4)),
      );
      final sheet = sheetOf(score, width: narrow);
      expect(sheet.systemCount, 2);
      final system = sheet.systemAt(0);
      final courtesy = glyphsOf(system)
          .where((glyph) => glyph.glyph == Glyph.accidentalSharp)
          .map((glyph) => glyph.bounds.left)
          .where((left) => left > system.bars.single.right)
          .reduce(min);

      expect(curvesOf(system), hasLength(2));
      for (final curve in curvesOf(system)) {
        expect(curve.bounds.right, lessThanOrEqualTo(courtesy));
      }
      final hairpin = linesOf(
        system,
        owner: const SpannerOwner(SpannerId(901)),
      );
      expect(hairpin, hasLength(2));
      for (final line in hairpin) {
        expect(line.to.x, lessThanOrEqualTo(courtesy));
      }
    });
  });

  group('pieces', () {
    test('pieceStart and pieceEnd agree with the model over random edits', () {
      var compared = 0;
      for (final seed in [1, 2, 3, 4]) {
        final random = Random(seed);
        var score = blankScore(parts: const [clarinet, piano, drums], bars: 24);
        for (var step = 0; step < 200; step++) {
          score = randomEdit(score, random);
          for (final measure in score.measures) {
            final view = score.measureView(measure.id);
            for (final segment in view.spanners) {
              final spanner = segment.spanner;
              final staff = view.staves
                  .where((staff) => staff.source.staff == spanner.staff)
                  .firstOrNull;
              if (staff == null) {
                continue;
              }
              compared++;
              final voice = spanner.voice ?? VoiceSlot.one;
              final start = pieceStart(segment, staff);
              final end = pieceEnd(segment, staff, measure.length);
              final reason = 'seed $seed step $step ${spanner.kind}';
              if (!segment.startsHere) {
                expect(start, (at: Moment.zero, event: null), reason: reason);
              } else if (spanner.kind.joinsNotes || spanner.kind is TrillLine) {
                final anchor = score.anchorAt(
                  spanner.staff,
                  voice,
                  spanner.first,
                );
                expect(start.event, anchor?.event.id, reason: reason);
                expect(start.at, anchor?.onset, reason: reason);
              } else {
                expect(start, (
                  at: spanner.first.offset,
                  event: null,
                ), reason: reason);
              }
              if (!segment.endsHere) {
                expect(end, (
                  at: Moment.zero + measure.length,
                  event: null,
                ), reason: reason);
              } else if (spanner.kind.joinsNotes || spanner.kind is TrillLine) {
                final anchor = score.anchorAt(
                  spanner.staff,
                  voice,
                  spanner.last,
                );
                expect(end.event, anchor?.event.id, reason: reason);
                expect(end.at, anchor?.onset, reason: reason);
              } else {
                expect(end, (
                  at: score.lineEnd(spanner),
                  event: null,
                ), reason: reason);
              }
            }
          }
        }
      }
      expect(compared, greaterThan(1000));
    });
  });
}
