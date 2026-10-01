/// Stand-ins for the score_model additions this design proposes (B1, B2b
/// and B2c), so the sketch type-checks against their exact signatures. Each one moves into
/// score_model as a member of the named type, and this file is deleted
/// when they land. RATIONALE "Model additions" gives the reasons.
library;

import 'package:score_model/score_model.dart';

/// B1. Where playback is at a moment of the script.
final class PlaybackPoint {
  const PlaybackPoint({required this.bar, required this.offset});

  /// The bar being played, with its pass.
  final PlayedBar bar;

  /// How far into the bar, in whole notes. A double, not a Moment, because
  /// a playhead moves continuously between onsets.
  final double offset;
}

extension PlaybackScriptPointAt on PlaybackScript {
  /// B1, a member of PlaybackScript. The inverse of `secondsAt`, over every
  /// pass. Null outside `[0, totalSeconds)`.
  ///
  /// Finds the played bar by binary search on `_timeline`, then inverts the
  /// bar's `_Clock`. Within a `_ClockStep`, a steady pace gives
  /// `wholes = seconds * rate`, a moving pace gives
  /// `wholes = rate * (exp(slope * seconds) - 1) / slope`, and a fermata's
  /// stretch divides the seconds first. The result is offset by `_Bar.from`
  /// so range playback reports the true position.
  PlaybackPoint? pointAt(double seconds) => throw UnimplementedError();
}

extension ScoreBarNumbers on Score {
  /// B2c, a member of Score. The printed number of bar [id]. A first bar
  /// shorter than its meter is a pickup and is numbered 0, as the exporter
  /// numbers it.
  int barNumberOf(MeasureId id) => throw UnimplementedError();
}

/// B2b. How an event joins each beam level, by the rule MusicXML export
/// uses today in the private `_beams`.
enum BeamJoin { begin, continued, end, forwardHook, backwardHook }

extension BeamGroupJoins on BeamGroup {
  /// B2b, a field of BeamGroup filled by the model. It holds, for each of
  /// [events], the join at every beam level, level 1 first.
  List<List<BeamJoin>> get joins => throw UnimplementedError();
}

extension JumpLabel on Jump {
  /// B2c, a member of Jump. It is [text], or the default rendering the exporter
  /// writes today ("D.C.", "D.S.", plus " al Fine" or " al Coda").
  String get label => throw UnimplementedError();
}
