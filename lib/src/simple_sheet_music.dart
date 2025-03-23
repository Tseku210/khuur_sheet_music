import 'dart:convert';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';
import 'package:simple_sheet_music/src/midi/midi_playback_mixin.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/sheet_music_metrics.dart';
import 'package:simple_sheet_music/src/sheet_music_renderer.dart';
import 'package:xml/xml.dart';

import 'music_objects/key_signature/keysignature_type.dart';
import 'sheet_music_layout.dart';

typedef OnTapMusicObjectCallback = void Function(
  MusicalSymbol musicObject,
  Offset offset,
);

/// The `SimpleSheetMusic` widget is used to display sheet music.
/// It takes a list of `Staff` objects, an initial clef, and other optional parameters to customize the appearance of the sheet music.
class SimpleSheetMusic extends StatefulWidget {
  const SimpleSheetMusic({
    super.key,
    required this.measures,
    this.initialClefType = ClefType.treble,
    this.initialKeySignatureType = KeySignatureType.cMajor,
    this.initialTimeSignatureType = TimeSignatureType.twoFour,
    this.height = 400.0,
    this.width = 400.0,
    this.lineColor = Colors.black,
    this.fontType = FontType.bravura,
    this.tempo = 120,
    this.enableMidi = false,
    this.soundFontType = SoundFontType.touhou,
    this.customSoundFontPath,
    this.highlightColor = Colors.red,
    this.debug = false,
    this.onTap,
  });

  /// The list of measures to be displayed.
  final List<Measure> measures;

  /// Receive maximum width and height so as not to break the aspect ratio of the score.
  final double height;

  /// Receive maximum width and height so as not to break the aspect ratio of the score.
  final double width;

  /// The font type to be used for rendering the sheet music.
  final FontType fontType;

  /// The initial clef  for the sheet music.
  final ClefType initialClefType;

  /// The initial keySignature for the sheet music.
  final KeySignatureType initialKeySignatureType;

  /// The initial timeSignature for the sheet music.
  final TimeSignatureType initialTimeSignatureType;

  /// The tempo in beats per minute (BPM).
  /// This affects timing and playback speed.
  final int tempo;

  /// Whether to enable MIDI playback.
  final bool enableMidi;

  /// The type of soundfont to use for MIDI playback.
  final SoundFontType soundFontType;

  /// Optional custom path to a soundfont file for MIDI playback.
  /// If provided, this will override the soundFontType.
  final String? customSoundFontPath;

  /// The color to use for highlighting the current note.
  final Color highlightColor;

  final Color lineColor;

  /// Whether to render outline boxes around music objects
  final bool debug;

  /// Callback function that is called when a musical symbol is tapped
  final OnTapMusicObjectCallback? onTap;

  @override
  SimpleSheetMusicState createState() => SimpleSheetMusicState();
}

/// The state class for the SimpleSheetMusic widget.
///
/// This class manages the state of the SimpleSheetMusic widget and handles the initialization,
/// font asset loading, and building of the widget.
class SimpleSheetMusicState extends State<SimpleSheetMusic>
    with MidiPlaybackMixin {
  late final GlyphPaths glyphPath;
  late final GlyphMetadata metadata;
  late final Future<void> _future;
  late SheetMusicLayout? _layout;

  FontType get fontType => widget.fontType;

  @override
  bool get enableMidi => widget.enableMidi;

  @override
  int get tempo => widget.tempo;

  @override
  SoundFontType get soundFontType => widget.soundFontType;

  @override
  String? get customSoundFontPath => widget.customSoundFontPath;

  @override
  Color get highlightColor => widget.highlightColor;

  @override
  List<Measure> get measures => widget.measures;

  @override
  TimeSignatureType get initialTimeSignatureType =>
      widget.initialTimeSignatureType;

  @override
  void initState() {
    _future = _initialize();
    super.initState();
  }

  Future<void> _initialize() async {
    await load();
    await initializeMidi();
  }

  Future<void> load() async {
    final xml = await rootBundle.loadString(fontType.svgPath);
    final document = XmlDocument.parse(xml);
    final allGlyphs = document.findAllElements('glyph').toSet();
    glyphPath = GlyphPaths(allGlyphs);
    final json = await rootBundle.loadString(fontType.metadataPath);
    metadata = GlyphMetadata(jsonDecode(json) as Map<String, dynamic>);
  }

  void _handleTap(TapDownDetails details) {
    if (_layout == null || widget.onTap == null) {
      return;
    }

    // Convert the tap position to canvas coordinates
    final tapPosition = details.localPosition / _layout!.canvasScale;

    // Find the tapped symbol by testing each staff
    for (final staff in _layout!.staffRenderers) {
      final hitSymbol = staff.hitTest(tapPosition);
      if (hitSymbol != null) {
        widget.onTap!(hitSymbol.musicalSymbol, tapPosition);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetSize = Size(widget.width, widget.height);
    return FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final metricsBuilder = SheetMusicMetrics(
          widget.measures,
          widget.initialClefType,
          widget.initialKeySignatureType,
          widget.initialTimeSignatureType,
          metadata,
          glyphPath,
          tempo: widget.tempo,
        );

        _layout = SheetMusicLayout(
          metricsBuilder,
          widget.lineColor,
          widgetWidth: widget.width,
          widgetHeight: widget.height,
          symbolPositionCallback: registerSymbolPosition,
          debug: widget.debug,
        );

        // Create the sheet music renderer without highlighting
        final renderer = SheetMusicRenderer(_layout!);

        return Stack(
          children: [
            // The sheet music is rendered once and doesn't change
            GestureDetector(
              onTapDown: _handleTap,
              child: CustomPaint(
                size: targetSize,
                painter: renderer,
              ),
            ),
            // The overlay that highlights the current note
            if (highlightedSymbolId != null)
              HighlightOverlay(
                highlightedSymbolId: highlightedSymbolId!,
                symbolPosition: getSymbolPosition(highlightedSymbolId),
                highlightColor: currentHighlightColor,
                canvasScale: _layout!.canvasScale,
              ),
          ],
        );
      },
    );
  }
}

/// A widget that draws a highlight around a musical symbol
class HighlightOverlay extends StatelessWidget {
  const HighlightOverlay({
    super.key,
    required this.highlightedSymbolId,
    required this.symbolPosition,
    required this.highlightColor,
    required this.canvasScale,
  });

  final String highlightedSymbolId;
  final Rect? symbolPosition;
  final Color highlightColor;
  final double canvasScale;

  @override
  Widget build(BuildContext context) {
    if (symbolPosition == null) {
      return const SizedBox.shrink();
    }

    // Scale the rect to match the canvas scale
    final scaledRect = Rect.fromLTRB(
      symbolPosition!.left * canvasScale,
      symbolPosition!.top * canvasScale,
      symbolPosition!.right * canvasScale,
      symbolPosition!.bottom * canvasScale,
    );

    return Positioned.fromRect(
      rect: scaledRect,
      child: CustomPaint(
        painter: HighlightPainter(highlightColor),
      ),
    );
  }
}

/// A custom painter that draws a highlight
class HighlightPainter extends CustomPainter {
  HighlightPainter(this.highlightColor);

  final Color highlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Add some padding to the highlight
    final highlightRect = Rect.fromLTRB(
      -4,
      -4,
      size.width + 4,
      size.height + 4,
    );

    // Draw a rounded rectangle with a semi-transparent fill
    final paint = Paint()
      ..color = highlightColor.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(highlightRect, const Radius.circular(4)),
      paint,
    );

    // Draw a border
    final borderPaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(highlightRect, const Radius.circular(4)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(HighlightPainter oldDelegate) {
    return oldDelegate.highlightColor != highlightColor;
  }
}
