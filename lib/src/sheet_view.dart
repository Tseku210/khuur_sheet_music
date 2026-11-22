import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:khuur_score_layout/khuur_score_layout.dart';
import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:khuur_sheet_music/src/painting.dart';
import 'package:khuur_sheet_music/src/paragraph_measurer.dart';
import 'package:khuur_sheet_music/src/score_player.dart';
import 'package:khuur_sheet_music/src/sheet_palette.dart';

part 'own_scroller.dart';

/// A score as a vertical, scrolling stack of systems at a fixed staff size.
///
/// It takes immutable values and lays out on its own. Give it the next
/// `Score` after an edit and it lays out only the bars the edit touched,
/// breaks lines again only where widths changed, and repaints only the
/// systems that changed. The cursor, the selection, tints and playback
/// repaint an overlay layer and never lay out.
///
/// Its width and its height come from its constraints, which must bound
/// both, as for any scroll view. It breaks lines at its width and scrolls
/// up and down. It does not scroll sideways. A bar wider than the view is
/// squeezed to fit it. Its notes may then overlap, but they keep their
/// order. A bar runs past the view's edge only when its widest mark or
/// its widest note, with the part names and brace, clef and signatures
/// before the bar, is wider than the view. Its size on screen is [staffSpace] times the
/// controller's zoom. It never scales a score to fit a box.
///
/// An update keeps the bar the user is reading where it is. With
/// [followCursor] that is the cursor's bar while its system is in view, and
/// otherwise the first bar of the first system in view. A view at the top
/// of its sheet stays at the top.
///
/// Each system is one node for a screen reader, labelled with the bars it
/// holds.
class SheetView extends StatefulWidget {
  /// A view of [score] with nothing drawn over it unless given.
  const SheetView({
    required this.score,
    this.cursor,
    this.preview,
    this.selection = const NoSelection(),
    this.tints = const {},
    this.playback,
    this.onTap,
    this.onHold,
    this.onRelease,
    this.controller,
    this.style = EngravingStyle.standard,
    this.palette,
    this.staffSpace = 8,
    this.tapGrid = DurationBase.sixteenth,
    this.followCursor = true,
    this.followPlayback = true,
    this.playbackStaff,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  /// The score to show. A new one lays out again only the bars that changed.
  final Score score;

  /// The edit cursor, drawn as a caret. Usually `EditSession.cursor`.
  final VoicePoint? cursor;

  /// A note that is not in the score, drawn where an entry would put it.
  /// The view draws it as a note that stands alone, with its stem, its flag
  /// and the ledger lines it needs, in the palette's preview colour. It
  /// lays nothing out for it, so nothing moves under a finger. An app that
  /// shows where a held finger would put a note sets it from the entry
  /// [onHold] reports, and clears it when [onHold] reports null.
  final NotePreview? preview;

  /// Usually `EditSession.selection`. The overlay repaints for a selection
  /// that is another object.
  final Selection selection;

  /// Colours for particular notes or events, drawn over the sheet, such as
  /// practice feedback or search results. The overlay repaints for a map
  /// that is another object.
  final Map<ElementRef, Color> tints;

  /// Usually `ScorePlayer.position`. The sheet highlights the playing
  /// events, and draws a playhead when the palette's has a width.
  final ValueListenable<PlaybackPosition?>? playback;

  /// Called with what a tap means. Not called for a tap outside every
  /// system.
  final ValueChanged<SheetHit>? onTap;

  /// Called while a finger is held on the view, with where it is and where
  /// a note entered there would go. It is called when the long press
  /// starts, each time the finger moves, and each time the sheet moves
  /// under the finger, as it does when it scrolls, zooms or is laid out
  /// again. It is called with null when the hold ends and when the finger
  /// slides off the view, and again with a hold when the finger slides
  /// back on. The entry is for the cursor's voice, or voice one with no
  /// cursor.
  ///
  /// The view recognizes a long press only when this or [onRelease] is
  /// set.
  final ValueChanged<EntryHold?>? onHold;

  /// Called with where a note entered goes when a held finger lifts over a
  /// system, after [onHold] reports null. The entry is asked again as the
  /// finger lifts, for the sheet on screen then. Not called when the finger
  /// lifts off the view or off every system, or when the hold is
  /// cancelled.
  final ValueChanged<SheetHit>? onRelease;

  /// Zoom, geometry queries and export. Null gives the view a controller of
  /// its own at zoom 1.
  final SheetController? controller;

  /// What changes layout. A style that is not equal to the previous one
  /// lays the whole score out again.
  final EngravingStyle style;

  /// Colours. Null derives them from the ambient theme.
  final SheetPalette? palette;

  /// Logical pixels per staff space at zoom 1.
  final double staffSpace;

  /// The grid a tap snaps to. A tap within a staff space of where a note or
  /// a rest of its voice starts takes that start, whatever the grid. Inside
  /// a tuplet the grid counts in the tuplet's written time. Its type keeps
  /// it from being finer than a 128th, the finest start the model accepts.
  ///
  /// An app that enters one note value at a time passes that value's base,
  /// so that a note starts on a beat of its own value everywhere but at
  /// such a start. A long note that starts off the beats of its own value,
  /// on a finer grid or at such a start, is cut at the beats and the
  /// barline, and the model ties the pieces.
  final DurationBase tapGrid;

  /// Open with the cursor's system in view, and scroll it into view when
  /// the cursor moves.
  final bool followCursor;

  /// While playing, scroll a system to the top of the view when the
  /// playhead enters it and it is not wholly in view.
  final bool followPlayback;

  /// The staff [followPlayback] keeps in view in a system taller than the
  /// view, as `SheetController.ensureVisible` does for its `staff`. Such a
  /// system is scrolled to once this staff is not wholly in view, and its
  /// top goes to the top of the view. Null, or a staff the system does not
  /// draw, follows the system's top.
  final StaffId? playbackStaff;

  /// Room around the sheet, which scrolls with it.
  final EdgeInsets padding;

  @override
  State<SheetView> createState() => _SheetViewState();
}

/// A finger held on a [SheetView], and where a note entered there would go.
@immutable
final class EntryHold {
  /// A hold of [finger] that would enter at [entry].
  const EntryHold({required this.finger, required this.entry});

  /// Where the finger is, in the view's local logical pixels.
  final Offset finger;

  /// What [SheetController.entryAt] answers at [finger] now, in the voice
  /// the view enters in. Null off every system.
  final SheetHit? entry;

  @override
  String toString() => 'EntryHold(finger: $finger, entry: $entry)';
}

/// Zoom, geometry queries and export for one [SheetView].
///
/// Geometry is in the view's local logical pixels and accounts for
/// scrolling, so an app can position its own widgets over the sheet (a
/// loupe, a delete badge, a popup) in a `Stack`. It notifies when
/// scrolling, zoom or layout move the geometry, and when a new tap grid
/// changes what a point means.
///
/// Every answer is about the sheet on screen. A new zoom notifies at once,
/// while the sheet on screen is still the one laid out at the old zoom, and
/// again after the frame that lays out at the new one.
///
/// The view itself listens only to the zoom. A scroll or a new layout
/// notifies the app's listeners and builds nothing in the view.
///
/// Views may share a controller. Each of them is drawn at its zoom, and a
/// scroll or a new layout of any of them notifies its listeners. The
/// queries, [ensureVisible] and [toImage] are for the view that took the
/// controller last of those that still have it, so when that view goes,
/// the one that took it before is served again. Every query answers null,
/// nothing or zero while no view has the controller, and before the first
/// frame of the view it serves. A view that takes the controller or lets
/// it go notifies no one.
class SheetController extends ChangeNotifier {
  /// Throws an [ArgumentError] unless [zoom] is positive and finite.
  SheetController({double zoom = 1}) : _zoom = ValueNotifier(_checked(zoom));

  final ValueNotifier<double> _zoom;

  /// The views that have this controller, in the order they took it. More
  /// than one has it when views share it, and for a frame when a view takes
  /// another's place, since its `initState` runs before the other is
  /// disposed.
  final List<_SheetViewState> _views = [];

  /// The view the queries are for.
  _SheetViewState? get _view => _views.lastOrNull;

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
      _view?._hitTest(local, voice);

  /// The clef, key signature, time signature or tempo mark under a tap at
  /// [local], or null when the tap is on none. A note, an event or a spanner drawn at
  /// least as near takes the tap instead, so ask this first and [hitTest]
  /// when it answers null. The reach is a finger's, as for [hitTest].
  SignatureHit? signatureAt(Offset local) => _view?._signatureAt(local);

  /// Where a note entered at [local] in [voice] would go, whatever is drawn
  /// there, on the view's tap grid. The hit has no target. `SheetView.onHold`
  /// reports this for a held finger, so an app asks it only for other
  /// gestures, such as a tap that enters a note.
  SheetHit? entryAt(Offset local, {VoiceSlot voice = VoiceSlot.one}) =>
      _view?._entryAt(local, voice);

  /// Where the note of [preview] is drawn, with its stem, its flag and its
  /// ledger lines, or null when it is not drawn (a hidden staff, or a bar
  /// the score lacks). A glass that shows where a note will go looks here.
  Rect? rectOfPreview(NotePreview preview) =>
      _rectsOf((layout) => [layout.boundsOfPreview(preview)]).firstOrNull;

  /// Where [ref] is drawn, or null when it is not drawn (a hidden staff).
  Rect? rectOf(ElementRef ref) =>
      _rectsOf((layout) => [layout.boundsOf(ref)]).firstOrNull;

  /// The caret for [cursor], a rect of no width over the cursor's staff.
  Rect? caretOf(VoicePoint cursor) =>
      _rectsOf((layout) => [layout.caretOf(cursor)]).firstOrNull;

  /// The boxes of [selection], which the view marks in the palette's
  /// selection style. The style's padding is not in them.
  List<Rect> rectsOf(Selection selection) =>
      _rectsOf((layout) => layout.selectionBoxes(selection));

  List<Rect> _rectsOf(Iterable<Box?> Function(SheetLayout layout) find) =>
      _view?._rectsOf(find) ?? [];

  /// Scrolls until the system holding [point] is wholly in view, by the
  /// shortest way. A system taller than the view shows its top. The future
  /// completes when the scroll ends or the user takes over.
  ///
  /// A system taller than the view shows [staff] instead when it draws
  /// that staff, which is how a view one staff high follows one part of a
  /// score of several. It scrolls, by the shortest way, until the staff is
  /// in view with the room that is its own, which reaches halfway to the
  /// staves next to it and to the system's edge where there is none. When
  /// the view is too short for that, the staff's lines go to its middle. A
  /// system that fits the view is shown whole, whatever [staff] is.
  ///
  /// The scroll starts when the code that calls is done and before the next
  /// frame, never inside the call. So a listener of this controller and the
  /// handler of a scroll notification of the view's may call it, and calls
  /// start in the order they were made. A call made inside a build starts
  /// when the frame of that build is drawn, and shows in the next one. A
  /// scroll inside a build would reach the app's scroll handlers in the
  /// middle of it.
  ///
  /// The bar may be one of a score the view is given in the same frame. A
  /// bar the sheet does not have after that frame scrolls nothing. A frame
  /// that is on its way when the scroll starts is taken into account, so a
  /// zoom, an edit or a new size of the view set by the code that calls,
  /// before the call or after it, does not leave the system cut. What
  /// changes later is followed while the scroll runs, and not once it has
  /// ended. A system that is in view, or out of it by less than a pixel of
  /// the screen, is scrolled to already, and a drag or a fling of the user's
  /// goes on. A call that asks again for what a scroll of the view's own is
  /// doing joins that scroll and ends with it, so a call on every frame
  /// still gets there. Any other scroll of the view's own stops where it is
  /// when this call replaces it.
  ///
  /// A scroll with a duration is an animation. It waits, and its future
  /// with it, while the view's tickers are muted, as they are under a route
  /// that covers the view. A scroll that waits for a frame waits while the
  /// app draws none, as it does in the background.
  Future<void> ensureVisible(
    ScorePoint point, {
    StaffId? staff,
    Duration duration = const Duration(milliseconds: 250),
  }) =>
      _view?._scroller.scrollTo(
        point.measure,
        staff: staff,
        toTop: false,
        duration: duration,
      ) ??
      Future.value();

  /// Systems [from] up to [to] as one image, without the overlay and
  /// without the view's padding, at [pixelRatio]. [to] is the system count
  /// when null. The header is included when [from] is 0. It draws the
  /// drawables the view paints, in the view's palette and at its size, on
  /// the palette's paper or, when it has none, on a transparent background.
  /// It assembles the systems it covers.
  ///
  /// One image holds only so many pixels on a side. A range taller than
  /// [maxImageSide] device pixels throws an [ArgumentError], so an app
  /// exports a long score as several images. A sheet wider than that throws
  /// one too. Every range is as wide as the sheet, so only a lower
  /// [pixelRatio] makes it fit. An empty range throws an [ArgumentError],
  /// and a range outside the sheet throws a [RangeError]. A controller
  /// without a laid-out view throws a [StateError].
  Future<ui.Image> toImage({int from = 0, int? to, double pixelRatio = 1}) {
    final view = _view;
    final shown = view?._shown;
    if (view == null || shown == null) {
      throw StateError('No SheetView has laid out a sheet for this controller');
    }
    final layout = shown.layout;
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
    final spacePx = shown.spacePx;
    final width = (layout.width * spacePx * pixelRatio).ceil();
    if (width > maxImageSide) {
      throw ArgumentError(
        'The sheet is $width device pixels wide, over the $maxImageSide one '
        'image holds. Lower the pixel ratio.',
      );
    }
    final top = from == 0 ? 0.0 : layout.tops[from];
    final bottom = layout.tops[end - 1] + layout.heightOf(end - 1);
    final height = ((bottom - top) * spacePx * pixelRatio).ceil();
    if (height > maxImageSide) {
      throw ArgumentError(
        'Systems $from to $end are $height device pixels high, over the '
        '$maxImageSide one image holds. Export fewer systems at a time.',
      );
    }
    final palette = shown.palette;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (palette.paper case final paper?) {
      canvas.drawColor(paper, BlendMode.src);
    }
    canvas.scale(pixelRatio);
    paintSystems(
      canvas,
      layout,
      from: from,
      end: end,
      top: top,
      spacePx: spacePx,
      glyphs: view._glyphs,
      palette: palette,
    );
    final picture = recorder.endRecording();
    return picture.toImage(width, height).whenComplete(picture.dispose);
  }

  /// The longest side of an image [toImage] makes, in device pixels. It is
  /// under the texture limit of the devices the package targets.
  static const int maxImageSide = 8192;

  /// How many systems the sheet has, for an app that exports in ranges.
  int get systemCount => _view?._shown?.layout.systemCount ?? 0;
}

/// The sheet on screen, which is the layout the last frame built and what
/// it was drawn with, and where its systems are in logical pixels.
///
/// A system has two frames. The sheet's starts at the first staff space of
/// the layout, and the scroll content's starts [padding] above it.
final class _Shown {
  const _Shown({
    required this.layout,
    required this.spacePx,
    required this.padding,
    required this.palette,
  });

  final SheetLayout layout;
  final double spacePx;
  final EdgeInsets padding;
  final SheetPalette palette;

  /// The top and bottom of the system at [index] in the sheet.
  ({double top, double bottom}) sheetSpanOf(int index) => (
    top: layout.tops[index] * spacePx,
    bottom: (layout.tops[index] + layout.heightOf(index)) * spacePx,
  );

  /// The top and bottom of the system at [index] in the scroll content.
  ({double top, double bottom}) contentSpanOf(int index) {
    final top = padding.top + layout.tops[index] * spacePx;
    return (top: top, bottom: top + layout.heightOf(index) * spacePx);
  }

  /// The height of the tile of the system at [index], which is its planned
  /// height and the gap to the next system. Known without assembling the
  /// system.
  double tileExtentOf(int index) {
    final next = index + 1 < layout.systemCount
        ? layout.tops[index + 1]
        : layout.height;
    return (next - layout.tops[index]) * spacePx;
  }
}

/// The bar the view keeps in place across an update, and where the top of
/// its system sits in the sheet, in logical pixels.
typedef _ScrollAnchor = ({MeasureId bar, double top});

/// The offset that brings a system spanning [top] to [bottom] into a view
/// [viewport] high that is at [pixels]. It is the system's top when [toTop]
/// is set, when the system starts above the view or when it is taller than
/// the view, and otherwise the offset that puts its bottom at the view's.
double _visibleTarget({
  required double top,
  required double bottom,
  required double viewport,
  required double pixels,
  required bool toTop,
}) =>
    toTop || top < pixels || bottom - top > viewport ? top : bottom - viewport;

/// A scroll controller whose position starts at [start]. The view knows
/// where that is only once it has laid the sheet out, which is after a
/// controller's own initial offset is fixed.
class _SheetScroll extends ScrollController {
  double start = 0;

  @override
  double get initialScrollOffset => start;
}

class _SheetViewState extends State<SheetView> {
  ParagraphMeasurer _measurer = ParagraphMeasurer();
  final _SheetScroll _scroll = _SheetScroll();
  late final _OwnScroller _scroller;
  late GlyphPainter _glyphs = GlyphPainter(widget.style.font);
  SheetController? _ownController;

  /// Null before the first frame. Only the builder writes it. A zoom or a
  /// padding that the next frame lays out at is not what is on screen, so
  /// every answer about geometry reads this and never the widget or the
  /// controller.
  _Shown? _shown;

  /// Set when the layout of [_shown] cannot be updated and a fresh one must
  /// replace it, because the style changed or a text font loaded late.
  bool _stale = false;

  /// Whether a font registration is waiting for [_afterFontsChanged].
  bool _fontsChanged = false;

  /// The bar the playhead was last seen in.
  MeasureId? _playing;

  /// Where a finger is held on the view, in its local pixels. Null with no
  /// finger held, and while the held finger is off the view.
  Offset? _held;

  static bool _licensed = false;

  SheetController get _controller =>
      widget.controller ?? (_ownController ??= SheetController());

  /// Sheet space to this widget's local pixels, scroll included.
  SheetScale _viewportOf(_Shown shown) => SheetScale(
    spacePx: shown.spacePx,
    origin: Offset(
      shown.padding.left,
      shown.padding.top - (_scroll.hasClients ? _scroll.offset : 0),
    ),
  );

  /// What a tap at [local] means on the sheet this view shows. A view that
  /// shares its controller answers for its own sheet here.
  SheetHit? _hitTest(Offset local, VoiceSlot voice) => switch (_shown) {
    final shown? => shown.layout.hitTest(
      _viewportOf(shown).toSheet(local),
      voice: voice,
      grid: widget.tapGrid,
      reach: kTouchSlop / shown.spacePx,
    ),
    null => null,
  };

  SignatureHit? _signatureAt(Offset local) => switch (_shown) {
    final shown? => shown.layout.signatureAt(
      _viewportOf(shown).toSheet(local),
      reach: kTouchSlop / shown.spacePx,
    ),
    null => null,
  };

  /// The voice a tap or a held finger enters in.
  VoiceSlot get _voice => widget.cursor?.voice ?? VoiceSlot.one;

  EntryHold? get _hold => switch (_held) {
    final at? => EntryHold(finger: at, entry: _entryAt(at, _voice)),
    null => null,
  };

  /// A held finger is at [local]. A finger off the view is reported once,
  /// as null.
  void _holdAt(Offset local) {
    final was = _held;
    final size = context.size;
    _held = size != null && size.contains(local) ? local : null;
    if (was != null || _held != null) {
      widget.onHold?.call(_hold);
    }
  }

  void _letGo({required bool release}) {
    final held = _held;
    if (held == null) {
      return;
    }
    _held = null;
    final entry = _entryAt(held, _voice);
    widget.onHold?.call(null);
    if (release && entry != null) {
      widget.onRelease?.call(entry);
    }
  }

  /// Tells the controller's listeners that the geometry moved, and the app
  /// what is under a finger held still.
  void _moved() {
    _controller._moved();
    if (_held != null) {
      widget.onHold?.call(_hold);
    }
  }

  SheetHit? _entryAt(Offset local, VoiceSlot voice) => switch (_shown) {
    final shown? => shown.layout.entryAt(
      _viewportOf(shown).toSheet(local),
      voice: voice,
      grid: widget.tapGrid,
    ),
    null => null,
  };

  /// The boxes [find] takes from the layout on screen, in this widget's
  /// local pixels. None before the first frame.
  List<Rect> _rectsOf(Iterable<Box?> Function(SheetLayout layout) find) {
    final shown = _shown;
    if (shown == null) {
      return [];
    }
    final viewport = _viewportOf(shown);
    return [
      for (final box in find(shown.layout).nonNulls) viewport.rectOf(box),
    ];
  }

  @override
  void initState() {
    super.initState();
    _attach(_controller);
    _scroller = _OwnScroller(_scroll, () => _shown, () => mounted);
    _scroll.addListener(_moved);
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
            'packages/khuur_sheet_music/fonts/OFL.txt',
          ),
        );
      });
    }
  }

  void _attach(SheetController controller) {
    controller
      .._views.add(this)
      .._zoom.addListener(_rebuild);
  }

  void _detach(SheetController controller) {
    controller
      .._zoom.removeListener(_rebuild)
      .._views.remove(this);
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
    if (oldWidget.tapGrid != widget.tapGrid) {
      // The controller's listeners may rebuild, which a build does not
      // allow.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _moved();
        }
      });
    }
    if (widget.onHold == null && widget.onRelease == null) {
      _held = null;
    }
    final cursor = widget.cursor;
    if (widget.followCursor && cursor != null && cursor != oldWidget.cursor) {
      // The cursor may be in a bar this build lays out for the first time.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scroller.scrollTo(cursor.at.measure, toTop: false);
        }
      });
    }
  }

  void _rebuild() => setState(() {});

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
  /// enters it and it is not wholly in view. The playhead enters a system
  /// when its bar is on another system than its last bar is in the layout
  /// on screen. So a user who scrolls away while it plays is not pulled
  /// back on every tick, nor when a zoom, a resize or an edit breaks the
  /// lines again under a playhead that stayed in its system.
  ///
  /// It never calls setState. The overlay painters listen to the same
  /// listenable and repaint on their own.
  void _followPlayback() {
    final bar = widget.playback?.value?.point.bar.measure;
    final last = _playing;
    _playing = bar;
    final shown = _shown;
    final index = bar == null ? null : shown?.layout.systemOf(bar);
    if (bar == null || shown == null || index == null) {
      return;
    }
    if (last != null && shown.layout.systemOf(last) == index) {
      return;
    }
    if (widget.followPlayback &&
        _scroller.isCutOff(bar, widget.playbackStaff)) {
      _scroller.scrollTo(bar, staff: widget.playbackStaff, toTop: true);
    }
  }

  /// The bar to keep in place across the next update, read from the sheet
  /// on screen.
  ///
  /// With [SheetView.followCursor] it is the cursor's bar, when any part of
  /// that bar's system is in the viewport. Otherwise it is the first bar of
  /// the first system that reaches below the viewport's top. A cursor the
  /// user scrolled away from is no anchor, because keeping it still would
  /// move what they are reading.
  ///
  /// A view at the top of its scroll extent has no anchor, cursor or not.
  /// It stays at the top. An anchor there would turn a title block that
  /// grows into scroll and hide it.
  _ScrollAnchor? _anchorIn(_Shown shown) {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      return null;
    }
    final position = _scroll.position;
    if (position.pixels <= position.minScrollExtent) {
      return null;
    }
    final layout = shown.layout;
    final viewTop = position.pixels - shown.padding.top;
    final viewBottom = viewTop + position.viewportDimension;
    double topOf(int index) => shown.sheetSpanOf(index).top;
    double bottomOf(int index) => shown.sheetSpanOf(index).bottom;
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

  /// The scroll offset a view that is [viewport] high opens [shown] at.
  ///
  /// A view that follows its cursor opens with the cursor's system in view,
  /// by the rule of `ensureVisible` from the top of the sheet. Any other
  /// opens at the top.
  double _startOf(_Shown shown, double viewport) {
    final cursor = widget.followCursor ? widget.cursor?.at.measure : null;
    final index = cursor == null ? null : shown.layout.systemOf(cursor);
    if (index == null) {
      return 0;
    }
    final (:top, :bottom) = shown.contentSpanOf(index);
    return math.max(
      0,
      _visibleTarget(
        top: top,
        bottom: bottom,
        viewport: viewport,
        pixels: 0,
        toTop: false,
      ),
    );
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
  /// The correction stops at the top of the scroll extent. An offset past
  /// the new end is brought back by the scroll physics, since the new
  /// extent is not known here.
  ///
  /// The correction holds while the scroll is idle, dragged or flung. A
  /// scroll the view itself is animating writes its own offsets on the next
  /// tick and would undo it, and it may be going to where its bar was. So
  /// the builder has such a scroll look again after every frame it builds.
  void _keepInPlace(_ScrollAnchor? anchor, _Shown shown) {
    final index = anchor == null ? null : shown.layout.systemOf(anchor.bar);
    if (anchor == null || index == null) {
      return;
    }
    final position = _scroll.position;
    final moved = math.max(
      shown.sheetSpanOf(index).top - anchor.top,
      position.minScrollExtent - position.pixels,
    );
    if (moved != 0) {
      position.correctBy(moved);
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
      final spacePx = widget.staffSpace * _controller.zoom;
      final padding = widget.padding;
      final width = (constraints.maxWidth - padding.horizontal) / spacePx;
      final previous = _shown;
      final anchor = previous == null ? null : _anchorIn(previous);
      final layout = previous == null || _stale
          ? SheetLayout(
              widget.score,
              width: width,
              text: _measurer,
              style: widget.style,
            )
          : previous.layout.update(widget.score, width: width);
      final palette = widget.palette ?? SheetPalette.of(context);
      final shown = _Shown(
        layout: layout,
        spacePx: spacePx,
        padding: padding,
        palette: palette,
      );
      if (previous == null) {
        // The scroll view makes its position after this returns.
        _scroll.start = _startOf(shown, constraints.maxHeight);
      }
      _keepInPlace(anchor, shown);
      _stale = false;
      _shown = shown;
      final relaid =
          !identical(layout, previous?.layout) ||
          spacePx != previous?.spacePx ||
          padding != previous?.padding;
      // The controller's listeners may rebuild, which a layout pass does
      // not allow. They hear of the new geometry after this frame, when the
      // scroll extent is the new layout's too, and of an offset this frame
      // moved without a notification. A scroll the view is animating looks
      // again then, because this frame may have moved its system, resized
      // the view or moved the offset under the animation.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scroller.afterLayout();
        if (relaid || _scroller.movedSilently) {
          _scroller.heard();
          _moved();
        }
      });
      final scale = SheetScale(spacePx: spacePx);
      final onTap = widget.onTap;
      final holds = widget.onHold != null || widget.onRelease != null;
      final sheet = CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: padding,
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
                  itemExtentBuilder: (index, _) => index < layout.systemCount
                      ? shown.tileExtentOf(index)
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
                          CustomPaint(
                            painter: HighlightPainter(
                              layout: layout,
                              index: index,
                              selection: widget.selection,
                              playback: widget.playback,
                              palette: palette,
                              scale: scale,
                            ),
                          ),
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
                              preview: widget.preview,
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
      );
      return GestureDetector(
        onTapUp: onTap == null
            ? null
            : (details) {
                final hit = _hitTest(details.localPosition, _voice);
                if (hit != null) {
                  onTap(hit);
                }
              },
        onLongPressStart: holds
            ? (details) => _holdAt(details.localPosition)
            : null,
        onLongPressMoveUpdate: holds
            ? (details) => _holdAt(details.localPosition)
            : null,
        onLongPressEnd: holds ? (_) => _letGo(release: true) : null,
        onLongPressCancel: holds ? () => _letGo(release: false) : null,
        // The box is there without a paper too. A box that came and went
        // with the paper would build the scroll view anew, at offset zero.
        child: ColoredBox(
          color: palette.paper ?? const Color(0x00000000),
          child: sheet,
        ),
      );
    },
  );

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
    _scroller.stop();
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
  ) => extent;
}
