/// The measure column and everything nested inside it.
///
/// A [MeasureColumn] is the unit a composer fills and the unit layout and
/// playback cache on. It is *self-describing*: it stores the meter and key in
/// effect for it, and each [StaffMeasure] stores the clef in effect at its
/// start. Nothing about a measure requires looking at earlier measures, so
/// fill validation, context resolution and per-measure caching are all local.
///
/// A "change" (a time signature, key signature or clef printed at a barline)
/// is not stored. It is derived: the column's value differs from the previous
/// column's. Commands that change context propagate the new value forward
/// through the run of columns that carried the old one.
library;

import 'events.dart';
import 'pitch.dart';
import 'refs.dart';
import 'seq.dart';
import 'time.dart';

/// One bar across every staff.
///
/// Invariant (checked in the constructor, the heart of this design): every
/// voice of every staff spans exactly [length]. There is no overfull and no
/// accidentally underfull measure anywhere in a `Score`. Underfill is always
/// explicit: a pickup bar sets [irregularLength], and a secondary voice with
/// nothing to say uses [Gap]s.
final class MeasureColumn {
  /// Throws [ArgumentError] when a voice does not span [length], a clef
  /// change is not strictly inside the bar, or a tempo mark lies outside
  /// `[0, length)`.
  MeasureColumn({
    required this.id,
    required this.meter,
    required this.key,
    required this.staves,
    this.irregularLength,
    this.barline = Barline.regular,
    this.repeatStart = false,
    this.repeatEnd,
    this.volta,
    this.navigation = const Seq.empty(),
    this.rehearsal,
    this.tempos = const Seq.empty(),
    this.breakBefore,
    this.keyDisplay = SignatureDisplay.auto,
    this.meterDisplay = SignatureDisplay.auto,
  }) {
    final capacity = length;
    final end = Moment.zero + capacity;
    for (final staff in staves) {
      for (final voice in staff.voices) {
        final filled = voice.length;
        if (filled != capacity) {
          throw ArgumentError(
            'measure ${id.value}, staff ${staff.staff.value}, '
            'voice ${voice.slot.name}: spans $filled, bar is $capacity',
          );
        }
      }
      if (staff.clefChanges.any(
        (c) => !c.offset.isPositive || c.offset >= end,
      )) {
        throw ArgumentError('mid-measure clef change outside (0, $capacity)');
      }
    }
    if (tempos.any((t) => t.offset.isNegative || t.offset >= end)) {
      throw ArgumentError('tempo mark outside [0, $capacity)');
    }
  }

  /// Stable identity of this bar. See [MeasureId].
  final MeasureId id;

  /// Meter in effect for this bar. Printed where it differs from the
  /// previous column's.
  final Meter meter;

  /// Concert key in effect for this bar. Key changes happen at barlines
  /// only.
  final KeySignature key;

  /// Overrides the meter's length: a pickup (shorter) or a cadenza bar
  /// (longer). Null for a regular bar.
  final Length? irregularLength;

  /// Barline at the end of this bar. An end repeat draws its own barline
  /// in place of this one.
  final Barline barline;

  /// Whether a start repeat barline opens this bar.
  final bool repeatStart;

  /// The end repeat that closes this bar, or null for none.
  final RepeatEnd? repeatEnd;

  /// The ending bracket this bar belongs to, if any. Consecutive columns
  /// with equal [Volta]s form one bracket. Stored per bar because "which
  /// passes play this bar" is a fact about the bar.
  final Volta? volta;

  /// Segno and coda sit at the start of the bar; to-coda, fine and jumps at
  /// its end. See [NavigationMark].
  final Seq<NavigationMark> navigation;

  /// Rehearsal letter or number, printed above the bar.
  final String? rehearsal;

  /// Tempo marks inside this bar, ascending by offset.
  final Seq<TempoMark> tempos;

  /// One per staff of the score, in system order.
  final Seq<StaffMeasure> staves;

  /// A break before this bar, so that it starts a new system or page. Null
  /// lets layout choose. The first bar starts both anyway.
  final LayoutBreak? breakBefore;

  /// How the key signature prints at this bar. See [SignatureDisplay].
  final SignatureDisplay keyDisplay;

  /// How the time signature prints at this bar. See [SignatureDisplay].
  final SignatureDisplay meterDisplay;

  /// Capacity every voice must fill.
  Length get length => irregularLength ?? meter.length;

  /// The slice of staff [id]. Throws [ArgumentError] when the bar has no
  /// such staff.
  StaffMeasure staff(StaffId id) {
    for (final staff in staves) {
      if (staff.staff == id) {
        return staff;
      }
    }
    throw ArgumentError.value(
      id,
      'id',
      'no such staff in measure ${this.id.value}',
    );
  }

  /// A copy with the given fields replaced and the same [id]. A nullable
  /// field takes a function so that it can be set to null. The copy is
  /// checked like a new column.
  MeasureColumn copyWith({
    Meter? meter,
    KeySignature? key,
    Length? Function()? irregularLength,
    Barline? barline,
    bool? repeatStart,
    RepeatEnd? Function()? repeatEnd,
    Volta? Function()? volta,
    Seq<NavigationMark>? navigation,
    String? Function()? rehearsal,
    Seq<TempoMark>? tempos,
    Seq<StaffMeasure>? staves,
    LayoutBreak? Function()? breakBefore,
    SignatureDisplay? keyDisplay,
    SignatureDisplay? meterDisplay,
  }) => MeasureColumn(
    id: id,
    meter: meter ?? this.meter,
    key: key ?? this.key,
    staves: staves ?? this.staves,
    irregularLength: irregularLength == null
        ? this.irregularLength
        : irregularLength(),
    barline: barline ?? this.barline,
    repeatStart: repeatStart ?? this.repeatStart,
    repeatEnd: repeatEnd == null ? this.repeatEnd : repeatEnd(),
    volta: volta == null ? this.volta : volta(),
    navigation: navigation ?? this.navigation,
    rehearsal: rehearsal == null ? this.rehearsal : rehearsal(),
    tempos: tempos ?? this.tempos,
    breakBefore: breakBefore == null ? this.breakBefore : breakBefore(),
    keyDisplay: keyDisplay ?? this.keyDisplay,
    meterDisplay: meterDisplay ?? this.meterDisplay,
  );

  /// A copy with [staff] in place of the slice of the same staff. Throws
  /// [ArgumentError] when the bar has no such staff.
  MeasureColumn withStaff(StaffMeasure staff) {
    final index = staves.indexWhere((s) => s.staff == staff.staff);
    if (index < 0) {
      throw ArgumentError.value(staff.staff, 'staff', 'not in measure');
    }
    return copyWith(staves: staves.replaceAt(index, staff));
  }
}

/// One staff's slice of a column.
final class StaffMeasure {
  /// Asserts that voice one comes first and that voice slots are unique
  /// and ascending.
  StaffMeasure({
    required this.staff,
    required this.clef,
    required this.voices,
    this.clefChanges = const Seq.empty(),
    this.directions = const Seq.empty(),
    this.measureRepeat,
  }) : assert(
         voices.isNotEmpty && voices.first.slot == VoiceSlot.one,
         'voice one always exists and comes first',
       ),
       assert(_ascendingSlots(voices), 'voice slots unique and ascending') {
    if (measureRepeat != null && !_holdsOnlyMeasureRest(voices, clefChanges)) {
      throw ArgumentError(
        'staff ${staff.value}: a bar under a measure-repeat sign holds one '
        'whole-bar rest and no clef change',
      );
    }
  }

  /// The staff this slice belongs to.
  final StaffId staff;

  /// Clef in effect at the start of this bar. Printed at the barline where
  /// it differs from the previous bar's [clefAtEnd].
  final Clef clef;

  /// Clef changes inside the bar, ascending, each at an offset in
  /// `(0, length)`.
  final Seq<ClefChange> clefChanges;

  /// Voice one first; voices two to four only while they hold content.
  final Seq<Voice> voices;

  /// Dynamics, text and chord symbols anchored to a time in this bar on this
  /// staff, ascending by offset.
  final Seq<StaffDirection> directions;

  /// The measure-repeat sign this bar of the staff is under, or null for a
  /// bar that plays what it holds. A bar under the sign holds one
  /// [MeasureRest] in voice one and no clef change, which the constructor
  /// checks, and plays the bars the sign repeats. Which bars those are, and
  /// whether the sign still stands after a change to the bars around it, is
  /// a rule across bars. See [MeasureRepeat].
  final MeasureRepeat? measureRepeat;

  /// Clef in effect at the end of this bar, after its last clef change.
  Clef get clefAtEnd => clefChanges.isEmpty ? clef : clefChanges.last.clef;

  /// Clef in effect at [offset] from the start of the bar. A change at
  /// exactly [offset] already applies.
  Clef clefAt(Moment offset) {
    var current = clef;
    for (final change in clefChanges) {
      if (change.offset > offset) {
        break;
      }
      current = change.clef;
    }
    return current;
  }

  /// The voice in [slot], or null when that slot holds nothing in this bar.
  Voice? voice(VoiceSlot slot) {
    for (final voice in voices) {
      if (voice.slot == slot) {
        return voice;
      }
    }
    return null;
  }

  /// A copy with the given fields replaced and the same [staff].
  ///
  /// Without [measureRepeat], the copy keeps this bar's sign while it still
  /// holds only its whole-bar rest and no clef change, and drops it
  /// otherwise. So writing notes into a bar under the sign clears the sign.
  StaffMeasure copyWith({
    Clef? clef,
    Seq<ClefChange>? clefChanges,
    Seq<Voice>? voices,
    Seq<StaffDirection>? directions,
    MeasureRepeat? Function()? measureRepeat,
  }) {
    final nextVoices = voices ?? this.voices;
    final nextChanges = clefChanges ?? this.clefChanges;
    return StaffMeasure(
      staff: staff,
      clef: clef ?? this.clef,
      voices: nextVoices,
      clefChanges: nextChanges,
      directions: directions ?? this.directions,
      measureRepeat: measureRepeat != null
          ? measureRepeat()
          : _holdsOnlyMeasureRest(nextVoices, nextChanges)
          ? this.measureRepeat
          : null,
    );
  }

  /// Replaces or adds the voice in the slot of [voice]. A secondary voice made only
  /// of gaps is dropped instead of stored.
  StaffMeasure withVoice(Voice voice) {
    final index = voices.indexWhere((v) => v.slot.index >= voice.slot.index);
    final replaces = index >= 0 && voices[index].slot == voice.slot;
    if (voice.slot != VoiceSlot.one && voice.items.every((i) => i is Gap)) {
      return replaces ? copyWith(voices: voices.removeAt(index)) : this;
    }
    if (replaces) {
      return copyWith(voices: voices.replaceAt(index, voice));
    }
    return copyWith(
      voices: voices.insertAt(index < 0 ? voices.length : index, voice),
    );
  }
}

bool _holdsOnlyMeasureRest(Seq<Voice> voices, Seq<ClefChange> clefChanges) =>
    clefChanges.isEmpty &&
    voices.length == 1 &&
    voices.first.items.singleOrNull is MeasureRest;

/// A measure-repeat sign over one staff's bar: the bar plays the bar or
/// two bars before it again, and prints the sign in place of notes.
///
/// A one-bar repeat covers one bar and repeats the bar before it. A two-bar
/// repeat covers two bars, [twoBarsFirst] then [twoBarsSecond], and repeats
/// the two bars before the first. Both halves of it repeat the bar
/// [bars] before them. A bar repeated may itself be under a sign, and then
/// plays what that sign repeats.
///
/// The sign is per staff, as MusicXML's `measure-repeat` is per part or per
/// staff. It stands only where it can: there are [bars] bars before it,
/// the bars it repeats have its length, and a half of a two-bar repeat sits
/// next to its other half. `scoreFromJson` refuses a sign that does not
/// stand, edits clear one, and MusicXML import drops one.
enum MeasureRepeat {
  /// Repeats the bar before. One slash between two dots, in the bar.
  oneBar(1),

  /// The first bar under a two-bar repeat. Two slashes between two dots,
  /// over the barline after this bar.
  twoBarsFirst(2),

  /// The second bar under a two-bar repeat. The first half draws the sign.
  twoBarsSecond(2);

  MeasureRepeat(this.bars);

  /// How many bars the sign repeats.
  final int bars;
}

bool _ascendingSlots(Seq<Voice> voices) {
  for (var i = 1; i < voices.length; i++) {
    if (voices[i].slot.index <= voices[i - 1].slot.index) {
      return false;
    }
  }
  return true;
}

/// One voice lane of one staff in one bar.
final class Voice {
  /// Asserts that [items] is not empty and that voice one holds no [Gap].
  Voice({required this.slot, required this.items})
    : assert(items.isNotEmpty, 'a stored voice has items'),
      assert(
        slot != VoiceSlot.one || !items.any((i) => i is Gap),
        'voice one has no gaps',
      );

  /// The lane this voice fills.
  final VoiceSlot slot;

  /// Events, tuplets and gaps in time order.
  final Seq<VoiceItem> items;

  /// Sum of the items' spans. The enclosing column requires this to equal
  /// its length.
  Length get length => Length.sum(items.map((i) => i.span));
}

/// A clef change inside a bar. See [StaffMeasure.clefChanges].
final class ClefChange {
  /// A change to [clef] at [offset].
  const ClefChange(this.offset, this.clef);

  /// Whole notes from the start of the bar, strictly inside it.
  final Moment offset;

  /// Clef in effect from [offset] on.
  final Clef clef;

  @override
  bool operator ==(Object other) =>
      other is ClefChange && other.offset == offset && other.clef == clef;

  @override
  int get hashCode => Object.hash(offset, clef);
}

/// The line drawn at the end of a bar.
enum Barline {
  /// One thin line.
  regular,

  /// Two thin lines.
  doubleBar,

  /// A thin line then a thick one, as at the end of a piece.
  finalBar,

  /// One dashed line.
  dashed,

  /// One dotted line.
  dotted,

  /// One thick line.
  heavy,

  /// No line.
  invisible,
}

/// A break that layout must make before a bar.
enum LayoutBreak {
  /// The bar starts a new system.
  system,

  /// The bar starts a new page, and so a new system.
  page,
}

/// How a bar prints its key or time signature where the composer overrides
/// layout's default.
enum SignatureDisplay {
  /// Printed where it changes. When the change starts a system, a courtesy
  /// signature prints at the end of the system before.
  auto,

  /// Printed here even where it hasn't changed, as at a new section.
  restated,

  /// Printed where it changes, with no courtesy signature before it.
  noCourtesy,
}

/// An end repeat barline at the end of a bar. Playback returns to the last
/// start repeat, or to the bar after the previous repeated section, or to
/// the start of the score.
final class RepeatEnd {
  /// Asserts that [times] is at least 2.
  const RepeatEnd({this.times = 2})
    : assert(times >= 2, 'a repeat plays twice or more');

  /// Total passes through the repeated section.
  final int times;

  @override
  bool operator ==(Object other) => other is RepeatEnd && other.times == times;

  @override
  int get hashCode => times.hashCode;
}

/// An ending bracket ("1.", "2.", "1.–3."). [endings] lists the passes on
/// which bars under this bracket play, ascending.
final class Volta {
  /// A bracket over the passes in [endings].
  const Volta(this.endings, {this.open = false});

  /// Pass numbers, counting from 1, on which these bars play.
  final List<int> endings;

  /// No downward hook at the right end (typical for the last ending).
  final bool open;

  @override
  bool operator ==(Object other) =>
      other is Volta &&
      other.open == open &&
      other.endings.length == endings.length &&
      Iterable<int>.generate(endings.length)
          .every((i) => other.endings[i] == endings[i]);

  @override
  int get hashCode => Object.hash(open, Object.hashAll(endings));
}

/// Navigation for repeats beyond simple repeat barlines. Where a mark takes
/// effect is part of its type:
/// - at the start of the bar: [Segno], [Coda];
/// - at the end of the bar: [ToCoda], [Fine], [Jump].
///
/// Playback honours all of them, codas included.
sealed class NavigationMark {
  /// Base constructor for the mark kinds.
  const NavigationMark();

  /// Whether the mark takes effect at the start of its bar rather than at
  /// its end.
  bool get atBarStart => switch (this) {
    Segno() || Coda() => true,
    ToCoda() || Fine() || Jump() => false,
  };

  /// Marks without fields are equal when they are the same kind.
  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The bar a D.S. [Jump] returns to. A D.S. in a score with no segno goes
/// to the start.
final class Segno extends NavigationMark {
  /// The segno sign.
  const Segno();
}

/// The coda section starts at this bar.
final class Coda extends NavigationMark {
  /// The coda sign.
  const Coda();
}

/// After a jump, leave for the [Coda] at the end of this bar.
final class ToCoda extends NavigationMark {
  /// The "To Coda" mark.
  const ToCoda();

  /// What prints.
  String get label => 'To Coda';
}

/// After a jump, stop at the end of this bar.
final class Fine extends NavigationMark {
  /// The "Fine" mark.
  const Fine();

  /// What prints.
  String get label => 'Fine';
}

/// D.C. or D.S., with what happens after the jump.
final class Jump extends NavigationMark {
  /// A jump back to [target] that then follows [then].
  const Jump(this.target, {this.then = JumpThen.toEnd, this.text});

  /// Where the jump goes back to.
  final JumpTarget target;

  /// What playback does after the jump.
  final JumpThen then;

  /// Printed text in place of the words [label] builds, or null to print
  /// those words.
  final String? text;

  /// What prints. It is [text], or else the words for [target] and [then],
  /// "D.C." or "D.S." with " al Fine" or " al Coda".
  String get label =>
      text ??
      '${target == JumpTarget.start ? 'D.C.' : 'D.S.'}'
          '${switch (then) {
            JumpThen.toEnd => '',
            JumpThen.toFine => ' al Fine',
            JumpThen.toCoda => ' al Coda',
          }}';

  @override
  bool operator ==(Object other) =>
      other is Jump &&
      other.target == target &&
      other.then == then &&
      other.text == text;

  @override
  int get hashCode => Object.hash(target, then, text);
}

/// Where a [Jump] goes back to.
enum JumpTarget {
  /// D.C., the first bar of the score.
  start,

  /// D.S., the bar marked [Segno], or the first bar when no bar is.
  segno,
}

/// What playback does after a [Jump]. Repeats are not taken again either
/// way.
enum JumpThen {
  /// Play on to the end of the score. [Fine] and [ToCoda] are ignored.
  toEnd,

  /// Stop at the end of the first bar marked [Fine] that plays after the
  /// jump.
  toFine,

  /// At the end of the first bar marked [ToCoda] that plays after the
  /// jump, leave for the bar marked [Coda], once.
  toCoda,
}

/// A tempo change at a time inside a bar. Playback takes [tempo] from
/// [offset] on.
final class TempoMark {
  /// A mark that sets [tempo] at [offset].
  const TempoMark({
    required this.offset,
    required this.tempo,
    this.text,
    this.showMetronome = true,
  });

  /// Whole notes from the start of the bar, in `[0, length)`.
  final Moment offset;

  /// The tempo from [offset] on.
  final Tempo tempo;

  /// Words printed before the metronome mark, such as "Allegro" or
  /// "Тайван". Null prints none.
  final String? text;

  /// Whether the metronome mark prints. Playback follows [tempo] either
  /// way.
  final bool showMetronome;

  @override
  bool operator ==(Object other) =>
      other is TempoMark &&
      other.offset == offset &&
      other.tempo == tempo &&
      other.text == text &&
      other.showMetronome == showMetronome;

  @override
  int get hashCode => Object.hash(offset, tempo, text, showMetronome);
}

/// Things anchored to a time on one staff (not to an event), like MusicXML
/// `<direction>`s.
sealed class StaffDirection {
  /// Base constructor for a direction at [offset].
  const StaffDirection(this.offset);

  /// Whole notes from the start of the bar.
  final Moment offset;
}

/// A dynamic marking such as p or sfz. It applies to every staff of its
/// part. See [Dynamic.velocity].
final class DynamicMark extends StaffDirection {
  /// A [level] marking at [offset].
  const DynamicMark(super.offset, this.level);

  /// The marking, which sets the loudness playback uses.
  final Dynamic level;

  @override
  bool operator ==(Object other) =>
      other is DynamicMark && other.offset == offset && other.level == level;

  @override
  int get hashCode => Object.hash(offset, level);
}

/// Expression text such as "dolce" or "pizz.". Playback ignores it.
final class TextMark extends StaffDirection {
  /// [text] at [offset], above the staff unless [above] is false.
  const TextMark(super.offset, this.text, {this.above = true});

  /// The words that print.
  final String text;

  /// Whether the text prints above the staff. False prints it below.
  final bool above;

  @override
  bool operator ==(Object other) =>
      other is TextMark &&
      other.offset == offset &&
      other.text == text &&
      other.above == above;

  @override
  int get hashCode => Object.hash(offset, text, above);
}

/// A chord symbol. Root and bass are spelled so transposition moves them
/// correctly; [quality] is free text ("m7", "sus4").
final class ChordSymbol extends StaffDirection {
  /// A symbol on [root] at [offset].
  const ChordSymbol(
    super.offset, {
    required this.root,
    this.quality = '',
    this.bass,
  });

  /// The chord's root, as the "C" of "Cm7".
  final PitchName root;

  /// Text printed after the root. Empty for a major triad.
  final String quality;

  /// The bass of a slash chord, as the "G" of "C/G". Null for none.
  final PitchName? bass;

  @override
  bool operator ==(Object other) =>
      other is ChordSymbol &&
      other.offset == offset &&
      other.root == root &&
      other.quality == quality &&
      other.bass == bass;

  @override
  int get hashCode => Object.hash(offset, root, quality, bass);
}

/// A dynamic marking, with the MIDI velocity playback gives it.
enum Dynamic {
  /// Quadruple piano.
  pppp(12),

  /// Pianississimo.
  ppp(20),

  /// Pianissimo.
  pp(31),

  /// Piano.
  p(42),

  /// Mezzo-piano.
  mp(53),

  /// Mezzo-forte.
  mf(64),

  /// Forte.
  f(80),

  /// Fortissimo.
  ff(96),

  /// Fortississimo.
  fff(112),

  /// Quadruple forte.
  ffff(127),

  /// Sforzando, a sudden accent on the chords at its time.
  sf(100),

  /// Sforzato, a sudden accent on the chords at its time.
  sfz(110),

  /// Forte-piano, a loud attack that then drops to [p].
  fp(80),

  /// Rinforzando, a sudden accent on the chords at its time.
  rfz(100);

  Dynamic(this.velocity);

  /// Default MIDI velocity. sf, sfz and rfz strike the chords at their time
  /// and leave the level alone, fp strikes them and then sets p, and the
  /// others set the level until the next dynamic. A dynamic on any staff of
  /// a part applies to the whole part.
  final int velocity;
}
