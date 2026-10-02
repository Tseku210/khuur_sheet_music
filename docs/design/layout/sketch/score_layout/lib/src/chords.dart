/// Chords and rests. Heads, accidentals, dots, stems, flags, ledger lines and
/// grace notes. Not exported.
///
/// A chord is planned before spacing (which glyphs, on which steps, on
/// which side of the stem, how wide) and placed after it (against which
/// slice). The plan carries its reach, so spacing keeps slices apart
/// without knowing what a chord is.
library;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'drawable.dart';
import 'glyphs.dart';
import 'spacing.dart';
import 'style.dart';

enum StemSide { up, down }

/// One notehead as planned.
final class HeadPlan {
  const HeadPlan({
    required this.id,
    required this.glyph,
    required this.step,
    required this.flipped,
    this.accidental,
    this.cautionary = false,
    this.ink = InkRole.normal,
  });

  final NoteId id;
  final Glyph glyph;

  /// Staff step, 0 at the bottom line. A pitched note takes it from
  /// `Clef.staffStepOf` of its written pitch (`StaffView.writtenPitches`,
  /// under the clef in effect at its onset). A drum note takes it from its
  /// kit sound's position.
  final int step;

  /// On the far side of the stem because of a second with its neighbour.
  final bool flipped;

  final Glyph? accidental;

  /// Print the accidental in parentheses.
  final bool cautionary;

  /// [InkRole.outOfRange] for a note outside its instrument's range.
  final InkRole ink;
}

final class ChordPlan {
  const ChordPlan({
    required this.timed,
    required this.chord,
    required this.stem,
    required this.heads,
    required this.dots,
    required this.flag,
    required this.reach,
    required this.graces,
  });

  final TimedEvent timed;
  final ChordEvent chord;
  final StemSide stem;

  /// Sorted by step, lowest first.
  final List<HeadPlan> heads;
  final int dots;

  /// Null for a quarter or longer. A beamed chord keeps its flag here and
  /// [placeChord] leaves it out.
  final Glyph? flag;

  /// Accidentals and grace notes to the left of the slice line. Flipped
  /// heads, dots and the flag to the right.
  final SliceReach reach;

  /// Grace chords in order, planned at the style's grace scale.
  final List<GracePlan> graces;
}

/// One grace chord before a principal. Built by [planChord], which keeps its
/// drawables with it.
final class GracePlan {
  const GracePlan({required this.source, required this.heads, required this.x});

  final GraceChord source;
  final List<HeadPlan> heads;

  /// The grace's own slice line against the principal's, negative.
  final double x;
}

/// A planned chord with its place in the bar. Beams, ties, tuplets and
/// spanners find their ends through it.
typedef PlacedChord = ({ChordPlan plan, int slice, int staff});

/// The stem side of [chord]. A stored `ChordEvent.stem` wins. With two or
/// more voices on the staff the voice decides (`VoiceSlot.stemsUp`). With
/// one voice the mean step against the middle line decides, and a chord
/// centred on it stems down. The steps follow the clef in force [at] the
/// chord. A beam group overrides this with one side for all its chords (see
/// `beamStemSides`).
StemSide stemSideFor(
  ChordEvent chord,
  StaffView staff,
  VoiceSlot slot, {
  required Moment at,
}) => throw UnimplementedError();

/// Plans [chord]. The plan has head glyphs from its value and
/// `StaffView.headOf`, steps, flipped heads for seconds, accidentals from
/// `StaffView.accidentals` stacked right to left by descending step, dots in
/// the next space up, the flag from the value, and each grace chord. It also
/// holds its drawables against its own slice line, built once here, so the
/// reach, the beam and the items read the same ink. A [beamed] chord is
/// planned without its stem and flag.
ChordPlan planChord({
  required TimedEvent timed,
  required ChordEvent chord,
  required StaffView staff,
  required StemSide stem,
  required bool beamed,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The chord's items against [slice]. They are heads, accidentals, dots, ledger
/// lines (for steps below 0 or above 8, extended by `legerLineExtension`, each
/// spanning the heads on it or beyond it) and tremolo strokes. An unbeamed
/// chord with a stem in its value also gets its stem, from the outer head's
/// `stemUpSE` or `stemDownNW` anchor to a tip 3.5 spaces beyond the far head
/// and never short of the middle line, and its flag at the tip. Dots that a
/// flag would reach move past the flag. A tremolo lengthens the stem until the
/// tip, or the flag, clears the strokes, and on a stemless chord its strokes
/// are centred on the heads. A beamed chord gets neither stem nor flag. Its
/// stem depends on the stretch, so `placeBeam` draws it at system time. An
/// accidental clears a ledger line's extension as it clears a head.
///
/// A head is owned by its `NoteRef`. Everything else is owned by the
/// event's `EventRef`.
List<BarItem> placeChord(
  ChordPlan plan, {
  required int slice,
  required int staff,
}) => throw UnimplementedError();

/// Where the chord's stem leaves its start head, the y of its far head, and
/// the y a beam's inner edge must stay beyond (`keep`, the far head's y or the
/// far edge of the tremolo strokes plus their clearance), against the chord's
/// slice line, for `planBeam`.
({double x, double start, double far, double keep}) stemOf(ChordPlan plan) =>
    throw UnimplementedError();

/// The grace chords of [plan], left of the principal at the style's grace
/// scale, each with its stem up and its flag, and a slash through the stem of
/// each acciaccatura where the font's eighth flag puts it, whatever the grace's
/// value. The ties of grace notes are unit 7's, by the rule below.
///
/// A grace chord has no reference of its own, so every grace drawable, heads
/// included, is owned by the principal's `EventRef`, and `TieView` cannot name
/// a grace. A tied grace note is drawn by one rule. It joins the head of the
/// same `Note.tone` in the next grace chord of this principal, or in the
/// principal when it is the last grace. This is the rule the model uses for
/// ordinary ties. With no head of that tone there, the tie is a short let-ring
/// stub. The curve lies inside one slice's reach, so it is a bar item and never
/// crosses a barline.
List<BarItem> graceItems(
  ChordPlan plan, {
  required int slice,
  required int staff,
}) => throw UnimplementedError();

/// Where each head of [chords] is, for ties, slurs and glissandi. An anchor is
/// the head's centre against its chord's slice.
Map<NoteId, BarAnchor> headAnchors(
  Iterable<PlacedChord> chords,
  EngravingStyle style,
) => throw UnimplementedError();

/// How far a rest's glyph and dots reach from its slice line. A
/// `MeasureRest` is centred in its bar and reaches nowhere.
SliceReach restReach(Event rest, EngravingStyle style) =>
    throw UnimplementedError();

/// A rest's glyph from its value, on the middle line, moved up for an
/// upstem voice and down for a downstem voice when the staff has
/// [voiceCount] of two or more. A hidden rest draws nothing. A
/// `MeasureRest` is a whole rest centred between the first slice and
/// [lastSlice] at stretch 1 ([xs]), hung from step 6, or from the line of a
/// one-line staff ([lines]).
List<BarItem> placeRest({
  required TimedEvent timed,
  required int slice,
  required int lastSlice,
  required int staff,
  required int voiceCount,
  required int lines,
  required List<double> xs,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// A run of [count] rest-only bars as one H-bar rest between [left] and
/// [right] on each staff of [tops], with the count above it in `timeSig`
/// digits. Drawn at system time, because the run's width is the system's.
List<Drawable> placeRestRun(
  int count, {
  required double left,
  required double right,
  required List<double> tops,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// How far the count of a folded rest run reaches above the top line. No
/// bar of the run holds the count, so planning adds this to the run's
/// room.
double restRunRise(EngravingStyle style) => throw UnimplementedError();

/// The head glyph for a value and a head shape. A breve takes the
/// `DoubleWhole` glyph of the shape, a whole and a half their own, and a
/// quarter or shorter the black one.
Glyph noteheadGlyph(DurationBase base, NoteHead head) =>
    throw UnimplementedError();

Glyph restGlyph(DurationBase base) => throw UnimplementedError();

/// The accidental glyph for [alter] in the chosen quarter-tone family.
Glyph accidentalGlyph(Alter alter, QuarterToneGlyphs family) =>
    throw UnimplementedError();
