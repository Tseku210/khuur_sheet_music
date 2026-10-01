// The call sites from RATIONALE.md "Usage", type-checked against the sketch.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';

// Quickstart. Show a saved score. It scrolls, follows the theme and lays itself
// out for its width.
class ScoreScreen extends StatelessWidget {
  const ScoreScreen({required this.saved, super.key});

  final String saved;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: SheetView(score: scoreFromJson(jsonDecode(saved))));
}

// Call site 1, an editor. A tap on a note selects it. A tap anywhere else
// enters a note there. The app keeps the EditSession. The sheet relays out only
// what each edit touched.
class Editor extends StatefulWidget {
  const Editor({super.key});

  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  EditSession _session = EditSession.start(
    Score.blank(
      parts: const [
        PartTemplate(
          name: 'Piano',
          instrument: Instrument(key: 'piano', program: 0),
          staves: 2,
        ),
      ],
    ),
  );
  final SheetController _sheet = SheetController();
  NoteValue _value = NoteValue.quarter;

  void _run(Edit edit) {
    switch (_session.run(edit)) {
      case Applied(:final session):
        setState(() => _session = session);
      case Refused(:final reason):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$reason')));
    }
  }

  void _onTap(SheetHit hit) {
    if (hit.target case ElementOwner(:final ref)) {
      setState(() => _session = _session.select(ItemSelection(Seq([ref]))));
      return;
    }
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
        value: _value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          icon: const Icon(Icons.zoom_in),
          onPressed: () => _sheet.zoom *= 1.25,
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => setState(
            () => _session = _session.moveCursor(CursorMove.nextEvent),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.music_note),
          onPressed: () => setState(() => _value = NoteValue.eighth),
        ),
      ],
    ),
    body: SheetView(
      score: _session.score,
      cursor: _session.cursor,
      selection: _session.selection,
      controller: _sheet,
      onTap: _onTap,
    ),
  );

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }
}

// Call site 2, playback. The player reports its position. The sheet highlights
// what sounds and moves a playhead. The play button reads the player's status
// instead of tracking it.
class Practice extends StatefulWidget {
  const Practice({required this.score, required this.from, super.key});

  final Score score;
  final ScorePoint from;

  @override
  State<Practice> createState() => _PracticeState();
}

class _PracticeState extends State<Practice>
    with SingleTickerProviderStateMixin {
  late final ScorePlayer _player = ScorePlayer(
    soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
    vsync: this,
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: SheetView(score: widget.score, playback: _player.position),
      ),
      ValueListenableBuilder(
        valueListenable: _player.status,
        builder: (context, status, _) => IconButton(
          icon: Icon(
            status == PlayerStatus.playing ? Icons.pause : Icons.play_arrow,
          ),
          onPressed: switch (status) {
            PlayerStatus.playing => _player.pause,
            PlayerStatus.paused => _player.resume,
            PlayerStatus.idle => () => _player.play(
              widget.score,
              startAt: widget.from,
            ),
            PlayerStatus.loading => null,
          },
        ),
      ),
      Slider(
        value: _player.tempoScale,
        min: 0.25,
        max: 1.5,
        onChanged: (value) => setState(() => _player.tempoScale = value),
      ),
    ],
  );

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

// Call site 3. The app draws its own overlay from the sheet's geometry (a
// delete badge on the selected event), and exports the sheet as an image.
class SelectionBadge extends StatelessWidget {
  const SelectionBadge({
    required this.session,
    required this.sheet,
    required this.onRun,
    super.key,
  });

  final EditSession session;
  final SheetController sheet;
  final ValueChanged<Edit> onRun;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sheet,
    builder: (context, child) {
      final rect = switch (session.selection.singleEvent) {
        final event? => sheet.rectOf(event),
        null => null,
      };
      return Stack(
        children: [
          child!,
          if (rect != null)
            Positioned(
              left: rect.right,
              top: rect.top - 32,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => onRun(Erase(session.selection)),
              ),
            ),
        ],
      );
    },
    child: SheetView(
      score: session.score,
      cursor: session.cursor,
      selection: session.selection,
      controller: sheet,
    ),
  );
}

Future<ui.Image> exportSheet(SheetController sheet) =>
    sheet.toImage(pixelRatio: 3);
