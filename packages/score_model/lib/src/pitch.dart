/// Spelled pitch, intervals, keys and clefs.
///
/// A pitch is a letter, an alteration and an octave, never a MIDI number or a
/// staff line. Spelling is what makes diatonic transposition, enharmonic
/// choice and automatic accidentals well defined. Staff position is derived
/// from pitch through a clef, and MIDI is derived for playback.
library;

/// The seven letter names. [semitones] is the offset above C.
enum Step {
  c(0),
  d(2),
  e(4),
  f(5),
  g(7),
  a(9),
  b(11);

  Step(this.semitones);

  final int semitones;
}

/// A chromatic alteration in quarter tones: sharp is +2, flat is −2, and the
/// odd values are the quarter-tone accidentals the Maestro feature list asks
/// for. Range −4 (double flat) to +4 (double sharp).
extension type const Alter._(int quarterTones) {
  /// Validates the range; the only way to build an arbitrary value.
  factory Alter.fromQuarterTones(int quarterTones) {
    if (quarterTones < -4 || quarterTones > 4) {
      throw RangeError.range(quarterTones, -4, 4, 'quarterTones');
    }
    return Alter._(quarterTones);
  }

  static const doubleFlat = Alter._(-4);
  static const threeQuarterFlat = Alter._(-3);
  static const flat = Alter._(-2);
  static const quarterFlat = Alter._(-1);
  static const natural = Alter._(0);
  static const quarterSharp = Alter._(1);
  static const sharp = Alter._(2);
  static const threeQuarterSharp = Alter._(3);
  static const doubleSharp = Alter._(4);

  bool get isQuarterTone => quarterTones.isOdd;
}

/// A letter plus alteration, without octave. Roots and basses of chord
/// symbols, and key-signature members.
final class PitchName {
  const PitchName(this.step, [this.alter = Alter.natural]);

  final Step step;
  final Alter alter;

  @override
  bool operator ==(Object other) =>
      other is PitchName && other.step == step && other.alter == alter;

  @override
  int get hashCode => Object.hash(step, alter);
}

/// A spelled pitch. In the model a note's pitch is the *concert, sounding*
/// pitch. Written pitch (after instrument transposition and 8va lines) is
/// derived for display by `StaffView.writtenPitch`.
final class Pitch implements Comparable<Pitch> {
  const Pitch(this.step, this.octave, [this.alter = Alter.natural]);

  /// Parses scientific pitch notation: `C4`, `Bb3`, `F#5`, `Ebb2`, `C+4`
  /// (quarter sharp), `Bd4` (quarter flat). Throws [FormatException].
  factory Pitch.parse(String text) {
    final match = RegExp(r'^([A-Ga-g])(bb|b|d|##|#|\+|x)?(-?\d)$')
        .firstMatch(text.trim());
    if (match == null) {
      throw FormatException('Not a pitch', text);
    }
    final step = Step.values.byName(match[1]!.toLowerCase());
    final alter = switch (match[2]) {
      null => Alter.natural,
      'bb' => Alter.doubleFlat,
      'b' => Alter.flat,
      'd' => Alter.quarterFlat,
      '+' => Alter.quarterSharp,
      '#' => Alter.sharp,
      '##' || 'x' => Alter.doubleSharp,
      _ => throw FormatException('Unknown accidental', text),
    };
    return Pitch(step, int.parse(match[3]!), alter);
  }

  final Step step;
  final int octave;
  final Alter alter;

  /// Position on the diatonic ladder: C4 is 28, D4 is 29. Staff positions
  /// and diatonic transposition work in these units.
  int get diatonic => octave * 7 + step.index;

  /// Pitch in quarter tones above C−1.
  int get _quarterTones =>
      (octave + 1) * 24 + step.semitones * 2 + alter.quarterTones;

  /// MIDI key, rounding quarter tones down; [cents] holds the remainder.
  int get midiKey {
    final q = _quarterTones;
    return (q - q % 2) ~/ 2;
  }

  /// 0 or 50. Playback turns this into pitch bend.
  int get cents => (_quarterTones % 2) * 50;

  /// Transposes by a spelled interval: the letter moves by
  /// [Interval.steps], and the alteration is whatever makes the distance
  /// exactly [Interval.semitones]. C4 up a major third is E4; C4 up a
  /// diminished fourth is Fb4.
  Pitch transpose(Interval interval) {
    final target = diatonic + interval.steps;
    final step = Step.values[target % 7];
    final octave = (target - target % 7) ~/ 7;
    final natural = Pitch(step, octave);
    final quarterTones =
        _quarterTones + interval.semitones * 2 - natural._quarterTones;
    return Pitch(step, octave, Alter.fromQuarterTones(quarterTones));
  }

  PitchName get name => PitchName(step, alter);

  @override
  int compareTo(Pitch other) {
    final byHeight = _quarterTones.compareTo(other._quarterTones);
    return byHeight != 0 ? byHeight : diatonic.compareTo(other.diatonic);
  }

  @override
  bool operator ==(Object other) =>
      other is Pitch &&
      other.step == step &&
      other.octave == octave &&
      other.alter == alter;

  @override
  int get hashCode => Object.hash(step, octave, alter);

  @override
  String toString() {
    final accidental = switch (alter.quarterTones) {
      -4 => 'bb',
      -3 => 'db',
      -2 => 'b',
      -1 => 'd',
      0 => '',
      1 => '+',
      2 => '#',
      3 => '#+',
      _ => 'x',
    };
    return '${step.name.toUpperCase()}$accidental$octave';
  }
}

/// A spelled interval: [steps] letter names and [semitones] half steps. An
/// augmented second (1, 3) and a minor third (2, 3) are different intervals.
final class Interval {
  const Interval(this.steps, this.semitones);

  static const unison = Interval(0, 0);
  static const minorSecond = Interval(1, 1);
  static const majorSecond = Interval(1, 2);
  static const minorThird = Interval(2, 3);
  static const majorThird = Interval(2, 4);
  static const perfectFourth = Interval(3, 5);
  static const perfectFifth = Interval(4, 7);
  static const octave = Interval(7, 12);

  final int steps;
  final int semitones;

  Interval operator -() => Interval(-steps, -semitones);

  Interval operator +(Interval other) =>
      Interval(steps + other.steps, semitones + other.semitones);

  Interval operator *(int times) => Interval(steps * times, semitones * times);

  @override
  bool operator ==(Object other) =>
      other is Interval && other.steps == steps && other.semitones == semitones;

  @override
  int get hashCode => Object.hash(steps, semitones);
}

enum KeyMode { none, major, minor }

/// A conventional key signature, as a position on the circle of fifths:
/// −7 (7 flats) to +7 (7 sharps). Stored in concert pitch on the measure
/// column; a transposing part's written key is derived.
final class KeySignature {
  const KeySignature(this.fifths, [this.mode = KeyMode.none])
    : assert(fifths >= -7 && fifths <= 7, 'fifths in -7..7');

  static const cMajor = KeySignature(0, KeyMode.major);

  final int fifths;
  final KeyMode mode;

  static const List<Step> _sharpOrder = [
    Step.f,
    Step.c,
    Step.g,
    Step.d,
    Step.a,
    Step.e,
    Step.b,
  ];

  /// The alteration this key applies to [step] with no accidental.
  Alter alterFor(Step step) {
    if (fifths > 0 && _sharpOrder.take(fifths).contains(step)) {
      return Alter.sharp;
    }
    if (fifths < 0 && _sharpOrder.reversed.take(-fifths).contains(step)) {
      return Alter.flat;
    }
    return Alter.natural;
  }

  /// The key a part reads when its instrument sounds [interval] away from
  /// written pitch. B♭ clarinet (sounds a major second lower) in concert
  /// C reads D. A key past seven sharps or flats is respelled
  /// enharmonically, so concert C♯ on that clarinet reads E♭, not D♯.
  KeySignature transpose(Interval interval) {
    // Where C major's written tonic sits on the circle of fifths is how far
    // every key moves.
    final tonic = const Pitch(Step.c, 4).transpose(-interval);
    final shift =
        _sharpOrder.indexOf(tonic.step) -
        1 +
        7 * (tonic.alter.quarterTones ~/ 2);
    var written = fifths + shift;
    if (written > 7) {
      written -= 12;
    } else if (written < -7) {
      written += 12;
    }
    return KeySignature(written, mode);
  }

  @override
  bool operator ==(Object other) =>
      other is KeySignature && other.fifths == fifths && other.mode == mode;

  @override
  int get hashCode => Object.hash(fifths, mode);

  @override
  String toString() => fifths >= 0 ? '$fifths#' : '${-fifths}b';
}

enum ClefSign { g, f, c, percussion }

/// Clefs from the Maestro feature list. A clef maps staff steps to written
/// pitch. Staff step 0 is the bottom line of the staff, 1 the first space,
/// and so on; negative steps are below the staff.
///
/// A drum staff and a one-line percussion staff both use [percussion]; the
/// line count lives on `Staff.lines`.
enum Clef {
  treble(ClefSign.g, 2),
  treble8vb(ClefSign.g, 2, octave: -1),
  treble8va(ClefSign.g, 2, octave: 1),
  bass(ClefSign.f, 4),
  bass8vb(ClefSign.f, 4, octave: -1),
  soprano(ClefSign.c, 1),
  mezzoSoprano(ClefSign.c, 2),
  alto(ClefSign.c, 3),
  tenor(ClefSign.c, 4),
  baritoneC(ClefSign.c, 5),
  baritoneF(ClefSign.f, 3),
  percussion(ClefSign.percussion, 3);

  Clef(this.sign, this.line, {this.octave = 0});

  final ClefSign sign;

  /// Staff line the clef sits on, 1 = bottom line.
  final int line;

  /// Octave transposition of the clef itself (treble 8vb for tenor voice).
  final int octave;

  /// Diatonic number of the pitch on the clef's own line. G clef marks G4,
  /// F clef F3, C clef C4. The percussion clef sits on the middle line and
  /// the staff reads like treble, so it marks B4.
  int get _anchor =>
      switch (sign) {
        ClefSign.g => const Pitch(Step.g, 4).diatonic,
        ClefSign.f => const Pitch(Step.f, 3).diatonic,
        ClefSign.c => const Pitch(Step.c, 4).diatonic,
        ClefSign.percussion => const Pitch(Step.b, 4).diatonic,
      } +
      octave * 7;

  /// The natural written pitch at [staffStep]. The caller applies the key
  /// and any accidental; `Score.pitchForStaffStep` does all of that.
  Pitch naturalAt(int staffStep) {
    final diatonic = _anchor + staffStep - 2 * (line - 1);
    return Pitch(Step.values[diatonic % 7], (diatonic - diatonic % 7) ~/ 7);
  }

  /// The staff step a written pitch sits on.
  int staffStepOf(Pitch written) => written.diatonic - _anchor + 2 * (line - 1);
}

/// How a transpose command moves pitches.
sealed class Transposition {
  const Transposition();

  /// By a fixed spelled interval, the same for every note.
  const factory Transposition.interval(Interval interval) = ByInterval;

  /// By scale steps inside the key in effect at each note: in F major, A up
  /// one step is B♭, and F♯ up one step is G♯ (chromatic alterations relative
  /// to the key are kept).
  const factory Transposition.diatonic(int steps) = ByScaleSteps;

  /// By semitones, respelled to suit the key in effect at each note: sharps
  /// in sharp keys, flats in flat keys.
  const factory Transposition.chromatic(int semitones) = BySemitones;
}

final class ByInterval extends Transposition {
  const ByInterval(this.interval);

  final Interval interval;
}

final class ByScaleSteps extends Transposition {
  const ByScaleSteps(this.steps);

  final int steps;
}

final class BySemitones extends Transposition {
  const BySemitones(this.semitones);

  final int semitones;
}
