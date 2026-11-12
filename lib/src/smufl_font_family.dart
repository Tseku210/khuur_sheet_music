import 'package:score_layout/score_layout.dart';

/// The name Flutter knows a [SmuflFont] by.
extension SmuflFontFamily on SmuflFont {
  /// The family to give `TextStyle.fontFamily` to draw this font's glyphs,
  /// which is the family the sheet's painter asks for. For the bundled
  /// Bravura, a copy of it with other engraving defaults included, it is
  /// [family] with the prefix Flutter gives a package's font. For a font the
  /// app declares it is [family] itself.
  ///
  /// A palette draws a value's glyph, as from `noteGlyph`, with
  /// `Text(String.fromCharCode(glyph.codepoint), style: TextStyle(fontFamily:
  /// SmuflFont.bravura.flutterFamily))`.
  String get flutterFamily =>
      family == SmuflFont.bravura.family &&
          identical(glyphs, SmuflFont.bravura.glyphs)
      ? 'packages/khuur_sheet_music/Bravura'
      : family;
}
