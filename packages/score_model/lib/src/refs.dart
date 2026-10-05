/// Identity and addressing.
///
/// Every durable entity carries a typed integer id. Ids come from one
/// monotonic counter owned by the `EditSession`; nothing generates an id in a
/// constructor, and nothing is random. Building the same score with the same
/// edits yields the same ids, and ids round-trip through JSON unchanged.
///
/// Undo does not rewind the counter, so an id is never reused within a
/// session, even for an entity that an undone edit created. Anything that
/// holds a stale id (a playback script, a highlight) can never alias a new
/// entity.
library;

import 'time.dart';

extension type const PartId(int value) implements Object;

extension type const StaffId(int value) implements Object;

/// Stable across insertions and deletions of other measures. Layout caches
/// key on it; the measure *number* is derived.
extension type const MeasureId(int value) implements Object;

extension type const EventId(int value) implements Object;

/// A single notehead inside a chord. Ties, fingering and string marks attach
/// to note heads, and a selection can hold one head of a chord.
extension type const NoteId(int value) implements Object;

extension type const TupletId(int value) implements Object;

extension type const SpannerId(int value) implements Object;

/// The four voice lanes of a staff. Slot one is the only voice that always
/// exists; it is never allowed to have gaps.
enum VoiceSlot {
  one,
  two,
  three,
  four;

  /// Stem direction when more than one voice is present on the staff.
  bool get stemsUp => index.isEven;
}

/// A point in notated time: a measure and a sounding offset from its start,
/// in whole notes. Staff-independent. Tempo marks, range selections and
/// spanner endpoints use it.
///
/// Invariant (checked by the edits that consume it): `0 <= offset < length`
/// of its bar, so the end of a bar is spelled as offset 0 of the next bar.
/// The one exception is an exclusive range end (`RangeSelection.to`,
/// `PlaybackOptions.to`), which may equal the bar length so a range can end
/// at the end of the score.
final class ScorePoint {
  const ScorePoint(this.measure, this.offset);

  final MeasureId measure;
  final Moment offset;

  @override
  bool operator ==(Object other) =>
      other is ScorePoint && other.measure == measure && other.offset == offset;

  @override
  int get hashCode => Object.hash(measure, offset);

  @override
  String toString() => 'm${measure.value}@$offset';
}

/// A writing position: one voice of one staff at a point in time. The edit
/// cursor is a [VoicePoint].
final class VoicePoint {
  const VoicePoint({
    required this.staff,
    required this.voice,
    required this.at,
  });

  final StaffId staff;
  final VoiceSlot voice;
  final ScorePoint at;

  VoicePoint withVoice(VoiceSlot voice) =>
      VoicePoint(staff: staff, voice: voice, at: at);

  @override
  bool operator ==(Object other) =>
      other is VoicePoint &&
      other.staff == staff &&
      other.voice == voice &&
      other.at == at;

  @override
  int get hashCode => Object.hash(staff, voice, at);
}

/// A reference to something a composer can select. Every reference carries
/// the measure that contained it when the reference was made, so resolving
/// one is usually a map lookup plus a scan of one measure. The measure is a
/// hint: identity is the event id alone, and `Score.lookup` falls back to a
/// lazy index when a re-bar has moved the event.
sealed class ElementRef {
  const ElementRef();

  EventRef get event;
}

final class EventRef extends ElementRef {
  const EventRef({
    required this.measure,
    required this.staff,
    required this.id,
  });

  final MeasureId measure;
  final StaffId staff;
  final EventId id;

  @override
  EventRef get event => this;

  @override
  bool operator ==(Object other) => other is EventRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class NoteRef extends ElementRef {
  const NoteRef(this.event, this.note);

  @override
  final EventRef event;
  final NoteId note;

  @override
  bool operator ==(Object other) =>
      other is NoteRef && other.event == event && other.note == note;

  @override
  int get hashCode => Object.hash(event, note);
}
