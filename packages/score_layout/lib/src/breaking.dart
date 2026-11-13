/// Line breaking and system planning over cached bars. Not exported.
///
/// Everything here reads bars and never builds a system. It decides where
/// each system starts, and for each system its stretch, its staff tops and
/// its height. So the sheet knows every system's place before any system
/// is assembled, and assembles one only when somebody looks at it.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_layout.dart';
import 'chords.dart';
import 'geometry.dart';
import 'lyrics.dart';
import 'signatures.dart';
import 'spacing.dart';
import 'style.dart';
import 'text.dart';

/// What a system takes whole. It is one bar, or a run of rest-only bars drawn
/// as one multi-measure rest.
///
/// Two units are equal when they hold the same `BarLayout` objects.
sealed class BreakUnit {
  const BreakUnit();

  List<BarLayout> get bars;

  BarLayout get first => bars.first;
  BarLayout get last => bars.last;

  LayoutBreak? get breakBefore => first.breakBefore;

  BarWidths get widths;

  /// Clear space between the unit's head and its first slice.
  double get lead;

  List<Slice> get slices;

  /// Per visible staff, how far the unit reaches outside it.
  List<BarStaff> get staves;

  /// The first bar's start and the last bar's end, for the barlines.
  BarEdges get edges => (
    repeatStart: first.edges.repeatStart,
    startJoins: first.edges.startJoins,
    end: last.edges.end,
    repeatEnd: last.edges.repeatEnd,
  );
}

final class SingleBar extends BreakUnit {
  const SingleBar(this.bar);

  final BarLayout bar;

  @override
  List<BarLayout> get bars => [bar];

  @override
  BarWidths get widths => bar.widths;

  @override
  double get lead => bar.lead;

  @override
  List<Slice> get slices => bar.slices;

  @override
  List<BarStaff> get staves => bar.staves;

  @override
  bool operator ==(Object other) =>
      other is SingleBar && identical(other.bar, bar);

  @override
  int get hashCode => identityHashCode(bar);
}

/// Two or more rest-only bars drawn as one H-bar rest with their count
/// above. It prints the first bar's head and the last bar's barline.
final class RestRun extends BreakUnit {
  RestRun(this.bars, {required double body, required double countRise})
    : slices = [
        Slice(at: Moment.zero, ideal: body, rod: body),
        bars.last.slices.last,
      ],
      staves = [
        for (final (index, staff) in bars.first.staves.indexed)
          (
            staff: staff.staff,
            lines: staff.lines,
            above: bars.fold(
              countRise,
              (above, bar) => math.max(above, bar.staves[index].above),
            ),
            below: bars.fold(
              0,
              (below, bar) => math.max(below, bar.staves[index].below),
            ),
          ),
      ];

  @override
  final List<BarLayout> bars;

  /// The H-bar, which stretches with its system, and the last bar's end.
  @override
  final List<Slice> slices;

  @override
  final List<BarStaff> staves;

  @override
  late final BarWidths widths = BarWidths(
    inlineHead: first.widths.inlineHead,
    systemHead: first.widths.systemHead,
    courtesy: first.widths.courtesy,
    body: naturalWidth(slices),
    minBody: rodWidth(slices),
  );

  @override
  double get lead => 0;

  @override
  bool operator ==(Object other) =>
      other is RestRun &&
      other.bars.length == bars.length &&
      Iterable<int>.generate(
        bars.length,
      ).every((i) => identical(other.bars[i], bars[i]));

  @override
  int get hashCode => Object.hashAll(bars.map(identityHashCode));
}

/// One unit per bar, or with `style.multiMeasureRests` one [RestRun] per
/// run of two or more rest-only bars. A run ends before a bar that is not
/// rest-only and before a bar with a `breakBefore`.
///
/// `MeasureView.isRestOnly` already excludes a bar that prints a signature,
/// a repeat, a volta, a mark or a barline other than the regular one, so a
/// run never hides one.
List<BreakUnit> foldBars(List<BarLayout> bars, EngravingStyle style) {
  if (!style.multiMeasureRests) {
    return [for (final bar in bars) SingleBar(bar)];
  }
  final units = <BreakUnit>[];
  var run = <BarLayout>[];
  void flush() {
    if (run.length >= 2) {
      units.add(
        RestRun(
          run,
          body: style.spacing.restRunWidth,
          countRise: restRunRise(style),
        ),
      );
    } else {
      units.addAll(run.map(SingleBar.new));
    }
    run = [];
  }

  for (final bar in bars) {
    if (!bar.restOnly || bar.breakBefore != null) {
      flush();
    }
    if (bar.restOnly) {
      run.add(bar);
    } else {
      units.add(SingleBar(bar));
    }
  }
  flush();
  return units;
}

/// Everything a system's layout is a function of under one style and one
/// text measurer. Equal keys give equal systems, so a plan and an assembled
/// system are both reused by key.
///
/// Bars are compared by identity, because a BarLayout is replaced exactly when
/// its bar was laid out again. [carry] and [carryOut] are compared by value.
final class SystemKey {
  SystemKey({
    required this.units,
    required this.next,
    required this.width,
    required this.lead,
    required this.first,
    required this.last,
    required this.carry,
    required this.carryOut,
  });

  final List<BreakUnit> units;

  /// The first bar of the next system. The system ends with that bar's
  /// courtesy signatures, and an open lyric extender asks how that bar's
  /// lane starts. Null on the last system.
  final BarLayout? next;

  final double width;
  final SystemLead lead;

  /// The first system prints full part names and has its own indent.
  final bool first;

  /// The last system may stay ragged (`justifyLastSystemFrom`).
  final bool last;

  /// The lyric hyphens and extenders open at the system's start.
  final LyricCarry carry;

  /// The lyric hyphens and extenders open at the system's end, which is the
  /// next system's [carry]. None on the last system, which carries nothing
  /// on. A final melisma's extender reads [next] instead.
  final LyricCarry carryOut;

  @override
  bool operator ==(Object other) =>
      other is SystemKey &&
      other.width == width &&
      other.first == first &&
      other.last == last &&
      identical(other.lead, lead) &&
      identical(other.next, next) &&
      other.carry == carry &&
      other.carryOut == carryOut &&
      other.units.length == units.length &&
      Iterable<int>.generate(
        units.length,
      ).every((i) => other.units[i] == units[i]);

  /// Computed once. A key is hashed several times an update, by the plans
  /// kept from the last break, the delta and the memo of assembled systems.
  @override
  late final int hashCode = Object.hash(
    width,
    first,
    last,
    identityHashCode(next),
    carry,
    carryOut,
    Object.hashAll(units),
  );
}

/// One staff of a planned system.
typedef PlannedStaff = ({
  /// y of the staff's top line in system space.
  double top,

  /// y where the staff's lyric rows start, below everything else the
  /// staff's bars reach.
  double lyricsFrom,
  List<LyricRow> rows,
});

/// A system decided and not yet assembled.
///
/// Invariant: assembly draws nothing outside the box from (0, 0) to
/// ([width], [height]). Every bar's reach holds the room of each piece
/// that crosses it, the rows hold every lyric lane, and the pieces drawn
/// at system time clamp to that room. The sheet stacks systems by
/// [height] alone, so a breach would overlap the next system.
final class SystemPlan {
  const SystemPlan({
    required this.key,
    required this.width,
    required this.stretch,
    required this.staves,
    required this.height,
    required this.labelAt,
  });

  final SystemKey key;

  /// The sheet's width, or the width of the system's rods when one bar
  /// alone is wider than the sheet.
  final double width;

  /// The one factor every spring of the system is scaled by.
  final double stretch;

  final List<PlannedStaff> staves;
  final double height;

  /// Where the bar number's baseline starts, in system space. The number
  /// itself is not here, so inserting a bar renumbers later systems
  /// without changing a plan.
  final SpPoint labelAt;

  /// The system's bars in score order.
  List<MeasureId> get bars => [
    for (final unit in key.units)
      for (final bar in unit.bars) bar.measure,
  ];

  List<double> get staffTops => [for (final staff in staves) staff.top];

  /// x where the staves start.
  double get indent => key.first ? key.lead.firstIndent : key.lead.indent;
}

/// The result of line breaking, kept to resume from.
typedef Breaks = ({
  List<BreakUnit> units,

  /// The first bar of each system, in score order.
  List<MeasureId> starts,
  List<SystemPlan> plans,
  double width,
  SystemLead lead,
});

/// Breaks [bars] into systems [width] wide and plans each one.
///
/// Greedy first-fit. A system takes units while its natural width (see
/// [BarWidths]) fits, and a unit with `breakBefore` starts a new system (a
/// page break is a system break, since the view has no pages). A unit
/// wider than the sheet on its own gets a system to itself and is
/// compressed to its rods.
///
/// Greedy is chosen over optimal breaking for stability. Where a system
/// starts depends only on where the one before it started and on the
/// widths from there. So an edit never moves an earlier system, and a
/// re-run can stop early.
///
/// With [previous] at the same width and lead, breaking resumes:
/// 1. Find the dirty units (see [_dirty]). With none, the old starts
///    stand, as the same list.
/// 2. Keep every old system before the one that holds the unit before the
///    first dirty unit, and resume greedy at that system's start. That
///    system is the earliest one whose end decision read a dirty unit.
/// 3. Stop at the first new start that lies past the last dirty unit and
///    was an old start. From there the units, their widths and the start
///    are what they were, so greedy would repeat the old starts.
///
/// Plans are then made per system and reused by key, whether or not the
/// starts were resumed.
///
/// [previous] must come from the same [style] and [text]. A key holds
/// neither, so a plan made under another style would be taken for this one.
Breaks breakSystems({
  required List<BarLayout> bars,
  required double width,
  required SystemLead lead,
  required EngravingStyle style,
  required TextMeasurer text,
  Breaks? previous,
}) {
  final units = foldBars(bars, style);
  final resumable =
      previous != null &&
      previous.width == width &&
      identical(previous.lead, lead);
  final starts = _starts(
    units,
    width: width,
    lead: lead,
    previous: resumable ? previous : null,
  );

  final old = {
    for (final plan in previous?.plans ?? const <SystemPlan>[]) plan.key: plan,
  };
  final indexOf = {
    for (final (index, unit) in units.indexed) unit.first.measure: index,
  };
  final bounds = [for (final start in starts) indexOf[start]!, units.length];

  // What is open at each system's edge. One pass forward folds what every
  // bar leaves open. One pass backward finds the lanes whose next syllable
  // joins a word, so a hyphen nothing joins is carried nowhere, and drops
  // an extender the system's first bar does not hold.
  final open = <LyricCarry>[LyricCarry.none];
  for (var system = 0; system < starts.length - 1; system++) {
    var carry = open.last;
    for (final unit in units.getRange(bounds[system], bounds[system + 1])) {
      for (final bar in unit.bars) {
        carry = bar.lyrics.after(carry);
      }
    }
    open.add(carry);
  }
  final edges = List.filled(starts.length + 1, LyricCarry.none);
  final ahead = <LyricLane>{};
  for (var system = starts.length - 1; system >= 0; system--) {
    for (var unit = bounds[system + 1] - 1; unit >= bounds[system]; unit--) {
      for (final bar in units[unit].bars.reversed) {
        for (final MapEntry(key: lane, value: here)
            in bar.lyrics.lanes.entries) {
          if (here.joins) {
            ahead.add(lane);
          } else {
            ahead.remove(lane);
          }
        }
      }
    }
    edges[system] = open[system].closing(
      ahead,
      units[bounds[system]].first.lyrics,
    );
  }

  final plans = <SystemPlan>[];
  for (var system = 0; system < starts.length; system++) {
    final to = bounds[system + 1];
    final key = SystemKey(
      units: units.sublist(bounds[system], to),
      next: to < units.length ? units[to].first : null,
      width: width,
      lead: lead,
      first: system == 0,
      last: to == units.length,
      carry: edges[system],
      carryOut: edges[system + 1],
    );
    plans.add(old[key] ?? planSystem(key, style, text));
  }
  return (units: units, starts: starts, plans: plans, width: width, lead: lead);
}

List<MeasureId> _starts(
  List<BreakUnit> units, {
  required double width,
  required SystemLead lead,
  required Breaks? previous,
}) {
  final starts = <MeasureId>[];
  var start = 0;
  var lastDirty = units.length;
  final old = previous?.starts ?? const <MeasureId>[];
  var oldStarts = const <MeasureId>{};
  if (previous != null) {
    final dirty = _dirty(previous.units, units);
    if (dirty.isEmpty) {
      return previous.starts;
    }
    // Units before the first dirty one are the old units, index for index,
    // because a clean unit has the predecessor it had.
    final oldIndex = {
      for (final (index, unit) in previous.units.indexed)
        unit.first.measure: index,
    };
    final before = math.max(dirty.first - 1, 0);
    final kept = [...old.takeWhile((id) => oldIndex[id]! <= before)];
    starts.addAll(kept.take(kept.length - 1));
    start = oldIndex[kept.last]!;
    lastDirty = dirty.last;
    oldStarts = old.toSet();
  }
  while (start < units.length) {
    final id = units[start].first.measure;
    if (start > lastDirty && oldStarts.contains(id)) {
      starts.addAll(old.skipWhile((was) => was != id));
      break;
    }
    starts.add(id);
    final room = width - (start == 0 ? lead.firstIndent : lead.indent);
    start = _endOf(units, start, room) + 1;
  }
  return starts;
}

/// The index of the last unit of the system that starts at [start].
///
/// The first unit is taken whatever its width. Each later unit is taken
/// when the system still fits with it as the last one, which counts the
/// courtesy of the unit after it.
int _endOf(List<BreakUnit> units, int start, double room) {
  var used = units[start].widths.systemHead + units[start].widths.body;
  var end = start;
  while (end + 1 < units.length) {
    final next = units[end + 1];
    if (next.breakBefore != null) {
      break;
    }
    final grown = used + next.widths.inlineHead + next.widths.body;
    if (grown + _courtesyAfter(units, end + 1) > room) {
      break;
    }
    used = grown;
    end++;
  }
  return end;
}

double _courtesyAfter(List<BreakUnit> units, int index) =>
    index + 1 < units.length ? units[index + 1].widths.courtesy : 0;

/// The indices in [fresh] of the units whose part in line breaking
/// changed, ascending.
///
/// A unit is clean when [old] has a unit starting on the same bar with the
/// same last bar, widths and `breakBefore`, the same unit before it, the
/// same unit after it, and the same courtesy after it. The decision where
/// a system ends reads its own units, the unit after its end, and the
/// courtesy of the unit after that. With the courtesy counted against the
/// unit before it, a system reads dirt from no unit past the one after its
/// end. That is what makes the resume point in [breakSystems] exact.
///
/// Widths are compared by value, so a bar laid out again at the same
/// widths is clean and the breaks stand.
List<int> _dirty(List<BreakUnit> old, List<BreakUnit> fresh) {
  final oldIndex = {
    for (final (index, unit) in old.indexed) unit.first.measure: index,
  };
  MeasureId? idAt(List<BreakUnit> units, int index) =>
      0 <= index && index < units.length ? units[index].first.measure : null;
  return [
    for (final (index, unit) in fresh.indexed)
      if (switch (oldIndex[unit.first.measure]) {
        null => true,
        final was =>
          old[was].last.measure != unit.last.measure ||
              old[was].widths != unit.widths ||
              old[was].breakBefore != unit.breakBefore ||
              idAt(old, was - 1) != idAt(fresh, index - 1) ||
              idAt(old, was + 1) != idAt(fresh, index + 1) ||
              _courtesyAfter(old, was) != _courtesyAfter(fresh, index),
      })
        index,
  ];
}

/// The bars of the volta bracket over the first bar of [units], as
/// `placeVoltas` joins them. Empty when that bar is under no volta.
Iterable<BarLayout> _firstBracket(List<BreakUnit> units) sync* {
  if (units.first is! SingleBar) {
    return;
  }
  for (final unit in units) {
    if (unit is! SingleBar) {
      continue;
    }
    final volta = unit.bar.volta;
    if (volta == null || (volta.starts && !identical(unit, units.first))) {
      return;
    }
    yield unit.bar;
  }
}

/// Plans the system of [key]. Its stretch comes from the slices, and its staff
/// tops and height from the bars' reach. Nothing is drawn.
SystemPlan planSystem(SystemKey key, EngravingStyle style, TextMeasurer text) {
  final units = key.units;
  final next = key.next;
  final indent = key.first ? key.lead.firstIndent : key.lead.indent;
  var fixed =
      indent + units.first.widths.systemHead + (next?.widths.courtesy ?? 0);
  for (final unit in units) {
    fixed += unit.lead;
  }
  for (final unit in units.skip(1)) {
    fixed += unit.widths.inlineHead;
  }
  final slices = [for (final unit in units) ...unit.slices];
  final room = key.width - fixed;
  final fill = stretchFor(slices, room);
  final ragged =
      key.last &&
      fixed + naturalWidth(slices) < key.width * style.justifyLastSystemFrom;

  final number = text.measure('0', style.specOf(TextRole.barNumber));
  final numberRoom = style.barNumbers ? number.ascent + number.descent : 0.0;
  final lyrics = [
    for (final unit in units)
      for (final bar in unit.bars) bar.lyrics,
  ];
  final reaches = <({double above, double below, List<LyricRow> rows})>[];
  var numberRise = 0.0;
  for (final (index, staff) in units.first.staves.indexed) {
    final courtesy = next == null
        ? (above: 0.0, below: 0.0)
        : headReach([
            next.heads.courtesy.before,
            next.heads.courtesy.after,
          ], index);
    // A staff's outer lines are ink too. Half a line lies outside the staff
    // on each side, and the band holds it like any other reach.
    final line = style.font.defaults.staffLineThickness / 2;
    var above = math.max(courtesy.above, line);
    var below = math.max(courtesy.below, line);
    for (final unit in units) {
      above = math.max(above, unit.staves[index].above);
      below = math.max(below, unit.staves[index].below);
    }
    if (index == 0) {
      // The bar number sits above whatever the first bar has over the top
      // staff, and takes its room from the system like any other mark. A
      // volta bracket over that bar is as high as its highest bar here.
      final under = _firstBracket(units).fold(
        units.first.staves[index].above,
        (under, bar) => math.max(under, bar.staves[index].above),
      );
      above = math.max(above, under + numberRoom);
      numberRise = under + number.descent;
    }
    reaches.add((
      above: above,
      below: below,
      rows: lyricRows(lyrics, key.carry, staff.staff, style, text),
    ));
  }
  // A part's name is centred on its staves. One taller than they are reaches
  // past them by the same amount at each end, and takes that room too. It
  // stands left of the staves, so the lyric rows under the last staff are
  // part of the room it has below.
  for (final part in key.lead.parts) {
    final name = part.nameOn(first: key.first);
    if (name == null) {
      continue;
    }
    var height = staffHeight;
    for (var index = part.firstStaff; index < part.lastStaff; index++) {
      height +=
          reaches[index].below +
          lyricRoom(reaches[index].rows, style) +
          style.staffGap +
          reaches[index + 1].above +
          staffHeight;
    }
    final past = (name.extent.ascent + name.extent.descent - height) / 2;
    final top = reaches[part.firstStaff];
    reaches[part.firstStaff] = (
      above: math.max(top.above, past),
      below: top.below,
      rows: top.rows,
    );
    final bottom = reaches[part.lastStaff];
    reaches[part.lastStaff] = (
      above: bottom.above,
      below: math.max(bottom.below, past - lyricRoom(bottom.rows, style)),
      rows: bottom.rows,
    );
  }
  final staves = <PlannedStaff>[];
  var y = 0.0;
  for (final (index, reach) in reaches.indexed) {
    final top = y + (index == 0 ? 0 : style.staffGap) + reach.above;
    final lyricsFrom = top + staffHeight + reach.below;
    staves.add((top: top, lyricsFrom: lyricsFrom, rows: reach.rows));
    y = lyricsFrom + lyricRoom(reach.rows, style);
  }
  return SystemPlan(
    key: key,
    width: math.max(key.width, fixed + rodWidth(slices)),
    stretch: ragged ? math.min(fill, 1) : fill,
    staves: staves,
    height: y,
    labelAt: SpPoint(
      indent,
      staves.isEmpty ? 0 : staves.first.top - numberRise,
    ),
  );
}
