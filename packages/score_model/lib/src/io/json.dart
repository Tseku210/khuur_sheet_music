/// Versioned JSON persistence (access pattern 7).
///
/// The wire format mirrors the tree: `measures` is a list of columns, each
/// with its bar facts and a list of staves, each with voices of items. Ids
/// are written as integers and read back unchanged.
///
/// One adaptation at the boundary: meter, key and clef are written only
/// where they change (as a composer reads them), and decoding fills them
/// into every column again. The file stays small and hand-readable; the
/// in-memory score stays self-describing per bar.
///
/// Wire types never cross this boundary. Callers see [Score] in and out.
library;

import '../score.dart';

/// Bumped on any incompatible change. Older files are migrated step by step
/// on load (`_migrations[v]` turns version v into v + 1).
const int scoreSchemaVersion = 1;

/// Encodes [score] as JSON-compatible maps and lists.
///
/// Shape (abridged):
/// ```json
/// {"schema": 1, "meta": {...},
///  "parts": [{"id": 1, "name": "Морин хуур", "instrument": "morin-khuur",
///             "staves": [{"id": 2}]}],
///  "measures": [{"id": 3, "meter": "4/4", "key": -1,
///                "staves": [{"staff": 2, "clef": "treble",
///                            "voices": [{"slot": 1, "items": [
///                              {"chord": 4, "value": "q",
///                               "notes": [{"id": 5, "pitch": "F4"}]}]}]}]}],
///  "spanners": []}
/// ```
Map<String, Object?> scoreToJson(Score score) => throw UnimplementedError();

/// Decodes a score, migrating older schema versions first.
///
/// This is the one place where untrusted structure becomes a [Score], so it
/// checks every invariant the constructors assume: bar fill, voice-one
/// gaps, staff order per column, unique ids across the whole score, spanner
/// anchors that exist, tuplet fill, alteration and fifths ranges. Throws
/// [ScoreFormatException] naming the JSON path of the first problem.
Score scoreFromJson(Object? json) {
  // TODO:
  //   map = json as Map (else throw at path "$")
  //   version = map["schema"]; reject > scoreSchemaVersion (file from a
  //     newer app); run migrations for version < scoreSchemaVersion
  //   decode parts, then columns in order, carrying meter/key/clef forward
  //     from the previous column where the file omits them
  //   construct via the public constructors (they re-check fill)
  //   run the cross-structure checks that Score only asserts in debug
  throw UnimplementedError();
}

final class ScoreFormatException implements Exception {
  const ScoreFormatException(this.path, this.message);

  /// JSON path of the offending value, such as `measures[12].staves[0]`.
  final String path;
  final String message;

  @override
  String toString() => 'ScoreFormatException at $path: $message';
}
