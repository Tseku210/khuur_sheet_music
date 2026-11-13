import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/bar_space.dart';
import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/signatures.dart';
import 'package:score_layout/src/spacing.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/bars.dart';
import 'support/fake_measurer.dart';

const EngravingStyle style = EngravingStyle.standard;

const clarinet = Instrument(
  key: 'clarinet-b-flat',
  program: 71,
  transposition: Interval(-1, -2),
);

const Glyph sharp = Glyph.accidentalSharp;
const Glyph flat = Glyph.accidentalFlat;
const Glyph natural = Glyph.accidentalNatural;

BarHeads headsOf(
  Score score,
  int bar, {
  EngravingStyle style = EngravingStyle.standard,
}) => barHeads(viewOf(score, bar), style);

List<GlyphDraw> drawsOf(BarHead head, [int staff = 0]) => [
  for (final item in head.items)
    if (item.staff == staff) item.drawable as GlyphDraw,
];

List<Glyph> glyphsOf(BarHead head, [int staff = 0]) => [
  for (final draw in drawsOf(head, staff)) draw.glyph,
];

List<int> stepsOf(Iterable<GlyphDraw> draws) => [
  for (final draw in draws) stepAtY(draw.origin.y),
];

void main() {
  group('key signature steps', () {
    const sharps = KeySignature(7);
    const flats = KeySignature(-7);

    test('sharps and flats take the treble clef positions', () {
      expect(keySignatureSteps(sharps, Clef.treble), [8, 5, 9, 6, 3, 7, 4]);
      expect(keySignatureSteps(flats, Clef.treble), [4, 7, 3, 6, 2, 5, 1]);
    });

    test('sharps and flats take the bass clef positions', () {
      expect(keySignatureSteps(sharps, Clef.bass), [6, 3, 7, 4, 1, 5, 2]);
      expect(keySignatureSteps(flats, Clef.bass), [2, 5, 1, 4, 0, 3, -1]);
    });

    test('sharps and flats take the alto clef positions', () {
      expect(keySignatureSteps(sharps, Clef.alto), [7, 4, 8, 5, 2, 6, 3]);
      expect(keySignatureSteps(flats, Clef.alto), [3, 6, 2, 5, 1, 4, 0]);
    });

    test('sharps start low under the tenor clef, and flats do not', () {
      expect(keySignatureSteps(sharps, Clef.tenor), [2, 6, 3, 7, 4, 8, 5]);
      expect(keySignatureSteps(flats, Clef.tenor), [5, 8, 4, 7, 3, 6, 2]);
    });

    test('the other C clefs and the baritone F clef take the positions '
        'LilyPond prints by default', () {
      expect(keySignatureSteps(sharps, Clef.soprano), [3, 0, 4, 1, 5, 2, 6]);
      expect(keySignatureSteps(flats, Clef.soprano), [6, 2, 5, 1, 4, 0, 3]);
      expect(
        keySignatureSteps(sharps, Clef.mezzoSoprano),
        [5, 2, 6, 3, 0, 4, 1],
      );
      expect(
        keySignatureSteps(flats, Clef.mezzoSoprano),
        [1, 4, 0, 3, 6, 2, 5],
      );
      for (final clef in [Clef.baritoneC, Clef.baritoneF]) {
        expect(keySignatureSteps(sharps, clef), [4, 1, 5, 2, 6, 3, 7]);
        expect(keySignatureSteps(flats, clef), [0, 3, -1, 2, 5, 1, 4]);
      }
    });

    test('a key prints as many accidentals as it has', () {
      expect(keySignatureSteps(const KeySignature(4), Clef.treble), [
        8,
        5,
        9,
        6,
      ]);
      expect(keySignatureSteps(const KeySignature(-4), Clef.treble), [
        4,
        7,
        3,
        6,
      ]);
      expect(keySignatureSteps(KeySignature.cMajor, Clef.treble), isEmpty);
    });

    test('an octave clef keeps the positions of its plain clef', () {
      expect(
        keySignatureSteps(sharps, Clef.treble8vb),
        keySignatureSteps(sharps, Clef.treble),
      );
      expect(
        keySignatureSteps(flats, Clef.bass8vb),
        keySignatureSteps(flats, Clef.bass),
      );
    });

    test('a percussion clef prints no key', () {
      expect(keySignatureSteps(sharps, Clef.percussion), isEmpty);

      final heads = headsOf(
        beatsScore(
          1,
          clefs: [Clef.percussion, Clef.treble],
          key: const KeySignature(4),
        ),
        0,
      );

      expect(glyphsOf(heads.system), [
        Glyph.unpitchedPercussionClef1,
        Glyph.timeSig4,
        Glyph.timeSig4,
      ]);
      expect(glyphsOf(heads.system, 1), contains(sharp));
    });
  });

  group('key signature items', () {
    BarHead keyOf(int fifths, {int? cancels, Clef clef = Clef.treble}) =>
        keySignatureItems(
          KeySignature(fifths),
          clef,
          staff: 0,
          cancels: cancels == null ? null : KeySignature(cancels),
          style: style,
        );

    void expectSpaced(BarHead head) {
      final draws = drawsOf(head);
      expect(draws.first.bounds.left, 0);
      for (var i = 1; i < draws.length; i++) {
        expect(
          draws[i].bounds.left - draws[i - 1].bounds.right,
          closeTo(draws[i - 1].glyph == natural ? 0.3 : 0.15, 1e-9),
          reason: 'the gap before accidental $i',
        );
      }
      expect(head.width, closeTo(draws.last.bounds.right, 1e-9));
    }

    test('a key change prints naturals for what it cancels, before the new '
        'accidentals', () {
      final fewer = keyOf(2, cancels: 4);
      expect(glyphsOf(fewer), [natural, natural, sharp, sharp]);
      expect(stepsOf(drawsOf(fewer)), [9, 6, 8, 5]);
      expectSpaced(fewer);

      final other = keyOf(1, cancels: -2);
      expect(glyphsOf(other), [natural, natural, sharp]);
      expect(stepsOf(drawsOf(other)), [4, 7, 8]);
      expectSpaced(other);
    });

    test('a change from sharps to flats on the same letters cancels every '
        'sharp', () {
      final all = keyOf(-7, cancels: 7);
      expect(glyphsOf(all), [
        ...List.filled(7, natural),
        ...List.filled(7, flat),
      ]);
      expect(stepsOf(drawsOf(all)).take(7), [8, 5, 9, 6, 3, 7, 4]);
      expectSpaced(all);

      final six = keyOf(6, cancels: -6);
      expect(glyphsOf(six), [
        ...List.filled(6, natural),
        ...List.filled(6, sharp),
      ]);
    });

    test('a change to no accidentals prints only the naturals', () {
      final head = keyOf(0, cancels: -3, clef: Clef.bass);

      expect(glyphsOf(head), [natural, natural, natural]);
      expect(stepsOf(drawsOf(head)), [2, 5, 1]);
    });

    test('a key that only gains accidentals cancels nothing', () {
      expect(glyphsOf(keyOf(-3, cancels: -1)), [flat, flat, flat]);
    });

    test('a key with nothing to cancel prints its accidentals alone', () {
      final head = keyOf(4);

      expect(glyphsOf(head), [sharp, sharp, sharp, sharp]);
      expect(stepsOf(drawsOf(head)), [8, 5, 9, 6]);
      expectSpaced(head);
    });

    test('no accidentals and nothing to cancel is no key', () {
      expect(keyOf(0, cancels: 0).items, isEmpty);
      expect(keyOf(0, cancels: 0).width, 0);
    });
  });

  group('meter', () {
    BarHead meterOf(Meter meter) => meterItems(meter, staff: 0, style: style);

    double centre(Iterable<GlyphDraw> row) =>
        (row.first.bounds.left + row.last.bounds.right) / 2;

    test('common and cut time print their symbols on the middle line', () {
      final common = drawsOf(meterOf(Meter.common)).single;
      final cut = drawsOf(meterOf(Meter.cut)).single;

      expect(common.glyph, Glyph.timeSigCommon);
      expect(cut.glyph, Glyph.timeSigCutCommon);
      expect(common.origin.y, 2);
      expect(cut.origin.y, 2);
    });

    test('a numeric meter prints its digits in two rows that meet on the '
        'middle line', () {
      final draws = drawsOf(meterOf(Meter.sixEight));

      expect(
        [for (final d in draws) d.glyph],
        [
          Glyph.timeSig6,
          Glyph.timeSig8,
        ],
      );
      expect(draws[0].origin.y, 1);
      expect(draws[1].origin.y, 3);
      expect(draws[0].bounds.bottom, closeTo(2, 0.05));
      expect(draws[1].bounds.top, closeTo(2, 0.05));
    });

    test('each row of a meter is centred on the wider row', () {
      final head = meterOf(Meter.simple(12, 8));
      final draws = drawsOf(head);

      expect(
        [for (final d in draws) d.glyph],
        [
          Glyph.timeSig1,
          Glyph.timeSig2,
          Glyph.timeSig8,
        ],
      );
      expect(draws[0].origin.x, 0);
      expect(draws[1].origin.x, greaterThan(0));
      expect(
        head.width,
        closeTo(
          style.font[Glyph.timeSig1].advance +
              style.font[Glyph.timeSig2].advance,
          1e-9,
        ),
      );
      expect(centre(draws.take(2)), closeTo(head.width / 2, 1e-9));
      expect(centre(draws.skip(2)), closeTo(head.width / 2, 1e-9));

      final wideBelow = drawsOf(meterOf(Meter.simple(3, 16)));
      expect(
        centre(wideBelow.take(1)),
        closeTo(centre(wideBelow.skip(1)), 1e-9),
      );
    });

    test('an additive meter joins its groups with plus signs', () {
      expect(glyphsOf(meterOf(const Meter([3, 2, 2], 8))), [
        Glyph.timeSig3,
        Glyph.timeSigPlus,
        Glyph.timeSig2,
        Glyph.timeSigPlus,
        Glyph.timeSig2,
        Glyph.timeSig8,
      ]);
    });
  });

  group('clefs', () {
    test('a clef is full size at a system start and small at a change', () {
      expect(clefGlyph(Clef.treble, change: false), (
        glyph: Glyph.gClef,
        scale: 1.0,
      ));
      expect(clefGlyph(Clef.treble, change: true), (
        glyph: Glyph.gClefChange,
        scale: 1.0,
      ));
      expect(clefGlyph(Clef.tenor, change: true), (
        glyph: Glyph.cClefChange,
        scale: 1.0,
      ));
      expect(clefGlyph(Clef.baritoneF, change: true), (
        glyph: Glyph.fClefChange,
        scale: 1.0,
      ));
    });

    test('a clef with no change glyph is its full glyph scaled down', () {
      for (final (clef, glyph) in [
        (Clef.treble8vb, Glyph.gClef8vb),
        (Clef.treble8va, Glyph.gClef8va),
        (Clef.bass8vb, Glyph.fClef8vb),
        (Clef.percussion, Glyph.unpitchedPercussionClef1),
      ]) {
        expect(clefGlyph(clef, change: false), (glyph: glyph, scale: 1.0));
        final change = clefGlyph(clef, change: true);
        expect(change.glyph, glyph);
        expect(change.scale, closeTo(2 / 3, 1e-9));
      }
    });

    test('a clef drawn scaled down has a box as small', () {
      final heads = headsOf(
        after(beatsScore(2), [
          SetClef(
            staff: staffId(0),
            at: ScorePoint(barId(1), Moment.zero),
            clef: Clef.treble8vb,
          ),
        ]),
        1,
      );
      final small = drawsOf(heads.inline.before).single;
      final full = drawsOf(heads.system).first;

      expect(full.glyph, Glyph.gClef8vb);
      expect(full.scale, 1);
      expect(small.glyph, Glyph.gClef8vb);
      expect(small.scale, closeTo(2 / 3, 1e-9));
      expect(small.origin.y, full.origin.y);
      expect(small.bounds.width, closeTo(full.bounds.width * 2 / 3, 1e-9));
      expect(
        small.origin.y - small.bounds.top,
        closeTo((full.origin.y - full.bounds.top) * 2 / 3, 1e-9),
      );
      expect(
        small.bounds.bottom - small.origin.y,
        closeTo((full.bounds.bottom - full.origin.y) * 2 / 3, 1e-9),
      );
    });

    test('a clef sits on its own line', () {
      final clefs = [
        Clef.treble,
        Clef.bass,
        Clef.alto,
        Clef.tenor,
        Clef.soprano,
        Clef.baritoneF,
        Clef.percussion,
      ];
      final heads = headsOf(beatsScore(1, clefs: clefs), 0);

      expect(
        [
          for (final (staff, _) in clefs.indexed)
            drawsOf(heads.system, staff).first.origin.y,
        ],
        [3, 1, 2, 1, 4, 2, 2],
      );
    });
  });

  group('system head', () {
    test('it prints the clef and the key on every staff', () {
      final heads = headsOf(
        beatsScore(
          2,
          clefs: [Clef.treble, Clef.bass],
          key: const KeySignature(2),
        ),
        1,
      );

      expect(glyphsOf(heads.system), [Glyph.gClef, sharp, sharp]);
      expect(glyphsOf(heads.system, 1), [Glyph.fClef, sharp, sharp]);
      expect(stepsOf(drawsOf(heads.system).skip(1)), [8, 5]);
      expect(stepsOf(drawsOf(heads.system, 1).skip(1)), [6, 3]);
    });

    test('it prints the meter only where it changes, or on every system when '
        'the style says so', () {
      final score = beatsScore(2, meter: Meter.threeFour);
      const everySystem = EngravingStyle(meterEverySystem: true);

      expect(glyphsOf(headsOf(score, 0).system), [
        Glyph.gClef,
        Glyph.timeSig3,
        Glyph.timeSig4,
      ]);
      expect(glyphsOf(headsOf(score, 1).system), [Glyph.gClef]);
      expect(glyphsOf(headsOf(score, 1, style: everySystem).system), [
        Glyph.gClef,
        Glyph.timeSig3,
        Glyph.timeSig4,
      ]);
      expect(headsOf(score, 1, style: everySystem).inline, SplitHead.none);
    });

    test('a changed key cancels the old one there only when no courtesy '
        'did', () {
      final changed = after(
        beatsScore(2, key: const KeySignature(3)),
        [SetKey(from: barId(1), key: const KeySignature(1))],
      );
      final silent = after(changed, [
        SetKeyDisplay(barId(1), SignatureDisplay.noCourtesy),
      ]);

      expect(glyphsOf(headsOf(changed, 1).system), [Glyph.gClef, sharp]);
      expect(glyphsOf(headsOf(silent, 1).system), [
        Glyph.gClef,
        natural,
        natural,
        sharp,
      ]);
      expect(
        glyphsOf(
          headsOf(
            changed,
            1,
            style: const EngravingStyle(courtesySignatures: false),
          ).system,
        ),
        [Glyph.gClef, natural, natural, sharp],
      );
    });
  });

  group('inline head', () {
    test('a bar that changes nothing prints nothing', () {
      final heads = headsOf(beatsScore(2, key: const KeySignature(2)), 1);

      expect(heads.inline, SplitHead.none);
      expect(heads.inline.width, 0);
      expect(heads.courtesy, SplitHead.none);
      expect(heads.courtesy.width, 0);
    });

    test('a key change prints the key alone, with its naturals', () {
      final score = after(
        beatsScore(2, key: const KeySignature(-3)),
        [SetKey(from: barId(1), key: const KeySignature(-1))],
      );

      expect(glyphsOf(headsOf(score, 1).inline.after), [
        natural,
        natural,
        flat,
      ]);
    });

    test('a meter change prints the meter alone', () {
      final score = after(beatsScore(2), [
        SetMeter(
          from: barId(1),
          meter: Meter.cut,
          content: MeterContent.keepBars,
        ),
      ]);

      expect(glyphsOf(headsOf(score, 1).inline.after), [
        Glyph.timeSigCutCommon,
      ]);
    });

    test('a restated key or meter prints without a change', () {
      final score = after(
        beatsScore(2, key: const KeySignature(1)),
        [
          SetKeyDisplay(barId(1), SignatureDisplay.restated),
          SetMeterDisplay(barId(1), SignatureDisplay.restated),
        ],
      );
      final heads = headsOf(score, 1);

      expect(glyphsOf(heads.inline.after), [
        sharp,
        Glyph.timeSig4,
        Glyph.timeSig4,
      ]);
      expect(heads.courtesy, SplitHead.none);
    });

    test('a clef change at the barline prints the small clef on its staff '
        'alone, before the barline', () {
      final score = after(
        beatsScore(2, clefs: [Clef.treble, Clef.treble]),
        [
          SetClef(
            staff: staffId(1),
            at: ScorePoint(barId(1), Moment.zero),
            clef: Clef.bass,
          ),
        ],
      );
      final heads = headsOf(score, 1);
      final clef = drawsOf(heads.inline.before, 1).single;

      expect(glyphsOf(heads.inline.before), isEmpty);
      expect(clef.glyph, Glyph.fClefChange);
      expect(clef.origin.y, 1);
      expect(clef.bounds.left, closeTo(0, 1e-9));
      expect(heads.inline.before.width, closeTo(clef.bounds.right + 0.5, 1e-9));
      expect(heads.inline.after, BarHead.none);
      expect(glyphsOf(heads.system, 1), [Glyph.fClef]);
    });

    test('clefs that change on two staves at one barline end at one x', () {
      final score = after(
        beatsScore(2, clefs: [Clef.treble, Clef.bass]),
        [
          SetClef(
            staff: staffId(0),
            at: ScorePoint(barId(1), Moment.zero),
            clef: Clef.alto,
          ),
          SetClef(
            staff: staffId(1),
            at: ScorePoint(barId(1), Moment.zero),
            clef: Clef.treble,
          ),
        ],
      );
      final before = headsOf(score, 1).inline.before;
      final alto = drawsOf(before).single;
      final treble = drawsOf(before, 1).single;

      expect(alto.glyph, Glyph.cClefChange);
      expect(treble.glyph, Glyph.gClefChange);
      expect(alto.bounds.width, greaterThan(treble.bounds.width));
      expect(alto.bounds.left, closeTo(0, 1e-9));
      expect(treble.bounds.right, closeTo(alto.bounds.right, 1e-9));
      expect(before.width, closeTo(alto.bounds.right + 0.5, 1e-9));
    });

    test('a transposing staff prints and cancels its written key', () {
      final score = after(
        beatsScore(
          2,
          clefs: [Clef.treble, Clef.treble],
          instruments: [clarinet],
        ),
        [SetKey(from: barId(1), key: const KeySignature(-2))],
      );
      final heads = headsOf(score, 1);

      expect(glyphsOf(heads.inline.after), [natural, natural]);
      expect(stepsOf(drawsOf(heads.inline.after)), [8, 5]);
      expect(glyphsOf(heads.inline.after, 1), [flat, flat]);
    });
  });

  group('courtesy head', () {
    final score = after(
      beatsScore(2, key: const KeySignature(2)),
      [
        SetKey(from: barId(1), key: const KeySignature(-1)),
        SetMeter(
          from: barId(1),
          meter: Meter.threeFour,
        ),
      ],
    );

    test('it holds the new key with its naturals and the new meter after the '
        'barline, and the small clef before it', () {
      final clefToo = after(score, [
        SetClef(
          staff: staffId(0),
          at: ScorePoint(barId(1), Moment.zero),
          clef: Clef.bass,
        ),
      ]);

      for (final changed in [score, clefToo]) {
        expect(glyphsOf(headsOf(changed, 1).courtesy.after), [
          natural,
          natural,
          flat,
          Glyph.timeSig3,
          Glyph.timeSig4,
        ]);
      }
      expect(headsOf(score, 1).courtesy.before, BarHead.none);
      expect(glyphsOf(headsOf(clefToo, 1).courtesy.before), [
        Glyph.fClefChange,
      ]);
      expect(
        headsOf(clefToo, 1).courtesy.before,
        headsOf(clefToo, 1).inline.before,
      );
    });

    test('noCourtesy removes the key or the meter from it', () {
      final noKey = after(score, [
        SetKeyDisplay(barId(1), SignatureDisplay.noCourtesy),
      ]);
      final neither = after(noKey, [
        SetMeterDisplay(barId(1), SignatureDisplay.noCourtesy),
      ]);

      expect(glyphsOf(headsOf(noKey, 1).courtesy.after), [
        Glyph.timeSig3,
        Glyph.timeSig4,
      ]);
      expect(headsOf(neither, 1).courtesy, SplitHead.none);
      expect(headsOf(neither, 1).courtesy.width, 0);
      expect(glyphsOf(headsOf(neither, 1).inline.after), hasLength(5));
    });

    test('a style without courtesy signatures has none, and keeps the '
        'courtesy clef', () {
      const off = EngravingStyle(courtesySignatures: false);
      final heads = headsOf(score, 1, style: off);
      final clefToo = headsOf(
        after(score, [
          SetClef(
            staff: staffId(0),
            at: ScorePoint(barId(1), Moment.zero),
            clef: Clef.bass,
          ),
        ]),
        1,
        style: off,
      );

      expect(heads.courtesy, SplitHead.none);
      expect(heads.courtesy.width, 0);
      expect(glyphsOf(clefToo.courtesy.before), [Glyph.fClefChange]);
      expect(clefToo.courtesy.after, BarHead.none);
      expect(clefToo.courtesy.width, clefToo.courtesy.before.width);
    });
  });

  group('head geometry', () {
    test('head groups align across staves', () {
      final heads = headsOf(
        beatsScore(
          1,
          clefs: [Clef.treble, Clef.bass, Clef.treble],
          instruments: [piano, piano, clarinet],
          key: const KeySignature(1),
        ),
        0,
      );
      final staves = [for (var s = 0; s < 3; s++) drawsOf(heads.system, s)];
      GlyphDraw first(int staff, bool Function(Glyph) test) =>
          staves[staff].firstWhere((draw) => test(draw.glyph));
      bool isClef(Glyph glyph) => glyph == Glyph.gClef || glyph == Glyph.fClef;
      bool isDigit(Glyph glyph) => glyph == Glyph.timeSig4;

      final clefLefts = [for (var s = 0; s < 3; s++) first(s, isClef)];
      final keyLefts = [
        for (var s = 0; s < 3; s++) first(s, (g) => g == sharp),
      ];
      final meterLefts = [for (var s = 0; s < 3; s++) first(s, isDigit)];

      expect({for (final d in clefLefts) d.bounds.left}, hasLength(1));
      expect({for (final d in keyLefts) d.bounds.left}, hasLength(1));
      expect({for (final d in meterLefts) d.bounds.left}, hasLength(1));

      final widestClef = clefLefts
          .map((d) => d.bounds.right)
          .reduce((a, b) => a > b ? a : b);
      expect(keyLefts.first.bounds.left, closeTo(widestClef + 0.75, 1e-9));

      expect(glyphsOf(heads.system, 2).where((g) => g == sharp), hasLength(3));
      final widestKey = staves[2].lastWhere((d) => d.glyph == sharp);
      expect(
        meterLefts.first.origin.x,
        closeTo(widestKey.bounds.right + 0.75, 1e-9),
      );
    });

    test('a head is as wide as its last group and a gap', () {
      final heads = headsOf(beatsScore(1), 0);
      final last = drawsOf(heads.system).last;

      expect(
        heads.system.width,
        closeTo(last.origin.x + style.font[last.glyph].advance + 0.75, 1e-9),
      );
      expect(drawsOf(heads.system).first.bounds.left, closeTo(0.75, 1e-9));
    });

    test('a bar that opens a repeat leaves room for the sign in its inline '
        'and system heads', () {
      final plain = beatsScore(2);
      final repeat = after(plain, [SetRepeatStart(barId(1), start: true)]);
      final sign = startRepeatWidth(style);

      expect(headsOf(repeat, 1).inline.before, BarHead.none);
      expect(headsOf(repeat, 1).inline.after.items, isEmpty);
      expect(headsOf(repeat, 1).inline.width, closeTo(sign + 0.75, 1e-9));
      expect(
        headsOf(repeat, 1).system.width,
        closeTo(headsOf(plain, 1).system.width + sign + 0.75, 1e-9),
      );
      expect(headsOf(repeat, 1).courtesy.width, 0);
    });

    test('headReach is how far a head passes its staff', () {
      final heads = headsOf(
        beatsScore(1, clefs: [Clef.treble, Clef.bass]),
        0,
      );
      final treble = headReach([heads.system], 0);
      final bass = headReach([heads.system], 1);

      expect(treble.above, closeTo(1.392, 1e-9));
      expect(treble.below, closeTo(1.632, 1e-9));
      expect(bass.above, closeTo(0.048, 1e-9));
      expect(bass.below, 0);
    });
  });

  group('barlines', () {
    BarEdges edgesOf({Barline end = Barline.regular, RepeatEnd? repeatEnd}) =>
        (repeatStart: false, startJoins: true, end: end, repeatEnd: repeatEnd);

    test('an end repeat barline is wider than a plain one', () {
      final plain = endBarlineWidth(edgesOf(), style);
      final repeat = endBarlineWidth(
        edgesOf(repeatEnd: const RepeatEnd()),
        style,
      );

      expect(plain, 0.16);
      expect(repeat, closeTo(0.4 + 0.16 + 0.16 + 0.4 + 0.5, 1e-9));
      expect(startRepeatWidth(style), repeat);
    });

    test('a double and a final barline are wider than a plain one', () {
      expect(
        endBarlineWidth(edgesOf(end: Barline.doubleBar), style),
        closeTo(0.16 + 0.4 + 0.16, 1e-9),
      );
      expect(
        endBarlineWidth(edgesOf(end: Barline.finalBar), style),
        closeTo(0.16 + 0.4 + 0.5, 1e-9),
      );
    });

    test('a heavy barline is a thick line, a dashed or dotted one is thin, '
        'and an invisible one has no width', () {
      expect(endBarlineWidth(edgesOf(end: Barline.heavy), style), 0.5);
      expect(endBarlineWidth(edgesOf(end: Barline.dashed), style), 0.16);
      expect(endBarlineWidth(edgesOf(end: Barline.dotted), style), 0.16);
      expect(endBarlineWidth(edgesOf(end: Barline.invisible), style), 0);
    });
  });

  group('clef change inside a bar', () {
    BarLayout layoutOf(Score score) =>
        layoutBar(viewOf(score), style, const FakeMeasurer());

    Score halves(String first, String second) => scoreOf([
      [
        staffOf([
          chordOf(1, first, value: half),
          chordOf(2, second, value: half),
        ]),
      ],
    ]);

    Score withAltoAt(Score score, Moment offset) => after(score, [
      SetClef(
        staff: staffId(0),
        at: ScorePoint(barId(0), offset),
        clef: Clef.alto,
      ),
    ]);

    List<BarItem> clefsOf(BarLayout layout) => [
      for (final item in layout.items)
        if (item.drawable case GlyphDraw(
          glyph: Glyph.cClefChange || Glyph.gClef8vb,
        ))
          item,
    ];

    BarItem sharpOf(BarLayout layout) => layout.items.singleWhere(
      (item) => switch (item.drawable) {
        GlyphDraw(:final glyph) => glyph == sharp,
        _ => false,
      },
    );

    test('it is the small clef left of its slice', () {
      final layout = layoutOf(withAltoAt(halves('G4', 'G4'), at(1, 2)));
      final clef = clefsOf(layout).single;
      final draw = clef.drawable as GlyphDraw;

      expect(draw.glyph, Glyph.cClefChange);
      expect(layout.slices[clef.slice].at, at(1, 2));
      expect(clef.staff, 0);
      expect(draw.origin.y, 2);
      expect(draw.bounds.right, closeTo(-0.5, 1e-9));
      expect(draw.bounds.width, closeTo(2.024, 1e-9));
    });

    test('it sits left of what its slice reaches, and the slice before it '
        'makes room', () {
      final plain = halves('G4', 'F#4');
      final without = layoutOf(plain);
      final layout = layoutOf(withAltoAt(plain, at(1, 2)));
      final clef = clefsOf(layout).single;
      final accidental = sharpOf(layout);

      expect(accidental.slice, clef.slice);
      expect(
        clef.drawable.bounds.right,
        closeTo(accidental.drawable.bounds.left - 0.5, 1e-9),
      );
      expect(
        layout.slices[0].rod - without.slices[0].rod,
        closeTo(2.024 + 0.5, 1e-9),
      );
    });

    test('a change where no note starts takes a slice of its own and splits '
        'the space of the note it falls in', () {
      final plain = halves('G4', 'G4');
      final without = layoutOf(plain);
      final layout = layoutOf(withAltoAt(plain, at(3, 4)));

      expect(
        [for (final slice in layout.slices) slice.at],
        [Moment.zero, at(1, 2), at(3, 4), at(1, 1)],
      );
      expect(clefsOf(layout).single.slice, 2);
      expect(layout.slices[0].ideal, without.slices[0].ideal);
      expect(
        layout.slices[1].ideal + layout.slices[2].ideal,
        closeTo(without.slices[1].ideal, 1e-9),
      );
      expect(layout.slices[2].ideal, closeTo(layout.slices[1].ideal, 1e-9));
    });

    test('changes on two staves at one moment end at one x, left of what '
        'either staff reaches', () {
      final plain = scoreOf([
        [
          staffOf([
            chordOf(1, 'G4', value: half),
            chordOf(2, 'F#4', value: half),
          ]),
          staffOf([
            chordOf(3, 'G4', value: half),
            chordOf(4, 'G4', value: half),
          ]),
        ],
      ]);
      final layout = layoutOf(
        after(plain, [
          for (final (staff, clef) in [Clef.alto, Clef.treble8vb].indexed)
            SetClef(
              staff: staffId(staff),
              at: ScorePoint(barId(0), at(1, 2)),
              clef: clef,
            ),
        ]),
      );
      final clefs = clefsOf(layout);

      expect(clefs.map((item) => item.staff), [0, 1]);
      expect(clefs.map((item) => item.slice), [1, 1]);
      expect(
        clefs[0].drawable.bounds.width,
        isNot(closeTo(clefs[1].drawable.bounds.width, 0.1)),
      );
      for (final clef in clefs) {
        expect(
          clef.drawable.bounds.right,
          closeTo(sharpOf(layout).drawable.bounds.left - 0.5, 1e-9),
          reason: 'staff ${clef.staff}',
        );
      }
    });
  });

  group('bar layout', () {
    test('a bar holds its three heads and their widths', () {
      final score = after(
        beatsScore(2, key: const KeySignature(2)),
        [SetKey(from: barId(1), key: const KeySignature(-1))],
      );
      final view = viewOf(score, 1);
      final layout = layoutBar(view, style, const FakeMeasurer());
      final heads = barHeads(view, style);

      expect(layout.heads, heads);
      expect(layout.widths.inlineHead, heads.inline.width);
      expect(layout.widths.systemHead, heads.system.width);
      expect(layout.widths.courtesy, heads.courtesy.width);
      expect(
        {heads.inline.width, heads.system.width, heads.courtesy.width, 0.0},
        hasLength(3),
        reason: 'the inline head and the courtesy are the same key',
      );
      expect(heads.system.width, greaterThan(heads.inline.width));
    });

    test('a bar start joins the barline before it only when its inline head '
        'has nothing after that barline', () {
      final plain = beatsScore(2, key: const KeySignature(1));
      bool joins(List<Edit> edits) => layoutBar(
        viewOf(after(plain, edits), 1),
        style,
        const FakeMeasurer(),
      ).edges.startJoins;

      expect(joins([]), isTrue);
      expect(
        joins([SetKey(from: barId(1), key: const KeySignature(2))]),
        isFalse,
      );
      expect(
        joins([
          SetMeter(
            from: barId(1),
            meter: Meter.cut,
            content: MeterContent.keepBars,
          ),
        ]),
        isFalse,
      );
      expect(
        joins([
          SetClef(
            staff: staffId(0),
            at: ScorePoint(barId(1), Moment.zero),
            clef: Clef.bass,
          ),
        ]),
        isTrue,
      );
    });

    test('two bars that differ in a head or in a head width are not '
        'equal', () {
      final score = after(
        beatsScore(2, key: const KeySignature(2)),
        [SetKey(from: barId(1), key: const KeySignature(-1))],
      );
      final bar = layoutBar(viewOf(score, 1), style, const FakeMeasurer());
      final heads = bar.heads;
      BarLayout withCourtesy(SplitHead courtesy) => BarLayout(
        measure: bar.measure,
        length: bar.length,
        breakBefore: bar.breakBefore,
        restOnly: bar.restOnly,
        widths: bar.widths,
        lead: bar.lead,
        slices: bar.slices,
        staves: bar.staves,
        items: bar.items,
        heads: BarHeads(
          inline: heads.inline,
          system: heads.system,
          courtesy: courtesy,
        ),
        edges: bar.edges,
        beams: bar.beams,
        tuplets: bar.tuplets,
        ties: bar.ties,
        spanners: bar.spanners,
        volta: bar.volta,
        lyrics: bar.lyrics,
      );
      final kept = heads.courtesy.after;
      SplitHead courtesyOf(BarHead after, {BarHead before = BarHead.none}) =>
          SplitHead(before: before, after: after);

      expect(kept.items, isNotEmpty);
      expect(heads.courtesy.before, BarHead.none);
      expect(
        withCourtesy(
          courtesyOf(BarHead(items: [...kept.items], width: kept.width)),
        ),
        bar,
      );
      expect(withCourtesy(SplitHead.none), isNot(bar));
      expect(withCourtesy(courtesyOf(kept, before: kept)), isNot(bar));
      expect(
        withCourtesy(
          courtesyOf(
            BarHead(
              items: [
                for (final item in kept.items)
                  (staff: item.staff, drawable: item.drawable.shift(0, 1)),
              ],
              width: kept.width,
            ),
          ),
        ),
        isNot(bar),
      );

      BarWidths widthsOf({
        double inlineHead = 1,
        double systemHead = 2,
        double courtesy = 3,
      }) => BarWidths(
        inlineHead: inlineHead,
        systemHead: systemHead,
        courtesy: courtesy,
        body: 4,
        minBody: 5,
      );
      expect(widthsOf(), widthsOf());
      expect(widthsOf(inlineHead: 0), isNot(widthsOf()));
      expect(widthsOf(systemHead: 0), isNot(widthsOf()));
      expect(widthsOf(courtesy: 0), isNot(widthsOf()));
    });
  });

  group('system lead', () {
    Score scoreWith(List<Part> parts) => Score(
      meta: const ScoreMeta(),
      parts: Seq(parts),
      measures: Seq([
        MeasureColumn(
          id: const MeasureId(3000),
          meter: Meter.fourFour,
          key: KeySignature.cMajor,
          staves: Seq([
            for (final part in parts)
              for (final staff in part.staves)
                StaffMeasure(
                  staff: staff.id,
                  clef: Clef.treble,
                  voices: Seq([
                    Voice(
                      slot: VoiceSlot.one,
                      items: Seq([
                        MeasureRest(
                          id: EventId(staff.id.value),
                          span: Meter.fourFour.length,
                        ),
                      ]),
                    ),
                  ]),
                ),
          ]),
        ),
      ]),
    );

    Part partOf(
      int id,
      String name, {
      String shortName = '',
      int staves = 1,
      bool hidden = false,
    }) => Part(
      id: PartId(id),
      name: name,
      shortName: shortName,
      instrument: piano,
      staves: Seq([
        for (var s = 0; s < staves; s++) Staff(id: StaffId(id * 10 + s)),
      ]),
      hidden: hidden,
    );

    SystemLead leadOf(List<Part> parts) =>
        systemLead(scoreWith(parts), style, const FakeMeasurer());

    test('an indent is the widest name and a gap', () {
      final lead = leadOf([
        partOf(1, 'Flute', shortName: 'Fl.'),
        partOf(2, 'Violin', shortName: 'V.'),
      ]);

      expect(lead.firstIndent, closeTo(6 * 1.2 + 1, 1e-9));
      expect(lead.indent, closeTo(3 * 1.2 + 1, 1e-9));
      expect(lead.groups, [(0, 0), (1, 1)]);
      expect(lead.parts.map((part) => part.name), ['Flute', 'Violin']);
      expect(lead.parts.first.nameExtent.width, closeTo(6, 1e-9));
    });

    test('a part of two staves adds the brace to both indents', () {
      final lead = leadOf([
        partOf(1, 'Piano', staves: 2),
        partOf(2, 'Flute'),
      ]);

      expect(lead.firstIndent, closeTo(5 * 1.2 + 1 + braceWidth, 1e-9));
      expect(lead.indent, braceWidth);
      expect(lead.groups, [(0, 1), (2, 2)]);
    });

    test('a single unnamed part has no indent', () {
      final lead = leadOf([partOf(1, '')]);

      expect(lead.firstIndent, 0);
      expect(lead.indent, 0);
    });

    test('a hidden part has no name and no staves in the lead', () {
      final lead = leadOf([
        partOf(1, 'A very long hidden name', staves: 2, hidden: true),
        partOf(2, 'Oboe'),
      ]);

      expect(lead.parts.map((part) => part.name), ['Oboe']);
      expect(lead.groups, [(0, 0)]);
      expect(lead.firstIndent, closeTo(4 * 1.2 + 1, 1e-9));
    });
  });

  group('slices', () {
    test('the slice times include a clef change between two notes', () {
      final score = after(
        scoreOf([
          [
            staffOf([chordOf(1, 'B4', value: whole)]),
          ],
        ]),
        [
          SetClef(
            staff: staffId(0),
            at: ScorePoint(barId(0), at(3, 4)),
            clef: Clef.alto,
          ),
        ],
      );

      expect(sliceTimes(viewOf(score)), [Moment.zero, at(3, 4), at(1, 1)]);
    });
  });
}
