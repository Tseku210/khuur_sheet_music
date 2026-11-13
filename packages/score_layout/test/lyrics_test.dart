import 'dart:math' as math;

import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/breaking.dart';
import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/lyrics.dart';
import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/signatures.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_layout/src/system_layout.dart';
import 'package:score_layout/src/text.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/bars.dart';
import 'support/fake_measurer.dart';
import 'support/sheets.dart';

const EngravingStyle style = EngravingStyle.standard;
const FakeMeasurer text = FakeMeasurer();
const SystemLead lead = SystemLead(parts: [], firstIndent: 6, indent: 2);

/// The fake measurer's lyric metrics at the standard size of 2, and the
/// room a syllable keeps on each side at that size.
const double ascent = 1.6;
const double descent = 0.4;
const double hyphenWidth = 1.2;
const double pad = 0.5;

/// The first verse of the one voice of the one staff of [sungScore].
const LyricLane lane = (staff: StaffId(2000), voice: VoiceSlot.one, verse: 1);

/// A one-staff score of quarter-note bars on G4, in one voice. Each beat is
/// a note singing one syllable per verse, split by `|`, a rest (`r`) or a
/// note with no syllable (null). A syllable starting with `-` joins its
/// word and one ending with `-` continues it, as in `-tle-`. One ending
/// with `_` starts a melisma. An empty verse sings nothing on that beat.
/// Beat `k` of bar `b` is event `b * 100 + k + 1`. An [accompanied] score
/// has a second part of quarters on G4 under it, with no lyrics.
Score sungScore(List<List<String?>> bars, {bool accompanied = false}) =>
    scoreOf([
      for (final (b, beats) in bars.indexed)
        [
          staffOf([
            for (final (k, beat) in beats.indexed)
              if (beat == 'r')
                restOf(b * 100 + k + 1, NoteValue.quarter)
              else
                chordOf(b * 100 + k + 1, 'G4').copyWith(
                  lyrics: Seq([
                    for (final (v, token) in (beat ?? '').split('|').indexed)
                      if (token.isNotEmpty) syllable(token, verse: v + 1),
                  ]),
                ),
          ]),
          if (accompanied)
            staffOf([
              for (var k = 0; k < 4; k++) chordOf(b * 100 + k + 51, 'G4'),
            ]),
        ],
    ]);

Lyric syllable(String token, {int verse = 1}) {
  final joins = token.startsWith('-');
  final continues = token.endsWith('-');
  final extend = token.endsWith('_');
  return Lyric(
    verse: verse,
    text: token.substring(
      joins ? 1 : 0,
      token.length - (continues || extend ? 1 : 0),
    ),
    syllabic: switch ((joins, continues)) {
      (false, false) => Syllabic.single,
      (false, true) => Syllabic.begin,
      (true, true) => Syllabic.middle,
      (true, false) => Syllabic.end,
    },
    extend: extend,
  );
}

EventRef eventOf(int id) => EventRef(
  measure: barId(id ~/ 100),
  staff: staffId(0),
  id: EventId(id),
);

/// [score] with bars [starts] each starting a system.
Score brokenBefore(Score score, List<int> starts) => after(score, [
  for (final bar in starts) SetBreak(barId(bar), LayoutBreak.system),
]);

SheetLayout sheetOf(Score score, {double width = 200}) =>
    SheetLayout(score, width: width, text: text);

/// The lyric text of [system]. A part name has the lyric's size, so it is
/// told apart by standing in the indent, left of the first bar.
Iterable<TextDraw> lyricText(SystemLayout system) =>
    system.drawables.whereType<TextDraw>().where(
      (draw) =>
          draw.spec == style.specOf(TextRole.lyric) &&
          draw.bounds.left >= system.bars.first.left,
    );

/// The x of the system head's right edge, where the clef and any key
/// signature end.
double headInkOf(SystemLayout system) => system.drawables
    .whereType<GlyphDraw>()
    .where(
      (draw) =>
          draw.glyph == Glyph.gClef || draw.glyph == Glyph.accidentalSharp,
    )
    .where(
      (draw) => draw.bounds.right <= system.bars.first.time.xAt(Moment.zero),
    )
    .map((draw) => draw.bounds.right)
    .reduce(math.max);

/// The left edge of the courtesy key signature at the end of [system].
double courtesyOf(SystemLayout system) => system.drawables
    .whereType<GlyphDraw>()
    .where((draw) => draw.glyph == Glyph.accidentalSharp)
    .map((draw) => draw.bounds.left)
    .where((left) => left > system.bars.last.right)
    .reduce(math.min);

/// [score] with the key of three sharps from bar [from].
Score sharpsFrom(Score score, int from) => after(score, [
  SetKey(from: barId(from), key: const KeySignature(3)),
]);

/// [score] with the bass clef from bar [from].
Score bassFrom(Score score, int from) => after(score, [
  SetClef(
    staff: staffId(0),
    at: ScorePoint(barId(from), Moment.zero),
    clef: Clef.bass,
  ),
]);

/// The left edge of the courtesy clef at the end of [system].
double courtesyClefOf(SystemLayout system) => system.drawables
    .whereType<GlyphDraw>()
    .singleWhere((draw) => draw.glyph == Glyph.fClefChange)
    .bounds
    .left;

List<TextDraw> syllablesOn(SystemLayout system) =>
    lyricText(system).where((draw) => draw.text != '-').toList();

List<TextDraw> hyphensOn(SystemLayout system) =>
    lyricText(system).where((draw) => draw.text == '-').toList();

/// The lyric extenders, which are the horizontal lines of the lyric line
/// thickness. No test score here has ledger lines, the other horizontal
/// line of that thickness a bar can hold.
List<LineDraw> extendersOn(SystemLayout system) => system.drawables
    .whereType<LineDraw>()
    .where(
      (line) =>
          line.from.y == line.to.y &&
          line.thickness == style.font.defaults.lyricLineThickness,
    )
    .toList();

TextDraw syllableOn(SystemLayout system, String text) =>
    syllablesOn(system).singleWhere((draw) => draw.text == text);

GlyphDraw headOn(SystemLayout system, int event) =>
    system.drawables.whereType<GlyphDraw>().singleWhere(
      (draw) =>
          draw.glyph == Glyph.noteheadBlack &&
          draw.owner ==
              ElementOwner(NoteRef(eventOf(event), NoteId(event * 10))),
    );

double centreOf(Drawable draw) => (draw.bounds.left + draw.bounds.right) / 2;

/// The hyphens of [system] fill the gap from [from] to [to], centred on it
/// as a group, none outside it.
void expectHyphensBetween(SystemLayout system, double from, double to) {
  final hyphens = hyphensOn(system);
  final centres = hyphens.map(centreOf);

  expect(hyphens, isNotEmpty);
  for (final hyphen in hyphens) {
    expect(hyphen.bounds.left, greaterThanOrEqualTo(from - 1e-9));
    expect(hyphen.bounds.right, lessThanOrEqualTo(to + 1e-9));
  }
  expect(
    centres.reduce((a, b) => a + b) / hyphens.length,
    closeTo((from + to) / 2, 1e-9),
  );
}

/// The baseline of the first lyric row, which clears everything else the
/// system draws by the lyric gap.
double firstBaseline(SystemLayout system) {
  final extenders = extendersOn(system).toSet();
  final lyrics = lyricText(system).toSet();
  final ink = system.drawables
      .where((draw) => !extenders.contains(draw) && !lyrics.contains(draw))
      .map((draw) => draw.bounds.bottom)
      .reduce(math.max);
  return ink + style.lyricGap + ascent;
}

void main() {
  group('a syllable', () {
    test('is centred under its note on a row below the staff, and the system '
        'is as tall as that row', () {
      final system = sheetOf(
        sungScore([
          ['la', null, null, null],
        ]),
      ).systemAt(0);
      final la = syllableOn(system, 'la');

      expect(centreOf(la), closeTo(centreOf(headOn(system, 1)), 1e-9));
      expect(la.origin.y, closeTo(firstBaseline(system), 1e-9));
      expect(la.bounds.top, closeTo(la.origin.y - ascent, 1e-9));
      expect(la.bounds.bottom, closeTo(la.origin.y + descent, 1e-9));
      expect(system.height, closeTo(la.origin.y + descent, 1e-9));
      expect(la.owner, ElementOwner(eventOf(1)));
    });

    test('of a second verse sits on a second row under the first', () {
      final system = sheetOf(
        sungScore([
          ['la|ло', null, 'ti|ти', null],
        ]),
      ).systemAt(0);
      final la = syllableOn(system, 'la');
      final lo = syllableOn(system, 'ло');
      final ti = syllableOn(system, 'ti');

      expect(
        lo.origin.y,
        closeTo(la.origin.y + descent + style.lyricGap + ascent, 1e-9),
      );
      expect(syllableOn(system, 'ти').origin.y, lo.origin.y);
      expect(ti.origin.y, la.origin.y);
      expect(centreOf(lo), closeTo(centreOf(la), 1e-9));
      expect(system.height, closeTo(lo.origin.y + descent, 1e-9));
    });

    test('of a second voice on the staff sits on a row under the first '
        'voice\'s rows', () {
      final score = scoreOf([
        [
          staffOf(
            [
              chordOf(1, 'B4').copyWith(
                lyrics: Seq([syllable('la'), syllable('ло', verse: 2)]),
              ),
              chordOf(
                2,
                'B4',
                value: const NoteValue(DurationBase.half, dots: 1),
              ),
            ],
            two: [
              chordOf(3, 'G4').copyWith(lyrics: Seq([syllable('ti')])),
            ],
          ),
        ],
      ]);
      final system = sheetOf(score).systemAt(0);
      final la = syllableOn(system, 'la');
      final lo = syllableOn(system, 'ло');
      final ti = syllableOn(system, 'ti');

      expect(lo.origin.y, greaterThan(la.origin.y));
      expect(
        ti.origin.y,
        closeTo(lo.origin.y + descent + style.lyricGap + ascent, 1e-9),
      );
      expect(centreOf(ti), closeTo(centreOf(headOn(system, 3)), 1e-9));
      expect(system.height, closeTo(ti.origin.y + descent, 1e-9));
    });

    test('sits under its own staff alone, and a staff without lyrics '
        'keeps no room for them', () {
      Score score({required bool sung}) => scoreOf([
        [
          staffOf([
            for (final (k, word) in ['a', 'b', 'c', 'd'].indexed)
              chordOf(
                k + 1,
                'G4',
              ).copyWith(lyrics: Seq([if (sung) syllable(word)])),
          ]),
          staffOf([for (var k = 5; k <= 8; k++) chordOf(k, 'G4')]),
        ],
      ]);
      final system = sheetOf(score(sung: true)).systemAt(0);
      final plain = sheetOf(score(sung: false)).systemAt(0);
      final lower = system.staves[1];

      expect(syllablesOn(system).map((draw) => draw.text), [
        'a',
        'b',
        'c',
        'd',
      ]);
      for (final draw in syllablesOn(system)) {
        expect(draw.bounds.top, greaterThan(system.staves[0].top + 4));
        expect(draw.bounds.bottom, lessThan(lower.top));
      }
      expect(
        system.height - lower.top,
        closeTo(plain.height - plain.staves[1].top, 1e-9),
      );
    });

    test('in another script is measured and placed like any other', () {
      final system = sheetOf(
        sungScore([
          ['Мо-', '-рин', '月', null],
        ]),
      ).systemAt(0);
      final mo = syllableOn(system, 'Мо');
      final rin = syllableOn(system, 'рин');

      expect(centreOf(mo), closeTo(centreOf(headOn(system, 1)), 1e-9));
      expect(
        centreOf(syllableOn(system, '月')),
        closeTo(centreOf(headOn(system, 3)), 1e-9),
      );
      expect(
        hyphensOn(system).single.bounds.left,
        greaterThan(mo.bounds.right),
      );
      expect(hyphensOn(system).single.bounds.right, lessThan(rin.bounds.left));
    });

    test('widens its bar so the next syllable clears it by a space on each '
        'side, and a word\'s hyphen has room between its syllables', () {
      SystemLayout sung(String first) => sheetOf(
        sungScore([
          [first, 'la', 'won-', '-derful'],
        ]),
      ).systemAt(0);
      final system = sung('strengths');
      final wide = syllableOn(system, 'strengths');
      final la = syllableOn(system, 'la');
      final won = syllableOn(system, 'won');
      final derful = syllableOn(system, 'derful');

      expect(centreOf(wide), closeTo(centreOf(headOn(system, 1)), 1e-9));
      expect(
        la.bounds.left - wide.bounds.right,
        greaterThanOrEqualTo(2 * pad - 1e-9),
      );
      expect(
        system.bars.first.right - system.bars.first.left,
        greaterThan(sung('a').bars.first.right - sung('a').bars.first.left),
      );
      expect(
        derful.bounds.left - won.bounds.right,
        greaterThanOrEqualTo(hyphenWidth + 2 * pad - 1e-9),
      );
    });
  });

  group('a hyphen', () {
    test('is centred between the two syllables of a word in one bar', () {
      final system = sheetOf(
        sungScore([
          ['do-', '-re', null, null],
        ]),
      ).systemAt(0);
      final hyphen = hyphensOn(system).single;
      final from = syllableOn(system, 'do').bounds.right;
      final to = syllableOn(system, 're').bounds.left;

      expect(centreOf(hyphen), closeTo((from + to) / 2, 1e-9));
      expect(hyphen.bounds.width, closeTo(hyphenWidth, 1e-9));
      expect(to - from, greaterThanOrEqualTo(hyphenWidth));
      expect(hyphen.origin.y, syllableOn(system, 'do').origin.y);
    });

    test('is centred between the two syllables of a word across a '
        'barline', () {
      final system = sheetOf(
        sungScore([
          [null, null, null, 'do-'],
          ['-re', null, null, null],
        ]),
      ).systemAt(0);
      final from = syllableOn(system, 'do').bounds.right;
      final to = syllableOn(system, 're').bounds.left;

      expect(
        centreOf(hyphensOn(system).single),
        closeTo((from + to) / 2, 1e-9),
      );
    });

    test('spans a bar of rests between two syllables of a word', () {
      final layout = sheetOf(
        sungScore([
          [null, null, null, 'do-'],
          ['r', 'r', 'r', 'r'],
          ['-re', null, null, null],
        ]),
      );
      final system = layout.systemAt(0);

      expect(layout.systemCount, 1);
      expect(hyphensOn(system).length, greaterThan(1));
      expectHyphensBetween(
        system,
        syllableOn(system, 'do').bounds.right,
        syllableOn(system, 're').bounds.left,
      );
    });

    test('is drawn on each side of a system break that splits a word', () {
      final layout = sheetOf(
        brokenBefore(
          sungScore([
            [null, null, null, 'do-'],
            ['-re', null, null, null],
          ]),
          [1],
        ),
      );
      final first = layout.systemAt(0);
      final second = layout.systemAt(1);
      final re = syllableOn(second, 're');

      expect(layout.systemCount, 2);
      expectHyphensBetween(
        first,
        syllableOn(first, 'do').bounds.right,
        first.width,
      );
      for (final hyphen in hyphensOn(second)) {
        expect(hyphen.bounds.left, greaterThan(headInkOf(second)));
        expect(hyphen.bounds.right, lessThanOrEqualTo(re.bounds.left));
      }
      expect(hyphensOn(second).first.origin.y, re.origin.y);
      expect(syllablesOn(second).single, re);
    });

    test('at a system break stands clear of the courtesy key signature '
        'before it and of the key signature after it', () {
      final layout = sheetOf(
        sharpsFrom(
          brokenBefore(
            sungScore([
              [null, null, null, 'do-'],
              ['-re', null, null, null],
            ]),
            [1],
          ),
          1,
        ),
      );
      final first = layout.systemAt(0);
      final second = layout.systemAt(1);
      final re = syllableOn(second, 're');

      final from = syllableOn(first, 'do').bounds.right;
      final leaving = hyphensOn(first);
      final centre =
          leaving.map(centreOf).reduce((a, b) => a + b) / leaving.length;

      expect(
        centre,
        inExclusiveRange(
          (from + first.bars.last.right) / 2,
          (from + courtesyOf(first)) / 2,
        ),
        reason:
            'centred on the gap to where the courtesy signature\'s room '
            'starts, past the last barline',
      );
      expect(hyphensOn(second), isNotEmpty);
      for (final hyphen in hyphensOn(second)) {
        expect(hyphen.bounds.left, greaterThan(headInkOf(second)));
        expect(hyphen.bounds.right, lessThanOrEqualTo(re.bounds.left));
      }
    });

    test('at a system break is centred on the gap to the courtesy clef, '
        'before the last barline', () {
      final first = sheetOf(
        bassFrom(
          brokenBefore(
            sungScore([
              [null, null, null, 'do-'],
              ['-re', null, null, null],
            ]),
            [1],
          ),
          1,
        ),
      ).systemAt(0);

      expectHyphensBetween(
        first,
        syllableOn(first, 'do').bounds.right,
        courtesyClefOf(first),
      );
    });

    test('is repeated along a wide gap, no two further apart than ten '
        'spaces', () {
      final system = sheetOf(
        sungScore([
          ['do-', null, null, null],
          [null, null, null, null],
          [null, null, null, '-re'],
        ]),
      ).systemAt(0);
      final hyphens = hyphensOn(system)
        ..sort((a, b) => a.origin.x.compareTo(b.origin.x));
      final edges = [
        syllableOn(system, 'do').bounds.right,
        for (final hyphen in hyphens) ...[
          hyphen.bounds.left,
          hyphen.bounds.right,
        ],
        syllableOn(system, 're').bounds.left,
      ];

      expect(hyphens.length, greaterThan(1));
      for (var i = 1; i < edges.length; i += 2) {
        expect(edges[i] - edges[i - 1], lessThanOrEqualTo(10));
      }
      expect(edges.last - edges.first, greaterThan(10));
    });

    test('follows a syllable whose word has no next syllable yet, right '
        'after its text', () {
      final system = sheetOf(
        sungScore([
          ['do-', null, 'la', null],
        ]),
      ).systemAt(0);
      final hyphen = hyphensOn(system).single;

      expect(
        hyphen.bounds.left,
        closeTo(syllableOn(system, 'do').bounds.right, 1e-9),
      );
      expect(
        hyphen.bounds.right,
        lessThan(syllableOn(system, 'la').bounds.left),
      );
    });
  });

  group('an extender', () {
    test('runs on the baseline from its syllable to the last note before '
        'the next syllable, and the syllable is aligned left with its '
        'head', () {
      final system = sheetOf(
        sungScore([
          ['ah_', null, null, 'la'],
        ]),
      ).systemAt(0);
      final ah = syllableOn(system, 'ah');
      final line = extendersOn(system).single;

      expect(ah.bounds.left, closeTo(headOn(system, 1).bounds.left, 1e-9));
      expect(line.from, SpPoint(ah.bounds.right, ah.origin.y));
      expect(line.to, SpPoint(headOn(system, 3).bounds.right, ah.origin.y));
      expect(line.owner, ah.owner);
      expect(hyphensOn(system), isEmpty);
    });

    test('runs on under a note that sings only another verse', () {
      final system = sheetOf(
        sungScore([
          ['ah_|la', null, null, null],
          ['|lo', null, null, null],
          ['ti', null, null, null],
        ]),
      ).systemAt(0);
      final ah = syllableOn(system, 'ah');
      final extender = extendersOn(system).single;

      expect(extender.from.y, ah.origin.y);
      expect(extender.to.x, closeTo(headOn(system, 104).bounds.right, 1e-9));
    });

    test('ends at the last note before a rest, and does not reach the held '
        'notes of the bar after it', () {
      final system = sheetOf(
        sungScore([
          ['ah_', null, 'r', null],
          [null, null, 'la', null],
        ]),
      ).systemAt(0);
      final line = extendersOn(system).single;

      expect(line.to.x, closeTo(headOn(system, 2).bounds.right, 1e-9));
    });

    test('ends before a multi-measure rest, and does not reach the held '
        'notes of the bar after it', () {
      MeasureRest restOn(int bar) =>
          MeasureRest(id: EventId(bar * 100 + 1), span: Meter.fourFour.length);
      final system = SheetLayout(
        scoreOf([
          [
            staffOf([
              chordOf(1, 'G4').copyWith(lyrics: Seq([syllable('ah_')])),
              for (var k = 2; k <= 4; k++) chordOf(k, 'G4'),
            ]),
          ],
          [
            staffOf([restOn(1)]),
          ],
          [
            staffOf([restOn(2)]),
          ],
          [
            staffOf([for (var k = 1; k <= 4; k++) chordOf(300 + k, 'G4')]),
          ],
        ]),
        width: 200,
        text: text,
        style: const EngravingStyle(multiMeasureRests: true),
      ).systemAt(0);

      expect(
        extendersOn(system).single.to.x,
        closeTo(headOn(system, 4).bounds.right, 1e-9),
      );
    });

    test('is not drawn for a melisma of one note, whose syllable stays '
        'centred', () {
      final system = sheetOf(
        sungScore([
          ['ah_', 'r', 'la_', 'ti'],
        ]),
      ).systemAt(0);

      expect(extendersOn(system), isEmpty);
      expect(
        centreOf(syllableOn(system, 'ah')),
        closeTo(centreOf(headOn(system, 1)), 1e-9),
      );
    });

    test('is not drawn under its own note alone, however narrow its '
        'syllable is', () {
      const small = EngravingStyle(
        text: {TextRole.lyric: TextSpec(size: 1)},
      );
      final system = SheetLayout(
        sungScore([
          ['o_', 'la', 'la', 'o_'],
          ['la', 'la', 'la', 'la'],
        ]),
        width: 200,
        text: text,
        style: small,
      ).systemAt(0);

      final o = system.drawables.whereType<TextDraw>().singleWhere(
        (draw) => draw.owner == ElementOwner(eventOf(1)),
      );

      expect(o.text, 'o');
      expect(
        o.bounds.right,
        lessThan(headOn(system, 1).bounds.right),
        reason: 'the syllable is narrower than its head',
      );
      expect(extendersOn(system), isEmpty);
    });

    test('from a bar\'s last note is drawn only when the next bar holds '
        'it, and only then is its syllable aligned left', () {
      for (final (next, breaks) in [
        (['ti', null, null, null], false),
        (['r', null, null, null], false),
        (['r', 'ti', null, null], false),
        (['ti', null, null, null], true),
        ([null, null, 'ti', null], false),
        ([null, null, 'ti', null], true),
      ]) {
        final layout = sheetOf(
          brokenBefore(
            sungScore([
              ['la', null, null, 'ah_'],
              next,
            ]),
            [if (breaks) 1],
          ),
        );
        final system = layout.systemAt(0);
        final ah = syllableOn(system, 'ah');
        final head = headOn(system, 4);
        final held = next.first == null;

        expect(
          extendersOn(system),
          hasLength(held ? 1 : 0),
          reason: '$next, broken $breaks',
        );
        if (held) {
          expect(ah.bounds.left, closeTo(head.bounds.left, 1e-9));
        } else {
          expect(
            centreOf(ah),
            closeTo(centreOf(head), 1e-9),
            reason: '$next, broken $breaks',
          );
        }
      }
    });

    test('ends at a gap in a second voice, as at a rest', () {
      final ah = chordOf(5, 'E4').copyWith(lyrics: Seq([syllable('ah_')]));
      for (final (bars, name) in [
        (
          [
            [
              staffOf(
                [for (var k = 1; k <= 4; k++) chordOf(k, 'B4')],
                two: [ah],
              ),
            ],
            [
              staffOf(
                [for (var k = 101; k <= 104; k++) chordOf(k, 'B4')],
                two: [
                  Gap(DurationBase.half.length),
                  chordOf(105, 'E4', value: half),
                ],
              ),
            ],
          ],
          'the gap after it and the gap opening the next bar',
        ),
        (
          [
            [
              staffOf(
                [for (var k = 1; k <= 4; k++) chordOf(k, 'B4')],
                two: [ah],
              ),
            ],
            [
              staffOf(
                [for (var k = 101; k <= 104; k++) chordOf(k, 'B4')],
                two: [chordOf(105, 'E4', value: whole)],
              ),
            ],
          ],
          'the gap after it, before a note opening the next bar',
        ),
        (
          [
            [
              staffOf(
                [for (var k = 1; k <= 4; k++) chordOf(k, 'B4')],
                two: [
                  ah,
                  Gap(DurationBase.quarter.length),
                  chordOf(6, 'E4'),
                  chordOf(7, 'E4'),
                ],
              ),
            ],
          ],
          'a gap inside its bar',
        ),
      ]) {
        final system = sheetOf(scoreOf(bars)).systemAt(0);

        expect(extendersOn(system), isEmpty, reason: name);
        expect(
          centreOf(syllableOn(system, 'ah')),
          closeTo(centreOf(headOn(system, 5)), 1e-9),
          reason: name,
        );
      }
    });

    test('leaving a system stops before the courtesy key signature', () {
      final first = sheetOf(
        sharpsFrom(
          brokenBefore(
            sungScore([
              ['ah_', null, null, null],
              [null, null, 'la', null],
            ]),
            [1],
          ),
          1,
        ),
      ).systemAt(0);

      expect(
        extendersOn(first).single.to.x,
        inExclusiveRange(first.bars.last.right, courtesyOf(first)),
      );
    });

    test('leaving a system stops before the courtesy clef', () {
      final first = sheetOf(
        bassFrom(
          brokenBefore(
            sungScore([
              ['ah_', null, null, null],
              [null, null, 'la', null],
            ]),
            [1],
          ),
          1,
        ),
      ).systemAt(0);

      expect(
        extendersOn(first).single.to.x,
        closeTo(courtesyClefOf(first), 1e-9),
      );
    });

    test('leaving a system ends where it ends with no clef when the '
        'courtesy clef is on another staff', () {
      SystemLayout first({required bool clef}) {
        final score = brokenBefore(
          sungScore([
            ['ah_', null, null, null],
            [null, null, 'la', null],
          ], accompanied: true),
          [1],
        );
        return sheetOf(
          clef
              ? after(score, [
                  SetClef(
                    staff: staffId(1),
                    at: ScorePoint(barId(1), Moment.zero),
                    clef: Clef.bass,
                  ),
                ])
              : score,
        ).systemAt(0);
      }

      final plain = first(clef: false);
      final changed = first(clef: true);

      expect(
        courtesyClefOf(changed),
        greaterThanOrEqualTo(changed.bars.single.right - 1e-9),
      );
      expect(
        changed.width - extendersOn(changed).single.to.x,
        closeTo(plain.width - extendersOn(plain).single.to.x, 1e-9),
      );
    });

    test('crosses a system break, running to the system\'s edge and on '
        'from the next system\'s first slice', () {
      final layout = sheetOf(
        brokenBefore(
          sungScore([
            ['ah_', null, null, null],
            [null, null, 'la', null],
          ]),
          [1],
        ),
      );
      final first = layout.systemAt(0);
      final second = layout.systemAt(1);
      final leaving = extendersOn(first).single;
      final arriving = extendersOn(second).single;
      final la = syllableOn(second, 'la');

      expect(
        leaving.from.x,
        closeTo(syllableOn(first, 'ah').bounds.right, 1e-9),
      );
      expect(leaving.to.x, closeTo(first.width, 1e-9));
      expect(
        arriving.from.x,
        closeTo(second.bars.first.time.xAt(Moment.zero), 1e-9),
      );
      expect(arriving.to.x, closeTo(headOn(second, 102).bounds.right, 1e-9));
      expect(arriving.from.y, la.origin.y);
      expect(second.height, closeTo(la.origin.y + descent, 1e-9));
    });

    test('stops at the last note of its system when the next system '
        'starts with a syllable or a rest', () {
      for (final next in [
        ['la', null, null, null],
        ['r', null, null, null],
        ['r', 'la', null, null],
      ]) {
        final layout = sheetOf(
          brokenBefore(
            sungScore([
              ['ah_', null, null, null],
              next,
            ]),
            [1],
          ),
        );
        final first = layout.systemAt(0);
        final sings = next.contains('la');

        expect(
          extendersOn(first).single.to.x,
          closeTo(headOn(first, 4).bounds.right, 1e-9),
          reason: '$next',
        );
        expect(extendersOn(layout.systemAt(1)), isEmpty, reason: '$next');
        expect(
          layout.heightOf(1),
          sings
              ? closeTo(layout.heightOf(0), 1e-9)
              : lessThan(layout.heightOf(0)),
          reason: '$next, the next system has a row only for its own syllable',
        );
      }
    });

    test('of a final melisma runs to the end of the score', () {
      final layout = sheetOf(
        brokenBefore(
          sungScore([
            ['ah_', null, null, null],
            [null, null, null, null],
          ]),
          [1],
        ),
      );
      final second = layout.systemAt(1);

      expect(
        extendersOn(layout.systemAt(0)).single.to.x,
        closeTo(layout.systemAt(0).width, 1e-9),
      );
      expect(
        extendersOn(second).single.to.x,
        closeTo(headOn(second, 104).bounds.right, 1e-9),
      );
      expect(syllablesOn(second), isEmpty);
    });
  });

  group('the carry', () {
    // Three bars a system, with the edits in a system's middle bar or the
    // score's last, so a relaid neighbour of an edited bar never crosses a
    // system edge.
    final plain = brokenBefore(
      sungScore([
        for (var bar = 0; bar < 18; bar++) [null, null, null, null],
      ]),
      [3, 6, 9, 12, 15],
    );
    final begun = after(plain, [
      SetLyric(eventOf(101), 1, syllable('do-')),
    ]);
    final joined = after(begun, [
      SetLyric(eventOf(1301), 1, syllable('-re')),
    ]);

    test('of a begin syllable with no later syllable in its lane rekeys only '
        'its own system, which draws one hyphen after its text', () {
      final layout = sheetOf(plain);
      final updated = layout.update(begun);
      final system = updated.systemAt(0);
      final hyphen = hyphensOn(system).single;

      expect(layout.systemCount, 6);
      expect(updated.delta.rekeyed, {0});
      expect(
        hyphen.bounds.left,
        closeTo(syllableOn(system, 'do').bounds.right, 1e-9),
      );
      for (var i = 1; i < 6; i++) {
        expect(updated.heightOf(i), layout.heightOf(i), reason: 'system $i');
        expect(lyricText(updated.systemAt(i)), isEmpty, reason: 'system $i');
      }
      expectSameSheet(updated, sheetOf(begun));
    });

    test('of a syllable joining a word several systems back rekeys exactly '
        'the systems between them, draws a hyphen on each, and an edit '
        'elsewhere keeps them', () {
      final layout = sheetOf(begun);
      final untouched = layout.systemAt(5);
      final updated = layout.update(joined);

      expect(updated.delta.rekeyed, {0, 1, 2, 3, 4});
      expect(identical(updated.systemAt(5), untouched), isTrue);
      for (var i = 0; i <= 4; i++) {
        final system = updated.systemAt(i);
        expect(hyphensOn(system), isNotEmpty, reason: 'system $i');
        expect(
          hyphensOn(system).map((h) => h.origin.y).toSet(),
          {firstBaseline(system)},
          reason: 'system $i',
        );
      }
      expect(hyphensOn(updated.systemAt(5)), isEmpty);
      expect(
        hyphensOn(updated.systemAt(4)).last.bounds.right,
        lessThan(syllableOn(updated.systemAt(4), 're').bounds.left),
      );
      expectSameSheet(updated, sheetOf(joined));

      final further = updated.update(
        after(joined, [SetLyric(eventOf(1701), 1, syllable('la'))]),
      );

      expect(further.delta.rekeyed, {5});
      for (var i = 0; i <= 4; i++) {
        expect(
          identical(further.systemAt(i), updated.systemAt(i)),
          isTrue,
          reason: 'system $i',
        );
      }
    });

    test('is the fold of what each bar leaves open, where a rest ends an '
        'extender but not a hyphen, and closes at an edge what nothing '
        'beyond it holds', () {
      final score = sungScore([
        ['do-', null, null, null],
        ['r', 'r', 'r', 'r'],
        ['-re', 'ah_', null, null],
        ['r', null, null, null],
        ['la_', null, null, null],
        [null, 'ti', null, null],
      ]);
      final bars = [
        for (final column in score.measures)
          layoutBar(score.measureView(column.id), style, text).lyrics,
      ];
      var carry = LyricCarry.none;
      final carries = [for (final bar in bars) carry = bar.after(carry)];
      const hyphen = LyricCarry({lane: OpenLyric.hyphen});
      const extender = LyricCarry({lane: OpenLyric.extender});

      expect(carries, [
        hyphen,
        hyphen,
        extender,
        LyricCarry.none,
        extender,
        LyricCarry.none,
      ]);
      expect(hyphen.closing({}, bars[1]), LyricCarry.none);
      expect(hyphen.closing({lane}, bars[1]), hyphen);
      expect(extender.closing({}, bars[3]), LyricCarry.none);
      expect(extender.closing({}, bars[5]), extender);
      expect(extender.closing({}, bars[0]), LyricCarry.none);
    });
  });

  group('breaking', () {
    final plain = brokenBefore(
      sungScore([
        for (var bar = 0; bar < 18; bar++) [null, null, null, null],
      ]),
      [3, 6, 9, 12, 15],
    );
    final begun = after(plain, [
      SetLyric(eventOf(101), 1, syllable('do-')),
      SetLyric(eventOf(1301), 1, syllable('re')),
    ]);
    final joined = after(begun, [
      SetLyric(eventOf(1301), 1, syllable('-re')),
    ]);
    List<BarLayout> layoutsOf(Score score) => [
      for (final column in score.measures)
        layoutBar(score.measureView(column.id), style, text),
    ];
    Breaks breaksOf(List<BarLayout> bars, {Breaks? previous}) => breakSystems(
      bars: bars,
      width: 100,
      lead: lead,
      style: style,
      text: text,
      previous: previous,
    );

    test('resumed after a change of carry alone equals a fresh break, and '
        'keeps the plans whose carry stood', () {
      final was = layoutsOf(begun);
      final before = breaksOf(was);
      // The sheet's bar cache keeps every other bar's layout by identity, and
      // a system's key reads its bars by identity.
      final bars = [...was]
        ..[13] = layoutBar(joined.measureView(barId(13)), style, text);
      final fresh = breaksOf(bars);
      final resumed = breaksOf(bars, previous: before);

      expect(before.plans, hasLength(6));
      expect(bars[13].widths, was[13].widths);
      expect(identical(resumed.starts, before.starts), isTrue);
      expect(fresh.starts, before.starts);
      for (var i = 0; i < 6; i++) {
        expect(resumed.plans[i].key, fresh.plans[i].key, reason: 'system $i');
        expect(resumed.plans[i].stretch, fresh.plans[i].stretch);
        expect(resumed.plans[i].staffTops, fresh.plans[i].staffTops);
        expect(resumed.plans[i].height, fresh.plans[i].height);
        expect(
          identical(resumed.plans[i], before.plans[i]),
          i == 5,
          reason: 'system $i',
        );
      }
      expect(fresh.plans[0].key.carry, LyricCarry.none);
      for (var i = 1; i <= 4; i++) {
        expect(
          fresh.plans[i].key.carry,
          const LyricCarry({lane: OpenLyric.hyphen}),
        );
      }
      expect(fresh.plans[4].key.carryOut, LyricCarry.none);
      expect(before.plans[1].key.carry, LyricCarry.none);
      expect(
        fresh.plans[1].height,
        before.plans[1].height + style.lyricGap + ascent + descent,
      );
    });
  });
}
