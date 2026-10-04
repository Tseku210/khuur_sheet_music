import 'package:example/midi_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page in a window the size of the macOS default.
Future<void> pumpPage(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(800, 600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MidiExampleApp());
}

void main() {
  testWidgets('shows the new player beside the old demo without overflow', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('New player (ScorePlayer)'), findsOneWidget);
    expect(find.text('MIDI Testing Tools'), findsOneWidget);
    expect(find.text('Status: idle'), findsOneWidget);
    expect(find.text('Position: stopped'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows why Play failed and goes back to idle', (tester) async {
    await pumpPage(tester);

    // No synthesizer plugin runs under flutter test, so loading fails. The
    // old demo has a Play button too, below the new panel.
    await tester.tap(find.text('Play').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.text('Status: idle'), findsOneWidget);
    expect(find.textContaining('MissingPluginException'), findsOneWidget);
  });
}
