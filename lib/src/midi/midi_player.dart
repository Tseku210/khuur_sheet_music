import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/midi/midi_keys.dart';
import 'package:simple_sheet_music/src/midi/sound_font.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/keysignature_type.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest.dart';

/// Status of the MIDI player.
enum MidiPlayerStatus {
  /// The player is stopped.
  stopped,

  /// The player is playing.
  playing,

  /// The player is paused.
  paused,
}

/// A class that handles MIDI playback for sheet music.
class MidiPlayer extends ChangeNotifier {
  MidiPlayer({
    required this.soundFont,
    this.tempo = 120,
    this.initialKeySignatureType = KeySignatureType.cMajor,
  }) : _midi = MidiPro();

  /// The tempo in beats per minute (BPM).
  int tempo;

  /// The SoundFont that supplies the instrument.
  final SoundFont soundFont;

  /// The key signature in effect before the first measure.
  final KeySignatureType initialKeySignatureType;

  /// The measures to play.
  List<Measure>? _measures;

  /// The MIDI key of each symbol in [_measures], from [resolveMidiKeys].
  List<List<int?>> _midiKeys = const [];

  /// The current status of the player.
  MidiPlayerStatus _status = MidiPlayerStatus.stopped;

  /// The MIDI plugin that handles the actual MIDI output.
  final MidiPro _midi;

  /// The ID of the soundfont loaded into [_midi].
  int? _soundfontId;

  /// The MIDI key that is currently sounding, if any.
  int? _soundingKey;

  /// The index of the current measure being played.
  int _currentMeasureIndex = 0;

  /// The index of the current symbol being played within the current measure.
  int _currentSymbolIndex = 0;

  /// The unique ID of the currently highlighted symbol.
  String? _highlightedSymbolId;

  /// A timer for scheduling note playback.
  Timer? _playbackTimer;

  /// Whether the playback is initialized.
  bool _isInitialized = false;

  /// Gets the current status of the player.
  MidiPlayerStatus get status => _status;

  /// Gets the unique ID of the currently highlighted symbol.
  String? get highlightedSymbolId => _highlightedSymbolId;

  /// Gets whether the player is currently playing.
  bool get isPlaying => _status == MidiPlayerStatus.playing;

  /// Initializes the MIDI engine and loads [soundFont].
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      if (!_midi.isInitialized) {
        await _midi.init();
      }
      _soundfontId = await switch (soundFont) {
        AssetSoundFont(:final path) =>
          _midi.loadSoundfontAsset(assetPath: path),
        FileSoundFont(:final path) => _midi.loadSoundfontFile(filePath: path),
      };

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing MIDI player: $e');
      }
      rethrow;
    }
  }

  /// Loads measures to play.
  void loadMeasures(List<Measure> measures) {
    _measures = measures;
    _midiKeys = resolveMidiKeys(measures, initialKeySignatureType);
    _currentMeasureIndex = 0;
    _currentSymbolIndex = 0;
    _clearHighlight();

    if (_status != MidiPlayerStatus.stopped) {
      stop();
    }

    notifyListeners();
  }

  /// Sets the tempo for playback.
  void setTempo(int newTempo) {
    if (newTempo <= 0) {
      throw ArgumentError('Tempo must be greater than 0');
    }

    tempo = newTempo;

    // If currently playing, restart playback with new tempo
    if (_status == MidiPlayerStatus.playing) {
      _stopPlaybackTimer();
      _startPlayback();
    }

    notifyListeners();
  }

  /// Starts playback from the current position.
  void play() {
    if (_measures == null) {
      throw StateError('No measures loaded');
    }

    if (_status == MidiPlayerStatus.playing) {
      return;
    }

    _status = MidiPlayerStatus.playing;
    _startPlayback();
    notifyListeners();
  }

  /// Pauses playback at the current position.
  void pause() {
    if (_status != MidiPlayerStatus.playing) {
      return;
    }

    _status = MidiPlayerStatus.paused;
    _stopPlaybackTimer();
    _releaseNote();
    notifyListeners();
  }

  /// Stops playback and resets the position.
  void stop() {
    if (_status == MidiPlayerStatus.stopped) {
      return;
    }

    _status = MidiPlayerStatus.stopped;
    _stopPlaybackTimer();
    _releaseNote();
    _currentMeasureIndex = 0;
    _currentSymbolIndex = 0;
    _clearHighlight();
    notifyListeners();
  }

  /// Jumps to a specific measure.
  void jumpToMeasure(int measureIndex) {
    if (_measures == null ||
        measureIndex < 0 ||
        measureIndex >= _measures!.length) {
      throw RangeError('Invalid measure index');
    }

    final wasPlaying = _status == MidiPlayerStatus.playing;
    if (wasPlaying) {
      _stopPlaybackTimer();
    }

    _currentMeasureIndex = measureIndex;
    _currentSymbolIndex = 0;
    _clearHighlight();

    if (wasPlaying) {
      _startPlayback();
    }

    notifyListeners();
  }

  /// Starts playback from the current position.
  void _startPlayback() {
    if (_measures == null) {
      return;
    }

    _playNextSymbol();
  }

  /// Stops the playback timer.
  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
  }

  /// Plays the next musical symbol in the sequence.
  void _playNextSymbol() {
    if (_measures == null) {
      return;
    }
    if (_status != MidiPlayerStatus.playing) {
      return;
    }

    // Check if we've reached the end
    if (_currentMeasureIndex >= _measures!.length) {
      stop();
      return;
    }

    final currentMeasure = _measures![_currentMeasureIndex];
    final symbols = currentMeasure.musicalSymbols;

    // Check if we've finished the current measure
    if (_currentSymbolIndex >= symbols.length) {
      _currentMeasureIndex++;
      _currentSymbolIndex = 0;
      _playNextSymbol();
      return;
    }

    final symbol = symbols[_currentSymbolIndex];

    // Only highlight notes and rests
    if (symbol is Note || symbol is Rest) {
      _highlightedSymbolId = symbol.id;
      notifyListeners();
    }

    _playKey(_midiKeys[_currentMeasureIndex][_currentSymbolIndex]);

    // Calculate duration for the next symbol
    final durationInSeconds =
        currentMeasure.getSymbolDurationInSeconds(symbol, tempo);

    // Schedule the next symbol
    _playbackTimer = Timer(
      Duration(milliseconds: (durationInSeconds * 1000).round()),
      () {
        _currentSymbolIndex++;
        _playNextSymbol();
      },
    );
  }

  /// Clears the current highlight
  void _clearHighlight() {
    _highlightedSymbolId = null;
    notifyListeners();
  }

  /// Plays [key], releasing the previous note first. A `null` key is silence.
  void _playKey(int? key) {
    _releaseNote();
    final sfId = _soundfontId;
    if (key != null && sfId != null) {
      unawaited(_midi.playNote(key: key, sfId: sfId));
      _soundingKey = key;
    }
  }

  /// Sends a note-off for the currently sounding note.
  void _releaseNote() {
    final key = _soundingKey;
    final sfId = _soundfontId;
    _soundingKey = null;
    if (key != null && sfId != null) {
      unawaited(_midi.stopNote(key: key, sfId: sfId));
    }
  }

  @override
  void dispose() {
    _stopPlaybackTimer();
    _releaseNote();
    final sfId = _soundfontId;
    if (sfId != null) {
      unawaited(_midi.unloadSoundfont(sfId));
    }
    super.dispose();
  }
}
