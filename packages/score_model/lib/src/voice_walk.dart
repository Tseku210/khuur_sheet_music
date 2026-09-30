/// Sounding time of the events in a voice. Internal to the package.
library;

import 'events.dart';
import 'measure.dart';
import 'refs.dart';
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
