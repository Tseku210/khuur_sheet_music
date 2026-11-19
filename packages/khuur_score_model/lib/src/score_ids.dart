/// The ids a score holds, for code that mints more of them.
library;

import 'dart:math';

import 'events.dart';
import 'score.dart';

/// The largest id in [score], of any kind, or 0 when it holds none.
int largestId(Score score) => _ids(score).fold(0, max);

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
