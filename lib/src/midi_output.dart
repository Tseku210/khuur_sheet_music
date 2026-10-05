/// The synthesizer behind `ScorePlayer`. An app passes its own
/// [MidiOutput] to play through another synthesizer.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// The reverb [FlutterMidiOutput] asks the synthesizer for.
///
/// [width] is 0 to 100 and every other number is 0 to 1. None is refused.
/// The output sends a number outside its range as the nearest end of it,
/// and one that is not a number as 0.
///
/// iOS and macOS do not read [roomSize] and [level] as Android does, so
/// neither has a default.
@immutable
final class MidiReverb {
  const MidiReverb({
    required this.roomSize,
    required this.level,
    this.damping = 0,
    this.width = 0.5,
  });

  /// The size of the room. Android takes the number. iOS and macOS have six
  /// rooms and pick one by it: the small room under 0.15, the medium room
  /// under 0.3, the large room under 0.45, the medium hall under 0.6, the
  /// large hall under 0.8, and the cathedral from there.
  final double roomSize;

  /// How much reverb there is. On iOS and macOS it is the reverb's share of
  /// the whole sound, so 1 leaves none of the dry sound. On Android it is
  /// the output level of the reverb.
  final double level;

  /// How much the reverb is damped. Only Android reads it.
  final double damping;

  /// How far the reverb spreads between left and right, of 0 to 100. Only
  /// Android reads it.
  final double width;

  @override
  bool operator ==(Object other) =>
      other is MidiReverb &&
      other.roomSize == roomSize &&
      other.level == level &&
      other.damping == damping &&
      other.width == width;

  @override
  int get hashCode => Object.hash(roomSize, level, damping, width);

  @override
  String toString() =>
      'MidiReverb(roomSize: $roomSize, level: $level, damping: $damping, '
      'width: $width)';
}

/// Plays through `flutter_midi_pro` (Android, iOS and macOS).
final class FlutterMidiOutput implements MidiOutput {
  FlutterMidiOutput({this.reverb});

  /// The reverb this output asks for when it loads. Null asks for none.
  ///
  /// The reverb belongs to the plugin's one synthesizer and not to an
  /// output. So the output that loaded last decides it for every output of
  /// the process, and one with no reverb turns off what an earlier one
  /// turned on.
  final MidiReverb? reverb;

  /// The plugin's `init` while it runs, which every output waits for. The
  /// plugin is one synthesizer for the whole process. Its `isInitialized`
  /// is true from the start of `init`, and `init` ends by emptying the
  /// directory it keeps loaded SoundFonts in, so an output that loaded
  /// before the end would lose its SoundFont.
  static Future<void>? _init;

  final MidiPro _midi = MidiPro();
  int? _soundFontId;

  /// The cents each channel was last bent by. A channel not here was never
  /// bent by this output, and may still hold the bend of an earlier one,
  /// because a synthesizer can outlive the SoundFont that was unloaded.
  final Map<int, int> _bends = {};
  bool _disposed = false;

  @override
  Future<void> load(SoundFont soundFont) async {
    if (_init != null || !_midi.isInitialized) {
      await (_init ??= _midi.init().whenComplete(() => _init = null));
    }
    await switch (reverb) {
      null => _midi.setReverb(enabled: false),
      MidiReverb(:final roomSize, :final level, :final damping, :final width) =>
        _midi.setReverb(
          enabled: true,
          roomSize: _within(roomSize, 1),
          damping: _within(damping, 1),
          width: _within(width, _widestReverb),
          level: _within(level, 1),
        ),
    };
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
    if (bank > _largestBank) {
      return;
    }
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
/// reports nothing. A bank over [_largestBank] is such a preset too, and
/// is never asked for.
const _missingPreset = {'SOUND_FONT_LOAD_FAILED', 'SOUND_FONT_LOAD_FAILED2'};

/// The largest bank the plugin's `selectInstrument` takes. On macOS and on
/// iOS it makes a byte of the bank, and a larger one stops the app.
const _largestBank = 255;

/// The largest width the plugin's `setReverb` takes, which is FluidSynth's.
const _widestReverb = 100.0;

/// [value] held to 0 to [most]. A value that is not a number is 0, where
/// `clamp` makes it [most].
double _within(double value, double most) =>
    value.isNaN ? 0 : value.clamp(0, most);

/// The pitch wheel at rest, of 0 to 16383.
const _bendCentre = 8192;

/// How far the wheel's end bends a note, which is two semitones unless a
/// channel is told otherwise.
const _bendRangeCents = 200;
