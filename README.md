<!--
<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages-and-plugins).
[developing packages and plugins](https://flutter.dev/developing-packages-and-plugins).
-->

This repository is part of the [Khuur](https://github.com/Tseku210/khuur_app) project, a Flutter application for learning and playing the Mongolian horse fiddle instrument (morin khuur). It extends the [simple_sheet_music](https://github.com/tomoyu719/simple_sheet_music) library with MIDI playback capabilities and missing music sheet logic. It adds support for playing sheet music through MIDI output.

<p align="center">
    <img src="midi-example.png" width="30%" style="display: block; margin: 0 auto;">
</p>

## Acknowledgments

This library is inspired by the excellent [simple_sheet_music](https://github.com/tomoyu719/simple_sheet_music) repository developed by [@tomoyu719](https://github.com/tomoyu719). The original repository provides the core music rendering foundation.

This library is being developed as part of the [Khuur](https://github.com/Tseku210/khuur_app) project, a Flutter application for learning and playing the Mongolian horse fiddle instrument (morin khuur).

## Features

- Sheet music rendering with support for:
  - Staves and measures
  - Clefs (treble, alto, tenor, bass)
  - Notes and rests
  - Time signatures
  - Key signatures
- MIDI playback support
- Real-time music playback
- Customizable soundfont support

## MIDI playback

The package does not bundle a SoundFont. To turn on playback, pass one to `SimpleSheetMusic`. Declare an `.sf2` file in your app's `pubspec.yaml` and pass its asset key:

```dart
SimpleSheetMusic(
  measures: measures,
  soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
)
```

To load a SoundFont your app downloaded at runtime, use `FileSoundFont('/absolute/path.sf2')`. Playback uses bank 0, program 0. When `soundFont` is null, playback is off. MIDI works on Android, iOS and macOS.

The example app ships a 9.5 MB piano, `example/assets/soundfonts/piano.sf2`. It is [Upright Piano KW (small)](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html#UprightKW) from FreePats, a sampled Kawai upright released under CC0. Its readme and license are next to it.

## License

MIT License

Copyright (c) 2025 Tseku210

Copyright (c) 2023 tomoyu719

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

