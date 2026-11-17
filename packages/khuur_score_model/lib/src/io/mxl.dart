/// MusicXML from file bytes, and the compressed `.mxl` format.
///
/// A compressed MusicXML file is a zip archive. Its first entry is a
/// stored `mimetype`, `META-INF/container.xml` names the score in its first
/// `<rootfile>`, and the score is an entry of its own.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../score.dart';
import 'json.dart';
import 'musicxml.dart';
import 'musicxml_import.dart';

const _container = 'META-INF/container.xml';

/// Reads a MusicXML file into a [Score], given the file's bytes.
///
/// [bytes] are a compressed `.mxl` file or an uncompressed `.musicxml`
/// file, told apart by the zip signature at the start. In an `.mxl` file
/// the score is the entry that the first `<rootfile>` of
/// `META-INF/container.xml` names. An archive without a container is read
/// only when it holds exactly one `.musicxml` or `.xml` entry outside
/// `META-INF/`.
///
/// The document is UTF-16 when it starts with a UTF-16 byte order mark,
/// and UTF-8 otherwise, with a UTF-8 byte order mark dropped. The text
/// then goes to [scoreFromMusicXml].
///
/// [maxScoreBytes] is the largest document it reads, counted in the bytes
/// of the file or of the archive entry once inflated. The container is
/// held to it too. The default, 64 MiB, is well above the largest
/// orchestral scores, which are a few tens of megabytes. An entry whose
/// archive declares a size over the limit is refused before any of it is
/// inflated, and no entry is inflated past the size its archive declares,
/// so a hostile archive cannot inflate more than [maxScoreBytes]. The
/// archive's other entries are never inflated.
///
/// Throws [ScoreFormatException] when the bytes cannot be read. Its `path`
/// is `/` for a damaged archive or a file whose text does not decode,
/// `META-INF/container.xml` for a container that names no score, and the
/// score entry's name for an entry that is too large, damaged or not
/// UTF-8. An error in the score keeps the element path that
/// [scoreFromMusicXml] gives.
Score scoreFromMusicXmlBytes(
  Uint8List bytes, {
  int maxScoreBytes = 64 << 20,
}) {
  final text = _isZip(bytes)
      ? _rootFile(bytes, maxScoreBytes)
      : _text(_limited('/', bytes, maxScoreBytes));
  return scoreFromMusicXml(text);
}

/// [score] as the bytes of a MusicXML 4.0 compressed `.mxl` file.
///
/// The archive holds a stored `mimetype`, `META-INF/container.xml`, and
/// the document of [scoreToMusicXml] deflated as `score.musicxml`. Every
/// entry carries a fixed time, so writing a score again gives the same
/// bytes.
Uint8List scoreToMxl(Score score) {
  final archive = Archive()
    ..add(
      ArchiveFile.string('mimetype', 'application/vnd.recordare.musicxml')
        ..compression = CompressionType.none,
    )
    ..add(
      ArchiveFile.string(
        _container,
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<container>\n'
        '  <rootfiles>\n'
        '    <rootfile full-path="score.musicxml"'
        ' media-type="application/vnd.recordare.musicxml+xml"/>\n'
        '  </rootfiles>\n'
        '</container>\n',
      ),
    )
    ..add(ArchiveFile.string('score.musicxml', scoreToMusicXml(score)));
  return ZipEncoder().encodeBytes(
    archive,
    level: DeflateLevel.bestCompression,
    modified: DateTime.utc(1980),
  );
}

bool _isZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4B &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// The text of the score's entry in the zip archive [bytes].
String _rootFile(Uint8List bytes, int maxScoreBytes) {
  // ZipDecoder reads a symbolic link's target while it lists the archive,
  // inflating up to the size the archive declares. The directory alone
  // inflates nothing until an entry is read.
  final directory = ZipDirectory();
  final List<ZipFileHeader> entries;
  try {
    entries = directory
        .headers(InputMemoryStream(bytes), verify: true)
        .where((entry) => !entry.filename.endsWith('/'))
        .toList();
  } on FormatException catch (e) {
    throw ScoreFormatException('/', 'not a readable zip archive: ${e.message}');
  }
  if (directory.filePosition < 0) {
    throw const ScoreFormatException(
      '/',
      'not a readable zip archive: no end of central directory',
    );
  }
  final containers = _named(entries, _container);
  final String path;
  if (containers.isNotEmpty) {
    path = _rootPath(_inflate(containers, _container, maxScoreBytes));
  } else {
    final candidates = [
      for (final entry in entries)
        if (_isScoreName(entry.filename)) entry.filename,
    ];
    if (candidates.length != 1) {
      throw ScoreFormatException(
        _container,
        candidates.isEmpty
            ? 'missing, and the archive has no .musicxml or .xml entry'
            : 'missing, and the archive has ${candidates.length} '
                  '.musicxml or .xml entries',
      );
    }
    path = candidates.single;
  }
  final root = _named(entries, path);
  if (root.isEmpty) {
    throw ScoreFormatException(
      _container,
      'names $path, which is not in the archive',
    );
  }
  return _text(_inflate(root, path, maxScoreBytes), path: path);
}

List<ZipFileHeader> _named(List<ZipFileHeader> entries, String name) => [
  for (final entry in entries)
    if (entry.filename == name) entry,
];

bool _isScoreName(String name) {
  final lower = name.toLowerCase();
  return !name.startsWith('META-INF/') &&
      (lower.endsWith('.musicxml') || lower.endsWith('.xml'));
}

/// The `full-path` of the first `<rootfile>` in [container].
String _rootPath(Uint8List container) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(_text(container, path: _container));
  } on XmlException catch (e) {
    throw ScoreFormatException(_container, 'not well-formed XML: $e');
  }
  final path = document
      .findAllElements('rootfile')
      .firstOrNull
      ?.getAttribute('full-path');
  if (path == null || path.isEmpty) {
    throw const ScoreFormatException(
      _container,
      'no <rootfile> with a full-path',
    );
  }
  return path;
}

/// The inflated bytes of the one entry in [entries], all named [name].
Uint8List _inflate(List<ZipFileHeader> entries, String name, int maxBytes) {
  if (entries.length > 1) {
    throw ScoreFormatException(
      name,
      'the archive has ${entries.length} entries of this name',
    );
  }
  final declared = entries.single.uncompressedSize;
  if (declared < 0 || declared > maxBytes) {
    throw ScoreFormatException(name, 'larger than the $maxBytes bytes allowed');
  }
  final Uint8List content;
  try {
    final file = entries.single.file!
      ..verify = true
      ..throwOnError = true;
    content = file.getStream().toUint8List();
  } on FormatException catch (e) {
    throw ScoreFormatException(name, 'cannot be read: ${e.message}');
  }
  return _limited(name, content, maxBytes);
}

Uint8List _limited(String path, Uint8List bytes, int maxBytes) {
  if (bytes.length > maxBytes) {
    throw ScoreFormatException(path, 'larger than the $maxBytes bytes allowed');
  }
  return bytes;
}

/// [bytes] as text: UTF-16 after a UTF-16 byte order mark, else UTF-8.
String _text(Uint8List bytes, {String path = '/'}) {
  final endian = bytes.length < 2
      ? null
      : switch ((bytes[0], bytes[1])) {
          (0xFF, 0xFE) => Endian.little,
          (0xFE, 0xFF) => Endian.big,
          _ => null,
        };
  if (endian == null) {
    try {
      final text = utf8.decode(bytes);
      return text.startsWith('﻿') ? text.substring(1) : text;
    } on FormatException catch (e) {
      throw ScoreFormatException(path, 'not UTF-8: ${e.message}');
    }
  }
  if (bytes.length.isOdd) {
    throw ScoreFormatException(path, 'not UTF-16: an odd number of bytes');
  }
  final data = ByteData.sublistView(bytes, 2);
  return String.fromCharCodes([
    for (var i = 0; i < data.lengthInBytes; i += 2) data.getUint16(i, endian),
  ]);
}
