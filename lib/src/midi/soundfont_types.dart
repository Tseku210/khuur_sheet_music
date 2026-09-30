/// Represents different types of soundfonts that can be used for MIDI playback.
enum SoundFontType {
  touhou(path: touhouPath, displayName: 'Touhou');

  const SoundFontType({required this.path, required this.displayName});

  /// Path to the Touhou soundfont file.
  static const touhouPath =
      'packages/simple_sheet_music/assets/soundfonts/touhou.sf2';

  /// The path to the soundfont file.
  final String path;

  /// The display name of the soundfont.
  final String displayName;
}
