import 'dart:math';

/// An immutable ordered sequence with non-destructive updates.
///
/// Every container in the score tree holds its children in a [Seq]. An update
/// returns a new [Seq] and leaves the receiver untouched, so an edit copies
/// only the path from the root to the changed leaf and shares every other
/// subtree with the previous score. That sharing is what keeps undo history
/// cheap and what makes change tracking free.
///
/// Equality is identity, on purpose. Two sequences with equal elements are
/// different values unless they are the same object. `Score.changesSince`
/// relies on this: an unchanged subtree is the *same object* in the old and
/// the new score, and comparing pointers is O(1).
///
/// Replacing one element copies one flat array of pointers. For a 500-entry
/// column list that is about 4 KB per edit. A long list of bars that an
/// edit writes many times over is held in runs, and a replace copies only
/// the run that holds the element.
final class Seq<T> extends Iterable<T> {
  /// A sequence of [items], copied so that later changes to [items] do not
  /// show.
  Seq(Iterable<T> items) : _items = List<T>.unmodifiable(items), _runs = null;

  /// The empty sequence.
  const Seq.empty() : _items = const <Never>[], _runs = null;

  const Seq._inRuns(_Runs<T> this._runs) : _items = const <Never>[];

  /// The items, when they are not held in [_runs].
  final List<T> _items;

  /// The items in runs, for a sequence [SeqRuns.inRuns] made, or null.
  final _Runs<T>? _runs;

  /// A growable copy of the items.
  List<T> _copy() => switch (_runs) {
    null => List<T>.of(_items),
    final runs => List<T>.of(runs.all),
  };

  @override
  Iterator<T> get iterator => switch (_runs) {
    null => _items.iterator,
    final runs => runs.all.iterator,
  };

  @override
  int get length => _runs?.length ?? _items.length;

  @override
  bool get isEmpty => length == 0;

  @override
  T elementAt(int index) => this[index];

  /// The element at [index].
  T operator [](int index) => switch (_runs) {
    null => _items[index],
    final runs => runs[index],
  };

  /// The index of the first element that passes [test], or -1 when none does.
  int indexWhere(bool Function(T element) test) {
    if (_runs == null) {
      return _items.indexWhere(test);
    }
    var index = 0;
    for (final item in _runs.all) {
      if (test(item)) {
        return index;
      }
      index++;
    }
    return -1;
  }

  /// A copy with [value] in place of the element at [index].
  Seq<T> replaceAt(int index, T value) {
    if (_runs case final runs?) {
      return Seq._inRuns(runs.replacing({index: value}));
    }
    final copy = _copy();
    copy[index] = value;
    return Seq(copy);
  }

  /// A copy with [value] inserted at [index].
  Seq<T> insertAt(int index, T value) => Seq(_copy()..insert(index, value));

  /// A copy with [values] inserted at [index], in order.
  Seq<T> insertAllAt(int index, Iterable<T> values) =>
      Seq(_copy()..insertAll(index, values));

  /// A copy without the element at [index].
  Seq<T> removeAt(int index) => Seq(_copy()..removeAt(index));

  /// Replaces `[start, end)` with [values].
  Seq<T> replaceRange(int start, int end, Iterable<T> values) =>
      Seq(_copy()..replaceRange(start, end, values));

  /// A copy with [value] added at the end.
  Seq<T> append(T value) => Seq(_copy()..add(value));
}

/// How the edit engine holds a long sequence in runs, so that replacing a
/// few elements copies only the runs that hold them. A sequence in runs
/// reads and compares as any other. The library does not export this.
extension SeqRuns<T> on Seq<T> {
  /// This sequence with its items in runs about as long as the list of
  /// runs, or this sequence when it already is.
  Seq<T> get inRuns => _runs != null ? this : Seq._inRuns(_Runs.of(_items));

  /// This sequence with its items in one list, or this sequence when it
  /// already is.
  Seq<T> get flat => switch (_runs) {
    null => this,
    final runs => Seq(runs.all),
  };

  /// A copy with each value of [values] in place of the element at its
  /// index. A sequence in runs stays in runs and copies only the runs it
  /// writes; any other copies its list once.
  Seq<T> replacingEach(Map<int, T> values) {
    if (_runs case final runs?) {
      return Seq._inRuns(runs.replacing(values));
    }
    final copy = _copy();
    values.forEach((index, value) => copy[index] = value);
    return Seq(copy);
  }
}

/// Items in runs of one length, the last run shorter when the items do not
/// fill it. Nothing writes to a run once the [_Runs] that holds it is made.
final class _Runs<T> {
  _Runs._(this._runs, this._shift, this.length);

  /// [items] in runs about as long as the list of runs.
  factory _Runs.of(List<T> items) {
    final shift = items.length.bitLength ~/ 2;
    final size = 1 << shift;
    return _Runs._(
      [
        for (var start = 0; start < items.length; start += size)
          items.sublist(start, min(start + size, items.length)),
      ],
      shift,
      items.length,
    );
  }

  final List<List<T>> _runs;
  final int _shift;

  /// How many items the runs hold.
  final int length;

  /// The items, in order.
  Iterable<T> get all => _runs.expand((run) => run);

  T operator [](int index) {
    RangeError.checkValidIndex(index, null, null, length);
    return _runs[index >> _shift][index & ((1 << _shift) - 1)];
  }

  /// The runs with each value of [values] in place of the item at its
  /// index.
  _Runs<T> replacing(Map<int, T> values) {
    final runs = List.of(_runs);
    for (final MapEntry(key: index, :value) in values.entries) {
      RangeError.checkValidIndex(index, null, null, length);
      final run = index >> _shift;
      if (identical(runs[run], _runs[run])) {
        runs[run] = List.of(_runs[run]);
      }
      runs[run][index & ((1 << _shift) - 1)] = value;
    }
    return _Runs._(runs, _shift, length);
  }
}
