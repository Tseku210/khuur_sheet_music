/// MusicXML from file bytes, and the compressed `.mxl` format.
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
/// It is [scoreFromMusicXml] of the text that [musicXmlFromBytes] finds in
/// [bytes], a compressed `.mxl` file or an uncompressed `.musicxml` file.
///
/// Throws [ScoreFormatException] when [musicXmlFromBytes] or
/// [scoreFromMusicXml] refuses the file. An error in the score keeps the
/// element path that [scoreFromMusicXml] gives.
Score scoreFromMusicXmlBytes(
  Uint8List bytes, {
  int maxScoreBytes = 64 << 20,
}) => scoreFromMusicXml(
  musicXmlFromBytes(bytes, maxScoreBytes: maxScoreBytes),
);

/// The text of the MusicXML document in a file, given the file's bytes.
///
/// For an app that changes the document before [scoreFromMusicXml] reads
/// it. [scoreFromMusicXmlBytes] reads it without that step.
///
/// [bytes] are a compressed `.mxl` file or an uncompressed `.musicxml`
/// file, told apart by the zip signature at the start. In an `.mxl` file
/// the document is the entry that the first `<rootfile>` of
/// `META-INF/container.xml` names. An archive without a container is read
/// only when it holds exactly one `.musicxml` or `.xml` entry outside
/// `META-INF/`.
///
/// The document is UTF-16 when it starts with a UTF-16 byte order mark,
/// and UTF-8 otherwise, with a UTF-8 byte order mark dropped.
///
/// [maxScoreBytes] is the largest document it reads, counted in the bytes
/// of the file or of the archive entry once inflated. The container is
/// held to it too. The default, 64 MiB, is meant to leave room for a long
/// orchestral score. An entry whose archive declares a size over the limit
/// is refused before any of it is inflated, and an entry is refused as soon
/// as it inflates past the size its archive declares, on every platform.
/// The archive's other entries are never inflated.
///
/// Throws [ScoreFormatException] when the bytes cannot be read. Its `path`
/// is `/` for a damaged archive, or for an uncompressed file that is too
/// large or whose text does not decode. It is `META-INF/container.xml` for
/// a container that cannot be read or names no score, and for an archive
/// without a container that does not hold exactly one score. It is the
/// score entry's name for an entry that is too large, damaged or does not
/// decode.
String musicXmlFromBytes(Uint8List bytes, {int maxScoreBytes = 64 << 20}) =>
    _isZip(bytes)
    ? _rootFile(bytes, maxScoreBytes)
    : _text(_limited('/', bytes, maxScoreBytes));

/// [score] as the bytes of a MusicXML 4.0 compressed `.mxl` file.
///
/// The archive holds a stored `mimetype`, `META-INF/container.xml`, and
/// the document of [scoreToMusicXml] deflated as `score.musicxml`. Every
/// entry carries a fixed time, so writing a score again on the same machine
/// gives the same bytes. The zip time fields follow the local time zone, so
/// two machines can differ.
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
    path = _rootPath(_inflate(bytes, containers, _container, maxScoreBytes));
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
  return _text(_inflate(bytes, root, path, maxScoreBytes), path: path);
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

Uint8List _inflate(
  Uint8List archive,
  List<ZipFileHeader> entries,
  String name,
  int maxBytes,
) {
  if (entries.length > 1) {
    throw ScoreFormatException(
      name,
      'the archive has ${entries.length} entries of this name',
    );
  }
  final header = entries.single;
  final ZipFile file;
  try {
    file = header.file!
      ..verify = true
      ..throwOnError = true;
  } on FormatException catch (e) {
    throw ScoreFormatException(name, 'cannot be read: ${e.message}');
  }
  // archive takes this from the data descriptor where the central
  // directory gives 0.
  final declared = file.uncompressedSize;
  if (declared < 0 || declared > maxBytes) {
    throw ScoreFormatException(name, 'larger than the $maxBytes bytes allowed');
  }
  if (file.flags & 1 != 0) {
    throw ScoreFormatException(name, 'encrypted');
  }
  final data = _entryData(archive, header, file, name);
  final content = switch (header.compressionMethod) {
    0 => data,
    8 => _deflated(data, declared, name),
    final method => throw ScoreFormatException(
      name,
      'compressed with method $method, where .mxl uses deflate',
    ),
  };
  if (content.length != declared || getCrc32(content) != file.crc32) {
    throw ScoreFormatException(
      name,
      'damaged: its size or CRC does not match the archive',
    );
  }
  return content;
}

/// The bytes of [file] as the archive stores them, after its local header.
Uint8List _entryData(
  Uint8List archive,
  ZipFileHeader header,
  ZipFile file,
  String name,
) {
  final at = header.localHeaderOffset;
  if (at < 0 || at + 30 > archive.length) {
    throw ScoreFormatException(name, 'damaged: no local header');
  }
  final fields = ByteData.sublistView(archive, at);
  final start =
      at +
      30 +
      fields.getUint16(26, Endian.little) +
      fields.getUint16(28, Endian.little);
  final end = start + file.compressedSize;
  if (end > archive.length) {
    throw ScoreFormatException(name, 'damaged: its data is truncated');
  }
  return Uint8List.sublistView(archive, start, end);
}

/// [data] inflated, refused once it passes [limit] bytes.
///
/// archive's own size check sees the output only after the web inflater
/// has inflated the whole entry into a buffer of its own. That inflater
/// writes straight into an [OutputMemoryStream], so [_Capped] counts every
/// write and stops it in the middle of a deflate block.
Uint8List _deflated(Uint8List data, int limit, String name) {
  final output = _Capped(limit);
  try {
    const ZLibDecoder().decodeStream(
      InputMemoryStream(data),
      output,
      raw: true,
      throwOnError: true,
    );
  } on Object catch (e) {
    if (!output.exceeded) {
      throw ScoreFormatException(name, 'cannot be inflated: $e');
    }
  }
  if (output.exceeded) {
    throw ScoreFormatException(
      name,
      'inflates past the $limit bytes the archive declares',
    );
  }
  return output.getBytes();
}

final class _Capped extends OutputMemoryStream {
  _Capped(this.limit);

  final int limit;
  bool exceeded = false;

  void _room(int count) {
    if (length + count > limit) {
      exceeded = true;
      throw StateError('more than $limit bytes');
    }
  }

  @override
  void writeByte(int value) {
    _room(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _room(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _room(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _room(count);
    super.writeBackReference(distance, count);
  }
}

Uint8List _limited(String path, Uint8List bytes, int maxBytes) {
  if (bytes.length > maxBytes) {
    throw ScoreFormatException(path, 'larger than the $maxBytes bytes allowed');
  }
  return bytes;
}

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
  final units = Uint16List(data.lengthInBytes ~/ 2);
  for (var i = 0; i < units.length; i++) {
    units[i] = data.getUint16(i * 2, endian);
  }
  return String.fromCharCodes(units);
}
