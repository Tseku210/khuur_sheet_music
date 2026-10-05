import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:simple_sheet_music/src/painting.dart';
import 'package:simple_sheet_music/src/score_player.dart';
import 'package:simple_sheet_music/src/sheet_palette.dart';
import 'package:simple_sheet_music/src/sheet_view.dart';

import 'sheet_picture_test.dart' show layoutOf, sheetWidth;
import 'sheet_view_test.dart'
    show
        cursorIn,
        headOf,
        host,
        imageOf,
        inked,
        picturesOf,
        playingIn,
        scrollOf,
        tune;
import 'support/draw.dart';
import 'support/glyph_gate.dart';

const double spacePx = 20;

/// Room around the system, so that a box grown past it stays in the picture.
const SheetScale scale = SheetScale(spacePx: spacePx, origin: Offset(40, 40));

const Color red = Color(0xFFFF0000);
const Color green = Color(0xFF00FF00);
const Color blue = Color(0xFF0000FF);
const Color black = Color(0xFF000000);
const Color clear = Color(0x00000000);

/// A palette whose overlay draws nothing, for a test to turn one part on.
const SheetPalette quiet = SheetPalette(
  ink: black,
  staffLines: black,
  outOfRange: black,
  cursor: SheetLine(color: clear),
  selection: SheetHighlight(),
  playback: SheetHighlight(),
  playhead: SheetLine(color: clear),
);

typedef Pixels = ({int width, Uint8List rgba});

extension on Pixels {
  /// The colour of the pixel that holds [point].
  Color at(Offset point) {
    final i = (point.dy.floor() * width + point.dx.floor()) * 4;
    return Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  /// The centre of every pixel that is not clear.
  List<Offset> get painted => [
    for (var i = 0; i < rgba.length; i += 4)
      if (rgba[i + 3] != 0) Offset(i ~/ 4 % width + 0.5, i ~/ 4 ~/ width + 0.5),
  ];

  /// How many pixels of the row through [point] are more than half covered.
  int widthAt(Offset point) {
    final row = point.dy.floor() * width * 4;
    return [
      for (var x = 0; x < width; x++)
        if (rgba[row + x * 4 + 3] > 127) x,
    ].length;
  }
}

/// What the tile of the first system of [layout] draws with [palette] on a
/// clear canvas, in the order the view stacks it. That is the highlights,
/// the system's own ink when [notes] is set, and the overlay.
Future<Pixels> marksOf(
  SheetLayout layout,
  SheetPalette palette, {
  Selection selection = const NoSelection(),
  Map<ElementRef, Color> tints = const {},
  VoicePoint? cursor,
  PlaybackPosition? playing,
  bool notes = false,
  SheetScale at = scale,
}) async {
  final playback = playing == null ? null : ValueNotifier(playing);
  final glyphs = bravuraPainter();
  final width = (sheetWidth * at.spacePx + 80).ceil();
  final height = (layout.heightOf(0) * at.spacePx + 80).ceil();
  final painters = [
    HighlightPainter(
      layout: layout,
      index: 0,
      selection: selection,
      playback: playback,
      palette: palette,
      scale: at,
    ),
    if (notes)
      SystemPainter(
        system: layout.systemAt(0),
        label: null,
        glyphs: glyphs,
        palette: palette,
        scale: at,
      ),
    OverlayPainter(
      layout: layout,
      index: 0,
      cursor: cursor,
      selection: selection,
      tints: tints,
      playback: playback,
      glyphs: glyphs,
      palette: palette,
      scale: at,
    ),
  ];
  final picture = await render(width, height, (canvas) {
    for (final painter in painters) {
      painter.paint(canvas, Size.zero);
    }
  }, background: null);
  playback?.dispose();
  return (width: width, rgba: picture.rgba);
}

/// What the repaint boundary with [key] shows on screen.
Future<Pixels> shotOf(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(key))
          .toImage();
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      final width = image.width;
      image.dispose();
      return (width: width, rgba: rgba);
    }))!;

void main() {
  setUpAll(() => loadBravura(bravuraPainter()));

  test('a selected note gets a box grown by the padding, with the border '
      'inside it, at any size of the staff', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final head = headOf(score, 0, 1);

    for (final space in [20.0, 10.0]) {
      final at = SheetScale(spacePx: space, origin: scale.origin);
      final note = at.rectOf(layout.systemAt(0).boundsOf(ElementOwner(head))!);
      final box = note.inflate(0.5 * space);
      final line = 0.2 * space;

      final pixels = await marksOf(
        layout,
        quiet.copyWith(
          selection: const SheetHighlight(
            fill: blue,
            border: red,
            borderWidth: 0.2,
            padding: 0.5,
          ),
        ),
        selection: ItemSelection(Seq([head])),
        at: at,
      );

      final reason = '$space pixels a staff space';
      expect(pixels.at(note.center), blue, reason: reason);
      expect(
        pixels.at(box.centerLeft.translate(line + 1.5, 0)),
        blue,
        reason: reason,
      );
      expect(
        pixels.at(box.centerLeft.translate(line / 2, 0)),
        red,
        reason: reason,
      );
      expect(
        pixels.at(box.topCenter.translate(0, line / 2)),
        red,
        reason: reason,
      );
      expect(
        pixels.at(box.topLeft.translate(1, 1)),
        red,
        reason: reason,
      );
      expect(
        pixels.at(box.centerLeft.translate(-2, 0)),
        clear,
        reason: reason,
      );
      expect(
        pixels.at(box.bottomCenter.translate(0, 2)),
        clear,
        reason: reason,
      );
    }
  });

  test('a border is 0.15 staff spaces wide when its style gives no '
      'width', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final head = headOf(score, 0, 1);
    final note = scale.rectOf(layout.systemAt(0).boundsOf(ElementOwner(head))!);

    final pixels = await marksOf(
      layout,
      quiet.copyWith(selection: const SheetHighlight(border: red)),
      selection: ItemSelection(Seq([head])),
    );

    // Three pixels at each side of the box, at 20 pixels a staff space.
    expect(pixels.widthAt(note.center), 6);
    expect(pixels.at(note.centerLeft.translate(1.5, 0)), red);
  });

  test('a fill lies under the notes and the staff lines', () async {
    const yellow = Color(0xFFFFEB3B);
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final staff = score.staves.first.id;
    final playing = playingIn(score, 0);
    final marks = <String, (SheetPalette, Selection, PlaybackPosition?)>{
      'a selected note': (
        quiet.copyWith(selection: const SheetHighlight(fill: yellow)),
        ItemSelection(Seq([headOf(score, 0, 1)])),
        null,
      ),
      'a selected range': (
        quiet.copyWith(selection: const SheetHighlight(fill: yellow)),
        RangeSelection(
          from: ScorePoint(score.measures[0].id, Moment.zero),
          to: ScorePoint(score.measures[1].id, Moment.zero),
          top: staff,
          bottom: staff,
        ),
        null,
      ),
      'a sounding note': (
        quiet.copyWith(
          playback: const SheetHighlight(fill: yellow, padding: 0.3),
        ),
        const NoSelection(),
        playing,
      ),
    };
    final plain = await marksOf(layout, quiet, notes: true);

    for (final MapEntry(key: what, value: (palette, selection, playing))
        in marks.entries) {
      final marked = await marksOf(
        layout,
        palette,
        selection: selection,
        playing: playing,
        notes: true,
      );
      final filled = marked.painted.where((at) => marked.at(at) == yellow);
      final inked = plain.painted.where((at) => plain.at(at) == black);
      final box = filled.fold<Rect?>(
        null,
        (box, at) => box?.expandToInclude(at & Size.zero) ?? at & Size.zero,
      )!;
      final under = inked.where(box.contains).toList();

      expect(under.length, greaterThan(20), reason: 'ink in the box of $what');
      expect(
        under.where((at) => marked.at(at) != black),
        isEmpty,
        reason: 'ink that the fill of $what covers',
      );
    }
  });

  testWidgets('the view lays the box of a selected note and of a sounding '
      'note under its notes', (tester) async {
    const yellow = Color(0xFFFFEB3B);
    final score = tune();
    final key = GlobalKey();
    final playback = ValueNotifier<PlaybackPosition?>(null);
    addTearDown(playback.dispose);
    Future<Pixels> onScreen(SheetPalette palette, Selection selection) async {
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: key,
            child: SheetView(
              score: score,
              style: pictureStyle,
              selection: selection,
              playback: playback,
              palette: palette,
            ),
          ),
        ),
      );
      return await shotOf(tester, key);
    }

    final plain = await onScreen(quiet, const NoSelection());
    final inked = plain.painted.where((at) => plain.at(at) == black).toList();
    const box = SheetHighlight(fill: yellow, padding: 0.5);

    for (final (what, palette, selection, playing) in [
      (
        'a selected note',
        quiet.copyWith(selection: box),
        Selection.event(headOf(score, 0, 1).event),
        null,
      ),
      (
        'a sounding note',
        quiet.copyWith(playback: box),
        const NoSelection(),
        playingIn(score, 0),
      ),
    ]) {
      playback.value = playing;
      final marked = await onScreen(palette, selection);
      final filled = marked.painted.where((at) => marked.at(at) == yellow);
      final around = filled.fold<Rect?>(
        null,
        (rect, at) => rect?.expandToInclude(at & Size.zero) ?? at & Size.zero,
      )!;
      final under = inked.where(around.contains).toList();

      expect(under.length, greaterThan(20), reason: 'ink in the box of $what');
      expect(
        under.where((at) => marked.at(at) != black),
        isEmpty,
        reason: 'ink that the fill of $what covers',
      );
    }
  });

  test('boxes that overlap make one shape, with one layer of fill and no '
      'border inside it', () async {
    const half = Color(0x800000FF);
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final system = layout.systemAt(0);
    final heads = [for (var note = 0; note < 4; note++) headOf(score, 0, note)];
    final notes = [
      for (final head in heads)
        scale.rectOf(system.boundsOf(ElementOwner(head))!),
    ];
    // Each box reaches into the next one and stays clear of the one after.
    final padding = (notes[1].left - notes[0].right) / 2 / spacePx + 0.6;
    final boxes = [for (final note in notes) note.inflate(padding * spacePx)];
    expect(boxes[0].intersect(boxes[1]).width, closeTo(1.2 * spacePx, 0.01));
    expect(boxes[0].right, lessThan(boxes[2].left));

    final pixels = await marksOf(
      layout,
      quiet.copyWith(
        selection: SheetHighlight(
          fill: half,
          border: red,
          borderWidth: 0.1,
          padding: padding,
        ),
      ),
      selection: ItemSelection(Seq(heads)),
    );

    final alone = pixels.at(boxes.first.centerLeft.translate(6, 0));
    expect(alone.a, closeTo(0.5, 0.01));
    for (var at = 0; at + 1 < boxes.length; at++) {
      final shared = boxes[at].intersect(boxes[at + 1]);
      final pair = 'boxes $at and ${at + 1}';
      expect(shared.width, greaterThan(4), reason: pair);
      expect(shared.height, greaterThan(10), reason: pair);
      expect(
        pixels.at(shared.center),
        alone,
        reason: 'one layer of fill where $pair meet',
      );
      expect(
        pixels.at(Offset(boxes[at + 1].left + 1, shared.center.dy)),
        alone,
        reason: 'no border where the later of $pair starts inside the other',
      );
      expect(
        pixels.at(Offset(boxes[at].right - 1, shared.center.dy)),
        alone,
        reason: 'no border where the earlier of $pair ends inside the other',
      );
    }
    expect(pixels.at(boxes.first.centerLeft.translate(1, 0)), red);
    expect(pixels.at(boxes.last.centerRight.translate(-1, 0)), red);
  });

  test('a style with nothing to draw draws nothing, and a border wider than '
      'its box stays in it', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final head = headOf(score, 0, 1);
    final note = scale.rectOf(layout.systemAt(0).boundsOf(ElementOwner(head))!);
    final cursor = cursorIn(score, 1);
    final nothing = <String, SheetPalette>{
      'a border of no width': quiet.copyWith(
        selection: const SheetHighlight(border: red, borderWidth: 0),
      ),
      'a padding that takes the box away': quiet.copyWith(
        selection: const SheetHighlight(fill: blue, border: red, padding: -3),
      ),
      'a caret of no width': quiet.copyWith(
        cursor: const SheetLine(color: red, width: 0),
      ),
    };

    for (final MapEntry(key: what, value: palette) in nothing.entries) {
      final pixels = await marksOf(
        layout,
        palette,
        selection: ItemSelection(Seq([head])),
        cursor: cursor,
      );
      expect(pixels.painted, isEmpty, reason: what);
    }

    final wide = await marksOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(border: red, borderWidth: 5),
      ),
      selection: ItemSelection(Seq([head])),
    );
    expect(wide.at(note.center), red);
    expect(
      wide.painted.where((at) => !note.inflate(1).contains(at)),
      isEmpty,
      reason: 'border off the box',
    );
  });

  test('a style refuses a length under zero, but a padding', () {
    for (final length in [-1.0, double.nan]) {
      expect(() => SheetHighlight(radius: length), throwsAssertionError);
      expect(() => SheetHighlight(borderWidth: length), throwsAssertionError);
      expect(() => SheetLine(color: red, width: length), throwsAssertionError);
    }
    expect(const SheetHighlight(padding: -1).padding, -1);
  });

  test('a radius rounds the corners of the box', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final head = headOf(score, 0, 1);
    final box = scale
        .rectOf(layout.systemAt(0).boundsOf(ElementOwner(head))!)
        .inflate(0.5 * spacePx);

    final pixels = await marksOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(fill: blue, radius: 0.4, padding: 0.5),
      ),
      selection: ItemSelection(Seq([head])),
    );

    expect(pixels.at(box.topLeft.translate(1.5, 1.5)), clear);
    expect(pixels.at(box.bottomRight.translate(-1.5, -1.5)), clear);
    expect(pixels.at(box.topLeft.translate(8, 8)), blue);
    expect(pixels.at(box.centerLeft.translate(1.5, 0)), blue);

    final bordered = await marksOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(
          fill: blue,
          border: red,
          borderWidth: 0.1,
          radius: 0.4,
          padding: 0.5,
        ),
      ),
      selection: ItemSelection(Seq([head])),
    );
    expect(
      bordered.at(box.topLeft.translate(1.5, 1.5)),
      clear,
      reason: 'the border follows the round corner',
    );
    expect(bordered.at(box.centerLeft.translate(1, 0)), red);
    expect(bordered.at(box.topLeft.translate(8, 8)), blue);

    // A corner so round that a border along the square would miss the arc,
    // in a style that has an ink too.
    final wide = scale
        .rectOf(layout.systemAt(0).boundsOf(ElementOwner(head))!)
        .inflate(spacePx);
    final arced = await marksOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(
          fill: blue,
          border: red,
          borderWidth: 0.2,
          radius: 1,
          padding: 1,
          ink: green,
        ),
      ),
      selection: ItemSelection(Seq([head])),
    );
    expect(arced.at(wide.topLeft.translate(1.5, 1.5)), clear);
    expect(
      arced.at(wide.topLeft.translate(7.5, 7.5)),
      red,
      reason: 'the border runs along the arc',
    );
    expect(arced.at(wide.topLeft.translate(12, 12)), blue);
  });

  test('a selected range gets the same box as a note', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final staff = score.staves.first.id;
    final range = RangeSelection(
      from: ScorePoint(score.measures[1].id, Moment.zero),
      to: ScorePoint(score.measures[2].id, Moment.zero),
      top: staff,
      bottom: staff,
    );
    final box = scale.rectOf(layout.selectionIn(0, range).single);

    final pixels = await marksOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(border: red, borderWidth: 0.2),
      ),
      selection: range,
    );

    expect(pixels.at(box.centerLeft.translate(2, 0)), red);
    expect(pixels.at(box.center), clear, reason: 'no fill was asked for');
    expect(pixels.at(box.centerLeft.translate(-2, 0)), clear);

    final styled = await marksOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(
          fill: blue,
          border: red,
          borderWidth: 0.2,
          radius: 0.4,
          padding: 0.5,
        ),
      ),
      selection: range,
    );
    final grown = box.inflate(0.5 * spacePx);
    expect(styled.at(box.center), blue);
    expect(styled.at(grown.centerLeft.translate(2, 0)), red);
    expect(
      styled.at(grown.centerLeft.translate(7, 0)),
      blue,
      reason: 'the fill reaches into the padding',
    );
    expect(styled.at(grown.topLeft.translate(1.5, 1.5)), clear);
    expect(styled.at(grown.centerLeft.translate(-2, 0)), clear);
  });

  test('an ink draws the selected note again in its colour, and no '
      'box', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final head = headOf(score, 0, 1);
    final note = scale.rectOf(layout.systemAt(0).boundsOf(ElementOwner(head))!);

    final pixels = await marksOf(
      layout,
      quiet.copyWith(selection: const SheetHighlight(ink: green)),
      selection: ItemSelection(Seq([head])),
    );

    expect(pixels.at(note.center), green, reason: 'the middle of the head');
    expect(
      pixels.painted.where((at) => !note.inflate(1).contains(at)),
      isEmpty,
      reason: 'ink off the selected head',
    );
    expect(pixels.at(note.topLeft.translate(1, 1)), clear, reason: 'no box');

    final other = scale.rectOf(
      layout.systemAt(0).boundsOf(ElementOwner(headOf(score, 0, 3)))!,
    );
    final two = await marksOf(
      layout,
      quiet.copyWith(selection: const SheetHighlight(ink: green)),
      selection: ItemSelection(Seq([head, headOf(score, 0, 3)])),
    );
    expect([two.at(note.center), two.at(other.center)], [green, green]);
  });

  test('the ink of the selection covers a tint, and the ink of playback '
      'covers both', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final playing = playingIn(score, 0);
    final sounding = playing.sounding.single;
    final head = score.lookup(sounding)!.event as ChordEvent;
    final note = NoteRef(sounding, head.notes.single.id);
    final middle = scale
        .rectOf(layout.systemAt(0).boundsOf(ElementOwner(note))!)
        .center;
    final palette = quiet.copyWith(
      selection: const SheetHighlight(ink: red),
      playback: const SheetHighlight(ink: green),
    );

    final tinted = await marksOf(layout, palette, tints: {note: blue});
    expect(tinted.at(middle), blue);

    final selected = await marksOf(
      layout,
      palette,
      tints: {note: blue},
      selection: ItemSelection(Seq([note])),
    );
    expect(selected.at(middle), red);

    final heard = await marksOf(
      layout,
      palette,
      tints: {note: blue},
      selection: ItemSelection(Seq([note])),
      playing: playing,
    );
    expect(heard.at(middle), green);
  });

  test('a box lies behind the ink it comes with', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final playing = playingIn(score, 0);
    final sounding = playing.sounding.single;
    final middle = scale
        .rectOf(
          layout.systemAt(0).boundsOf(ElementOwner(headOf(score, 0, 1)))!,
        )
        .center;
    expect(sounding.id, headOf(score, 0, 1).event.id);

    final selected = await marksOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(fill: blue, ink: red),
      ),
      selection: ItemSelection(Seq([sounding])),
    );
    expect(selected.at(middle), red);

    final heard = await marksOf(
      layout,
      quiet.copyWith(
        playback: const SheetHighlight(fill: blue, ink: green),
      ),
      playing: playing,
    );
    expect(heard.at(middle), green);
  });

  test('the sounding notes get a box when the playback style has a '
      'fill', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final playing = playingIn(score, 0);
    final sounding = [
      for (final ref in playing.sounding)
        scale.rectOf(layout.systemAt(0).boundsOf(ElementOwner(ref))!),
    ];
    expect(sounding, hasLength(1));

    final pixels = await marksOf(
      layout,
      quiet.copyWith(
        playback: const SheetHighlight(fill: blue, padding: 0.25),
      ),
      playing: playing,
    );

    final box = sounding.single.inflate(0.25 * spacePx);
    expect(pixels.at(box.topLeft.translate(2, 2)), blue);
    expect(pixels.at(box.bottomRight.translate(-2, -2)), blue);
    expect(
      pixels.painted.where((at) => !box.inflate(1).contains(at)),
      isEmpty,
      reason: 'paint off the sounding note',
    );

    final lined = await marksOf(
      layout,
      quiet.copyWith(
        playback: const SheetHighlight(border: red, borderWidth: 0.2),
      ),
      playing: playing,
    );
    expect(lined.at(sounding.single.centerLeft.translate(2, 0)), red);
    expect(lined.at(sounding.single.center), clear);

    final later = headOf(score, 0, 3).event;
    final laterBox = scale.rectOf(
      layout.systemAt(0).boundsOf(ElementOwner(later))!,
    );
    final two = await marksOf(
      layout,
      quiet.copyWith(
        playback: const SheetHighlight(fill: blue, ink: green),
      ),
      playing: PlaybackPosition(
        seconds: playing.seconds,
        point: playing.point,
        sounding: [...playing.sounding, later],
      ),
    );
    expect(two.at(laterBox.topLeft.translate(2, 2)), blue);
    expect(
      two.painted.where((at) => two.at(at) == green).any(laterBox.contains),
      isTrue,
      reason: 'the second sounding note is inked too',
    );

    final both = await marksOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(fill: red),
        playback: const SheetHighlight(fill: blue),
      ),
      selection: ItemSelection(Seq([playing.sounding.single])),
      playing: playing,
    );
    expect(
      both.at(sounding.single.topLeft.translate(2, 2)),
      blue,
      reason: 'the box of a sounding note lies over the box of a selected one',
    );
  });

  test('the caret and the playhead are as wide as their styles '
      'say', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final cursor = cursorIn(score, 1);
    final playing = playingIn(score, 2, through: 0.6);
    final caret = scale.rectOf(layout.caretIn(0, cursor)!);
    Future<Pixels> drawn({required double caretWidth, double? headWidth}) =>
        marksOf(
          layout,
          quiet.copyWith(
            cursor: SheetLine(color: red, width: caretWidth),
            playhead: headWidth == null
                ? null
                : SheetLine(color: green, width: headWidth),
          ),
          cursor: cursor,
          playing: headWidth == null ? null : playing,
        );

    final thin = await drawn(caretWidth: 0.2);
    final wide = await drawn(caretWidth: 0.5);
    expect(thin.widthAt(caret.center), closeTo(4, 1));
    expect(wide.widthAt(caret.center), closeTo(10, 1));
    expect(wide.at(caret.center.translate(3, 0)), red);

    // The caret stands on the staff, so a row above it holds the playhead
    // alone.
    final above = Offset(0, scale.origin.dy + 2);
    expect(caret.top, greaterThan(above.dy + 2));
    final both = await drawn(caretWidth: 0.2, headWidth: 0.6);
    expect(both.widthAt(above), closeTo(12, 1));
    final head = both.painted.firstWhere((at) => at.dy.floor() == above.dy);
    expect(both.at(head.translate(6, 0)), green);
  });

  testWidgets('the paper lies behind the sheet on screen and in an image', (
    tester,
  ) async {
    const cream = Color(0xFFFFF8E1);
    final controller = SheetController();
    addTearDown(controller.dispose);
    final key = GlobalKey();
    Future<Pixels> onScreen(SheetPalette palette) async {
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: key,
            child: SheetView(
              score: tune(bars: 12),
              controller: controller,
              style: pictureStyle,
              palette: palette,
            ),
          ),
        ),
      );
      return await shotOf(tester, key);
    }

    int inkIn(Pixels pixels) =>
        pixels.painted.where((at) => pixels.at(at) == inked.ink).length;

    final bare = await onScreen(inked);
    expect(bare.at(const Offset(1, 1)), clear);
    final plain = await imageOf(tester, controller);
    expect(
      (width: plain.width, rgba: plain.rgba).at(const Offset(1, 1)),
      clear,
    );

    final screen = await onScreen(inked.copyWith(paper: cream));
    expect(screen.at(const Offset(1, 1)), cream);
    expect(inkIn(bare), greaterThan(100));
    expect(inkIn(screen), inkIn(bare), reason: 'the ink on screen, on paper');

    expect(controller.systemCount, greaterThan(1));
    for (final from in [0, 1]) {
      final onPaper = await imageOf(tester, controller, from: from);
      final pixels = (width: onPaper.width, rgba: onPaper.rgba);
      expect(pixels.at(const Offset(1, 1)), cream, reason: 'from $from');
      expect(
        pixels.at(Offset(onPaper.width - 1, onPaper.height - 1)),
        cream,
        reason: 'the far corner of the image from $from',
      );
      expect(
        inkIn(pixels),
        greaterThan(100),
        reason: 'the ink of the image from $from, on paper',
      );
    }
  });

  testWidgets('a change of the palette repaints what shows the changed part '
      'and nothing else', (tester) async {
    final score = tune();
    // The painters compare these by identity, so the view gets the same
    // two each time and only the palette differs.
    final cursor = cursorIn(score, 1);
    final selection = Selection.event(headOf(score, 1, 0).event);
    Widget view(SheetPalette palette) => host(
      SheetView(
        score: score,
        cursor: cursor,
        selection: selection,
        palette: palette,
      ),
    );
    await tester.pumpWidget(view(inked));
    var header = picturesOf<HeaderPainter>(tester).single;
    var systems = picturesOf<SystemPainter>(tester);
    var overlays = picturesOf<OverlayPainter>(tester);
    expect(systems.length, greaterThan(1));

    Future<void> expectPainted(
      String part,
      SheetPalette palette, {
      required bool notes,
      required bool marks,
    }) async {
      await tester.pumpWidget(view(palette));
      final headerNow = picturesOf<HeaderPainter>(tester).single;
      final systemsNow = picturesOf<SystemPainter>(tester);
      final overlaysNow = picturesOf<OverlayPainter>(tester);
      expect(
        identical(headerNow, header),
        !notes,
        reason: 'the header, after $part',
      );
      for (final (tile, picture) in systemsNow.indexed) {
        expect(
          identical(picture, systems[tile]),
          !notes,
          reason: 'system $tile, after $part',
        );
      }
      for (final (tile, picture) in overlaysNow.indexed) {
        expect(
          identical(picture, overlays[tile]),
          !marks,
          reason: 'the marks of tile $tile, after $part',
        );
      }
      header = headerNow;
      systems = systemsNow;
      overlays = overlaysNow;
    }

    var palette = inked;
    for (final (part, change, notes, marks) in [
      ('ink', (SheetPalette p) => p.copyWith(ink: red), true, false),
      (
        'staffLines',
        (SheetPalette p) => p.copyWith(staffLines: red),
        true,
        false,
      ),
      (
        'outOfRange',
        (SheetPalette p) => p.copyWith(outOfRange: blue),
        true,
        false,
      ),
      (
        'selection',
        (SheetPalette p) =>
            p.copyWith(selection: const SheetHighlight(fill: green)),
        false,
        true,
      ),
      (
        'playback',
        (SheetPalette p) =>
            p.copyWith(playback: const SheetHighlight(fill: green)),
        false,
        true,
      ),
      (
        'cursor',
        (SheetPalette p) => p.copyWith(cursor: const SheetLine(color: green)),
        false,
        true,
      ),
      (
        'playhead',
        (SheetPalette p) => p.copyWith(playhead: const SheetLine(color: blue)),
        false,
        true,
      ),
      ('paper', (SheetPalette p) => p.copyWith(paper: green), false, false),
    ]) {
      palette = change(palette);
      await expectPainted(part, palette, notes: notes, marks: marks);
    }
  });

  testWidgets('a paper that comes and goes leaves the sheet where it was '
      'scrolled to', (tester) async {
    Widget view(SheetPalette palette) =>
        host(SheetView(score: tune(), palette: palette));
    await tester.pumpWidget(view(inked));
    scrollOf(tester).jumpTo(300);
    await tester.pump();

    await tester.pumpWidget(view(inked.copyWith(paper: red)));
    expect(scrollOf(tester).pixels, 300);

    await tester.pumpWidget(view(inked));
    expect(scrollOf(tester).pixels, 300);
  });

  // Which colour of the theme each part takes is not checked here.
  testWidgets('the palette of the theme fills the selection, inks the '
      'sounding notes and draws lines a fifth of a staff space wide', (
    tester,
  ) async {
    late SheetPalette palette;
    await tester.pumpWidget(
      Theme(
        data: ThemeData(colorScheme: const ColorScheme.light()),
        child: Builder(
          builder: (context) {
            palette = SheetPalette.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(palette.selection.fill, isNotNull);
    expect(palette.selection, SheetHighlight(fill: palette.selection.fill));
    expect(palette.playback.ink, isNotNull);
    expect(palette.playback, SheetHighlight(ink: palette.playback.ink));
    expect([palette.cursor.width, palette.playhead.width], [0.2, 0.2]);
    expect(palette.paper, isNull);
  });

  test('copyWith replaces the parts it is given and keeps the others', () {
    const other = SheetPalette(
      ink: Color(0xFF111111),
      staffLines: Color(0xFF222222),
      outOfRange: Color(0xFF333333),
      cursor: SheetLine(color: red, width: 0.4),
      selection: SheetHighlight(border: red),
      playback: SheetHighlight(fill: green),
      playhead: SheetLine(color: blue, width: 0.1),
      paper: Color(0xFF444444),
    );
    List<Object?> partsOf(SheetPalette palette) => [
      palette.ink,
      palette.staffLines,
      palette.outOfRange,
      palette.cursor,
      palette.selection,
      palette.playback,
      palette.playhead,
      palette.paper,
    ];
    final copies = [
      inked.copyWith(ink: other.ink),
      inked.copyWith(staffLines: other.staffLines),
      inked.copyWith(outOfRange: other.outOfRange),
      inked.copyWith(cursor: other.cursor),
      inked.copyWith(selection: other.selection),
      inked.copyWith(playback: other.playback),
      inked.copyWith(playhead: other.playhead),
      inked.copyWith(paper: other.paper),
    ];

    for (final (changed, copy) in copies.indexed) {
      expect(partsOf(copy), [
        for (final (index, part) in partsOf(inked).indexed)
          index == changed ? partsOf(other)[index] : part,
      ], reason: 'part $changed');
    }
    expect(inked.copyWith(), inked);
  });

  test('a copy of a style has the given parts replaced, and a style says '
      'what it holds', () {
    const highlight = SheetHighlight(
      fill: red,
      border: green,
      borderWidth: 0.2,
      radius: 0.3,
      padding: 0.4,
      ink: blue,
    );
    expect(highlight.copyWith(), highlight);
    expect(
      const SheetHighlight().copyWith(
        fill: red,
        border: green,
        borderWidth: 0.2,
        radius: 0.3,
        padding: 0.4,
        ink: blue,
      ),
      highlight,
    );
    expect(highlight.copyWith(radius: 0.5).radius, 0.5);
    expect(highlight.copyWith(radius: 0.5).copyWith(radius: 0.3), highlight);

    const line = SheetLine(color: red, width: 0.3);
    expect(line.copyWith(), line);
    expect(
      line.copyWith(color: blue),
      const SheetLine(color: blue, width: 0.3),
    );
    expect(line.copyWith(width: 0.5), const SheetLine(color: red, width: 0.5));

    expect('$line', allOf(contains('SheetLine'), contains('0.3')));
    expect(
      '$highlight',
      allOf(contains('SheetHighlight'), contains('0.2'), contains('0.4')),
    );
  });

  test('two styles are equal when every part is, so that only a style that '
      'differs repaints', () {
    const highlight = SheetHighlight(
      fill: red,
      border: green,
      borderWidth: 0.2,
      radius: 0.3,
      padding: 0.4,
      ink: blue,
    );
    const others = [
      SheetHighlight(
        fill: blue,
        border: green,
        borderWidth: 0.2,
        radius: 0.3,
        padding: 0.4,
        ink: blue,
      ),
      SheetHighlight(
        fill: red,
        border: blue,
        borderWidth: 0.2,
        radius: 0.3,
        padding: 0.4,
        ink: blue,
      ),
      SheetHighlight(
        fill: red,
        border: green,
        borderWidth: 0.25,
        radius: 0.3,
        padding: 0.4,
        ink: blue,
      ),
      SheetHighlight(
        fill: red,
        border: green,
        borderWidth: 0.2,
        radius: 0.35,
        padding: 0.4,
        ink: blue,
      ),
      SheetHighlight(
        fill: red,
        border: green,
        borderWidth: 0.2,
        radius: 0.3,
        padding: 0.45,
        ink: blue,
      ),
      SheetHighlight(
        fill: red,
        border: green,
        borderWidth: 0.2,
        radius: 0.3,
        padding: 0.4,
        ink: red,
      ),
    ];
    // Built at run time, so that it is another object than the constant.
    final same = SheetHighlight(
      fill: highlight.fill,
      border: highlight.border,
      borderWidth: highlight.borderWidth,
      radius: highlight.radius,
      padding: highlight.padding,
      ink: highlight.ink,
    );

    expect(same, highlight);
    expect(same.hashCode, highlight.hashCode);
    for (final other in others) {
      expect(other, isNot(highlight));
      expect(
        inked.copyWith(selection: other),
        isNot(inked.copyWith(selection: highlight)),
      );
    }

    const line = SheetLine(color: red, width: 0.3);
    final sameLine = SheetLine(color: line.color, width: line.width);
    expect(sameLine, line);
    expect(sameLine.hashCode, line.hashCode);
    expect(const SheetLine(color: blue, width: 0.3), isNot(line));
    expect(const SheetLine(color: red, width: 0.31), isNot(line));
    expect(
      inked.copyWith(paper: red),
      isNot(inked),
      reason: 'a paper is a part of the palette',
    );
  });
}
