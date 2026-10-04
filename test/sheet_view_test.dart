import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show ColorScheme, Theme, ThemeData;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:simple_sheet_music/src/painting.dart';
import 'package:simple_sheet_music/src/paragraph_measurer.dart';
import 'package:simple_sheet_music/src/score_player.dart';
import 'package:simple_sheet_music/src/sheet_palette.dart';
import 'package:simple_sheet_music/src/sheet_view.dart';

import '../packages/score_model/test/support.dart';
import 'sheet_picture_test.dart' show edit, inkOf, pictured, sheetWidth, violin;
import 'support/draw.dart';
import 'support/glyph_gate.dart';

const Size viewSize = Size(400, 400);
const EdgeInsets padding = EdgeInsets.all(16);
const double staffSpace = 8;

const SheetPalette inked = SheetPalette(
  ink: Color(0xFF000000),
  staffLines: Color(0xFF000000),
  outOfRange: Color(0xFFC62828),
  cursor: Color(0xFFDD2222),
  selection: Color(0x553366FF),
  playback: Color(0xFF8822CC),
  playhead: Color(0xFF22AA44),
);

int eventOf(int bar, int beat) => 10000 + bar * 4 + beat;

/// [bars] bars of quarter notes for one violin, under a title. A bar in
/// [high] is written far above the staff.
Score tune({int bars = 40, Set<int> high = const {}}) {
  var score = blankScore(
    parts: const [violin],
    bars: bars,
  ).copyWith(meta: const ScoreMeta(title: 'Tune'));
  for (var bar = 0; bar < bars; bar++) {
    score = fill(score, bar, [
      for (final (beat, pitch) in const ['G4', 'A4', 'B4', 'C5'].indexed)
        chordOf(eventOf(bar, beat), high.contains(bar) ? 'C7' : pitch),
    ]);
  }
  return score;
}

/// [score] with bar [bar] rewritten far above the staff, which makes its
/// system taller.
Score raised(Score score, int bar) => fill(score, bar, [
  for (var beat = 0; beat < 4; beat++) chordOf(20000 + bar * 4 + beat, 'C7'),
]);

NoteRef headOf(Score score, int bar, int beat) => NoteRef(
  EventRef(
    measure: score.measures[bar].id,
    staff: score.staves.first.id,
    id: EventId(eventOf(bar, beat)),
  ),
  NoteId(eventOf(bar, beat) * 10),
);

VoicePoint cursorIn(Score score, int bar) => point(score, bar, Moment.zero);

/// Where a player is [through] of the way through bar [bar] of [score].
PlaybackPosition playingIn(Score score, int bar, {double through = 0.25}) {
  final script = PlaybackCompiler().compile(score);
  final played = script.bars.firstWhere(
    (played) => played.measure == score.measures[bar].id,
  );
  final seconds = played.start + (played.end - played.start) * through;
  return PlaybackPosition(
    seconds: seconds,
    point: script.pointAt(seconds)!,
    sounding: script.sourcesAt(seconds),
  );
}

/// [view] at the top left of the test surface, so that a point of the view
/// is the same point of the surface.
Widget host(Widget view, {Size size = viewSize}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox.fromSize(size: size, child: view),
  ),
);

Finder paintedBy<T extends CustomPainter>() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is T,
);

List<T> paintersOf<T extends CustomPainter>(WidgetTester tester) => [
  for (final paint in tester.widgetList<CustomPaint>(paintedBy<T>()))
    paint.painter! as T,
];

/// The layout the view shows.
SheetLayout shown(WidgetTester tester) =>
    paintersOf<OverlayPainter>(tester).first.layout;

ScrollPosition scrollOf(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position;

/// The tile of system [index], which is as high as the system and the gap
/// under it.
Finder tileOf(int index) => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter is OverlayPainter &&
      (widget.painter! as OverlayPainter).index == index,
);

/// The top and the bottom of system [index] on screen, read from where its
/// tile is.
({double top, double bottom}) spanOf(
  WidgetTester tester,
  int index, {
  double spacePx = staffSpace,
}) {
  final top = tester.getTopLeft(tileOf(index)).dy;
  return (top: top, bottom: top + shown(tester).heightOf(index) * spacePx);
}

/// The top on screen of the system that holds [bar].
double topOf(WidgetTester tester, MeasureId bar) =>
    spanOf(tester, shown(tester).systemOf(bar)!).top;

/// The systems with a tile, which are those in view and those near it.
Iterable<int> built(WidgetTester tester) => [
  for (var index = 0; index < shown(tester).systemCount; index++)
    if (tileOf(index).evaluate().isNotEmpty) index,
];

/// The first bar of the first system that reaches below the view's top
/// edge.
MeasureId firstBarInView(WidgetTester tester) => shown(tester).firstBarOf(
  built(tester).firstWhere((index) => spanOf(tester, index).bottom > 0),
);

void expectWhollyInView(
  WidgetTester tester,
  MeasureId bar, {
  double spacePx = staffSpace,
  double? height,
}) {
  final index = shown(tester).systemOf(bar)!;
  expect(
    tileOf(index),
    findsOneWidget,
    reason: 'a system that is out of view has no tile',
  );
  final span = spanOf(tester, index, spacePx: spacePx);
  expect(span.top, greaterThanOrEqualTo(-1e-6));
  expect(span.bottom, lessThanOrEqualTo((height ?? viewSize.height) + 1e-6));
}

/// The first bar of the first system that is wholly in view.
MeasureId firstBarWhollyInView(WidgetTester tester) => shown(tester).firstBarOf(
  built(tester).firstWhere((index) {
    final span = spanOf(tester, index);
    return span.top >= 0 && span.bottom <= viewSize.height;
  }),
);

/// The picture each tile in view holds for its painter of type [T]. Painting
/// again replaces the picture's layer, so a layer that is the same object
/// was not painted again.
List<Layer> picturesOf<T extends CustomPainter>(WidgetTester tester) => [
  for (final box in tester.renderObjectList<RenderBox>(paintedBy<T>()))
    if ((box.localToGlobal(Offset.zero) & box.size).overlaps(
      Offset.zero & viewSize,
    ))
      _boundaryOf(box).debugLayer!.lastChild!,
];

RenderRepaintBoundary _boundaryOf(RenderObject object) {
  var boundary = object.parent!;
  while (boundary is! RenderRepaintBoundary) {
    boundary = boundary.parent!;
  }
  return boundary;
}

/// Where the sheet point [at] of system [index] is on screen, read from
/// where the system's tile is.
Offset onScreen(
  WidgetTester tester,
  int index,
  SpPoint at, {
  double spacePx = staffSpace,
}) =>
    tester.getTopLeft(tileOf(index)) +
    Offset(at.x * spacePx, (at.y - shown(tester).tops[index]) * spacePx);

/// The middle of [ref]'s ink on screen.
Offset middleOf(
  WidgetTester tester,
  ElementRef ref, {
  double spacePx = staffSpace,
}) {
  final layout = shown(tester);
  final box = layout.boundsOf(ref)!;
  return onScreen(
    tester,
    layout.systemOf(ref.event.measure)!,
    SpPoint((box.left + box.right) / 2, (box.top + box.bottom) / 2),
    spacePx: spacePx,
  );
}

/// [box] of system [index] on screen.
Rect rectOnScreen(WidgetTester tester, int index, Box box) => Rect.fromPoints(
  onScreen(tester, index, SpPoint(box.left, box.top)),
  onScreen(tester, index, SpPoint(box.right, box.bottom)),
);

(StaffId, VoiceSlot, ScorePoint, int, Owner?) fieldsOf(SheetHit hit) =>
    (hit.staff, hit.voice, hit.at, hit.staffStep, hit.target);

/// The labels a screen reader says, in its order, for what is in view.
List<String> spoken(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.label.isNotEmpty &&
        !node.getSemanticsData().flagsCollection.isHidden)
      node.label,
];

/// The image [controller] makes of systems [from] up to [to], as its size
/// and its pixels.
Future<({int width, int height, Uint8List rgba})> imageOf(
  WidgetTester tester,
  SheetController controller, {
  int from = 0,
  int? to,
  double pixelRatio = 1,
}) async => (await tester.runAsync(() async {
  final image = await controller.toImage(
    from: from,
    to: to,
    pixelRatio: pixelRatio,
  );
  final rgba = (await image.toByteData())!.buffer.asUint8List();
  final read = (width: image.width, height: image.height, rgba: rgba);
  image.dispose();
  return read;
}))!;

/// A playback position that says whether anything listens to it.
final class HeardPlayback extends ValueNotifier<PlaybackPosition?> {
  HeardPlayback() : super(null);

  bool get isHeard => hasListeners;
}

/// Tints that count how often they are walked.
final class WalkedTints extends MapView<ElementRef, Color> {
  WalkedTints(super.map);

  int walks = 0;

  @override
  Iterable<MapEntry<ElementRef, Color>> get entries {
    walks++;
    return super.entries;
  }

  @override
  Iterable<ElementRef> get keys {
    walks++;
    return super.keys;
  }

  @override
  void forEach(void Function(ElementRef key, Color value) action) {
    walks++;
    super.forEach(action);
  }
}

void main() {
  setUpAll(() => loadBravura(bravuraPainter()));

  testWidgets(
    'a playback position, a cursor, a selection, a tint and an edit below '
    'the view repaint the overlays over the same system pictures, and a '
    'scroll builds nothing',
    (tester) async {
      var score = tune();
      Selection selection = const NoSelection();
      var tints = const <ElementRef, Color>{};
      final playback = ValueNotifier<PlaybackPosition?>(null);
      addTearDown(playback.dispose);
      Widget view(int cursor, {SheetPalette palette = inked}) => host(
        SheetView(
          score: score,
          cursor: cursorIn(score, cursor),
          selection: selection,
          tints: tints,
          playback: playback,
          palette: palette,
        ),
      );
      await tester.pumpWidget(view(1));
      expect(shown(tester).style.barNumbers, isTrue);
      final title = picturesOf<HeaderPainter>(tester).single;
      final systems = picturesOf<SystemPainter>(tester);
      var overlays = picturesOf<OverlayPainter>(tester);
      expect(systems.length, greaterThan(1));
      expect(overlays, hasLength(systems.length));

      void expectOnlyOverlaysPainted(String after) {
        final systemsNow = picturesOf<SystemPainter>(tester);
        final overlaysNow = picturesOf<OverlayPainter>(tester);
        expect(overlaysNow, hasLength(overlays.length), reason: after);
        expect(
          picturesOf<HeaderPainter>(tester).single,
          same(title),
          reason: 'the header, $after',
        );
        for (final (tile, picture) in systemsNow.indexed) {
          expect(picture, same(systems[tile]), reason: 'system $tile, $after');
        }
        for (final (tile, picture) in overlaysNow.indexed) {
          expect(
            picture,
            isNot(same(overlays[tile])),
            reason: 'overlay $tile, $after',
          );
        }
        overlays = overlaysNow;
      }

      playback.value = playingIn(score, 1);
      await tester.pump();
      expectOnlyOverlaysPainted('after a playback position');

      await tester.pumpWidget(view(2));
      expectOnlyOverlaysPainted('after a cursor');

      selection = Selection.event(headOf(score, 1, 0).event);
      await tester.pumpWidget(view(2));
      expectOnlyOverlaysPainted('after a selection');

      tints = {headOf(score, 1, 0): const Color(0xFFFF8800)};
      await tester.pumpWidget(view(2));
      expectOnlyOverlaysPainted('after a tint');

      final layout = shown(tester);
      final labels = [
        for (final painter in paintersOf<SystemPainter>(tester)) painter.label,
      ];
      expect(labels.nonNulls, isNotEmpty);
      score = raised(score, score.measures.length - 1);
      await tester.pumpWidget(view(2));
      expect(shown(tester), isNot(same(layout)));
      for (final (tile, painter) in paintersOf<SystemPainter>(tester).indexed) {
        final label = labels[tile];
        if (label != null) {
          expect(painter.label, isNot(same(label)), reason: 'tile $tile');
          expect(painter.label, label, reason: 'tile $tile');
        }
      }
      expectOnlyOverlaysPainted('after an edit below the view');
      expect(scrollOf(tester).pixels, 0);

      final scrollView = tester.widget(find.byType(CustomScrollView));
      final header = tester.renderObject(paintedBy<HeaderPainter>());
      final rebuilt = <Widget>[];
      final painted = <RenderObject>[];
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is SheetView) {
          rebuilt.add(element.widget);
        }
      };
      debugOnProfilePaint = painted.add;
      try {
        await tester.drag(find.byType(SheetView), const Offset(0, -80));
        await tester.pump();
      } finally {
        debugOnRebuildDirtyWidget = null;
        debugOnProfilePaint = null;
      }
      expect(scrollOf(tester).pixels, inExclusiveRange(50, 104));
      expect(rebuilt, isEmpty);
      expect(tester.widget(find.byType(CustomScrollView)), same(scrollView));
      expect(painted, isNotEmpty);
      expect(painted, isNot(contains(header)));
      expect(picturesOf<SystemPainter>(tester).take(2), systems.take(2));

      scrollOf(tester).jumpTo(0);
      await tester.pump();
      final before = picturesOf<SystemPainter>(tester);
      await tester.pumpWidget(
        view(
          2,
          palette: SheetPalette(
            ink: const Color(0xFF224466),
            staffLines: inked.staffLines,
            outOfRange: inked.outOfRange,
            cursor: inked.cursor,
            selection: inked.selection,
            playback: inked.playback,
            playhead: inked.playhead,
          ),
        ),
      );
      for (final (tile, picture) in picturesOf<SystemPainter>(tester).indexed) {
        expect(
          picture,
          isNot(same(before[tile])),
          reason: 'system $tile, after a new palette',
        );
      }
      expect(
        picturesOf<HeaderPainter>(tester).single,
        isNot(same(title)),
        reason: 'the header, after a new palette',
      );
    },
  );

  testWidgets(
    'an edit above the view that makes a system taller leaves the first '
    'bar in view where it was',
    (tester) async {
      final score = tune();
      await tester.pumpWidget(host(SheetView(score: score)));
      scrollOf(tester).jumpTo(scrollOf(tester).maxScrollExtent / 2);
      await tester.pump();
      final bar = firstBarInView(tester);
      final top = topOf(tester, bar);
      final inSheet = shown(tester).tops[shown(tester).systemOf(bar)!];

      await tester.pumpWidget(host(SheetView(score: raised(score, 0))));
      final layout = shown(tester);
      expect(
        layout.tops[layout.systemOf(bar)!],
        greaterThan(inSheet + 1),
        reason: 'the system moved down the sheet',
      );
      expect(topOf(tester, bar), closeTo(top, 1e-6));
      await tester.pumpAndSettle();
      expect(topOf(tester, bar), closeTo(top, 1e-6));
    },
  );

  testWidgets('a new zoom leaves the first bar in view where it was', (
    tester,
  ) async {
    final controller = SheetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(SheetView(score: tune(), controller: controller)),
    );
    scrollOf(tester).jumpTo(scrollOf(tester).maxScrollExtent / 2);
    await tester.pump();
    final bar = firstBarInView(tester);
    final top = topOf(tester, bar);
    final width = shown(tester).width;

    controller.zoom = 1.25;
    await tester.pump();
    expect(shown(tester).width, closeTo(width / 1.25, 1e-9));
    expect(topOf(tester, bar), closeTo(top, 1e-6));
    await tester.pumpAndSettle();
    expect(topOf(tester, bar), closeTo(top, 1e-6));
  });

  testWidgets('a new zoom leaves the first bar in view where it was when the '
      "cursor's system is scrolled out of view", (tester) async {
    final score = tune();
    final controller = SheetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        SheetView(
          score: score,
          cursor: cursorIn(score, 0),
          controller: controller,
        ),
      ),
    );
    scrollOf(tester).jumpTo(scrollOf(tester).maxScrollExtent / 2);
    await tester.pump();
    expect(tileOf(0), findsNothing);
    final bar = firstBarInView(tester);
    final top = topOf(tester, bar);

    controller.zoom = 1.25;
    await tester.pump();
    expect(topOf(tester, bar), closeTo(top, 1e-6));
  });

  testWidgets(
    "a new zoom leaves the cursor's bar where it was while its system is "
    'in view',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      Widget view(VoicePoint? cursor) => host(
        SheetView(score: score, cursor: cursor, controller: controller),
      );
      await tester.pumpWidget(view(null));
      scrollOf(tester).jumpTo(scrollOf(tester).maxScrollExtent / 2);
      await tester.pump();
      final layout = shown(tester);
      final below = layout.systemOf(firstBarInView(tester))! + 1;
      final bar = layout.firstBarOf(below);
      await tester.pumpWidget(
        view(
          VoicePoint(
            staff: score.staves.first.id,
            voice: VoiceSlot.one,
            at: ScorePoint(bar, Moment.zero),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(firstBarInView(tester), isNot(bar));
      final top = topOf(tester, bar);

      controller.zoom = 1.25;
      await tester.pump();
      expect(topOf(tester, bar), closeTo(top, 1e-6));
    },
  );

  testWidgets('a new zoom leaves the first bar in view where it was, with the '
      'cursor in view, when followCursor is off', (tester) async {
    final score = tune();
    final controller = SheetController();
    addTearDown(controller.dispose);
    Widget view(VoicePoint? cursor) => host(
      SheetView(
        score: score,
        cursor: cursor,
        controller: controller,
        followCursor: false,
      ),
    );
    await tester.pumpWidget(view(null));
    scrollOf(tester).jumpTo(scrollOf(tester).maxScrollExtent / 2);
    await tester.pump();
    final layout = shown(tester);
    final bar = firstBarInView(tester);
    final below = layout.firstBarOf(layout.systemOf(bar)! + 1);
    await tester.pumpWidget(
      view(
        VoicePoint(
          staff: score.staves.first.id,
          voice: VoiceSlot.one,
          at: ScorePoint(below, Moment.zero),
        ),
      ),
    );
    expect(topOf(tester, below), lessThan(viewSize.height));
    final top = topOf(tester, bar);

    controller.zoom = 1.25;
    await tester.pump();
    expect(topOf(tester, bar), closeTo(top, 1e-6));
  });

  testWidgets(
    'a view at the top of its sheet stays there through a new zoom and a '
    'title block that grows, with a cursor in view or without one',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      Widget view(Score score, {VoicePoint? cursor}) => host(
        SheetView(score: score, cursor: cursor, controller: controller),
      );
      double titleTop() => tester.getTopLeft(paintedBy<HeaderPainter>()).dy;
      await tester.pumpWidget(view(score, cursor: cursorIn(score, 0)));
      final header = shown(tester).tops.first;

      controller.zoom = 1.5;
      await tester.pump();
      expect(shown(tester).tops.first * 1.5, greaterThan(header + 1));
      expect(scrollOf(tester).pixels, 0, reason: 'after a larger zoom');
      expect(titleTop(), padding.top);

      controller.zoom = 0.8;
      await tester.pump();
      expect(scrollOf(tester).pixels, 0, reason: 'after a smaller zoom');

      controller.zoom = 1;
      await tester.pumpWidget(view(score));
      await tester.pumpWidget(
        view(
          score.copyWith(
            meta: const ScoreMeta(
              title: 'Tune',
              subtitle: 'A subtitle',
              composer: 'Someone',
            ),
          ),
        ),
      );
      expect(shown(tester).tops.first, greaterThan(header + 1));
      expect(scrollOf(tester).pixels, 0, reason: 'after a taller title block');
      expect(titleTop(), padding.top);
    },
  );

  testWidgets(
    'a new zoom that would keep the first bar in view above the top of '
    'the sheet stops at the top',
    (tester) async {
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: tune(), controller: controller)),
      );
      scrollOf(tester).jumpTo(5);
      await tester.pump();
      final inSheet = shown(tester).tops.first * staffSpace;

      controller.zoom = 0.5;
      await tester.pump();
      expect(
        inSheet - shown(tester).tops.first * staffSpace * 0.5,
        greaterThan(5),
        reason: 'the first system moved up the sheet by more than the scroll',
      );
      expect(scrollOf(tester).pixels, 0);
    },
  );

  testWidgets(
    'ensureVisible ends with its system in view when an edit moves the '
    'system on the way',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, controller: controller)),
      );
      final target = score.measures[20].id;
      var done = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(target, Moment.zero))
            .then((_) => done = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(done, isFalse);
      expect(tileOf(0), findsNothing);

      await tester.pumpWidget(
        host(SheetView(score: raised(score, 0), controller: controller)),
      );
      expect(done, isFalse);
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expectWhollyInView(tester, target);
    },
  );

  testWidgets(
    'ensureVisible goes the shortest way to show a whole system, at once '
    'for no duration, and shows the top of a system taller than the view',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      Widget view({Size size = viewSize}) => host(
        SheetView(score: score, controller: controller),
        size: size,
      );
      ScorePoint startOf(int bar) =>
          ScorePoint(score.measures[bar].id, Moment.zero);
      ({double top, double bottom}) systemOf(int bar) =>
          spanOf(tester, shown(tester).systemOf(score.measures[bar].id)!);
      await tester.pumpWidget(view());

      unawaited(controller.ensureVisible(startOf(30)));
      await tester.pumpAndSettle();
      expect(systemOf(30).bottom, closeTo(viewSize.height, 1e-6));

      final offset = scrollOf(tester).pixels;
      final layout = shown(tester);
      final above = layout.firstBarOf(
        layout.systemOf(score.measures[30].id)! - 1,
      );
      expect(topOf(tester, above), greaterThan(0));
      var done = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(above, Moment.zero))
            .then((_) => done = true),
      );
      await tester.pump();
      expect(done, isTrue, reason: 'a system in view is scrolled to already');
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, offset);

      unawaited(controller.ensureVisible(startOf(10), duration: Duration.zero));
      await tester.pump();
      expect(systemOf(10).top, closeTo(0, 1e-6));

      await tester.pumpWidget(view(size: const Size(400, 60)));
      unawaited(controller.ensureVisible(startOf(30)));
      await tester.pumpAndSettle();
      expect(systemOf(30).top, closeTo(0, 1e-6));
    },
  );

  testWidgets(
    'a drag takes over from ensureVisible, and an edit after it leaves '
    'the scroll alone',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, controller: controller)),
      );
      var done = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(score.measures[30].id, Moment.zero))
            .then((_) => done = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(done, isFalse);

      await tester.drag(find.byType(SheetView), const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(done, isTrue);
      final offset = scrollOf(tester).pixels;

      await tester.pumpWidget(
        host(SheetView(score: raised(score, 39), controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, offset);
    },
  );

  testWidgets(
    'ensureVisible for a system in view, called while the view scrolls '
    'to another, stops the scroll where it is',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, controller: controller)),
      );
      var first = false;
      var second = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(score.measures[38].id, Moment.zero))
            .then((_) => first = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(first, isFalse);
      final offset = scrollOf(tester).pixels;
      expect(offset, greaterThan(0));

      final inView = firstBarWhollyInView(tester);
      unawaited(
        controller
            .ensureVisible(ScorePoint(inView, Moment.zero))
            .then((_) => second = true),
      );
      await tester.pump();
      expect(first, isTrue);
      expect(second, isTrue);
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, offset);
    },
  );

  testWidgets(
    'ensureVisible for a system in view leaves alone a fling that took '
    'over from a scroll of the view',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, controller: controller)),
      );
      unawaited(
        controller.ensureVisible(
          ScorePoint(score.measures[38].id, Moment.zero),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.fling(find.byType(SheetView), const Offset(0, -200), 1500);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final offset = scrollOf(tester).pixels;

      var done = false;
      unawaited(
        controller
            .ensureVisible(
              ScorePoint(firstBarWhollyInView(tester), Moment.zero),
            )
            .then((_) => done = true),
      );
      await tester.pump();
      expect(done, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      expect(scrollOf(tester).pixels, greaterThan(offset + 1));
    },
  );

  testWidgets('a view that goes away while it scrolls ends the scroll', (
    tester,
  ) async {
    final score = tune();
    final controller = SheetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(SheetView(score: score, controller: controller)),
    );
    var done = false;
    unawaited(
      controller
          .ensureVisible(ScorePoint(score.measures[38].id, Moment.zero))
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(done, isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(done, isTrue);
  });

  testWidgets(
    'ensureVisible for a bar of a score the view is given in the same '
    'frame scrolls to it, and for a bar of no score ends after a frame',
    (tester) async {
      final score = tune();
      final longer = tune(bars: 44);
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, controller: controller)),
      );
      final added = longer.measures[43].id;
      expect(shown(tester).systemOf(added), isNull);
      var done = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(added, Moment.zero))
            .then((_) => done = true),
      );
      await tester.pumpWidget(
        host(SheetView(score: longer, controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(built(tester), contains(shown(tester).systemOf(added)));
      expectWhollyInView(tester, added);

      final offset = scrollOf(tester).pixels;
      final missing = tune(bars: 50).measures[49].id;
      expect(shown(tester).systemOf(missing), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
      done = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(missing, Moment.zero))
            .then((_) => done = true),
      );
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'the request waits for a frame, so it asks for one',
      );
      await tester.pump();
      expect(done, isTrue);
      expect(scrollOf(tester).pixels, offset);
    },
  );

  testWidgets(
    'ensureVisible for a bar in view asks for no frame, and after a zoom '
    'that cuts its system at the next frame it scrolls to it at the new zoom',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, controller: controller)),
      );
      final layout = shown(tester);
      final bar = layout.firstBarOf(3);
      scrollOf(tester).jumpTo(
        padding.top +
            (layout.tops[3] + layout.heightOf(3)) * staffSpace -
            viewSize.height,
      );
      await tester.pumpAndSettle();
      expectWhollyInView(tester, bar);
      expect(tester.binding.hasScheduledFrame, isFalse);
      var done = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(bar, Moment.zero))
            .then((_) => done = true),
      );
      await tester.idle();
      expect(done, isTrue, reason: 'nothing can change the answer');
      expect(tester.binding.hasScheduledFrame, isFalse);

      controller.zoom = 1.5;
      done = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(bar, Moment.zero))
            .then((_) => done = true),
      );
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expectWhollyInView(tester, bar, spacePx: staffSpace * 1.5);
    },
  );

  testWidgets(
    'ensureVisible after a zoom set inside a frame, in the continuation of '
    'an awaited ensureVisible, scrolls to its system at the new zoom',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, controller: controller)),
      );
      final bar = shown(tester).firstBarOf(3);
      final at = ScorePoint(bar, Moment.zero);
      SchedulerPhase? phase;
      var done = false;
      unawaited(() async {
        await controller.ensureVisible(at);
        phase = tester.binding.schedulerPhase;
        controller.zoom = 1.5;
        await controller.ensureVisible(at);
        done = true;
      }());
      await tester.pumpAndSettle();
      expect(
        phase,
        SchedulerPhase.midFrameMicrotasks,
        reason: 'the first scroll ends inside a frame',
      );
      expect(done, isTrue);
      expectWhollyInView(tester, bar, spacePx: staffSpace * 1.5);
    },
  );

  testWidgets(
    'ensureVisible with no duration, after a zoom the next frame lays out '
    'at, ends with its system in view at the new zoom',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, controller: controller)),
      );
      final bar = score.measures[20].id;
      controller.zoom = 1.5;
      var done = false;
      unawaited(
        controller
            .ensureVisible(
              ScorePoint(bar, Moment.zero),
              duration: Duration.zero,
            )
            .then((_) => done = true),
      );
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expectWhollyInView(tester, bar, spacePx: staffSpace * 1.5);
    },
  );

  testWidgets(
    'ensureVisible in the handler that makes the view shorter ends with '
    'its system in the shorter view, from in view and from out of it',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      const shorter = 250.0;
      var height = viewSize.height;
      late StateSetter setState;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, set) {
            setState = set;
            return host(
              SheetView(score: score, controller: controller),
              size: Size(viewSize.width, height),
            );
          },
        ),
      );
      Future<void> shortenAndShow(MeasureId bar) async {
        var done = false;
        setState(() => height = shorter);
        unawaited(
          controller
              .ensureVisible(ScorePoint(bar, Moment.zero))
              .then((_) => done = true),
        );
        await tester.pumpAndSettle();
        expect(done, isTrue);
        expectWhollyInView(tester, bar, height: shorter);
      }

      final cut = built(tester).lastWhere(
        (index) => spanOf(tester, index).bottom <= viewSize.height,
      );
      expect(spanOf(tester, cut).bottom, greaterThan(shorter));
      await shortenAndShow(shown(tester).firstBarOf(cut));

      setState(() => height = viewSize.height);
      await tester.pumpAndSettle();
      final below = score.measures[30].id;
      expect(tileOf(shown(tester).systemOf(below)!), findsNothing);
      await shortenAndShow(below);
    },
  );

  testWidgets(
    'ensureVisible for a system in view leaves alone a fling that carries '
    'the system out of view before the next frame',
    (tester) async {
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: tune(bars: 200), controller: controller)),
      );
      await tester.fling(find.byType(SheetView), const Offset(0, -300), 8000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final offset = scrollOf(tester).pixels;
      var done = false;
      unawaited(
        controller
            .ensureVisible(
              ScorePoint(firstBarWhollyInView(tester), Moment.zero),
            )
            .then((_) => done = true),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(done, isTrue);
      await tester.pumpAndSettle();
      expect(
        scrollOf(tester).pixels,
        greaterThan(offset + 5 * viewSize.height),
        reason: 'the fling ran on',
      );
    },
  );

  testWidgets(
    'ensureVisible for a system in view leaves alone a drag that goes on '
    'before the next frame',
    (tester) async {
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: tune(bars: 200), controller: controller)),
      );
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
      // One pixel of finger asks for a frame and cuts no system that was
      // two pixels inside the view.
      final inView = shown(tester).firstBarOf(
        built(tester).firstWhere((index) {
          final span = spanOf(tester, index);
          return span.top >= 2 && span.bottom <= viewSize.height;
        }),
      );
      await gesture.moveBy(const Offset(0, -1));
      expect(tester.binding.hasScheduledFrame, isTrue);
      final offset = scrollOf(tester).pixels;
      var done = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(inView, Moment.zero))
            .then((_) => done = true),
      );
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      expect(done, isTrue);
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        scrollOf(tester).pixels,
        closeTo(offset + 160, 1e-6),
        reason: 'the view still follows the finger',
      );
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a scroll of the view goes on while a padding changes under it on '
    'every frame',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      Widget view(double bottom) => host(
        SheetView(
          score: score,
          controller: controller,
          padding: padding.copyWith(bottom: bottom),
        ),
      );
      await tester.pumpWidget(view(padding.bottom));
      final bar = score.measures[30].id;
      var done = false;
      unawaited(
        controller
            .ensureVisible(ScorePoint(bar, Moment.zero))
            .then((_) => done = true),
      );
      await tester.pump();
      // An inset that grows for 320 ms, which is longer than the scroll
      // takes.
      for (var frame = 1; frame <= 20; frame++) {
        await tester.pumpWidget(
          view(padding.bottom + frame * 10),
          duration: const Duration(milliseconds: 16),
        );
      }
      expect(done, isTrue);
      expectWhollyInView(tester, bar);
    },
  );

  testWidgets("the scroll extent is the sheet's height on the first frame", (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SheetView(
          score: tune(high: {for (var bar = 20; bar < 40; bar++) bar}),
        ),
      ),
    );
    final position = scrollOf(tester);
    expect(
      position.maxScrollExtent + position.viewportDimension,
      closeTo(shown(tester).height * staffSpace + padding.vertical, 1e-6),
    );
  });

  testWidgets(
    'a cursor that moves to a system out of view scrolls it into view, '
    'unless followCursor is off',
    (tester) async {
      final score = tune();
      Widget view(int bar, {bool follow = true}) => host(
        SheetView(
          score: score,
          cursor: cursorIn(score, bar),
          followCursor: follow,
        ),
      );
      await tester.pumpWidget(view(0));
      await tester.pumpWidget(view(30));
      await tester.pumpAndSettle();
      expectWhollyInView(tester, score.measures[30].id);

      final offset = scrollOf(tester).pixels;
      expect(offset, greaterThan(0));
      await tester.pumpWidget(view(0, follow: false));
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, offset);
    },
  );

  testWidgets(
    "a view that opens with its cursor far down the sheet shows the cursor's "
    'system on its first frame, unless followCursor is off',
    (tester) async {
      final score = tune();
      Widget view(int bar, {bool follow = true}) => host(
        SheetView(
          score: score,
          cursor: cursorIn(score, bar),
          followCursor: follow,
        ),
      );
      await tester.pumpWidget(view(20));
      final system = shown(tester).systemOf(score.measures[20].id)!;
      expect(built(tester), contains(system));
      expect(scrollOf(tester).pixels, greaterThan(0));
      expect(spanOf(tester, system).bottom, closeTo(viewSize.height, 1e-6));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view(0));
      expect(scrollOf(tester).pixels, 0);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view(20, follow: false));
      expect(scrollOf(tester).pixels, 0);
    },
  );

  testWidgets(
    'a view that opens with its cursor in a system taller than the view '
    "shows the system's top",
    (tester) async {
      final score = tune();
      await tester.pumpWidget(host(SheetView(score: score)));
      final system = shown(tester).systemOf(score.measures[20].id)!;
      final size = Size(
        viewSize.width,
        shown(tester).heightOf(system) * staffSpace / 2,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        host(
          SheetView(score: score, cursor: cursorIn(score, 20)),
          size: size,
        ),
      );
      expect(tileOf(system), findsOneWidget);
      expect(tester.getTopLeft(tileOf(system)).dy, closeTo(0, 1e-6));
    },
  );

  testWidgets('a cursor that moves to the next system and back, while the view '
      'scrolls after it, leaves its system wholly in view', (tester) async {
    final score = tune();
    await tester.pumpWidget(host(SheetView(score: score)));
    final layout = shown(tester);
    final tile = (layout.tops[6] - layout.tops[5]) * staffSpace;
    final size = Size(viewSize.width, tile * 1.5);
    Widget view(int system) => host(
      SheetView(
        score: score,
        cursor: cursorIn(score, score.indexOf(layout.firstBarOf(system))),
      ),
      size: size,
    );
    await tester.pumpWidget(view(5));
    await tester.pumpAndSettle();
    scrollOf(tester).jumpTo(
      padding.top + layout.tops[5] * staffSpace - tile * 0.2,
    );
    await tester.pump();
    final start = scrollOf(tester).pixels;
    expect(spanOf(tester, 5).top, closeTo(tile * 0.2, 1e-6));
    expect(spanOf(tester, 5).bottom, lessThan(size.height));
    expect(spanOf(tester, 6).bottom, greaterThan(size.height));

    await tester.pumpWidget(view(6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(scrollOf(tester).pixels, greaterThan(start));
    await tester.pumpWidget(view(5));
    await tester.pumpAndSettle();
    expect(spanOf(tester, 5).top, greaterThanOrEqualTo(0));
    expect(spanOf(tester, 5).bottom, lessThanOrEqualTo(size.height));
  });

  testWidgets(
    'playback brings a system to the top of the view once, when it enters '
    'one that is out of view, unless followPlayback is off',
    (tester) async {
      final score = tune();
      final playback = ValueNotifier<PlaybackPosition?>(null);
      addTearDown(playback.dispose);
      Widget view({bool follow = true}) => host(
        SheetView(score: score, playback: playback, followPlayback: follow),
      );
      await tester.pumpWidget(view());
      playback.value = playingIn(score, 20);
      await tester.pumpAndSettle();
      expect(topOf(tester, score.measures[20].id), closeTo(0, 1e-6));

      scrollOf(tester).jumpTo(0);
      await tester.pump();
      playback.value = playingIn(score, 20, through: 0.75);
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, 0);

      await tester.pumpWidget(view(follow: false));
      playback.value = playingIn(score, 35);
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, 0);
    },
  );

  testWidgets(
    'playback still brings its system to the top of the view when an edit '
    'moves the system on the way',
    (tester) async {
      final score = tune();
      final playback = ValueNotifier<PlaybackPosition?>(null);
      addTearDown(playback.dispose);
      Widget view(Score score) =>
          host(SheetView(score: score, playback: playback));
      await tester.pumpWidget(view(score));
      final bar = shown(tester).firstBarOf(
        built(tester).firstWhere(
          (index) => spanOf(tester, index).bottom > viewSize.height,
        ),
      );
      playback.value = playingIn(score, score.indexOf(bar));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      expect(topOf(tester, bar), greaterThan(1));
      expectWhollyInView(tester, bar);

      await tester.pumpWidget(view(raised(score, 0)));
      await tester.pumpAndSettle();
      expect(topOf(tester, bar), closeTo(0, 1e-6));
    },
  );

  testWidgets(
    'playback leaves a user who scrolled away where they are when a new '
    "zoom breaks the playhead's system again, and follows into the next "
    'system',
    (tester) async {
      final score = tune(bars: 80);
      final controller = SheetController();
      addTearDown(controller.dispose);
      final playback = ValueNotifier<PlaybackPosition?>(null);
      addTearDown(playback.dispose);
      await tester.pumpWidget(
        host(
          SheetView(score: score, playback: playback, controller: controller),
          size: const Size(800, 400),
        ),
      );
      final bar = score.measures[41].id;
      MeasureId firstOfItsSystem() =>
          shown(tester).firstBarOf(shown(tester).systemOf(bar)!);
      playback.value = playingIn(score, 41, through: 0.1);
      await tester.pumpAndSettle();
      expect(topOf(tester, bar), closeTo(0, 1e-6));
      final first = firstOfItsSystem();

      scrollOf(tester).jumpTo(100);
      await tester.pump();
      controller.zoom = 1.25;
      await tester.pump();
      expect(firstOfItsSystem(), isNot(first));
      final offset = scrollOf(tester).pixels;
      playback.value = playingIn(score, 41, through: 0.2);
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, offset);

      final layout = shown(tester);
      final next = layout.firstBarOf(layout.systemOf(bar)! + 1);
      playback.value = playingIn(score, score.indexOf(next));
      await tester.pumpAndSettle();
      expect(topOf(tester, next), closeTo(0, 1e-6));
    },
  );

  testWidgets(
    'a view follows the playback it was last given, and listens to no '
    'other',
    (tester) async {
      final score = tune();
      final first = HeardPlayback();
      final second = HeardPlayback();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(host(SheetView(score: score, playback: first)));
      expect(first.isHeard, isTrue);
      await tester.pumpWidget(host(SheetView(score: score, playback: second)));
      expect(first.isHeard, isFalse);

      first.value = playingIn(score, 20);
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, 0);

      second.value = playingIn(score, 20);
      await tester.pumpAndSettle();
      expect(topOf(tester, score.measures[20].id), closeTo(0, 1e-6));

      await tester.pumpWidget(const SizedBox());
      expect(second.isHeard, isFalse);
    },
  );

  testWidgets(
    'a playback tick repaints the overlays and does not walk the tints '
    'again',
    (tester) async {
      final score = tune();
      final tints = WalkedTints({
        for (var bar = 0; bar < score.measures.length; bar++)
          headOf(score, bar, 0): const Color(0xFFFF8800),
      });
      final playback = ValueNotifier<PlaybackPosition?>(null);
      addTearDown(playback.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, tints: tints, playback: playback)),
      );
      final walks = tints.walks;
      expect(walks, greaterThan(0), reason: 'the first paint reads the tints');

      var overlays = picturesOf<OverlayPainter>(tester);
      expect(overlays.length, greaterThan(1));
      for (final through in [0.1, 0.3, 0.5, 0.7]) {
        playback.value = playingIn(score, 1, through: through);
        await tester.pump();
        final painted = picturesOf<OverlayPainter>(tester);
        for (final (tile, picture) in painted.indexed) {
          expect(picture, isNot(same(overlays[tile])), reason: 'overlay $tile');
        }
        overlays = painted;
      }
      expect(tints.walks, walks);
    },
  );

  testWidgets('a new style lays the whole sheet out again', (tester) async {
    final score = tune();
    Iterable<TextDraw> labels() =>
        paintersOf<SystemPainter>(tester)
            .map((painter) => painter.label)
            .nonNulls;
    await tester.pumpWidget(host(SheetView(score: score)));
    expect(labels(), isNotEmpty);

    await tester.pumpWidget(
      host(
        SheetView(
          score: score,
          style: const EngravingStyle(barNumbers: false),
        ),
      ),
    );
    expect(labels(), isEmpty);
  });

  testWidgets(
    'a text font that loads after the first layout replaces the layout '
    'once',
    (tester) async {
      final score = tune();
      final style = EngravingStyle(
        text: {
          TextRole.title: TextSpec(
            size: TextRole.title.standard.size,
            family: 'LateText',
          ),
        },
      );
      Widget view() => host(SheetView(score: score, style: style));
      double titleWidth() =>
          shown(tester).header.whereType<TextDraw>().first.bounds.width;
      await tester.pumpWidget(view());
      final first = shown(tester);
      final boxes = titleWidth();

      await tester.runAsync(() => loadFontFile(bravuraFile, 'LateText'));
      await tester.pump();
      await tester.pump();
      final second = shown(tester);
      expect(second, isNot(same(first)));
      expect(titleWidth(), lessThan(boxes));

      await tester.pumpWidget(view());
      expect(shown(tester), same(second));
    },
  );

  testWidgets(
    'a font the text does not use that loads late leaves the layout as '
    'it is',
    (tester) async {
      await tester.pumpWidget(host(SheetView(score: tune())));
      final first = shown(tester);
      final glyphs = paintersOf<SystemPainter>(tester).first.glyphs;

      await tester.runAsync(() => loadFontFile(bravuraFile, 'UnusedText'));
      await tester.pump();
      await tester.pump();
      expect(
        paintersOf<SystemPainter>(tester).first.glyphs,
        isNot(same(glyphs)),
        reason: 'the view heard of the font',
      );
      expect(shown(tester), same(first));
    },
  );

  testWidgets(
    'toImage of a range of systems is as high as they are planned, times '
    'the pixel ratio, and holds their ink',
    (tester) async {
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: tune(), controller: controller, palette: inked)),
      );
      final layout = shown(tester);
      const pixelRatio = 2.0;
      const px = staffSpace * pixelRatio;
      final planned = layout.tops[2] + layout.heightOf(2) - layout.tops[1];

      final (:width, :height, :rgba) = await imageOf(
        tester,
        controller,
        from: 1,
        to: 3,
        pixelRatio: pixelRatio,
      );
      expect(height, (planned * px).ceil());
      expect(width, (layout.width * px).ceil());
      final ink = inkIn(
        rgba,
        width,
        left: 0,
        top: 0,
        right: width,
        bottom: height,
      )!;
      expect(ink.top, lessThan(layout.heightOf(1) * px));
      expect(ink.bottom, greaterThan((layout.tops[2] - layout.tops[1]) * px));
      expect(ink.left, lessThan(px));
      expect(ink.right, greaterThan(width - px));

      final withHeader = await imageOf(tester, controller, to: 1);
      expect(
        withHeader.height,
        ((layout.tops[0] + layout.heightOf(0)) * staffSpace).ceil(),
      );
    },
  );

  testWidgets(
    'toImage refuses a range higher than one image holds, an empty range '
    'and a range outside the sheet',
    (tester) async {
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: tune(), controller: controller)),
      );
      final layout = shown(tester);
      expect(controller.systemCount, layout.systemCount);
      expect(
        layout.height * staffSpace * 8,
        greaterThan(SheetController.maxImageSide),
      );
      expect(() => controller.toImage(pixelRatio: 8), throwsArgumentError);
      expect(() => controller.toImage(from: 2, to: 2), throwsArgumentError);
      expect(() => controller.toImage(pixelRatio: 0), throwsArgumentError);
      expect(
        () => controller.toImage(to: layout.systemCount + 1),
        throwsRangeError,
      );
    },
  );

  testWidgets('toImage refuses a sheet wider than one image holds, and says to '
      'lower the pixel ratio', (tester) async {
    final controller = SheetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(SheetView(score: tune(), controller: controller)),
    );
    final layout = shown(tester);
    const pixelRatio = 60.0;
    expect(
      layout.heightOf(1) * staffSpace * pixelRatio,
      lessThan(SheetController.maxImageSide),
    );
    expect(
      layout.width * staffSpace * pixelRatio,
      greaterThan(SheetController.maxImageSide),
    );
    expect(
      () => controller.toImage(from: 1, to: 2, pixelRatio: pixelRatio),
      throwsA(
        isA<ArgumentError>().having(
          (error) => '${error.message}',
          'message',
          contains('pixel ratio'),
        ),
      ),
    );
  });

  testWidgets(
    'toImage straight after a new zoom makes the image of the sheet on '
    'screen',
    (tester) async {
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: tune(), controller: controller, palette: inked)),
      );
      final onScreen = await imageOf(tester, controller, from: 1, to: 3);

      controller.zoom = 2;
      final image = await imageOf(tester, controller, from: 1, to: 3);
      expect(
        (image.width, image.height),
        (onScreen.width, onScreen.height),
      );
      expect(image.rgba, onScreen.rgba);
    },
  );

  testWidgets(
    'toImage of the whole sheet, and of the systems after the first, is '
    'the picture their drawables make on one canvas',
    (tester) async {
      await tester.runAsync(loadTextFont);
      final ensemble = pictured();
      final first = ensemble.parts.first;
      // The first part's notes above E5 are out of its range here, so the
      // sheet has ink of every role.
      final score = ensemble.copyWith(
        parts: ensemble.parts.replaceAt(
          0,
          Part(
            id: first.id,
            name: first.name,
            shortName: first.shortName,
            instrument: const Instrument(
              key: 'violin',
              program: 40,
              highest: Pitch(Step.e, 5),
            ),
            staves: first.staves,
          ),
        ),
      );
      final plan = SheetLayout(
        score,
        width: sheetWidth,
        text: ParagraphMeasurer(),
        style: pictureStyle,
      );
      expect(plan.systemCount, greaterThanOrEqualTo(3));
      expect(plan.header, isNotEmpty);
      expect(plan.labelOf(1), isNotNull);
      expect(
        {
          for (var index = 0; index < plan.systemCount; index++)
            for (final drawable in inkOf(plan, index)) drawable.ink,
        },
        InkRole.values.toSet(),
        reason: 'ink of every role',
      );
      final size = Size(sheetWidth * staffSpace + padding.horizontal, 400);
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const ink = Color(0xFF224466);
      const staffLines = Color(0xFF8899AA);
      const outOfRange = Color(0xFFC62828);
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          SheetView(
            score: score,
            controller: controller,
            style: pictureStyle,
            palette: SheetPalette(
              ink: ink,
              staffLines: staffLines,
              outOfRange: outOfRange,
              cursor: inked.cursor,
              selection: inked.selection,
              playback: inked.playback,
              playhead: inked.playhead,
            ),
          ),
          size: size,
        ),
      );
      expect(controller.systemCount, plan.systemCount);

      final glyphs = bravuraPainter();
      const scale = SheetScale(spacePx: staffSpace);
      void paint(Canvas canvas, Iterable<Drawable> drawables) {
        for (final drawable in drawables) {
          paintDrawable(
            canvas,
            drawable,
            glyphs,
            scale,
            switch (drawable.ink) {
              InkRole.normal => ink,
              InkRole.staffLine => staffLines,
              InkRole.outOfRange => outOfRange,
            },
          );
        }
      }

      for (final (from, pixelRatio) in [(0, 1.0), (1, 2.0)]) {
        final top = from == 0 ? 0.0 : plan.tops[from];
        final width = (sheetWidth * staffSpace * pixelRatio).ceil();
        final height = ((plan.height - top) * staffSpace * pixelRatio).ceil();
        final image = await imageOf(
          tester,
          controller,
          from: from,
          pixelRatio: pixelRatio,
        );
        expect(
          (image.width, image.height),
          (width, height),
          reason: 'from system $from',
        );
        final canvas = (await tester.runAsync(
          () => render(
            width,
            height,
            (canvas) {
              canvas.scale(pixelRatio);
              if (from == 0) {
                paint(canvas, plan.header);
              }
              for (var index = from; index < plan.systemCount; index++) {
                canvas
                  ..save()
                  ..translate(0, (plan.tops[index] - top) * staffSpace);
                paint(canvas, inkOf(plan, index));
                canvas.restore();
              }
            },
            background: null,
          ),
        ))!;
        var differing = 0;
        for (var at = 0; at < image.rgba.length; at++) {
          if ((image.rgba[at] - canvas.rgba[at]).abs() > 32) {
            differing++;
          }
        }
        expect(
          differing,
          0,
          reason: 'colour channels that differ, from system $from',
        );
      }
    },
  );

  testWidgets(
    'each system in view is one node for a screen reader, labelled with '
    'the bars it holds',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var score = tune(bars: 12);
      for (final bar in [3, 6, 7, 10]) {
        score = edit(
          score,
          SetBreak(score.measures[bar].id, LayoutBreak.system),
        );
      }
      const size = Size(800, 300);
      const labels = [
        'Bars 1 to 3',
        'Bars 4 to 6',
        'Bar 7',
        'Bars 8 to 10',
        'Bars 11 to 12',
      ];
      await tester.pumpWidget(host(SheetView(score: score), size: size));
      expect(shown(tester).systemCount, labels.length);

      List<String> inView() => [
        for (final index in built(tester))
          if (tester.getRect(tileOf(index)).overlaps(Offset.zero & size))
            labels[index],
      ];
      final said = <String>{};
      final position = scrollOf(tester);
      for (final offset in [0.0, 0.5, 1.0]) {
        position.jumpTo(position.maxScrollExtent * offset);
        await tester.pump();
        expect(inView().length, lessThan(labels.length));
        expect(spoken(tester), inView(), reason: 'scrolled to $offset');
        said.addAll(spoken(tester));
      }
      expect(said, labels.toSet());

      await tester.pumpWidget(
        host(SheetView(score: tune(bars: 2)), size: size),
      );
      final alone = tester.semantics.simulatedAccessibilityTraversal().where(
        (node) => node.label == 'Bars 1 to 2',
      );
      expect(alone, hasLength(1));
      expect(
        alone.single.getSemanticsData().flagsCollection.hasImplicitScrolling,
        isFalse,
        reason: 'a lone system is a node of its own, not the scrolling one',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a tap reports the hit the layout gives for the same point of the '
    'sheet, at two zooms and after a scroll',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      final hits = <SheetHit>[];
      await tester.pumpWidget(
        host(
          SheetView(
            score: score,
            cursor: point(score, 0, Moment.zero, voice: VoiceSlot.two),
            controller: controller,
            onTap: hits.add,
            tapGrid: DurationBase.eighth,
            followCursor: false,
          ),
          size: const Size(800, 400),
        ),
      );

      SpPoint inSheet(Offset at) {
        final spacePx = staffSpace * controller.zoom;
        return SpPoint(
          (at.dx - padding.left) / spacePx,
          (at.dy - padding.top + scrollOf(tester).pixels) / spacePx,
        );
      }

      Future<SheetHit> tap(Offset at) async {
        hits.clear();
        await tester.tapAt(at);
        final expected = shown(tester).hitTest(
          inSheet(at),
          voice: VoiceSlot.two,
          grid: DurationBase.eighth,
          reach: kTouchSlop / (staffSpace * controller.zoom),
        );
        expect(hits.map(fieldsOf), [fieldsOf(expected!)], reason: 'at $at');
        return hits.single;
      }

      final head = headOf(score, 0, 0);
      Future<Owner?> targetLeftOf(double px, {double spacePx = staffSpace}) =>
          tap(middleOf(tester, head, spacePx: spacePx) - Offset(px, 0))
              .then((hit) => hit.target);
      expect(await targetLeftOf(0), ElementOwner(head));
      expect(await targetLeftOf(20), ElementOwner(head));
      expect(await targetLeftOf(30), isNull);

      final between = Offset(
        ui.lerpDouble(
          controller.rectOf(head)!.left,
          controller.rectOf(headOf(score, 0, 1))!.left,
          0.7,
        )!,
        middleOf(tester, head).dy + 30,
      );
      final snapped = await tap(between);
      expect(snapped.target, isNull);
      expect(
        snapped.at,
        isNot(shown(tester).hitTest(inSheet(between))!.at),
        reason: "the tap snaps to the view's grid, not the layout's own",
      );

      hits.clear();
      await tester.tapAt(const Offset(200, 20));
      expect(hits, isEmpty, reason: 'a tap on the title is on no system');

      controller.zoom = 2;
      await tester.pump();
      expect(await targetLeftOf(0, spacePx: 16), ElementOwner(head));
      expect(await targetLeftOf(24, spacePx: 16), ElementOwner(head));
      expect(
        await targetLeftOf(30, spacePx: 16),
        isNull,
        reason: 'a finger reaches as far on screen at every zoom',
      );

      controller.zoom = 1;
      await tester.pump();
      await tester.drag(find.byType(SheetView), const Offset(0, -150));
      await tester.pump();
      expect(scrollOf(tester).pixels, greaterThan(100));
      final lower =
          [
            for (var bar = 0; bar < score.measures.length; bar++)
              headOf(score, bar, 2),
          ].firstWhere((head) {
            final system = shown(tester).systemOf(head.event.measure)!;
            return built(tester).contains(system) &&
                spanOf(tester, system).top > 0 &&
                spanOf(tester, system).bottom < viewSize.height;
          });
      expect((await tap(middleOf(tester, lower))).target, ElementOwner(lower));
    },
  );

  testWidgets(
    'a tap is a tap on the sheet of the view tapped, when another view '
    'took the controller after it',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      const upper = ValueKey('upper');
      const lower = ValueKey('lower');
      final hits = {upper: <SheetHit>[], lower: <SheetHit>[]};
      const size = Size(400, 300);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final MapEntry(:key, value: taps) in hits.entries)
                SizedBox.fromSize(
                  size: size,
                  child: SheetView(
                    key: key,
                    score: score,
                    controller: controller,
                    onTap: taps.add,
                  ),
                ),
            ],
          ),
        ),
      );
      Finder inUpper(Finder finder) =>
          find.descendant(of: find.byKey(upper), matching: finder);
      tester
          .state<ScrollableState>(inUpper(find.byType(Scrollable)))
          .position
          .jumpTo(300);
      await tester.pump();

      final OverlayPainter(:layout, :index) = tester
          .widgetList<CustomPaint>(inUpper(paintedBy<OverlayPainter>()))
          .map((paint) => paint.painter! as OverlayPainter)
          .firstWhere((painter) {
            final tile = tester.getRect(inUpper(tileOf(painter.index)));
            return tile.top >= 0 && tile.bottom <= size.height;
          });
      final head = headOf(score, score.indexOf(layout.firstBarOf(index)), 1);
      final box = layout.boundsOf(head)!;
      await tester.tapAt(
        tester.getTopLeft(inUpper(tileOf(index))) +
            Offset(
              (box.left + box.right) / 2 * staffSpace,
              ((box.top + box.bottom) / 2 - layout.tops[index]) * staffSpace,
            ),
      );
      expect(hits[upper]!.map((hit) => hit.target), [ElementOwner(head)]);
      expect(hits[lower], isEmpty);
    },
  );

  testWidgets(
    'the controller says where a note is drawn, and tells its listeners '
    'when a scroll, a zoom, an edit, a padding or a staff space moves it',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      final head = headOf(score, 0, 1);
      final cursor = point(score, 0, Moment(Fraction(1, 4)));
      final selection = RangeSelection(
        from: ScorePoint(score.measures[0].id, Moment(Fraction(1, 4))),
        to: ScorePoint(score.measures[0].id, Moment(Fraction(3, 4))),
        top: score.staves.first.id,
        bottom: score.staves.first.id,
      );
      expect(controller.rectOf(head), isNull);
      expect(controller.caretOf(cursor), isNull);
      expect(controller.rectsOf(selection), isEmpty);
      expect(controller.systemCount, 0);
      expect(controller.hitTest(const Offset(100, 100)), isNull);

      var told = 0;
      controller.addListener(() => told++);
      Future<void> expectTold(String what, Future<void> Function() act) async {
        final before = told;
        await act();
        expect(told, greaterThan(before), reason: what);
      }

      await expectTold(
        'the first layout',
        () => tester.pumpWidget(
          host(SheetView(score: score, controller: controller)),
        ),
      );
      expect(
        controller.rectOf(head)!.center,
        within(distance: 1e-6, from: middleOf(tester, head)),
      );

      await expectTold('a scroll', () async => scrollOf(tester).jumpTo(40));
      await tester.pump();
      expect(
        controller.rectOf(head)!.center,
        within(distance: 1e-6, from: middleOf(tester, head)),
      );
      final layout = shown(tester);
      final caret = controller.caretOf(cursor)!;
      expect(
        caret,
        within(
          distance: 1e-6,
          from: rectOnScreen(tester, 0, layout.caretOf(cursor)!),
        ),
      );
      expect(caret.height, greaterThan(4 * staffSpace - 1e-6));
      final shaded = layout.selectionBoxes(selection);
      expect(shaded, hasLength(1));
      expect(
        controller.rectsOf(selection).single,
        within(distance: 1e-6, from: rectOnScreen(tester, 0, shaded.single)),
      );

      await expectTold('a zoom', () async => controller.zoom = 2);
      await expectTold('the layout at the new zoom', tester.pump);
      expect(
        controller.rectOf(head)!.center,
        within(distance: 1e-6, from: middleOf(tester, head, spacePx: 16)),
      );

      final edited = raised(score, 30);
      await expectTold(
        'an edit',
        () => tester.pumpWidget(
          host(SheetView(score: edited, controller: controller)),
        ),
      );

      final top = controller.rectOf(head)!.top;
      await expectTold(
        'a padding that moves the sheet',
        () => tester.pumpWidget(
          host(
            SheetView(
              score: edited,
              controller: controller,
              padding: padding.copyWith(top: padding.top + 24),
            ),
          ),
        ),
      );
      expect(controller.rectOf(head)!.top, closeTo(top + 24, 1e-6));

      // The zoom is 2. A view 216 wide at a staff space of 4 is as many
      // staff spaces wide as one 400 wide at 8, so no line breaks anew.
      final unscaled = shown(tester);
      await expectTold(
        'a staff space that scales the layout it has',
        () => tester.pumpWidget(
          host(
            SheetView(
              score: edited,
              controller: controller,
              padding: padding.copyWith(top: padding.top + 24),
              staffSpace: 4,
            ),
            size: const Size(216, 400),
          ),
        ),
      );
      expect(shown(tester), same(unscaled));
      expect(
        controller.rectOf(head)!.center,
        within(distance: 1e-6, from: middleOf(tester, head)),
      );
    },
  );

  testWidgets(
    'between a new zoom and the frame that lays out at it, the controller '
    'answers for the sheet on screen, to the listeners of the zoom too',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SheetView(score: score, controller: controller)),
      );
      scrollOf(tester).jumpTo(40);
      await tester.pump();
      final head = headOf(score, 0, 1);
      final cursor = point(score, 0, Moment(Fraction(1, 4)));
      final selection = RangeSelection(
        from: ScorePoint(score.measures[0].id, Moment(Fraction(1, 4))),
        to: ScorePoint(score.measures[0].id, Moment(Fraction(3, 4))),
        top: score.staves.first.id,
        bottom: score.staves.first.id,
      );
      final middle = middleOf(tester, head);
      final caret = controller.caretOf(cursor);
      final shaded = controller.rectsOf(selection);
      expect(caret, isNotNull);
      expect(shaded, hasLength(1));
      expect(controller.hitTest(middle)?.target, ElementOwner(head));

      final heard = <Offset>[];
      controller.addListener(() => heard.add(controller.rectOf(head)!.center));
      controller.zoom = 2;
      expect(heard, hasLength(1), reason: 'a new zoom is told at once');
      expect(heard.single, within(distance: 1e-6, from: middle));
      expect(
        controller.rectOf(head)!.center,
        within(distance: 1e-6, from: middle),
      );
      expect(controller.caretOf(cursor), caret);
      expect(controller.rectsOf(selection), shaded);
      expect(controller.hitTest(middle)?.target, ElementOwner(head));

      await tester.pump();
      expect(
        heard.length,
        greaterThan(1),
        reason: 'the layout at the new zoom is told after its frame',
      );
      expect(
        heard.last,
        within(distance: 1e-6, from: middleOf(tester, head, spacePx: 16)),
      );
    },
  );

  testWidgets('a controller serves the view that has it, and no other', (
    tester,
  ) async {
    final score = tune();
    final first = SheetController();
    final second = SheetController(zoom: 2);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(host(SheetView(score: score, controller: first)));
    final width = shown(tester).width;

    await tester.pumpWidget(host(SheetView(score: score, controller: second)));
    expect(shown(tester).width, closeTo(width / 2, 1e-9));
    expect(first.systemCount, 0);
    expect(second.systemCount, shown(tester).systemCount);

    first.zoom = 3;
    await tester.pump();
    expect(shown(tester).width, closeTo(width / 2, 1e-9));

    await tester.pumpWidget(const SizedBox());
    first.zoom = 4;
    second.zoom = 4;
    expect(tester.takeException(), isNull);
    expect(second.systemCount, 0);
  });

  testWidgets(
    'a controller serves the view that takes the place of the one that had '
    'it',
    (tester) async {
      final score = tune();
      final controller = SheetController();
      addTearDown(controller.dispose);
      Widget view(String key) => host(
        SheetView(key: ValueKey(key), score: score, controller: controller),
      );
      await tester.pumpWidget(view('first'));
      final first = shown(tester);

      await tester.pumpWidget(view('second'));
      expect(shown(tester), isNot(same(first)));
      expect(controller.systemCount, first.systemCount);
      final head = headOf(score, 0, 1);
      expect(
        controller.rectOf(head)!.center,
        within(distance: 1e-6, from: middleOf(tester, head)),
      );

      controller.zoom = 2;
      await tester.pump();
      expect(shown(tester).width, closeTo(first.width / 2, 1e-9));
    },
  );

  test('a controller refuses a zoom that is not positive and finite', () {
    expect(() => SheetController(zoom: 0), throwsArgumentError);
    final controller = SheetController();
    addTearDown(controller.dispose);
    expect(() => controller.zoom = -1, throwsArgumentError);
    expect(() => controller.zoom = double.infinity, throwsArgumentError);
    expect(() => controller.zoom = double.nan, throwsArgumentError);
    expect(controller.zoom, 1);
  });

  test('a controller without a view cannot make an image', () {
    final controller = SheetController();
    addTearDown(controller.dispose);
    expect(controller.toImage, throwsStateError);
  });

  testWidgets('without a palette the colours come from the theme', (
    tester,
  ) async {
    const scheme = ColorScheme.dark();
    await tester.pumpWidget(
      Theme(
        data: ThemeData(colorScheme: scheme),
        child: host(SheetView(score: tune(bars: 4))),
      ),
    );
    final palette = paintersOf<SystemPainter>(tester).first.palette;
    expect(palette.ink, scheme.onSurface);
    expect(palette.outOfRange, scheme.error);
    expect(palette.cursor, scheme.primary);
  });

  testWidgets("a view registers the music font's licence once", (tester) async {
    // A view under a new key is a new view, so two views start here.
    for (final key in const ['first', 'second']) {
      await tester.pumpWidget(
        host(SheetView(key: ValueKey(key), score: tune(bars: 2))),
      );
    }
    final entries = (await tester.runAsync(
      () => LicenseRegistry.licenses
          .where((entry) => entry.packages.contains('Bravura'))
          .toList(),
    ))!;
    expect(entries, hasLength(1));
    expect(
      entries.single.paragraphs.map((paragraph) => paragraph.text).join(' '),
      contains('SIL OPEN FONT LICENSE'),
    );
  });

  testWidgets(
    'a view of the ensemble score shows the picture its drawables make on '
    'one canvas, with a caret, a selection, a tint and a playhead',
    (tester) async {
      await tester.runAsync(loadTextFont);
      final score = pictured();
      final plan = SheetLayout(
        score,
        width: sheetWidth,
        text: ParagraphMeasurer(),
        style: pictureStyle,
      );
      final size = Size(
        sheetWidth * staffSpace + padding.horizontal,
        (plan.height * staffSpace + padding.vertical).ceilToDouble(),
      );
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final ids = [for (final measure in score.measures) measure.id];
      final staves = [for (final staff in score.staves) staff.id];
      final second = plan.firstBarOf(1);
      final selection = RangeSelection(
        from: ScorePoint(ids[ids.indexOf(second) - 1], Moment(Fraction(1, 2))),
        to: ScorePoint(second, Moment(Fraction(1, 2))),
        top: staves[0],
        bottom: staves[1],
      );
      final cursor = VoicePoint(
        staff: staves[1],
        voice: VoiceSlot.one,
        at: ScorePoint(plan.firstBarOf(2), Moment(Fraction(1, 4))),
      );
      final script = PlaybackCompiler().compile(score);
      final seconds = script.totalSeconds * 0.3;
      final playback = ValueNotifier<PlaybackPosition?>(
        PlaybackPosition(
          seconds: seconds,
          point: script.pointAt(seconds)!,
          sounding: script.sourcesAt(seconds),
        ),
      );
      addTearDown(playback.dispose);
      const orange = Color(0xFFFF8800);
      final note = plan
          .systemAt(0)
          .drawables
          .map((drawable) => drawable.owner)
          .whereType<ElementOwner>()
          .map((owner) => owner.ref)
          .whereType<NoteRef>()
          .first;
      final tints = <ElementRef, Color>{note: orange};

      final key = GlobalKey();
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: SheetView(
                score: score,
                cursor: cursor,
                selection: selection,
                tints: tints,
                playback: playback,
                style: pictureStyle,
                palette: inked,
              ),
            ),
          ),
          size: size,
        ),
      );
      final layout = shown(tester);
      expect(layout.systemCount, greaterThanOrEqualTo(3));
      expect(layout.width, closeTo(sheetWidth, 1e-9));
      expect(layout.height, plan.height);
      expect(built(tester), hasLength(layout.systemCount));
      final width = size.width.toInt();
      final height = size.height.toInt();

      final view = (await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage();
        final rgba = (await image.toByteData())!.buffer.asUint8List();
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        expect((image.width, image.height), (width, height));
        image.dispose();
        return (rgba: rgba, png: png);
      }))!;
      writeSnapshot('sheet_view', view.png);

      final glyphs = bravuraPainter();
      const scale = SheetScale(spacePx: staffSpace);
      final canvas = (await tester.runAsync(
        () => render(width, height, (canvas) {
          canvas.translate(padding.left, padding.top);
          paintDrawables(canvas, glyphs, layout.header, scale);
          for (var index = 0; index < layout.systemCount; index++) {
            canvas
              ..save()
              ..translate(0, layout.tops[index] * staffSpace);
            paintDrawables(canvas, glyphs, inkOf(layout, index), scale);
            OverlayPainter(
              layout: layout,
              index: index,
              cursor: cursor,
              selection: selection,
              tints: tints,
              playback: playback,
              glyphs: glyphs,
              palette: inked,
              scale: scale,
            ).paint(canvas, Size.zero);
            canvas.restore();
          }
        }),
      ))!;
      var differing = 0;
      for (var at = 0; at < view.rgba.length; at++) {
        if ((view.rgba[at] - canvas.rgba[at]).abs() > 32) {
          differing++;
        }
      }
      expect(differing, 0, reason: 'colour channels that differ');

      const sheet = SheetScale(
        spacePx: staffSpace,
        origin: Offset(16, 16),
      );
      (int, int, int) pixel(Uint8List rgba, Offset at) {
        final i = (at.dy.floor() * width + at.dx.floor()) * 4;
        return (rgba[i], rgba[i + 1], rgba[i + 2]);
      }

      final caret = layout.caretOf(cursor)!;
      final (caretRed, caretGreen, caretBlue) = pixel(
        view.rgba,
        sheet.toPx(SpPoint(caret.left, caret.top + 0.25)),
      );
      expect(caretRed, greaterThan(caretGreen + 60), reason: 'the caret');
      expect(caretRed, greaterThan(caretBlue + 60), reason: 'the caret');

      final playhead = layout.playheadAt(playback.value!.point)!;
      final (headRed, headGreen, headBlue) = pixel(
        view.rgba,
        sheet.toPx(SpPoint(playhead.left, playhead.top + 0.25)),
      );
      expect(headGreen, greaterThan(headRed + 40), reason: 'the playhead');
      expect(headGreen, greaterThan(headBlue + 40), reason: 'the playhead');

      final boxes = layout.selectionBoxes(selection);
      expect(boxes, hasLength(2));
      for (final box in boxes) {
        final middle = SpPoint(
          (box.left + box.right) / 2,
          (box.top + box.bottom) / 2,
        );
        final (red, _, blue) = pixel(view.rgba, sheet.toPx(middle));
        expect(blue, greaterThan(red + 30), reason: 'shaded at $middle');
        final (redAbove, _, blueAbove) = pixel(
          view.rgba,
          sheet.toPx(SpPoint(middle.x, box.top)).translate(0, -3),
        );
        expect(redAbove, blueAbove, reason: 'not shaded above $middle');
      }

      List<Offset> pixelsOf(int red, int green, int blue) => [
        for (var at = 0; at < view.rgba.length; at += 4)
          if (view.rgba[at] == red &&
              view.rgba[at + 1] == green &&
              view.rgba[at + 2] == blue)
            Offset(at ~/ 4 % width + 0.5, at ~/ 4 ~/ width + 0.5),
      ];
      // Ink may leave its box by a pixel.
      Rect placeOf(ElementRef ref) =>
          sheet.rectOf(layout.boundsOf(ref)!).inflate(1);

      final sounding = [
        for (final ref in playback.value!.sounding)
          if (layout.boundsOf(ref) != null) placeOf(ref),
      ];
      expect(sounding, isNotEmpty);
      final purple = pixelsOf(0x88, 0x22, 0xCC);
      expect(purple, isNotEmpty, reason: 'a sounding note in its colour');
      expect(
        purple.where((at) => !sounding.any((place) => place.contains(at))),
        isEmpty,
        reason: 'the playback colour off the sounding notes',
      );

      final tinted = pixelsOf(0xFF, 0x88, 0x00);
      expect(tinted, isNotEmpty, reason: 'the tinted note in its colour');
      expect(
        tinted.where((at) => !placeOf(note).contains(at)),
        isEmpty,
        reason: 'the tint off the tinted note',
      );
      expect(
        layout.boundsOf(note.event),
        isNot(layout.boundsOf(note)),
        reason: "the note's event draws more than its head",
      );
    },
  );
}
