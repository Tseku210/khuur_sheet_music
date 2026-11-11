/// A SoundFont (`.sf2`) that MIDI playback loads its instruments from.
///
/// The package does not bundle one. The app supplies its own, either as an
/// asset it declares ([AssetSoundFont]) or as a file on the device, such as
/// one it downloaded ([FileSoundFont]). Each part plays the program and the
/// bank of its `Instrument`, so the SoundFont a part plays from needs every
/// program the part names. A SoundFont keeps its drum kits in bank 128, so
/// the `Instrument` of a kit names that bank.
///
/// Two SoundFonts of the same kind and path are equal, and a player loads
/// them once.
sealed class SoundFont {
  const SoundFont();
}

/// A SoundFont declared in the app's `pubspec.yaml` assets.
final class AssetSoundFont extends SoundFont {
  const AssetSoundFont(this.path);

  /// The asset key, for example `assets/soundfonts/piano.sf2`.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is AssetSoundFont && other.path == path;

  @override
  int get hashCode => Object.hash(AssetSoundFont, path);

  @override
  String toString() => 'AssetSoundFont($path)';
}

/// A SoundFont file on the device's file system.
final class FileSoundFont extends SoundFont {
  const FileSoundFont(this.path);

  /// The absolute path of the `.sf2` file.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is FileSoundFont && other.path == path;

  @override
  int get hashCode => Object.hash(FileSoundFont, path);

  @override
  String toString() => 'FileSoundFont($path)';
}
