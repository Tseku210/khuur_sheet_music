import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'assembly.dart';
import 'bar_layout.dart';
import 'breaking.dart';
import 'drawable.dart';
import 'geometry.dart';
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
    return _memo.putIfAbsent(plan.key, () => assembleSystem(plan, style));
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

  static List<Drawable> _header(
    ScoreMeta meta,
    double width,
    EngravingStyle style,
    TextMeasurer text,
  ) {
    final lines = [
      [(meta.title, TextRole.title, _Align.centre)],
      [(meta.subtitle, TextRole.subtitle, _Align.centre)],
      [
        (meta.lyricist, TextRole.credit, _Align.left),
        (meta.composer, TextRole.credit, _Align.right),
      ],
    ];
    final drawables = <Drawable>[];
    var bottom = 0.0;
    for (final line in lines) {
      final texts = [
        for (final (string, role, align) in line)
          if (string.isNotEmpty)
            (
              string,
              style.specOf(role),
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
          texts.map((entry) => entry.$4.ascent).reduce(math.max);
      for (final (string, spec, align, extent) in texts) {
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
