import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show ColorScheme, Theme, ThemeData;
import 'package:flutter/rendering.dart';
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
  var score = blankScore(parts: const [violin], bars: bars)
      .copyWith(meta: const ScoreMeta(title: 'Tune'));
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
      for (var beat = 0; beat < 4; beat++)
        chordOf(20000 + bar * 4 + beat, 'C7'),
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
MeasureId firstBarInView(WidgetTester tester, {double spacePx = staffSpace}) =>
    shown(tester).firstBarOf(
      built(tester).firstWhere(
        (index) => spanOf(tester, index, spacePx: spacePx).bottom > 0,
      ),
    );

void expectWhollyInView(WidgetTester tester, MeasureId bar) {
  final span = spanOf(tester, shown(tester).systemOf(bar)!);
  expect(span.top, greaterThanOrEqualTo(-1e-6));
  expect(span.bottom, lessThanOrEqualTo(viewSize.height + 1e-6));
}

/// The picture each tile in view holds for its painter of type [T]. Painting
/// again replaces the picture's layer, so a layer that is the same object
/// was not painted again.
List<Layer> picturesOf<T extends CustomPainter>(WidgetTester tester) => [
      for (final box in tester.renderObjectList<RenderBox>(paintedBy<T>()))
        if ((box.localToGlobal(Offset.zero) & box.size)
            .overlaps(Offset.zero & viewSize))
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

/// A playback position that says whether anything listens to it.
final class HeardPlayback extends ValueNotifier<PlaybackPosition?> {
  HeardPlayback() : super(null);

  bool get isHeard => hasListeners;
}

void main() {
  setUpAll(() => loadBravura(bravuraPainter()));

  testWidgets(
      'a playback position, a cursor, a selection, a tint and an edit below '
      'the view repaint the overlays over the same system pictures, and a '
      'scroll builds nothing', (tester) async {
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
  });

  testWidgets(
      'an edit above the view that makes a system taller leaves the first '
      'bar in view where it was', (tester) async {
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
  });

  testWidgets('a new zoom leaves the first bar in view where it was',
      (tester) async {
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

  testWidgets(
      'a new zoom leaves the first bar in view where it was when the '
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
      'in view', (tester) async {
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
      view(VoicePoint(
        staff: score.staves.first.id,
        voice: VoiceSlot.one,
        at: ScorePoint(bar, Moment.zero),
      )),
    );
    await tester.pumpAndSettle();
    expect(firstBarInView(tester), isNot(bar));
    final top = topOf(tester, bar);

    controller.zoom = 1.25;
    await tester.pump();
    expect(topOf(tester, bar), closeTo(top, 1e-6));
  });

  testWidgets(
      'a new zoom leaves the first bar in view where it was, with the '
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
      view(VoicePoint(
        staff: score.staves.first.id,
        voice: VoiceSlot.one,
        at: ScorePoint(below, Moment.zero),
      )),
    );
    expect(topOf(tester, below), lessThan(viewSize.height));
    final top = topOf(tester, bar);

    controller.zoom = 1.25;
    await tester.pump();
    expect(topOf(tester, bar), closeTo(top, 1e-6));
  });

  testWidgets(
      'ensureVisible ends with its system in view when an edit moves the '
      'system on the way', (tester) async {
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
  });

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
    final above =
        layout.firstBarOf(layout.systemOf(score.measures[30].id)! - 1);
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
  });

  testWidgets(
      'a drag takes over from ensureVisible, and an edit after it leaves '
      'the scroll alone', (tester) async {
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
  });

  testWidgets("the scroll extent is the sheet's height on the first frame",
      (tester) async {
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
      'unless followCursor is off', (tester) async {
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
  });

  testWidgets(
      'playback brings a system to the top of the view once, when it enters '
      'one that is out of view, unless followPlayback is off', (tester) async {
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
  });

  testWidgets(
      'a view follows the playback it was last given, and listens to no '
      'other', (tester) async {
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
  });

  testWidgets('a new style lays the whole sheet out again', (tester) async {
    final score = tune();
    Iterable<TextDraw> labels() => paintersOf<SystemPainter>(tester)
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
      'once', (tester) async {
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
  });

  testWidgets(
      'a font the text does not use that loads late leaves the layout as '
      'it is', (tester) async {
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
  });

  testWidgets(
      'toImage of a range of systems is as high as they are planned, times '
      'the pixel ratio, and holds their ink', (tester) async {
    final controller = SheetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(SheetView(score: tune(), controller: controller, palette: inked)),
    );
    final layout = shown(tester);
    const pixelRatio = 2.0;
    const px = staffSpace * pixelRatio;
    final planned = layout.tops[2] + layout.heightOf(2) - layout.tops[1];

    final (:width, :height, :rgba) = (await tester.runAsync(() async {
      final image =
          await controller.toImage(from: 1, to: 3, pixelRatio: pixelRatio);
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final size = (width: image.width, height: image.height, rgba: bytes);
      image.dispose();
      return size;
    }))!;
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

    final withHeader = (await tester.runAsync(() async {
      final image = await controller.toImage(to: 1);
      final height = image.height;
      image.dispose();
      return height;
    }))!;
    expect(
      withHeader,
      ((layout.tops[0] + layout.heightOf(0)) * staffSpace).ceil(),
    );
  });

  testWidgets(
      'toImage refuses a range higher than one image holds, an empty range '
      'and a range outside the sheet', (tester) async {
    final controller = SheetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(SheetView(score: tune(), controller: controller)),
    );
    final layout = shown(tester);
    expect(controller.systemCount, layout.systemCount);
    expect(
      layout.height * staffSpace * 8,
      greaterThan(SheetController.maxImageHeight),
    );
    expect(() => controller.toImage(pixelRatio: 8), throwsArgumentError);
    expect(() => controller.toImage(from: 2, to: 2), throwsArgumentError);
    expect(() => controller.toImage(pixelRatio: 0), throwsArgumentError);
    expect(
      () => controller.toImage(to: layout.systemCount + 1),
      throwsRangeError,
    );
  });

  testWidgets(
      'each system in view is one node for a screen reader, labelled with '
      'the bars it holds', (tester) async {
    final semantics = tester.ensureSemantics();
    var score = tune(bars: 12);
    for (final bar in [3, 6, 7, 10]) {
      score = edit(score, SetBreak(score.measures[bar].id, LayoutBreak.system));
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

    await tester.pumpWidget(host(SheetView(score: tune(bars: 2)), size: size));
    final alone = tester.semantics
        .simulatedAccessibilityTraversal()
        .where((node) => node.label == 'Bars 1 to 2');
    expect(alone, hasLength(1));
    expect(
      alone.single.getSemanticsData().flagsCollection.hasImplicitScrolling,
      isFalse,
      reason: 'a lone system is a node of its own, not the scrolling one',
    );
    semantics.dispose();
  });

  testWidgets(
      'a tap reports the hit the layout gives for the same point of the '
      'sheet, at two zooms and after a scroll', (tester) async {
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
    final lower = [
      for (var bar = 0; bar < score.measures.length; bar++)
        headOf(score, bar, 2),
    ].firstWhere((head) {
      final system = shown(tester).systemOf(head.event.measure)!;
      return built(tester).contains(system) &&
          spanOf(tester, system).top > 0 &&
          spanOf(tester, system).bottom < viewSize.height;
    });
    expect((await tap(middleOf(tester, lower))).target, ElementOwner(lower));
  });

  testWidgets(
      'the controller says where a note is drawn, and tells its listeners '
      'when a scroll, a zoom or an edit moves it', (tester) async {
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

    await expectTold(
      'an edit',
      () => tester.pumpWidget(
        host(SheetView(score: raised(score, 30), controller: controller)),
      ),
    );
  });

  testWidgets('a controller serves the view that has it, and no other',
      (tester) async {
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
      'it', (tester) async {
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
  });

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

  testWidgets('without a palette the colours come from the theme',
      (tester) async {
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
    await tester.pumpWidget(host(SheetView(score: tune(bars: 2))));
    await tester.pumpWidget(host(SheetView(score: tune(bars: 3))));
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
    final tints = {
      plan
          .systemAt(0)
          .drawables
          .map((drawable) => drawable.owner)
          .whereType<ElementOwner>()
          .first
          .ref: orange,
    };

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

    final sounding = playback.value!.sounding
        .where((ref) => layout.boundsOf(ref) != null)
        .toList();
    expect(sounding, isNotEmpty);
    final purple = [
      for (var at = 0; at < view.rgba.length; at += 4)
        if (view.rgba[at] == 0x88 &&
            view.rgba[at + 1] == 0x22 &&
            view.rgba[at + 2] == 0xCC)
          at,
    ];
    expect(purple, isNotEmpty, reason: 'a sounding note in its colour');

    final tinted = [
      for (var at = 0; at < view.rgba.length; at += 4)
        if (view.rgba[at] == 0xFF &&
            view.rgba[at + 1] == 0x88 &&
            view.rgba[at + 2] == 0x00)
          at,
    ];
    expect(tinted, isNotEmpty, reason: 'a tinted note in its colour');
  });
}
