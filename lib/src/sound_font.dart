/// A SoundFont (`.sf2`) that MIDI playback loads its instruments from.
///
/// The package does not bundle one. The app supplies its own, either as an
/// asset it declares ([AssetSoundFont]) or as a file on the device, such as
/// one it downloaded ([FileSoundFont]). Each part plays the program and the
/// bank of its `Instrument`, so the SoundFont needs every program the score
/// names. A SoundFont keeps its drum kits in bank 128, so the `Instrument`
/// of a kit names that bank.
sealed class SoundFont {
  const SoundFont();
}

/// A SoundFont declared in the app's `pubspec.yaml` assets.
final class AssetSoundFont extends SoundFont {
  const AssetSoundFont(this.path);

  /// The asset key, for example `assets/soundfonts/piano.sf2`.
  final String path;
}

/// A SoundFont file on the device's file system.
final class FileSoundFont extends SoundFont {
  const FileSoundFont(this.path);

  /// The absolute path of the `.sf2` file.
  final String path;
}
