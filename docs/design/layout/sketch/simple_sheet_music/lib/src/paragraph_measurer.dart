import 'package:score_layout/score_layout.dart';

/// Measures layout text with the `dart:ui` paragraphs the painter draws.
/// Not exported.
///
/// Measures at a fixed reference size and scales to the spec's size in
/// staff spaces, so a measurement does not depend on zoom and a bar laid
/// out at one zoom is valid at every zoom. Results are cached per text and
/// spec, which makes the measurer pure for its lifetime as `TextMeasurer`
/// requires. It ignores the platform text scale for the same reason.
///
/// A text font that loads after the first measurement would leave fallback
/// extents in the cache. The view handles that. It listens for late fonts,
/// asks a fresh measurer whether it [agreesWith] this one, and replaces the
/// measurer and the layout together when it does not.
final class ParagraphMeasurer implements TextMeasurer {
  ParagraphMeasurer();

  final Map<(String, TextSpec), TextExtent> _cache = {};

  @override
  TextExtent measure(String text, TextSpec spec) =>
      _cache.putIfAbsent((text, spec), () => _measure(text, spec));

  /// Whether this measurer gives every text [other] was asked for the
  /// extent [other] gave it. False after a font those texts use has loaded.
  bool agreesWith(ParagraphMeasurer other) => other._cache.entries.every((
    entry,
  ) {
    final (text, spec) = entry.key;
    final now = measure(text, spec);
    return now.width == entry.value.width &&
        now.ascent == entry.value.ascent &&
        now.descent == entry.value.descent;
  });

  TextExtent _measure(String text, TextSpec spec) {
    // TODO: build the paragraph the painter draws, at 100 logical px in
    // spec's family, weight and style; return maxIntrinsicWidth,
    // alphabeticBaseline and height minus baseline, each times
    // spec.size / 100.
    throw UnimplementedError();
  }
}
