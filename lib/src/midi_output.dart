/// The synthesizer behind `ScorePlayer`. An app passes its own
/// [MidiOutput] to play through another synthesizer.
library;

import 'dart:async';

import 'package:khuur_synth/khuur_synth.dart';

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
  /// [allNotesOff], [rest] and [dispose] may come before it, or while it
  /// runs.
  Future<void> load(SoundFont soundFont);

  /// Selects [program] of [bank] from [soundFont] for [channel], which is 0
  /// to 15. Completes once a note on [channel] sounds with it, so an output
  /// that sounds through a device opens the device here.
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

  /// Says that no note comes before the next [program]. The player sends it
  /// when the score ends, on a stop and after a play that failed, and not
  /// on a pause. An output that sounds through a device may close the
  /// device once what still sounds has rung out.
  void rest();

  /// Frees every SoundFont. The player calls nothing after it.
  void dispose();
}

/// Plays through a FluidSynth synthesizer from `khuur_synth`, on iOS and
/// Android.
///
/// Each output is one [Synth] of its own, so two outputs share no reverb,
/// gain or channel. The output opens it on its first [load], opens the
/// device output on each [program], and closes the device once the notes
/// have rung out after [rest].
///
/// Each SoundFont takes the next 16 of the synth's 256 channels in the
/// order the output loaded it, so an output plays from at most 16.
final class SynthOutput implements MidiOutput {
  /// An output that plays [reverb], null for none, at [gain], from 0 to 10.
  ///
  /// [open] makes the synth, `Synth.open` unless given. A test passes
  /// `Synth.silent`. The output sets its own [reverb] and [gain] on the
  /// synth it gets.
  SynthOutput({
    this._reverb,
    this.gain = defaultGain,
    Future<Synth> Function()? open,
  }) : _open = open ?? Synth.open {
    if (!(gain >= 0 && gain <= 10)) {
      throw RangeError.value(gain, 'gain', 'Must be from 0 to 10');
    }
  }

  /// The gain at which the piano of GeneralUser GS 2.0.3 measures about
  /// -24 LUFS. FluidSynth's own default, 0.2, plays 12 dB quieter.
  static const defaultGain = 0.8;

  final double gain;

  /// The reverb, or null for none. A new one sounds from the next note.
  /// Its numbers must lie within the ranges `Reverb` names.
  Reverb? get reverb => _reverb;
  set reverb(Reverb? value) {
    _synth?.reverb = value;
    _reverb = value;
  }

  Reverb? _reverb;

  final Future<Synth> Function() _open;
  Future<Synth>? _opening;
  Synth? _synth;

  final Map<SoundFont, ({LoadedSoundFont font, int block})> _loaded = {};

  /// Every start and every stop of the device, one after the other. A stop
  /// asked while a start runs comes after it, and a start after a stop
  /// takes the device back from its ring-out, so a rest never closes the
  /// device under the play that follows it.
  Future<void> _device = Future.value();

  bool _disposed = false;

  static const int _blocks = Synth.channelCount ~/ 16;

  @override
  Future<void> load(SoundFont soundFont) async {
    final synth = await (_opening ??= _openSynth());
    if (_disposed) {
      return;
    }
    if (_loaded.length == _blocks) {
      throw StateError('An output plays from at most $_blocks SoundFonts.');
    }
    final font = await synth.load(soundFont);
    if (!_disposed) {
      _loaded[soundFont] = (font: font, block: _loaded.length);
    }
  }

  Future<Synth> _openSynth() async {
    final Synth synth;
    try {
      synth = await _open();
    } on Object {
      _opening = null;
      rethrow;
    }
    if (_disposed) {
      unawaited(synth.close());
      return synth;
    }
    if (synth.reverb != _reverb) {
      synth.reverb = _reverb;
    }
    if (synth.gain != gain) {
      synth.gain = gain;
    }
    return _synth = synth;
  }

  /// A preset that [soundFont] lacks leaves [channel] silent and is not a
  /// failure, so the other parts of a score still play.
  @override
  Future<void> program({
    required SoundFont soundFont,
    required int channel,
    required int program,
    required int bank,
  }) {
    final synth = _synth!;
    final (:font, :block) = _loaded[soundFont]!;
    try {
      synth.select(
        channel: block * 16 + channel,
        font: font,
        program: program,
        bank: bank,
      );
    } on PresetNotFound {
      // The channel plays nothing, which is what a missing preset means.
    }
    final started = _device.then((_) {
      if (!_disposed) {
        return synth.start();
      }
    });
    _device = started.then((_) {}, onError: (Object _) {});
    return started;
  }

  @override
  void noteOn({
    required SoundFont soundFont,
    required int channel,
    required int key,
    required int velocity,
    required int cents,
  }) => _synth!.noteOn(
    channel: _channel(soundFont, channel),
    key: key,
    velocity: velocity.clamp(1, 127),
    cents: cents.toDouble(),
  );

  @override
  void noteOff({
    required SoundFont soundFont,
    required int channel,
    required int key,
  }) => _synth!.noteOff(channel: _channel(soundFont, channel), key: key);

  @override
  void allNotesOff() => _synth?.allSoundsOff();

  @override
  void rest() {
    if (_synth case final synth?) {
      _device = _device.then((_) {
        if (!_disposed) {
          unawaited(synth.stop(ringOut: true));
        }
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loaded.clear();
    if (_synth case final synth?) {
      unawaited(synth.close());
    }
  }

  int _channel(SoundFont soundFont, int channel) =>
      _loaded[soundFont]!.block * 16 + channel;
}
