import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khuur_sheet_music/khuur_sheet_music.dart';

import 'support/draw.dart';

void main() {
  testWidgets("a value's glyph as text in the bundled font's flutterFamily is "
      'drawn in Bravura, as wide as its table says', (tester) async {
    await tester.runAsync(
      () => loadFontFile(bravuraFile, SmuflFont.bravura.flutterFamily),
    );
    const fontSize = 40.0;

    for (final glyph in [
      noteGlyph(.quarter),
      restGlyph(.eighth),
      accidentalGlyph(.sharp, .steinZimmermann),
      dynamicGlyph(.mf),
      bowingGlyph(.up),
      ...fingeringGlyphs(3),
      Glyph.augmentationDot,
    ]) {
      final text = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(glyph.codepoint),
          style: TextStyle(
            fontFamily: SmuflFont.bravura.flutterFamily,
            fontSize: fontSize,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      expect(
        text.width,
        closeTo(SmuflFont.bravura[glyph].advance * fontSize / 4, 0.5),
        reason: glyph.name,
      );
      text.dispose();
    }
  });
}
