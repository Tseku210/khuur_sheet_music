import 'package:simple_sheet_music/src/music_objects/notes/noteflag_type.dart';
import 'package:simple_sheet_music/src/music_objects/notes/notehead_type.dart';

/// Enum representing the duration of a musical note.
enum NoteDuration {
  /// Whole note duration.
  whole(hasStem: false, hasFlag: false, duration: 4),

  /// Half note duration.
  half(hasFlag: false, duration: 2),

  /// Quarter note duration.
  quarter(hasFlag: false, duration: 1),

  /// Eighth note duration.
  eighth(duration: 0.5),

  /// Sixteenth note duration.
  sixteenth(duration: 0.25),

  /// Thirty-second note duration.
  thirtySecond(duration: 0.125),

  /// Sixty-fourth note duration.
  sixtyFourth(duration: 0.0625),

  /// Hundred twenty-eighth note duration.
  hundredsTwentyEighth(duration: 0.03125);

  /// Constructs a NoteDuration with the given parameters.
  const NoteDuration({
    this.hasStem = true,
    this.hasFlag = true,
    required this.duration,
  });

  /// Whether the note duration has a stem.
  final bool hasStem;

  /// Whether the note duration has a flag.
  final bool hasFlag;

  /// The duration of the note in beats (where a quarter note is 1.0 beats).
  final double duration;

  /// Returns the corresponding NoteHeadType for the note duration.
  NoteHeadType get noteHeadType {
    switch (this) {
      case NoteDuration.whole:
        return NoteHeadType.whole;
      case NoteDuration.half:
        return NoteHeadType.half;
      case NoteDuration.quarter:
      case NoteDuration.eighth:
      case NoteDuration.sixteenth:
      case NoteDuration.thirtySecond:
      case NoteDuration.sixtyFourth:
      case NoteDuration.hundredsTwentyEighth:
        return NoteHeadType.black;
    }
  }

  /// Returns the corresponding NoteFlagType for the note duration.
  NoteFlagType? get noteFlagType {
    switch (this) {
      case NoteDuration.whole:
      case NoteDuration.half:
      case NoteDuration.quarter:
        return null;
      case NoteDuration.eighth:
        return NoteFlagType.flag8th;
      case NoteDuration.sixteenth:
        return NoteFlagType.flag16th;
      case NoteDuration.thirtySecond:
        return NoteFlagType.flag32nd;
      case NoteDuration.sixtyFourth:
        return NoteFlagType.flag64th;
      case NoteDuration.hundredsTwentyEighth:
        return NoteFlagType.flag128th;
    }
  }
}
