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

  /// Barline at the end of this bar.
  final Barline barline;

  /// A start-repeat sign at the beginning of this bar.
  final bool repeatStart;

  /// An end-repeat sign at the end of this bar.
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

  /// Tempo marks inside this bar, ascending by offset. The tempo in effect
  /// is derived by playback's fold over the columns.
  final Seq<TempoMark> tempos;

  /// One per staff of the score, in system order. `Score` checks the order.
  final Seq<StaffMeasure> staves;

  /// Capacity every voice must fill.
  Length get length => irregularLength ?? meter.length;

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
  );

  /// Returns a column with [staff] replaced. The single step every note edit
  /// takes on its way back up the tree.
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
  StaffMeasure({
    required this.staff,
    required this.clef,
    required this.voices,
    this.clefChanges = const Seq.empty(),
    this.directions = const Seq.empty(),
  }) : assert(
         voices.isNotEmpty && voices.first.slot == VoiceSlot.one,
         'voice one always exists and comes first',
       ),
       assert(_ascendingSlots(voices), 'voice slots unique and ascending');

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

  Clef get clefAtEnd => clefChanges.isEmpty ? clef : clefChanges.last.clef;

  /// Clef in effect at [offset].
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

  Voice? voice(VoiceSlot slot) {
    for (final voice in voices) {
      if (voice.slot == slot) {
        return voice;
      }
    }
    return null;
  }

  StaffMeasure copyWith({
    Clef? clef,
    Seq<ClefChange>? clefChanges,
    Seq<Voice>? voices,
    Seq<StaffDirection>? directions,
  }) => StaffMeasure(
    staff: staff,
    clef: clef ?? this.clef,
    voices: voices ?? this.voices,
    clefChanges: clefChanges ?? this.clefChanges,
    directions: directions ?? this.directions,
  );

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
  Voice({required this.slot, required this.items})
    : assert(items.isNotEmpty, 'a stored voice has items'),
      assert(
        slot != VoiceSlot.one || !items.any((i) => i is Gap),
        'voice one has no gaps',
      );

  final VoiceSlot slot;
  final Seq<VoiceItem> items;

  /// Sum of the items' spans. The enclosing column requires this to equal
  /// its length.
  Length get length => Length.sum(items.map((i) => i.span));
}

final class ClefChange {
  const ClefChange(this.offset, this.clef);

  final Moment offset;
  final Clef clef;
}

enum Barline { regular, doubleBar, finalBar, dashed, dotted, heavy, invisible }

final class RepeatEnd {
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
  const Volta(this.endings, {this.open = false});

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
/// Playback honours all of them, codas included (Maestro ignores codas).
sealed class NavigationMark {
  const NavigationMark();
}

final class Segno extends NavigationMark {
  const Segno();
}

/// The coda section starts at this bar.
final class Coda extends NavigationMark {
  const Coda();
}

/// After a jump, leave for the [Coda] at the end of this bar.
final class ToCoda extends NavigationMark {
  const ToCoda();
}

/// After a jump, stop at the end of this bar.
final class Fine extends NavigationMark {
  const Fine();
}

/// D.C. or D.S., with what happens after the jump.
final class Jump extends NavigationMark {
  const Jump(this.target, {this.then = JumpThen.toEnd, this.text});

  final JumpTarget target;
  final JumpThen then;

  /// Printed text override ("D.C. al Fine" is the default rendering).
  final String? text;
}

enum JumpTarget { start, segno }

enum JumpThen { toEnd, toFine, toCoda }

final class TempoMark {
  const TempoMark({
    required this.offset,
    required this.tempo,
    this.text,
    this.showMetronome = true,
  });

  final Moment offset;
  final Tempo tempo;

  /// "Allegro", "Тайван". Full Unicode.
  final String? text;

  final bool showMetronome;
}

/// Things anchored to a time on one staff (not to an event), like MusicXML
/// `<direction>`s.
sealed class StaffDirection {
  const StaffDirection(this.offset);

  final Moment offset;
}

final class DynamicMark extends StaffDirection {
  const DynamicMark(super.offset, this.level);

  final Dynamic level;
}

final class TextMark extends StaffDirection {
  const TextMark(super.offset, this.text, {this.above = true});

  final String text;
  final bool above;
}

/// A chord symbol. Root and bass are spelled so transposition moves them
/// correctly; [quality] is free text ("m7", "sus4").
final class ChordSymbol extends StaffDirection {
  const ChordSymbol(
    super.offset, {
    required this.root,
    this.quality = '',
    this.bass,
  });

  final PitchName root;
  final String quality;
  final PitchName? bass;
}

enum Dynamic {
  pppp(12),
  ppp(20),
  pp(31),
  p(42),
  mp(53),
  mf(64),
  f(80),
  ff(96),
  fff(112),
  ffff(127),
  sf(100),
  sfz(110),
  fp(80),
  rfz(100);

  Dynamic(this.velocity);

  /// Default MIDI velocity. Accents (sf, sfz, fp, rfz) affect one event;
  /// the others set the level until the next dynamic.
  final int velocity;
}
