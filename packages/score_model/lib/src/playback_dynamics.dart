part of 'playback.dart';

/// How loud one part plays through the score, read in notated order like
/// tempo: the dynamics on any of its staves, and its hairpins. Positions
/// count from the start of the score.
final class _Loudness {
  factory _Loudness(Score score, Seq<Staff> staves, List<Length> starts) {
    final ids = {for (final staff in staves) staff.id};
    Moment place(MeasureId measure, Moment offset) =>
        _place(score, starts, measure, offset);
    final strikes = <Moment, Dynamic>{};
    final marks = <(Moment, Dynamic)>[];
    for (final column in score.measures) {
      for (final measure in column.staves) {
        if (!ids.contains(measure.staff)) {
          continue;
        }
        for (final direction in measure.directions) {
          if (direction case DynamicMark(:final offset, :final level)) {
            final position = place(column.id, offset);
            switch (level) {
              case Dynamic.fp:
                strikes[position] = level;
                marks.add((position, Dynamic.p));
              case Dynamic.sf || Dynamic.sfz || Dynamic.rfz:
                strikes[position] = level;
              case Dynamic.pppp ||
                  Dynamic.ppp ||
                  Dynamic.pp ||
                  Dynamic.p ||
                  Dynamic.mp ||
                  Dynamic.mf ||
                  Dynamic.f ||
                  Dynamic.ff ||
                  Dynamic.fff ||
                  Dynamic.ffff:
                marks.add((position, level));
            }
          }
        }
      }
    }
    final written = stableSorted(marks, (a, b) => a.$1.compareTo(b.$1));
    final levels = [...written];
    final hairpins = stableSorted(
      [
        for (final spanner in score.spanners)
          if (spanner.kind case Hairpin(:final crescendo)
              when ids.contains(spanner.staff))
            (
              from: place(spanner.first.measure, spanner.first.offset),
              spanner: spanner,
              crescendo: crescendo,
            ),
      ],
      (a, b) => a.from.compareTo(b.from),
    );
    final ramps = <_Ramp>[];
    for (final (:from, :spanner, :crescendo) in hairpins) {
      final end = place(spanner.last.measure, score.lineEnd(spanner));
      final start = _levelAt(levels, from);
      final arrival = written
          .where((l) => from < l.$1 && l.$1 <= end)
          .firstOrNull;
      final (to, target) = arrival ?? (end, _step(start, louder: crescendo));
      ramps.add(_Ramp(from, to, start.velocity, target.velocity));
      if (arrival == null) {
        levels.insert(
          _partition(levels.length, (i) => levels[i].$1 > end),
          (end, target),
        );
      }
    }
    return _Loudness._(strikes, levels, ramps);
  }

  _Loudness._(this._strikes, this._levels, this._ramps);

  /// sf, sfz, fp and rfz by position. Each strikes the chords there, and
  /// fp then leaves the level at p.
  final Map<Moment, Dynamic> _strikes;

  /// Level dynamics and the levels hairpins arrive at, by position.
  final List<(Moment, Dynamic)> _levels;

  /// By start.
  final List<_Ramp> _ramps;

  /// The velocity a chord starting at [position] strikes at, before its
  /// own marks. A strike there comes first, then the latest hairpin
  /// running there, then the level.
  double at(Moment position) {
    if (_strikes[position] case final strike?) {
      return strike.velocity.toDouble();
    }
    final started = _partition(_ramps.length, (i) => _ramps[i].from > position);
    for (var i = started - 1; i >= 0; i--) {
      if (position < _ramps[i].to) {
        return _ramps[i].at(position);
      }
    }
    return _levelAt(_levels, position).velocity.toDouble();
  }
}

/// The last level at or before [position], or mf before the first.
Dynamic _levelAt(List<(Moment, Dynamic)> levels, Moment position) {
  final after = _partition(levels.length, (i) => levels[i].$1 > position);
  return after == 0 ? Dynamic.mf : levels[after - 1].$2;
}

/// The level one step louder or softer, within pppp to ffff, which lead
/// the [Dynamic] values in order.
Dynamic _step(Dynamic level, {required bool louder}) =>
    Dynamic.values[(level.index + (louder ? 1 : -1)).clamp(
      Dynamic.pppp.index,
      Dynamic.ffff.index,
    )];

/// A hairpin's velocity, moving straight from [start] at [from] to
/// [target] at [to].
final class _Ramp {
  const _Ramp(this.from, this.to, this.start, this.target);

  final Moment from;
  final Moment to;
  final int start;
  final int target;

  double at(Moment position) =>
      start +
      (target - start) * (from.until(position) / from.until(to)).toDouble();
}
