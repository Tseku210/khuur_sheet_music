import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';
import 'package:simple_sheet_music/src/midi/midi_keys.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/keysignature_type.dart';

void main() {
  test('accidentals shift the natural pitch by their semitones', () {
    final keys = resolveMidiKeys([
      Measure([
        Note(Pitch.c4, accidental: Accidental.sharp),
        Note(Pitch.d4, accidental: Accidental.flat),
        Note(Pitch.e4, accidental: Accidental.doubleFlat),
        Note(Pitch.f4, accidental: Accidental.doubleSharp),
      ]),
    ], KeySignatureType.cMajor);
    expect(keys, [
      [61, 61, 62, 67],
    ]);
  });

  test('key signature alters only the letters it names', () {
    final keys = resolveMidiKeys([
      Measure([
        Note(Pitch.f4),
        Note(Pitch.c5),
        Note(Pitch.g4),
        Note(Pitch.b4),
      ]),
    ], KeySignatureType.dMajor);
    expect(keys, [
      [66, 73, 67, 71],
    ]);
  });

  test('flat key signature lowers its letters in every octave', () {
    final keys = resolveMidiKeys([
      Measure([Note(Pitch.b3), Note(Pitch.b4), Note(Pitch.e4), Note(Pitch.a4)]),
    ], KeySignatureType.bFlatMajor);
    expect(keys, [
      [58, 70, 63, 69],
    ]);
  });

  test('an accidental carries to the same pitch until the barline', () {
    final keys = resolveMidiKeys([
      Measure([
        Note(Pitch.f4, accidental: Accidental.natural),
        Note(Pitch.f4),
        Note(Pitch.f5),
      ]),
      Measure([Note(Pitch.f4)]),
    ], KeySignatureType.gMajor);
    expect(
        keys,
        [
          [65, 65, 78],
          [66],
        ],
        reason: 'F5 keeps the key signature sharp; the barline resets F4');
  });

  test('a key signature change applies to the notes after it', () {
    final keys = resolveMidiKeys([
      Measure([Note(Pitch.f4)]),
      Measure([KeySignature.gMajor(), Note(Pitch.f4), Rest(RestType.quarter)]),
    ], KeySignatureType.cMajor);
    expect(keys, [
      [65],
      [null, 66, null],
    ]);
  });
}
