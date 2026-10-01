part of 'playback.dart';

/// The tempo through the score in notated order, like loudness. It is
/// steady from each tempo mark and moves straight under a tempo line: from
/// the tempo at the line's start to the first mark after its start and no
/// later than the end of its last event, reaching it there, or else to its
/// start tempo times its factor at that end, where it stays. A line that
/// starts under another takes over from it. Positions count from the start
/// of the score.
final class _TempoMap {
  factory _TempoMap(Score score, List<Length> starts) {
    Moment place(MeasureId measure, Moment offset) =>
        _place(score, starts, measure, offset);
    final marks = [
      for (final column in score.measures)
        for (final TempoMark(:offset, :tempo) in column.tempos)
          _TempoPiece.steady(place(column.id, offset), tempo),
    ];
    final lines = _stableSorted(
      [
        for (final spanner in score.spanners)
          if (spanner.kind case TempoLine(:final factor))
            (
              from: place(spanner.first.measure, spanner.first.offset),
              spanner: spanner,
              factor: factor,
            ),
      ],
      (a, b) => a.from.compareTo(b.from),
    );
    final pieces = [const _TempoPiece.steady(Moment.zero, Tempo.unmarked)];
    var next = 0;
    for (final (:from, :spanner, :factor) in lines) {
      for (; next < marks.length && marks[next].from <= from; next++) {
        pieces.add(marks[next]);
      }
      final last = score.eventAt(
        VoicePoint(
          staff: spanner.staff,
          voice: VoiceSlot.one,
          at: spanner.last,
        ),
      )!;
      final end = place(spanner.last.measure, last.onset + last.duration);
      final start = pieces.last.tempoAt(from);
      final arrival = next < marks.length && marks[next].from <= end
          ? marks[next]
          : null;
      pieces.add(
        _TempoPiece(
          from,
          start,
          arrival?.from ?? end,
          arrival?.target ?? Tempo(start.bpm * factor, beat: start.beat),
        ),
      );
    }
    return _TempoMap._([...pieces, ...marks.skip(next)]);
  }

  _TempoMap._(this._pieces);

  /// By start. Each runs until the next begins.
  final List<_TempoPiece> _pieces;

  _Pace paceAt(Moment position) =>
      _pieces[_covering(position)].paceAt(position);

  /// Where the tempo starts or stops moving inside `(from, to)`.
  Iterable<Moment> turnsBetween(Moment from, Moment to) sync* {
    for (final piece in _pieces.skip(_covering(from))) {
      if (piece.from >= to) {
        return;
      }
      for (final turn in [piece.from, piece.to]) {
        if (from < turn && turn < to) {
          yield turn;
        }
      }
    }
  }

  /// The index of the piece in effect at [position].
  int _covering(Moment position) =>
      _partition(_pieces.length, (i) => _pieces[i].from > position) - 1;
}

/// A tempo moving straight from [start] at [from] to [target] at [to], and
/// then holding [target].
final class _TempoPiece {
  const _TempoPiece(this.from, this.start, this.to, this.target);

  const _TempoPiece.steady(Moment at, Tempo tempo) : this(at, tempo, at, tempo);

  final Moment from;
  final Tempo start;
  final Moment to;
  final Tempo target;

  Tempo tempoAt(Moment position) => switch (paceAt(position)) {
    _Steady(:final tempo) => tempo,
    _Moving(:final rate) => Tempo(
      rate * 60 / target.beat.length.wholeNotes.toDouble(),
      beat: target.beat,
    ),
  };

  _Pace paceAt(Moment position) {
    if (position >= to) {
      return _Steady(target);
    }
    final from = _rate(start);
    final slope =
        (_rate(target) - from) / this.from.until(to).wholeNotes.toDouble();
    return _Moving(
      from + slope * this.from.until(position).wholeNotes.toDouble(),
      slope,
    );
  }
}

/// Whole notes a second at [tempo].
double _rate(Tempo tempo) =>
    tempo.bpm * tempo.beat.length.wholeNotes.toDouble() / 60;

/// How time passes from a point of the score on.
sealed class _Pace {
  const _Pace();

  /// Seconds that [length] after the point lasts.
  double secondsFor(Length length);
}

/// At one tempo, timed exactly as the tempo mark says.
final class _Steady extends _Pace {
  const _Steady(this.tempo);

  final Tempo tempo;

  @override
  double secondsFor(Length length) => tempo.secondsFor(length);
}

/// At [rate] whole notes a second, changing by [slope] each whole note.
final class _Moving extends _Pace {
  const _Moving(this.rate, this.slope);

  final double rate;
  final double slope;

  @override
  double secondsFor(Length length) {
    final wholes = length.wholeNotes.toDouble();
    return slope == 0
        ? wholes / rate
        : log((rate + slope * wholes) / rate) / slope;
  }
}

/// Seconds from a bar's downbeat, by the score's tempo from where the bar
/// sits in it. Time under a fermata on any staff passes at half speed, so
/// the held event lasts twice its length.
final class _Clock {
  factory _Clock(
    _TempoMap tempo,
    Moment downbeat,
    Length length,
    List<(Moment, Moment)> holds,
  ) {
    final cuts = {
      Moment.zero,
      for (final turn in tempo.turnsBetween(downbeat, downbeat + length))
        Moment.zero + downbeat.until(turn),
      for (final (from, to) in holds) ...[from, to],
    }.toList()..sort((a, b) => a.compareTo(b));
    final steps = <_ClockStep>[];
    for (final cut in cuts) {
      steps.add(
        _ClockStep(
          cut,
          steps.lastOrNull?.secondsAt(cut) ?? 0,
          tempo.paceAt(downbeat + Moment.zero.until(cut)),
          holds.any((h) => h.$1 <= cut && cut < h.$2) ? 2 : 1,
        ),
      );
    }
    return _Clock._(steps);
  }

  _Clock._(this._steps);

  /// By start.
  final List<_ClockStep> _steps;

  double at(Moment offset) =>
      _steps[_partition(_steps.length, (i) => _steps[i].from > offset) - 1]
          .secondsAt(offset);
}

/// A stretch of a bar from [from], [seconds] after the downbeat, where the
/// tempo moves at one [pace] and time passes [stretch] times slower.
final class _ClockStep {
  const _ClockStep(this.from, this.seconds, this.pace, this.stretch);

  final Moment from;
  final double seconds;
  final _Pace pace;
  final int stretch;

  double secondsAt(Moment offset) =>
      seconds + pace.secondsFor(from.until(offset)) * stretch;
}
