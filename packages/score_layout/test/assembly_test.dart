import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/signatures.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_layout/src/system_layout.dart';
import 'package:score_layout/src/text.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/support.dart';
import 'support/fake_measurer.dart';

const EngravingStyle style = EngravingStyle.standard;
const FakeMeasurer text = FakeMeasurer();

SheetLayout sheetOf(
  Score score, {
  double width = 120,
  EngravingStyle style = style,
}) => SheetLayout(score, width: width, text: text, style: style);

SystemLayout systemOf(
  Score score, {
  double width = 120,
  EngravingStyle style = style,
  int index = 0,
}) => sheetOf(score, width: width, style: style).systemAt(index);

Score edit(Score score, Edit edit) =>
    applied(EditSession.start(score).run(edit)).score;

Score quarters(Score score, int bar, {int staff = 0, String pitch = 'C5'}) =>
    fill(score, bar, [
      for (var beat = 0; beat < 4; beat++)
        chordOf(10000 + bar * 100 + staff * 10 + beat, pitch),
    ], staff: staff);

Score ensemble(List<PartTemplate> parts, int bars) {
  var score = blankScore(parts: parts, bars: bars);
  for (var bar = 0; bar < bars; bar++) {
    score = quarters(score, bar);
  }
  return score;
}

Score oneLine(Score score, int index) {
  final part = score.parts[index];
  return score.copyWith(
    parts: score.parts.replaceAt(
      index,
      Part(
        id: part.id,
        name: part.name,
        shortName: part.shortName,
        instrument: part.instrument,
        staves: Seq([
          for (final staff in part.staves) Staff(id: staff.id, lines: 1),
        ]),
      ),
    ),
  );
}

Iterable<GlyphDraw> glyphsOf(SystemLayout system, Glyph glyph) =>
    system.drawables.whereType<GlyphDraw>().where((g) => g.glyph == glyph);

Iterable<TextDraw> namesOf(
  SystemLayout system, {
  EngravingStyle style = style,
}) => system.drawables.whereType<TextDraw>().where(
  (text) => text.spec == style.specOf(TextRole.partName),
);

/// Vertical lines of [system] with their x in [from] to [to], left to
/// right, and the repeat dots among them, each named by its piece.
List<String> piecesBetween(SystemLayout system, double from, double to) {
  final defaults = style.font.defaults;
  final pieces =
      <(double, String)>[
          for (final drawable in system.drawables)
            switch (drawable) {
              LineDraw(
                from: final a,
                to: final b,
                :final thickness,
                :final dash,
              )
                  when a.x == b.x && a.x >= from - 1e-9 && a.x <= to + 1e-9 =>
                (
                  a.x,
                  switch (dash) {
                    LineDash.dashed => 'dashed',
                    LineDash.dotted => 'dotted',
                    LineDash.solid
                        when thickness == defaults.thickBarlineThickness =>
                      'thick',
                    LineDash.solid
                        when thickness == defaults.thinBarlineThickness =>
                      'thin',
                    LineDash.solid => 'line $thickness',
                  },
                ),
              GlyphDraw(glyph: Glyph.repeatDots, :final bounds)
                  when bounds.left >= from - 1e-9 &&
                      bounds.right <= to + 1e-9 =>
                (bounds.left, 'dots'),
              _ => (double.nan, ''),
            },
        ]
        ..removeWhere((piece) => piece.$1.isNaN)
        ..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, name) in pieces) name];
}

List<(double, double)> spansBetween(
  SystemLayout system,
  double from,
  double to,
) => [
  for (final drawable in system.drawables)
    if (drawable case LineDraw(from: final a, to: final b)
        when a.x == b.x && a.x >= from - 1e-9 && a.x <= to + 1e-9)
      (a.y, b.y),
];

/// What stands at a barline of [system] with its centre from [from] to
/// [to], in x order: a clef change, a barline or repeat sign, a key or a
/// meter. A run of one kind is one entry holding the union of its ink.
List<(String, Box)> standingBetween(
  SystemLayout system,
  double from,
  double to,
) {
  final ink = <(String, Box)>[
    for (final drawable in system.drawables)
      if (kindOf(drawable) case final kind?
          when (drawable.bounds.left + drawable.bounds.right) / 2 >= from &&
              (drawable.bounds.left + drawable.bounds.right) / 2 <= to)
        (kind, drawable.bounds),
  ]..sort((a, b) => a.$2.left.compareTo(b.$2.left));
  final runs = <(String, Box)>[];
  for (final (kind, box) in ink) {
    if (runs.lastOrNull case (final last, final run) when last == kind) {
      runs.last = (kind, run.union(box));
    } else {
      runs.add((kind, box));
    }
  }
  return runs;
}

/// What [drawable] is at a barline. A note's own accidental is owned by
/// its event, which tells it apart from a key signature's.
String? kindOf(Drawable drawable) => switch (drawable) {
  LineDraw(owner: null, :final from, :final to) when from.x == to.x =>
    'barline',
  GlyphDraw(glyph: Glyph.repeatDots) => 'barline',
  GlyphDraw(
    owner: null,
    glyph: Glyph.gClefChange || Glyph.fClefChange || Glyph.cClefChange,
  ) =>
    'clef',
  GlyphDraw(owner: null, :final glyph)
      when glyph.name.startsWith('accidental') =>
    'key',
  GlyphDraw(owner: null, :final glyph) when glyph.name.startsWith('timeSig') =>
    'meter',
  _ => null,
};

/// Expects [runs] to be of [kinds] in order, each wholly right of the one
/// before it.
void expectStanding(List<(String, Box)> runs, List<String> kinds) {
  expect([for (final (kind, _) in runs) kind], kinds);
  for (var i = 1; i < runs.length; i++) {
    expect(
      runs[i].$2.left,
      greaterThan(runs[i - 1].$2.right),
      reason: '${runs[i].$1} stands clear of ${runs[i - 1].$1}',
    );
  }
}

void main() {
  group('barlines', () {
    final two = quarters(quarters(blankScore(parts: const [clarinet]), 0), 1);

    for (final (barline, pieces) in [
      (Barline.regular, ['thin']),
      (Barline.doubleBar, ['thin', 'thin']),
      (Barline.finalBar, ['thin', 'thick']),
      (Barline.heavy, ['thick']),
      (Barline.dashed, ['dashed']),
      (Barline.dotted, ['dotted']),
      (Barline.invisible, <String>[]),
    ]) {
      test('$barline draws $pieces between its bar and the next', () {
        final system = systemOf(
          edit(two, SetBarline(two.measures[0].id, barline)),
        );
        final [first, second] = system.bars;

        expect(piecesBetween(system, first.right, second.left), pieces);
        expect(
          second.left - first.right,
          pieces.isEmpty ? 0 : greaterThan(0),
          reason: 'the next bar starts where the barline ends',
        );
      });
    }

    test(
      'the last bar of the score ends in the barline the model gives it',
      () {
        final system = systemOf(two);
        final ended = systemOf(
          edit(two, SetBarline(two.measures[1].id, Barline.finalBar)),
        );

        expect(
          piecesBetween(system, system.bars.last.right, system.width),
          ['thin'],
        );
        expect(piecesBetween(ended, ended.bars.last.right, ended.width), [
          'thin',
          'thick',
        ]);
      },
    );

    test('a start repeat draws thick, thin and dots before its bar, in '
        'place of the barline of the bar before', () {
      final system = systemOf(
        edit(two, SetRepeatStart(two.measures[1].id, start: true)),
      );
      final [first, second] = system.bars;
      final content = second.time.stops.first.$2;

      expect(piecesBetween(system, first.right, second.left), <String>[]);
      expect(piecesBetween(system, second.left, content), [
        'thick',
        'thin',
        'dots',
      ]);
    });

    test('a start repeat stands in for the barline before it when the key it '
        'prints has no glyphs', () {
      final score = blankScore(parts: const [drums]);
      final ids = barIds(score);
      final system = systemOf(
        edit(
          edit(score, SetRepeatStart(ids[1], start: true)),
          SetKey(from: ids[1], key: const KeySignature(2)),
        ),
      );
      final [first, second] = system.bars;
      final content = second.time.stops.first.$2;

      expect(piecesBetween(system, first.right, second.left), <String>[]);
      expect(piecesBetween(system, second.left, content), [
        'thick',
        'thin',
        'dots',
      ]);
    });

    test('a start repeat keeps a double barline before it', () {
      final system = systemOf(
        edit(
          edit(two, SetRepeatStart(two.measures[1].id, start: true)),
          SetBarline(two.measures[0].id, Barline.doubleBar),
        ),
      );
      final [first, second] = system.bars;

      expect(piecesBetween(system, first.right, second.left), [
        'thin',
        'thin',
      ]);
    });

    test('a start repeat keeps the barline of the bar before when a '
        'signature stands between them', () {
      final system = systemOf(
        edit(
          edit(two, SetRepeatStart(two.measures[1].id, start: true)),
          SetKey(from: two.measures[1].id, key: const KeySignature(2)),
        ),
      );
      final [first, second] = system.bars;
      final content = second.time.stops.first.$2;

      expect(piecesBetween(system, first.right, second.left), ['thin']);
      expect(piecesBetween(system, second.left, content), [
        'thick',
        'thin',
        'dots',
      ]);
    });

    test('an end repeat draws dots, thin and thick after its bar', () {
      final system = systemOf(
        edit(two, SetRepeatEnd(two.measures[0].id, const RepeatEnd())),
      );
      final [first, second] = system.bars;

      expect(piecesBetween(system, first.right, second.left), [
        'dots',
        'thin',
        'thick',
      ]);
    });

    test('an end repeat meeting a start repeat is one sign centred on the '
        'boundary', () {
      final system = systemOf(
        edit(
          edit(two, SetRepeatEnd(two.measures[0].id, const RepeatEnd())),
          SetRepeatStart(two.measures[1].id, start: true),
        ),
      );
      final [first, second] = system.bars;
      final content = second.time.stops.first.$2;
      final thick = system.drawables.whereType<LineDraw>().singleWhere(
        (line) =>
            line.from.x == line.to.x &&
            line.from.x > first.right &&
            line.thickness == style.font.defaults.thickBarlineThickness,
      );

      expect(piecesBetween(system, first.right, content), [
        'dots',
        'thin',
        'thick',
        'thin',
        'dots',
      ]);
      expect(thick.from.x, closeTo(second.left, 1e-9));
    });

    test('a barline runs through the staves of a part and breaks between '
        'parts, and repeat dots stand on every staff', () {
      final score = ensemble(const [clarinet, piano], 2);
      final system = systemOf(
        edit(score, SetRepeatEnd(score.measures[0].id, const RepeatEnd())),
      );
      final [first, second] = system.bars;
      final tops = [for (final staff in system.staves) staff.top];

      expect(spansBetween(system, first.right, second.left), [
        (tops[0], tops[0] + staffHeight),
        (tops[1], tops[2] + staffHeight),
        (tops[0], tops[0] + staffHeight),
        (tops[1], tops[2] + staffHeight),
      ]);
      expect(
        glyphsOf(system, Glyph.repeatDots).map((dots) => dots.origin.y),
        [for (final top in tops) top + staffHeight],
      );
    });
  });

  group('the lead', () {
    test('a two-staff part has a brace over both staves, braceWidth wide, on '
        'a short and a tall system, with barlines joining the staves', () {
      final short = quarters(quarters(blankScore(parts: const [piano]), 0), 1);
      final tall = fill(
        fill(short, 0, [chordOf(20001, 'C3', value: NoteValue.whole)]),
        0,
        [chordOf(20002, 'C6', value: NoteValue.whole)],
        staff: 1,
      );
      final braces = <GlyphDraw>[];

      for (final score in [short, tall]) {
        final system = systemOf(score);
        final tops = [for (final staff in system.staves) staff.top];
        final brace = glyphsOf(system, Glyph.brace).single;
        final indent = system.bars.first.left;

        expect(tops, hasLength(2));
        expect(
          brace.bounds,
          Box(indent - braceWidth, tops[0], indent, tops[1] + staffHeight),
        );
        expect(
          spansBetween(system, system.bars.last.right, system.width),
          [(tops[0], tops[1] + staffHeight)],
        );
        braces.add(brace);
      }

      expect(
        braces[1].bounds.bottom - braces[1].bounds.top,
        greaterThan(braces[0].bounds.bottom - braces[0].bounds.top + 4),
      );
      expect(braces[1].scale, braces[0].scale);
      expect(braces[1].stretch, greaterThan(braces[0].stretch));
    });

    test('a hidden part draws no staff, name or brace', () {
      final score = ensemble(const [clarinet, piano], 2);
      final shown = systemOf(score);
      final system = systemOf(hidePart(score, 1));

      expect(shown.staves, hasLength(3));
      expect(system.staves.map((staff) => staff.staff), [
        score.staves.first.id,
      ]);
      expect(glyphsOf(system, Glyph.brace), isEmpty);
      expect(namesOf(system).map((text) => text.text), ['Clarinet in B♭']);
      expect(
        system.drawables.where((d) => d.ink == InkRole.staffLine),
        hasLength(5),
      );
      expect(system.height, lessThan(shown.height));
    });

    test('the first system is indented by the full names and later ones by '
        'the short names, each name centred on its part', () {
      const short = PartTemplate(
        name: 'Clarinet in B♭',
        shortName: 'Cl.',
        instrument: Instrument(key: 'clarinet-b-flat', program: 71),
      );
      final layout = sheetOf(ensemble(const [short, piano], 12), width: 100);
      final first = layout.systemAt(0);
      final second = layout.systemAt(1);
      final tops = [for (final staff in first.staves) staff.top];
      final names = {for (final text in namesOf(first)) text.text: text};
      final clarinetName = names['Clarinet in B♭']!;
      final pianoName = names['Piano']!;

      expect(names.keys, hasLength(2));
      expect(clarinetName.spec, style.specOf(TextRole.partName));
      expect(clarinetName.bounds.right, pianoName.bounds.right);
      expect(
        first.bars.first.left - braceWidth - clarinetName.bounds.right,
        closeTo(1, 1e-9),
      );
      expect(
        (clarinetName.bounds.top + clarinetName.bounds.bottom) / 2,
        closeTo(tops[0] + staffHeight / 2, 1e-9),
      );
      expect(
        (pianoName.bounds.top + pianoName.bounds.bottom) / 2,
        closeTo((tops[1] + tops[2] + staffHeight) / 2, 1e-9),
      );
      expect(namesOf(second).map((text) => text.text), ['Cl.']);
      expect(second.bars.first.left, lessThan(first.bars.first.left));
      expect(
        second.bars.first.left -
            braceWidth -
            namesOf(second).single.bounds.right,
        closeTo(1, 1e-9),
      );
    });

    test('a name taller than its part takes its room from the system, half '
        'above the first staff of the part and half below the last', () {
      for (final (part, size) in const [(clarinet, 20.0), (piano, 40.0)]) {
        final tall = EngravingStyle(
          barNumbers: false,
          text: {TextRole.partName: TextSpec(size: size)},
        );
        final system = systemOf(ensemble([part], 2), style: tall);
        final name = namesOf(system, style: tall).single;
        final tops = [for (final staff in system.staves) staff.top];

        expect(name.text, part.name);
        expect(name.bounds.bottom - name.bounds.top, size);
        expect(name.bounds.top, closeTo(0, 1e-9), reason: part.name);
        expect(
          name.bounds.bottom,
          closeTo(system.height, 1e-9),
          reason: part.name,
        );
        expect(
          (name.bounds.top + name.bounds.bottom) / 2,
          closeTo((tops.first + tops.last + staffHeight) / 2, 1e-9),
          reason: part.name,
        );
      }
    });

    test('a name reaches down beside the lyrics under its part, and moves '
        'them only when it reaches below them', () {
      final score = ensemble(const [clarinet], 2);
      final sung = edit(
        score,
        SetLyric(
          EventRef(
            measure: score.measures.first.id,
            staff: score.staves.first.id,
            id: const EventId(10000),
          ),
          1,
          const Lyric(verse: 1, text: 'la'),
        ),
      );
      double lyricUnderStaff(SystemLayout system) =>
          system.drawables
              .whereType<TextDraw>()
              .singleWhere((text) => text.text == 'la')
              .bounds
              .top -
          system.staves.single.top;
      EngravingStyle named(double size) => EngravingStyle(
        barNumbers: false,
        text: {TextRole.partName: TextSpec(size: size)},
      );
      final plain = systemOf(sung, style: named(2));
      final beside = systemOf(sung, style: named(8));
      final below = systemOf(sung, style: named(20));
      final name = namesOf(below, style: named(20)).single;

      expect(lyricUnderStaff(beside), closeTo(lyricUnderStaff(plain), 1e-9));
      expect(beside.height, closeTo(plain.height, 1e-9));
      expect(name.bounds.top, closeTo(0, 1e-9));
      expect(name.bounds.bottom, closeTo(below.height, 1e-9));
      expect(lyricUnderStaff(below), greaterThan(lyricUnderStaff(plain) + 1));
    });

    test('the lyrics between the staves of a part are part of its height', () {
      final score = ensemble(const [piano], 2);
      final sung = edit(
        score,
        SetLyric(
          EventRef(
            measure: score.measures.first.id,
            staff: score.staves.first.id,
            id: const EventId(10000),
          ),
          1,
          const Lyric(verse: 1, text: 'la'),
        ),
      );
      const tall = EngravingStyle(
        barNumbers: false,
        text: {TextRole.partName: TextSpec(size: 40)},
      );
      final system = systemOf(sung, style: tall);
      final name = namesOf(system, style: tall).single;

      expect(
        system.staves.last.top - system.staves.first.top,
        greaterThan(
          systemOf(score, style: tall).staves.last.top -
              systemOf(score, style: tall).staves.first.top +
              2,
        ),
      );
      expect(name.bounds.top, closeTo(0, 1e-9));
      expect(name.bounds.bottom, closeTo(system.height, 1e-9));
    });

    test('a bar number stays as far above the top staff under a tall name '
        'as under a short one', () {
      final score = ensemble(const [clarinet], 2);
      double numberOverStaff(double size) {
        final layout = sheetOf(
          score,
          style: EngravingStyle(
            text: {TextRole.partName: TextSpec(size: size)},
          ),
        );
        return layout.systemAt(0).staves.first.top -
            layout.labelOf(0)!.bounds.bottom;
      }

      expect(numberOverStaff(20), closeTo(numberOverStaff(2), 1e-9));
      expect(numberOverStaff(2), greaterThan(0));
    });

    test('a tall name of one part keeps clear of the name of the next', () {
      const tall = EngravingStyle(
        barNumbers: false,
        text: {TextRole.partName: TextSpec(size: 20)},
      );
      final system = systemOf(
        ensemble(const [clarinet, drums], 2),
        style: tall,
      );
      final names = namesOf(system, style: tall).toList();

      expect(names.map((name) => name.text), ['Clarinet in B♭', 'Drums']);
      expect(
        names[1].bounds.top - names[0].bounds.bottom,
        closeTo(tall.staffGap, 1e-9),
      );
      expect(names[0].bounds.top, closeTo(0, 1e-9));
      expect(names[1].bounds.bottom, closeTo(system.height, 1e-9));
    });
  });

  group('staff lines', () {
    test('run from the indent to the right edge, five per staff and one for '
        'a one-line staff', () {
      final layout = sheetOf(
        oneLine(ensemble(const [clarinet, drums], 12), 1),
        width: 100,
      );
      final system = layout.systemAt(0);
      final tops = [for (final staff in system.staves) staff.top];
      final lines = system.drawables
          .whereType<LineDraw>()
          .where((line) => line.ink == InkRole.staffLine)
          .toList();

      expect(layout.systemCount, greaterThan(1));
      expect(system.staves.map((staff) => staff.lines), [5, 1]);
      expect(lines.map((line) => line.from.y), [
        for (final step in const [0, 2, 4, 6, 8]) tops[0] + yOfStep(step),
        tops[1] + yOfStep(4),
      ]);
      for (final line in lines) {
        expect(line.from.x, system.bars.first.left);
        expect(line.to.x, closeTo(system.width, 1e-6));
        expect(line.to.y, line.from.y);
        expect(line.thickness, style.font.defaults.staffLineThickness);
      }
    });

    test('reach past the last barline to hold a courtesy key, which starts '
        'where that barline ends', () {
      final score = ensemble(const [clarinet], 12);
      final at = sheetOf(score, width: 100).firstBarOf(1);
      final changed = edit(
        edit(score, SetBreak(at, LayoutBreak.system)),
        SetKey(from: at, key: const KeySignature(3)),
      );
      final system = systemOf(changed, width: 100);
      final last = system.bars.last;
      final sharps = glyphsOf(
        system,
        Glyph.accidentalSharp,
      ).where((sharp) => sharp.bounds.left > last.right).toList();
      final staffLine = system.drawables.whereType<LineDraw>().firstWhere(
        (line) => line.ink == InkRole.staffLine,
      );
      final lastBar = layoutBar(changed.measureView(last.measure), style, text);
      final courtesy = layoutBar(
        changed.measureView(at),
        style,
        text,
      ).heads.courtesy.after;
      final courtesyLeft = last.right + lastBar.slices.last.rod;

      expect(
        sharps,
        hasLength(5),
        reason: 'a clarinet in B flat writes A major as B major',
      );
      expect(piecesBetween(system, last.right, courtesyLeft), ['thin']);
      expect(
        sharps.first.bounds.left,
        closeTo(courtesyLeft + courtesy.items.first.drawable.bounds.left, 1e-9),
      );
      expect(staffLine.to.x, closeTo(courtesyLeft + courtesy.width, 1e-9));
      for (final sharp in sharps) {
        expect(sharp.bounds.right, lessThanOrEqualTo(staffLine.to.x));
      }
      expect(system.width, 100);
    });
  });

  group('a rest run', () {
    for (final count in [5, 12]) {
      test('of $count bars at the start of a system draws $count over an '
          'H-bar and shares its content among its bars, after the head', () {
        final score = blankScore(parts: const [clarinet], bars: count + 2);
        final system = systemOf(
          quarters(
            quarters(
              edit(score, SetBreak(barIds(score)[1], LayoutBreak.system)),
              0,
            ),
            count + 1,
          ),
          width: 80,
          style: const EngravingStyle(multiMeasureRests: true),
          index: 1,
        );
        final left = glyphsOf(system, Glyph.restHBarLeft).single;
        final right = glyphsOf(system, Glyph.restHBarRight).single;
        final head = system.drawables.whereType<GlyphDraw>().where(
          (glyph) => glyph.bounds.left < left.bounds.left,
        );
        final digits =
            system.drawables
                .whereType<GlyphDraw>()
                .where(
                  (glyph) =>
                      timeSigDigits.contains(glyph.glyph) &&
                      glyph.bounds.left >= left.bounds.left,
                )
                .toList()
              ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
        final bar = system.drawables.whereType<LineDraw>().singleWhere(
          (line) =>
              line.from.y == line.to.y &&
              line.from.x >= left.bounds.left &&
              line.to.x <= right.bounds.right,
        );
        final rests = system.bars.sublist(0, count);
        final from = rests.first.time.stops.first.$2;
        final each = (rests.last.right - from) / count;
        final topLine = system.drawables.whereType<LineDraw>().firstWhere(
          (line) =>
              line.from.y == line.to.y &&
              line.from.y == system.staves.first.yOf(0),
        );

        expect(digits.map((digit) => digit.glyph), [
          for (final digit in '$count'.runes) timeSigDigits[digit - 0x30],
        ]);
        expect(
          (digits.first.bounds.left + digits.last.bounds.right) / 2,
          closeTo((left.bounds.left + right.bounds.right) / 2, 0.1),
        );
        for (final digit in digits) {
          expect(digit.bounds.bottom, lessThanOrEqualTo(bar.bounds.top));
        }
        expect(
          bar.from.y,
          inInclusiveRange(left.bounds.top, left.bounds.bottom),
        );
        expect(system.bars, hasLength(count + 1));
        expect(head, isNotEmpty);
        for (final glyph in head) {
          expect(glyph.bounds.left, greaterThanOrEqualTo(rests.first.left));
          expect(glyph.bounds.right, lessThanOrEqualTo(from));
        }
        expect(rests.first.left, lessThan(from));
        for (final (index, rest) in rests.indexed) {
          final share = from + each * index;
          expect(
            rest.left,
            index == 0 ? topLine.from.x : closeTo(share, 1e-9),
          );
          expect(rest.right, closeTo(share + each, 1e-9));
          expect(rest.time.stops.first.$2, closeTo(share, 1e-9));
          expect(rest.time.stops.last.$2, rest.right);
        }
        expect(system.bars.last.left, greaterThan(rests.last.right));
        expect(left.bounds.left, greaterThanOrEqualTo(from));
        expect(right.bounds.right, lessThanOrEqualTo(rests.last.right));
      });
    }

    test('draws the H-bar and the count on every staff', () {
      final system = systemOf(
        quarters(blankScore(parts: const [clarinet, piano], bars: 5), 4),
        width: 80,
        style: const EngravingStyle(multiMeasureRests: true),
      );
      final lefts = glyphsOf(system, Glyph.restHBarLeft).toList();
      final rights = glyphsOf(system, Glyph.restHBarRight).toList();
      final lines = {for (final staff in system.staves) staff.yOf(4)};
      final counts = system.drawables.whereType<GlyphDraw>().where(
        (glyph) =>
            glyph.glyph == Glyph.timeSig3 &&
            glyph.bounds.left >= lefts.first.bounds.left,
      );

      expect(system.staves, hasLength(3));
      expect(lefts.map((end) => end.origin.y).toSet(), lines);
      expect(rights.map((end) => end.origin.y).toSet(), lines);
      expect(counts.map((count) => count.bounds.bottom).toSet(), hasLength(3));
      for (final (index, count) in counts.indexed) {
        expect(count.bounds.bottom, lessThan(lefts[index].bounds.top));
      }
    });
  });

  group('a placed bar', () {
    test('maps time to x through its slices', () {
      final system = systemOf(
        quarters(blankScore(parts: const [clarinet], bars: 1), 0),
        width: 60,
      );
      final bar = system.bars.single;
      final stops = bar.time.stops;

      expect(stops.map((stop) => stop.$1), [
        Moment.zero,
        at(1, 4),
        at(1, 2),
        at(3, 4),
        at(1, 1),
      ]);
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i].$2, greaterThan(stops[i - 1].$2));
      }
      expect(stops.last.$2, bar.right);
      expect(bar.length, Meter.fourFour.length);
      expect(
        bar.time.xAt(at(1, 8)),
        closeTo((stops[0].$2 + stops[1].$2) / 2, 1e-9),
      );
      expect(bar.time.xAt(at(3, 2)), bar.right);
    });

    test('centres a measure rest in the bar at the system\'s stretch', () {
      var score = quarters(blankScore(parts: const [clarinet], bars: 3), 0);
      score = edit(score, SetBreak(score.measures[2].id, LayoutBreak.system));
      final system = systemOf(score, width: 60);
      final rest = glyphsOf(system, Glyph.restWhole).single;
      final bar = system.bars[1];
      final from = bar.time.stops.first.$2;

      expect(bar.right - from, greaterThan(10));
      expect(
        (rest.bounds.left + rest.bounds.right) / 2,
        closeTo((from + bar.right) / 2, 1e-9),
      );
    });
  });

  group('a clef change at a barline', () {
    final two = quarters(quarters(blankScore(parts: const [clarinet]), 0), 1);
    final ids = barIds(two);
    final clefChanged = edit(
      two,
      SetClef(
        staff: two.staves.single.id,
        at: ScorePoint(ids[1], Moment.zero),
        clef: Clef.bass,
      ),
    );
    final signed = edit(
      edit(clefChanged, SetKey(from: ids[1], key: const KeySignature(1))),
      SetMeter(from: ids[1], meter: Meter.cut, content: MeterContent.keepBars),
    );
    final endRepeat = SetRepeatEnd(ids[0], const RepeatEnd());
    final startRepeat = SetRepeatStart(ids[1], start: true);

    for (final (name, score, kinds, pieces) in [
      (
        'with a key and meter',
        signed,
        ['clef', 'barline', 'key', 'meter'],
        ['thin'],
      ),
      (
        'with a key, a meter and a start repeat',
        edit(signed, startRepeat),
        ['clef', 'barline', 'key', 'meter', 'barline'],
        ['thin', 'thick', 'thin', 'dots'],
      ),
      (
        'with a key and meter after an end repeat',
        edit(signed, endRepeat),
        ['clef', 'barline', 'key', 'meter'],
        ['dots', 'thin', 'thick'],
      ),
      (
        'with a start repeat in place of the barline',
        edit(clefChanged, startRepeat),
        ['clef', 'barline'],
        ['thick', 'thin', 'dots'],
      ),
      (
        'with an end repeat meeting a start repeat',
        edit(edit(clefChanged, endRepeat), startRepeat),
        ['clef', 'barline'],
        ['dots', 'thin', 'thick', 'thin', 'dots'],
      ),
    ]) {
      test('stands small before every barline sign, at the end of the bar '
          'before, $name: $kinds', () {
        final system = systemOf(score);
        final [first, second] = system.bars;
        final content = second.time.stops.first.$2;
        final runs = standingBetween(system, first.right, content);
        final notes = system.drawables.where(
          (drawable) =>
              drawable.owner != null &&
              drawable.bounds.left < runs.first.$2.left,
        );

        expectStanding(runs, kinds);
        expect(piecesBetween(system, first.right, content), pieces);
        expect(runs.first.$2.left, greaterThanOrEqualTo(first.right - 1e-9));
        expect(
          notes.map((drawable) => drawable.bounds.right),
          everyElement(lessThanOrEqualTo(runs.first.$2.left)),
          reason: 'the clef stands clear of the bar before',
        );
        expect(glyphsOf(system, Glyph.fClefChange), hasLength(1));
      });
    }

    final startsSystem = () {
      final score = ensemble(const [clarinet], 4);
      final ids = barIds(score);
      return [
        SetBreak(ids[2], LayoutBreak.system),
        SetClef(
          staff: score.staves.single.id,
          at: ScorePoint(ids[2], Moment.zero),
          clef: Clef.bass,
        ),
        SetKey(from: ids[2], key: const KeySignature(1)),
        SetMeter(
          from: ids[2],
          meter: Meter.cut,
          content: MeterContent.keepBars,
        ),
      ].fold(score, edit);
    }();

    test('starting a system is printed in full there, and small before the '
        'last barline of the system before, with the courtesy key and meter '
        'after that barline', () {
      final sheet = sheetOf(startsSystem);
      final ending = sheet.systemAt(0);
      final starting = sheet.systemAt(1);
      final last = ending.bars.last;

      expect(ending.bars, hasLength(2));
      expectStanding(standingBetween(ending, last.right, ending.width), [
        'clef',
        'barline',
        'key',
        'meter',
      ]);
      expect(piecesBetween(ending, last.right, ending.width), ['thin']);
      expect(
        ending.drawables.map((drawable) => drawable.bounds.right),
        everyElement(lessThanOrEqualTo(ending.width + 1e-9)),
      );
      expect(glyphsOf(ending, Glyph.fClef), isEmpty);
      expect(glyphsOf(starting, Glyph.fClef), hasLength(1));
      expect(glyphsOf(starting, Glyph.fClefChange), isEmpty);
      expect(glyphsOf(starting, Glyph.gClef), isEmpty);
    });

    test('starting a system is printed small before the last barline of the '
        'system before with courtesy signatures off, and the key and meter '
        'are not', () {
      final system = sheetOf(
        startsSystem,
        style: const EngravingStyle(courtesySignatures: false),
      ).systemAt(0);
      final last = system.bars.last;
      final runs = standingBetween(system, last.right, system.width);
      final staffLines = system.drawables.whereType<LineDraw>().where(
        (line) => line.owner == null && line.from.y == line.to.y,
      );

      expectStanding(runs, ['clef', 'barline']);
      expect(runs.last.$2.right, closeTo(system.width, 1e-9));
      expect(
        staffLines.map((line) => line.to.x),
        everyElement(closeTo(system.width, 1e-9)),
      );
    });

    test('on one staff of a part stands before the barline that runs through '
        'both staves', () {
      final score = ensemble(const [piano], 2);
      final system = systemOf(
        edit(
          score,
          SetClef(
            staff: score.staves[1].id,
            at: ScorePoint(barIds(score)[1], Moment.zero),
            clef: Clef.treble,
          ),
        ),
      );
      final [first, second] = system.bars;
      final tops = [for (final staff in system.staves) staff.top];
      final runs = standingBetween(system, first.right, second.left);

      expectStanding(runs, ['clef', 'barline']);
      expect(glyphsOf(system, Glyph.gClefChange).single.origin.y, tops[1] + 3);
      expect(spansBetween(system, first.right, second.left), [
        (tops[0], tops[1] + staffHeight),
      ]);
    });
  });
}
