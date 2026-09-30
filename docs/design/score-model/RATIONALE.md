# Score model: measure-major nested tree

## Problem

A notation editor needs an immutable, pure-Dart score model. Layout, painting, playback, editing and persistence all derive from it. The current engine fails in ways that come from its shape. Model, layout and paint are fused. Durations are `double`. Pitch is a 52-value enum with display-only accidentals. Clef and key do not cross barlines. `Note` and `ChordNote` duplicate code. IDs are random UUIDs minted in constructors. There is no cache, and playback is monophonic. Voices, staves, ties, tuplets, undo and selection do not exist. The grounding for all of this is in [`grounding.md`](grounding.md).

The constraints make the shape non-obvious. A single-note edit in a 500-bar, 4-staff score must not force a whole-score relayout or recompile, and the consumer must be able to tell which bars changed. Undo must share structure instead of making deep copies. Identity must survive edits, undo and a JSON round trip. The model must also carry Maestro's full scope. That means voices, tuplets, grace notes, quarter tones, twelve clefs (Maestro has nine), mid-score changes, voltas, D.C./D.S./coda, lyrics in any script, and string marks such as fingering, string numbers and bowing. The library is open source and stays general. The Khuur composer is its first consumer, and nothing in the model is specific to it.

This design makes the measure the organizing unit, as MuseScore and MusicXML's `score-timewise` do. A bar is a real container that the composer fills.

## Usage (caller's view)

This was written first. The full file is [`packages/score_model/example/usage.dart`](../../../packages/score_model/example/usage.dart), which type-checks against the model.

```dart
final score = Score.blank(
  title: 'Étude',
  parts: [PartTemplate(name: 'Violin', instrument: violin)],
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
6. **Change tracking is pointer identity.** An edit rebuilds only the path event → voice → staff measure → column → column list. Every other column is the same object in the old and new score. `changesSince` compares columns by identity. It marks a bar when the bar or either neighbour is a different object, because a view reads the previous bar for printed changes, arriving ties and courtesy accidentals and the next bar for tie targets and volta ends. It also marks the bars covered by added or removed spanners. It costs O(bars + spanners) pointer checks. It can't under-report, because nothing records changes by hand.
7. **Pitch is spelled and concert.** `Pitch(step, octave, Alter)` uses a range-checked quarter-tone `Alter`. `Pitch.transpose(Interval(steps, semitones))` spells correctly, so C4 up a diminished fourth gives F♭4. Written pitch (instrument transposition, 8va lines) is derived in `StaffView.writtenPitches`, so playback never applies 8va or transposition.
8. **Marks split by whether they stack.** `Event.articulations` is a set of marks that stack (staccato, accent, tenuto, fermata and so on). Marks that exclude each other are single nullable fields on `ChordEvent`. `ornament` holds at most one of trill, mordent or turn. `bowing` holds up or down. A string note can carry down-bow, accent and trill at once, and it can't carry up-bow and down-bow at once.
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
- **Cursor revalidation is simpler than "nearest".** `_revalidateCursor` keeps the cursor while its bar and staff exist. It moves the cursor to the bar start when the bar got too short, and to the first bar when the bar is gone. Finding the nearest surviving bar needs the previous score. Unit 6 resolved this when `DeleteMeasures` arrived.
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

### Unit 3: measure view

Implemented in Phase D, unit 3. It covers access pattern 5 through `Score.measureView`, `Meter.beamBreaks`, `MeasureView.isRestOnly` and `Instrument.writtenKey`. The builder lives in `measure_view.dart` and beaming in `beaming.dart`. Neither is exported. The deviations below have not yet been reviewed by the project owner.

- **`StaffView.writtenPitches` replaces `StaffView.writtenPitch(Note)`.** A view is a plain value, and the method would have needed the octave lines and the instrument it was built from. The map is computed with the view, like `accidentals`, and covers grace notes too.
- **Percussion prints no key.** `Instrument.writtenKey` gives C for a percussion instrument and the transposed concert key otherwise. `contextAt` and `StaffView.writtenKey` both use it. Without this, a drum staff in D major would carry two sharps and print naturals on its C and F positions.
- **A mode-only key change prints nothing.** `keyChanged` compares `fifths`, so D major to B minor draws no signature. `previousKey` is null at the first bar.
- **Default beam breaks follow one rule.** A simple bar up to 3/4 beams whole. A longer simple bar with an even numerator breaks at the half bar. Everything else breaks per beat, which means per dotted beat in compound meters and per group in additive meters. An ungrouped 7/8 therefore beams per eighth, which is why a meter carries its grouping.
- **Beaming rules.** Eighths and shorter beam together until a note of a quarter or longer, `BeamMode.none` or `BeamMode.begin`, a change of enclosing tuplet, or a meter beam break interrupts them. A rest breaks the beam only when the notes on either side sit in different beats. `BeamMode.join` overrides the tuplet, meter and rest breaks. A group holding sixteenths or shorter then splits per beat, except at a join. Secondary beams break where two sixteenths or shorter meet on a multiple of the meter's unit, so six 6/8 sixteenths break after the second and fourth. Grace notes are not beamed by the view.
- **Accidentals are resolved at written pitch.** Heads across all voices of the staff are read by onset, grace notes before any chord at the same onset, then in voice order. An alteration holds at its written staff position and octave until the barline. `never` prints nothing and leaves that state alone. `always` and `cautionary` print and set it. Under `auto`, a note tied in from the previous bar prints nothing and leaves the state alone, so the next note at that position reprints against the key signature.
- **A tie lands only on the adjacent event.** Its target is the next event of the voice when that event starts where the tied one ends, or the voice's opening event in the next bar when the tied one ends the bar. A gap, an absent voice or no note of the same concert pitch gives a let-ring tie with `to` null. `crossesBarline` is set only for a tie that lands in the next bar. `tiedIn` applies the same rule from the previous bar, so the two views agree.
- **Spanner segments come from visible staves only.** A segment's `to` is the last anchor's offset in the bar where the spanner ends, and the bar length elsewhere. An octave line covers its anchors inclusively, as in `contextAt`.
- **`isRestOnly` is conservative.** Every voice of every visible staff must be a single `MeasureRest`, the bar must have its regular length, and nothing may be printed in or around it. That rules out spanners, directions, clef, key and meter changes, tempo marks, rehearsal marks, repeats, voltas, navigation marks and any barline other than a regular one. A mark that wouldn't actually break a multi-measure rest still does.
- **Tuplet views are in pre-order.** An outer tuplet comes before the tuplets it holds. Each lists the ids of every event inside it, nested ones included.

### Unit 4: change tracking

Implemented in Phase D, unit 4. It covers `Score.changesSince`, which lets layout redo only the bars an edit touched. The deviations below have not yet been reviewed by the project owner.

- **Both neighbours are marked, without conditions.** The pseudocode marked a bar after a changed one, and marked the bar before a changed one only when a tie crossed into it. A view also reads the next bar for `voltaEnds`, so giving bar 6 the volta of bar 5 moves the end of bar 5's bracket with no tie involved. A bar is now relaid out when it is new, when it or either neighbour is a different object than before, or when a spanner covering it was added or removed. Neighbours are compared by identity, so an inserted or deleted bar marks the bars on both sides of it.
- **Bar numbers are left out of `relayout`.** An insert or delete moves `MeasureView.index` for every later bar. `reflow` already tells layout to break lines again, which renumbers, so `relayout` does not list those bars.
- **A parts change relays out every bar and still reports removed bars.** The pseudocode returned `ScoreChanges.all`, which reports nothing removed and would leave stale entries in a layout cache.
- **A reorder relays out every bar.** A reorder can carry a bar into or out of an unchanged spanner's range while its neighbours stay the same. No edit reorders bars today, so the fallback costs nothing in practice and keeps the result correct for any two scores that share parts.
- **Spanners are diffed by identity.** An added spanner marks the bars it covers in the new score. A removed one marks the bars it covered in the old score that still exist. A spanner kept as the same object marks nothing, because surviving bars keep their order.
- **`Score.meta` is not compared.** No measure view reads it.

### Unit 5: point edits

Implemented in Phase D, unit 5. It covers `RemoveNote`, `SetPitch`, `SetTie`, `AddGrace`, `SetArticulation`, `SetOrnament`, `SetBowing`, `SetFingering`, `SetString`, `SetAccidental` and `SetLyric`. The deviations below have not yet been reviewed by the project owner.

- **`RemoveNote` clears the tie into the removed head.** The sketch said a point edit touches one column. A tie from the event before, which may sit in the bar before, would otherwise turn silently into a let-ring tie. Note entry already clears a tie that leads into new music, so removal follows the same rule.
- **The last head leaves a rest that keeps only a fermata.** Ornament, bowing, graces, lyrics and the other articulations go with the chord, because a rest can't carry them.
- **A rest carries only a fermata.** `SetArticulation` refuses any other articulation on a rest with `InvalidValue`. `SetOrnament`, `SetBowing`, `SetLyric` and `AddGrace` refuse a rest. Clearing any of them on a rest changes nothing, so a caller can clear without checking what the event is.
- **`SetPitch` follows the tie chain both ways.** It walks heads of the old pitch through adjacent events of the voice, across barlines, and stops at a gap, the same way `measureView` draws ties. It refuses with `InvalidValue` when any chord in the chain already has the new pitch, rather than merging two heads.
- **`SetTie` only sets the flag.** The sketch said it may touch the next column. It never does, because the tie's end is derived. A tie with no matching head draws as let-ring.
- **`AddGrace` adds the new grace chord nearest the principal.**
- **`SetFingering` refuses a negative finger and nothing else.** The upper bound depends on the instrument, and the model keeps fingering a free integer.
- **`SetString` refuses an index the part's instrument doesn't have.**
- **`SetLyric` refuses a verse below 1 and a lyric whose own verse differs from the edit's.** Lyrics stay in verse order. `Lyric` now has value equality, so setting the same lyric again changes nothing.
- **An edit that changes nothing returns the same score.** The session then records no undo step, as it already did for `AddToChord`.

### Unit 6: bar edits

Implemented in Phase D, unit 6. It covers `InsertMeasures`, `DeleteMeasures`, `SetBarLength`, `SetBarline`, `SetRepeatStart`, `SetRepeatEnd`, `SetVolta`, `SetNavigation` and `SetRehearsal`. The deviations below have not yet been reviewed by the project owner.

- **A bar edit clears a tie whose end head changes.** A tie's end is derived from the next event, so adding, removing or cutting time can silently retarget it. `_untieAt` compares the head a tie meets before and after the edit, and clears the flag when they differ, including a let-ring tie that now meets a head and a tie whose head went away. A let-ring tie that still meets nothing is kept. Insert, delete, shorten and lengthen all go through this one rule.
- **Inserted bars carry on the music's context.** They take the meter and key of the bar before and its closing clefs, or the first bar's opening clefs when inserted at the start. They join a volta only when the bars on both sides share it. Barlines, repeats, navigation, rehearsal marks and tempo stay on the bars that had them.
- **Spanners stretch over inserted bars and are clipped by deleted time.** Anchors are `ScorePoint`s, so an insert needs no change to them. For removed time, a start moves to where the music resumes, which is the next bar's start, and an end moves to the last onset before the cut in the spanner's voice. A spanner is dropped when both ends are removed, when one end has nowhere to go, or when it would start where it ends.
- **`DeleteMeasures` takes its two bars in either order.** It refuses with `WouldEmptyScore` when every bar would go. Tempo marks and dynamics in deleted bars are lost, as in MuseScore. That is an open question below.
- **`SetBarLength` normalizes and refuses.** A length equal to the meter's is stored as null, so restoring a bar needs no special value. A length that is not a positive whole number of 128th notes is refused with `InvalidValue`, because `spellOnGrid` cannot write it.
- **Shortening a bar cuts the crossing event.** The event keeps its head and loses its tail, so a chord becomes tied pieces as in note entry. A tuplet that crosses the new end is refused with `WouldSplitTuplet`. Clef changes, directions and tempo marks at or past the new end are dropped.
- **Lengthening a bar pads it.** Voice one gets rests spelled on the bar's beat grid. Other voices get a gap, merged into a trailing gap when there is one. A measure rest stays a measure rest with the new span.
- **Bar marks validate their values.** `SetVolta` refuses endings that are empty, start below 1 or are not strictly ascending. `SetRehearsal` treats empty text as clearing the mark. Navigation marks now have value equality, so setting the same mark again changes nothing.
- **The cursor moves to the nearest surviving bar.** When its bar is deleted, `_revalidateCursor` finds the first surviving bar after it in the previous score, else the last one before it. This settles the Unit 1 note.
- **Ids implement `Object`.** The typed ids are now `extension type const X(int value) implements Object`, so a bar edit's `StaleReference` names the `MeasureId` it was given. Note entry still reports its `VoicePoint`, which is what that edit named.
- **An edit that changes nothing returns the same score**, as in unit 5. Setting a mark to its current value, or a length to the current one, records no undo step.

### Unit 7: meter changes

Implemented in Phase D, unit 7. It covers `SetMeter` with both `MeterContent` policies, in `rebar.dart`. The deviations below have not yet been reviewed by the project owner.

- **Sections break at more barlines.** The sketch named repeat signs, volta boundaries, key changes, double and final barlines, and pickups. A rehearsal mark, a navigation mark and any barline other than a plain one also end a section, because each is structure the composer placed on that barline. A Segno or Coda belongs to the bar it opens and ToCoda, Fine and jumps to the bar they close, so each stays on its bar.
- **An irregular bar keeps its content.** A pickup or other irregular bar is a section of its own. It takes the new meter, and its `irregularLength` becomes null when it equals the new meter's length.
- **Trailing gaps are elastic, and a fermata rest is not.** Gaps at the end of a second voice are dropped like trailing rests. A rest with a fermata is music, so it keeps its time.
- **A meter of the same length only replaces the meter.** 4/4 to common time changes no bar's content, ids or marks.
- **Marks in dropped time are dropped.** Tempo marks, directions and clef changes move by absolute time. Trailing rests that were dropped leave time that no longer exists, and marks there are lost. A spanner start there moves to the bar after the section, and an end moves back to the last onset in the section's last bar.
- **The cursor and a range follow the music.** The sketch left them to revalidation, which would reset a cursor to its bar's start. They now move by time like spanner ends. A range that ends up empty becomes no selection.
- **Spanner moving is one helper.** `_moveSpanners` now serves `DeleteMeasures`, `SetBarLength` and `SetMeter`. It drops a spanner that would no longer start before it ends, which includes one whose ends now cross, where unit 6 dropped only one that collapsed to a point.
- **`keepBars` is the same engine.** Every bar is its own section that may not grow. A bar that still overflows after its trailing rests are dropped is refused with `WouldCrossBarline`. When a bar gets shorter, marks past its new end are dropped, so "anchors are untouched" holds only for a bar that grows.
- **The tie rule follows unit 6.** A section that used to end on the next bar's music and now ends on rests, or the reverse, clears the ties of its last event that meet the next bar's opening chord. This includes the last note of a tuplet.
- **Every piece of a split hidden rest stays hidden.** Mutation testing found that only the first piece kept `hidden`. The fix is in `_restPieces`, which note entry also uses when it cuts a rest.

### Unit 8: key, clef and tempo

Implemented in Phase D, unit 8. It covers `SetClef` and `SetTempoMarks` in `_context`, and fixes `SetKey`. The deviations below have not yet been reviewed by the project owner.

- **`SetKey` refuses a bar that is gone.** It threw `ArgumentError` from `Score.indexOf`. It now resolves its bar through `_barIndex`, like every bar edit.
- **A bar's clef changes stay canonical.** A change to the clef already in effect is dropped, whether it was given or left redundant by the edit. So setting the clef in effect removes a change, and setting the same clef twice changes nothing.
- **A clef runs on from the end of the bar.** The sketch described two cases, a start clef that replaces the old one up to the next change and a mid-bar change that propagates from the next bar. Both are one rule. When the edited bar now ends in another clef, each following bar that opens in the old ending clef takes the new one. The run stops at a bar that opens in another clef or still ends as it did before.
- **`SetClef` refuses instead of throwing.** A staff that is gone is `StaleReference(staff)`, and a time outside the bar is `OutsideMeasure`.
- **`SetTempoMarks` sorts and validates.** Marks are stored in time order. A mark outside the bar is `OutsideMeasure` at that time, and two marks at one time are `InvalidValue`, because playback could not tell which applies. The constructor's `ArgumentError` is no longer reachable through an edit.
- **`TempoMark` and `ClefChange` have value equality**, as navigation marks got in unit 6, so an equal value is a no-op. Unit 7's re-barring still reuses an unmoved tempo, which now keeps it the same object rather than keeping it equal.
- **The `changesSince` sweep runs `SetKey` and `SetClef`** instead of setting one bar's key or clef by hand.

### Scope: a general library

Accepted by the project owner on 2026-09-30. `simple_sheet_music` is an open-source library, so the model stays general. The Khuur composer is its first consumer, and its designs are direction for that app, not requirements for the library.

- **The library ships no instruments.** `Instrument` is a plain const value, so each app defines the instruments it offers. `Instrument.morinKhuur` was removed. The tests keep a two-string fiddle as test data in `support.dart`.
- **Examples and docs use general instruments.** The usage example defines a violin.
- **The Khuur screens need no instrument-specific marks.** They use fingering, accidentals, accents, hairpins, slurs, ties and dynamics, which the model already has. They also use tempo text with a metronome mark, title, lyricist and composer, range copy, cut and paste, undo and redo, and playback with a moving cursor.
- **Exporting a MIDI file belongs in the library.** It builds on `PlaybackCompiler`, and any app can use it. Audio export, an instrument view that follows playback, note names in a given language and left-handed layouts stay in apps. An instrument view reads `sourcesAt` for what is sounding and `Note.string` and `Note.fingering` for where it is played.

## Open questions and risks

Each question is filed under the point it must be answered by. An answer that changes a stored type gets more expensive with every layer built on it, and once the save format is released it also means migrating other people's saved scores. An answer that changes one function's behaviour, or only adds a value, stays cheap. The deviations under units 1 to 8 that the project owner has not reviewed are behaviour too, so they can be reviewed any time before the release.

**Before the layout engine starts.** These decide how layout is built.

- Do manual system breaks belong in v1? They are not modeled, and they change how line breaking is designed.
- Should restated or courtesy signatures be representable, with a `restate` flag on the column?

**Before the save format is released.** These change stored types.

- On percussion parts, `Note.pitch` is a display position mapped through `Instrument.drums`, which breaks the concert-pitch rule. Should unpitched notes get their own note type? If v1 ships without percussion, this can wait.
- Grace heads can't be named by a `NoteRef`, because `ChordEvent.note` finds only principal heads. No edit can yet repitch or remove one grace note. Should grace chords get their own reference? The editing surface needs this answer before it is built.
- Do gradual tempo changes (rit., accel.) belong in v1? Neither is modeled.

**Any time, including after the release.** Each changes one edit or playback, or adds a value old saves never contain.

- Which string-technique marks belong in v1 beyond fingering, string numbers, bowing and the common ornaments? Harmonics, pizzicato and glissando are candidates.
- Does Maestro push later notes forward when you enter into a full bar? If users expect insert mode, is an `InsertTime` edit batched with `EnterNote` enough? It would have to ripple every voice on the staff together, because a one-voice ripple desyncs the others. Trying it in Maestro answers the first question.
- Should a tap read accidentals earlier in the bar, as MuseScore does? `pitchForStaffStep` reads only the key signature, so after an F♯ in C major a tap on the F line enters F natural, which then prints a natural sign. `measureView` now resolves the accidental state per staff, so reading it is possible. Trying it in Maestro answers this.
- Is "re-barring never removes bars" the right call, or should surplus bars that are entirely empty be dropped? `SetMeter` keeps them until this is answered.
- Deleting bars drops the tempo marks and dynamics written in them, so the music after the cut can play at the wrong tempo or volume. Should `DeleteMeasures` carry the tempo and dynamic in effect onto the next surviving bar?
- A pickup bar beams and resolves beats from its own start, not aligned to the end of a full bar. Five eighths in a 4/4 pickup beam as four plus one, where aligning them to the bar's end would give one plus four. Should `irregularLength` bars shift the beat grid?
- Should hidden parts play? The sketch says yes.
- Quarter tones use channel-wide pitch bend, so a chord mixing a quarter-tone note and a plain note on one channel can't sound correctly. Is it acceptable to allocate an extra channel per part when needed?

## Next implementation step

Units 1 to 8 (note entry, tap to enter, chords, cursor moves, the measure view, change tracking, the point edits, the bar edits, meter changes, and key, clef and tempo) are done. The model now answers everything layout reads, so the Flutter layout engine can start against `measureView` and `changesSince`. On the model side the marks in `_marks` (`SetDirections`, `AddSpanner`, `RemoveSpanner`) come next. The `changesSince` sweep already drives the bar edits, `SetMeter`, `SetKey` and `SetClef`. Once the marks land it should drive them too, replacing its hand-built spanner edits. Stubs left are 7 in `apply.dart`, 6 in `playback.dart`, 2 each in `json.dart` and `musicxml.dart`, and 1 each in `lane_writer.dart` and `session.dart`.

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

`score.changesSince(lastLaidOut)` says which bars changed. A changed bar marks its two neighbours, not a cascade to the end. The cost of a view is proportional to the bar plus the spanner count, and no other bar is walked.

**6. Compile playback.** `PlaybackCompiler.compile(score, options)` runs in three steps.
1. `_playOrder` unrolls `repeatStart`, `repeatEnd.times`, `Volta.endings`, `Segno`, `Coda`, `ToCoda`, `Fine` and `Jump` into (bar, pass) pairs. Codas are honoured.
2. One fold over bar-level facts gives each played bar a start time in seconds, a tempo map and its entry dynamics.
3. Each bar's fragment comes from the `Expando` cache keyed by column, or is compiled on a miss. Compiling merges tie chains through `Note.tie` into one attack. It applies dynamics, hairpins and accents to velocity, shapes note lengths from articulations, and realizes grace notes, tremolos and ornaments.

`notesBetween` converts to seconds lazily. `sourcesAt(seconds)` binary-searches the played bars, then the fragment, and returns `EventRef`s for highlighting. A one-note edit recompiles one fragment.

**7. Save and load.** `scoreToJson` walks the tree. IDs are written as integers, and meter, key and clef are written only where they change. `scoreFromJson` checks the schema version and runs migrations. It fills meter, key and clef back into every bar and rebuilds through the public constructors, which re-check fill. Then it runs the cross-structure checks for unique IDs, staff order and spanner anchors. `EditSession.start` seeds the counter at the largest ID plus one, so IDs are preserved and never reissued.

**8. Change the time signature mid-score.** `SetMeter(from, meter, content)` sets the scope to the run of bars that carried the old meter, up to the next different meter.
- A meter of the same length only replaces the meter.
- With `MeterContent.rebar` (the default), the scope is split into sections at structural barlines. Those are repeat signs, volta boundaries, key changes, rehearsal and navigation marks, and any barline other than a plain one. A pickup or other irregular bar is a section of its own and keeps its content. In each section every lane is streamed end to end. Trailing rests and gaps are trimmed, because they are elastic. The stream is cut at the new bar length. Notes that cross a new barline are split and tied, and the last bar is padded. Old bar IDs are reused in order. Tempo marks, directions, clef changes, spanner anchors, the cursor and a range selection are re-anchored by absolute time, and marks in trimmed time are dropped. A section never loses bars. A tuplet crossing a new barline returns `Refused(WouldSplitTuplet)`. Events that moved to another bar still resolve through `locate`.
- With `MeterContent.keepBars`, every bar keeps its content. Trailing rests are dropped, a bar that is still too long returns `Refused(WouldCrossBarline)`, and a short bar is padded. Pickup bars keep their irregular length. IDs are untouched, and marks past a shortened bar's end are dropped.

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
- Unit 3 adds 49 tests in `measure_view_test.dart`, for 130 in all, and all pass. They cover beam breaks in nine meters, meter, key and volta flags, visible staves, clef changes carried over a mid-bar change, written keys and pitches for a B♭ clarinet, a drum staff and 8va lines, events, gaps and nested tuplets, ties within and across bars and past gaps, accidentals (key, bar, octave, barline, voices, tie arrivals, requests, transposition, quarter tones, graces), beaming (meter groups, sixteenths, rests, tuplets, every `BeamMode`, secondary breaks), spanner segments and `isRestOnly`.
  - Thirty mutations of the new code were each caught. Four survived the first run: a join inside a sixteenth run, an 8va line on another staff of the part, a voice-two tie ending before the barline, and a grace note in voice two beside a chord in voice one. Each now has a test that fails under its mutation.
- Unit 4 adds 12 tests in `changes_test.dart`, for 142 in all, and all pass. They cover an unchanged score, an edited bar and its neighbours, both ends of the score, two edits that must not cascade, undo in both directions, inserted and deleted bars, a parts change, added and removed spanners including one over a deleted bar, and a hand-built reorder. A seeded sweep makes 450 random edits across note entry in two voices, voltas, keys, clefs, spanners, inserted and deleted bars and hiding a part. After each edit it checks `removed` and `reflow` exactly, and checks that every bar whose view differs in anything but its index is in `relayout`.
  - Thirteen of 14 mutations were caught, among them dropping either neighbour check, the spanner diff, the filter on removed spanners and the reorder fallback. The survivor sets `reflow` only for new bars and a shorter score, which gives the same answer once a reorder falls back to every bar.
  - The sweep first failed on its own ids. Its counter and `EditSession` both issued ids, so after the sweep deleted a bar it had inserted, the session could start below the counter and a measure id appeared twice. The sweep now counts its ids down from -1.
- Unit 5 adds 23 tests in `point_edits_test.dart`, for 165 in all, and all pass. They cover removing a head and the last head, the tie cleared into a removed head, tie chains across the barline, through chords and stopped by a gap, pitch collisions anywhere in a chain, every mark on chords and rests, string and finger bounds, lyric order and replacement, an event inside a tuplet, no-op edits keeping the same score, and a stale reference refused by every point edit.
  - Thirty-three mutations were each caught by a failing assertion. The first run needed three fixes. Two mutations only broke compilation and were rewritten. One survived, because re-setting verse 2 last put the lyrics back in order by accident, and the test now checks the order before that step.
- Unit 6 adds 23 tests in `bar_edits_test.dart`, for 188 in all, and all pass. They cover inserting at the start, middle and end with a piano's clefs, a key change and a clef change, joining a volta, spanners stretched over new bars, deleting in either order, refusing an empty score, the tie rule on insert, delete, shorten and lengthen, a let-ring tie that meets a gap, spanners clipped or dropped by a delete, the cursor moving to the nearest bar, cutting and padding every voice kind, measure rests, marks and spanners past a new end, length refusals, every bar mark, no-op edits keeping the same score, and a stale reference refused by every bar edit. The `changesSince` sweep now runs `InsertMeasures`, `DeleteMeasures`, `SetVolta` and `SetBarLength` through a real session instead of building those bars by hand.
  - Forty-eight mutations were each caught by a failing assertion. The first run needed four fixes. Two mutations did not match their anchor and were rewritten, one only broke compilation and was rewritten, and one survived. The survivor let the tie check skip a gap at the start of the next bar, and the let-ring gap test was added for it.
- Unit 7 adds 48 tests in `meter_test.dart`, for 236 in all, and all pass. They cover re-barring end to end, notes split and tied across one or more new barlines, trailing rests dropped, sections that never lose bars, measure rests turned into rests, fermata rests kept, hidden rests split and kept hidden, second voices (padding, a bar without the voice, merged gaps, a trailing gap), every staff getting the same bars, the tuplet refusal, the scope ending at the next meter, no-op and same-length meters, a stale reference, every section boundary, irregular bars kept, tempo, direction, clef and spanner moves and drops, the tie rule both ways including a tuplet's last note, `keepBars` padding, exact fit, refusal and lengthening, and the cursor and range following the music, including dropped time and bars before the scope. The `changesSince` sweep now also runs `SetMeter` with both policies.
  - Eighty-two mutations of `rebar.dart` and the helpers it shares with the bar edits and the lane writer were each caught. Before the first run, tracing each branch against the tests found gaps in gap splitting and merging, an irregular bar after regular ones, ties that must stay, a tuplet's last note, dropped-time ranges and several mark fields, and tests were added for them. The first run of 81 then needed ten fixes. Three mutations only broke compilation. Two were rewritten, and dropping the key was removed because a required parameter guards it. Seven survived. Tests were added for five of them: points before the scope, a `keepBars` bar that fits exactly, an unmoved tempo and direction staying the same object, and a chord symbol's bass. `TempoMark` has no value equality, so reusing the object is what keeps an unmoved tempo equal. One was equivalent, because streams for absent voices become gaps that the voice filter drops, so the guard was deleted. The last found the hidden-rest bug above. Its test failed with `Actual: [[true], [false]]` before the fix.
- Unit 8 adds 24 tests in `context_test.dart`, for 260 in all, and all pass. They cover a stale `SetKey`, a start clef running to the next clef, stopping at a change inside a bar and after a bar that ends as before, redundant changes dropped at the start and mid-bar, one staff of a piano, notes left alone, adding, replacing and removing a change mid-bar, carrying nothing on before a later change, no-op clefs, each refusal, and tempo marks sorted, equal, differing in the metronome flag, outside the bar, doubled and stale. The first test of `SetKey` failed with `Invalid argument (id): no such measure: 999` before the fix.
  - Twenty-three mutations were each caught. The first run caught 18. Four survivors got tests: the run's ending clef not updated after a bar, the clef in effect not tracked while dropping changes, `ClefChange` compared by identity, and the metronome flag ignored. One only broke compilation and was rewritten. It then survived too, because the two equal tempo marks in its test were both `const` and so the same object. One is now built at run time.
- Synthesis review caught two pseudocode bugs, which are fixed. `changesSince` marked a bar dirty whenever its predecessor was marked, which would have cascaded one edit to the last bar. It now tests the set of identity-changed columns, a rule unit 4 replaced with neighbour identity. The `keepBars` branch used the scope's end before computing it.
