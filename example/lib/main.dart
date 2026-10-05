import 'package:example/demo_score.dart';
import 'package:example/selection_actions.dart';
import 'package:flutter/material.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';

void main() => runApp(const ExampleApp());

/// One score to read, edit and play.
class ExampleApp extends StatelessWidget {
  const ExampleApp({this.output, this.score, super.key});

  /// Where the player sends its notes. Null plays through the device's
  /// synthesizer.
  final MidiOutput? output;

  /// The score the page opens with. Null opens the tune of
  /// [buildDemoScore].
  final Score? score;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'simple_sheet_music',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: ScorePage(output: output, score: score),
  );
}

/// Why an edit did not apply, as a sentence for the person at the page.
String refusalSentence(EditRefusal reason) => switch (reason) {
  StaleReference() => 'That is no longer in the score.',
  WouldSplitTuplet() => 'This would cut a tuplet in two.',
  OutsideMeasure() => 'That point is outside its bar.',
  WouldCrossBarline() => 'This note does not fit in the bar.',
  WouldEmptyScore() => 'The score would have nothing left to show.',
  InvalidValue(:final message) =>
    '${message[0].toUpperCase()}${message.substring(1)}.',
};

class ScorePage extends StatefulWidget {
  const ScorePage({this.output, this.score, super.key});

  final MidiOutput? output;
  final Score? score;

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage>
    with SingleTickerProviderStateMixin {
  late EditSession _session = EditSession.start(
    widget.score ?? buildDemoScore(),
  );
  NoteValue _value = NoteValue.quarter;
  bool _autoBars = true;
  bool _autoBeams = true;
  ScoreClip? _clip;
  final SheetController _sheet = SheetController();
  final ScrollController _rowScroll = ScrollController();
  late final ScorePlayer _player = ScorePlayer(
    soundFont: const AssetSoundFont('assets/soundfonts/piano.sf2'),
    vsync: this,
    output: widget.output,
  );

  @override
  void dispose() {
    _player.dispose();
    _sheet.dispose();
    _rowScroll.dispose();
    super.dispose();
  }

  void _onTap(SheetHit hit) {
    if (hit.target case ElementOwner(:final ref)) {
      setState(
        () => _session = _session.select(ItemSelection(Seq([_whole(ref)]))),
      );
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
    final at = VoicePoint(staff: hit.staff, voice: hit.voice, at: hit.at);
    final entered = _run(
      EnterNote(
        at: at,
        tone: tone,
        value: _value,
        overfill: _overfill,
        beam: _autoBeams ? BeamMode.auto : BeamMode.none,
        appendBar: _autoBars,
      ),
    );
    // The cursor stays at a note that ends the score when no bar is added
    // for it to move into.
    if (entered && _session.cursor == at) {
      _say('The score ends here.', offerBar: true);
    }
  }

  /// The only head of a chord stands for the chord, so that a tap selects
  /// the same thing wherever on a note it lands.
  ElementRef _whole(ElementRef ref) =>
      switch (_session.score.lookup(ref.event)?.event) {
        ChordEvent(:final notes) when notes.length > 1 => ref,
        _ => ref.event,
      };

  Overfill get _overfill => _autoBars ? Overfill.splitAndTie : Overfill.refuse;

  /// Whether [edit] applied. With Auto bars off, only Add bar may lengthen
  /// the score. A paste appends the bars it needs whatever its overfill, so
  /// the page turns such a paste down itself.
  bool _run(Edit edit) {
    switch (_session.run(edit)) {
      case Applied(:final session):
        final longer =
            session.score.measures.length > _session.score.measures.length;
        if (longer && !_autoBars && edit is! InsertMeasures) {
          _say('The score is too short for this.', offerBar: true);
          return false;
        }
        setState(() => _session = session);
        return true;
      case Refused(:final reason):
        _say(refusalSentence(reason));
        return false;
    }
  }

  void _addBar() => _run(const InsertMeasures());

  void _press(Press press) {
    switch (press) {
      case RunEdit(:final edit):
        _run(edit);
      case Reselect(:final selection):
        setState(() => _session = _session.select(selection));
      case TakeCopy():
        setState(() => _clip = _session.copy());
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

  void _say(String message, {bool offerBar = false}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            persist: false,
            action: offerBar
                ? SnackBarAction(label: 'Add bar', onPressed: _addBar)
                : null,
          ),
        );

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
          Expanded(
            child: SheetView(
              score: _session.score,
              cursor: _session.cursor,
              selection: _session.selection,
              playback: _player.position,
              controller: _sheet,
              palette: _palette(context),
              onTap: _onTap,
            ),
          ),
          _underSheet(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Column(
              children: [_entryOptions(), _valuePicker(), _transport()],
            ),
          ),
        ],
      ),
    ),
  );

  /// The theme's palette with a selection of the page's own, a round box
  /// with a border. The copy keeps the sheet in step with light and dark
  /// mode.
  SheetPalette _palette(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SheetPalette.of(context).copyWith(
      selection: SheetHighlight(
        fill: primary.withValues(alpha: 0.14),
        border: primary.withValues(alpha: 0.7),
        borderWidth: 0.1,
        radius: 0.4,
        padding: 0.25,
      ),
    );
  }

  /// The size of a button of the action row, an icon over its name on one
  /// line, which grows with the text size of the device. A phone 390 wide
  /// shows five and part of a sixth, and the cut button says that the row
  /// goes on.
  Size _buttonSize(BuildContext context) {
    final text = MediaQuery.textScalerOf(context).scale(1);
    return Size(72 * text, 32 + 16 * text);
  }

  ButtonStyle _actionStyle(BuildContext context) => TextButton.styleFrom(
    foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
    textStyle: Theme.of(context).textTheme.labelSmall,
    padding: const EdgeInsets.symmetric(vertical: 4),
    shape: const RoundedRectangleBorder(),
  );

  /// The hint and the action row take turns in one slot as high as the row,
  /// so the sheet keeps its size when the selection comes and goes.
  Widget _underSheet() {
    final actions = selectionActions(
      Picked.of(_session.score, _session.selection),
      clip: _clip,
      overfill: _overfill,
    );
    final button = _buttonSize(context);
    return SizedBox(
      height: button.height,
      child: actions.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Tap a staff to enter a note. Tap a note to select it.',
                  ),
                ),
              ),
            )
          : Scrollbar(
              controller: _rowScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _rowScroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (:label, :icon, :press) in actions)
                      SizedBox.fromSize(
                        size: button,
                        child: TextButton(
                          style: _actionStyle(context),
                          onPressed: press == null ? null : () => _press(press),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon),
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _entryOptions() => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      _toggle(
        'Auto bars',
        on: _autoBars,
        onChanged: (on) => setState(() => _autoBars = on),
      ),
      _toggle(
        'Auto beams',
        on: _autoBeams,
        onChanged: (on) => setState(() => _autoBeams = on),
      ),
      OutlinedButton(
        // Narrower than the default, so that the three share one line on a
        // phone.
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: _addBar,
        child: const Text('Add bar'),
      ),
    ],
  );

  Widget _toggle(
    String label, {
    required bool on,
    required ValueChanged<bool> onChanged,
  }) => InkWell(
    onTap: () => onChanged(!on),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        Switch(value: on, onChanged: onChanged),
      ],
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
