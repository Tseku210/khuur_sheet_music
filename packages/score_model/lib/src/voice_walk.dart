/// Sounding time of the events in a voice. Internal to the package.
library;

import 'events.dart';
import 'measure.dart';
import 'refs.dart';
import 'seq.dart';
import 'time.dart';
import 'views.dart';

/// [voice]'s events in time order, with sounding onsets and durations.
/// Descends into tuplets, scaling by each ratio. Gaps are skipped.
Iterable<TimedEvent> timedEvents(
  Voice voice, {
  required MeasureId measure,
  required StaffId staff,
}) {
  Iterable<TimedEvent> walk(
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
          yield TimedEvent(
            ref: EventRef(measure: measure, staff: staff, id: item.id),
            voice: voice.slot,
            event: item,
            onset: at,
            duration: duration,
            tuplets: tuplets,
          );
        case Tuplet(:final id, :final ratio, :final members):
          yield* walk(members, at, scale * ratio.scale, [...tuplets, id]);
      }
      at += duration;
    }
  }

  return walk(voice.items, Moment.zero, Fraction.one, const []);
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
