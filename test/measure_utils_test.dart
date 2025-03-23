import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/measure/measure_utils.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_duration.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_pitch.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest_type.dart';
import 'package:simple_sheet_music/src/music_objects/time_signature/time_signature.dart';
import 'package:simple_sheet_music/src/music_objects/time_signature/time_signature_type.dart';

void main() {
  group('Measure Validation Tests - Simple Meters', () {
    test('Valid 4/4 measure with whole note', () {
      final measure = Measure([
        Note(Pitch.c4, noteDuration: NoteDuration.whole),
      ]);
      final timeSignature = TimeSignature.fourFour();

      expect(measure.validate(timeSignature), true);
      expect(measure.getValidationErrors(timeSignature), isEmpty);
    });

    test('Valid 4/4 measure with four quarter notes', () {
      final measure = Measure([
        Note(Pitch.c4),
        Note(Pitch.d4),
        Note(Pitch.e4),
        Note(Pitch.f4),
      ]);
      final timeSignature = TimeSignature.fourFour();

      expect(measure.validate(timeSignature), true);
      expect(measure.getValidationErrors(timeSignature), isEmpty);
    });

    test('Valid 4/4 measure with mixed durations', () {
      final measure = Measure([
        Note(Pitch.c4, noteDuration: NoteDuration.half),
        Note(Pitch.e4),
        Note(Pitch.g4),
      ]);
      final timeSignature = TimeSignature.fourFour();

      expect(measure.validate(timeSignature), true);
      expect(measure.getValidationErrors(timeSignature), isEmpty);
    });

    test('Valid 4/4 measure with rests', () {
      final measure = Measure([
        Note(Pitch.c4),
        Rest(RestType.quarter),
        Note(Pitch.e4, noteDuration: NoteDuration.half),
      ]);
      final timeSignature = TimeSignature.fourFour();

      expect(measure.validate(timeSignature), true);
      expect(measure.getValidationErrors(timeSignature), isEmpty);
    });

    test('Invalid 4/4 measure - too long', () {
      final measure = Measure([
        Note(Pitch.c4, noteDuration: NoteDuration.whole),
        Note(Pitch.d4),
      ]);
      final timeSignature = TimeSignature.fourFour();

      expect(measure.validate(timeSignature), false);
      expect(measure.getValidationErrors(timeSignature), isNotEmpty);
      expect(
        measure.getValidationErrors(timeSignature).first,
        contains('Duration mismatch'),
      );
    });

    test('Invalid 4/4 measure - too short', () {
      final measure = Measure([
        Note(Pitch.c4, noteDuration: NoteDuration.half),
        Note(Pitch.e4),
      ]);
      final timeSignature = TimeSignature.fourFour();

      expect(measure.validate(timeSignature), false);
      expect(measure.getValidationErrors(timeSignature), isNotEmpty);
      expect(
        measure.getValidationErrors(timeSignature).first,
        contains('Duration mismatch'),
      );
    });

    test('Valid 3/4 measure', () {
      final measure = Measure([
        Note(Pitch.c4, noteDuration: NoteDuration.half),
        Note(Pitch.e4),
      ]);
      final timeSignature = TimeSignature.threeFour();

      expect(measure.validate(timeSignature), true);
      expect(measure.getValidationErrors(timeSignature), isEmpty);
    });

    test('Valid 2/2 measure', () {
      final measure = Measure([
        Note(Pitch.c4, noteDuration: NoteDuration.whole),
      ]);
      final timeSignature = TimeSignature.twoTwo();

      expect(measure.validate(timeSignature), true);
      expect(measure.getValidationErrors(timeSignature), isEmpty);
    });
  });

  group('Duration Calculation Tests - Tempo', () {
    test('4/4 measure duration at 60 BPM', () {
      const timeSignature = TimeSignatureType.fourFour;
      const tempo = 60; // 60 beats per minute

      // At 60 BPM, each beat is 1 second
      // So a 4/4 measure (4 beats) should be 4 seconds
      expect(
        calculateMeasureDurationInSeconds(timeSignature, tempo),
        4.0,
      );
    });

    test('4/4 measure duration at 120 BPM', () {
      const timeSignature = TimeSignatureType.fourFour;
      const tempo = 120; // 120 beats per minute

      // At 120 BPM, each beat is 0.5 seconds
      // So a 4/4 measure (4 beats) should be 2 seconds
      expect(
        calculateMeasureDurationInSeconds(timeSignature, tempo),
        2.0,
      );
    });

    test('3/4 measure duration at 60 BPM', () {
      const timeSignature = TimeSignatureType.threeFour;
      const tempo = 60; // 60 beats per minute

      // At 60 BPM, each beat is 1 second
      // So a 3/4 measure (3 beats) should be 3 seconds
      expect(
        calculateMeasureDurationInSeconds(timeSignature, tempo),
        3.0,
      );
    });

    test('2/2 measure duration at 60 BPM', () {
      const timeSignature = TimeSignatureType.twoTwo;
      const tempo = 60; // 60 beats per minute

      // At 60 BPM, each beat is 1 second
      // In 2/2, there are 2 half-note beats
      // When converted to quarter notes, that's 4 beats
      // So at 60 BPM, a 2/2 measure should be 4 seconds
      expect(
        calculateMeasureDurationInSeconds(timeSignature, tempo),
        4.0,
      );
    });
  });

  group('Individual Note Duration Tests', () {
    test('Quarter note duration at different tempos', () {
      final note = Note(Pitch.c4); // Default is quarter note

      // At 60 BPM, a quarter note (1 beat) = 1 second
      expect(calculateSymbolDurationInSeconds(note, 60), 1.0);

      // At 120 BPM, a quarter note (1 beat) = 0.5 seconds
      expect(calculateSymbolDurationInSeconds(note, 120), 0.5);

      // At 240 BPM, a quarter note (1 beat) = 0.25 seconds
      expect(calculateSymbolDurationInSeconds(note, 240), 0.25);
    });

    test('Different note durations at same tempo', () {
      final tempo = 60; // 60 BPM

      // Quarter note (1 beat) at 60 BPM = 1 second
      final quarterNote = Note(Pitch.c4, noteDuration: NoteDuration.quarter);
      expect(calculateSymbolDurationInSeconds(quarterNote, tempo), 1.0);

      // Half note (2 beats) at 60 BPM = 2 seconds
      final halfNote = Note(Pitch.c4, noteDuration: NoteDuration.half);
      expect(calculateSymbolDurationInSeconds(halfNote, tempo), 2.0);

      // Whole note (4 beats) at 60 BPM = 4 seconds
      final wholeNote = Note(Pitch.c4, noteDuration: NoteDuration.whole);
      expect(calculateSymbolDurationInSeconds(wholeNote, tempo), 4.0);

      // Eighth note (0.5 beats) at 60 BPM = 0.5 seconds
      final eighthNote = Note(Pitch.c4, noteDuration: NoteDuration.eighth);
      expect(calculateSymbolDurationInSeconds(eighthNote, tempo), 0.5);
    });
  });
}
