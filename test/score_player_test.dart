import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_model/score_model.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart'
    show AssetSoundFont, PlaybackPosition, PlayerStatus, ScorePlayer;

import '../packages/score_model/test/support.dart'
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
import 'mock/fake_midi_output.dart';
import 'mock/fake_wall_time.dart';

/// A player over a fake output and the test's fake time.
final class Rig {
  Rig(WidgetTester tester, {TickerProvider? vsync})
      : time = FakeWallTime(tester.binding) {
    midi = FakeMidiOutput(time.now);
    player = ScorePlayer(
      soundFont: const AssetSoundFont('piano.sf2'),
      vsync: vsync ?? tester,
      output: midi,
      now: time.now,
    );
    player.status.addListener(() => statuses.add(player.status.value));
  }

  final FakeWallTime time;
  late final FakeMidiOutput midi;
  late final ScorePlayer player;

  /// Every status the player went through.
  final List<PlayerStatus> statuses = [];

  PlayerStatus get status => player.status.value;

  PlaybackPosition? get position => player.position.value;

  double get seconds => position!.seconds;

  /// Each note on as (wall second, key).
  List<(double, int)> get ons => [
        for (final note in midi.ons) (note.at, note.key),
      ];
}

/// Runs [body] with a player that is disposed when the body ends, so no
/// test leaves a timer behind.
void testPlayer(
  String description,
  Future<void> Function(WidgetTester tester, Rig rig) body,
) =>
    testWidgets(description, (tester) async {
      final rig = Rig(tester);
      try {
        await body(tester, rig);
      } finally {
        rig.player.dispose();
      }
    });

const second = Duration(seconds: 1);
const half = Duration(milliseconds: 500);

/// [score] at 60 quarters a minute, so a quarter lasts one second.
Score atSixty(Score score) => changeBar(
      score,
      0,
      (column) => column.copyWith(
        tempos: Seq([
          const TempoMark(offset: Moment.zero, tempo: Tempo(60)),
        ]),
      ),
    );

/// [bars] bars of the quarters C4 D4 E4 F4 (keys 60, 62, 64, 65) on the
/// first staff, a second each and sounding for 0.9 of it. An event's id is
/// 10 × bar + beat, both counted from 1.
Score tune({int bars = 1, List<PartTemplate> parts = const [piano]}) {
  var score = atSixty(blankScore(parts: parts, bars: bars));
  for (var bar = 0; bar < bars; bar++) {
    score = fill(score, bar, [
      for (final (beat, pitch) in const ['C4', 'D4', 'E4', 'F4'].indexed)
        chordOf(10 * (bar + 1) + beat + 1, pitch),
    ]);
  }
  return score;
}

/// [tune] of one bar for a piano on channel 0, with a clarinet on channel 1
/// that holds a whole note, event 1, under it.
Score duet() => fill(
      tune(parts: const [piano, clarinet]),
      0,
      [chordOf(1, 'G4', value: NoteValue.whole)],
      staff: 2,
    );

class Host extends StatefulWidget {
  const Host(this.create, {super.key});

  final Rig Function(TickerProvider vsync) create;

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> with SingleTickerProviderStateMixin {
  late final Rig rig = widget.create(this);

  @override
  void dispose() {
    rig.player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  group('one clock', () {
    testPlayer(
        'the position is continuous across a new tempoScale, a pause and a '
        'resume', (tester, rig) async {
      await rig.player.play(tune(bars: 2));
      await tester.pump(second);
      expect(rig.seconds, closeTo(1, 1e-9));

      rig.player.tempoScale = 0.5;
      await tester.pump();
      expect(rig.seconds, closeTo(1, 1e-9));
      await tester.pump(second);
      expect(rig.seconds, closeTo(1.5, 1e-9));

      rig.player.pause();
      expect(rig.seconds, closeTo(1.5, 1e-9));
      await tester.pump(second * 3);
      rig.player.resume();
      await tester.pump();
      expect(rig.seconds, closeTo(1.5, 1e-9));
      await tester.pump(second);
      expect(rig.seconds, closeTo(2, 1e-9));

      rig.player.tempoScale = 2;
      await tester.pump();
      expect(rig.seconds, closeTo(2, 1e-9));
      await tester.pump(half);
      expect(rig.seconds, closeTo(3, 1e-9));
    });

    testPlayer(
        'every note is sent at its own script second after a new tempoScale, '
        'a pause and a resume', (tester, rig) async {
      await rig.player.play(tune(bars: 2));
      await tester.pump(second);

      rig.player.tempoScale = 0.5;
      await tester.pump(second * 4.5);
      expect(
        rig.ons,
        [(0.0, 60), (1.0, 62), (3.0, 64), (5.0, 65)],
        reason: 'at half speed the note two script seconds on is sent four '
            'wall seconds on',
      );

      rig.player.pause();
      await tester.pump(second * 4.5);
      rig.player.resume();
      await tester.pump(second * 1.5);
      expect(rig.ons.last, (11.5, 60));

      rig.player.tempoScale = 1;
      await tester.pump(second * 4);
      expect(rig.ons.skip(5), [(12.5, 62), (13.5, 64), (14.5, 65)]);
      expect(rig.status, PlayerStatus.idle);
    });

    testWidgets(
        'with tickers muted, playback still ends, every note is sent and the '
        'status goes idle', (tester) async {
      await tester.pumpWidget(
        TickerMode(
          enabled: false,
          child: Host((vsync) => Rig(tester, vsync: vsync)),
        ),
      );
      final rig = tester.state<HostState>(find.byType(Host)).rig;
      final published = <double?>[];
      rig.player.position.addListener(
        () => published.add(rig.position?.seconds),
      );

      await rig.player.play(tune());
      await tester.pump(second * 2);
      expect(rig.status, PlayerStatus.playing);
      await tester.pump(second * 2);

      expect(published, [0.0, null], reason: 'no frame published a position');
      expect(rig.ons, [(0.0, 60), (1.0, 62), (2.0, 64), (3.0, 65)]);
      expect(rig.midi.held, isEmpty);
      expect(
        rig.statuses,
        [PlayerStatus.loading, PlayerStatus.playing, PlayerStatus.idle],
      );
    });
  });

  group('play', () {
    testPlayer(
        'goes loading, then playing, then idle with the position cleared',
        (tester, rig) async {
      final gate = rig.midi.loadGate = Completer();
      final started = rig.player.play(tune());
      expect(rig.status, PlayerStatus.loading);
      expect(rig.position, isNull);

      gate.complete();
      await started;
      expect(rig.status, PlayerStatus.playing);
      expect(rig.seconds, 0);

      await tester.pump(second * 4);
      expect(
        rig.statuses,
        [PlayerStatus.loading, PlayerStatus.playing, PlayerStatus.idle],
      );
      expect(rig.position, isNull);
      expect(rig.midi.log, [
        '0.000 load',
        '0.000 program 0 = 0/0',
        '0.000 on 0:60',
        '0.900 off 0:60',
        '1.000 on 0:62',
        '1.900 off 0:62',
        '2.000 on 0:64',
        '2.900 off 0:64',
        '3.000 on 0:65',
        '3.900 off 0:65',
      ]);
    });

    testPlayer("sets every channel's program before the first note",
        (tester, rig) async {
      final gate = rig.midi.programGate = Completer();
      final started = rig.player.play(tune(parts: const [piano, clarinet]));
      await tester.pump(second);
      expect(rig.midi.log, [
        '0.000 load',
        '0.000 program 0 = 0/0',
        '0.000 program 1 = 0/71',
      ]);
      expect(rig.status, PlayerStatus.loading);

      gate.complete();
      await started;
      expect(rig.midi.log.last, '1.000 on 0:60');
    });

    testPlayer('sends each note with its channel, key, velocity and cents',
        (tester, rig) async {
      var score = atSixty(blankScore(parts: const [piano, clarinet], bars: 1));
      score = fill(score, 0, [
        chordOf(1, 'C+4'),
        chordOf(2, 'E4 G4'),
        rest(3, NoteValue.half),
      ]);
      score = fill(
        score,
        0,
        [chordOf(4, 'G4', value: NoteValue.whole)],
        staff: 2,
      );
      await rig.player.play(score);
      await tester.pump(second * 4);

      expect(
        rig.midi.ons,
        [
          for (final note
              in PlaybackCompiler().compile(score).notesBetween(0, 4))
            (
              at: note.start,
              channel: note.channel,
              key: note.key,
              velocity: note.velocity,
              cents: note.cents,
            ),
        ],
      );
      expect(
        {for (final note in rig.midi.ons) (note.channel, note.cents)},
        {(0, 50), (0, 0), (1, 0)},
      );
    });

    testPlayer('starts at the second startAt is first reached',
        (tester, rig) async {
      final score = tune();
      await rig.player.play(score, startAt: pointAt(score, 0, at(1, 2)));
      expect(rig.seconds, 2);

      await tester.pump(second * 2);
      expect(rig.ons, [(0.0, 64), (1.0, 65)]);
      expect(rig.status, PlayerStatus.idle);
    });

    testPlayer('does not strike a note that began before startAt',
        (tester, rig) async {
      final score = duet();
      await rig.player.play(score, startAt: pointAt(score, 0, at(1, 2)));
      await tester.pump(second * 2);

      expect(
        [for (final note in rig.midi.ons) (note.channel, note.key)],
        [(0, 64), (0, 65)],
      );
    });

    testPlayer('starts at the beginning when startAt is not played',
        (tester, rig) async {
      final score = tune(bars: 2);
      await rig.player.play(
        score,
        startAt: pointAt(score, 0, at(1, 2)),
        options: PlaybackOptions(from: pointAt(score, 1, Moment.zero)),
      );
      expect(rig.seconds, 0);
      expect(rig.position!.point.bar.measure, score.measures[1].id);
      expect(rig.ons, [(0.0, 60)]);
    });

    testPlayer('while playing starts again and drops the old schedule',
        (tester, rig) async {
      await rig.player.play(tune());
      await tester.pump(second * 1.5);
      await rig.player.play(tune());
      await tester.pump(second * 4);

      expect(rig.midi.log, [
        '0.000 load',
        '0.000 program 0 = 0/0',
        '0.000 on 0:60',
        '0.900 off 0:60',
        '1.000 on 0:62',
        '1.500 off 0:62',
        '1.500 program 0 = 0/0',
        '1.500 on 0:60',
        '2.400 off 0:60',
        '2.500 on 0:62',
        '3.400 off 0:62',
        '3.500 on 0:64',
        '4.400 off 0:64',
        '4.500 on 0:65',
        '5.400 off 0:65',
      ]);
      expect(rig.status, PlayerStatus.idle);
    });

    testPlayer('called again while loading, starts only the later call',
        (tester, rig) async {
      final gate = rig.midi.loadGate = Completer();
      final score = tune();
      final first = rig.player.play(score);
      final second =
          rig.player.play(score, startAt: pointAt(score, 0, at(1, 2)));
      gate.complete();
      await first;
      await second;

      expect(rig.midi.log, [
        '0.000 load',
        '0.000 program 0 = 0/0',
        '0.000 on 0:64',
      ]);
      expect(rig.statuses, [PlayerStatus.loading, PlayerStatus.playing]);
    });

    testPlayer('fails when the SoundFont does not load, and loads it again',
        (tester, rig) async {
      rig.midi.loadError = StateError('no such file');
      await expectLater(rig.player.play(tune()), throwsStateError);
      expect(rig.status, PlayerStatus.idle);

      rig.midi.loadError = null;
      await rig.player.play(tune());
      expect(rig.status, PlayerStatus.playing);
      expect(
        rig.midi.log.take(3),
        ['0.000 load', '0.000 load', '0.000 program 0 = 0/0'],
      );
    });

    testPlayer('fails when a program cannot be set, and plays the next time',
        (tester, rig) async {
      rig.midi.programError = StateError('no synthesizer');
      await expectLater(rig.player.play(tune()), throwsStateError);
      expect(rig.status, PlayerStatus.idle);

      rig.midi.programError = null;
      await rig.player.play(tune());
      expect(rig.status, PlayerStatus.playing);
      expect(rig.midi.log, [
        '0.000 load',
        '0.000 program 0 = 0/0',
        '0.000 program 0 = 0/0',
        '0.000 on 0:60',
      ]);
    });

    testPlayer(
        'called again while programs are being set, starts only the later '
        'call and sets its programs last', (tester, rig) async {
      final gate = rig.midi.programGate = Completer();
      final score = tune();
      final earlier = rig.player.play(tune(parts: const [piano, clarinet]));
      await tester.pump();
      final later =
          rig.player.play(score, startAt: pointAt(score, 0, at(1, 2)));
      await tester.pump();
      gate.complete();
      await earlier;
      await later;

      expect(rig.midi.log, [
        '0.000 load',
        '0.000 program 0 = 0/0',
        '0.000 program 1 = 0/71',
        '0.000 program 0 = 0/0',
        '0.000 on 0:64',
      ]);
      expect(rig.statuses, [PlayerStatus.loading, PlayerStatus.playing]);
    });

    testPlayer(
        'fails before anything changes when its range is not in the score',
        (tester, rig) async {
      const outside = PlaybackOptions(
        from: ScorePoint(MeasureId(999), Moment.zero),
      );
      await expectLater(
        rig.player.play(tune(), options: outside),
        throwsArgumentError,
      );
      expect(rig.statuses, isEmpty);

      await rig.player.play(tune());
      await tester.pump(half);
      await expectLater(
        rig.player.play(tune(), options: outside),
        throwsArgumentError,
      );
      await tester.pump(second);
      expect(rig.ons, [(0.0, 60), (1.0, 62)]);
      expect(rig.statuses, [PlayerStatus.loading, PlayerStatus.playing]);
    });

    testPlayer('a range of no length ends at once, also when it loops',
        (tester, rig) async {
      final score = tune();
      final point = pointAt(score, 0, at(1, 2));
      await rig.player.play(
        score,
        loop: true,
        options: PlaybackOptions(from: point, to: point),
      );

      expect(
        rig.statuses,
        [PlayerStatus.loading, PlayerStatus.playing, PlayerStatus.idle],
      );
      expect(rig.position, isNull);
      expect(rig.midi.ons, isEmpty);
    });

    testPlayer(
        'a listener of the position that stops playback leaves the player '
        'idle', (tester, rig) async {
      rig.player.position.addListener(() {
        if (rig.position != null) {
          rig.player.stop();
        }
      });
      await rig.player.play(tune());

      expect(rig.status, PlayerStatus.idle);
      expect(rig.position, isNull);
      expect(rig.midi.held, isEmpty);
      await tester.pump(second * 4);
      expect(rig.midi.log.last, '0.000 all off');
    });

    testPlayer(
        'a listener of the position can play the next score when one ends',
        (tester, rig) async {
      final next = [tune()];
      rig.player.position.addListener(() {
        if (rig.position == null && next.isNotEmpty) {
          unawaited(rig.player.play(next.removeLast()));
        }
      });
      await rig.player.play(tune());
      await tester.pump(second * 5);

      expect(rig.statuses, [
        PlayerStatus.loading,
        PlayerStatus.playing,
        PlayerStatus.idle,
        PlayerStatus.loading,
        PlayerStatus.playing,
      ]);
      expect(rig.ons.last, (5.0, 62));
    });

    testPlayer('sends nothing for a muted part', (tester, rig) async {
      final score = duet();
      expect(
        {
          for (final note
              in PlaybackCompiler().compile(score).notesBetween(0, 4))
            note.channel,
        },
        {0, 1},
      );

      await rig.player.play(
        score,
        options: PlaybackOptions(muted: {score.parts[1].id}),
      );
      await tester.pump(second * 4);
      expect({for (final note in rig.midi.ons) note.channel}, {0});
      expect(
        rig.midi.log.where((call) => call.contains('program')),
        ['0.000 program 0 = 0/0'],
      );
    });

    testPlayer('plays a repeat twice and says which pass it is on',
        (tester, rig) async {
      final score = changeBar(
        tune(bars: 2),
        0,
        (column) => column.copyWith(repeatEnd: () => const RepeatEnd()),
      );
      (MeasureId, int, double) where() {
        final PlaybackPoint(:bar, :offset) = rig.position!.point;
        return (bar.measure, bar.pass, offset);
      }

      await rig.player.play(score);
      await tester.pump(half);
      expect(where(), (score.measures[0].id, 1, 0.125));
      await tester.pump(second * 4);
      expect(where(), (score.measures[0].id, 2, 0.125));
      await tester.pump(second * 4);
      expect(where(), (score.measures[1].id, 1, 0.125));
      await tester.pump(second * 4);

      expect(
        [for (final (_, key) in rig.ons) key],
        [60, 62, 64, 65, 60, 62, 64, 65, 60, 62, 64, 65],
      );
      expect(rig.status, PlayerStatus.idle);
    });

    testPlayer('publishes the events that sound at its position',
        (tester, rig) async {
      List<int> sounding() => [
            for (final ref in rig.position!.sounding) ref.id.value,
          ];

      await rig.player.play(duet());
      expect(sounding(), [11, 1]);
      rig.player.tempoScale = 0.5;
      await tester.pump(second * 3);
      expect(sounding(), [12, 1]);
      await tester.pump(second * 0.9);
      expect(sounding(), [12, 1], reason: 'for its written length');
      rig.player.pause();
      expect(sounding(), [12, 1]);
    });

    testPlayer('loops a range until stop, releasing what the end cuts short',
        (tester, rig) async {
      final score = tune(bars: 2);
      await rig.player.play(
        score,
        loop: true,
        options: PlaybackOptions(
          from: pointAt(score, 0, at(1, 2)),
          to: pointAt(score, 1, at(3, 8)),
        ),
      );
      await tester.pump(second * 4);

      expect(rig.midi.log.skip(2), [
        '0.000 on 0:64',
        '0.900 off 0:64',
        '1.000 on 0:65',
        '1.900 off 0:65',
        '2.000 on 0:60',
        '2.900 off 0:60',
        '3.000 on 0:62',
        '3.500 off 0:62',
        '3.500 on 0:64',
      ]);
      expect(rig.seconds, closeTo(0.5, 1e-9));
      expect(rig.status, PlayerStatus.playing);

      await tester.pump(second * 3.5);
      expect(rig.ons.last, (7.0, 64));
      rig.player.stop();
      expect(rig.status, PlayerStatus.idle);
    });

    testPlayer('keeps the period of a loop when its wrap comes late',
        (tester, rig) async {
      await rig.player.play(tune(), loop: true);
      await tester.pump(second * 3.5);
      rig.time.stalled = second;
      await tester.pump(second);

      expect(rig.ons.skip(4), [(5.0, 62)]);
      expect(rig.seconds, closeTo(1.5, 1e-9));
    });

    testPlayer('keeps the position on a frame that comes before a late wrap',
        (tester, rig) async {
      await rig.player.play(tune(), loop: true);
      await tester.pump(second * 3.5);
      rig.time.stalled = second;
      await tester.pump();

      expect(rig.position, isNotNull, reason: 'the playhead does not blink');
      expect(rig.seconds, closeTo(3.5, 1e-9));
    });

    testPlayer('keeps the period of a loop when its wrap comes early',
        (tester, rig) async {
      await rig.player.play(tune(), loop: true);
      await tester.pump(second * 3.95);
      rig.time.stalled = -const Duration(milliseconds: 1);
      await tester.pump(second * 1.1);

      expect(rig.ons.skip(4), [(3.999, 60), (5.0, 62)]);
    });

    testPlayer('releases what the end of a range cuts short',
        (tester, rig) async {
      final score = tune();
      await rig.player.play(
        score,
        options: PlaybackOptions(to: pointAt(score, 0, at(3, 8))),
      );
      await tester.pump(second * 4);

      expect(rig.midi.log.skip(2), [
        '0.000 on 0:60',
        '0.900 off 0:60',
        '1.000 on 0:62',
        '1.500 off 0:62',
      ]);
      expect(rig.status, PlayerStatus.idle);
    });

    testPlayer(
        'releases a key before it strikes it again, and holds it for the '
        'longer note', (tester, rig) async {
      var score = fill(atSixty(blankScore(bars: 1)), 0, [
        chordOf(1, 'C4', value: NoteValue.whole),
      ]);
      score = fill(
        score,
        0,
        [
          rest(2, NoteValue.quarter),
          chordOf(3, 'C4'),
          rest(4, NoteValue.half),
        ],
        slot: VoiceSlot.two,
      );
      await rig.player.play(score);
      await tester.pump(second * 4);

      expect(rig.midi.log.skip(2), [
        '0.000 on 0:60',
        '1.000 off 0:60',
        '1.000 on 0:60',
        '3.600 off 0:60',
      ]);
    });

    testPlayer(
        'does not send a note that began and ended while the isolate was busy',
        (tester, rig) async {
      await rig.player.play(tune());
      await tester.pump(half);
      rig.time.stalled = second * 1.5;
      await tester.pump(second * 2);

      expect(rig.midi.log.skip(2), [
        '0.000 on 0:60',
        '2.400 off 0:60',
        '2.400 on 0:64',
        '2.900 off 0:64',
        '3.000 on 0:65',
        '3.900 off 0:65',
      ]);
      expect(rig.status, PlayerStatus.idle);
    });
  });

  group('tempoScale', () {
    testPlayer('set while idle or paused applies when playback runs',
        (tester, rig) async {
      rig.player.tempoScale = 2;
      await rig.player.play(tune());
      await tester.pump(second * 0.75);
      rig.player.pause();
      rig.player.tempoScale = 1;
      await tester.pump(second);
      rig.player.resume();
      await tester.pump(second);

      expect(rig.ons, [(0.0, 60), (0.5, 62), (2.25, 64)]);
      expect(rig.player.tempoScale, 1);
    });

    testPlayer(
        'at a speed that puts notes between two microseconds, sends each '
        'once and ends', (tester, rig) async {
      rig.player.tempoScale = 3;
      await rig.player.play(tune());
      await tester.pump(second * 2);

      expect(
        rig.ons,
        [(0.0, 60), (0.333333, 62), (0.666667, 64), (1.0, 65)],
      );
      expect(rig.status, PlayerStatus.idle);
    });

    testPlayer('refuses a speed that is not positive and finite',
        (tester, rig) async {
      for (final speed in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => rig.player.tempoScale = speed, throwsArgumentError);
      }
      expect(rig.player.tempoScale, 1);
    });
  });

  group('pause, stop and dispose', () {
    testPlayer(
        'pause releases what sounds, and resume does not strike it again',
        (tester, rig) async {
      await rig.player.play(tune());
      await tester.pump(second * 1.5);
      rig.player.pause();
      expect(rig.status, PlayerStatus.paused);
      expect(rig.midi.log.last, '1.500 off 0:62');
      expect(rig.midi.held, isEmpty);

      await tester.pump(second * 10);
      expect(rig.midi.log.last, '1.500 off 0:62');

      rig.player.resume();
      expect(rig.status, PlayerStatus.playing);
      await tester.pump(second * 2.5);
      expect(rig.ons, [(0.0, 60), (1.0, 62), (12.0, 64), (13.0, 65)]);
      expect(rig.status, PlayerStatus.idle);
    });

    testPlayer('pause publishes the position it holds', (tester, rig) async {
      await rig.player.play(tune());
      await tester.pump(second);
      rig.time.stalled = half;
      rig.player.pause();

      expect(rig.seconds, closeTo(1.5, 1e-9));
    });

    testPlayer(
        'a listener of the position that stops playback on pause leaves the '
        'player idle', (tester, rig) async {
      await rig.player.play(tune());
      await tester.pump(half);
      rig.player.position.addListener(rig.player.stop);
      rig.player.pause();

      expect(rig.status, PlayerStatus.idle);
      expect(rig.position, isNull);
    });

    for (final trigger in [PlayerStatus.playing, PlayerStatus.paused]) {
      testPlayer(
          'a listener of the status that stops playback when it is '
          '${trigger.name} leaves the player idle', (tester, rig) async {
        rig.player.status.addListener(() {
          if (rig.status == trigger) {
            rig.player.stop();
          }
        });
        await rig.player.play(tune());
        await tester.pump(half);
        rig.player.pause();
        await tester.pump(second * 4);

        expect(rig.status, PlayerStatus.idle);
        expect(rig.position, isNull);
        expect(rig.midi.held, isEmpty);
        expect(rig.midi.log.last, endsWith('all off'));
      });
    }

    testPlayer(
        'a listener of the status that pauses whenever playback runs keeps '
        'it paused, with no note sent', (tester, rig) async {
      rig.player.status.addListener(() {
        if (rig.status == PlayerStatus.playing) {
          rig.player.pause();
        }
      });
      await rig.player.play(tune());
      expect(rig.status, PlayerStatus.paused);

      rig.player.resume();
      await tester.pump(second * 5);

      expect(rig.status, PlayerStatus.paused);
      expect(rig.seconds, 0);
      expect(rig.midi.ons, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testPlayer(
        'a listener of the status that resumes when playback pauses lets it '
        'play on to the end', (tester, rig) async {
      rig.player.status.addListener(() {
        if (rig.status == PlayerStatus.paused) {
          rig.player.resume();
        }
      });
      await rig.player.play(tune());
      await tester.pump(second * 1.5);
      rig.player.pause();
      expect(rig.status, PlayerStatus.playing);
      await tester.pump(second * 3);

      expect(rig.ons, [(0.0, 60), (1.0, 62), (2.0, 64), (3.0, 65)]);
      expect(rig.midi.held, isEmpty);
      expect(rig.status, PlayerStatus.idle);
    });

    testPlayer('asks for frames only while it plays', (tester, rig) async {
      int tickers() => tester.binding.transientCallbackCount;

      expect(tickers(), 0);
      await rig.player.play(tune());
      expect(tickers(), 1);
      rig.player.pause();
      expect(tickers(), 0);
      rig.player.resume();
      expect(tickers(), 1);
      await tester.pump(second * 4);
      expect(tickers(), 0);
    });

    testPlayer('pause does nothing unless playing, and resume unless paused',
        (tester, rig) async {
      rig.player
        ..pause()
        ..resume();
      expect(rig.statuses, isEmpty);

      await rig.player.play(tune());
      await tester.pump(half);
      rig.player.resume();
      await tester.pump(second);
      expect(rig.ons, [(0.0, 60), (1.0, 62)]);

      rig.player.pause();
      var published = 0;
      rig.player.position.addListener(() => published++);
      rig.player.pause();
      expect(published, 0);
      expect(rig.midi.log.where((call) => call.contains('off')), [
        '0.900 off 0:60',
        '1.500 off 0:62',
      ]);
      expect(
        rig.statuses,
        [PlayerStatus.loading, PlayerStatus.playing, PlayerStatus.paused],
      );
    });

    testPlayer('stop releases what sounds and clears the position',
        (tester, rig) async {
      await rig.player.play(tune());
      await tester.pump(second * 1.5);
      rig.player.stop();

      expect(rig.midi.log.skip(5), ['1.500 off 0:62', '1.500 all off']);
      expect(rig.position, isNull);
      expect(rig.status, PlayerStatus.idle);

      await tester.pump(second * 10);
      expect(rig.midi.log.last, '1.500 all off');
    });

    testPlayer('stop while loading leaves the player idle',
        (tester, rig) async {
      final gate = rig.midi.loadGate = Completer();
      final started = rig.player.play(tune());
      rig.player.stop();
      gate.complete();
      await started;
      await tester.pump(second * 4);

      expect(rig.statuses, [PlayerStatus.loading, PlayerStatus.idle]);
      expect(rig.midi.ons, isEmpty);
    });

    testPlayer('a call that stop withdrew does not fail when its programs do',
        (tester, rig) async {
      final gate = rig.midi.programGate = Completer();
      rig.midi.programError = StateError('no synthesizer');
      final started = rig.player.play(tune());
      await tester.pump();
      rig.player.stop();
      gate.complete();
      await started;

      expect(rig.statuses, [PlayerStatus.loading, PlayerStatus.idle]);
    });

    testWidgets('dispose releases what sounds and sends nothing after',
        (tester) async {
      final rig = Rig(tester);
      await rig.player.play(tune());
      await tester.pump(second * 1.5);
      rig.player.dispose();

      expect(rig.midi.log.skip(5), ['1.500 off 0:62', '1.500 dispose']);
      await tester.pump(second * 10);
      expect(rig.midi.log.last, '1.500 dispose');
    });

    testWidgets('dispose while loading sends nothing', (tester) async {
      final rig = Rig(tester);
      final gate = rig.midi.loadGate = Completer();
      final started = rig.player.play(tune());
      rig.player.dispose();
      gate.complete();
      await started;
      await tester.pump(second * 4);

      expect(rig.midi.log, ['0.000 load', '0.000 dispose']);
    });
  });
}
