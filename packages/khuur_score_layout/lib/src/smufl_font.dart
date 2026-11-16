import 'bravura.g.dart';
import 'glyphs.dart';
import 'smufl_metadata.dart';

/// A SMuFL font, which is the family the painter draws with and the metrics
/// layout measures with. One object carries both, so the outlines on screen and
/// the metrics in layout cannot come from different fonts.
///
/// Invariant: [glyphs] has an entry for every [Glyph], so `font[glyph]` is
/// total. The generator guarantees it for [bravura], and
/// [SmuflFont.fromMetadata] checks it at the boundary.
///
/// Two fonts are equal when they name the same family, hold the same glyph
/// table by identity and have equal [defaults]. The const [bravura] is
/// canonical, so it equals itself everywhere. A font from
/// [SmuflFont.fromMetadata] has a glyph table of its own, so it equals
/// itself and its copies with equal defaults. An app parses its metadata
/// once and keeps the font. Parsing it again makes an unequal font, an
/// unequal style and a full layout.
final class SmuflFont {
  const SmuflFont({
    required this.family,
    required this.glyphs,
    required this.defaults,
  });

  /// Parses an app's own SMuFL font metadata (the `*_metadata.json` a SMuFL
  /// font ships) for a font the app declares under [family].
  ///
  /// Applies the generator's checks and throws one [FormatException] that
  /// names every failure. The failures are a [Glyph] with no box or an
  /// inverted one, a [Glyph] with no advance, an anchor name outside
  /// [GlyphAnchor], and a numeric engraving default that [EngravingDefaults]
  /// lacks or the metadata lacks. This is the only place font metadata is
  /// parsed at run time.
  factory SmuflFont.fromMetadata({
    required String family,
    required Map<String, Object?> metadata,
  }) {
    final (:glyphs, :defaults) = readSmuflMetadata(metadata);
    return SmuflFont(
      family: family,
      glyphs: glyphs,
      defaults: EngravingDefaults.read((name) => defaults[name]!),
    );
  }

  /// Bravura 1.392, shipped unmodified as the package font
  /// `fonts/Bravura.otf`, with metrics generated from its metadata.
  static const bravura = SmuflFont(
    family: 'Bravura',
    glyphs: bravuraGlyphs,
    defaults: bravuraDefaults,
  );

  /// The font family name the painter asks the text engine for.
  final String family;

  final Map<Glyph, GlyphMetrics> glyphs;
  final EngravingDefaults defaults;

  GlyphMetrics operator [](Glyph glyph) => glyphs[glyph]!;

  /// This font with other engraving defaults, which is how an app changes
  /// the thickness of stems, staff lines, barlines and the other lines.
  SmuflFont copyWith({EngravingDefaults? defaults}) => SmuflFont(
    family: family,
    glyphs: glyphs,
    defaults: defaults ?? this.defaults,
  );

  @override
  bool operator ==(Object other) =>
      other is SmuflFont &&
      other.family == family &&
      identical(other.glyphs, glyphs) &&
      other.defaults == defaults;

  @override
  int get hashCode => Object.hash(family, identityHashCode(glyphs), defaults);
}
