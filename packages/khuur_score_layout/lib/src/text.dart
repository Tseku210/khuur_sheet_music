/// Text. The one input to layout that only the platform can measure.
library;

/// What a piece of text is, which decides its default look.
enum TextRole {
  /// A lyric syllable, and the hyphen between syllables.
  lyric(TextSpec(size: 2)),

  /// The text of a chord symbol.
  chordSymbol(TextSpec(size: 2.2)),

  /// A text direction, and the words of a tempo line such as `rit.`.
  expression(TextSpec(size: 2, italic: true)),

  /// A tempo mark.
  tempo(TextSpec(size: 2.2, bold: true)),

  /// A rehearsal mark, drawn in its enclosure.
  rehearsal(TextSpec(size: 2.4, bold: true)),

  /// The words of a To Coda, Fine or jump.
  navigation(TextSpec(size: 2, italic: true)),

  /// The label of a volta bracket.
  volta(TextSpec(size: 1.8)),

  /// A string number printed as a roman numeral.
  stringNumber(TextSpec(size: 1.6)),

  /// The number at the start of a system.
  barNumber(TextSpec(size: 1.5)),

  /// A part's name or short name at the start of a system.
  partName(TextSpec(size: 2)),

  /// The score's title in the header.
  title(TextSpec(size: 5)),

  /// The score's subtitle in the header.
  subtitle(TextSpec(size: 3)),

  /// The lyricist and composer in the header.
  credit(TextSpec(size: 2));

  /// A role whose text looks like [standard] unless the style overrides it.
  TextRole(this.standard);

  /// The look of this role's text when `EngravingStyle.text` does not
  /// override it.
  final TextSpec standard;
}

/// How to set one piece of text. Sizes are in staff spaces, so text scales
/// with the staff and a bar's layout does not change with zoom.
final class TextSpec {
  /// A spec of [size] in staff spaces, upright and regular weight unless
  /// [italic] or [bold] says otherwise.
  const TextSpec({
    required this.size,
    this.italic = false,
    this.bold = false,
    this.family,
  });

  /// The font size in staff spaces.
  final double size;

  /// Whether the text is set in italics.
  final bool italic;

  /// Whether the text is set in bold.
  final bool bold;

  /// Null for the platform's default text font.
  final String? family;

  @override
  bool operator ==(Object other) =>
      other is TextSpec &&
      other.size == size &&
      other.italic == italic &&
      other.bold == bold &&
      other.family == family;

  @override
  int get hashCode => Object.hash(size, italic, bold, family);
}

/// A measured run of text in staff spaces, from its origin on the baseline.
final class TextExtent {
  /// An extent of [width] that reaches [ascent] above the baseline and
  /// [descent] below it.
  const TextExtent({
    required this.width,
    required this.ascent,
    required this.descent,
  });

  /// The advance from the origin to the end of the run.
  final double width;

  /// How far the run reaches above the baseline, as a positive length.
  final double ascent;

  /// How far the run reaches below the baseline, as a positive length.
  final double descent;

  @override
  bool operator ==(Object other) =>
      other is TextExtent &&
      other.width == width &&
      other.ascent == ascent &&
      other.descent == descent;

  @override
  int get hashCode => Object.hash(width, ascent, descent);
}

/// Measures text for layout. The Flutter shell implements it with `dart:ui`
/// paragraphs. Tests use a fixed-pitch fake, so layout runs off device and
/// gives the same breaks on every host.
///
/// Implementations must be pure. The same text and spec give the same extent
/// for the measurer's lifetime. Layout caches bars on that promise.
abstract interface class TextMeasurer {
  /// The extent of [text] set as [spec], in staff spaces.
  TextExtent measure(String text, TextSpec spec);
}
