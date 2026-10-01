part of 'session.dart';

Score _erase(Score score, Selection selection, _Ids ids) => switch (selection) {
  NoSelection() => score,
  ItemSelection(:final items) => _eraseItems(score, items, ids),
  final RangeSelection range => _eraseRange(score, range, ids),
};

/// Erases the picked events whole, and the picked heads of a chord that
/// keeps another head. Picking every head of a chord picks the chord.
Score _eraseItems(Score score, Seq<ElementRef> items, _Ids ids) {
  final targets = <EventId, TimedEvent>{};
  final whole = <EventId>{};
  final heads = <EventId, Set<NoteId>>{};
  for (final item in items) {
    switch (item) {
      case EventRef(:final id):
        targets[id] = _target(score, item);
        whole.add(id);
      case NoteRef(:final event, :final note):
        targets[event.id] = _targetHead(score, item).timed;
        (heads[event.id] ??= {}).add(note);
    }
  }
  var trimmed = score;
  for (final MapEntry(key: id, value: notes) in heads.entries) {
    final timed = targets[id]!;
    final chord = timed.event as ChordEvent;
    if (chord.notes.every((n) => notes.contains(n.id))) {
      whole.add(id);
    } else {
      trimmed = _replace(
        trimmed,
        timed,
        chord.copyWith(
          notes: Seq([
            for (final n in chord.notes)
              if (!notes.contains(n.id)) n,
          ]),
        ),
      );
    }
  }
  final lanes = {
    for (final timed in targets.values)
      (score.indexOf(timed.ref.measure), timed.ref.staff),
  };
  final cleared = _clear(
    trimmed,
    lanes,
    (_) =>
        (item, _, _) => item is Event && whole.contains(item.id),
    ids,
  );
  return _retie(score, cleared, lanes);
}

/// Erases every voice of the staves from [RangeSelection.top] to
/// [RangeSelection.bottom], from [RangeSelection.from] up to
/// [RangeSelection.to]: the events that start in it, the tuplets wholly
/// inside it, its directions, and the spanners that start and end in it.
Score _eraseRange(Score score, RangeSelection range, _Ids ids) {
  final (:lanes, :staves, :inRange) = _covers(score, range);
  final to = range.to;
  final cleared = _clear(
    score,
    lanes,
    (measure) =>
        (item, onset, duration) =>
            inRange(ScorePoint(measure, onset)) &&
            (item is! Tuplet ||
                !_precedes(score, to, ScorePoint(measure, onset + duration))),
    ids,
  );
  var measures = cleared.measures;
  for (final (bar, staff) in lanes) {
    final column = measures[bar];
    final old = column.staff(staff);
    final kept = [
      for (final d in old.directions)
        if (!inRange(ScorePoint(column.id, d.offset))) d,
    ];
    if (kept.length != old.directions.length) {
      measures = measures.replaceAt(
        bar,
        column.withStaff(old.copyWith(directions: Seq(kept))),
      );
    }
  }
  final spanners = [
    for (final s in score.spanners)
      if (!staves.contains(s.staff) || !inRange(s.first) || !inRange(s.last)) s,
  ];
  final unchanged =
      identical(measures, cleared.measures) &&
      spanners.length == score.spanners.length;
  return _retie(
    score,
    unchanged
        ? cleared
        : cleared.copyWith(measures: measures, spanners: Seq(spanners)),
    lanes,
  );
}

/// Whether an erase takes [item], which sounds from [onset] for
/// [duration] in its bar, whole.
typedef _Pick = bool Function(Content item, Moment onset, Length duration);

/// [score] with what [pickIn] picks in each bar cleared from every voice
/// of the (bar index, staff) [lanes]. A voice one left with only plain
/// rests becomes one [MeasureRest]; the other voices merge their gaps and
/// go when only gaps are left.
Score _clear(
  Score score,
  Set<(int, StaffId)> lanes,
  _Pick Function(MeasureId measure) pickIn,
  _Ids ids,
) {
  var measures = score.measures;
  for (final (bar, staff) in lanes) {
    final column = measures[bar];
    final old = column.staff(staff);
    var cleared = old;
    for (final voice in old.voices) {
      final gaps = voice.slot != VoiceSlot.one;
      final items = _cleared(
        voice.items,
        Moment.zero,
        Fraction.one,
        BeatGrid.meter(column.meter),
        pickIn(column.id),
        ids,
        gaps: gaps,
      );
      if (_same(items, voice.items)) {
        continue;
      }
      cleared = cleared.withVoice(
        Voice(
          slot: voice.slot,
          items: Seq(
            gaps
                ? _mergeGaps(items)
                : _onlyRests(items)
                ? [
                    MeasureRest(
                      id: _eventsIn(items.first as Content).first.id,
                      span: column.length,
                    ),
                  ]
                : items,
          ),
        ),
      );
    }
    if (!identical(cleared, old)) {
      measures = measures.replaceAt(bar, column.withStaff(cleared));
    }
  }
  return identical(measures, score.measures)
      ? score
      : score.copyWith(measures: measures);
}

/// [items], one frame sounding from [onset] at [scale], with what [pick]
/// takes cleared. Taken content leaves a gap when [gaps] is set and rests
/// on [grid] otherwise; a chord's rest keeps its id and a fermata. A tuplet
/// in a gapped frame that is left with only rests becomes a gap.
List<VoiceItem> _cleared(
  Iterable<VoiceItem> items,
  Moment onset,
  Fraction scale,
  BeatGrid grid,
  _Pick pick,
  _Ids ids, {
  required bool gaps,
}) {
  final cleared = <VoiceItem>[];
  var at = onset;
  var written = Moment.zero;
  for (final item in items) {
    final duration = item.span * scale;
    switch (item) {
      case Content() when pick(item, at, duration):
        cleared.addAll(switch (item) {
          _ when gaps => [Gap(item.span)],
          ChordEvent(:final id, :final value, :final articulations) => [
            RestEvent(
              id: id,
              value: value,
              articulations: Set.unmodifiable(
                articulations.intersection(_restMarks),
              ),
            ),
          ],
          RestEvent() || MeasureRest() => [item],
          Tuplet() => _rests(grid, written, item.span, ids),
        });
      case Tuplet(:final ratio, :final unit, :final members):
        final inner = _cleared(
          members,
          at,
          scale * ratio.scale,
          BeatGrid.single(unit.length * Fraction(ratio.actual)),
          pick,
          ids,
          gaps: false,
        );
        cleared.add(
          _same(inner, members)
              ? item
              : gaps && _onlyRests(inner)
              ? Gap(item.span)
              : _refill(item, inner.cast()),
        );
      case Gap() || Event():
        cleared.add(item);
    }
    at += duration;
    written += item.span;
  }
  return cleared;
}

/// Whether [items] hold only rests that print plainly, in tuplets or not.
bool _onlyRests(Iterable<VoiceItem> items) => items.every(
  (item) => switch (item) {
    RestEvent(:final hidden, :final articulations) =>
      !hidden && articulations.isEmpty,
    Tuplet(:final members) => _onlyRests(members),
    _ => false,
  },
);
