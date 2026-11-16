---
title: The score model
description: Why khuur_score_model stores a score as an immutable tree of full bars, how its ids, edits, undo, views and rules work, and what each choice buys.
sidebar:
  order: 2
---

`khuur_score_model` holds a score as an immutable tree of values, and every other part of the library reads it. Layout reads it bar by bar, playback compiles it, and the file formats write it and read it back. The model imports nothing from Flutter. This page explains its shape and the reasons for it, for a contributor who will change it.

## The bar is the unit

A `Score` has three children, and each one owns one kind of fact:

```
Score
├─ meta                               title and credits
├─ parts: Seq<Part>                   who plays: instrument, staves, hidden
├─ measures: Seq<MeasureColumn>       what is played, bar by bar
│   └─ MeasureColumn                  id, meter, key, barline, repeats,
│      │                              volta, navigation, rehearsal,
│      │                              tempo marks, breaks
│      └─ staves: Seq<StaffMeasure>   staff, clef at the bar's start,
│          │                          clef changes, directions
│          └─ voices: Seq<Voice>      slot one to four
│              └─ items: Seq<VoiceItem>
│                   Gap | ChordEvent | RestEvent | MeasureRest | Tuplet
└─ spanners: Seq<Spanner>             slurs, hairpins, octave lines,
                                      pedal lines, trill lines,
                                      tempo lines, glissandi
```

Every bar-level fact and every event lives inside exactly one `MeasureColumn`. The bar is the unit that a composer fills, that layout lays out, and that playback caches, so the structure follows it. MusicXML's timewise form and MuseScore organize a score the same way.

Two other shapes are worth knowing, because a change can drift toward them. One stores a stream of events per voice and derives barlines from a map of meters. That makes a meter change trivial, but bar fill becomes a property of the whole score, and every per-bar consumer needs an index from time to events. The other is a normalized store of entities with foreign keys and undo by inverse patches. Its correctness then depends on hand-written rules that say which bars a patch touches, and a missed rule under-reports a change without any error. Per-bar consumers are the main readers of a score, so the bar stays the container.

## Every bar is full

The `MeasureColumn` constructor throws an `ArgumentError` when a voice of a staff does not span exactly the bar's length. So an overfull bar cannot exist, and an underfull bar cannot exist by accident. Underfill is always explicit. A pickup bar sets `irregularLength`. Voices two to four say "nothing here" with a `Gap`, which MusicXML calls `<forward>`. Voice one never holds a gap. It holds rests.

Because an invalid bar cannot be built, no layout, playback or edit code ever asks whether a bar is valid. The cost moves to the edits, which must decide what happens to music that does not fit. Each one states its policy:

- Note entry overwrites what was there. Nothing moves in time unless the edit asks to ripple.
- A note longer than the room left in its bar splits at the barline and ties into the next bar, with `Overfill.splitAndTie`. With `Overfill.refuse` the edit is refused with `WouldCrossBarline`, which an app can show as "needs a bar line".
- A meter change re-bars the music up to the next meter change, one section at a time, with `MeterContent.rebar`. With `MeterContent.keepBars` each bar keeps its content. Re-barring never deletes a bar. Surplus bars stay, filled with rests, so an edit never removes a container the composer made.
- With `Ripple.part` or `Ripple.staff`, note entry, rest entry, `SetValue` and `Erase` push or pull the later music of one part or one staff, inside one section. Every voice of those staves moves together, because a ripple in one voice alone would put it out of step with the others.

## Every bar describes itself

Each `MeasureColumn` stores its own meter and key, and each `StaffMeasure` stores the clef in effect at its start. A printed change is not stored. It is derived by comparing a bar with the bar before it. So a view of bar 40 needs no scan of bars 1 to 39 to know that bar 40 is in 3/4, and a cache keyed on a bar's column holds everything that bar depends on.

The price is paid in three edits. `SetKey`, `SetClef` and `SetMeter` write the new value forward through the run of bars that carried the old one. The JSON format reverses the trade at its boundary. It writes meter, key and clef only where they change, as a reader expects, and the loader fills them into every bar again.

## Values that share structure

Every container in the tree holds its children in a `Seq`, an immutable sequence whose updates return a new sequence. An edit rebuilds only the path from the changed leaf to the root, which is the event, its voice, its staff measure, its column and the list of columns. Every other column is the same object in the old score and the new one. For a 500-bar score, one note edit copies one list of about 500 pointers, about 4 KB.

`Seq` and `Score` compare by identity on purpose. Two scores are the same only if they are the same object. That one decision gives the model three properties at no extra cost:

- Undo can keep whole scores, because consecutive scores share almost everything.
- Change tracking is a pointer comparison per bar. See [Views are derived](#views-are-derived).
- A per-bar cache can key on the column object. `PlaybackCompiler` keeps each bar's compiled notes in an `Expando` on its column, so after an edit it compiles only the columns that are new.

## Ids name things across edits

Every durable entity has a typed id. The kinds are `PartId`, `StaffId`, `MeasureId`, `EventId`, `NoteId`, `TupletId` and `SpannerId`. Each is an extension type over `int`, so passing a bar id where an event id is expected does not compile.

Ids come from one counter that the `EditSession` owns. Every kind of id draws from it, so no two entities of a score share a value, whatever their kinds. No constructor mints an id, and nothing is random. `Score.blank` numbers its entities from 1 in document order, and `EditSession.start` resumes one past the largest id already in its score. Building the same score with the same edits gives the same ids, and ids survive a JSON save and load unchanged.

Undo does not rewind the counter. An id that an undone edit minted is never minted again in that session. So anything that holds an old id, such as a playback script, a highlight or a selection, can find that its entity is gone, but it can never find a different entity under the same id.

Each kind of id stays valid across a different set of edits:

- A `PartId` names its part through hiding and through a change of instrument, until the part is removed.
- A `StaffId` names its staff wherever the staff sits in system order, until its part is removed or a change of instrument drops the staff.
- A `MeasureId` stays the same when other bars are inserted or deleted. Layout caches key on it, and the printed bar number is derived. Re-barring reuses the ids of the bars it rewrites, in order, so a bar id can come to hold different music.
- An `EventId` stays the same when re-barring moves its event into another bar.
- A `NoteId` names one head of a chord. Ties, fingerings and strings attach to heads, and a selection can hold one head.

An `EventRef` names an event by its id, and also carries the bar that held the event when the reference was made. Two references are equal when their ids are equal, whatever bar they name. The bar is a hint for the fast path. `Score.lookup` looks in the hinted bar first. When a re-bar has moved the event, it falls back to `Score.locate`, an index from event id to bar that a score builds the first time a lookup misses. Only re-barring moves events between bars, so ordinary editing never builds that index.

## Time and pitch are exact

All notated time is a `Fraction` of a whole note, so a triplet eighth is exactly 1/12 and bar fill is an exact equality. Seconds appear only in playback output. Two extension types over `Fraction` keep points and spans apart. A `Moment` is a point in a bar, and a `Length` is a span, such as a duration or a bar's capacity. A `Moment` plus a `Length` is a `Moment`, and the distance between two moments is a `Length`. Adding two moments does not compile.

A `Pitch` is spelled. It is a letter (`Step`), an octave and an `Alter`, never a MIDI number or a staff line. `Alter` counts quarter tones from a double flat (−4) to a double sharp (+4), and its factory refuses anything outside that range. Spelling is what gives diatonic transposition, enharmonic choice and automatic accidentals a defined meaning. An `Interval` has letter steps and semitones, so an augmented second and a minor third are different intervals. `Pitch.transpose` moves the letter by the steps and picks the alteration that gives the semitones, so C4 up a diminished fourth is F♭4. When that would need more than a double sharp or flat, it spells the same sound as the key spells it.

A note stores its concert pitch, the pitch that sounds. The written pitch, after an instrument's transposition and any octave line, is derived per staff in `StaffView.writtenPitches`. So playback never has to undo a transposition or an 8va line, and `SetKey` keeps every note's sounding pitch and changes only the printed accidentals. `SetClef` keeps the pitches too, and the notes move on the staff.

A percussion staff holds `DrumNote`s. Each one names a `Drum` of its part's kit, such as the snare, not a pitch that stands for a staff position. So no feature that reads pitch needs a drum exception.

## Rhythm is spelled by rule

An edit sometimes has to write a length that no single note value has. It happens when a note splits at a barline, when rests fill what an overwrite left, and when re-barring cuts music into new bars. `Meter.spell` turns such a span into note values that respect the meter's beats, and rests split more readily than notes. The values a composer enters are written as entered. Only the pieces that a split or a fill creates are spelled.

A note starts on a whole number of 128th notes into its bar, or into the written time of the tuplet that holds it. Entry, tuplets and paste refuse any other start with `InvalidValue`. Without that grid, some starts would have no spelling at all.

## Ties, spanners and marks

A tie is a flag on the `Note` where it starts. Its end is derived. It is the head of the same tone in the next event of the same voice, which may be in the next bar. So a tie cannot point at a head that is gone. A tie with no matching head draws as a short let-ring tie.

Marks that cross barlines belong to no single bar, so a `Spanner` sits in `Score.spanners`, beside the bars. Its ends are `ScorePoint`s, a bar id and a `Moment` in that bar, not events. Overwriting a note under a slur keeps the slur, and inserting bars inside a hairpin stretches it. When an overwrite leaves no event starting at an end, the view attaches that end to the event sounding there. Voice one fills every bar, so such an event always exists.

A single note is a `ChordEvent` with one head, so stem, flag and accidental logic exists once. Grace notes hang off the chord they ornament and take no time in the voice. Marks split by whether they stack. `Event.articulations` is a set, so a note can carry staccato, accent and fermata at once. Marks that exclude each other are single fields. `ChordEvent.ornament` holds at most one ornament, and `ChordEvent.bowing` holds up-bow or down-bow, never both.

## Edits are data, and the session is a value

An `Edit` is plain data that names its targets, such as a bar id, a `VoicePoint` or an `EventRef`. It never reads a hidden "current cursor", so an edit means the same thing whenever it runs. `Edit` is a sealed class, so code that handles every edit is checked for completeness.

`EditSession` is an immutable value that holds the current score, the cursor, the selection, the undo and redo history, and the id counter. An app keeps one in a field and replaces it after each call. It has eight operations: `start`, `run`, `undo`, `redo`, `select`, `placeCursor`, `moveCursor` and `copy`. Behind them is all the hard work, and none of it is public.

`run(edit)` returns `Applied` with the next session or `Refused` with the same session and an `EditRefusal`. It does not throw for a bad value. A refusal is an expected outcome, such as `WouldCrossBarline`, `StaleReference` for a target that an earlier edit removed, or `InvalidValue`, and the app shows it as a message. Each applied edit is one undo step, and a `Batch` groups several edits into one. An edit that changes nothing returns the same score and records no step.

In overwrite mode, note and rest entry, paste, tuplet entry and value changes all write through one private function. So these edits cannot disagree about how music is cut and tied at a barline.

Undo keeps snapshots. Each history entry holds the score, the cursor and the selection from before an edit, and `undo` swaps them back. Snapshots are cheap because consecutive scores share every column the edit did not touch. A history entry holds a fresh `Score` wrapper over those shared children, so the lazy indexes of an old score are not kept alive for each step. The history keeps 200 steps unless the app sets another `historyLimit`.

The alternative is undo by inverse edits. It uses less memory, but every edit then needs an exact inverse, and the inverse of a re-bar is as hard as the re-bar itself. Snapshots make undo correct for every edit with no extra code.

## Views are derived

Layout reads the model through two calls. `Score.measureView(id)` returns a `MeasureView` with everything needed to draw one bar: its column, which signatures it prints, its staves with their voices, resolved accidentals, beam groups, ties, tuplets and written pitches, and the spanner segments that touch it. A view is never stored or kept in sync. It is a pure function of the score, computed on demand. It reads its own column, both neighbours, and the spanners touching the bar, and nothing else.

`Score.changesSince(previous)` says which bars' views may differ from those of an earlier score. It works by identity. A bar is in `ScoreChanges.relayout` when it is new, when it or either neighbour is a different object, or when a spanner that covers it was added or removed. Neighbours count because a view reads the previous bar for printed changes and arriving ties, and the next bar for tie targets and volta ends. When the parts change, every bar is relaid out. `ScoreChanges.removed` names the bars that are gone, and `ScoreChanges.reflow` says that the sequence of bars, the parts or a forced line break changed, so lines must be broken again. The result is conservative. It never misses a change, because nothing records changes by hand, and it may include a neighbour that turns out identical.

## One rule for each value

The rules that a stored value keeps live in one internal file, `lib/src/rules.dart`. Each function takes a value and returns why it breaks its rule, or null. Every way into a score uses the same function. An edit refuses with that message as `InvalidValue`. The JSON loader fails with it at the value's path in the file. `Score.blank` throws it as an `ArgumentError`. MusicXML import refuses with it too.

One set of rules means that an edit can never store a value that the loader would then refuse. Examples are an infinite tempo, a meter of 4/3, a MIDI program of 200, and a pitch above MIDI key 127. Two of the rules exist to keep hostile input from stalling or crashing an app. A bar lasts at most 64 whole notes, because filling a bar with rests costs time in proportion to its length. Tuplets nest at most 16 deep, because reading a voice recurses once per level.

The shape of a whole score is checked at the boundary. `scoreFromJson` always refuses a file whose bars do not hold one entry per staff, whose ids repeat, or whose spanners name a bar or a staff that the score lacks. Inside the library, the `Score` constructor asserts the same shape in debug builds: every bar lists the parts' staves in system order, no two bars share an id, and every spanner names a bar and a staff of the score.

## Where to go next

[Architecture](/khuur_sheet_music/explanation/architecture/) shows where the model sits among the three packages. [The layout engine](/khuur_sheet_music/explanation/layout-engine/) explains what layout does with `measureView` and `changesSince`. [Edit by tap](/khuur_sheet_music/guides/edit-by-tap/) shows an `EditSession` in an app.
