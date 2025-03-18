import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/measure/measure_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// The renderer for a measure in sheet music.
class MeasureRenderer {
  const MeasureRenderer(
    this.symbolRenderers,
    this.measureMetrics,
    this.layout, {
    required this.measureOriginX,
    required this.staffLineCenterY,
  });

  final List<MusicalSymbolRenderer> symbolRenderers;
  final MeasureMetrics measureMetrics;
  final double measureOriginX;
  final double staffLineCenterY;

  /// Performs a hit test at the given [position] and returns the corresponding [MusicalSymbolRenderer].
  ///
  /// Returns `null` if no symbol is hit.
  MusicalSymbolRenderer? hitTest(Offset position) {
    for (final object in symbolRenderers) {
      if (object.isHit(position)) {
        return object;
      }
    }
    return null;
  }

  /// Renders the measure on the given [canvas] with the specified [size].
  void render(Canvas canvas, Size size) {
    _renderStaffLine(canvas);

    for (final symbol in symbolRenderers) {
      symbol.render(canvas);
    }

    _renderBarline(canvas);
  }

  void _renderStaffLine(Canvas canvas) {
    final initX = measureOriginX + _barlineSpacing;
    final staffLineHeights = [
      staffLineCenterY - Constants.staffSpace * 2,
      staffLineCenterY - Constants.staffSpace,
      staffLineCenterY,
      staffLineCenterY + Constants.staffSpace,
      staffLineCenterY + Constants.staffSpace * 2,
    ];
    for (final height in staffLineHeights) {
      canvas.drawLine(
        Offset(initX, height),
        Offset(initX + width, height),
        Paint()
          ..color = layout.lineColor
          ..strokeWidth = measureMetrics.staffLineThickness,
      );
    }
  }

  void _renderBarline(Canvas canvas) {
    final barlineX = measureOriginX + width + _barlineSpacing;

    final paint = Paint()
      ..color = layout.lineColor
      ..strokeWidth = measureMetrics.staffLineThickness;

    if (measureMetrics.isLastMeasure) {
      _drawFinalBarline(canvas, barlineX);
    } else if (!measureMetrics.isNewLine) {
      // Single barline between measures
      canvas.drawLine(
        Offset(barlineX, _barlineStartY),
        Offset(barlineX, _barlineEndY),
        paint,
      );
    }
  }

  /// Draws the final barline with a thick and thin line.
  void _drawFinalBarline(Canvas canvas, double barlineX) {
    final thickPaint = Paint()
      ..color = layout.lineColor
      ..strokeWidth = measureMetrics.staffLineThickness * 3;

    // Calculate spacing dynamically
    final thinBarX = barlineX - measureMetrics.staffLineThickness * 4;
    final thickBarX = barlineX - measureMetrics.staffLineThickness * 1.5;

    // Thin line (left)
    canvas
      ..drawLine(
        Offset(thinBarX, _barlineStartY),
        Offset(thinBarX, _barlineEndY),
        Paint()
          ..color = layout.lineColor
          ..strokeWidth = measureMetrics.staffLineThickness,
      )
      // Thick line (right)
      ..drawLine(
        Offset(thickBarX, _barlineStartY),
        Offset(thickBarX, _barlineEndY),
        thickPaint,
      );
  }

  /// Dynamic spacing for barline padding
  double get _barlineSpacing =>
      measureMetrics.isLastMeasure ? measureMetrics.staffLineThickness * 3 : 0;

  /// Dynamic start and end Y positions for barlines
  double get _barlineStartY => staffLineCenterY - 2 * Constants.staffSpace;
  double get _barlineEndY => staffLineCenterY + 2 * Constants.staffSpace;

  final SheetMusicLayout layout;

  /// The width of the measure.
  double get width =>
      measureMetrics.objectsWidth + measureMetrics.horizontalMarginSum / scale;

  /// The scale of the measure.
  double get scale => layout.canvasScale;
}
