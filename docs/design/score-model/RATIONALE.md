# Score model: measure-major nested tree

## Problem

The Khuur composer needs an immutable, pure-Dart score model. Layout, painting, playback, editing and persistence all derive from it. The current engine fails in ways that come from its shape. Model, layout and paint are fused. Durations are `double`. Pitch is a 52-value enum with display-only accidentals. Clef and key do not cross barlines. `Note` and `ChordNote` duplicate code. IDs are random UUIDs minted in constructors. There is no cache, and playback is monophonic. Voices, staves, ties, tuplets, undo and selection do not exist. The grounding for all of this is in [`grounding.md`](grounding.md).

The constraints make the shape non-obvious. A single-note edit in a 500-bar, 4-staff score must not force a whole-score relayout or recompile, and the consumer must be able to tell which bars changed. Undo must share structure instead of making deep copies. Identity must survive edits, undo and a JSON round trip. The model must also carry Maestro's full scope. That means voices, tuplets, grace notes, quarter tones, twelve clefs (Maestro has nine), mid-score changes, voltas, D.C./D.S./coda, lyrics in Mongolian Cyrillic, and morin khuur marks.

This design makes the measure the organizing unit, as MuseScore and MusicXML's `score-timewise` do. A bar is a real container that the composer fills.

## Usage (caller's view)

This was written first. The full file is [`packages/score_model/example/usage.dart`](../../../packages/score_model/example/usage.dart), which type-checks against the model.

```dart
final score = Score.blank(
  title: 'Жороо морь',
  parts: [PartTemplate(name: 'Морин хуур', instrument: Instrument.morinKhuur)],
  measureCount: 8,
  meter: Meter.fourFour,
  key: const KeySignature(-1),
);
var session = EditSession.start(score);
session = session.run(EnterNote(
    at: session.cursor, pitch: Pitch.parse('F4'), value: NoteValue.quarter)).session;
```

The composer controller is a `ChangeNotifier` in the app.

```dart
void onStaffTap(StaffHit hit) {
  final pitch = score.pitchForStaffStep(hit.staff, hit.at, hit.staffStep);
  _run(EnterNote(
    at: VoicePoint(staff: hit.staff, voice: inputVoice, at: hit.at),
    pitch: pitch,
    value: inputValue,
    overfill: overfill, // splitAndTie, or refuse for Maestro's "need a bar line"
  ));
}

void _run(Edit edit) {
  switch (_session.run(edit)) {
    case Applied(:final session): _session = session; lastRefusal = null;
    case Refused(:final reason):  lastRefusal = reason;
  }
  notifyListeners();
}
```

The layout engine relays out only what changed.

```dart
final changes = previous == null ? ScoreChanges.all(score) : score.changesSince(previous);
changes.removed.forEach(_measures.remove);
for (final id in changes.relayout) {
  _measures[id] = _layoutMeasure(score.measureView(id));
}
```

Playback compiles a script and maps sounding notes back to events.

```dart
final script = compiler.compile(score, PlaybackOptions(from: sel.from, to: sel.to));
for (final n in script.notesBetween(t, t + 0.5)) { /* n.start, n.key, n.velocity, n.duration, n.channel, n.source */ }
final lit = script.sourcesAt(playhead); // List<EventRef>
```

## Shape

```
Score
├─ parts: Seq<Part>                 who plays: instrument, staves, hidden flag
├─ measures: Seq<MeasureColumn>     the global, ordered list of bars
│   └─ MeasureColumn  id · meter · key · irregularLength · barline · repeatStart
│      │              repeatEnd · volta · navigation · rehearsal · tempos
│      └─ staves: Seq<StaffMeasure>   staff · clef (at bar start) · clefChanges · directions
│          └─ voices: Seq<Voice>        slot one..four
│              └─ items: Seq<VoiceItem> = Gap | Content
│                   Content = Event (ChordEvent | RestEvent | MeasureRest) | Tuplet(members: Seq<Content>)
│                   ChordEvent  notes · articulations (a set) · ornament? · bowing? · graces · lyrics
│                   Note        id · concert Pitch · tie flag · fingering · string
└─ spanners: Seq<Spanner>           slur, hairpin, 8va, trill, pedal, gliss; anchored at ScorePoint(MeasureId, Moment)
```

These are the load-bearing decisions.

1. **The fill invariant lives in the `MeasureColumn` constructor.** Every voice of every staff spans exactly `column.length`, and the column can't be built otherwise. Underfill is always explicit. A pickup or cadenza bar sets `irregularLength`, and voices two to four say "nothing here" with a `Gap` (MusicXML's `<forward>`). Voice one never has gaps. It has rests. Three policies follow. Note entry overwrites. Overfill splits and ties at the barline, or refuses when the app asks for that. A meter change re-bars or keeps bars. No layout, playback or edit code ever asks whether a bar is valid. The old engine compared doubles with `!=` at render time. Here, an invalid bar can't be built, per **type-system-discipline** (make illegal states unrepresentable).
2. **Bars are self-describing.** Each column stores its own meter and concert key, and each `StaffMeasure` stores the clef in effect at its start. A printed change is derived by comparing a bar with the previous one. Context resolution is O(1) and needs no index. Per-bar caches keyed on the column are complete. The old "clef lost after bar 1" bug can't happen, because no bar depends on scanning earlier bars. The price is `_propagate`, which three edits (`SetKey`, `SetClef`, `SetMeter`) use to rewrite the run of bars that carried the old value. The fact "bar 40 is in 3/4" is stored once, in bar 40. The bar is the unit every consumer works in, so the structure follows it, per **model-the-domain**.
3. **Ties are note flags. Spanners are score-level and anchored by time.** A tie always joins adjacent events in one voice. So `Note.tie` holds only the start, the end is derived, and a tie end can never dangle. Things that cross barlines belong to no single bar, so they sit beside the column list. They are anchored at `ScorePoint(MeasureId, Moment)`, the way MuseScore anchors spanners by tick. Overwriting a note under a slur keeps the slur. Inserting bars inside a hairpin stretches it without any fix-up. If an overwrite leaves no event starting at an anchor, the view attaches to the event sounding there. Voice one fills every bar, so that event always exists.
4. **Identity uses typed integer IDs from one monotonic session counter.** `EventId`, `NoteId`, `MeasureId` and the rest are extension types over `int`, so they can't be mixed up. Nothing mints an ID in a constructor, and nothing is random. Undo doesn't rewind the counter, so a stale ID never aliases a new entity. An `EventRef` is equal to another by `EventId` alone. Its `MeasureId` is a hint for the fast path. When re-barring has moved the event, `Score.lookup` misses the hint and falls back to `Score.locate`, a lazy event-to-measure index built on the first miss. Only re-barring moves events between measures, so the index is rarely built.
5. **Time points and time spans are different types.** `Moment` (a point in a bar, or an onset) and `Length` (a span, a duration, a capacity) are extension types over the exact `Fraction`. `Moment + Length` is a `Moment`. `Moment.until(Moment)` is a `Length`. Adding two moments does not compile. Two arguments that share a primitive but mean different things get brands, per **type-system-discipline**. The brand paid for itself during synthesis. It flagged the `MeasureColumn` constructor comparing a clef-change offset against the bar's capacity.
6. **Change tracking is pointer identity.** An edit rebuilds only the path event → voice → staff measure → column → column list. Every other column is the same object in the old and new score. `changesSince` compares columns by identity. It also marks the direct successor of a changed or re-parented bar (printed changes, arriving ties, courtesy accidentals) and the bars covered by changed spanners. It costs O(bars + spanners) pointer checks. It can't under-report, because nothing records changes by hand.
7. **Pitch is spelled and concert.** `Pitch(step, octave, Alter)` uses a range-checked quarter-tone `Alter`. `Pitch.transpose(Interval(steps, semitones))` spells correctly, so C4 up a diminished fourth gives F♭4. Written pitch (instrument transposition, 8va lines) is derived in `StaffView.writtenPitch`, so playback never applies 8va or transposition.
8. **Marks split by whether they stack.** `Event.articulations` is a set of marks that stack (staccato, accent, tenuto, fermata and so on). Marks that exclude each other are single nullable fields on `ChordEvent`. `ornament` holds at most one of trill, mordent or turn. `bowing` holds up or down. A morin khuur note can carry down-bow, accent and trill at once, and it can't carry up-bow and down-bow at once.
9. **One deep editing module.** `EditSession` is a value with eight public operations. They are `start`, `run`, `undo`, `redo`, `select`, `placeCursor`, `moveCursor` and `copy`. Edits are sealed plain data that name their targets. Behind that surface, one library holds everything that is hard. That includes the overwrite, split and tie engine (`_overwrite`, `_replaceSpan`), the re-barrer, forward propagation, ID minting, refusals, cursor revalidation and snapshot history. Every note-writing edit, including paste and lengthening, goes through `_overwrite`, so entry and paste can't disagree about barlines.
10. **Playback caches per column.** `PlaybackCompiler` keeps compiled bar fragments in an `Expando` keyed by the column object, in whole-note time. Each compile folds tempo and dynamics over bar-level facts and unrolls repeats. A one-note edit recompiles one fragment. Seconds are computed only for the window the player asks for.

Encoded in types:

- no gap inside a tuplet (`Tuplet.members: Seq<Content>`)
- grace notes can't float free (`ChordEvent.graces`)
- a single note is a one-note chord, so stem and accidental logic exists once
- IDs can't be mixed up, and neither can points and spans
- where a navigation mark takes effect is fixed by its class
- up-bow and down-bow can't both be set

The constructors check bar fill, tuplet fill, no gaps in voice one, voice slot order, and clef-change and tempo offsets. Only the boundary (`scoreFromJson`) checks staff order per column, unique IDs across the whole score, and spanner anchors. Debug asserts cover those elsewhere.

The sketch deliberately leaves out insert-mode ripple, polymeter (one meter per column), beams or tuplets across a barline, mid-bar key changes, cross-staff beaming, and stored restated signatures.

Interface depth. Layout sees two calls (`measureView`, `changesSince`) plus the read-only domain types. Playback sees `compile` and three query methods on the script. The editor sees `EditSession` plus edit data. Everything hard sits behind those surfaces. That covers overwrite, split, tie, re-bar, propagation, accidental rules, beaming, repeat unrolling and identity-keyed caching. The domain types are public because layout has to read events, notes and bar facts. They expose fields and `copyWith`, and no editing algorithms.

## Synthesis decision

Three runners sketched three structurally different shapes from the same grounding and rubric. C1 (Opus) is this measure-major nested tree. C2 (Fable) is stream-major, with absolute time, voice streams per staff and derived barlines. C3 (Sonnet) is a normalized entity store with inverse patches. All three passed `dart analyze`.

**Scores.** The cross-judge scored C1 24, C2 22 and C3 26, and recommended C3. My own scoring against the same rubric was C1 26, C2 23 and C3 22.

**Base: C1, overruling the judge.** The judge's case for C3 rested on three C1 defects and one principle. Each is answered.

- *Undo memory is O(bars) per step* (judge probe 1). The cause was a lazily built measure index that every snapshot kept alive. Graft G5 stores a fresh `Score` wrapper in each history entry, so the index is rebuilt on demand and never retained. What remains is a 4 KB pointer copy per step at 500 bars, about 800 KB for 200 steps. `Seq` can become a chunked trie behind the same API if that ever matters.
- *`EventRef` goes stale on re-bar.* Graft G3 makes the measure a hint and adds the lazy `locate` fallback. Equality ignores the hint.
- *No overfill policy or insert mode.* Graft G2 adds `Overfill`. Insert mode stays an open question below.
- *Per-column meter and key are two sources of truth.* They are one source per bar. Nothing else stores "bar 40 is in 3/4", and a printed change is derived. The judge listed "a column whose meter disagrees with its predecessor" as a representable illegal state. That state is a legal meter change. The real cost is that `_propagate` must be right in three edits, and that is accepted below.

C3 also carries machinery the rest of the design would have to trust. It has a hand-written HAMT (which the judge itself listed as a rejection), an integrity fixpoint over reverse indexes, an unsealed `Entity`, an unchecked `IdList.retype` cast and nine public tables. The judge made C3 conditional on four fixes. They were to seal `Entity`, delete `retype`, hide the tables, and range-check `Alter`. C1 needed none of them. C3's `ChangeSet.of` derives dirty measures from five hand-written closure rules, and a missed rule under-reports silently. C1's identity walk can't under-report. Choosing the shape with less machinery to get right is **laziness-protocol** applied to architecture.

**Grafts.** Each one was folded into the shape as if it had been there from day one, not bolted on beside it, per **redesign-from-first-principles**.

| Graft | Source | What changed |
|---|---|---|
| G1. Exclusive marks | C3 (marks as single values on the event) | `ChordEvent.ornament` and `ChordEvent.bowing`, the `Ornament` and `Bowing` enums, and the `SetOrnament` and `SetBowing` edits. `Articulation` keeps only marks that stack. |
| G2. Overfill policy | C3 `OverfillPolicy`, C2 `OverflowPolicy` | `Overfill { splitAndTie, refuse }` on `EnterNote`, `EnterRest` and `Paste`, and the `WouldCrossBarline` refusal. Maestro's "need a bar line" is `refuse`. |
| G3. Stable event refs | Judge finding; C3's O(1) `measureOf` | `EventRef` equality by id, the measure as a hint, and the lazy `Score.locate` index. |
| G4. Time brands | C2 `Moment` and `Length` | Every offset and onset is a `Moment`. Every duration, span and capacity is a `Length`. `Meter.spell`, `beatOffsets`, `beamBreaks`, `SetBarLength`, views and clip lanes use them. |
| G5. Undo memory | Judge finding | History entries hold a fresh `Score` wrapper over shared children. |
| G6. Meter content policy | C3 `MeterPolicy { reflow, keepBars }` | `SetMeter.content: MeterContent { rebar, keepBars }`. |

**Rejected, with reasons.**

- *C2's `FillReport`.* Fill is a constructor invariant here, so no underfull bar exists to report on.
- *C2's derived ties and `splitPoints`.* They lose the difference between a composer's tie and a barline split. Deleting one note deletes the chain. MusicXML `<tie>` pairs would need merging on import.
- *C2's spanners keyed by absolute time.* An absolute moment changes meaning whenever an earlier bar changes length. C1 anchors at a measure id plus a local offset, which only re-barring moves.
- *C2's `atMeasure: int` edit targets and chord marks keyed by moment.* Indices shift under the edit that uses them, and moment-keyed marks orphan when the rhythm changes.
- *C3's `ChangeSet.of` and `dirtySound`.* Identity comparison covers layout, and the `Expando` fragment cache covers playback without a second dirty set.
- *C3's HAMT tables and kind bits packed into IDs.* Typed extension types already stop mix-ups, and `Seq` plus structural sharing already gives cheap undo.
- *C3's `AccidentalDisplay` reasons.* Layout needs whether and which accidental to draw, not why.
- *`InputMode.insert` (C2, C3).* Left open below. C2's own rationale notes that a ripple within one voice desyncs it from the other voices.

**Convergence.** All three runners chose overwrite entry. C1 and C3 independently chose measure containers with split-and-tie at the barline. All three chose spelled pitch with a quarter-tone `Alter` and a spelled `Interval`. Independent agreement on these three points is strong evidence they are right.

## Tradeoffs accepted

- We accept copying the column-pointer array on every edit (about 4 KB at 500 bars, about 800 KB for 200 undo steps) in exchange for a `Seq` that is trivially correct and comparable by identity. A chunked trie can replace it behind the same API.
- We accept storing meter, key and clef in every bar, with propagation logic in three edits, in exchange for O(1) context, local validation and per-bar caches that capture everything a bar depends on.
- We accept rigid bars. Entry overwrites and never pushes music forward, and a re-barring meter change rewrites every bar up to the next meter change. In exchange, no bar in any score can be invalid, and no edit ripples across the whole score.
- We accept that re-barring never deletes bars (surplus bars stay, filled with rests) in exchange for never silently removing a composer's container.
- We accept that a redundant restated signature can't be represented (a 3/4 printed again where 3/4 already holds) in exchange for deriving what a change is rather than storing it.
- We accept an O(spanners) scan per `measureView` in exchange for having no spanner index to maintain. With hundreds of spanners this costs microseconds.
- We accept a lazy event-to-measure index, built only when a hinted lookup misses, in exchange for O(1) resolution in the common case and no index to maintain on every edit.
- We accept snapshot undo in exchange for undo that can't be wrong. No edit needs a hand-written inverse, which matters most for re-barring.
- We accept a private exception inside the engine for early exit on refusal. It never escapes `run`, which returns sealed `Applied` or `Refused`.

## Alternatives considered

- **Voice streams per staff, with barlines derived from a meter map (Dorico-like, C2's shape).** Meter changes and insert mode become trivial because barlines are just a view. But the bar stops being a container. Fill validation becomes a global property. Change tracking has to map edits to bars by time, and per-bar caches need an index from time to events. The MusicXML mapping becomes indirect. It hides more for meter changes and exposes more to every per-bar consumer. Per-bar consumers are the dominant access pattern, so it lost.
- **A normalized entity store with inverse patches (C3's shape).** Every relationship is a foreign key, and undo inverts a patch. It hides cascade and change tracking behind one reducer. But its correctness spans a transaction, a patch, closure rules, violations and repairs. The consumer sees nine tables unless an extra read layer hides them. It exposes more surface for the same capability, so it lost.
- **Store context changes sparsely** (meter, key or clef only where they change, as MusicXML does on disk). This is lighter to edit. But every context query scans back or needs a prefix index, and a column's layout would depend on data outside the column, which breaks identity-keyed caching. It survives only as the JSON wire format.
- **Spanners stored in the bar where they start.** Adding a slur would touch one column. But a later bar's view would have to scan back to find open spanners, and identity-based change tracking would miss the bar where the spanner ends. It lost.
- **Inverse-command undo.** It uses less memory, but every edit needs an exact inverse, and re-barring's inverse is as hard as re-barring. Snapshots plus structural sharing are cheap enough.

## Red-flag screen

Each flag from the architect red-flag list was checked against the synthesized sketch.

- **Shallow module.** None found. `EditSession` has eight operations over roughly forty edit types and hides the whole edit engine. `Score` exposes two read calls for layout. `Seq` is small, but it carries the identity semantics that change tracking relies on, so it earns its place.
- **Information leakage.** The per-bar context rule (store in every bar, derive changes) is known to `_propagate`, `measureView` and the JSON codec. The codec's sparse wire format is the one deliberate second encoding, and it is private to `io/json.dart`. `Clip`'s lanes are private, so paste's internal shape doesn't leak.
- **Temporal decomposition.** None found. Modules follow domain knowledge (time, pitch, events, measure, score, edit, views, playback, io), not execution order. Entry, paste and lengthening share one `_overwrite` instead of each running its own stages.
- **Pass-through method.** `MeasureColumn.withStaff` and `StaffMeasure.withVoice` look like forwarders. They are the single rebuild step on the path from leaf to root, and `withVoice` adds the rule that drops an all-gap secondary voice. The usage example's controller methods forward to `run`, but they belong to the app, not the model.

## Implementation reconciliation

### Unit 1: note and rest entry

Implemented in Phase D, unit 1. The deviations below were accepted during implementation and have not yet been reviewed by the project owner. Each one updates the contract the next unit builds on.

- **Package location.** The sketch moved from `docs/design/score-model/sketch/` to [`packages/score_model`](../../../packages/score_model), a pub workspace member of the root package. Root `flutter analyze` covers it. Its tests run with `dart test` inside the package, because root `flutter test` does not run workspace members.
- **Tuplet descent lives in `_overwrite`.** The sketch had `_replaceSpan` recurse into a tuplet that wholly contains the span. Now `_replaceSpan` replaces a span within one frame, either a bar's voice or a tuplet's members, given that frame's beat grid and whether leftover time becomes rests or gaps. `_overwrite` decides whether to descend, because only a piece's start can enter a tuplet. The continuation of a note tied over a barline never does, even when the next bar opens with a tuplet. The start of a tuplet counts as inside it.
- **A piece that starts in a tuplet must end in it.** Otherwise the edit is refused with `WouldSplitTuplet` naming the innermost tuplet that holds the start. The sketch only said the value is read in the tuplet's time.
- **Entered values are written as entered.** A piece that fits in its bar keeps its value. Only the parts of a piece split at a barline are spelled with `Meter.spell`. The pseudocode spelled every part, which would have written a half note on beat two of 4/4 as two tied quarters and contradicted `EnterNote`'s "writes a note of [value]".
- **Filling the last bar appends a bar.** A write that ends exactly at the end of the score appends one empty bar, so the cursor keeps its invariant of an offset strictly inside a bar.
- **Cursor revalidation is simpler than "nearest".** `_revalidateCursor` keeps the cursor while its bar and staff exist. It moves the cursor to the bar start when the bar got too short, and to the first bar when the bar is gone. Finding the nearest surviving bar needs the previous score. Revisit this with `DeleteMeasures`, the first edit that removes bars.
- **`StaleReference` names the edit's target.** Note entry at a missing measure or staff reports the `VoicePoint` it was given. The typed ids are extension types, which are not `Object`s, and the point is what the edit named.
- **`_Piece` is sealed.** `_Entry` is a chord, or a rest when it has no pitches. `_Copied` is a clip item for paste and is not implemented yet. This replaces the nullable `value` and `copied` fields.
- **Spelling rules.** `Meter.spell` is greedy. It takes the longest plain or single-dotted value that fits the remaining span and satisfies one of these:
  - it stays inside one beat;
  - on a compound or additive meter, it starts and ends on beats;
  - on a simple meter, a plain value starts on a multiple of its own length from the bar start, and a dotted note on a multiple of twice its base. A dotted rest never crosses a beat.

  A tuplet's members are spelled on one beat that spans the tuplet. A known limit is that in 3/4 a respelled span from beat two to the barline comes out as two tied quarters rather than a half. This affects only split and filler material, never an entered value.
- **Internal helpers.** `spelling.dart` holds `BeatGrid` and `spellOnGrid`. `voice_walk.dart` holds `timedEvents`, the tuplet-scaled walk that `lookup`, `locate`, `eventAt` and the lane writer share. `empty_bar.dart` builds the empty bars used by `Score.blank` and by appending at the end of the score. None of them are exported.
- **Lint.** `avoid_unused_constructor_parameters` is back on, since the factories it flagged are implemented.

### Unit 2: tap to enter a note or chord

Implemented in Phase D, unit 2. It covers access patterns 1 and 2 through `Score.contextAt`, `Score.pitchForStaffStep`, `KeySignature.transpose`, `Score.spannersTouching`, `AddToChord`, `EditSession.placeCursor` and `EditSession.moveCursor`. The deviations below have not yet been reviewed by the project owner.

- **The percussion clef reads like treble.** The sketch anchored G4 on the percussion clef's own line, which is the middle line, so a percussion staff read a third low. The clef now marks B4 there, and the bottom line is E4 as on a treble staff. This was a bug in the sketch.
- **A percussion tap ignores key, 8va and transposition.** `pitchForStaffStep` returns the natural position on the staff, which is what `Instrument.drums` maps. The pseudocode applied the key signature, which in D major would turn the F4 position into F♯4 and miss the drum map.
- **`Tempo.unmarked`.** Music before its first tempo mark plays at 100 quarter notes per minute. `contextAt` falls back to it, and `Score.blank` uses it as its default. Playback needs the same fallback.
- **An octave line covers its anchors inclusively.** A point is under the line from its first anchor through its last, compared by bar position and then offset. A tap later inside the last covered event is outside, because the new note would start after the line's last anchor.
- **`AddToChord` ties when any note of the chord is tied.** The sketch said the event's first note. The lowest note is an arbitrary choice, and "the chord continues into the next event" is what the tie means. The next event is found with `eventAt`, in the same bar or at the start of the next.
- **A measure rest becomes chords that fill the bar.** It has no value to keep, so the bar length is spelled with `Meter.spell` and the pieces are tied. The first keeps the rest's id and articulations. A 5/4 bar gives a whole note tied to a quarter.
- **Cursor moves.** Event moves stop at every event onset in the cursor's voice and at every bar start. That makes voices two to four, which can start with a gap or be absent, step bar by bar like voice one. `previousMeasure` goes to the start of the current bar before the previous one. Staff moves skip hidden parts. Every move leaves the cursor in place when there is nowhere to go.
- **`placeCursor` rejects points outside the score.** It throws `ArgumentError` for an unknown staff or bar, an offset outside `[0, length]`, and the end of the last bar, which has no next bar to snap to.

## Open questions and risks

- Does Maestro push later notes forward when you enter into a full bar? If users expect insert mode, is an `InsertTime` edit batched with `EnterNote` enough? It would have to ripple every voice on the staff together, because a one-voice ripple desyncs the others.
- Should restated or courtesy signatures be representable, with a `restate` flag on the column?
- Is "re-barring never removes bars" the right call, or should surplus bars that are entirely empty be dropped?
- On percussion parts, `Note.pitch` is a display position mapped through `Instrument.drums`, which breaks the concert-pitch rule. Should unpitched notes get their own note type?
- Quarter tones use channel-wide pitch bend, so a chord mixing a quarter-tone note and a plain note on one channel can't sound correctly. Is it acceptable to allocate an extra channel per part when needed?
- Which Mongolian-specific marks are missing? The morin khuur set (fingering 0 to 4, string index, up-bow, down-bow, the ornament enum) is a guess. The Figma file is still unread, because access failed on the account's View-only seat.
- Do gradual tempo changes (rit., accel.) and manual system breaks belong in v1? Neither is modeled.
- Should hidden parts play? The sketch says yes.
- Should a tap read accidentals earlier in the bar, as MuseScore does? `pitchForStaffStep` reads only the key signature, so after an F♯ in C major a tap on the F line enters F natural, which then prints a natural sign. Revisit when `measureView` resolves accidentals.

## Next implementation step

Units 1 and 2 (note entry, tap to enter, chords and cursor moves) are done. Next come `measureView` and `changesSince`, which the layout engine needs, with `Meter.beamBreaks` and `StaffView.writtenPitch` behind them.

## Access pattern traces

**1. Tap to enter a note.** The layout's hit test yields a staff, a `ScorePoint(measureId, Moment)` and a staff step. `Score.pitchForStaffStep` reads `StaffMeasure.clefAt(offset)` and `column.key`, both stored in the bar. It applies any 8va line from `spannersTouching` and converts written to concert pitch through `Instrument.transposition`. The controller runs `EnterNote(at, pitch, value, overfill)`. `EditSession.run` calls `_apply`, then `_overwrite`. That finds the column through `indexOf` and rebuilds the voice with `_replaceSpan`, where `Meter.spell` splits and re-spells the rest at the tap point. The staff measure and column are rebuilt, and the column constructor re-checks fill. One `replaceRange` completes the edit. The new session's cursor sits after the note, the new event is selected, and one snapshot is pushed.

**2. Enter a chord.** `AddToChord(event: selection.singleEvent, pitch)` goes to `_pointEdit`. It resolves the `EventRef` through `Score.lookup` (the hinted bar, or `locate` on a miss) and inserts a `Note` with a fresh `NoteId` into `ChordEvent.notes` in pitch order. A single note is already a `ChordEvent`, so nothing changes type. A rest becomes a one-note chord. One column is rebuilt. Adding a pitch the chord already has returns the identical score, and the session records no history entry.

**3. Copy, paste, transpose.** `select(RangeSelection(from, to, top, bottom))`, then `copy()` walks the columns from `from.measure` to `to.measure`. For each staff in the block it dissolves barlines into one timeline per voice of `(Moment offset, Content item)` pairs, keeping tied pieces tied. It also takes the spanners and directions inside the range. The result is an opaque `Clip`. `Paste(clip, at: cursor, overfill)` re-mints every ID and sends each lane through `_overwrite`. It follows the same barline rule as entry. It splits, ties and appends bars at the end if needed, or refuses with `WouldCrossBarline`. The pasted range becomes the selection. `Transpose(selection, Transposition.diatonic(1))` or `.chromatic(1)` reads `column.key` for each note's bar in O(1). It moves the spelled pitch, extends to whole tie chains, and rebuilds each touched column once.

**4. Undo and redo.** `undo()` pops a `_Snapshot(score, cursor, selection, label)` and pushes the current state, in a fresh wrapper, onto the redo stack. The ID counter is not rewound. Undo is a pointer swap. The restored columns are the original objects, so `changesSince` reports exactly the bars the edit had touched. A layout cache keyed on column identity could even reuse its old layouts.

**5. Lay out one measure.** `score.measureView(id)` returns the following.
- `column` gives meter, key, barline, repeats, volta, navigation and tempo, read directly.
- `meterChanged` and `keyChanged` come from comparing with the previous column, along with `previousKey` for cancellation naturals.
- Each visible staff gets a `StaffView` with the stored `clef`, `clefChanged`, `writtenKey` and its `VoiceView`s. Each `VoiceView` has `events` (a `TimedEvent` with a `Moment` onset and a `Length` duration, computed by walking items with tuplet scaling), `beams` (from `Meter.beamBreaks` plus each event's `BeamMode`) and `tuplets`.
- `accidentals` are resolved per staff across voices. Tie arrivals come from the previous bar's `Note.tie` flags.
- `ties` and `tiedIn` include ties that cross the barline.
- `spanners` arrive as `SpannerSegment`s with start and end flags.

`score.changesSince(lastLaidOut)` says which bars changed. A changed bar marks only its direct successor, not a cascade to the end. The cost of a view is proportional to the bar plus the spanner count, and no other bar is walked.

**6. Compile playback.** `PlaybackCompiler.compile(score, options)` runs in three steps.
1. `_playOrder` unrolls `repeatStart`, `repeatEnd.times`, `Volta.endings`, `Segno`, `Coda`, `ToCoda`, `Fine` and `Jump` into (bar, pass) pairs. Codas are honoured.
2. One fold over bar-level facts gives each played bar a start time in seconds, a tempo map and its entry dynamics.
3. Each bar's fragment comes from the `Expando` cache keyed by column, or is compiled on a miss. Compiling merges tie chains through `Note.tie` into one attack. It applies dynamics, hairpins and accents to velocity, shapes note lengths from articulations, and realizes grace notes, tremolos and ornaments.

`notesBetween` converts to seconds lazily. `sourcesAt(seconds)` binary-searches the played bars, then the fragment, and returns `EventRef`s for highlighting. A one-note edit recompiles one fragment.

**7. Save and load.** `scoreToJson` walks the tree. IDs are written as integers, and meter, key and clef are written only where they change. `scoreFromJson` checks the schema version and runs migrations. It fills meter, key and clef back into every bar and rebuilds through the public constructors, which re-check fill. Then it runs the cross-structure checks for unique IDs, staff order and spanner anchors. `EditSession.start` seeds the counter at the largest ID plus one, so IDs are preserved and never reissued.

**8. Change the time signature mid-score.** `SetMeter(from, meter, content)` sets the scope to the run of bars that carried the old meter, up to the next different meter.
- With `MeterContent.rebar` (the default), the scope is split into sections at structural barlines. Those are repeat signs, volta boundaries, key changes, double and final barlines, and pickups. In each section every lane is streamed end to end. Trailing rests are trimmed, because they are elastic. The stream is cut at the new bar length. Notes that cross a new barline are split and tied, and the last bar is padded. Old bar IDs are reused in order. Tempo marks, directions, clef changes and spanner anchors are re-anchored by absolute time. A section never loses bars. A tuplet crossing a new barline returns `Refused(WouldSplitTuplet)`. Events that moved to another bar still resolve through `locate`.
- With `MeterContent.keepBars`, every bar keeps its content. Trailing rests are dropped, a bar that is still too long returns `Refused(WouldCrossBarline)`, and a short bar is padded. Pickup bars keep their irregular length. IDs and anchors are untouched.

**9. Overfill a measure.** Bars are always exactly full, of rests at worst. So "inserting a quarter into a full bar" means overwriting the quarter's span at the cursor. A note longer than the room left is handled by `_overwrite` according to `Overfill`. With `splitAndTie` (the default) it writes the part that fits, tied, splits at the barline, and continues into the next bar under the same overwrite rule. If the note runs past the last bar, it appends a bar with the last bar's meter, key and clefs. With `refuse` the edit returns `Refused(WouldCrossBarline(measure, excess))`, which the app shows as Maestro's "need a bar line". Neither mode pushes later music forward. The default touches at most the bars the note spans (usually two), keeps every bar valid, matches what MuseScore users expect, and never shifts one staff against the others, as a ripple would in a multi-staff score.

**Where the direction strains.** It satisfies every pattern. Pattern 8 is the weakest. The bar is a container with a hard fill invariant, so a re-barring meter change has to rewrite every bar in its scope and re-anchor everything in them. Insert mode, which is not in the pattern list, would need the same re-bar machinery.

## Verification

- `dart analyze` on the sketch reported **No issues found!** under `pedantic_mono` 1.38.1. The package's [`analysis_options.yaml`](../../../packages/score_model/analysis_options.yaml) records the lints turned off and why.
- A scratch program outside the package exercised the implemented helpers, and all 13 checks passed. It confirmed the following.
  - A dotted quarter is exactly 3/8 and a double-dotted half 7/8.
  - C4 up `Interval(3, 4)` spells F♭4.
  - `Alter.fromQuarterTones` accepts +3 and rejects +5.
  - An eighth-note triplet spans a quarter, and the `Tuplet` constructor rejects two eighths under a 3:2 bracket.
  - The `MeasureColumn` constructor rejects a half-empty 4/4 bar and an overfull 3/4 bar, and accepts a triplet plus a half in 3/4.
  - `Moment` and `Length` arithmetic is exact.
  - `EventRef` equality ignores the measure hint.
- Unit 1 is covered by 48 tests in [`packages/score_model/test`](../../../packages/score_model/test), and all pass.
  - `spell_test.dart` has 18 tests. They cover beat offsets for simple, compound and additive meters, and spelling of notes and rests in 4/4, 6/8, 12/8 and 7/8. A sweep over every 1/32 span of 4/4, 3/4, 6/8 and 7/8 checks that each spelling sums to its span. A 1/12 span is an error.
  - `note_entry_test.dart` has 30 tests. They cover `Score.blank` ids, the session start, overwriting rests and notes (cut heads keep ids, tails become rests), split-and-tie and refusal at the barline, appended bars, clearing and keeping ties into the entry point, voice two gaps, writes inside, over and partly over a triplet, `EnterRest`, stale and outside points, undo and redo, id monotonicity, `lookup`, `locate` and `eventAt`, and revalidation after `SetKey`.
  - Five mutations of the lane writer were each caught by the test written for that behavior. The mutations were dropping the tie fix, not merging gaps, respelling entered values, not appending the cursor's bar, and untying head pieces.
- Unit 2 adds 33 tests in `tap_to_note_test.dart`, for 81 in all, and all pass. They cover written keys with enharmonic respelling, clef, key, meter, tempo and octave lines from `contextAt`, and taps through every clef family, key, clef change, 8va and 8vb, a B♭ clarinet and a drum staff. `AddToChord` is covered on chords, rests, measure rests in 4/4, 3/4 and 5/4, tuplet members, voice two, ties in and out, duplicates and stale references. The cursor tests cover snapping, rejection, and every `CursorMove` including tuplets, gaps and a hidden part.
  - Six mutations were each caught by the test written for that behavior. The mutations were counting another staff's octave line, taking a later tempo mark, dropping enharmonic respelling, adding a pitch the chord has, tying without checking the next event, and visiting hidden staves.
- Synthesis review caught two pseudocode bugs, which are fixed. `changesSince` marked a bar dirty whenever its predecessor was marked, which would have cascaded one edit to the last bar. It now tests the set of identity-changed columns. The `keepBars` branch used the scope's end before computing it.
