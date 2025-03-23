import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/measure/measure_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// The renderer for a staff, which is responsible for rendering measures and handling hit tests.
class StaffRenderer {
  const StaffRenderer(
    this.measureRendereres, {
    this.symbolPositionCallback,
  });

  final List<MeasureRenderer> measureRendereres;

  /// Callback to register the position of a symbol
  final SymbolPositionCallback? symbolPositionCallback;

  /// Performs a hit test at the given position on the staff.
  ///
  /// Returns the [MusicalSymbolRenderer] that was hit, or `null` if no object was hit.
  MusicalSymbolRenderer? hitTest(Offset position) {
    for (final measure in measureRendereres) {
      final hit = measure.hitTest(position);
      if (hit != null) {
        return hit;
      }
    }
    return null;
  }

  /// Renders the staff on the given canvas with the specified size and font family.
  void render(Canvas canvas, Size size) {
    for (var i = 0; i < measureRendereres.length; i++) {
      measureRendereres[i]
        // Pass the symbol position callback
        ..symbolPositionCallback = symbolPositionCallback
        ..render(canvas, size);
    }
  }
}
