/// MusicXML adapter (future). Declared now to show where it plugs in.
///
/// The model is shaped like MusicXML's `score-timewise` document: measure,
/// then part, then notes. Export walks columns and emits one `<measure>` per
/// column with a `<part>` per part; voices become `<voice>` numbers with
/// `<backup>` between them, and [Gap]s become `<forward>`. Ties map to
/// `<tie>`/`<tied>` on notes, spanners to `<direction>`/`<notations>` with
/// start and stop in the bars their anchors name. Import is the same walk in
/// reverse, validated like `scoreFromJson`.
library;

import '../events.dart' show Gap;
import '../score.dart';

String scoreToMusicXml(Score score) => throw UnimplementedError();

Score scoreFromMusicXml(String xml) => throw UnimplementedError();
