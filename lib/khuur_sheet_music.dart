/// Sheet music for Flutter. A scrolling, editable view of a `Score` from
/// `score_model`, and MIDI playback.
///
/// Import this library alone. It re-exports the score model, so an app
/// builds and edits scores (`Score`, `EditSession`, the edits) and shows
/// them (`SheetView`) through one import.
library;

export 'package:score_layout/score_layout.dart'
    show
        ChordSymbolSpelling,
        ElementOwner,
        EngravingDefaults,
        EngravingStyle,
        InkRole,
        NotePreview,
        Owner,
        QuarterToneGlyphs,
        SheetHit,
        SmuflFont,
        SpacingPolicy,
        SpannerOwner,
        StringNumbers,
        TextRole,
        TextSpec;
export 'package:score_model/score_model.dart';

export 'src/midi_output.dart' show FlutterMidiOutput, MidiOutput, MidiReverb;
export 'src/score_player.dart';
export 'src/sheet_palette.dart';
export 'src/sheet_view.dart';
export 'src/sound_font.dart';
