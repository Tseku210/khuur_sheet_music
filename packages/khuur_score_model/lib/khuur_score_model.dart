/// Immutable, measure-major score model for a notation editor.
///
/// Read `Score` first. It owns parts, a global list of `MeasureColumn`s, and
/// cross-bar `Spanner`s. Change it only through `EditSession.run`. Layout
/// reads `Score.measureView` and `Score.changesSince`. Playback uses
/// `PlaybackCompiler`, and `scoreToMidi` writes what it plays as a MIDI
/// file. Persistence is `scoreToJson` and `scoreFromJson`. MusicXML is
/// `scoreToMusicXml` and `scoreFromMusicXml`, and `scoreToMxl` and
/// `scoreFromMusicXmlBytes` add the compressed `.mxl` file.
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
export 'src/io/midi.dart';
export 'src/io/musicxml.dart';
export 'src/io/musicxml_import.dart';
export 'src/io/mxl.dart';
export 'src/measure.dart';
export 'src/pitch.dart';
export 'src/playback.dart'
    show
        ChannelSetup,
        Expression,
        ExpressionPoint,
        PlaybackCompiler,
        PlaybackNote,
        PlaybackOptions,
        PlaybackPoint,
        PlaybackScript,
        PlayedBar;
export 'src/refs.dart';
export 'src/score.dart' hide replacingBars;
export 'src/seq.dart';
export 'src/time.dart';
export 'src/views.dart';
