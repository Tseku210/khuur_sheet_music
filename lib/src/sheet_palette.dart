import 'package:flutter/material.dart';
import 'package:score_layout/score_layout.dart';

/// A line drawn over the sheet, which is the caret or the playhead.
@immutable
final class SheetLine {
  const SheetLine({required this.color, this.width = 0.2});

  final Color color;

  /// In staff spaces, so the line grows with the zoom.
  final double width;

  @override
  bool operator ==(Object other) =>
      other is SheetLine && other.color == color && other.width == width;

  @override
  int get hashCode => Object.hash(color, width);
}

/// How the sheet marks notes, which are the selected ones or the sounding
/// ones. A box behind them, a border around them and another ink are each
/// drawn when given, so a style may mix them.
///
/// Lengths are in staff spaces, so the mark grows with the zoom.
@immutable
final class SheetHighlight {
  const SheetHighlight({
    this.fill,
    this.border,
    this.borderWidth = 0.15,
    this.radius = 0,
    this.padding = 0,
    this.ink,
  });

  /// The colour of the box behind the notes. Null draws no box.
  final Color? fill;

  /// The colour of the line around the box. Null draws no line.
  final Color? border;

  /// The line lies inside the box, so a wider one takes no more room.
  final double borderWidth;

  /// How round the corners of the box are.
  final double radius;

  /// How far the box reaches past the notes on every side.
  final double padding;

  /// The colour the notes themselves are drawn in. Null leaves them in
  /// their own. A selected range has a box and no ink, since it is a region
  /// of the sheet and not a list of notes.
  final Color? ink;

  @override
  bool operator ==(Object other) =>
      other is SheetHighlight &&
      other.fill == fill &&
      other.border == border &&
      other.borderWidth == borderWidth &&
      other.radius == radius &&
      other.padding == padding &&
      other.ink == ink;

  @override
  int get hashCode =>
      Object.hash(fill, border, borderWidth, radius, padding, ink);
}

/// The sheet's colours and the look of what is drawn over it. Changing them
/// repaints and never lays out.
///
/// Layout gives each drawable an [InkRole], and the palette maps roles to
/// colours. The cursor, the selection and playback have styles of their
/// own.
@immutable
final class SheetPalette {
  const SheetPalette({
    required this.ink,
    required this.staffLines,
    required this.outOfRange,
    required this.cursor,
    required this.selection,
    required this.playback,
    required this.playhead,
    this.paper,
  });

  /// Derived from the ambient theme's colour scheme, so the sheet follows
  /// light and dark mode with no app code.
  factory SheetPalette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetPalette(
      ink: scheme.onSurface,
      staffLines: scheme.onSurface.withValues(alpha: 0.8),
      outOfRange: scheme.error,
      cursor: SheetLine(color: scheme.primary),
      selection: SheetHighlight(fill: scheme.primary.withValues(alpha: 0.18)),
      playback: SheetHighlight(ink: scheme.tertiary),
      playhead: SheetLine(color: scheme.tertiary.withValues(alpha: 0.6)),
    );
  }

  /// Notes, signatures, text and every other mark.
  final Color ink;

  final Color staffLines;

  /// A note the part's instrument cannot play.
  final Color outOfRange;

  /// The caret at the edit cursor.
  final SheetLine cursor;

  /// The selected items and ranges.
  final SheetHighlight selection;

  /// The events sounding now.
  final SheetHighlight playback;

  /// The moving playhead line.
  final SheetLine playhead;

  /// The colour behind the sheet, on screen and in an image the controller
  /// makes. Null draws none, so the sheet shows what lies under the view.
  final Color? paper;

  Color colorOf(InkRole role) => switch (role) {
    InkRole.staffLine => staffLines,
    InkRole.outOfRange => outOfRange,
    _ => ink,
  };

  /// This palette with the given parts replaced. A null leaves a part as it
  /// is, so this cannot take the [paper] away.
  SheetPalette copyWith({
    Color? ink,
    Color? staffLines,
    Color? outOfRange,
    SheetLine? cursor,
    SheetHighlight? selection,
    SheetHighlight? playback,
    SheetLine? playhead,
    Color? paper,
  }) => SheetPalette(
    ink: ink ?? this.ink,
    staffLines: staffLines ?? this.staffLines,
    outOfRange: outOfRange ?? this.outOfRange,
    cursor: cursor ?? this.cursor,
    selection: selection ?? this.selection,
    playback: playback ?? this.playback,
    playhead: playhead ?? this.playhead,
    paper: paper ?? this.paper,
  );

  @override
  bool operator ==(Object other) =>
      other is SheetPalette &&
      other.ink == ink &&
      other.staffLines == staffLines &&
      other.outOfRange == outOfRange &&
      other.cursor == cursor &&
      other.selection == selection &&
      other.playback == playback &&
      other.playhead == playhead &&
      other.paper == paper;

  @override
  int get hashCode => Object.hash(
    ink,
    staffLines,
    outOfRange,
    cursor,
    selection,
    playback,
    playhead,
    paper,
  );
}
