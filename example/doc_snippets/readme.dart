// README.md shows the code between the markers.
// .github/scripts/check_release_docs.sh fails when the two differ.
// #docregion
import 'package:khuur_sheet_music/khuur_sheet_music.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  var session = EditSession.start(
    Score.blank(
      parts: const [
        PartTemplate(
          name: 'Piano',
          instrument: Instrument(key: 'piano', program: 0),
        ),
      ],
      measureCount: 4,
    ),
  );
  for (final name in ['C4', 'E4', 'G4', 'C5']) {
    final edit = EnterNote(
      at: session.cursor,
      tone: Pitch.parse(name),
      value: NoteValue.quarter,
    );
    if (session.run(edit) case Applied(session: final next)) session = next;
  }
  runApp(
    MaterialApp(
      home: Scaffold(body: SheetView(score: session.score)),
    ),
  );
}
// #enddocregion
