/// Reading SMuFL font metadata. Not exported.
library;

import 'geometry.dart';
import 'glyphs.dart';

/// What a font's metadata says about the glyphs the engine draws, in staff
/// spaces with y down.
typedef SmuflMetadata = ({
  Map<Glyph, GlyphMetrics> glyphs,

  /// The numeric engraving defaults by SMuFL name, one per name in
  /// [engravingDefaultNames] and in that order.
  Map<String, double> defaults,
});

/// Reads [metadata], the decoded `*_metadata.json` a SMuFL font ships.
///
/// The one reader the generator and `SmuflFont.fromMetadata` share. SMuFL
/// metadata is y up, and y is flipped here, once.
///
/// Throws one [FormatException] that names every failure. The failures are
/// a [Glyph] with no box or an inverted one, a [Glyph] with no advance, an
/// anchor on a [Glyph] that [GlyphAnchor] lacks, and a numeric engraving
/// default that [EngravingDefaults] lacks or the metadata lacks.
SmuflMetadata readSmuflMetadata(Map<String, Object?> metadata) {
  final failures = <String>[];
  Map<String, Object?> table(String key) {
    if (metadata[key] case final Map<String, Object?> table) {
      return table;
    }
    failures.add('the metadata has no $key');
    return const {};
  }

  final boxes = table('glyphBBoxes');
  final advances = table('glyphAdvanceWidths');
  final anchors = table('glyphsWithAnchors');
  final engraving = table('engravingDefaults');

  final glyphs = <Glyph, GlyphMetrics>{};
  for (final glyph in Glyph.values) {
    Box? box;
    switch (boxes[glyph.name]) {
      case {
            'bBoxNE': [final num right, final num top],
            'bBoxSW': [final num left, final num bottom],
          }
          when left <= right && bottom <= top:
        box = Box(left.toDouble(), _down(top), right.toDouble(), _down(bottom));
      case {'bBoxNE': [num _, num _], 'bBoxSW': [num _, num _]}:
        failures.add('${glyph.name} has an inverted box');
      default:
        failures.add('${glyph.name} has no box');
    }
    final advance = switch (advances[glyph.name]) {
      final num advance => advance.toDouble(),
      _ => null,
    };
    if (advance == null) {
      failures.add('${glyph.name} has no advance');
    }
    final points = <GlyphAnchor, SpPoint>{};
    if (anchors[glyph.name] case final Map<String, Object?> named) {
      for (final MapEntry(key: name, value: point) in named.entries) {
        final anchor = GlyphAnchor.values.asNameMap()[name];
        if (anchor == null) {
          failures.add(
            '${glyph.name} has the anchor $name, which GlyphAnchor lacks',
          );
        } else if (point case [final num x, final num y]) {
          points[anchor] = SpPoint(x.toDouble(), _down(y));
        } else {
          failures.add('${glyph.name} has no point for the anchor $name');
        }
      }
    }
    if (box != null && advance != null) {
      glyphs[glyph] = GlyphMetrics(box: box, advance: advance, anchors: points);
    }
  }

  final numeric = {
    for (final MapEntry(:key, :value) in engraving.entries)
      if (value is num) key: value.toDouble(),
  };
  for (final name in numeric.keys) {
    if (!engravingDefaultNames.contains(name)) {
      failures.add(
        'the engraving default $name is not in EngravingDefaults',
      );
    }
  }
  for (final name in engravingDefaultNames) {
    if (!numeric.containsKey(name)) {
      failures.add('the metadata has no engraving default $name');
    }
  }

  if (failures.isNotEmpty) {
    throw FormatException(
      'The SMuFL metadata does not fit the engine:\n${failures.join('\n')}',
    );
  }
  return (
    glyphs: glyphs,
    defaults: {for (final name in engravingDefaultNames) name: numeric[name]!},
  );
}

/// A y-up value in the y-down frame. Adding zero turns -0.0 into 0.0, which
/// equals it and would hash apart from it.
double _down(num y) => -y + 0.0;
