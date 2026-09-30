/// The editing surface: a session value with cursor, selection, undo/redo
/// and clipboard, over an immutable score.
///
/// One library split over part files, so the edit engine's internals
/// ([Clip]'s representation, the lane writer, the re-barrer) stay private to
/// it while living in separate files.
library;

import 'dart:math';

import '../empty_bar.dart';
import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../refs.dart';
import '../score.dart';
import '../seq.dart';
import '../spelling.dart';
import '../time.dart';
import '../views.dart';
import '../voice_walk.dart';
import 'edits.dart';

part 'apply.dart';
part 'bars.dart';
part 'clipboard.dart';
part 'lane_writer.dart';
part 'rebar.dart';

/// An immutable editing session: the current score, where the cursor is,
/// what is selected, the undo and redo stacks, and the id counter.
///
/// The composer controller holds one in a field and replaces it after each
/// call. Because every version is a value, "what did the score look like
/// before this edit" is just the previous session, and undo is swapping
/// back to a stored score.
///
/// Undo memory: each history entry holds a whole [Score], but consecutive
/// scores share every column the edit did not touch. One note edit costs
/// one new event, voice, staff measure and column, plus a copy of the
/// column pointer list (about 4 KB at 500 bars). History entries hold a
/// fresh `Score` wrapper around the shared children, so the lazily built
/// indexes of a score (`indexOf`, `locate`) are not kept alive per step;
/// an undone-to score rebuilds them on first use. If 4 KB per step ever
/// matters, `Seq` can become a chunked trie without any caller changing.
final class EditSession {
  const EditSession._(
    this.score,
    this.cursor,
    this.selection,
    this._past,
    this._future,
    this._nextId,
    this._historyLimit,
  );

  /// Starts a session with the cursor at the start of the first staff's
  /// first bar, nothing selected, and empty history. The id counter starts
  /// one past the largest id in [score], so ids loaded from JSON are never
  /// reissued.
  factory EditSession.start(Score score, {int historyLimit = 200}) =>
      EditSession._(
        score,
        VoicePoint(
          staff: score.staves.first.id,
          voice: VoiceSlot.one,
          at: ScorePoint(score.measures.first.id, Moment.zero),
        ),
        const Selection.none(),
        const Seq.empty(),
        const Seq.empty(),
        _ids(score).fold(0, max) + 1,
        historyLimit,
      );

  final Score score;

  /// Where the next entered note goes. Always a valid point in [score]
  /// (offset strictly inside its bar).
  final VoicePoint cursor;

  final Selection selection;

  final Seq<_Snapshot> _past;
  final Seq<_Snapshot> _future;

  /// Monotonic across the whole session. Undo does not rewind it.
  final int _nextId;
  final int _historyLimit;

  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;
  String? get undoLabel => canUndo ? _past.last.label : null;
  String? get redoLabel => canRedo ? _future.last.label : null;

  /// Applies [edit] as one undo step.
  ///
  /// Returns [Applied] with the next session, or [Refused] with this session
  /// unchanged and the reason. An edit that leaves the score identical (an
  /// idempotent re-set) returns [Applied] without a history entry. The redo
  /// stack is cleared by any edit that changes the score.
  EditOutcome run(Edit edit) {
    final ids = _Ids(_nextId);
    final EditSession next;
    try {
      next = _advance(edit, ids);
    } on _Refuse catch (refusal) {
      return Refused(this, refusal.reason);
    }
    if (identical(next.score, score)) {
      return Applied(
        EditSession._(
          score,
          next.cursor,
          next.selection,
          _past,
          _future,
          ids.next,
          _historyLimit,
        ),
      );
    }
    var past = _past.append(
      _Snapshot(score.copyWith(), cursor, selection, edit.label),
    );
    if (past.length > _historyLimit) {
      past = past.removeAt(0);
    }
    return Applied(
      EditSession._(
        next.score,
        next.cursor,
        next.selection,
        past,
        const Seq.empty(),
        ids.next,
        _historyLimit,
      ),
    );
  }

  /// This session with [edit] applied to its score, cursor and selection,
  /// and its history untouched. Throws [_Refuse].
  EditSession _advance(Edit edit, _Ids ids) {
    final result = _apply(score, edit, ids, this);
    return EditSession._(
      result.score,
      result.cursor ?? _revalidateCursor(cursor, score, result.score),
      result.selection ?? _revalidateSelection(selection, result.score),
      _past,
      _future,
      _nextId,
      _historyLimit,
    );
  }

  /// Restores the score, cursor and selection from before the last edit.
  /// No-op when [canUndo] is false. The id counter is not rewound, so an id
  /// minted by the undone edit is never minted again.
  EditSession undo() {
    if (!canUndo) {
      return this;
    }
    final back = _past.last;
    return EditSession._(
      back.score,
      back.cursor,
      back.selection,
      _past.removeAt(_past.length - 1),
      _future.append(
        _Snapshot(score.copyWith(), cursor, selection, back.label),
      ),
      _nextId,
      _historyLimit,
    );
  }

  EditSession redo() {
    if (!canRedo) {
      return this;
    }
    final forward = _future.last;
    return EditSession._(
      forward.score,
      forward.cursor,
      forward.selection,
      _past.append(
        _Snapshot(score.copyWith(), cursor, selection, forward.label),
      ),
      _future.removeAt(_future.length - 1),
      _nextId,
      _historyLimit,
    );
  }

  /// Moves the cursor. Snaps [at] into the bar (an offset equal to the bar
  /// length becomes offset 0 of the next bar). Not an undo step.
  ///
  /// Throws [ArgumentError] when [at] names a staff or bar the score does
  /// not have or lies outside its bar. The end of the last bar is outside,
  /// because no bar follows it.
  EditSession placeCursor(VoicePoint at) {
    final point = at.at;
    final inside =
        score.staves.any((staff) => staff.id == at.staff) &&
        score.contains(point.measure) &&
        !point.offset.isNegative &&
        point.offset <= Moment.zero + score.column(point.measure).length;
    final snapped = inside ? _normalize(score, point) : null;
    if (snapped == null) {
      throw ArgumentError.value(at, 'at', 'not a cursor position in the score');
    }
    return _withCursor(
      VoicePoint(staff: at.staff, voice: at.voice, at: snapped),
    );
  }

  /// Moves the cursor by [move], or leaves it where it is when there is
  /// nowhere to go. Event moves stop at every event onset in the cursor's
  /// voice and at every bar start. Staff moves skip hidden parts and keep
  /// the time and voice. Not an undo step.
  EditSession moveCursor(CursorMove move) {
    final bar = score.indexOf(cursor.at.measure);
    final offset = cursor.at.offset;
    final last = score.measures.length - 1;
    switch (move) {
      case CursorMove.nextEvent:
        final stop = _stops(bar).where((s) => s > offset).firstOrNull;
        if (stop != null) {
          return _cursorAt(bar, stop);
        }
        return bar < last ? _cursorAt(bar + 1, Moment.zero) : this;
      case CursorMove.previousEvent:
        final stop = _stops(bar).where((s) => s < offset).lastOrNull;
        if (stop != null) {
          return _cursorAt(bar, stop);
        }
        return bar > 0 ? _cursorAt(bar - 1, _stops(bar - 1).last) : this;
      case CursorMove.nextMeasure:
        return bar < last ? _cursorAt(bar + 1, Moment.zero) : this;
      case CursorMove.previousMeasure:
        if (offset.isPositive) {
          return _cursorAt(bar, Moment.zero);
        }
        return bar > 0 ? _cursorAt(bar - 1, Moment.zero) : this;
      case CursorMove.staffUp || CursorMove.staffDown:
        final visible = [
          for (final part in score.parts)
            if (!part.hidden) ...part.staves,
        ];
        final from = visible.indexWhere((staff) => staff.id == cursor.staff);
        final to = from + (move == CursorMove.staffUp ? -1 : 1);
        if (from == -1 || to < 0 || to == visible.length) {
          return this;
        }
        return _withCursor(
          VoicePoint(staff: visible[to].id, voice: cursor.voice, at: cursor.at),
        );
    }
  }

  /// Where event moves stop in bar [bar]: its start, then every event onset
  /// in the cursor's voice.
  List<Moment> _stops(int bar) {
    final column = score.measures[bar];
    final voice = column.staff(cursor.staff).voice(cursor.voice);
    return [
      Moment.zero,
      if (voice != null)
        for (final timed in timedEvents(
          voice,
          measure: column.id,
          staff: cursor.staff,
        ))
          if (timed.onset.isPositive) timed.onset,
    ];
  }

  EditSession _cursorAt(int bar, Moment offset) => _withCursor(
    VoicePoint(
      staff: cursor.staff,
      voice: cursor.voice,
      at: ScorePoint(score.measures[bar].id, offset),
    ),
  );

  EditSession _withCursor(VoicePoint cursor) => EditSession._(
    score,
    cursor,
    selection,
    _past,
    _future,
    _nextId,
    _historyLimit,
  );

  /// Not an undo step. A stale selection is dropped on the next edit.
  EditSession select(Selection selection) => EditSession._(
    score,
    cursor,
    selection,
    _past,
    _future,
    _nextId,
    _historyLimit,
  );

  /// Copies the selected music into a [Clip], or null when nothing is
  /// selected or the range is empty or runs outside its bars.
  ///
  /// A copy takes what [Erase] would clear: the events that start in the
  /// range, the tuplets wholly inside it, its directions, and the spanners
  /// that start and end in it. It runs to the end of the last event it
  /// takes. A measure rest is silence and is not taken. An item selection
  /// copies the smallest range that covers the picked events on their
  /// staves, widened to the whole tuplet of a picked member.
  ///
  /// The clip is a standalone value: bars are dissolved into one timeline
  /// per voice, tied pieces stay tied, and a tie that leads out of the
  /// copied music onto a head is cleared. It can be pasted into any score.
  Clip? copy() => switch (_revalidateSelection(selection, score)) {
    NoSelection() => null,
    ItemSelection(:final items) => _copy(score, _covering(score, items)),
    final RangeSelection range => _copy(score, range),
  };
}

/// [point] with the end of its bar spelled as offset 0 of the next bar.
/// Null for the end of the last bar. [point]'s offset is at most its bar's
/// length.
ScorePoint? _normalize(Score score, ScorePoint point) {
  final index = score.indexOf(point.measure);
  if (point.offset < Moment.zero + score.measures[index].length) {
    return point;
  }
  return index + 1 < score.measures.length
      ? ScorePoint(score.measures[index + 1].id, Moment.zero)
      : null;
}

/// Every id in [score], for seeding the counter.
Iterable<int> _ids(Score score) sync* {
  for (final part in score.parts) {
    yield part.id.value;
    yield* part.staves.map((staff) => staff.id.value);
  }
  for (final column in score.measures) {
    yield column.id.value;
    for (final staff in column.staves) {
      for (final voice in staff.voices) {
        yield* voice.items.expand(_itemIds);
      }
    }
  }
  yield* score.spanners.map((spanner) => spanner.id.value);
}

Iterable<int> _itemIds(VoiceItem item) sync* {
  switch (item) {
    case Gap():
      break;
    case Tuplet(:final id, :final members):
      yield id.value;
      yield* members.expand(_itemIds);
    case ChordEvent(:final id, :final notes, :final graces):
      yield id.value;
      yield* notes.map((note) => note.id.value);
      for (final grace in graces) {
        yield grace.id.value;
        yield* grace.notes.map((note) => note.id.value);
      }
    case RestEvent(:final id) || MeasureRest(:final id):
      yield id.value;
  }
}

/// Keeps [cursor] while its bar and staff exist, moving it to the bar start
/// if the bar became too short for it. When the bar is gone, the start of
/// the nearest bar after it in [before] that survived, or else the nearest
/// before it. On the same staff if it survived, or on the first staff.
VoicePoint _revalidateCursor(VoicePoint cursor, Score before, Score score) {
  final staffAlive = score.staves.any((staff) => staff.id == cursor.staff);
  final measure = cursor.at.measure;
  if (staffAlive &&
      score.contains(measure) &&
      cursor.at.offset < Moment.zero + score.column(measure).length) {
    return cursor;
  }
  return VoicePoint(
    staff: staffAlive ? cursor.staff : score.staves.first.id,
    voice: cursor.voice,
    at: ScorePoint(
      score.contains(measure) ? measure : _survivor(measure, before, score),
      Moment.zero,
    ),
  );
}

MeasureId _survivor(MeasureId gone, Score before, Score score) {
  final index = before.indexOf(gone);
  bool kept(MeasureColumn column) => score.contains(column.id);
  return (before.measures.skip(index + 1).where(kept).firstOrNull ??
          before.measures.take(index).where(kept).last)
      .id;
}

/// Drops references that no longer resolve in [score] and moves the rest
/// to the measure that now holds them.
Selection _revalidateSelection(Selection selection, Score score) {
  switch (selection) {
    case NoSelection():
      return selection;
    case ItemSelection(:final items):
      final kept = [
        for (final item in items) ?_resolve(item, score),
      ];
      return kept.isEmpty ? const Selection.none() : ItemSelection(Seq(kept));
    case RangeSelection(:final from, :final to, :final top, :final bottom):
      final staves = score.staves.map((staff) => staff.id).toSet();
      final alive =
          score.contains(from.measure) &&
          score.contains(to.measure) &&
          staves.contains(top) &&
          staves.contains(bottom);
      return alive ? selection : const Selection.none();
  }
}

ElementRef? _resolve(ElementRef item, Score score) {
  final timed = score.lookup(item.event);
  if (timed == null) {
    return null;
  }
  return switch (item) {
    EventRef() => timed.ref,
    NoteRef(:final note) => switch (timed.event) {
      final ChordEvent chord when chord.note(note) != null => NoteRef(
        timed.ref,
        note,
      ),
      _ => null,
    },
  };
}

enum CursorMove {
  nextEvent,
  previousEvent,
  nextMeasure,
  previousMeasure,
  staffUp,
  staffDown,
}

final class _Snapshot {
  const _Snapshot(this.score, this.cursor, this.selection, this.label);

  final Score score;
  final VoicePoint cursor;
  final Selection selection;
  final String label;
}

/// The result of [EditSession.run]. Both cases carry a session, so a caller
/// that does not care about the reason can read `.session` directly.
sealed class EditOutcome {
  const EditOutcome();

  EditSession get session;
}

final class Applied extends EditOutcome {
  const Applied(this.session);

  @override
  final EditSession session;
}

final class Refused extends EditOutcome {
  const Refused(this.session, this.reason);

  /// The session the edit was run on, unchanged.
  @override
  final EditSession session;
  final EditRefusal reason;
}

/// What is selected.
sealed class Selection {
  const Selection();

  const factory Selection.none() = NoSelection;

  factory Selection.event(EventRef event) => ItemSelection(Seq([event]));

  /// The one selected event, when exactly one event (or one head of one
  /// chord) is selected. Point edits (add to chord, articulation) use it.
  EventRef? get singleEvent;

  bool get isEmpty;
}

final class NoSelection extends Selection {
  const NoSelection();

  @override
  EventRef? get singleEvent => null;

  @override
  bool get isEmpty => true;
}

/// Individually picked events and note heads (tap, shift-tap).
final class ItemSelection extends Selection {
  const ItemSelection(this.items);

  final Seq<ElementRef> items;

  @override
  EventRef? get singleEvent {
    if (items.isEmpty) {
      return null;
    }
    final first = items.first.event;
    return items.every((item) => item.event == first) ? first : null;
  }

  @override
  bool get isEmpty => items.isEmpty;
}

/// A time range across a contiguous block of staves: every voice of staves
/// [top]..[bottom] (system order) from [from] (inclusive) to [to]
/// (exclusive). [to] may sit at the very end of its bar (offset equal to
/// the bar length) so a range can end at the end of the score.
final class RangeSelection extends Selection {
  const RangeSelection({
    required this.from,
    required this.to,
    required this.top,
    required this.bottom,
  });

  final ScorePoint from;
  final ScorePoint to;
  final StaffId top;
  final StaffId bottom;

  @override
  EventRef? get singleEvent => null;

  @override
  bool get isEmpty => false;
}
