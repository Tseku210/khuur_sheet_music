/// Bar edges. Not exported.
///
/// The clefs, key and time signatures of the sketch's `signatures.dart`
/// arrive with the unit that draws them. Spacing needs the end barline's
/// width before that, so that piece is here.
library;

import 'package:score_model/score_model.dart';

import 'glyphs.dart';
import 'style.dart';

/// What a bar's edges are, for the barlines the system draws.
typedef BarEdges = ({
  /// The bar opens a repeat.
  bool repeatStart,

  /// The bar's inline head prints no signature, so a start repeat here can
  /// join the end repeat of the bar before it into one sign.
  bool startJoins,
  Barline end,
  RepeatEnd? repeatEnd,
});

/// The width of the bar's end barline with its repeat dots, which is the
/// rod of the bar's last slice.
double endBarlineWidth(BarEdges edges, EngravingStyle style) {
  final defaults = style.font.defaults;
  final thin = defaults.thinBarlineThickness;
  final thick = defaults.thickBarlineThickness;
  final gap = defaults.barlineSeparation;
  if (edges.repeatEnd != null) {
    final dots = style.font[Glyph.repeatDot].box.width;
    return dots + defaults.repeatBarlineDotSeparation + thin + gap + thick;
  }
  return switch (edges.end) {
    Barline.regular => thin,
    Barline.doubleBar => thin + gap + thin,
    Barline.finalBar => thin + gap + thick,
    Barline.heavy => thick,
    Barline.dashed || Barline.dotted => defaults.dashedBarlineThickness,
    Barline.invisible => 0,
  };
}
