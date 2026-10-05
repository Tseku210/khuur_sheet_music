# Score model: grounding

The package was renamed `khuur_sheet_music` on 2026-10-05. This document keeps the name it had when it was written.

These are the facts that every candidate design starts from. They were gathered on 2026-09-30 by reading this repository, the Khuur app repository, and the public store listings for Maestro.

## Goal

**Update, 2026-09-30.** The project owner widened the goal. `simple_sheet_music` is an open-source library and stays general. The Khuur composer is its first consumer, and nothing in the library is specific to it. The Khuur facts below are kept as the record the design started from. The scope decision is in [`RATIONALE.md`](RATIONALE.md).

The goal is to rewrite `simple_sheet_music` into a notation engine for the composer screen of the Khuur app. The composer should match Maestro - Music Composer, published by Future Sculptor. The first artifact is the score model. It is an immutable domain model with no Flutter imports. Every other layer is derived from it:

- a layout engine that computes spacing, line breaks and glyph positions
- a painter that only draws
- a playback compiler that turns the score into timed MIDI events
- an editor that applies commands and supports a cursor, a selection, undo and redo
- persistence as versioned JSON, with MusicXML import and export possible later

## Consumer: the Khuur app

The app lives at `/Users/tsekushi/dev/work/khuur_app`.

- Today the app contains only a tuner. No composer exists yet, and the app does not depend on `simple_sheet_music`. The composer is greenfield on the consumer side as well.
- The app is Flutter, targets Android and iOS only, and uses Dart SDK 3.13.
- State management uses `provider` only, meaning `ChangeNotifier` with `context.watch` and `context.read`. The composer controller will be a `ChangeNotifier`.
- The UI strings are in Mongolian, so lyrics and text in a score must be full Unicode, including Mongolian Cyrillic.
- The instrument is the morin khuur, a two-string bowed fiddle. The standard tuning is F3 and B♭3. Its notation probably needs these marks:
  - fingering
  - which string to play (inner or outer)
  - up-bow and down-bow
  - ornaments

  The Figma design was not accessible, so the exact set of marks is unknown.

## Target feature scope (Maestro)

This list comes from the App Store and Google Play listing. Reviews confirmed some of the limits.

- Rhythm:
  - dots and double dots
  - beams
  - ties and slurs
  - grace notes
  - tuplets (duplets, triplets, quintuplets)
  - multi-measure rests
- Pitch:
  - accidentals, including quarter tones
  - octave lines (8va, 8vb, 15ma, 15mb, 22va, 22vb)
  - transposition
- Chords and "layered notes", which are multiple voices on one staff.
- Unlimited staves and parts, with parts that can be shown or hidden. The app offers more than 100 instruments.
- Clefs:
  - treble, bass, alto, soprano, mezzo-soprano, tenor and baritone
  - drum and one-line percussion clefs
- Changes to clef, key, time signature and tempo in the middle of a score.
- Articulations:
  - staccato, staccatissimo, accent, tenuto, fermata
  - trill, tremolo, mordent
  - reviewers asked to be able to stack articulations
- Dynamics and hairpins.
- Repeats:
  - repeat barlines and voltas (first and second endings)
  - D.C., D.S., Segno, Coda and Fine
  - Maestro's playback ignores codas, and reviewers complained about it
- Text:
  - lyrics
  - chord symbols
  - finger numbers
- Playback:
  - play instantly
  - play a selected section and loop it
- Export to PNG, JPG, PDF and audio. Maestro has no MusicXML, and reviewers asked for it.
- Layout wraps systems continuously, with an adjustable number of notes per line (a zoom level).
- Maestro validates measure fill, and reviewers mention "need a rest" and "need a bar line" prompts.

## Lessons from the current engine

A code review of this repository found the following problems. The new model must not repeat them.

- **Model, layout and paint are fused.** Each symbol type has a model class, a metrics class and a renderer class. The model carries presentation data: a Flutter `Color`, an `EdgeInsets` margin, and a random UUID generated in the constructor. Because of the UUID, the same score built twice gets different identities.
- **Durations are `double` quarter-beats.** Triplets cannot be represented exactly. Measure validation compares these doubles with `!=`.
- **`Pitch` is an enum of 52 natural notes.** Each note stores its accidental only as a display attribute. There is no spelled pitch made of step, alteration and octave. As a result, transposition, enharmonic spelling and automatic accidentals have no home.
- **Musical context does not cross barlines.** Every measure gets the initial clef and key. A clef change in measure 1 is lost by measure 2. Playback threads the key signature separately, so there are two sources of truth.
- **`Note` and `ChordNote` duplicate about 400 lines of stem and flag math.** A note should be a chord with one note head.
- **Nothing is cached.** Layout cost grows quadratically with the number of measures. The whole score is laid out again on every playback highlight tick.
- **Playback is monophonic, and chords are silent.** Playback uses a chain of `Timer`s, so drift accumulates.
- **Many features are missing entirely.** There are no voices, staves, parts, beams, dots, ties, tuplets, selection or undo.

The review also found things worth keeping. These are rendering concerns, not model concerns:

- The SMuFL glyph approach, meaning the Bravura font plus metadata anchors that position stems and flags.
- The pitch-to-MIDI math.
- The rule that resolves accidentals until the end of the measure.

## Constraints

- The model is a pure Dart package. It imports nothing from Flutter or `dart:ui`. It must be testable with `dart test`.
- It targets Dart 3.13. Sealed classes, records, patterns and extension types are available.
- Lints come from `pedantic_mono`. Tests use hand-written fakes, not a mocking package.
- A composer on a phone should handle a score of about 500 measures across 4 staves. A single-note edit must not force a relayout or recompilation of the whole score. The layer that consumes the model must be able to tell which measures changed.
- The undo history must stay cheap in memory. Aim for structural sharing, not deep copies.
- Identity must be stable. An event keeps its ID across edits, undo and a save-and-load round trip, because highlights, the selection and the playback-to-event mapping key on it.

## Access patterns to trace

Every candidate should trace these operations through its proposed structure.

1. **Tap to enter a note.** The user taps a staff. Hit-testing resolves the tap to a staff, a measure, a voice, a time offset and a staff line. The composer inserts a note of the current duration at the cursor, and the cursor advances.
2. **Enter a chord.** The user adds a pitch to the event under the cursor, which turns a single note into a chord.
3. **Copy, paste and transpose.** The user selects a range across measures and staves, copies it, pastes it elsewhere, and transposes the selection up a diatonic step or a semitone.
4. **Undo and redo** any of the edits above.
5. **Lay out one measure.** For measure *m*, layout needs:
   - every event per staff and voice, with its onset time
   - the resolved clef, key and time signature
   - which accidentals to display
   - which notes are beamed together
   - which ties and slurs start or end in the measure
   - which measures changed since the last layout
6. **Compile playback.** Playback needs a list of entries of the form (seconds, MIDI key, velocity, duration, channel, source event ID). Repeats must be unrolled, tied notes merged, and tempo changes and dynamics applied. The playhead time must map back to an event ID for highlighting.
7. **Save and load.** The score round-trips through JSON and keeps its identities.
8. **Change the time signature in the middle of a score.** Decide what happens to the content already there. Is it re-barred? Does it overflow?
9. **Overfill a measure.** Decide what happens when a quarter note is inserted into a full measure. It could split and tie across the barline, push content forward, or be rejected.
