import 'dart:async';
import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/midi/midi_player.dart';
import 'package:simple_sheet_music/src/midi/sound_font.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/keysignature_type.dart';

/// A mixin that provides MIDI playback functionality to the SimpleSheetMusic widget.
mixin MidiPlaybackMixin<T extends StatefulWidget> on State<T> {
  /// The MIDI player instance.
  MidiPlayer? _midiPlayer;

  /// Store the positions of all musical symbols for efficient highlighting
  final Map<String, Rect> _symbolPositions = {};

  /// The unique ID of the currently highlighted symbol
  String? _highlightedSymbolId;

  /// The tempo in beats per minute
  int get tempo;

  /// The SoundFont to play with. MIDI playback is off when this is null.
  SoundFont? get soundFont;

  /// The color to use for highlighting
  Color get highlightColor;

  /// The list of measures to play
  List<Measure> get measures;

  /// The key signature in effect before the first measure
  KeySignatureType get initialKeySignatureType;

  /// Initialize MIDI playback
  Future<void> initializeMidi() async {
    final soundFont = this.soundFont;
    if (soundFont == null) {
      return;
    }

    _midiPlayer = MidiPlayer(
      soundFont: soundFont,
      tempo: tempo,
      initialKeySignatureType: initialKeySignatureType,
    );

    try {
      await _midiPlayer!.initialize();
      _midiPlayer!.loadMeasures(measures);
      _midiPlayer!.addListener(_updateHighlightedSymbol);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize MIDI: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  /// Updates the highlighted symbol when the MIDI player changes
  void _updateHighlightedSymbol() {
    if (_midiPlayer != null && mounted) {
      setState(() {
        _highlightedSymbolId = _midiPlayer!.highlightedSymbolId;
      });
    }
  }

  /// Register a symbol and its position for efficient lookup
  void registerSymbolPosition(MusicalSymbol symbol, Rect bounds) {
    _symbolPositions[symbol.id] = bounds;
  }

  /// Gets the position of a symbol if it's been registered
  Rect? getSymbolPosition(String? symbolId) {
    if (symbolId == null) {
      return null;
    }
    return _symbolPositions[symbolId];
  }

  /// Gets the position of the currently highlighted symbol
  Rect? get highlightedSymbolPosition {
    if (_highlightedSymbolId == null) {
      return null;
    }
    return _symbolPositions[_highlightedSymbolId];
  }

  /// Plays the sheet music using MIDI
  void playMidi() {
    if (_midiPlayer != null) {
      _midiPlayer!.play();
    }
  }

  /// Pauses MIDI playback
  void pauseMidi() {
    if (_midiPlayer != null) {
      _midiPlayer!.pause();
    }
  }

  /// Stops MIDI playback
  void stopMidi() {
    if (_midiPlayer != null) {
      _midiPlayer!.stop();
    }
  }

  /// Sets the tempo for MIDI playback
  void setTempo(int newTempo) {
    if (_midiPlayer != null) {
      _midiPlayer!.setTempo(newTempo);
    }
  }

  /// Gets the unique ID of the currently highlighted symbol
  String? get highlightedSymbolId => _highlightedSymbolId;

  /// Gets the highlight color
  Color get currentHighlightColor => highlightColor;

  /// Clears all symbol positions
  void clearSymbolPositions() {
    _symbolPositions.clear();
  }

  @override
  void dispose() {
    _midiPlayer?.dispose();
    clearSymbolPositions();
    super.dispose();
  }
}
