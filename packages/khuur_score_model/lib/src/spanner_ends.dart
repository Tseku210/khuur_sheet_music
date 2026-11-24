/// Where each spanner of a score starts and stops. Internal to the package.
library;

import 'events.dart';
import 'refs.dart';
import 'score.dart';
import 'time.dart';
import 'views.dart';

/// The ends of each spanner a score has been asked about, by score. A
/// score is immutable, so its answer for a spanner never changes.
final _cache = Expando<Map<Spanner, SpannerEnds>>('spanner ends');

/// How a score answers where its spanners start and stop.
extension SpannerEndsOf on Score {
  /// Where [spanner] starts and stops in this score. One value for each
  /// score and spanner object, so each part of the answer is worked out
  /// once however often it is asked for. [spanner] need not be one of
  /// [Score.spanners].
  SpannerEnds spannerEnds(Spanner spanner) =>
      (_cache[this] ??= Map.identity())[spanner] ??= SpannerEnds._(
        this,
        spanner,
      );

  /// The bars, by index from `from` up to the bar `to` it ends in, whose
  /// events where [spanner] ends can depend on besides that bar: every bar
  /// from the one before its first, for a slur, glissando or trill line
  /// that ends in a later bar than it starts. Null for every other spanner,
  /// whose ends read no bar but the one it ends in and the one before.
  /// Reads only the indices of the spanner's bars.
  ({int from, int to})? endsReadBefore(Spanner spanner) {
    final first = indexOf(spanner.first.measure);
    final last = indexOf(spanner.last.measure);
    return spanner.kind.reach == SpannerReach.events && first < last
        ? (from: first > 0 ? first - 1 : 0, to: last)
        : null;
  }
}

/// Where a spanner starts and stops in one score: the events it attaches
/// to at its ends, the notes a glissando joins, and where it stops in its
/// last bar. Each part is worked out the first time it is asked for.
final class SpannerEnds {
  SpannerEnds._(this._score, this.spanner);

  final Score _score;

  /// The spanner whose ends these are.
  final Spanner spanner;

  /// The event the spanner attaches to at its first end
  /// ([Score.anchorOf]).
  late final TimedEvent? startsOn = _anchor(last: false);

  /// The event the spanner attaches to at its last end ([Score.anchorOf]).
  late final TimedEvent? endsOn = _anchor(last: true);

  /// The note of [startsOn] a [Glissando] starts on ([Glissando.notesOn]),
  /// or null for another kind and where [startsOn] is a rest.
  late final Note? startNote = switch (spanner.kind) {
    final Glissando kind =>
      kind.notesOn(startsOn?.event, null, instrument: _instrument).from,
    _ => null,
  };

  /// The note of [endsOn] a [Glissando] ends on ([Glissando.notesOn]), or
  /// null for another kind and where [endsOn] is a rest.
  late final Note? endNote = switch (spanner.kind) {
    final Glissando kind =>
      kind
          .notesOn(
            startsOn?.event,
            endsOn?.event,
            instrument: _instrument,
          )
          .to,
    _ => null,
  };

  Instrument get _instrument => _score.partOf(spanner.staff).instrument;

  /// Whether the spanner joins notes but starts and ends on one event, or
  /// on none at both ends.
  late final bool collapsed =
      spanner.kind.joinsNotes && startsOn?.event.id == endsOn?.event.id;

  /// The note a [Glissando] names that no voice of its staff sounds at that
  /// end of it, its first end's before its last's, or null when each note
  /// it names is there and for another kind.
  NoteId? get lostNote => switch (spanner.kind) {
    Glissando(:final from?) when startNote?.id != from => from,
    Glissando(:final to?) when endNote?.id != to => to,
    _ => null,
  };

  /// Whether the spanner joins notes and ends on an event that starts too
  /// soon. A [Glissando] must end on an event that starts after its start
  /// event. A [Slur] may end on one that starts with its start event, in
  /// another voice. A collapsed spanner ([collapsed]), one with no event at
  /// an end, and a glissando that has lost a note it names ([lostNote])
  /// never end too soon.
  bool get endsTooSoon {
    final kind = spanner.kind;
    if (!kind.joinsNotes || collapsed) {
      return false;
    }
    final (first, last) = (startsOn, endsOn);
    if (first == null || last == null || lostNote != null) {
      return false;
    }
    final bars =
        _score.indexOf(last.ref.measure) - _score.indexOf(first.ref.measure);
    final order = bars != 0 ? bars : last.onset.compareTo(first.onset);
    return order < 0 || (order == 0 && kind is Glissando);
  }

  /// Where a spanner of [SpannerReach.time] stops in its last bar
  /// ([Score.lineEnd]): the end of the voice-one event its last point falls
  /// in.
  late final Moment timeEnd = () {
    final last = _score.eventAt(
      VoicePoint(staff: spanner.staff, voice: VoiceSlot.one, at: spanner.last),
    )!;
    return last.onset + last.duration;
  }();

  /// Where the spanner stops in its last bar ([Score.endOf]): [timeEnd] for
  /// a spanner of [SpannerReach.time], its last point for one of
  /// [SpannerReach.events].
  Moment get stop => switch (spanner.kind.reach) {
    SpannerReach.events => spanner.last.offset,
    SpannerReach.time => timeEnd,
  };

  /// The rules [Score.anchorOf] describes. The last end reads [startsOn].
  TimedEvent? _anchor({required bool last}) {
    final at = last ? spanner.last : spanner.first;
    TimedEvent? sounding(VoiceSlot voice) =>
        _score.eventAt(VoicePoint(staff: spanner.staff, voice: voice, at: at));
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
        final start = startsOn;
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
    final start = startsOn;
    if (start == null ||
        !_heldSince(one, start, orWith: spanner.kind is Glissando)) {
      return one;
    }
    for (final slot in VoiceSlot.values.skip(1)) {
      final timed = sounding(slot);
      if (timed != null &&
          timed.onset == at.offset &&
          timed.event is ChordEvent) {
        return timed;
      }
    }
    return one;
  }

  bool _startsAfter(TimedEvent event, TimedEvent other) =>
      _score.compare(
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
    final bar = _score.indexOf(start.ref.measure);
    for (TimedEvent? part = held; part != null; part = _tiedFrom(part)) {
      if (part.ref == start.ref) {
        return false;
      }
      final bars = _score.indexOf(part.ref.measure) - bar;
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
    final before = _score.eventBefore(part);
    if (before == null) {
      return null;
    }
    final end = before.onset + before.duration;
    final joined = before.ref.measure == part.ref.measure
        ? end == part.onset
        : part.onset.isZero &&
              end == Moment.zero + _score.column(before.ref.measure).length;
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
}
