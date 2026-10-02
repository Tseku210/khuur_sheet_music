/// Text. The one input to layout that only the platform can measure.
library;

/// What a piece of text is, which decides its default look.
enum TextRole {
  lyric(TextSpec(size: 2)),
  chordSymbol(TextSpec(size: 2.2)),
  expression(TextSpec(size: 2, italic: true)),
  tempo(TextSpec(size: 2.2, bold: true)),
  rehearsal(TextSpec(size: 2.4, bold: true)),
  navigation(TextSpec(size: 2, italic: true)),
  volta(TextSpec(size: 1.8)),
  barNumber(TextSpec(size: 1.5)),
  partName(TextSpec(size: 2)),
  title(TextSpec(size: 5)),
  subtitle(TextSpec(size: 3)),
  credit(TextSpec(size: 2));

  TextRole(this.standard);

  final TextSpec standard;
}

/// How to set one piece of text. Sizes are in staff spaces, so text scales
/// with the staff and a bar's layout does not change with zoom.
final class TextSpec {
  const TextSpec({
    required this.size,
    this.italic = false,
    this.bold = false,
    this.family,
  });

  /// The font size in staff spaces.
  final double size;
  final bool italic;
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
  const TextExtent({
    required this.width,
    required this.ascent,
    required this.descent,
  });

  final double width;
  final double ascent;
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
  TextExtent measure(String text, TextSpec spec);
}
