import 'package:score_model/score_model.dart';

import 'drawable.dart';
import 'system_layout.dart';

/// What a tap on the sheet means in the score.
///
/// Every field is a model value, so an app can run an edit straight from a
/// hit. `score.toneForStaffStep(hit.staff, hit.at, hit.staffStep)` gives
/// the tone, and `VoicePoint(staff: hit.staff, voice: hit.voice, at:
/// hit.at)` the place. When [target] is a note or an event, [staff],
/// [voice] and [at] are its event's, so they agree with it wherever its
/// ink lies. Otherwise [at] is snapped in [voice].
final class SheetHit {
  const SheetHit({
    required this.staff,
    required this.voice,
    required this.at,
    required this.staffStep,
    this.target,
  });

  /// The staff of [target]'s event, else the visible staff nearest the tap.
  /// So [staffStep] is the step of a tapped head.
  final StaffId staff;

  /// The voice of [target]'s event, else the voice the hit test was asked
  /// about. So a tap on a voice-two note selects in voice two without the
  /// app looking it up.
  final VoiceSlot voice;

  /// The onset of [target]'s event, else a start the model allows for an
  /// entry in [voice], by [snapTime]. Never the end of a bar. Whether a
  /// given note value fits there is the edit's question. Inside a tuplet
  /// `EnterNote` refuses a value that runs past the tuplet's end, at this
  /// point as at any other.
  final ScorePoint at;

  /// In the convention of `Score.toneForStaffStep`: 0 is the bottom line of
  /// a five-line staff, 1 the space above it. Steps above and below the
  /// staff continue the count, so ledger positions are reachable. A
  /// one-line staff uses the same steps, with its line at step 4.
  final int staffStep;

  /// The note, event or spanner drawn within a finger's reach of the tap,
  /// if any. A notehead gives a NoteRef, a rest, stem or flag gives an
  /// EventRef, and a grace head gives its principal's EventRef. An element
  /// wins over a spanner drawn at the same place. A slur or a tie is hit
  /// near its line only, so a tap on the staff under a slur's arc has no
  /// target and enters a note.
  final Owner? target;
}

/// One voice of one bar in time. `onsets` holds its events' onsets in time
/// order. Grace chords ride on their principal and are not in it.
typedef VoiceTimes = ({List<Moment> onsets, List<TupletSpan> tuplets});

/// A tuplet in sounding time. It sounds from `onset` for `duration`, and
/// its members are written over `written`, which is
/// `unit.length * ratio.actual`.
typedef TupletSpan = ({
  Moment onset,
  Length duration,
  Length written,
  int depth,
});

/// [voice] of [staff] in [view], or null when the bar has no such voice.
///
/// Built when a tap asks, from the score, so laying out a bar does not pay
/// for it.
VoiceTimes? voiceTimes(MeasureView view, StaffId staff, VoiceSlot voice) {
  for (final staffView in view.staves) {
    if (staffView.source.staff != staff) {
      continue;
    }
    for (final voiceView in staffView.voices) {
      if (voiceView.slot == voice) {
        return (
          onsets: [for (final timed in voiceView.events) timed.onset],
          tuplets: [
            for (final tuplet in voiceView.tuplets)
              (
                onset: tuplet.onset,
                duration: tuplet.duration,
                written:
                    tuplet.tuplet.unit.length *
                    Fraction(tuplet.tuplet.ratio.actual),
                depth: tuplet.depth,
              ),
          ],
        );
      }
    }
  }
  return null;
}

/// The moments of a bar at which the model allows a note to start in a
/// voice, on [grid], in time order.
///
/// The model takes a start that lies a whole number of 128ths into its bar
/// or, inside a tuplet, into the tuplet's written time (`startProblem`,
/// applied per tuplet by the lane writer). So outside every tuplet the
/// points are the multiples of [grid] in the bar. Inside a tuplet they are
/// the multiples of [grid] in its written time, mapped to sounding time by
/// `duration / written`. A triplet of eighths on a sixteenth grid gives
/// six points, a twenty-fourth of a whole note apart. Where a tuplet holds
/// a deeper one, the deeper one's points replace its own over that
/// stretch.
///
/// [voice] is null for a voice the bar does not have, which has no tuplet.
List<Moment> entryPoints(
  Length barLength,
  VoiceTimes? voice,
  DurationBase grid,
) {
  final tuplets = voice?.tuplets ?? const <TupletSpan>[];
  final spans = <TupletSpan>[
    (onset: Moment.zero, duration: barLength, written: barLength, depth: -1),
    ...tuplets,
  ];
  return [
    for (final span in spans)
      for (var at = Length.zero; at < span.written; at += grid.length)
        if (span.onset + at * (span.duration / span.written) case final point
            when !tuplets.any(
              (inner) =>
                  inner.depth == span.depth + 1 &&
                  inner.onset <= point &&
                  point < inner.onset + inner.duration,
            ))
          point,
  ]..sort((a, b) => a.compareTo(b));
}

/// The moment a tap at [x] in [bar] means for entry in [voice].
///
/// An onset of the voice within one staff space of the tap wins, so a tap
/// above or below a note, where a chord tone goes, lands on that note
/// whatever the grid. Otherwise the nearest of [entryPoints] wins, so a tap
/// between the notes of a triplet lands on a point the triplet can take.
Moment snapTime(PlacedBar bar, VoiceTimes? voice, double x, DurationBase grid) {
  final onsets = voice?.onsets ?? const <Moment>[];
  if (onsets.isNotEmpty) {
    final onset = bar.time.nearest(onsets, x);
    if ((bar.time.xAt(onset) - x).abs() <= 1) {
      return onset;
    }
  }
  return bar.time.nearest(entryPoints(bar.length, voice, grid), x);
}
