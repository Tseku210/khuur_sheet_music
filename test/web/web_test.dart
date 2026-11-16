@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khuur_sheet_music/khuur_sheet_music.dart';

import '../mock/fake_midi_output.dart';
import '../mock/fake_wall_time.dart';

Score arpeggio() {
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
    if (session.run(edit) case Applied(session: final next)) {
      session = next;
    }
  }
  return session.score;
}

const piano = AssetSoundFont('piano.sf2');

void main() {
  testWidgets('SheetView shows a score on the web', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SheetView(score: arpeggio()),
      ),
    );
    expect(find.bySemanticsLabel('Bars 1 to 4'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('ScorePlayer.play throws SynthUnavailable on the web', (
    tester,
  ) async {
    final player = ScorePlayer(soundFont: piano, vsync: tester);
    await expectLater(
      player.play(arpeggio()),
      throwsA(isA<SynthUnavailable>()),
    );
    player.dispose();
  });

  testWidgets('ScorePlayer plays through the app\'s own MidiOutput', (
    tester,
  ) async {
    final time = FakeWallTime(tester.binding);
    final midi = FakeMidiOutput(time.now);
    final player = ScorePlayer(
      soundFont: piano,
      vsync: tester,
      output: midi,
      now: time.now,
    );
    await player.play(arpeggio());
    await tester.pump(const Duration(seconds: 3));
    expect([for (final note in midi.ons) note.key], [60, 64, 67, 72]);
    player.dispose();
  });
}
