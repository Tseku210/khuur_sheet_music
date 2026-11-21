---
title: Supply a SoundFont and add reverb
description: Give ScorePlayer the SoundFonts your app ships or downloads, play each instrument from its own file, and set the reverb, the gain and the audio session.
sidebar:
  order: 8
---

This guide gives `ScorePlayer` the sounds it plays and sets how its `SynthOutput` sounds.

:::note[Platforms]
`SynthOutput` plays through FluidSynth on Android and iOS only. On every other platform the future of `ScorePlayer.play` fails with `SynthUnavailable`.
:::

## Add a SoundFont to your app

The package bundles no SoundFont, because Flutter ships every asset of a package to every app that uses the package. Your app supplies the SoundFont.

1. Put an `.sf2` file in your app, for example at `assets/soundfonts/piano.sf2`.
2. Declare it in your app's `pubspec.yaml`.

   ```yaml
   flutter:
     assets:
       - assets/soundfonts/piano.sf2
   ```

3. Pass its asset key to the player as an `AssetSoundFont`.

   ```dart
   late final _player = ScorePlayer(
     soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
     vsync: this,
   );
   ```

For a file that your app downloaded, pass `FileSoundFont` with the file's absolute path in place of `AssetSoundFont`.

Each part plays the program and the bank of its `Instrument`, so the SoundFont needs every program that the score names. A preset that the SoundFont lacks leaves that part silent, and the other parts still play. A SoundFont keeps its drum kits in bank 128, so the `Instrument` of a kit names that bank.

```dart
const kit = Instrument(key: 'drums', program: 0, bank: 128);
```

The example app plays [Upright Piano KW](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html#UprightKW) from FreePats, a 57 MB piano under CC0. FreePats also has a 9.5 MB version, in mono at one loudness, for an app that has to stay small. Check the licence of any SoundFont before you ship it.

## Play an instrument from its own SoundFont

Pass `instrumentSoundFonts`, a map from `Instrument.key` to a SoundFont. A part whose instrument is not in the map plays from `soundFont`.

```dart
late final _player = ScorePlayer(
  soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
  instrumentSoundFonts: const {
    'cello': AssetSoundFont('assets/soundfonts/cello.sf2'),
  },
  vsync: this,
);
```

Here the cello part plays from `cello.sf2` and every other part from `piano.sf2`. The player loads a SoundFont once, also when two instruments name it. A score saves its instruments and not the files they play from, so the map lives in your app and not in the score.

To change a sound between plays, set `instrumentSoundFonts` to a new map. The next `play` plays from it. This example swaps in a piano that the app downloaded.

```dart
_player.instrumentSoundFonts = {
  ..._player.instrumentSoundFonts,
  'piano': FileSoundFont(path),
};
```

A `SynthOutput` plays from at most 16 SoundFonts, because each SoundFont takes 16 of FluidSynth's 256 channels.

## Add reverb

The player plays through a `SynthOutput` with no reverb. To play with one, create the output yourself and pass it as `output`.

```dart
late final _player = ScorePlayer(
  soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
  vsync: this,
  output: SynthOutput(
    reverb: const Reverb(roomSize: 0.5, level: 0.3),
  ),
);
```

`Reverb` takes FluidSynth's own numbers, so it sounds the same on Android and iOS. `roomSize`, `damping` and `level` run from 0 to 1, and `width` from 0 to 100. A value that you leave out takes FluidSynth's default, so `Reverb()` is FluidSynth's default reverb.

To change the reverb between plays, keep the output and set its `reverb`. A new reverb sounds from the next note. Set it to null for no reverb.

```dart
final _output = SynthOutput();
late final _player = ScorePlayer(
  soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
  vsync: this,
  output: _output,
);

void _playWet(Score score) {
  _output.reverb = const Reverb(roomSize: 0.5, level: 0.3);
  _player.play(score);
}
```

## Set the gain

Pass `gain`, how loud FluidSynth plays, from 0 to 10. A value outside that range throws a `RangeError`.

```dart
final _output = SynthOutput(gain: 1.2);
```

The default is `SynthOutput.defaultGain`, 0.8. At 0.8 the piano of GeneralUser GS 2.0.3 measures about -24 LUFS. FluidSynth's own default, 0.2, plays it 12 dB quieter. The gain is fixed for the life of the output.

Each `SynthOutput` is a synthesizer of its own, so two outputs share no reverb, gain or channel. The player disposes its output when you dispose the player.

## Play while the app records

On iOS the output sets the audio session to playback as it opens the audio. To play while the app records, as when it listens to the microphone, open the synth with `AudioSessionPolicy.playAndRecord`. The synth then keeps the recording's session, so the input stays open.

```dart
final _output = SynthOutput(
  open: () => Synth.open(session: AudioSessionPolicy.playAndRecord),
);
```

The output sets its own `reverb` and `gain` on the synth that `open` returns. Android has no audio session, so the policy changes nothing there.

The output opens the device's audio as each play starts. It closes the audio once the last note has rung out after the score ends or the player stops. A pause keeps the audio open.

## Play through another synthesizer

To send the notes somewhere else, implement `MidiOutput` and pass your object as `output`. The player calls its methods as follows:

- `load` once for each SoundFont, before any program or note from it. After a failed load, the next `play` calls it again.
- `program` for each channel. The player waits for every program before the first note, so an output that sounds through a device opens the device here.
- `noteOn` and `noteOff` as the notes fall due, without waiting for an answer.
- `expression` for each channel before its first note, and again wherever that channel's value changes. Only a part that swells has a value below 127, and only while its level is under velocity 84. It is MIDI controller 11, 0 to 127, and it scales the channel's notes until the next call. A part that swells strikes its soft notes at velocity 84 and lowers them through expression, so an output that ignores this call plays them too loud. An output that cannot send a controller can weigh each note's velocity by the channel's last value as the note starts, as `SynthOutput` does.
- `allNotesOff` on a stop, to cut every sound at once.
- `rest` when no note comes before the next `program`. That is when the score ends, the player stops or a play fails, and not on a pause. An output that sounds through a device can let the device go here.
- `dispose` when the player is disposed. The player calls nothing after it.

Each SoundFont has its own 16 channels, so channel 0 of one SoundFont is not channel 0 of another.

## Related pages

- [Play a score](/khuur_sheet_music/guides/play-a-score/)
- [How playback follows one clock](/khuur_sheet_music/explanation/playback-timeline/)
- [Platforms and limits](/khuur_sheet_music/reference/platforms-and-limits/)
