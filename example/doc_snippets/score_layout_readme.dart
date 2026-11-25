// packages/khuur_score_layout/README.md shows the code between the
// markers.
// .github/scripts/check_release_docs.sh fails when the two differ.
// ignore_for_file: avoid_print, depend_on_referenced_packages
// #docregion
import 'package:khuur_score_layout/khuur_score_layout.dart';
import 'package:khuur_score_model/khuur_score_model.dart';

/// Measures text as if every character were 0.6 of the font size wide.
final class MonospaceMeasurer implements TextMeasurer {
  const MonospaceMeasurer();

  @override
  TextExtent measure(String text, TextSpec spec) => TextExtent(
    width: text.runes.length * 0.6 * spec.size,
    ascent: 0.8 * spec.size,
    descent: 0.2 * spec.size,
  );
}

void main() {
  final score = Score.blank(
    parts: [
      const PartTemplate(
        name: 'Flute',
        instrument: Instrument(key: 'flute', program: 73),
      ),
    ],
    measureCount: 12,
  );
  final layout = SheetLayout(
    score,
    width: 100,
    text: const MonospaceMeasurer(),
  );
  for (var index = 0; index < layout.systemCount; index++) {
    final system = layout.systemAt(index);
    print('System $index: ${system.bars.length} bars');
  }
}
// #enddocregion
