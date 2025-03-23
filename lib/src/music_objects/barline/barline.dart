import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/mixin/debug_render_mixin.dart';
import 'package:simple_sheet_music/src/music_objects/barline/barline_type.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// This class is not used in the library. It was implemented for future reference.
class Barline extends MusicalSymbol {
  Barline.single({
    super.color,
    super.margin,
  }) : barlineType = BarlineType.single;

  Barline.double({
    super.color,
    super.margin,
  }) : barlineType = BarlineType.double;

  /// The type of the barline.
  final BarlineType barlineType;

  @override
  double get duration => 0;

  @override
  MusicalSymbolMetrics setContext(
    MusicalContext context,
    GlyphMetadata metadata,
    GlyphPaths paths,
  ) =>
      BarlineMetrics(this, paths);
}

class BarlineMetrics implements MusicalSymbolMetrics {
  const BarlineMetrics(
    this.barline,
    this.paths,
  );
  final Barline barline;
  final GlyphPaths paths;

  Rect get bbox => Rect.fromLTWH(0, upperHeight, width, lowerHeight);

  Color get color => barline.color;

  @override
  double get width {
    switch (barline.barlineType) {
      case BarlineType.single:
        return 2;
      case BarlineType.double:
      case BarlineType.finalEnd:
        return 6;
    }
  }

  /// top line of the staff is 2 lines above the center line. Therefore multiplying staffSpace by -2.
  @override
  double get upperHeight => -2 * Constants.staffSpace;

  /// bottom line of the staff is 2 lines below the center line. Therefore multiplying staffSpace by 2.
  @override
  double get lowerHeight => 2 * Constants.staffSpace;

  @override
  EdgeInsets get margin => barline.margin;

  @override
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  }) {
    return BarlineRenderer(
      this,
      layout,
      staffLineCenterY: staffLineCenterY,
      symbolX: symbolX,
      musicalSymbol: barline,
    );
  }
}

class BarlineRenderer with DebugRenderMixin implements MusicalSymbolRenderer {
  const BarlineRenderer(
    this.barline,
    this.layout, {
    required this.staffLineCenterY,
    required this.symbolX,
    required this.musicalSymbol,
  });

  final BarlineMetrics barline;
  final SheetMusicLayout layout;
  final double staffLineCenterY;
  final double symbolX;

  @override
  final MusicalSymbol musicalSymbol;

  Offset get renderOffset => Offset(symbolX, staffLineCenterY) + marginOffset;

  Offset get marginOffset =>
      Offset(barline.margin.left, 0) / layout.canvasScale;

  Rect get renderArea => barline.bbox.shift(renderOffset);

  double get startY => staffLineCenterY - barline.upperHeight;
  double get endY => staffLineCenterY + barline.lowerHeight;

  @override
  bool isHit(Offset position) => renderArea.contains(position);

  @override
  Rect getBounds() => renderArea;

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = barline.color
      ..strokeWidth = barline.width;

    switch (barline.barline.barlineType) {
      case BarlineType.single:
        canvas.drawLine(Offset(symbolX, startY), Offset(symbolX, endY), paint);
        break;

      case BarlineType.double:
        canvas.drawLine(
          Offset(symbolX - 3, startY),
          Offset(symbolX - 3, endY),
          paint,
        );
        canvas.drawLine(
          Offset(symbolX + 3, startY),
          Offset(symbolX + 3, endY),
          paint,
        );
        break;

      case BarlineType.finalEnd:
        final thickPaint = Paint()
          ..color = barline.color
          ..strokeWidth = 5.0;
        canvas.drawLine(
          Offset(symbolX - 4, startY),
          Offset(symbolX - 4, endY),
          paint,
        );
        canvas.drawLine(
          Offset(symbolX + 4, startY),
          Offset(symbolX + 4, endY),
          thickPaint,
        );
        break;
    }

    if (layout.debug) {
      renderBoundingBox(canvas, renderArea);
    }
  }
}
