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
/// column list that is about 4 KB per edit.
final class Seq<T> extends Iterable<T> {
  /// A sequence of [items], copied so that later changes to [items] do not
  /// show.
  Seq(Iterable<T> items) : _items = List<T>.unmodifiable(items);

  /// The empty sequence.
  const Seq.empty() : _items = const <Never>[];

  final List<T> _items;

  @override
  Iterator<T> get iterator => _items.iterator;

  @override
  int get length => _items.length;

  @override
  bool get isEmpty => _items.isEmpty;

  @override
  T elementAt(int index) => _items[index];

  /// The element at [index].
  T operator [](int index) => _items[index];

  /// The index of the first element that passes [test], or -1 when none does.
  int indexWhere(bool Function(T element) test) => _items.indexWhere(test);

  /// A copy with [value] in place of the element at [index].
  Seq<T> replaceAt(int index, T value) {
    final copy = List<T>.of(_items);
    copy[index] = value;
    return Seq(copy);
  }

  /// A copy with [value] inserted at [index].
  Seq<T> insertAt(int index, T value) =>
      Seq(List<T>.of(_items)..insert(index, value));

  /// A copy with [values] inserted at [index], in order.
  Seq<T> insertAllAt(int index, Iterable<T> values) =>
      Seq(List<T>.of(_items)..insertAll(index, values));

  /// A copy without the element at [index].
  Seq<T> removeAt(int index) => Seq(List<T>.of(_items)..removeAt(index));

  /// Replaces `[start, end)` with [values].
  Seq<T> replaceRange(int start, int end, Iterable<T> values) =>
      Seq(List<T>.of(_items)..replaceRange(start, end, values));

  /// A copy with [value] added at the end.
  Seq<T> append(T value) => Seq(List<T>.of(_items)..add(value));
}
