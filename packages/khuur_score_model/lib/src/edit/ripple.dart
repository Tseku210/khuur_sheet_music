part of 'session.dart';

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
/// keeps the session's), where its times now lie, the bar after its
/// section, and the cuts it closed.
final class _Rippled {
  const _Rippled(
    this.score,
    this.cursor,
    this.selection,
    this.place,
    this.next, [
    this.closed = const [],
  ]);

  final Score score;
  final VoicePoint? cursor;
  final Selection? selection;

  /// Where a time counted from the start of the edit's bar now lies. Null
  /// at or past the end of the section.
  final ScorePoint? Function(Length time) place;

  /// The bar after the section. Null at the end of the score.
  final MeasureColumn? next;

  /// The cuts that changed the section, counted from its first bar.
  final List<_Cut> closed;
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
    shift: _Grow(at: from + rests, by: span - rests),
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
    shift: by.isPositive
        ? _Grow(at: to, by: by)
        : _Collapse([(from: from + value.length, to: to)]),
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
/// moves back over the gaps.
_Result _eraseRippled(
  Score score,
  Selection selection,
  _Ids ids,
  Ripple ripple,
  EditSession session,
) {
  switch (selection) {
    case NoSelection():
      return _Result(score);
    case ItemSelection(:final items):
      final (:targets, :whole, :trimmed) = _picked(score, items);
      var now = _retie(score, trimmed, {
        for (final MapEntry(key: id, value: timed) in targets.entries)
          if (!whole.contains(id))
            (score.indexOf(timed.ref.measure), timed.ref.staff),
      });
      var cursor = session.cursor;
      final range = _RangeFollower(score, session.selection);
      final lines = _SectionLines(now);
      for (final (:staves, :bar, :cuts) in _sectionCuts(score, ripple, [
        for (final id in whole) targets[id]!,
      ])) {
        final (a, b) = _sectionAround(now.measures, bar);
        final rippled = lines.rippled(
          now,
          [for (var i = a; i < b; i++) now.measures[i].id],
          (held) => _ripple(
            held,
            ids,
            staves: staves,
            bar: bar,
            shift: _Collapse(cuts),
            cursor: cursor,
            selection: const Selection.none(),
          ),
        );
        now = rippled.score;
        cursor = rippled.cursor ?? cursor;
        range.close(staves, bar, rippled.closed);
      }
      final after = lines.whole(now);
      return _Result(after, cursor: cursor, selection: range.followed(after));
    case final RangeSelection range:
      var now = score;
      var cursor = session.cursor;
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
            final rippled = _ripple(
              now,
              ids,
              staves: scope,
              bar: bar,
              shift: _Collapse([(from: from, to: to)]),
              cursor: cursor,
              selection: const Selection.none(),
            );
            now = rippled.score;
            cursor = rippled.cursor ?? cursor;
          }
          bar = end;
        }
      }
      return _Result(now, cursor: cursor, selection: const Selection.none());
  }
}

/// The spanners of a score while an erase ripples it one section at a
/// time. A ripple leaves a spanner with no end in its section as it is, so
/// each section is rippled with only the spanners that have an end in it,
/// and a score of many sections is not read through once for each.
final class _SectionLines {
  _SectionLines(this._before) : _now = [..._before.spanners] {
    for (final (slot, line) in _before.spanners.indexed) {
      _file(slot, line);
    }
  }

  final Score _before;
  final List<Spanner?> _now;
  final _byBar = <MeasureId, List<int>>{};
  var _moved = false;

  void _file(int slot, Spanner line) {
    for (final bar in {line.first.measure, line.last.measure}) {
      final slots = _byBar[bar] ??= [];
      if (!slots.contains(slot)) {
        slots.add(slot);
      }
    }
  }

  /// What [ripple] makes of [score] with only the spanners that have an
  /// end in [bars], the bars of the section it ripples. The score it
  /// returns holds only those spanners.
  _Rippled rippled(
    Score score,
    List<MeasureId> bars,
    _Rippled Function(Score held) ripple,
  ) {
    final slots = [
      for (final slot in {for (final bar in bars) ...?_byBar[bar]})
        if (_now[slot] != null) slot,
    ]..sort();
    final held = Seq([for (final slot in slots) _now[slot]!]);
    final rippled = ripple(score.copyWith(spanners: held));
    final left = rippled.score.spanners;
    if (!identical(left, held)) {
      _moved = true;
      var next = 0;
      for (final slot in slots) {
        final stays = next < left.length && left[next].id == _now[slot]!.id;
        final line = _now[slot] = stays ? left[next++] : null;
        if (line != null) {
          _file(slot, line);
        }
      }
    }
    return rippled;
  }

  /// [rippled], the score that the last ripple returned, with every
  /// spanner the ripples left, in the order they had. It is the score the
  /// ripples began with when none of them changed a bar.
  Score whole(Score rippled) => identical(rippled.measures, _before.measures)
      ? _before
      : rippled.copyWith(
          spanners: _moved ? Seq(_now.nonNulls) : _before.spanners,
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

/// [score] with the music of [staves] moved by [shift], counted from bar
/// [bar], through the section that holds the bar, and the edited voice
/// changed by [splice]. The section grows by whole bars when the music no
/// longer fits it, and every other staff rests in the new bars. The cursor,
/// a range selection and spanner ends on [staves] follow the music.
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
  final next = b < measures.length ? measures[b] : null;
  final moving = staves.toSet();
  final origins = <EventId, EventId>{};
  final shortened = <EventId>{};
  final edited = measures[bar].id;
  ScorePoint? unmoved(Length time) {
    final (k, offset) = _barAt(origin + time, length);
    return k < old.length ? ScorePoint(old[k].id, offset) : null;
  }

  final streams = {
    for (final s in first.staves)
      if (moving.contains(s.staff))
        for (final slot in VoiceSlot.values)
          (s.staff, slot): [
            for (final (item, from) in _Stream(old, s.staff, slot).items)
              (item: item, span: item.span, origin: from),
          ],
  };
  var placed = shift.from(origin);
  final starts = {for (final staff in moving) staff: <Length>[]};
  if (placed is _Collapse && placed.cuts.isNotEmpty && splice == null) {
    final hit = List.filled(placed.cuts.length, false);
    var musicEnd = Length.zero;
    for (final MapEntry(key: (staff, _), value: items) in streams.entries) {
      final end = placed.musicEnd(items, hit, starts[staff]!);
      if (end > musicEnd) {
        musicEnd = end;
      }
    }
    for (final list in starts.values) {
      list.sort((x, y) => x.compareTo(y));
    }
    Length? lastMark;
    for (final (:at, :direction) in _marks(old, moving)) {
      final removed = direction ? placed.cutOver(at) : null;
      if (removed != null) {
        hit[removed] = true;
      } else if (lastMark == null || at > lastMark) {
        lastMark = at;
      }
    }
    final changing = placed.changing(
      hit,
      musicEnd,
      lastMark,
      refills: () => !identical(
        _ripple(
          score,
          ids,
          staves: staves,
          bar: a,
          shift: _Collapse(const []),
          cursor: cursor,
          selection: const Selection.none(),
        ).score,
        score,
      ),
    );
    if (changing == null) {
      return _Rippled(score, null, null, unmoved, next);
    }
    placed = changing;
  }
  final time = placed;

  List<_Placed> moved(StaffId staff, VoiceSlot slot) {
    final items = streams[(staff, slot)]!;
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
    return time.voice(items, slot, edited, ids, shortened);
  }

  final (count, voices) = _rippledVoices(
    old,
    moving,
    moved,
    ids,
    origins,
    shortened,
  );

  final end = length * Fraction(count);

  /// Where a mark at [at] goes: with its music, or where it was when no
  /// music carries it into the section. A mark in removed time goes.
  Length? kept(Length at) => switch (time.moved(at)) {
    final moved? when moved >= end => at,
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
        clef: time.land,
      ),
  };
  final grown = count > old.length;
  final untied = grown
      ? _untieAt(score, b - 1, _barEnd(closing), null).measures[b - 1]
      : closing;
  final bars = _rippledBars(
    old,
    untied,
    cut,
    count,
    ids,
    unsigned: (staff, k) =>
        time is _Collapse &&
        time.crosses(starts[staff]!, length * Fraction(k + 1)),
  );
  ScorePoint? place(Length time) {
    if (time >= end) {
      return null;
    }
    final (k, offset) = _barAt(time, length);
    return ScorePoint(bars[k].id, offset);
  }

  if (!grown && _same(bars, old)) {
    return _Rippled(score, null, null, (at) => place(origin + at), next);
  }
  final rebuilt = _retied(
    score,
    grown
        ? score.copyWith(measures: measures.replaceRange(a, b, bars))
        : replacingBars(score, a, bars),
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
  ScorePoint onItsNote(Spanner spanner, {required bool last}) {
    final point = last ? spanner.last : spanner.first;
    return index.containsKey(point.measure)
        ? _onItsNote(score, spanner, last: last)
        : point;
  }

  final last = rebuilt.measures[a + count - 1];
  final sectionEnd = ScorePoint(last.id, _barEnd(last));

  ScorePoint? onset(ScorePoint point) => switch (timeOf(point)) {
    final at? => place(kept(at) ?? time.land(at))!,
    null => point,
  };
  ScorePoint close(ScorePoint point) => switch (timeOf(point)) {
    final at? => place(kept(at) ?? time.land(at)) ?? sectionEnd,
    null => point,
  };
  ScorePoint? firstOf(Spanner spanner) => moving.contains(spanner.staff)
      ? onset(onItsNote(spanner, last: false))
      : spanner.first;

  bool unnoted(Spanner spanner) {
    if (time is! _Collapse ||
        spanner.kind is! Glissando ||
        !moving.contains(spanner.staff)) {
      return false;
    }
    bool startsInCut({required bool last}) {
      final point = last ? spanner.last : spanner.first;
      if (!index.containsKey(point.measure)) {
        return false;
      }
      final onset = score.anchorOf(spanner, last: last)!.onset;
      return time.cutOver(timeOf(ScorePoint(point.measure, onset))!) != null;
    }

    return startsInCut(last: false) || startsInCut(last: true);
  }

  final spanners = _moveSpanners(
    rebuilt,
    score.spanners,
    first: (spanner) => unnoted(spanner) ? null : firstOf(spanner),
    last: (spanner) {
      if (unnoted(spanner)) {
        return null;
      }
      final at = moving.contains(spanner.staff)
          ? timeOf(onItsNote(spanner, last: true))
          : null;
      if (at == null) {
        return spanner.last;
      }
      final moved = switch (time.moved(at)) {
        final moved? => place(moved >= end ? at : moved),
        null => place(time.land(at)) ?? sectionEnd,
      };
      if (time is! _Collapse || spanner.kind.joinsNotes) {
        return moved;
      }
      final ended = timeOf(_lastCoveredEnd(score, spanner))!;
      final ends = time.land(ended);
      final stop = place(ends) ?? sectionEnd;
      final before = _onsetBefore(rebuilt, spanner, stop);
      final lost = ends - time.land(at) < ended - at;
      final short =
          spanner.kind.reach == SpannerReach.time &&
          moved != null &&
          before != null &&
          rebuilt.compare(moved, before) < 0;
      if (!lost && !short) {
        return moved;
      }
      final first = firstOf(spanner);
      return before != null &&
              first != null &&
              rebuilt.compare(before, first) < 0 &&
              rebuilt.compare(first, stop) < 0
          ? first
          : before;
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
    (at) => place(origin + at),
    next,
    time is _Collapse ? time.cuts : const [],
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
  Set<EventId> shortened,
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
          shortened: shortened,
        ),
      ),
  ];
  return (count, voices);
}

/// The [count] bars of a rippled section that held [old], with [untied] in
/// place of its last bar and [cut] the new bars of each staff the ripple
/// moved. A bar whose staves did not change is kept as it was, and bars past
/// the old section are new, the last of them taking the section's closing
/// barline, repeat end and closing navigation. A staff bar that [unsigned]
/// names loses its measure-repeat sign.
List<MeasureColumn> _rippledBars(
  List<MeasureColumn> old,
  MeasureColumn untied,
  Map<StaffId, List<StaffMeasure>> cut,
  int count,
  _Ids ids, {
  required bool Function(StaffId staff, int bar) unsigned,
}) {
  final first = old.first;
  final closing = old.last;
  final length = first.length;
  final grown = count > old.length;
  final placed = {
    for (final bars in cut.values)
      for (final bar in bars) ..._eventIds(bar),
  };
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
              restStaff(
                s.staff,
                closing.staff(s.staff).clefAtEnd,
                length,
                ids.event,
              )
        else if (base != null &&
            _sameStaff(
              base.staff(s.staff),
              cut[s.staff]![k],
              placed,
            ) &&
            !(base.staff(s.staff).measureRepeat != null &&
                unsigned(s.staff, k)))
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

/// The ids of the events at the top of [bar]'s voices.
Set<EventId> _eventIds(StaffMeasure bar) => {
  for (final voice in bar.voices)
    for (final item in voice.items)
      if (item is Event) item.id,
};

/// Whether [cut], a staff bar a ripple cut again, holds the same music as
/// [old], so the bar can keep its old object. [placed] holds the id of
/// every event the cut bars hold, [cut] among them.
bool _sameStaff(StaffMeasure old, StaffMeasure cut, Set<EventId> placed) =>
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
      (x, y) =>
          x.slot == y.slot &&
          _sameBy(
            x.items,
            y.items,
            (x, y) => _sameItem(x, y, placed, cut),
          ),
    );

/// Whether [old] and [cut] are the same item, or the same blank time under
/// other ids: a re-cut bar mints new ids for the rests it fills in. A rest
/// the ripple moved to another bar took its id there, so the blank time
/// that follows it into its old bar is not the same. [bar] is the cut bar
/// that holds [cut].
bool _sameItem(
  VoiceItem old,
  VoiceItem cut,
  Set<EventId> placed,
  StaffMeasure bar,
) =>
    identical(old, cut) ||
    switch ((old, cut)) {
      (Gap(span: final a), Gap(span: final b)) => a == b,
      (final MeasureRest a, final MeasureRest b) =>
        a.span == b.span &&
            _elastic(a) &&
            _elastic(b) &&
            _free(a, b, placed, bar),
      (final RestEvent a, final RestEvent b) =>
        a.value == b.value &&
            !a.hidden &&
            !b.hidden &&
            _elastic(a) &&
            _elastic(b) &&
            _free(a, b, placed, bar),
      _ => false,
    };

/// Whether [old] in place of [cut] repeats no id that a cut bar other than
/// [bar] holds. [placed] holds the ids of every cut bar.
bool _free(Event old, Event cut, Set<EventId> placed, StaffMeasure bar) =>
    old.id == cut.id ||
    !placed.contains(old.id) ||
    _eventIds(bar).contains(old.id);

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
