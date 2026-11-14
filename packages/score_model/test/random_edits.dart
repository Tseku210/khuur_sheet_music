import 'dart:math';

import 'package:score_model/score_model.dart';

import 'support.dart';

/// Everything layout reads from [view] but the bar number, as one string
/// to compare.
String describeView(MeasureView view) => [
  view.meterChanged,
  view.keyChanged,
  view.printsMeter,
  view.printsKey,
  view.meterCourtesy,
  view.keyCourtesy,
  _key(view.previousKey),
  view.voltaStarts,
  view.voltaEnds,
  view.isRestOnly,
  for (final s in view.spanners)
    (s.spanner.id, s.from, s.to, s.startsHere, s.endsHere),
  for (final staff in view.staves) ...[
    staff.source.staff,
    staff.clefChanged,
    _key(staff.writtenKey),
    for (final MapEntry(:key, :value) in staff.accidentals.entries)
      (key, value.alter, value.cautionary),
    for (final tie in staff.ties)
      (
        tie.from,
        tie.to?.event.id,
        tie.to?.event.measure,
        tie.to?.note,
        tie.crossesBarline,
      ),
    staff.tiedIn,
    for (final MapEntry(:key, :value) in staff.writtenPitches.entries)
      (key, value),
    for (final voice in staff.voices) ...[
      voice.slot,
      for (final e in voice.events) (e.event.id, e.onset, e.duration),
      for (final b in voice.beams) (b.events, b.secondaryBreaks),
      for (final t in voice.tuplets)
        (t.tuplet.id, t.onset, t.duration, t.events, t.depth),
    ],
  ],
].join(' | ');

(int, KeyMode)? _key(KeySignature? key) =>
    key == null ? null : (key.fifths, key.mode);

T pick<T>(Random random, List<T> options) =>
    options[random.nextInt(options.length)];

/// [score] after [edit], or as it was when the edit is refused. Throws when
/// the edit leaves two things of a kind with one id, which no file may
/// hold, or a score that does not load from its own JSON, since an app
/// that saved it would lose the piece. Throws too when a rippled edit
/// changes the dynamic in force after the bars it changed, since the rest
/// of the piece would play at another level, or the clef a note starts in
/// while the note keeps its length.
Score edited(Score score, Edit edit) {
  final outcome = EditSession.start(score).run(edit);
  if (outcome is! Applied) {
    return score;
  }
  final next = outcome.session.score;
  final repeated = repeatedIds(next);
  if (repeated.isNotEmpty) {
    throw StateError('${edit.runtimeType} repeats ${repeated.join(', ')}');
  }
  try {
    reloaded(next);
  } on ScoreFormatException catch (error) {
    throw StateError(
      '${edit.runtimeType} left a score that does not load: $error',
    );
  }
  final rippled = switch (edit) {
    EnterNote(:final ripple) ||
    EnterRest(:final ripple) ||
    SetValue(:final ripple) ||
    Erase(:final ripple) => ripple != Ripple.none,
    _ => false,
  };
  if (rippled) {
    final clefs = _clefsOf(next);
    for (final MapEntry(key: note, value: (clef, length)) in _clefsOf(
      score,
    ).entries) {
      if (clefs[note] case (final now, final span)
          when span == length && now != clef) {
        throw StateError('${edit.runtimeType} changed the clef of a note');
      }
    }
    for (final staff in score.staves) {
      if (_dynamicAfterChanged(score, next, staff.id)) {
        throw StateError(
          '${edit.runtimeType} changed the dynamic in force after it',
        );
      }
    }
  }
  return next;
}

/// The clef each note of [score] starts in, with the note's length. An
/// erase can cut a note short from its start, and what is left may start
/// in another clef.
Map<(StaffId, EventId), (Clef, Length)> _clefsOf(Score score) {
  final bars = {for (final column in score.measures) column.id: column};
  return {
    for (final staff in score.staves)
      for (final slot in VoiceSlot.values)
        for (final timed in score.laneOf(staff.id, slot))
          if (timed.event is ChordEvent)
            (staff.id, timed.event.id): (
              bars[timed.ref.measure]!.staff(staff.id).clefAt(timed.onset),
              timed.duration,
            ),
  };
}

/// The dynamics of [staff] in each bar of [score], in order.
List<List<Dynamic>> _dynamicsOf(Score score, StaffId staff) => [
  for (final column in score.measures)
    [
      for (final direction in column.staff(staff).directions)
        if (direction is DynamicMark) direction.level,
    ],
];

/// Whether [staff]'s last dynamic before the bars that [before] and [after]
/// both end with differs between them: the one in force where those bars
/// start. A staff that lost a dynamic is passed over, since an erase takes
/// the marks in the time it removes.
bool _dynamicAfterChanged(Score before, Score after, StaffId staff) {
  final was = _dynamicsOf(before, staff);
  final now = _dynamicsOf(after, staff);
  if (now.expand((bar) => bar).length < was.expand((bar) => bar).length) {
    return false;
  }
  var kept = 0;
  while (kept < was.length &&
      kept < now.length &&
      identical(
        before.measures[was.length - 1 - kept],
        after.measures[now.length - 1 - kept],
      )) {
    kept++;
  }
  Dynamic? last(List<List<Dynamic>> bars) =>
      bars.take(bars.length - kept).expand((bar) => bar).lastOrNull;
  return last(was) != last(now);
}

/// Each id of [score] that two things of its kind share, as `event 6`. The
/// kinds are the ones `scoreFromJson` tells apart.
List<String> repeatedIds(Score score) {
  final events = [
    for (final column in score.measures)
      for (final staff in column.staves)
        for (final voice in staff.voices) ..._flat(voice.items),
  ];
  final chords = events.whereType<ChordEvent>();
  final ids = {
    'part': [for (final part in score.parts) part.id.value],
    'staff': [for (final staff in score.staves) staff.id.value],
    'measure': [for (final column in score.measures) column.id.value],
    'event': [
      for (final event in events) event.id.value,
      for (final chord in chords)
        for (final grace in chord.graces) grace.id.value,
    ],
    'note': [
      for (final chord in chords) ...[
        for (final note in chord.notes) note.id.value,
        for (final grace in chord.graces)
          for (final note in grace.notes) note.id.value,
      ],
    ],
    'tuplet': [
      for (final column in score.measures)
        for (final staff in column.staves)
          for (final voice in staff.voices)
            for (final tuplet in _tuplets(voice.items)) tuplet.id.value,
    ],
    'spanner': [for (final spanner in score.spanners) spanner.id.value],
  };
  return [
    for (final MapEntry(key: kind, value: list) in ids.entries)
      for (final id in _repeats(list)) '$kind $id',
  ];
}

Set<int> _repeats(List<int> ids) {
  final seen = <int>{};
  return {
    for (final id in ids)
      if (!seen.add(id)) id,
  };
}

Iterable<Tuplet> _tuplets(Iterable<VoiceItem> items) => items
    .whereType<Tuplet>()
    .expand((tuplet) => [tuplet, ..._tuplets(tuplet.members)]);

/// Every event of [score], tuplet members included, with a reference to it.
List<(EventRef, Event)> _eventsOf(Score score) => [
  for (final column in score.measures)
    for (final staff in column.staves)
      for (final voice in staff.voices)
        for (final event in _flat(voice.items))
          (
            EventRef(measure: column.id, staff: staff.staff, id: event.id),
            event,
          ),
];

Iterable<Event> _flat(Iterable<VoiceItem> items) => items.expand(
  (item) => switch (item) {
    Event() => [item],
    Tuplet(:final members) => _flat(members),
    Gap() => const <Event>[],
  },
);

List<(EventRef, ChordEvent)> _chordsOf(Score score) => [
  for (final (ref, event) in _eventsOf(score))
    if (event is ChordEvent) (ref, event),
];

typedef _Head = ({NoteRef ref, Note note, Instrument instrument});

List<_Head> _headsOf(Score score) => [
  for (final (event, chord) in _chordsOf(score))
    for (final note in chord.notes)
      (
        ref: NoteRef(event, note.id),
        note: note,
        instrument: score.partOf(event.staff).instrument,
      ),
];

bool _pitched(_Head head) => head.note is PitchedNote;

/// The edits of one note head, each with the heads it applies to: a drum
/// head takes only a tie, and only a string instrument's head a string.
/// [SetAccidental] is listed twice so its four requests each come up.
final List<
  ({bool Function(_Head head) takes, Edit Function(_Head, Random) make})
>
_headEdits = [
  (
    takes: (_) => true,
    make: (head, random) => SetTie(head.ref, tied: random.nextInt(4) > 0),
  ),
  for (var k = 0; k < 2; k++)
    (
      takes: _pitched,
      make: (head, random) =>
          SetAccidental(head.ref, pick(random, AccidentalRequest.values)),
    ),
  (
    takes: _pitched,
    make: (head, random) =>
        SetFingering(head.ref, pick(random, [null, 0, 1, 2, 3, 4])),
  ),
  (
    takes: (head) => _pitched(head) && head.instrument.strings.isNotEmpty,
    make: (head, random) => SetString(
      head.ref,
      pick(random, [
        null,
        for (final (s, _) in head.instrument.strings.indexed) s,
      ]),
    ),
  ),
];

/// The quarter-note offsets inside [column], so that a point drawn from
/// them lies in the bar whatever its meter or pickup length.
List<Moment> _beatsIn(MeasureColumn column) => [
  for (var k = 0; at(k, 4) < Moment.zero + column.length; k++) at(k, 4),
];

/// A tone [staff] takes: a drum of its part's kit, or a pitch.
Tone _toneFor(Score score, StaffId staff, Random random) {
  final kit = score.partOf(staff).instrument.drums;
  return kit.isEmpty
      ? Pitch.parse(pick(random, ['F4', 'F#4', 'Bb4', 'E5']))
      : Drum(pick(random, kit).name);
}

/// Text as a composer might type it: Latin, Cyrillic, CJK, empty, and
/// characters markup must escape.
const _texts = ['dolce', 'Тайван', '月', '', 'a < b & "c"'];

StaffDirection _direction(Moment offset, Random random) =>
    switch (random.nextInt(3)) {
      0 => DynamicMark(offset, pick(random, Dynamic.values)),
      1 => TextMark(offset, pick(random, _texts), above: random.nextBool()),
      _ => ChordSymbol(
        offset,
        root: PitchName(
          pick(random, Step.values),
          pick(random, [Alter.natural, Alter.flat, Alter.sharp]),
        ),
        quality: pick(random, ['', 'm7', 'sus4', 'ø']),
        bass: random.nextBool() ? null : PitchName(pick(random, Step.values)),
      ),
    };

SetLyric _lyric(EventRef event, Random random) {
  final verse = 1 + random.nextInt(2);
  return SetLyric(
    event,
    verse,
    random.nextInt(4) == 0
        ? null
        : Lyric(
            verse: verse,
            text: pick(random, _texts),
            syllabic: pick(random, Syllabic.values),
            extend: random.nextBool(),
          ),
  );
}

/// One random edit of the kinds a composer makes: note entry (the common
/// case, overwriting or rippling), rippled value changes and deletes,
/// tuplets, chords, graces, event and note marks, beams, lyrics,
/// voltas, keys, clefs, spanners, directions, tempo marks, barlines,
/// repeats, navigation and rehearsal marks, inserted and deleted bars, bar
/// lengths, meters, erased, pasted and transposed ranges, breaks, signature
/// displays, and adding, removing, hiding and showing parts.
///
/// A rippled value change or delete takes time out of every staff and
/// voice of its part, and the music in that time with it. The two share
/// one case, and value changes go to chords only, so that the walks keep
/// the music and marks the layout tests count.
Score randomEdit(Score score, Random random) {
  final bar = random.nextInt(score.measures.length);
  final id = score.measures[bar].id;
  final beats = _beatsIn(score.measures[bar]);
  switch (random.nextInt(36)) {
    case 0 || 1 || 2:
      final staff = pick(random, score.staves).id;
      return edited(
        score,
        EnterNote(
          at: VoicePoint(
            staff: staff,
            voice: pick(random, [VoiceSlot.one, VoiceSlot.two]),
            at: ScorePoint(id, at(random.nextInt(8), 8)),
          ),
          tone: _toneFor(score, staff, random),
          value: pick(random, [
            NoteValue.eighth,
            NoteValue.sixteenth,
            NoteValue.quarter,
            NoteValue.quarter.dotted,
            NoteValue.half,
          ]),
          beam: random.nextInt(3) == 0
              ? pick(random, BeamMode.values)
              : BeamMode.auto,
          appendBar: random.nextInt(4) > 0,
          ripple: pick(random, Ripple.values),
        ),
      );
    case 3:
      final last = score.measures[min(bar + 1, score.measures.length - 1)];
      return edited(
        score,
        SetVolta(
          id,
          last.id,
          pick(random, [
            null,
            const Volta([1]),
            const Volta([2]),
          ]),
        ),
      );
    case 4:
      return edited(
        score,
        SetKey(
          from: id,
          key: KeySignature(
            random.nextInt(5) - 2,
            pick(random, KeyMode.values),
          ),
        ),
      );
    case 5:
      return edited(
        score,
        SetClef(
          staff: pick(random, score.staves).id,
          at: ScorePoint(id, at(random.nextInt(4), 4)),
          clef: pick(random, [Clef.treble, Clef.bass, Clef.alto]),
        ),
      );
    case 6 || 7 || 8 || 9:
      if (score.spanners.isNotEmpty && random.nextInt(4) == 0) {
        return edited(
          score,
          RemoveSpanner(pick(random, score.spanners.toList()).id),
        );
      }
      final ends = [
        for (final index in [
          random.nextInt(score.measures.length),
          random.nextInt(score.measures.length),
        ])
          (index, pick(random, _beatsIn(score.measures[index]))),
      ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.compareTo(b.$2));
      return edited(
        score,
        AddSpanner(
          kind: switch (random.nextInt(7)) {
            0 => Slur(dashed: random.nextBool()),
            1 => OctaveLine(
              pick(random, [OctaveShift.up8, OctaveShift.down8]),
            ),
            2 => Hairpin(crescendo: random.nextBool()),
            3 => const PedalLine(),
            4 => const TrillLine(),
            5 => const Glissando(),
            _ => TempoLine(
              text: pick(random, ['rit.', ..._texts]),
              factor: pick(random, [0.5, 0.75, 4 / 3]),
            ),
          },
          staff: pick(random, score.staves).id,
          voice: pick(random, [null, VoiceSlot.one, VoiceSlot.two]),
          first: pointAt(score, ends[0].$1, ends[0].$2),
          last: pointAt(score, ends[1].$1, ends[1].$2),
        ),
      );
    case 10:
      if (score.measures.length > 3 && random.nextBool()) {
        final last = score.measures[min(bar + 1, score.measures.length - 1)];
        return edited(score, DeleteMeasures(id, last.id));
      }
      return edited(
        score,
        InsertMeasures(
          before: random.nextBool() ? id : null,
          count: 1 + random.nextInt(2),
        ),
      );
    case 11:
      return edited(
        score,
        SetBarLength(id, pick(random, [null, len(1, 4), len(3, 8), len(5, 4)])),
      );
    case 12:
      return edited(
        score,
        SetMeter(
          from: id,
          meter: pick(random, const [
            Meter.fourFour,
            Meter.threeFour,
            Meter.twoFour,
            Meter.sixEight,
          ]),
          content: pick(random, MeterContent.values),
        ),
      );
    case 13:
      final last = min(bar + random.nextInt(2), score.measures.length - 1);
      return edited(
        score,
        Erase(
          RangeSelection(
            from: ScorePoint(id, at(random.nextInt(4), 4)),
            to: pointAt(score, last, at(1 + random.nextInt(4), 4)),
            top: pick(random, score.staves).id,
            bottom: pick(random, score.staves).id,
          ),
          ripple: pick(random, Ripple.values),
        ),
      );
    case 14:
      final last = min(bar + random.nextInt(2), score.measures.length - 1);
      final clip = EditSession.start(score)
          .select(
            RangeSelection(
              from: ScorePoint(id, at(random.nextInt(4), 4)),
              to: pointAt(score, last, at(1 + random.nextInt(4), 4)),
              top: pick(random, score.staves).id,
              bottom: pick(random, score.staves).id,
            ),
          )
          .copy();
      return clip == null
          ? score
          : edited(
              score,
              Paste(
                clip,
                at: VoicePoint(
                  staff: pick(random, score.staves).id,
                  voice: VoiceSlot.one,
                  at: ScorePoint(
                    score.measures[random.nextInt(score.measures.length)].id,
                    at(random.nextInt(4), 4),
                  ),
                ),
              ),
            );
    case 15:
      final last = min(bar + random.nextInt(2), score.measures.length - 1);
      return edited(
        score,
        Transpose(
          RangeSelection(
            from: ScorePoint(id, at(random.nextInt(4), 4)),
            to: pointAt(score, last, at(1 + random.nextInt(4), 4)),
            top: pick(random, score.staves).id,
            bottom: pick(random, score.staves).id,
          ),
          pick(random, const [
            Transposition.interval(Interval.majorSecond),
            Transposition.diatonic(-2),
            Transposition.chromatic(1),
          ]),
        ),
      );
    case 16:
      return edited(score, switch (random.nextInt(3)) {
        0 => SetBreak(id, pick(random, [null, ...LayoutBreak.values])),
        1 => SetKeyDisplay(id, pick(random, SignatureDisplay.values)),
        _ => SetMeterDisplay(id, pick(random, SignatureDisplay.values)),
      });
    case 17 || 18:
      final part = score.parts[random.nextInt(score.parts.length)];
      return edited(score, switch (random.nextInt(5)) {
        0 => SetPartHidden(part.id, hidden: !part.hidden),
        1 || 2 => AddPart(
          pick(random, const [morinKhuur, clarinet, piano, drums]),
          index: random.nextInt(score.parts.length + 1),
        ),
        3 => SetInstrument(
          part.id,
          part.instrument.isPercussion
              ? pick(random, const [drums, bigKit])
              : pick(random, const [morinKhuur, clarinet, piano]),
        ),
        _ => RemovePart(part.id),
      });
    case 19:
      return edited(
        score,
        EnterTuplet(
          at: VoicePoint(
            staff: pick(random, score.staves).id,
            voice: pick(random, [VoiceSlot.one, VoiceSlot.two]),
            at: ScorePoint(id, pick(random, beats)),
          ),
          ratio: pick(random, const [
            TupletRatio.triplet,
            TupletRatio.duplet,
            TupletRatio.quintuplet,
          ]),
          unit: pick(random, [
            NoteValue.eighth,
            NoteValue.sixteenth,
            NoteValue.quarter,
          ]),
        ),
      );
    case 20 || 21:
      final (event, _) = pick(random, _eventsOf(score));
      return edited(
        score,
        AddToChord(event: event, tone: _toneFor(score, event.staff, random)),
      );
    case 22 || 23 || 24 || 25:
      final chords = _chordsOf(score);
      final event = chords.isEmpty
          ? pick(random, _eventsOf(score)).$1
          : pick(random, chords).$1;
      return edited(score, switch (random.nextInt(6)) {
        0 => AddGrace(
          event: event,
          tone: _toneFor(score, event.staff, random),
          kind: pick(random, GraceKind.values),
          value: pick(random, [NoteValue.eighth, NoteValue.sixteenth]),
        ),
        1 => SetArticulation(
          event,
          pick(random, Articulation.values),
          present: random.nextInt(4) > 0,
        ),
        2 => SetOrnament(event, pick(random, [null, ...Ornament.values])),
        3 => SetBowing(event, pick(random, [null, ...Bowing.values])),
        4 => SetBeam(event, pick(random, BeamMode.values)),
        _ => _lyric(event, random),
      });
    case 26 || 27 || 28 || 29:
      final (:takes, :make) = pick(random, _headEdits);
      final heads = _headsOf(score).where(takes).toList();
      return heads.isEmpty
          ? score
          : edited(score, make(pick(random, heads), random));
    case 30:
      return edited(
        score,
        SetDirections(
          staff: pick(random, score.staves).id,
          measure: id,
          directions: Seq([
            for (var n = random.nextInt(4); n > 0; n--)
              _direction(pick(random, beats), random),
          ]),
        ),
      );
    case 31 || 32 || 33:
      return edited(score, switch (random.nextInt(5)) {
        0 => SetBarline(id, pick(random, Barline.values)),
        1 => SetRepeatStart(id, start: random.nextBool()),
        2 => SetRepeatEnd(
          id,
          pick(random, const [null, RepeatEnd(), RepeatEnd(times: 3)]),
        ),
        3 => SetNavigation(
          id,
          Seq(
            pick(random, const <List<NavigationMark>>[
              [],
              [Segno()],
              [Coda()],
              [ToCoda()],
              [Fine()],
              [Segno(), Fine()],
              [Jump(JumpTarget.start)],
              [Jump(JumpTarget.segno, then: JumpThen.toCoda)],
              [Jump(JumpTarget.start, then: JumpThen.toFine, text: 'Да капо')],
            ]),
          ),
        ),
        _ => SetRehearsal(id, pick(random, [null, '', 'A', 'B2', 'Б'])),
      });
    case 35:
      final chords = _chordsOf(score);
      if (chords.isNotEmpty && random.nextBool()) {
        return edited(
          score,
          SetValue(
            pick(random, chords).$1,
            pick(random, [
              NoteValue.eighth,
              NoteValue.quarter,
              NoteValue.quarter.dotted,
              NoteValue.half,
            ]),
            ripple: Ripple.part,
          ),
        );
      }
      final (event, _) = pick(random, _eventsOf(score));
      return edited(
        score,
        Erase(ItemSelection(Seq([event])), ripple: Ripple.part),
      );
    default:
      return edited(
        score,
        SetTempoMarks(
          id,
          Seq([
            for (final beat in beats)
              if (random.nextInt(3) == 0)
                TempoMark(
                  offset: beat,
                  tempo: Tempo(
                    pick(random, [60, 96.5, 132]),
                    beat: pick(random, [
                      NoteValue.quarter,
                      NoteValue.quarter.dotted,
                      NoteValue.half,
                      NoteValue.eighth,
                    ]),
                  ),
                  text: pick(random, [null, ..._texts]),
                  showMetronome: random.nextBool(),
                ),
          ]),
        ),
      );
  }
}
