import 'smufl_font.dart';
import 'text.dart';

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
    this.text = const {},
    this.graceScale = 0.66,
    this.staffGap = 4,
    this.lyricGap = 0.5,
    this.systemGap = 6,
    this.multiMeasureRests = false,
    this.meterEverySystem = false,
    this.courtesySignatures = true,
    this.justifyLastSystemFrom = 0.75,
    this.barNumbers = true,
    this.quarterTones = QuarterToneGlyphs.steinZimmermann,
    this.stringNumbers = StringNumbers.circled,
    this.chordSymbols = ChordSymbolSpelling.asStored,
    this.extenders = ExtenderEnd.beforeNextSyllable,
  });

  static const standard = EngravingStyle();

  final SmuflFont font;
  final SpacingPolicy spacing;

  /// Overrides of [TextRole.standard]. A role not listed keeps its default.
  final Map<TextRole, TextSpec> text;

  /// Size of grace notes relative to normal notes.
  final double graceScale;

  /// Least clear space between the bottom of one staff's content and the
  /// top of the next staff's content, in staff spaces.
  final double staffGap;

  /// Clear space above each lyric row, in staff spaces.
  final double lyricGap;

  /// Least clear space between two systems, in staff spaces.
  final double systemGap;

  /// Draw a run of rest-only bars as one bar with a count. Off by default
  /// because an editor needs every bar visible to write into.
  final bool multiMeasureRests;

  /// Restate the time signature at the start of every system, as some
  /// teaching material does. Off by default, as in engraving convention.
  final bool meterEverySystem;

  /// End a system with the key and time signature the next system changes
  /// to, unless the change itself says `noCourtesy`.
  final bool courtesySignatures;

  /// The last system is stretched to the full width only when its natural
  /// width is at least this fraction of it. Otherwise it stays ragged.
  final double justifyLastSystemFrom;

  /// Number the first bar of every system.
  final bool barNumbers;

  final QuarterToneGlyphs quarterTones;
  final StringNumbers stringNumbers;
  final ChordSymbolSpelling chordSymbols;
  final ExtenderEnd extenders;

  TextSpec specOf(TextRole role) => text[role] ?? role.standard;

  @override
  bool operator ==(Object other) =>
      other is EngravingStyle &&
      other.font == font &&
      other.spacing == spacing &&
      _sameText(other.text, text) &&
      other.graceScale == graceScale &&
      other.staffGap == staffGap &&
      other.lyricGap == lyricGap &&
      other.systemGap == systemGap &&
      other.multiMeasureRests == multiMeasureRests &&
      other.meterEverySystem == meterEverySystem &&
      other.courtesySignatures == courtesySignatures &&
      other.justifyLastSystemFrom == justifyLastSystemFrom &&
      other.barNumbers == barNumbers &&
      other.quarterTones == quarterTones &&
      other.stringNumbers == stringNumbers &&
      other.chordSymbols == chordSymbols &&
      other.extenders == extenders;

  @override
  int get hashCode => Object.hash(
    font,
    spacing,
    Object.hashAllUnordered(
      text.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    graceScale,
    staffGap,
    lyricGap,
    systemGap,
    multiMeasureRests,
    meterEverySystem,
    courtesySignatures,
    justifyLastSystemFrom,
    barNumbers,
    quarterTones,
    stringNumbers,
    chordSymbols,
    extenders,
  );
}

bool _sameText(Map<TextRole, TextSpec> a, Map<TextRole, TextSpec> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

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
    this.restRunWidth = 12,
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

  /// Width of a folded run of rest-only bars before justification.
  final double restRunWidth;

  @override
  bool operator ==(Object other) =>
      other is SpacingPolicy &&
      other.quarterSpace == quarterSpace &&
      other.ratio == ratio &&
      other.minGap == minGap &&
      other.barPad == barPad &&
      other.restRunWidth == restRunWidth;

  @override
  int get hashCode =>
      Object.hash(quarterSpace, ratio, minGap, barPad, restRunWidth);
}

/// Which SMuFL family spells quarter-tone accidentals.
enum QuarterToneGlyphs {
  /// E280 to E285, MusicXML's default mapping.
  steinZimmermann,

  /// E270 to E275.
  gouldArrows,
}

/// How string numbers print. Both count from the highest string, as the
/// exporter does (`strings.length - string`).
enum StringNumbers { circled, roman }

/// Whether chord symbols on a transposing staff print as stored or as the
/// written key would spell them.
enum ChordSymbolSpelling { asStored, written }

/// Where a lyric extender (`Lyric.extend`) stops.
enum ExtenderEnd {
  /// At the last note before the verse's next syllable or a rest.
  beforeNextSyllable,

  /// At the last note tied or slurred to the syllable's note.
  overTiesAndSlurs,
}
