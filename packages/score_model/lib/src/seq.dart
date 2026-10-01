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
/// Representation: a flat unmodifiable array. Replacing one element copies
/// one array of pointers. For the 500-entry column list that is about 4 KB per
/// edit. A chunked trie can replace the array behind this API if undo memory
/// ever matters; no caller would change.
final class Seq<T> extends Iterable<T> {
  Seq(Iterable<T> items) : _items = List<T>.unmodifiable(items);

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

  T operator [](int index) => _items[index];

  /// Index of the first element matching [test], or -1.
  int indexWhere(bool Function(T element) test) => _items.indexWhere(test);

  Seq<T> replaceAt(int index, T value) {
    final copy = List<T>.of(_items);
    copy[index] = value;
    return Seq(copy);
  }

  Seq<T> insertAt(int index, T value) =>
      Seq(List<T>.of(_items)..insert(index, value));

  Seq<T> insertAllAt(int index, Iterable<T> values) =>
      Seq(List<T>.of(_items)..insertAll(index, values));

  Seq<T> removeAt(int index) => Seq(List<T>.of(_items)..removeAt(index));

  /// Replaces `[start, end)` with [values].
  Seq<T> replaceRange(int start, int end, Iterable<T> values) =>
      Seq(List<T>.of(_items)..replaceRange(start, end, values));

  Seq<T> append(T value) => Seq(List<T>.of(_items)..add(value));
}
