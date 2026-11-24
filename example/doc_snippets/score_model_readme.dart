// packages/khuur_score_model/README.md shows the code between the
// markers.
// .github/scripts/check_release_docs.sh fails when the two differ.
// ignore_for_file: depend_on_referenced_packages
// #docregion
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
// #enddocregion
