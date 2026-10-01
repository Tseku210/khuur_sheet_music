part of 'session.dart';

final class _LaneWrite {
  const _LaneWrite(this.score, this.end, this.first, this.last);

  final Score score;

  /// Where the written music ends: offset 0 of the next bar when it ends on
  /// a barline, or the end of the last bar when it ends the score.
  final VoicePoint end;

  /// The first and last events written.
  final EventRef first;
  final EventRef last;
}

/// Writes [music] into one voice lane from [at], overwriting whatever
/// sounded there. The single implementation of the overwrite and overfill
/// policies: note, rest and tuplet entry, value changes and paste all go
/// through it, so they cannot disagree about barlines.
///
/// An item that starts inside a tuplet is written in the innermost tuplet
/// that holds its start, at its value in that tuplet's time, and must end
/// inside it. Otherwise a tuplet must fit in its bar, an event that fits is
/// written as it is, and one that runs past the barline is split into tied
/// values spelled by the meter of each bar it reaches (see [_piece]).
///
/// Touches only the bars the written span covers (usually one, two when a
/// note crosses the barline) and bars appended for music that runs past
/// the end of the score.
_LaneWrite _overwrite(
  Score score,
  VoicePoint at,
  List<Content> music,
  _Ids ids,
  Overfill overfill,
) {
  if (!score.contains(at.at.measure) ||
      !score.staves.any((staff) => staff.id == at.staff)) {
    throw _Refuse(StaleReference(at));
  }
  final lane = _Lane(score, at.staff, at.voice);
  var i = score.indexOf(at.at.measure);
  var o = at.at.offset;
  if (o.isNegative || o >= lane.end(i)) {
    throw _Refuse(OutsideMeasure(at.at));
  }
  void crossBarline() {
    if (o == lane.end(i)) {
      i++;
      o = Moment.zero;
      if (i == lane.columns.length) {
        lane.appendBar(ids);
      }
    }
  }

  EventRef? first;
  EventRef? last;
  void placed(Iterable<Content> parts) {
    final written = {
      for (final part in parts)
        for (final event in _eventsIn(part)) event.id,
    };
    final timed = lane.events(i).where((e) => written.contains(e.event.id));
    first ??= timed.first.ref;
    last = timed.last.ref;
    o = timed.last.onset + timed.last.duration;
  }

  void write(List<Content> parts, Length span) {
    lane.write(
      i,
      _replaceSpan(
        lane.items(i),
        o,
        span,
        parts,
        BeatGrid.meter(lane.columns[i].meter),
        ids,
        gaps: at.voice != VoiceSlot.one,
      ),
    );
    placed(parts);
  }

  for (final item in music) {
    crossBarline();
    final column = lane.columns[i];
    final items = lane.items(i);
    if (_tupletAt(items, o) case final inside?) {
      lane.write(
        i,
        items.replaceAt(
          inside.index,
          _writeInTuplet(inside.tuplet, inside.at, item, ids, column.id),
        ),
      );
      placed([item]);
      continue;
    }
    _check(startProblem(o));
    switch (item) {
      case Tuplet(:final id, :final span):
        if (o + span > lane.end(i)) {
          throw _Refuse(WouldSplitTuplet(id, column.id));
        }
        write([item], span);
      case Event():
        final value = switch (item) {
          ChordEvent(:final value) || RestEvent(:final value) => value,
          MeasureRest() => throw StateError('a measure rest is never written'),
        };
        var remaining = item.span;
        var opens = true;
        while (remaining.isPositive) {
          crossBarline();
          final room = o.until(lane.end(i));
          if (remaining > room && overfill == Overfill.refuse) {
            throw _Refuse(
              WouldCrossBarline(lane.columns[i].id, remaining - room),
            );
          }
          final take = remaining < room ? remaining : room;
          remaining -= take;
          final values = take == item.span
              ? [value]
              : lane.columns[i].meter.spell(
                  o,
                  take,
                  rest: item is! ChordEvent,
                );
          write([
            for (final (k, v) in values.indexed)
              _piece(
                item,
                v,
                ids,
                first: opens && k == 0,
                tied: remaining.isPositive || k < values.length - 1,
              ),
          ], take);
          opens = false;
        }
    }
  }
  return _LaneWrite(
    score.copyWith(measures: Seq(lane.columns)),
    VoicePoint(
      staff: at.staff,
      voice: at.voice,
      at: o == lane.end(i) && i + 1 < lane.columns.length
          ? ScorePoint(lane.columns[i + 1].id, Moment.zero)
          : ScorePoint(lane.columns[i].id, o),
    ),
    first!,
    last!,
  );
}

/// Enters [event] at [at] as new music. A tie into [at] keeps only the
/// tones [event] starts with, [event] is selected, and the cursor moves
/// past it, into a new bar when it ends the score.
_Result _enter(
  Score score,
  VoicePoint at,
  Event event,
  _Ids ids,
  Overfill overfill,
) {
  final write = _overwrite(score, at, [event], ids, overfill);
  var entered = _untieInto(write.score, at, _tones(event));
  var end = write.end;
  final bar = entered.column(end.at.measure);
  if (end.at.offset == _barEnd(bar)) {
    final added = _barAfter(bar, ids);
    entered = entered.copyWith(measures: entered.measures.append(added));
    end = VoicePoint(
      staff: end.staff,
      voice: end.voice,
      at: ScorePoint(added.id, Moment.zero),
    );
  }
  return _Result(entered, cursor: end, selection: Selection.event(write.first));
}

/// [score] with the tie into [at] cleared on every note whose tone is not
/// in [kept], for new music written at [at].
Score _untieInto(Score score, VoicePoint at, Set<Tone> kept) {
  final lane = _Lane(score, at.staff, at.voice)
    ..untieInto(score.indexOf(at.at.measure), at.at.offset, kept);
  return score.copyWith(measures: Seq(lane.columns));
}

Set<Tone> _tones(Event event) => switch (event) {
  ChordEvent(:final notes) => {for (final note in notes) note.tone},
  _ => const {},
};

Iterable<Event> _eventsIn(Content item) sync* {
  switch (item) {
    case Event():
      yield item;
    case Tuplet(:final members):
      for (final member in members) {
        yield* _eventsIn(member);
      }
  }
}

/// An empty bar after [last], with its meter, key and closing clefs.
MeasureColumn _barAfter(MeasureColumn last, _Ids ids) => emptyBar(
  id: ids.measure(),
  meter: last.meter,
  key: last.key,
  clefs: [for (final s in last.staves) (s.staff, s.clefAtEnd)],
  restId: ids.event,
);

/// The columns of a score while one voice lane of one staff is written.
/// Columns the write does not reach stay the same objects.
final class _Lane {
  _Lane(Score score, this.staff, this.slot) : columns = List.of(score.measures);

  final List<MeasureColumn> columns;
  final StaffId staff;
  final VoiceSlot slot;

  Moment end(int i) => _barEnd(columns[i]);

  /// The lane's items in bar [i]; a whole-bar gap where the voice is absent.
  Seq<VoiceItem> items(int i) {
    final column = columns[i];
    return column.staff(staff).voice(slot)?.items ?? Seq([Gap(column.length)]);
  }

  Iterable<TimedEvent> events(int i) {
    final column = columns[i];
    final voice = column.staff(staff).voice(slot);
    return voice == null
        ? const []
        : timedEvents(voice, measure: column.id, staff: staff);
  }

  void write(int i, Iterable<VoiceItem> items) {
    final column = columns[i];
    columns[i] = column.withStaff(
      column.staff(staff).withVoice(Voice(slot: slot, items: Seq(items))),
    );
  }

  void appendBar(_Ids ids) => columns.add(_barAfter(columns.last, ids));

  /// A tie from the event that ends at [offset] of bar [i] (or at the end
  /// of the bar before, for offset 0) now leads into new music. Clears it on
  /// every note whose tone the new music does not start with.
  void untieInto(int i, Moment offset, Set<Tone> kept) {
    final bar = offset.isZero ? i - 1 : i;
    if (bar < 0) {
      return;
    }
    final stop = offset.isZero ? end(bar) : offset;
    final before = events(
      bar,
    ).where((e) => e.onset + e.duration == stop).firstOrNull?.event;
    if (before is! ChordEvent ||
        !before.notes.any((n) => n.tie && !kept.contains(n.tone))) {
      return;
    }
    final untied = _untied(before, (note) => !kept.contains(note.tone));
    write(bar, [
      for (final item in items(bar))
        item is Content ? _replaceEvent(item, untied) : item,
    ]);
  }
}

/// The tuplet in [items] whose time holds [at], with its index and [at]
/// converted to the tuplet's written time. Null when [at] falls outside
/// every tuplet.
({int index, Tuplet tuplet, Moment at})? _tupletAt(
  Iterable<VoiceItem> items,
  Moment at,
) {
  var start = Moment.zero;
  for (final (index, item) in items.indexed) {
    final stop = start + item.span;
    if (at < stop) {
      return item is Tuplet
          ? (
              index: index,
              tuplet: item,
              at: Moment(start.until(at).wholeNotes / item.ratio.scale),
            )
          : null;
    }
    start = stop;
  }
  return null;
}

/// Writes [item] at [at] (in [tuplet]'s written time) into the innermost
/// tuplet that holds [at]. Refused when [item] would run past its end.
Tuplet _writeInTuplet(
  Tuplet tuplet,
  Moment at,
  Content item,
  _Ids ids,
  MeasureId measure,
) {
  final nested = _tupletAt(tuplet.members, at);
  if (nested != null) {
    return _refill(
      tuplet,
      tuplet.members.replaceAt(
        nested.index,
        _writeInTuplet(nested.tuplet, nested.at, item, ids, measure),
      ),
    );
  }
  _check(startProblem(at));
  final written = tuplet.unit.length * Fraction(tuplet.ratio.actual);
  if (at + item.span > Moment.zero + written) {
    throw _Refuse(WouldSplitTuplet(tuplet.id, measure));
  }
  final items = _replaceSpan(
    tuplet.members,
    at,
    item.span,
    [item],
    BeatGrid.single(written),
    ids,
    gaps: false,
  );
  return _refill(tuplet, [
    for (final item in items)
      switch (item) {
        Content() => item,
        Gap() => throw StateError('rests mode never leaves a gap'),
      },
  ]);
}

Tuplet _refill(Tuplet tuplet, Iterable<Content> members) => Tuplet(
  id: tuplet.id,
  ratio: tuplet.ratio,
  unit: tuplet.unit,
  members: Seq(members),
  bracket: tuplet.bracket,
);

Content _replaceEvent(Content item, Event replacement) => switch (item) {
  Event(:final id) when id == replacement.id => replacement,
  Tuplet(:final members) => _refill(item, [
    for (final member in members) _replaceEvent(member, replacement),
  ]),
  _ => item,
};

/// Replaces `[offset, offset + length)` of [items] with [parts]. The items
/// are one frame (a bar's voice, or a tuplet's members) and every time is
/// in that frame's written time; [grid] is its beat grid.
///
/// Items wholly inside the span are dropped. An item cut at the start keeps
/// its head: a chord as chord pieces tied together, the first keeping the
/// chord's ids and the last its tie flags; a rest as rests, the first
/// keeping its id; a gap as a shorter gap; a tuplet as rests. An item cut
/// at the end leaves its tail as rests, or as a gap when [gaps] is set
/// (voices two to four). Adjacent gaps merge.
List<VoiceItem> _replaceSpan(
  Iterable<VoiceItem> items,
  Moment offset,
  Length length,
  List<Content> parts,
  BeatGrid grid,
  _Ids ids, {
  required bool gaps,
}) {
  final end = offset + length;
  final before = <VoiceItem>[];
  final after = <VoiceItem>[];
  var start = Moment.zero;
  for (final item in items) {
    final stop = start + item.span;
    if (stop <= offset) {
      before.add(item);
    } else if (start >= end) {
      after.add(item);
    } else {
      if (start < offset) {
        before.addAll(_head(item, start, start.until(offset), grid, ids));
      }
      if (stop > end) {
        final tail = end.until(stop);
        after.addAll(gaps ? [Gap(tail)] : _rests(grid, end, tail, ids));
      }
    }
    start = stop;
  }
  return _mergeGaps([...before, ...parts, ...after]);
}

List<VoiceItem> _mergeGaps(Iterable<VoiceItem> items) {
  final merged = <VoiceItem>[];
  for (final item in items) {
    if (merged.lastOrNull case final Gap previous when item is Gap) {
      merged.last = Gap(previous.span + item.span);
    } else {
      merged.add(item);
    }
  }
  return merged;
}

/// What stays of [item], which starts at [start], when only its first
/// [span] survives.
List<VoiceItem> _head(
  VoiceItem item,
  Moment start,
  Length span,
  BeatGrid grid,
  _Ids ids,
) {
  switch (item) {
    case Gap():
      return [Gap(span)];
    case Tuplet():
      return _rests(grid, start, span, ids);
    case Event():
      return _split(
        item,
        spellOnGrid(grid, start, span, rest: item is! ChordEvent),
        ids,
      );
  }
}

/// [event] written as tied [values]. The first piece keeps its ids and
/// marks, and the last keeps its ties.
List<Event> _split(Event event, List<NoteValue> values, _Ids ids) => [
  for (final (k, value) in values.indexed)
    _piece(event, value, ids, first: k == 0, tied: k < values.length - 1),
];

/// One piece of [event], of [value]. The [first] piece keeps [event]'s ids
/// and marks, and the others get fresh ids. Every note keeps its string.
/// A chord's notes are tied on when [tied], and otherwise keep their own
/// ties. Every piece of a hidden rest stays hidden.
Event _piece(
  Event event,
  NoteValue value,
  _Ids ids, {
  required bool first,
  required bool tied,
}) => switch (event) {
  ChordEvent(:final notes) when first => event.copyWith(
    value: value,
    notes: Seq([for (final n in notes) n.copyWith(tie: tied || n.tie)]),
  ),
  ChordEvent(:final notes) => ChordEvent(
    id: ids.event(),
    value: value,
    notes: Seq([
      for (final n in notes)
        switch (n) {
          PitchedNote(:final pitch, :final head, :final string) => PitchedNote(
            id: ids.note(),
            pitch: pitch,
            head: head,
            string: string,
            tie: tied || n.tie,
          ),
          DrumNote(:final drum) => DrumNote(
            id: ids.note(),
            drum: drum,
            tie: tied || n.tie,
          ),
        },
    ]),
  ),
  _ => RestEvent(
    id: first ? event.id : ids.event(),
    value: value,
    articulations: first ? event.articulations : const {},
    hidden: event is RestEvent && event.hidden,
  ),
};

/// [chord] with the ties of the notes that [clears] removed.
ChordEvent _untied(ChordEvent chord, bool Function(Note note) clears) =>
    chord.copyWith(
      notes: Seq([
        for (final note in chord.notes)
          clears(note) ? note.copyWith(tie: false) : note,
      ]),
    );

List<RestEvent> _rests(BeatGrid grid, Moment at, Length span, _Ids ids) => [
  for (final value in spellOnGrid(grid, at, span, rest: true))
    RestEvent(id: ids.event(), value: value),
];
