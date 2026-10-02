/// Default beam groups. Internal to the package.
library;

import 'events.dart';
import 'refs.dart';
import 'time.dart';
import 'views.dart';

/// Beam groups for one voice of one bar in [meter].
///
/// Eighths and shorter beam together until one of these breaks the run: a
/// note of a quarter or longer, [BeamMode.none] or [BeamMode.begin], a
/// change of enclosing tuplet, one of the meter's beam breaks, or a rest
/// that falls between two beats. [BeamMode.join] overrides all but the
/// first two. A group holding sixteenths or shorter then splits per beat,
/// again except at a join.
List<BeamGroup> beamGroups(List<TimedEvent> events, Meter meter) {
  final breaks = meter.beamBreaks;
  final beats = meter.beatOffsets;
  final runs = <List<_Beamed>>[];
  var run = <_Beamed>[];
  var restBefore = false;
  for (final timed in events) {
    final event = timed.event;
    if (event is! ChordEvent) {
      restBefore = true;
      continue;
    }
    final next = _Beamed(timed, event);
    final last = run.lastOrNull;
    if (next.beams == 0 || next.mode == BeamMode.none) {
      runs.add(run);
      run = [];
    } else if (last == null || _joins(last, next, restBefore, breaks, beats)) {
      run.add(next);
    } else {
      runs.add(run);
      run = [next];
    }
    restBefore = false;
  }
  runs.add(run);
  return [
    for (final run in runs)
      for (final group in _splitByBeat(run, beats))
        if (group.length > 1) _beamGroup(group, _secondaryBreaks(group, meter)),
  ];
}

/// The beam group of [group], whose secondary beams break before the
/// indices in [breaks]. [BeamGroup.joins] states the rule.
BeamGroup _beamGroup(List<_Beamed> group, List<int> breaks) {
  bool reaches(int i, int level) =>
      i > 0 &&
      i < group.length &&
      group[i - 1].beams >= level &&
      group[i].beams >= level &&
      (level == 1 || !breaks.contains(i));
  return BeamGroup(
    [for (final beamed in group) beamed.timed.event.id],
    secondaryBreaks: breaks,
    joins: [
      for (final (i, beamed) in group.indexed)
        [
          for (var level = 1; level <= beamed.beams; level++)
            switch ((reaches(i, level), reaches(i + 1, level))) {
              (true, true) => BeamJoin.continued,
              (true, false) => BeamJoin.end,
              (false, true) => BeamJoin.begin,
              (false, false) =>
                i < group.length - 1 && (i == 0 || breaks.contains(i))
                    ? BeamJoin.forwardHook
                    : BeamJoin.backwardHook,
            },
        ],
    ],
  );
}

final class _Beamed {
  _Beamed(this.timed, ChordEvent chord)
    : beams = chord.value.base.beams,
      mode = chord.beam;

  final TimedEvent timed;
  final int beams;
  final BeamMode mode;

  Moment get onset => timed.onset;

  TupletId? get tuplet => timed.tuplets.lastOrNull;
}

bool _joins(
  _Beamed last,
  _Beamed next,
  bool restBefore,
  List<Moment> breaks,
  List<Moment> beats,
) => switch (next.mode) {
  BeamMode.join => true,
  BeamMode.begin => false,
  _ =>
    last.tuplet == next.tuplet &&
        _span(breaks, last.onset) == _span(breaks, next.onset) &&
        (!restBefore || _span(beats, last.onset) == _span(beats, next.onset)),
};

/// Which of the spans starting at [starts] holds [at].
int _span(List<Moment> starts, Moment at) =>
    starts.lastIndexWhere((start) => start <= at);

List<List<_Beamed>> _splitByBeat(List<_Beamed> run, List<Moment> beats) {
  if (!run.any((beamed) => beamed.beams >= 2)) {
    return [run];
  }
  final groups = <List<_Beamed>>[[]];
  for (final beamed in run) {
    final last = groups.last.lastOrNull;
    if (last != null &&
        beamed.mode != BeamMode.join &&
        _span(beats, last.onset) != _span(beats, beamed.onset)) {
      groups.add([]);
    }
    groups.last.add(beamed);
  }
  return groups;
}

/// Where two sixteenths or shorter meet on a multiple of the meter's unit,
/// only the eighth beam continues.
List<int> _secondaryBreaks(List<_Beamed> group, Meter meter) {
  final unit = Fraction(1, meter.unit);
  return [
    for (var i = 1; i < group.length; i++)
      if (group[i - 1].beams >= 2 &&
          group[i].beams >= 2 &&
          (group[i].onset.wholeNotes / unit).denominator == 1)
        i,
  ];
}
