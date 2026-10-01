import 'dart:convert';
import 'dart:io';

import 'package:score_layout/score_layout.dart';
import 'package:test/test.dart';

import '../tool/generate_bravura.dart' as generator;

Map<String, Object?> bravuraMetadata() =>
    jsonDecode(File(generator.metadataPath).readAsStringSync())
        as Map<String, Object?>;

Map<String, Object?> part(Map<String, Object?> metadata, String key) =>
    metadata[key]! as Map<String, Object?>;

void main() {
  test('the generator reproduces the committed table byte for byte', () {
    // Inside the package, so the formatter reads the package's options.
    final scratch = Directory('test').createTempSync('generated');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final written = '${scratch.path}/bravura.g.dart';

    generator.main([written]);

    expect(
      File(written).readAsStringSync(),
      File(generator.outputPath).readAsStringSync(),
    );
  });

  test('the table is y down, in staff spaces from the glyph origin', () {
    const font = SmuflFont.bravura;

    expect(font[Glyph.gClef].box, const Box(0, -4.392, 2.684, 2.632));
    expect(font[Glyph.gClef].advance, 2.684);
    expect(
      font[Glyph.noteheadBlack].anchors[GlyphAnchor.stemUpSE],
      const SpPoint(1.18, -0.168),
    );
    expect(
      font[Glyph.noteheadBlack].anchors[GlyphAnchor.stemDownNW],
      const SpPoint(0, 0.168),
    );
    expect(font.defaults.staffLineThickness, 0.13);
    expect(font.defaults.beamThickness, 0.5);
  });

  test('metadata parsed at run time gives the generated metrics', () {
    final font = SmuflFont.fromMetadata(
      family: 'Mine',
      metadata: bravuraMetadata(),
    );

    expect(font.family, 'Mine');
    for (final glyph in Glyph.values) {
      final read = font[glyph];
      final generated = SmuflFont.bravura[glyph];
      expect(read.box, generated.box, reason: glyph.name);
      expect(read.advance, generated.advance, reason: glyph.name);
      expect(read.anchors, generated.anchors, reason: glyph.name);
    }
    expect(
      font.defaults.thickBarlineThickness,
      SmuflFont.bravura.defaults.thickBarlineThickness,
    );
  });

  test('each engraving default is read from its own name', () {
    // Dart cannot list a class's fields, and Bravura gives many of them one
    // value, so a crossed pair in `EngravingDefaults.read` would show in no
    // metric. Its source is checked instead, line by line.
    final pairs = RegExp(r"(\w+): valueOf\('(\w+)'\)")
        .allMatches(File('lib/src/glyphs.dart').readAsStringSync())
        .map((match) => (field: match[1], name: match[2]))
        .toList();

    expect(pairs, hasLength(28));
    expect(pairs.where((pair) => pair.field != pair.name), isEmpty);
    expect(engravingDefaultNames, [for (final pair in pairs) pair.name]);
    expect(engravingDefaultNames.toSet(), hasLength(28));
  });

  test('engraving defaults are read from the metadata', () {
    final metadata = bravuraMetadata();
    part(metadata, 'engravingDefaults')
      ..['stemThickness'] = 0.31
      ..['beamSpacing'] = 0.77;

    final defaults = SmuflFont.fromMetadata(
      family: 'Mine',
      metadata: metadata,
    ).defaults;

    expect(defaults.stemThickness, 0.31);
    expect(defaults.beamSpacing, 0.77);
    expect(defaults.beamThickness, SmuflFont.bravura.defaults.beamThickness);
  });

  test('a font that does not fit names every failure at once', () {
    final metadata = bravuraMetadata();
    part(metadata, 'glyphBBoxes')
      ..remove('gClef')
      ..['fClef'] = {
        'bBoxNE': [0, 0],
        'bBoxSW': [1, 1],
      };
    part(metadata, 'glyphAdvanceWidths').remove('restQuarter');
    part(
      part(metadata, 'glyphsWithAnchors'),
      'noteheadBlack',
    )['stemSideways'] = [
      0.5,
      0.5,
    ];
    part(metadata, 'engravingDefaults')
      ..remove('stemThickness')
      ..['wobbleThickness'] = 0.2;

    expect(
      () => SmuflFont.fromMetadata(family: 'Mine', metadata: metadata),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('gClef has no box'),
            contains('fClef has an inverted box'),
            contains('restQuarter has no advance'),
            contains('noteheadBlack has the anchor stemSideways'),
            contains('stemThickness'),
            contains('wobbleThickness'),
          ),
        ),
      ),
    );
  });

  test('metadata without its tables is refused, not a cast error', () {
    expect(
      () => SmuflFont.fromMetadata(family: 'Mine', metadata: {}),
      throwsFormatException,
    );
  });

  test('a font equals itself and no reparsed copy', () {
    final metadata = bravuraMetadata();
    final first = SmuflFont.fromMetadata(family: 'Mine', metadata: metadata);
    final second = SmuflFont.fromMetadata(family: 'Mine', metadata: metadata);

    expect(first, first);
    expect(first, isNot(second));
    expect(SmuflFont.bravura, SmuflFont.bravura);
  });
}
