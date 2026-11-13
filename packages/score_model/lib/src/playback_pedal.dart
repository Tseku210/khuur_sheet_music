part of 'playback.dart';

/// When the sustain pedal of one part is down, in seconds of the script.
///
/// A [PedalLine] on any staff of a part puts the pedal down for the whole
/// part, from the line's first point to the end of the event its last
/// point falls in. Lines that overlap keep it down, and a line that starts
/// where another ends changes it. The pedal goes down on every pass that
/// reaches a line. A range or a jump that lands under a line starts with
/// it down, and it lifts where the music jumps away.
final class _Pedal {
  _Pedal._(this._downs, this._ups);

  /// In time order. The pedal is down in each `[down, up)`, and no two
  /// overlap.
  final List<double> _downs;
  final List<double> _ups;

  /// When the pedal that is down at [seconds] lifts, or null when it is up
  /// then. A key let go as the pedal goes down is let go before it.
  double? liftAfter(double seconds) {
    final at = _partition(_downs.length, (i) => _downs[i] >= seconds) - 1;
    return at >= 0 && seconds < _ups[at] ? _ups[at] : null;
  }
}

/// The pedal of every staff of a part with a pedal line.
Map<StaffId, _Pedal> _pedals(
  Score score,
  List<Length> starts,
  List<({int index, int pass, Moment from, Moment to})> windows,
  List<_Bar> timeline,
) {
  final lines = <Part, List<(Moment, Moment)>>{};
  for (final spanner in score.spanners) {
    if (spanner.kind is PedalLine) {
      (lines[score.partOf(spanner.staff)] ??= []).add((
        _place(score, starts, spanner.first.measure, spanner.first.offset),
        _place(score, starts, spanner.last.measure, score.lineEnd(spanner)),
      ));
    }
  }
  if (lines.isEmpty) {
    return const {};
  }
  // Where each played bar starts and ends in notated time. The music runs
  // on from one to the next where the two meet.
  final played = [
    for (final (:index, :from, :to, pass: _) in windows)
      (from + starts[index], to + starts[index]),
  ];
  double secondsAt(int k, Moment position) =>
      timeline[k].secondsAt(position - starts[windows[k].index]);
  final pedals = <StaffId, _Pedal>{};
  for (final MapEntry(key: part, value: written) in lines.entries) {
    final spans = <(Moment, Moment)>[];
    for (final (down, up) in stableSorted(
      written,
      (a, b) => a.$1.compareTo(b.$1),
    )) {
      if (spans.isEmpty || down >= spans.last.$2) {
        spans.add((down, up));
      } else if (up > spans.last.$2) {
        spans.last = (spans.last.$1, up);
      }
    }
    final downs = <double>[];
    final ups = <double>[];
    for (final (k, (start, end)) in played.indexed) {
      final landed = k == 0 || played[k - 1].$2 != start;
      for (
        var i = _partition(spans.length, (i) => spans[i].$2 > start);
        i < spans.length && spans[i].$1 < end;
        i++
      ) {
        final (down, up) = spans[i];
        if (down < start && !landed) {
          continue;
        }
        var last = k;
        while (up > played[last].$2 &&
            last + 1 < played.length &&
            played[last + 1].$1 == played[last].$2) {
          last++;
        }
        downs.add(down < start ? timeline[k].played.start : secondsAt(k, down));
        ups.add(
          up > played[last].$2
              ? timeline[last].played.end
              : secondsAt(last, up),
        );
      }
    }
    final pedal = _Pedal._(downs, ups);
    for (final staff in part.staves) {
      pedals[staff.id] = pedal;
    }
  }
  return pedals;
}
