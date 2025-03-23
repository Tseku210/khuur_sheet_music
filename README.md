<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages-and-plugins). 
-->

This repository is part of the [Khuur](https://github.com/Tseku210/khuur_app) project, a Flutter application for learning and playing the Mongolian horse fiddle instrument (morin khuur). It extends the [simple_sheet_music](https://github.com/tomoyu719/simple_sheet_music) library with MIDI playback capabilities and missing music sheet logic. It adds support for playing sheet music through MIDI output.

<p align="center">
    <img src="midi-example.png" width="30%" style="display: block; margin: 0 auto;">
</p>

## Acknowledgments

This library is an extension of the excellent [simple_sheet_music](https://github.com/tomoyu719/simple_sheet_music) repository developed by [@tomoyu719](https://github.com/tomoyu719). The original repository provides the core music rendering logic and sheet music display functionality.

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