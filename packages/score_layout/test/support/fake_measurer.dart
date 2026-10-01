import 'package:score_layout/score_layout.dart';

/// A fixed-pitch [TextMeasurer], so text has the same extent on every host.
///
/// Every character is 0.6 of the font size wide, whatever the style or the
/// family. The ascent is 0.8 of the size and the descent 0.2. A character is
/// one Unicode code point.
final class FakeMeasurer implements TextMeasurer {
  const FakeMeasurer();

  @override
  TextExtent measure(String text, TextSpec spec) => TextExtent(
    width: text.runes.length * 0.6 * spec.size,
    ascent: 0.8 * spec.size,
    descent: 0.2 * spec.size,
  );
}
