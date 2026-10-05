import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:score_layout/score_layout.dart';

/// A line drawn over the sheet, which is the caret or the playhead.
@immutable
final class SheetLine {
  const SheetLine({required this.color, this.width = 0.2})
    : assert(width >= 0, 'a line has no width under zero');

  final Color color;

  /// In staff spaces, so the line grows with the zoom. Zero draws no line.
  final double width;

  SheetLine copyWith({Color? color, double? width}) =>
      SheetLine(color: color ?? this.color, width: width ?? this.width);

  @override
  bool operator ==(Object other) =>
      other is SheetLine && other.color == color && other.width == width;

  @override
  int get hashCode => Object.hash(color, width);

  @override
  String toString() => 'SheetLine(color: $color, width: $width)';
}

/// How the sheet marks notes, which are the selected ones or the sounding
/// ones. A box behind them, a border around the box and another ink are
/// each drawn when given, so a style may mix them.
///
/// The box and its border lie under the notes and the staff lines, so a
/// fill of any colour leaves them to read. Boxes that overlap make one
/// shape with one border around it.
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
  }) : assert(borderWidth >= 0, 'a border has no width under zero'),
       assert(radius >= 0, 'a corner has no radius under zero');

  /// The colour of the box behind the notes. Null draws no box.
  final Color? fill;

  /// The colour of the line around the box. Null draws no line.
  final Color? border;

  /// The line lies inside the box, so a wider one takes no more room. Zero
  /// draws no line.
  final double borderWidth;

  /// How round the corners of the box are.
  final double radius;

  /// How far the box reaches past the notes on every side. Under zero it
  /// makes the box smaller than the notes.
  final double padding;

  /// The colour the marked item is drawn in again. Null leaves it in its
  /// own. The ink reaches what the item owns. For an event that is the
  /// chord or the rest with its stem, accidentals and dots, and for one
  /// note of a chord it is the head. A selected range has a box and no
  /// ink, since it is a region of the sheet and not a list of notes.
  final Color? ink;

  /// This style with the given parts replaced. A null leaves a part as it
  /// is, so this cannot take a colour away.
  SheetHighlight copyWith({
    Color? fill,
    Color? border,
    double? borderWidth,
    double? radius,
    double? padding,
    Color? ink,
  }) => SheetHighlight(
    fill: fill ?? this.fill,
    border: border ?? this.border,
    borderWidth: borderWidth ?? this.borderWidth,
    radius: radius ?? this.radius,
    padding: padding ?? this.padding,
    ink: ink ?? this.ink,
  );

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

  @override
  String toString() =>
      'SheetHighlight(fill: $fill, border: $border, '
      'borderWidth: $borderWidth, radius: $radius, padding: $padding, '
      'ink: $ink)';
}

/// The sheet's colours and the look of what is drawn over it. Changing them
/// repaints and never lays out.
///
/// Layout gives each drawable an [InkRole], which is its kind of mark, and
/// the palette maps roles to colours. The cursor, the selection and
/// playback have styles of their own.
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
    this.inks = const {},
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

  /// Every mark that has no colour of its own in [inks], but for the staff
  /// lines and a note out of range.
  final Color ink;

  /// The staff lines, when [inks] has no colour for them.
  final Color staffLines;

  /// A note the part's instrument cannot play, when [inks] has no colour
  /// for it.
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

  /// A colour for one kind of mark, which it takes in place of [ink],
  /// [staffLines] or [outOfRange]. Two palettes are compared by what their
  /// maps hold, so give a new map for a new colour and leave this one as it
  /// is.
  final Map<InkRole, Color> inks;

  /// The colour a mark of [role] is drawn in.
  Color colorOf(InkRole role) =>
      inks[role] ??
      switch (role) {
        InkRole.staffLine => staffLines,
        InkRole.outOfRange => outOfRange,
        _ => ink,
      };

  /// This palette with the given parts replaced. A null leaves a part as it
  /// is, so this cannot take the [paper] away. A map of [inks] replaces the
  /// whole map.
  SheetPalette copyWith({
    Color? ink,
    Color? staffLines,
    Color? outOfRange,
    SheetLine? cursor,
    SheetHighlight? selection,
    SheetHighlight? playback,
    SheetLine? playhead,
    Color? paper,
    Map<InkRole, Color>? inks,
  }) => SheetPalette(
    ink: ink ?? this.ink,
    staffLines: staffLines ?? this.staffLines,
    outOfRange: outOfRange ?? this.outOfRange,
    cursor: cursor ?? this.cursor,
    selection: selection ?? this.selection,
    playback: playback ?? this.playback,
    playhead: playhead ?? this.playhead,
    paper: paper ?? this.paper,
    inks: inks ?? this.inks,
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
      other.paper == paper &&
      mapEquals(other.inks, inks);

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
    Object.hashAllUnordered(
      inks.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}
