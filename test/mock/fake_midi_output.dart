import 'dart:async';

import 'package:khuur_sheet_music/src/midi_output.dart';
import 'package:khuur_synth/khuur_synth.dart';

/// A note on as [FakeMidiOutput] received it, with the wall second it
/// arrived at.
typedef SentNote = ({
  double at,
  SoundFont soundFont,
  int channel,
  int key,
  int velocity,
  int cents,
});

/// A program as [FakeMidiOutput] received it.
typedef SentProgram = ({
  SoundFont soundFont,
  int channel,
  int bank,
  int program,
});

/// A key that is on, on a channel of a SoundFont.
typedef HeldKey = ({SoundFont soundFont, int channel, int key});

/// Records what a `ScorePlayer` sends, and when.
final class FakeMidiOutput implements MidiOutput {
  FakeMidiOutput(this._now);

  final Duration Function() _now;

  /// Every call in order, with the wall second it arrived at, as
  /// `1.500 on 0:60`. A note is written `channel:key` and a program
  /// `channel = bank/program`. [ons], [programs] and [held] say which
  /// SoundFont each is from.
  final List<String> log = [];

  final List<SentNote> ons = [];

  final List<SentProgram> programs = [];

  /// The keys that are on. A key struck twice without a note off between
  /// is here twice.
  final List<HeldKey> held = [];

  /// The SoundFont of every [load], in order.
  final List<SoundFont> loaded = [];

  /// When set, [load] does not complete before it.
  Completer<void>? loadGate;

  /// What [load] fails with for each SoundFont here.
  final Map<SoundFont, Object> loadErrors = {};

  /// When set, no [program] completes before it.
  Completer<void>? programGate;

  /// When set, every [program] fails with it.
  Object? programError;

  double get _seconds => _now().inMicroseconds / 1e6;

  void _record(String call) => log.add('${_seconds.toStringAsFixed(3)} $call');

  @override
  Future<void> load(SoundFont soundFont) async {
    _record('load');
    loaded.add(soundFont);
    await loadGate?.future;
    if (loadErrors[soundFont] case final error?) {
      // ignore: only_throw_errors
      throw error;
    }
  }

  @override
  Future<void> program({
    required SoundFont soundFont,
    required int channel,
    required int program,
    required int bank,
  }) async {
    _record('program $channel = $bank/$program');
    programs.add(
      (soundFont: soundFont, channel: channel, bank: bank, program: program),
    );
    await programGate?.future;
    if (programError case final error?) {
      // ignore: only_throw_errors
      throw error;
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
    _record('on $channel:$key');
    ons.add(
      (
        at: _seconds,
        soundFont: soundFont,
        channel: channel,
        key: key,
        velocity: velocity,
        cents: cents,
      ),
    );
    held.add((soundFont: soundFont, channel: channel, key: key));
  }

  @override
  void noteOff({
    required SoundFont soundFont,
    required int channel,
    required int key,
  }) {
    _record('off $channel:$key');
    held.remove((soundFont: soundFont, channel: channel, key: key));
  }

  @override
  void allNotesOff() {
    _record('all off');
    held.clear();
  }

  @override
  void rest() => _record('rest');

  @override
  void dispose() => _record('dispose');
}
