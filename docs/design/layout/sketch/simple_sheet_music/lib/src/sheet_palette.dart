import 'package:flutter/material.dart';
import 'package:score_layout/score_layout.dart';

/// The sheet's colours. Changing them repaints and never lays out.
///
/// Layout assigns each drawable an [InkRole]; the palette maps roles to
/// colours. Overlays (cursor, selection, playback) have their own colours.
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
  });

  /// Derived from the ambient theme's colour scheme, so the sheet follows
  /// light and dark mode with no app code.
  factory SheetPalette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetPalette(
      ink: scheme.onSurface,
      staffLines: scheme.onSurface.withValues(alpha: 0.8),
      outOfRange: scheme.error,
      cursor: scheme.primary,
      selection: scheme.primary.withValues(alpha: 0.18),
      playback: scheme.tertiary,
      playhead: scheme.tertiary.withValues(alpha: 0.6),
    );
  }

  final Color ink;
  final Color staffLines;
  final Color outOfRange;
  final Color cursor;

  /// Fill behind selected items and ranges.
  final Color selection;

  /// Colour of the events sounding now.
  final Color playback;

  /// Colour of the moving playhead line.
  final Color playhead;

  Color colorOf(InkRole role) => switch (role) {
    InkRole.normal => ink,
    InkRole.staffLine => staffLines,
    InkRole.outOfRange => outOfRange,
  };

  @override
  bool operator ==(Object other) =>
      other is SheetPalette &&
      other.ink == ink &&
      other.staffLines == staffLines &&
      other.outOfRange == outOfRange &&
      other.cursor == cursor &&
      other.selection == selection &&
      other.playback == playback &&
      other.playhead == playhead;

  @override
  int get hashCode => Object.hash(
    ink,
    staffLines,
    outOfRange,
    cursor,
    selection,
    playback,
    playhead,
  );
}
