import 'package:flutter/material.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';
import 'midi_example.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Simple Sheet Music Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeScreen());
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simple Sheet Music')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SimpleSheetMusicDemo()));
              },
              child: const Text('Basic Example'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const MidiExamplePage()));
              },
              child: const Text('MIDI Example'),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleSheetMusicDemo extends StatefulWidget {
  const SimpleSheetMusicDemo({super.key});

  @override
  State<StatefulWidget> createState() => SimpleSheetMusicDemoState();
}

class SimpleSheetMusicDemoState extends State<SimpleSheetMusicDemo> {
  @override
  Widget build(BuildContext context) {
    final sheetMusicSize = MediaQuery.of(context).size;
    final width = sheetMusicSize.width;
    final height = sheetMusicSize.height / 2;

    Measure measure1 = Measure([
      Clef.treble(),
      TimeSignature.twoFour(),
      KeySignature.dMajor(),
      ChordNote([
        const ChordNotePart(Pitch.b4),
        const ChordNotePart(Pitch.g5),
        const ChordNotePart(Pitch.a4),
      ]),
      Rest(RestType.quarter),
      Note(Pitch.a4, noteDuration: NoteDuration.quarter),
      Rest(RestType.sixteenth),
    ]);
    Measure measure2 = Measure([
      ChordNote([
        const ChordNotePart(Pitch.c4),
        const ChordNotePart(Pitch.c5),
      ], noteDuration: NoteDuration.sixteenth),
      Note(Pitch.a4,
          noteDuration: NoteDuration.sixteenth, accidental: Accidental.flat)
    ]);
    Measure measure3 = Measure(
      [
        Clef.bass(),
        TimeSignature.fourFour(),
        KeySignature.cMinor(),
        ChordNote(
          [
            const ChordNotePart(Pitch.c2),
            const ChordNotePart(Pitch.c3),
          ],
        ),
        Rest(RestType.quarter),
        Note(Pitch.a3,
            noteDuration: NoteDuration.whole, accidental: Accidental.flat),
      ],
      isNewLine: true,
    );
    return Scaffold(
        appBar: AppBar(title: const Text('Simple Sheet Music')),
        body: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SimpleSheetMusic(
              height: height,
              width: width,
              debug: true,
              onTap: (symbol, position) {
                // Handle the tapped symbol
                print(
                    'Tapped symbol: ${symbol is Clef ? symbol.id : symbol.runtimeType}');
                print('At position: $position');

                // You can now:
                // 1. Store the selected symbol
                // 2. Show a menu for actions (remove, move up/down)
                // 3. Update the measures list to reflect changes
              },
              measures: [measure1, measure2, measure3],
            ),
          ),
        ));
  }
}
