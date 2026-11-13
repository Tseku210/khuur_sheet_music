part of 'session.dart';

/// A change to the time of the staves a ripple moves, counted from the start
/// of the edit's bar: `by` is added at `at` when positive, and the time from
/// `at` for minus `by` is removed when negative.
typedef _Shift = ({Length at, Length by});

/// The edited voice's own change, counted from the start of the edit's
/// bar: its music from `from` to `to` replaced by `music`. The music after
/// `to` moves by the [_Shift] it comes with.
typedef _Splice = ({
  StaffId staff,
  VoiceSlot slot,
  Length from,
  Length to,
  List<Content> music,
});

/// What a ripple left: the score, the cursor and selection it moved (null
/// keeps the session's), where its times now lie, and the bar after its
/// section.
final class _Rippled {
  const _Rippled(
    this.score,
    this.cursor,
    this.selection,
    this.place,
    this.next,
  );

  final Score score;
  final VoicePoint? cursor;
  final Selection? selection;

  /// Where a time counted from the start of the edit's bar now lies. Null
  /// at or past the end of the section.
  final ScorePoint? Function(Length time) place;

  /// The bar after the section. Null at the end of the score.
  final MeasureColumn? next;
}

/// The staves that [ripple] moves for an edit on [staff], the staff that
/// stands for them first.
List<StaffId> _rippledStaves(Score score, StaffId staff, Ripple ripple) =>
    switch (ripple) {
      Ripple.none => throw StateError('Ripple.none moves nothing'),
      Ripple.staff => [staff],
      Ripple.part => [for (final s in score.partOf(staff).staves) s.id],
    };

/// Enters [event] at [at], pushing the later music that [ripple] moves by
/// the time the rests at [at] cannot give it.
_Result _enterRippled(
  Score score,
  VoicePoint at,
  Event event,
  _Ids ids,
  Overfill overfill,
  Ripple ripple, {
  required bool appendBar,
  required EditSession session,
}) {
  if (!score.contains(at.at.measure) ||
      !score.staves.any((staff) => staff.id == at.staff)) {
    throw _Refuse(StaleReference(at));
  }
  final bar = score.indexOf(at.at.measure);
  final column = score.measures[bar];
  final offset = at.at.offset;
  if (offset.isNegative || offset >= _barEnd(column)) {
    throw _Refuse(OutsideMeasure(at.at));
  }
  final span = event.span;
  final items =
      column.staff(at.staff).voice(at.voice)?.items ??
      Seq([Gap(column.length)]);
  final Length rests;
  if (_tupletAt(items, offset) case final inside?) {
    if (_restsIn(inside.tuplet, inside.at, span)) {
      return _enter(score, at, event, ids, overfill, appendBar: appendBar);
    }
    if (!inside.at.isZero) {
      throw _Refuse(WouldSplitTuplet(inside.tuplet.id, column.id));
    }
    rests = Length.zero;
  } else {
    _check(startProblem(offset));
    final (_, end) = _sectionAround(score.measures, bar);
    rests = _restsFrom(score, at, bar, end, span);
    if (rests >= span) {
      return _enter(score, at, event, ids, overfill, appendBar: appendBar);
    }
  }
  final room = offset.until(_barEnd(column));
  if (overfill == Overfill.refuse && span > room) {
    throw _Refuse(WouldCrossBarline(column.id, span - room));
  }
  final from = Moment.zero.until(offset);
  final rippled = _ripple(
    score,
    ids,
    staves: _rippledStaves(score, at.staff, ripple),
    bar: bar,
    shift: (at: from + rests, by: span - rests),
    cursor: session.cursor,
    selection: session.selection,
    splice: (
      staff: at.staff,
      slot: at.voice,
      from: from,
      to: from + rests,
      music: [event],
    ),
  );
  var entered = _untieInto(rippled.score, at, _tones(event));
  VoicePoint cursorAt(ScorePoint point) =>
      VoicePoint(staff: at.staff, voice: at.voice, at: point);
  final VoicePoint cursor;
  if (rippled.place(from + span) case final end?) {
    cursor = cursorAt(end);
  } else if (rippled.next case final next?) {
    cursor = cursorAt(ScorePoint(next.id, Moment.zero));
  } else if (appendBar) {
    final added = _barAfter(entered.measures.last, ids);
    entered = entered.copyWith(measures: entered.measures.append(added));
    cursor = cursorAt(ScorePoint(added.id, Moment.zero));
  } else {
    cursor = at;
  }
  return _Result(
    entered,
    cursor: cursor,
    selection: Selection.event(
      EventRef(measure: at.at.measure, staff: at.staff, id: event.id),
    ),
  );
}

/// Whether [tuplet], or the innermost tuplet in it that holds [at], has
/// only plain rests from [at] for [length] of its written time.
bool _restsIn(Tuplet tuplet, Moment at, Length length) {
  if (_tupletAt(tuplet.members, at) case final nested?) {
    return _restsIn(nested.tuplet, nested.at, length);
  }
  final end = at + length;
  var start = Moment.zero;
  for (final member in tuplet.members) {
    final stop = start + member.span;
    if (stop > at && start < end && !_elastic(member)) {
      return false;
    }
    start = stop;
  }
  return true;
}

/// How much plain rest and gap the voice of [at] holds from [at] up to its
/// next music, stopping once it reaches [cap] or bar [end].
Length _restsFrom(Score score, VoicePoint at, int bar, int end, Length cap) {
  var rests = Length.zero;
  for (var i = bar; i < end; i++) {
    final column = score.measures[i];
    final items =
        column.staff(at.staff).voice(at.voice)?.items ??
        Seq([Gap(column.length)]);
    var start = Moment.zero;
    for (final item in items) {
      final stop = start + item.span;
      if (i > bar || stop > at.at.offset) {
        if (!_elastic(item)) {
          return rests;
        }
        final from = i == bar && start < at.at.offset ? at.at.offset : start;
        rests += from.until(stop);
        if (rests >= cap) {
          return rests;
        }
      }
      start = stop;
    }
  }
  return rests;
}

/// Changes [ref]'s value and moves the later music that [ripple] moves by
/// the change.
_Result _setValueRippled(
  Score score,
  EventRef ref,
  NoteValue value,
  _Ids ids,
  Ripple ripple,
  EditSession session,
) {
  final timed = _target(score, ref);
  final by = value.length - timed.duration;
  if (by.isZero) {
    return _Result(_setValue(score, timed, value, ids));
  }
  if (timed.tuplets.isNotEmpty) {
    throw _Refuse(WouldSplitTuplet(timed.tuplets.last, timed.ref.measure));
  }
  final from = Moment.zero.until(timed.onset);
  final to = from + timed.duration;
  final rippled = _ripple(
    score,
    ids,
    staves: _rippledStaves(score, timed.ref.staff, ripple),
    bar: score.indexOf(timed.ref.measure),
    shift: (at: by.isPositive ? to : from + value.length, by: by),
    cursor: session.cursor,
    selection: session.selection,
    splice: (
      staff: timed.ref.staff,
      slot: timed.voice,
      from: from,
      to: to,
      music: [_piece(timed.event, value, ids, first: true, tied: false)],
    ),
  );
  return _Result(
    rippled.score,
    cursor: rippled.cursor,
    selection: rippled.selection,
  );
}

/// Deletes what [selection] holds and pulls the later music that [ripple]
/// moves back over each gap.
_Result _eraseRippled(
  Score score,
  Selection selection,
  _Ids ids,
  Ripple ripple,
  EditSession session,
) {
  var now = score;
  var cursor = session.cursor;
  Selection? selected;
  void remove(List<StaffId> staves, int bar, Length from, Length to) {
    final rippled = _ripple(
      now,
      ids,
      staves: staves,
      bar: bar,
      shift: (at: from, by: from - to),
      cursor: cursor,
      selection: selected ?? session.selection,
    );
    now = rippled.score;
    cursor = rippled.cursor ?? cursor;
    selected = rippled.selection ?? selected;
  }

  switch (selection) {
    case NoSelection():
      return _Result(score);
    case ItemSelection(:final items):
      final (:targets, :whole, :trimmed) = _picked(score, items);
      now = _retie(score, trimmed, {
        for (final MapEntry(key: id, value: timed) in targets.entries)
          if (!whole.contains(id))
            (score.indexOf(timed.ref.measure), timed.ref.staff),
      });
      for (final (:staves, :bar, :from, :to) in _gaps(score, ripple, [
        for (final id in whole) targets[id]!,
      ])) {
        remove(staves, bar, from, to);
      }
      return _Result(now, cursor: cursor, selection: selected);
    case final RangeSelection range:
      selected = const Selection.none();
      final (:staves, lanes: _, inRange: _) = _covers(score, range);
      final scopes = <StaffId, List<StaffId>>{};
      for (final staff in staves) {
        final scope = _rippledStaves(score, staff, ripple);
        scopes[scope.first] = scope;
      }
      final first = score.indexOf(range.from.measure);
      final last = score.indexOf(range.to.measure);
      for (final scope in scopes.values) {
        var bar = first;
        while (bar <= last) {
          final (_, end) = _sectionAround(now.measures, bar);
          final length = now.measures[bar].length;
          final from = bar == first
              ? Moment.zero.until(range.from.offset)
              : Length.zero;
          final to = last < end
              ? length * Fraction(last - bar) +
                    Moment.zero.until(range.to.offset)
              : length * Fraction(end - bar);
          if (to > from) {
            remove(scope, bar, from, to);
          }
          bar = end;
        }
      }
      return _Result(now, cursor: cursor, selection: selected);
  }
}

/// The time [events] take in the staves that [ripple] moves with each, as
/// gaps within one bar each, last first: a pull of a later gap leaves the
/// earlier ones where they were. Events that move together and overlap in
/// time make one gap.
List<({List<StaffId> staves, int bar, Length from, Length to})> _gaps(
  Score score,
  Ripple ripple,
  List<TimedEvent> events,
) {
  final scopes = <StaffId, List<StaffId>>{};
  final spans = <(StaffId, int), List<(Length, Length)>>{};
  for (final timed in events) {
    if (timed.tuplets.isNotEmpty) {
      throw _Refuse(WouldSplitTuplet(timed.tuplets.last, timed.ref.measure));
    }
    final from = Moment.zero.until(timed.onset);
    final staves = _rippledStaves(score, timed.ref.staff, ripple);
    scopes[staves.first] = staves;
    final key = (staves.first, score.indexOf(timed.ref.measure));
    (spans[key] ??= []).add((from, from + timed.duration));
  }
  final gaps = <({List<StaffId> staves, int bar, Length from, Length to})>[];
  for (final MapEntry(key: (first, bar), value: list) in spans.entries) {
    final staves = scopes[first]!;
    list.sort((x, y) => x.$1.compareTo(y.$1));
    var (from, to) = list.first;
    for (final (start, stop) in list.skip(1)) {
      if (start > to) {
        gaps.add((staves: staves, bar: bar, from: from, to: to));
        from = start;
      }
      if (stop > to) {
        to = stop;
      }
    }
    gaps.add((staves: staves, bar: bar, from: from, to: to));
  }
  return gaps..sort(
    (x, y) => x.bar != y.bar ? y.bar - x.bar : y.from.compareTo(x.from),
  );
}

/// The first bar and the bar after the last of the stretch around bar
/// [index] that a ripple moves music within: a section of [_sections],
/// also ended where the meter changes.
(int, int) _sectionAround(Seq<MeasureColumn> measures, int index) {
  bool ends(int i) =>
      _splits(measures[i - 1], measures[i]) ||
      measures[i - 1].meter != measures[i].meter;
  var start = index;
  while (start > 0 && !ends(start)) {
    start--;
  }
  var end = index + 1;
  while (end < measures.length && !ends(end)) {
    end++;
  }
  return (start, end);
}

/// [score] with the music of [staves] moved by [shift] through the section
/// that holds bar [bar], and the edited voice changed by [splice]. The
/// section grows by whole bars when the music no longer fits it, and every
/// other staff rests in the new bars. The cursor, a range selection and
/// spanner ends on [staves] follow the music.
_Rippled _ripple(
  Score score,
  _Ids ids, {
  required List<StaffId> staves,
  required int bar,
  required _Shift shift,
  required VoicePoint cursor,
  required Selection selection,
  _Splice? splice,
}) {
  final measures = score.measures;
  final (a, b) = _sectionAround(measures, bar);
  final old = [for (var i = a; i < b; i++) measures[i]];
  final first = old.first;
  final closing = old.last;
  final length = first.length;
  final origin = length * Fraction(bar - a);
  final at = origin + shift.at;
  final by = shift.by;
  final next = b < measures.length ? measures[b] : null;
  final moving = staves.toSet();
  final origins = <EventId, EventId>{};
  final edited = measures[bar].id;

  List<_Placed> moved(StaffId staff, VoiceSlot slot) {
    final items = [
      for (final (item, from) in _Stream(old, staff, slot).items)
        (item: item, span: item.span, origin: from),
    ];
    if (splice != null && splice.staff == staff && splice.slot == slot) {
      return _spliced(
        items,
        origin + splice.from,
        origin + splice.to,
        splice.music,
        slot,
        edited,
        ids,
        origins,
      );
    }
    return by.isNegative
        ? _shrunk(items, at, at - by)
        : _grown(items, at, by, slot, edited, ids);
  }

  final (count, voices) = _rippledVoices(old, moving, moved, ids, origins);

  final end = length * Fraction(count);

  /// Where [time] now lies. Null inside removed time.
  Length? movedTime(Length time) => switch (time) {
    _ when time < at => time,
    _ when by.isNegative && time < at - by => null,
    _ => time + by,
  };

  /// Where a mark at [time] goes: with its music, or where it was when no
  /// music carries it into the section. A mark in removed time goes.
  Length? kept(Length time) => switch (movedTime(time)) {
    final moved? when moved >= end => time,
    final moved => moved,
  };

  final cut = {
    for (final s in moving)
      s: _staffBars(
        old,
        s,
        count,
        length,
        voices,
        direction: kept,
        clef: (time) => kept(time) ?? at,
      ),
  };
  final grown = count > old.length;
  final untied = grown
      ? _untieAt(score, b - 1, _barEnd(closing), null).measures[b - 1]
      : closing;
  final bars = _rippledBars(old, untied, cut, count, ids);
  ScorePoint? place(Length time) {
    if (time >= end) {
      return null;
    }
    final (k, offset) = _barAt(time, length);
    return ScorePoint(bars[k].id, offset);
  }

  if (!grown && _same(bars, old)) {
    return _Rippled(score, null, null, (time) => place(origin + time), next);
  }
  final rebuilt = _retied(
    score,
    score.copyWith(measures: measures.replaceRange(a, b, bars)),
    moving,
    max(a - 1, 0),
    a + count,
    origins,
  );
  final index = {for (final (i, column) in old.indexed) column.id: i};
  Length? timeOf(ScorePoint point) => switch (index[point.measure]) {
    final i? => length * Fraction(i) + Moment.zero.until(point.offset),
    null => null,
  };
  final last = rebuilt.measures[a + count - 1];
  final sectionEnd = ScorePoint(last.id, _barEnd(last));

  ScorePoint? onset(ScorePoint point) => switch (timeOf(point)) {
    final time? => place(kept(time) ?? at)!,
    null => point,
  };
  ScorePoint close(ScorePoint point) => switch (timeOf(point)) {
    final time? => place(kept(time) ?? at) ?? sectionEnd,
    null => point,
  };
  final spanners = _moveSpanners(
    rebuilt,
    score.spanners,
    first: (spanner) =>
        moving.contains(spanner.staff) ? onset(spanner.first) : spanner.first,
    last: (spanner) {
      final time = moving.contains(spanner.staff) ? timeOf(spanner.last) : null;
      if (time == null) {
        return spanner.last;
      }
      return switch (movedTime(time)) {
        final moved? => place(moved >= end ? time : moved)!,
        null => _onsetBefore(rebuilt, spanner, place(at) ?? sectionEnd),
      };
    },
  );
  final followed = _follow(
    rebuilt,
    cursor,
    selection,
    onset: onset,
    close: close,
    movesCursor: moving.contains(cursor.staff),
    movesRange: switch (selection) {
      RangeSelection(:final top, :final bottom) => _reaches(
        score,
        top,
        bottom,
        moving,
      ),
      _ => false,
    },
  );
  return _Rippled(
    rebuilt.copyWith(spanners: spanners),
    followed.cursor,
    followed.selection,
    (time) => place(origin + time),
    next,
  );
}

/// How many bars the rippled section that held [old] needs, and the voices
/// of [staves] cut into that many bars, each voice's music given by [moved].
/// Each later piece of a split event is entered in [origins] under the
/// event it came from. Refused when an irregular bar would have to grow.
(int, List<(StaffId, VoiceSlot, List<List<VoiceItem>>)>) _rippledVoices(
  List<MeasureColumn> old,
  Set<StaffId> staves,
  List<_Placed> Function(StaffId staff, VoiceSlot slot) moved,
  _Ids ids,
  Map<EventId, EventId> origins,
) {
  final first = old.first;
  final length = first.length;
  final total = length * Fraction(old.length);
  final lanes = [
    for (final s in first.staves)
      if (staves.contains(s.staff))
        for (final slot in VoiceSlot.values)
          (s.staff, slot, _fitted(moved(s.staff, slot), total)),
  ];
  final longest = lanes
      .map((lane) => Length.sum(lane.$3.map((placed) => placed.span)))
      .reduce((x, y) => x > y ? x : y);
  final count = max(_ceil(longest / length), old.length);
  if (count > old.length && first.irregularLength != null) {
    throw _Refuse(WouldCrossBarline(first.id, longest - total));
  }
  final voices = [
    for (final (s, slot, items) in lanes)
      (
        s,
        slot,
        _cut(
          items,
          count,
          first.meter,
          ids,
          gaps: slot != VoiceSlot.one,
          length: length,
          origins: origins,
        ),
      ),
  ];
  return (count, voices);
}

/// The [count] bars of a rippled section that held [old], with [untied] in
/// place of its last bar and [cut] the new bars of each staff the ripple
/// moved. A bar whose staves did not change is kept as it was, and bars past
/// the old section are new, the last of them taking the section's closing
/// barline, repeat end and closing navigation.
List<MeasureColumn> _rippledBars(
  List<MeasureColumn> old,
  MeasureColumn untied,
  Map<StaffId, List<StaffMeasure>> cut,
  int count,
  _Ids ids,
) {
  final first = old.first;
  final closing = old.last;
  final length = first.length;
  final grown = count > old.length;
  MeasureColumn column(int k) {
    final base = k < old.length - 1
        ? old[k]
        : k == old.length - 1
        ? untied
        : null;
    final staves = [
      for (final s in first.staves)
        if (!cut.containsKey(s.staff))
          base?.staff(s.staff) ??
              _restStaff(s.staff, closing.staff(s.staff).clefAtEnd, length, ids)
        else if (base != null &&
            _sameStaff(base.staff(s.staff), cut[s.staff]![k]))
          base.staff(s.staff)
        else
          cut[s.staff]![k],
    ];
    if (base == null) {
      final last = k == count - 1;
      return MeasureColumn(
        id: ids.measure(),
        meter: first.meter,
        key: first.key,
        volta: first.volta,
        staves: Seq(staves),
        barline: last ? closing.barline : Barline.regular,
        repeatEnd: last ? closing.repeatEnd : null,
        navigation: Seq([
          if (last) ...closing.navigation.where((mark) => !mark.atBarStart),
        ]),
      );
    }
    var column = base;
    if (!_same(staves, base.staves)) {
      column = column.copyWith(staves: Seq(staves));
    }
    if (grown && k == old.length - 1) {
      column = column.copyWith(
        barline: Barline.regular,
        repeatEnd: () => null,
        navigation: Seq(base.navigation.where((mark) => mark.atBarStart)),
      );
    }
    return column;
  }

  return [for (var k = 0; k < count; k++) column(k)];
}

/// [cursor] and [selection] after the music under them moved: each start
/// goes through [onset], a range's end through [close], and a range that
/// is left empty becomes no selection. Null for what does not move: a
/// cursor when [movesCursor] is false or [onset] gives null, and any
/// selection that is not a range or whose range [movesRange] holds still.
({VoicePoint? cursor, Selection? selection}) _follow(
  Score moved,
  VoicePoint cursor,
  Selection selection, {
  required ScorePoint? Function(ScorePoint) onset,
  required ScorePoint Function(ScorePoint) close,
  bool movesCursor = true,
  bool movesRange = true,
}) {
  final at = movesCursor ? onset(cursor.at) : null;
  return (
    cursor: at == null
        ? null
        : VoicePoint(staff: cursor.staff, voice: cursor.voice, at: at),
    selection: switch (selection) {
      RangeSelection(:final from, :final to, :final top, :final bottom)
          when movesRange =>
        switch ((onset(from), close(to))) {
          (final start?, final stop) when moved.compare(start, stop) < 0 =>
            RangeSelection(from: start, to: stop, top: top, bottom: bottom),
          _ => const Selection.none(),
        },
      _ => null,
    },
  );
}

/// Whether the staves from [top] to [bottom], in system order, include one
/// of [staves].
bool _reaches(Score score, StaffId top, StaffId bottom, Set<StaffId> staves) =>
    score.stavesBetween(top, bottom)?.any(staves.contains) ?? false;

/// [items] with [music] in place of the time from [from] to [to]. An item
/// cut at [from] keeps its head before [music], and an item cut at [to]
/// moves its tail after it as a new item. A note's tail is entered in
/// [origins] under the note it came from. Blank time pads the voice up to
/// [from].
List<_Placed> _spliced(
  List<_Placed> items,
  Length from,
  Length to,
  List<Content> music,
  VoiceSlot slot,
  MeasureId origin,
  _Ids ids,
  Map<EventId, EventId> origins,
) {
  final out = <_Placed>[];
  var placed = false;
  void put() {
    if (!placed) {
      placed = true;
      out.addAll([
        for (final item in music) (item: item, span: item.span, origin: origin),
      ]);
    }
  }

  var time = Length.zero;
  for (final item in items) {
    final start = time;
    time += item.span;
    if (time <= from) {
      out.add(item);
    } else if (start >= to) {
      put();
      out.add(item);
    } else {
      if (item.item case Tuplet(:final id)) {
        throw _Refuse(WouldSplitTuplet(id, item.origin));
      }
      if (start < from) {
        out.add((item: item.item, span: from - start, origin: item.origin));
      }
      put();
      if (time > to) {
        out.add(_tail(item, time - to, ids, origins));
      }
    }
  }
  if (time < from) {
    out.add(_blank(from - time, slot, origin, ids));
  }
  put();
  return out;
}

/// The last [span] of [placed] as a new item of its kind.
_Placed _tail(
  _Placed placed,
  Length span,
  _Ids ids,
  Map<EventId, EventId> origins,
) {
  final item = switch (placed.item) {
    Gap() => Gap(span),
    MeasureRest() => MeasureRest(id: ids.event(), span: span),
    final ChordEvent chord => _piece(
      chord,
      chord.value,
      ids,
      first: false,
      tied: false,
    ),
    final RestEvent rest => _piece(
      rest,
      rest.value,
      ids,
      first: false,
      tied: false,
    ),
    Tuplet() => throw StateError('a tuplet is never cut'),
  };
  if ((placed.item, item) case (ChordEvent(:final id), final Event piece)) {
    origins[piece.id] = id;
  }
  return (item: item, span: span, origin: placed.origin);
}

/// [items] with [by] of blank time added at [at]. An item that sounds
/// across [at] becomes [by] longer instead.
List<_Placed> _grown(
  List<_Placed> items,
  Length at,
  Length by,
  VoiceSlot slot,
  MeasureId origin,
  _Ids ids,
) {
  final out = <_Placed>[];
  var done = false;
  var time = Length.zero;
  for (final item in items) {
    final start = time;
    time += item.span;
    if (!done && start >= at) {
      out.add(_blank(by, slot, origin, ids));
      done = true;
    } else if (!done && at < time) {
      if (item.item case Tuplet(:final id)) {
        throw _Refuse(WouldSplitTuplet(id, item.origin));
      }
      out.add((item: item.item, span: item.span + by, origin: item.origin));
      done = true;
      continue;
    }
    out.add(item);
  }
  return out;
}

/// [items] without the time from [from] to [to]. Each item loses its
/// overlap with it, and an item inside it goes.
List<_Placed> _shrunk(List<_Placed> items, Length from, Length to) {
  final out = <_Placed>[];
  var time = Length.zero;
  for (final item in items) {
    final start = time;
    time += item.span;
    final overlap = (time < to ? time : to) - (start > from ? start : from);
    if (!overlap.isPositive) {
      out.add(item);
    } else if (overlap < item.span) {
      if (item.item case Tuplet(:final id)) {
        throw _Refuse(WouldSplitTuplet(id, item.origin));
      }
      out.add((
        item: item.item,
        span: item.span - overlap,
        origin: item.origin,
      ));
    }
  }
  return out;
}

/// [items] no longer than [limit] where only blank time at their end
/// passes it: that time gives way, as the rests of a re-barred voice do.
List<_Placed> _fitted(List<_Placed> items, Length limit) {
  var over = Length.sum(items.map((placed) => placed.span)) - limit;
  final out = [...items];
  while (over.isPositive && out.isNotEmpty && _elastic(out.last.item)) {
    final last = out.removeLast();
    if (last.span > over) {
      out.add((item: last.item, span: last.span - over, origin: last.origin));
    }
    over -= last.span;
  }
  return out;
}

/// [span] of blank time: rests in voice one, a gap in the others.
_Placed _blank(Length span, VoiceSlot slot, MeasureId origin, _Ids ids) => (
  item: slot == VoiceSlot.one
      ? MeasureRest(id: ids.event(), span: span)
      : Gap(span),
  span: span,
  origin: origin,
);

StaffMeasure _restStaff(StaffId staff, Clef clef, Length length, _Ids ids) =>
    StaffMeasure(
      staff: staff,
      clef: clef,
      voices: Seq([
        Voice(
          slot: VoiceSlot.one,
          items: Seq([MeasureRest(id: ids.event(), span: length)]),
        ),
      ]),
    );

/// Whether [cut], a staff bar a ripple cut again, holds the same music as
/// [old], so the bar can keep its old object.
bool _sameStaff(StaffMeasure old, StaffMeasure cut) =>
    old.clef == cut.clef &&
    _same(old.directions, cut.directions) &&
    _sameBy(
      old.clefChanges,
      cut.clefChanges,
      (x, y) => x.offset == y.offset && x.clef == y.clef,
    ) &&
    _sameBy(
      old.voices,
      cut.voices,
      (x, y) => x.slot == y.slot && _sameBy(x.items, y.items, _sameItem),
    );

/// Whether [x] and [y] are the same item, or the same blank time under
/// other ids: a re-cut bar mints new ids for the rests it fills in.
bool _sameItem(VoiceItem x, VoiceItem y) =>
    identical(x, y) ||
    switch ((x, y)) {
      (Gap(span: final a), Gap(span: final b)) => a == b,
      (final MeasureRest a, final MeasureRest b) =>
        a.span == b.span && _elastic(a) && _elastic(b),
      (final RestEvent a, final RestEvent b) =>
        a.value == b.value &&
            !a.hidden &&
            !b.hidden &&
            _elastic(a) &&
            _elastic(b),
      _ => false,
    };

bool _sameBy<T>(Iterable<T> a, Iterable<T> b, bool Function(T, T) same) {
  if (a.length != b.length) {
    return false;
  }
  final x = a.iterator;
  final y = b.iterator;
  while (x.moveNext() && y.moveNext()) {
    if (!same(x.current, y.current)) {
      return false;
    }
  }
  return true;
}

/// [after] without the ties on [staves], in bars [from] up to [to], that a
/// ripple sent somewhere else. A tie stays while it ends on the event it
/// ended on before, on the next piece of its own note, or on a new note of
/// its tone, and while it ends on no head where it ended on none.
/// [origins] names the event each new piece came from. [_retie] cannot
/// do this, because it looks every event up in [before] by its id, and the
/// pieces a ripple cuts have new ids.
Score _retied(
  Score before,
  Score after,
  Set<StaffId> staves,
  int from,
  int to,
  Map<EventId, EventId> origins,
) {
  EventId source(EventId id) {
    var at = id;
    for (var earlier = origins[at]; earlier != null; earlier = origins[at]) {
      at = earlier;
    }
    return at;
  }

  TimedEvent? was(TimedEvent timed) => before.lookup(
    EventRef(
      measure: timed.ref.measure,
      staff: timed.ref.staff,
      id: source(timed.event.id),
    ),
  );

  bool moves(TimedEvent timed, ChordEvent chord, Note note) {
    final old = was(timed);
    if (old == null || !note.tie) {
      return false;
    }
    final ahead = _headOfTone(_next(after, timed), note.tone);
    final behind = _headOfTone(_next(before, old), note.tone);
    if (ahead == null) {
      return behind != null;
    }
    final target = source(ahead.timed.event.id);
    return target != old.event.id &&
        target != behind?.timed.event.id &&
        was(ahead.timed) != null;
  }

  return _untieWhere(after, [
    for (var bar = from; bar < to; bar++)
      for (final staff in after.measures[bar].staves)
        if (staves.contains(staff.staff)) (bar, staff.staff),
  ], moves);
}

/// Where the last event of [spanner]'s voice that starts before [point]
/// starts, as for [_lastOnset]. Null when none does.
ScorePoint? _onsetBefore(Score score, Spanner spanner, ScorePoint point) {
  final bar = score.indexOf(point.measure);
  for (var i = bar; i >= 0; i--) {
    final column = score.measures[i];
    final staff = column.staff(spanner.staff);
    final voice =
        staff.voice(spanner.voice ?? VoiceSlot.one) ?? staff.voices.first;
    final onsets = [
      for (final timed in timedEvents(
        voice,
        measure: column.id,
        staff: spanner.staff,
      ))
        if (i < bar || timed.onset < point.offset) timed.onset,
    ];
    if (onsets.isNotEmpty) {
      return ScorePoint(column.id, onsets.last);
    }
  }
  return null;
}
