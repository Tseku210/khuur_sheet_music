import 'dart:typed_data';
import 'dart:ui' as ui;

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
    show cursorIn, headOf, host, imageOf, inked, playingIn, scrollOf, tune;
import 'support/draw.dart';
import 'support/glyph_gate.dart';

const double spacePx = 20;

/// Room around the system, so that a box grown past it stays in the picture.
const SheetScale scale = SheetScale(spacePx: spacePx, origin: Offset(40, 40));

const Color red = Color(0xFFFF0000);
const Color green = Color(0xFF00FF00);
const Color blue = Color(0xFF0000FF);
const Color clear = Color(0x00000000);

/// A palette whose overlay draws nothing, for a test to turn one part on.
const SheetPalette quiet = SheetPalette(
  ink: Color(0xFF000000),
  staffLines: Color(0xFF000000),
  outOfRange: Color(0xFF000000),
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

/// What the overlay of the first system of [layout] draws with [palette],
/// on a clear canvas.
Future<Pixels> overlayOf(
  SheetLayout layout,
  SheetPalette palette, {
  Selection selection = const NoSelection(),
  Map<ElementRef, Color> tints = const {},
  VoicePoint? cursor,
  PlaybackPosition? playing,
}) async {
  final playback = playing == null ? null : ValueNotifier(playing);
  final width = (sheetWidth * spacePx + 80).ceil();
  final height = (layout.heightOf(0) * spacePx + 80).ceil();
  final picture = await render(
    width,
    height,
    OverlayPainter(
      layout: layout,
      index: 0,
      cursor: cursor,
      selection: selection,
      tints: tints,
      playback: playback,
      glyphs: bravuraPainter(),
      palette: palette,
      scale: scale,
    ).paintOn,
    background: null,
  );
  playback?.dispose();
  return (width: width, rgba: picture.rgba);
}

extension on OverlayPainter {
  void paintOn(ui.Canvas canvas) => paint(canvas, Size.zero);
}

void main() {
  setUpAll(() => loadBravura(bravuraPainter()));

  test('a selected note gets a box grown by the padding, with the border '
      'inside it', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final head = headOf(score, 0, 1);
    final note = scale.rectOf(layout.systemAt(0).boundsOf(ElementOwner(head))!);
    final box = note.inflate(0.5 * spacePx);

    final pixels = await overlayOf(
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
    );

    expect(pixels.at(note.center), blue);
    expect(pixels.at(box.centerLeft.translate(6, 0)), blue);
    expect(pixels.at(box.centerLeft.translate(2, 0)), red);
    expect(pixels.at(box.topCenter.translate(0, 2)), red);
    expect(pixels.at(box.topLeft.translate(1.5, 1.5)), red);
    expect(pixels.at(box.centerLeft.translate(-2, 0)), clear);
    expect(pixels.at(box.bottomCenter.translate(0, 2)), clear);
  });

  test('a radius rounds the corners of the box', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final head = headOf(score, 0, 1);
    final box = scale
        .rectOf(layout.systemAt(0).boundsOf(ElementOwner(head))!)
        .inflate(0.5 * spacePx);

    final pixels = await overlayOf(
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

    final pixels = await overlayOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(border: red, borderWidth: 0.2),
      ),
      selection: range,
    );

    expect(pixels.at(box.centerLeft.translate(2, 0)), red);
    expect(pixels.at(box.center), clear, reason: 'no fill was asked for');
    expect(pixels.at(box.centerLeft.translate(-2, 0)), clear);
  });

  test('an ink draws the selected note again in its colour, and no '
      'box', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final head = headOf(score, 0, 1);
    final note = scale.rectOf(layout.systemAt(0).boundsOf(ElementOwner(head))!);

    final pixels = await overlayOf(
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

    final tinted = await overlayOf(layout, palette, tints: {note: blue});
    expect(tinted.at(middle), blue);

    final selected = await overlayOf(
      layout,
      palette,
      tints: {note: blue},
      selection: ItemSelection(Seq([note])),
    );
    expect(selected.at(middle), red);

    final heard = await overlayOf(
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

    final selected = await overlayOf(
      layout,
      quiet.copyWith(
        selection: const SheetHighlight(fill: blue, ink: red),
      ),
      selection: ItemSelection(Seq([sounding])),
    );
    expect(selected.at(middle), red);

    final heard = await overlayOf(
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

    final pixels = await overlayOf(
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
  });

  test('the caret and the playhead are as wide as their styles '
      'say', () async {
    final score = tune(bars: 4);
    final layout = layoutOf(score);
    final cursor = cursorIn(score, 1);
    final playing = playingIn(score, 2, through: 0.6);
    final caret = scale.rectOf(layout.caretIn(0, cursor)!);
    Future<Pixels> drawn({required double caretWidth, double? headWidth}) =>
        overlayOf(
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
    Future<Color> onScreen(SheetPalette palette) async {
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: key,
            child: SheetView(
              score: tune(bars: 2),
              controller: controller,
              style: pictureStyle,
              palette: palette,
            ),
          ),
        ),
      );
      return (await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage();
        final rgba = (await image.toByteData())!.buffer.asUint8List();
        final width = image.width;
        image.dispose();
        return (width: width, rgba: rgba).at(const Offset(1, 1));
      }))!;
    }

    expect(await onScreen(inked), clear);
    final plain = await imageOf(tester, controller);
    expect(
      (width: plain.width, rgba: plain.rgba).at(const Offset(1, 1)),
      clear,
    );

    expect(await onScreen(inked.copyWith(paper: cream)), cream);
    final onPaper = await imageOf(tester, controller);
    final pixels = (width: onPaper.width, rgba: onPaper.rgba);
    expect(pixels.at(const Offset(1, 1)), cream);
    expect(
      pixels.at(Offset(onPaper.width - 1, onPaper.height - 1)),
      cream,
      reason: 'the paper reaches the far corner of the image',
    );
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
