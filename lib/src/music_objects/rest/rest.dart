import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/mixin/debug_render_mixin.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest_type.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// Represents a rest in sheet music.
class Rest extends MusicalSymbol {
  Rest(
    this.restType, {
    super.color,
    super.margin,
  });

  final RestType restType;

  @override
  double get duration => restType.duration;

  @override
  MusicalSymbolMetrics setContext(
    MusicalContext context,
    GlyphMetadata metadata,
    GlyphPaths paths,
  ) =>
      RestMetrics(
        this,
        context,
        metadata,
        paths,
      );
}

/// Represents the metrics of a rest in sheet music.
class RestMetrics implements MusicalSymbolMetrics {
  const RestMetrics(
    this.rest,
    this.context,
    this.metadata,
    this.paths,
  );

  final MusicalContext context;
  final GlyphMetadata metadata;
  final GlyphPaths paths;
  final Rest rest;

  RestType get restType => rest.restType;

  Offset get defaultOffset =>
      Offset(0, -1 * restType.offsetSpace * Constants.staffSpace);

  Path get path => paths.parsePath(rest.restType.pathKey).shift(defaultOffset);
  Rect get bbox => path.getBounds();

  @override
  double get lowerHeight => bbox.bottom;

  double get leftMargin => rest.margin.left;

  @override
  double get upperHeight => -bbox.top;

  @override
  double get width => bbox.width;

  @override
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  }) =>
      RestRenderer(
        this,
        layout,
        staffLineCenterY: staffLineCenterY,
        symbolX: symbolX,
        musicalSymbol: rest,
      );

  @override
  EdgeInsets get margin => rest.margin;
}

/// Renders a rest in sheet music.
class RestRenderer with DebugRenderMixin implements MusicalSymbolRenderer {
  const RestRenderer(
    this.restMetrics,
    this.layout, {
    required this.staffLineCenterY,
    required this.symbolX,
    required this.musicalSymbol,
  });

  final double staffLineCenterY;
  final double symbolX;
  final RestMetrics restMetrics;
  final SheetMusicLayout layout;

  @override
  final MusicalSymbol musicalSymbol;

  Offset get renderOffset => Offset(symbolX, staffLineCenterY) + marginOffset;
  Offset get marginOffset =>
      Offset(restMetrics.leftMargin, 0) / layout.canvasScale;

  @override
  bool isHit(Offset position) {
    return renderArea.contains(position);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPath(renderPath, Paint()..color = restMetrics.rest.color);

    if (layout.debug) {
      renderBoundingBox(canvas, renderArea);
    }
  }

  @override
  Rect getBounds() => renderArea;

  Path get renderPath => restMetrics.path.shift(renderOffset);

  Rect get renderArea => renderPath.getBounds();
}
