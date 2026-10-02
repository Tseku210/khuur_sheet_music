/// Signatures and structure. Clefs, key and time signatures, the widths of
/// barlines and repeat signs, and what stands before the first bar of a
/// system. Not exported.
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

/// Clear space before each group of a head and after its last one.
const double _headGap = 0.75;

/// Clear space after a sharp or a flat of a key signature.
const double _keyGap = 0.15;

/// Clear space after a natural of a key signature. A natural is narrow and
/// reads as part of its neighbour at the gap a sharp takes.
const double _naturalGap = 0.3;

/// Clear space between a clef change and what its slice reaches to the left.
const double _clefChangeGap = 0.5;

/// The size of a clef change whose clef has no `Change` glyph in SMuFL.
const double _clefChangeScale = 2 / 3;

/// Clear space between the widest part name and the staves or their brace.
const double _nameGap = 1;

/// A drawable of a head, with x from the head's left edge and y from the top
/// line of its staff.
typedef HeadItem = ({int staff, Drawable drawable});

/// What a bar prints before its first slice in one situation.
final class BarHead {
  const BarHead({required this.items, required this.width});

  static const none = BarHead(items: [], width: 0);

  final List<HeadItem> items;

  /// From the head's left edge to the end of its last group, with the gap
  /// after it. Room for a start repeat sign is included, as the last group.
  /// The sign is not. The system draws it with the barlines.
  final double width;

  @override
  bool operator ==(Object other) =>
      other is BarHead &&
      other.width == width &&
      other.items.length == items.length &&
      other.items.indexed.every((item) => items[item.$1] == item.$2);

  @override
  int get hashCode => Object.hash(width, items.length);
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

  @override
  bool operator ==(Object other) =>
      other is BarHeads &&
      other.inline == inline &&
      other.system == system &&
      other.courtesy == courtesy;

  @override
  int get hashCode => Object.hash(inline, system, courtesy);
}

/// The heads of [view].
///
/// A head is up to three groups, left to right, which are the clefs, the keys
/// and the meters, and then room for a start repeat sign when the bar opens a
/// repeat. Groups align across staves. Each starts one gap after the widest
/// end of the group before it.
BarHeads barHeads(MeasureView view, EngravingStyle style) {
  final staves = view.staves;
  final keyCourtesy = style.courtesySignatures && view.keyCourtesy;
  final meterCourtesy = style.courtesySignatures && view.meterCourtesy;

  List<BarHead> clefs({required bool change}) => [
    for (final (staff, staffView) in staves.indexed)
      if (!change || staffView.clefChanged)
        _clefHead(staffView.clef, staff: staff, change: change, style: style),
  ];
  List<BarHead> keys({required bool cancel}) => [
    for (final (staff, staffView) in staves.indexed)
      keySignatureItems(
        staffView.writtenKey,
        staffView.clef,
        staff: staff,
        cancels: switch (view.previousKey) {
          final previous? when cancel && view.keyChanged =>
            staffView.part.instrument.writtenKey(previous),
          _ => null,
        },
        style: style,
      ),
  ];
  final meters = view.printsMeter || style.meterEverySystem
      ? [
          for (final (staff, _) in staves.indexed)
            meterItems(view.column.meter, staff: staff, style: style),
        ]
      : const <BarHead>[];
  final changedKeys = keys(cancel: true);
  final repeat = view.column.repeatStart ? startRepeatWidth(style) : 0.0;

  return BarHeads(
    inline: _joined([
      clefs(change: true),
      if (view.printsKey) changedKeys,
      if (view.printsMeter) meters,
    ], repeat: repeat),
    system: _joined([
      clefs(change: false),
      if (keyCourtesy) keys(cancel: false) else changedKeys,
      meters,
    ], repeat: repeat),
    courtesy: _joined([
      if (keyCourtesy) changedKeys,
      if (meterCourtesy) meters,
    ], repeat: 0),
  );
}

/// One head from [groups], each a list of per-staff pieces from x 0.
BarHead _joined(List<List<BarHead>> groups, {required double repeat}) {
  final items = <HeadItem>[];
  var x = 0.0;
  for (final group in groups) {
    final width = group.fold<double>(
      0,
      (width, piece) => math.max(width, piece.width),
    );
    if (width == 0) {
      continue;
    }
    x += _headGap;
    for (final piece in group) {
      for (final item in piece.items) {
        items.add((staff: item.staff, drawable: item.drawable.shift(x, 0)));
      }
    }
    x += width;
  }
  if (repeat > 0) {
    // The sign stands in for the barline, so it needs no gap from it.
    x += (x > 0 ? _headGap : 0) + repeat;
  }
  return x == 0 ? BarHead.none : BarHead(items: items, width: x + _headGap);
}

GlyphDraw _glyph(
  Glyph glyph,
  double x,
  double y,
  EngravingStyle style, {
  double scale = 1,
}) {
  final box = style.font[glyph].box;
  return GlyphDraw(
    glyph,
    SpPoint(x, y),
    bounds: Box(
      x + box.left * scale,
      y + box.top * scale,
      x + box.right * scale,
      y + box.bottom * scale,
    ),
    scale: scale,
  );
}

/// The clef's glyph and the scale to draw it at. It is full size at the start
/// of a system and small where the clef changes. SMuFL has a `Change` glyph
/// for the three plain clefs. An octave clef or a percussion clef is its
/// full glyph scaled down.
({Glyph glyph, double scale}) clefGlyph(Clef clef, {required bool change}) {
  final full = switch (clef) {
    Clef.treble => Glyph.gClef,
    Clef.treble8vb => Glyph.gClef8vb,
    Clef.treble8va => Glyph.gClef8va,
    Clef.bass || Clef.baritoneF => Glyph.fClef,
    Clef.bass8vb => Glyph.fClef8vb,
    Clef.soprano ||
    Clef.mezzoSoprano ||
    Clef.alto ||
    Clef.tenor ||
    Clef.baritoneC => Glyph.cClef,
    Clef.percussion => Glyph.unpitchedPercussionClef1,
  };
  if (!change) {
    return (glyph: full, scale: 1);
  }
  return switch (full) {
    Glyph.gClef => (glyph: Glyph.gClefChange, scale: 1),
    Glyph.cClef => (glyph: Glyph.cClefChange, scale: 1),
    Glyph.fClef => (glyph: Glyph.fClefChange, scale: 1),
    _ => (glyph: full, scale: _clefChangeScale),
  };
}

/// [clef] on its line, with its ink's left edge at x [left].
GlyphDraw _clefAt(
  Clef clef,
  double left, {
  required bool change,
  required EngravingStyle style,
}) {
  final (:glyph, :scale) = clefGlyph(clef, change: change);
  return _glyph(
    glyph,
    left - style.font[glyph].box.left * scale,
    yOfStep(2 * (clef.line - 1)),
    style,
    scale: scale,
  );
}

BarHead _clefHead(
  Clef clef, {
  required int staff,
  required bool change,
  required EngravingStyle style,
}) {
  final drawable = _clefAt(clef, 0, change: change, style: style);
  return BarHead(
    items: [(staff: staff, drawable: drawable)],
    width: drawable.bounds.width,
  );
}

const List<Step> _sharpOrder = [
  Step.f,
  Step.c,
  Step.g,
  Step.d,
  Step.a,
  Step.e,
  Step.b,
];

/// The highest staff step a sharp or a flat of a key signature may take, by
/// the step of a C under the clef, modulo 7. An accidental sits on the one
/// step of its letter in the seven steps that end there. The treble clef has
/// its C at step 5, so its sharps lie on steps 3 to 9 and its flats on 1 to 7.
const List<int> _sharpTops = [6, 7, 6, 7, 8, 9, 8];
const List<int> _flatTops = [6, 5, 6, 5, 6, 7, 8];

/// The letters [key] alters, in printing order.
List<Step> _alteredLetters(KeySignature key) => key.fifths >= 0
    ? _sharpOrder.sublist(0, key.fifths)
    : [for (var i = 0; i < -key.fifths; i++) _sharpOrder[6 - i]];

/// The staff steps of a key signature's accidentals under [clef], in printing
/// order. Empty under a percussion clef, which prints no key.
List<int> keySignatureSteps(KeySignature key, Clef clef) {
  if (clef.sign == ClefSign.percussion || key.fifths == 0) {
    return const [];
  }
  final c = clef.staffStepOf(const Pitch(Step.c, 4)) % 7;
  final low = (key.fifths > 0 ? _sharpTops : _flatTops)[c] - 6;
  return [
    for (final letter in _alteredLetters(key))
      low + (clef.staffStepOf(Pitch(letter, 4)) - low) % 7,
  ];
}

/// A key signature from x 0. Naturals come first, for each letter [cancels]
/// alters and [key] alters differently or not at all, on the steps [cancels]
/// printed them. Then come the sharps or flats of [key]. Returns the items and
/// their width.
BarHead keySignatureItems(
  KeySignature key,
  Clef clef, {
  required int staff,
  required KeySignature? cancels,
  required EngravingStyle style,
}) {
  final items = <HeadItem>[];
  var x = 0.0;
  var gap = 0.0;
  void add(Glyph glyph, int step) {
    x += gap;
    items.add((staff: staff, drawable: _glyph(glyph, x, yOfStep(step), style)));
    x += style.font[glyph].advance;
    gap = glyph == Glyph.accidentalNatural ? _naturalGap : _keyGap;
  }

  if (cancels != null) {
    final letters = _alteredLetters(cancels);
    for (final (index, step) in keySignatureSteps(cancels, clef).indexed) {
      final letter = letters[index];
      if (key.alterFor(letter) != cancels.alterFor(letter)) {
        add(Glyph.accidentalNatural, step);
      }
    }
  }
  final accidental = key.fifths > 0
      ? Glyph.accidentalSharp
      : Glyph.accidentalFlat;
  for (final step in keySignatureSteps(key, clef)) {
    add(accidental, step);
  }
  return items.isEmpty ? BarHead.none : BarHead(items: items, width: x);
}

const List<Glyph> timeSigDigits = [
  Glyph.timeSig0,
  Glyph.timeSig1,
  Glyph.timeSig2,
  Glyph.timeSig3,
  Glyph.timeSig4,
  Glyph.timeSig5,
  Glyph.timeSig6,
  Glyph.timeSig7,
  Glyph.timeSig8,
  Glyph.timeSig9,
];

Iterable<Glyph> digitGlyphs(int number) =>
    number.toString().codeUnits.map((unit) => timeSigDigits[unit - 0x30]);

/// A time signature from x 0. It is `timeSigCommon` or `timeSigCutCommon` for
/// those symbols, else numerator over denominator in `timeSig` digits, each row
/// centred. The groups of an additive meter are joined by plus signs. The rows
/// meet on the middle line, which is also the line of a one-line staff.
BarHead meterItems(
  Meter meter, {
  required int staff,
  required EngravingStyle style,
}) {
  final symbol = switch (meter.symbol) {
    MeterSymbol.common => Glyph.timeSigCommon,
    MeterSymbol.cut => Glyph.timeSigCutCommon,
    MeterSymbol.numeric => null,
  };
  final rows = symbol != null
      ? [
          (y: yOfStep(4), glyphs: [symbol]),
        ]
      : [
          (
            y: yOfStep(6),
            glyphs: [
              for (final (index, group) in meter.groups.indexed) ...[
                if (index > 0) Glyph.timeSigPlus,
                ...digitGlyphs(group),
              ],
            ],
          ),
          (y: yOfStep(2), glyphs: [...digitGlyphs(meter.unit)]),
        ];
  double widthOf(List<Glyph> glyphs) =>
      glyphs.fold(0, (width, glyph) => width + style.font[glyph].advance);
  final width = rows.fold<double>(
    0,
    (width, row) => math.max(width, widthOf(row.glyphs)),
  );
  final items = <HeadItem>[];
  for (final row in rows) {
    var x = (width - widthOf(row.glyphs)) / 2;
    for (final glyph in row.glyphs) {
      items.add((staff: staff, drawable: _glyph(glyph, x, row.y, style)));
      x += style.font[glyph].advance;
    }
  }
  return BarHead(items: items, width: width);
}

/// The clef changes inside the bar on one staff. Each is the small clef left
/// of everything its slice reaches to the left on any staff, which is
/// [reach] before the clefs widen it. A change at offset 0 belongs to the
/// head, not here.
List<BarItem> clefChangeItems(
  StaffView view, {
  required int staff,
  required List<Moment> times,
  required List<SliceReach> reach,
  required EngravingStyle style,
}) {
  final items = <BarItem>[];
  for (final change in view.source.clefChanges) {
    final slice = times.indexOf(change.offset);
    final (:glyph, :scale) = clefGlyph(change.clef, change: true);
    final right = -reach[slice].left - _clefChangeGap;
    items.add(
      BarItem(
        slice,
        staff,
        _clefAt(
          change.clef,
          right - style.font[glyph].box.width * scale,
          change: true,
          style: style,
        ),
      ),
    );
  }
  return items;
}

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

/// What a barline or a repeat sign is made of, left to right.
enum _Piece { thin, thick, dashed, dotted, dots }

const List<_Piece> _startRepeat = [_Piece.thick, _Piece.thin, _Piece.dots];

const List<_Piece> _endRepeat = [_Piece.dots, _Piece.thin, _Piece.thick];

const List<_Piece> _joinedRepeat = [
  _Piece.dots,
  _Piece.thin,
  _Piece.thick,
  _Piece.thin,
  _Piece.dots,
];

List<_Piece> _endPieces(BarEdges edges) => edges.repeatEnd != null
    ? _endRepeat
    : switch (edges.end) {
        Barline.regular => const [_Piece.thin],
        Barline.doubleBar => const [_Piece.thin, _Piece.thin],
        Barline.finalBar => const [_Piece.thin, _Piece.thick],
        Barline.heavy => const [_Piece.thick],
        Barline.dashed => const [_Piece.dashed],
        Barline.dotted => const [_Piece.dotted],
        Barline.invisible => const [],
      };

double _pieceWidth(_Piece piece, EngravingStyle style) => switch (piece) {
  _Piece.thin => style.font.defaults.thinBarlineThickness,
  _Piece.thick => style.font.defaults.thickBarlineThickness,
  _Piece.dashed || _Piece.dotted => style.font.defaults.dashedBarlineThickness,
  _Piece.dots => style.font[Glyph.repeatDots].box.width,
};

double _gapBefore(_Piece before, _Piece piece, EngravingStyle style) =>
    before == _Piece.dots || piece == _Piece.dots
    ? style.font.defaults.repeatBarlineDotSeparation
    : style.font.defaults.barlineSeparation;

double _piecesWidth(List<_Piece> pieces, EngravingStyle style) {
  var width = 0.0;
  for (final (index, piece) in pieces.indexed) {
    if (index > 0) {
      width += _gapBefore(pieces[index - 1], piece, style);
    }
    width += _pieceWidth(piece, style);
  }
  return width;
}

List<Drawable> _placePieces(
  List<_Piece> pieces,
  double left, {
  required List<(int, int)> groups,
  required List<double> tops,
  required EngravingStyle style,
}) {
  final drawables = <Drawable>[];
  var x = left;
  for (final (index, piece) in pieces.indexed) {
    if (index > 0) {
      x += _gapBefore(pieces[index - 1], piece, style);
    }
    final width = _pieceWidth(piece, style);
    if (piece == _Piece.dots) {
      final box = style.font[Glyph.repeatDots].box;
      for (final top in tops) {
        final origin = SpPoint(x - box.left, top + staffHeight);
        drawables.add(
          GlyphDraw(
            Glyph.repeatDots,
            origin,
            bounds: box.shift(origin.x, origin.y),
          ),
        );
      }
    } else {
      for (final (first, last) in groups) {
        drawables.add(
          LineDraw(
            SpPoint(x + width / 2, tops[first]),
            SpPoint(x + width / 2, tops[last] + staffHeight),
            thickness: width,
            dash: switch (piece) {
              _Piece.dashed => LineDash.dashed,
              _Piece.dotted => LineDash.dotted,
              _ => LineDash.solid,
            },
          ),
        );
      }
    }
    x += width;
  }
  return drawables;
}

/// The width of the bar's end barline with its repeat dots, which is the
/// rod of the bar's last slice.
double endBarlineWidth(BarEdges edges, EngravingStyle style) =>
    _piecesWidth(_endPieces(edges), style);

double startRepeatWidth(EngravingStyle style) =>
    _piecesWidth(_startRepeat, style);

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
}) {
  final drawables = <Drawable>[];
  bool repeatAlone(int index) =>
      index + 1 < bars.length &&
      bars[index + 1].of.edges.repeatStart &&
      bars[index + 1].of.edges.startJoins;
  bool joined(int index) =>
      repeatAlone(index) && bars[index].of.edges.repeatEnd != null;
  bool replaced(int index) =>
      repeatAlone(index) && bars[index].of.edges.end == Barline.regular;
  for (final (index, (of: (:edges, :head), :frame)) in bars.indexed) {
    if (edges.repeatStart && !(index > 0 && joined(index - 1))) {
      drawables.addAll(
        _placePieces(
          _startRepeat,
          frame.left + head - _headGap - startRepeatWidth(style),
          groups: groups,
          tops: tops,
          style: style,
        ),
      );
    }
    if (joined(index)) {
      drawables.addAll(
        _placePieces(
          _joinedRepeat,
          bars[index + 1].frame.left - _piecesWidth(_joinedRepeat, style) / 2,
          groups: groups,
          tops: tops,
          style: style,
        ),
      );
    } else if (!replaced(index)) {
      drawables.addAll(
        _placePieces(
          _endPieces(edges),
          frame.right,
          groups: groups,
          tops: tops,
          style: style,
        ),
      );
    }
  }
  return drawables;
}

/// How wide a brace is drawn, in staff spaces, whatever its height.
///
/// A part's height differs from system to system with its reach, and the
/// lead's indent is one value for every system. So the brace glyph is scaled
/// to this width once and stretched vertically to the part. Scaled evenly it
/// would be as wide as the part is tall, and would leave its indent on a
/// tall system.
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

  double get braceRoom => _braceRoomOf(parts);
}

double _braceRoomOf(List<LeadPart> parts) =>
    parts.any((part) => part.lastStaff > part.firstStaff) ? braceWidth : 0;

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
///
/// An indent is the widest name and a gap after it, when any part has a name,
/// and [braceWidth] when any part has two staves or more.
SystemLead systemLead(Score score, EngravingStyle style, TextMeasurer text) {
  final spec = style.specOf(TextRole.partName);
  final parts = <LeadPart>[];
  var staff = 0;
  for (final part in score.parts) {
    if (part.hidden) {
      continue;
    }
    parts.add((
      name: part.name,
      nameExtent: text.measure(part.name, spec),
      shortName: part.shortName,
      shortExtent: text.measure(part.shortName, spec),
      firstStaff: staff,
      lastStaff: staff + part.staves.length - 1,
    ));
    staff += part.staves.length;
  }
  final braceRoom = _braceRoomOf(parts);
  double indentOf(Iterable<TextExtent> names) {
    final widest = names.fold<double>(
      0,
      (widest, name) => math.max(widest, name.width),
    );
    return (widest > 0 ? widest + _nameGap : 0) + braceRoom;
  }

  return SystemLead(
    parts: parts,
    firstIndent: indentOf(parts.map((part) => part.nameExtent)),
    indent: indentOf(parts.map((part) => part.shortExtent)),
  );
}

/// The lead's drawables on one system. They are each part's name centred on
/// its staves (the full name when [first]), a brace (`Glyph.brace`,
/// [braceWidth] wide and stretched to the part's height) for a part of two
/// staves or more, and one thin line down the left edge of the staves when
/// the system has more than one.
List<Drawable> placeLead(
  SystemLead lead, {
  required bool first,
  required List<double> tops,
  required EngravingStyle style,
}) {
  final indent = first ? lead.firstIndent : lead.indent;
  final spec = style.specOf(TextRole.partName);
  final nameRight = indent - lead.braceRoom - _nameGap;
  final drawables = <Drawable>[];
  for (final part in lead.parts) {
    final top = tops[part.firstStaff];
    final bottom = tops[part.lastStaff] + staffHeight;
    final name = first ? part.name : part.shortName;
    final extent = first ? part.nameExtent : part.shortExtent;
    if (name.isNotEmpty) {
      final x = nameRight - extent.width;
      final y = (top + bottom + extent.ascent - extent.descent) / 2;
      drawables.add(
        TextDraw(
          name,
          SpPoint(x, y),
          spec: spec,
          bounds: Box(
            x,
            y - extent.ascent,
            x + extent.width,
            y + extent.descent,
          ),
        ),
      );
    }
    if (part.lastStaff > part.firstStaff) {
      drawables.add(_brace(indent - braceWidth, top, bottom, style));
    }
  }
  if (tops.length > 1) {
    final thin = style.font.defaults.thinBarlineThickness;
    drawables.add(
      LineDraw(
        SpPoint(indent + thin / 2, tops.first),
        SpPoint(indent + thin / 2, tops.last + staffHeight),
        thickness: thin,
      ),
    );
  }
  return drawables;
}

/// `Glyph.brace` with its ink from x [left] to `left + braceWidth` and
/// from [top] to [bottom]. The glyph is scaled to [braceWidth] and then
/// stretched to its height about its origin, which is at its foot.
GlyphDraw _brace(double left, double top, double bottom, EngravingStyle style) {
  final box = style.font[Glyph.brace].box;
  final scale = braceWidth / box.width;
  final stretch = (bottom - top) / (box.height * scale);
  return GlyphDraw(
    Glyph.brace,
    SpPoint(left - box.left * scale, bottom - box.bottom * scale * stretch),
    bounds: Box(left, top, left + braceWidth, bottom),
    scale: scale,
    stretch: stretch,
  );
}
