/// Builds `Score.measureView`. Internal to the package.
library;

import 'beaming.dart';
import 'events.dart';
import 'measure.dart';
import 'pitch.dart';
import 'refs.dart';
import 'score.dart';
import 'spanner_ends.dart';
import 'stable_sort.dart';
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
      _segment(score, column, spanner),
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

/// The piece of [spanner] in [column]. It ends at `Score.endOf` in the
/// spanner's last bar and at the bar's end before it.
SpannerSegment _segment(Score score, MeasureColumn column, Spanner spanner) {
  final startsHere = spanner.first.measure == column.id;
  final endsHere = spanner.last.measure == column.id;
  final onEvents = spanner.kind.reach == SpannerReach.events;
  final ends = score.spannerEnds(spanner);
  return SpannerSegment(
    spanner: spanner,
    from: startsHere ? spanner.first.offset : Moment.zero,
    to: endsHere ? ends.stop : Moment.zero + column.length,
    startsHere: startsHere,
    endsHere: endsHere,
    startsOn: startsHere && onEvents ? ends.startsOn : null,
    endsOn: endsHere && onEvents ? ends.endsOn : null,
    startNote: startsHere ? ends.startNote?.id : null,
    endNote: endsHere ? ends.endNote?.id : null,
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
  final walked = [
    for (final voice in source.voices)
      (voice, timedVoice(voice, measure: column.id, staff: id)),
  ];
  final lanes = [for (final (voice, timed) in walked) (voice, timed.events)];
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
            .where((line) => line.from <= onset && onset < line.to)
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

  final heads = accidentalHeads([for (final (_, events) in lanes) events]);
  final writtenPitches = {
    for (final head in heads) head.note.id: written(head.note, head.onset),
  };

  final tiedIn = [
    if (previous != null)
      for (final (slot, chord) in _tiedAtEnd(previous, id))
        for (final (_, to) in _tieEnds(
          chord,
          slot,
          voicesAtBarline(previous, column, id),
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
      for (final (voice, (:events, :tuplets)) in walked)
        VoiceView(
          slot: voice.slot,
          events: events,
          beams: beamGroups(events, column.meter),
          tuplets: _tuplets(tuplets, events),
          nextOpening: next == null ? null : openingEvent(next, id, voice.slot),
        ),
    ],
    accidentals: foldAccidentals(
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

bool _tied(ChordEvent chord) =>
    chord.notes.any((note) => note.tie || note.letRing);

/// Each tied note of [chord], a chord of voice [from], with the head it
/// lands on among [voices], the staff's voices where the chord ends
/// ([tieLanding]), or null when it lands on none or lets ring.
List<(Note, NoteRef?)> _tieEnds(
  ChordEvent chord,
  VoiceSlot from,
  List<VoiceAround> voices,
) => [
  for (final note in chord.notes)
    if (note.tie)
      (note, tieLandingAround(note, from, voices))
    else if (note.letRing)
      (note, null),
];

/// The chords that end [column] on [staff] with a tie or a let-ring tie,
/// each with its voice.
Iterable<(VoiceSlot, ChordEvent)> _tiedAtEnd(
  MeasureColumn column,
  StaffId staff,
) sync* {
  for (final voice in column.staff(staff).voices) {
    if (lastEvent(voice) case final ChordEvent chord when _tied(chord)) {
      final last = timedEvents(voice, measure: column.id, staff: staff).last;
      if (last.onset + last.duration == Moment.zero + column.length) {
        yield (voice.slot, chord);
      }
    }
  }
}

/// A tie lands where [tieLanding] says, inside the bar or, from a note that
/// ends the bar, in the next one.
List<TieView> _ties(
  List<(Voice, List<TimedEvent>)> lanes,
  MeasureColumn column,
  MeasureColumn? next,
  StaffId id,
) {
  final barEnd = Moment.zero + column.length;
  final ties = <TieView>[];
  for (final (voice, events) in lanes) {
    for (final timed in events) {
      if (timed.event case final ChordEvent chord when _tied(chord)) {
        final end = timed.onset + timed.duration;
        final crosses = end == barEnd;
        final voices = crosses
            ? (next == null
                  ? const <VoiceAround>[]
                  : voicesAtBarline(column, next, id))
            : voicesInside(lanes, end);
        for (final (from, to) in _tieEnds(chord, voice.slot, voices)) {
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

/// Tuplets in pre-order: an outer tuplet before the tuplets it holds.
List<TupletView> _tuplets(
  List<TimedTuplet> tuplets,
  List<TimedEvent> events,
) {
  final members = <TupletId, List<EventId>>{};
  for (final timed in events) {
    for (final id in timed.tuplets) {
      (members[id] ??= []).add(timed.event.id);
    }
  }
  return [
    for (final (:tuplet, :onset, :span, :depth) in tuplets)
      TupletView(
        tuplet: tuplet,
        onset: onset,
        duration: span,
        events: members[tuplet.id] ?? const [],
        depth: depth,
      ),
  ];
}

/// One note head as the accidental rules read it, with its chord's `onset`
/// in the bar and whether it is a `grace` note.
typedef AccidentalHead = ({Moment onset, bool grace, Note note});

/// Every note head of a staff's [lanes], each lane's events in time order,
/// graces included.
List<AccidentalHead> accidentalHeads(Iterable<List<TimedEvent>> lanes) => [
  for (final events in lanes)
    for (final timed in events)
      if (timed.event case ChordEvent(:final graces, :final notes)) ...[
        for (final grace in graces)
          for (final note in grace.notes)
            (onset: timed.onset, grace: true, note: note),
        for (final note in notes)
          (onset: timed.onset, grace: false, note: note),
      ],
];

/// The request [note] states. [autoPrints] says whether the auto rule
/// would print an accidental on it.
typedef AccidentalRequestOf = AccidentalRequest Function(
  PitchedNote note, {
  required bool autoPrints,
});

AccidentalRequest _stated(PitchedNote note, {required bool autoPrints}) =>
    note.accidental;

/// Whether a head that asks for [request] sets the alteration in force at
/// its staff position for the heads after it. A head that never prints does
/// not, and neither does one [tiedIn] from the bar before that prints only
/// by the rules.
bool holdsAlteration(AccidentalRequest request, {required bool tiedIn}) =>
    request != AccidentalRequest.never &&
    (request != AccidentalRequest.auto || !tiedIn);

/// The accidental each of [heads] prints, given [written] pitches, the
/// notes [tiedIn] from the bar before, and the staff's [key].
///
/// Heads are read in time order, grace notes before the chords they
/// ornament. An alteration holds at its written staff position until the
/// barline. A note tied in from the previous bar prints nothing and leaves
/// the state alone, so the next note at that position reprints.
///
/// [request] decides each head's request in that order, after the heads
/// before it, which is how import recovers the requests a file prints.
Map<NoteId, AccidentalMark> foldAccidentals(
  List<AccidentalHead> heads,
  Map<NoteId, Pitch> written,
  Set<NoteId> tiedIn,
  KeySignature key, {
  AccidentalRequestOf request = _stated,
}) {
  final ordered = stableSorted(heads, (a, b) {
    final byOnset = a.onset.compareTo(b.onset);
    if (byOnset != 0) {
      return byOnset;
    }
    return a.grace == b.grace ? 0 : (a.grace ? -1 : 1);
  });
  var inForce = Alterations(key);
  final marks = <NoteId, AccidentalMark>{};
  for (final AccidentalHead(:note) in ordered) {
    if (note is! PitchedNote) {
      continue;
    }
    final pitch = written[note.id]!;
    final tied = tiedIn.contains(note.id);
    final autoPrints = !tied && pitch.alter != inForce.at(pitch.diatonic);
    final asked = request(note, autoPrints: autoPrints);
    if (!holdsAlteration(asked, tiedIn: tied)) {
      continue;
    }
    if (asked != AccidentalRequest.auto || autoPrints) {
      marks[note.id] = AccidentalMark(
        pitch.alter,
        cautionary: asked == AccidentalRequest.cautionary,
      );
    }
    inForce = inForce.after(pitch);
  }
  return marks;
}
