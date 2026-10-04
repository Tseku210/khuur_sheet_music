import 'dart:io';
import 'dart:ui' as ui;

import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';

import '../../test/mock/fake_midi_output.dart';
import '../../test/support/draw.dart';

const Size desktop = Size(800, 600);
const Size phone = Size(390, 844);

final Key pageKey = UniqueKey();

Future<void> pumpApp(
  WidgetTester tester, {
  Size size = desktop,
  MidiOutput? output,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: ExampleApp(output: output),
    ),
  );
  await tester.pump();
}

/// An output that stamps every call at time zero, as these tests read only
/// what was sent.
FakeMidiOutput fakeOutput() => FakeMidiOutput(() => Duration.zero);

SheetView sheetOf(WidgetTester tester) => tester.widget(find.byType(SheetView));

Score scoreOf(WidgetTester tester) => sheetOf(tester).score;

SheetController controllerOf(WidgetTester tester) =>
    sheetOf(tester).controller!;

Offset onScreen(WidgetTester tester, Offset local) =>
    tester.getTopLeft(find.byType(SheetView)) + local;

/// Voice one of the staff at [staff] at [beat] of the first bar, counting
/// quarters from 0.
VoicePoint beatOf(Score score, int staff, int beat) => VoicePoint(
  staff: score.staves[staff].id,
  voice: VoiceSlot.one,
  at: ScorePoint(score.measures.first.id, Moment(Fraction(beat, 4))),
);

({Fraction startQuarter, String written}) eventHolding(
  Score score,
  VoicePoint at,
) {
  final timed = score.eventAt(at)!;
  return (
    startQuarter: timed.onset.wholeNotes * Fraction(4, 1),
    written: switch (timed.event) {
      ChordEvent(:final value, :final notes) =>
        '$value ${notes.map((note) => note.tone).join(' ')}',
      RestEvent(:final value) => '$value rest',
      MeasureRest() => 'bar rest',
    },
  );
}

/// Taps the staff at [at], on its middle line, where no note is.
Future<void> tapStaffAt(WidgetTester tester, VoicePoint at) async {
  final caret = controllerOf(tester).caretOf(at)!;
  final hit = controllerOf(tester).hitTest(caret.center)!;
  expect(
    (hit.staff, hit.at, hit.staffStep, hit.target),
    (at.staff, at.at, 4, null),
    reason: 'the tap must land on the middle line at the point, off a note',
  );
  await tester.tapAt(onScreen(tester, caret.center));
  await tester.pump();
}

/// Taps the first note of the top staff.
Future<EventRef> tapFirstNote(WidgetTester tester) async {
  final score = scoreOf(tester);
  final ref = score.eventAt(beatOf(score, 0, 0))!.ref;
  final at = controllerOf(tester).rectOf(ref)!.center;
  expect(controllerOf(tester).hitTest(at)!.target, isA<ElementOwner>());
  await tester.tapAt(onScreen(tester, at));
  await tester.pump();
  return ref;
}

/// Loads the Flutter SDK's own fonts under the families the page asks for,
/// so that its picture has letters and icons. `flutter test` registers no
/// font, and draws a box for every letter without them. The sheet's own
/// text names no family, so its letters stay boxes.
Future<void> loadPageFonts() async {
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  for (final (file, family) in const [
    ('Roboto-Regular.ttf', 'Roboto'),
    ('MaterialIcons-Regular.otf', 'MaterialIcons'),
  ]) {
    if (File('$fonts/$file').existsSync()) {
      await loadFontFile('$fonts/$file', family);
    }
  }
}

Iterable<int> keysOf(FakeMidiOutput output) =>
    output.ons.map((note) => note.key);

/// Lets time pass until [output] has been sent more than [sent] notes, for
/// ten seconds at most. The player sends every note of one moment at once.
Future<void> pumpUntilMoreThan(
  WidgetTester tester,
  FakeMidiOutput output,
  int sent,
) async {
  for (var tenths = 0; tenths < 100 && output.ons.length <= sent; tenths++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(
    () => loadFontFile(
      '../fonts/Bravura.otf',
      'packages/simple_sheet_music/Bravura',
    ),
  );

  for (final (name, size) in [
    ('a desktop window', desktop),
    ('a phone', phone),
  ]) {
    testWidgets('fits $name and shows more than one system', (tester) async {
      await pumpApp(tester, size: size);

      expect(tester.takeException(), isNull);
      expect(controllerOf(tester).systemCount, greaterThan(1));
    });
  }

  testWidgets('a tap on a staff enters a quarter note where it lands', (
    tester,
  ) async {
    await pumpApp(tester);
    final beat2 = beatOf(scoreOf(tester), 1, 1);
    expect(eventHolding(scoreOf(tester), beat2), (
      startQuarter: Fraction.zero,
      written: 'half C3 E3 G3',
    ));

    await tapStaffAt(tester, beat2);

    expect(eventHolding(scoreOf(tester), beat2), (
      startQuarter: Fraction(1, 1),
      written: 'quarter D3',
    ));
    expect(sheetOf(tester).cursor, beatOf(scoreOf(tester), 1, 2));
  });

  testWidgets('a tap enters the value picked below the sheet', (tester) async {
    await pumpApp(tester);
    final beat2 = beatOf(scoreOf(tester), 1, 1);

    await tester.tap(find.text('1/8'));
    await tester.pump();
    await tapStaffAt(tester, beat2);

    expect(eventHolding(scoreOf(tester), beat2), (
      startQuarter: Fraction(1, 1),
      written: 'eighth D3',
    ));
  });

  testWidgets('a tap on a note selects it and enters nothing', (tester) async {
    await pumpApp(tester);
    final before = scoreOf(tester);
    expect(sheetOf(tester).selection.singleEvent, isNull);

    final ref = await tapFirstNote(tester);

    expect(sheetOf(tester).selection.singleEvent, ref);
    expect(scoreOf(tester), same(before));
  });

  testWidgets('the delete badge sits at the selected note and clears it', (
    tester,
  ) async {
    await pumpApp(tester);
    final badge = find.widgetWithIcon(IconButton, Icons.delete_outline);
    expect(badge, findsNothing);

    final ref = await tapFirstNote(tester);

    final rect = controllerOf(tester).rectOf(ref)!;
    expect(
      tester.getTopLeft(badge),
      onScreen(tester, Offset(rect.right, rect.top - 32)),
    );

    await tester.tap(badge);
    await tester.pump();

    final beat1 = beatOf(scoreOf(tester), 0, 0);
    expect(eventHolding(scoreOf(tester), beat1), (
      startQuarter: Fraction.zero,
      written: 'quarter rest',
    ));
  });

  testWidgets('the badge follows its note when the sheet scrolls', (
    tester,
  ) async {
    await pumpApp(tester);
    final badge = find.widgetWithIcon(IconButton, Icons.delete_outline);
    final ref = await tapFirstNote(tester);
    final before = tester.getTopLeft(badge);

    await tester.drag(find.byType(SheetView), const Offset(0, -60));
    await tester.pump();

    final rect = controllerOf(tester).rectOf(ref)!;
    expect(tester.getTopLeft(badge).dy, lessThan(before.dy));
    expect(
      tester.getTopLeft(badge),
      onScreen(tester, Offset(rect.right, rect.top - 32)),
    );
  });

  testWidgets('Undo takes back the last edit and is off with none to take', (
    tester,
  ) async {
    await pumpApp(tester);
    final undo = find.widgetWithIcon(IconButton, Icons.undo);
    final beat2 = beatOf(scoreOf(tester), 1, 1);
    expect(tester.widget<IconButton>(undo).onPressed, isNull);

    await tapStaffAt(tester, beat2);
    await tester.tap(undo);
    await tester.pump();

    expect(eventHolding(scoreOf(tester), beat2), (
      startQuarter: Fraction.zero,
      written: 'half C3 E3 G3',
    ));
    expect(tester.widget<IconButton>(undo).onPressed, isNull);
  });

  testWidgets('the zoom buttons scale the sheet through its controller', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    final ref = score.eventAt(beatOf(score, 0, 0))!.ref;
    final width = controllerOf(tester).rectOf(ref)!.width;

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    await tester.pump();

    expect(controllerOf(tester).zoom, 1.25);
    expect(
      controllerOf(tester).rectOf(ref)!.width,
      closeTo(width * 1.25, 1e-6),
    );

    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    await tester.pump();

    expect(controllerOf(tester).zoom, closeTo(0.8, 1e-9));
    expect(controllerOf(tester).rectOf(ref)!.width, closeTo(width * 0.8, 1e-6));
  });

  testWidgets('Play loads the sound font and plays the score on screen', (
    tester,
  ) async {
    final output = fakeOutput();
    await pumpApp(tester, output: output);
    await tapStaffAt(tester, beatOf(scoreOf(tester), 1, 1));

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();

    expect(output.loaded, [
      isA<AssetSoundFont>().having(
        (font) => font.path,
        'path',
        'assets/soundfonts/piano.sf2',
      ),
    ]);
    expect(keysOf(output), unorderedEquals([64, 48, 52, 55]));
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(sheetOf(tester).playback!.value, isNotNull);

    await pumpUntilMoreThan(tester, output, 4);

    expect(
      keysOf(output).skip(4),
      unorderedEquals([67, 50]),
      reason: 'the second beat, with the entered D3 in the bass',
    );

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
  });

  testWidgets('Pause lets go of the notes and Resume plays on from there', (
    tester,
  ) async {
    final output = fakeOutput();
    await pumpApp(tester, output: output);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(output.held, hasLength(4));

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();

    expect(output.held, isEmpty);
    expect(find.byTooltip('Resume'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));

    expect(keysOf(output), hasLength(4), reason: 'nothing sounds while paused');

    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    await pumpUntilMoreThan(tester, output, 4);

    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(keysOf(output).skip(4), [
      67,
    ], reason: 'the second beat, not the first again');

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
  });

  testWidgets('Stop silences the output and takes the playhead away', (
    tester,
  ) async {
    final output = fakeOutput();
    await pumpApp(tester, output: output);
    final stop = find.widgetWithIcon(IconButton, Icons.stop);
    expect(tester.widget<IconButton>(stop).onPressed, isNull);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();

    await tester.tap(stop);
    await tester.pump();

    expect(output.log.last, endsWith('all off'));
    expect(output.held, isEmpty);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(sheetOf(tester).playback!.value, isNull);

    await tester.pump(const Duration(seconds: 5));

    expect(keysOf(output), hasLength(4), reason: 'nothing sounds once stopped');
  });

  testWidgets('the tempo slider slows the player', (tester) async {
    final output = fakeOutput();
    await pumpApp(tester, output: output);
    expect(find.text('100%'), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(-600, 0));
    await tester.pump();

    expect(find.text('25%'), findsOneWidget);

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    // The second beat is 0.625 seconds in as written, and four times that
    // at a quarter of the speed.
    await tester.pump(const Duration(seconds: 2));

    expect(keysOf(output), hasLength(4));

    await pumpUntilMoreThan(tester, output, 4);

    expect(keysOf(output).skip(4), [67]);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
  });

  testWidgets('shows why Play failed and offers Play again', (tester) async {
    await pumpApp(tester);

    // No synthesizer plugin runs under flutter test, so loading fails.
    await tester.tap(find.byTooltip('Play'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.textContaining('MissingPluginException'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  for (final (name, size) in [('desktop', desktop), ('phone', phone)]) {
    testWidgets('draws dark ink on a light page where the first note is, '
        'at the $name size', (tester) async {
      await tester.runAsync(loadPageFonts);
      await pumpApp(tester, size: size);
      final ref = await tapFirstNote(tester);
      final rect = controllerOf(tester).rectOf(ref)!;
      // The head sits on the bottom line, so this is its lower half, clear
      // of the line.
      final head = onScreen(tester, Offset(rect.center.dx, rect.bottom - 2));
      final margin = onScreen(tester, const Offset(4, 4));

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(pageKey),
      );
      final (:rgba, :png) = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final rgba = await image.toByteData();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return (
          rgba: rgba!.buffer.asUint8List(),
          png: png!.buffer.asUint8List(),
        );
      }))!;
      writeSnapshot('example_app_$name', png);

      int redAt(Offset at) =>
          rgba[(at.dy.round() * size.width.round() + at.dx.round()) * 4];
      expect(redAt(margin), greaterThan(200), reason: 'the page is light');
      expect(redAt(head), lessThan(100), reason: 'the note head is dark');
    });
  }
}
