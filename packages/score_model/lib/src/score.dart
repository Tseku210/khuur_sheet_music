/// The score root: parts, the global column list, and cross-bar spanners.
library;

import 'empty_bar.dart';
import 'events.dart';
import 'measure.dart';
import 'measure_view.dart';
import 'pitch.dart';
import 'refs.dart';
import 'rules.dart';
import 'seq.dart';
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
  Score({
    required this.meta,
    required this.parts,
    required this.measures,
    this.spanners = const Seq.empty(),
  }) : assert(parts.isNotEmpty, 'a score has at least one part'),
       assert(measures.isNotEmpty, 'a score has at least one measure'),
       assert(
         _shapeProblem(parts, measures, spanners) == null,
         _shapeProblem(parts, measures, spanners),
       );

  /// A score with [parts], [measureCount] empty bars of [meter] in [key], and
  /// a tempo mark at the start. Ids are allocated 1, 2, 3… in document order,
  /// so two blank scores built with the same arguments are identical in
  /// content and ids. Throws [ArgumentError] for a value a saved score may
  /// not hold.
  factory Score.blank({
    required List<PartTemplate> parts,
    String title = '',
    int measureCount = 16,
    Meter meter = Meter.fourFour,
    KeySignature key = KeySignature.cMajor,
    Tempo tempo = Tempo.unmarked,
  }) {
    final problem =
        meterProblem(meter) ??
        keyProblem(key.fifths) ??
        tempoMarkProblem(tempo) ??
        parts
            .map((part) => instrumentProblem(part.instrument))
            .nonNulls
            .firstOrNull;
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

  final ScoreMeta meta;
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
  }) => Score(
    meta: meta ?? this.meta,
    parts: parts ?? this.parts,
    measures: measures ?? this.measures,
    spanners: spanners ?? this.spanners,
  );

  /// Staves in system order: parts top to bottom, then each part's staves
  /// top to bottom. Every column's `staves` follows this order.
  late final List<Staff> staves = [for (final part in parts) ...part.staves];

  late final Map<MeasureId, int> _indexById = {
    for (var i = 0; i < measures.length; i++) measures[i].id: i,
  };

  /// Position of [id] in [measures]. Throws if [id] is not in this score.
  int indexOf(MeasureId id) =>
      _indexById[id] ??
      (throw ArgumentError.value(id, 'id', 'no such measure'));

  bool contains(MeasureId id) => _indexById.containsKey(id);

  /// The printed number of bar [id]. Bars count from 1. A first bar shorter
  /// than its meter is a pickup and is numbered 0, so the bar after it is 1.
  /// Throws if [id] is not in this score.
  int barNumberOf(MeasureId id) {
    final first = measures.first;
    return indexOf(id) + (first.length < first.meter.length ? 0 : 1);
  }

  MeasureColumn column(MeasureId id) => measures[indexOf(id)];

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

  /// The event a slur, glissando or trill line on [staff] attaches to at
  /// [at]: the one sounding there in [voice], else in voice one.
  TimedEvent? anchorAt(StaffId staff, VoiceSlot voice, ScorePoint at) =>
      eventAt(VoicePoint(staff: staff, voice: voice, at: at)) ??
      eventAt(VoicePoint(staff: staff, voice: VoiceSlot.one, at: at));

  /// Where a hairpin, octave line, pedal line or tempo line stops in its
  /// last bar: the end of the voice-one event its last point falls in. The
  /// line covers that event.
  Moment lineEnd(Spanner spanner) {
    final last = eventAt(
      VoicePoint(staff: spanner.staff, voice: VoiceSlot.one, at: spanner.last),
    )!;
    return last.onset + last.duration;
  }

  /// Whether [spanner] joins notes but starts and ends on one event.
  bool isCollapsed(Spanner spanner) {
    if (!spanner.kind.joinsNotes) {
      return false;
    }
    final voice = spanner.voice ?? VoiceSlot.one;
    return anchorAt(spanner.staff, voice, spanner.first)?.event.id ==
        anchorAt(spanner.staff, voice, spanner.last)?.event.id;
  }

  /// Everything in effect at a point on a staff.
  ScoreContext contextAt(StaffId staff, ScorePoint at) {
    final index = indexOf(at.measure);
    final column = measures[index];
    final octaveLine = spannersTouching(at.measure)
        .where((s) => s.staff == staff && _within(s.first, at, s.last))
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

  bool _within(ScorePoint first, ScorePoint at, ScorePoint last) =>
      _compare(first, at) <= 0 && _compare(at, last) <= 0;

  int _compare(ScorePoint a, ScorePoint b) {
    final byBar = indexOf(a.measure).compareTo(indexOf(b.measure));
    return byBar != 0 ? byBar : a.offset.compareTo(b.offset);
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
  /// targets. No other measure is touched.
  MeasureView measureView(MeasureId id) => buildMeasureView(this, indexOf(id));

  /// Which measures' [MeasureView]s may differ from those of [previous].
  ///
  /// Works by identity. An edit rebuilds only the path from the root to what
  /// it touched, so every other column is the same object in both scores. A
  /// view reads its own column, both neighbours and the spanners touching it.
  /// So a bar is relaid out when it is new, when it or either neighbour is a
  /// different object than before, or when a spanner covering it was added
  /// or removed. Every bar is relaid out when the parts change or when bars
  /// that survive change order. [meta] is not compared.
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

  /// Spanners with at least one point inside bar [id]. Linear in the
  /// spanner count (hundreds in a large score).
  Iterable<Spanner> spannersTouching(MeasureId id) {
    final index = indexOf(id);
    return spanners.where(
      (s) =>
          indexOf(s.first.measure) <= index && index <= indexOf(s.last.measure),
    );
  }
}

final class ScoreMeta {
  const ScoreMeta({
    this.title = '',
    this.subtitle = '',
    this.composer = '',
    this.lyricist = '',
    this.copyright = '',
  });

  final String title;
  final String subtitle;
  final String composer;
  final String lyricist;
  final String copyright;
}

final class Part {
  const Part({
    required this.id,
    required this.name,
    required this.instrument,
    required this.staves,
    this.shortName = '',
    this.hidden = false,
  });

  final PartId id;

  final String name;
  final String shortName;
  final Instrument instrument;

  /// One for most instruments, two for piano.
  final Seq<Staff> staves;

  /// Hidden parts stay in the score and play, but layout skips them.
  final bool hidden;

  Part copyWith({bool? hidden}) => Part(
    id: id,
    name: name,
    shortName: shortName,
    instrument: instrument,
    staves: staves,
    hidden: hidden ?? this.hidden,
  );
}

final class Staff {
  const Staff({required this.id, this.lines = 5});

  final StaffId id;

  /// 5 for pitched staves, 1 for one-line percussion.
  final int lines;
}

/// A playable instrument. Parts copy it by value; the app's catalogue of
/// 100+ instruments is a list of these constants.
final class Instrument {
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
  });

  /// Stable catalogue key, for example `violin`. Saved in JSON.
  final String key;

  /// General MIDI program 0–127. The app's SoundFont decides the sound.
  final int program;
  final int bank;

  /// Written to sounding: B♭ clarinet is (−1 step, −2 semitones). Unison for
  /// concert-pitch instruments. Display only; pitches are stored concert.
  final Interval transposition;

  final Clef clef;

  /// Open strings, lowest first. Violin: G3, D4, A4, E5.
  final List<Pitch> strings;

  /// The kit, non-empty only for percussion. Names are unique, because a
  /// [Drum] names its sound.
  final List<DrumSound> drums;

  /// Comfortable range, for out-of-range colouring. Null when unknown.
  final Pitch? lowest;
  final Pitch? highest;

  bool get isPercussion => drums.isNotEmpty;

  DrumSound? soundOf(Drum drum) =>
      drums.where((sound) => sound.name == drum.name).firstOrNull;

  /// The key signature this instrument prints in concert [key]. Percussion
  /// prints none.
  KeySignature writtenKey(KeySignature key) =>
      isPercussion ? const KeySignature(0) : key.transpose(transposition);
}

/// One sound of a drum kit: where it sits on the staff, the head it is
/// drawn with and which MIDI key plays it.
final class DrumSound {
  const DrumSound({
    required this.name,
    required this.position,
    required this.midiKey,
    this.head = NoteHead.normal,
  });

  final String name;
  final Pitch position;
  final int midiKey;
  final NoteHead head;
}

/// What `Score.blank` and `AddPart` need to create a part. Ids are minted by
/// the caller of the template, never by the template.
final class PartTemplate {
  const PartTemplate({
    required this.name,
    required this.instrument,
    this.shortName = '',
    this.staves = 1,
    this.clefs,
  });

  final String name;
  final String shortName;
  final Instrument instrument;
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
/// offset in [voice], or in voice one where [voice] holds a gap. Voice one
/// fills every bar, so such an event always exists.
final class Spanner {
  const Spanner({
    required this.id,
    required this.kind,
    required this.staff,
    required this.first,
    required this.last,
    this.voice,
  });

  final SpannerId id;
  final SpannerKind kind;
  final StaffId staff;

  /// Slurs and glissandi belong to a voice; lines and hairpins to the staff.
  final VoiceSlot? voice;

  final ScorePoint first;
  final ScorePoint last;
}

sealed class SpannerKind {
  const SpannerKind();

  /// Whether the spanner joins notes of one voice, as a slur or glissando
  /// does. It then belongs to that voice and covers at least two events.
  /// Lines and hairpins mark a stretch of the staff and may cover one.
  bool get joinsNotes => false;
}

final class Slur extends SpannerKind {
  const Slur({this.dashed = false});

  final bool dashed;

  @override
  bool get joinsNotes => true;
}

final class Hairpin extends SpannerKind {
  const Hairpin({required this.crescendo});

  final bool crescendo;
}

/// 8va, 8vb, 15ma, 15mb, 22ma, 22mb. Notes under it keep their sounding
/// pitch; layout prints them [OctaveShift.octaves] octaves lower (8va) or
/// higher (8vb).
final class OctaveLine extends SpannerKind {
  const OctaveLine(this.shift);

  final OctaveShift shift;
}

final class TrillLine extends SpannerKind {
  const TrillLine();
}

/// rit., rall., accel. and the like: the tempo moves gradually under the
/// line. It sets the tempo for every part, whichever staff it is written on,
/// as a fermata holds every part.
final class TempoLine extends SpannerKind {
  const TempoLine({required this.text, required this.factor})
    : assert(factor > 0, 'factor is positive');

  static const ritardando = TempoLine(text: 'rit.', factor: 0.75);
  static const accelerando = TempoLine(text: 'accel.', factor: 4 / 3);

  /// What prints, as "rit." or "poco accel.".
  final String text;

  /// The tempo the line reaches, as a share of the tempo at its start, when
  /// no tempo mark is written inside it. Below 1 slows down.
  final double factor;
}

final class PedalLine extends SpannerKind {
  const PedalLine();
}

final class Glissando extends SpannerKind {
  const Glissando();

  @override
  bool get joinsNotes => true;
}

enum OctaveShift {
  up8(1),
  down8(-1),
  up15(2),
  down15(-2),
  up22(3),
  down22(-3);

  OctaveShift(this.octaves);

  final int octaves;
}
