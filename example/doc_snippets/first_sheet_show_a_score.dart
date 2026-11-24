// site/src/content/docs/tutorial/first-sheet.mdx shows the code between
// the markers in "Show a score".
// .github/scripts/check_release_docs.sh fails when the two differ.
// #docregion
import 'package:khuur_sheet_music/khuur_sheet_music.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const FirstSheetApp());

class FirstSheetApp extends StatelessWidget {
  const FirstSheetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'First sheet',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: const SheetPage(),
  );
}

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

class SheetPage extends StatelessWidget {
  const SheetPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('First sheet')),
    body: SheetView(score: blankScore),
  );
}
// #enddocregion
