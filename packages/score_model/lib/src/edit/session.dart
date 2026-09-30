/// The editing surface: a session value with cursor, selection, undo/redo
/// and clipboard, over an immutable score.
///
/// One library split over part files, so the edit engine's internals
/// ([Clip]'s representation, the lane writer, the re-barrer) stay private to
/// it while living in separate files.
library;

import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../refs.dart';
import '../score.dart';
import '../seq.dart';
import '../time.dart';
import 'edits.dart';

part 'apply.dart';
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
  factory EditSession.start(Score score, {int historyLimit = 200}) {
    // TODO: nextId = 1 + max over every PartId, StaffId, MeasureId, EventId,
    // NoteId, TupletId, SpannerId in score (one pass at load time).
    throw UnimplementedError();
  }

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
    final _Result result;
    try {
      result = _apply(score, edit, ids, this);
    } on _Refuse catch (refusal) {
      return Refused(this, refusal.reason);
    }
    final cursor =
        result.cursor ?? _revalidateCursor(this.cursor, result.score);
    final selection =
        result.selection ?? _revalidateSelection(this.selection, result.score);
    if (identical(result.score, score)) {
      return Applied(
        EditSession._(
          score,
          cursor,
          selection,
          _past,
          _future,
          ids.next,
          _historyLimit,
        ),
      );
    }
    var past = _past.append(
      _Snapshot(score.copyWith(), this.cursor, this.selection, edit.label),
    );
    if (past.length > _historyLimit) {
      past = past.removeAt(0);
    }
    return Applied(
      EditSession._(
        result.score,
        cursor,
        selection,
        past,
        const Seq.empty(),
        ids.next,
        _historyLimit,
      ),
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
  EditSession placeCursor(VoicePoint at) => throw UnimplementedError();

  EditSession moveCursor(CursorMove move) => throw UnimplementedError();

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

  /// Copies the selected range into a [Clip], or null when nothing is
  /// selected. An item selection copies the smallest range on its staff that
  /// covers the selected events.
  ///
  /// The clip is a standalone value: bars are dissolved into one timeline
  /// per voice, tied pieces stay tied, and spanners and directions wholly
  /// inside the range come along with offsets relative to the clip start.
  /// It can be pasted into any score.
  Clip? copy() => throw UnimplementedError();
}

/// Keeps [cursor] if its bar still exists; otherwise the start of the
/// nearest surviving bar on the same staff (or the first staff).
VoicePoint _revalidateCursor(VoicePoint cursor, Score score) =>
    throw UnimplementedError();

/// Drops references that no longer resolve in [score].
Selection _revalidateSelection(Selection selection, Score score) =>
    throw UnimplementedError();

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

/// Copied music, detached from any score. Opaque: the only things a caller
/// does with a clip are keep it and paste it.
final class Clip {
  const Clip._(this.length, this._lanes, this._spanners, this._directions);

  /// Sounding length of the copied range.
  final Length length;

  final List<_ClipLane> _lanes;
  // Read by `_paste` once its body is written.
  // ignore: unused_field
  final List<_ClipSpanner> _spanners;
  // ignore: unused_field
  final List<_ClipDirection> _directions;

  /// Number of staves the clip spans.
  int get staffCount =>
      _lanes.fold(0, (n, lane) => lane.staff >= n ? lane.staff + 1 : n);
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
