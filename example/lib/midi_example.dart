import 'package:flutter/material.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';

void main() {
  runApp(const MidiExampleApp());
}

class MidiExampleApp extends StatelessWidget {
  const MidiExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Sheet Music MIDI Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MidiExamplePage(),
    );
  }
}

class MidiExamplePage extends StatefulWidget {
  const MidiExamplePage({super.key});

  @override
  MidiExamplePageState createState() => MidiExamplePageState();
}

class MidiExamplePageState extends State<MidiExamplePage> {
  final GlobalKey<SimpleSheetMusicState> _sheetMusicKey = GlobalKey();
  int _tempo = 120;
  bool _isPlaying = false;
  Color _highlightColor = Colors.green;
  late final SimpleSheetMusicState _sheetMusicState;

  // Add more example measures for testing
  List<List<Measure>> _exampleSets = [];
  int _currentExampleIndex = 0;
  SoundFontType _selectedSoundFont = SoundFontType.touhou;

  @override
  void initState() {
    super.initState();
    // Initialize example sets
    _exampleSets = [
      _createCMajorScaleMeasures(),
      // _createChordExampleMeasures(),
      // _createArpeggioExampleMeasures(),
    ];
    // Access the sheet music state after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetMusicState = _sheetMusicKey.currentState!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Sheet Music MIDI Example'),
      ),
      body: Column(
        children: [
          _buildInfoPanel(),
          Expanded(
            child: SimpleSheetMusic(
              key: _sheetMusicKey,
              measures: _exampleSets[_currentExampleIndex],
              initialTimeSignatureType: TimeSignatureType.fourFour,
              width: MediaQuery.of(context).size.width,
              height: 300,
              tempo: _tempo,
              enableMidi: true,
              soundFontType: _selectedSoundFont,
              highlightColor: _highlightColor,
            ),
          ),
          _buildExampleSelector(),
          _buildControlPanel(),
        ],
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MIDI Testing Tools',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '• Play the sheet music and observe note highlighting\n'
            '• Change examples using the selector below\n'
            '• Adjust tempo with the slider\n'
            '• Try different highlight colors',
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Example Selection:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton(
                onPressed:
                    _currentExampleIndex == 0 ? null : () => _changeExample(0),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _currentExampleIndex == 0
                      ? Colors.blue.withOpacity(0.2)
                      : null,
                ),
                child: const Text('C Major Scale'),
              ),
              // OutlinedButton(
              //   onPressed:
              //       _currentExampleIndex == 1 ? null : () => _changeExample(1),
              //   style: OutlinedButton.styleFrom(
              //     backgroundColor: _currentExampleIndex == 1
              //         ? Colors.blue.withOpacity(0.2)
              //         : null,
              //   ),
              //   child: const Text('Chord Example'),
              // ),
              // OutlinedButton(
              //   onPressed:
              //       _currentExampleIndex == 2 ? null : () => _changeExample(2),
              //   style: OutlinedButton.styleFrom(
              //     backgroundColor: _currentExampleIndex == 2
              //         ? Colors.blue.withOpacity(0.2)
              //         : null,
              //   ),
              //   child: const Text('Arpeggio'),
              // ),
            ],
          ),
        ],
      ),
    );
  }

  void _changeExample(int index) {
    // Stop any current playback
    _sheetMusicKey.currentState?.stopMidi();

    setState(() {
      _currentExampleIndex = index;
      _isPlaying = false;
    });
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isPlaying = true;
                  });
                  _sheetMusicKey.currentState?.playMidi();
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              ElevatedButton.icon(
                onPressed: _isPlaying
                    ? () {
                        setState(() {
                          _isPlaying = false;
                        });
                        _sheetMusicKey.currentState?.pauseMidi();
                      }
                    : null,
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
              ),
              ElevatedButton.icon(
                onPressed: _isPlaying
                    ? () {
                        setState(() {
                          _isPlaying = false;
                        });
                        _sheetMusicKey.currentState?.stopMidi();
                      }
                    : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Tempo: '),
              Expanded(
                child: Slider(
                  min: 60,
                  max: 200,
                  divisions: 14,
                  value: _tempo.toDouble(),
                  label: '$_tempo BPM',
                  onChanged: (value) {
                    setState(() {
                      _tempo = value.round();
                      _sheetMusicState.setTempo(_tempo);
                    });
                  },
                ),
              ),
              Text('$_tempo BPM'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Highlight Color: '),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _colorOption(Colors.green),
                      _colorOption(Colors.red),
                      _colorOption(Colors.blue),
                      _colorOption(Colors.orange),
                      _colorOption(Colors.purple),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SoundFontType>(
            decoration: const InputDecoration(
              labelText: 'SoundFont',
              border: OutlineInputBorder(),
            ),
            value: _selectedSoundFont,
            onChanged: (SoundFontType? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedSoundFont = newValue;
                  // Need to reload the page to change soundfont
                  _showRestartDialog();
                });
              }
            },
            items: SoundFontType.values
                .map<DropdownMenuItem<SoundFontType>>((SoundFontType font) {
              return DropdownMenuItem<SoundFontType>(
                value: font,
                child: Text(font.displayName),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _colorOption(Color color) {
    final isSelected = _highlightColor == color;

    return GestureDetector(
      onTap: () {
        setState(() {
          _highlightColor = color;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.black : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }

  List<Measure> _createCMajorScaleMeasures() {
    // Create a C major scale in 4/4 time
    return [
      Measure([
        // First measure: C4, D4, E4, F4
        Clef.alto(),
        KeySignature.dMajor(),
        TimeSignature.fourFour(),
        Note(Pitch.c4, noteDuration: NoteDuration.quarter),
        Note(Pitch.d4, noteDuration: NoteDuration.quarter),
        Note(Pitch.e4, noteDuration: NoteDuration.quarter),
        Note(Pitch.e4, noteDuration: NoteDuration.quarter),
      ]),
      // Measure([
      //   const Note(Pitch.g4, noteDuration: NoteDuration.whole),
      // ]),
      Measure([
        Rest(RestType.quarter),
        Note(Pitch.f4, noteDuration: NoteDuration.half),
        Rest(RestType.quarter),
      ])
    ];
  }

  void _showRestartDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Restart Required'),
          content: const Text(
              'Changing the soundfont requires restarting the application to take effect.'),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
