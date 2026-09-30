part of 'session.dart';

/// Edits to the bars themselves: adding and removing them, their length,
/// and the marks on their barlines. Each resolves its bars before changing
/// anything, so a stale id is refused. An edit that changes nothing returns
/// the same score.
_Result _bars(Score score, Edit edit, _Ids ids) {
  switch (edit) {
    case InsertMeasures(:final before, :final count):
      final index = before == null
          ? score.measures.length
          : _barIndex(score, before);
      return _Result(_insertMeasures(score, index, count, ids));
    case DeleteMeasures(:final first, :final last):
      final (start, end) = _barSpan(score, first, last);
      return _Result(_deleteMeasures(score, start, end));
    case SetBarLength(:final measure, :final length):
      return _Result(
        _setBarLength(score, _barIndex(score, measure), length, ids),
      );
    case SetBarline(:final measure, :final barline):
      return _changeBars(
        score,
        measure,
        measure,
        (c) => c.barline == barline ? c : c.copyWith(barline: barline),
      );
    case SetRepeatStart(:final measure, :final start):
      return _changeBars(
        score,
        measure,
        measure,
        (c) => c.repeatStart == start ? c : c.copyWith(repeatStart: start),
      );
    case SetRepeatEnd(:final measure, :final end):
      return _changeBars(
        score,
        measure,
        measure,
        (c) => c.repeatEnd == end ? c : c.copyWith(repeatEnd: () => end),
      );
    case SetVolta(:final first, :final last, :final volta):
      if (volta != null && !_countsPasses(volta.endings)) {
        throw const _Refuse(
          InvalidValue('an ending lists its passes from 1, in order'),
        );
      }
      return _changeBars(
        score,
        first,
        last,
        (c) => c.volta == volta ? c : c.copyWith(volta: () => volta),
      );
    case SetNavigation(:final measure, :final marks):
      return _changeBars(
        score,
        measure,
        measure,
        (c) => _same(c.navigation, marks) ? c : c.copyWith(navigation: marks),
      );
    case SetRehearsal(:final measure, :final text):
      final rehearsal = text == null || text.isEmpty ? null : text;
      return _changeBars(
        score,
        measure,
        measure,
        (c) => c.rehearsal == rehearsal
            ? c
            : c.copyWith(rehearsal: () => rehearsal),
      );
    default:
      throw StateError('not a bar edit: $edit');
  }
}

int _barIndex(Score score, MeasureId id) =>
    score.contains(id) ? score.indexOf(id) : throw _Refuse(StaleReference(id));

/// Bars [first] to [last], in either order, as a start index and the index
/// after the end.
(int, int) _barSpan(Score score, MeasureId first, MeasureId last) {
  final a = _barIndex(score, first);
  final b = _barIndex(score, last);
  return (min(a, b), max(a, b) + 1);
}

Moment _barEnd(MeasureColumn column) => Moment.zero + column.length;

/// Rewrites bars [first] to [last] with [change], which returns a column
/// itself when it has nothing to change.
_Result _changeBars(
  Score score,
  MeasureId first,
  MeasureId last,
  MeasureColumn Function(MeasureColumn column) change,
) {
  final (start, end) = _barSpan(score, first, last);
  final measures = score.measures;
  final changed = [for (var i = start; i < end; i++) change(measures[i])];
  final same = Iterable<int>.generate(
    changed.length,
  ).every((k) => identical(changed[k], measures[start + k]));
  return _Result(
    same
        ? score
        : score.copyWith(
            measures: measures.replaceRange(start, end, changed),
          ),
  );
}

/// Whether [endings] name passes counted from 1, ascending, each once.
bool _countsPasses(List<int> endings) =>
    endings.isNotEmpty &&
    endings.first >= 1 &&
    Iterable<int>.generate(
      endings.length - 1,
    ).every((k) => endings[k] < endings[k + 1]);

/// Whether [a] and [b] hold equal elements in the same order.
bool _same<T>(Iterable<T> a, Iterable<T> b) =>
    a.length == b.length &&
    Iterable<int>.generate(
      a.length,
    ).every((k) => a.elementAt(k) == b.elementAt(k));

/// [score] with [count] empty bars at [index]. They carry on the meter,
/// key and clefs of the bar before, or the opening ones of the first bar
/// when [index] is 0, and join an ending both neighbours share.
Score _insertMeasures(Score score, int index, int count, _Ids ids) {
  final measures = score.measures;
  final like = measures[max(index - 1, 0)];
  final volta =
      index > 0 &&
          index < measures.length &&
          measures[index].volta == like.volta
      ? like.volta
      : null;
  final bars = [
    for (var n = 0; n < count; n++)
      emptyBar(
        id: ids.measure(),
        meter: like.meter,
        key: like.key,
        clefs: [
          for (final s in like.staves)
            (s.staff, index == 0 ? s.clef : s.clefAtEnd),
        ],
        restId: ids.event,
      ).copyWith(volta: () => volta),
  ];
  final untied = index == 0
      ? score
      : _untieAt(score, index - 1, _barEnd(like), null);
  return untied.copyWith(measures: untied.measures.insertAllAt(index, bars));
}

/// [score] without the bars from [start] up to [end]. Refused when no bar
/// would be left.
Score _deleteMeasures(Score score, int start, int end) {
  final measures = score.measures;
  if (start == 0 && end == measures.length) {
    throw const _Refuse(WouldEmptyScore());
  }
  final next = end < measures.length ? measures[end] : null;
  final untied = start == 0
      ? score
      : _untieAt(score, start - 1, _barEnd(measures[start - 1]), next);
  final gone = {for (var i = start; i < end; i++) measures[i].id};
  final resume = next == null ? null : ScorePoint(next.id, Moment.zero);
  final before = start == 0 ? null : untied.measures[start - 1];
  final cut = untied.copyWith(
    measures: untied.measures.replaceRange(start, end, const []),
  );
  return cut.copyWith(
    spanners: _moveSpanners(
      cut,
      first: (spanner) =>
          gone.contains(spanner.first.measure) ? resume : spanner.first,
      last: (spanner) => !gone.contains(spanner.last.measure)
          ? spanner.last
          : before == null
          ? null
          : _lastOnset(before, spanner),
    ),
  );
}

/// [score] with bar [index] [length] long, or as long as its meter when
/// [length] is null. A shorter bar loses its music past the new end, and an
/// event crossing the end keeps its head. A longer bar gains rests in voice
/// one and a gap in the other voices.
Score _setBarLength(Score score, int index, Length? length, _Ids ids) {
  final column = score.measures[index];
  final target = length ?? column.meter.length;
  if (!target.isPositive ||
      (target / DurationBase.oneTwentyEighth.length).denominator != 1) {
    throw const _Refuse(
      InvalidValue('a bar holds a whole number of 128th notes'),
    );
  }
  final irregular = target == column.meter.length ? null : target;
  if (irregular == column.irregularLength) {
    return score;
  }
  final oldEnd = _barEnd(column);
  final newEnd = Moment.zero + target;
  if (newEnd == oldEnd) {
    return score.copyWith(
      measures: score.measures.replaceAt(
        index,
        column.copyWith(irregularLength: () => irregular),
      ),
    );
  }
  final shorter = newEnd < oldEnd;
  final next = index + 1 < score.measures.length
      ? score.measures[index + 1]
      : null;
  final untied = shorter
      ? _untieAt(score, index, newEnd, next)
      : _untieAt(score, index, oldEnd, null);
  final bar = untied.measures[index];
  final grid = BeatGrid.meter(bar.meter);
  final resized = bar.copyWith(
    irregularLength: () => irregular,
    tempos: Seq(bar.tempos.where((t) => t.offset < newEnd)),
    staves: Seq([
      for (final staff in bar.staves)
        staff.voices.fold(
          staff.copyWith(
            clefChanges: Seq(staff.clefChanges.where((c) => c.offset < newEnd)),
            directions: Seq(staff.directions.where((d) => d.offset < newEnd)),
          ),
          (resizing, voice) => resizing.withVoice(
            Voice(
              slot: voice.slot,
              items: Seq(_resize(voice, bar.id, oldEnd, newEnd, grid, ids)),
            ),
          ),
        ),
    ]),
  );
  bool removed(ScorePoint point) =>
      point.measure == bar.id && point.offset >= newEnd;
  final resume = next == null ? null : ScorePoint(next.id, Moment.zero);
  final cut = untied.copyWith(
    measures: untied.measures.replaceAt(index, resized),
  );
  return cut.copyWith(
    spanners: _moveSpanners(
      cut,
      first: (spanner) => removed(spanner.first) ? resume : spanner.first,
      last: (spanner) =>
          removed(spanner.last) ? _lastOnset(resized, spanner) : spanner.last,
    ),
  );
}

/// [voice]'s items in a bar of [measure] that now ends at [newEnd] instead
/// of [oldEnd]. Refused when the new end cuts a tuplet.
List<VoiceItem> _resize(
  Voice voice,
  MeasureId measure,
  Moment oldEnd,
  Moment newEnd,
  BeatGrid grid,
  _Ids ids,
) {
  final items = voice.items;
  final gaps = voice.slot != VoiceSlot.one;
  if (items.first case MeasureRest(:final id, :final articulations)) {
    return [
      MeasureRest(
        id: id,
        span: Moment.zero.until(newEnd),
        articulations: articulations,
      ),
    ];
  }
  if (newEnd < oldEnd) {
    var start = Moment.zero;
    for (final item in items) {
      final stop = start + item.span;
      if (item is Tuplet && start < newEnd && newEnd < stop) {
        throw _Refuse(WouldSplitTuplet(item.id, measure));
      }
      start = stop;
    }
    return _replaceSpan(
      items,
      newEnd,
      newEnd.until(oldEnd),
      const [],
      grid,
      ids,
      gaps: gaps,
    );
  }
  final added = oldEnd.until(newEnd);
  return switch (items.last) {
    final Gap last when gaps => [
      ...items.take(items.length - 1),
      Gap(last.span + added),
    ],
    _ => [
      ...items,
      if (gaps) Gap(added) else ..._rests(grid, oldEnd, added, ids),
    ],
  };
}

/// [score] with the ties of bar [index] cleared that would end on a
/// different head once its music from [from] on is followed by the opening
/// of [next], or by rests when [next] is null. A tie that ends on no head,
/// and still won't, stays for let-ring.
Score _untieAt(Score score, int index, Moment from, MeasureColumn? next) {
  final column = score.measures[index];
  var untied = column;
  for (final staff in column.staves) {
    for (final voice in staff.voices) {
      final following = next == null
          ? null
          : _opening(next, staff.staff, voice.slot);
      var items = voice.items;
      for (final timed in timedEvents(
        voice,
        measure: column.id,
        staff: staff.staff,
      )) {
        final event = timed.event;
        if (event is! ChordEvent || timed.onset + timed.duration < from) {
          continue;
        }
        final now = _next(score, timed);
        bool moves(Note note) => _tieMoves(note, now, following);
        if (event.notes.any(moves)) {
          final replacement = _untied(event, moves);
          items = Seq([
            for (final item in items)
              item is Content ? _replaceEvent(item, replacement) : item,
          ]);
        }
      }
      if (!identical(items, voice.items)) {
        untied = untied.withStaff(
          untied
              .staff(staff.staff)
              .withVoice(Voice(slot: voice.slot, items: items)),
        );
      }
    }
  }
  return identical(untied, column)
      ? score
      : score.copyWith(measures: score.measures.replaceAt(index, untied));
}

/// The event that opens [column] in [slot] of [staff]. Null when that voice
/// is absent or opens with a gap.
TimedEvent? _opening(MeasureColumn column, StaffId staff, VoiceSlot slot) {
  final voice = column.staff(staff).voice(slot);
  final first = voice == null
      ? null
      : timedEvents(voice, measure: column.id, staff: staff).firstOrNull;
  return first != null && first.onset.isZero ? first : null;
}

/// [score]'s spanners with their ends where [first] and [last] put them
/// among [score]'s bars, which are the bars after the edit. An end with
/// nowhere to go is null. A spanner that loses an end, or whose ends no
/// longer fit its kind (see [_fits]), is dropped. The same object when
/// nothing moves.
Seq<Spanner> _moveSpanners(
  Score score, {
  required ScorePoint? Function(Spanner spanner) first,
  required ScorePoint? Function(Spanner spanner) last,
}) {
  var moved = false;
  final kept = <Spanner>[];
  for (final spanner in score.spanners) {
    final from = first(spanner);
    final to = last(spanner);
    if (from == spanner.first && to == spanner.last) {
      kept.add(spanner);
      continue;
    }
    moved = true;
    if (from == null || to == null || !_fits(score, spanner.kind, from, to)) {
      continue;
    }
    kept.add(
      Spanner(
        id: spanner.id,
        kind: spanner.kind,
        staff: spanner.staff,
        voice: spanner.voice,
        first: from,
        last: to,
      ),
    );
  }
  return moved ? Seq(kept) : score.spanners;
}

/// Whether a [kind] spanner can run from [first] to [last] in [score]: in
/// order, and past its first event when it joins notes.
bool _fits(Score score, SpannerKind kind, ScorePoint first, ScorePoint last) =>
    kind.joinsNotes
    ? _precedes(score, first, last)
    : !_precedes(score, last, first);

/// Whether [a] comes before [b] in [score].
bool _precedes(Score score, ScorePoint a, ScorePoint b) {
  final i = score.indexOf(a.measure);
  final j = score.indexOf(b.measure);
  return i < j || i == j && a.offset < b.offset;
}

/// Where the last event of [spanner]'s voice in [column] starts, taking
/// voice one when the spanner has no voice or its voice is absent there.
ScorePoint _lastOnset(MeasureColumn column, Spanner spanner) {
  final staff = column.staff(spanner.staff);
  final voice =
      staff.voice(spanner.voice ?? VoiceSlot.one) ?? staff.voices.first;
  return ScorePoint(
    column.id,
    timedEvents(voice, measure: column.id, staff: spanner.staff).last.onset,
  );
}
