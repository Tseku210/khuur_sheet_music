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
  return score.copyWith(measures: score.measures.insertAllAt(index, bars));
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
  final gone = {for (var i = start; i < end; i++) measures[i].id};
  final resume = next == null ? null : ScorePoint(next.id, Moment.zero);
  final before = start == 0 ? null : score.measures[start - 1];
  final cut = score.copyWith(
    measures: score.measures.replaceRange(start, end, const []),
    spanners: const Seq.empty(),
  );
  final moved = cut.copyWith(
    spanners: _moveSpanners(
      cut,
      score.spanners,
      first: (spanner) =>
          gone.contains(spanner.first.measure) ? resume : spanner.first,
      last: (spanner) => !gone.contains(spanner.last.measure)
          ? spanner.last
          : before == null
          ? null
          : _lastOnset(before, spanner),
    ),
  );
  final played = PlayedTempo(score);
  final lined = _keepTempoLines(moved, score, played, start, end, ids);
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
    if (spannerProblem(cut, trimmed) != null) {
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
  final next = index + 1 < score.measures.length
      ? score.measures[index + 1]
      : null;
  final grid = BeatGrid.meter(column.meter);
  final resized = column.copyWith(
    irregularLength: () => irregular,
    tempos: Seq(column.tempos.where((t) => t.offset < newEnd)),
    staves: Seq([
      for (final staff in column.staves)
        staff.voices.fold(
          staff.copyWith(
            clefChanges: Seq(staff.clefChanges.where((c) => c.offset < newEnd)),
            directions: Seq(staff.directions.where((d) => d.offset < newEnd)),
          ),
          (resizing, voice) => resizing.withVoice(
            Voice(
              slot: voice.slot,
              items: Seq(_resize(voice, column.id, oldEnd, newEnd, grid, ids)),
            ),
          ),
        ),
    ]),
  );
  bool removed(ScorePoint point) =>
      point.measure == column.id && point.offset >= newEnd;
  ScorePoint onItsNote(Spanner spanner, {required bool last}) {
    final point = last ? spanner.last : spanner.first;
    return point.measure == column.id
        ? _onItsNote(score, spanner, last: last)
        : point;
  }

  bool unnoted(Spanner spanner) =>
      spanner.kind is Glissando &&
      (removed(onItsNote(spanner, last: false)) ||
          removed(onItsNote(spanner, last: true)));

  final resume = next == null ? null : ScorePoint(next.id, Moment.zero);
  final cut = score.copyWith(
    measures: score.measures.replaceAt(index, resized),
    spanners: const Seq.empty(),
  );
  return cut.copyWith(
    spanners: _moveSpanners(
      cut,
      score.spanners,
      first: (spanner) {
        final first = onItsNote(spanner, last: false);
        return unnoted(spanner)
            ? null
            : removed(first)
            ? resume
            : first;
      },
      last: (spanner) {
        final last = onItsNote(spanner, last: true);
        return unnoted(spanner)
            ? null
            : !removed(last)
            ? last
            : resume != null && spanner.kind.joinsNotes
            ? resume
            : _lastOnset(resized, spanner);
      },
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

/// [spanners] with their ends where [first] and [last] put them among the
/// bars of [score], which are the bars after the edit. An end with nowhere
/// to go is null. A spanner that loses an end, or that no longer fits (see
/// [_settled]), is dropped. The same object when nothing moves.
Seq<Spanner> _moveSpanners(
  Score score,
  Seq<Spanner> spanners, {
  required ScorePoint? Function(Spanner spanner) first,
  required ScorePoint? Function(Spanner spanner) last,
}) {
  var moved = false;
  final kept = <Spanner>[];
  final starts = _NoteStarts(score);
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
    final settled = _settled(_at(spanner, from, to), starts);
    if (settled != null) {
      kept.add(settled);
    }
  }
  return moved ? Seq(kept) : spanners;
}

/// [spanner] from [first] to [last].
Spanner _at(Spanner spanner, ScorePoint first, ScorePoint last) => Spanner(
  id: spanner.id,
  kind: spanner.kind,
  staff: spanner.staff,
  voice: spanner.voice,
  first: first,
  last: last,
);

/// [score] with each spanner as it can stand after an edit (see
/// [_settled]), and without the ones that cannot.
Score _withFittingSpanners(Score score) {
  final starts = _NoteStarts(score);
  final settled = [
    for (final spanner in score.spanners) _settled(spanner, starts),
  ];
  return score.spanners.indexed.every((at) => identical(at.$2, settled[at.$1]))
      ? score
      : score.copyWith(spanners: Seq(settled.nonNulls));
}

/// [score] with the ends of each slur and glissando stored where they are
/// ([endsHeld]), so that an edit of other notes does not move them. The
/// same object when every end is stored already.
Score _withEndsHeld(Score score) {
  final held = [
    for (final spanner in score.spanners) endsHeld(score, spanner),
  ];
  return score.spanners.indexed.every((at) => identical(at.$2, held[at.$1]))
      ? score
      : score.copyWith(spanners: Seq(held));
}

/// [spanner] as it can stand in the score of [starts] after an edit, or null
/// when it cannot, as a slur whose notes a longer note has replaced. A
/// glissando follows the notes it names. An end whose note no longer sounds
/// at it moves to where that note starts on the staff, and a line whose
/// note has left the staff cannot stand. The same object when nothing moves.
Spanner? _settled(Spanner spanner, _NoteStarts starts) {
  final score = starts.score;

  ScorePoint? end(NoteId? note, {required bool last}) {
    final at = last ? spanner.last : spanner.first;
    if (note == null) {
      return at;
    }
    final sounding = score.anchorOf(spanner, last: last)?.event;
    if (sounding is ChordEvent && sounding.notes.any((n) => n.id == note)) {
      return at;
    }
    return starts.of(spanner.staff, note);
  }

  var placed = spanner;
  if (spanner.kind case Glissando(:final from, :final to)) {
    final first = end(from, last: false);
    final last = end(to, last: true);
    if (first == null || last == null) {
      return null;
    }
    if (first != spanner.first || last != spanner.last) {
      placed = _at(spanner, first, last);
    }
  }
  return spannerProblem(score, placed) == null ? placed : null;
}

/// Where each note of [score] starts, read one staff at a time and only for
/// a staff that is asked about.
final class _NoteStarts {
  _NoteStarts(this.score);

  final Score score;
  final _byStaff = <StaffId, Map<NoteId, ScorePoint>>{};

  /// Where the chord that holds [note] starts on [staff], or null when no
  /// voice of the staff has the note.
  ScorePoint? of(StaffId staff, NoteId note) =>
      (_byStaff[staff] ??= _read(staff))[note];

  Map<NoteId, ScorePoint> _read(StaffId staff) {
    final starts = <NoteId, ScorePoint>{};
    for (final slot in VoiceSlot.values) {
      for (final timed in score.laneOf(staff, slot)) {
        if (timed.event case ChordEvent(:final notes)) {
          final start = ScorePoint(timed.ref.measure, timed.onset);
          for (final note in notes) {
            starts.putIfAbsent(note.id, () => start);
          }
        }
      }
    }
    return starts;
  }
}

/// The end of [spanner] in [score], its last when [last], at the onset of
/// the note it belongs to, for a slur, glissando or trill line. Other kinds
/// keep their point.
ScorePoint _onItsNote(Score score, Spanner spanner, {required bool last}) {
  final point = last ? spanner.last : spanner.first;
  return switch (spanner.kind.reach) {
    SpannerReach.events => ScorePoint(
      point.measure,
      score.anchorOf(spanner, last: last)!.onset,
    ),
    SpannerReach.time => point,
  };
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
