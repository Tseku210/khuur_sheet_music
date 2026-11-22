part of 'playback.dart';

/// How loud one part plays through the score, read in notated order like
/// tempo: the dynamics on any of its staves, and its hairpins. Positions
/// count from the start of the score.
final class _Loudness {
  factory _Loudness(
    Score score,
    Seq<Staff> staves,
    _Timeline time,
    _TempoMap tempo,
  ) {
    final ids = {for (final staff in staves) staff.id};
    final strikes = <Moment, Dynamic>{};
    final strikeEnds = <Moment, Moment>{};
    final marks = <(Moment, Dynamic)>[];
    for (final column in score.measures) {
      for (final measure in column.staves) {
        if (!ids.contains(measure.staff)) {
          continue;
        }
        for (final direction in measure.directions) {
          if (direction case DynamicMark(:final offset, :final level)) {
            final position = time.of(column.id, offset);
            switch (level) {
              case Dynamic.fp:
                strikes[position] = level;
                strikeEnds[position] = position + _easeAt(tempo, position);
                marks.add((position, Dynamic.p));
              case Dynamic.sf || Dynamic.sfz || Dynamic.rfz:
                strikes[position] = level;
                final next = [
                  for (final voice in measure.voices)
                    for (final timed in timedEvents(
                      voice,
                      measure: column.id,
                      staff: measure.staff,
                    ))
                      if (timed.onset > offset) timed.onset,
                ].fold(Moment.zero + column.length, (a, b) => b < a ? b : a);
                strikeEnds[position] = time.of(column.id, next);
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
            if (time.extentOf(spanner) case (final from, final end))
              (from: from, end: end, crescendo: crescendo),
      ],
      (a, b) => a.from.compareTo(b.from),
    );
    final ramps = <_Ramp>[];
    for (final (:from, :end, :crescendo) in hairpins) {
      final start = _levelAt(levels, from);
      final arrival = written
          .where((l) => from < l.$1 && l.$1 <= end)
          .firstOrNull;
      // As in MuseScore, a dynamic that lies against the hairpin is not
      // its target.
      final aimed =
          arrival != null &&
          (crescendo
              ? arrival.$2.velocity > start.velocity
              : arrival.$2.velocity < start.velocity);
      final target = aimed ? arrival.$2 : _step(start, louder: crescendo);
      ramps.add(
        _Ramp(from, arrival?.$1 ?? end, start.velocity, target.velocity),
      );
      if (arrival == null) {
        levels.insert(
          _partition(levels.length, (i) => levels[i].$1 > end),
          (end, target),
        );
      }
    }
    return _Loudness._(strikes, strikeEnds, written, levels, ramps);
  }

  _Loudness._(
    this._strikes,
    this._strikeEnds,
    this._written,
    this._levels,
    this._ramps,
  );

  /// sf, sfz, fp and rfz by position. Each strikes the chords there, and
  /// fp then leaves the level at p.
  final Map<Moment, Dynamic> _strikes;

  /// Where each strike stops holding a note's level: for sf, sfz and rfz
  /// the next onset on its staff in the bar, or the bar's end, and for fp
  /// the end of its ease down to p.
  final Map<Moment, Moment> _strikeEnds;

  /// Level dynamics as written, by position.
  final List<(Moment, Dynamic)> _written;

  /// Level dynamics and the levels hairpins arrive at, by position.
  final List<(Moment, Dynamic)> _levels;

  /// By start.
  final List<_Ramp> _ramps;

  /// Whether a dynamic or a hairpin is written from [from] to [to], both
  /// included. The level a hairpin ending at [from] arrives at is not.
  bool markedIn(Moment from, Moment to) =>
      _strikes.keys.any((at) => from <= at && at <= to) ||
      _written.any((level) => from <= level.$1 && level.$1 <= to) ||
      _ramps.any((ramp) => ramp.from <= to && from < ramp.to);

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

  /// The first point of [from] to [to], both included, where a dynamic or
  /// a hairpin written there takes over, or null. [markedIn] is true from
  /// there on.
  Moment? firstMarkIn(Moment from, Moment to) {
    Moment? first;
    void take(Moment at) {
      if (from <= at && at <= to && (first == null || at < first!)) {
        first = at;
      }
    }

    _strikes.keys.forEach(take);
    for (final (at, _) in _written) {
      take(at);
    }
    for (final ramp in _ramps) {
      if (from < ramp.to) {
        take(ramp.from < from ? from : ramp.from);
      }
    }
    return first;
  }

  /// The level a sounding note has at [position], held from each point of
  /// [_heldSteps] to the next.
  double heldAt(Moment position) {
    final after = _partition(
      _heldSteps.length,
      (i) => _heldSteps[i].$1 > position,
    );
    return after == 0
        ? Dynamic.mf.velocity.toDouble()
        : _heldSteps[after - 1].$2;
  }

  Iterable<(Moment, double)> changesIn(Moment from, Moment to) => _heldSteps
      .skip(_partition(_heldSteps.length, (i) => _heldSteps[i].$1 > from))
      .takeWhile((step) => step.$1 < to);

  /// As in MuseScore, a hairpin that starts on an fp starts after its ease.
  late final List<(Moment, double)> _heldSteps = () {
    final ramps = [
      for (final ramp in _ramps)
        if (_strikeEnds[ramp.from] case final end?
            when _strikes[ramp.from] == Dynamic.fp && end < ramp.to)
          _Ramp(end, ramp.to, ramp.start, ramp.target)
        else
          ramp,
    ];
    final strikes = stableSorted([
      for (final MapEntry(key: at, value: strike) in _strikes.entries)
        (at, _strikeEnds[at]!, strike),
    ], (a, b) => a.$1.compareTo(b.$1));
    final cuts = <Moment>{
      Moment.zero,
      for (final (at, _) in _levels) at,
      for (final ramp in ramps)
        for (var i = 0; i <= ramp.steps; i++)
          ramp.from + ramp.from.until(ramp.to) * Fraction(i, ramp.steps),
      for (final (at, end, strike) in strikes) ...[
        end,
        if (strike == Dynamic.fp)
          for (var i = 0; i < _easeSteps; i++)
            at + at.until(end) * Fraction(i, _easeSteps)
        else
          at,
      ],
    }.toList()..sort((a, b) => a.compareTo(b));
    double levelAt(Moment position) {
      final struck = _partition(
        strikes.length,
        (i) => strikes[i].$1 > position,
      );
      if (struck > 0) {
        final (at, end, strike) = strikes[struck - 1];
        if (position < end) {
          if (strike != Dynamic.fp) {
            return strike.velocity.toDouble();
          }
          final step =
              (at.until(position) / at.until(end) * Fraction(_easeSteps))
                  .floor();
          return Dynamic.fp.velocity +
              (Dynamic.p.velocity - Dynamic.fp.velocity) * step / _easeSteps;
        }
      }
      final started = _partition(ramps.length, (i) => ramps[i].from > position);
      for (var i = started - 1; i >= 0; i--) {
        if (position < ramps[i].to) {
          return ramps[i].stepAt(position);
        }
      }
      return _levelAt(_levels, position).velocity.toDouble();
    }

    final steps = <(Moment, double)>[];
    for (final at in cuts) {
      final level = levelAt(at);
      if (steps.lastOrNull?.$2 != level) {
        steps.add((at, level));
      }
    }
    return steps;
  }();
}

/// How many steps fp's ease from f to p takes, as in MuseScore.
const _easeSteps = 6;

/// How long fp's ease lasts at [position]: 0.4 seconds, MuseScore's 0.8 of
/// a quarter at 120 a minute, at the tempo there.
Length _easeAt(_TempoMap tempo, Moment position) {
  final Tempo(:bpm, :beat) = tempo.tempoAt(position);
  final wholes = 0.4 * bpm / 60 * beat.length.wholeNotes.toDouble();
  return Length(Fraction(max((wholes * 1920).round(), 1), 1920));
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

  /// How many steps a held note moves in, one a sixteenth and at least 24,
  /// as MuseScore's hairpin.
  int get steps =>
      max((from.until(to) / NoteValue.sixteenth.length).floor(), 24);

  double stepAt(Moment position) {
    final step = (from.until(position) / from.until(to) * Fraction(steps))
        .floor();
    return start + (target - start) * step / steps;
  }
}
