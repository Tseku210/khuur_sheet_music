/// Versioned JSON persistence (access pattern 7).
///
/// The wire format mirrors the tree. `measures` is a list of columns, each
/// with its bar facts and one entry per staff in system order, each with
/// voices of items. Ids are written as integers and read back unchanged.
/// Values at their defaults are left out.
///
/// Meter, key and clef are the one adaptation at the boundary. They are
/// written only where they change, as a composer reads them, and decoding
/// fills them into every column again. The file stays small and
/// hand-readable, and the in-memory score stays self-describing per bar.
///
/// Wire types never cross this boundary. Callers see [Score] in and out.
library;

import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../refs.dart';
import '../rules.dart';
import '../score.dart';
import '../seq.dart';
import '../time.dart';

part 'json_read.dart';
part 'json_write.dart';

/// Bumped on any incompatible change. A file from a newer version is
/// refused. When the version moves on, a migration from each older one
/// runs before decoding.
const int scoreSchemaVersion = 1;

/// Encodes [score] as JSON-compatible maps and lists.
///
/// Shape (abridged):
/// ```json
/// {"schema": 1, "meta": {"title": "Jasmine"},
///  "parts": [{"id": 1, "name": "Violin",
///             "instrument": {"key": "violin", "program": 40},
///             "staves": [{"id": 2}]}],
///  "measures": [{"id": 3, "meter": "4/4", "key": -1,
///                "staves": [{"clef": "treble",
///                            "voices": [{"voice": 1, "items": [
///                              {"chord": 4, "value": "quarter",
///                               "notes": [{"id": 5, "pitch": "F4"}]}]}]}]}],
///  "spanners": [{"id": 6, "kind": "slur", "staff": 2, "voice": 1,
///                "from": {"measure": 3, "at": "0"},
///                "to": {"measure": 3, "at": "3/4"}}]}
/// ```
Map<String, Object?> scoreToJson(Score score) {
  final meta = {
    for (final (key, value) in [
      ('title', score.meta.title),
      ('subtitle', score.meta.subtitle),
      ('composer', score.meta.composer),
      ('lyricist', score.meta.lyricist),
      ('copyright', score.meta.copyright),
    ])
      if (value.isNotEmpty) key: value,
  };
  return {
    'schema': scoreSchemaVersion,
    if (meta.isNotEmpty) 'meta': meta,
    'parts': [for (final part in score.parts) _part(part)],
    'measures': [
      for (final (i, column) in score.measures.indexed)
        _column(column, i == 0 ? null : score.measures[i - 1]),
    ],
    if (score.spanners.isNotEmpty)
      'spanners': [for (final spanner in score.spanners) _spanner(spanner)],
  };
}

/// Decodes a score, refusing a file from a newer schema version.
///
/// This is the one place where untrusted structure becomes a [Score], so it
/// checks every invariant the constructors assume and the rules the edits
/// rely on. Those are bar fill, voice order and gaps, tuplet fill, ids
/// unique per kind across the whole score, notes that suit their staff,
/// marks inside their bars in time order, and spanner anchors that exist.
/// Throws [ScoreFormatException] naming the JSON path of the first problem.
Score scoreFromJson(Object? json) => _Decoder().score(_In(json, r'$'));

final class ScoreFormatException implements Exception {
  const ScoreFormatException(this.path, this.message);

  /// A JSON path or a MusicXML element path to the offending value, such as
  /// `$.measures[12].staves[0]` or `/score-partwise/part/measure[3]/note[2]`.
  final String path;
  final String message;

  @override
  String toString() => 'ScoreFormatException at $path: $message';
}

String _fraction(Fraction fraction) => '$fraction';

String _value(NoteValue value) => '${value.base.name}${'.' * value.dots}';

String _pitch(Pitch pitch) => '${_pitchName(pitch.name)}${pitch.octave}';

String _pitchName(PitchName name) =>
    '${name.step.name.toUpperCase()}${_alterNames[name.alter]}';

/// How the file spells each alteration after the letter.
const Map<String, Alter> _alters = {
  'bb': Alter.doubleFlat,
  'db': Alter.threeQuarterFlat,
  'b': Alter.flat,
  'd': Alter.quarterFlat,
  '': Alter.natural,
  '+': Alter.quarterSharp,
  '#': Alter.sharp,
  '#+': Alter.threeQuarterSharp,
  'x': Alter.doubleSharp,
};

final Map<Alter, String> _alterNames = {
  for (final MapEntry(:key, :value) in _alters.entries) value: key,
};

/// A letter, an alteration and, for a pitch, an octave, as in `F#4`.
final _spelling = RegExp(
  '^([A-G])(${[
    for (final name in _alters.keys)
      if (name.isNotEmpty) RegExp.escape(name),
  ].join('|')})?(-?\\d)?\$',
);
