import 'package:example/demo_score.dart';
import 'package:flutter/material.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';

void main() => runApp(const ExampleApp());

/// One score to read, edit and play.
class ExampleApp extends StatelessWidget {
  const ExampleApp({this.output, super.key});

  /// Where the player sends its notes. Null plays through the device's
  /// synthesizer.
  final MidiOutput? output;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'simple_sheet_music',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: ScorePage(output: output),
  );
}

class ScorePage extends StatefulWidget {
  const ScorePage({this.output, super.key});

  final MidiOutput? output;

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage>
    with SingleTickerProviderStateMixin {
  EditSession _session = EditSession.start(buildDemoScore());
  NoteValue _value = NoteValue.quarter;
  final SheetController _sheet = SheetController();
  late final ScorePlayer _player = ScorePlayer(
    soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
    vsync: this,
    output: widget.output,
  );

  @override
  void dispose() {
    _player.dispose();
    _sheet.dispose();
    super.dispose();
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

  void _run(Edit edit) {
    switch (_session.run(edit)) {
      case Applied(:final session):
        setState(() => _session = session);
      case Refused(:final reason):
        _say('${edit.label} refused: ${reason.runtimeType}');
    }
  }

  Future<void> _play() async {
    try {
      await _player.play(_session.score);
    } on Object catch (error) {
      if (mounted) {
        _say('$error');
      }
    }
  }

  void _zoomBy(double factor) =>
      _sheet.zoom = (_sheet.zoom * factor).clamp(0.5, 3);

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('simple_sheet_music'),
      actions: [
        IconButton(
          tooltip: 'Undo',
          icon: const Icon(Icons.undo),
          onPressed: _session.canUndo
              ? () => setState(() => _session = _session.undo())
              : null,
        ),
        IconButton(
          tooltip: 'Zoom out',
          icon: const Icon(Icons.zoom_out),
          onPressed: () => _zoomBy(1 / 1.25),
        ),
        IconButton(
          tooltip: 'Zoom in',
          icon: const Icon(Icons.zoom_in),
          onPressed: () => _zoomBy(1.25),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(child: _sheetUnderBadge()),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              children: [
                const Text(
                  'Tap a staff to enter a note. Tap a note to select it.',
                ),
                const SizedBox(height: 8),
                _valuePicker(),
                _transport(),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  /// The controller notifies when a scroll, a zoom or a layout moves the
  /// selected event, so the delete badge follows it.
  Widget _sheetUnderBadge() => ListenableBuilder(
    listenable: _sheet,
    builder: (context, sheet) {
      final rect = switch (_session.selection.singleEvent) {
        final event? => _sheet.rectOf(event),
        null => null,
      };
      return Stack(
        children: [
          sheet!,
          if (rect != null)
            Positioned(
              left: rect.right,
              top: rect.top - 32,
              child: IconButton.filledTonal(
                tooltip: 'Delete',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _run(Erase(_session.selection)),
              ),
            ),
        ],
      );
    },
    child: SheetView(
      score: _session.score,
      cursor: _session.cursor,
      selection: _session.selection,
      playback: _player.position,
      controller: _sheet,
      onTap: _onTap,
    ),
  );

  Widget _valuePicker() => SegmentedButton<NoteValue>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: NoteValue.whole, label: Text('1')),
      ButtonSegment(value: NoteValue.half, label: Text('1/2')),
      ButtonSegment(value: NoteValue.quarter, label: Text('1/4')),
      ButtonSegment(value: NoteValue.eighth, label: Text('1/8')),
      ButtonSegment(value: NoteValue.sixteenth, label: Text('1/16')),
    ],
    selected: {_value},
    onSelectionChanged: (values) => setState(() => _value = values.single),
  );

  /// The buttons read the player's status, so the page keeps no play state
  /// of its own.
  Widget _transport() => Row(
    children: [
      ValueListenableBuilder(
        valueListenable: _player.status,
        builder: (context, status, _) {
          final (
            IconData icon,
            String tooltip,
            VoidCallback? onPressed,
          ) = switch (status) {
            PlayerStatus.idle => (Icons.play_arrow, 'Play', _play),
            PlayerStatus.loading => (Icons.hourglass_empty, 'Loading', null),
            PlayerStatus.playing => (Icons.pause, 'Pause', _player.pause),
            PlayerStatus.paused => (Icons.play_arrow, 'Resume', _player.resume),
          };
          return Row(
            children: [
              IconButton(
                tooltip: tooltip,
                icon: Icon(icon),
                onPressed: onPressed,
              ),
              IconButton(
                tooltip: 'Stop',
                icon: const Icon(Icons.stop),
                onPressed: status == PlayerStatus.idle ? null : _player.stop,
              ),
            ],
          );
        },
      ),
      Expanded(
        child: Slider(
          min: 0.25,
          max: 1.5,
          value: _player.tempoScale,
          onChanged: (scale) => setState(() => _player.tempoScale = scale),
        ),
      ),
      Text('${(_player.tempoScale * 100).round()}%'),
    ],
  );
}
