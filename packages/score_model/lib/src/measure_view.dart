/// Builds `Score.measureView`. Internal to the package.
library;

import 'beaming.dart';
import 'events.dart';
import 'measure.dart';
import 'pitch.dart';
import 'refs.dart';
import 'score.dart';
import 'time.dart';
import 'views.dart';
import 'voice_walk.dart';

/// The view of bar [index] of [score]. Reads the previous column for printed
/// changes and tie arrivals, and the next column for tie targets.
MeasureView buildMeasureView(Score score, int index) {
  final column = score.measures[index];
  final previous = index > 0 ? score.measures[index - 1] : null;
  final next = index + 1 < score.measures.length
      ? score.measures[index + 1]
      : null;
  final segments = [
    for (final spanner in score.spannersTouching(column.id))
      _segment(column, spanner),
  ];
  final staves = [
    for (final part in score.parts)
      if (!part.hidden)
        for (final staff in part.staves)
          _staffView(part, staff.id, column, previous, next, segments),
  ];
  final visible = {for (final staff in staves) staff.source.staff};
  return MeasureView(
    column: column,
    index: index,
    meterChanged: previous == null || previous.meter != column.meter,
    keyChanged: previous == null || previous.key.fifths != column.key.fifths,
    previousKey: previous?.key,
    voltaStarts: column.volta != null && previous?.volta != column.volta,
    voltaEnds: column.volta != null && next?.volta != column.volta,
    staves: staves,
    spanners: [
      for (final segment in segments)
        if (visible.contains(segment.spanner.staff)) segment,
    ],
  );
}

SpannerSegment _segment(MeasureColumn column, Spanner spanner) {
  final startsHere = spanner.first.measure == column.id;
  final endsHere = spanner.last.measure == column.id;
  return SpannerSegment(
    spanner: spanner,
    from: startsHere ? spanner.first.offset : Moment.zero,
    to: endsHere ? spanner.last.offset : Moment.zero + column.length,
    startsHere: startsHere,
    endsHere: endsHere,
  );
}

StaffView _staffView(
  Part part,
  StaffId id,
  MeasureColumn column,
  MeasureColumn? previous,
  MeasureColumn? next,
  List<SpannerSegment> segments,
) {
  final source = column.staff(id);
  final writtenKey = part.instrument.writtenKey(column.key);
  final lanes = [
    for (final voice in source.voices)
      (voice, timedEvents(voice, measure: column.id, staff: id).toList()),
  ];
  final octaveLines = [
    for (final segment in segments)
      if (segment.spanner
          case Spanner(
            :final staff,
            kind: OctaveLine(:final shift),
          )
          when staff == id)
        (from: segment.from, to: segment.to, octaves: shift.octaves),
  ];

  Pitch written(Note note, Moment onset) {
    final octaves =
        octaveLines
            .where((line) => line.from <= onset && onset <= line.to)
            .firstOrNull
            ?.octaves ??
        0;
    return switch (note) {
      PitchedNote(:final pitch) => pitch.transpose(
        -(part.instrument.transposition + Interval.octave * octaves),
        key: writtenKey,
      ),
      DrumNote(:final drum) => part.instrument.soundOf(drum)!.position,
    };
  }

  final heads = [
    for (final (_, events) in lanes)
      for (final timed in events)
        if (timed.event case ChordEvent(:final graces, :final notes)) ...[
          for (final grace in graces)
            for (final note in grace.notes)
              (onset: timed.onset, grace: true, note: note),
          for (final note in notes)
            (onset: timed.onset, grace: false, note: note),
        ],
  ];
  final writtenPitches = {
    for (final head in heads) head.note.id: written(head.note, head.onset),
  };

  final tiedIn = [
    if (previous != null)
      for (final voice in previous.staff(id).voices)
        if (timedEvents(voice, measure: previous.id, staff: id).lastOrNull
            case final last?
            when last.onset + last.duration == Moment.zero + previous.length)
          if (last.event case final ChordEvent chord)
            for (final (_, to) in _tieEnds(
              chord,
              _openingEvent(column, id, voice.slot),
            ))
              ?to?.note,
  ];

  return StaffView(
    source: source,
    part: part,
    clefChanged:
        previous == null || previous.staff(id).clefAtEnd != source.clef,
    writtenKey: writtenKey,
    voices: [
      for (final (voice, events) in lanes)
        VoiceView(
          slot: voice.slot,
          events: events,
          beams: beamGroups(events, column.meter),
          tuplets: _tuplets(voice, events),
        ),
    ],
    accidentals: _accidentals(
      heads,
      writtenPitches,
      tiedIn.toSet(),
      writtenKey,
    ),
    ties: _ties(lanes, column, next, id),
    tiedIn: tiedIn,
    writtenPitches: writtenPitches,
  );
}

/// Each tied note of [chord], with the note of the same tone in [target]
/// that the tie lands on, or null when none matches.
List<(Note, NoteRef?)> _tieEnds(ChordEvent chord, TimedEvent? target) {
  NoteRef? landing(Note tied) {
    if (target case TimedEvent(:final ref, event: ChordEvent(:final notes))) {
      for (final note in notes) {
        if (note.tone == tied.tone) {
          return NoteRef(ref, note.id);
        }
      }
    }
    return null;
  }

  return [
    for (final note in chord.notes)
      if (note.tie) (note, landing(note)),
  ];
}

/// A tie lands on the next event of its voice when that event starts where
/// the tied one ends, or on the voice's opening event in the next bar when
/// the tied one ends this bar.
List<TieView> _ties(
  List<(Voice, List<TimedEvent>)> lanes,
  MeasureColumn column,
  MeasureColumn? next,
  StaffId id,
) {
  final barEnd = Moment.zero + column.length;
  final ties = <TieView>[];
  for (final (voice, events) in lanes) {
    for (final (i, timed) in events.indexed) {
      if (timed.event case final ChordEvent chord) {
        final end = timed.onset + timed.duration;
        final following = events.elementAtOrNull(i + 1);
        final crosses = end == barEnd;
        final target = crosses
            ? _openingEvent(next, id, voice.slot)
            : (following?.onset == end ? following : null);
        for (final (from, to) in _tieEnds(chord, target)) {
          ties.add(
            TieView(
              from: from.id,
              to: to,
              crossesBarline: to != null && crosses,
            ),
          );
        }
      }
    }
  }
  return ties;
}

/// The event that starts voice [slot] of staff [id] in [column], or null
/// when that voice is absent or opens with a gap.
TimedEvent? _openingEvent(MeasureColumn? column, StaffId id, VoiceSlot slot) {
  final voice = column?.staff(id).voice(slot);
  if (column == null || voice == null) {
    return null;
  }
  final first = timedEvents(voice, measure: column.id, staff: id).first;
  return first.onset.isZero ? first : null;
}

/// Tuplets in pre-order: an outer tuplet before the tuplets it holds.
List<TupletView> _tuplets(Voice voice, List<TimedEvent> events) {
  final views = <TupletView>[];
  void walk(
    Iterable<VoiceItem> items,
    Moment start,
    Fraction scale,
    int depth,
  ) {
    var at = start;
    for (final item in items) {
      final duration = item.span * scale;
      if (item is Tuplet) {
        views.add(
          TupletView(
            tuplet: item,
            onset: at,
            duration: duration,
            events: [
              for (final timed in events)
                if (timed.tuplets.contains(item.id)) timed.event.id,
            ],
            depth: depth,
          ),
        );
        walk(item.members, at, scale * item.ratio.scale, depth + 1);
      }
      at += duration;
    }
  }

  walk(voice.items, Moment.zero, Fraction.one, 0);
  return views;
}

typedef _Head = ({Moment onset, bool grace, Note note});

/// Heads are read in time order, grace notes before the chords they
/// ornament. An alteration holds at its written staff position until the
/// barline. A note tied in from the previous bar prints nothing and leaves
/// the state alone, so the next note at that position reprints.
Map<NoteId, AccidentalMark> _accidentals(
  List<_Head> heads,
  Map<NoteId, Pitch> written,
  Set<NoteId> tiedIn,
  KeySignature key,
) {
  // List.sort is not stable, so the index breaks ties to keep voice order.
  final order = [for (var i = 0; i < heads.length; i++) i]
    ..sort((a, b) {
      final byOnset = heads[a].onset.compareTo(heads[b].onset);
      if (byOnset != 0) {
        return byOnset;
      }
      if (heads[a].grace != heads[b].grace) {
        return heads[a].grace ? -1 : 1;
      }
      return a - b;
    });
  final state = <int, Alter>{};
  final marks = <NoteId, AccidentalMark>{};
  for (final i in order) {
    final note = heads[i].note;
    if (note is! PitchedNote) {
      continue;
    }
    final pitch = written[note.id]!;
    switch (note.accidental) {
      case AccidentalRequest.never:
        continue;
      case AccidentalRequest.always:
        marks[note.id] = AccidentalMark(pitch.alter);
      case AccidentalRequest.cautionary:
        marks[note.id] = AccidentalMark(pitch.alter, cautionary: true);
      case AccidentalRequest.auto:
        if (tiedIn.contains(note.id)) {
          continue;
        }
        final expected = state[pitch.diatonic] ?? key.alterFor(pitch.step);
        if (pitch.alter != expected) {
          marks[note.id] = AccidentalMark(pitch.alter);
        }
    }
    state[pitch.diatonic] = pitch.alter;
  }
  return marks;
}
