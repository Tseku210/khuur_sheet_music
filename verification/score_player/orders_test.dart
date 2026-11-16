/// Every order of up to [depth] steps that a `ScorePlayer` can meet,
/// replayed on the real player, checked against its promises.
///
/// Run it with
/// `flutter test verification/score_player/orders_test.dart`, and
/// `--dart-define=PLAYER_ORDERS_DEPTH=n` for another bound. The project
/// skill `.claude/skills/score-player-orders/SKILL.md` says what it covers.
library;

import 'package:flutter_test/flutter_test.dart';

import 'contract_output.dart';
import 'world.dart';

const depth = int.fromEnvironment('PLAYER_ORDERS_DEPTH', defaultValue: 7);

/// With `--dart-define=PLAYER_ORDERS_NO_MERGE=true`, two paths that reach
/// the same `World.key` are both explored. Slower, and it rules out that
/// the key merged two states that differ.
const noMerge = bool.fromEnvironment('PLAYER_ORDERS_NO_MERGE');

void main() {
  testWidgets(
    'every order of up to $depth steps keeps the promises of ScorePlayer',
    (tester) async {
      final watch = Stopwatch()..start();
      final found = <String, _Counterexample>{};
      final seen = <String>{};
      final reached = <String>{};
      var frontier = <List<Step>>[[]];
      var replays = 0;

      /// Replays [path] on a fresh player and returns it, checked after
      /// every step. Stops at the first broken promise.
      Future<World> replay(List<Step> path) async {
        replays++;
        final world = World(tester);
        for (final step in path) {
          await world.take(step);
          world.checkSettled();
          if (world.violations.isNotEmpty) {
            break;
          }
        }
        return world;
      }

      Future<void> note(List<Step> path, World world) async {
        await world.close();
        reached.addAll(world.reached);
        for (final violation in world.violations) {
          final known = found[violation.property];
          if (known == null || known.path.length > path.length) {
            found[violation.property] = _Counterexample(
              path,
              violation,
              world.output.log,
            );
          }
        }
      }

      {
        final world = await replay(const []);
        seen.add(world.key);
        await note(const [], world);
      }
      for (var level = 1; level <= depth && frontier.isNotEmpty; level++) {
        final next = <List<Step>>[];
        for (final path in frontier) {
          final here = await replay(path);
          final steps = Step.values.where(here.canTake).toList();
          await here.close();
          for (final step in steps) {
            final longer = [...path, step];
            final world = await replay(longer);
            final broken = world.violations.isNotEmpty;
            final key = world.key;
            await note(longer, world);
            final fresh = seen.add(key) || noMerge;
            if (!broken && step != Step.dispose && fresh) {
              next.add(longer);
            }
          }
        }
        frontier = next;
      }

      final summary =
          '${seen.length} states to depth $depth, $replays replays, '
          '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';
      print(summary);
      // A broken promise goes first: the states past it are not explored,
      // so it can also leave cases unreached.
      expect(
        found,
        isEmpty,
        reason: [
          summary,
          for (final counterexample in found.values) counterexample.story,
        ].join('\n\n'),
      );
      expect(
        mustReach.difference(reached),
        isEmpty,
        reason:
            '$summary\nThe search did not reach these, so a pass would '
            'not cover them. Raise PLAYER_ORDERS_DEPTH or add the steps that '
            'reach them.',
      );
    },
    timeout: Timeout.none,
  );
}

/// The shortest path the search found to a broken promise.
final class _Counterexample {
  _Counterexample(this.path, this.violation, List<String> log)
    : log = List.of(log);

  final List<Step> path;
  final Violation violation;
  final List<String> log;

  String get story => [
    'BROKEN ${violation.property}: ${violation.detail}',
    'after ${path.length} steps:',
    for (final (i, step) in path.indexed)
      '  ${i + 1}. ${step.words} (${step.name})',
    'the output received: ${log.join(', ')}',
  ].join('\n');
}
