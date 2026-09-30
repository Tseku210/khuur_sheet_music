import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/key_signature.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/keysignature_type.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_pitch.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';

/// Returns the MIDI key each symbol sounds, indexed like
/// `measures[i].musicalSymbols[j]`, with `null` for symbols that make no sound.
///
/// A note's explicit accidental wins and holds for that pitch until the end of
/// the measure. Otherwise the active key signature applies.
List<List<int?>> resolveMidiKeys(
  List<Measure> measures,
  KeySignatureType initialKeySignatureType,
) {
  var keySignatureType = initialKeySignatureType;
  final result = <List<int?>>[];
  for (final measure in measures) {
    final measureAccidentals = <Pitch, int>{};
    final keys = <int?>[];
    for (final symbol in measure.musicalSymbols) {
      if (symbol is KeySignature) {
        keySignatureType = symbol.keySignatureType;
      }
      if (symbol is! Note) {
        keys.add(null);
        continue;
      }
      final pitch = symbol.pitch;
      final accidental = symbol.accidental;
      if (accidental != null) {
        measureAccidentals[pitch] = accidental.semitones;
      }
      final alteration =
          measureAccidentals[pitch] ?? keySignatureType.alterationFor(pitch);
      keys.add(pitch.midiNoteNumber + alteration);
    }
    result.add(keys);
  }
  return result;
}
