import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:simple_sheet_music/src/painting.dart';
import 'package:simple_sheet_music/src/paragraph_measurer.dart';

import '../packages/score_model/test/support.dart';
import 'support/draw.dart';
import 'support/glyph_gate.dart';

const double spacePx = 20;
const double margin = 2;
const double sheetWidth = 110;

const NoteValue dottedHalf = NoteValue(DurationBase.half, dots: 1);
const NoteValue eighth = NoteValue.eighth;
const NoteValue half = NoteValue.half;
const NoteValue whole = NoteValue.whole;

const violin = PartTemplate(
  name: 'Violin',
  shortName: 'Vln.',
  instrument: Instrument(key: 'violin', program: 40),
);

const grand = PartTemplate(
  name: 'Piano',
  shortName: 'Pno.',
  instrument: Instrument(key: 'piano', program: 0),
  staves: 2,
  clefs: [Clef.treble, Clef.bass],
);

const voice = PartTemplate(
  name: 'Voice',
  shortName: 'V.',
  instrument: Instrument(key: 'voice', program: 52),
);

Score edit(Score score, Edit edit) =>
    applied(EditSession.start(score).run(edit)).score;

SheetLayout layoutOf(Score score) => SheetLayout(
      score,
      width: sheetWidth,
      text: ParagraphMeasurer(),
      style: pictureStyle,
    );

List<Drawable> inkOf(SheetLayout layout, int system) {
  final label = layout.labelOf(system);
  return [...layout.systemAt(system).drawables, if (label != null) label];
}

Ink? inkOfImage(Uint8List rgba, int width) => inkIn(
      rgba,
      width,
      left: 0,
      top: 0,
      right: width,
      bottom: rgba.length ~/ (4 * width),
    );

/// The ink in each pixel column of an RGBA image [width] pixels wide, in
/// pixels fully covered.
List<double> columnInk(Uint8List rgba, int width) => [
      for (var x = 0; x < width; x++)
        [for (var at = x * 4 + 3; at < rgba.length; at += width * 4) rgba[at]]
                .fold(0, (sum, alpha) => sum + alpha) /
            255,
    ];

void expectInside(Ink? ink, ui.Rect rect, String reason) {
  expect(ink, isNotNull, reason: reason);
  expect(ink!.left, greaterThanOrEqualTo(rect.left - 1), reason: reason);
  expect(ink.top, greaterThanOrEqualTo(rect.top - 1), reason: reason);
  expect(ink.right, lessThanOrEqualTo(rect.right + 1), reason: reason);
  expect(ink.bottom, lessThanOrEqualTo(rect.bottom + 1), reason: reason);
}

/// The scale that paints a system whose band starts at [top]. A system on a
/// whole pixel keeps its glyphs where their boxes say.
SheetScale scaleOf(double top) => SheetScale(
      spacePx: spacePx,
      origin: ui.Offset(
        margin * spacePx,
        ((margin + top) * spacePx).ceilToDouble(),
      ),
    );

/// The PNG of [layout] under its header, after checking that each system's
/// ink alone stays inside its band.
Future<Uint8List> pictureOf(SheetLayout layout, GlyphPainter painter) async {
  final width = ((sheetWidth + 2 * margin) * spacePx).ceil();
  final height = ((layout.height + 2 * margin) * spacePx).ceil();
  for (var i = 0; i < layout.systemCount; i++) {
    final system = layout.systemAt(i);
    final scale = scaleOf(layout.tops[i]);
    final drawables = inkOf(layout, i);
    final alone = await render(
      width,
      height,
      (canvas) => paintDrawables(canvas, painter, drawables, scale),
      background: null,
    );
    expect(system.width, sheetWidth, reason: 'system $i');
    expectInside(
      inkOfImage(alone.rgba, width),
      scale.rectOf(Box(0, 0, system.width, system.height)),
      'system $i',
    );
  }
  final image = await render(width, height, (canvas) {
    paintDrawables(canvas, painter, layout.header, scaleOf(0));
    for (var i = 0; i < layout.systemCount; i++) {
      paintDrawables(
          canvas, painter, inkOf(layout, i), scaleOf(layout.tops[i]));
    }
  });
  return image.png;
}

/// A syllable from a token of a verse, where a leading `-` joins the word
/// before it, a trailing `-` continues the word and a trailing `_` starts a
/// melisma, as in `Gen-`, `-tle` and `ah_`.
Lyric syllable(String token, int verse) {
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

/// Eight bars for one voice with two verses, one in Latin and one in
/// Cyrillic letters. Words of two and three syllables are hyphenated inside a
/// bar, across a barline and across the system break before bar 5. Two
/// melismas carry extenders, one ending before the next syllable and one
/// crossing a barline to end before a rest.
Score vocal() {
  var score = blankScore(parts: const [voice], bars: 8).copyWith(
    meta: const ScoreMeta(
      title: 'Vocal Picture',
      subtitle: 'Eight bars for one voice, two verses',
      composer: 'The Layout Engine',
      lyricist: 'Nobody',
    ),
  );
  final ids = barIds(score);
  score = edit(score, SetBreak(ids[4], LayoutBreak.system));
  score = edit(score, SetBarline(ids[7], Barline.finalBar));

  var id = 10000;
  ChordEvent sung(
    String pitch,
    NoteValue value, [
    String? first,
    String? second,
  ]) =>
      chordOf(id++, pitch, value: value).copyWith(
        lyrics: Seq([
          if (first != null) syllable(first, 1),
          if (second != null) syllable(second, 2),
        ]),
      );

  for (final (bar, items) in <(int, List<VoiceItem>)>[
    (
      0,
      [
        sung('G4', NoteValue.quarter, 'Gen-', 'Сал-'),
        sung('A4', NoteValue.quarter, '-tle', '-хи'),
        sung('B4', half, 'wind', 'нам'),
      ]
    ),
    (
      1,
      [
        sung('C5', NoteValue.quarter, 'blows', 'дуу'),
        sung('D5', NoteValue.quarter, 'o-', 'сай-'),
        sung('E5', NoteValue.quarter, '-ver', '-хан'),
        sung('D5', NoteValue.quarter, 'the', 'тэр'),
      ]
    ),
    (
      2,
      [
        sung('C5', half, 'ah_', 'а_'),
        sung('B4', NoteValue.quarter),
        sung('A4', NoteValue.quarter),
      ]
    ),
    (
      3,
      [
        sung('G4', half, 'bright', 'гэгээн'),
        sung('A4', half, 'sun-', 'нар-'),
      ]
    ),
    (
      4,
      [
        sung('B4', half, '-light', '-ан'),
        sung('C5', half, 'falls', 'тусна'),
      ]
    ),
    (
      5,
      [
        sung('D5', NoteValue.quarter, 'soft-', 'зөө-'),
        sung('C5', NoteValue.quarter, '-ly', '-лөн'),
        sung('B4', NoteValue.quarter, 'down', 'бууна'),
        sung('A4', NoteValue.quarter, 'ev-', 'мөн-'),
      ]
    ),
    (
      6,
      [
        sung('G4', half, '-er', '-хөд'),
        sung('A4', half, 'oh_', 'о_'),
      ]
    ),
    (7, [sung('B4', half), rest(id++, half)]),
  ]) {
    score = fill(score, bar, items);
  }
  return score;
}

Score ensemble() {
  var score = blankScore(parts: const [violin, grand], bars: 16).copyWith(
    meta: const ScoreMeta(
      title: 'Sheet Picture',
      subtitle: 'Sixteen bars for violin and piano',
      composer: 'The Layout Engine',
      lyricist: 'Nobody',
    ),
  );
  final ids = barIds(score);
  score = edit(score, SetBarLength(ids[0], len(1, 4)));
  score = edit(score, SetRepeatStart(ids[4], start: true));
  score = edit(score, SetRepeatEnd(ids[7], const RepeatEnd()));
  score = edit(score, SetKey(from: ids[8], key: const KeySignature(2)));
  score = edit(score, SetMeter(from: ids[12], meter: Meter.threeFour));
  score = edit(score, SetBarline(ids[15], Barline.finalBar));

  var id = 10000;
  ChordEvent chord(
    String pitches, [
    NoteValue value = NoteValue.quarter,
    Set<Articulation> marks = const {},
  ]) =>
      chordOf(id++, pitches, value: value).copyWith(articulations: marks);
  RestEvent silence(NoteValue value) => rest(id++, value);
  ChordEvent fingered(ChordEvent chord, int finger) => chord.copyWith(
        notes: Seq([
          for (final note in chord.notes)
            (note as PitchedNote).copyWith(fingering: () => finger),
        ]),
      );
  const held = {Articulation.fermata};

  score = fill(score, 0, [chord('G4').copyWith(bowing: () => Bowing.up)]);
  for (final bar in [1, 2, 3]) {
    score = fill(score, bar, [
      for (final (i, pitch)
          in const ['G4', 'A4', 'B4', 'C5', 'D5', 'C5', 'B4', 'A4'].indexed)
        if (bar != 2)
          chord(pitch, eighth)
        else
          chord(pitch, eighth, {
            Articulation.staccato,
            if (i % 4 == 0) Articulation.accent,
          }).copyWith(bowing: () => i == 0 ? Bowing.down : null),
    ]);
    score = fill(
        score,
        bar,
        [
          chord('C4 E4 G4', half),
          chord('D4 F4 A4', half),
        ],
        staff: 1);
    score = fill(
        score,
        bar,
        [
          chord('C3'),
          chord('G2'),
          chord('E3'),
          chord('G2'),
        ],
        staff: 2);
  }
  for (final bar in [4, 5, 6, 7]) {
    score = fill(score, bar, [
      chord('D5').copyWith(ornament: () => bar == 6 ? Ornament.turn : null),
      silence(NoteValue.quarter),
      chord('E5', eighth),
      chord('F5', eighth),
      chord('G5').copyWith(ornament: () => bar == 5 ? Ornament.trill : null),
    ]);
    score = fill(
        score,
        bar,
        [
          silence(half),
          chord('E4 G4 B4', half),
        ],
        staff: 1);
    score = fill(score, bar, [chord('C3', whole)], staff: 2);
  }
  for (final bar in [8, 9, 10, 11]) {
    score = fill(score, bar, [
      for (final (pitch, value, finger) in const [
        ('A4', NoteValue.quarter, 0),
        ('D5', eighth, 3),
        ('F#5', eighth, 1),
        ('A5', NoteValue.quarter, 3),
        ('F#5', NoteValue.quarter, 1),
      ])
        if (bar == 9)
          fingered(chord(pitch, value), finger)
        else
          chord(pitch, value),
    ]);
    score = fill(score, bar, [chord('D4 F#4 A4', whole)], staff: 1);
    score = fill(
        score,
        bar,
        [
          chord('D3'),
          chord('A2'),
          chord('D3', half),
        ],
        staff: 2);
  }
  for (final bar in [12, 13, 14]) {
    score = fill(score, bar, [
      if (bar == 12)
        tripletOfEighths(500, [
          for (final pitch in const ['D5', 'E5', 'F#5']) chord(pitch, eighth),
        ])
      else
        chord('D5'),
      if (bar == 14)
        Tuplet(
          id: const TupletId(501),
          ratio: TupletRatio.triplet,
          unit: NoteValue.quarter,
          members: Seq([chord('C#5'), chord('D5'), chord('E5')]),
        )
      else ...[chord('C#5'), chord('D5')],
    ]);
    score = fill(
        score,
        bar,
        [
          chord('G4 B4'),
          silence(NoteValue.quarter),
          chord('A4 C#5'),
        ],
        staff: 1);
    score = fill(
        score,
        bar,
        [
          silence(NoteValue.quarter),
          chord('G2'),
          chord('A2'),
        ],
        staff: 2);
  }
  score = fill(score, 15, [chord('D5', dottedHalf, held)]);
  score = fill(score, 15, [chord('D4 F#4 A4', dottedHalf, held)], staff: 1);
  score = fill(score, 15, [chord('D3', dottedHalf, held)], staff: 2);

  score = edit(
    score,
    SetTempoMarks(
      ids[0],
      Seq(const [
        TempoMark(offset: Moment.zero, tempo: Tempo(120), text: 'Allegro'),
      ]),
    ),
  );
  score = edit(score, SetRehearsal(ids[4], 'A'));
  score = edit(score, SetRehearsal(ids[12], 'B'));
  for (final (bar, mark) in const <(int, NavigationMark)>[
    (4, Segno()),
    (6, ToCoda()),
    (11, Jump(JumpTarget.segno, then: JumpThen.toCoda)),
    (12, Coda()),
  ]) {
    score = edit(score, SetNavigation(ids[bar], Seq([mark])));
  }
  for (final (bar, staff, directions) in <(int, int, List<StaffDirection>)>[
    (0, 0, const [DynamicMark(Moment.zero, Dynamic.mf)]),
    (
      1,
      1,
      [
        const DynamicMark(Moment.zero, Dynamic.mp),
        const ChordSymbol(Moment.zero, root: PitchName(Step.c)),
        ChordSymbol(at(2, 4), root: const PitchName(Step.d), quality: 'm'),
      ]
    ),
    (4, 0, const [DynamicMark(Moment.zero, Dynamic.f)]),
    (8, 0, const [DynamicMark(Moment.zero, Dynamic.p)]),
    (
      9,
      1,
      const [
        ChordSymbol(
          Moment.zero,
          root: PitchName(Step.f, Alter.sharp),
          quality: 'm7',
          bass: PitchName(Step.a),
        ),
      ]
    ),
    (10, 0, const [TextMark(Moment.zero, 'dolce')]),
    (
      11,
      1,
      const [
        ChordSymbol(Moment.zero, root: PitchName(Step.b, Alter.flat)),
      ]
    ),
    (14, 0, const [DynamicMark(Moment.zero, Dynamic.pp)]),
  ]) {
    score = edit(
      score,
      SetDirections(
        staff: score.staves[staff].id,
        measure: ids[bar],
        directions: Seq(directions),
      ),
    );
  }

  score = edit(score, SetVolta(ids[7], ids[7], const Volta([1])));
  score = edit(score, SetVolta(ids[8], ids[8], const Volta([2])));
  score = tiedInto(score, 13, staff: 0);
  ScorePoint point(int bar, [Moment offset = Moment.zero]) =>
      pointAt(score, bar, offset);
  score = withSlur(score, point(1), point(1, at(7, 8)));
  score = withSpanner(
    score,
    const Slur(dashed: true),
    point(3),
    point(3, at(7, 8)),
  );
  score = withSpanner(
    score,
    const PedalLine(),
    point(8),
    point(9, at(2, 4)),
    staff: 2,
  );
  score = withSpanner(
    score,
    const Hairpin(crescendo: true),
    point(10),
    point(11, at(3, 4)),
  );
  score = withSpanner(
    score,
    const Hairpin(crescendo: false),
    point(12),
    point(13, at(2, 4)),
  );
  return withSpanner(score, const TrillLine(), point(14), point(15));
}

/// [score] with the last chord of [staff] in the bar before [bar] tied to the
/// first chord of [bar], and retuned to it where the two differ.
Score tiedInto(Score score, int bar, {required int staff}) {
  List<VoiceItem> itemsOf(int bar) =>
      [...score.measures[bar].staves[staff].voice(VoiceSlot.one)!.items];
  final before = itemsOf(bar - 1);
  final from = before.removeLast() as ChordEvent;
  final to = itemsOf(bar).first as ChordEvent;
  return fill(
    score,
    bar - 1,
    [
      ...before,
      chordOf(
        from.id.value,
        [for (final note in to.notes) '${(note as PitchedNote).pitch}']
            .join(' '),
        value: from.value,
        tie: true,
      ),
    ],
    staff: staff,
  );
}

Score overBarline(Score score, int bar) => withSpanner(
      withSlur(
        tiedInto(score, bar, staff: 2),
        pointAt(score, bar - 1, at(2, 4)),
        pointAt(score, bar, Moment.zero),
      ),
      const OctaveLine(OctaveShift.up8),
      pointAt(score, bar - 1, Moment.zero),
      pointAt(score, bar + 1, Moment.zero),
    );

int secondSystemStart(Score score) {
  final layout = layoutOf(score);
  return barIds(score).indexWhere((id) => layout.systemOf(id) == 1);
}

int tiedBar(Score score, int staff) => score.measures.toList().indexWhere(
      (measure) =>
          switch (measure.staves[staff].voice(VoiceSlot.one)!.items.last) {
        ChordEvent(:final notes) => notes.any((note) => note.tie),
        _ => false,
      },
    );

/// [ensemble] with [overBarline] at its first system break. What that adds
/// can move the break, so it is added again where the break went, three
/// times at most.
Score pictured() {
  final base = ensemble();
  var bar = secondSystemStart(base);
  var score = overBarline(base, bar);
  for (var round = 1; round < 3 && secondSystemStart(score) != bar; round++) {
    bar = secondSystemStart(score);
    score = overBarline(base, bar);
  }
  return score;
}

/// A violin and a piano over eight bars on two systems. The piano's lower
/// staff turns to the treble clef at a start repeat. The violin turns to
/// the alto clef with a new key and meter where the second system starts,
/// and back to the treble clef at the barline of an end repeat.
Score clefChanges() {
  var score = blankScore(parts: const [violin, grand], bars: 8);
  final ids = barIds(score);
  final [fiddle, _, lower] = [for (final staff in score.staves) staff.id];
  SetClef clefAt(StaffId staff, int bar, Clef clef) =>
      SetClef(staff: staff, at: ScorePoint(ids[bar], Moment.zero), clef: clef);
  score = [
    SetMeter(
      from: ids[4],
      meter: Meter.threeFour,
      content: MeterContent.keepBars,
    ),
    SetKey(from: ids[4], key: const KeySignature(-2)),
    SetBreak(ids[4], LayoutBreak.system),
    SetRepeatStart(ids[2], start: true),
    SetRepeatEnd(ids[5], const RepeatEnd()),
    clefAt(lower, 2, Clef.treble),
    clefAt(fiddle, 4, Clef.alto),
    clefAt(fiddle, 6, Clef.treble),
  ].fold(score, edit);

  var id = 20000;
  List<VoiceItem> line(List<String> pitches,
          [NoteValue value = NoteValue.quarter]) =>
      [for (final pitch in pitches) chordOf(id++, pitch, value: value)];
  for (var bar = 0; bar < 8; bar++) {
    final (melody, chords, bass) = switch (bar) {
      < 4 => (
          line(['G4', 'A4', 'B4', 'D5']),
          line(['C4 E4 G4', 'B3 D4 G4'], half),
          line(bar < 2 ? ['C3', 'G2'] : ['E4', 'C4'], half),
        ),
      < 6 => (
          line(['D4', 'F4', 'A4']),
          line(['D4 F4 A4'], dottedHalf),
          line(['F4'], dottedHalf),
        ),
      _ => (
          line(['F4', 'A4', 'D5']),
          line(['D4 F4 A4'], dottedHalf),
          line(['F4'], dottedHalf),
        ),
    };
    score = fill(score, bar, melody);
    score = fill(score, bar, chords, staff: 1);
    score = fill(score, bar, bass, staff: 2);
  }
  return score;
}

void main() {
  testWidgets(
      'clef changes paint small before their barlines, and the courtesy '
      'clef before the last barline of the system before', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();
      final layout = layoutOf(clefChanges());

      expect(layout.systemCount, 2);
      for (final (index, glyph, bar) in [
        (0, 'gClefChange', 1),
        (0, 'cClefChange', 3),
        (1, 'gClefChange', 1),
      ]) {
        final system = layout.systemAt(index);
        final bars = system.bars;
        final clef = system.drawables
            .whereType<GlyphDraw>()
            .singleWhere((draw) => draw.glyph.name == glyph)
            .bounds;
        final reason = '$glyph after bar $bar of system $index';

        expect(clef.left, greaterThanOrEqualTo(bars[bar].right - 1e-9),
            reason: reason);
        expect(
          clef.right,
          lessThan(bar + 1 < bars.length ? bars[bar + 1].left : system.width),
          reason: reason,
        );
      }
      writeSnapshot('sheet_clefs', await pictureOf(layout, painter));
    });
  });

  testWidgets(
      'a sheet of systems paints each system inside its band, under '
      'its header', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();
      final layout = layoutOf(pictured());
      final width = ((sheetWidth + 2 * margin) * spacePx).ceil();
      final height = ((layout.height + 2 * margin) * spacePx).ceil();
      final header = scaleOf(0);

      expect(layout.systemCount, inInclusiveRange(3, 4));
      expect(layout.header, isNotEmpty);
      writeSnapshot('sheet_ensemble', await pictureOf(layout, painter));

      final headerAlone = await render(
        width,
        height,
        (canvas) => paintDrawables(canvas, painter, layout.header, header),
        background: null,
      );
      final headerInk = inkOfImage(headerAlone.rgba, width);
      expect(headerInk, isNotNull);
      expect(headerInk!.top, greaterThanOrEqualTo(header.origin.dy - 1));
      expect(
        headerInk.bottom,
        lessThanOrEqualTo(scaleOf(layout.tops.first).origin.dy),
      );
    });
  });

  testWidgets(
      'a vocal line paints two verses with their hyphens and extenders '
      'inside each system\'s band', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();
      final layout = layoutOf(vocal());
      final spec = pictureStyle.specOf(TextRole.lyric);
      final thickness = painter.font.defaults.lyricLineThickness;
      List<TextDraw> lyricsOn(int system) => layout
          .systemAt(system)
          .drawables
          .whereType<TextDraw>()
          .where((text) => text.spec == spec)
          .toList();
      TextDraw wordOn(int system, String text) =>
          lyricsOn(system).singleWhere((draw) => draw.text == text);
      List<LineDraw> extendersOn(int system) => layout
          .systemAt(system)
          .drawables
          .whereType<LineDraw>()
          .where(
            (line) => line.from.y == line.to.y && line.thickness == thickness,
          )
          .toList();

      expect(layout.systemCount, 2);
      expect(wordOn(0, 'Сал').origin.y, greaterThan(wordOn(0, 'Gen').origin.y));
      expect(wordOn(0, 'Сал').bounds.left,
          lessThan(wordOn(0, 'Gen').bounds.right));
      expect(wordOn(0, 'Сал').bounds.right,
          greaterThan(wordOn(0, 'Gen').bounds.left));
      for (final (system, after, before) in [
        (0, 'Gen', 'tle'),
        (0, 'o', 'ver'),
        (1, 'soft', 'ly'),
        (1, 'ev', 'er'),
      ]) {
        expect(
          lyricsOn(system).where(
            (draw) =>
                draw.text == '-' &&
                draw.origin.y == wordOn(system, after).origin.y &&
                draw.bounds.left >= wordOn(system, after).bounds.right &&
                draw.bounds.right <= wordOn(system, before).bounds.left,
          ),
          hasLength(1),
          reason: 'one hyphen between $after and $before',
        );
      }
      for (final (system, from, to) in [
        (0, 'sun', null),
        (1, null, 'light'),
        (0, 'нар', null),
        (1, null, 'ан'),
      ]) {
        final edge = from != null
            ? wordOn(system, from).bounds.right
            : wordOn(system, to!).bounds.left;
        final row = wordOn(system, from ?? to!).origin.y;
        expect(
          lyricsOn(system).where(
            (draw) =>
                draw.text == '-' &&
                draw.origin.y == row &&
                (from != null
                    ? draw.bounds.left >= edge
                    : draw.bounds.right <= edge),
          ),
          isNotEmpty,
          reason: 'a hyphen ${from != null ? 'after $from' : 'before $to'} '
              'at the system break',
        );
      }
      expect(extendersOn(0), hasLength(2));
      expect(extendersOn(1), hasLength(2));
      for (final word in ['ah', 'а']) {
        final melisma = wordOn(0, word);
        expect(
          extendersOn(0)
              .singleWhere((line) => line.from.y == melisma.origin.y)
              .from
              .x,
          closeTo(melisma.bounds.right, 1e-9),
          reason: 'the extender of $word starts at its text',
        );
      }
      expect(
        extendersOn(1).map((line) => line.to.x),
        everyElement(greaterThan(layout.systemAt(1).bars[3].left)),
        reason: 'the final melisma runs on past the last barline',
      );

      writeSnapshot('sheet_lyrics', await pictureOf(layout, painter));
    });
  });

  testWidgets(
      'every tie, slur, line and ending of the score is drawn on the '
      'systems its bars are on', (tester) async {
    await tester.runAsync(() async {
      await loadTextFont();
      final score = pictured();
      final ids = barIds(score);
      final layout = layoutOf(score);
      final first = layout.systemAt(0);
      final second = layout.systemAt(1);
      SystemLayout systemOf(MeasureId bar) =>
          layout.systemAt(layout.systemOf(bar)!);
      Iterable<T> drawn<T extends Drawable>(SystemLayout system, Spanner of) =>
          system.drawables
              .whereType<T>()
              .where((drawable) => drawable.owner == SpannerOwner(of.id));
      Iterable<CurveDraw> tiesOf(SystemLayout system) => system.drawables
          .whereType<CurveDraw>()
          .where((curve) => curve.owner is ElementOwner);
      Spanner only<K extends SpannerKind>() =>
          score.spanners.singleWhere((spanner) => spanner.kind is K);

      final slurs = score.spanners.where((spanner) => spanner.kind is Slur);
      final cut = slurs.singleWhere(
        (slur) => slur.first.measure != slur.last.measure,
      );
      final octave = only<OctaveLine>();
      final cutTie = tiedBar(score, 2);
      for (final (what, from) in [
        ('the tie', ids[cutTie]),
        ('the slur', cut.first.measure),
        ('the octave line', octave.first.measure),
      ]) {
        expect(
          first.bars.last.measure,
          from,
          reason: '$what starts in the last bar of the first system',
        );
      }
      for (final (what, to) in [
        ('the tie', ids[cutTie + 1]),
        ('the slur', cut.last.measure),
      ]) {
        expect(
          second.bars.first.measure,
          to,
          reason: '$what ends in the first bar of the second system',
        );
      }
      expect(
        layout.systemOf(octave.last.measure),
        greaterThan(0),
        reason: 'the octave line runs on after the first system',
      );
      expect(
        drawn<GlyphDraw>(second, octave).map((glyph) => glyph.glyph),
        contains(Glyph.octaveParensLeft),
        reason: 'the octave line restates its sign on the second system',
      );
      for (final system in [first, second]) {
        expect(
          tiesOf(system),
          hasLength(1),
          reason: 'each system draws its half of the cut tie',
        );
      }

      for (final slur in slurs) {
        final from = layout.systemOf(slur.first.measure)!;
        final to = layout.systemOf(slur.last.measure)!;
        for (var i = from; i <= to; i++) {
          expect(
            drawn<CurveDraw>(layout.systemAt(i), slur).map((c) => c.dashed),
            [(slur.kind as Slur).dashed],
            reason: 'system $i draws one piece of slur ${slur.id}',
          );
        }
      }

      final tied = ids[tiedBar(score, 0)];
      final barline = systemOf(tied).barOf(tied)!.right;
      expect(
        tiesOf(systemOf(tied)).where(
          (tie) => tie.start.x < barline && tie.end.x > barline,
        ),
        hasLength(1),
        reason: 'a tie inside a system is one curve over its barline',
      );

      for (final hairpin in score.spanners.where((s) => s.kind is Hairpin)) {
        expect(
          drawn<LineDraw>(systemOf(hairpin.first.measure), hairpin),
          hasLength(2),
          reason: 'hairpin ${hairpin.id} is two lines',
        );
      }
      final pedal = only<PedalLine>();
      expect(
        drawn<GlyphDraw>(systemOf(pedal.first.measure), pedal)
            .map((glyph) => glyph.glyph),
        [Glyph.keyboardPedalPed],
        reason: 'the pedal line starts with its sign',
      );
      final trill = only<TrillLine>();
      expect(
        drawn<GlyphRunDraw>(systemOf(trill.first.measure), trill),
        hasLength(1),
        reason: 'the trill line is a run of wiggles',
      );

      final endings = systemOf(
        score.measures.firstWhere((measure) => measure.volta != null).id,
      ).drawables.whereType<TextDraw>().map((label) => label.text);
      expect(
        endings.where(const ['1.', '2.'].contains),
        ['1.', '2.'],
        reason: 'both endings are labelled, on one system',
      );
    });
  });

  testWidgets(
      'every mark, direction, system mark and tuplet of the score is drawn',
      (tester) async {
    await tester.runAsync(() async {
      await loadTextFont();
      final layout = layoutOf(pictured());
      final drawables = [
        for (var i = 0; i < layout.systemCount; i++)
          ...layout.systemAt(i).drawables,
      ];
      // A trill line starts with the trill's glyph too.
      final glyphs = drawables
          .whereType<GlyphDraw>()
          .where((glyph) => glyph.owner is! SpannerOwner)
          .toList();
      final texts = drawables.whereType<TextDraw>().toList();
      int count(Glyph glyph) => glyphs.where((g) => g.glyph == glyph).length;

      for (final (glyph, times) in const [
        (Glyph.articStaccatoBelow, 4),
        (Glyph.articStaccatoAbove, 4),
        (Glyph.articAccentBelow, 1),
        (Glyph.articAccentAbove, 1),
        (Glyph.fermataAbove, 3),
        (Glyph.ornamentTrill, 1),
        (Glyph.ornamentTurn, 1),
        (Glyph.stringsUpBow, 1),
        (Glyph.stringsDownBow, 1),
        (Glyph.fingering0, 1),
        (Glyph.fingering1, 2),
        (Glyph.fingering3, 2),
        (Glyph.dynamicMF, 1),
        (Glyph.dynamicMP, 1),
        (Glyph.dynamicForte, 1),
        (Glyph.dynamicPiano, 1),
        (Glyph.dynamicPP, 1),
        (Glyph.metNoteQuarterUp, 1),
        (Glyph.segno, 1),
        (Glyph.coda, 1),
        (Glyph.csymAccidentalSharp, 1),
        (Glyph.csymAccidentalFlat, 1),
        (Glyph.tuplet3, 2),
      ]) {
        expect(count(glyph), times, reason: glyph.name);
      }

      final words = texts.map((text) => text.text).toList();
      for (final text in const [
        'Allegro',
        '= 120',
        'dolce',
        'To Coda',
        'D.S. al Coda',
        'C',
        'D',
        'm',
        'F',
        'm7',
        '/',
        'B',
      ]) {
        expect(words, contains(text));
      }
      expect(
        texts.where((text) => text.enclosed).map((text) => text.text),
        ['A', 'B'],
        reason: 'the rehearsal marks are the boxed texts',
      );

      // A tuplet's number and bracket belong to no event. The bracket's
      // lines are as thick as the font says and no taller than the number,
      // which keeps barlines, staff lines and stems out of the count.
      final thickness =
          EngravingStyle.standard.font.defaults.tupletBracketThickness;
      final brackets = [
        for (var i = 0; i < layout.systemCount; i++)
          for (final number in layout
              .systemAt(i)
              .drawables
              .whereType<GlyphDraw>()
              .where((glyph) => glyph.glyph == Glyph.tuplet3))
            layout
                .systemAt(i)
                .drawables
                .whereType<LineDraw>()
                .where(
                  (line) =>
                      line.owner == null &&
                      line.thickness == thickness &&
                      line.bounds.bottom - line.bounds.top <=
                          number.bounds.bottom - number.bounds.top &&
                      line.bounds.bottom > number.bounds.top &&
                      line.bounds.top < number.bounds.bottom &&
                      line.bounds.left < number.bounds.right + 8 &&
                      line.bounds.right > number.bounds.left - 8,
                )
                .length,
      ];
      expect(
        glyphs
            .where((glyph) => glyph.glyph == Glyph.tuplet3)
            .map((glyph) => glyph.owner),
        everyElement(isNull),
      );
      expect(
        brackets,
        [0, 4],
        reason: 'the beamed triplet is its number alone, and the triplet of '
            'quarters has a bracket of two hooks and two halves',
      );
    });
  });

  testWidgets(
      'a rehearsal mark is painted with a hollow box on the edge of its '
      'bounds', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();
      final layout = layoutOf(pictured());
      const pad = 4;
      final marks = [
        for (var i = 0; i < layout.systemCount; i++)
          ...layout
              .systemAt(i)
              .drawables
              .whereType<TextDraw>()
              .where((text) => text.enclosed),
      ];
      expect(marks, hasLength(2));

      for (final mark in marks) {
        final box = mark.bounds;
        final scale = SheetScale(
          spacePx: spacePx,
          origin: ui.Offset(
            pad - box.left * spacePx,
            pad - box.top * spacePx,
          ),
        );
        final width = (box.width * spacePx).ceil() + 2 * pad;
        final alone = await render(
          width,
          (box.height * spacePx).ceil() + 2 * pad,
          (canvas) => paintDrawables(canvas, painter, [mark], scale),
          background: null,
        );
        final ink = inkOfImage(alone.rgba, width)!;
        final rect = scale.rectOf(box);
        final line = painter.font.defaults.textEnclosureThickness * spacePx;
        final columns = columnInk(alone.rgba, width);
        final reason = 'rehearsal mark ${mark.text}';

        expect(ink.left, closeTo(rect.left, 1), reason: reason);
        expect(ink.top, closeTo(rect.top, 1), reason: reason);
        expect(ink.right, closeTo(rect.right, 1), reason: reason);
        expect(ink.bottom, closeTo(rect.bottom, 1), reason: reason);
        for (final (side, x) in [
          ('left', rect.left + 1),
          ('right', rect.right - 2),
        ]) {
          expect(
            columns[x.floor()],
            closeTo(rect.height, 0.5),
            reason: '$reason, the $side line of its box',
          );
        }
        expect(
          columns[(rect.left + line + 2).floor()],
          closeTo(2 * line, 0.5),
          reason: '$reason, between its box and its letter',
        );
      }
    });
  });

  testWidgets(
      'a curve, a glyph run and a dashed line leave the ink their drawables '
      'describe', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();
      final layout = layoutOf(pictured());
      const pad = 4;
      final kinds = <String>{};

      for (var i = 0; i < layout.systemCount; i++) {
        for (final drawable in layout.systemAt(i).drawables) {
          final dashedLine =
              drawable is LineDraw && drawable.dash == LineDash.dashed;
          if (drawable is! CurveDraw &&
              drawable is! GlyphRunDraw &&
              !dashedLine) {
            continue;
          }
          final box = drawable.bounds;
          final scale = SheetScale(
            spacePx: spacePx,
            origin: ui.Offset(
              pad - (box.left * spacePx).floorToDouble(),
              pad - (box.top * spacePx).floorToDouble(),
            ),
          );
          final width = (box.width * spacePx).ceil() + 2 * pad + 1;
          final alone = await render(
            width,
            (box.height * spacePx).ceil() + 2 * pad + 1,
            (canvas) => paintDrawables(canvas, painter, [drawable], scale),
            background: null,
          );
          final ink = inkOfImage(alone.rgba, width);
          final rect = scale.rectOf(box);
          final reason = 'system $i, ${drawable.runtimeType} from x '
              '${box.left.toStringAsFixed(2)}';
          expectInside(ink, rect, reason);

          switch (drawable) {
            case GlyphRunDraw():
              kinds.add('glyph run');
              expect(ink!.left, closeTo(rect.left, 1), reason: reason);
              expect(ink.right, closeTo(rect.right, 1), reason: reason);
            case LineDraw(:final from, :final to, :final thickness):
              kinds.add('dashed line');
              expect(ink!.right, closeTo(rect.right, 1), reason: reason);
              final dashes =
                  columnInk(alone.rgba, width).reduce((a, b) => a + b) /
                      (thickness * spacePx);
              expect(
                dashes / ((to.x - from.x) * spacePx),
                inInclusiveRange(0.6, 0.7),
                reason: '$reason, the share of its length under dashes',
              );
            case CurveDraw(:final midThickness, :final endThickness):
              final start = scale.toPx(drawable.start).dx;
              final end = scale.toPx(drawable.end).dx;
              expect(ink!.left, lessThanOrEqualTo(start + 1), reason: reason);
              expect(ink.right, greaterThanOrEqualTo(end - 1), reason: reason);
              final columns = columnInk(alone.rgba, width);
              if (!drawable.dashed) {
                kinds.add('curve');
                expect(
                  columns[scale.toPx(drawable.pointAt(0.5)).dx.floor()],
                  closeTo((midThickness + endThickness) * spacePx, 0.5),
                  reason: '$reason, thickness at its middle',
                );
                continue;
              }
              kinds.add('dashed curve');
              final length = [
                for (var step = 0; step < 64; step++)
                  (scale.toPx(drawable.pointAt((step + 1) / 64)) -
                          scale.toPx(drawable.pointAt(step / 64)))
                      .distance,
              ].reduce((a, b) => a + b);
              final dashes =
                  columns.reduce((a, b) => a + b) / (midThickness * spacePx);
              expect(
                dashes / length,
                inInclusiveRange(0.6, 0.7),
                reason: '$reason, the share of its length under dashes '
                    'of its middle thickness',
              );
            default:
          }
        }
      }
      expect(kinds, {'curve', 'dashed curve', 'dashed line', 'glyph run'});
    });
  });

  testWidgets(
      'a sheet paints a caret, a selection across a system break and a '
      'playhead from the overlay queries as plain boxes', (tester) async {
    await tester.runAsync(() async {
      final painter = bravuraPainter();
      await loadBravura(painter);
      await loadTextFont();
      final score = pictured();
      final layout = layoutOf(score);
      final width = ((sheetWidth + 2 * margin) * spacePx).ceil();
      final height = ((layout.height + 2 * margin) * spacePx).ceil();
      final sheet = scaleOf(0);
      final ids = [for (final measure in score.measures) measure.id];
      final staves = [for (final staff in score.staves) staff.id];
      expect(layout.systemCount, greaterThanOrEqualTo(3));

      final second = layout.firstBarOf(1);
      final selection = RangeSelection(
        from: ScorePoint(ids[ids.indexOf(second) - 1], Moment(Fraction(1, 2))),
        to: ScorePoint(second, Moment(Fraction(1, 2))),
        top: staves[0],
        bottom: staves[1],
      );
      final cursor = VoicePoint(
        staff: staves[1],
        voice: VoiceSlot.one,
        at: ScorePoint(layout.firstBarOf(2), Moment(Fraction(1, 4))),
      );
      final script = PlaybackCompiler().compile(score);
      final point = script.pointAt(script.totalSeconds * 0.3)!;

      final boxes = layout.selectionBoxes(selection);
      final caret = layout.caretOf(cursor)!;
      final playhead = layout.playheadAt(point)!;
      final played = layout.systemOf(point.bar.measure)!;
      expect(boxes, hasLength(2));
      expect(boxes[0].right, layout.systemAt(0).bars.last.right);
      expect(
        boxes[1].left,
        layout.systemAt(1).bars.first.time.xAt(Moment.zero),
      );
      expect(boxes[0].top,
          closeTo(layout.tops[0] + layout.systemAt(0).staves[0].top, 1e-9));
      expect(
          boxes[0].bottom,
          closeTo(
              layout.tops[0] + layout.systemAt(0).staves[1].top + staffHeight,
              1e-9));
      expect(caret.left, caret.right);
      expect(
          caret.top,
          closeTo(layout.tops[2] + layout.systemAt(2).staffOf(staves[1])!.top,
              1e-9));
      expect(playhead.top, layout.tops[played]);
      expect(playhead.bottom, layout.tops[played] + layout.heightOf(played));

      void paintSheet(ui.Canvas canvas) {
        paintDrawables(canvas, painter, layout.header, scaleOf(0));
        for (var i = 0; i < layout.systemCount; i++) {
          paintDrawables(
              canvas, painter, inkOf(layout, i), scaleOf(layout.tops[i]));
        }
      }

      ui.Rect lineOf(Box box) => sheet.rectOf(box).inflate(1);
      final plain = await render(width, height, paintSheet);
      final image = await render(width, height, (canvas) {
        paintSheet(canvas);
        for (final box in boxes) {
          canvas.drawRect(
            sheet.rectOf(box),
            ui.Paint()..color = const ui.Color(0x553366FF),
          );
        }
        canvas
          ..drawRect(
            lineOf(playhead),
            ui.Paint()..color = const ui.Color(0xFF22AA44),
          )
          ..drawRect(
            lineOf(caret),
            ui.Paint()..color = const ui.Color(0xFFDD2222),
          );
      });
      writeSnapshot('sheet_overlays', image.png);

      (int, int, int) pixel(Uint8List rgba, ui.Offset at) {
        final i = (at.dy.round() * width + at.dx.round()) * 4;
        return (rgba[i], rgba[i + 1], rgba[i + 2]);
      }

      final caretPx = sheet.toPx(
        SpPoint(caret.left, (caret.top + caret.bottom) / 2),
      );
      expect(pixel(image.rgba, caretPx), (0xDD, 0x22, 0x22));
      final playheadPx = sheet.toPx(
        SpPoint(playhead.left, (playhead.top + playhead.bottom) / 2),
      );
      expect(pixel(image.rgba, playheadPx), (0x22, 0xAA, 0x44));
      for (final box in boxes) {
        final inside = sheet.toPx(
          SpPoint((box.left + box.right) / 2, (box.top + box.bottom) / 2),
        );
        final (r, _, b) = pixel(image.rgba, inside);
        final (r0, _, b0) = pixel(plain.rgba, inside);
        expect(r0, b0, reason: 'the sheet alone is grey at $inside');
        expect(b, greaterThan(r + 30), reason: 'tinted at $inside');
        final above = sheet.toPx(SpPoint((box.left + box.right) / 2, box.top));
        final (ra, _, ba) = pixel(image.rgba, above.translate(0, -3));
        expect(ra, ba, reason: 'untinted above the box at $above');
      }
    });
  });

  test('a dashed path ends on a dash, and a short one is stroked whole', () {
    List<ui.Rect> dashesOf(double length) => [
          for (final metric in dashPath(
            ui.Path()..lineTo(length, 0),
            LineDash.dashed,
            spacePx,
          ).computeMetrics())
            metric.extractPath(0, metric.length).getBounds(),
        ];

    final long = dashesOf(10.2 * spacePx);
    expect(long, hasLength(13));
    expect(
      long.map((dash) => dash.width),
      everyElement(closeTo(0.5 * spacePx, 1e-3)),
    );
    expect(long.first.left, 0);
    expect(long.last.right, closeTo(10.2 * spacePx, 1e-3));

    final short = dashesOf(0.9 * spacePx);
    expect(short, hasLength(1));
    expect(short.single.width, closeTo(0.9 * spacePx, 1e-3));
  });
}
