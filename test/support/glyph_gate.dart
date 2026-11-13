/// Gate 1 of the layout design. Measures where `GlyphPainter` puts a glyph's
/// ink against the box the font's table gives it.
///
/// The host test and the device test both run [measureGlyph] and judge it
/// with [failuresAtViewSize] and [failuresAtTableSize], so one definition of
/// the gate holds on every platform.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:khuur_sheet_music/src/painting.dart';
import 'package:score_layout/score_layout.dart';

/// A pixel rectangle with fractional edges, in device pixels.
typedef Ink = ({double left, double top, double right, double bottom});

/// The worst a glyph's ink was off over every origin tried, in device
/// pixels.
typedef InkErrors = ({
  double centreX,
  double centreY,
  double width,
  double height,
  double edge,
});

/// Logical pixels per staff space, and device pixels per logical pixel.
typedef GateSize = ({double spacePx, double pixelRatio});

/// The sizes the view draws at, each at three device pixel ratios.
const List<GateSize> viewSizes = [
  (spacePx: 8.0, pixelRatio: 1.0),
  (spacePx: 8.0, pixelRatio: 2.0),
  (spacePx: 8.0, pixelRatio: 3.0),
  (spacePx: 16.0, pixelRatio: 1.0),
  (spacePx: 16.0, pixelRatio: 2.0),
  (spacePx: 16.0, pixelRatio: 3.0),
];

/// The size that checks the table itself, where a pixel is small against
/// the glyph.
const GateSize tableSize = (spacePx: 64.0, pixelRatio: 1.0);

/// How many origins are tried along each axis, a device pixel apart in
/// [phases] steps.
const phases = 8;

/// Clear pixels around each glyph, so a misplaced one is measured and does
/// not run into its neighbour.
const _margin = 6;

/// The ink box inside the pixels `[left, right) x [top, bottom)` of an RGBA
/// image [imageWidth] wide, read by coverage. Null when nothing is drawn
/// there.
///
/// An edge is the outermost row or column the ink touches, moved in by the
/// part of that pixel the ink leaves empty. That is exact for ink at least a
/// pixel wide where it meets the edge. A thinner or pointed end covers less
/// of its last pixel than it reaches into it, and reads short. Ink inside a
/// single row or column is taken as centred in it, because its place there
/// cannot be read.
Ink? inkIn(
  Uint8List rgba,
  int imageWidth, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final rows = Uint8List(bottom - top);
  final columns = Uint8List(right - left);
  for (var y = top; y < bottom; y++) {
    var alpha = (y * imageWidth + left) * 4 + 3;
    for (var x = left; x < right; x++, alpha += 4) {
      final value = rgba[alpha];
      if (value > rows[y - top]) {
        rows[y - top] = value;
      }
      if (value > columns[x - left]) {
        columns[x - left] = value;
      }
    }
  }
  final x = _span(columns);
  final y = _span(rows);
  if (x == null || y == null) {
    return null;
  }
  return (
    left: left + x.from,
    top: top + y.from,
    right: left + x.to,
    bottom: top + y.to,
  );
}

({double from, double to})? _span(Uint8List coverage) {
  final first = coverage.indexWhere((value) => value > 0);
  if (first < 0) {
    return null;
  }
  final last = coverage.lastIndexWhere((value) => value > 0);
  if (first == last) {
    final covered = coverage[first] / 255;
    return (from: first + (1 - covered) / 2, to: first + (1 + covered) / 2);
  }
  return (
    from: first + 1 - coverage[first] / 255,
    to: last + coverage[last] / 255,
  );
}

/// Draws [glyph] through [painter] at [phases] x [phases] origins and
/// returns the worst error of each kind.
///
/// With [size] or [stretch] the ink is held to the table's box scaled about
/// the glyph's origin, evenly by [size] and vertically by [stretch] too.
///
/// Null when any origin drew no ink, which is what a font that did not load
/// looks like.
Future<InkErrors?> measureGlyph(
  GlyphPainter painter,
  Glyph glyph, {
  required double spacePx,
  required double pixelRatio,
  double size = 1,
  double stretch = 1,
}) async {
  final unit = spacePx * pixelRatio;
  final table = painter.font[glyph].box;
  final box = Box(
    table.left * size,
    table.top * size * stretch,
    table.right * size,
    table.bottom * size * stretch,
  );
  // Whole pixels, so each origin's place inside a pixel is its phase alone.
  int reach(double spaces) => math.max(0, (spaces * unit).ceil());
  final lead = _margin + reach(-box.left);
  final rise = _margin + reach(-box.top);
  final cellWidth = lead + reach(box.right) + _margin + 1;
  final cellHeight = rise + reach(box.bottom) + _margin + 1;

  final scale = SheetScale(spacePx: spacePx);
  // The origin of the cell in [column], in device pixels from the corner of
  // its row's image.
  ui.Offset originOf(int column, int row) => ui.Offset(
    column * cellWidth + lead + column / phases,
    rise + row / phases,
  );

  var worst = (centreX: 0.0, centreY: 0.0, width: 0.0, height: 0.0, edge: 0.0);
  // One image per row of cells, which keeps a tall glyph's image inside the
  // texture size of an old phone.
  for (var row = 0; row < phases; row++) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(pixelRatio);
    for (var column = 0; column < phases; column++) {
      final origin = originOf(column, row);
      painter.paint(
        canvas,
        glyph,
        SpPoint(origin.dx / unit, origin.dy / unit),
        scale,
        const ui.Color(0xFF000000),
        size: size,
        stretch: stretch,
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(cellWidth * phases, cellHeight);
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    picture.dispose();

    for (var column = 0; column < phases; column++) {
      final ink = inkIn(
        rgba,
        cellWidth * phases,
        left: column * cellWidth,
        top: 0,
        right: (column + 1) * cellWidth,
        bottom: cellHeight,
      );
      if (ink == null) {
        return null;
      }
      final origin = originOf(column, row);
      final want = (
        left: origin.dx + box.left * unit,
        top: origin.dy + box.top * unit,
        right: origin.dx + box.right * unit,
        bottom: origin.dy + box.bottom * unit,
      );
      worst = (
        centreX: math.max(
          worst.centreX,
          ((ink.left + ink.right) / 2 - (want.left + want.right) / 2).abs(),
        ),
        centreY: math.max(
          worst.centreY,
          ((ink.top + ink.bottom) / 2 - (want.top + want.bottom) / 2).abs(),
        ),
        width: math.max(
          worst.width,
          ((ink.right - ink.left) - (want.right - want.left)).abs(),
        ),
        height: math.max(
          worst.height,
          ((ink.bottom - ink.top) - (want.bottom - want.top)).abs(),
        ),
        edge: [
          worst.edge,
          (ink.left - want.left).abs(),
          (ink.top - want.top).abs(),
          (ink.right - want.right).abs(),
          (ink.bottom - want.bottom).abs(),
        ].reduce(math.max),
      );
    }
  }
  return worst;
}

/// Device pixels a rasteriser may put a glyph's ink from the table's box at
/// a size the view draws at: its centre vertically, and its width or its
/// height.
typedef RasterBounds = ({double centreY, double size});

/// The bounds where Apple's rasteriser draws, measured on a Mac and on an
/// iPhone.
///
/// Ink lands on whole pixels vertically, which is the pixel of the centre.
/// The size may be off by a pixel at each edge. The Mac thickens ink and
/// the phone thins it, and a thin or pointed end reads short on top of
/// that, so a glyph that is drawn right is up to 1.55 pixels small on a
/// phone.
const RasterBounds appleBounds = (centreY: 1, size: 2);

/// The bounds where FreeType draws, which is Linux and Android, measured on
/// Linux alone.
///
/// The notes, the clefs, the rests and the accidentals read as on a Mac.
/// The letters of the dynamics, the digits and the octave parentheses read
/// up to 1.17 pixels off their centre, and the parentheses up to 2.5
/// pixels short at the smallest size. Each bound is Apple's with half a
/// pixel more at each edge.
const RasterBounds freeTypeBounds = (centreY: 1.5, size: 3);

/// The bounds of the rasteriser this test runs on. Nothing has measured
/// Windows, which is held to Apple's until something does.
RasterBounds get rasterBounds =>
    Platform.isLinux || Platform.isAndroid ? freeTypeBounds : appleBounds;

/// Why [errors] fails the gate at a size the view draws at. Empty when it
/// passes.
///
/// Placement and size are judged apart. A rasteriser thickens ink by a
/// fraction of a pixel on every side, which moves edges and leaves the
/// centre. So the centre says where the glyph is and the size says what the
/// rasteriser did to it. Both are held to [rasterBounds].
///
/// Glyphs are placed to a fraction of a pixel horizontally on every
/// platform, so that bound is the reader's own. A pointed end covers little
/// of its last pixel and reads short, which moves the centre of a glyph
/// pointed on one side by up to a third of a pixel at every size.
List<String> failuresAtViewSize(InkErrors errors) {
  final bounds = rasterBounds;
  return [
    if (errors.centreY > bounds.centreY)
      'centre ${errors.centreY.toStringAsFixed(2)} px off vertically',
    if (errors.centreX > 0.5)
      'centre ${errors.centreX.toStringAsFixed(2)} px off horizontally',
    if (errors.width > bounds.size)
      'width ${errors.width.toStringAsFixed(2)} px off',
    if (errors.height > bounds.size)
      'height ${errors.height.toStringAsFixed(2)} px off',
  ];
}

/// Why [errors] fails the gate at [tableSize], where every edge is within
/// 0.05 staff spaces. Empty when it passes.
List<String> failuresAtTableSize(InkErrors errors) {
  final spaces = errors.edge / (tableSize.spacePx * tableSize.pixelRatio);
  return [
    if (spaces > 0.05) 'an edge ${spaces.toStringAsFixed(3)} staff spaces off',
  ];
}

/// A painter for the bundled font.
GlyphPainter bravuraPainter() => GlyphPainter(SmuflFont.bravura);

/// Why a notehead drawn through [painter] fails the gate. Empty when it
/// passes.
///
/// A font that did not load still draws ink, the fallback font's box for a
/// missing character, so counting ink does not prove the font. That box is
/// not the size of a notehead.
Future<List<String>> noteheadFailures(GlyphPainter painter) async {
  final errors = await measureGlyph(
    painter,
    Glyph.noteheadBlack,
    spacePx: 16,
    pixelRatio: 1,
  );
  return errors == null ? ['no ink'] : failuresAtViewSize(errors);
}

/// Runs the whole gate through [painter], whose font must already be
/// loaded, and returns why it fails. Empty when it passes.
///
/// [report] gets one line per size with the worst errors found there.
Future<List<String>> glyphGateFailures(
  GlyphPainter painter, {
  required void Function(String line) report,
}) async {
  final failures = <String>[];
  for (final size in [...viewSizes, tableSize]) {
    var worst = (
      centreX: 0.0,
      centreY: 0.0,
      width: 0.0,
      height: 0.0,
      edge: 0.0,
    );
    for (final glyph in Glyph.values) {
      final errors = await measureGlyph(
        painter,
        glyph,
        spacePx: size.spacePx,
        pixelRatio: size.pixelRatio,
      );
      final where =
          '${glyph.name} at ${size.spacePx} px per staff space, '
          'ratio ${size.pixelRatio}';
      if (errors == null) {
        failures.add('$where: no ink');
        continue;
      }
      final found = size == tableSize
          ? failuresAtTableSize(errors)
          : failuresAtViewSize(errors);
      failures.addAll([for (final failure in found) '$where: $failure']);
      worst = (
        centreX: math.max(worst.centreX, errors.centreX),
        centreY: math.max(worst.centreY, errors.centreY),
        width: math.max(worst.width, errors.width),
        height: math.max(worst.height, errors.height),
        edge: math.max(worst.edge, errors.edge),
      );
    }
    report(
      'gate 1: ${size.spacePx} px per staff space, ratio '
      '${size.pixelRatio}: worst centre '
      '${worst.centreX.toStringAsFixed(2)} x '
      '${worst.centreY.toStringAsFixed(2)} y, size '
      '${worst.width.toStringAsFixed(2)} w '
      '${worst.height.toStringAsFixed(2)} h, edge '
      '${worst.edge.toStringAsFixed(2)} device px',
    );
  }
  return failures;
}
