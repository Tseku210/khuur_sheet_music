/// Enum representing different types of rests in sheet music.
enum RestType {
  whole(_wholePathKey, offsetSpace: 1, duration: 4),
  half(_halfPathKey, duration: 2),
  quarter(_quarterPathKey, duration: 1),
  eighth(_eighthPathKey, duration: 0.5),
  sixteenth(_sixteenthPathKey, duration: 0.25),
  thirtySecond(_thirtySecondPathKey, duration: 0.125),
  sixtyFourth(_sixtyFourthPathKey, duration: 0.0625),
  hundredTwentyEighth(_hundredTwentyEighthPathKey, duration: 0.03125);

  const RestType(
    this.pathKey, {
    this.offsetSpace = 0,
    required this.duration,
  });

  /// The key used to retrieve the path of the rest symbol.
  final String pathKey;

  /// The number of offset spaces for the rest symbol.
  final int offsetSpace;

  /// The duration of the rest in beats (where a quarter note is 1.0 beats).
  final double duration;

  static const _wholePathKey = 'uniE4E3';
  static const _halfPathKey = 'uniE4E4';
  static const _quarterPathKey = 'uniE4E5';
  static const _eighthPathKey = 'uniE4E6';
  static const _sixteenthPathKey = 'uniE4E7';
  static const _thirtySecondPathKey = 'uniE4E8';
  static const _sixtyFourthPathKey = 'uniE4E9';
  static const _hundredTwentyEighthPathKey = 'uniE4EA';
}
