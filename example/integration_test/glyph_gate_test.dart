// Gate 1 of the layout design, on a device. See
// docs/design/layout/RATIONALE.md, decision 10.
//
// Placement, in a debug build:
//   flutter test integration_test/glyph_gate_test.dart -d <device>
// Raster time, which only a profile build can judge:
//   flutter drive --profile --driver=test_driver/integration_test.dart \
//     --target=integration_test/glyph_gate_test.dart -d <device>

import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/support/glyph_field.dart';
import '../../test/support/glyph_gate.dart';

/// Half a frame at 60 Hz.
const rasterBudgetMillis = 8.0;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // No font is loaded here. The glyphs come from the font the package
  // declares, under the family the painter asks for, as in any app.
  testWidgets('every glyph is drawn where the table says', (tester) async {
    await tester.runAsync(() async {
      final failures = await glyphGateFailures(
        bravuraPainter(),
        report: debugPrint,
      );

      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });

  testWidgets('$glyphCount glyphs raster in half a frame', (tester) async {
    final playhead = ValueNotifier<double>(0);
    addTearDown(playhead.dispose);
    final timings = <FrameTiming>[];
    binding.addTimingsCallback(timings.addAll);
    addTearDown(() => binding.removeTimingsCallback(timings.addAll));
    await tester.pumpWidget(GlyphField(playhead: playhead));
    await tester.pump();
    expect(await _darkPixels(tester), greaterThan(glyphCount * 4));
    expect(
      await tester.runAsync(() => noteheadFailures(bravuraPainter())),
      isEmpty,
    );
    // The engine reports timings in batches, up to a second late.
    await tester.pump(const Duration(seconds: 2));
    timings.clear();

    for (var frame = 1; frame <= 240; frame++) {
      playhead.value = frame / 240;
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 2));

    final raster = [
      for (final timing in timings) timing.rasterDuration.inMicroseconds / 1000,
    ]..sort();
    final build = [
      for (final timing in timings) timing.buildDuration.inMicroseconds / 1000,
    ]..sort();
    expect(raster.length, greaterThan(200));
    final typical = raster[raster.length * 9 ~/ 10];
    debugPrint(
      'gate 1: $glyphCount glyphs, ${raster.length} frames: raster median '
      '${raster[raster.length ~/ 2]} ms, 90th percentile $typical ms, worst '
      '${raster.last} ms; build median ${build[build.length ~/ 2]} ms',
    );

    // A debug build's times say nothing about a release build's.
    if (!kDebugMode) {
      expect(typical, lessThanOrEqualTo(rasterBudgetMillis));
    }
    // A window that is not on screen gets no frames, and a pump then waits
    // for ever.
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// How many pixels of the glyph layer are ink, which proves the frames
/// that are timed show something. `noteheadFailures` proves it is the font.
Future<int> _darkPixels(WidgetTester tester) async {
  final layer = tester.renderObject<RenderRepaintBoundary>(
    find.descendant(
      of: find.byType(GlyphField),
      matching: find.byType(RepaintBoundary),
    ),
  );
  final rgba = await tester.runAsync(() async {
    final image = await layer.toImage();
    return (await image.toByteData())!.buffer.asUint8List();
  });
  var dark = 0;
  for (var red = 0; red < rgba!.length; red += 4) {
    if (rgba[red] < 128) {
      dark++;
    }
  }
  return dark;
}
