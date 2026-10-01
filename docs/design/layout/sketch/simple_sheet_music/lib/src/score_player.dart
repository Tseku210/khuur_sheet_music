import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';

import 'sound_font.dart';

/// Plays a score over MIDI and reports where it is, for the sheet to show.
///
/// Replaces `MidiPlayer`, `MidiPlaybackMixin` and the `SimpleSheetMusicState`
/// play methods. It owns the `PlaybackCompiler` (whose fragment cache makes
/// recompiling after an edit cheap), the SoundFont, the MIDI output through
/// `flutter_midi_pro` (Android, iOS and macOS), and one script clock that
/// two readers share.
///
/// The clock maps wall time to script seconds from one anchor
/// ([_ScriptClock]). A one-shot timer reads it to sleep until the next note
/// of `PlaybackScript.notesBetween` and sends that note when it wakes. A
/// ticker reads it once per frame to publish [position]. Neither keeps time
/// of its own, so the sound and the playhead cannot drift apart.
///
/// The timer does not wait for a frame to be drawn, so sound goes on when
/// nothing repaints. It does run on the UI isolate, as the plugin's
/// `playNote` takes no timestamp. A note is therefore late by as long as
/// the isolate is busy when the note is due, which is at most one build or
/// one layout.
///
/// The timer also owns the end of playback and the wrap of a loop. A ticker
/// is muted while the app's tickers are off, and sound must still stop at
/// the end then. The ticker only publishes.
///
/// Whatever changes the mapping moves the anchor to the present first.
/// That is a new [tempoScale], [pause], [resume] and the wrap of a loop. So
/// the script second is continuous across the change, and the note timer is
/// cancelled and set again from the new anchor.
final class ScorePlayer {
  ScorePlayer({required this.soundFont, required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_tick);
  }

  final SoundFont soundFont;
  late final Ticker _ticker;

  final ValueNotifier<PlayerStatus> _status = ValueNotifier(PlayerStatus.idle);
  final ValueNotifier<PlaybackPosition?> _position = ValueNotifier(null);

  /// Where playback is, or null when stopped. Pass it to
  /// `SheetView.playback`.
  ValueListenable<PlaybackPosition?> get position => _position;

  /// Whether the player is loading, playing or paused. Returns to
  /// [PlayerStatus.idle] when the score ends, so an app's play button needs
  /// no state of its own.
  ValueListenable<PlayerStatus> get status => _status;

  /// Speed relative to the written tempo: 1 as written, 0.5 half speed.
  /// Takes effect immediately, also while playing. The position does not
  /// jump, and the next note sounds at the new speed.
  double get tempoScale => throw UnimplementedError();
  set tempoScale(double value) {
    // TODO: re-anchor the clock at now with the new scale, then cancel the
    // note timer and set it again.
    throw UnimplementedError();
  }

  /// Compiles [score] and plays it.
  ///
  /// Starts at [startAt] (with repeats, from `secondsAt`), else at the
  /// beginning. [options] limits playback to a range or mutes parts; with
  /// [loop] the range repeats until [stop]. Loads the SoundFont on first
  /// use, with [status] at [PlayerStatus.loading] meanwhile.
  Future<void> play(
    Score score, {
    ScorePoint? startAt,
    PlaybackOptions options = const PlaybackOptions(),
    bool loop = false,
  }) {
    // TODO: compile with the long-lived PlaybackCompiler, load channels,
    // anchor the clock at script.secondsAt(startAt) ?? 0, set the note
    // timer, then _ticker.start().
    throw UnimplementedError();
  }

  void _tick(Duration elapsed) {
    // TODO: seconds = the clock's reading now. script.pointAt(seconds) (B1)
    // is null at and past totalSeconds, and then nothing is published.
    // Otherwise set _position to PlaybackPosition(seconds, that point,
    // script.sourcesAt(seconds)). The note timer, not this, ends playback
    // at totalSeconds (stop the ticker, clear the position, go idle) or
    // re-anchors at the loop's start.
  }

  void pause() => throw UnimplementedError();

  void resume() => throw UnimplementedError();

  /// Stops sound, clears [position] and goes idle.
  void stop() => throw UnimplementedError();

  void dispose() {
    _ticker.dispose();
    _status.dispose();
    _position.dispose();
  }
}

/// Script seconds as a function of wall time, from one anchor.
///
/// `secondsAt(wall) = seconds + scale * (wall - wall0)`. A paused clock has
/// scale 0. [wallAt] is the inverse the note timer sleeps by.
// The sketch declares the shape. The player holds one and replaces it at
// every change of speed.
// ignore: unused_element
final class _ScriptClock {
  const _ScriptClock({
    required this.wall,
    required this.seconds,
    required this.scale,
  });

  /// The stopwatch reading at the anchor.
  final Duration wall;

  /// The script second at the anchor.
  final double seconds;

  /// Script seconds per wall second from the anchor on.
  final double scale;

  double secondsAt(Duration now) =>
      seconds + scale * (now - wall).inMicroseconds / 1e6;

  /// When script second [at] is reached. Only for a running clock.
  Duration wallAt(double at) =>
      wall + Duration(microseconds: ((at - seconds) / scale * 1e6).round());

  /// The same script second at [now], running at [scale] from there.
  _ScriptClock rescaled(Duration now, double scale) =>
      _ScriptClock(wall: now, seconds: secondsAt(now), scale: scale);
}

enum PlayerStatus { idle, loading, playing, paused }

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

  /// The bar, pass and continuous offset, for the playhead (B1).
  final PlaybackPoint point;

  /// The events sounding now, one per voice, for the highlight. May include
  /// events on hidden staves; the sheet skips any it did not draw.
  final List<EventRef> sounding;
}
