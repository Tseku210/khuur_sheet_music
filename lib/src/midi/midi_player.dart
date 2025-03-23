import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi/flutter_midi.dart';
import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/midi/soundfont_types.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
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
    this.tempo = 120,
    this.soundFontType = SoundFontType.touhou,
  }) : _flutterMidi = FlutterMidi();

  /// The tempo in beats per minute (BPM).
  int tempo;

  /// The soundfont type to use for playback.
  final SoundFontType soundFontType;

  /// The measures to play.
  List<Measure>? _measures;

  /// The current status of the player.
  MidiPlayerStatus _status = MidiPlayerStatus.stopped;

  /// The MIDI plugin that handles the actual MIDI output.
  final FlutterMidi _flutterMidi;

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

  /// Initializes the MIDI player with the specified soundfont.
  ///
  /// If no soundfont path is provided, the default soundfont from [soundFontType] will be used.
  Future<void> initialize([String? customSoundfontPath]) async {
    if (_isInitialized) {
      return;
    }

    try {
      // Load the soundfont file
      final soundfontPath = customSoundfontPath ?? soundFontType.path;
      final byte = await rootBundle.load(soundfontPath);
      await _flutterMidi.prepare(sf2: byte);

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
    notifyListeners();
  }

  /// Stops playback and resets the position.
  void stop() {
    if (_status == MidiPlayerStatus.stopped) {
      return;
    }

    _status = MidiPlayerStatus.stopped;
    _stopPlaybackTimer();
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

    _playSymbol(symbol);

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

  /// Plays a musical symbol.
  void _playSymbol(MusicalSymbol symbol) {
    if (symbol is Note) {
      _flutterMidi.playMidiNote(midi: symbol.pitch.midiNoteNumber);
    }
  }

  @override
  void dispose() {
    _stopPlaybackTimer();
    super.dispose();
  }
}
