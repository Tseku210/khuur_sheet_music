part of 'session.dart';

/// Copied music, detached from any score. Opaque: the only things a caller
/// does with a clip are keep it and paste it.
final class Clip {
  const Clip._(
    this.length,
    this.staffCount,
    this._lanes,
    this._spanners,
    this._directions,
  );

  /// Sounding length of the copied range.
  final Length length;

  /// Number of staves the clip spans.
  final int staffCount;

  final List<_ClipLane> _lanes;
  final List<_ClipSpanner> _spanners;
  final List<_ClipDirection> _directions;
}

/// One voice of one staff, barlines dissolved. [items] are placed at
/// offsets from the clip start. Ids inside are the source ids and are never
/// written into a score as-is; paste mints new ones.
final class _ClipLane {
  const _ClipLane(this.staff, this.voice, this.items);

  /// Staff index relative to the clip's top staff.
  final int staff;
  final VoiceSlot voice;
  final List<({Moment offset, Content item})> items;
}

final class _ClipSpanner {
  const _ClipSpanner(this.staff, this.kind, this.voice, this.first, this.last);

  final int staff;
  final SpannerKind kind;
  final VoiceSlot? voice;
  final Moment first;
  final Moment last;
}

final class _ClipDirection {
  const _ClipDirection(this.staff, this.offset, this.direction);

  final int staff;
  final Moment offset;
  final StaffDirection direction;
}

/// What [_eraseRange] would clear of [range], as a clip: the events that
/// start in it and the tuplets wholly inside it, with its directions and
/// the spanners that start and end in it. The clip runs to the end of the
/// last event it takes. A measure rest is silence and is not taken. A tie
/// that leads out of the taken music onto a head is cleared. Null when the
/// range is empty or runs outside its bars.
Clip? _copy(Score score, RangeSelection range) {
  final RangeSelection(:from, :to, :top, :bottom) = range;
  bool within(ScorePoint point) =>
      !point.offset.isNegative &&
      point.offset <= _barEnd(score.column(point.measure));
  if (!within(from) || !within(to) || !_precedes(score, from, to)) {
    return null;
  }
  final order = [for (final staff in score.staves) staff.id];
  final ends = [order.indexOf(top), order.indexOf(bottom)];
  final staves = order.sublist(ends.reduce(min), ends.reduce(max) + 1);
  bool inRange(ScorePoint point) =>
      !_precedes(score, point, from) && _precedes(score, point, to);
  Moment offsetOf(ScorePoint point) =>
      Moment.zero + _between(score, from, point);

  final lanes = <(int, VoiceSlot), List<({Moment offset, Content item})>>{};
  final timed = <EventId, TimedEvent>{};
  final directions = <_ClipDirection>[];
  var length = _between(score, from, to);
  for (
    var bar = score.indexOf(from.measure);
    bar <= score.indexOf(to.measure);
    bar++
  ) {
    final column = score.measures[bar];
    for (final (k, staff) in staves.indexed) {
      final measure = column.staff(staff);
      for (final voice in measure.voices) {
        var onset = Moment.zero;
        for (final item in voice.items) {
          final start = ScorePoint(column.id, onset);
          onset += item.span;
          if (item is! Content ||
              item is MeasureRest ||
              !inRange(start) ||
              item is Tuplet &&
                  _precedes(score, to, ScorePoint(column.id, onset))) {
            continue;
          }
          final offset = offsetOf(start);
          (lanes[(k, voice.slot)] ??= []).add((offset: offset, item: item));
          final stop = offset + item.span;
          if (stop > Moment.zero + length) {
            length = Moment.zero.until(stop);
          }
        }
        for (final event in timedEvents(
          voice,
          measure: column.id,
          staff: staff,
        )) {
          timed[event.event.id] = event;
        }
      }
      for (final direction in measure.directions) {
        final point = ScorePoint(column.id, direction.offset);
        if (inRange(point)) {
          directions.add(_ClipDirection(k, offsetOf(point), direction));
        }
      }
    }
  }

  final copied = {
    for (final items in lanes.values)
      for (final (:item, offset: _) in items)
        for (final event in _eventsIn(item)) event.id,
  };
  bool inside(TimedEvent event) => copied.contains(event.event.id);
  return Clip._(
    length,
    staves.length,
    [
      for (final MapEntry(key: (staff, slot), value: items) in lanes.entries)
        _ClipLane(staff, slot, [
          for (final (:offset, :item) in items)
            (
              offset: offset,
              item: _eventsIn(item).fold(
                item,
                (content, event) => switch (_crossingTies(
                  score,
                  timed[event.id]!,
                  inside,
                )) {
                  final untied? => _replaceEvent(content, untied),
                  null => content,
                },
              ),
            ),
        ]),
    ],
    [
      for (final s in score.spanners)
        if (staves.contains(s.staff) && inRange(s.first) && inRange(s.last))
          _ClipSpanner(
            staves.indexOf(s.staff),
            s.kind,
            s.voice,
            offsetOf(s.first),
            offsetOf(s.last),
          ),
    ],
    directions,
  );
}

/// The smallest range covering [items] on the staves they are on. An event
/// in a tuplet stands for its outermost tuplet, which is copied whole or
/// not at all.
RangeSelection _covering(Score score, Seq<ElementRef> items) {
  final spans = [
    for (final item in items) _outermost(score, score.lookup(item.event)!),
  ];
  final from = spans
      .map((s) => s.from)
      .reduce((a, b) => _precedes(score, b, a) ? b : a);
  final to = spans
      .map((s) => s.to)
      .reduce((a, b) => _precedes(score, a, b) ? b : a);
  final order = [for (final staff in score.staves) staff.id];
  final rows = [for (final item in items) order.indexOf(item.event.staff)];
  return RangeSelection(
    from: from,
    to: to,
    top: order[rows.reduce(min)],
    bottom: order[rows.reduce(max)],
  );
}

/// Where the top-level item of its voice that holds [timed] starts and
/// ends.
({ScorePoint from, ScorePoint to}) _outermost(Score score, TimedEvent timed) {
  final measure = timed.ref.measure;
  var start = timed.onset;
  var stop = timed.onset + timed.duration;
  if (timed.tuplets.isNotEmpty) {
    final voice = score
        .column(measure)
        .staff(timed.ref.staff)
        .voice(timed.voice)!;
    var onset = Moment.zero;
    for (final item in voice.items) {
      if (item is Tuplet && item.id == timed.tuplets.first) {
        start = onset;
        stop = onset + item.span;
      }
      onset += item.span;
    }
  }
  return (from: ScorePoint(measure, start), to: ScorePoint(measure, stop));
}

/// Replaces what [_eraseRange] clears from [at] for the clip's length, on
/// the clip's staves from [at]'s down, with the clip. Bars are appended
/// first when the score is too short. The pasted range is selected.
_Result _paste(
  Score score,
  Clip clip,
  VoicePoint at,
  _Ids ids,
  Overfill overfill,
) {
  final order = [for (final staff in score.staves) staff.id];
  final top = order.indexOf(at.staff);
  if (top < 0 || !score.contains(at.at.measure)) {
    throw _Refuse(StaleReference(at));
  }
  final staves = order.sublist(
    top,
    min(order.length, top + clip.staffCount),
  );
  var padded = score;
  ScorePoint scoreEnd() {
    final last = padded.measures.last;
    return ScorePoint(last.id, _barEnd(last));
  }

  while (_between(padded, at.at, scoreEnd()) < clip.length) {
    padded = padded.copyWith(
      measures: padded.measures.append(_barAfter(padded.measures.last, ids)),
    );
  }
  final range = RangeSelection(
    from: at.at,
    to: _later(padded, at.at, clip.length),
    top: staves.first,
    bottom: staves.last,
  );
  ScorePoint place(Moment offset) =>
      _later(padded, at.at, Moment.zero.until(offset));
  var pasted = _eraseRange(padded, range, ids);
  for (final lane in clip._lanes) {
    if (lane.staff >= staves.length) {
      continue;
    }
    for (final (:item, offset: _) in lane.items) {
      for (final event in _eventsIn(item)) {
        if (event case ChordEvent(:final notes, :final graces)) {
          for (final note in [...notes, for (final g in graces) ...g.notes]) {
            _checkTone(score, staves[lane.staff], note.tone);
          }
        }
      }
    }
    for (final run in _runs(lane.items)) {
      pasted = _overwrite(
        pasted,
        VoicePoint(
          staff: staves[lane.staff],
          voice: lane.voice,
          at: place(run.offset),
        ),
        [for (final item in run.items) _remint(item, ids)],
        ids,
        overfill,
      ).score;
    }
  }
  for (final direction in clip._directions) {
    if (direction.staff >= staves.length) {
      continue;
    }
    final staff = staves[direction.staff];
    final point = place(direction.offset);
    pasted = _setDirections(
      pasted,
      staff,
      point.measure,
      Seq([
        ...pasted.column(point.measure).staff(staff).directions,
        _movedTo(direction.direction, point.offset),
      ]),
    );
  }
  pasted = pasted.copyWith(
    spanners: Seq([
      ...pasted.spanners,
      for (final s in clip._spanners)
        if (s.staff < staves.length)
          Spanner(
            id: ids.spanner(),
            kind: s.kind,
            staff: staves[s.staff],
            voice: s.voice,
            first: place(s.first),
            last: place(s.last),
          ),
    ]),
  );
  bool inRange(ScorePoint point) =>
      !_precedes(pasted, point, range.from) &&
      _precedes(pasted, point, range.to);
  bool inside(TimedEvent event) =>
      inRange(ScorePoint(event.ref.measure, event.onset));
  var untied = pasted;
  for (
    var bar = max(0, pasted.indexOf(range.from.measure) - 1);
    bar <= pasted.indexOf(range.to.measure);
    bar++
  ) {
    final column = pasted.measures[bar];
    for (final staff in staves) {
      for (final voice in column.staff(staff).voices) {
        for (final event in timedEvents(
          voice,
          measure: column.id,
          staff: staff,
        )) {
          if (_crossingTies(pasted, event, inside) case final chord?) {
            untied = _replace(untied, event, chord);
          }
        }
      }
    }
  }
  return _Result(untied, selection: range);
}

/// [timed]'s chord without the ties that lead into or out of the music
/// [inside] holds and onto a head, or null when it keeps its ties. A
/// let-ring tie before pasted music would otherwise end on a pasted head.
ChordEvent? _crossingTies(
  Score score,
  TimedEvent timed,
  bool Function(TimedEvent timed) inside,
) {
  final chord = timed.event;
  if (chord is! ChordEvent) {
    return null;
  }
  final next = _next(score, timed);
  if (next == null || inside(next) == inside(timed)) {
    return null;
  }
  bool crosses(Note note) => _tieMoves(note, next, null);
  return chord.notes.any(crosses) ? _untied(chord, crosses) : null;
}

/// [items] in runs that each follow on without a hole.
List<({Moment offset, List<Content> items})> _runs(
  List<({Moment offset, Content item})> items,
) {
  final runs = <({Moment offset, List<Content> items})>[];
  var end = Moment.zero;
  for (final (:offset, :item) in items) {
    if (runs.isEmpty || offset != end) {
      runs.add((offset: offset, items: []));
    }
    runs.last.items.add(item);
    end = offset + item.span;
  }
  return runs;
}

/// [item] with a new id on every event, note, grace and tuplet in it.
Content _remint(Content item, _Ids ids) {
  Seq<Note> notes(Seq<Note> notes) =>
      Seq([for (final note in notes) note.copyWith(id: ids.note())]);
  return switch (item) {
    ChordEvent(:final graces) => item.copyWith(
      id: ids.event(),
      notes: notes(item.notes),
      graces: Seq([
        for (final grace in graces)
          GraceChord(
            id: ids.event(),
            kind: grace.kind,
            value: grace.value,
            notes: notes(grace.notes),
          ),
      ]),
    ),
    RestEvent(:final value, :final articulations, :final hidden) => RestEvent(
      id: ids.event(),
      value: value,
      articulations: articulations,
      hidden: hidden,
    ),
    MeasureRest() => throw StateError('a clip holds no measure rest'),
    Tuplet(:final ratio, :final unit, :final members, :final bracket) => Tuplet(
      id: ids.tuplet(),
      ratio: ratio,
      unit: unit,
      members: Seq([for (final member in members) _remint(member, ids)]),
      bracket: bracket,
    ),
  };
}

/// The sounding time from [a] to [b] in [score].
Length _between(Score score, ScorePoint a, ScorePoint b) => Length.sum([
  for (var i = score.indexOf(a.measure); i < score.indexOf(b.measure); i++)
    score.measures[i].length,
  a.offset.until(b.offset),
]);

/// The point [time] after [from] in [score], at the start of the next bar
/// when it falls on a barline, and past the end of the last bar when the
/// score is too short.
ScorePoint _later(Score score, ScorePoint from, Length time) {
  var i = score.indexOf(from.measure);
  var at = from.offset + time;
  while (i + 1 < score.measures.length && at >= _barEnd(score.measures[i])) {
    at = Moment.zero + _barEnd(score.measures[i]).until(at);
    i++;
  }
  return ScorePoint(score.measures[i].id, at);
}
