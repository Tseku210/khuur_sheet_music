/// Signatures and structure. Clefs, key and time signatures, barlines and
/// repeat signs, and what stands before the first bar of a system. Not
/// exported.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'glyphs.dart';
import 'spacing.dart';
import 'style.dart';
import 'text.dart';

/// A drawable of a head, with x from the head's left edge and y from the top
/// line of its staff.
typedef HeadItem = ({int staff, Drawable drawable});

/// What a bar prints before its first slice in one situation.
final class BarHead {
  const BarHead({required this.items, required this.width});

  static const none = BarHead(items: [], width: 0);

  final List<HeadItem> items;

  /// From the head's left edge to the end of its last group, with the gap
  /// after it. Room for a start repeat sign ([startRepeatWidth]) is included,
  /// as the last group, so the sign's left edge is at
  /// `width - gap - startRepeatWidth`. The sign is not included:
  /// [placeBarlines] draws it.
  final double width;
}

/// How far [head] reaches outside staff [staff], above its top line and below
/// its bottom line. A G clef reaches both ways.
({double above, double below}) headReach(BarHead head, int staff) {
  var above = 0.0;
  var below = 0.0;
  for (final item in head.items) {
    if (item.staff == staff) {
      final bounds = item.drawable.bounds;
      above = math.max(above, -bounds.top);
      below = math.max(below, bounds.bottom - staffHeight);
    }
  }
  return (above: above, below: below);
}

/// The three heads a bar can print. A bar does not know where it lands, so
/// it holds all three and the system picks.
final class BarHeads {
  const BarHeads({
    required this.inline,
    required this.system,
    required this.courtesy,
  });

  /// When the bar follows another on its system. It holds the clef, key and
  /// meter the bar changes or restates (`StaffView.clefChanged`, `printsKey`,
  /// `printsMeter`). The clef is the small one, as for a change inside a bar.
  final BarHead inline;

  /// When the bar starts a system. It holds the clef and key on every staff,
  /// and the meter when it changes here or `style.meterEverySystem` is set.
  /// A changed key cancels the old one here only when no courtesy did.
  final BarHead system;

  /// What the system before ends with when this bar starts a system. It holds
  /// the new key and meter (`keyCourtesy`, `meterCourtesy`), unless
  /// `style.courtesySignatures` is off. Its x runs from the last barline of
  /// that system.
  final BarHead courtesy;
}

/// The heads of [view].
BarHeads barHeads(MeasureView view, EngravingStyle style) {
  // Per variant, left to right, with one gap before each group and one
  // after the last:
  // - clef per staff: clefGlyph, on the line Clef.line names;
  // - key per staff: keySignatureItems of StaffView.writtenKey, cancelling
  //   the staff's written form of MeasureView.previousKey when the key
  //   changes. A percussion clef prints no key;
  // - meter per staff: meterItems;
  // - room for the start repeat sign when column.repeatStart.
  // Groups align across staves: each group starts one gap after the widest
  // end of the group before it.
  throw UnimplementedError();
}

/// The clef's glyph and the scale to draw it at. It is full size at the start
/// of a system and small where the clef changes. SMuFL has a `Change` glyph
/// for the three plain clefs. An octave clef or a percussion clef is its
/// full glyph scaled down.
({Glyph glyph, double scale}) clefGlyph(Clef clef, {required bool change}) =>
    throw UnimplementedError();

/// The staff steps of a key signature's accidentals under [clef], in printing
/// order. Each accidental sits on the one step of its letter in an octave
/// whose top step is looked up by where the clef puts C. Empty under a
/// percussion clef, which prints no key.
List<int> keySignatureSteps(KeySignature key, Clef clef) =>
    throw UnimplementedError();

/// A key signature from x 0. Naturals come first, for what [cancels] has and
/// [key] lacks, on the steps [cancels] printed them. Then come the sharps or
/// flats of [key]. Returns the items and their width.
BarHead keySignatureItems(
  KeySignature key,
  Clef clef, {
  required int staff,
  required KeySignature? cancels,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// A time signature from x 0. It is `timeSigCommon` or `timeSigCutCommon` for
/// those symbols, else numerator over denominator in `timeSig` digits, each row
/// centred. The groups of an additive meter are joined by plus signs. The rows
/// meet on the middle line, which is also the line of a one-line staff.
BarHead meterItems(
  Meter meter, {
  required int staff,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The clef changes inside the bar on one staff. Each is the small clef left
/// of everything its slice reaches to the left on any staff, which is
/// [reach] before the clefs widen it. `layoutBar` then widens the slice's
/// left reach by the clef, so the slice before it makes room. A change at
/// offset 0 belongs to the head, not here.
List<BarItem> clefChangeItems(
  StaffView view, {
  required int staff,
  required List<Moment> times,
  required List<SliceReach> reach,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// What a bar's edges are, for the barlines the system draws.
typedef BarEdges = ({
  /// The bar opens a repeat.
  bool repeatStart,

  /// The bar's inline head prints nothing, so a start repeat here can stand
  /// in for the barline of the bar before it, or join its end repeat into
  /// one sign. Read from the head's items, not from what the bar prints,
  /// since a restated C major or a key under a percussion clef prints
  /// nothing.
  bool startJoins,
  Barline end,
  RepeatEnd? repeatEnd,
});

/// The width of the bar's end barline with its repeat dots, which is the
/// rod of the bar's last slice.
double endBarlineWidth(BarEdges edges, EngravingStyle style) =>
    throw UnimplementedError();

/// The width of a start repeat sign, which is a thick line, a thin line and
/// the dots. An end repeat sign is its mirror image and as wide.
double startRepeatWidth(EngravingStyle style) => throw UnimplementedError();

/// A bar's edges with the width of the head the system placed before it,
/// which holds the room of a start repeat sign as its last group.
typedef PlacedEdges = ({BarEdges edges, double head});

/// The barlines and repeat signs of one system.
///
/// A barline runs from the top line of the first staff of a part to the
/// bottom line of its last staff, so it joins the staves of a piano part
/// and breaks between parts ([groups] holds the first and last staff index
/// of each part). The end barline starts at the bar's last slice and is as
/// wide as that slice's rod. A start repeat sits at the end of the bar's
/// head, and stands in for the regular barline of the bar before it when
/// nothing else is in the head. An end repeat followed on the same system
/// by a bar whose start repeat joins it draws as one sign, with its thick
/// line on the boundary. The last bar of the score draws `Barline.finalBar`
/// only when the model says so.
List<Drawable> placeBarlines(
  List<Framed<PlacedEdges>> bars, {
  required List<(int, int)> groups,
  required List<double> tops,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// How wide a brace is drawn, in staff spaces, whatever its height.
///
/// A part's height differs from system to system with its reach and its
/// lyric rows, and the lead's indent is one value for every system. So the
/// brace glyph is scaled to this width once and stretched vertically to the
/// part (`GlyphDraw.stretch`). Scaled evenly it would be as wide as the
/// part is tall, and would leave its indent on a tall system.
const double braceWidth = 1;

/// What stands before the first bar of every system, which is part names,
/// braces and the line that joins the staves. A function of the parts, the
/// style and the text measurer, so one value serves every system of a score.
final class SystemLead {
  const SystemLead({
    required this.parts,
    required this.firstIndent,
    required this.indent,
  });

  /// Visible parts, top to bottom.
  final List<LeadPart> parts;

  /// x where the first system's staves start, leaving room for the widest full
  /// name and a brace. 0 for a single unnamed part.
  final double firstIndent;

  /// The same for every later system, with short names.
  final double indent;

  /// The first and last staff index of each part.
  List<(int, int)> get groups => [
    for (final part in parts) (part.firstStaff, part.lastStaff),
  ];

  double get braceRoom =>
      parts.any((part) => part.lastStaff > part.firstStaff) ? braceWidth : 0;
}

/// A visible part's name, measured, and its staves by index among the
/// visible staves.
typedef LeadPart = ({
  String name,
  TextExtent nameExtent,
  String shortName,
  TextExtent shortExtent,
  int firstStaff,
  int lastStaff,
});

/// The lead of [score]. Reused while `score.parts` is the same object.
SystemLead systemLead(Score score, EngravingStyle style, TextMeasurer text) {
  // For each part that is not hidden, measure name and shortName with the
  // partName spec and count its staves. An indent is the widest name plus
  // a gap, when any part has a name, plus braceWidth when any part has two
  // staves or more.
  throw UnimplementedError();
}

/// The lead's drawables on one system. They are each part's name centred on its
/// staves (the full name when [first]), a brace (`Glyph.brace`, [braceWidth]
/// wide and stretched to the part's height) for a part of two staves or more,
/// and one thin line down the left edge of the staves when the system has more
/// than one.
List<Drawable> placeLead(
  SystemLead lead, {
  required bool first,
  required List<double> tops,
  required EngravingStyle style,
}) => throw UnimplementedError();
