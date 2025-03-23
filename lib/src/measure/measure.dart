import 'dart:core';

import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/measure/measure_utils.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef_type.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/key_signature.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/keysignature_type.dart';
import 'package:simple_sheet_music/src/music_objects/time_signature/time_signature.dart';
import 'package:simple_sheet_music/src/musical_context.dart';

/// Represents a measure in sheet music.
class Measure {
  /// Creates a new instance of the [Measure] class.
  ///
  /// The [musicalSymbols] parameter is a list of musical symbols that make up the measure.
  /// The [isNewLine] parameter indicates whether the measure is a new line in the sheet music.
  ///
  /// Throws an [AssertionError] if the [musicalSymbols] list is empty.
  const Measure(
    this.musicalSymbols, {
    this.isNewLine = false,
  }) : assert(musicalSymbols.length != 0);

  /// The list of musical symbols that make up the measure.
  final List<MusicalSymbol> musicalSymbols;

  /// Indicates whether the measure is a new line in the sheet music.
  final bool isNewLine;

  /// Sets the context for the measure and returns a list of musical symbol metrics.
  ///
  /// The [context] parameter is the musical context in which the measure is being rendered.
  /// The [metadata] parameter provides metadata for the glyphs used in the measure.
  /// The [paths] parameter provides the paths for the glyphs used in the measure.
  ///
  /// Returns a list of [MusicalSymbolMetrics] objects representing the metrics of each musical symbol in the measure.
  List<MusicalSymbolMetrics> setContext(
    MusicalContext context,
    GlyphMetadata metadata,
    GlyphPaths paths,
  ) {
    final result = <MusicalSymbolMetrics>[];
    var symbolContext = context;
    for (final symbol in musicalSymbols) {
      final symbolMetrics = symbol.setContext(symbolContext, metadata, paths);
      symbolContext = symbolContext.update(symbol);
      result.add(symbolMetrics);
    }
    return result;
  }

  ClefType? get lastClefType {
    for (final symbol in musicalSymbols.reversed) {
      if (symbol is Clef) {
        return symbol.clefType;
      }
    }
    return null;
  }

  KeySignatureType? get lastKeySignatureType {
    for (final symbol in musicalSymbols.reversed) {
      if (symbol is KeySignature) {
        return symbol.keySignatureType;
      }
    }
    return null;
  }

  MusicalContext updateContext(MusicalContext context) => context.updateWith(
        clefType: lastClefType,
        keySignatureType: lastKeySignatureType,
      );

  /// Validates the measure against the given time signature.
  bool validate(TimeSignature timeSignature) {
    return validateMeasureDuration(this, timeSignature);
  }

  /// Returns a list of validation errors for the measure.
  List<String> getValidationErrors(TimeSignature timeSignature) {
    return getMeasureValidationErrors(this, timeSignature);
  }

  /// Calculates the real-time duration of this measure in seconds based on tempo.
  double getDurationInSeconds(TimeSignature timeSignature, int tempo) {
    return calculateMeasureDurationInSeconds(timeSignature.timeSignatureType, tempo);
  }
  
  /// Calculates the real-time duration of a specific musical symbol in seconds based on tempo.
  /// 
  /// For example, in 4/4 time at 120 BPM:
  /// - A quarter note (1.0 beats) = 0.5 seconds
  /// - A half note (2.0 beats) = 1.0 seconds
  /// - A whole note (4.0 beats) = 2.0 seconds
  double getSymbolDurationInSeconds(MusicalSymbol symbol, int tempo) {
    return calculateSymbolDurationInSeconds(symbol, tempo);
  }
}
