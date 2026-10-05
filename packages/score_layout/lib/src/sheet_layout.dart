import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'assembly.dart';
import 'bar_layout.dart';
import 'breaking.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'hit.dart';
import 'signatures.dart';
import 'style.dart';
import 'system_layout.dart';
import 'text.dart';

/// Clear space between the lines of the header, in staff spaces.
const double _headerLineGap = 1;

/// A score laid out as a vertical stack of systems at one width, in staff
/// spaces. The engine's only entry point.
///
/// Build one with [SheetLayout.new], then call [update] with every new
/// score value or width. An update lays out only the bars
/// `Score.changesSince` names, breaks lines again only from the first
/// system an edit can reach, and plans again only the systems whose inputs
/// changed.
///
/// Building or updating a layout assembles no system. It gives every system's
/// place through [systemCount], [tops] and [heightOf]. A system's drawables are
/// assembled the first time [systemAt] is asked for it and kept by the system's
/// key, so a view that shows five systems of a hundred assembles five.
/// [hitTest], [boundsOf], [caretOf], [selectionBoxes] and [playheadAt]
/// assemble the systems they read and lay nothing out.
///
/// Sheet space has its origin at the top-left of the header block, y down. The
/// layout is a value to its readers. Nothing it reports ever changes.
final class SheetLayout {
  factory SheetLayout(
    Score score, {
    required double width,
    required TextMeasurer text,
    EngravingStyle style = EngravingStyle.standard,
  }) => SheetLayout._build(score, width, style, text, null);

  SheetLayout._({
    required this.score,
    required this.width,
    required this.style,
    required this.header,
    required this.tops,
    required this.delta,
    required this._text,
    required this._bars,
    required this._breaks,
    required this._memo,
  });

  factory SheetLayout._build(
    Score score,
    double width,
    EngravingStyle style,
    TextMeasurer text,
    SheetLayout? previous,
  ) {
    final changes = previous == null
        ? ScoreChanges.all(score)
        : score.changesSince(previous.score);
    final old = previous?._bars ?? const <MeasureId, BarLayout>{};
    final bars = <MeasureId, BarLayout>{
      for (final column in score.measures)
        column.id: switch (old[column.id]) {
          final kept? when !changes.relayout.contains(column.id) => kept,
          _ => layoutBar(score.measureView(column.id), style, text),
        },
    };
    final lead =
        previous != null && identical(previous.score.parts, score.parts)
        ? previous._breaks.lead
        : systemLead(score, style, text);
    final breaks = breakSystems(
      bars: [...bars.values],
      width: width,
      lead: lead,
      style: style,
      text: text,
      previous: previous?._breaks,
    );
    final header =
        previous != null &&
            previous.width == width &&
            identical(previous.score.meta, score.meta)
        ? previous.header
        : _header(score.meta, width, style, text);
    final keys = {for (final plan in breaks.plans) plan.key};
    return SheetLayout._(
      score: score,
      width: width,
      style: style,
      header: header,
      tops: _stack(header, breaks.plans, style),
      delta: _delta(previous, bars, breaks),
      text: text,
      bars: bars,
      breaks: breaks,
      memo: {
        for (final MapEntry(:key, :value)
            in (previous?._memo ?? const <SystemKey, SystemLayout>{}).entries)
          if (keys.contains(key)) key: value,
      },
    );
  }

  final Score score;

  /// The sheet's width in staff spaces, which is the view's width in pixels
  /// over the pixels per staff space. Zoom changes it, and so rebreaks lines.
  final double width;

  final EngravingStyle style;

  /// Title, subtitle and credits from `score.meta`, in sheet space.
  final List<Drawable> header;

  /// The sheet y of each system's top.
  final List<double> tops;

  /// What building this layout changed from the layout it was updated
  /// from. An [update] that changes nothing returns the same layout, with
  /// the delta it already had, so compare the layouts before reading it.
  final LayoutDelta delta;

  final TextMeasurer _text;
  final Map<MeasureId, BarLayout> _bars;
  final Breaks _breaks;

  /// Assembled systems by key. An update carries over the entries whose
  /// key is still some system's key and drops the rest, so the memo never
  /// holds more than one entry per system of this layout.
  final Map<SystemKey, SystemLayout> _memo;

  final Map<int, TextDraw> _labels = {};

  late final Map<MeasureId, int> _systemOfBar = {
    for (final (index, plan) in _breaks.plans.indexed)
      for (final measure in plan.bars) measure: index,
  };

  int get systemCount => _breaks.plans.length;

  /// The planned height of system [index]. Known without assembling it.
  double heightOf(int index) => _breaks.plans[index].height;

  double get height => tops.last + heightOf(systemCount - 1);

  /// System [index], assembled on first use.
  ///
  /// The same object comes back for as long as the system's key is
  /// unchanged, across updates too, so identity is the painter's cache
  /// key. An update carries over the systems assembled before it. One the
  /// old layout assembles after the update is its own.
  SystemLayout systemAt(int index) {
    final plan = _breaks.plans[index];
    return _memo.putIfAbsent(
      plan.key,
      () => assembleSystem(plan, style, _text),
    );
  }

  /// The bar number printed at the start of system [index], in system
  /// space, or null when `style.barNumbers` is off.
  ///
  /// Kept outside [SystemLayout], so inserting a bar renumbers every later
  /// system without assembling one. The number is `Score.barNumberOf`,
  /// which gives a pickup bar 0. Its room above the top staff is part of
  /// the system's plan.
  TextDraw? labelOf(int index) {
    if (!style.barNumbers) {
      return null;
    }
    return _labels.putIfAbsent(index, () {
      final plan = _breaks.plans[index];
      final number = '${score.barNumberOf(plan.bars.first)}';
      final spec = style.specOf(TextRole.barNumber);
      final extent = _text.measure(number, spec);
      final at = plan.labelAt;
      return TextDraw(
        number,
        at,
        spec: spec,
        bounds: Box(
          at.x,
          at.y - extent.ascent,
          at.x + extent.width,
          at.y + extent.descent,
        ),
        ink: InkRole.barNumber,
      );
    });
  }

  /// Lays out [next], at [width] if given, reusing all that is still valid.
  ///
  /// Returns this layout when nothing changed. A different style needs a
  /// new SheetLayout, since every bar depends on it. So does a text font
  /// that finished loading, since every measured text depends on it.
  SheetLayout update(Score next, {double? width}) {
    final nextWidth = width ?? this.width;
    if (identical(next, score) && nextWidth == this.width) {
      return this;
    }
    return SheetLayout._build(next, nextWidth, style, _text, this);
  }

  /// The system showing bar [measure], or null when the bar is not in the
  /// score.
  int? systemOf(MeasureId measure) => _systemOfBar[measure];

  /// The first bar of system [index]. Known without assembling it, so a
  /// view can name the bar it keeps in place across an update.
  MeasureId firstBarOf(int index) => _breaks.plans[index].bars.first;

  /// What a tap at [point] in sheet space means. Null more than half a
  /// system gap above the first system or below the last, and on a sheet
  /// without a visible staff.
  ///
  /// 1. The system, by binary search of [tops]. A point in the gap between
  ///    two systems belongs to the nearer one. A system's band ends where
  ///    its content does, so a ledger position over a staff with nothing
  ///    above it lies outside the band and is still that system's.
  /// 2. The target, which is what is drawn nearest the point within
  ///    [reach]. Between things as near as each other, a notehead comes
  ///    first, then any other part of an event, then a spanner.
  /// 3. When the target is a note or an event, the staff, voice and time
  ///    of its event. A head beside its stem, a grace head and a rest in the
  ///    middle of its bar lie away from their event's onset, and still give
  ///    it.
  /// 4. Otherwise the bar whose x range holds the point, the staff whose
  ///    middle is nearest, [voice], and the time by [snapTime] for entry in
  ///    [voice] on [grid]. The grid's type keeps it from being finer than a
  ///    128th.
  /// 5. The staff step nearest the point's y, on the staff of step 3 or 4.
  ///
  /// [reach] is a finger's reach in staff spaces. The view passes its touch
  /// slop over its pixels per staff space.
  SheetHit? hitTest(
    SpPoint point, {
    VoiceSlot voice = VoiceSlot.one,
    DurationBase grid = DurationBase.sixteenth,
    double reach = 0,
  }) {
    final under = _systemUnder(point);
    if (under == null) {
      return null;
    }
    final (system, local) = under;
    final target = system.targetAt(local, reach: reach);
    if (target case ElementOwner(ref: ElementRef(:final event))) {
      final timed = score.lookup(event)!;
      return SheetHit(
        staff: timed.ref.staff,
        voice: timed.voice,
        at: ScorePoint(timed.ref.measure, timed.onset),
        staffStep: system.staffOf(timed.ref.staff)!.stepAt(local.y),
        target: target,
      );
    }
    return _entryIn(system, local, voice, grid, target);
  }

  /// Where a note entered at [point] in [voice] would go, whatever is drawn
  /// there. It is steps 1, 4 and 5 of [hitTest], so the hit has no target,
  /// and it is null where [hitTest] is null.
  ///
  /// An editor asks this for a finger that is held on the sheet to place a
  /// note. [hitTest] at a rest in the middle of its bar gives the rest's
  /// onset, which is the start of the bar and far from the finger.
  SheetHit? entryAt(
    SpPoint point, {
    VoiceSlot voice = VoiceSlot.one,
    DurationBase grid = DurationBase.sixteenth,
  }) => switch (_systemUnder(point)) {
    (final system, final local) => _entryIn(system, local, voice, grid, null),
    null => null,
  };

  /// The system a tap at [point] belongs to, with the point in that
  /// system's space. Null where no system is and on a system without a
  /// staff.
  (SystemLayout, SpPoint)? _systemUnder(SpPoint point) {
    final index = _systemAtY(point.y);
    if (index == null) {
      return null;
    }
    final system = systemAt(index);
    return system.staves.isEmpty
        ? null
        : (system, point.shift(0, -tops[index]));
  }

  SheetHit _entryIn(
    SystemLayout system,
    SpPoint local,
    VoiceSlot voice,
    DurationBase grid,
    Owner? target,
  ) {
    final bar = system.barAt(local.x);
    final staff = system.staffNear(local.y);
    final times = voiceTimes(
      score.measureView(bar.measure),
      staff.staff,
      voice,
    );
    return SheetHit(
      staff: staff.staff,
      voice: voice,
      at: ScorePoint(bar.measure, snapTime(bar, times, local.x, grid)),
      staffStep: staff.stepAt(local.y),
      target: target,
    );
  }

  /// The system a tap at sheet y [y] belongs to. That is the system whose
  /// planned band holds it, or the nearer of the two systems around the gap
  /// it lies in. Null more than half a system gap above the first system,
  /// where the header is, or below the last.
  int? _systemAtY(double y) {
    var low = 0;
    var high = tops.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (tops[mid] <= y) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final index = low - 1;
    if (index < 0) {
      return tops.first - y <= style.systemGap / 2 ? 0 : null;
    }
    final under = y - (tops[index] + heightOf(index));
    if (under <= 0) {
      return index;
    }
    if (index + 1 == tops.length) {
      return under <= style.systemGap / 2 ? index : null;
    }
    return under <= tops[index + 1] - y ? index : index + 1;
  }

  /// The system that draws [ref], or null when its event is gone.
  ///
  /// A ref's measure is a hint. A change of meter moves an event to another
  /// bar and leaves the refs an app holds naming the old one. So the score
  /// says which bar holds the event now (`Score.lookup`, which tries the
  /// hinted bar first).
  int? systemOfRef(ElementRef ref) => switch (score.lookup(ref.event)) {
    final found? => systemOf(found.ref.measure),
    null => null,
  };

  /// In sheet space, or null when [ref] is drawn nowhere (a hidden staff,
  /// or an event no longer in the score).
  Box? boundsOf(ElementRef ref) {
    final index = systemOfRef(ref);
    return index == null
        ? null
        : systemAt(index).boundsOf(ElementOwner(ref))?.shift(0, tops[index]);
  }

  /// The caret for [cursor] in sheet space. It is a box of no width at the
  /// cursor's x, spanning its staff.
  Box? caretOf(VoicePoint cursor) {
    final index = systemOf(cursor.at.measure);
    return index == null ? null : caretIn(index, cursor)?.shift(0, tops[index]);
  }

  /// The caret in the space of system [index], or null when the cursor is
  /// on another system or a hidden staff. The overlay of one system tile
  /// asks this for its own system.
  Box? caretIn(int index, VoicePoint cursor) {
    if (systemOf(cursor.at.measure) != index) {
      return null;
    }
    final system = systemAt(index);
    final staff = system.staffOf(cursor.staff);
    final bar = system.barOf(cursor.at.measure);
    if (staff == null || bar == null) {
      return null;
    }
    final x = bar.time.xAt(cursor.at.offset);
    return Box(x, staff.top, x, staff.top + staffHeight);
  }

  /// Boxes to shade for [selection], in sheet space. An item asks the score
  /// once for the system that draws it.
  List<Box> selectionBoxes(Selection selection) => switch (selection) {
    ItemSelection(:final items) => [for (final ref in items) ?boundsOf(ref)],
    _ => [
      for (var index = 0; index < systemCount; index++)
        for (final box in selectionIn(index, selection))
          box.shift(0, tops[index]),
    ],
  };

  /// Boxes to shade on system [index] for [selection], in system space. An
  /// item gives its bounds. A range gives one box from its start to its
  /// exclusive end (which may be a bar's end) over the visible staves from
  /// `top` to `bottom`, and no box when it holds nothing.
  List<Box> selectionIn(int index, Selection selection) {
    switch (selection) {
      case NoSelection():
        return const [];
      case ItemSelection(:final items):
        return [
          for (final ref in items)
            if (systemOfRef(ref) == index)
              ?systemAt(index).boundsOf(ElementOwner(ref)),
        ];
      case RangeSelection(:final from, :final to, :final top, :final bottom):
        final first = systemOf(from.measure);
        final ending = systemOf(to.measure);
        if (first == null || ending == null) {
          return const [];
        }
        // The end is exclusive. A range that ends at the very start of a
        // system holds nothing of it, and would shade its clef and key.
        final last =
            ending > first &&
                to.offset == Moment.zero &&
                firstBarOf(ending) == to.measure
            ? ending - 1
            : ending;
        if (index < first || index > last) {
          return const [];
        }
        final system = systemAt(index);
        final order = [for (final staff in score.staves) staff.id];
        final staves = [
          for (final staff in system.staves)
            if (order.indexOf(top) <= order.indexOf(staff.staff) &&
                order.indexOf(staff.staff) <= order.indexOf(bottom))
              staff,
        ];
        if (staves.isEmpty) {
          return const [];
        }
        // A continuation starts at its first bar's first point, after the
        // clef and signatures, as a range starting there would.
        final start = system.barOf(from.measure) ?? system.bars.first;
        final end = system.bars.indexWhere((bar) => bar.measure == to.measure);
        // A range to the start of a bar ends where the bar before it ends,
        // short of the bar's clef before the barline and of the signatures
        // it opens with.
        final right = switch (end) {
          -1 => system.bars.last.right,
          > 0 when to.offset == Moment.zero => system.bars[end - 1].right,
          _ => system.bars[end].time.xAt(to.offset),
        };
        final left = start.time.xAt(
          start.measure == from.measure ? from.offset : Moment.zero,
        );
        // A range that ends where it starts, or before, holds nothing.
        if (right <= left) {
          return const [];
        }
        return [
          Box(left, staves.first.top, right, staves.last.top + staffHeight),
        ];
    }
  }

  /// The playhead for [point] in sheet space. It is a box of no width
  /// across its system. Null when the bar is not in the score.
  Box? playheadAt(PlaybackPoint point) {
    final index = systemOf(point.bar.measure);
    final x = index == null ? null : playheadIn(index, point);
    return index == null || x == null
        ? null
        : Box(x, tops[index], x, tops[index] + heightOf(index));
  }

  /// The playhead's x in the space of system [index], or null when [point]
  /// is on another system.
  double? playheadIn(int index, PlaybackPoint point) =>
      systemOf(point.bar.measure) == index
      ? systemAt(index)
            .barOf(point.bar.measure)
            ?.time
            .xAtWholeNotes(
              point.offset,
            )
      : null;

  static List<Drawable> _header(
    ScoreMeta meta,
    double width,
    EngravingStyle style,
    TextMeasurer text,
  ) {
    final lines = [
      [(meta.title, TextRole.title, InkRole.title, _Align.centre)],
      [(meta.subtitle, TextRole.subtitle, InkRole.subtitle, _Align.centre)],
      [
        (meta.lyricist, TextRole.credit, InkRole.credit, _Align.left),
        (meta.composer, TextRole.credit, InkRole.credit, _Align.right),
      ],
    ];
    final drawables = <Drawable>[];
    var bottom = 0.0;
    for (final line in lines) {
      final texts = [
        for (final (string, role, ink, align) in line)
          if (string.isNotEmpty)
            (
              string,
              style.specOf(role),
              ink,
              align,
              text.measure(string, style.specOf(role)),
            ),
      ];
      if (texts.isEmpty) {
        continue;
      }
      final y =
          bottom +
          (drawables.isEmpty ? 0 : _headerLineGap) +
          texts.map((entry) => entry.$5.ascent).reduce(math.max);
      for (final (string, spec, ink, align, extent) in texts) {
        final x = switch (align) {
          _Align.left => 0.0,
          _Align.centre => math.max<double>(0, (width - extent.width) / 2),
          _Align.right => math.max<double>(0, width - extent.width),
        };
        drawables.add(
          TextDraw(
            string,
            SpPoint(x, y),
            spec: spec,
            bounds: Box(
              x,
              y - extent.ascent,
              x + extent.width,
              y + extent.descent,
            ),
            ink: ink,
          ),
        );
        bottom = math.max(bottom, y + extent.descent);
      }
    }
    return drawables;
  }

  static List<double> _stack(
    List<Drawable> header,
    List<SystemPlan> plans,
    EngravingStyle style,
  ) {
    var y = 0.0;
    for (final drawable in header) {
      y = math.max(y, drawable.bounds.bottom + style.systemGap);
    }
    final tops = <double>[];
    for (final plan in plans) {
      tops.add(y);
      y += plan.height + style.systemGap;
    }
    return tops;
  }

  static LayoutDelta _delta(
    SheetLayout? previous,
    Map<MeasureId, BarLayout> bars,
    Breaks breaks,
  ) {
    if (previous == null) {
      return LayoutDelta(
        relaid: bars.keys.toSet(),
        rekeyed: {for (var i = 0; i < breaks.plans.length; i++) i},
        rebroke: true,
      );
    }
    final oldKeys = {for (final plan in previous._breaks.plans) plan.key};
    final oldStarts = previous._breaks.starts;
    return LayoutDelta(
      relaid: {
        for (final MapEntry(key: measure, value: bar) in bars.entries)
          if (!identical(previous._bars[measure], bar)) measure,
      },
      rekeyed: {
        for (final (index, plan) in breaks.plans.indexed)
          if (!oldKeys.contains(plan.key)) index,
      },
      rebroke:
          oldStarts.length != breaks.starts.length ||
          breaks.starts.indexed.any((start) => oldStarts[start.$1] != start.$2),
    );
  }
}

enum _Align { left, centre, right }

/// What an update changed.
final class LayoutDelta {
  const LayoutDelta({
    required this.relaid,
    required this.rekeyed,
    required this.rebroke,
  });

  final Set<MeasureId> relaid;

  /// Indices in the new layout of the systems whose key no system of the
  /// layout before had. Each needs a new plan, and a new assembly when it
  /// is next asked for. A system that only moved to another index keeps
  /// its key and is not here.
  final Set<int> rekeyed;

  /// Whether the list of system starts differs from before.
  final bool rebroke;
}
