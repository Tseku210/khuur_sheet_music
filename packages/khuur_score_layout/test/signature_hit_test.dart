import 'package:khuur_score_layout/khuur_score_layout.dart';
import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import '../../khuur_score_model/test/support.dart' show withSpanner;
import 'support/bars.dart';
import 'support/fake_measurer.dart';

SheetLayout sheetOf(Score score, {double width = 120}) =>
    SheetLayout(score, width: width, text: const FakeMeasurer());

/// The glyphs of [ink] that [system] draws, left to right.
List<GlyphDraw> glyphsOf(SystemLayout system, InkRole ink) =>
    system.drawables.whereType<GlyphDraw>().where((d) => d.ink == ink).toList()
      ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));

SpPoint centreOf(Box box) =>
    SpPoint((box.left + box.right) / 2, (box.top + box.bottom) / 2);

/// The text and the glyphs of the tempo marks [system] draws.
List<Drawable> tempoOf(SystemLayout system) => [
  for (final drawable in system.drawables)
    if (drawable.ink == InkRole.tempo) drawable,
];

/// [local], a point of system [index], in sheet space.
SpPoint onSheet(SheetLayout layout, int index, SpPoint local) =>
    local.shift(0, layout.tops[index]);

/// What a tap at the middle of [box] on system [index] is on.
SignatureHit? signatureOn(
  SheetLayout layout,
  int index,
  Box box, {
  double reach = 0,
}) => layout.signatureAt(onSheet(layout, index, centreOf(box)), reach: reach);

SignatureHit sign(
  SignatureKind kind,
  int bar, {
  int staff = 0,
  Moment offset = Moment.zero,
}) => SignatureHit(
  staff: staffId(staff),
  kind: kind,
  at: ScorePoint(barId(bar), offset),
);

void main() {
  group('a tap on a sign', () {
    test('on the first system names its clef, key and meter at the first '
        'bar, and between two sharps still names the key', () {
      final layout = sheetOf(beatsScore(2, key: const KeySignature(2)));
      final system = layout.systemAt(0);
      final clef = glyphsOf(system, InkRole.clef).first;
      final [first, second, ...] = glyphsOf(system, InkRole.keySignature);
      final digit = glyphsOf(system, InkRole.timeSignature).first;

      expect(signatureOn(layout, 0, clef.bounds), sign(SignatureKind.clef, 0));
      expect(signatureOn(layout, 0, first.bounds), sign(SignatureKind.key, 0));
      expect(
        signatureOn(layout, 0, digit.bounds),
        sign(SignatureKind.meter, 0),
      );
      final between = SpPoint(
        (first.bounds.right + second.bounds.left) / 2,
        (centreOf(first.bounds).y + centreOf(second.bounds).y) / 2,
      );
      expect(
        layout.signatureAt(onSheet(layout, 0, between)),
        sign(SignatureKind.key, 0),
      );
      expect(
        layout.hitTest(onSheet(layout, 0, centreOf(clef.bounds)))!.target,
        isNull,
        reason: 'hitTest still reports no target on a clef',
      );
    });

    test('on a later system names the clef and key it restates at its own '
        'first bar', () {
      final layout = sheetOf(
        after(beatsScore(4, key: const KeySignature(-3)), [
          SetBreak(barId(2), LayoutBreak.system),
        ]),
      );
      expect(layout.systemCount, 2);
      final system = layout.systemAt(1);
      final clef = glyphsOf(system, InkRole.clef).first;
      final key = glyphsOf(system, InkRole.keySignature).first;

      expect(signatureOn(layout, 1, clef.bounds), sign(SignatureKind.clef, 2));
      expect(signatureOn(layout, 1, key.bounds), sign(SignatureKind.key, 2));
    });

    test('on a key change in the middle of a system names the bar it heads, '
        'and on a courtesy key at a system end names the next system\'s '
        'first bar, as that system\'s own key does', () {
      final layout = sheetOf(
        after(beatsScore(4), [
          SetKey(from: barId(1), key: const KeySignature(-2)),
          SetKey(from: barId(2), key: const KeySignature(3)),
          SetBreak(barId(2), LayoutBreak.system),
        ]),
      );
      expect(layout.systemCount, 2);
      final system = layout.systemAt(0);
      final keys = glyphsOf(system, InkRole.keySignature);
      final inline = keys.firstWhere(
        (glyph) => glyph.bounds.left > system.bars[1].left - 2,
      );
      final courtesy = keys.lastWhere(
        (glyph) => glyph.bounds.left > system.bars.last.right,
      );
      final restated = glyphsOf(
        layout.systemAt(1),
        InkRole.keySignature,
      ).first;

      expect(signatureOn(layout, 0, inline.bounds), sign(SignatureKind.key, 1));
      expect(
        signatureOn(layout, 0, courtesy.bounds),
        sign(SignatureKind.key, 2),
      );
      expect(
        signatureOn(layout, 1, restated.bounds),
        signatureOn(layout, 0, courtesy.bounds),
      );
    });

    test('on a meter change at a system\'s first bar names that bar, both '
        'on the courtesy meter before it and on the meter it starts with', () {
      final layout = sheetOf(
        after(beatsScore(4), [
          SetMeter(from: barId(2), meter: Meter.threeFour),
          SetBreak(barId(2), LayoutBreak.system),
        ]),
      );
      expect(layout.systemCount, 2);
      final system = layout.systemAt(0);
      final courtesy = glyphsOf(
        system,
        InkRole.timeSignature,
      ).lastWhere((glyph) => glyph.bounds.left > system.bars.last.right);
      final restated = glyphsOf(
        layout.systemAt(1),
        InkRole.timeSignature,
      ).first;

      expect(
        signatureOn(layout, 0, courtesy.bounds),
        sign(SignatureKind.meter, 2),
      );
      expect(
        signatureOn(layout, 1, restated.bounds),
        sign(SignatureKind.meter, 2),
      );
    });

    test('on a clef that changes inside a bar names its offset, and on one '
        'before a barline names the bar after it', () {
      final layout = sheetOf(
        after(beatsScore(2), [
          SetClef(
            staff: staffId(0),
            at: ScorePoint(barId(0), at(1, 2)),
            clef: Clef.bass,
          ),
          SetClef(
            staff: staffId(0),
            at: ScorePoint(barId(1), Moment.zero),
            clef: Clef.alto,
          ),
        ]),
      );
      final system = layout.systemAt(0);
      Box changeOf(Glyph glyph) => glyphsOf(
        system,
        InkRole.clef,
      ).singleWhere((d) => d.glyph == glyph).bounds;

      expect(
        signatureOn(layout, 0, changeOf(Glyph.fClefChange)),
        sign(SignatureKind.clef, 0, offset: at(1, 2)),
      );
      expect(
        signatureOn(layout, 0, changeOf(Glyph.cClefChange)),
        sign(SignatureKind.clef, 1),
      );
    });

    test('on the lower staff of a two-staff part names that staff', () {
      final score = Score.blank(
        parts: const [
          PartTemplate(
            name: '',
            instrument: piano,
            staves: 2,
            clefs: [Clef.treble, Clef.bass],
          ),
        ],
        measureCount: 2,
        key: const KeySignature(1),
      );
      final [upper, lower] = [
        for (final staff in score.parts.single.staves) staff.id,
      ];
      final layout = sheetOf(score);
      final system = layout.systemAt(0);
      final lowerTop = system.staffOf(lower)!.top;
      final bass = glyphsOf(
        system,
        InkRole.clef,
      ).singleWhere((d) => d.glyph == Glyph.fClef);
      final [upperKey, lowerKey] = [
        for (final glyph in glyphsOf(system, InkRole.keySignature))
          if (glyph.bounds.left < system.bars.first.time.xAt(Moment.zero))
            glyph,
      ]..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
      final digits = glyphsOf(system, InkRole.timeSignature);

      SignatureHit on(Box box) => signatureOn(layout, 0, box)!;
      expect(on(bass.bounds).staff, lower);
      expect(on(bass.bounds).kind, SignatureKind.clef);
      expect(on(upperKey.bounds).staff, upper);
      expect(on(lowerKey.bounds).staff, lower);
      expect(
        on(digits.lastWhere((d) => d.bounds.top > lowerTop).bounds),
        SignatureHit(
          staff: lower,
          kind: SignatureKind.meter,
          at: ScorePoint(score.measures.first.id, Moment.zero),
        ),
      );
    });
  });

  group('a tap on a tempo mark', () {
    test('names the bar and the offset it stands at, on its words, its '
        'note or its number, and a mark of words alone too', () {
      final layout = sheetOf(
        after(beatsScore(2), [
          SetTempoMarks(
            barId(0),
            Seq(const [TempoMark(offset: Moment.zero, tempo: Tempo.unmarked)]),
          ),
          SetTempoMarks(
            barId(1),
            Seq([
              TempoMark(
                offset: at(2, 4),
                tempo: const Tempo(60),
                text: 'Adagio',
                showMetronome: false,
              ),
            ]),
          ),
        ]),
        width: 200,
      );
      final system = layout.systemAt(0);
      final [note, number, words] = [
        system.drawables.whereType<GlyphDraw>().singleWhere(
          (d) => d.ink == InkRole.tempo,
        ),
        system.drawables.whereType<TextDraw>().singleWhere(
          (d) => d.ink == InkRole.tempo && d.text == '= 100',
        ),
        system.drawables.whereType<TextDraw>().singleWhere(
          (d) => d.ink == InkRole.tempo && d.text == 'Adagio',
        ),
      ];

      expect(
        signatureOn(layout, 0, note.bounds),
        sign(SignatureKind.tempo, 0),
      );
      expect(
        signatureOn(layout, 0, number.bounds),
        sign(SignatureKind.tempo, 0),
      );
      expect(
        signatureOn(layout, 0, words.bounds),
        sign(SignatureKind.tempo, 1, offset: at(2, 4)),
      );
      expect(
        system.signatures
            .where((placed) => placed.signature.kind == SignatureKind.tempo)
            .map((placed) => placed.signature),
        [
          sign(SignatureKind.tempo, 0),
          sign(SignatureKind.tempo, 1, offset: at(2, 4)),
        ],
        reason: 'one box for each mark, over all it prints',
      );
    });

    test('names the top staff of the system, over a two-staff part', () {
      final score = Score.blank(
        parts: const [
          PartTemplate(
            name: '',
            instrument: piano,
            staves: 2,
            clefs: [Clef.treble, Clef.bass],
          ),
        ],
        measureCount: 1,
      );
      final marked = after(score, [
        SetTempoMarks(
          score.measures.single.id,
          Seq(const [TempoMark(offset: Moment.zero, tempo: Tempo(80))]),
        ),
      ]);
      final layout = sheetOf(marked);
      final mark = tempoOf(layout.systemAt(0)).first;

      expect(
        signatureOn(layout, 0, mark.bounds),
        SignatureHit(
          staff: marked.parts.single.staves.first.id,
          kind: SignatureKind.tempo,
          at: ScorePoint(marked.measures.single.id, Moment.zero),
        ),
      );
    });

    test("is not a tap on a tempo line's words, which are the line's", () {
      final score = beatsScore(1);
      final layout = sheetOf(
        withSpanner(
          score,
          const TempoLine(text: 'rit.', factor: 0.5),
          ScorePoint(score.measures.single.id, Moment.zero),
          ScorePoint(score.measures.single.id, at(2, 4)),
        ),
      );
      final system = layout.systemAt(0);
      final label = system.drawables.whereType<TextDraw>().singleWhere(
        (d) => d.text == 'rit.',
      );

      expect(system.signatures.map((placed) => placed.signature.kind), {
        SignatureKind.clef,
        SignatureKind.meter,
      });
      expect(signatureOn(layout, 0, label.bounds), isNull);
      expect(
        layout.hitTest(onSheet(layout, 0, centreOf(label.bounds)))!.target,
        label.owner,
      );
    });
  });

  group('a tap that is not on a sign', () {
    const reach = 2.0;

    test('on the first note after a meter takes the note, and one nearer '
        'the meter takes the meter, at a finger\'s reach', () {
      final layout = sheetOf(beatsScore(1));
      final system = layout.systemAt(0);
      final meter = glyphsOf(
        system,
        InkRole.timeSignature,
      ).map((d) => d.bounds).reduce((a, b) => a.union(b));
      final head = system.drawables.whereType<GlyphDraw>().firstWhere(
        (d) => d.owner is ElementOwner && d.ink == InkRole.notehead,
      );
      final owner = head.owner!;
      final gap = head.bounds.left - meter.right;
      expect(gap, lessThan(reach), reason: 'both are within reach');
      final y = centreOf(head.bounds).y;
      SpPoint at(double x) => onSheet(layout, 0, SpPoint(x, y));

      expect(
        layout.signatureAt(at(centreOf(head.bounds).x), reach: reach),
        isNull,
      );
      expect(
        layout.hitTest(at(centreOf(head.bounds).x), reach: reach)!.target,
        owner,
      );
      final nearHead = at(head.bounds.left - gap / 4);
      expect(layout.signatureAt(nearHead, reach: reach), isNull);
      expect(layout.hitTest(nearHead, reach: reach)!.target, owner);
      final nearMeter = at(meter.right + gap / 4);
      expect(
        layout.signatureAt(nearMeter, reach: reach),
        sign(SignatureKind.meter, 0),
      );
    });

    test('on an empty stretch of staff, on a bar with no sign and on a C '
        'major key\'s place is on nothing', () {
      final layout = sheetOf(
        scoreOf([
          [staffOf([])],
          [staffOf([])],
        ]),
      );
      final system = layout.systemAt(0);
      final staff = system.staves.single;
      final clef = glyphsOf(system, InkRole.clef).single;
      final bar = system.bars[1];

      expect(glyphsOf(system, InkRole.keySignature), isEmpty);
      expect(
        layout.signatureAt(
          onSheet(layout, 0, SpPoint(clef.bounds.right + 0.6, staff.yOf(4))),
        ),
        isNull,
        reason: 'where a key would stand, C major draws nothing',
      );
      expect(
        layout.signatureAt(
          onSheet(
            layout,
            0,
            SpPoint((bar.left + bar.right) / 2, staff.yOf(4)),
          ),
          reach: reach,
        ),
        isNull,
      );
    });
  });

  test('timeSignatureRows gives the glyphs and the steps the sheet draws '
      'each meter in', () {
    for (final meter in [
      Meter.fourFour,
      Meter.common,
      Meter.cut,
      Meter.simple(12, 8),
      Meter.simple(1, 16),
      const Meter([3, 2, 2], 8),
    ]) {
      final layout = sheetOf(beatsScore(1, meter: meter), width: 200);
      final system = layout.systemAt(0);
      final staff = system.staves.single;
      final drawn = <int, List<Glyph>>{};
      for (final glyph in glyphsOf(system, InkRole.timeSignature)) {
        (drawn[staff.stepAt(glyph.origin.y)] ??= []).add(glyph.glyph);
      }
      expect(
        {
          for (final row in timeSignatureRows(meter)) row.step: row.glyphs,
        },
        drawn,
        reason: '$meter',
      );
    }
  });

  test('keySignatureSteps gives the steps the sheet draws each key on, for '
      'every key under the treble, the bass and the alto clef', () {
    for (final clef in [Clef.treble, Clef.bass, Clef.alto]) {
      for (var fifths = -7; fifths <= 7; fifths++) {
        final key = KeySignature(fifths);
        final layout = sheetOf(
          beatsScore(1, clefs: [clef], key: key),
          width: 200,
        );
        final system = layout.systemAt(0);
        final staff = system.staves.single;
        final drawn = [
          for (final glyph in glyphsOf(system, InkRole.keySignature))
            staff.stepAt(glyph.origin.y),
        ];
        expect(
          keySignatureSteps(key, clef),
          drawn,
          reason: '$fifths fifths under $clef',
        );
        expect(
          glyphsOf(system, InkRole.keySignature).map((d) => d.glyph).toSet(),
          fifths == 0
              ? isEmpty
              : {
                  fifths > 0 ? Glyph.accidentalSharp : Glyph.accidentalFlat,
                },
        );
      }
    }
  });
}
