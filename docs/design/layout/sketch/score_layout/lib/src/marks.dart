/// Marks. Everything attached to a chord or a time that is not a head, a stem
/// or a beam. That is articulations, ornaments, bowing, fingering, string
/// numbers, dynamics, text, chord symbols, tempo and rehearsal marks,
/// navigation marks, and tuplet numbers and brackets. Not exported.
///
/// Marks stack outside the staff against a [Skyline], so none overlaps
/// another or the notes. The skyline works at stretch 1. Justification
/// only spreads slices, so what cleared at stretch 1 clears on a stretched
/// system. A bar compressed to its rods can still collide, and that bar is
/// already wider than its system.
library;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'chords.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'glyphs.dart';
import 'spacing.dart';
import 'style.dart';
import 'text.dart';

/// The reach text and wide marks add to their slices, for spacing. Those are
/// chord symbols, text directions, dynamics, tempo marks and the rehearsal
/// mark. What a line starts with at its own start is `lineStartReach` in
/// `spanners.dart`, merged by the bar after the chords are planned.
List<SliceReach> markReach(
  MeasureView view,
  List<Moment> times,
  EngravingStyle style,
  TextMeasurer text,
) => throw UnimplementedError();

/// One glyph per `Articulation`, in the SMuFL `Above` or `Below` variant.
/// Staccato and tenuto go on the head side, inside the staff when a space
/// is free. Accent, marcato and staccatissimo go outside the staff on the
/// head side. Fermata and harmonic always go above.
List<BarItem> articulationItems(
  PlacedChord chord,
  Skyline skyline, {
  required List<double> xs,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The ornament above the staff, centred on the chord. A trill whose chord
/// starts a `TrillLine` leaves the wiggle to the spanner.
List<BarItem> ornamentItems(
  PlacedChord chord,
  Skyline skyline, {
  required List<double> xs,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// Bowing above, fingering above each head in head order, and string
/// numbers as circled glyphs or roman text (`style.stringNumbers`),
/// counted from the highest string.
List<BarItem> stringMarkItems(
  PlacedChord chord,
  Skyline skyline, {
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) => throw UnimplementedError();

/// The glyphs of a dynamic level, one for `mf` and forte then piano for `fp`.
List<Glyph> dynamicGlyphs(Dynamic level) => throw UnimplementedError();

/// The directions of one staff at their slices. Dynamics go below, centred by
/// `opticalCenter`. Text marks go on their stored side. Chord symbols go above,
/// with accidentals as `csym` glyphs and the spelling `style.chordSymbols` asks
/// for.
List<BarItem> directionItems(
  StaffView view,
  Skyline skyline, {
  required int staff,
  required List<Moment> times,
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) => throw UnimplementedError();

/// What the bar prints above its top staff. That is each tempo mark as text and
/// metronome glyphs at its slice, the rehearsal mark in a box at the bar's
/// start, segno and coda at the start, and `Jump.label` (B2c), Fine and To Coda
/// as text at the end. The items sit on staff 0, against [top].
List<BarItem> systemMarkItems(
  MeasureView view,
  Skyline top, {
  required List<Moment> times,
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) => throw UnimplementedError();

/// Metronome glyphs for a beat value, which are the `metNote` of its base, then
/// one `metAugmentationDot` per dot.
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

  /// The bracket's ends, already clear of the skyline.
  final BarAnchor first;
  final BarAnchor last;

  /// The number, or the ratio with `tupletColon` when the tuplet's ratio
  /// is not the default for its number.
  final List<Glyph> digits;

  /// False when the tuplet is fully beamed and `TupletBracket.auto`, or
  /// `hidden`.
  final bool bracket;

  final Side side;
}

/// The tuplets of one voice, outermost last so an inner bracket sits
/// nearer the notes. Each goes on the beam side, or the stem side of
/// unbeamed notes, and reserves its room in [skyline].
List<TupletStub> tupletStubs(
  VoiceView voice,
  Map<EventId, PlacedChord> chords,
  Skyline skyline, {
  required List<double> xs,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The number centred between the ends, and the bracket as two lines with
/// hooks, `tupletBracketThickness` thick, broken around the number.
List<Drawable> placeTuplet(
  TupletStub stub,
  BarFrame frame,
  EngravingStyle style,
) => throw UnimplementedError();
