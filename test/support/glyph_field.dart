/// The raster half of gate 1. A frame that shows [glyphCount] glyphs under
/// an overlay that repaints, as a system tile does during playback.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:khuur_sheet_music/src/painting.dart';
import 'package:score_layout/score_layout.dart';

/// More glyphs than a dense phone screen of music holds.
const glyphCount = 3000;

/// [glyphCount] glyphs in their own layer, under a line at [playhead].
///
/// The glyphs never repaint. Each new [playhead] repaints the overlay
/// alone, and the engine replays the glyph layer to compose the frame. That
/// replay is what the raster time measures.
class GlyphField extends StatelessWidget {
  const GlyphField({required this.playhead, super.key});

  final ValueListenable<double> playhead;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.topLeft,
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: CustomPaint(
          painter: _FieldPainter(GlyphPainter(SmuflFont.bravura)),
        ),
      ),
      CustomPaint(painter: _PlayheadPainter(playhead)),
    ],
  );
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.glyphs);

  final GlyphPainter glyphs;

  @override
  void paint(Canvas canvas, Size size) {
    const scale = SheetScale(spacePx: 8);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final columns = (size.width / 12).floor();
    final rows = (glyphCount / columns).ceil();
    for (var index = 0; index < glyphCount; index++) {
      final x = (index % columns + 0.5) * size.width / columns;
      final y = (index ~/ columns + 0.5) * size.height / rows;
      glyphs.paint(
        canvas,
        Glyph.values[index % Glyph.values.length],
        scale.toSheet(Offset(x, y)),
        scale,
        const Color(0xFF000000),
      );
    }
  }

  @override
  bool shouldRepaint(_FieldPainter oldDelegate) => false;
}

class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter(this.playhead) : super(repaint: playhead);

  final ValueListenable<double> playhead;

  @override
  void paint(Canvas canvas, Size size) {
    final x = playhead.value % 1 * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = const Color(0xFFD32F2F)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PlayheadPainter oldDelegate) =>
      oldDelegate.playhead != playhead;
}
