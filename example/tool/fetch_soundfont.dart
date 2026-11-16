// Downloads the example's piano SoundFont, Upright Piano KW from FreePats,
// to assets/soundfonts/piano.sf2. Run it once from example/:
//
//   dart run tool/fetch_soundfont.dart
//
// FreePats ships the SoundFont in a 7-Zip archive. The script unpacks it with
// tar (bsdtar, as on macOS and Windows) or with 7-Zip (7zz, 7z or 7za), and
// checks the SHA-256 of the archive and of the SoundFont.

import 'dart:io';

import 'package:crypto/crypto.dart';

const _archiveUrl =
    'https://freepats.zenvoid.org/Piano/UprightPianoKW/'
    'UprightPianoKW-SF2-20220221.7z';
const _archiveSha256 =
    '17c084c6e4205233dc49b34e4bc44a9b2d7c7a2c02b04729ecda77079b07c826';
const _member = 'UprightPianoKW-SF2-20220221/UprightPianoKW-20220221.sf2';
const _soundFontSha256 =
    'd9f5157720963671906727ca2e12b3293fd822c831bb0de477dd1c5f3ad37108';

Future<void> main() async {
  final target = File.fromUri(
    Platform.script.resolve('../assets/soundfonts/piano.sf2'),
  );
  if (target.existsSync() && await _sha256Of(target) == _soundFontSha256) {
    stdout.writeln('${target.path} is already there.');
    return;
  }
  final work = Directory.systemTemp.createTempSync('fetch_soundfont');
  try {
    final archive = File('${work.path}/soundfont.7z');
    stdout.writeln('Downloading $_archiveUrl (29 MB)');
    await _download(Uri.parse(_archiveUrl), archive);
    _check(await _sha256Of(archive), _archiveSha256, 'The archive');
    final soundFont = await _unpack(archive, work);
    _check(await _sha256Of(soundFont), _soundFontSha256, 'The SoundFont');
    target.parent.createSync(recursive: true);
    soundFont.copySync(target.path);
    stdout.writeln('Wrote ${target.path}.');
  } on _Failure catch (failure) {
    stderr.writeln(failure.message);
    exitCode = 1;
  } finally {
    work.deleteSync(recursive: true);
  }
}

Future<void> _download(Uri url, File to) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw _Failure('The download failed with HTTP ${response.statusCode}.');
    }
    await response.pipe(to.openWrite());
  } on SocketException catch (error) {
    throw _Failure('The download failed: ${error.message}');
  } finally {
    client.close();
  }
}

/// Unpacks [_member] of [archive] into [into] with the first unpacker that
/// works.
Future<File> _unpack(File archive, Directory into) async {
  final unpackers = [
    ['tar', '-xf', archive.path, '-C', into.path, _member],
    for (final sevenZip in ['7zz', '7z', '7za'])
      [sevenZip, 'x', '-y', '-o${into.path}', archive.path, _member],
  ];
  for (final [command, ...arguments] in unpackers) {
    try {
      final result = await Process.run(command, arguments);
      final soundFont = File('${into.path}/$_member');
      if (result.exitCode == 0 && soundFont.existsSync()) {
        return soundFont;
      }
    } on ProcessException {
      // This unpacker is not installed. Try the next one.
    }
  }
  throw _Failure(
    'Could not unpack the 7-Zip archive. Install bsdtar (libarchive-tools) '
    'or 7-Zip, then run the script again.',
  );
}

Future<String> _sha256Of(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

void _check(String actual, String expected, String what) {
  if (actual != expected) {
    throw _Failure(
      '$what has SHA-256 $actual, not $expected. '
      'FreePats may have changed the file.',
    );
  }
}

class _Failure implements Exception {
  _Failure(this.message);

  final String message;
}
