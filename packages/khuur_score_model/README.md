# khuur_score_model

An immutable score model for sheet music, in pure Dart. It holds the notes of a score, edits them with undo and redo, reads and writes MusicXML, writes MIDI, and compiles a timed playback script.

It has no Flutter dependency, so it runs in a Flutter app, on a server or in a command-line tool. [`khuur_sheet_music`](https://pub.dev/packages/khuur_sheet_music) builds a scrolling, editable sheet view and a player on top of it.

## Features

- `Score` is a value shaped like a MusicXML timewise score: a list of measure columns, each with the bar-level facts that every staff shares, and voices that fill each bar exactly. Slurs, hairpins and other marks that cross barlines live beside the columns.
- `EditSession` runs `Edit`s such as `EnterNote`, `AddToChord` or `Transpose`. Each run returns `Applied`, with a new score, cursor, selection and undo history, or `Refused`, with the reason.
- `scoreFromMusicXml` and `scoreToMusicXml` read and write MusicXML. `scoreToMidi` writes a standard MIDI file.
- `scoreToJson` and `scoreFromJson` save and load a score with every id kept.
- `PlaybackCompiler` compiles a `PlaybackScript` of timed MIDI notes, each pointing back at the event that produced it.

## Install

```bash
dart pub add khuur_score_model
```

## Use

```dart
import 'dart:io';

import 'package:khuur_score_model/khuur_score_model.dart';

const flute = Instrument(
  key: 'flute',
  program: 73,
  lowest: Pitch(Step.c, 4),
  highest: Pitch(Step.c, 7),
);

void main() {
  var session = EditSession.start(
    Score.blank(
      title: 'Study',
      parts: [const PartTemplate(name: 'Flute', instrument: flute)],
      measureCount: 4,
    ),
  );
  for (final tone in ['C5', 'E5', 'G5', 'C6']) {
    session = session
        .run(
          EnterNote(
            at: session.cursor,
            tone: Pitch.parse(tone),
            value: NoteValue.quarter,
          ),
        )
        .session;
  }

  File('study.musicxml').writeAsStringSync(scoreToMusicXml(session.score));
  File('study.mid').writeAsBytesSync(scoreToMidi(session.score));
}
```

A score is never changed in place. Every edit gives a new score, so an app can keep the old one for undo or compare the two to redraw only what changed.

## More

The [repository](https://github.com/Tseku210/khuur_sheet_music) has the guides, the architecture and the issue tracker. The package is part of `khuur_sheet_music` and is released with it.

## Licence

MIT. See [LICENSE](LICENSE).
