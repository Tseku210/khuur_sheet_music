/// Draws the pictures of sheets on the docs site and in the README, from
/// scores built here as the code on each page builds them.
///
/// Run it from `example/`, and commit the files it writes:
///
/// ```bash
/// flutter test tool/render_docs_images.dart
/// ```
///
/// Each picture of the site is drawn twice, in the light and the dark theme
/// with no paper, and the page shows the one for its own theme. The README's
/// pictures are drawn on white paper, as GitHub and pub.dev show them on
/// either theme. A second run on the same machine writes the same bytes.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:example/demo_score.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khuur_sheet_music/khuur_sheet_music.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/draw.dart';

const double pixelRatio = 2;

const String siteAssets = '../site/src/assets/sheets';

/// The theme of the tutorial's app, which every page's picture shares.
final ThemeData lightTheme = ThemeData(colorSchemeSeed: Colors.indigo);

final ThemeData darkTheme = ThemeData(
  colorSchemeSeed: Colors.indigo,
  brightness: Brightness.dark,
);

/// One file of a shot: its theme, whether it is drawn on the theme's paper
/// or on none, and what its file name ends in.
typedef Look = ({String suffix, ThemeData theme, bool paper});

final List<Look> themed = [
  (suffix: '-light', theme: lightTheme, paper: false),
  (suffix: '-dark', theme: darkTheme, paper: false),
];

final List<Look> onWhite = [(suffix: '', theme: lightTheme, paper: true)];

/// What a shot shows, and what it does to the widgets once they are on
/// screen, before the picture is taken.
typedef Scene = ({Widget widget, Future<void> Function(WidgetTester)? act});

/// A picture, written to `<path><suffix>.png` for each of its [looks]. With
/// no [height] it is as high as its sheets need to show whole.
final class Shot {
  const Shot(
    this.path,
    this.scene, {
    required this.looks,
    this.width = 720,
    this.height,
  });

  final String path;
  final Scene Function() scene;
  final List<Look> looks;
  final double width;
  final double? height;
}

Scene still(Widget widget) => (widget: widget, act: null);

// The README's quick start.

/// The quick start's four notes, with the session after each, so that a
/// picture can mark one of them.
List<EditSession> quickStartSessions() {
  var session = EditSession.start(
    Score.blank(
      parts: const [
        PartTemplate(
          name: 'Piano',
          instrument: Instrument(key: 'piano', program: 0),
        ),
      ],
      measureCount: 4,
    ),
  );
  return [
    for (final name in ['C4', 'E4', 'G4', 'C5'])
      if (session.run(
            EnterNote(
              at: session.cursor,
              tone: Pitch.parse(name),
              value: NoteValue.quarter,
            ),
          )
          case Applied(session: final next))
        session = next,
  ];
}

// tutorial/first-sheet.mdx

final Score blankScore = Score.blank(
  title: 'First sheet',
  parts: const [
    PartTemplate(
      name: 'Piano',
      instrument: Instrument(key: 'piano', program: 0),
    ),
  ],
  measureCount: 4,
);

/// The tutorial's scale, with the session after each note, so that a
/// picture can mark one of them.
List<EditSession> scaleSessions() {
  var session = EditSession.start(blankScore);
  return [
    for (final name in ['C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5'])
      if (session.run(
            EnterNote(
              at: session.cursor,
              tone: Pitch.parse(name),
              value: NoteValue.quarter,
            ),
          )
          case Applied(session: final next))
        session = next,
  ];
}

final Score scale = scaleSessions().last.score;

/// The tutorial's first tap: a quarter note G on the second beat of the
/// third bar, entered as the page's `_onTap` enters it.
EditSession tappedG() {
  final session = EditSession.start(scale);
  final third = scale.measures[2].id;
  return session
      .run(
        EnterNote(
          at: VoicePoint(
            staff: session.cursor.staff,
            voice: VoiceSlot.one,
            at: ScorePoint(third, Moment.zero + NoteValue.quarter.length),
          ),
          tone: Pitch.parse('G4'),
          value: NoteValue.quarter,
        ),
      )
      .session;
}

/// The scale as the player reports it while its third note, E, sounds.
PlaybackPosition playingE() {
  final e = scaleSessions()[2].selection.singleEvent!;
  return PlaybackPosition(
    seconds: 1,
    point: PlaybackPoint(
      bar: PlayedBar(measure: e.measure, pass: 1, start: 0, end: 2),
      offset: 0.5,
    ),
    playing: [e],
  );
}

// guides/show-a-score.mdx

Score showAScore() {
  var session = EditSession.start(
    Score.blank(
      parts: const [
        PartTemplate(
          name: 'Piano',
          instrument: Instrument(key: 'piano', program: 0),
          staves: 2,
          clefs: [Clef.treble, Clef.bass],
        ),
      ],
      measureCount: 8,
    ),
  );

  final edit = EnterNote(
    at: session.cursor,
    tone: Pitch.parse('E4'),
    value: NoteValue.quarter,
  );
  if (session.run(edit) case Applied(session: final next)) {
    session = next;
  }

  final bars = [for (final column in session.score.measures) column.id];
  session = session
      .run(
        Batch([
          SetKey(from: bars.first, key: const KeySignature(-1)),
          SetBreak(bars[4], LayoutBreak.system),
        ], label: 'Key and break'),
      )
      .session;
  return session.score;
}

// guides/keep-a-staff-in-view.mdx

/// A score of three parts whose system is higher than a short view, with a
/// tune in the second part, the solo.
Score trio() {
  var session = EditSession.start(
    Score.blank(
      parts: const [
        PartTemplate(
          name: 'Flute',
          instrument: Instrument(key: 'flute', program: 73),
        ),
        PartTemplate(
          name: 'Violin',
          instrument: Instrument(key: 'violin', program: 40),
        ),
        PartTemplate(
          name: 'Cello',
          instrument: Instrument(key: 'cello', program: 42),
          clefs: [Clef.bass],
        ),
      ],
      measureCount: 2,
    ),
  );
  final solo = session.score.parts[1].staves.first.id;
  var at = VoicePoint(staff: solo, voice: VoiceSlot.one, at: session.cursor.at);
  for (final name in ['G4', 'B4', 'D5', 'B4', 'C5', 'A4', 'F#4', 'G4']) {
    session = session
        .run(
          EnterNote(at: at, tone: Pitch.parse(name), value: NoteValue.quarter),
        )
        .session;
    at = session.cursor;
  }
  return session.score;
}

/// [child] in a box with the theme's outline, as a view on a screen.
Widget framed(Widget child, {double? height}) => Builder(
  builder: (context) => Container(
    height: height,
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  ),
);

/// [child] over a [caption] in code.
Widget captioned(String caption, Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(child: child),
    const SizedBox(height: 8),
    Builder(
      builder: (context) => Text(
        caption,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  ],
);

Widget sideBySide(Widget left, Widget right) => Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Expanded(child: left),
    const SizedBox(width: 16),
    Expanded(child: right),
  ],
);

Scene keepAStaff() {
  final score = trio();
  final soloStaff = score.parts[1].staves.first.id;
  final point = ScorePoint(score.measures.first.id, Moment.zero);
  final top = SheetController();
  final solo = SheetController();
  Widget view(SheetController controller) => framed(
    SheetView(score: score, controller: controller, style: pictureStyle),
  );
  return (
    widget: sideBySide(
      captioned('ensureVisible(point)', view(top)),
      captioned('ensureVisible(point, staff: soloStaff)', view(solo)),
    ),
    act: (tester) async {
      unawaited(top.ensureVisible(point));
      unawaited(solo.ensureVisible(point, staff: soloStaff));
      await tester.pumpAndSettle();
    },
  );
}

/// The builder of guides/widgets-over-the-sheet.mdx, over the tutorial's
/// scale with its last note selected.
Scene widgetsOverTheSheet() {
  final session = scaleSessions().last;
  final sheet = SheetController();
  return still(
    ListenableBuilder(
      listenable: sheet,
      builder: (context, child) {
        final rect = switch (session.selection.singleEvent) {
          final event? => sheet.rectOf(event),
          null => null,
        };
        return Stack(
          children: [
            child!,
            if (rect != null)
              Positioned(
                left: rect.right,
                top: rect.top - 32,
                child: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.close),
                  onPressed: () {},
                ),
              ),
          ],
        );
      },
      child: SheetView(
        score: session.score,
        selection: session.selection,
        controller: sheet,
        style: pictureStyle,
      ),
    ),
  );
}

/// The view with a caret and a selection, next to the image its controller
/// exports of it.
Scene exportAnImage() {
  final session = scaleSessions()[4];
  final sheet = SheetController();
  final exported = ValueNotifier<ui.Image?>(null);
  return (
    widget: sideBySide(
      captioned(
        'SheetView',
        framed(
          SheetView(
            score: session.score,
            cursor: session.cursor,
            selection: session.selection,
            controller: sheet,
            style: pictureStyle,
          ),
        ),
      ),
      captioned(
        'toImage(pixelRatio: 2)',
        framed(
          Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder(
              valueListenable: exported,
              builder: (context, image, _) =>
                  RawImage(image: image, scale: pixelRatio),
            ),
          ),
        ),
      ),
    ),
    act: (tester) async {
      exported.value = await tester.runAsync(
        () => sheet.toImage(pixelRatio: pixelRatio),
      );
      await tester.pump();
    },
  );
}

/// The quick start's four notes with the caret on the first, the third
/// selected and the second sounding, in the light palette over the dark,
/// each on its theme's surface.
Scene changeTheLook() {
  final sessions = quickStartSessions();
  final score = sessions.last.score;
  final [_, e, g, _] = [
    for (final session in sessions) session.selection.singleEvent!,
  ];
  final playing = ValueNotifier<PlaybackPosition?>(
    PlaybackPosition(
      seconds: 0.6,
      point: PlaybackPoint(
        bar: PlayedBar(measure: e.measure, pass: 1, start: 0, end: 2.4),
        offset: 0.25,
      ),
      playing: [e],
    ),
  );
  Widget panel(ThemeData theme) => Theme(
    data: theme,
    child: ColoredBox(
      color: theme.colorScheme.surface,
      child: SheetView(
        score: score,
        cursor: EditSession.start(score).cursor,
        selection: Selection.event(g),
        playback: playing,
        style: pictureStyle,
      ),
    ),
  );
  return still(
    Column(
      children: [
        Expanded(child: panel(lightTheme)),
        Expanded(child: panel(darkTheme)),
      ],
    ),
  );
}

/// `valueLabel` of guides/glyphs-in-your-widgets.mdx.
Widget valueLabel(NoteValue value, {double staffSpace = 8}) {
  final glyphs = [
    noteGlyph(value.base),
    for (var dot = 0; dot < value.dots; dot++) Glyph.metAugmentationDot,
  ];
  return Text(
    String.fromCharCodes([for (final glyph in glyphs) glyph.codepoint]),
    style: TextStyle(
      fontFamily: SmuflFont.bravura.flutterFamily,
      fontSize: 4 * staffSpace,
    ),
  );
}

/// A note palette of buttons, each labelled with a glyph the sheet
/// engraves, as guides/glyphs-in-your-widgets.mdx draws them.
Scene glyphPalette() {
  Widget glyph(Glyph glyph) => Text(
    String.fromCharCode(glyph.codepoint),
    style: TextStyle(fontFamily: SmuflFont.bravura.flutterFamily, fontSize: 32),
  );
  final labels = [
    for (final base in [
      DurationBase.whole,
      DurationBase.half,
      DurationBase.quarter,
      DurationBase.eighth,
      DurationBase.sixteenth,
    ])
      valueLabel(NoteValue(base)),
    valueLabel(const NoteValue(DurationBase.quarter, dots: 1)),
    glyph(restGlyph(DurationBase.quarter)),
    glyph(accidentalGlyph(Alter.sharp, EngravingStyle.standard.quarterTones)),
    glyph(dynamicGlyph(Dynamic.mf)),
  ];
  return still(
    Center(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final label in labels)
            OutlinedButton(onPressed: () {}, child: label),
        ],
      ),
    ),
  );
}

final List<Shot> shots = [
  Shot(
    '../doc/hero',
    () => still(SheetView(score: buildDemoScore(), style: pictureStyle)),
    looks: [...onWhite, (suffix: '-dark', theme: darkTheme, paper: true)],
  ),
  Shot(
    '../doc/quick-start',
    () => still(
      SheetView(score: quickStartSessions().last.score, style: pictureStyle),
    ),
    looks: onWhite,
  ),
  Shot(
    '$siteAssets/home',
    () => still(SheetView(score: buildDemoScore(), style: pictureStyle)),
    looks: themed,
  ),
  Shot(
    '$siteAssets/first-sheet-blank',
    () => still(SheetView(score: blankScore, style: pictureStyle)),
    looks: themed,
  ),
  Shot(
    '$siteAssets/first-sheet-scale',
    () => still(SheetView(score: scale, style: pictureStyle)),
    looks: themed,
  ),
  Shot('$siteAssets/first-sheet-cursor', () {
    final session = EditSession.start(scale);
    return still(
      SheetView(
        score: session.score,
        cursor: session.cursor,
        tapGrid: DurationBase.quarter,
        style: pictureStyle,
      ),
    );
  }, looks: themed),
  Shot('$siteAssets/first-sheet-tap', () {
    final session = tappedG();
    return still(
      SheetView(
        score: session.score,
        cursor: session.cursor,
        tapGrid: DurationBase.quarter,
        style: pictureStyle,
      ),
    );
  }, looks: themed),
  Shot(
    '$siteAssets/first-sheet-playing',
    () => still(
      SheetView(
        score: scale,
        playback: ValueNotifier(playingE()),
        style: pictureStyle,
      ),
    ),
    looks: themed,
  ),
  Shot(
    '$siteAssets/show-a-score',
    () => still(SheetView(score: showAScore(), style: pictureStyle)),
    looks: themed,
  ),
  Shot(
    '$siteAssets/change-the-look',
    changeTheLook,
    looks: [(suffix: '', theme: lightTheme, paper: false)],
  ),
  Shot(
    '$siteAssets/keep-a-staff-in-view',
    keepAStaff,
    looks: themed,
    height: 180,
  ),
  Shot(
    '$siteAssets/widgets-over-the-sheet',
    widgetsOverTheSheet,
    looks: themed,
  ),
  Shot('$siteAssets/export-an-image', exportAnImage, looks: themed),
  Shot(
    '$siteAssets/glyphs-in-your-widgets',
    glyphPalette,
    looks: themed,
    height: 80,
  ),
];

Future<void> loadFonts() async {
  final material =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  await loadFontFile('../$bravuraFile', SmuflFont.bravura.flutterFamily);
  await loadTextFont();
  await loadFontFile('$material/Roboto-Regular.ttf', 'Roboto');
  await loadFontFile('$material/MaterialIcons-Regular.otf', 'MaterialIcons');
}

/// How much higher the screen must be for every sheet on it to fit whole.
double shortfall(WidgetTester tester) => [
  for (final state in tester.stateList<ScrollableState>(
    find.descendant(
      of: find.byType(SheetView),
      matching: find.byType(Scrollable),
    ),
  ))
    state.position.maxScrollExtent,
].fold(0, max);

Future<void> take(WidgetTester tester, Shot shot, Look look) async {
  final key = GlobalKey();
  final scene = shot.scene();
  Future<void> show(double height) async {
    tester.view
      ..physicalSize = Size(shot.width, height) * pixelRatio
      ..devicePixelRatio = pixelRatio;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: look.theme,
        home: RepaintBoundary(
          key: key,
          child: Material(
            color: look.paper
                ? (look.theme.brightness == Brightness.light
                      ? Colors.white
                      : look.theme.colorScheme.surface)
                : Colors.transparent,
            child: scene.widget,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  var height = shot.height ?? 120;
  await show(height);
  while (shot.height == null && shortfall(tester) > 0) {
    height += shortfall(tester).ceilToDouble();
    await show(height);
  }
  await scene.act?.call(tester);
  final png = await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(key))
        .toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  });
  File('${shot.path}${look.suffix}.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!);
}

void main() {
  setUpAll(loadFonts);

  for (final shot in shots) {
    for (final look in shot.looks) {
      testWidgets('${shot.path}${look.suffix}.png', (tester) async {
        addTearDown(tester.view.reset);
        await take(tester, shot, look);
      });
    }
  }
}
