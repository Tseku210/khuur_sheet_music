import 'dart:async';

import 'package:khuur_sheet_music/khuur_sheet_music.dart';

/// A key that is on, on a channel of a SoundFont.
typedef HeldKey = ({SoundFont soundFont, int channel, int key});

/// What a load or a program that [ContractOutput] holds back fails with.
final class InjectedFailure implements Exception {
  const InjectedFailure(this.what);

  final String what;

  @override
  String toString() => 'InjectedFailure($what)';
}

/// A promise that `ScorePlayer` broke, as the search saw it.
final class Violation {
  const Violation(this.property, this.detail);

  /// One of the property names in `README.md` of the skill.
  final String property;
  final String detail;

  @override
  String toString() => '$property: $detail';
}

/// One `load` or `program` that waits for the search to finish or fail it.
final class Pending {
  Pending(this.soundFont, {required this.play, this.channel});

  final SoundFont soundFont;

  /// Which call of `play` the player was serving when it asked, counted
  /// from 1. A program of an older call than the latest one is stale.
  final int play;

  /// The channel of a program, or null for a load.
  final int? channel;

  final Completer<void> completer = Completer();
}

/// A synthesizer that holds `ScorePlayer` to the contract of [MidiOutput]
/// and to its own bookkeeping of keys.
///
/// It records a [Violation] and carries on, rather than throwing, so a
/// broken promise does not change what the player does next.
final class ContractOutput implements MidiOutput {
  ContractOutput({required this.statusNow, required this.playCalls});

  /// The player's status as its listeners see it now.
  final PlayerStatus Function() statusNow;

  /// How many times `play` has been called so far.
  final int Function() playCalls;

  final List<Violation> violations = [];

  /// Every call in order, as `on reed 1:67`.
  final List<String> log = [];

  /// The note calls since no key was last held. Part of the search's
  /// state.
  final List<String> sinceQuiet = [];

  /// The keys that are on. A key struck twice would be here twice.
  final List<HeldKey> held = [];

  /// When true, every [load] and [program] waits in [pendingLoads] or
  /// [pendingPrograms] until the search finishes or fails it. When false
  /// they finish at once.
  bool holding = false;

  final List<Pending> pendingLoads = [];
  final List<Pending> pendingPrograms = [];

  /// The SoundFonts whose load finished and did not fail.
  final Set<SoundFont> loaded = {};

  /// The SoundFonts with a load that has not finished.
  final Set<SoundFont> loading = {};

  /// The channels of each SoundFont whose program finished.
  final Set<(SoundFont, int)> programmed = {};

  final Map<(SoundFont, int), int> expressed = {};

  bool movedUnderHeldKey = false;

  /// True from a [rest] until the next [program]. A note then breaks the
  /// promise of [rest].
  bool rested = false;

  bool disposed = false;

  void violate(String property, String detail) =>
      violations.add(Violation(property, detail));

  void _record(String call, {bool note = false}) {
    log.add(call);
    if (note) {
      sinceQuiet.add(call);
    }
    if (disposed) {
      violate('output-contract', '$call after dispose');
    }
  }

  void _quietIfSilent() {
    if (held.isEmpty) {
      sinceQuiet.clear();
    }
  }

  @override
  Future<void> load(SoundFont soundFont) {
    _record('load ${nameOf(soundFont)}');
    if (loaded.contains(soundFont) || loading.contains(soundFont)) {
      violate(
        'output-contract',
        'load of ${nameOf(soundFont)}, which is already loaded or loading',
      );
    }
    loading.add(soundFont);
    final pending = Pending(soundFont, play: playCalls());
    pending.completer.future.then(
      (_) {
        loading.remove(soundFont);
        loaded.add(soundFont);
      },
      onError: (Object _) {
        loading.remove(soundFont);
      },
    );
    if (holding) {
      pendingLoads.add(pending);
    } else {
      pending.completer.complete();
    }
    return pending.completer.future;
  }

  @override
  Future<void> program({
    required SoundFont soundFont,
    required int channel,
    required int program,
    required int bank,
  }) {
    _record('program ${nameOf(soundFont)} $channel');
    rested = false;
    if (!loaded.contains(soundFont)) {
      violate(
        'output-contract',
        'program on ${nameOf(soundFont)} before its load finished',
      );
    }
    final pending = Pending(soundFont, play: playCalls(), channel: channel);
    pending.completer.future.then(
      (_) {
        programmed.add((soundFont, channel));
      },
      onError: (Object _) {},
    );
    if (holding) {
      pendingPrograms.add(pending);
    } else {
      pending.completer.complete();
    }
    return pending.completer.future;
  }

  @override
  void noteOn({
    required SoundFont soundFont,
    required int channel,
    required int key,
    required int velocity,
    required int cents,
  }) {
    final name = 'on ${nameOf(soundFont)} $channel:$key';
    _record(name, note: true);
    final voice = (soundFont: soundFont, channel: channel, key: key);
    if (held.contains(voice)) {
      violate('one-strike-per-key', '$name while that key is held');
    }
    _whilePlaying(name);
    if (!loaded.contains(soundFont)) {
      violate('output-contract', '$name before its SoundFont loaded');
    } else if (!programmed.contains((soundFont, channel))) {
      violate('output-contract', '$name before its channel has a program');
    }
    if (rested) {
      violate('output-contract', '$name after rest, before a program');
    }
    held.add(voice);
  }

  @override
  void expression({
    required SoundFont soundFont,
    required int channel,
    required int value,
  }) {
    _record('expression ${nameOf(soundFont)} $channel = $value');
    final before = expressed[(soundFont, channel)];
    if (before != null &&
        before != value &&
        held.any((v) => v.soundFont == soundFont && v.channel == channel)) {
      movedUnderHeldKey = true;
    }
    expressed[(soundFont, channel)] = value;
  }

  @override
  void noteOff({
    required SoundFont soundFont,
    required int channel,
    required int key,
  }) {
    final name = 'off ${nameOf(soundFont)} $channel:$key';
    _record(name, note: true);
    if (!held.remove((soundFont: soundFont, channel: channel, key: key))) {
      violate('off-matches-on', '$name for a key that is not held');
    }
    _whilePlaying(name);
    _quietIfSilent();
  }

  @override
  void allNotesOff() {
    _record('all off', note: true);
    held.clear();
    _quietIfSilent();
  }

  @override
  void rest() {
    _record('rest');
    rested = true;
  }

  @override
  void dispose() {
    _record('dispose');
    disposed = true;
  }

  void _whilePlaying(String call) {
    final status = statusNow();
    if (status != PlayerStatus.playing) {
      violate('notes-only-while-playing', '$call while ${status.name}');
    }
  }
}

/// A short name for each SoundFont the search uses.
String nameOf(SoundFont soundFont) => switch (soundFont) {
  AssetSoundFont(:final key) => key.split('.').first,
  FileSoundFont(:final path) => path,
};
