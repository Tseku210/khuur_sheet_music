/// The synthesizer behind `ScorePlayer`. An app passes its own
/// [MidiOutput] to play through another synthesizer.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:khuur_sheet_music/src/sound_font.dart';

/// Where `ScorePlayer` sends a script's notes.
///
/// The player waits for [load] and for every [program], and then sends
/// notes without waiting, because a note that waited for an answer would be
/// late.
abstract interface class MidiOutput {
  /// Loads [soundFont]. The player waits for it before any [program] or
  /// note, and calls it again only after it failed. [allNotesOff] and
  /// [dispose] may come before it, or while it runs.
  Future<void> load(SoundFont soundFont);

  /// Selects [program] of [bank] for [channel], which is 0 to 15.
  Future<void> program({
    required int channel,
    required int program,
    required int bank,
  });

  /// Starts [key] on [channel], [cents] above its pitch.
  void noteOn({
    required int channel,
    required int key,
    required int velocity,
    required int cents,
  });

  /// Lets go of [key] on [channel]. The sound rings out as the instrument
  /// releases it.
  void noteOff({required int channel, required int key});

  /// Cuts every sound on every channel at once.
  void allNotesOff();

  /// Frees the SoundFont. The player calls nothing after it.
  void dispose();
}

/// Plays through `flutter_midi_pro` (Android, iOS and macOS).
final class FlutterMidiOutput implements MidiOutput {
  final MidiPro _midi = MidiPro();
  int? _soundFontId;

  /// The cents each channel was last bent by. A channel not here was never
  /// bent by this output, and may still hold the bend of an earlier one,
  /// because a synthesizer can outlive the SoundFont that was unloaded.
  final Map<int, int> _bends = {};
  bool _disposed = false;

  @override
  Future<void> load(SoundFont soundFont) async {
    if (!_midi.isInitialized) {
      await _midi.init();
    }
    final id = await switch (soundFont) {
      AssetSoundFont(:final path) => _midi.loadSoundfontAsset(assetPath: path),
      FileSoundFont(:final path) => _midi.loadSoundfontFile(filePath: path),
    };
    if (_disposed) {
      unawaited(_midi.unloadSoundfont(id));
    } else {
      _soundFontId = id;
    }
  }

  @override
  Future<void> program({
    required int channel,
    required int program,
    required int bank,
  }) async {
    final soundFontId = _soundFontId!;
    // A synthesizer may put a channel's bend back at rest when its program
    // changes. Sending it to rest first keeps [_bends] true either way, and
    // clears what an earlier output left on the channel.
    _bend(soundFontId, channel, 0);
    try {
      await _midi.selectInstrument(
        sfId: soundFontId,
        channel: channel,
        bank: bank,
        program: program,
      );
    } on PlatformException catch (error) {
      if (!_missingPreset.contains(error.code)) {
        rethrow;
      }
    }
  }

  @override
  void noteOn({
    required int channel,
    required int key,
    required int velocity,
    required int cents,
  }) {
    final soundFontId = _soundFontId!;
    // MIDI bends a whole channel, not one key. A quarter tone therefore
    // also bends what its channel still holds, until the next note that
    // is not one.
    _bend(soundFontId, channel, cents);
    unawaited(
      _midi.playNote(
        sfId: soundFontId,
        channel: channel,
        key: key,
        velocity: velocity,
      ),
    );
  }

  @override
  void noteOff({required int channel, required int key}) => unawaited(
    _midi.stopNote(sfId: _soundFontId!, channel: channel, key: key),
  );

  @override
  void allNotesOff() {
    final soundFontId = _soundFontId;
    if (soundFontId != null) {
      unawaited(_midi.stopAllNotes(sfId: soundFontId));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final soundFontId = _soundFontId;
    _soundFontId = null;
    if (soundFontId != null) {
      unawaited(_midi.unloadSoundfont(soundFontId));
    }
  }

  void _bend(int soundFontId, int channel, int cents) {
    if (_bends[channel] == cents) {
      return;
    }
    _bends[channel] = cents;
    unawaited(
      _midi.pitchBend(
        sfId: soundFontId,
        channel: channel,
        value: _bendCentre + cents * _bendCentre ~/ _bendRangeCents,
      ),
    );
  }
}

/// What the plugin's `selectInstrument` fails with when the SoundFont lacks
/// the preset, on macOS and on iOS. Android keeps the channel's sound and
/// reports nothing.
const _missingPreset = {'SOUND_FONT_LOAD_FAILED', 'SOUND_FONT_LOAD_FAILED2'};

/// The pitch wheel at rest, of 0 to 16383.
const _bendCentre = 8192;

/// How far the wheel's end bends a note, which is two semitones unless a
/// channel is told otherwise.
const _bendRangeCents = 200;
