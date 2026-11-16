// Lays out a short score and prints where each system lands.
//
// Run it from packages/khuur_score_layout:
//
//   dart run example/khuur_score_layout_example.dart

// ignore_for_file: avoid_print

import 'package:khuur_score_layout/khuur_score_layout.dart';
import 'package:khuur_score_model/khuur_score_model.dart';

/// Measures text as if every character were 0.6 of the font size wide.
///
/// Layout needs the size of titles, lyrics and other text. A Flutter app
/// measures it with `dart:ui` paragraphs, as `khuur_sheet_music` does. A
/// program without Flutter can use a fixed-pitch estimate like this one.
final class MonospaceMeasurer implements TextMeasurer {
  const MonospaceMeasurer();

  @override
  TextExtent measure(String text, TextSpec spec) => TextExtent(
    width: text.runes.length * 0.6 * spec.size,
    ascent: 0.8 * spec.size,
    descent: 0.2 * spec.size,
  );
}

const flute = Instrument(
  key: 'flute',
  program: 73,
  lowest: Pitch(Step.c, 4),
  highest: Pitch(Step.c, 7),
);

void main() {
  var session = EditSession.start(
    Score.blank(
      title: 'Study',
      parts: [const PartTemplate(name: 'Flute', instrument: flute)],
      measureCount: 12,
    ),
  );
  // Enter a rising scale of quarter notes. Each note moves the cursor on.
  for (final tone in ['C5', 'D5', 'E5', 'F5', 'G5', 'A5', 'B5', 'C6']) {
    session = session
        .run(
          EnterNote(
            at: session.cursor,
            tone: Pitch.parse(tone),
            value: NoteValue.quarter,
          ),
        )
        .session;
  }

  // Width and every length the layout reports are in staff spaces, the
  // distance between two lines of a staff.
  final layout = SheetLayout(
    session.score,
    width: 100,
    text: const MonospaceMeasurer(),
  );
  print(
    '${layout.systemCount} systems, '
    '${layout.height.toStringAsFixed(1)} staff spaces tall',
  );
  for (var index = 0; index < layout.systemCount; index++) {
    final system = layout.systemAt(index);
    print(
      'System $index at y ${layout.tops[index].toStringAsFixed(1)}: '
      '${system.bars.length} bars, ${system.drawables.length} drawables',
    );
  }
}
