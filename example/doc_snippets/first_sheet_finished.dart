// site/src/content/docs/tutorial/first-sheet.mdx shows the code between
// the markers as the finished lib/main.dart.
// .github/scripts/check_release_docs.sh fails when the two differ.
// #docregion
import 'package:khuur_sheet_music/khuur_sheet_music.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const FirstSheetApp());

class FirstSheetApp extends StatelessWidget {
  const FirstSheetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'First sheet',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: const SheetPage(),
  );
}

final Score blankScore = Score.blank(
  title: 'First sheet',
  parts: const [
    PartTemplate(
      name: 'Piano',
      instrument: Instrument(key: 'piano', program: 0),
    ),
  ],
  measureCount: 4,
);

Score buildScale() {
  var session = EditSession.start(blankScore);
  for (final name in ['C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5']) {
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

final Score scale = buildScale();

class SheetPage extends StatefulWidget {
  const SheetPage({super.key});

  @override
  State<SheetPage> createState() => _SheetPageState();
}

class _SheetPageState extends State<SheetPage>
    with SingleTickerProviderStateMixin {
  EditSession _session = EditSession.start(scale);

  late final ScorePlayer _player = ScorePlayer(
    soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
    vsync: this,
  );

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _onTap(SheetHit hit) {
    final tone = _session.score.toneForStaffStep(
      hit.staff,
      hit.at,
      hit.staffStep,
    );
    if (tone == null) {
      return;
    }
    _run(
      EnterNote(
        at: VoicePoint(staff: hit.staff, voice: hit.voice, at: hit.at),
        tone: tone,
        value: NoteValue.quarter,
      ),
    );
  }

  void _run(Edit edit) {
    switch (_session.run(edit)) {
      case Applied(:final session):
        setState(() => _session = session);
      case Refused(:final reason):
        _say('$reason');
    }
  }

  void _undo() => setState(() => _session = _session.undo());

  Future<void> _play() async {
    try {
      await _player.play(_session.score);
    } on Object catch (error) {
      if (mounted) {
        _say('$error');
      }
    }
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('First sheet'),
      actions: [
        IconButton(
          tooltip: 'Undo',
          icon: const Icon(Icons.undo),
          onPressed: _session.canUndo ? _undo : null,
        ),
        ValueListenableBuilder(
          valueListenable: _player.status,
          builder: (context, status, _) => IconButton(
            tooltip: status == PlayerStatus.playing ? 'Pause' : 'Play',
            icon: Icon(
              status == PlayerStatus.playing ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: switch (status) {
              PlayerStatus.idle => _play,
              PlayerStatus.loading => null,
              PlayerStatus.playing => _player.pause,
              PlayerStatus.paused => _player.resume,
            },
          ),
        ),
      ],
    ),
    body: SheetView(
      score: _session.score,
      cursor: _session.cursor,
      tapGrid: DurationBase.quarter,
      onTap: _onTap,
      playback: _player.position,
    ),
  );
}
// #enddocregion
