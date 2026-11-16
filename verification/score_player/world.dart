import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:khuur_sheet_music/khuur_sheet_music.dart';

import '../../packages/khuur_score_model/test/support.dart'
    show
        at,
        blankScore,
        changeBar,
        chordOf,
        clarinet,
        fill,
        piano,
        pointAt,
        rest;
import '../../test/mock/fake_wall_time.dart';
import 'contract_output.dart';

const pianoFile = AssetSoundFont('piano.sf2');
const reedFile = AssetSoundFont('reed.sf2');

/// How far one [Step.wait] or [Step.stall] moves the wall clock.
const stepTime = Duration(milliseconds: 500);

/// One thing that can happen to a `ScorePlayer`: a call from the app, time
/// passing, a load or program finishing, or a listener calling back in.
enum Step {
  playA('play the restrike tune'),
  playD('play the duet, looping, from its second beat'),
  pause('pause'),
  resume('resume'),
  stop('stop'),
  tempo('switch tempoScale between 1 and 0.5'),
  wait('let 0.5 s pass, firing the timers that come due'),
  stall('keep the isolate busy for 0.5 s, so the timers due then fire late'),
  hold('hold every later load and program until the search ends it'),
  loadOk('finish the oldest held load'),
  loadFails('fail the oldest held load'),
  programsOk('finish every held program'),
  programFails('fail the oldest held program'),
  onStatusPause('arm a status listener that calls pause once'),
  onStatusResume('arm a status listener that calls resume once'),
  onStatusStop('arm a status listener that calls stop once'),
  onStatusPlayA('arm a status listener that plays the restrike tune once'),
  onStatusTempo('arm a status listener that switches tempoScale once'),
  onPositionStop('arm a position listener that calls stop once'),
  onPositionPlayA('arm a position listener that plays the restrike tune once'),
  dispose('dispose the player');

  Step(this.words);

  final String words;
}

/// The restrike tune: a whole C4 with a quarter C4 struck over it on beat
/// 2, at 120 quarters a minute, so one bar lasts 2 s. Its key is struck
/// again while it is held.
Score restrikeTune() {
  final score = fill(atTempo(blankScore(bars: 1)), 0, [
    chordOf(1, 'C4', value: NoteValue.whole),
  ]);
  return fill(
    score,
    0,
    [rest(2, NoteValue.quarter), chordOf(3, 'C4'), rest(4, NoteValue.half)],
    slot: VoiceSlot.two,
  );
}

/// The duet: quarters C4 D4 E4 F4 on a piano over a whole G4 on a
/// clarinet, which plays from [reedFile], at 120 quarters a minute.
Score duet() {
  var score = atTempo(blankScore(parts: const [piano, clarinet], bars: 1));
  score = fill(score, 0, [
    for (final (beat, pitch) in const ['C4', 'D4', 'E4', 'F4'].indexed)
      chordOf(11 + beat, pitch),
  ]);
  return fill(score, 0, [
    chordOf(1, 'G4', value: NoteValue.whole),
  ], staff: 2);
}

Score atTempo(Score score) => changeBar(
  score,
  0,
  (column) => column.copyWith(
    tempos: Seq([
      const TempoMark(offset: Moment.zero, tempo: Tempo(120)),
    ]),
  ),
);

/// A score the search plays, with what the player needs to play it and
/// what the checks need to know about it.
final class Tune {
  Tune(this.name, this.score, {this.loop = false, this.startAt}) {
    script = PlaybackCompiler().compile(score);
    final ofPart = {
      for (final Part(:id, :instrument) in score.parts)
        id: instrumentSoundFonts[instrument.key] ?? pianoFile,
    };
    soundFonts = {
      for (final Part(:id, :staves) in score.parts)
        for (final staff in staves) staff.id: ofPart[id]!,
    };
    notes = script
        .notesBetween(double.negativeInfinity, double.infinity)
        .toList();
  }

  final String name;
  final Score score;
  final bool loop;
  final ScorePoint? startAt;
  late final PlaybackScript script;
  late final Map<StaffId, SoundFont> soundFonts;
  late final List<PlaybackNote> notes;

  /// Whether a note of this tune holds [voice] at script second [seconds].
  bool holds(HeldKey voice, double seconds) => notes.any(
    (note) =>
        note.key == voice.key &&
        note.channel == voice.channel &&
        soundFonts[note.source.staff] == voice.soundFont &&
        note.start - _slack <= seconds &&
        seconds <= note.start + note.duration + _slack,
  );
}

const _slack = 1e-6;

const Map<String, SoundFont> instrumentSoundFonts = {
  'clarinet-b-flat': reedFile,
};

final restrike = Tune('restrike', restrikeTune());
final looping = Tune(
  'duet',
  duet(),
  loop: true,
  startAt: pointAt(duet(), 0, at(1, 4)),
);

/// A note timer the player set, as the search's zone saw it made.
final class Wake {
  Wake(this.timer, {required this.dueFake, required this.stalledAtSet});

  final Timer timer;

  /// The test clock's time at which the timer fires.
  final Duration dueFake;

  /// [FakeWallTime.stalled] when the timer was set.
  final Duration stalledAtSet;
}

/// One fresh player that a path of [Step]s is replayed on.
final class World {
  World(this.tester) : time = FakeWallTime(tester.binding) {
    output = ContractOutput(
      statusNow: () => player.status.value,
      playCalls: () => playCalls,
    );
    zone = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createTimer(zone, duration, callback);
          wakes.add(
            Wake(
              timer,
              dueFake:
                  _fakeNow() +
                  (duration < Duration.zero ? Duration.zero : duration),
              stalledAtSet: time.stalled,
            ),
          );
          return timer;
        },
      ),
    );
    player = ScorePlayer(
      soundFont: pianoFile,
      instrumentSoundFonts: instrumentSoundFonts,
      vsync: tester,
      output: output,
      now: time.now,
    );
    player.status.addListener(_onStatus);
    player.position.addListener(_onPosition);
  }

  final WidgetTester tester;
  final FakeWallTime time;
  late final ContractOutput output;
  late final ScorePlayer player;
  late final Zone zone;
  final List<Wake> wakes = [];

  int playCalls = 0;

  /// The tune of the latest call of `play`, or null before the first.
  Tune? latest;

  Step? armed;
  bool disposed = false;

  /// What this world reached that the search must reach somewhere, so that
  /// a pass is not vacuous. See [mustReach].
  final Set<String> reached = {};

  List<Violation> get violations => output.violations;

  Duration _fakeNow() => tester.binding.clock.now().difference(_epoch);

  static final DateTime _epoch = DateTime.utc(2000);

  PlayerStatus get status => player.status.value;

  Iterable<Wake> get activeWakes => wakes.where((wake) => wake.timer.isActive);

  /// Whether [step] can happen now. A call that does nothing in this
  /// status is left out, since the checks would see no change.
  bool canTake(Step step) {
    if (disposed) {
      return false;
    }
    return switch (step) {
      Step.pause => status == PlayerStatus.playing,
      Step.resume => status == PlayerStatus.paused,
      Step.stop => status != PlayerStatus.idle,
      Step.stall => status == PlayerStatus.playing,
      Step.hold => !output.holding,
      Step.loadOk || Step.loadFails => output.pendingLoads.isNotEmpty,
      Step.programsOk || Step.programFails => output.pendingPrograms.isNotEmpty,
      Step.onStatusPause ||
      Step.onStatusResume ||
      Step.onStatusStop ||
      Step.onStatusPlayA ||
      Step.onStatusTempo ||
      Step.onPositionStop ||
      Step.onPositionPlayA => armed == null,
      Step.playA ||
      Step.playD ||
      Step.tempo ||
      Step.wait ||
      Step.dispose => true,
    };
  }

  /// Takes [step], then lets a frame be drawn, as the app would before the
  /// next event.
  Future<void> take(Step step) async {
    switch (step) {
      case Step.wait:
        final before = status;
        await tester.pump(stepTime);
        if (before == PlayerStatus.playing && status == PlayerStatus.idle) {
          reached.add('playback ended by itself');
        }
        _caught();
        return;
      case Step.stall:
        time.stalled += stepTime;
      case Step.hold:
        output.holding = true;
      case Step.loadOk:
        output.pendingLoads.removeAt(0).completer.complete();
      case Step.loadFails:
        final pending = output.pendingLoads.removeAt(0);
        reached.add('${_age(pending)} load failed');
        pending.completer.completeError(const InjectedFailure('load'));
      case Step.programsOk:
        for (final pending in output.pendingPrograms) {
          pending.completer.complete();
        }
        output.pendingPrograms.clear();
      case Step.programFails:
        final pending = output.pendingPrograms.removeAt(0);
        reached.add('${_age(pending)} program failed');
        pending.completer.completeError(const InjectedFailure('program'));
      case Step.onStatusPause ||
          Step.onStatusResume ||
          Step.onStatusStop ||
          Step.onStatusPlayA ||
          Step.onStatusTempo ||
          Step.onPositionStop ||
          Step.onPositionPlayA:
        armed = step;
      case Step.dispose:
        _call(player.dispose);
        disposed = true;
      case Step.playA ||
          Step.playD ||
          Step.pause ||
          Step.resume ||
          Step.stop ||
          Step.tempo:
        _call(() => _app(step));
    }
    await tester.pump();
    _caught();
  }

  /// Calls what the app calls for [step]. Runs in [zone], so the search
  /// sees every timer the player sets from it.
  void _app(Step step) {
    switch (step) {
      case Step.playA || Step.onStatusPlayA || Step.onPositionPlayA:
        _play(restrike);
      case Step.playD:
        _play(looping);
      case Step.pause || Step.onStatusPause:
        player.pause();
      case Step.resume || Step.onStatusResume:
        player.resume();
      case Step.stop || Step.onStatusStop || Step.onPositionStop:
        player.stop();
      case Step.tempo || Step.onStatusTempo:
        player.tempoScale = player.tempoScale == 1 ? 0.5 : 1;
      case _:
        throw StateError('$step is not a call of the app');
    }
  }

  String _age(Pending pending) =>
      pending.play == playCalls ? 'latest' : 'stale';

  void _play(Tune tune) {
    playCalls++;
    latest = tune;
    player
        .play(tune.score, startAt: tune.startAt, loop: tune.loop)
        .then(
          (_) {},
          onError: (Object error) {
            if (error is! InjectedFailure) {
              output.violate('no-throw', 'play failed with $error');
            }
          },
        );
  }

  void _call(void Function() call) {
    try {
      zone.run(call);
    } on Object catch (error) {
      output.violate('no-throw', '$error');
    }
  }

  void _caught() {
    final Object? error = tester.takeException();
    if (error != null) {
      output.violate('no-throw', '$error');
    }
  }

  void _onStatus() {
    if (status case PlayerStatus.idle || PlayerStatus.loading
        when player.position.value != null) {
      output.violate(
        'no-position-off-run',
        'a status listener sees a position while ${status.name}',
      );
    }
    if (armed case final step? when step.name.startsWith('onStatus')) {
      armed = null;
      reached.add('${step.name} while ${status.name}');
      _call(() => _app(step));
    }
  }

  void _onPosition() {
    if (armed case final step? when step.name.startsWith('onPosition')) {
      armed = null;
      reached.add('${step.name} while ${status.name}');
      _call(() => _app(step));
    }
  }

  /// Checks the promises that hold between events, after the frame that
  /// follows each step.
  void checkSettled() {
    if (disposed) {
      if (output.held.isNotEmpty) {
        output.violate(
          'silent-unless-playing',
          'keys held after dispose: ${_keys(output.held)}',
        );
      }
      if (activeWakes.isNotEmpty) {
        output.violate('one-wake-while-playing', 'a timer after dispose');
      }
      return;
    }
    final playing = status == PlayerStatus.playing;
    reached.add('settled ${status.name}');
    if (playing && _overdue) {
      reached.add('a note timer late');
    }
    if (!playing && output.held.isNotEmpty) {
      output.violate(
        'silent-unless-playing',
        'keys held while ${status.name}: ${_keys(output.held)}',
      );
    }
    if (status case PlayerStatus.idle || PlayerStatus.loading
        when player.position.value != null) {
      output.violate(
        'no-position-off-run',
        'a position while ${status.name}',
      );
    }
    final wakes = activeWakes.length;
    if (playing ? wakes != 1 : wakes != 0) {
      output.violate(
        'one-wake-while-playing',
        '$wakes note timers pending while ${status.name}',
      );
    }
    final asksForFrames = tester.binding.transientCallbackCount > 0;
    if (asksForFrames != playing) {
      output.violate(
        'frames-only-while-playing',
        '${asksForFrames ? 'asks' : 'asks no'} frames while ${status.name}',
      );
    }
    final seconds = player.position.value?.seconds;
    if (playing && seconds != null && !_overdue) {
      final strays = [
        for (final voice in output.held)
          if (!latest!.holds(voice, seconds)) voice,
      ];
      if (strays.isNotEmpty) {
        output.violate(
          'released-on-time',
          'at script second ${seconds.toStringAsFixed(3)} of '
              '${latest!.name}, no note holds ${_keys(strays)}',
        );
      }
    }
  }

  /// Whether a note timer should have fired by the wall clock but has not,
  /// because the isolate was busy.
  bool get _overdue {
    final now = _fakeNow() + time.stalled;
    return activeWakes.any(
      (wake) => wake.dueFake + wake.stalledAtSet <= now,
    );
  }

  /// What the search treats as this world's state. Two paths that reach
  /// the same key are explored once.
  String get key {
    final position = player.position.value;
    final fakeNow = _fakeNow();
    return [
      if (disposed) 'disposed',
      status.name,
      if (status != PlayerStatus.idle) 'run ${latest?.name}',
      'tempo ${player.tempoScale}',
      'at ${position?.seconds.toStringAsFixed(6)}',
      'held ${_keys(output.held)}',
      'since quiet ${output.sinceQuiet}',
      'wakes ${[
        for (final wake in activeWakes) '${(wake.dueFake - fakeNow).inMicroseconds}/${(wake.stalledAtSet - time.stalled).inMicroseconds}',
      ]}',
      'loaded ${[for (final file in output.loaded) nameOf(file)]..sort()}',
      'loading ${[for (final p in output.pendingLoads) nameOf(p.soundFont)]}',
      'programs ${[
        for (final p in output.pendingPrograms) p.play == playCalls ? 'latest' : 'stale',
      ]}',
      if (output.rested) 'rested',
      if (output.holding) 'holding',
      'armed ${armed?.name}',
    ].join(' | ');
  }

  /// Lets go of everything this world left running, so the next world
  /// starts clean and the test ends with no timer.
  Future<void> close() async {
    if (!disposed) {
      _call(player.dispose);
      disposed = true;
    }
    // A timer that outlives dispose would keep firing in every later world.
    final leaked = activeWakes.toList();
    if (leaked.isNotEmpty) {
      output.violate(
        'one-wake-while-playing',
        '${leaked.length} note timers pending after dispose',
      );
      for (final wake in leaked) {
        wake.timer.cancel();
      }
    }
    for (final pending in [...output.pendingLoads, ...output.pendingPrograms]) {
      pending.completer.complete();
    }
    output.pendingLoads.clear();
    output.pendingPrograms.clear();
    await tester.pump(stepTime * 4);
    _caught();
    final log = output.log;
    if (log.any((call) => call.startsWith('on reed'))) {
      reached.add('a loop wrapped');
    }
    for (var i = 1; i < log.length; i++) {
      if (log[i - 1].startsWith('off ') &&
          log[i] == 'on ${log[i - 1].substring(4)}') {
        reached.add('a held key struck again');
      }
    }
  }
}

/// What the search must reach for a pass to mean something. The duet
/// starts after its clarinet note, so a note on the reed means its loop
/// wrapped.
const mustReach = {
  'settled idle',
  'settled loading',
  'settled playing',
  'settled paused',
  'playback ended by itself',
  'a loop wrapped',
  'a held key struck again',
  'a note timer late',
  'latest load failed',
  'stale load failed',
  'latest program failed',
  'stale program failed',
  'onStatusPause while playing',
  'onStatusResume while paused',
  'onStatusStop while loading',
  'onStatusStop while playing',
  'onStatusStop while paused',
  'onStatusPlayA while idle',
  'onStatusPlayA while loading',
  'onStatusPlayA while playing',
  'onStatusTempo while playing',
  'onPositionStop while playing',
  'onPositionPlayA while playing',
};

String _keys(Iterable<HeldKey> keys) => [
  for (final (:soundFont, :channel, :key) in keys)
    '${nameOf(soundFont)} $channel:$key',
].join(', ');
