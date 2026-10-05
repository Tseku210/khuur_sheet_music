import 'package:flutter/painting.dart';
import 'package:khuur_sheet_music/src/painting.dart';
import 'package:score_layout/score_layout.dart';

/// Measures layout text with the `dart:ui` paragraphs the painter draws.
/// Not exported.
///
/// It measures at one reference size and scales to the spec's size in staff
/// spaces, so a measurement does not depend on zoom and a bar laid out at
/// one zoom is valid at every zoom. Results are kept per text and spec,
/// which makes the measurer pure for its lifetime as `TextMeasurer`
/// requires. It ignores the platform text scale for the same reason.
///
/// A text font that loads after the first measurement would leave fallback
/// extents behind. The view handles that. It listens for late fonts, asks a
/// fresh measurer whether it [agreesWith] this one, and replaces the
/// measurer and the layout together when it does not.
final class ParagraphMeasurer implements TextMeasurer {
  final Map<(String, TextSpec), TextExtent> _extents = {};

  /// The font size the probe paragraph is laid out at, in logical pixels.
  static const double _probePx = 100;

  @override
  TextExtent measure(String text, TextSpec spec) =>
      _extents.putIfAbsent((text, spec), () {
        final paragraph = textParagraph(
          text,
          spec,
          _probePx,
          const Color(0xFF000000),
        );
        final perPx = spec.size / _probePx;
        final extent = TextExtent(
          width: paragraph.maxIntrinsicWidth * perPx,
          ascent: paragraph.alphabeticBaseline * perPx,
          descent: (paragraph.height - paragraph.alphabeticBaseline) * perPx,
        );
        paragraph.dispose();
        return extent;
      });

  /// Whether this measurer gives every text [other] was asked for the
  /// extent [other] gave it. False after a font those texts use has loaded.
  bool agreesWith(ParagraphMeasurer other) => other._extents.entries.every(
    (entry) => measure(entry.key.$1, entry.key.$2) == entry.value,
  );
}
