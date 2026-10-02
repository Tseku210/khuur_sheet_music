/// Marks. Everything attached to a chord or a time that is not a head, a stem
/// or a beam. That is articulations, ornaments, bowing, fingering, string
/// numbers, dynamics, text, chord symbols, tempo and rehearsal marks,
/// navigation marks, and tuplet numbers and brackets. Not exported.
///
/// Marks stack outside the staff against a [Skyline], so none overlaps
/// another or the notes. Each takes the next free room on its side, in the
/// order the bar calls these functions. The skyline works at stretch 1.
/// Justification only spreads slices, so what cleared at stretch 1 clears on
/// a stretched system. A bar compressed to its rods can still collide, and
/// that bar is already wider than its system.
///
/// A mark never leaves its bar sideways. [markReach] widens the slices
/// until the rods alone hold every mark between the bar's content start and
/// its end, so a system of one bar pressed to its rods still holds them.
library;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'chords.dart';
import 'drawable.dart';
import 'glyphs.dart';
import 'spacing.dart';
import 'style.dart';
import 'text.dart';

/// [reach] widened until the bar's rods hold every mark of [view] inside
/// the bar.
///
/// A mark of an event is centred on it, so what passes the event's own
/// reach on either side widens its slice. A tuplet's number needs the rods
/// between its ends. A direction or a tempo mark needs the rods from its
/// slice to the next mark of its lane, or to the bar's end, to hold what it
/// reaches to the right, and the rods before its slice to hold what it
/// reaches to the left. A mark held at the bar's start or end needs the
/// whole bar. What is missing is shared evenly by the slices it spans, so a
/// long tempo mark opens no gap after its own note. What a line starts with
/// is `lineStartReach` in `spanners.dart`, merged by the bar before this.
/// [trills] is [trillLineStarts].
List<SliceReach> markReach(
  MeasureView view,
  Map<EventId, PlacedChord> chords,
  List<SliceReach> reach, {
  required List<Moment> times,
  required Set<EventId> trills,
  required EngravingStyle style,
  required TextMeasurer text,
}) => throw UnimplementedError();

/// One glyph per `Articulation` but the fermata, in the SMuFL `Above` or
/// `Below` variant, nearest the head in the order staccato, staccatissimo,
/// tenuto, accent, marcato, harmonic.
///
/// A voice alone on its staff ([voices] is 1) puts them on the head side,
/// and the harmonic above. Staccato and tenuto then sit in the next space
/// that is clear of the head, which is the next space for a head in a space
/// and the one after it for a head on a line, as long as that space is
/// inside the staff or between the staff and the head. Every other mark,
/// and every mark after the first that leaves the staff, stacks outside the
/// staff. With two voices or more every mark stacks outside the staff on
/// its voice's side, which is the stem side.
List<BarItem> articulationItems(
  PlacedChord chord,
  Skyline skyline, {
  required int voices,
  required List<double> xs,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The fermata of a chord or a rest, outside every other mark of its event,
/// so the bar calls this after them. It goes above, and on a staff with two
/// voices or more on its voice's side, inverted below. A measure rest's is
/// centred in the bar with its rest and keeps the whole bar's width clear,
/// since a stretch moves it against the bar's slices. A hidden rest draws
/// none.
List<BarItem> fermataItems(
  TimedEvent timed,
  Skyline skyline, {
  required PlacedChord? chord,
  required int slice,
  required int staff,
  required int voices,
  required List<double> xs,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The events a trill line starts on. Such a chord leaves its trill sign to
/// the line, which draws one.
Set<EventId> trillLineStarts(MeasureView view) => throw UnimplementedError();

/// The ornament above the staff, centred on the chord, or on its voice's
/// side on a staff with two voices or more. A trill whose chord starts a
/// `TrillLine` ([lineStarts]) leaves the sign to the spanner.
List<BarItem> ornamentItems(
  PlacedChord chord,
  Skyline skyline, {
  required int voices,
  required bool lineStarts,
  required List<double> xs,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The marks of a string player, nearest the chord first. Those are each
/// head's fingering, each head's string number, then the bowing. All go
/// above, or on their voice's side on a staff with two voices or more, and
/// the marks of several heads stack in head order with the highest head's
/// on top. A string number counts from the highest of the instrument's
/// [strings], as a circled digit or a roman numeral (`style.stringNumbers`).
/// A string the instrument does not have draws nothing.
List<BarItem> stringMarkItems(
  PlacedChord chord,
  Skyline skyline, {
  required int voices,
  required int strings,
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) => throw UnimplementedError();

/// The glyph of a dynamic level. Each level is one glyph of the font, `fp`
/// and `sfz` included.
Glyph dynamicGlyph(Dynamic level) => throw UnimplementedError();

/// The directions of one staff at their slices, the dynamics first, then
/// the text marks, then the chord symbols, each kind in stored order.
/// Dynamics go below, with their `opticalCenter` under the middle of a
/// notehead on the slice. Text marks go on their stored side and chord
/// symbols above, both starting at the slice line. A chord symbol's
/// accidentals are `csym` glyphs, and its root and bass are spelled as
/// `style.chordSymbols` asks. An empty text draws nothing.
List<BarItem> directionItems(
  StaffView view,
  Skyline skyline, {
  required int staff,
  required List<Moment> times,
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) => throw UnimplementedError();

/// What the bar prints above its top staff, in the order it stacks. Each
/// tempo mark starts at its slice line, as its words, then its metronome
/// note, then `= ` and its number. Segno and coda start at [left], the
/// bar's content start. `ToCoda.label`, `Fine.label` and `Jump.label` (B2c)
/// end just before the bar's end. The rehearsal mark starts at [left] in a
/// box, outside the rest. The items sit on staff 0, against [top]. A mark
/// with nothing to print draws nothing.
List<BarItem> systemMarkItems(
  MeasureView view,
  Skyline top, {
  required List<Moment> times,
  required List<double> xs,
  required double left,
  required EngravingStyle style,
  required TextMeasurer text,
}) => throw UnimplementedError();

/// Metronome glyphs for a beat value, which are the `metNote` of its base,
/// then one `metAugmentationDot` per dot. Empty for a breve and for a value
/// shorter than a sixteenth, which the font's table has no note for. A
/// tempo mark with such a beat prints its words alone.
List<Glyph> metronomeGlyphs(NoteValue beat) => throw UnimplementedError();

/// A tuplet's number and bracket, decided in bar space. The system draws
/// it, because a bracket spans slices that the stretch moves apart.
final class TupletStub {
  const TupletStub({
    required this.owner,
    required this.first,
    required this.last,
    required this.digits,
    required this.bracket,
    required this.side,
  });

  /// The tuplet's first event.
  final Owner owner;

  /// The bracket's ends, at the left edge of the first event's heads or
  /// rest and the right edge of the last's, already clear of the skyline.
  /// Both are at one height, the bracket's line, which runs through the
  /// middle of the number.
  final BarAnchor first;
  final BarAnchor last;

  /// The number, or the ratio with `tupletColon` when the tuplet's ratio
  /// is not the usual one for its number.
  final List<Glyph> digits;

  /// False when the tuplet's events are exactly one beam group and it is
  /// `TupletBracket.auto`, or when it is `hidden`.
  final bool bracket;

  final Side side;

  /// By value, so a bar that lays out the same compares equal.
  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();
}

/// The tuplets of one voice, innermost first, so an inner bracket sits
/// nearer the notes. Each goes on the side most of its chords' stems point
/// to, which is the beam side of a beamed tuplet, above when the sides are
/// even, and on its voice's side when it holds rests alone. Each reserves
/// one row of [skyline] from its first event to its last, as high as its
/// number, where the number and the bracket are drawn at any stretch.
List<TupletStub> tupletStubs(
  VoiceView voice,
  Map<EventId, PlacedChord> chords,
  Skyline skyline, {
  required int staff,
  required List<Moment> times,
  required List<double> xs,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The number centred between the ends, and the bracket as two lines with
/// hooks, `tupletBracketThickness` thick, broken around the number. The
/// hooks point to the notes and are half as long as the number is high. A
/// bracket with no room for a line on each side of its number is left out.
List<Drawable> placeTuplet(
  TupletStub stub,
  BarFrame frame,
  EngravingStyle style,
) => throw UnimplementedError();
