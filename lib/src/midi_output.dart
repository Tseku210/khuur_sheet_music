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
/// An output holds several SoundFonts at once. Every program and note names
/// the one it plays from, and each SoundFont has its own 16 channels, so
/// channel 0 of one is not channel 0 of another.
///
/// The player waits for [load] and for every [program], and then sends
/// notes without waiting, because a note that waited for an answer would be
/// late.
abstract interface class MidiOutput {
  /// Loads [soundFont]. The player waits for it before any [program] or
  /// note from that SoundFont, and calls it again for the same SoundFont
  /// only after it failed. It may load several SoundFonts at once.
  /// [allNotesOff] and [dispose] may come before it, or while it runs.
  Future<void> load(SoundFont soundFont);

  /// Selects [program] of [bank] from [soundFont] for [channel], which is 0
  /// to 15. Completes once a note on [channel] sounds with it.
  Future<void> program({
    required SoundFont soundFont,
    required int channel,
    required int program,
    required int bank,
  });

  /// Starts [key] on [channel] of [soundFont], [cents] above its pitch.
  void noteOn({
    required SoundFont soundFont,
    required int channel,
    required int key,
    required int velocity,
    required int cents,
  });

  /// Lets go of [key] on [channel] of [soundFont]. The sound rings out as
  /// the instrument releases it.
  void noteOff({
    required SoundFont soundFont,
    required int channel,
    required int key,
  });

  /// Cuts every sound on every channel of every SoundFont at once.
  void allNotesOff();

  /// Frees every SoundFont. The player calls nothing after it.
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
  FlutterMidiOutput({this._reverb, this._gain = 1});

  /// The reverb this output asks for. Null asks for none.
  ///
  /// The output asks for it each time it loads a SoundFont and each time
  /// it sets a [program], which the player does as every play starts. It
  /// also asks at once when it changes while the synthesizer runs, so a new
  /// one sounds from the next note.
  ///
  /// The reverb and the [gain] belong to the plugin's one synthesizer and
  /// not to an output. So the output that asked last decides them for every
  /// output of the process, and one with no reverb turns off what an earlier
  /// one turned on. An output still plays each play with its own, whatever
  /// another output asked for before, because it asks again as the play
  /// starts. Two outputs that sound at once share those of the later one.
  MidiReverb? get reverb => _reverb;
  set reverb(MidiReverb? value) {
    if (value != _reverb) {
      _reverb = value;
      if (_running) {
        unawaited(_askForReverb());
      }
    }
  }

  MidiReverb? _reverb;

  /// How loud the synthesizer plays, as a multiple of its own level: 1 is
  /// its level and 0 is silence. The output holds it to 0 to 4, about
  /// 12 dB louder, the most iOS takes. It asks for it as it asks for the
  /// [reverb].
  double get gain => _gain;
  set gain(double value) {
    if (value != _gain) {
      _gain = value;
      if (_running) {
        unawaited(_askForGain());
      }
    }
  }

  double _gain;

  /// The plugin's `init` while it runs, which every output waits for. The
  /// plugin is one synthesizer for the whole process. Its `isInitialized`
  /// is true from the start of `init`, and `init` ends by emptying the
  /// directory it keeps loaded SoundFonts in, so an output that loaded
  /// before the end would lose its SoundFont.
  static Future<void>? _init;

  final MidiPro _midi = MidiPro();

  /// The plugin's id of each SoundFont that is loaded.
  final Map<SoundFont, int> _ids = {};

  /// The cents each channel of each SoundFont, by the plugin's id, was last
  /// bent by. A channel not here was never bent by this output, and may
  /// still hold the bend of an earlier one, because a synthesizer can
  /// outlive the SoundFont that was unloaded.
  final Map<(int, int), int> _bends = {};
  bool _disposed = false;

  @override
  Future<void> load(SoundFont soundFont) async {
    if (_init != null || !_midi.isInitialized) {
      await (_init ??= _midi.init().whenComplete(() => _init = null));
    }
    await _askForReverb();
    await _askForGain();
    final id = await switch (soundFont) {
      AssetSoundFont(:final path) => _midi.loadSoundfontAsset(assetPath: path),
      FileSoundFont(:final path) => _midi.loadSoundfontFile(filePath: path),
    };
    if (_disposed) {
      unawaited(_midi.unloadSoundfont(id));
    } else {
      _ids[soundFont] = id;
    }
  }

  /// Whether the synthesizer runs and no `init` is under way, so what
  /// this output asks for now holds.
  bool get _running => !_disposed && _init == null && _midi.isInitialized;

  Future<void> _askForReverb() => switch (_reverb) {
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

  Future<void> _askForGain() =>
      _midi.setMasterGain(_within(_gain, _loudestGain));

  @override
  Future<void> program({
    required SoundFont soundFont,
    required int channel,
    required int program,
    required int bank,
  }) async {
    final id = _ids[soundFont]!;
    // A synthesizer may put a channel's bend back at rest when its program
    // changes. Sending it to rest first keeps [_bends] true either way, and
    // clears what an earlier output left on the channel.
    _bend(id, channel, 0);
    // Another output may have put its own reverb and gain on the one
    // synthesizer since this one last asked. Everything is sent before the
    // first answer comes, so the programs keep the order they were asked in.
    await Future.wait([
      _askForReverb(),
      _askForGain(),
      if (bank <= _largestBank) _select(id, channel, program, bank),
    ]);
  }

  Future<void> _select(int id, int channel, int program, int bank) async {
    try {
      await _midi.selectInstrument(
        sfId: id,
        channel: channel,
        bank: bank,
        program: program,
      );
      if (_samplerDropsEarlyNotes.contains(defaultTargetPlatform)) {
        await Future<void>.delayed(_instrumentTakesHold);
      }
    } on PlatformException catch (error) {
      if (!_missingPreset.contains(error.code)) {
        rethrow;
      }
    }
  }

  @override
  void noteOn({
    required SoundFont soundFont,
    required int channel,
    required int key,
    required int velocity,
    required int cents,
  }) {
    final id = _ids[soundFont]!;
    // MIDI bends a whole channel, not one key. A quarter tone therefore
    // also bends what its channel still holds, until the next note that
    // is not one.
    _bend(id, channel, cents);
    unawaited(
      _midi.playNote(sfId: id, channel: channel, key: key, velocity: velocity),
    );
  }

  @override
  void noteOff({
    required SoundFont soundFont,
    required int channel,
    required int key,
  }) => unawaited(
    _midi.stopNote(sfId: _ids[soundFont]!, channel: channel, key: key),
  );

  @override
  void allNotesOff() {
    for (final id in _ids.values) {
      unawaited(_midi.stopAllNotes(sfId: id));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final id in _ids.values) {
      unawaited(_midi.unloadSoundfont(id));
    }
    _ids.clear();
  }

  void _bend(int id, int channel, int cents) {
    if (_bends[(id, channel)] == cents) {
      return;
    }
    _bends[(id, channel)] = cents;
    unawaited(
      _midi.pitchBend(
        sfId: id,
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

/// Where the plugin plays through Apple's sampler, which takes a new
/// instrument on its next render cycle and drops a note that comes before
/// it. The note is silent for its whole length, so without a wait the
/// first note of every play is lost.
const Set<TargetPlatform> _samplerDropsEarlyNotes = {
  TargetPlatform.iOS,
  TargetPlatform.macOS,
};

/// How long [FlutterMidiOutput.program] waits on [_samplerDropsEarlyNotes]
/// after the sampler loads an instrument. A render cycle is about 11 ms at
/// 512 frames, which the iOS simulator uses, and 23 ms at 1024, the most
/// iOS usually grants, so this holds twice that.
const _instrumentTakesHold = Duration(milliseconds: 50);

/// The largest bank the plugin's `selectInstrument` takes. On macOS and on
/// iOS it makes a byte of the bank, and a larger one stops the app.
const _largestBank = 255;

/// The largest width the plugin's `setReverb` takes, which is FluidSynth's.
const _widestReverb = 100.0;

/// The largest gain iOS takes, about 12 dB above the synthesizer's level.
/// Android takes up to 10.
const _loudestGain = 4.0;

/// [value] held to 0 to [most]. A value that is not a number is 0, where
/// `clamp` makes it [most].
double _within(double value, double most) =>
    value.isNaN ? 0 : value.clamp(0, most);

/// The pitch wheel at rest, of 0 to 16383.
const _bendCentre = 8192;

/// How far the wheel's end bends a note, which is two semitones unless a
/// channel is told otherwise.
const _bendRangeCents = 200;
