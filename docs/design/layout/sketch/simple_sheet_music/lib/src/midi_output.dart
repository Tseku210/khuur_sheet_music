import 'sound_font.dart';

/// Where `ScorePlayer` sends a script's notes. An app passes its own to
/// play through another synthesizer.
///
/// The player waits for [load] and for every [program], and then sends
/// notes without waiting, because a note that waited for an answer would be
/// late. `FlutterMidiOutput` is the one implementation, over
/// `flutter_midi_pro`. A test passes a fake.
abstract interface class MidiOutput {
  /// Loads [soundFont]. The player waits for it before any [program] or
  /// note, and calls it again only after it failed. [allNotesOff] and
  /// [dispose] may come before it, or while it runs.
  Future<void> load(SoundFont soundFont);

  /// Selects [program] of [bank] for [channel], which is 0 to 15.
  Future<void> program({
    required int channel,
    required int program,
    required int bank,
  });

  /// Starts [key] on [channel], [cents] above its pitch.
  void noteOn({
    required int channel,
    required int key,
    required int velocity,
    required int cents,
  });

  /// Lets go of [key] on [channel]. The sound rings out as the instrument
  /// releases it.
  void noteOff({required int channel, required int key});

  /// Cuts every sound on every channel at once.
  void allNotesOff();

  /// Frees the SoundFont. The player calls nothing after it.
  void dispose();
}
