/// Enum representing different types of accidentals in music notation.
enum Accidental {
  flat(_flatPathKey, -1), // Represents a flat accidental.
  natural(_naturalPathKey, 0), // Represents a natural accidental.
  sharp(_sharpPathKey, 1), // Represents a sharp accidental.
  doubleSharp(_doubleSharpPathKey, 2), // Represents a double sharp accidental.
  doubleFlat(_doubleFlatPathKey, -2); // Represents a double flat accidental.

  /// The path key used to retrieve the corresponding symbol for the accidental.
  const Accidental(this.pathKey, this.semitones);

  /// The path key for the flat accidental symbol.
  final String pathKey;

  /// How many semitones the accidental moves the natural pitch.
  final int semitones;

  /// The path key for the flat accidental symbol.
  static const _flatPathKey = 'uniE260';

  /// The path key for the natural accidental symbol.
  static const _naturalPathKey = 'uniE261';

  /// The path key for the sharp accidental symbol.
  static const _sharpPathKey = 'uniE262';

  /// The path key for the double sharp accidental symbol.
  static const _doubleSharpPathKey = 'uniE263';

  /// The path key for the double flat accidental symbol.
  static const _doubleFlatPathKey = 'uniE264';
}
