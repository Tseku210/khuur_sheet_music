/// A sort that keeps equal items in order. Internal to the package.
library;

/// [items] sorted by [compare], keeping their order where it finds them
/// equal. `List.sort` promises no such order.
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final list = [...items];
  final order = [for (var i = 0; i < list.length; i++) i]
    ..sort((a, b) {
      final by = compare(list[a], list[b]);
      return by != 0 ? by : a - b;
    });
  return [for (final i in order) list[i]];
}
