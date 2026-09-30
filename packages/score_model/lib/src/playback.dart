/// Playback compilation (access pattern 6).
///
/// The score is compiled bar by bar. A bar's notes are compiled once into a
/// fragment in whole-note time and cached on the column object itself, so a
/// one-note edit recompiles one fragment. The cheap part, which runs on
/// every compile, folds tempo and dynamics over the bars and unrolls the
/// repeats into a play order. Seconds are computed only when the player
/// asks for a window of notes.
library;

import 'measure.dart';
import 'refs.dart';
import 'score.dart';
import 'time.dart';

/// Long-lived. Keep one per composer screen so its fragment cache survives
/// across edits.
final class PlaybackCompiler {
  PlaybackCompiler();

  /// Fragments keyed by column identity. A column that an edit did not touch
  /// is the same object in the new score, so its fragment is reused. Entries
  /// die with their columns.
  // Read by `compile` once its body is written.
  // ignore: unused_field
  final Expando<List<_Fragment>> _fragments = Expando('playback fragments');

  PlaybackScript compile(
    Score score, [
    PlaybackOptions options = const PlaybackOptions(),
  ]) {
    // TODO:
    // 1. Play order. With a range (options.from/to), the bars of the range
    //    in notated order, once. Otherwise _playOrder(score.measures).
    // 2. One fold over the play order, reading only bar-level facts and
    //    staff directions: tempo in effect (TempoMarks, including mid-bar
    //    ones), dynamic level per staff (DynamicMarks), hairpin segments
    //    from score.spanners, fermata holds. Produces, per played bar, its
    //    start in seconds, its internal tempo map, and its entry state.
    // 3. For each played bar, fetch the fragment for (column, entry state,
    //    next notated column if a tie leaves the bar) from _fragments or
    //    compile it with _compileBar.
    // 4. Channels: parts in order get channels 0..15 skipping 9; percussion
    //    parts get 9; muted parts are left out.
    throw UnimplementedError();
  }

  /// Compiles one bar into notes in whole-note time relative to the bar.
  // TODO: for each visible or hidden staff (hidden parts still play), each
  // voice, each TimedEvent:
  //   - skip heads that a tie from the previous event lands on;
  //   - for heads with `tie`, follow the chain (into the next notated bar if
  //     needed) and sum sounding lengths: one attack, merged duration;
  //   - velocity = entry dynamic, updated by in-bar DynamicMarks, shaped by
  //     hairpin interpolation, +accent/marcato, sf/sfz/fp for one event;
  //   - length shaping: staccato 1/2, staccatissimo 1/4, tenuto full,
  //     default 0.9 of the notated length; fermata holds (from step 2);
  //   - grace chords: acciaccatura just before the beat, appoggiatura takes
  //     half the principal's length; tremolo strokes and the chord's
  //     ornament (trill, mordent, turn) expand to notes; percussion heads
  //     map through Instrument.drums;
  //   - key and cents from Pitch.midiKey / Pitch.cents (pitch is already
  //     concert; 8va lines and transposition are display-only).
  // ignore: unused_element
  List<_Fragment> _compileBar(Score score, MeasureColumn column) =>
      throw UnimplementedError();
}

/// Unrolls repeats, voltas and navigation into (bar index, pass) pairs.
///
/// Rules: a start repeat marks where an end repeat returns to (the score
/// start if none). A bar under a volta plays only on the passes its endings
/// list. A [Jump] is taken once, after the repeats before it are done;
/// after a jump, repeats are not taken again, [Fine] stops, and [ToCoda]
/// continues at the [Coda] bar. A loop guard stops at 64 × bar count.
// TODO: state machine over (index, pass, jumped, repeatStart) as described.
// ignore: unused_element
List<({int index, int pass})> _playOrder(List<MeasureColumn> measures) =>
    throw UnimplementedError();

final class PlaybackOptions {
  const PlaybackOptions({this.from, this.to, this.muted = const {}});

  /// Play only `[from, to)` in notated order, ignoring repeats. The player
  /// loops the returned script when the user asked for a loop.
  final ScorePoint? from;
  final ScorePoint? to;

  final Set<PartId> muted;
}

/// A compiled score. Immutable; recompile after an edit (cheap, see the
/// library doc).
final class PlaybackScript {
  const PlaybackScript._({
    required this.totalSeconds,
    required this.channels,
    required this.bars,
  });

  final double totalSeconds;

  /// Program to load on each channel before playing.
  final List<ChannelSetup> channels;

  /// The unrolled play order with timings. The UI can show "2nd time".
  final List<PlayedBar> bars;

  /// Notes whose start falls in `[from, to)` seconds, sorted by start. The
  /// player pulls windows ahead of a monotonic clock.
  Iterable<PlaybackNote> notesBetween(double from, double to) {
    // TODO: binary search `bars` for the first bar ending after `from`;
    // convert that bar's fragment notes from whole-note time to seconds with
    // the bar's tempo map; continue until a bar starts at or after `to`.
    throw UnimplementedError();
  }

  /// Events sounding at [seconds], one per voice, for highlighting.
  List<EventRef> sourcesAt(double seconds) => throw UnimplementedError();

  /// When [point] is first reached, for starting playback at the cursor.
  /// Null if the point is not in the played range.
  double? secondsAt(ScorePoint point) => throw UnimplementedError();
}

final class PlaybackNote {
  const PlaybackNote({
    required this.start,
    required this.duration,
    required this.key,
    required this.velocity,
    required this.channel,
    required this.source,
    this.cents = 0,
  });

  /// Seconds from the script start.
  final double start;
  final double duration;

  /// MIDI key 0–127.
  final int key;

  /// 0 or 50 (quarter tones). The player applies pitch bend.
  final int cents;

  final int velocity;
  final int channel;

  /// The event that produced this note. A tie chain reports its first
  /// event; a grace note reports the grace chord's id.
  final EventRef source;
}

final class ChannelSetup {
  const ChannelSetup({
    required this.channel,
    required this.part,
    required this.program,
    this.bank = 0,
  });

  final int channel;
  final PartId part;
  final int program;
  final int bank;
}

final class PlayedBar {
  const PlayedBar({
    required this.measure,
    required this.pass,
    required this.start,
    required this.end,
  });

  final MeasureId measure;

  /// 1 for the first time through.
  final int pass;
  final double start;
  final double end;
}

/// One note of a compiled bar, in whole-note time relative to the bar.
final class _Fragment {
  const _Fragment({
    required this.onset,
    required this.length,
    required this.key,
    required this.cents,
    required this.velocity,
    required this.part,
    required this.source,
  });

  final Moment onset;

  /// May reach past the bar end when a tie chain continues.
  final Length length;
  final int key;
  final int cents;
  final int velocity;
  final PartId part;
  final EventRef source;
}
