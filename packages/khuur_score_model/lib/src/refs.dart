/// Identity and addressing.
///
/// Every durable entity carries a typed integer id. Ids come from one
/// monotonic counter owned by the `EditSession`; nothing generates an id in a
/// constructor, and nothing is random. Building the same score with the same
/// edits yields the same ids, and ids round-trip through JSON unchanged.
///
/// Every kind of id draws from that one counter, so no two entities of a
/// score share a value, whatever their kinds. `Score.blank` counts from 1 in
/// document order, and `EditSession.start` resumes one past the largest id
/// already in its score.
///
/// Undo does not rewind the counter, so an id is never reused within a
/// session, even for an entity that an undone edit created. Anything that
/// holds a stale id (a playback script, a highlight) can never alias a new
/// entity.
library;

import 'time.dart';

/// The id of one part. It names the part for as long as the part is in the
/// score, through hiding and a change of instrument.
extension type const PartId(int value) implements Object;

/// The id of one staff. It names the staff until its part is removed or a
/// change of instrument drops it, wherever the staff sits in system order.
extension type const StaffId(int value) implements Object;

/// The id of one bar. Stable across insertions and deletions of other
/// measures. Layout caches key on it; the measure *number* is derived.
/// Re-barring after a meter change reuses the ids of the bars it rewrites,
/// so a bar id can come to hold different music.
extension type const MeasureId(int value) implements Object;

/// The id of one event: a chord, a rest or a measure rest. It stays the
/// same when re-barring moves the event into another bar.
extension type const EventId(int value) implements Object;

/// A single notehead inside a chord. Ties, fingering and string marks attach
/// to note heads, and a selection can hold one head of a chord.
extension type const NoteId(int value) implements Object;

/// The id of one tuplet group of a voice.
extension type const TupletId(int value) implements Object;

/// The id of one spanner of the score.
extension type const SpannerId(int value) implements Object;

/// The four voice lanes of a staff. Slot one is the only voice that always
/// exists; it is never allowed to have gaps.
enum VoiceSlot {
  /// The voice every bar of every staff holds. Stems up when voices share
  /// the staff.
  one,

  /// The second voice. Stems down when voices share the staff.
  two,

  /// The third voice. Stems up when voices share the staff.
  three,

  /// The fourth voice. Stems down when voices share the staff.
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
  /// The point [offset] whole notes into bar [measure].
  const ScorePoint(this.measure, this.offset);

  /// The bar the point falls in.
  final MeasureId measure;

  /// Sounding offset from the start of [measure], in whole notes.
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
  /// The point [at] in [voice] of [staff].
  const VoicePoint({
    required this.staff,
    required this.voice,
    required this.at,
  });

  /// The staff written on.
  final StaffId staff;

  /// The voice lane of [staff] written in.
  final VoiceSlot voice;

  /// The bar and offset written at.
  final ScorePoint at;

  /// The same staff and point in time, in [voice].
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

/// A reference to an event or a note head that a composer can select. A
/// selected spanner sits in no bar, so `ItemSelection.spanners` names it
/// by its [SpannerId] instead. Every reference carries the measure that
/// contained it when the reference was made, so resolving one is usually a
/// map lookup plus a scan of one measure. The measure is a hint: identity
/// is the event id alone, and `Score.lookup` falls back to a lazy index
/// when a re-bar has moved the event.
sealed class ElementRef {
  /// Lets the subclasses be constant.
  const ElementRef();

  /// The event referred to, or the event that holds the referred head.
  EventRef get event;
}

/// A reference to one event. Two references are equal when they name the
/// same [id], whatever bar they hint at.
final class EventRef extends ElementRef {
  /// A reference to event [id] on [staff], last seen in [measure].
  const EventRef({
    required this.measure,
    required this.staff,
    required this.id,
  });

  /// The bar that held the event when this reference was made. A hint that
  /// can go stale after a re-bar; see [ElementRef].
  final MeasureId measure;

  /// The staff the event is on.
  final StaffId staff;

  /// The event's identity.
  final EventId id;

  @override
  EventRef get event => this;

  @override
  bool operator ==(Object other) => other is EventRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A reference to one note head of a chord event.
final class NoteRef extends ElementRef {
  /// A reference to head [note] of [event].
  const NoteRef(this.event, this.note);

  @override
  final EventRef event;

  /// The head within the chord of [event].
  final NoteId note;

  @override
  bool operator ==(Object other) =>
      other is NoteRef && other.event == event && other.note == note;

  @override
  int get hashCode => Object.hash(event, note);
}
