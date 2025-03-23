import 'package:flutter/rendering.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';

/// An abstract class representing a renderer for a musical symbol.
abstract class MusicalSymbolRenderer {
  MusicalSymbolRenderer(this.musicalSymbol);
  
  /// The musical symbol being rendered.
  final MusicalSymbol musicalSymbol;

  /// Checks if the symbol is hit at the given position.
  bool isHit(Offset position);

  /// Renders the symbol on the given canvas.
  void render(Canvas canvas);
  
  /// Gets the bounding rectangle of the symbol.
  Rect getBounds();
}
