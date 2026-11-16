part of 'session.dart';

// Each edit here resolves its bars before changing anything, so a stale id
// is refused. An edit that changes nothing returns the same score.

_Result _insertMeasuresBefore(
  Score score,
  MeasureId? before,
  int count,
  _Ids ids,
) {
  if (count < 1) {
    throw const _Refuse(InvalidValue('a bar count is 1 or more'));
  }
  final index = before == null
      ? score.measures.length
      : _barIndex(score, before);
  return _Result(_insertMeasures(score, index, count, ids));
}

_Result _deleteMeasuresBetween(
  Score score,
  MeasureId first,
  MeasureId last,
  _Ids ids,
) {
  final (start, end) = _barSpan(score, first, last);
  return _Result(_deleteMeasures(score, start, end, ids));
}

_Result _setBarline(Score score, MeasureId measure, Barline barline) =>
    _changeBars(
      score,
      measure,
      measure,
      (c) => c.barline == barline ? c : c.copyWith(barline: barline),
    );

_Result _setRepeatStart(Score score, MeasureId measure, bool start) =>
    _changeBars(
      score,
      measure,
      measure,
      (c) => c.repeatStart == start ? c : c.copyWith(repeatStart: start),
    );

_Result _setRepeatEnd(Score score, MeasureId measure, RepeatEnd? end) {
  if (end != null) {
    _check(repeatProblem(end.times));
  }
  return _changeBars(
    score,
    measure,
    measure,
    (c) => c.repeatEnd == end ? c : c.copyWith(repeatEnd: () => end),
  );
}

_Result _setVolta(
  Score score,
  MeasureId first,
  MeasureId last,
  Volta? volta,
) {
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
}

_Result _setNavigation(
  Score score,
  MeasureId measure,
  Seq<NavigationMark> marks,
) => _changeBars(
  score,
  measure,
  measure,
  (c) => _same(c.navigation, marks) ? c : c.copyWith(navigation: marks),
);

_Result _setRehearsal(Score score, MeasureId measure, String? text) {
  final rehearsal = text == null || text.isEmpty ? null : text;
  return _changeBars(
    score,
    measure,
    measure,
    (c) =>
        c.rehearsal == rehearsal ? c : c.copyWith(rehearsal: () => rehearsal),
  );
}

_Result _setBreak(Score score, MeasureId measure, LayoutBreak? layoutBreak) =>
    _changeBars(
      score,
      measure,
      measure,
      (c) => c.breakBefore == layoutBreak
          ? c
          : c.copyWith(breakBefore: () => layoutBreak),
    );

_Result _setKeyDisplay(
  Score score,
  MeasureId measure,
  SignatureDisplay display,
) => _changeBars(
  score,
  measure,
  measure,
  (c) => c.keyDisplay == display ? c : c.copyWith(keyDisplay: display),
);

_Result _setMeterDisplay(
  Score score,
  MeasureId measure,
  SignatureDisplay display,
) => _changeBars(
  score,
  measure,
  measure,
  (c) => c.meterDisplay == display ? c : c.copyWith(meterDisplay: display),
);

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
  if (index == 0) {
    // The score's opening tempo mark moves to the new first bar, so every
    // old bar still starts under the tempo mark it started under.
    final (opening, rest) = _splitOpening(like.tempos);
    if (opening.isEmpty) {
      return score.copyWith(measures: score.measures.insertAllAt(0, bars));
    }
    bars[0] = bars[0].copyWith(tempos: opening);
    return score.copyWith(
      measures: score.measures
          .replaceAt(0, like.copyWith(tempos: rest))
          .insertAllAt(0, bars),
    );
  }
  final untied = _untieAt(score, index - 1, _barEnd(like), null);
  return untied.copyWith(measures: untied.measures.insertAllAt(index, bars));
}

/// [marks] split into those at the bar's start and the rest.
(Seq<TempoMark>, Seq<TempoMark>) _splitOpening(Seq<TempoMark> marks) => (
  Seq(marks.where((mark) => mark.offset == Moment.zero)),
  Seq(marks.where((mark) => mark.offset != Moment.zero)),
);

/// [score] without the bars from [start] up to [end]. Refused when no bar
/// would be left. The bars left play at the tempo they played at, with the
/// one exception [_keepTempoLines] names.
Score _deleteMeasures(Score score, int start, int end, _Ids ids) {
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
    spanners: const Seq.empty(),
  );
  final moved = cut.copyWith(
    spanners: _moveSpanners(
      cut,
      untied.spanners,
      first: (spanner) =>
          gone.contains(spanner.first.measure) ? resume : spanner.first,
      last: (spanner) => !gone.contains(spanner.last.measure)
          ? spanner.last
          : before == null
          ? null
          : _lastOnset(before, spanner),
    ),
  );
  final played = PlayedTempo(untied);
  final lined = _keepTempoLines(moved, untied, played, start, end, ids);
  return next == null ? lined : _keepTempo(lined, start, played, measures, end);
}

/// [cut], the bars [start] up to [end] of [old] cut and its spanners moved,
/// with its tempo lines bent so the bars left play at the tempo [played]
/// gave them in [old]:
///
/// - A line that ended in the range now ends before it, and reaches the
///   tempo it had reached there.
/// - A line that ran past the range from inside it, or from before it,
///   goes on from the bar after the range, reaching the tempo it reached.
///   One that ran from before the range is split in two. It goes on only if
///   it was still moving the tempo there.
///
/// Where a line now ends just as the bar after the range starts at another
/// tempo, it reaches that tempo instead, as the tempo mark there takes over
/// a line that ends on it.
Score _keepTempoLines(
  Score cut,
  Score old,
  PlayedTempo played,
  int start,
  int end,
  _Ids ids,
) {
  int index(ScorePoint point) => old.indexOf(point.measure);
  bool touches(Spanner line) =>
      line.kind is TempoLine &&
      index(line.last) >= start &&
      index(line.first) < end;
  if (!old.spanners.any(touches)) {
    return cut;
  }
  final next = end < old.measures.length ? old.measures[end] : null;
  final moving = next == null ? null : played.movingAt(next.id, Moment.zero);
  final moved = {for (final spanner in cut.spanners) spanner.id: spanner};

  /// [line] ending at the last onset before the range, reaching the tempo
  /// it reached there, or null when that onset is before its start.
  Spanner? head(Spanner line) {
    final before = cut.measures[start - 1];
    final trimmed = _tempoLine(line, last: _lastOnset(before, line));
    if (!_fits(cut, trimmed)) {
      return null;
    }
    final from = played.at(line.first.measure, line.first.offset);
    final to = played.alongLine(line.id, before.id, cut.lineEnd(trimmed))!;
    return _tempoLine(trimmed, factor: to.bpm / from.bpm);
  }

  /// [line] going on from the start of the bar after the range, or null
  /// when it no longer moved the tempo there.
  Spanner? tail(Spanner line, SpannerId Function() id) {
    if (moving == null || moving.line != line.id) {
      return null;
    }
    final from = played.at(next!.id, Moment.zero);
    return _tempoLine(
      line,
      id: id(),
      first: ScorePoint(next.id, Moment.zero),
      factor: moving.target.bpm / from.bpm,
    );
  }

  /// What [line], which touches the range, becomes. A line inside the range
  /// goes with it.
  List<Spanner> bend(Spanner line) {
    final startsBefore = index(line.first) < start;
    return [
      if (startsBefore) ?head(line),
      if (index(line.last) >= end)
        ?tail(line, startsBefore ? ids.spanner : () => line.id),
    ];
  }

  return cut.copyWith(
    spanners: Seq([
      for (final spanner in old.spanners)
        if (touches(spanner)) ...bend(spanner) else ?moved[spanner.id],
    ]),
  );
}

/// [line], a tempo line, with what is given changed.
Spanner _tempoLine(
  Spanner line, {
  SpannerId? id,
  ScorePoint? first,
  ScorePoint? last,
  double? factor,
}) {
  final kind = line.kind as TempoLine;
  return Spanner(
    id: id ?? line.id,
    kind: TempoLine(text: kind.text, factor: factor ?? kind.factor),
    staff: line.staff,
    voice: line.voice,
    first: first ?? line.first,
    last: last ?? line.last,
  );
}

/// [cut], whose bar [start] was bar [end] of [old], with that bar starting
/// at the tempo [played] had there before bars [start] up to [end] were
/// cut. It gains a tempo mark at its start for that tempo, unless it has
/// one there of its own or plays at that tempo already. The mark is a copy
/// of the last one the range held when that one gives the tempo.
Score _keepTempo(
  Score cut,
  int start,
  PlayedTempo played,
  Seq<MeasureColumn> old,
  int end,
) {
  final bar = cut.measures[start];
  if (bar.tempos.any((mark) => mark.offset == Moment.zero)) {
    return cut;
  }
  final tempo = played.at(bar.id, Moment.zero);
  if (_sameTempo(PlayedTempo(cut).at(bar.id, Moment.zero), tempo)) {
    return cut;
  }
  final last = [
    for (var i = start; i < end; i++) ...old[i].tempos,
  ].lastOrNull;
  final opening = last != null && _sameTempo(last.tempo, tempo)
      ? TempoMark(
          offset: Moment.zero,
          tempo: last.tempo,
          text: last.text,
          showMetronome: last.showMetronome,
        )
      : TempoMark(offset: Moment.zero, tempo: tempo);
  return cut.copyWith(
    measures: cut.measures.replaceAt(
      start,
      bar.copyWith(tempos: Seq([opening, ...bar.tempos])),
    ),
  );
}

/// Whether [a] and [b] are one tempo, but for rounding.
bool _sameTempo(Tempo a, Tempo b) =>
    a.beat == b.beat && (a.bpm - b.bpm).abs() <= 1e-9 * b.bpm;

/// [score] with bar [index] [length] long, or as long as its meter when
/// [length] is null. A shorter bar loses its music past the new end, and an
/// event crossing the end keeps its head. A longer bar gains rests in voice
/// one and a gap in the other voices.
Score _setBarLength(Score score, int index, Length? length, _Ids ids) {
  final column = score.measures[index];
  final target = length ?? column.meter.length;
  _check(barLengthProblem(target));
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
    spanners: const Seq.empty(),
  );
  return cut.copyWith(
    spanners: _moveSpanners(
      cut,
      untied.spanners,
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
          : openingEvent(next, staff.staff, voice.slot);
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

/// [spanners] with their ends where [first] and [last] put them among the
/// bars of [score], which are the bars after the edit. An end with nowhere
/// to go is null. A spanner that loses an end, or whose ends no longer fit
/// its kind (see [_fits]), is dropped. The same object when nothing moves.
Seq<Spanner> _moveSpanners(
  Score score,
  Seq<Spanner> spanners, {
  required ScorePoint? Function(Spanner spanner) first,
  required ScorePoint? Function(Spanner spanner) last,
}) {
  var moved = false;
  final kept = <Spanner>[];
  for (final spanner in spanners) {
    final from = first(spanner);
    final to = last(spanner);
    if (from == spanner.first && to == spanner.last) {
      kept.add(spanner);
      continue;
    }
    moved = true;
    if (from == null || to == null) {
      continue;
    }
    final candidate = Spanner(
      id: spanner.id,
      kind: spanner.kind,
      staff: spanner.staff,
      voice: spanner.voice,
      first: from,
      last: to,
    );
    if (_fits(score, candidate)) {
      kept.add(candidate);
    }
  }
  return moved ? Seq(kept) : spanners;
}

/// Whether [spanner] can stand in [score]: in order, and past its first
/// event when it joins notes.
bool _fits(Score score, Spanner spanner) =>
    spannerOrderProblem(
          joinsNotes: spanner.kind.joinsNotes,
          firstBar: score.indexOf(spanner.first.measure),
          firstOffset: spanner.first.offset,
          lastBar: score.indexOf(spanner.last.measure),
          lastOffset: spanner.last.offset,
        ) ==
        null &&
    !score.isCollapsed(spanner);

/// [score] without the spanners an edit has left unable to stand, such as a
/// slur whose notes a longer note has replaced.
Score _withFittingSpanners(Score score) {
  final kept = [
    for (final spanner in score.spanners)
      if (_fits(score, spanner)) spanner,
  ];
  return kept.length == score.spanners.length
      ? score
      : score.copyWith(spanners: Seq(kept));
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
