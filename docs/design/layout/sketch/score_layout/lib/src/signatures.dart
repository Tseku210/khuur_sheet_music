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

  /// From the head's left edge to the end of its last glyph, with the gap
  /// after it. Room for a start repeat sign is included, the sign is not:
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
  /// `printsMeter`).
  final BarHead inline;

  /// When the bar starts a system. It holds the clef and key on every staff,
  /// and the meter when it changes here or `style.meterEverySystem` is set.
  final BarHead system;

  /// What the system before ends with when this bar starts a system. It holds
  /// the new key and meter (`keyCourtesy`, `meterCourtesy`), unless
  /// `style.courtesySignatures` is off. Its x runs from the last barline of
  /// that system.
  final BarHead courtesy;
}

/// The heads of [view].
BarHeads barHeads(MeasureView view, EngravingStyle style) {
  // TODO, per variant, left to right with one gap between groups:
  // - clef per staff: clefGlyph, on the line Clef.line names;
  // - key per staff: keySignatureItems of StaffView.writtenKey, cancelling
  //   MeasureView.previousKey when the key changes. A percussion clef
  //   prints no key;
  // - meter per staff: meterItems;
  // - room for the start repeat sign when column.repeatStart.
  // Groups align across staves: each group starts at the widest end of the
  // group before it.
  throw UnimplementedError();
}

/// The clef's glyph, full size in a head and the `Change` size inside a bar.
Glyph clefGlyph(Clef clef, {required bool change}) =>
    throw UnimplementedError();

/// The staff steps of a key signature's accidentals under [clef], in printing
/// order. They follow the standard octave pattern of sharps or flats for the
/// clef's sign, moved by its line.
List<int> keySignatureSteps(KeySignature key, Clef clef) =>
    throw UnimplementedError();

/// A key signature from x 0. Naturals come first, for what [cancels] has and
/// [key] lacks, then the sharps or flats of [key]. Returns the items and their
/// width.
BarHead keySignatureItems(
  KeySignature key,
  Clef clef, {
  required int staff,
  required KeySignature? cancels,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// A time signature from x 0. It is `timeSigCommon` or `timeSigCutCommon` for
/// those symbols, else numerator over denominator in `timeSig` digits, each row
/// centred. On a one-line staff both rows straddle the line.
BarHead meterItems(
  Meter meter, {
  required int staff,
  required int lines,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// A clef change inside the bar. It is the small clef just left of the slice at
/// its offset. A change at offset 0 belongs to the head, not here.
List<BarItem> clefChangeItems(
  StaffView view, {
  required int staff,
  required List<Moment> times,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// What a bar's edges are, for the barlines the system draws.
typedef BarEdges = ({
  /// The bar opens a repeat.
  bool repeatStart,

  /// The bar's inline head prints no signature, so a start repeat here can
  /// join the end repeat of the bar before it into one sign.
  bool startJoins,
  Barline end,
  RepeatEnd? repeatEnd,
});

/// The width of the bar's end barline with its repeat dots, which is the
/// rod of the bar's last slice.
double endBarlineWidth(BarEdges edges, EngravingStyle style) =>
    throw UnimplementedError();

/// The barlines and repeat signs of one system.
///
/// A barline runs from the top line of the first staff of a part to the
/// bottom line of its last staff, so it joins the staves of a piano part
/// and breaks between parts ([groups] holds the first and last staff index
/// of each part). The end barline sits at the bar's last slice. A start
/// repeat sits at the end of the bar's head. An end repeat followed on the
/// same system by a bar whose start repeat joins it draws as one sign at
/// the boundary. The last bar of the score draws `Barline.finalBar` only
/// when the model says so.
List<Drawable> placeBarlines(
  List<Framed<BarEdges>> bars, {
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
  // TODO: for each part that is not hidden, measure name and shortName
  // with the partName spec and count its staves. An indent is the widest
  // name plus a gap, plus braceWidth when any part has two staves or
  // more.
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
