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

/// [voice]'s tuplets in pre-order: an outer tuplet before the tuplets it
/// holds.
Iterable<TimedTuplet> timedTuplets(Voice voice) sync* {
  for (final step in _walk(voice.items, Moment.zero, Fraction.one, const [])) {
    if (step.item case final Tuplet tuplet) {
      yield (
        tuplet: tuplet,
        onset: step.onset,
        span: step.duration,
        depth: step.tuplets.length,
      );
    }
  }
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
/// of its voice.
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
