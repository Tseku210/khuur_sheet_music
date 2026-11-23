/// The score root: parts, the global column list, and cross-bar spanners.
library;

import 'dart:math';

import 'empty_bar.dart';
import 'events.dart';
import 'measure.dart';
import 'measure_view.dart';
import 'pitch.dart';
import 'refs.dart';
import 'rules.dart';
import 'seq.dart';
import 'stable_sort.dart';
import 'time.dart';
import 'views.dart';
import 'voice_walk.dart';

/// What is wrong with how the pieces of a score fit together, or null.
///
/// Checked in debug builds only. `scoreFromJson` refuses the same always,
/// and edits keep it by construction.
String? _shapeProblem(
  Seq<Part> parts,
  Seq<MeasureColumn> measures,
  Seq<Spanner> spanners,
) {
  final staves = [
    for (final part in parts)
      for (final staff in part.staves) staff.id,
  ];
  final indexOf = <MeasureId, int>{};
  for (final (index, column) in measures.indexed) {
    if (indexOf.containsKey(column.id)) {
      return 'measure id ${column.id} is used twice';
    }
    indexOf[column.id] = index;
    final listed = [for (final staff in column.staves) staff.staff];
    if (listed.length != staves.length ||
        listed.indexed.any((staff) => staves[staff.$1] != staff.$2)) {
      return 'bar ${index + 1} does not list the staves of the parts in '
          'system order';
    }
  }
  for (final spanner in spanners) {
    final first = indexOf[spanner.first.measure];
    final last = indexOf[spanner.last.measure];
    if (first == null || last == null || !staves.contains(spanner.staff)) {
      return 'spanner ${spanner.id} names a bar or staff the score lacks';
    }
    if (first > last ||
        first == last && spanner.first.offset > spanner.last.offset) {
      return 'spanner ${spanner.id} ends before it starts';
    }
  }
  return null;
}

/// An immutable score.
///
/// Three children, each owning one kind of fact:
/// - [parts]: who plays (instruments, staves, visibility).
/// - [measures]: what is played, bar by bar. Every bar-level fact and every
///   event lives inside exactly one [MeasureColumn].
/// - [spanners]: marks that cross barlines (slurs, hairpins, 8va lines,
///   pedal, trill lines), anchored to [ScorePoint]s.
///
/// Ties are not spanners: a tie always joins adjacent events of one voice, so
/// it is a flag on the starting [Note] and its end is derived.
///
/// Equality is identity. Two scores are "the same" only if they are the same
/// object; comparing subtrees by identity is how [changesSince] works.
final class Score {
  /// A score from its children. Debug builds assert that it has a part and
  /// a bar, that bar ids are unique, that every bar lists the staves of
  /// [parts] in system order, and that every spanner names a bar and staff
  /// of the score and does not end before it starts.
  Score({
    required ScoreMeta meta,
    required Seq<Part> parts,
    required Seq<MeasureColumn> measures,
    Seq<Spanner> spanners = const Seq.empty(),
  }) : this._(
         _Places(),
         meta: meta,
         parts: parts,
         measures: measures,
         spanners: spanners,
       );

  Score._(
    this._places, {
    required this.meta,
    required this.parts,
    required this.measures,
    required this.spanners,
  }) : assert(parts.isNotEmpty, 'a score has at least one part'),
       assert(measures.isNotEmpty, 'a score has at least one measure'),
       assert(
         _shapeProblem(parts, measures, spanners) == null,
         _shapeProblem(parts, measures, spanners),
       );

  /// A score with [parts], [measureCount] empty bars of [meter] in [key], and
  /// a tempo mark at the start. Ids are allocated 1, 2, 3… in document order,
  /// so two blank scores built with the same arguments are identical in
  /// content and ids. Throws [ArgumentError] for no part or no bar, a template
  /// with no staff or a clef list of another length, or a value a saved score
  /// may not hold.
  factory Score.blank({
    required List<PartTemplate> parts,
    String title = '',
    int measureCount = 16,
    Meter meter = Meter.fourFour,
    KeySignature key = KeySignature.cMajor,
    Tempo tempo = Tempo.unmarked,
  }) {
    final problem = [
      if (parts.isEmpty) 'a score has at least one part',
      if (measureCount < 1) 'a score has at least one measure',
      ?meterProblem(meter),
      ?keyProblem(key.fifths),
      ?tempoMarkProblem(tempo),
      for (final part in parts) ?templateProblem(part),
    ].firstOrNull;
    if (problem != null) {
      throw ArgumentError(problem);
    }
    var next = 1;
    final built = <Part>[];
    final clefs = <(StaffId, Clef)>[];
    for (final template in parts) {
      final id = PartId(next++);
      final staves = <Staff>[];
      for (var i = 0; i < template.staves; i++) {
        final staff = Staff(id: StaffId(next++));
        staves.add(staff);
        clefs.add((staff.id, template.clefs?[i] ?? template.instrument.clef));
      }
      built.add(
        Part(
          id: id,
          name: template.name,
          shortName: template.shortName,
          instrument: template.instrument,
          staves: Seq(staves),
        ),
      );
    }
    return Score(
      meta: ScoreMeta(title: title),
      parts: Seq(built),
      measures: Seq([
        for (var bar = 0; bar < measureCount; bar++)
          emptyBar(
            id: MeasureId(next++),
            meter: meter,
            key: key,
            clefs: clefs,
            restId: () => EventId(next++),
            tempos: bar == 0
                ? Seq([TempoMark(offset: Moment.zero, tempo: tempo)])
                : const Seq.empty(),
          ),
      ]),
    );
  }

  /// Title and credits.
  final ScoreMeta meta;

  /// The parts, top to bottom in system order. Never empty.
  final Seq<Part> parts;

  /// The global, ordered list of bars. Bar *numbers* are derived from
  /// position; bar *identity* is [MeasureColumn.id].
  final Seq<MeasureColumn> measures;

  /// Cross-bar marks, in no particular order.
  final Seq<Spanner> spanners;

  /// Replaces children. Everything not passed is shared with this score.
  Score copyWith({
    ScoreMeta? meta,
    Seq<Part>? parts,
    Seq<MeasureColumn>? measures,
    Seq<Spanner>? spanners,
  }) => Score._(
    measures == null || identical(measures, this.measures)
        ? _places
        : _Places(),
    meta: meta ?? this.meta,
    parts: parts ?? this.parts,
    measures: measures ?? this.measures,
    spanners: spanners ?? this.spanners,
  );

  /// Staves in system order: parts top to bottom, then each part's staves
  /// top to bottom. Every column's `staves` follows this order.
  late final List<Staff> staves = [for (final part in parts) ...part.staves];

  /// Where the place of each bar by its id is kept once it is built. A
  /// copy with the same bars, and one that [replacingBars] makes, shares it,
  /// so an edit that writes bars many times over builds the index once and
  /// not once for each copy.
  final _Places _places;

  Map<MeasureId, int> get _indexById => _places.byId ??= {
    for (var i = 0; i < measures.length; i++) measures[i].id: i,
  };

  /// Position of [id] in [measures]. Throws if [id] is not in this score.
  int indexOf(MeasureId id) =>
      _indexById[id] ??
      (throw ArgumentError.value(id, 'id', 'no such measure'));

  /// Whether bar [id] is in this score.
  bool contains(MeasureId id) => _indexById.containsKey(id);

  /// The printed number of bar [id]. Bars count from 1. A first bar shorter
  /// than its meter is a pickup and is numbered 0, so the bar after it is 1.
  /// Throws if [id] is not in this score.
  int barNumberOf(MeasureId id) {
    final first = measures.first;
    return indexOf(id) + (first.length < first.meter.length ? 0 : 1);
  }

  /// Bar [id]. Throws if [id] is not in this score.
  MeasureColumn column(MeasureId id) => measures[indexOf(id)];

  /// The part that holds [staff]. Throws if no part does.
  Part partOf(StaffId staff) {
    for (final part in parts) {
      if (part.staves.any((s) => s.id == staff)) {
        return part;
      }
    }
    throw ArgumentError.value(staff, 'staff', 'no such staff');
  }

  /// Resolves a reference. Null when the event no longer exists (a stale
  /// selection after undo, for instance).
  ///
  /// [EventRef.measure] is a hint, not part of the identity. The fast path
  /// is one map lookup plus a walk of one staff of one measure. When the
  /// event is not in the hinted measure (a meter change re-barred it into
  /// a neighbour), the lookup falls back to [locate]. The result's `ref`
  /// always carries the current measure, so a caller that stores it gets
  /// the fast path next time.
  TimedEvent? lookup(EventRef ref) {
    final hit = _find(ref);
    if (hit != null) {
      return hit;
    }
    final located = locate(ref.id);
    return located == null ? null : _find(located);
  }

  TimedEvent? _find(EventRef ref) {
    final staff = _staffMeasure(ref.measure, ref.staff);
    if (staff == null) {
      return null;
    }
    for (final voice in staff.voices) {
      for (final timed in timedEvents(
        voice,
        measure: ref.measure,
        staff: ref.staff,
      )) {
        if (timed.event.id == ref.id) {
          return timed;
        }
      }
    }
    return null;
  }

  StaffMeasure? _staffMeasure(MeasureId measure, StaffId staff) {
    final index = _indexById[measure];
    if (index == null) {
      return null;
    }
    return measures[index].staves.where((s) => s.staff == staff).firstOrNull;
  }

  /// Where [id] lives in this score, or null when it does not exist.
  ///
  /// Backed by an index from event id to measure id, built lazily on the
  /// first miss for this score value (one pass over every event, about
  /// 16k at 500 bars and 4 staves). Only re-barring moves events between
  /// measures, so ordinary editing never builds it.
  EventRef? locate(EventId id) => _refById[id];

  late final Map<EventId, EventRef> _refById = {
    for (final column in measures)
      for (final staff in column.staves)
        for (final voice in staff.voices)
          for (final timed in timedEvents(
            voice,
            measure: column.id,
            staff: staff.staff,
          ))
            timed.event.id: timed.ref,
  };

  /// The event whose sounding time covers [at] in that voice, or null when
  /// the voice is absent or the point falls in a gap.
  TimedEvent? eventAt(VoicePoint at) {
    final voice = _staffMeasure(at.at.measure, at.staff)?.voice(at.voice);
    if (voice == null) {
      return null;
    }
    final offset = at.at.offset;
    return timedEvents(voice, measure: at.at.measure, staff: at.staff)
        .where((e) => e.onset <= offset && offset < e.onset + e.duration)
        .firstOrNull;
  }

  /// The events of [voice] on [staff] in every bar, in score order. Each
  /// [TimedEvent.onset] counts from the start of the bar that
  /// [TimedEvent.ref] names. A bar where the voice is absent adds nothing,
  /// and gaps are skipped. Walks only that voice, so it is much cheaper than
  /// building a [measureView] per bar. Throws if [staff] is not in this
  /// score.
  Iterable<TimedEvent> laneOf(StaffId staff, VoiceSlot voice) sync* {
    for (final column in measures) {
      if (column.staff(staff).voice(voice) case final lane?) {
        yield* timedEvents(lane, measure: column.id, staff: staff);
      }
    }
  }

  /// The event before [timed] in its staff and voice, skipping gaps. It is
  /// the one before in the bar of [timed], or the last of the voice in the
  /// bar before when [timed] opens its bar. Null at the start of the score,
  /// and where the bar before has no such voice or no event in it. Reads
  /// only those two bars.
  TimedEvent? eventBefore(TimedEvent timed) {
    final bar = indexOf(timed.ref.measure);
    TimedEvent? earlier;
    for (final event in _voiceEvents(bar, timed)) {
      if (event.ref == timed.ref) {
        break;
      }
      earlier = event;
    }
    return earlier ?? _voiceEvents(bar - 1, timed).lastOrNull;
  }

  /// The event after [timed] in its staff and voice, skipping gaps. It is
  /// the one after in the bar of [timed], or the first of the voice in the
  /// bar after when [timed] closes its bar. Null at the end of the score,
  /// and where the bar after has no such voice or no event in it. Reads only
  /// those two bars.
  TimedEvent? eventAfter(TimedEvent timed) {
    final bar = indexOf(timed.ref.measure);
    final later = _voiceEvents(
      bar,
      timed,
    ).skipWhile((event) => event.ref != timed.ref).skip(1);
    return later.firstOrNull ?? _voiceEvents(bar + 1, timed).firstOrNull;
  }

  /// The events of the voice and staff of [like] in the bar at index [bar],
  /// or nothing where this score has no such bar or the bar no such voice.
  Iterable<TimedEvent> _voiceEvents(int bar, TimedEvent like) sync* {
    if (bar < 0 || bar >= measures.length) {
      return;
    }
    final column = measures[bar];
    if (column.staff(like.ref.staff).voice(like.voice) case final lane?) {
      yield* timedEvents(lane, measure: column.id, staff: like.ref.staff);
    }
  }

  /// Orders two points in time: negative when [a] comes before [b], zero
  /// when they are the same point, positive when [a] comes after. Bars
  /// order by their place in [measures], not by their ids, and points in
  /// one bar order by offset. Throws if either bar is not in this score.
  int compare(ScorePoint a, ScorePoint b) {
    final byBar = indexOf(a.measure).compareTo(indexOf(b.measure));
    return byBar != 0 ? byBar : a.offset.compareTo(b.offset);
  }

  /// The events of [voice] on [staff] that start at or after [from] and
  /// before [to], in score order: the events a range selection from [from]
  /// to [to] takes from that voice. Reads only the bars from [from] to
  /// [to]. Empty when [to] does not come after [from]. Throws if [staff]
  /// or either bar is not in this score.
  Iterable<TimedEvent> laneBetween(
    StaffId staff,
    VoiceSlot voice,
    ScorePoint from,
    ScorePoint to,
  ) sync* {
    for (var bar = indexOf(from.measure); bar <= indexOf(to.measure); bar++) {
      final column = measures[bar];
      if (column.staff(staff).voice(voice) case final lane?) {
        for (final timed in timedEvents(
          lane,
          measure: column.id,
          staff: staff,
        )) {
          final start = ScorePoint(column.id, timed.onset);
          if (compare(from, start) <= 0 && compare(start, to) < 0) {
            yield timed;
          }
        }
      }
    }
  }

  /// The staves from [a] to [b] in system order, whichever of the two comes
  /// first. Null when the score has either no longer.
  List<StaffId>? stavesBetween(StaffId a, StaffId b) {
    final order = [for (final staff in staves) staff.id];
    final first = order.indexOf(a);
    final last = order.indexOf(b);
    if (first == -1 || last == -1) {
      return null;
    }
    return first <= last
        ? order.sublist(first, last + 1)
        : order.sublist(last, first + 1);
  }

  /// The event sounding at [at] on [staff] in [voice], else in voice one.
  /// [anchorOf] gives the event an end of a spanner attaches to.
  TimedEvent? anchorAt(StaffId staff, VoiceSlot voice, ScorePoint at) =>
      eventAt(VoicePoint(staff: staff, voice: voice, at: at)) ??
      eventAt(VoicePoint(staff: staff, voice: VoiceSlot.one, at: at));

  /// Where a spanner of [SpannerReach.time] stops in its last bar: the end
  /// of the voice-one event its last point falls in. The line covers that
  /// event.
  Moment lineEnd(Spanner spanner) {
    final last = eventAt(
      VoicePoint(staff: spanner.staff, voice: VoiceSlot.one, at: spanner.last),
    )!;
    return last.onset + last.duration;
  }

  /// Where [spanner] stops in its last bar: [lineEnd] for a spanner of
  /// [SpannerReach.time], its last point for one of [SpannerReach.events].
  Moment endOf(Spanner spanner) => switch (spanner.kind.reach) {
    SpannerReach.events => spanner.last.offset,
    SpannerReach.time => lineEnd(spanner),
  };

  /// The event [spanner], of [SpannerReach.events], attaches to at its
  /// first end, or at its last when [last].
  ///
  /// An end of a [Glissando] that names a note is on the chord that holds
  /// the note, in whichever voice sounds it at that end. The last end of a
  /// [Slur] that names a voice ([Slur.endVoice]) is on the chord that voice
  /// sounds there, when that chord starts after the event the slur starts
  /// on. Every other end, and one whose note or voice sounds no such chord
  /// there, is on the event of the spanner's voice, or of voice one when
  /// that voice has none there.
  ///
  /// A last end that falls to an event voice one has held since before the
  /// event the spanner starts on would run the line backward. It is on the
  /// chord another voice starts at that end instead, the first such voice,
  /// and on the event of voice one only when there is none. Voice one has
  /// held its event since before that event when the event at the end, or
  /// an event it is tied from through any number of ties and barlines,
  /// starts before it. For a [Glissando], which may not end on an event
  /// that starts with its first, starting with that event counts too. A
  /// line that starts on the held note itself ends on voice one's event.
  ///
  /// The last end of a [Glissando] that starts on a note, names no last
  /// note and would fall on a rest is on the first chord a voice of the
  /// staff starts there, in voice order from voice one. It stays on the rest
  /// when no voice starts a chord there.
  TimedEvent? anchorOf(Spanner spanner, {required bool last}) {
    final anchor = _anchorOf(spanner, last: last);
    if (spanner.kind case Glissando(to: null)
        when last &&
            anchor != null &&
            anchor.event is! ChordEvent &&
            _anchorOf(spanner, last: false)?.event is ChordEvent) {
      return _firstChordStartingAt(
            spanner.staff,
            spanner.last,
            VoiceSlot.values,
          ) ??
          anchor;
    }
    return anchor;
  }

  TimedEvent? _anchorOf(Spanner spanner, {required bool last}) {
    final at = last ? spanner.last : spanner.first;
    TimedEvent? sounding(VoiceSlot voice) =>
        eventAt(VoicePoint(staff: spanner.staff, voice: voice, at: at));
    switch (spanner.kind) {
      case Glissando(:final from, :final to):
        if (last ? to : from case final named?) {
          for (final slot in VoiceSlot.values) {
            final timed = sounding(slot);
            if (timed?.event case ChordEvent(:final notes)
                when notes.any((note) => note.id == named)) {
              return timed;
            }
          }
        }
      case Slur(:final endVoice?) when last:
        final timed = sounding(endVoice);
        final start = anchorOf(spanner, last: false);
        if (timed != null &&
            timed.event is ChordEvent &&
            (start == null || _startsAfter(timed, start))) {
          return timed;
        }
      default:
    }
    final own = sounding(spanner.voice ?? VoiceSlot.one);
    if (own != null) {
      return own;
    }
    final one = sounding(VoiceSlot.one);
    if (!last || one == null) {
      return one;
    }
    final start = anchorOf(spanner, last: false);
    if (start == null ||
        !_heldSince(one, start, orWith: spanner.kind is Glissando)) {
      return one;
    }
    return _firstChordStartingAt(spanner.staff, at, VoiceSlot.values.skip(1)) ??
        one;
  }

  TimedEvent? _firstChordStartingAt(
    StaffId staff,
    ScorePoint at,
    Iterable<VoiceSlot> voices,
  ) {
    for (final voice in voices) {
      final timed = eventAt(VoicePoint(staff: staff, voice: voice, at: at));
      if (timed != null &&
          timed.onset == at.offset &&
          timed.event is ChordEvent) {
        return timed;
      }
    }
    return null;
  }

  bool _startsAfter(TimedEvent event, TimedEvent other) =>
      compare(
        ScorePoint(event.ref.measure, event.onset),
        ScorePoint(other.ref.measure, other.onset),
      ) >
      0;

  /// Whether [held], or an event it is tied from, starts before [start],
  /// or with it when [orWith]. Not when [start] is itself one of those
  /// events, as the line then starts on the held note.
  bool _heldSince(
    TimedEvent held,
    TimedEvent start, {
    required bool orWith,
  }) {
    final bar = indexOf(start.ref.measure);
    for (TimedEvent? part = held; part != null; part = _tiedFrom(part)) {
      if (part.ref == start.ref) {
        return false;
      }
      final bars = indexOf(part.ref.measure) - bar;
      final order = bars != 0 ? bars : part.onset.compareTo(start.onset);
      if (order < 0 || (order == 0 && orWith)) {
        return true;
      }
    }
    return false;
  }

  /// The event [part] continues: the one before it in its voice that ends
  /// where [part] starts and ties a note to every note of [part]. Null when
  /// [part] starts a note of its own.
  TimedEvent? _tiedFrom(TimedEvent part) {
    final before = eventBefore(part);
    if (before == null) {
      return null;
    }
    final end = before.onset + before.duration;
    final joined = before.ref.measure == part.ref.measure
        ? end == part.onset
        : part.onset.isZero &&
              end == Moment.zero + column(before.ref.measure).length;
    if (!joined) {
      return null;
    }
    if ((before.event, part.event)
        case (
          ChordEvent(notes: final tied),
          ChordEvent(:final notes),
        )
        when notes.every(
          (note) => tied.any((from) => from.tie && from.tone == note.tone),
        )) {
      return before;
    }
    return null;
  }

  /// Whether [spanner] joins notes but starts and ends on one event.
  bool isCollapsed(Spanner spanner) =>
      spanner.kind.joinsNotes &&
      anchorOf(spanner, last: false)?.event.id ==
          anchorOf(spanner, last: true)?.event.id;

  /// The notes a glissando [spanner] starts and ends on, by
  /// [Glissando.notesOn] from the events [anchorOf] finds at its ends, or
  /// null where that end is on a rest. Both are null for a spanner that is
  /// not a glissando.
  ({Note? from, Note? to}) glissandoNotes(Spanner spanner) =>
      switch (spanner.kind) {
        final Glissando kind => kind.notesOn(
          anchorOf(spanner, last: false)?.event,
          anchorOf(spanner, last: true)?.event,
          instrument: partOf(spanner.staff).instrument,
        ),
        _ => (from: null, to: null),
      };

  /// Everything in effect at a point on a staff.
  ScoreContext contextAt(StaffId staff, ScorePoint at) {
    final index = indexOf(at.measure);
    final column = measures[index];
    final octaveLine = spannersTouching(at.measure)
        .where(
          (s) =>
              s.staff == staff &&
              s.kind is OctaveLine &&
              compare(s.first, at) <= 0 &&
              compare(at, ScorePoint(s.last.measure, endOf(s))) < 0,
        )
        .map((s) => s.kind)
        .whereType<OctaveLine>()
        .firstOrNull;
    return ScoreContext(
      clef: column.staff(staff).clefAt(at.offset),
      key: column.key,
      writtenKey: partOf(staff).instrument.writtenKey(column.key),
      meter: column.meter,
      tempo: _tempoAt(index, at.offset),
      octaveShift: octaveLine?.shift.octaves ?? 0,
    );
  }

  Tempo _tempoAt(int index, Moment offset) {
    for (var i = index; i >= 0; i--) {
      final mark = measures[i].tempos
          .where((mark) => i < index || mark.offset <= offset)
          .lastOrNull;
      if (mark != null) {
        return mark.tempo;
      }
    }
    return Tempo.unmarked;
  }

  /// What a tap at [staffStep] enters at [at] on [staff]. On a pitched
  /// staff it is the concert pitch: the clef gives the written letter and
  /// octave, the key gives the default alteration, an 8va line in effect
  /// shifts it, and the part's instrument transposition turns written into
  /// concert pitch. On a percussion staff it is the kit's first drum at that
  /// position, or null when none sits there.
  Tone? toneForStaffStep(StaffId staff, ScorePoint at, int staffStep) {
    final context = contextAt(staff, at);
    final natural = context.clef.naturalAt(staffStep);
    final instrument = partOf(staff).instrument;
    if (instrument.isPercussion) {
      return instrument.drums
          .where((sound) => sound.position.diatonic == natural.diatonic)
          .map((sound) => Drum(sound.name))
          .firstOrNull;
    }
    final written = Pitch(
      natural.step,
      natural.octave,
      context.writtenKey.alterFor(natural.step),
    );
    return written.transpose(
      Interval.octave * context.octaveShift + instrument.transposition,
      key: context.key,
    );
  }

  /// Everything layout needs to draw bar [id]. Cost is proportional to the
  /// bar's content plus the spanner count; it reads the previous column for
  /// printed changes and tie arrivals, and the next column for outgoing tie
  /// targets. For a slur, glissando or trill line that ends in the bar it
  /// may also read every bar from the one before the line's first, to find
  /// the events the line starts and ends on ([anchorOf]), at a cost
  /// proportional to the ties it follows back. No other measure is touched.
  MeasureView measureView(MeasureId id) => buildMeasureView(this, indexOf(id));

  /// Which measures' [MeasureView]s may differ from those of [previous].
  ///
  /// Works by identity. An edit rebuilds only the path from the root to what
  /// it touched, so every other column is the same object in both scores. A
  /// view reads its own column, both neighbours and the spanners touching it.
  /// So a bar is relaid out when it is new, when it or either neighbour is a
  /// different object than before, or when a spanner covering it was added
  /// or removed. The event a slur, glissando or trill line of more than one
  /// bar ends on can depend on every bar from the one before its first
  /// ([anchorOf]), and the note a glissando ends on depends on the chord it
  /// starts on, so the bar it ends in is relaid out when any of those is.
  /// Every bar is relaid out when the parts change or when bars that survive
  /// change order. [meta] is not compared.
  ScoreChanges changesSince(Score previous) {
    if (identical(previous, this)) {
      return ScoreChanges.none;
    }
    final removed = {
      for (final column in previous.measures)
        if (!contains(column.id)) column.id,
    };
    final everything = ScoreChanges(
      relayout: {for (final column in measures) column.id},
      removed: removed,
      reflow: true,
    );
    if (!identical(parts, previous.parts)) {
      return everything;
    }
    final relayout = <MeasureId>{};
    var reflow = measures.length != previous.measures.length;
    var lastSurvivor = -1;
    for (var i = 0; i < measures.length; i++) {
      final column = measures[i];
      final j = previous._indexById[column.id];
      if (j != i) {
        reflow = true;
      }
      if (j == null) {
        relayout.add(column.id);
        continue;
      }
      // A reorder can carry a bar into or out of an unchanged spanner's range
      // while its neighbours stay the same.
      if (j < lastSurvivor) {
        return everything;
      }
      lastSurvivor = j;
      if (column.breakBefore != previous.measures[j].breakBefore) {
        reflow = true;
      }
      if (!identical(column, previous.measures[j]) ||
          !identical(_columnAt(i - 1), previous._columnAt(j - 1)) ||
          !identical(_columnAt(i + 1), previous._columnAt(j + 1))) {
        relayout.add(column.id);
      }
    }
    if (!identical(spanners, previous.spanners)) {
      final now = Set<Spanner>.identity()..addAll(spanners);
      final before = Set<Spanner>.identity()..addAll(previous.spanners);
      for (final spanner in spanners) {
        if (!before.contains(spanner)) {
          relayout.addAll(_covered(spanner));
        }
      }
      for (final spanner in previous.spanners) {
        if (!now.contains(spanner)) {
          relayout.addAll(previous._covered(spanner).where(contains));
        }
      }
    }
    if (relayout.isNotEmpty) {
      for (final spanner in spanners) {
        final first = indexOf(spanner.first.measure);
        final last = indexOf(spanner.last.measure);
        if (spanner.kind.reach == SpannerReach.events && first < last) {
          for (var i = first > 0 ? first - 1 : 0; i < last; i++) {
            if (relayout.contains(measures[i].id)) {
              relayout.add(measures[last].id);
              break;
            }
          }
        }
      }
    }
    return ScoreChanges(relayout: relayout, removed: removed, reflow: reflow);
  }

  MeasureColumn? _columnAt(int index) =>
      index >= 0 && index < measures.length ? measures[index] : null;

  List<MeasureId> _covered(Spanner spanner) => [
    for (
      var i = indexOf(spanner.first.measure);
      i <= indexOf(spanner.last.measure);
      i++
    )
      measures[i].id,
  ];

  /// The spanners touching each bar, by the bar's index, in the order of
  /// [spanners]. Null for a bar that none touches. Built on first use, so a
  /// score pays for it once, however many bars are then viewed.
  late final List<List<Spanner>?> _spannersByBar = () {
    final byBar = List<List<Spanner>?>.filled(measures.length, null);
    for (final spanner in spanners) {
      final last = indexOf(spanner.last.measure);
      for (var i = indexOf(spanner.first.measure); i <= last; i++) {
        (byBar[i] ??= []).add(spanner);
      }
    }
    return byBar;
  }();

  /// Spanners with at least one point inside bar [id], in the order of
  /// [spanners].
  Iterable<Spanner> spannersTouching(MeasureId id) =>
      _spannersByBar[indexOf(id)] ?? const [];
}

/// The index of each bar of a score by its id. Null until it is first asked
/// for.
final class _Places {
  Map<MeasureId, int>? byId;
}

/// [score] with the bars from [start] replaced by [bars], one for one. When
/// every new bar has the id of the bar it replaces, the copy shares the
/// score's index of bars by id. The library does not export this.
Score replacingBars(Score score, int start, List<MeasureColumn> bars) {
  final measures = score.measures;
  final keepsIds = bars.indexed.every(
    (bar) => bar.$2.id == measures[start + bar.$1].id,
  );
  return Score._(
    keepsIds ? score._places : _Places(),
    meta: score.meta,
    parts: score.parts,
    measures: measures.replaceRange(start, start + bars.length, bars),
    spanners: score.spanners,
  );
}

/// The title and credits of a score. An empty string means the score has
/// none of that kind, and layout prints nothing for it.
final class ScoreMeta {
  /// Credits that default to empty.
  const ScoreMeta({
    this.title = '',
    this.subtitle = '',
    this.composer = '',
    this.lyricist = '',
    this.copyright = '',
  });

  /// Printed centred above the first system.
  final String title;

  /// Printed centred under [title].
  final String subtitle;

  /// Printed flush right on the line under the titles.
  final String composer;

  /// Printed flush left on the line of [composer].
  final String lyricist;

  /// Saved and exported to MusicXML. Layout does not print it.
  final String copyright;
}

/// One player's part: its names, its instrument and its staves.
final class Part {
  /// A part, shown and with no short name unless told otherwise.
  const Part({
    required this.id,
    required this.name,
    required this.instrument,
    required this.staves,
    this.shortName = '',
    this.hidden = false,
  });

  /// The part's identity.
  final PartId id;

  /// Printed before the first system. Empty prints none.
  final String name;

  /// Printed before every system after the first. Empty prints none.
  final String shortName;

  /// What the part plays: its sound, transposition, clef and kit.
  final Instrument instrument;

  /// One for most instruments, two for piano.
  final Seq<Staff> staves;

  /// Hidden parts stay in the score and play, but layout skips them.
  final bool hidden;

  /// This part with [hidden] replaced when given.
  Part copyWith({bool? hidden}) => Part(
    id: id,
    name: name,
    shortName: shortName,
    instrument: instrument,
    staves: staves,
    hidden: hidden ?? this.hidden,
  );
}

/// One staff of a part. Its music lives in the bars, one `StaffMeasure` per
/// bar.
final class Staff {
  /// A staff of [lines] lines, five unless given.
  const Staff({required this.id, this.lines = 5});

  /// The staff's identity.
  final StaffId id;

  /// 5 for pitched staves, 1 for one-line percussion.
  final int lines;
}

/// A playable instrument. Parts copy it by value; the app's catalogue of
/// 100+ instruments is a list of these constants.
final class Instrument {
  /// An instrument that, unless told otherwise, sounds as written in bank
  /// 0, reads treble clef, and has no strings, kit or known range.
  const Instrument({
    required this.key,
    required this.program,
    this.bank = 0,
    this.transposition = Interval.unison,
    this.clef = Clef.treble,
    this.strings = const [],
    this.drums = const [],
    this.lowest,
    this.highest,
    this._singleNoteDynamics,
  });

  /// Stable catalogue key, for example `violin`. Saved in JSON.
  final String key;

  /// General MIDI program 0–127. The app's SoundFont decides the sound.
  final int program;

  /// The SoundFont bank [program] is in, 0 or more. 0 is the melodic bank,
  /// and 128 is a SoundFont's percussion bank.
  final int bank;

  /// Written to sounding: B♭ clarinet is (−1 step, −2 semitones). Unison for
  /// concert-pitch instruments. Display only; pitches are stored concert.
  final Interval transposition;

  /// The clef a new staff of this instrument starts in.
  final Clef clef;

  /// Open strings, lowest first. Violin: G3, D4, A4, E5.
  final List<Pitch> strings;

  /// The kit, non-empty only for percussion. Names are unique, because a
  /// [Drum] names its sound.
  final List<DrumSound> drums;

  /// Bottom of the comfortable range, in concert pitch, for out-of-range
  /// colouring. Null when unknown.
  final Pitch? lowest;

  /// Top of the comfortable range, in concert pitch. Null when unknown.
  final Pitch? highest;

  /// Whether this is a drum kit, an instrument with [drums].
  bool get isPercussion => drums.isNotEmpty;

  final bool? _singleNoteDynamics;

  /// Whether a held note follows the dynamics while it sounds, as a bowed,
  /// blown or sung note does and a struck or plucked one does not. Unless
  /// the constructor is told, it is false for the General MIDI programs that
  /// strike or pluck (pianos, chromatic percussion, guitars, basses,
  /// pizzicato strings, harp, timpani, the plucked ethnic instruments and
  /// the percussive programs) and true for the rest. A kit never does.
  bool get singleNoteDynamics =>
      !isPercussion && (_singleNoteDynamics ?? !_struck(program));

  /// The kit sound that [drum] names, or null when the kit has none.
  DrumSound? soundOf(Drum drum) =>
      drums.where((sound) => sound.name == drum.name).firstOrNull;

  /// The key signature this instrument prints in concert [key]. Percussion
  /// prints none.
  KeySignature writtenKey(KeySignature key) =>
      isPercussion ? const KeySignature(0) : key.transpose(transposition);
}

bool _struck(int program) =>
    program <= 15 ||
    (24 <= program && program <= 39) ||
    (45 <= program && program <= 47) ||
    (104 <= program && program <= 108) ||
    (112 <= program && program <= 119);

/// One sound of a drum kit: where it sits on the staff, the head it is
/// drawn with and which MIDI key plays it.
final class DrumSound {
  /// A sound drawn with a normal head unless [head] says otherwise.
  const DrumSound({
    required this.name,
    required this.position,
    required this.midiKey,
    this.head = NoteHead.normal,
  });

  /// The name a [Drum] uses to pick this sound. Unique within a kit.
  final String name;

  /// Where the sound's notes print, given as the written pitch that sits
  /// there in the staff's clef.
  final Pitch position;

  /// The MIDI note number that plays the sound, 0 to 127.
  final int midiKey;

  /// The notehead the sound's notes are drawn with.
  final NoteHead head;
}

/// What `Score.blank` and `AddPart` need to create a part. Ids are minted by
/// the caller of the template, never by the template.
final class PartTemplate {
  /// A template for a part of one staff with no short name, unless told
  /// otherwise.
  const PartTemplate({
    required this.name,
    required this.instrument,
    this.shortName = '',
    this.staves = 1,
    this.clefs,
  });

  /// The new part's [Part.name].
  final String name;

  /// The new part's [Part.shortName].
  final String shortName;

  /// The new part's instrument.
  final Instrument instrument;

  /// How many staves the new part gets, 1 or more.
  final int staves;

  /// Initial clef per staff; defaults to the instrument's clef on each.
  final List<Clef>? clefs;
}

/// A mark that crosses barlines, on one staff.
///
/// Anchored by time, not by event: [first] and [last] are the onsets of the
/// first and last events the spanner covers. Overwriting a note under a slur
/// keeps the slur. Re-barring and measure deletion remap or drop anchors;
/// no other edit touches them.
///
/// An anchor is never dangling. The measure exists (checked at load) and the
/// offset lies inside it. If an overwrite leaves no event starting exactly
/// at an anchor, the view attaches that end to the event sounding at that
/// offset in [voice], or to an event of another voice where [voice] holds a
/// gap ([Score.anchorOf]). Voice one fills every bar, so such an event
/// always exists.
final class Spanner {
  /// A spanner of the whole staff unless [voice] is given. It checks
  /// nothing itself; [Score] asserts its anchors in debug builds.
  const Spanner({
    required this.id,
    required this.kind,
    required this.staff,
    required this.first,
    required this.last,
    this.voice,
  });

  /// The spanner's identity.
  final SpannerId id;

  /// What the spanner is and draws.
  final SpannerKind kind;

  /// The staff it is written on.
  final StaffId staff;

  /// Slurs and glissandi belong to a voice; lines and hairpins to the staff.
  final VoiceSlot? voice;

  /// The start anchor, the onset of the first event covered.
  final ScorePoint first;

  /// The end anchor, the onset of the last event covered. A spanner of
  /// [SpannerReach.time] runs on to the end of that event.
  final ScorePoint last;
}

/// What a spanner's ends attach to.
enum SpannerReach {
  /// The events sounding at its points, in its voice or else in another
  /// ([Score.anchorOf]): a slur, glissando or trill line. A glissando end
  /// that names a note is on that note's event in any voice, and a slur's
  /// last end that names a voice is on that voice's chord.
  events,

  /// Its points in time, the last one running to the end of the voice-one
  /// event it falls in: a hairpin, octave, pedal or tempo line.
  time,
}

/// The kind of a [Spanner]: what it draws and the fields of that kind.
sealed class SpannerKind {
  /// Lets the subclasses be constant.
  const SpannerKind();

  /// Whether the spanner joins notes of one voice, as a slur or glissando
  /// does. It then belongs to that voice and covers at least two events.
  /// Lines and hairpins mark a stretch of the staff and may cover one.
  bool get joinsNotes => false;

  /// What the spanner's ends attach to.
  SpannerReach get reach => switch (this) {
    Slur() || Glissando() || TrillLine() => SpannerReach.events,
    Hairpin() ||
    OctaveLine() ||
    PedalLine() ||
    TempoLine() => SpannerReach.time,
  };

  /// Kinds without fields are equal when they are the same kind.
  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A slur over notes of one voice. Where that voice has no event at an end,
/// the end is on an event of another voice ([Score.anchorOf]). The event
/// a slur ends on starts no sooner than the event it starts on, as in each
/// slur MuseScore 4's editor builds. A tied part of a note is an event of
/// its own, so a slur may end on one of its own voice that starts after its
/// first event even when the note it is tied from started before. Where
/// the last end only falls to voice one's event, and voice one has held
/// that event through any ties since before the slur's first event, the
/// end is on the chord another voice starts there instead, when there is
/// one. `AddSpanner` refuses a slur that ends on an event that starts
/// before the one it starts on, an edit that leaves one removes it, and
/// MusicXML import and a JSON file load without it.
///
/// `AddSpanner`, and each edit before it changes the score, store each end
/// that is on a chord where it is, as MuseScore 4 stores the chords a slur
/// joins. The first end, on a chord of the slur's voice, moves its point to
/// the chord's onset. The last end, on a chord that starts after the
/// slur's first point, moves its point to that chord's onset and names the
/// chord's voice in [endVoice] when it is not the slur's own. A later edit
/// of other notes then leaves the ends on their chords. An end on a rest,
/// a first end on a chord of another voice, and a last end on a chord that
/// starts no later than the first point are not stored and follow the rules
/// above.
final class Slur extends SpannerKind {
  /// A solid slur, or a dashed one when [dashed]. Its last end is on the
  /// chord of [endVoice] when that is given.
  const Slur({this.dashed = false, this.endVoice});

  /// Draw the curve as a dashed line.
  final bool dashed;

  /// The voice whose chord the slur ends on. `AddSpanner` and each edit set
  /// it when the slur ends on a chord of a voice other than its own that
  /// starts after the slur's first point, and clear it when that chord is of
  /// the slur's own voice, and MusicXML import sets it when the stop
  /// is written on a chord a voice other than the slur's own starts there or
  /// the slur would end on another chord than the one its stop is on, as
  /// MuseScore 4 keeps a slur on the chord it ends on. The end is on the
  /// chord that voice sounds at the last end, while that chord starts after
  /// the event the slur starts on, so a note that another voice starts or
  /// ties there does not take the end. While the voice sounds no such chord
  /// there, the end is where it falls without a name ([Score.anchorOf]),
  /// as it is for a slur without one, which a JSON file can hold. Each edit
  /// then names the voice of the chord the end falls on in its place.
  final VoiceSlot? endVoice;

  @override
  bool get joinsNotes => true;

  @override
  bool operator ==(Object other) =>
      other is Slur && other.dashed == dashed && other.endVoice == endVoice;

  @override
  int get hashCode => Object.hash(dashed, endVoice);
}

/// A crescendo or diminuendo wedge.
final class Hairpin extends SpannerKind {
  /// A crescendo when [crescendo], else a diminuendo.
  const Hairpin({required this.crescendo});

  /// The wedge opens toward its end (crescendo) rather than closing
  /// (diminuendo).
  final bool crescendo;

  @override
  bool operator ==(Object other) =>
      other is Hairpin && other.crescendo == crescendo;

  @override
  int get hashCode => crescendo.hashCode;
}

/// 8va, 8vb, 15ma, 15mb, 22ma, 22mb. Notes under it keep their sounding
/// pitch; layout prints them [OctaveShift.octaves] octaves lower (8va) or
/// higher (8vb).
final class OctaveLine extends SpannerKind {
  /// A line for [shift].
  const OctaveLine(this.shift);

  /// How many octaves, and which way, the music sounds from where it
  /// prints.
  final OctaveShift shift;

  @override
  bool operator ==(Object other) => other is OctaveLine && other.shift == shift;

  @override
  int get hashCode => shift.hashCode;
}

/// A trill sign with a wavy line, for a trill held over several notes.
/// Playback trills the notes from the one it starts on to the one it ends
/// on, as the sheet draws it, and a trilled note on through its tie.
final class TrillLine extends SpannerKind {
  /// The trill line, which has no fields.
  const TrillLine();
}

/// rit., rall., accel. and the like: the tempo moves gradually under the
/// line. It sets the tempo for every part, whichever staff it is written on,
/// as a fermata holds every part.
final class TempoLine extends SpannerKind {
  /// A line printing [text] that moves the tempo to [factor] of its start.
  /// Asserts that [factor] is positive.
  const TempoLine({required this.text, required this.factor})
    : assert(factor > 0, 'factor is positive');

  /// "rit.", slowing to three quarters of the tempo at its start.
  static const ritardando = TempoLine(text: 'rit.', factor: 0.75);

  /// "accel.", speeding up to four thirds of the tempo at its start.
  static const accelerando = TempoLine(text: 'accel.', factor: 4 / 3);

  /// What prints, as "rit." or "poco accel.".
  final String text;

  /// The tempo the line reaches, as a share of the tempo at its start, when
  /// no tempo mark is written inside it. Below 1 slows down.
  final double factor;

  @override
  bool operator ==(Object other) =>
      other is TempoLine && other.text == text && other.factor == factor;

  @override
  int get hashCode => Object.hash(text, factor);
}

/// A sustain pedal line. Playback holds the pedal down for the whole part
/// under it, whichever of the part's staves it is written on.
final class PedalLine extends SpannerKind {
  /// The pedal line, which has no fields.
  const PedalLine();
}

/// A glissando line from one note to another on one staff. Playback moves
/// the note it starts on toward the note it ends on in semitone steps, each
/// an equal share of the note, as MuseScore 4 plays a chromatic glissando.
/// The other notes of the chord hold, and a chord with two lines glides
/// each note along its own. A trill, mordent, turn or tremolo on the first
/// chord plays instead, and a note that ties on plays its tie.
///
/// [from] and [to] name the two notes. A named end is on its note in
/// whichever voice of the staff sounds it at that end, so a line of voice
/// two can end on a note of voice one while voice two plays under it
/// ([Score.anchorOf]). The line goes with a note it names, as in MuseScore
/// 4. An edit that moves or shortens the note moves that end to the note's
/// start, and an edit that takes the note off the staff removes the line.
/// A shorter `SetValue`, or a ripple that removes part of a chord's time,
/// removes each line that starts on that chord, as MuseScore 4 does.
/// A file whose line names a note that does not sound at that end loads
/// without the line. An end that names no note is on the event the
/// spanner's voice has there. When that voice has none, it is on an event of
/// another voice ([Score.anchorOf]). The last end of a line that starts on a
/// note, names no last note and would fall on a rest is on the first chord a
/// voice of the staff starts there, in voice order from voice one, when there
/// is one.
/// [notesOn] picks the note of that event.
/// `AddSpanner`, and each edit before it changes the score, name the note
/// of each end that is on a chord, so the line then goes with those notes,
/// as MuseScore 4 keeps the notes a glissando joins.
///
/// The event a line ends on starts after the event it starts on, as in each
/// line MuseScore 4's editor builds. So a line cannot end on an event of
/// another voice that starts with its first event or before it, whether the
/// end names a note of that event or is on voice one's event where its own
/// voice has none. `AddSpanner` refuses such a line, an edit that leaves
/// one removes it, and MusicXML import leaves it out. A JSON file with one
/// that names a note does not load. One that names no note, as a file saved
/// before 0.5.0 can hold, loads without the line. A tied part of a note is
/// an event of its own. Where the last end only falls to voice one's event,
/// and voice one has held that event through any ties since the line's
/// first event or before, the end is on the chord another voice starts
/// there instead, when there is one.
final class Glissando extends SpannerKind {
  /// A line from note [from] of the chord it starts on to note [to] of the
  /// chord it ends on. [notesOn] gives the note of an end whose id is null.
  const Glissando({this.from, this.to});

  /// The note the line starts on, or null for the top note of its chord.
  final NoteId? from;

  /// The note the line ends on, or null for the note of its chord at the
  /// start note's place ([notesOn]).
  final NoteId? to;

  /// The notes this line joins, where [first] and [last] are the events
  /// [Score.anchorOf] finds at its ends, on a staff of [instrument]. An end
  /// on a rest has no note.
  ///
  /// The start is on the note [from] names, or on the chord's top note when
  /// [from] is null or names no note of the chord. The end is on the note
  /// [to] names. When [to] is null or names no note of the chord, the end is
  /// on the note as far from the bottom of its chord as the start note is
  /// from the bottom of its own, or on the top note when the chord has fewer
  /// notes. MuseScore 4 picks the end of a new glissando that way. A line
  /// that starts on a rest ends on the top note. `AddSpanner` and each edit
  /// name the notes picked, so adding or removing a note of either chord
  /// later does not move an end.
  ///
  /// Top and bottom are by staff line, as MuseScore 4 orders a chord's
  /// notes, and by sound for notes on one line. A pitched note's line is its
  /// letter and octave, so B sharp 3 is below C flat 4 although it sounds
  /// higher. A drum's line is where [instrument] prints its sound, and drums
  /// on one line go by their MIDI keys.
  ({Note? from, Note? to}) notesOn(
    Event? first,
    Event? last, {
    required Instrument instrument,
  }) {
    final start = first is ChordEvent ? _byLine(first.notes, instrument) : null;
    final end = last is ChordEvent ? _byLine(last.notes, instrument) : null;
    final place = start == null
        ? null
        : _indexOf(start, from) ?? start.length - 1;
    return (
      from: place == null ? null : start![place],
      to: end == null
          ? null
          : end[_indexOf(end, to) ??
                min(place ?? end.length - 1, end.length - 1)],
    );
  }

  static List<Note> _byLine(Seq<Note> notes, Instrument instrument) {
    DrumSound sound(Drum drum) => instrument.soundOf(drum)!;
    int line(Note note) => switch (note) {
      PitchedNote(:final pitch) => pitch.diatonic,
      DrumNote(:final drum) => sound(drum).position.diatonic,
    };
    int height(Note a, Note b) => switch ((a, b)) {
      (final PitchedNote x, final PitchedNote y) => x.pitch.compareTo(y.pitch),
      (final DrumNote x, final DrumNote y) =>
        sound(x.drum).midiKey - sound(y.drum).midiKey,
      _ => 0,
    };
    return stableSorted(notes, (a, b) {
      final byLine = line(a) - line(b);
      return byLine != 0 ? byLine : height(a, b);
    });
  }

  static int? _indexOf(List<Note> notes, NoteId? id) {
    final index = id == null ? -1 : notes.indexWhere((note) => note.id == id);
    return index < 0 ? null : index;
  }

  /// This line on copies of its notes, where [copies] maps the id of each
  /// copied note to its copy's. An end whose note was not copied names none.
  Glissando onCopies(Map<NoteId, NoteId> copies) =>
      Glissando(from: copies[from], to: copies[to]);

  @override
  bool get joinsNotes => true;

  @override
  bool operator ==(Object other) =>
      other is Glissando && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(Glissando, from, to);
}

/// How far an [OctaveLine] moves the sound from the print.
enum OctaveShift {
  /// 8va: sounds one octave above where it prints.
  up8(1),

  /// 8vb: sounds one octave below where it prints.
  down8(-1),

  /// 15ma: sounds two octaves above where it prints.
  up15(2),

  /// 15mb: sounds two octaves below where it prints.
  down15(-2),

  /// 22ma: sounds three octaves above where it prints.
  up22(3),

  /// 22mb: sounds three octaves below where it prints.
  down22(-3);

  OctaveShift(this.octaves);

  /// Octaves the sound lies above the print, negative for below.
  final int octaves;
}
