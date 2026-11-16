part of 'sheet_view.dart';

/// An animated scroll of the view's own, to the system holding `bar`, or
/// to `staff` of it when the system is taller than the view. It goes to
/// the top of that when `toTop`, else the shortest way that shows it whole.
/// `done` completes when the scroll ends.
typedef _OwnScroll = ({
  MeasureId bar,
  StaffId? staff,
  bool toTop,
  Duration duration,
  Completer<void> done,
});

/// Where what a scroll shows is in the scroll content, which is a system
/// or the part of one that holds a staff, and how much of the content the
/// view shows, in logical pixels.
typedef _Place = ({double top, double bottom, double viewport});

/// The scrolls of a view's own, from `ensureVisible`, a moved cursor and
/// playback, over the view's scroll controller.
///
/// At most one runs at a time. [scrollTo] starts one, joins the one that
/// runs when it asks for the same, or replaces it. A frame that lays the
/// sheet out may move the system a scroll goes to, or the offset under its
/// animation, so the view tells the scroller when such a frame ends
/// ([afterLayout]).
final class _OwnScroller {
  /// Scrolls over [_scroll] to the systems of the sheet [_shown] reads,
  /// while [_mounted] holds. It listens to [_scroll] to know the offset the
  /// controller's listeners heard of, so the view makes it before it adds a
  /// listener of its own.
  _OwnScroller(this._scroll, this._shown, this._mounted) {
    _scroll.addListener(heard);
  }

  final ScrollController _scroll;
  final _Shown? Function() _shown;
  final bool Function() _mounted;

  /// The scroll of the view's own that is running or waits for a frame,
  /// from `ensureVisible`, a moved cursor or playback. Null when none is.
  _OwnScroll? _scrollingTo;

  /// Counts the starts of [_scrollingTo], so that the end of a start that
  /// was replaced is told from the end of the scroll.
  int _drives = 0;

  /// The start of [_scrollingTo] whose animation the scroll position is
  /// running, and the offset it goes to. Null when it runs none of the
  /// view's, because none started, it ended, or a drag or a fling of the
  /// user's took over.
  ({int drive, double target})? _animating;

  /// The scroll offset the controller's listeners last heard of. A frame
  /// that lays the sheet out may move the offset and notify no one, to keep
  /// its anchor in place or to stay inside a new scroll extent. From then
  /// to the end of that frame the offset is another than this.
  double? _toldAt;

  /// Notes the offset the controller's listeners hear of now.
  void heard() => _toldAt = _offset;

  double? get _offset => _scroll.hasClients ? _scroll.position.pixels : null;

  /// Whether the frame that is ending moved the scroll offset and notified
  /// no one.
  bool get movedSilently => _offset != _toldAt;

  /// Starts a scroll of the view's own in a microtask, which runs when the
  /// code that asks is done and before the next frame.
  ///
  /// A listener of the controller and the handler of a scroll notification
  /// ask from inside the scroll position, which has more to do when they
  /// return. It ends a scroll that starts there, and a jump there trips its
  /// assertions. And what a handler changes after it asks is on its way
  /// when the scroll starts, like what it changed before.
  Future<void> scrollTo(
    MeasureId bar, {
    StaffId? staff,
    required bool toTop,
    Duration duration = const Duration(milliseconds: 250),
  }) => Future.microtask(
    () => _mounted()
        ? _scrollNow(bar, staff: staff, toTop: toTop, duration: duration)
        : null,
  );

  Future<void> _scrollNow(
    MeasureId bar, {
    required StaffId? staff,
    required bool toTop,
    required Duration duration,
  }) {
    final running = _scrollingTo;
    if (running != null &&
        running.bar == bar &&
        running.staff == staff &&
        running.toTop == toTop &&
        running.duration == duration) {
      // The same scroll, asked for again. Starting it over would take its
      // animation back to its first frame, and one asked for on every
      // frame would never get there.
      _drive(running, hold: true);
      return running.done.future;
    }
    stop();
    final scroll = (
      bar: bar,
      staff: staff,
      toTop: toTop,
      duration: duration,
      done: Completer<void>(),
    );
    _scrollingTo = scroll;
    _drive(scroll, hold: true);
    return scroll.done.future;
  }

  /// Ends the scroll of the view's own, if there is one. Its animation
  /// stops where it is, or it would run on to a place nothing asks for any
  /// more. A drag or a fling that took the animation's place is the user's
  /// and is left alone.
  void stop() {
    final scroll = _scrollingTo;
    _scrollingTo = null;
    if (_animating != null) {
      _animating = null;
      // The scroll view is gone already when the view is disposed.
      if (_scroll.hasClients) {
        _scroll.position.jumpTo(_scroll.position.pixels);
      }
    }
    scroll?.done.complete();
  }

  /// Where the system holding [bar] is. Null when the sheet on screen has no
  /// such bar, or the view has no scroll position yet.
  ///
  /// For a system taller than the view that draws [staff], it is where the
  /// staff's share of the system is, or when the view is too short for
  /// that too, what the view shows with the staff's lines at its middle.
  _Place? _placeOf(MeasureId bar, [StaffId? staff]) {
    final shown = _shown();
    final index = shown?.layout.systemOf(bar);
    if (shown == null || index == null || !_scroll.hasClients) {
      return null;
    }
    final _Shown(:layout, :spacePx) = shown;
    final (:top, :bottom) = shown.contentSpanOf(index);
    final viewport = _scroll.position.viewportDimension;
    final system = (top: top, bottom: bottom, viewport: viewport);
    if (staff == null || bottom - top <= viewport) {
      return system;
    }
    final placed = layout.systemAt(index);
    final band = placed.bandOf(staff);
    final lines = placed.staffOf(staff);
    if (band == null || lines == null) {
      return system;
    }
    if ((band.bottom - band.top) * spacePx <= viewport) {
      return (
        top: top + band.top * spacePx,
        bottom: top + band.bottom * spacePx,
        viewport: viewport,
      );
    }
    final middle = top + (lines.top + staffHeight / 2) * spacePx;
    return (
      top: middle - viewport / 2,
      bottom: middle + viewport / 2,
      viewport: viewport,
    );
  }

  /// Whether the view shows all of the system at [place]. A system that is
  /// out of view by less than [slack] counts as in it.
  bool _showsAll(_Place place, {double slack = 0}) {
    final pixels = _scroll.position.pixels;
    return place.top >= pixels - slack &&
        place.bottom <= pixels + place.viewport + slack;
  }

  /// The distance the scroll position takes for none, which is about one
  /// physical pixel. An animation that short is one it does not run.
  double get _slack {
    final position = _scroll.position;
    return position.physics.toleranceFor(position).distance;
  }

  /// The offset [scroll] goes to for a system at [place]. Null when it has
  /// nowhere to go, because the system is wholly in view and the scroll is
  /// not one to the top.
  double? _targetOf(_OwnScroll scroll, _Place place) {
    if (!scroll.toTop && _showsAll(place)) {
      return null;
    }
    final position = _scroll.position;
    final (:top, :bottom, :viewport) = place;
    return _visibleTarget(
      top: top,
      bottom: bottom,
      viewport: viewport,
      pixels: position.pixels,
      toTop: scroll.toTop,
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// Whether a frame that may lay the sheet out again is on its way. It is
  /// one that is asked for, or one that has begun and has not ended.
  bool get _frameAhead {
    final binding = WidgetsBinding.instance;
    return binding.hasScheduledFrame ||
        switch (binding.schedulerPhase) {
          SchedulerPhase.transientCallbacks ||
          SchedulerPhase.midFrameMicrotasks ||
          SchedulerPhase.persistentCallbacks => true,
          SchedulerPhase.idle || SchedulerPhase.postFrameCallbacks => false,
        };
  }

  /// Starts [scroll], or starts it again towards where its bar is now. An
  /// animation that goes there already runs on, unless it is to start
  /// [anew] because a frame moved the offset under it. Its next tick would
  /// write the offset it had planned from where it began, and undo the move
  /// or run into the end of a sheet that got shorter.
  ///
  /// A scroll to the top goes on until its system is at the top. Any other
  /// ends as soon as its system is wholly in view.
  ///
  /// With [hold], the scroll takes a frame that is on its way into
  /// account. An app does two things in one handler, and the view sees the
  /// second before the frame that shows the first. A bar the sheet on
  /// screen does not have may be in the score that frame lays out. A system
  /// that is in view, or one the scroll jumped to, may be moved or cut by
  /// that frame, after a new zoom, an edit or a new size of the view. So
  /// the scroll looks again after the frame, and starts again when its
  /// system is somewhere else in the sheet or the frame moved the offset
  /// itself. A system only the user's scroll moved is where it was, and the
  /// scroll ends. An animation that gets to its target holds too, because
  /// it gets there inside a frame that may still lay the sheet out. One
  /// that ends anywhere else, or with the position still scrolling, was
  /// ended by the user or by a later scroll, and the scroll ends with it.
  ///
  /// A scroll that has less to go than the position takes for a distance
  /// has nowhere to go. The position's own animation would jump there and
  /// end at once, before the frame the scroll has to look after, and the
  /// jump would take a drag from the user.
  void _drive(_OwnScroll scroll, {bool hold = false, bool anew = false}) {
    final place = _placeOf(scroll.bar, scroll.staff);
    final target = place == null ? null : _targetOf(scroll, place);
    if (!anew && target != null && target == _animating?.target) {
      return;
    }
    final drive = ++_drives;
    bool isLive() => drive == _drives && identical(_scrollingTo, scroll);
    void end() {
      if (isLive()) {
        stop();
      }
    }

    void afterFrame(VoidCallback look) {
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (isLive()) {
            look();
          }
        })
        ..ensureVisualUpdate();
    }

    if (place == null) {
      if (hold) {
        afterFrame(() => _drive(scroll));
      } else {
        end();
      }
      return;
    }
    final position = _scroll.position;
    final near = target != null && (target - position.pixels).abs() < _slack;
    if (target == null || near || scroll.duration == Duration.zero) {
      if (target != null && !near) {
        position.jumpTo(target);
      }
      if (hold && _frameAhead) {
        afterFrame(() {
          if (_placeOf(scroll.bar, scroll.staff) == place && !movedSilently) {
            end();
          } else {
            _drive(scroll);
          }
        });
      } else {
        end();
      }
      return;
    }
    _animating = (drive: drive, target: target);
    position
        .animateTo(target, duration: scroll.duration, curve: Curves.easeInOut)
        .whenComplete(() {
          // The position runs nothing of the view's now.
          if (_animating?.drive == drive) {
            _animating = null;
          }
          // Only an animation that ran to its end leaves the view at its
          // target and at rest. The view may have a new scroll position by
          // now, which took the animation over, so both are read from that
          // one.
          if (isLive() &&
              _offset == target &&
              !_scroll.position.isScrollingNotifier.value) {
            _drive(scroll, hold: true);
          } else {
            // The user or a later scroll took over on the way, be it on the
            // last pixel, or with a drag that went to the target itself.
            end();
          }
        });
  }

  /// Whether the system holding [bar], or [staff]'s share of it, is out of
  /// view by more than about a pixel. False when the sheet on screen has no
  /// such bar.
  bool isCutOff(MeasureId bar, StaffId? staff) {
    final place = _placeOf(bar, staff);
    return place != null && !_showsAll(place, slack: _slack);
  }

  /// A frame that laid the sheet out has ended. A scroll that is animating
  /// looks again, because the frame may have moved its system, resized the
  /// view or moved the offset under the animation.
  void afterLayout() {
    final scroll = _scrollingTo;
    if (scroll != null && _animating != null) {
      _drive(scroll, anew: movedSilently);
    }
  }
}
