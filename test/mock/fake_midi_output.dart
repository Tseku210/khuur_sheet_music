import 'dart:async';

import 'package:khuur_sheet_music/src/midi_output.dart';
import 'package:khuur_sheet_music/src/sound_font.dart';

/// A note on as [FakeMidiOutput] received it, with the wall second it
/// arrived at.
typedef SentNote = ({
  double at,
  int channel,
  int key,
  int velocity,
  int cents,
});

/// Records what a `ScorePlayer` sends, and when.
final class FakeMidiOutput implements MidiOutput {
  FakeMidiOutput(this._now);

  final Duration Function() _now;

  /// Every call in order, with the wall second it arrived at, as
  /// `1.500 on 0:60`. A note is written `channel:key` and a program
  /// `channel = bank/program`.
  final List<String> log = [];

  final List<SentNote> ons = [];

  /// The notes that are on, as `channel:key`. A key struck twice without a
  /// note off between is here twice.
  final List<String> held = [];

  /// The SoundFont of every [load], in order.
  final List<SoundFont> loaded = [];

  /// When set, [load] does not complete before it.
  Completer<void>? loadGate;

  /// When set, [load] fails with it.
  Object? loadError;

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
    if (loadError case final error?) {
      // ignore: only_throw_errors
      throw error;
    }
  }

  @override
  Future<void> program({
    required int channel,
    required int program,
    required int bank,
  }) async {
    _record('program $channel = $bank/$program');
    await programGate?.future;
    if (programError case final error?) {
      // ignore: only_throw_errors
      throw error;
    }
  }

  @override
  void noteOn({
    required int channel,
    required int key,
    required int velocity,
    required int cents,
  }) {
    _record('on $channel:$key');
    ons.add(
      (
        at: _seconds,
        channel: channel,
        key: key,
        velocity: velocity,
        cents: cents,
      ),
    );
    held.add('$channel:$key');
  }

  @override
  void noteOff({required int channel, required int key}) {
    _record('off $channel:$key');
    held.remove('$channel:$key');
  }

  @override
  void allNotesOff() {
    _record('all off');
    held.clear();
  }

  @override
  void dispose() => _record('dispose');
}
