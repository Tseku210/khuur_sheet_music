part of 'playback.dart';

/// Seconds of real time a slurred note sounds into the next. In FluidSynth
/// renders of a bowed string, a note that ends as the next starts still
/// dips between the two, and 40 ms of overlap takes the dip away.
const _legatoOverlap = 0.04;

/// Two script times this close are one instant.
const _sameInstant = 1e-9;

/// Lets each legato note sound into the note after it in its voice, by
/// [_legatoOverlap]. A legato note that no note follows, as before a rest,
/// ends on time. So does one whose key is struck again on its channel
/// before the overlap ends, because a synthesizer lets go of that key at
/// the earlier note's note off and silences the new note.
void _join(List<_Sounding> notes) {
  final starts = <_Lane, List<double>>{};
  final strikes = <(int, int), List<double>>{};
  for (final note in notes) {
    (starts[note.lane] ??= []).add(note.start);
    (strikes[(note.channel, note.key)] ??= []).add(note.start);
  }
  for (final times in [...starts.values, ...strikes.values]) {
    times.sort();
  }
  for (final note in notes.where((note) => note.legato)) {
    final end = note.end;
    final next = _firstFrom(starts[note.lane]!, end - _sameInstant);
    final again = _firstFrom(
      strikes[(note.channel, note.key)]!,
      end - _sameInstant,
    );
    if (next != null &&
        next < end + _sameInstant &&
        (again == null || again >= end + _legatoOverlap)) {
      note.overlap = _legatoOverlap;
    }
  }
}

/// The first of [sorted] at or after [from], or null when none is.
double? _firstFrom(List<double> sorted, double from) {
  final at = _partition(sorted.length, (i) => sorted[i] >= from);
  return at < sorted.length ? sorted[at] : null;
}
