part of 'session.dart';

/// Time a ripple removes, from `from` up to `to`.
typedef _Cut = ({Length from, Length to});

/// How a ripple changes the time of the staves it moves, and where each
/// time lies after it. Times are counted from the start of one bar: the
/// edit's bar for the caller, the section's first bar once [from] has
/// moved it there.
sealed class _Shift {
  const _Shift();

  /// This shift counted from [origin] earlier.
  _Shift from(Length origin);

  /// Where [time] lies after the shift. Null inside removed time.
  Length? moved(Length time);

  /// Where [time] lies after the shift, removed time at the place it was
  /// removed from.
  Length land(Length time);

  /// [items] after the shift. A chord that removed time makes shorter is
  /// entered in [shortened].
  List<_Placed> voice(
    List<_Placed> items,
    VoiceSlot slot,
    MeasureId edited,
    _Ids ids,
    Set<EventId> shortened,
  );
}

/// [by] of time added at [at].
final class _Grow extends _Shift {
  const _Grow({required this.at, required this.by});

  final Length at;
  final Length by;

  @override
  _Grow from(Length origin) => _Grow(at: origin + at, by: by);

  @override
  Length moved(Length time) => time < at ? time : time + by;

  @override
  Length land(Length time) => moved(time);

  @override
  List<_Placed> voice(
    List<_Placed> items,
    VoiceSlot slot,
    MeasureId edited,
    _Ids ids,
    Set<EventId> shortened,
  ) => _grown(items, at, by, slot, edited, ids);
}

/// The time of [cuts] removed, every cut at once. The rests and gaps that
/// the first cut leaves at the end of a voice stay as written, unless
/// [clearing].
final class _Collapse extends _Shift {
  _Collapse(this.cuts, {this.clearing = false}) {
    var gone = Length.zero;
    for (final (i, cut) in cuts.indexed) {
      assert(
        cut.from < cut.to && (i == 0 || cuts[i - 1].to <= cut.from),
        'cuts ascend and do not overlap',
      );
      _gone.add(gone);
      gone += cut.to - cut.from;
    }
  }

  /// Whether every rest and gap at the end of a voice goes.
  final bool clearing;
  final List<_Cut> cuts;

  /// The time removed before each cut.
  final _gone = <Length>[];

  @override
  _Collapse from(Length origin) => _Collapse([
    for (final cut in cuts) (from: origin + cut.from, to: origin + cut.to),
  ], clearing: clearing);

  /// The last cut that starts at or before [time]. -1 when none does.
  int _cutAt(Length time) {
    var low = 0;
    var high = cuts.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (cuts[middle].from <= time) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }

  /// The cut that removes [time]. Null when none does.
  int? cutOver(Length time) {
    final i = _cutAt(time);
    return i >= 0 && time < cuts[i].to ? i : null;
  }

  /// Whether a cut removes any of the time from [from] up to [to].
  bool cutsInto(Length from, Length to) {
    final i = _cutAt(from);
    return (i >= 0 && from < cuts[i].to) ||
        (i + 1 < cuts.length && cuts[i + 1].from < to);
  }

  @override
  Length? moved(Length time) {
    final i = _cutAt(time);
    if (i < 0) {
      return time;
    }
    final cut = cuts[i];
    return time < cut.to ? null : time - _gone[i] - (cut.to - cut.from);
  }

  @override
  Length land(Length time) => switch (cutOver(time)) {
    final i? => cuts[i].from - _gone[i],
    null => moved(time)!,
  };

  /// Whether the cuts carry music across the barline at [barEnd]: whether
  /// the first of [starts], the ascending times at which music the cuts
  /// leave starts, that is at or after [barEnd] lands before it.
  bool crosses(List<Length> starts, Length barEnd) {
    var low = 0;
    var high = starts.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (starts[middle] < barEnd) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < starts.length && land(starts[low]) < barEnd;
  }

  /// Where the music of [items] ends once the cuts are closed, counted in
  /// time before the cuts: the end of the last item that is no rest or gap
  /// and that no cut removes whole. Marks in [hit] each cut that takes time
  /// from such an item, and adds to [starts] the start of each such item
  /// that stays.
  Length musicEnd(List<_Placed> items, List<bool> hit, List<Length> starts) {
    var end = Length.zero;
    var time = Length.zero;
    var first = 0;
    for (final item in items) {
      final start = time;
      time += item.span;
      while (first < cuts.length && cuts[first].to <= start) {
        first++;
      }
      if (_elastic(item.item)) {
        continue;
      }
      for (var i = first; i < cuts.length && cuts[i].from < time; i++) {
        hit[i] = true;
      }
      final i = _cutAt(start);
      if (i < 0 || time > cuts[i].to) {
        end = time;
        starts.add(start);
      }
    }
    return end;
  }

  /// This collapse without the cuts that change nothing: a cut that takes
  /// time from no music and no direction ([hit]) and that has no music after
  /// it ([musicEnd]) and no kept direction or clef change at or after it
  /// ([lastMark]). The last cut stays all the same when the section's rests
  /// are not written as a re-bar writes them ([refills]), because closing it
  /// rewrites them. A cut left out before the first one kept still makes
  /// every voice drop the rests at its end, as closing it after the others
  /// would. Null when no cut is left.
  _Collapse? changing(
    List<bool> hit,
    Length musicEnd,
    Length? lastMark, {
    required bool Function() refills,
  }) {
    bool changes(int i) =>
        hit[i] ||
        cuts[i].from < musicEnd ||
        (lastMark != null && cuts[i].from <= lastMark);
    final last = cuts.length - 1;
    final kept = [
      for (final (i, cut) in cuts.indexed)
        if (changes(i) || (i == last && refills())) cut,
    ];
    return kept.isEmpty
        ? null
        : kept.length == cuts.length
        ? this
        : _Collapse(kept, clearing: clearing || !changes(0));
  }

  /// [items] without the time of the cuts. Each item loses its overlap with
  /// them, and an item inside one goes. Rests and gaps left at the end of
  /// the voice go, so the time after the music is filled as a re-bar fills
  /// it. The ones before music that only the first cut removes stay, as
  /// closing that cut after the others leaves them.
  @override
  List<_Placed> voice(
    List<_Placed> items,
    VoiceSlot slot,
    MeasureId edited,
    _Ids ids,
    Set<EventId> shortened,
  ) {
    final out = <_Placed>[];
    final starts = <Length>[];
    var tail = Length.zero;
    var time = Length.zero;
    var first = 0;
    for (final item in items) {
      final start = time;
      time += item.span;
      while (first < cuts.length && cuts[first].to <= start) {
        first++;
      }
      var overlap = Length.zero;
      var later = Length.zero;
      for (var i = first; i < cuts.length && cuts[i].from < time; i++) {
        final cut = cuts[i];
        final taken =
            (time < cut.to ? time : cut.to) -
            (start > cut.from ? start : cut.from);
        overlap += taken;
        if (i > 0) {
          later += taken;
        }
      }
      if (!_elastic(item.item) && later < item.span) {
        tail = time;
      }
      if (!overlap.isPositive) {
        out.add(item);
      } else if (overlap < item.span) {
        if (item.item case Tuplet(:final id)) {
          throw _Refuse(WouldSplitTuplet(id, item.origin));
        }
        if (item.item case ChordEvent(:final id)) {
          shortened.add(id);
        }
        out.add((
          item: item.item,
          span: item.span - overlap,
          origin: item.origin,
        ));
      } else {
        continue;
      }
      starts.add(start);
    }
    while (out.isNotEmpty &&
        _elastic(out.last.item) &&
        (clearing || starts.last >= tail)) {
      out.removeLast();
      starts.removeLast();
    }
    return out;
  }
}

/// A cut an erase closed in one section, counted from bar `bar`, its first.
/// `end` is the bar after the section.
typedef _SectionCut = ({int bar, int end, _Cut cut});

/// A range selection through an erase of items that closes cuts on several
/// groups of staves. The range follows each group it reaches through that
/// group's cuts, and [_rangeOver] joins the spans this leaves.
final class _RangeFollower {
  _RangeFollower(this._before, this._selection);

  final Score _before;
  final Selection _selection;

  /// The cuts of each group of staves, under the group's first staff.
  final _cuts = <StaffId, List<_SectionCut>>{};
  final _moved = <StaffId>{};

  /// Takes the cuts that [staves] closed, counted from bar [bar], the first
  /// of their section.
  void close(List<StaffId> staves, int bar, List<_Cut> cuts) {
    if (_selection case RangeSelection(:final top, :final bottom)
        when cuts.isNotEmpty &&
            _reach(_before, top, bottom, staves.toSet()) != _Reach.none) {
      final (_, end) = _sectionAround(_before, bar);
      (_cuts[staves.first] ??= []).addAll([
        for (final cut in cuts) (bar: bar, end: end, cut: cut),
      ]);
      _moved.addAll(staves);
    }
  }

  /// The selection in [after], or null when no cut moved it.
  Selection? followed(Score after) {
    final selection = _selection;
    if (selection is! RangeSelection || _cuts.isEmpty) {
      return null;
    }
    final RangeSelection(:from, :to, :top, :bottom) = selection;
    final held = !_before.stavesBetween(top, bottom)!.every(_moved.contains);
    return _rangeOver(after, selection, [
      if (held) (from, to),
      for (final cuts in _cuts.values) ?_pulled(after, selection, cuts),
    ]);
  }

  /// [range] in [after] once [cuts], those of one group of staves, are
  /// closed. Null when they leave it no time.
  (ScorePoint, ScorePoint)? _pulled(
    Score after,
    RangeSelection range,
    List<_SectionCut> cuts,
  ) {
    cuts.sort(
      (x, y) =>
          x.bar != y.bar ? y.bar - x.bar : y.cut.from.compareTo(x.cut.from),
    );
    final measures = _before.measures;
    (int, Length) at(ScorePoint point) =>
        (_before.indexOf(point.measure), Moment.zero.until(point.offset));
    var (fromBar, from) = at(range.from);
    var (toBar, to) = at(range.to);
    for (final (:bar, :end, :cut) in cuts) {
      final length = measures[bar].length;
      (int, Length) pulled((int, Length) point) {
        final (index, offset) = point;
        if (index < bar || index >= end) {
          return point;
        }
        final time = length * Fraction(index - bar) + offset;
        final landed = time < cut.from
            ? time
            : time < cut.to
            ? cut.from
            : time - (cut.to - cut.from);
        final (k, moved) = _barAt(landed, length);
        return bar + k < end
            ? (bar + k, Moment.zero.until(moved))
            : (end - 1, length);
      }

      (fromBar, from) = pulled((fromBar, from));
      (toBar, to) = pulled((toBar, to));
      if (fromBar > toBar || (fromBar == toBar && from >= to)) {
        return null;
      }
    }
    return (
      ScorePoint(after.measures[fromBar].id, Moment.zero + from),
      ScorePoint(after.measures[toBar].id, Moment.zero + to),
    );
  }
}

/// How much of a range a ripple moves: none of its staves, some of them
/// while the others hold still, or all of them.
enum _Reach { none, some, all }

/// How many of the staves from [top] to [bottom], in system order, are
/// among [staves].
_Reach _reach(Score score, StaffId top, StaffId bottom, Set<StaffId> staves) {
  final range = score.stavesBetween(top, bottom);
  if (range == null || !range.any(staves.contains)) {
    return _Reach.none;
  }
  return range.every(staves.contains) ? _Reach.all : _Reach.some;
}

/// [range] in [score] after a ripple left it [spans]: one span for each
/// group of its staves that moved together, and its own span when one of
/// its staves held still. The range runs from the earliest start to the
/// latest end of the spans that hold time, so it keeps every event that
/// stayed in place and takes in the music that moved. No selection when
/// no span holds time.
Selection _rangeOver(
  Score score,
  RangeSelection range,
  List<(ScorePoint, ScorePoint)> spans,
) {
  final timed = [
    for (final span in spans)
      if (score.compare(span.$1, span.$2) < 0) span,
  ];
  if (timed.isEmpty) {
    return const Selection.none();
  }
  var (from, to) = timed.first;
  for (final (start, stop) in timed.skip(1)) {
    if (score.compare(start, from) < 0) {
      from = start;
    }
    if (score.compare(stop, to) > 0) {
      to = stop;
    }
  }
  return RangeSelection(
    from: from,
    to: to,
    top: range.top,
    bottom: range.bottom,
  );
}

/// The time [events] take in the staves that [ripple] moves with each, as
/// the cuts of each section, counted from the section's first bar and
/// ascending. Events that move together and overlap in time make one cut.
List<({List<StaffId> staves, int bar, List<_Cut> cuts})> _sectionCuts(
  Score score,
  Ripple ripple,
  List<TimedEvent> events,
) {
  final scopes = <StaffId, List<StaffId>>{};
  final spans = <(StaffId, int), List<_Cut>>{};
  for (final timed in events) {
    if (timed.tuplets.isNotEmpty) {
      throw _Refuse(WouldSplitTuplet(timed.tuplets.last, timed.ref.measure));
    }
    final from = Moment.zero.until(timed.onset);
    final staves = _rippledStaves(score, timed.ref.staff, ripple);
    scopes[staves.first] = staves;
    final key = (staves.first, score.indexOf(timed.ref.measure));
    (spans[key] ??= []).add((from: from, to: from + timed.duration));
  }
  final measures = score.measures;
  final sections = <(StaffId, int), List<_Cut>>{};
  var start = 0;
  var end = 0;
  final order = {
    for (final (i, staff) in score.staves.indexed) staff.id: i,
  };
  final keys = spans.keys.toList()
    ..sort(
      (x, y) => x.$2 != y.$2 ? x.$2 - y.$2 : order[x.$1]! - order[y.$1]!,
    );
  for (final key in keys) {
    final (first, bar) = key;
    if (bar >= end) {
      (start, end) = _sectionAround(score, bar);
    }
    final origin = measures[start].length * Fraction(bar - start);
    final cuts = sections[(first, start)] ??= [];
    final list = spans[key]!..sort((x, y) => x.from.compareTo(y.from));
    var (:from, :to) = list.first;
    for (final span in list.skip(1)) {
      if (span.from > to) {
        cuts.add((from: origin + from, to: origin + to));
        from = span.from;
      }
      if (span.to > to) {
        to = span.to;
      }
    }
    cuts.add((from: origin + from, to: origin + to));
  }
  return [
    for (final MapEntry(key: (first, bar), value: cuts) in sections.entries)
      (staves: scopes[first]!, bar: bar, cuts: cuts),
  ];
}

/// When each direction and each clef change of [staves] in [bars] falls,
/// counted from the first bar. A bar that opens in another clef than the bar
/// before it ends in holds a change at its start.
Iterable<({Length at, bool direction})> _marks(
  List<MeasureColumn> bars,
  Set<StaffId> staves,
) sync* {
  final length = bars.first.length;
  for (final (i, column) in bars.indexed) {
    final start = length * Fraction(i);
    for (final staff in column.staves) {
      if (staves.contains(staff.staff)) {
        if (i > 0 && staff.clef != bars[i - 1].staff(staff.staff).clefAtEnd) {
          yield (at: start, direction: false);
        }
        for (final change in staff.clefChanges) {
          yield (
            at: start + Moment.zero.until(change.offset),
            direction: false,
          );
        }
        for (final mark in staff.directions) {
          yield (at: start + Moment.zero.until(mark.offset), direction: true);
        }
      }
    }
  }
}

/// Where the last event [spanner] covers ends in [score]: the event its
/// last end attaches to for a slur, glissando or trill line, and the
/// voice-one event its last point falls in for any other line.
ScorePoint _lastCoveredEnd(Score score, Spanner spanner) => ScorePoint(
  spanner.last.measure,
  switch (spanner.kind.reach) {
    SpannerReach.events => switch (score.anchorOf(spanner, last: true)!) {
      final anchor => anchor.onset + anchor.duration,
    },
    SpannerReach.time => score.lineEnd(spanner),
  },
);
