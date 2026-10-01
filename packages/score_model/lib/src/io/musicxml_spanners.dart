/// The spanners of a MusicXML file, placed on the score its bars make.
/// Internal to the package.
library;

import 'dart:collection';

import '../refs.dart';
import '../score.dart';
import '../time.dart';
import '../voice_walk.dart';
import 'musicxml_records.dart';

/// The spanners [document] pairs, on [score]'s bars. They come part by
/// part, each part's in the order that writes its marks back as the file
/// has them.
List<Spanner> spannersOf(Score score, DocumentRecord document) => [
  for (final part in document.parts)
    for (final placed in _inWritingOrder([
      for (final pair in _pairs(part))
        ?_Placing(score, document, part).place(pair),
    ]))
      placed.spanner(SpannerId(document.ids.take())),
];

/// A start mark and the stop that closes it.
final class _Pair {
  _Pair(this.kind, this.number, this.start, this.stop);

  final SpannerKind kind;
  final int number;
  final LineMark start;
  final LineMark stop;
}

/// The spanners [part]'s marks pair into, in the order their starts are
/// written. A start opens a spanner, replacing one still open under its
/// element and number, and a stop closes the open one.
///
/// A stop can also come before its start. The exporter writes voice one
/// first, so a slur that starts in another voice and ends in a gap of it,
/// on the event of voice one that sounds there, has its stop written
/// first. A stop with nothing open is kept for a start in its bar that its
/// event sounds past.
List<_Pair> _pairs(PartRecord part) {
  final pairs = <_Pair>[];
  for (final MapEntry(key: (_, name), value: marks) in part.marks.entries) {
    final number = int.tryParse(name) ?? 1;
    ({LineMark mark, SpannerKind kind})? open;
    LineMark? early;
    for (final mark in marks) {
      if (!mark.starts) {
        if (open == null) {
          early = mark;
        } else {
          pairs.add(_Pair(open.kind, number, open.mark, mark));
          open = null;
        }
      } else if (mark.kind case final kind?) {
        if (early != null && _soundsPast(early.anchor, mark.anchor)) {
          pairs.add(_Pair(kind, number, mark, early));
          early = null;
        } else {
          open = (mark: mark, kind: kind);
        }
      } else {
        open = null;
      }
    }
  }
  return pairs..sort((a, b) => a.start.index - b.start.index);
}

bool _soundsPast(Anchor stop, Anchor start) =>
    stop is EventAnchor &&
    start is EventAnchor &&
    stop.bar == start.bar &&
    stop.event.end > start.event.onset;

/// A spanner with its ends resolved, before it has an id.
final class _Placed {
  _Placed(
    this.record, {
    required this.staff,
    required this.first,
    required this.last,
    this.voice,
    this.stopsAfter,
  });

  final _Pair record;
  final StaffId staff;
  final ScorePoint first;
  final ScorePoint last;
  final VoiceSlot? voice;

  /// The event a line written as directions stops after. The exporter
  /// writes the stop at that event's end.
  final EventId? stopsAfter;

  Spanner spanner(SpannerId id) => Spanner(
    id: id,
    kind: record.kind,
    staff: staff,
    first: first,
    last: last,
    voice: voice,
  );
}

final class _Placing {
  _Placing(this.score, this.document, this.part);

  final Score score;
  final DocumentRecord document;
  final PartRecord part;

  _Placed? place(_Pair record) =>
      switch ((record.start.anchor, record.stop.anchor)) {
        (final EventAnchor start, final EventAnchor stop) => _onNotes(
          record,
          start,
          stop,
        ),
        (final TimeAnchor start, final TimeAnchor stop) => _onStaff(
          record,
          start,
          stop,
        ),
        // A start and its stop pair under one element name, so both are
        // written the same way.
        (EventAnchor(), TimeAnchor()) || (TimeAnchor(), EventAnchor()) => null,
      };

  ScorePoint _point(int bar, Moment offset) =>
      ScorePoint(document.measures[bar], offset);

  int _compare(ScorePoint a, ScorePoint b) {
    final byBar = score.indexOf(a.measure) - score.indexOf(b.measure);
    return byBar != 0 ? byBar : a.offset.compareTo(b.offset);
  }

  _Placed? _onNotes(_Pair record, EventAnchor start, EventAnchor stop) {
    final staff = start.event.lane.staff;
    if (!record.kind.joinsNotes) {
      final first = _point(start.bar, start.event.onset);
      final last = _point(stop.bar, stop.event.onset);
      return _compare(first, last) > 0
          ? null
          : _Placed(
              record,
              staff: part.staves[staff],
              first: first,
              last: last,
            );
    }
    final slot = start.event.lane.slot;
    final voice = slot == VoiceSlot.one ? stop.event.lane.slot : slot;
    final first = _point(
      start.bar,
      _timeOn(start, staff, voice, from: Moment.zero),
    );
    final placed = _Placed(
      record,
      staff: part.staves[staff],
      first: first,
      last: _point(
        stop.bar,
        _timeOn(
          stop,
          staff,
          voice,
          from: stop.bar == start.bar ? first.offset : Moment.zero,
        ),
      ),
      voice: voice,
    );
    return _compare(first, placed.last) >= 0 ||
            score.isCollapsed(placed.spanner(const SpannerId(0)))
        ? null
        : placed;
  }

  /// The first time from [from] at which a spanner of [voice] on [staff]
  /// attaches to [anchor]'s event. Where [voice] has a gap the spanner
  /// attaches to the event of voice one, so a mark on such an event stands
  /// for a time in that gap, which need not be the event's onset.
  Moment _timeOn(
    EventAnchor anchor,
    int staff,
    VoiceSlot voice, {
    required Moment from,
  }) {
    final event = anchor.event;
    final lane = event.lane;
    if (lane.staff != staff ||
        lane.slot != VoiceSlot.one ||
        voice == VoiceSlot.one) {
      return event.onset;
    }
    final column = score.measures[anchor.bar];
    final id = part.staves[staff];
    var at = from > event.onset ? from : event.onset;
    if (column.staff(id).voice(voice) case final own?) {
      for (final timed in timedEvents(own, measure: column.id, staff: id)) {
        if (timed.onset <= at && at < timed.onset + timed.duration) {
          at = timed.onset + timed.duration;
        }
      }
    }
    return at < event.end ? at : event.onset;
  }

  /// A line written as directions. It starts at its start's time, or with
  /// the next bar when that is the bar's end, and lasts through the
  /// voice-one event that sounds just before its stop.
  _Placed? _onStaff(_Pair record, TimeAnchor start, TimeAnchor stop) {
    final columns = score.measures;
    final staff = part.staves[start.staff];
    final atEnd = start.at >= Moment.zero + columns[start.bar].length;
    if (atEnd && start.bar + 1 == columns.length) {
      return null;
    }
    final first = atEnd
        ? _point(start.bar + 1, Moment.zero)
        : _point(start.bar, start.at);

    final lastBar = stop.at.isZero ? stop.bar - 1 : stop.bar;
    if (lastBar < 0) {
      return null;
    }
    final column = columns[lastBar];
    final events = timedEvents(
      column.staff(staff).voices.first,
      measure: column.id,
      staff: staff,
    );
    final event = stop.at.isZero
        ? events.last
        : events.lastWhere((event) => event.onset < stop.at);
    final written = _point(lastBar, event.onset);
    final last = _compare(written, first) < 0 ? first : written;
    return _Placed(
      record,
      staff: staff,
      first: first,
      last: last,
      stopsAfter: score
          .eventAt(VoicePoint(staff: staff, voice: VoiceSlot.one, at: last))
          ?.event
          .id,
    );
  }
}

/// [placed] in an order that the exporter writes back as the file had it.
/// The exporter writes the marks that share a place in list order, and
/// numbers the spanners that start together in list order, so each such
/// group constrains the list. Where nothing constrains two spanners, the
/// one that starts first in the file comes first.
List<_Placed> _inWritingOrder(List<_Placed> placed) {
  int byStart(int a, int b) =>
      placed[a].record.start.index - placed[b].record.start.index;
  final after = [for (final _ in placed) <int>{}];
  final waiting = List.filled(placed.length, 0);
  void chain(Iterable<List<({int spanner, int rank})>> groups) {
    for (final group in groups) {
      group.sort(
        (a, b) =>
            a.rank != b.rank ? a.rank - b.rank : byStart(a.spanner, b.spanner),
      );
      for (var i = 1; i < group.length; i++) {
        final before = group[i - 1].spanner;
        final next = group[i].spanner;
        if (before != next && after[before].add(next)) {
          waiting[next]++;
        }
      }
    }
  }

  final stops = <EventId?, List<({int spanner, int rank})>>{};
  final starts = <(StaffId, ScorePoint), List<({int spanner, int rank})>>{};
  final onNote = <(int, Type), List<({int spanner, int rank})>>{};
  final together = <(Type, ScorePoint), List<({int spanner, int rank})>>{};
  for (final (i, spanner) in placed.indexed) {
    final _Pair(:kind, :number, :start, :stop) = spanner.record;
    final type = kind.runtimeType;
    switch (start.anchor) {
      case EventAnchor(:final note):
        onNote.putIfAbsent((note, type), () => []).add((
          spanner: i,
          rank: start.index,
        ));
      case TimeAnchor():
        starts.putIfAbsent((spanner.staff, spanner.first), () => []).add((
          spanner: i,
          rank: start.index,
        ));
    }
    switch (stop.anchor) {
      case EventAnchor(:final note):
        onNote.putIfAbsent((note, type), () => []).add((
          spanner: i,
          rank: stop.index,
        ));
      case TimeAnchor():
        stops.putIfAbsent(spanner.stopsAfter, () => []).add((
          spanner: i,
          rank: stop.index,
        ));
    }
    together.putIfAbsent((type, spanner.first), () => []).add((
      spanner: i,
      rank: number,
    ));
  }
  chain(stops.values);
  chain(starts.values);
  chain(onNote.values);
  chain(together.values);

  final left = SplayTreeSet<int>(byStart)
    ..addAll([for (var i = 0; i < placed.length; i++) i]);
  final ready = SplayTreeSet<int>(byStart)
    ..addAll(left.where((i) => waiting[i] == 0));
  final ordered = <_Placed>[];
  while (left.isNotEmpty) {
    // Constraints that contradict each other leave nothing ready.
    final next = ready.firstOrNull ?? left.first;
    ready.remove(next);
    left.remove(next);
    ordered.add(placed[next]);
    for (final later in after[next]) {
      if (--waiting[later] == 0 && left.contains(later)) {
        ready.add(later);
      }
    }
  }
  return ordered;
}
