import 'smufl_font.dart';

/// Everything that changes where things go. A change of style lays the
/// whole score out again. Colours live in the Flutter shell's palette and
/// only repaint.
///
/// Each convention the library's owner has not settled is a field here with
/// the default the library ships. RATIONALE "Open questions" lists them.
final class EngravingStyle {
  const EngravingStyle({
    this.font = SmuflFont.bravura,
    this.spacing = const SpacingPolicy(),
    this.graceScale = 0.66,
    this.quarterTones = QuarterToneGlyphs.steinZimmermann,
  });

  static const standard = EngravingStyle();

  final SmuflFont font;
  final SpacingPolicy spacing;

  /// Size of grace notes relative to normal notes.
  final double graceScale;

  final QuarterToneGlyphs quarterTones;

  @override
  bool operator ==(Object other) =>
      other is EngravingStyle &&
      other.font == font &&
      other.spacing == spacing &&
      other.graceScale == graceScale &&
      other.quarterTones == quarterTones;

  @override
  int get hashCode => Object.hash(font, spacing, graceScale, quarterTones);
}

/// Horizontal spacing, as springs between time slices with rods that keep
/// glyphs from touching.
///
/// The ideal space after a slice follows the shortest note sounding there, on
/// an absolute scale. A note twice as long gets [ratio] times the space. The
/// scale does not depend on other bars, which is what lets a bar be laid out
/// and cached alone.
final class SpacingPolicy {
  const SpacingPolicy({
    this.quarterSpace = 3.5,
    this.ratio = 1.41,
    this.minGap = 0.4,
    this.barPad = 1,
  });

  /// Ideal space after a quarter note, in staff spaces.
  final double quarterSpace;

  /// Space multiplier per doubling of duration.
  final double ratio;

  /// Least clear space between glyphs of neighbouring slices.
  final double minGap;

  /// Clear space between a bar's head, or the barline before it, and what
  /// the bar's first slice reaches to the left.
  final double barPad;

  @override
  bool operator ==(Object other) =>
      other is SpacingPolicy &&
      other.quarterSpace == quarterSpace &&
      other.ratio == ratio &&
      other.minGap == minGap &&
      other.barPad == barPad;

  @override
  int get hashCode => Object.hash(quarterSpace, ratio, minGap, barPad);
}

/// Which SMuFL family spells quarter-tone accidentals.
enum QuarterToneGlyphs {
  /// E280 to E283, MusicXML's default mapping.
  steinZimmermann,

  /// E271 to E274, with the natural-based arrows for a quarter step.
  gouldArrows,
}
