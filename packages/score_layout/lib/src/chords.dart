/// Chords and rests. Heads, accidentals, dots, stems, flags, ledger lines and
/// grace notes. Not exported.
///
/// A chord is planned before spacing (which glyphs, on which steps, on
/// which side of the stem, how wide) and placed after it (against which
/// slice). The plan carries its reach, so spacing keeps slices apart
/// without knowing what a chord is.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'glyphs.dart';
import 'signatures.dart';
import 'smufl_font.dart';
import 'spacing.dart';
import 'spanners.dart';
import 'style.dart';

enum StemSide { up, down }

/// Length of a stem beyond its far head, in staff spaces.
const double stemLength = 3.5;

const double _accidentalGap = 0.25;
const double _accidentalClearance = 0.1;
const double _dotGap = 0.5;
const double _dotSpacing = 0.25;

/// Clear space between the last grace and its principal, and between
/// graces.
const double _graceGap = 0.5;
const double _graceSpacing = 0.3;

/// How far a tremolo's strokes sit from the far head along the stem, and
/// how far the stem's tip, a flag or a beam stays clear of them.
const double _tremoloRise = 2;
const double _tremoloClearance = 0.5;

/// Whether a chord's value has a stem, and whether the chord draws it or
/// leaves it to its beam.
enum _Stemming { none, drawn, byBeam }

/// One notehead as planned.
final class HeadPlan {
  const HeadPlan({
    required this.id,
    required this.glyph,
    required this.step,
    required this.column,
    this.accidental,
    this.cautionary = false,
    this.ink = InkRole.normal,
  });

  final NoteId id;
  final Glyph glyph;

  /// Staff step, 0 at the bottom line. A pitched note takes it from
  /// `Clef.staffStepOf` of its written pitch (`StaffView.writtenPitches`,
  /// under the clef in effect at its onset). A drum note takes it from its
  /// kit sound's position.
  final int step;

  /// 0 for a head on its own side of the stem. A head a second or less from
  /// one there stands in column 1, across the stem, and one that close to a
  /// head in each of those in column 2, beyond column 1, and so on outward.
  final int column;

  final Glyph? accidental;

  /// Print the accidental in parentheses.
  final bool cautionary;

  /// [InkRole.outOfRange] for a note outside its instrument's range.
  final InkRole ink;
}

/// A chord planned against its own slice line. The plan holds the chord's
/// drawables, made once. Placing wraps them against a slice, and a beam
/// reads the stem off them.
final class ChordPlan {
  const ChordPlan._(
    this._ink, {
    required this.timed,
    required this.chord,
    required this.stem,
    required this.heads,
    required this.reach,
    required this.graces,
  });

  final TimedEvent timed;
  final ChordEvent chord;
  final StemSide stem;

  /// Sorted by step, lowest first.
  final List<HeadPlan> heads;

  /// Accidentals, grace notes and the further head columns of a downstem
  /// chord to the left of the slice line. Heads, the further head columns of
  /// an upstem chord, dots and the flag to the right.
  final SliceReach reach;

  /// Grace chords in order, planned at the style's grace scale.
  final List<GracePlan> graces;

  final _ChordInk _ink;

  /// Each head's box against the slice line, by note.
  Map<NoteId, Box> get headBoxes => _ink.headBoxes;

  /// The union of [headBoxes].
  Box get headsBox => _ink.headsBox;
}

/// One grace chord before a principal.
final class GracePlan {
  const GracePlan._(
    this._ink, {
    required this.source,
    required this.x,
  });

  final GraceChord source;

  /// Where the grace's own slice line sits, left of the principal's.
  final double x;

  final _ChordInk _ink;

  /// Each head's box against the grace's own slice line, before [x].
  Map<NoteId, Box> get headBoxes => _ink.headBoxes;
}

/// A planned chord with its place in the bar. Beams, ties, tuplets and
/// spanners find their ends through it.
typedef PlacedChord = ({ChordPlan plan, int slice, int staff});

/// The stem side of [chord]. A stored `ChordEvent.stem` wins. With two or
/// more voices on the staff the voice decides (`VoiceSlot.stemsUp`). With
/// one voice the mean step against the middle line decides, under the clef
/// in effect [at] the chord's onset, and a chord centred on it stems down.
/// A beam group overrides this with one side for all its chords (see
/// `beamStemSides`).
StemSide stemSideFor(
  ChordEvent chord,
  StaffView staff,
  VoiceSlot slot, {
  required Moment at,
}) {
  switch (chord.stem) {
    case StemDirection.up:
      return StemSide.up;
    case StemDirection.down:
      return StemSide.down;
    case StemDirection.auto:
      break;
  }
  if (staff.voices.length >= 2) {
    return slot.stemsUp ? StemSide.up : StemSide.down;
  }
  final clef = staff.source.clefAt(at);
  var steps = 0;
  for (final note in chord.notes) {
    steps += clef.staffStepOf(staff.writtenPitches[note.id]!);
  }
  return steps < 4 * chord.notes.length ? StemSide.up : StemSide.down;
}

/// Plans [chord]. The plan has head glyphs from its value and
/// `StaffView.headOf`, steps, a column for each head so that those of a
/// second or a unison stand side by side, accidentals from
/// `StaffView.accidentals` stacked right to left by descending step, dots in
/// the next space up, the flag from the value, and each grace chord at its
/// place left of the principal. A [beamed] chord's reach leaves its flag
/// out, because the beam replaces it. The staff's [lines] decide its ledger
/// lines.
ChordPlan planChord({
  required TimedEvent timed,
  required ChordEvent chord,
  required StaffView staff,
  required int lines,
  required StemSide stem,
  required bool beamed,
  required EngravingStyle style,
}) {
  final clef = staff.source.clefAt(timed.onset);
  final heads = _planHeads(
    chord.notes,
    chord.value.base,
    stem,
    staff,
    clef,
    style,
  );
  final flag = _flagOf(chord.value.base, stem);
  final ink = _ChordInk.of(
    heads: heads,
    lines: lines,
    stem: stem,
    dots: chord.value.dots,
    flag: flag,
    tremolo: chord.tremolo,
    stemming: beamed ? _Stemming.byBeam : _stemmingOf(chord.value.base),
    slashed: false,
    scale: 1,
    owner: ElementOwner(timed.ref),
    headOwner: (head) => ElementOwner(NoteRef(timed.ref, head.id)),
    style: style,
  );
  var left = ink.left;
  final graces = <GracePlan>[];
  for (final grace in chord.graces.toList().reversed) {
    final graceHeads = _planHeads(
      grace.notes,
      grace.value.base,
      StemSide.up,
      staff,
      clef,
      style,
    );
    final graceOwner = ElementOwner(timed.ref);
    final graceInk = _ChordInk.of(
      heads: graceHeads,
      lines: lines,
      stem: StemSide.up,
      dots: grace.value.dots,
      flag: _flagOf(grace.value.base, StemSide.up),
      tremolo: 0,
      stemming: _stemmingOf(grace.value.base),
      slashed: grace.kind == GraceKind.acciaccatura,
      scale: style.graceScale,
      owner: graceOwner,
      headOwner: (_) => graceOwner,
      style: style,
    );
    final gap = graces.isEmpty ? _graceGap : _graceSpacing;
    final x = left - gap - graceInk.right;
    graces.insert(
      0,
      GracePlan._(graceInk, source: grace, x: x),
    );
    left = x + graceInk.left;
  }
  return ChordPlan._(
    ink,
    timed: timed,
    chord: chord,
    stem: stem,
    heads: heads,
    reach: (left: math.max(0, -left), right: math.max(0, ink.right)),
    graces: graces,
  );
}

/// The chord's items against [slice]. They are heads, accidentals, dots, ledger
/// lines (for steps below 0 or above 8, extended by `legerLineExtension`, each
/// spanning the heads on it or beyond it) and tremolo strokes. A one-line staff
/// has no ledger lines, since engravers write its heads above, on or below the
/// line. A chord planned unbeamed also has its stem, from the outer head's
/// `stemUpSE` or `stemDownNW` anchor to a tip [stemLength] beyond the far head
/// and never short of the middle line, and its flag at the tip. Dots that a
/// flag would reach move past the flag. A chord planned beamed has neither stem
/// nor flag. Its stem depends on the stretch, so `placeBeam` draws it at system
/// time.
///
/// A head is owned by its `NoteRef`. Everything else is owned by the
/// event's `EventRef`.
List<BarItem> placeChord(
  ChordPlan plan, {
  required int slice,
  required int staff,
}) => [
  for (final drawable in plan._ink.drawables) BarItem(slice, staff, drawable),
];

/// The grace chords of [plan], left of the principal at the style's grace
/// scale, each with its stem up and its flag, and a slash through the stem
/// of each acciaccatura, where the font's eighth flag puts it.
///
/// A tied grace note joins the head of the same `Note.tone` in the next
/// grace chord, or in the principal when it is the last grace. With no
/// such head the tie is a short let-ring tie. The curve lies inside the
/// principal's slice, so it is a bar item and never crosses a barline.
///
/// A grace chord has no reference of its own, so every grace drawable,
/// heads included, is owned by the principal's `EventRef`.
List<BarItem> graceItems(
  ChordPlan plan, {
  required int slice,
  required int staff,
  required EngravingStyle style,
}) {
  final owner = ElementOwner(plan.timed.ref);
  final items = <BarItem>[];
  for (final (index, grace) in plan.graces.indexed) {
    for (final drawable in grace._ink.drawables) {
      items.add(BarItem(slice, staff, drawable.shift(grace.x, 0)));
    }
    final next = plan.graces.elementAtOrNull(index + 1);
    for (final note in grace.source.notes) {
      if (!note.tie) {
        continue;
      }
      final from = grace.headBoxes[note.id]!.shift(grace.x, 0);
      final to = next == null
          ? _headOfTone(plan.chord.notes, plan.headBoxes, note.tone)
          : _headOfTone(
              next.source.notes,
              next.headBoxes,
              note.tone,
            )?.shift(next.x, 0);
      items.add(
        BarItem(slice, staff, graceTie(from, to, owner: owner, style: style)),
      );
    }
  }
  return items;
}

Box? _headOfTone(Iterable<Note> notes, Map<NoteId, Box> boxes, Tone tone) {
  final note = notes.where((note) => note.tone == tone).firstOrNull;
  return note == null ? null : boxes[note.id];
}

/// Where a chord's stem leaves its heads, the y of the head it reaches past,
/// and the y a beam's inner edge must stay beyond (`keep`), which is the far
/// head's y, or the far edge of the tremolo strokes plus their clearance.
/// All against the chord's slice line.
({double x, double start, double far, double keep}) stemOf(ChordPlan plan) => (
  x: plan._ink.stemX,
  start: plan._ink.stemStart,
  far: plan._ink.farY,
  keep: plan._ink.keep,
);

/// How far a rest's glyph and dots reach from its slice line. A
/// `MeasureRest` is centred in its bar, and reaches its glyph's width so
/// that a bar pressed to its rods still holds it.
SliceReach restReach(Event rest, EngravingStyle style) => switch (rest) {
  RestEvent(hidden: true) => noReach,
  MeasureRest() => (left: 0, right: style.font[Glyph.restWhole].box.width),
  RestEvent(:final value) => (
    left: 0,
    right: _dotsRight(
      style.font[restGlyph(value.base)].box.right,
      value.dots,
      style.font[Glyph.augmentationDot].box.width,
    ),
  ),
  ChordEvent() => throw ArgumentError.value(rest, 'rest', 'is a chord'),
};

/// A rest's glyph from its value, on the middle line, moved up for an
/// upstem voice and down for a downstem voice when the staff has
/// [voiceCount] of two or more. A hidden rest draws nothing. A
/// `MeasureRest` is a whole rest centred between its slice and the bar's
/// end (`BarItem.centred`), hung from step 6, or from the line of a
/// one-line staff ([lines]).
List<BarItem> placeRest({
  required TimedEvent timed,
  required int slice,
  required int staff,
  required int voiceCount,
  required int lines,
  required EngravingStyle style,
}) {
  final owner = ElementOwner(timed.ref);
  final font = style.font;
  final shift = voiceCount < 2 ? 0.0 : (timed.voice.stemsUp ? -1.0 : 1.0);
  switch (timed.event) {
    case RestEvent(hidden: true):
      return const [];
    case RestEvent(:final value):
      final glyph = restGlyph(value.base);
      final origin = SpPoint(0, _restLine(value.base, lines) + shift);
      final box = font[glyph].box.shift(origin.x, origin.y);
      final dot = font[Glyph.augmentationDot].box;
      return [
        BarItem(
          slice,
          staff,
          GlyphDraw(glyph, origin, bounds: box, owner: owner),
        ),
        for (var i = 0; i < value.dots; i++)
          BarItem(
            slice,
            staff,
            _dot(dot, box.right, i, yOfStep(5) + shift, 1, owner),
          ),
      ];
    case MeasureRest():
      final box = font[Glyph.restWhole].box;
      final origin = SpPoint(
        -box.width / 2 - box.left,
        _restLine(DurationBase.whole, lines) + shift,
      );
      return [
        BarItem(
          slice,
          staff,
          GlyphDraw(
            Glyph.restWhole,
            origin,
            bounds: box.shift(origin.x, origin.y),
            owner: owner,
          ),
          centred: true,
        ),
      ];
    case ChordEvent():
      throw ArgumentError.value(timed.event, 'timed', 'is a chord');
  }
}

/// The y a rest's origin sits on. A whole rest hangs from the line above
/// the middle, which a one-line staff does not have.
double _restLine(DurationBase base, int lines) =>
    yOfStep(base == DurationBase.whole && lines != 1 ? 6 : 4);

/// y of the origin of a rest run's count from the top line of its staff.
/// The digits reach one space each way from it, so they stand one space
/// clear of the staff.
const double _countY = -2;

/// A run of [count] rest-only bars as one multi-measure rest on every
/// staff. It is an H-bar on the middle line from [left] to [right], less a
/// bar pad at each end to stand clear of the head before it and the barline
/// after it, with the count centred above it in `timeSig` digits.
///
/// The H-bar is the font's two end pieces joined by a line as thick as its
/// middle piece, so it is as long as the system makes it.
List<Drawable> placeRestRun(
  int count, {
  required double left,
  required double right,
  required List<double> tops,
  required EngravingStyle style,
}) {
  final font = style.font;
  final from = left + style.spacing.barPad;
  final to = right - style.spacing.barPad;
  final leftBox = font[Glyph.restHBarLeft].box;
  final rightBox = font[Glyph.restHBarRight].box;
  final middle = font[Glyph.restHBarMiddle].box;
  final digits = [...digitGlyphs(count)];
  final digitsWidth = digits.fold<double>(
    0,
    (width, glyph) => width + font[glyph].advance,
  );
  final drawables = <Drawable>[];
  for (final top in tops) {
    final line = top + yOfStep(4);
    final leftEnd = SpPoint(from - leftBox.left, line);
    final rightEnd = SpPoint(to - rightBox.right, line);
    drawables
      ..add(
        GlyphDraw(
          Glyph.restHBarLeft,
          leftEnd,
          bounds: leftBox.shift(leftEnd.x, leftEnd.y),
        ),
      )
      ..add(
        LineDraw(
          SpPoint(
            from + leftBox.width,
            line + (middle.top + middle.bottom) / 2,
          ),
          SpPoint(to - rightBox.width, line + (middle.top + middle.bottom) / 2),
          thickness: middle.height,
        ),
      )
      ..add(
        GlyphDraw(
          Glyph.restHBarRight,
          rightEnd,
          bounds: rightBox.shift(rightEnd.x, rightEnd.y),
        ),
      );
    var x = (from + to - digitsWidth) / 2;
    for (final glyph in digits) {
      final origin = SpPoint(x, top + _countY);
      drawables.add(
        GlyphDraw(
          glyph,
          origin,
          bounds: font[glyph].box.shift(origin.x, origin.y),
        ),
      );
      x += font[glyph].advance;
    }
  }
  return drawables;
}

/// How far the count of a rest run reaches above the top line of its staff.
double restRunRise(EngravingStyle style) =>
    timeSigDigits.fold<double>(
      0,
      (rise, glyph) => math.max(rise, -style.font[glyph].box.top),
    ) -
    _countY;

typedef _HeadGlyphs = ({Glyph breve, Glyph whole, Glyph half, Glyph black});

const Map<NoteHead, _HeadGlyphs> _headGlyphs = {
  NoteHead.normal: (
    breve: Glyph.noteheadDoubleWhole,
    whole: Glyph.noteheadWhole,
    half: Glyph.noteheadHalf,
    black: Glyph.noteheadBlack,
  ),
  NoteHead.cross: (
    breve: Glyph.noteheadXDoubleWhole,
    whole: Glyph.noteheadXWhole,
    half: Glyph.noteheadXHalf,
    black: Glyph.noteheadXBlack,
  ),
  NoteHead.diamond: (
    breve: Glyph.noteheadDiamondDoubleWhole,
    whole: Glyph.noteheadDiamondWhole,
    half: Glyph.noteheadDiamondHalf,
    black: Glyph.noteheadDiamondBlack,
  ),
  NoteHead.slash: (
    breve: Glyph.noteheadSlashWhiteDoubleWhole,
    whole: Glyph.noteheadSlashWhiteWhole,
    half: Glyph.noteheadSlashWhiteHalf,
    black: Glyph.noteheadSlashHorizontalEnds,
  ),
  NoteHead.triangle: (
    breve: Glyph.noteheadTriangleUpDoubleWhole,
    whole: Glyph.noteheadTriangleUpWhole,
    half: Glyph.noteheadTriangleUpHalf,
    black: Glyph.noteheadTriangleUpBlack,
  ),
  NoteHead.circleCross: (
    breve: Glyph.noteheadCircleXDoubleWhole,
    whole: Glyph.noteheadCircleXWhole,
    half: Glyph.noteheadCircleXHalf,
    black: Glyph.noteheadCircleX,
  ),
};

/// The head glyph for a value and a head shape. A breve takes the
/// `DoubleWhole` glyph of the shape, a whole and a half their own, and a
/// quarter or shorter the black one.
Glyph noteheadGlyph(DurationBase base, NoteHead head) {
  final glyphs = _headGlyphs[head]!;
  return switch (base) {
    DurationBase.breve => glyphs.breve,
    DurationBase.whole => glyphs.whole,
    DurationBase.half => glyphs.half,
    _ => glyphs.black,
  };
}

const Map<DurationBase, Glyph> _restGlyphs = {
  DurationBase.breve: Glyph.restDoubleWhole,
  DurationBase.whole: Glyph.restWhole,
  DurationBase.half: Glyph.restHalf,
  DurationBase.quarter: Glyph.restQuarter,
  DurationBase.eighth: Glyph.rest8th,
  DurationBase.sixteenth: Glyph.rest16th,
  DurationBase.thirtySecond: Glyph.rest32nd,
  DurationBase.sixtyFourth: Glyph.rest64th,
  DurationBase.oneTwentyEighth: Glyph.rest128th,
};

Glyph restGlyph(DurationBase base) => _restGlyphs[base]!;

/// The accidental glyph for [alter] in the chosen quarter-tone family.
Glyph accidentalGlyph(Alter alter, QuarterToneGlyphs family) {
  final stein = family == QuarterToneGlyphs.steinZimmermann;
  return switch (alter.quarterTones) {
    -4 => Glyph.accidentalDoubleFlat,
    -3 =>
      stein
          ? Glyph.accidentalThreeQuarterTonesFlatZimmermann
          : Glyph.accidentalThreeQuarterTonesFlatArrowDown,
    -2 => Glyph.accidentalFlat,
    -1 =>
      stein
          ? Glyph.accidentalQuarterToneFlatStein
          : Glyph.accidentalQuarterToneFlatNaturalArrowDown,
    0 => Glyph.accidentalNatural,
    1 =>
      stein
          ? Glyph.accidentalQuarterToneSharpStein
          : Glyph.accidentalQuarterToneSharpNaturalArrowUp,
    2 => Glyph.accidentalSharp,
    3 =>
      stein
          ? Glyph.accidentalThreeQuarterTonesSharpStein
          : Glyph.accidentalThreeQuarterTonesSharpArrowUp,
    4 => Glyph.accidentalDoubleSharp,
    _ => throw ArgumentError.value(alter, 'alter', 'outside two sharps'),
  };
}

const List<({Glyph up, Glyph down})> _flags = [
  (up: Glyph.flag8thUp, down: Glyph.flag8thDown),
  (up: Glyph.flag16thUp, down: Glyph.flag16thDown),
  (up: Glyph.flag32ndUp, down: Glyph.flag32ndDown),
  (up: Glyph.flag64thUp, down: Glyph.flag64thDown),
  (up: Glyph.flag128thUp, down: Glyph.flag128thDown),
];

Glyph? _flagOf(DurationBase base, StemSide side) {
  final beams = base.beams;
  if (beams == 0) {
    return null;
  }
  final flag = _flags[beams - 1];
  return side == StemSide.up ? flag.up : flag.down;
}

const List<Glyph> _tremolos = [
  Glyph.tremolo1,
  Glyph.tremolo2,
  Glyph.tremolo3,
  Glyph.tremolo4,
];

/// The heads of one chord or grace chord, lowest first, each in its column.
/// The walk starts at the head the stem leaves, and a head takes the first
/// column that holds no earlier head a second or less away.
List<HeadPlan> _planHeads(
  Iterable<Note> notes,
  DurationBase base,
  StemSide stem,
  StaffView staff,
  Clef clef,
  EngravingStyle style,
) {
  final instrument = staff.part.instrument;
  final stepped = [
    for (final note in notes)
      (note: note, step: clef.staffStepOf(staff.writtenPitches[note.id]!)),
  ]..sort((a, b) => a.step.compareTo(b.step));
  final column = List.filled(stepped.length, 0);
  final up = stem == StemSide.up;
  final last = <int>[];
  for (var n = 0; n < stepped.length; n++) {
    final i = up ? n : stepped.length - 1 - n;
    final step = stepped[i].step;
    var free = last.indexWhere((taken) => (step - taken).abs() > 1);
    if (free < 0) {
      free = last.length;
      last.add(step);
    } else {
      last[free] = step;
    }
    column[i] = free;
  }
  return [
    for (final (i, head) in stepped.indexed)
      () {
        final mark = staff.accidentals[head.note.id];
        return HeadPlan(
          id: head.note.id,
          glyph: noteheadGlyph(base, staff.headOf(head.note)),
          step: head.step,
          column: column[i],
          accidental: mark == null
              ? null
              : accidentalGlyph(mark.alter, style.quarterTones),
          cautionary: mark?.cautionary ?? false,
          ink: _inkOf(head.note, instrument),
        );
      }(),
  ];
}

InkRole _inkOf(Note note, Instrument instrument) {
  if (note is! PitchedNote) {
    return InkRole.normal;
  }
  final low = instrument.lowest;
  final high = instrument.highest;
  final outside =
      (low != null && note.pitch.compareTo(low) < 0) ||
      (high != null && note.pitch.compareTo(high) > 0);
  return outside ? InkRole.outOfRange : InkRole.normal;
}

_Stemming _stemmingOf(DurationBase base) =>
    base == DurationBase.whole || base == DurationBase.breve
    ? _Stemming.none
    : _Stemming.drawn;

/// Where a flag meets the stem: its `stemUpNW` or `stemDownSW` anchor, or
/// the matching corner of its box when the font has none.
SpPoint _flagStemAnchor(GlyphMetrics metrics, bool up) =>
    metrics.anchors[up ? GlyphAnchor.stemUpNW : GlyphAnchor.stemDownSW] ??
    SpPoint(metrics.box.left, up ? metrics.box.top : metrics.box.bottom);

/// How far a flag hung from the stem's tip reaches back toward the heads.
double _flagReach(SmuflFont font, Glyph flag, bool up, double scale) {
  final metrics = font[flag];
  final anchor = _scaledPoint(_flagStemAnchor(metrics, up), scale);
  final box = _scaled(metrics.box, scale);
  return up ? box.bottom - anchor.y : anchor.y - box.top;
}

/// Accidentals that share one column left of a chord, because none of
/// them overlaps another vertically.
final class _AccidentalColumn {
  final entries = <({List<Glyph> run, double y, double top, double bottom})>[];
  double width = 0;

  bool fits(double top, double bottom) => entries.every(
    (entry) =>
        bottom + _accidentalClearance <= entry.top ||
        top - _accidentalClearance >= entry.bottom,
  );
}

/// The drawables of one chord or grace chord against its own slice line,
/// at one scale, and what later steps read off them.
final class _ChordInk {
  const _ChordInk({
    required this.drawables,
    required this.headBoxes,
    required this.headsBox,
    required this.left,
    required this.right,
    required this.stemX,
    required this.stemStart,
    required this.farY,
    required this.keep,
  });

  factory _ChordInk.of({
    required List<HeadPlan> heads,
    required int lines,
    required StemSide stem,
    required int dots,
    required Glyph? flag,
    required int tremolo,
    required _Stemming stemming,
    required bool slashed,
    required double scale,
    required Owner owner,
    required Owner Function(HeadPlan head) headOwner,
    required EngravingStyle style,
  }) {
    final font = style.font;
    final defaults = font.defaults;
    final up = stem == StemSide.up;
    final thickness = defaults.stemThickness * scale;
    final start = up ? heads.first : heads.last;
    final far = up ? heads.last : heads.first;
    final startMetrics = font[start.glyph];
    final startAnchor = _scaledPoint(
      startMetrics.anchors[up
              ? GlyphAnchor.stemUpSE
              : GlyphAnchor.stemDownNW] ??
          SpPoint(up ? startMetrics.box.right : startMetrics.box.left, 0),
      scale,
    );
    final stemLeft = up ? startAnchor.x - thickness : startAnchor.x;
    final stemX = stemLeft + thickness / 2;
    final drawables = <Drawable>[];

    // Column 1 starts at the stem's far edge. Each column after it starts
    // where the widest head of the one before ends.
    final outermost = heads.fold(
      0,
      (most, head) => math.max(most, head.column),
    );
    final origins = [for (final head in heads) SpPoint(0, yOfStep(head.step))];
    var columnFrom = up ? stemLeft + thickness : stemLeft;
    for (var column = 1; column <= outermost; column++) {
      var columnEnd = columnFrom;
      for (final (i, head) in heads.indexed) {
        if (head.column != column) {
          continue;
        }
        final box = _scaled(font[head.glyph].box, scale);
        final x = up ? columnFrom - box.left : columnFrom - box.right;
        origins[i] = SpPoint(x, origins[i].y);
        columnEnd = up
            ? math.max(columnEnd, x + box.right)
            : math.min(columnEnd, x + box.left);
      }
      columnFrom = columnEnd;
    }
    final headBoxes = <NoteId, Box>{};
    Box? headsBox;
    for (final (i, head) in heads.indexed) {
      final origin = origins[i];
      final at = _scaled(font[head.glyph].box, scale).shift(origin.x, origin.y);
      headBoxes[head.id] = at;
      headsBox = headsBox?.union(at) ?? at;
      drawables.add(
        GlyphDraw(
          head.glyph,
          origin,
          bounds: at,
          scale: scale,
          owner: headOwner(head),
          ink: head.ink,
        ),
      );
    }
    final heads0 = headsBox!;

    var inkLeft = heads0.left;
    final extension = defaults.legerLineExtension * scale;
    void ledger(int line, bool Function(int step) served) {
      Box? span;
      for (final (i, head) in heads.indexed) {
        if (served(head.step)) {
          final box = _scaled(font[head.glyph].box, scale);
          final at = box.shift(origins[i].x, origins[i].y);
          span = span?.union(at) ?? at;
        }
      }
      final y = yOfStep(line);
      inkLeft = math.min(inkLeft, span!.left - extension);
      drawables.add(
        LineDraw(
          SpPoint(span.left - extension, y),
          SpPoint(span.right + extension, y),
          thickness: defaults.legerLineThickness * scale,
          owner: owner,
        ),
      );
    }

    if (lines > 1) {
      for (var line = -2; line >= heads.first.step; line -= 2) {
        ledger(line, (step) => step <= line);
      }
      for (var line = 10; line <= heads.last.step; line += 2) {
        ledger(line, (step) => step >= line);
      }
    }

    final columns = <_AccidentalColumn>[];
    for (var i = heads.length - 1; i >= 0; i--) {
      final head = heads[i];
      final accidental = head.accidental;
      if (accidental == null) {
        continue;
      }
      final run = [
        if (head.cautionary) Glyph.accidentalParensLeft,
        accidental,
        if (head.cautionary) Glyph.accidentalParensRight,
      ];
      final y = origins[i].y;
      var width = 0.0;
      var top = double.infinity;
      var bottom = double.negativeInfinity;
      for (final glyph in run) {
        final box = _scaled(font[glyph].box, scale);
        width += box.width;
        top = math.min(top, y + box.top);
        bottom = math.max(bottom, y + box.bottom);
      }
      final column =
          columns.where((c) => c.fits(top, bottom)).firstOrNull ??
          (() {
            final fresh = _AccidentalColumn();
            columns.add(fresh);
            return fresh;
          })();
      column
        ..entries.add((run: run, y: y, top: top, bottom: bottom))
        ..width = math.max(column.width, width);
    }
    var edge = inkLeft - _accidentalGap * scale;
    for (final column in columns) {
      for (final entry in column.entries) {
        var x = edge;
        for (final glyph in entry.run.reversed) {
          final box = _scaled(font[glyph].box, scale);
          x -= box.right;
          final origin = SpPoint(x, entry.y);
          drawables.add(
            GlyphDraw(
              glyph,
              origin,
              bounds: box.shift(origin.x, origin.y),
              scale: scale,
              owner: owner,
            ),
          );
          x += box.left;
        }
      }
      edge -= column.width + _accidentalGap * scale;
    }

    final startY = origins[heads.indexOf(start)].y + startAnchor.y;
    final farY = yOfStep(far.step);
    final stemmed = stemming == _Stemming.drawn;
    final clearance = _tremoloClearance * scale;
    ({Glyph glyph, SpPoint origin, Box box})? strokes;
    if (tremolo > 0) {
      final glyph = _tremolos[math.min(tremolo, _tremolos.length) - 1];
      final origin = SpPoint(
        stemming == _Stemming.none ? (heads0.left + heads0.right) / 2 : stemX,
        up ? farY - _tremoloRise * scale : farY + _tremoloRise * scale,
      );
      strokes = (
        glyph: glyph,
        origin: origin,
        box: _scaled(font[glyph].box, scale).shift(origin.x, origin.y),
      );
    }
    var length = stemLength * scale;
    if (strokes != null) {
      length = math.max(
        length,
        (up ? farY - strokes.box.top : strokes.box.bottom - farY) +
            clearance +
            (stemmed && flag != null ? _flagReach(font, flag, up, scale) : 0),
      );
    }
    var tipY = up ? farY - length : farY + length;
    if (scale == 1) {
      tipY = up ? math.min(tipY, yOfStep(4)) : math.max(tipY, yOfStep(4));
    }
    GlyphDraw? flagDraw;
    if (stemmed && flag != null) {
      final metrics = font[flag];
      final anchor = _scaledPoint(_flagStemAnchor(metrics, up), scale);
      final origin = SpPoint(stemLeft - anchor.x, tipY - anchor.y);
      flagDraw = GlyphDraw(
        flag,
        origin,
        bounds: _scaled(metrics.box, scale).shift(origin.x, origin.y),
        scale: scale,
        owner: owner,
      );
    }

    if (dots > 0) {
      final dot = _scaled(font[Glyph.augmentationDot].box, scale);
      final rows = [
        for (final step in {
          for (final head in heads) head.step.isOdd ? head.step : head.step + 1,
        })
          yOfStep(step),
      ];
      final flagBox = flagDraw?.bounds;
      final from =
          flagBox != null &&
              rows.any(
                (y) =>
                    y + dot.top < flagBox.bottom &&
                    y + dot.bottom > flagBox.top,
              )
          ? math.max(heads0.right, flagBox.right)
          : heads0.right;
      for (final y in rows) {
        for (var i = 0; i < dots; i++) {
          drawables.add(_dot(dot, from, i, y, scale, owner));
        }
      }
    }

    if (stemmed) {
      drawables.add(
        LineDraw(
          SpPoint(stemX, startY),
          SpPoint(stemX, tipY),
          thickness: thickness,
          owner: owner,
        ),
      );
      if (flagDraw != null) {
        drawables.add(flagDraw);
      }
      if (slashed) {
        final eighth = font[up ? Glyph.flag8thUp : Glyph.flag8thDown];
        final meets = _flagStemAnchor(eighth, up);
        final low =
            eighth.anchors[up
                ? GlyphAnchor.graceNoteSlashSW
                : GlyphAnchor.graceNoteSlashNW];
        final high =
            eighth.anchors[up
                ? GlyphAnchor.graceNoteSlashNE
                : GlyphAnchor.graceNoteSlashSE];
        if (low != null && high != null) {
          drawables.add(
            LineDraw(
              SpPoint(
                stemLeft + (low.x - meets.x) * scale,
                tipY + (low.y - meets.y) * scale,
              ),
              SpPoint(
                stemLeft + (high.x - meets.x) * scale,
                tipY + (high.y - meets.y) * scale,
              ),
              thickness: thickness,
              owner: owner,
            ),
          );
        }
      }
    }
    if (strokes != null) {
      drawables.add(
        GlyphDraw(
          strokes.glyph,
          strokes.origin,
          bounds: strokes.box,
          scale: scale,
          owner: owner,
        ),
      );
    }

    var left = double.infinity;
    var right = double.negativeInfinity;
    for (final drawable in drawables) {
      left = math.min(left, drawable.bounds.left);
      right = math.max(right, drawable.bounds.right);
    }
    return _ChordInk(
      drawables: drawables,
      headBoxes: headBoxes,
      headsBox: heads0,
      left: left,
      right: right,
      stemX: stemX,
      stemStart: startY,
      farY: farY,
      keep: strokes == null
          ? farY
          : up
          ? strokes.box.top - clearance
          : strokes.box.bottom + clearance,
    );
  }

  final List<Drawable> drawables;

  final Map<NoteId, Box> headBoxes;
  final Box headsBox;

  /// The leftmost and rightmost ink.
  final double left;
  final double right;

  /// The stem's centre line.
  final double stemX;

  /// Where the stem leaves its head, and the y of the head it reaches past.
  final double stemStart;
  final double farY;

  /// The y a beam's inner edge must stay beyond: [farY], or the far edge of
  /// the tremolo strokes plus their clearance.
  final double keep;
}

/// Dot [index] of a row that starts [_dotGap] right of [from], at [y].
GlyphDraw _dot(
  Box dot,
  double from,
  int index,
  double y,
  double scale,
  Owner owner,
) {
  final x =
      from +
      _dotGap * scale +
      index * (dot.width + _dotSpacing * scale) -
      dot.left;
  return GlyphDraw(
    Glyph.augmentationDot,
    SpPoint(x, y),
    bounds: dot.shift(x, y),
    scale: scale,
    owner: owner,
  );
}

/// The right edge of [dots] dots after ink that ends at [from].
double _dotsRight(double from, int dots, double dotWidth) => dots == 0
    ? from
    : from + _dotGap + dots * dotWidth + (dots - 1) * _dotSpacing;

Box _scaled(Box box, double scale) => scale == 1
    ? box
    : Box(
        box.left * scale,
        box.top * scale,
        box.right * scale,
        box.bottom * scale,
      );

SpPoint _scaledPoint(SpPoint point, double scale) =>
    scale == 1 ? point : SpPoint(point.x * scale, point.y * scale);
