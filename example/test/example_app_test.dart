import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:example/demo_score.dart';
import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';

import '../../test/mock/fake_midi_output.dart';
import '../../test/support/draw.dart';
import 'support/eight_bars.dart';

const Size desktop = Size(800, 600);
const Size phone = Size(390, 844);

final Key pageKey = UniqueKey();

/// Shows the page over [eightBars], so that what a test edits and plays
/// does not hang on the tune the app ships with. With [demo] the page opens
/// as the app does, with the tune of its own.
Future<void> pumpApp(
  WidgetTester tester, {
  Size size = desktop,
  MidiOutput? output,
  bool demo = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: ExampleApp(output: output, score: demo ? null : eightBars()),
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

/// Voice one of the staff at [staff], [eighth] eighths into bar [bar], both
/// counted from 0.
VoicePoint eighthOf(Score score, int staff, int eighth, {int bar = 0}) =>
    VoicePoint(
      staff: score.staves[staff].id,
      voice: VoiceSlot.one,
      at: ScorePoint(score.measures[bar].id, Moment(Fraction(eighth, 8))),
    );

/// Voice one of the staff at [staff] at [beat] of bar [bar], counting
/// quarters and bars from 0.
VoicePoint beatOf(Score score, int staff, int beat, {int bar = 0}) =>
    eighthOf(score, staff, beat * 2, bar: bar);

String writtenOf(Event event) => switch (event) {
  ChordEvent(:final value, :final notes) =>
    '$value ${notes.map((note) => note.tone).join(' ')}',
  RestEvent(:final value) => '$value rest',
  MeasureRest() => 'bar rest',
};

({Fraction startQuarter, String written}) eventHolding(
  Score score,
  VoicePoint at,
) {
  final timed = score.eventAt(at)!;
  return (
    startQuarter: timed.onset.wholeNotes * Fraction(4, 1),
    written: writtenOf(timed.event),
  );
}

ChordEvent chordAt(Score score, VoicePoint at) =>
    score.eventAt(at)!.event as ChordEvent;

VoiceView _voiceOne(Score score, int staff, int bar) =>
    score.measureView(score.measures[bar].id).staves[staff].voices.first;

/// What voice one of the staff at [staff] holds in bar [bar], in order.
List<String> writtenIn(Score score, int staff, {int bar = 0}) => [
  for (final timed in _voiceOne(score, staff, bar).events)
    writtenOf(timed.event),
];

/// Whether each event of that voice is a chord with every head tied onward.
List<bool> tiesIn(Score score, int staff, {int bar = 0}) => [
  for (final timed in _voiceOne(score, staff, bar).events)
    switch (timed.event) {
      ChordEvent(:final notes) => notes.every((note) => note.tie),
      _ => false,
    },
];

/// The beam groups of that voice, each as the ids of its events.
List<List<EventId>> beamsOf(Score score, int staff, {int bar = 0}) => [
  for (final group in _voiceOne(score, staff, bar).beams) group.events,
];

/// The slurs and hairpins of [score], in the order they were added.
List<(String kind, StaffId staff, ScorePoint first, ScorePoint last)> linesOf(
  Score score,
) => [
  for (final spanner in score.spanners)
    (
      switch (spanner.kind) {
        Slur() => 'slur',
        Hairpin(crescendo: true) => 'crescendo',
        Hairpin(crescendo: false) => 'decrescendo',
        final other => '${other.runtimeType}',
      },
      spanner.staff,
      spanner.first,
      spanner.last,
    ),
];

/// The picked events in time order, each as its bar, counted from 0, and
/// what it holds.
List<(int bar, String written)> selectedOf(WidgetTester tester) {
  final score = scoreOf(tester);
  final picked = switch (sheetOf(tester).selection) {
    ItemSelection(:final items) => [
      for (final ref in {for (final item in items) item.event})
        score.lookup(ref)!,
    ],
    _ => <TimedEvent>[],
  };
  final sorted = [
    for (final timed in picked)
      (score.indexOf(timed.ref.measure), timed.onset, timed.event),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.compareTo(b.$2));
  return [for (final (bar, _, event) in sorted) (bar, writtenOf(event))];
}

/// Scrolls the system that holds [at] into view.
Future<void> bringIntoView(WidgetTester tester, VoicePoint at) async {
  unawaited(controllerOf(tester).ensureVisible(at.at, duration: Duration.zero));
  await tester.pump();
  await tester.pump();
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

/// Taps the staff at [at] at a height where nothing drawn is in reach, so
/// the tap enters a note there, at whatever pitch that height is.
Future<void> tapClearOf(WidgetTester tester, VoicePoint at) async {
  final sheet = controllerOf(tester);
  final caret = sheet.caretOf(at)!;
  for (var y = caret.top - 24; y <= caret.bottom + 24; y += 4) {
    final spot = Offset(caret.center.dx, y);
    final hit = sheet.hitTest(spot);
    if (hit != null &&
        (hit.staff, hit.at, hit.target) == (at.staff, at.at, null)) {
      await tester.tapAt(onScreen(tester, spot));
      await tester.pump();
      return;
    }
  }
  fail('nothing clear to tap on the staff at ${at.at}');
}

/// Taps the note or the rest that holds [at], and gives its event.
Future<EventRef> tapNoteAt(WidgetTester tester, VoicePoint at) async {
  await bringIntoView(tester, at);
  final ref = scoreOf(tester).eventAt(at)!.ref;
  final centre = controllerOf(tester).rectOf(ref)!.center;
  expect(
    controllerOf(tester).hitTest(centre)!.target,
    isA<ElementOwner>().having((owner) => owner.ref.event, 'event', ref),
  );
  await tester.tapAt(onScreen(tester, centre));
  await tester.pump();
  return ref;
}

/// Taps the first note of the top staff.
Future<EventRef> tapFirstNote(WidgetTester tester) =>
    tapNoteAt(tester, beatOf(scoreOf(tester), 0, 0));

/// Taps one head of the chord that holds [at], counted from 0 in the
/// chord's own order.
Future<void> tapHeadAt(WidgetTester tester, VoicePoint at, int index) async {
  final chord = scoreOf(tester).eventAt(at)!;
  final head = NoteRef(
    chord.ref,
    (chord.event as ChordEvent).notes.elementAt(index).id,
  );
  final centre = controllerOf(tester).rectOf(head)!.center;
  expect(controllerOf(tester).hitTest(centre)!.target, ElementOwner(head));
  await tester.tapAt(onScreen(tester, centre));
  await tester.pump();
}

/// The button of the action row that shows [label] under its icon.
Finder actionButton(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextButton));

/// Whether the button of the action row named [label] can be pressed.
bool isOn(WidgetTester tester, String label) =>
    tester.widget<TextButton>(actionButton(label)).onPressed != null;

/// Presses the button of the action row named [label], scrolled into reach
/// first.
Future<void> press(WidgetTester tester, String label) async {
  await tester.ensureVisible(actionButton(label));
  await tester.pump();
  await tester.tap(actionButton(label));
  await tester.pump();
}

/// Flips the switch under the sheet that [label] names.
Future<void> flip(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
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

/// Picks [name] from the menu of sheets. The pumps are of a fixed length,
/// since a page that plays never settles.
Future<void> openSheet(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('New sheet'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text(name));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// How far down the sheet is scrolled.
double scrolledBy(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(SheetView),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .pixels;

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

  testWidgets('opens with the demo tune when it is given no score', (
    tester,
  ) async {
    await pumpApp(tester, demo: true);

    final demo = buildDemoScore();
    expect(scoreOf(tester).meta.title, demo.meta.title);
    expect(writtenIn(scoreOf(tester), 0), writtenIn(demo, 0));
    expect(writtenIn(scoreOf(tester), 0), isNot(writtenIn(eightBars(), 0)));
  });

  testWidgets('New sheet opens an empty sheet to write on, and the tune '
      'comes back from the same menu', (tester) async {
    await pumpApp(tester, demo: true);

    await openSheet(tester, 'Empty sheet');

    final empty = scoreOf(tester);
    expect(empty.meta.title, isEmpty);
    expect(empty.staves.length, 1);
    expect([
      for (final column in empty.measures) column.meter,
    ], List.filled(4, Meter.fourFour));
    expect([
      for (var bar = 0; bar < 4; bar++) writtenIn(empty, 0, bar: bar),
    ], List.filled(4, ['bar rest']));

    await tapStaffAt(tester, beatOf(empty, 0, 0));

    expect(writtenIn(scoreOf(tester), 0).first, 'quarter B4');

    await openSheet(tester, 'Für Elise');

    final demo = buildDemoScore();
    expect(scoreOf(tester).meta.title, demo.meta.title);
    expect(
      [
        for (var bar = 0; bar < demo.measures.length; bar++)
          for (var staff = 0; staff < 2; staff++)
            writtenIn(scoreOf(tester), staff, bar: bar),
      ],
      [
        for (var bar = 0; bar < demo.measures.length; bar++)
          for (var staff = 0; staff < 2; staff++)
            writtenIn(demo, staff, bar: bar),
      ],
    );
  });

  testWidgets('a new sheet stops the player', (tester) async {
    final output = fakeOutput();
    await pumpApp(tester, output: output);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();

    await openSheet(tester, 'Empty sheet');

    expect(output.log.last, endsWith('all off'));
    expect(output.held, isEmpty);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(sheetOf(tester).playback!.value, isNull);
    final sent = keysOf(output).length;

    await tester.pump(const Duration(seconds: 5));

    expect(keysOf(output), hasLength(sent));
  });

  testWidgets('a new sheet has nothing to undo and shows its top', (
    tester,
  ) async {
    await pumpApp(tester, size: phone, demo: true);
    final undo = find.widgetWithIcon(IconButton, Icons.undo);
    final score = scoreOf(tester);
    await tapStaffAt(tester, eighthOf(score, 1, 0, bar: 1));
    await bringIntoView(tester, eighthOf(score, 0, 0, bar: 8));
    expect(tester.widget<IconButton>(undo).onPressed, isNotNull);
    expect(scrolledBy(tester), greaterThan(0));

    await openSheet(tester, 'Für Elise');

    expect(tester.widget<IconButton>(undo).onPressed, isNull);
    expect(scrolledBy(tester), 0);
    expect(writtenIn(scoreOf(tester), 1, bar: 1), ['bar rest']);
  });

  testWidgets("on a phone the demo tune's pickup shares its system with the "
      'bar after it', (tester) async {
    await pumpApp(tester, size: phone, demo: true);
    final score = scoreOf(tester);
    Rect firstNoteOf(int bar) =>
        controllerOf(tester)
            .rectOf(score.eventAt(eighthOf(score, 0, 0, bar: bar))!.ref)!;

    expect(
      [
        for (final bar in [0, 1]) writtenIn(score, 0, bar: bar).first,
      ],
      ['sixteenth E5', 'sixteenth E5'],
      reason: 'both bars open on the same note, so on the same height',
    );
    expect(firstNoteOf(1).top, closeTo(firstNoteOf(0).top, 1e-6));
    expect(firstNoteOf(1).left, greaterThan(firstNoteOf(0).right));
  });

  for (final (tune, demo) in [('the demo tune', true), ('eight bars', false)]) {
    for (final (name, size) in [
      ('a desktop window', desktop),
      ('a phone', phone),
    ]) {
      testWidgets('$tune fits $name and shows more than one system', (
        tester,
      ) async {
        await pumpApp(tester, size: size, demo: demo);

        expect(tester.takeException(), isNull);
        expect(controllerOf(tester).systemCount, greaterThan(1));
      });

      testWidgets('$tune fits $name with the action row showing, and the '
          'row scrolls to its last button', (tester) async {
        await pumpApp(tester, size: size, demo: demo);

        await tapFirstNote(tester);

        expect(tester.takeException(), isNull);
        expect(actionButton('Widen left'), findsOneWidget);
        expect(
          tester
              .widget<Scrollbar>(
                find.ancestor(
                  of: actionButton('Widen left'),
                  matching: find.byType(Scrollbar),
                ),
              )
              .thumbVisibility,
          isTrue,
          reason: 'the thumb says how much of the row is past the edge',
        );

        await press(tester, 'Deselect');

        expect(tester.takeException(), isNull);
        expect(sheetOf(tester).selection.isEmpty, isTrue);
      });
    }
  }

  testWidgets("the sheet keeps the theme's colours in dark mode, under a "
      'selection style of its own', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester);
    final scheme = Theme.of(tester.element(find.byType(SheetView))).colorScheme;
    expect(scheme.brightness, Brightness.dark);

    final palette = sheetOf(tester).palette;

    expect(palette?.ink, scheme.onSurface);
    expect(palette?.cursor.color, scheme.primary);
    expect(palette?.selection.border, isNotNull);
    expect(palette?.selection.radius, greaterThan(0));
  });

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

  testWidgets('the action row takes the place of the hint while something is '
      'selected, between the sheet and the panel', (tester) async {
    await pumpApp(tester);
    final hint = find.textContaining('Tap a staff to enter a note.');
    final sheet = tester.getRect(find.byType(SheetView));
    expect(hint, findsOneWidget);
    expect(actionButton('Delete'), findsNothing);

    await tapFirstNote(tester);

    final row = tester.getRect(actionButton('Delete'));
    expect(row.top, sheet.bottom);
    expect(row.bottom, tester.getRect(find.byType(Divider)).top);
    expect(hint, findsNothing);
    expect(
      tester.getRect(find.byType(SheetView)),
      sheet,
      reason: 'the sheet keeps its size, so no note moves under the row',
    );

    await press(tester, 'Deselect');

    expect(sheetOf(tester).selection.isEmpty, isTrue);
    expect(actionButton('Delete'), findsNothing);
    expect(hint, findsOneWidget);
  });

  testWidgets('on a phone the row opens with Delete and the four buttons that '
      'widen and narrow, each with its name', (tester) async {
    await pumpApp(tester, size: phone);

    await tapFirstNote(tester);

    final opening = [
      for (final label in const [
        'Delete',
        'Widen left',
        'Widen right',
        'Narrow left',
        'Narrow right',
      ])
        tester.getRect(actionButton(label)),
    ];
    expect(opening.first.left, greaterThanOrEqualTo(0));
    expect(opening.last.right, lessThanOrEqualTo(phone.width));
    for (final (index, rect) in opening.indexed.skip(1)) {
      expect(rect.left, opening[index - 1].right);
    }
    for (final label in const [
      'Pitch down',
      'Pitch up',
      'Octave down',
      'Octave up',
      'Tie',
      'Slur',
      'Beam',
      'Unbeam',
      'Auto beam',
      'Crescendo',
      'Decrescendo',
      'Copy',
      'Paste',
      'Deselect',
    ]) {
      expect(actionButton(label), findsOneWidget, reason: label);
    }
    final cut = tester.getRect(actionButton('Pitch down'));
    expect(
      phone.width,
      allOf(greaterThan(cut.left), lessThan(cut.right)),
      reason: 'a button cut by the edge says that the row goes on',
    );
  });

  testWidgets('the hint and the action row keep to their slot at twice the '
      'text size, and the sheet keeps its size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: phone);
    final sheet = tester.getRect(find.byType(SheetView));
    final slot = Rect.fromLTRB(
      0,
      sheet.bottom,
      phone.width,
      tester.getRect(find.byType(Divider)).top,
    );
    Rect within(Rect outer, Rect inner) => outer.expandToInclude(inner);

    final hint = tester.getRect(
      find.textContaining('Tap a staff to enter a note.'),
    );
    expect(within(slot, hint), slot, reason: 'the hint at $hint');

    await tapFirstNote(tester);

    expect(tester.takeException(), isNull);
    final button = tester.getRect(actionButton('Delete'));
    final name = tester.getRect(find.text('Delete'));
    expect(within(slot, button), slot, reason: 'the button at $button');
    expect(within(button, name), button, reason: 'the name at $name');
    expect(tester.getRect(find.byType(SheetView)), sheet);
  });

  testWidgets('Delete clears every selected event', (tester) async {
    await pumpApp(tester);
    await tapFirstNote(tester);
    await press(tester, 'Widen right');

    await press(tester, 'Delete');

    expect(writtenIn(scoreOf(tester), 0), [
      'quarter rest',
      'quarter rest',
      'eighth C5',
      'eighth B4',
      'quarter C5',
    ]);
  });

  testWidgets('Widen right and Widen left take in the note across a bar line', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);

    await tapNoteAt(tester, beatOf(score, 0, 3));
    await press(tester, 'Widen right');

    expect(selectedOf(tester), [(0, 'quarter C5'), (1, 'quarter A4')]);

    await tapNoteAt(tester, beatOf(score, 0, 0, bar: 1));
    expect(selectedOf(tester), [(1, 'quarter A4')]);
    await press(tester, 'Widen left');

    expect(selectedOf(tester), [(0, 'quarter C5'), (1, 'quarter A4')]);
  });

  testWidgets('the selection widens past neither end of the score', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);

    await tapNoteAt(tester, beatOf(score, 0, 0));

    expect(isOn(tester, 'Widen left'), isFalse);
    expect(isOn(tester, 'Widen right'), isTrue);

    await tapNoteAt(tester, beatOf(score, 0, 2, bar: 7));

    expect(isOn(tester, 'Widen left'), isTrue);
    expect(isOn(tester, 'Widen right'), isFalse);
  });

  testWidgets('the selection widens over a rest', (tester) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    await tapNoteAt(tester, beatOf(score, 0, 1));
    await press(tester, 'Delete');

    await tapNoteAt(tester, beatOf(score, 0, 0));
    await press(tester, 'Widen right');
    await press(tester, 'Widen right');

    expect(selectedOf(tester), [
      (0, 'quarter E4'),
      (0, 'quarter rest'),
      (0, 'eighth C5'),
    ]);
  });

  testWidgets('Narrow left and Narrow right drop an end, and are off with one '
      'event', (tester) async {
    await pumpApp(tester);
    await tapFirstNote(tester);
    expect(isOn(tester, 'Narrow left'), isFalse);
    expect(isOn(tester, 'Narrow right'), isFalse);
    await press(tester, 'Widen right');
    await press(tester, 'Widen right');

    await press(tester, 'Narrow left');

    expect(selectedOf(tester), [(0, 'quarter G4'), (0, 'eighth C5')]);

    await press(tester, 'Widen right');
    await press(tester, 'Narrow right');

    expect(selectedOf(tester), [(0, 'quarter G4'), (0, 'eighth C5')]);

    await press(tester, 'Narrow right');

    expect(selectedOf(tester), [(0, 'quarter G4')]);
    expect(isOn(tester, 'Narrow left'), isFalse);
    expect(isOn(tester, 'Narrow right'), isFalse);
  });

  testWidgets('the row works on the selection in time order, whatever order '
      'it grew in', (tester) async {
    await pumpApp(tester);
    await tapNoteAt(tester, beatOf(scoreOf(tester), 0, 0, bar: 1));

    await press(tester, 'Widen left');
    await press(tester, 'Widen left');

    expect(selectedOf(tester), [
      (0, 'eighth B4'),
      (0, 'quarter C5'),
      (1, 'quarter A4'),
    ]);

    await press(tester, 'Narrow right');

    expect(selectedOf(tester), [(0, 'eighth B4'), (0, 'quarter C5')]);

    await press(tester, 'Widen left');

    expect(selectedOf(tester), [
      (0, 'eighth C5'),
      (0, 'eighth B4'),
      (0, 'quarter C5'),
    ]);
  });

  testWidgets('Paste is off with nothing copied, and puts the copy at the '
      'first selected event', (tester) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    await tapFirstNote(tester);
    expect(isOn(tester, 'Paste'), isFalse);
    await press(tester, 'Widen right');
    await press(tester, 'Copy');
    await tapNoteAt(tester, beatOf(score, 0, 0, bar: 1));
    await press(tester, 'Widen right');

    await press(tester, 'Paste');

    expect(writtenIn(scoreOf(tester), 0, bar: 1), [
      'quarter E4',
      'quarter G4',
      'quarter C5',
      'quarter E5',
    ]);
  });

  testWidgets('what was pasted is selected, so the row works on it', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    await tapFirstNote(tester);
    await press(tester, 'Widen right');
    await press(tester, 'Copy');
    await tapNoteAt(tester, beatOf(score, 0, 0, bar: 1));
    await press(tester, 'Paste');

    await press(tester, 'Widen right');

    expect(selectedOf(tester), [
      (1, 'quarter E4'),
      (1, 'quarter G4'),
      (1, 'quarter C5'),
    ]);
  });

  testWidgets('Pitch up and Pitch down move the selected notes by a step of '
      'the scale', (tester) async {
    await pumpApp(tester);
    await tapFirstNote(tester);
    await press(tester, 'Widen right');

    await press(tester, 'Pitch up');

    expect(writtenIn(scoreOf(tester), 0).take(3), [
      'quarter F4',
      'quarter A4',
      'eighth C5',
    ]);

    await press(tester, 'Pitch down');
    await press(tester, 'Pitch down');

    expect(writtenIn(scoreOf(tester), 0).take(3), [
      'quarter D4',
      'quarter F4',
      'eighth C5',
    ]);
  });

  testWidgets('Octave up and Octave down move the selected note by an octave', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapFirstNote(tester);

    await press(tester, 'Octave up');

    expect(writtenIn(scoreOf(tester), 0).first, 'quarter E5');

    await press(tester, 'Octave down');
    await press(tester, 'Octave down');

    expect(writtenIn(scoreOf(tester), 0).first, 'quarter E3');
  });

  testWidgets('Tie ties a note to the same pitch after it, and a second press '
      'unties it', (tester) async {
    await pumpApp(tester);
    await tapNoteAt(tester, beatOf(scoreOf(tester), 0, 0, bar: 1));

    await press(tester, 'Tie');

    expect(tiesIn(scoreOf(tester), 0, bar: 1), [
      true,
      false,
      false,
      false,
      false,
    ]);

    await press(tester, 'Tie');

    expect(tiesIn(scoreOf(tester), 0, bar: 1), everyElement(isFalse));
  });

  testWidgets('Tie is off on a note that another pitch follows', (
    tester,
  ) async {
    await pumpApp(tester);

    await tapFirstNote(tester);

    expect(isOn(tester, 'Tie'), isFalse);
  });

  testWidgets('Tie on several notes ties each one whose pitch the next note '
      'has', (tester) async {
    await pumpApp(tester);
    await tapNoteAt(tester, beatOf(scoreOf(tester), 0, 0, bar: 1));
    await press(tester, 'Widen right');
    await press(tester, 'Widen right');
    expect(selectedOf(tester), [
      (1, 'quarter A4'),
      (1, 'eighth A4'),
      (1, 'eighth B4'),
    ]);

    await press(tester, 'Tie');

    expect(tiesIn(scoreOf(tester), 0, bar: 1), [
      true,
      false,
      false,
      false,
      false,
    ]);

    await press(tester, 'Tie');

    expect(tiesIn(scoreOf(tester), 0, bar: 1), everyElement(isFalse));
  });

  testWidgets('Tie on one head of a chord ties that head alone', (
    tester,
  ) async {
    await pumpApp(tester);
    final first = beatOf(scoreOf(tester), 1, 0);
    expect(writtenOf(chordAt(scoreOf(tester), first)), 'half C3 E3 G3');
    await tapHeadAt(tester, first, 0);

    await press(tester, 'Tie');

    expect(
      [for (final note in chordAt(scoreOf(tester), first).notes) note.tie],
      [true, false, false],
    );
  });

  testWidgets('Slur joins the first selected event to the last, and is off '
      'with one', (tester) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    await tapFirstNote(tester);
    expect(isOn(tester, 'Slur'), isFalse);
    await press(tester, 'Widen right');
    await press(tester, 'Widen right');

    await press(tester, 'Slur');

    expect(linesOf(scoreOf(tester)), [
      (
        'slur',
        score.staves.first.id,
        beatOf(score, 0, 0).at,
        beatOf(score, 0, 2).at,
      ),
    ]);
  });

  testWidgets('Crescendo and Decrescendo put a hairpin over the selection', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    final (first, last) = (beatOf(score, 0, 0).at, beatOf(score, 0, 1).at);
    await tapFirstNote(tester);
    await press(tester, 'Widen right');

    await press(tester, 'Crescendo');
    await press(tester, 'Decrescendo');

    expect(linesOf(scoreOf(tester)), [
      ('crescendo', score.staves.first.id, first, last),
      ('decrescendo', score.staves.first.id, first, last),
    ]);
  });

  testWidgets('Unbeam takes the selected notes out of their beam, and Beam '
      'joins them in one step', (tester) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    final (c5, b4) = (eighthOf(score, 0, 4), eighthOf(score, 0, 5));
    final pair = [score.eventAt(c5)!.ref.id, score.eventAt(b4)!.ref.id];
    List<BeamMode> modes() => [
      chordAt(scoreOf(tester), c5).beam,
      chordAt(scoreOf(tester), b4).beam,
    ];
    expect(beamsOf(score, 0), [pair]);
    await tapNoteAt(tester, c5);
    expect(isOn(tester, 'Beam'), isFalse);
    await press(tester, 'Widen right');

    await press(tester, 'Unbeam');

    expect(beamsOf(scoreOf(tester), 0), isEmpty);
    expect(modes(), [BeamMode.none, BeamMode.none]);

    await press(tester, 'Beam');

    expect(beamsOf(scoreOf(tester), 0), [pair]);
    expect(modes(), [BeamMode.begin, BeamMode.join]);
    expect(
      chordAt(scoreOf(tester), beatOf(score, 0, 3)).beam,
      BeamMode.auto,
      reason: 'the quarter after the pair has no beam to keep off it',
    );

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();

    expect(modes(), [BeamMode.none, BeamMode.none]);
  });

  testWidgets('Beam joins the selected notes and no other, in one step', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    final run = [
      for (final eighth in [0, 1, 2, 3])
        score.eventAt(eighthOf(score, 0, eighth, bar: 3))!.ref.id,
    ];
    expect(beamsOf(score, 0, bar: 3), [run]);
    await tapNoteAt(tester, eighthOf(score, 0, 1, bar: 3));
    await press(tester, 'Widen right');

    await press(tester, 'Beam');

    expect(beamsOf(scoreOf(tester), 0, bar: 3), [
      [run[1], run[2]],
    ]);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();

    expect(beamsOf(scoreOf(tester), 0, bar: 3), [run]);
  });

  testWidgets('Beam leaves the note after the group unbeamed when it was', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    final fourth = eighthOf(score, 0, 3, bar: 3);
    final pair = [
      for (final eighth in [1, 2])
        score.eventAt(eighthOf(score, 0, eighth, bar: 3))!.ref.id,
    ];
    await tapNoteAt(tester, fourth);
    await press(tester, 'Unbeam');
    await tapNoteAt(tester, eighthOf(score, 0, 1, bar: 3));
    await press(tester, 'Widen right');

    await press(tester, 'Beam');

    expect(beamsOf(scoreOf(tester), 0, bar: 3), [pair]);
    expect(chordAt(scoreOf(tester), fourth).beam, BeamMode.none);
  });

  testWidgets('Beam is off unless every selected chord carries a beam and '
      'all stand in one bar', (tester) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    await tapNoteAt(tester, eighthOf(score, 0, 5));
    await press(tester, 'Widen right');
    expect(selectedOf(tester), [(0, 'eighth B4'), (0, 'quarter C5')]);
    expect(isOn(tester, 'Beam'), isFalse, reason: 'a quarter has no beam');
    await press(tester, 'Widen left');
    expect(selectedOf(tester), [
      (0, 'eighth C5'),
      (0, 'eighth B4'),
      (0, 'quarter C5'),
    ]);
    expect(isOn(tester, 'Beam'), isFalse, reason: 'a quarter among eighths');

    final lastEighth = eighthOf(score, 0, 7, bar: 4);
    await tester.tap(find.text('1/8'));
    await tester.pump();
    await bringIntoView(tester, lastEighth);
    await tapClearOf(tester, lastEighth);
    await press(tester, 'Widen right');

    expect(selectedOf(tester).map((picked) => picked.$1), [4, 5]);
    expect(
      chordAt(scoreOf(tester), eighthOf(score, 0, 0, bar: 5)).value,
      NoteValue.eighth,
    );
    expect(isOn(tester, 'Beam'), isFalse, reason: 'no beam crosses a bar line');
  });

  testWidgets('Unbeam is off on a note with no beam to lose, and Auto beam '
      'hands unbeamed notes back to the meter', (tester) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    final (c5, b4) = (eighthOf(score, 0, 4), eighthOf(score, 0, 5));
    final pair = [score.eventAt(c5)!.ref.id, score.eventAt(b4)!.ref.id];
    await tapFirstNote(tester);
    expect(isOn(tester, 'Unbeam'), isFalse, reason: 'a quarter has no beam');
    expect(isOn(tester, 'Auto beam'), isFalse);

    await tapNoteAt(tester, c5);
    await press(tester, 'Widen right');
    expect(isOn(tester, 'Auto beam'), isFalse, reason: 'the meter beams them');
    await press(tester, 'Unbeam');
    expect(beamsOf(scoreOf(tester), 0), isEmpty);

    await press(tester, 'Auto beam');

    expect(beamsOf(scoreOf(tester), 0), [pair]);
    expect(
      [chordAt(scoreOf(tester), c5).beam, chordAt(scoreOf(tester), b4).beam],
      [BeamMode.auto, BeamMode.auto],
    );
  });

  testWidgets('a second press of Slur or of a hairpin takes the line away', (
    tester,
  ) async {
    await pumpApp(tester);
    List<String> kinds() => [
      for (final line in linesOf(scoreOf(tester))) line.$1,
    ];
    await tapFirstNote(tester);
    await press(tester, 'Widen right');
    await press(tester, 'Slur');
    await press(tester, 'Crescendo');
    expect(kinds(), ['slur', 'crescendo']);

    await press(tester, 'Slur');

    expect(kinds(), ['crescendo']);

    await press(tester, 'Crescendo');

    expect(kinds(), isEmpty);
  });

  testWidgets('only a line over the very same notes is taken away', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    final (treble, bass) = (score.staves[0].id, score.staves[1].id);
    final (one, two, three) = (
      beatOf(score, 0, 0).at,
      beatOf(score, 0, 1).at,
      beatOf(score, 0, 2).at,
    );
    await tapFirstNote(tester);
    await press(tester, 'Widen right');
    await press(tester, 'Slur');
    await press(tester, 'Widen right');
    await press(tester, 'Slur');
    await press(tester, 'Narrow left');
    await press(tester, 'Slur');
    await tapNoteAt(tester, beatOf(score, 1, 0));
    await press(tester, 'Widen right');

    await press(tester, 'Slur');

    expect(linesOf(scoreOf(tester)), [
      ('slur', treble, one, two),
      ('slur', treble, one, three),
      ('slur', treble, two, three),
      ('slur', bass, one, three),
    ]);
  });

  testWidgets('Slur and Copy are off where a rest leaves them nothing to do', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapNoteAt(tester, beatOf(scoreOf(tester), 0, 1));
    expect(isOn(tester, 'Copy'), isTrue);
    await press(tester, 'Delete');

    expect(selectedOf(tester), [(0, 'quarter rest')]);
    expect(isOn(tester, 'Copy'), isFalse, reason: 'a rest alone');
    await press(tester, 'Widen right');
    expect(selectedOf(tester), [(0, 'quarter rest'), (0, 'eighth C5')]);
    expect(isOn(tester, 'Slur'), isFalse, reason: 'a slur starts on a note');

    await tapFirstNote(tester);
    await press(tester, 'Widen right');

    expect(selectedOf(tester), [(0, 'quarter E4'), (0, 'quarter rest')]);
    expect(isOn(tester, 'Copy'), isTrue);
    expect(isOn(tester, 'Slur'), isFalse, reason: 'a slur ends on a note');
  });

  testWidgets('a tap on the head of a note with one head selects the note, '
      'as a tap on its stem does', (tester) async {
    await pumpApp(tester);
    final first = beatOf(scoreOf(tester), 0, 0);
    final note = scoreOf(tester).eventAt(first)!.ref;

    await tapHeadAt(tester, first, 0);

    expect(
      sheetOf(tester).selection,
      isA<ItemSelection>().having((picked) => [...picked.items], 'items', [
        note,
      ]),
    );

    await press(tester, 'Delete');

    expect(selectedOf(tester), [(0, 'quarter rest')]);
    expect(actionButton('Delete'), findsOneWidget);
  });

  testWidgets('a selection widened from one head of a chord holds whole '
      'chords', (tester) async {
    await pumpApp(tester);
    final first = beatOf(scoreOf(tester), 1, 0);
    await tapHeadAt(tester, first, 1);
    await press(tester, 'Widen right');

    await press(tester, 'Pitch up');

    expect(writtenIn(scoreOf(tester), 1), ['half D3 F3 A3', 'half D3 F3 A3']);
  });

  testWidgets('Auto bars decides whether a note that ends the score gets a '
      'bar after it', (tester) async {
    await pumpApp(tester);
    final lastBeat = beatOf(scoreOf(tester), 1, 3, bar: 7);
    await bringIntoView(tester, lastBeat);

    await tapStaffAt(tester, lastBeat);

    expect(scoreOf(tester).measures.length, 9);
    expect(find.text('The score ends here.'), findsNothing);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    await flip(tester, 'Auto bars');
    await bringIntoView(tester, lastBeat);
    await tapStaffAt(tester, lastBeat);

    expect(scoreOf(tester).measures.length, 8);
    expect(eventHolding(scoreOf(tester), lastBeat), (
      startQuarter: Fraction(3, 1),
      written: 'quarter D3',
    ));
  });

  testWidgets('with Auto bars off, the page says when a note ends the score '
      'and offers a bar', (tester) async {
    await pumpApp(tester);
    final full = find.text('The score ends here.');
    await flip(tester, 'Auto bars');

    await tapStaffAt(tester, beatOf(scoreOf(tester), 1, 3));

    expect(
      full,
      findsNothing,
      reason: 'a note that ends an inner bar has a bar to go on to',
    );

    final lastBeat = beatOf(scoreOf(tester), 1, 3, bar: 7);
    await bringIntoView(tester, lastBeat);
    await tapStaffAt(tester, lastBeat);

    expect(full, findsOneWidget);
    expect(scoreOf(tester).measures.length, 8);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(SnackBarAction, 'Add bar'));
    await tester.pump();

    expect(scoreOf(tester).measures.length, 9);
  });

  testWidgets('a tap starts a note on a beat of the value it enters, so a '
      'whole note tapped beside another is not cut and tied', (tester) async {
    await pumpApp(tester, size: phone, demo: true);
    await openSheet(tester, 'Empty sheet');
    final score = scoreOf(tester);
    final sheet = controllerOf(tester);
    // Half a space over the staff at an eighth of a bar, which is G5 and
    // out of reach of what the bar holds.
    Future<void> tapOver(int eighth, {required int bar}) async {
      final caret = sheet.caretOf(eighthOf(score, 0, eighth, bar: bar))!;
      final spot = caret.topCenter - const Offset(0, 4);
      expect(sheet.hitTest(spot)!.target, isNull);
      await tester.tapAt(onScreen(tester, spot));
      await tester.pump();
    }

    List<List<String>> written() => [
      for (var bar = 0; bar < 4; bar++) writtenIn(scoreOf(tester), 0, bar: bar),
    ];

    await tester.tap(find.text('1'));
    await tester.pump();
    await tapStaffAt(tester, beatOf(score, 0, 0, bar: 1));
    await tapOver(5, bar: 1);

    expect(written(), [
      ['bar rest'],
      ['whole G5'],
      ['bar rest'],
      ['bar rest'],
    ]);

    await tester.tap(find.text('1/2'));
    await tester.pump();
    await tapOver(7, bar: 2);

    expect(written(), [
      ['bar rest'],
      ['whole G5'],
      ['half rest', 'half G5'],
      ['bar rest'],
    ]);
    expect([
      for (var bar = 0; bar < 4; bar++) ...tiesIn(scoreOf(tester), 0, bar: bar),
    ], everyElement(isFalse));
  });

  testWidgets('Auto bars decides whether a note longer than the rest of its '
      'bar is cut or refused', (tester) async {
    await pumpApp(tester);
    // The fourth quarter of a bar of quarters. A half note starts on a beat
    // of its own there only because a note does.
    final beat4 = beatOf(scoreOf(tester), 1, 3, bar: 2);
    final nextBar = beatOf(scoreOf(tester), 1, 0, bar: 3);
    await tester.tap(find.text('1/2'));
    await tester.pump();
    await flip(tester, 'Auto bars');
    final before = scoreOf(tester);

    await tapClearOf(tester, beat4);

    expect(scoreOf(tester), same(before));
    expect(find.text('This note does not fit in the bar.'), findsOneWidget);

    await flip(tester, 'Auto bars');
    await tapClearOf(tester, beat4);

    final cut = chordAt(scoreOf(tester), beat4);
    final tone = cut.notes.single.tone;
    expect(eventHolding(scoreOf(tester), beat4), (
      startQuarter: Fraction(3, 1),
      written: 'quarter $tone',
    ));
    expect(eventHolding(scoreOf(tester), nextBar), (
      startQuarter: Fraction.zero,
      written: 'quarter $tone',
    ));
    expect(cut.notes.single.tie, isTrue);
  });

  testWidgets('Auto beams decides whether entered eighths beam', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    final (first, second) = (eighthOf(score, 1, 2), eighthOf(score, 1, 3));
    Future<List<ChordEvent>> enterBoth() async {
      await tapClearOf(tester, first);
      await tapClearOf(tester, second);
      return [
        chordAt(scoreOf(tester), first),
        chordAt(scoreOf(tester), second),
      ];
    }

    await tester.tap(find.text('1/8'));
    await tester.pump();

    final beamed = await enterBoth();

    expect(beamed.map((chord) => '${chord.value}'), ['eighth', 'eighth']);
    expect(beamed.map((chord) => chord.beam), [BeamMode.auto, BeamMode.auto]);
    expect(beamsOf(scoreOf(tester), 1), [
      [for (final chord in beamed) chord.id],
    ]);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    await flip(tester, 'Auto beams');
    final apart = await enterBoth();

    expect(apart.map((chord) => '${chord.value}'), ['eighth', 'eighth']);
    expect(apart.map((chord) => chord.beam), [BeamMode.none, BeamMode.none]);
    expect(beamsOf(scoreOf(tester), 1), isEmpty);
  });

  testWidgets('Add bar puts an empty bar at the end', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Add bar'));
    await tester.pump();

    final score = scoreOf(tester);
    expect(score.measures.length, 9);
    expect(
      [writtenIn(score, 0, bar: 8), writtenIn(score, 1, bar: 8)],
      [
        ['bar rest'],
        ['bar rest'],
      ],
    );
  });

  testWidgets('a paste follows Auto bars where its note crosses a bar line', (
    tester,
  ) async {
    await pumpApp(tester);
    final score = scoreOf(tester);
    final beat4 = beatOf(score, 0, 3);
    await tapNoteAt(tester, beatOf(score, 0, 2, bar: 7));
    await press(tester, 'Copy');
    await tapNoteAt(tester, beat4);
    await flip(tester, 'Auto bars');

    await press(tester, 'Paste');

    expect(scoreOf(tester), same(score));
    expect(find.text('This note does not fit in the bar.'), findsOneWidget);

    await flip(tester, 'Auto bars');
    await press(tester, 'Paste');

    expect(writtenIn(scoreOf(tester), 0).last, 'quarter C5');
    expect(tiesIn(scoreOf(tester), 0).last, isTrue);
    expect(writtenIn(scoreOf(tester), 0, bar: 1).first, 'quarter C5');
  });

  testWidgets(
    'with Auto bars off, a paste that needs a new bar waits for one',
    (tester) async {
      await pumpApp(tester);
      final score = scoreOf(tester);
      await tapNoteAt(tester, beatOf(score, 0, 0, bar: 7));
      await press(tester, 'Widen right');
      await press(tester, 'Widen right');
      await press(tester, 'Copy');
      await tapNoteAt(tester, beatOf(score, 0, 2, bar: 7));
      await flip(tester, 'Auto bars');

      await press(tester, 'Paste');

      expect(scoreOf(tester), same(score));
      expect(find.text('The score is too short for this.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.widgetWithText(SnackBarAction, 'Add bar'));
      await tester.pump();
      await press(tester, 'Paste');

      expect(scoreOf(tester).measures.length, 9);
      expect(writtenIn(scoreOf(tester), 0, bar: 7), [
        'quarter E5',
        'quarter D5',
        'quarter E5',
        'quarter D5',
      ]);
      expect(writtenIn(scoreOf(tester), 0, bar: 8).first, 'half C5');
    },
  );

  testWidgets('a refusal that the model words is shown as its sentence', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapHeadAt(tester, beatOf(scoreOf(tester), 1, 0), 0);

    await press(tester, 'Pitch up');
    await press(tester, 'Pitch up');

    expect(writtenIn(scoreOf(tester), 1).first, 'half D3 E3 G3');
    expect(find.text('The chord would have E3 twice.'), findsOneWidget);
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
      await pumpApp(tester, size: size, demo: true);
      final ref = await tapFirstNote(tester);
      final rect = controllerOf(tester).rectOf(ref)!;
      // The head sits in the top space, so this is its lower half, clear of
      // the lines.
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
