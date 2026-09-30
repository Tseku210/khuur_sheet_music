part of 'session.dart';

/// Music to write into a lane, before it is cut to bars.
sealed class _Piece {
  const _Piece();
}

/// A chord of [pitches], lowest first, or a rest when [pitches] is empty.
final class _Entry extends _Piece {
  const _Entry(this.pitches, this.value);

  const _Entry.rest(this.value) : pitches = const [];

  final List<Pitch> pitches;
  final NoteValue value;

  /// One event of [value] with fresh ids. [tied] ties every note into the
  /// next event.
  Event written(NoteValue value, _Ids ids, {required bool tied}) =>
      pitches.isEmpty
      ? RestEvent(id: ids.event(), value: value)
      : ChordEvent(
          id: ids.event(),
          value: value,
          notes: Seq([
            for (final pitch in pitches)
              Note(id: ids.note(), pitch: pitch, tie: tied),
          ]),
        );
}

/// A clip item, already re-minted. Used by `_paste`.
final class _Copied extends _Piece {
  const _Copied(this.item);

  final Content item;
}

final class _LaneWrite {
  const _LaneWrite(this.score, this.end, this.first);

  final Score score;

  /// Where the written music ends, normalized to offset 0 of the next bar
  /// when it ends on a barline.
  final VoicePoint end;

  /// The first event written, for the selection.
  final EventRef? first;

  _Result asResult() => _Result(
    score,
    cursor: end,
    selection: first == null ? null : Selection.event(first!),
  );
}

/// Writes [pieces] into one voice lane from [at], overwriting whatever
/// sounded there. The single implementation of the overwrite and overfill
/// policies: note entry, rest entry, lengthening, and paste all go through
/// it, so they cannot disagree about barlines.
///
/// A piece that starts inside a tuplet is written in the innermost tuplet
/// that holds its start, at its value in that tuplet's time, and must end
/// inside it. Otherwise a piece that fits in its bar is written as entered,
/// and one that runs past the barline is split into tied values spelled by
/// the meter of each bar it reaches.
///
/// Touches only the bars the written span covers (usually one, two when a
/// note crosses the barline), the bar before when a tie into [at] is
/// cleared, and bars appended at the end of the score. A write that ends
/// at the end of the score appends one empty bar for the cursor.
_LaneWrite _overwrite(
  Score score,
  VoicePoint at,
  List<_Piece> pieces,
  _Ids ids,
  Overfill overfill,
) {
  if (!score.contains(at.at.measure) ||
      !score.staves.any((staff) => staff.id == at.staff)) {
    throw _Refuse(StaleReference(at));
  }
  final lane = _Lane(score, at.staff, at.voice, ids);
  final start = score.indexOf(at.at.measure);
  var i = start;
  var o = at.at.offset;
  if (o.isNegative || o >= lane.end(i)) {
    throw _Refuse(OutsideMeasure(at.at));
  }
  void crossBarline() {
    if (o == lane.end(i)) {
      i++;
      o = Moment.zero;
      if (i == lane.columns.length) {
        lane.appendBar();
      }
    }
  }

  EventRef? first;
  for (final piece in pieces) {
    final entry = switch (piece) {
      _Entry() => piece,
      // TODO(paste): write the copied item; a copied tuplet never splits.
      _Copied() => throw UnimplementedError(),
    };
    final items = lane.items(i);
    final inside = _tupletAt(items, o);
    if (inside != null) {
      final column = lane.columns[i];
      final event = entry.written(entry.value, ids, tied: false);
      lane.write(
        i,
        items.replaceAt(
          inside.index,
          _writeInTuplet(inside.tuplet, inside.at, event, ids, column.id),
        ),
      );
      final timed = lane.events(i).firstWhere((e) => e.event.id == event.id);
      first ??= timed.ref;
      o = timed.onset + timed.duration;
      crossBarline();
    } else {
      var remaining = entry.value.length;
      while (remaining.isPositive) {
        final column = lane.columns[i];
        final room = o.until(lane.end(i));
        if (remaining > room && overfill == Overfill.refuse) {
          throw _Refuse(WouldCrossBarline(column.id, remaining - room));
        }
        final take = remaining < room ? remaining : room;
        remaining -= take;
        final values = take == entry.value.length
            ? [entry.value]
            : column.meter.spell(o, take, rest: entry.pitches.isEmpty);
        final parts = [
          for (final (k, value) in values.indexed)
            entry.written(
              value,
              ids,
              tied: remaining.isPositive || k < values.length - 1,
            ),
        ];
        lane.write(
          i,
          _replaceSpan(
            lane.items(i),
            o,
            take,
            parts,
            BeatGrid.meter(column.meter),
            ids,
            gaps: at.voice != VoiceSlot.one,
          ),
        );
        first ??= EventRef(
          measure: column.id,
          staff: at.staff,
          id: parts[0].id,
        );
        o += take;
        crossBarline();
      }
    }
  }
  if (pieces case [_Entry(:final pitches), ...]) {
    lane.untieInto(start, at.at.offset, pitches.toSet());
  }
  return _LaneWrite(
    score.copyWith(measures: Seq(lane.columns)),
    VoicePoint(
      staff: at.staff,
      voice: at.voice,
      at: ScorePoint(lane.columns[i].id, o),
    ),
    first,
  );
}

/// The columns of a score while one voice lane of one staff is written.
/// Columns the write does not reach stay the same objects.
final class _Lane {
  _Lane(Score score, this.staff, this.slot, this.ids)
    : columns = List.of(score.measures);

  final List<MeasureColumn> columns;
  final StaffId staff;
  final VoiceSlot slot;
  final _Ids ids;

  Moment end(int i) => Moment.zero + columns[i].length;

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

  /// Appends an empty bar with the last bar's meter, key and closing clefs.
  void appendBar() {
    final last = columns.last;
    columns.add(
      emptyBar(
        id: ids.measure(),
        meter: last.meter,
        key: last.key,
        clefs: [for (final s in last.staves) (s.staff, s.clefAtEnd)],
        restId: ids.event,
      ),
    );
  }

  /// A tie from the event that ends at [offset] of bar [i] (or at the end
  /// of the bar before, for offset 0) now leads into new music. Clears it on
  /// every note whose pitch the new music does not start with.
  void untieInto(int i, Moment offset, Set<Pitch> kept) {
    final bar = offset.isZero ? i - 1 : i;
    if (bar < 0) {
      return;
    }
    final stop = offset.isZero ? end(bar) : offset;
    final before = events(
      bar,
    ).where((e) => e.onset + e.duration == stop).firstOrNull?.event;
    if (before is! ChordEvent ||
        !before.notes.any((n) => n.tie && !kept.contains(n.pitch))) {
      return;
    }
    final untied = before.copyWith(
      notes: Seq([
        for (final note in before.notes)
          kept.contains(note.pitch) ? note : note.copyWith(tie: false),
      ]),
    );
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

/// Writes [event] at [at] (in [tuplet]'s written time) into the innermost
/// tuplet that holds [at]. Refused when [event] would run past its end.
Tuplet _writeInTuplet(
  Tuplet tuplet,
  Moment at,
  Event event,
  _Ids ids,
  MeasureId measure,
) {
  final nested = _tupletAt(tuplet.members, at);
  if (nested != null) {
    return _refill(
      tuplet,
      tuplet.members.replaceAt(
        nested.index,
        _writeInTuplet(nested.tuplet, nested.at, event, ids, measure),
      ),
    );
  }
  final written = tuplet.unit.length * Fraction(tuplet.ratio.actual);
  if (at + event.span > Moment.zero + written) {
    throw _Refuse(WouldSplitTuplet(tuplet.id, measure));
  }
  final items = _replaceSpan(
    tuplet.members,
    at,
    event.span,
    [event],
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
    case ChordEvent():
      return _pieces(item, spellOnGrid(grid, start, span, rest: false), ids);
    case Event():
      return _restPieces(item, spellOnGrid(grid, start, span, rest: true), ids);
  }
}

/// [chord] written as tied [values]. The first piece keeps the chord's ids
/// and marks, and the last keeps its ties.
List<ChordEvent> _pieces(ChordEvent chord, List<NoteValue> values, _Ids ids) {
  bool tied(Note note, int piece) => piece < values.length - 1 || note.tie;
  return [
    chord.copyWith(
      value: values.first,
      notes: Seq([for (final n in chord.notes) n.copyWith(tie: tied(n, 0))]),
    ),
    for (final (k, value) in values.indexed.skip(1))
      ChordEvent(
        id: ids.event(),
        value: value,
        notes: Seq([
          for (final n in chord.notes)
            Note(id: ids.note(), pitch: n.pitch, head: n.head, tie: tied(n, k)),
        ]),
      ),
  ];
}

/// [rest] written as rests of [values]. The first keeps its id and marks,
/// and every piece of a hidden rest stays hidden.
List<RestEvent> _restPieces(Event rest, List<NoteValue> values, _Ids ids) {
  final hidden = rest is RestEvent && rest.hidden;
  return [
    RestEvent(
      id: rest.id,
      value: values.first,
      articulations: rest.articulations,
      hidden: hidden,
    ),
    for (final value in values.skip(1))
      RestEvent(id: ids.event(), value: value, hidden: hidden),
  ];
}

List<RestEvent> _rests(BeatGrid grid, Moment at, Length span, _Ids ids) => [
  for (final value in spellOnGrid(grid, at, span, rest: true))
    RestEvent(id: ids.event(), value: value),
];
