---
title: The playback timeline
description: Why ScorePlayer plays a precomputed playback script from one clock, and how the sheet stays in step with the sound.
sidebar:
  order: 4
---

`ScorePlayer` does not read the score while it plays. It first compiles the score into a `PlaybackScript`, which is every note the score sounds, placed in seconds. Then it plays that list from one clock. The sheet reads the same clock through the player's `position`. This page explains why playback has that shape and how its parts fit together. To play a score in an app, see [Play a score](/khuur_sheet_music/guides/play-a-score/).

## A script is the score as it sounds

`PlaybackCompiler.compile` takes a `Score` and an optional `PlaybackOptions`, and returns a `PlaybackScript`. The script holds the following:

- `totalSeconds`, how long the script plays.
- `channels`, one `ChannelSetup` for each part that is heard, with its MIDI channel, program, bank and `expression`.
- `bars`, the bars in the order they play. Each `PlayedBar` has its `measure`, its `pass`, and its `start` and `end` in seconds.
- The notes, which `notesBetween` returns for a window of seconds, sorted by start. Each `PlaybackNote` has a `start`, a `duration`, a MIDI `key`, `cents` for a quarter tone, a `velocity`, a `channel`, and the `source` event that produced it.

Three queries connect script seconds and the score. `secondsAt` gives the first time a `ScorePoint` plays. `pointAt` gives the bar, the pass and the offset into the bar at a given second. `playingAt` gives the events that sound at a given second, one per voice.

### Why the score is compiled first

A player that walked the score live would have to answer hard questions at the moment each note is due. Where does this end repeat go back to? Was the D.S. taken already? How loud is this chord, halfway through a hairpin that started two bars ago? When does a note end that is tied into the next bar played, which has another tempo? Each answer depends on music before or after the note, sometimes far from it. The compiler answers all of them once, in order, over the whole score. What is left for the player is a list sorted by time. It sleeps until the next note starts or ends or a channel's expression changes, sends that, and sleeps again.

The same script serves three readers. The player sends its notes. The sheet asks `pointAt` and `playingAt` where to draw the playhead and what to highlight. `scoreToMidi` writes a MIDI file from it, so the file plays what the player plays. Because all three read one script, they cannot disagree about a repeat or a dynamic.

Recompiling after an edit is cheap. The compiler caches each bar's notes, in whole-note time, on the bar's column object. An edit replaces only the columns it touches, so a one-note edit recompiles one bar. The rest runs on every compile. It unrolls the repeats, folds tempo and dynamics over the bars, and places each played bar in seconds. `ScorePlayer` owns one `PlaybackCompiler`, so every `play` reuses the cache.

A script is immutable, and the player compiles only in `play`. An edit made while the score plays is heard from the next `play`. There is no separate seek. To start somewhere else, call `play` again with `startAt`.

## Repeats and jumps unroll into a play order

The compiler turns repeat signs, voltas and navigation marks into a list of bars, each with a pass number. `PlayedBar.pass` counts how many times that bar has played, this time included. A bar played again after a D.C. reports pass 2, even with no repeat sign near it. An app can show "2nd time" from it.

The compiler unrolls the score by these rules:

- An end repeat returns to the last start repeat. With no start repeat, it returns to the bar after the previous repeated section, or else to the start of the score.
- A bar under a volta plays on the passes that its endings list. A repeated section ends after its endings, so a later end repeat returns to the bar after them.
- A D.C. or a D.S. is taken once, after the repeats of its bar are done. A D.S. with no segno goes to the start.
- After the jump, no repeat is taken, and of each run of voltas only the last ending plays. The jump's `JumpThen` says whether a Fine stops playback and whether a To Coda leaves for the coda, once.
- A guard stops the order at 64 times the number of bars, so a malformed score cannot loop forever.

## A range plays once, and a loop wraps the script

`PlaybackOptions.from` and `PlaybackOptions.to` limit the script to `[from, to)`. A range plays in notated order with repeats and jumps ignored, and its script starts at zero at `from`. It plays the part of each bar that lies inside it, and strikes the notes that start inside it. A note tied into `from` is struck at `from`. `secondsAt` returns null for a point outside the range.

`PlaybackOptions.muted` leaves parts silent. A muted part gets no channel setup and no notes, and its events are not in `playingAt`. It keeps its place in the channel order, so muting one part never moves another part to a new channel. Pitched parts take channels 0 to 15 in score order, skipping 9, and percussion parts share channel 9.

The script itself has no loop. With `loop: true`, `ScorePlayer.play` plays the script again from zero each time it reaches the end, until `stop`. A loop over a range is a range script that wraps.

## Dynamics become velocities, and marks become lengths

A MIDI note has one velocity, fixed when it is struck. So the compiler works out every note's velocity in advance, and for a part that swells, how its channel's expression moves while the note sounds. It reads loudness in notated order, as it reads tempo. Each part starts at mf, and a level dynamic sets the part's level until the next one:

| Dynamic | pppp | ppp | pp | p | mp | mf | f | ff | fff | ffff |
|---|---|---|---|---|---|---|---|---|---|---|
| Velocity | 12 | 20 | 31 | 42 | 53 | 64 | 80 | 96 | 112 | 127 |

sf and rfz strike the chords at their time at velocity 100, and sfz at 110. All three leave the level as it was. fp strikes at 80 and then sets the level to p. A dynamic on any staff of a part applies to the whole part, so one mark between the staves of a piano serves both hands.

A hairpin ramps the velocity in a straight line over notated time. It runs to the first level dynamic written after its start, no later than the end of its last event. It arrives at that dynamic when the dynamic lies the way the hairpin moves, louder for a crescendo and softer for a diminuendo. Otherwise it moves one level up or down, and the dynamic takes over where it stands, so a crescendo that ends on a softer dynamic grows and then drops. With no such dynamic, the hairpin moves one level and leaves the part there. Each chord strikes at the ramp's value at its onset.

An accent strikes at 1.25 times the dynamic's velocity, and a marcato at 1.5 times, up to 127. Because the level is read in notated order, a D.C. brings back the opening dynamic.

A part whose instrument has `singleNoteDynamics`, as a bowed string, a wind or a voice has, also carries its level on its channel's expression, MIDI controller 11, so a held note follows the dynamics while it sounds, as in MuseScore 4. Each `ChannelSetup` has an `Expression`, a list of points that each hold a value until the next. Under a hairpin it moves in steps, one a sixteenth and at least 24. fp eases from f to p in six steps over 0.4 seconds, and sf, sfz and rfz hold their level until the next note or rest on their staff starts, or the bar ends. Below velocity 84 the expression is the level times 127 / 84 and the note strikes at 84 times its accents, so it starts about as loud as on a part that does not swell, unless it has both an accent and a marcato. From 84 up the expression is full and the velocity carries the level, so a held note does not swell past about f. A piano, a guitar, a harp or a kit keeps full expression and plays its level on velocity alone, as does a part that shares its channel. The player sends each channel's value before its first note and wherever it changes, and sets it again after a seek, a pause, a loop or a new score. `scoreToMidi` writes the same points. `SynthOutput` sends the expression to FluidSynth as controller 11.

Articulations set how long a note sounds. A note sounds 0.99 of its written time by default, as an unmarked note of a string, a wind or a voice does in MuseScore 4, so a long note stops just short of the next. A staccato sounds half of it, a staccatissimo a quarter, a staccato under a tenuto three quarters, and a tenuto all of it. A slurred note with none of those marks sounds all of its time. When the next note of its voice starts as it ends, it runs 40 milliseconds into that note, so a synthesizer does not dip between the two. Each note of a trill, a mordent, a turn or a tremolo sounds until the next one starts, and the marks on the chord set the length of the last. A `Glissando` moves the note it starts on a semitone at a time toward the note it ends on, in equal steps over the first chord's time, as MuseScore 4 plays a chromatic glissando. Its `from` and `to` name the two notes. A named end is on its note in whichever voice of the staff plays it, and an end that names none is on its own voice's chord. A start that names no note is on that chord's top note. A last end that names none is on the note as far from the bottom of its chord as the start note is from the bottom of its own, or on the top note when the chord has fewer notes, as MuseScore 4 picks the end of a new glissando. So a line from a single note ends on the bottom note of a chord. Where its voice has no event, the end is on the event of voice one. A last end that would then lie on an event voice one has held since the line's first note or before, through any ties, is on the chord another voice starts there instead, when there is one. `AddSpanner` names the two notes it picks, and each edit first names them for a line that names none, so adding or removing another note of either chord later leaves the line on its notes, as MuseScore 4 keeps the notes a glissando was made between. An edit that moves a named note, or shortens it from its end, moves that end to where the note starts. An edit that removes a named note removes the line with it, as MuseScore 4 does. A shorter `SetValue`, or a ripple that removes part of a chord's time, removes each line that starts on that chord, as MuseScore 4 does too. Each step sounds until the next one starts, and the marks on the chord set the length of the last. The other notes of the chord hold, and a chord with two lines glides each note along its own. MuseScore also bends the pitch smoothly for an instrument whose glissando style is portamento, such as bowed and plucked strings, voices, trombones, timpani and many synths, and it plays a harp glissando on the harp's scale. `MidiOutput` has no pitch bend, so every part plays the chromatic steps.

Tied notes sound as one note as long as all of them, so a chain without marks sounds 0.99 of its whole length. A mark on a note of the chain sets the length from that note to the end of the chain, and the last marked note counts.

A `PedalLine` holds the notes of its part until the pedal lifts. The compiler lengthens those notes itself, and the output never receives a pedal message. That keeps the pedal out of `MidiOutput`, and means a pause, a new start point or a loop never has to put a pedal back down.

## Tempo is part of the script

Tempo is also read in notated order. Music before the first tempo mark plays at 100 quarter notes a minute, which is `Tempo.unmarked`. A bar starts at the last tempo written before it in the score, not the last tempo that played, so a D.C. brings back the opening tempo. A `TempoLine` (rit. or accel.) moves the tempo in a straight line to the next tempo mark. With no mark before the line ends, it reaches its start tempo times its `factor`, and the music stays at that tempo after it. A fermata on any staff makes the time under it pass at half speed, so every part holds together.

The compiler gives each played bar a clock that maps whole notes into the bar to seconds. It places every note with that clock, and `pointAt` is its inverse. So the playhead stays correct under a fermata, a tempo line or a tempo mark inside a bar, on every pass through the bar.

Script seconds are seconds at the written tempo. `ScorePlayer.tempoScale` makes the whole script faster or slower without a new compile.

## One clock maps wall time to script seconds

The player keeps one clock for each run. The clock is an anchor, made of a wall time and the script second at that time, and a scale:

```text
script seconds = anchor seconds + scale × (now − anchor wall time)
```

Two readers share the clock. A one-shot timer reads it to find the next script second at which a note starts or ends, converts that second back to a wall time, and sleeps until then. When it wakes, it sends what is due. A ticker reads the clock once per frame and publishes `position`. Neither reader keeps time of its own, so the sound and the playhead cannot drift apart.

The timer does not wait for a frame. Sound goes on when nothing repaints, for example while the app's tickers are muted. For the same reason, the timer owns the end of playback and the wrap of a loop, and the ticker only publishes.

The timer runs on the UI isolate, because `MidiOutput.noteOn` takes no timestamp. A note is late by as long as the isolate is busy when the note is due, which is at most one build or one layout. A note that starts and ends while the isolate is busy is not sent.

## Speed, pause and resume move the anchor

Every change of speed moves the anchor to the present first, and then sets the new scale. When you set `tempoScale` to 0.5, the clock keeps its script second and runs at half speed from there. The position does not jump, and the next note sounds at the new speed. The player cancels the note timer and sets it again from the new anchor.

`pause` is a change of speed to zero. The clock stops at the current script second, the player lets go of every sounding note, and the ticker stops. `resume` moves the anchor to the present at the current `tempoScale`, so playback goes on from the same script second. A note that `pause` cut short is not struck again.

The wrap of a loop works the other way. When the clock passes `totalSeconds`, the player keeps the anchor and moves the clock back by whole multiples of the script's length. A timer that wakes slightly early or late does not change where the next pass starts, so each pass of the loop lasts exactly as long as the script.

`play` with `startAt` starts the clock at the point's `secondsAt`, which is the first time that point plays. A point outside the script starts at zero. A note that started before the start point stays silent.

These rules give the player a small set of promises that hold in any order of `play`, `pause`, `resume`, `tempoScale`, `stop` and a SoundFont load that finishes or fails:

- While the player is idle, loading or paused, no key is held.
- Notes go out only while the player is playing.
- The player never strikes a key that is already held on that channel. It lets go of the key first, and holds it to the later of the two ends.
- While playing, exactly one note timer is pending, and the player asks for frames. Otherwise no timer is pending and no frame is asked for.
- While the player is idle or loading, `position` is null, also for a listener of `status`.

## The player sends notes through `MidiOutput`

`MidiOutput` is the interface between the player and sound. It has eight calls: `load`, `program`, `noteOn`, `expression`, `noteOff`, `allNotesOff`, `rest` and `dispose`. The player waits for `load` and for every `program`. It sends notes and expressions without waiting, because a note that waited for an answer would be late. `rest` says that no note comes before the next `program`. The player sends it when the score ends, on `stop` and after a `play` that failed, and not on `pause`. An output can hold several SoundFonts, and each SoundFont has its own 16 channels, so channel 0 of one SoundFont is not channel 0 of another.

The interface exists for two reasons. The first is that sound is platform-specific. `SynthOutput`, the default output, plays through FluidSynth from `khuur_synth`, on Android and iOS only. It opens the audio device on each `program` and closes it once the notes ring out after `rest`, so a pause keeps the device open. An app that plays through another synthesizer passes its own `MidiOutput` as `output`. [SoundFonts and reverb](/khuur_sheet_music/guides/soundfonts-and-reverb/) covers the options of `SynthOutput`.

The second reason is testing. A test passes a fake output that records each call, and a `now` function that reads a clock the test controls:

```dart
ScorePlayer playerUnderTest(
  TickerProvider vsync,
  MidiOutput recorder,
  Duration Function() now,
) => ScorePlayer(
  soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
  vsync: vsync,
  output: recorder,
  now: now,
);
```

In a widget test, `vsync` is the `WidgetTester`, `now` returns the time since the test began on `tester.binding.clock`, and `recorder` implements `MidiOutput` and appends each call to a list. `tester.pump` then moves the wall clock and the note timer together, and the test compares the notes it recorded, with their times, to what the score should play. `now` must never go back. The player disposes the output when it is disposed itself. The package's own player tests work this way, with hand-written fakes and no mocking package.

## The sheet follows the sound

`SheetView` takes its `playback` as a `ValueListenable<PlaybackPosition?>`, usually `ScorePlayer.position`. The view does not depend on the player. A test, or an app that plays some other way, can drive it with a `ValueNotifier`.

While the player plays, its ticker publishes a `PlaybackPosition` on each frame. The position holds the script `seconds`, the `point` from `pointAt`, and the `playing` events from `playingAt`. On a pause it publishes once more and then holds. It is null while the player is idle or loading.

The painters that draw the highlight and the playhead listen to `playback` directly. A tick repaints them without a build and without touching the view's state. Each system's engraving has a `RepaintBoundary` of its own, so a tick does not redraw the notes under the highlight.

The sheet draws two things from the position:

- The playing events take the palette's playback style. They are one event per voice, and rests count, so the reader keeps their place through a rest. The box is one column down the system, over the events that started last. It covers each chord's heads, accidentals and dots, and not its grace notes, which sound off the beat, or its ties and marks, which may reach into the next bar. A bar rest is centred in its bar, so it gives the column its width only when nothing else started with it. A note held from an earlier beat takes the playback ink too, and stays out of the column. `playingAt` includes events on hidden staves, because a hidden part plays, and the sheet skips the events it did not draw.
- The playhead, when the palette gives it a width. `SheetPalette.of` gives it zero width, so by default it draws none. Its x comes from the offset into the bar, in whole notes, mapped through the bar's spacing. So it meets each onset as that onset sounds, and between onsets it moves at the pace of the spacing, not of time. When the bar that plays next is the next bar drawn on the same system, the playhead runs from the bar's last onset to that bar's downbeat. Otherwise, as at a repeat or the end of a system, it runs to the barline.

With `followPlayback`, which is on by default, the view scrolls a system to the top when the playhead enters it and the system is not wholly in view. The playhead enters a system when its bar is on another system than its last bar was. So a user who scrolls away during playback is not pulled back on every tick, nor when a zoom, a resize or an edit breaks the lines again. In a system taller than the view, `playbackStaff` names the staff to keep in view.

For how the layout places bars and onsets on a system, see [The layout engine](/khuur_sheet_music/explanation/layout-engine/).
