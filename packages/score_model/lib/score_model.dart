/// Immutable, measure-major score model for a notation editor.
///
/// Read `Score` first. It owns parts, a global list of `MeasureColumn`s, and
/// cross-bar `Spanner`s. Change it only through `EditSession.run`. Layout
/// reads `Score.measureView` and `Score.changesSince`. Playback uses
/// `PlaybackCompiler`. Persistence is `scoreToJson` and `scoreFromJson`.
library;

export 'src/edit/edits.dart';
export 'src/edit/session.dart'
    show
        Applied,
        CursorMove,
        EditOutcome,
        EditSession,
        ItemSelection,
        NoSelection,
        RangeSelection,
        Refused,
        ScoreClip,
        Selection;
export 'src/events.dart';
export 'src/io/json.dart';
export 'src/io/musicxml.dart';
export 'src/io/musicxml_import.dart';
export 'src/measure.dart';
export 'src/pitch.dart';
export 'src/playback.dart'
    show
        ChannelSetup,
        PlaybackCompiler,
        PlaybackNote,
        PlaybackOptions,
        PlaybackPoint,
        PlaybackScript,
        PlayedBar;
export 'src/refs.dart';
export 'src/score.dart';
export 'src/seq.dart';
export 'src/time.dart';
export 'src/views.dart';
