import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:khuur_sheet_music/src/midi_output.dart';
import 'package:khuur_sheet_music/src/sound_font.dart';
import 'package:score_model/score_model.dart';

/// Plays a score over MIDI and reports where it is, for the sheet to show.
///
/// It owns the `PlaybackCompiler` (whose fragment cache makes recompiling
/// after an edit cheap), the SoundFonts, the MIDI output through
/// `flutter_midi_pro` (Android, iOS and macOS), and one script clock that
/// two readers share.
///
/// The clock maps wall time to script seconds from one anchor. A one-shot
/// timer reads it to sleep until the script's next note starts or ends, and
/// sends that when it wakes. A ticker reads it once per frame to publish
/// [position]. Neither keeps time of its own, so the sound and the playhead
/// cannot drift apart.
///
/// The timer does not wait for a frame to be drawn, so sound goes on when
/// nothing repaints. It does run on the UI isolate, as the plugin's
/// `playNote` takes no timestamp. A note is therefore late by as long as
/// the isolate is busy when the note is due, which is at most one build or
/// one layout. A note that both starts and ends while the isolate is busy
/// is not sent.
///
/// The timer also owns the end of playback and the wrap of a loop. A ticker
/// is muted while the app's tickers are off, and sound must still stop at
/// the end then. The ticker only publishes.
///
/// A change of speed moves the anchor to the present first. That is a new
/// [tempoScale], [pause] and [resume]. So the script second is continuous
/// across the change, and the note timer is cancelled and set again from
/// the new anchor. The wrap of a loop keeps the anchor and moves the clock
/// back by the loop's length, so the loop's period is exact.
final class ScorePlayer {
  /// A player that loads each SoundFont on the first [play] that needs it.
  ///
  /// [vsync] drives the ticker that publishes [position]. A test passes a
  /// fake [output] and a [now] it controls. [now] is a wall time that never
  /// goes back. The player disposes the output with itself.
  ScorePlayer({
    required this.soundFont,
    required TickerProvider vsync,
    this.instrumentSoundFonts = const {},
    MidiOutput? output,
    Duration Function()? now,
  }) : _output = output ?? FlutterMidiOutput(),
       _now = now ?? _stopwatch() {
    _ticker = vsync.createTicker((_) {
      if (_phase case _Playing(:final run)) {
        _publish(run);
      }
    });
  }

  /// The SoundFont a part plays from when [instrumentSoundFonts] has none
  /// for its instrument.
  final SoundFont soundFont;

  /// The SoundFont each instrument plays from, by `Instrument.key`, in
  /// place of [soundFont]. A score saves its instruments and not where
  /// their sounds are, so the app gives the files here.
  final Map<String, SoundFont> instrumentSoundFonts;

  final MidiOutput _output;
  final Duration Function() _now;
  late final Ticker _ticker;
  final PlaybackCompiler _compiler = PlaybackCompiler();

  final ValueNotifier<PlayerStatus> _status = ValueNotifier(PlayerStatus.idle);
  final ValueNotifier<PlaybackPosition?> _position = ValueNotifier(null);

  _Phase _phase = const _Idle();

  /// One load of each SoundFont serves every [play], until it fails.
  final Map<SoundFont, Future<void>> _loads = {};
  Timer? _timer;
  double _tempoScale = 1;

  /// Where playback is, or null when stopped. Null as soon as the player
  /// leaves its run, also for a [status] listener that runs before the
  /// position's own listeners are told.
  ValueListenable<PlaybackPosition?> get position => _runPosition;
  late final _runPosition = _RunPosition(this);

  /// Whether the player is loading, playing or paused. Returns to
  /// [PlayerStatus.idle] when the score ends, so an app's play button needs
  /// no state of its own.
  ValueListenable<PlayerStatus> get status => _status;

  /// Speed relative to the written tempo: 1 as written, 0.5 half speed.
  /// Takes effect immediately, also while playing. The position does not
  /// jump, and the next note sounds at the new speed.
  ///
  /// Throws an [ArgumentError] unless the value is positive and finite.
  double get tempoScale => _tempoScale;
  set tempoScale(double value) {
    if (!(value > 0 && value.isFinite)) {
      throw ArgumentError.value(value, 'tempoScale', 'Must be positive');
    }
    _tempoScale = value;
    if (_phase case _Playing(:final run)) {
      run.clock = run.clock.rescaled(_now(), value);
      _sleep(run);
    }
  }

  /// Compiles [score] and plays it, replacing whatever was playing.
  ///
  /// Starts at [startAt] (with repeats, from `secondsAt`), else at the
  /// beginning. [options] limits playback to a range or mutes parts; with
  /// [loop] what [options] selects repeats until [stop]. Loads each
  /// SoundFont a part that plays needs, if no earlier call loaded it, and
  /// sets each part's program from it, with [status] at
  /// [PlayerStatus.loading] meanwhile.
  ///
  /// The future completes when playback has started, or when a later
  /// [play], [stop] or [dispose] took its place. It fails when a SoundFont
  /// cannot be loaded or a program cannot be set, and the player is then
  /// idle. The next call loads again each SoundFont that failed. It fails
  /// before anything changes when [options] names a point that is not in
  /// [score].
  Future<void> play(
    Score score, {
    ScorePoint? startAt,
    PlaybackOptions options = const PlaybackOptions(),
    bool loop = false,
  }) async {
    final script = _compiler.compile(score, options);
    final ofPart = {
      for (final Part(:id, :instrument) in score.parts)
        id: instrumentSoundFonts[instrument.key] ?? soundFont,
    };
    final ofStaff = {
      for (final Part(:id, :staves) in score.parts)
        for (final staff in staves) staff.id: ofPart[id]!,
    };
    _stopRun();
    final loading = _Loading();
    _enter(loading);
    _position.value = null;
    try {
      final files = {
        for (final ChannelSetup(:part) in script.channels) ofPart[part]!,
      };
      await Future.wait([for (final file in files) _load(file)]);
      if (!identical(_phase, loading)) {
        return;
      }
      await _setPrograms(script.channels, ofPart);
    } on Object {
      if (!identical(_phase, loading)) {
        return;
      }
      _enter(const _Idle());
      rethrow;
    }
    if (!identical(_phase, loading)) {
      return;
    }
    final from = switch (startAt) {
      final point? => script.secondsAt(point) ?? 0.0,
      null => 0.0,
    };
    final notes = script.notesBetween(0, double.infinity).toList();
    final run = _Run(
      script,
      notes,
      ofStaff,
      loop: loop && script.totalSeconds > 0,
      clock: _ScriptClock(wall: _now(), seconds: from, scale: _tempoScale),
      unsent: notes.length - script.notesBetween(from, double.infinity).length,
    );
    final playing = _Playing(run);
    _ticker.start();
    _enter(playing);
    if (identical(_phase, playing)) {
      _wake(run, from);
      _publish(run);
    }
  }

  /// Lets go of every sounding note and holds the position. A note cut
  /// short here is not struck again by [resume]. Does nothing unless
  /// playing.
  void pause() {
    if (_phase case _Playing(:final run)) {
      run.clock = run.clock.rescaled(_now(), 0);
      _timer?.cancel();
      _ticker.stop();
      _silence(run);
      _enter(_Paused(run));
      _publish(run);
    }
  }

  /// Plays on from where [pause] left off. Does nothing unless paused.
  void resume() {
    if (_phase case _Paused(:final run)) {
      run.clock = run.clock.rescaled(_now(), _tempoScale);
      _ticker.start();
      _sleep(run);
      _enter(_Playing(run));
    }
  }

  /// Stops sound, clears [position] and goes idle.
  void stop() {
    _goIdle();
    _output.allNotesOff();
  }

  /// Stops sound and frees every SoundFont. Notifies no listener. Not to be
  /// called from a listener of [status] or [position].
  void dispose() {
    _stopRun();
    _phase = const _Idle();
    _ticker.dispose();
    _status.dispose();
    _position.dispose();
    _output.dispose();
  }

  /// The run that is playing or paused.
  _Run? get _run => switch (_phase) {
    _Playing(:final run) || _Paused(:final run) => run,
    _Idle() || _Loading() => null,
  };

  /// Makes [phase] the player's phase and tells the status listeners. A
  /// listener may call back into the player, so whatever follows this in a
  /// method must hold for any phase.
  void _enter(_Phase phase) {
    _phase = phase;
    _status.value = phase.status;
  }

  Future<void> _load(SoundFont soundFont) async {
    final load = _loads[soundFont] ??= _output.load(soundFont);
    try {
      await load;
    } on Object {
      _loads.removeWhere((_, each) => identical(each, load));
      rethrow;
    }
  }

  /// Asks for every program before the first answer comes, so the programs
  /// of an older [play] cannot land after those of a newer one.
  Future<void> _setPrograms(
    List<ChannelSetup> channels,
    Map<PartId, SoundFont> ofPart,
  ) => Future.wait([
    for (final ChannelSetup(:part, :channel, :program, :bank) in channels)
      _output.program(
        soundFont: ofPart[part]!,
        channel: channel,
        program: program,
        bank: bank,
      ),
  ]);

  /// Sends what is due and sleeps until the next thing is. [due] is the
  /// script second the timer was set for. A timer can fire a moment early,
  /// and what it was set for is due all the same.
  void _wake(_Run run, double due) {
    var at = max(run.clock.secondsAt(_now()), due);
    final total = run.script.totalSeconds;
    if (at >= total) {
      if (!run.loop) {
        _goIdle();
        return;
      }
      _silence(run);
      // The clock moves back by whole passes and keeps its anchor, so a
      // timer that woke early or late does not change the loop's period.
      final passed = (at / total).floorToDouble() * total;
      at -= passed;
      run
        ..clock = run.clock.earlier(passed)
        ..unsent = 0;
    }
    run.soundingUntil.removeWhere((voice, end) {
      if (end > at) {
        return false;
      }
      _output.noteOff(
        soundFont: voice.soundFont,
        channel: voice.channel,
        key: voice.key,
      );
      return true;
    });
    for (; run.unsent < run.notes.length; run.unsent++) {
      final note = run.notes[run.unsent];
      if (note.start > at) {
        break;
      }
      final end = note.start + note.duration + note.overlap * _tempoScale;
      final endedInAStall = end <= at;
      if (endedInAStall) {
        continue;
      }
      // A channel holds a key once, so a key that is struck again is let go
      // first and then held to the later of the two ends.
      final soundFont = run.soundFonts[note.source.staff]!;
      final voice = (
        soundFont: soundFont,
        channel: note.channel,
        key: note.key,
      );
      final held = run.soundingUntil[voice];
      if (held != null) {
        _output.noteOff(
          soundFont: soundFont,
          channel: note.channel,
          key: note.key,
        );
      }
      _output.noteOn(
        soundFont: soundFont,
        channel: note.channel,
        key: note.key,
        velocity: note.velocity,
        cents: note.cents,
      );
      run.soundingUntil[voice] = max(held ?? end, end);
    }
    _sleep(run);
  }

  void _sleep(_Run run) {
    var next = run.script.totalSeconds;
    if (run.unsent < run.notes.length) {
      next = min(next, run.notes[run.unsent].start);
    }
    for (final end in run.soundingUntil.values) {
      next = min(next, end);
    }
    _timer?.cancel();
    _timer = Timer(run.clock.wallAt(next) - _now(), () => _wake(run, next));
  }

  void _silence(_Run run) {
    for (final (:soundFont, :channel, :key) in run.soundingUntil.keys) {
      _output.noteOff(soundFont: soundFont, channel: channel, key: key);
    }
    run.soundingUntil.clear();
  }

  /// Stops the timer and the ticker and lets go of what sounds. The caller
  /// enters the next phase.
  void _stopRun() {
    _timer?.cancel();
    _ticker.stop();
    if (_run case final run?) {
      _silence(run);
    }
  }

  void _goIdle() {
    _stopRun();
    _enter(const _Idle());
    _position.value = null;
  }

  /// Publishes where [run] is, unless the player has left it.
  void _publish(_Run run) {
    if (!identical(_run, run)) {
      return;
    }
    final seconds = run.clock.secondsAt(_now());
    final point = run.script.pointAt(seconds);
    // Past the script's end the timer is about to end the run or wrap it.
    if (point == null) {
      return;
    }
    _position.value = PlaybackPosition(
      seconds: seconds,
      point: point,
      sounding: run.script.sourcesAt(seconds),
    );
  }
}

/// [ScorePlayer._position], read as null while the player has no run.
final class _RunPosition implements ValueListenable<PlaybackPosition?> {
  _RunPosition(this._player);

  final ScorePlayer _player;

  @override
  PlaybackPosition? get value =>
      _player._run == null ? null : _player._position.value;

  @override
  void addListener(VoidCallback listener) =>
      _player._position.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _player._position.removeListener(listener);
}

Duration Function() _stopwatch() {
  final watch = Stopwatch()..start();
  return () => watch.elapsed;
}

/// What the player is doing. [ScorePlayer.status] shows it to the app.
sealed class _Phase {
  const _Phase();

  PlayerStatus get status;
}

final class _Idle extends _Phase {
  const _Idle();

  @override
  PlayerStatus get status => PlayerStatus.idle;
}

/// One [ScorePlayer.play] call waiting for the SoundFonts and the programs.
/// The call starts playback only if this is still the phase when they are
/// ready, so any phase entered meanwhile withdraws it.
final class _Loading extends _Phase {
  @override
  PlayerStatus get status => PlayerStatus.loading;
}

final class _Playing extends _Phase {
  const _Playing(this.run);

  final _Run run;

  @override
  PlayerStatus get status => PlayerStatus.playing;
}

final class _Paused extends _Phase {
  const _Paused(this.run);

  final _Run run;

  @override
  PlayerStatus get status => PlayerStatus.paused;
}

/// One playback of a script.
final class _Run {
  _Run(
    this.script,
    this.notes,
    this.soundFonts, {
    required this.loop,
    required this.clock,
    required this.unsent,
  });

  final PlaybackScript script;

  /// Sorted by start.
  final List<PlaybackNote> notes;

  /// The SoundFont the notes of each staff play from.
  final Map<StaffId, SoundFont> soundFonts;

  final bool loop;

  /// Replaced at every change of speed. Its scale is 0 while paused.
  _ScriptClock clock;

  /// The index in [notes] of the first note not yet sent.
  int unsent;

  /// The script second at which each key that is on gets its note off.
  final Map<({SoundFont soundFont, int channel, int key}), double>
  soundingUntil = {};
}

/// Script seconds as a function of wall time, from one anchor.
///
/// `secondsAt(now) = seconds + scale * (now - wall)`. [wallAt] is the
/// inverse the note timer sleeps by.
final class _ScriptClock {
  const _ScriptClock({
    required this.wall,
    required this.seconds,
    required this.scale,
  });

  final Duration wall;
  final double seconds;

  /// Script seconds per wall second.
  final double scale;

  double secondsAt(Duration now) =>
      seconds + scale * (now - wall).inMicroseconds / 1e6;

  Duration wallAt(double at) {
    assert(scale > 0, 'A paused clock reaches no later second.');
    return wall +
        Duration(microseconds: ((at - seconds) / scale * 1e6).round());
  }

  /// The same script second at [now], running at [scale] from there.
  _ScriptClock rescaled(Duration now, double scale) =>
      _ScriptClock(wall: now, seconds: secondsAt(now), scale: scale);

  /// This clock reading [by] script seconds less at every wall time.
  _ScriptClock earlier(double by) =>
      _ScriptClock(wall: wall, seconds: seconds - by, scale: scale);
}

/// What a [ScorePlayer] is doing.
enum PlayerStatus {
  /// Nothing is playing. [ScorePlayer.play] starts playback.
  idle,

  /// [ScorePlayer.play] was called. The SoundFonts are loading or the
  /// programs are being set.
  loading,

  /// Notes are being sent.
  playing,

  /// Held by [ScorePlayer.pause] until [ScorePlayer.resume].
  paused,
}

/// One frame's playback position.
@immutable
final class PlaybackPosition {
  const PlaybackPosition({
    required this.seconds,
    required this.point,
    required this.sounding,
  });

  /// Script time, which runs at [ScorePlayer.tempoScale] times real time.
  final double seconds;

  /// The bar, pass and continuous offset, for the playhead.
  final PlaybackPoint point;

  /// The events sounding now, one per voice, for the highlight. May include
  /// events on hidden staves; the sheet skips any it did not draw.
  final List<EventRef> sounding;
}
