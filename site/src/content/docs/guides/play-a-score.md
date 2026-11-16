---
title: Play a score
description: Play a score through ScorePlayer, with pause, tempo, loops and muted parts, while the sheet marks the notes that sound.
sidebar:
  order: 7
---

This guide plays a `Score` through `ScorePlayer` and makes the `SheetView` show and follow what sounds.

:::note[Platforms]
Playback runs on Android and iOS only, through FluidSynth from [`khuur_synth`](https://github.com/Tseku210/khuur_synth). On every other platform the future of `play` fails with `SynthUnavailable`. [Platforms and limits](/khuur_sheet_music/reference/platforms-and-limits/) lists what runs where.
:::

## Create a player

The package bundles no SoundFont, so your app supplies one. Add an `.sf2` file to your app's assets first, as [Supply a SoundFont and add reverb](/khuur_sheet_music/guides/soundfonts-and-reverb/) shows.

1. Mix `SingleTickerProviderStateMixin` into the state of the widget that plays. The player takes the state as `vsync` and creates one ticker from it. If the state has other tickers too, mix in `TickerProviderStateMixin` instead.
2. Create the player with the asset key of your SoundFont.
3. Dispose the player in the state's `dispose`.

```dart
class _PracticePageState extends State<PracticePage>
    with SingleTickerProviderStateMixin {
  late final _player = ScorePlayer(
    soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
    vsync: this,
  );

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
```

The player loads a SoundFont when the first `play` that needs it starts. It loads each SoundFont once and keeps it for every later `play`.

## Show the playing notes on the sheet

Pass the player's `position` to the view as `playback`.

```dart
SheetView(score: widget.score, playback: _player.position)
```

The sheet marks the beat that plays with one column down the system, over the notes and the rests that start there. It draws every playing event in the playback ink. A note held from an earlier beat also takes the playback ink, and stays out of the column. To change these colours, see [Change the look of the sheet](/khuur_sheet_music/guides/change-the-look/).

When the playhead enters a system that is not wholly in view, the view scrolls that system to its top. To keep the view where the user puts it, pass `followPlayback: false`.

```dart
SheetView(
  score: score,
  playback: _player.position,
  followPlayback: false,
)
```

A system can be taller than the view, as on a phone held sideways. To follow one staff of such a system, see [Keep one staff in view](/khuur_sheet_music/guides/keep-a-staff-in-view/).

## Add a play and pause button

Build the button from the player's `status`. The status goes back to `PlayerStatus.idle` when the score ends, so your app keeps no play state of its own.

```dart
ValueListenableBuilder(
  valueListenable: _player.status,
  builder: (context, status, _) => IconButton(
    icon: Icon(
      status == PlayerStatus.playing ? Icons.pause : Icons.play_arrow,
    ),
    onPressed: switch (status) {
      PlayerStatus.playing => _player.pause,
      PlayerStatus.paused => _player.resume,
      PlayerStatus.idle => () => _player.play(widget.score),
      PlayerStatus.loading => null,
    },
  ),
)
```

`pause` lets go of every sounding note and holds the position. `resume` plays on from there, and does not strike again a note that the pause cut short. `stop` silences the output, removes the playing marks from the sheet and sets the status to idle.

## Start from the cursor

Pass a `ScorePoint` as `startAt`. The edit cursor of an `EditSession` holds one in `cursor.at`.

```dart
await _player.play(session.score, startAt: session.cursor.at);
```

In a score with repeats, playback starts where the play order first reaches that point.

## Change the tempo

Set `tempoScale`, the speed against the written tempo. A value of 1 plays as written, and 0.5 plays at half speed. The new speed applies at once, also while the score plays, and the position does not jump.

```dart
Slider(
  value: _player.tempoScale,
  min: 0.25,
  max: 1.5,
  onChanged: (value) => setState(() => _player.tempoScale = value),
)
```

A value that is zero, negative or not finite throws an `ArgumentError`.

## Loop a passage

Pass the passage as `PlaybackOptions` with `from` and `to`, and pass `loop: true`. The passage repeats until `stop` or the next `play`. This example loops the range the user selected.

```dart
if (session.selection case RangeSelection(:final from, :final to)) {
  await _player.play(
    session.score,
    options: PlaybackOptions(from: from, to: to),
    loop: true,
  );
}
```

The point `to` does not play. A range plays its bars in the order they are written, and ignores repeats and jumps. To loop the whole score with its repeats, pass `loop: true` and no range.

## Mute a part

Pass the ids of the parts to leave out as `muted`.

```dart
await _player.play(
  score,
  options: PlaybackOptions(muted: {score.parts.first.id}),
);
```

A muted part gets no channel and no notes, and the sheet does not mark its events. The player loads no SoundFont that only muted parts need.

## Hold notes with the sustain pedal

Add a `PedalLine`. It plays as the sustain pedal, so the notes of its part ring on every staff of the part until the line ends.

```dart
AddSpanner(kind: const PedalLine(), staff: staff, first: first, last: last)
```

## Hear an edit

The player plays the score it was given when `play` was called. To hear an edit, call `play` again with the new score. A call to `play` replaces whatever plays. The player keeps each bar it compiled, so it compiles again only the bars that the edit changed.

## Handle a failure

The future of `play` completes once playback has started. It fails when a SoundFont does not load or a program cannot be set, and the player is then idle. The next `play` tries the failed SoundFont again.

```dart
try {
  await _player.play(score);
} on SynthUnavailable {
  // FluidSynth cannot run here, as on a platform other than Android or iOS.
} on SynthException catch (error) {
  // A SoundFont did not load, or the audio output did not open.
}
```

## Related pages

- [Supply a SoundFont and add reverb](/khuur_sheet_music/guides/soundfonts-and-reverb/)
- [Change the look of the sheet](/khuur_sheet_music/guides/change-the-look/)
- [Keep one staff in view](/khuur_sheet_music/guides/keep-a-staff-in-view/)
- [How playback follows one clock](/khuur_sheet_music/explanation/playback-timeline/)
- [Platforms and limits](/khuur_sheet_music/reference/platforms-and-limits/)
