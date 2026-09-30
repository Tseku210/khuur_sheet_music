/// A SoundFont (`.sf2`) that MIDI playback loads its instrument from.
///
/// The package does not bundle one. The app supplies its own, either as an
/// asset it declares ([AssetSoundFont]) or as a file on the device, such as
/// one it downloaded ([FileSoundFont]). Playback uses bank 0, program 0.
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
