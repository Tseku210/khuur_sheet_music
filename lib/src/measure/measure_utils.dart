import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/time_signature/time_signature.dart';
import 'package:simple_sheet_music/src/music_objects/time_signature/time_signature_type.dart';

/// Utility functions for measure operations, validation, and time calculations.

// Duration calculation functions

/// Calculates the expected duration in beats for a given time signature.
double calculateExpectedDuration(TimeSignatureType timeSignature) {
  // For simple meters, the number of beats is the numerator (top number)
  // and the beat unit is determined by the denominator (bottom number)
  return timeSignature.beats * (4 / timeSignature.beatUnit);
}

/// Calculates the real-time duration in seconds based on tempo (BPM).
/// Formula: (beats * 60) / tempo
double calculateDurationInSeconds(double beats, int tempo) {
  return (beats * 60) / tempo;
}

/// Calculates the real-time duration of a measure in seconds based on tempo.
double calculateMeasureDurationInSeconds(
  TimeSignatureType timeSignature,
  int tempo,
) {
  final beatCount = calculateExpectedDuration(timeSignature);
  return calculateDurationInSeconds(beatCount, tempo);
}

/// Calculates the real-time duration of a musical symbol in seconds based on tempo.
double calculateSymbolDurationInSeconds(MusicalSymbol symbol, int tempo) {
  return calculateDurationInSeconds(symbol.duration, tempo);
}

// Validation functions

/// Validates if a measure has the correct duration according to its time signature.
bool validateMeasureDuration(Measure measure, TimeSignature timeSignature) {
  return getMeasureValidationErrors(measure, timeSignature).isEmpty;
}

/// Gets validation errors for a measure based on its time signature.
List<String> getMeasureValidationErrors(
  Measure measure,
  TimeSignature timeSignature,
) {
  final errors = <String>[];

  // Calculate the total duration of all symbols in the measure
  final totalDuration = measure.musicalSymbols.fold<double>(
    0,
    (sum, symbol) => sum + symbol.duration,
  );

  // Calculate the expected duration based on the time signature
  final expectedDuration = calculateExpectedDuration(timeSignature.timeSignatureType);

  // Check if the total duration matches the expected duration
  if (totalDuration != expectedDuration) {
    errors.add(
      'Duration mismatch: expected $expectedDuration beats, got $totalDuration beats',
    );
  }

  return errors;
} 