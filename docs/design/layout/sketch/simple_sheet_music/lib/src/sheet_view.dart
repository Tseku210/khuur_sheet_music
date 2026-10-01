import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';

import 'painting.dart';
import 'paragraph_measurer.dart';
import 'score_player.dart';
import 'sheet_palette.dart';

/// A score as a vertical, scrolling stack of systems at a fixed staff size.
///
/// Replaces `SimpleSheetMusic`. It takes immutable values and lays out on
/// its own. Give it the next `Score` after an edit and it lays out only the
/// bars the edit touched, breaks lines again only where widths changed, and
/// repaints only the systems that changed. The cursor, the selection, tints
/// and playback repaint an overlay layer and never lay out.
///
/// Its width comes from its constraints, its height is unbounded (it
/// scrolls), and its size on screen is [staffSpace] times the controller's
/// zoom. It never scales a score to fit a box.
class SheetView extends StatefulWidget {
  const SheetView({
    required this.score,
    this.cursor,
    this.selection = const NoSelection(),
    this.tints = const {},
    this.playback,
    this.onTap,
    this.controller,
    this.style = EngravingStyle.standard,
    this.palette,
    this.staffSpace = 8,
    this.tapGrid = DurationBase.sixteenth,
    this.followCursor = true,
    this.followPlayback = true,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Score score;

  /// The edit cursor, drawn as a caret. Usually `EditSession.cursor`.
  final VoicePoint? cursor;

  /// Usually `EditSession.selection`.
  final Selection selection;

  /// Colours for particular notes or events, drawn over the sheet, such as
  /// practice feedback or search results. Replaces the old per-symbol colour.
  final Map<ElementRef, Color> tints;

  /// Usually `ScorePlayer.position`. The sheet highlights the sounding
  /// events and draws a playhead.
  final ValueListenable<PlaybackPosition?>? playback;

  /// Called with what a tap means. Not called for a tap outside every
  /// system.
  final ValueChanged<SheetHit>? onTap;

  final SheetController? controller;

  /// What changes layout. A style that is not equal to the previous one
  /// lays the whole score out again.
  final EngravingStyle style;

  /// Colours. Null derives them from the ambient theme.
  final SheetPalette? palette;

  /// Logical pixels per staff space at zoom 1.
  final double staffSpace;

  /// The grid a tap snaps to when it is not on a note. Inside a tuplet the
  /// grid counts in the tuplet's written time. Its type keeps it from being
  /// finer than a 128th, the finest start the model accepts.
  final DurationBase tapGrid;

  /// Scroll the cursor into view when it moves.
  final bool followCursor;

  /// Scroll the playhead into view while playing.
  final bool followPlayback;

  final EdgeInsets padding;

  @override
  State<SheetView> createState() => _SheetViewState();
}

/// Zoom, geometry queries and export for one [SheetView].
///
/// Geometry is in the SheetView's local logical pixels and accounts for
/// scrolling, so an app can position its own widgets over the sheet (a
/// loupe, a delete badge, a popup) in a `Stack`. It notifies when scrolling,
/// zoom or layout move the geometry.
///
/// The view itself listens only to the zoom. A scroll or a new layout
/// notifies the app's listeners and builds nothing in the view.
class SheetController extends ChangeNotifier {
  SheetController({double zoom = 1}) : _zoom = ValueNotifier(zoom);

  final ValueNotifier<double> _zoom;
  _SheetViewState? _view;

  /// Multiplies `SheetView.staffSpace`. A new zoom breaks lines again at
  /// the next frame and keeps the bar at the top of the viewport in place.
  /// Every set is a full break over cached bars, so an app that zooms by
  /// pinch sets it when the gesture ends.
  double get zoom => _zoom.value;
  set zoom(double value) {
    if (value == _zoom.value) {
      return;
    }
    _zoom.value = value;
    notifyListeners();
  }

  void _moved() => notifyListeners();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// What a tap at [local] would mean, snapped for entry in [voice].
  SheetHit? hitTest(Offset local, {VoiceSlot voice = VoiceSlot.one}) =>
      switch (_view) {
        final view? => view._layout?.hitTest(
          view._viewport.toSheet(local),
          voice: voice,
          grid: view.widget.tapGrid,
          reach: kTouchSlop / view._spacePx,
        ),
        null => null,
      };

  /// Where [ref] is drawn, or null when it is not drawn (a hidden staff).
  Rect? rectOf(ElementRef ref) => throw UnimplementedError();

  Rect? caretOf(VoicePoint cursor) => throw UnimplementedError();

  /// The rects the view shades for [selection].
  List<Rect> rectsOf(Selection selection) => throw UnimplementedError();

  /// Scrolls until the system holding [point] is in view.
  Future<void> ensureVisible(
    ScorePoint point, {
    Duration duration = const Duration(milliseconds: 250),
  }) => throw UnimplementedError();

  /// Systems [from] up to [to] as one image, without the overlay, at
  /// [pixelRatio]. The header is included when [from] is 0. It draws the
  /// same drawables the view paints and assembles the systems it covers.
  ///
  /// One image holds only so many pixels. A range taller than
  /// [maxImageHeight] device pixels throws an [ArgumentError], so an app
  /// exports a long score as several images.
  Future<ui.Image> toImage({int from = 0, int? to, double pixelRatio = 1}) =>
      throw UnimplementedError();

  /// The tallest image [toImage] makes, in device pixels. It is under the
  /// texture limit of the devices the package targets.
  static const int maxImageHeight = 8192;

  /// How many systems the sheet has, for an app that exports in ranges.
  int get systemCount => _view?._layout?.systemCount ?? 0;
}

/// The bar the view keeps in place across an update, and where the top of
/// its system sits in the scrolled content, in logical pixels. With the
/// scroll offset that is the system's offset from the top of the viewport.
typedef _ScrollAnchor = ({MeasureId bar, double top});

class _SheetViewState extends State<SheetView> {
  ParagraphMeasurer _measurer = ParagraphMeasurer();
  final ScrollController _scroll = ScrollController();
  late GlyphPainter _glyphs = GlyphPainter(widget.style.font);
  SheetController? _ownController;

  /// The layout on screen, and the pixels per staff space it was shown at.
  SheetLayout? _layout;
  double _shownSpacePx = 0;

  /// Set when [_layout] cannot be updated and a fresh one must replace it:
  /// the style changed, or a text font loaded late.
  bool _stale = false;

  SheetController get _controller =>
      widget.controller ?? (_ownController ??= SheetController());

  double get _spacePx => widget.staffSpace * _controller.zoom;

  /// Sheet space to this widget's local pixels, scroll included.
  SheetScale get _viewport => SheetScale(
    spacePx: _spacePx,
    origin: Offset(
      widget.padding.left,
      widget.padding.top - (_scroll.hasClients ? _scroll.offset : 0),
    ),
  );

  @override
  void initState() {
    super.initState();
    _controller._view = this;
    _controller._zoom.addListener(_rebuild);
    _scroll.addListener(_controller._moved);
    widget.playback?.addListener(_followPlayback);
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
  }

  @override
  void didUpdateWidget(SheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // TODO:
    // - Swap the controller's listeners when the controller changes.
    // - followCursor and a moved cursor: ensureVisible after this frame.
    // A new score needs nothing here. build() calls update(), which returns
    // the same layout when the score is identical.
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback?.removeListener(_followPlayback);
      widget.playback?.addListener(_followPlayback);
    }
    if (oldWidget.style != widget.style) {
      _stale = true;
      _glyphs = GlyphPainter(widget.style.font);
    }
  }

  void _rebuild() => setState(() {});

  /// Whether a font registration is waiting for [_afterFontsChanged].
  bool _fontsChanged = false;

  /// Flutter reports every font registered at run time here, a `FontLoader`
  /// load included, whoever loaded it. A burst of registrations is handled
  /// once, after the frame.
  void _onFontsChanged() {
    if (_fontsChanged) {
      return;
    }
    _fontsChanged = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fontsChanged = false;
      if (mounted) {
        _afterFontsChanged();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// A font may have finished loading after the sheet measured text or drew
  /// a glyph with a fallback.
  ///
  /// A fresh measurer measures again every text the old one was asked
  /// for. When an extent differs, nothing laid out before can be trusted,
  /// and the fresh measurer and a fresh layout replace the old ones. The
  /// engine is not told. Its measurer stays pure for its lifetime because
  /// the old one is thrown away. When no extent differs, the font was not
  /// one the sheet's text uses and the layout stays.
  ///
  /// The glyph painter is replaced either way, because a SMuFL font an app
  /// loads itself can arrive late too. A new painter repaints the systems
  /// on screen and lays nothing out.
  void _afterFontsChanged() => setState(() {
    final fresh = ParagraphMeasurer();
    if (!fresh.agreesWith(_measurer)) {
      _measurer = fresh;
      _stale = true;
    }
    _glyphs = GlyphPainter(widget.style.font);
  });

  /// Keeps the playhead's system in view. It never calls setState. The
  /// overlay painters listen to the same listenable and repaint on their
  /// own.
  void _followPlayback() {
    // TODO: with followPlayback, when the system of the playhead's bar
    // (layout.systemOf(position.point.bar.measure)) is outside the
    // viewport, animate the scroll so its top sits at the viewport's top.
  }

  /// The bar to keep in place across the next update, read from the layout
  /// on screen. Null before the first frame.
  ///
  /// With [SheetView.followCursor] it is the cursor's bar, when any part of
  /// that bar's system is in the viewport. Otherwise it is the first bar of
  /// the system at the top of the viewport. A cursor the user scrolled away
  /// from is no anchor, because keeping it still would move what they are
  /// reading.
  _ScrollAnchor? _anchorIn(SheetLayout layout, double spacePx) {
    if (!_scroll.hasClients) {
      return null;
    }
    final viewportTop = _scroll.offset - widget.padding.top;
    final viewportBottom = viewportTop + _scroll.position.viewportDimension;
    final cursor = widget.followCursor ? widget.cursor?.at.measure : null;
    final cursorSystem = cursor == null ? null : layout.systemOf(cursor);
    if (cursor != null && cursorSystem != null) {
      final top = layout.tops[cursorSystem] * spacePx;
      final bottom = top + layout.heightOf(cursorSystem) * spacePx;
      if (top < viewportBottom && bottom > viewportTop) {
        return (bar: cursor, top: top);
      }
    }
    final atTop = layout.tops.lastIndexWhere(
      (top) => top * spacePx <= viewportTop,
    );
    final index = atTop < 0 ? 0 : atTop;
    return (bar: layout.firstBarOf(index), top: layout.tops[index] * spacePx);
  }

  /// Scrolls so the system holding the anchor's bar sits as far below the
  /// viewport's top as it did before the update.
  ///
  /// This runs after every update. It moves the scroll only when the
  /// anchor's system moved in the content, which happens when lines were
  /// broken again (`delta.rebroke`, a zoom or a resize included) or a
  /// system above it changed height. The scroll moves by as much as the
  /// system did. A bar that was deleted leaves the scroll alone.
  ///
  /// It runs inside the LayoutBuilder callback, before the viewport lays
  /// out. `correctBy` moves the offset without notifying, so no listener
  /// rebuilds during layout and the frame paints at the corrected offset.
  /// The viewport clamps an offset past the new end by itself.
  ///
  /// The correction holds while the scroll is idle, dragged or flung. A
  /// scroll the view itself is animating writes its own offsets on the next
  /// tick and would undo it. So the view remembers the bar such a scroll is
  /// going to ([_scrollingTo]) and, after a correction, starts it again
  /// towards where that bar is now.
  void _keepInPlace(_ScrollAnchor? anchor, SheetLayout layout, double spacePx) {
    final index = anchor == null ? null : layout.systemOf(anchor.bar);
    if (anchor == null || index == null) {
      return;
    }
    final moved = layout.tops[index] * spacePx - anchor.top;
    if (moved != 0) {
      _scroll.position.correctBy(moved);
      // TODO: when _scrollingTo is set, animate again to its system's top
      // in the new layout, after this frame.
    }
  }

  /// The bar an animated scroll of the view's own is going to, which is the
  /// target of `ensureVisible` or of following playback. Null when no such
  /// scroll is running.
  // The sketch declares it. ensureVisible and _followPlayback set it and
  // clear it when their scroll ends.
  // ignore: unused_field
  MeasureId? _scrollingTo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final spacePx = _spacePx;
      final width =
          (constraints.maxWidth - widget.padding.horizontal) / spacePx;
      final previous = _layout;
      final anchor = previous == null
          ? null
          : _anchorIn(previous, _shownSpacePx);
      final layout = previous == null || _stale
          ? SheetLayout(
              widget.score,
              width: width,
              text: _measurer,
              style: widget.style,
            )
          : previous.update(widget.score, width: width);
      _keepInPlace(anchor, layout, spacePx);
      _stale = false;
      _shownSpacePx = spacePx;
      if (!identical(layout, previous)) {
        _layout = layout;
        // The controller's listeners may rebuild, which a layout pass does
        // not allow. They hear of the new geometry after this frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _controller._moved();
          }
        });
      }
      final palette = widget.palette ?? SheetPalette.of(context);
      final scale = SheetScale(spacePx: spacePx);
      return GestureDetector(
        onTapUp: (details) {
          final hit = _controller.hitTest(
            details.localPosition,
            voice: widget.cursor?.voice ?? VoiceSlot.one,
          );
          if (hit != null) {
            widget.onTap?.call(hit);
          }
        },
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: widget.padding,
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: layout.tops.first * spacePx,
                      child: CustomPaint(
                        painter: HeaderPainter(
                          header: layout.header,
                          glyphs: _glyphs,
                          palette: palette,
                          scale: scale,
                        ),
                      ),
                    ),
                  ),
                  SliverVariedExtentList(
                    itemExtentBuilder: (index, _) =>
                        _extentOf(layout, index) * spacePx,
                    // Only a system scrolled into view is asked for, so
                    // only those are assembled.
                    delegate: _SystemTiles(
                      (context, index) => Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: SystemPainter(
                                system: layout.systemAt(index),
                                label: layout.labelOf(index),
                                glyphs: _glyphs,
                                palette: palette,
                                scale: scale,
                              ),
                            ),
                          ),
                          CustomPaint(
                            painter: OverlayPainter(
                              layout: layout,
                              index: index,
                              cursor: widget.cursor,
                              selection: widget.selection,
                              tints: widget.tints,
                              playback: widget.playback,
                              glyphs: _glyphs,
                              palette: palette,
                              scale: scale,
                            ),
                          ),
                        ],
                      ),
                      childCount: layout.systemCount,
                      extent: (layout.height - layout.tops.first) * spacePx,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  /// The height of a system's tile in staff spaces, which is its planned height
  /// and the gap to the next system. Known without assembling the system.
  double _extentOf(SheetLayout layout, int index) =>
      (index + 1 < layout.systemCount
          ? layout.tops[index + 1]
          : layout.height) -
      layout.tops[index];

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    widget.playback?.removeListener(_followPlayback);
    _controller._zoom.removeListener(_rebuild);
    _controller._view = null;
    _ownController?.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

/// The system tiles, with the height of all of them.
///
/// A sliver list guesses its scroll extent from the tiles it has laid out,
/// even when every tile's extent is known. A probe showed a list of ten
/// short and ninety tall tiles reporting a third of its true extent at the
/// top. The layout knows the sum, so the delegate reports it, and the
/// scroll bar and a scroll to the end are exact from the first frame.
final class _SystemTiles extends SliverChildBuilderDelegate {
  _SystemTiles(
    super.builder, {
    required super.childCount,
    required this.extent,
  });

  /// The height of all tiles together, in logical pixels.
  final double extent;

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => extent;
}
