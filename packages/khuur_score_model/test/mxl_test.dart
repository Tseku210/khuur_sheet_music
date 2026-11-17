import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'showcase.dart';
import 'support.dart';

final String golden = File('test/golden/showcase.musicxml').readAsStringSync();

/// A short score that differs from the showcase.
final String blank = scoreToMusicXml(
  Score.blank(parts: const [morinKhuur], measureCount: 2),
);

/// The `.mxl` of another program: [entries] by name, deflated unless
/// [stored] names them.
Uint8List zip(Map<String, String> entries, {Set<String> stored = const {}}) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in entries.entries) {
    archive.add(
      ArchiveFile.string(key, value)
        ..compression = stored.contains(key)
            ? CompressionType.none
            : CompressionType.deflate,
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

String container(List<String> paths) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<container><rootfiles>'
    '${paths.map((path) => '<rootfile full-path="$path"/>').join()}'
    '</rootfiles></container>';

/// The export of the score that [bytes] read as.
String read(Uint8List bytes, {int? maxScoreBytes}) => scoreToMusicXml(
  maxScoreBytes == null
      ? scoreFromMusicXmlBytes(bytes)
      : scoreFromMusicXmlBytes(bytes, maxScoreBytes: maxScoreBytes),
);

Matcher refusedAt(String path, [Object? message]) => throwsA(
  isA<ScoreFormatException>()
      .having((e) => e.path, 'path', path)
      .having((e) => e.message, 'message', message ?? anything),
);

Uint8List utf16(String text, Endian endian) {
  final data = ByteData(2 + 2 * text.length)..setUint16(0, 0xFEFF, endian);
  for (final (i, unit) in text.codeUnits.indexed) {
    data.setUint16(2 + 2 * i, unit, endian);
  }
  return data.buffer.asUint8List();
}

/// [bytes] with the central directory declaring [size] bytes for [name].
Uint8List declaring(Uint8List bytes, String name, int size) {
  final copy = Uint8List.fromList(bytes);
  final data = ByteData.sublistView(copy);
  for (var at = 0; at + 46 <= copy.length; at++) {
    if (data.getUint32(at, Endian.little) != 0x02014b50) {
      continue;
    }
    final length = data.getUint16(at + 28, Endian.little);
    if (utf8.decode(copy.sublist(at + 46, at + 46 + length)) == name) {
      data.setUint32(at + 24, size, Endian.little);
      return copy;
    }
  }
  throw StateError('no $name in the central directory');
}

/// An archive of [text] stored as [name], whose sizes are in a data
/// descriptor that declares [size] once inflated. The central directory
/// gives 0 for that size, as a streaming zip writer may.
Uint8List withDescriptor(String name, String text, int size) {
  final data = utf8.encode(text);
  final path = utf8.encode(name);
  final crc = getCrc32(data);
  final out = BytesBuilder();
  void u16(int value) => out.add([value & 0xFF, value >> 8 & 0xFF]);
  void u32(int value) {
    u16(value & 0xFFFF);
    u16(value >> 16 & 0xFFFF);
  }

  u32(0x04034b50);
  u16(20);
  u16(0x08);
  u16(0);
  u16(0);
  u16(0x21);
  u32(0);
  u32(0);
  u32(0);
  u16(path.length);
  u16(0);
  out
    ..add(path)
    ..add(data);
  u32(0x08074b50);
  u32(crc);
  u32(data.length);
  u32(size);
  final central = out.length;
  u32(0x02014b50);
  u16(20);
  u16(20);
  u16(0x08);
  u16(0);
  u16(0);
  u16(0x21);
  u32(crc);
  u32(data.length);
  u32(0);
  u16(path.length);
  u16(0);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(0);
  out.add(path);
  final centralSize = out.length - central;
  u32(0x06054b50);
  u16(0);
  u16(0);
  u16(1);
  u16(1);
  u32(centralSize);
  u32(central);
  u16(0);
  return out.toBytes();
}

void main() {
  group('scoreToMxl', () {
    test('reads back as the same score', () {
      expect(read(scoreToMxl(showcase())), scoreToMusicXml(showcase()));
    });

    test('writes the entries in the order the spec gives', () {
      final archive = ZipDecoder().decodeBytes(scoreToMxl(showcase()));

      expect(
        [for (final file in archive) file.name],
        [
          'mimetype',
          'META-INF/container.xml',
          'score.musicxml',
        ],
      );
      expect(archive.files.first.compression, CompressionType.none);
      expect(
        utf8.decode(archive.findFile('score.musicxml')!.content),
        scoreToMusicXml(showcase()),
      );
    });

    test('starts with the stored mimetype, without an extra field', () {
      final bytes = scoreToMxl(showcase());
      final data = ByteData.sublistView(bytes);
      const mimetype = 'application/vnd.recordare.musicxml';

      expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      expect(
        data.getUint16(6, Endian.little) & 0x8,
        0,
        reason: 'no data descriptor',
      );
      expect(data.getUint16(8, Endian.little), 0, reason: 'stored');
      expect(data.getUint32(18, Endian.little), mimetype.length);
      expect(data.getUint16(26, Endian.little), 'mimetype'.length);
      expect(data.getUint16(28, Endian.little), 0, reason: 'no extra field');
      expect(ascii.decode(bytes.sublist(30, 38)), 'mimetype');
      expect(ascii.decode(bytes.sublist(38, 38 + mimetype.length)), mimetype);
    });

    test('names the score in the container', () {
      final archive = ZipDecoder().decodeBytes(scoreToMxl(showcase()));
      final text = utf8.decode(
        archive.findFile('META-INF/container.xml')!.content,
      );

      expect(text, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(
        text,
        contains(
          '<rootfile full-path="score.musicxml" '
          'media-type="application/vnd.recordare.musicxml+xml"/>',
        ),
      );
    });

    test('writes the same bytes for the same score', () {
      expect(scoreToMxl(showcase()), scoreToMxl(showcase()));
    });
  });

  group('scoreFromMusicXmlBytes reads an archive', () {
    test('whose rootfile is deflated in a folder, without a mimetype', () {
      final bytes = zip({
        'META-INF/container.xml': container(['scores/3f9a2c.xml']),
        'scores/3f9a2c.xml': golden,
      });

      expect(read(bytes), golden);
    });

    test('by the first of several rootfiles', () {
      final bytes = zip({
        'META-INF/container.xml': container(['b.musicxml', 'a.musicxml']),
        'a.musicxml': golden,
        'b.musicxml': blank,
      });

      expect(read(bytes), blank);
    });

    test('without a container when one entry is a score', () {
      final bytes = zip(
        {'mimetype': 'application/vnd.recordare.musicxml', 'tune.xml': golden},
        stored: {'mimetype'},
      );

      expect(read(bytes), golden);
    });

    test('with a stored score', () {
      final bytes = zip(
        {
          'META-INF/container.xml': container(['tune.musicxml']),
          'tune.musicxml': golden,
        },
        stored: {'tune.musicxml'},
      );

      expect(read(bytes), golden);
    });
  });

  group('scoreFromMusicXmlBytes refuses', () {
    test('an archive without a container that holds two scores', () {
      final bytes = zip({'a.musicxml': golden, 'b.xml': blank});

      expect(
        () => scoreFromMusicXmlBytes(bytes),
        refusedAt('META-INF/container.xml', contains('2 .musicxml or .xml')),
      );
    });

    test('an archive with no score', () {
      expect(
        () => scoreFromMusicXmlBytes(zip({'notes.txt': 'hello'})),
        refusedAt('META-INF/container.xml'),
      );
    });

    test('bytes that are neither a zip nor XML', () {
      expect(
        () => scoreFromMusicXmlBytes(Uint8List.fromList([1, 2, 3, 250, 7])),
        refusedAt('/'),
      );
    });

    test('a zip signature followed by garbage', () {
      expect(
        () => scoreFromMusicXmlBytes(
          Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...List.filled(64, 9)]),
        ),
        refusedAt('/'),
      );
    });

    test('a truncated archive', () {
      final bytes = scoreToMxl(showcase());

      expect(
        () => scoreFromMusicXmlBytes(bytes.sublist(0, bytes.length ~/ 2)),
        refusedAt('/'),
      );
    });

    test('a container that is not well-formed', () {
      final bytes = zip({
        'META-INF/container.xml': '<container><rootfiles>',
        'score.musicxml': golden,
      });

      expect(
        () => scoreFromMusicXmlBytes(bytes),
        refusedAt('META-INF/container.xml', startsWith('not well-formed')),
      );
    });

    test('a container without a rootfile', () {
      final bytes = zip({
        'META-INF/container.xml': container([]),
        'score.musicxml': golden,
      });

      expect(
        () => scoreFromMusicXmlBytes(bytes),
        refusedAt('META-INF/container.xml'),
      );
    });

    test('a rootfile that names no entry', () {
      final bytes = zip({
        'META-INF/container.xml': container(['missing.musicxml']),
        'score.musicxml': golden,
      });

      expect(
        () => scoreFromMusicXmlBytes(bytes),
        refusedAt('META-INF/container.xml', contains('missing.musicxml')),
      );
    });

    test('a score larger than maxScoreBytes', () {
      final bytes = scoreToMxl(showcase());
      final size = utf8.encode(scoreToMusicXml(showcase())).length;

      expect(read(bytes, maxScoreBytes: size), scoreToMusicXml(showcase()));
      expect(
        () => scoreFromMusicXmlBytes(bytes, maxScoreBytes: size - 1),
        refusedAt('score.musicxml', contains('${size - 1} bytes')),
      );
    });

    test('an entry that inflates past the size it declares', () {
      final bytes = declaring(scoreToMxl(showcase()), 'score.musicxml', 100);

      expect(
        () => scoreFromMusicXmlBytes(bytes),
        refusedAt('score.musicxml'),
      );
    });

    test('an entry whose data descriptor declares more than allowed', () {
      final size = utf8.encode(blank).length;

      expect(
        read(withDescriptor('score.musicxml', blank, size)),
        read(zip({'score.musicxml': blank})),
      );
      expect(
        () => scoreFromMusicXmlBytes(
          withDescriptor('score.musicxml', blank, size + 1),
          maxScoreBytes: size,
        ),
        refusedAt('score.musicxml', contains('bytes allowed')),
      );
    });

    test('plain bytes larger than maxScoreBytes', () {
      final bytes = utf8.encode(golden);

      expect(
        () => scoreFromMusicXmlBytes(bytes, maxScoreBytes: bytes.length - 1),
        refusedAt('/'),
      );
    });

    test('bytes that are not UTF-8', () {
      final bytes = utf8.encode(golden)..[100] = 0xFF;

      expect(
        () => scoreFromMusicXmlBytes(bytes),
        refusedAt('/', startsWith('not UTF-8')),
      );
    });

    test('an archived score that is not UTF-8', () {
      final archive = Archive()
        ..add(ArchiveFile.bytes('tune.musicxml', [0x3C, 0xC3, 0x28]));

      expect(
        () => scoreFromMusicXmlBytes(ZipEncoder().encodeBytes(archive)),
        refusedAt('tune.musicxml', startsWith('not UTF-8')),
      );
    });

    test('UTF-16 with an odd number of bytes', () {
      final bytes = utf16(golden, Endian.little);

      expect(
        () => scoreFromMusicXmlBytes(bytes.sublist(0, bytes.length - 1)),
        refusedAt('/', startsWith('not UTF-16')),
      );
    });

    test('nothing but a ScoreFormatException for any damaged archive', () {
      final bytes = scoreToMxl(
        Score.blank(parts: const [morinKhuur], measureCount: 1),
      );
      final damaged = [
        for (var length = 0; length < bytes.length; length++)
          bytes.sublist(0, length),
        for (var at = 0; at < bytes.length; at++)
          Uint8List.fromList(bytes)..[at] ^= 0x5A,
      ];

      for (final (i, candidate) in damaged.indexed) {
        try {
          scoreFromMusicXmlBytes(candidate);
        } on ScoreFormatException {
          // Refused as it should be.
        } on Object catch (e) {
          fail('damaged archive $i threw ${e.runtimeType}: $e');
        }
      }
    });
  });

  test('musicXmlFromBytes gives the document of an archive', () {
    expect(
      musicXmlFromBytes(scoreToMxl(showcase())),
      scoreToMusicXml(showcase()),
    );
  });

  group('scoreFromMusicXmlBytes reads plain bytes', () {
    test('in UTF-8', () {
      expect(read(utf8.encode(golden)), golden);
    });

    test('in UTF-8 after a byte order mark', () {
      expect(
        read(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(golden)])),
        golden,
      );
    });

    test('in UTF-16 little-endian after a byte order mark', () {
      expect(read(utf16(golden, Endian.little)), golden);
    });

    test('in UTF-16 big-endian after a byte order mark', () {
      expect(read(utf16(golden, Endian.big)), golden);
    });
  });

  test('keeps the element path of an error in the score', () {
    final bytes = zip({
      'score.musicxml': golden
          .replaceFirst(
            '<score-partwise',
            '<score-timewise',
          )
          .replaceFirst('</score-partwise>', '</score-timewise>'),
    });

    expect(() => scoreFromMusicXmlBytes(bytes), refusedAt('/score-timewise'));
  });
}
