/// Where glyphs and text land, with the bounds they cover. Not exported.
library;

import 'drawable.dart';
import 'geometry.dart';
import 'glyphs.dart';
import 'smufl_font.dart';
import 'text.dart';

/// [glyph] drawn at [origin] at [scale], with the font's ink box for it
/// scaled and shifted to the same origin.
GlyphDraw glyphAt(
  SmuflFont font,
  Glyph glyph,
  SpPoint origin, {
  required InkRole ink,
  double scale = 1,
  Owner? owner,
}) => GlyphDraw(
  glyph,
  origin,
  bounds: font[glyph].box.scaled(scale).shift(origin.x, origin.y),
  ink: ink,
  scale: scale,
  owner: owner,
);

/// The box of a text run.
extension TextBox on TextExtent {
  /// The box of this run with its origin at [x] on [baseline].
  Box boxAt(double x, double baseline) =>
      Box(x, baseline - ascent, x + width, baseline + descent);
}
