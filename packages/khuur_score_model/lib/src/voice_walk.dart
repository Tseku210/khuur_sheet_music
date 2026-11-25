/// Sounding time of the events in a voice. Internal to the package.
library;

import 'events.dart';
import 'measure.dart';
import 'pitch.dart';
import 'refs.dart';
import 'seq.dart';
import 'time.dart';
import 'views.dart';

/// An event or tuplet met by [_walk], with its sounding onset and duration
/// and the ids of the tuplets enclosing it, outermost first.
typedef _Step = ({
  VoiceItem item,
  Moment onset,
  Length duration,
  List<TupletId> tuplets,
});

/// The events and tuplets of [items] in pre-order, scaling by each tuplet's
/// ratio. Gaps are skipped.
Iterable<_Step> _walk(
  Iterable<VoiceItem> items,
  Moment start,
  Fraction scale,
  List<TupletId> tuplets,
) sync* {
  var at = start;
  for (final item in items) {
    final duration = item.span * scale;
    switch (item) {
      case Gap():
        break;
      case Event():
        yield (item: item, onset: at, duration: duration, tuplets: tuplets);
      case Tuplet(:final id, :final ratio, :final members):
        yield (item: item, onset: at, duration: duration, tuplets: tuplets);
        yield* _walk(members, at, scale * ratio.scale, [...tuplets, id]);
    }
    at += duration;
  }
}

/// [voice]'s events in time order, with sounding onsets and durations.
/// Descends into tuplets, scaling by each ratio. Gaps are skipped.
Iterable<TimedEvent> timedEvents(
  Voice voice, {
  required MeasureId measure,
  required StaffId staff,
}) sync* {
  for (final step in _walk(voice.items, Moment.zero, Fraction.one, const [])) {
    if (step.item case final Event event) {
      yield TimedEvent(
        ref: EventRef(measure: measure, staff: staff, id: event.id),
        voice: voice.slot,
        event: event,
        onset: step.onset,
        duration: step.duration,
        tuplets: step.tuplets,
      );
    }
  }
}

/// A tuplet of a voice with its sounding onset and length, and its nesting
/// depth (0 for an outermost tuplet).
typedef TimedTuplet = ({
  Tuplet tuplet,
  Moment onset,
  Length span,
  int depth,
});

/// What [timedEvents] gives for [voice], and its tuplets in pre-order, an
/// outer tuplet before the tuplets it holds, from one walk.
///
/// A measure view reads both lists whole, so it walks the voice once here
/// and builds neither lazily.
({List<TimedEvent> events, List<TimedTuplet> tuplets}) timedVoice(
  Voice voice, {
  required MeasureId measure,
  required StaffId staff,
}) {
  final events = <TimedEvent>[];
  final tuplets = <TimedTuplet>[];
  void walk(
    Iterable<VoiceItem> items,
    Moment start,
    Fraction scale,
    List<TupletId> enclosing,
  ) {
    var at = start;
    for (final item in items) {
      final duration = item.span * scale;
      switch (item) {
        case Gap():
          break;
        case Event():
          events.add(
            TimedEvent(
              ref: EventRef(measure: measure, staff: staff, id: item.id),
              voice: voice.slot,
              event: item,
              onset: at,
              duration: duration,
              tuplets: enclosing,
            ),
          );
        case Tuplet(:final id, :final ratio, :final members):
          tuplets.add(
            (
              tuplet: item,
              onset: at,
              span: duration,
              depth: enclosing.length,
            ),
          );
          walk(members, at, scale * ratio.scale, [...enclosing, id]);
      }
      at += duration;
    }
  }

  walk(voice.items, Moment.zero, Fraction.one, const []);
  return (events: events, tuplets: tuplets);
}

/// The last event [timedEvents] gives for [voice], found without its time.
Event? lastEvent(Voice voice) {
  Event? last(Seq<VoiceItem> items) {
    for (var i = items.length - 1; i >= 0; i--) {
      switch (items[i]) {
        case Gap():
          break;
        case final Event event:
          return event;
        case Tuplet(:final members):
          if (last(members) case final event?) {
            return event;
          }
      }
    }
    return null;
  }

  return last(voice.items);
}

/// The event that opens [column] in [slot] of [staff]. Null when that voice
/// is absent or opens with a gap.
TimedEvent? openingEvent(MeasureColumn column, StaffId staff, VoiceSlot slot) {
  final voice = column.staff(staff).voice(slot);
  final first = voice == null
      ? null
      : timedEvents(voice, measure: column.id, staff: staff).firstOrNull;
  return first != null && first.onset.isZero ? first : null;
}

/// The head of [event] with [tone], or null when [event] is null, a rest,
/// or has no head of that tone. A tie ends on this head of the next event
/// of its voice, or of an event of another voice ([tieLanding]).
Note? headOfTone(Event? event, Tone tone) {
  if (event case ChordEvent(:final notes)) {
    for (final note in notes) {
      if (note.tone == tone) {
        return note;
      }
    }
  }
  return null;
}

/// A head a tie could land on where it ends: the head, the voice that
/// holds it, and whether a tie from that voice's own previous event lands
/// on it.
typedef TieHead<T> = ({VoiceSlot slot, T head, bool tiedInVoice});

/// The head that a tie from voice [from] lands on. [heads] are the heads of
/// the tie's tone in the events of its staff that start where the tied note
/// ends, at most one a voice. The head in [from] wins. Failing that, the tie
/// lands on the head of the lowest other voice that no tie of its own voice
/// lands on, as MusicXML lets a tie end in another voice. Null when no head
/// is left, and the tie lands on no note.
///
/// This is the one rule of where a tie ends. The view, playback, the
/// MusicXML import and the edits each gather [heads] from what they hold.
T? tieLanding<T>(VoiceSlot from, Iterable<TieHead<T>> heads) {
  T? other;
  VoiceSlot? lowest;
  for (final (:slot, :head, :tiedInVoice) in heads) {
    if (slot == from) {
      return head;
    }
    if (!tiedInVoice && (lowest == null || slot.index < lowest.index)) {
      other = head;
      lowest = slot;
    }
  }
  return other;
}

/// One voice of a staff at a moment: its event that ends there and its event
/// that starts there, either of which may be absent.
typedef VoiceAround = ({
  VoiceSlot slot,
  TimedEvent? ending,
  TimedEvent? starting,
});

/// The head that [tied], a tied note of voice [from], lands on, given
/// [voices], the voices of its staff where the tie ends ([tieLanding]).
NoteRef? tieLandingAround(
  Note tied,
  VoiceSlot from,
  Iterable<VoiceAround> voices,
) => tieLanding(from, [
  for (final (:slot, :ending, :starting) in voices)
    if (starting case TimedEvent(:final ref, :final event))
      if (headOfTone(event, tied.tone) case final head?)
        (
          slot: slot,
          head: NoteRef(ref, head.id),
          tiedInVoice: headOfTone(ending?.event, tied.tone)?.tie ?? false,
        ),
]);
