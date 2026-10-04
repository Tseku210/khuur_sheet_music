import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:simple_sheet_music/src/painting.dart';
import 'package:simple_sheet_music/src/paragraph_measurer.dart';
import 'package:simple_sheet_music/src/score_player.dart';
import 'package:simple_sheet_music/src/sheet_palette.dart';

/// A score as a vertical, scrolling stack of systems at a fixed staff size.
///
/// It takes immutable values and lays out on its own. Give it the next
/// `Score` after an edit and it lays out only the bars the edit touched,
/// breaks lines again only where widths changed, and repaints only the
/// systems that changed. The cursor, the selection, tints and playback
/// repaint an overlay layer and never lay out.
///
/// Its width comes from its constraints, which must bound it. Its height is
/// unbounded, since it scrolls. Its size on screen is [staffSpace] times
/// the controller's zoom. It never scales a score to fit a box.
///
/// An update keeps the bar the user is reading where it is. With
/// [followCursor] that is the cursor's bar while its system is in view, and
/// otherwise the first bar of the first system in view.
///
/// Each system is one node for a screen reader, labelled with the bars it
/// holds.
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

  /// Usually `EditSession.selection`. The overlay repaints for a selection
  /// that is another object.
  final Selection selection;

  /// Colours for particular notes or events, drawn over the sheet, such as
  /// practice feedback or search results. The overlay repaints for a map
  /// that is another object.
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

  /// Scroll the cursor's system into view when the cursor moves.
  final bool followCursor;

  /// While playing, scroll a system to the top of the view when the
  /// playhead enters it and it is not wholly in view.
  final bool followPlayback;

  /// Room around the sheet, which scrolls with it.
  final EdgeInsets padding;

  @override
  State<SheetView> createState() => _SheetViewState();
}

/// Zoom, geometry queries and export for one [SheetView].
///
/// Geometry is in the view's local logical pixels and accounts for
/// scrolling, so an app can position its own widgets over the sheet (a
/// loupe, a delete badge, a popup) in a `Stack`. It notifies when
/// scrolling, zoom or layout move the geometry.
///
/// The view itself listens only to the zoom. A scroll or a new layout
/// notifies the app's listeners and builds nothing in the view.
///
/// A controller serves the view that took it last. Every query answers
/// null, nothing or zero while no view has the controller, and before that
/// view's first frame.
class SheetController extends ChangeNotifier {
  /// Throws an [ArgumentError] unless [zoom] is positive and finite.
  SheetController({double zoom = 1}) : _zoom = ValueNotifier(_checked(zoom));

  final ValueNotifier<double> _zoom;
  _SheetViewState? _view;

  static double _checked(double zoom) {
    if (!(zoom > 0 && zoom.isFinite)) {
      throw ArgumentError.value(zoom, 'zoom', 'Must be positive and finite');
    }
    return zoom;
  }

  /// Multiplies `SheetView.staffSpace`. A new zoom breaks lines again at
  /// the next frame and keeps the bar the user is reading in place. Every
  /// set is a full break over cached bars, so an app that zooms by pinch
  /// sets it when the gesture ends.
  ///
  /// Throws an [ArgumentError] unless the value is positive and finite.
  double get zoom => _zoom.value;
  set zoom(double value) {
    if (_checked(value) == _zoom.value) {
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
  Rect? rectOf(ElementRef ref) => _rectOf(_view?._layout?.boundsOf(ref));

  /// The caret for [cursor], a rect of no width over the cursor's staff.
  Rect? caretOf(VoicePoint cursor) => _rectOf(_view?._layout?.caretOf(cursor));

  /// The rects the view shades for [selection].
  List<Rect> rectsOf(Selection selection) => [
        for (final box
            in _view?._layout?.selectionBoxes(selection) ?? const <Box>[])
          _view!._viewport.rectOf(box),
      ];

  Rect? _rectOf(Box? box) => box == null ? null : _view!._viewport.rectOf(box);

  /// Scrolls until the system holding [point] is wholly in view, by the
  /// shortest way. A system taller than the view shows its top. The future
  /// completes when the scroll ends or the user takes over.
  Future<void> ensureVisible(
    ScorePoint point, {
    Duration duration = const Duration(milliseconds: 250),
  }) =>
      _view?._scrollTo(point.measure, toTop: false, duration: duration) ??
      Future.value();

  /// Systems [from] up to [to] as one image, without the overlay and
  /// without the view's padding, on a transparent background, at
  /// [pixelRatio]. [to] is the system count when null. The header is
  /// included when [from] is 0. It draws the drawables the view paints, in
  /// the view's palette and at its size, and assembles the systems it
  /// covers.
  ///
  /// One image holds only so many pixels. A range taller than
  /// [maxImageHeight] device pixels throws an [ArgumentError], so an app
  /// exports a long score as several images. So does an empty range, and a
  /// range outside the sheet throws a [RangeError]. A controller without a
  /// laid-out view throws a [StateError].
  Future<ui.Image> toImage({int from = 0, int? to, double pixelRatio = 1}) {
    final view = _view;
    final layout = view?._layout;
    if (view == null || layout == null) {
      throw StateError('No SheetView has laid out a sheet for this controller');
    }
    final end = RangeError.checkValidRange(from, to, layout.systemCount);
    if (end == from) {
      throw ArgumentError.value(to, 'to', 'The range holds no system');
    }
    if (!(pixelRatio > 0 && pixelRatio.isFinite)) {
      throw ArgumentError.value(
        pixelRatio,
        'pixelRatio',
        'Must be positive and finite',
      );
    }
    final spacePx = view._spacePx;
    final top = from == 0 ? 0.0 : layout.tops[from];
    final bottom = layout.tops[end - 1] + layout.heightOf(end - 1);
    final height = ((bottom - top) * spacePx * pixelRatio).ceil();
    if (height > maxImageHeight) {
      throw ArgumentError(
        'Systems $from to $end are $height device pixels high, over the '
        '$maxImageHeight one image holds. Export fewer systems at a time.',
      );
    }
    final palette = view._palette;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    SheetScale below(double y) =>
        SheetScale(spacePx: spacePx, origin: Offset(0, (y - top) * spacePx));
    if (from == 0) {
      HeaderPainter(
        header: layout.header,
        glyphs: view._glyphs,
        palette: palette,
        scale: below(0),
      ).paint(canvas, Size.zero);
    }
    for (var index = from; index < end; index++) {
      SystemPainter(
        system: layout.systemAt(index),
        label: layout.labelOf(index),
        glyphs: view._glyphs,
        palette: palette,
        scale: below(layout.tops[index]),
      ).paint(canvas, Size.zero);
    }
    final picture = recorder.endRecording();
    return picture
        .toImage((layout.width * spacePx * pixelRatio).ceil(), height)
        .whenComplete(picture.dispose);
  }

  /// The tallest image [toImage] makes, in device pixels. It is under the
  /// texture limit of the devices the package targets.
  static const int maxImageHeight = 8192;

  /// How many systems the sheet has, for an app that exports in ranges.
  int get systemCount => _view?._layout?.systemCount ?? 0;
}

/// The bar the view keeps in place across an update, and where the top of
/// its system sits in the sheet, in logical pixels.
typedef _ScrollAnchor = ({MeasureId bar, double top});

/// An animated scroll of the view's own, to the system holding `bar`. It
/// goes to the system's top when `toTop`, else the shortest way that shows
/// the whole system. `done` completes when the scroll ends.
typedef _OwnScroll = ({
  MeasureId bar,
  bool toTop,
  Duration duration,
  Completer<void> done,
});

class _SheetViewState extends State<SheetView> {
  ParagraphMeasurer _measurer = ParagraphMeasurer();
  final ScrollController _scroll = ScrollController();
  late GlyphPainter _glyphs = GlyphPainter(widget.style.font);
  SheetController? _ownController;

  /// The layout on screen, and the pixels per staff space it was shown at.
  SheetLayout? _layout;
  double _shownSpacePx = 0;

  /// The colours the sheet was last built with.
  late SheetPalette _palette;

  /// Set when [_layout] cannot be updated and a fresh one must replace it,
  /// because the style changed or a text font loaded late.
  bool _stale = false;

  /// Whether a font registration is waiting for [_afterFontsChanged].
  bool _fontsChanged = false;

  /// The animated scroll of the view's own that is running, from
  /// `ensureVisible`, a moved cursor or playback. Null when none is.
  _OwnScroll? _scrollingTo;

  /// Counts the starts of [_scrollingTo], so that the end of a start that
  /// was replaced is told from the end of the scroll.
  int _drives = 0;

  /// The first bar of the system the playhead was last seen in.
  MeasureId? _playing;

  static bool _licensed = false;

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
    _attach(_controller);
    _scroll.addListener(_onScroll);
    widget.playback?.addListener(_followPlayback);
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
    if (!_licensed) {
      _licensed = true;
      // The tool that collects licences reads a package's LICENSE file and
      // never a font's, so the font's licence is registered here.
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(
          const ['Bravura'],
          await rootBundle.loadString(
            'packages/simple_sheet_music/fonts/OFL.txt',
          ),
        );
      });
    }
  }

  void _attach(SheetController controller) {
    controller
      .._view = this
      .._zoom.addListener(_rebuild);
  }

  /// A view that takes this one's place takes the controller in its
  /// `initState`, which runs before this one is disposed. So the controller
  /// is let go only while it is still this view's.
  void _detach(SheetController controller) {
    controller._zoom.removeListener(_rebuild);
    if (identical(controller._view, this)) {
      controller._view = null;
    }
  }

  @override
  void didUpdateWidget(SheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller ?? _ownController!);
      if (widget.controller != null) {
        _ownController?.dispose();
        _ownController = null;
      }
      _attach(_controller);
    }
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback?.removeListener(_followPlayback);
      widget.playback?.addListener(_followPlayback);
    }
    if (oldWidget.style != widget.style) {
      _stale = true;
      _glyphs = GlyphPainter(widget.style.font);
    }
    final cursor = widget.cursor;
    if (widget.followCursor && cursor != null && cursor != oldWidget.cursor) {
      // The cursor may be in a bar this build lays out for the first time.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollTo(cursor.at.measure, toTop: false);
        }
      });
    }
  }

  void _rebuild() => setState(() {});

  void _onScroll() => _controller._moved();

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
  /// A fresh measurer measures again every text the old one was asked for.
  /// When an extent differs, nothing laid out before can be trusted, and
  /// the fresh measurer and a fresh layout replace the old ones. The engine
  /// is not told. Its measurer stays pure for its lifetime because the old
  /// one is thrown away. When no extent differs, the font was not one the
  /// sheet's text uses and the layout stays.
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

  /// Brings the playhead's system to the top of the view when the playhead
  /// enters it and it is not wholly in view. It acts once per system, so a
  /// user who scrolls away while it plays is not pulled back on every tick.
  /// It never calls setState. The overlay painters listen to the same
  /// listenable and repaint on their own.
  void _followPlayback() {
    final point = widget.playback?.value?.point;
    final layout = _layout;
    final index = point == null ? null : layout?.systemOf(point.bar.measure);
    if (layout == null || index == null) {
      _playing = null;
      return;
    }
    final bar = layout.firstBarOf(index);
    if (bar == _playing) {
      return;
    }
    _playing = bar;
    if (widget.followPlayback) {
      _scrollTo(bar, toTop: true);
    }
  }

  Future<void> _scrollTo(
    MeasureId bar, {
    required bool toTop,
    Duration duration = const Duration(milliseconds: 250),
  }) {
    _stopScrolling();
    final scroll = (
      bar: bar,
      toTop: toTop,
      duration: duration,
      done: Completer<void>(),
    );
    _scrollingTo = scroll;
    _drive(scroll);
    return scroll.done.future;
  }

  void _stopScrolling() {
    final scroll = _scrollingTo;
    _scrollingTo = null;
    scroll?.done.complete();
  }

  /// Starts [scroll], or starts it again towards where its bar is now.
  void _drive(_OwnScroll scroll) {
    final drive = ++_drives;
    void end() {
      if (drive == _drives && identical(_scrollingTo, scroll)) {
        _stopScrolling();
      }
    }

    final layout = _layout;
    final index = layout?.systemOf(scroll.bar);
    if (layout == null || index == null || !_scroll.hasClients) {
      end();
      return;
    }
    final position = _scroll.position;
    final top = widget.padding.top + layout.tops[index] * _spacePx;
    final bottom = top + layout.heightOf(index) * _spacePx;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    if (top >= viewTop && bottom <= viewBottom) {
      end();
      return;
    }
    final fits = bottom - top <= position.viewportDimension;
    final target = (scroll.toTop || top < viewTop || !fits
            ? top
            : bottom - position.viewportDimension)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (scroll.duration == Duration.zero) {
      position.jumpTo(target);
      end();
      return;
    }
    position
        .animateTo(target, duration: scroll.duration, curve: Curves.easeInOut)
        .whenComplete(end);
  }

  /// The bar to keep in place across the next update, read from the layout
  /// on screen. Null before the first frame.
  ///
  /// With [SheetView.followCursor] it is the cursor's bar, when any part of
  /// that bar's system is in the viewport. Otherwise it is the first bar of
  /// the first system that reaches below the viewport's top. A cursor the
  /// user scrolled away from is no anchor, because keeping it still would
  /// move what they are reading.
  _ScrollAnchor? _anchorIn(SheetLayout layout, double spacePx) {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      return null;
    }
    final viewTop = _scroll.offset - widget.padding.top;
    final viewBottom = viewTop + _scroll.position.viewportDimension;
    double topOf(int index) => layout.tops[index] * spacePx;
    double bottomOf(int index) =>
        (layout.tops[index] + layout.heightOf(index)) * spacePx;
    final cursor = widget.followCursor ? widget.cursor?.at.measure : null;
    final cursorSystem = cursor == null ? null : layout.systemOf(cursor);
    if (cursor != null &&
        cursorSystem != null &&
        topOf(cursorSystem) < viewBottom &&
        bottomOf(cursorSystem) > viewTop) {
      return (bar: cursor, top: topOf(cursorSystem));
    }
    var first = 0;
    while (first + 1 < layout.systemCount && bottomOf(first) <= viewTop) {
      first++;
    }
    return (bar: layout.firstBarOf(first), top: topOf(first));
  }

  /// Scrolls so the system holding the anchor's bar sits as far below the
  /// viewport's top as it did before the update.
  ///
  /// This runs after every update. It moves the scroll only when the
  /// anchor's system moved in the sheet, which happens when lines were
  /// broken again (`delta.rebroke`, a zoom or a resize included) or a
  /// system above it changed height. The scroll moves by as much as the
  /// system did. A bar that was deleted leaves the scroll alone.
  ///
  /// It runs inside the LayoutBuilder callback, before the viewport lays
  /// out. `correctBy` moves the offset without notifying, so no listener
  /// rebuilds during layout and the frame paints at the corrected offset.
  /// An offset past the new end is brought back by the scroll physics.
  ///
  /// The correction holds while the scroll is idle, dragged or flung. A
  /// scroll the view itself is animating writes its own offsets on the next
  /// tick and would undo it, and it is going to where its bar was. So the
  /// builder starts such a scroll again after every new layout.
  void _keepInPlace(_ScrollAnchor? anchor, SheetLayout layout, double spacePx) {
    final index = anchor == null ? null : layout.systemOf(anchor.bar);
    if (anchor == null || index == null) {
      return;
    }
    final moved = layout.tops[index] * spacePx - anchor.top;
    if (moved != 0) {
      _scroll.position.correctBy(moved);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          assert(
            constraints.hasBoundedWidth,
            'SheetView breaks lines at its width, so it needs a bounded '
            'width. Give it one with a SizedBox or an Expanded.',
          );
          final spacePx = _spacePx;
          final width =
              (constraints.maxWidth - widget.padding.horizontal) / spacePx;
          final previous = _layout;
          final anchor =
              previous == null ? null : _anchorIn(previous, _shownSpacePx);
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
            // The controller's listeners may rebuild, which a layout pass
            // does not allow. They hear of the new geometry after this
            // frame, when the scroll extent is the new layout's too.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              final scroll = _scrollingTo;
              if (scroll != null) {
                _drive(scroll);
              }
              _controller._moved();
            });
          }
          final palette = _palette = widget.palette ?? SheetPalette.of(context);
          final scale = SheetScale(spacePx: spacePx);
          final onTap = widget.onTap;
          return GestureDetector(
            onTapUp: onTap == null
                ? null
                : (details) {
                    final hit = _controller.hitTest(
                      details.localPosition,
                      voice: widget.cursor?.voice ?? VoiceSlot.one,
                    );
                    if (hit != null) {
                      onTap(hit);
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
                          child: RepaintBoundary(
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
                      ),
                      SliverVariedExtentList(
                        itemExtentBuilder: (index, _) =>
                            index < layout.systemCount
                                ? _extentOf(layout, index) * spacePx
                                : null,
                        // Only a system scrolled into view is asked for,
                        // so only those are assembled.
                        delegate: _SystemTiles(
                          // The scroll view makes each tile a node of its
                          // own for a screen reader.
                          (context, index) => Semantics(
                            label: _labelOf(layout, index),
                            child: Stack(
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

  /// The height of a system's tile in staff spaces, which is its planned
  /// height and the gap to the next system. Known without assembling the
  /// system.
  double _extentOf(SheetLayout layout, int index) =>
      (index + 1 < layout.systemCount
          ? layout.tops[index + 1]
          : layout.height) -
      layout.tops[index];

  /// What a screen reader says for system [index], which is the bars it
  /// holds by their printed numbers. Known without assembling the system.
  String _labelOf(SheetLayout layout, int index) {
    final score = layout.score;
    final first = score.barNumberOf(layout.firstBarOf(index));
    final last = index + 1 < layout.systemCount
        ? score.barNumberOf(layout.firstBarOf(index + 1)) - 1
        : score.barNumberOf(score.measures.last.id);
    return first == last ? 'Bar $first' : 'Bars $first to $last';
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    widget.playback?.removeListener(_followPlayback);
    _stopScrolling();
    _detach(_controller);
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
  ) =>
      extent;
}
