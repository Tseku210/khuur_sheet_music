/// Spelled pitch, intervals, keys and clefs.
///
/// A pitch is a letter, an alteration and an octave, never a MIDI number or a
/// staff line. Spelling is what makes diatonic transposition, enharmonic
/// choice and automatic accidentals well defined. Staff position is derived
/// from pitch through a clef, and MIDI is derived for playback.
library;

/// The seven letter names. [semitones] is the offset above C.
enum Step {
  /// C, 0 semitones above C.
  c(0),

  /// D, 2 semitones above C.
  d(2),

  /// E, 4 semitones above C.
  e(4),

  /// F, 5 semitones above C.
  f(5),

  /// G, 7 semitones above C.
  g(7),

  /// A, 9 semitones above C.
  a(9),

  /// B, 11 semitones above C.
  b(11);

  Step(this.semitones);

  /// Semitones above C in the same octave, 0 to 11.
  final int semitones;
}

/// A chromatic alteration in quarter tones: sharp is +2, flat is −2, and the
/// odd values are the quarter-tone accidentals. Range −4 (double flat) to +4
/// (double sharp).
extension type const Alter._(int quarterTones) {
  /// Validates the range; the only way to build an arbitrary value.
  factory Alter.fromQuarterTones(int quarterTones) {
    if (quarterTones < -4 || quarterTones > 4) {
      throw RangeError.range(quarterTones, -4, 4, 'quarterTones');
    }
    return Alter._(quarterTones);
  }

  /// Double flat, −4 quarter tones.
  static const doubleFlat = Alter._(-4);

  /// Three-quarter-tone flat, −3 quarter tones.
  static const threeQuarterFlat = Alter._(-3);

  /// Flat, −2 quarter tones.
  static const flat = Alter._(-2);

  /// Quarter-tone flat, −1 quarter tone.
  static const quarterFlat = Alter._(-1);

  /// No alteration, 0 quarter tones.
  static const natural = Alter._(0);

  /// Quarter-tone sharp, +1 quarter tone.
  static const quarterSharp = Alter._(1);

  /// Sharp, +2 quarter tones.
  static const sharp = Alter._(2);

  /// Three-quarter-tone sharp, +3 quarter tones.
  static const threeQuarterSharp = Alter._(3);

  /// Double sharp, +4 quarter tones.
  static const doubleSharp = Alter._(4);
}

/// A letter plus alteration, without octave. Roots and basses of chord
/// symbols, and key-signature members.
final class PitchName {
  /// [step] with [alter], natural by default.
  const PitchName(this.step, [this.alter = Alter.natural]);

  /// The letter.
  final Step step;

  /// The alteration of the letter.
  final Alter alter;

  @override
  bool operator ==(Object other) =>
      other is PitchName && other.step == step && other.alter == alter;

  @override
  int get hashCode => Object.hash(step, alter);
}

/// What a note head plays: a [Pitch] on a pitched staff, or a [Drum] of
/// its part's kit on a percussion staff. A chord holds one kind.
sealed class Tone implements Comparable<Tone> {
  const Tone();
}

/// A spelled pitch. In the model a note's pitch is the *concert, sounding*
/// pitch. Written pitch (after instrument transposition and 8va lines) is
/// derived for display in `StaffView.writtenPitches`.
final class Pitch extends Tone {
  /// [step] in [octave] with [alter], natural by default.
  const Pitch(this.step, this.octave, [this.alter = Alter.natural]);

  /// Parses scientific pitch notation: `C4`, `Bb3`, `F#5`, `Ebb2`, `C+4`
  /// (quarter sharp), `Bd4` (quarter flat). Throws [FormatException].
  factory Pitch.parse(String text) {
    final match = RegExp(r'^([A-Ga-g])(bb|db|b|d|##|#\+|#|\+|x)?(-?\d)$')
        .firstMatch(text.trim());
    if (match == null) {
      throw FormatException('Not a pitch', text);
    }
    final step = Step.values.byName(match[1]!.toLowerCase());
    final alter = switch (match[2]) {
      null => Alter.natural,
      'bb' => Alter.doubleFlat,
      'db' => Alter.threeQuarterFlat,
      'b' => Alter.flat,
      'd' => Alter.quarterFlat,
      '+' => Alter.quarterSharp,
      '#' => Alter.sharp,
      '#+' => Alter.threeQuarterSharp,
      '##' || 'x' => Alter.doubleSharp,
      _ => throw FormatException('Unknown accidental', text),
    };
    return Pitch(step, int.parse(match[3]!), alter);
  }

  /// The letter.
  final Step step;

  /// The octave in scientific numbering. Middle C is C4, and each octave
  /// starts at C, so B3 is the step below C4. Can be negative.
  final int octave;

  /// The alteration of the letter.
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
  /// diminished fourth is Fb4. When that would need more than a double
  /// sharp or flat, the same sound is spelled as [key] spells it, so
  /// concert E𝄪 on a B♭ clarinet reads G♯ rather than F with three sharps.
  Pitch transpose(Interval interval, {KeySignature key = KeySignature.cMajor}) {
    final quarterTones = _quarterTones + interval.semitones * 2;
    return _spelledAt(diatonic + interval.steps, quarterTones) ??
        _spell(quarterTones, key);
  }

  /// The letter and alteration, without the octave.
  PitchName get name => PitchName(step, alter);

  /// By sounding height, then by letter, and before any drum.
  @override
  int compareTo(Tone other) {
    if (other is! Pitch) {
      return -1;
    }
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

/// A sound of a percussion part's kit, named as in `Instrument.drums`. It is
/// drawn where the kit places it, with the kit's head, and plays the kit's
/// MIDI key.
final class Drum extends Tone {
  /// The kit sound named [name].
  const Drum(this.name);

  /// The sound's name in its part's kit, as in `Instrument.drums`.
  final String name;

  /// By name, and after any pitch.
  @override
  int compareTo(Tone other) => switch (other) {
    Drum(:final name) => this.name.compareTo(name),
    Pitch() => 1,
  };

  @override
  bool operator ==(Object other) => other is Drum && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// A spelled interval: [steps] letter names and [semitones] half steps. An
/// augmented second (1, 3) and a minor third (2, 3) are different intervals.
final class Interval {
  /// An interval of [steps] letters and [semitones] half steps. Negative
  /// values go down.
  const Interval(this.steps, this.semitones);

  /// The same pitch, (0, 0).
  static const unison = Interval(0, 0);

  /// A minor second, (1, 1).
  static const minorSecond = Interval(1, 1);

  /// A major second, (1, 2).
  static const majorSecond = Interval(1, 2);

  /// A minor third, (2, 3).
  static const minorThird = Interval(2, 3);

  /// A major third, (2, 4).
  static const majorThird = Interval(2, 4);

  /// A perfect fourth, (3, 5).
  static const perfectFourth = Interval(3, 5);

  /// A perfect fifth, (4, 7).
  static const perfectFifth = Interval(4, 7);

  /// An octave, (7, 12).
  static const octave = Interval(7, 12);

  /// Letter names moved. Negative is downward.
  final int steps;

  /// Half steps moved. Negative is downward.
  final int semitones;

  /// The same interval in the other direction.
  Interval operator -() => Interval(-steps, -semitones);

  /// The two intervals stacked, letters and half steps added.
  Interval operator +(Interval other) =>
      Interval(steps + other.steps, semitones + other.semitones);

  /// This interval stacked [times] times.
  Interval operator *(int times) => Interval(steps * times, semitones * times);

  @override
  bool operator ==(Object other) =>
      other is Interval && other.steps == steps && other.semitones == semitones;

  @override
  int get hashCode => Object.hash(steps, semitones);
}

/// The mode a key signature names, if any.
enum KeyMode {
  /// No mode stated. The signature gives only its sharps or flats.
  none,

  /// Major.
  major,

  /// Minor.
  minor,
}

/// A conventional key signature, as a position on the circle of fifths:
/// −7 (7 flats) to +7 (7 sharps). Stored in concert pitch on the measure
/// column; a transposing part's written key is derived.
final class KeySignature {
  /// [fifths] on the circle of fifths in [mode], unstated by default.
  /// Asserts that [fifths] is −7 to 7.
  const KeySignature(this.fifths, [this.mode = KeyMode.none])
    : assert(fifths >= -7 && fifths <= 7, 'fifths in -7..7');

  /// C major, no sharps or flats.
  static const cMajor = KeySignature(0, KeyMode.major);

  /// Sharps when positive, flats when negative, −7 to 7.
  final int fifths;

  /// The mode, or [KeyMode.none] when the key does not state one.
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

/// The symbol a [Clef] draws, which fixes the pitch on its line.
enum ClefSign {
  /// The G clef. Its line is G4.
  g,

  /// The F clef. Its line is F3.
  f,

  /// The C clef. Its line is middle C, C4.
  c,

  /// The neutral percussion clef. Its line reads as B4, as in treble.
  percussion,
}

/// A clef maps staff steps to written pitch. Staff step 0 is the bottom line
/// of the staff, 1 the first space, and so on; negative steps are below the
/// staff.
///
/// A drum staff and a one-line percussion staff both use [percussion]; the
/// line count lives on `Staff.lines`.
enum Clef {
  /// G clef on the second line.
  treble(ClefSign.g, 2),

  /// Treble clef with an 8 below, so the staff reads an octave lower.
  treble8vb(ClefSign.g, 2, octave: -1),

  /// Treble clef with an 8 above, so the staff reads an octave higher.
  treble8va(ClefSign.g, 2, octave: 1),

  /// F clef on the fourth line.
  bass(ClefSign.f, 4),

  /// Bass clef with an 8 below, so the staff reads an octave lower.
  bass8vb(ClefSign.f, 4, octave: -1),

  /// C clef on the first line.
  soprano(ClefSign.c, 1),

  /// C clef on the second line.
  mezzoSoprano(ClefSign.c, 2),

  /// C clef on the third line.
  alto(ClefSign.c, 3),

  /// C clef on the fourth line.
  tenor(ClefSign.c, 4),

  /// C clef on the fifth line.
  baritoneC(ClefSign.c, 5),

  /// F clef on the third line. Reads the same as [baritoneC].
  baritoneF(ClefSign.f, 3),

  /// Percussion clef on the middle line. The staff reads like treble.
  percussion(ClefSign.percussion, 3);

  Clef(this.sign, this.line, {this.octave = 0});

  /// The symbol drawn.
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
  /// and any accidental; `Score.toneForStaffStep` does all of that.
  Pitch naturalAt(int staffStep) =>
      _natural(_anchor + staffStep - 2 * (line - 1));

  /// The staff step of [written], the inverse of [naturalAt]. Ignores the
  /// alteration.
  int staffStepOf(Pitch written) => written.diatonic - _anchor + 2 * (line - 1);
}

/// How a transpose command moves pitches.
sealed class Transposition {
  const Transposition();

  /// By a fixed spelled interval, the same for every note.
  const factory Transposition.interval(Interval interval) = ByInterval;

  /// By staff positions. The note lands on the alteration in force at its
  /// new position, so it takes no accidental of its own: in F major, A up
  /// one step is B♭, F♯ up one step is G, and after a B♮ earlier in the bar
  /// A up one step is B♮. A move of 0 leaves the note as it is.
  const factory Transposition.diatonic(int steps) = ByScaleSteps;

  /// By semitones, spelled as a member of the key in effect at each note
  /// when one fits, else with sharps in C and sharp keys and flats in flat
  /// keys.
  const factory Transposition.chromatic(int semitones) = BySemitones;

  /// [pitch] moved by this transposition, where [inForce] is what the staff
  /// reads at the note. Null when the result needs more than a double sharp
  /// or flat.
  Pitch? apply(Pitch pitch, Alterations inForce) => switch (this) {
    ByInterval(:final interval) => _spelledAt(
      pitch.diatonic + interval.steps,
      pitch._quarterTones + interval.semitones * 2,
    ),
    ByScaleSteps(steps: 0) => pitch,
    ByScaleSteps(:final steps) => _altered(
      pitch.diatonic + steps,
      inForce.at(pitch.diatonic + steps).quarterTones,
    ),
    BySemitones(:final semitones) => _spell(
      pitch._quarterTones + semitones * 2,
      inForce.key,
    ),
  };
}

/// The alteration each staff position reads at one point of a bar. A
/// position takes the alteration of the last note before the point that
/// sits on it, and the key's when there is none. Positions count as
/// [Pitch.diatonic] does, so an accidental holds in its own octave only.
final class Alterations {
  /// What a staff in [key] reads at the start of a bar.
  const Alterations(this.key) : _held = const {};

  const Alterations._(this.key, this._held);

  /// The key signature the staff reads.
  final KeySignature key;

  final Map<int, Alter> _held;

  /// The alteration in force at [position].
  Alter at(int position) =>
      _held[position] ?? key.alterFor(Step.values[position % 7]);

  /// What the staff reads after a note at [pitch].
  Alterations after(Pitch pitch) => at(pitch.diatonic) == pitch.alter
      ? this
      : Alterations._(key, {..._held, pitch.diatonic: pitch.alter});
}

Pitch _natural(int diatonic) =>
    Pitch(Step.values[diatonic % 7], (diatonic - diatonic % 7) ~/ 7);

Pitch? _altered(int diatonic, int quarterTones) {
  if (quarterTones.abs() > 4) {
    return null;
  }
  final natural = _natural(diatonic);
  return Pitch(natural.step, natural.octave, Alter._(quarterTones));
}

/// The pitch [quarterTones] above C−1 written on the letter at [diatonic].
Pitch? _spelledAt(int diatonic, int quarterTones) =>
    _altered(diatonic, quarterTones - _natural(diatonic)._quarterTones);

Pitch _spell(int quarterTones, KeySignature key) {
  final degree = quarterTones % 24;
  final below =
      ((quarterTones - degree) ~/ 24 - 1) * 7 +
      Step.values.lastIndexWhere((step) => step.semitones * 2 <= degree);
  final inKey = [
    for (final diatonic in [below - 1, below, below + 1])
      ?_spelledAt(diatonic, quarterTones),
  ].where((pitch) => pitch.alter == key.alterFor(pitch.step));
  if (inKey.isNotEmpty) {
    return inKey.first;
  }
  final sharp = _spelledAt(below, quarterTones)!;
  return key.fifths >= 0 || sharp.alter == Alter.natural
      ? sharp
      : _spelledAt(below + 1, quarterTones)!;
}

/// A move by a fixed spelled interval. See [Transposition.interval].
final class ByInterval extends Transposition {
  /// Moves every note by [interval].
  const ByInterval(this.interval);

  /// The interval every note moves by.
  final Interval interval;
}

/// A move by staff positions. See [Transposition.diatonic].
final class ByScaleSteps extends Transposition {
  /// Moves every note [steps] staff positions.
  const ByScaleSteps(this.steps);

  /// Staff positions to move. Negative is downward.
  final int steps;
}

/// A move by half steps, spelled for the key. See
/// [Transposition.chromatic].
final class BySemitones extends Transposition {
  /// Moves every note [semitones] half steps.
  const BySemitones(this.semitones);

  /// Half steps to move. Negative is downward.
  final int semitones;
}
