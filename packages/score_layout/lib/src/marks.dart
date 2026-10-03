/// Marks. Everything attached to a chord or a time that is not a head, a stem
/// or a beam. That is articulations, ornaments, bowing, fingering, string
/// numbers, dynamics, text, chord symbols, tempo and rehearsal marks,
/// navigation marks, and tuplet numbers and brackets. Not exported.
///
/// Marks stack outside the staff against a [Skyline], so none overlaps
/// another or the notes. Each takes the next free room on its side, in the
/// order the bar calls these functions. The skyline works at stretch 1.
/// Justification only spreads slices, so what cleared at stretch 1 clears on
/// a stretched system. A bar compressed to its rods can still collide, and
/// that bar is already wider than its system.
///
/// A mark never leaves its bar sideways. [markReach] widens the slices
/// until the rods alone hold every mark between the bar's content start and
/// its end, so a system of one bar pressed to its rods still holds them.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'chords.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'glyphs.dart';
import 'smufl_font.dart';
import 'spacing.dart';
import 'spanners.dart';
import 'style.dart';
import 'text.dart';

/// Clear space between an articulation, a fingering or a string number and
/// what it stacks on.
const double _closeGap = 0.3;

/// Clear space between any other mark and what it stacks on.
const double _markGap = 0.5;

/// Clear space between the parts of one mark, as between a tempo's words
/// and its metronome note.
const double _partGap = 0.4;

/// Clear space between two marks of one lane at neighbouring slices in a
/// bar pressed to its rods.
const double _laneGap = 0.6;

/// Clear space between a label held at the bar's end and the barline, so
/// the label does not touch what the next bar starts with over the barline,
/// as an ending's hook.
const double _endGap = 0.5;

/// Clear space between a rehearsal mark's text and its box.
const double _enclosurePad = 0.3;

/// Clear space between a tuplet's number and each half of its bracket.
const double _numberPad = 0.3;

/// What one mark draws along one baseline, around its own origin.
final class _Row {
  _Row(this._font, {this.owner});

  final SmuflFont _font;
  final Owner? owner;
  final List<Drawable> parts = [];
  double _x = 0;
  Box? _box;

  bool get isEmpty => _box == null;

  /// The union of the parts' boxes. A row with no part has none.
  Box get box => _box!;

  void glyph(Glyph glyph, {double scale = 1, double dy = 0}) {
    final metrics = _font[glyph];
    final bounds = Box(
      _x + metrics.box.left * scale,
      dy + metrics.box.top * scale,
      _x + metrics.box.right * scale,
      dy + metrics.box.bottom * scale,
    );
    parts.add(
      GlyphDraw(
        glyph,
        SpPoint(_x, dy),
        bounds: bounds,
        scale: scale,
        owner: owner,
      ),
    );
    _box = _box?.union(bounds) ?? bounds;
    _x += metrics.advance * scale;
  }

  /// Adds [text], or nothing when it is empty. With an [enclosure], the
  /// text is boxed and its bounds grow by that much on every side.
  void text(
    String text,
    TextSpec spec,
    TextMeasurer measurer, {
    double? enclosure,
  }) {
    if (text.isEmpty) {
      return;
    }
    final extent = measurer.measure(text, spec);
    final inset = enclosure ?? 0;
    final bounds = Box(
      _x,
      -extent.ascent - inset,
      _x + extent.width + 2 * inset,
      extent.descent + inset,
    );
    parts.add(
      TextDraw(
        text,
        SpPoint(_x + inset, 0),
        spec: spec,
        bounds: bounds,
        enclosed: enclosure != null,
        owner: owner,
      ),
    );
    _box = _box?.union(bounds) ?? bounds;
    _x = bounds.right;
  }

  void space(double width) => _x += width;
}

/// A mark of one event before it has a height.
typedef _Hung = ({_Row row, Side side, double gap});

/// How a direction or a system mark is held across its bar.
enum _Hold {
  /// Its origin is the mark's `x` from its slice line.
  slice,

  /// Its left edge is at the bar's content start.
  start,

  /// Its right edge is [_endGap] before the bar's end.
  end,
}

/// Marks of one lane keep their order along the bar, so the rods between
/// their slices hold each one's width.
enum _Lane { dynamics, textAbove, textBelow, chordSymbols, tempo }

/// A direction or a system mark before it has a height. Its `lane` is null
/// when it is held at the bar's start or end.
typedef _Wide = ({
  _Row row,
  int slice,
  _Hold hold,
  double x,
  Side side,
  Object? lane,
});

/// [reach] widened until the bar's rods hold every mark of [view] inside
/// the bar.
///
/// A mark of an event is centred on it, so what passes the event's own
/// reach on either side widens its slice. A tuplet's number needs the rods
/// between its ends. A direction or a tempo mark needs the rods from its
/// slice to the next mark of its lane, or to the bar's end, to hold what it
/// reaches to the right, and the rods before its slice to hold what it
/// reaches to the left. A mark held at the bar's start or end needs the
/// whole bar. What is missing is shared evenly by the slices it spans, so a
/// long tempo mark opens no gap after its own note. What a line starts with
/// is `lineStartReach` in `spanners.dart`, merged by the bar before this.
List<SliceReach> markReach(
  MeasureView view,
  Map<EventId, PlacedChord> chords,
  List<SliceReach> reach, {
  required List<Moment> times,
  required Set<EventId> trills,
  required EngravingStyle style,
  required TextMeasurer text,
}) {
  final wide = [...reach];
  final font = style.font;
  final gap = style.spacing.minGap;
  void hold(int slice, double left, double right) =>
      wide[slice] = widest(wide[slice], (left: left, right: right));

  for (final staffView in view.staves) {
    final voices = staffView.voices.length;
    final strings = staffView.part.instrument.strings.length;
    for (final voice in staffView.voices) {
      for (final timed in voice.events) {
        if (!carriesMarks(timed.event)) {
          continue;
        }
        final chord = chords[timed.event.id];
        final rows = [
          if (chord != null) ...[
            for (final entry in _articulations(chord.plan, voices, style))
              entry.mark.row,
            ?_ornament(
              chord.plan,
              voices,
              style,
              lineStarts: trills.contains(timed.event.id),
            )?.row,
            for (final mark in _stringMarks(
              chord.plan,
              voices,
              strings,
              style,
              text,
            ))
              mark.row,
          ],
          ?_fermata(timed, voices, style)?.row,
        ];
        final slice = times.indexOf(timed.onset);
        for (final row in rows) {
          if (timed.event is MeasureRest) {
            hold(slice, 0, row.box.width);
          } else {
            final centre = _centreOf(timed, chord, font);
            hold(slice, row.box.width / 2 - centre, centre + row.box.width / 2);
          }
        }
      }
      if (voice.tuplets.isEmpty) {
        continue;
      }
      final events = {for (final timed in voice.events) timed.event.id: timed};
      for (final tuplet in voice.tuplets) {
        final ends = _tupletEnds(tuplet, events, chords, times, font);
        final width = _numberRow(
          _tupletNumber(tuplet.tuplet.ratio),
          font,
        ).box.width;
        if (ends.first == ends.last) {
          final centre = (ends.left + ends.right) / 2;
          hold(ends.first, width / 2 - centre, centre + width / 2);
        } else {
          _widen(
            wide,
            ends.first,
            ends.last,
            width - ends.right + ends.left,
            gap,
          );
        }
      }
    }
  }

  final marks = [
    for (final (staff, staffView) in view.staves.indexed)
      ..._directions(
        staffView,
        staff: staff,
        times: times,
        style: style,
        text: text,
      ),
    if (view.staves.isNotEmpty)
      ..._systemMarks(view, times: times, style: style, text: text),
  ];
  final pad = style.spacing.barPad;
  final end = times.length - 1;
  final lanes = <Object, Map<int, SliceReach>>{};
  for (final mark in marks) {
    final box = mark.row.box;
    if (mark.hold != _Hold.slice) {
      final inset = mark.hold == _Hold.end ? _endGap : 0;
      _widen(wide, 0, end, box.width + inset - wide.first.left - pad, gap);
      continue;
    }
    final extent = (left: -mark.x - box.left, right: mark.x + box.right);
    if (mark.slice == 0) {
      hold(0, extent.left - pad, 0);
    } else {
      _widen(wide, 0, mark.slice, extent.left - wide.first.left - pad, gap);
    }
    final lane = lanes.putIfAbsent(mark.lane!, () => {});
    final known = lane[mark.slice];
    lane[mark.slice] = known == null ? extent : widest(known, extent);
  }
  for (final lane in lanes.values) {
    final slices = lane.keys.toList()..sort();
    for (final (index, slice) in slices.indexed) {
      final next = slices.elementAtOrNull(index + 1);
      _widen(
        wide,
        slice,
        next ?? end,
        lane[slice]!.right + (next == null ? 0 : lane[next]!.left + _laneGap),
        gap,
      );
    }
  }
  return wide;
}

/// Widens [reach] until the rods from slice [from] to slice [to] are [need]
/// wide together, each slice between them taking an equal share of what is
/// missing.
void _widen(
  List<SliceReach> reach,
  int from,
  int to,
  double need,
  double gap,
) {
  var rods = 0.0;
  for (var i = from; i < to; i++) {
    rods += reach[i].right + gap + reach[i + 1].left;
  }
  if (rods >= need || to <= from) {
    return;
  }
  final share = (need - rods) / (to - from);
  for (var i = from; i < to; i++) {
    reach[i] = (left: reach[i].left, right: reach[i].right + share);
  }
}

/// Whether [event] has a mark of its own to draw, which is an articulation,
/// an ornament, a bowing, a fingering or a string number.
bool carriesMarks(Event event) =>
    event.articulations.isNotEmpty ||
    (event is ChordEvent &&
        (event.ornament != null ||
            event.bowing != null ||
            event.notes.any(
              (note) =>
                  note is PitchedNote &&
                  (note.fingering != null || note.string != null),
            )));

/// The side the marks of an event go to. On a staff with two voices or
/// more every mark keeps to its own voice's side, as its stems do. A voice
/// [alone] on its staff puts each mark where its kind belongs.
Side _sideOf(VoiceSlot voice, int voices, Side alone) => voices < 2
    ? alone
    : voice.stemsUp
    ? Side.above
    : Side.below;

/// The x range of an event's heads, or of its rest, against its slice
/// line. A measure rest has no slice line. Its marks are centred on its bar.
({double left, double right}) _inkOf(
  TimedEvent timed,
  PlacedChord? chord,
  SmuflFont font,
) {
  if (chord != null) {
    final heads = chord.plan.headsBox;
    return (left: heads.left, right: heads.right);
  }
  switch (timed.event) {
    case RestEvent(hidden: true):
      return (left: 0, right: 0);
    case RestEvent(:final value):
      final box = font[restGlyph(value.base)].box;
      return (left: box.left, right: box.right);
    case MeasureRest() || ChordEvent():
      throw ArgumentError.value(timed.event, 'timed', 'has no ink at a slice');
  }
}

/// The x an event's marks are centred on. For a chord it is the middle of
/// the head its stem leaves, which is never a flipped one.
double _centreOf(TimedEvent timed, PlacedChord? chord, SmuflFont font) {
  if (chord == null) {
    final ink = _inkOf(timed, null, font);
    return (ink.left + ink.right) / 2;
  }
  final plan = chord.plan;
  final head = plan.stem == StemSide.up ? plan.heads.first : plan.heads.last;
  final box = plan.headBoxes[head.id]!;
  return (box.left + box.right) / 2;
}

/// The y shift that puts [box] on [side] of everything the skyline has
/// from [left] to [right], [gap] clear of it.
double _clearance(
  Skyline skyline,
  Side side,
  Box box,
  double gap,
  double left,
  double right,
) => switch (side) {
  Side.above => skyline.freeAbove(left, right) - gap - box.bottom,
  Side.below => skyline.freeBelow(left, right) + gap - box.top,
};

/// Stacks [mark] outside everything the skyline has over the mark and over
/// its event's heads or rest, centred on the event, and reserves its room.
/// Clearing the whole event keeps a narrow mark on the stem side beyond the
/// stem's tip and not beside the stem.
List<BarItem> _hang(
  _Hung mark,
  Skyline skyline,
  TimedEvent timed,
  PlacedChord? chord, {
  required int slice,
  required int staff,
  required List<double> xs,
  required SmuflFont font,
}) {
  final row = mark.row;
  final ink = _inkOf(timed, chord, font);
  final x = _centreOf(timed, chord, font) - (row.box.left + row.box.right) / 2;
  final box = row.box.shift(xs[slice] + x, 0);
  final dy = _clearance(
    skyline,
    mark.side,
    box,
    mark.gap,
    math.min(box.left, xs[slice] + ink.left),
    math.max(box.right, xs[slice] + ink.right),
  );
  skyline.add(box.shift(0, dy));
  return [
    for (final part in row.parts) BarItem(slice, staff, part.shift(x, dy)),
  ];
}

List<BarItem> _hangOnChord(
  _Hung mark,
  Skyline skyline,
  PlacedChord chord,
  List<double> xs,
  SmuflFont font,
) => _hang(
  mark,
  skyline,
  chord.plan.timed,
  chord,
  slice: chord.slice,
  staff: chord.staff,
  xs: xs,
  font: font,
);

/// Nearest the head first. A fermata is not here. [fermataItems] puts it
/// outside every other mark of its event.
const List<Articulation> _nearestFirst = [
  Articulation.staccato,
  Articulation.staccatissimo,
  Articulation.tenuto,
  Articulation.accent,
  Articulation.marcato,
  Articulation.harmonic,
];

Glyph _articulationGlyph(Articulation mark, Side side) {
  final above = side == Side.above;
  return switch (mark) {
    Articulation.staccato =>
      above ? Glyph.articStaccatoAbove : Glyph.articStaccatoBelow,
    Articulation.staccatissimo =>
      above ? Glyph.articStaccatissimoAbove : Glyph.articStaccatissimoBelow,
    Articulation.tenuto =>
      above ? Glyph.articTenutoAbove : Glyph.articTenutoBelow,
    Articulation.accent =>
      above ? Glyph.articAccentAbove : Glyph.articAccentBelow,
    Articulation.marcato =>
      above ? Glyph.articMarcatoAbove : Glyph.articMarcatoBelow,
    Articulation.harmonic => Glyph.stringsHarmonic,
    Articulation.fermata => above ? Glyph.fermataAbove : Glyph.fermataBelow,
  };
}

List<({Articulation kind, _Hung mark})> _articulations(
  ChordPlan plan,
  int voices,
  EngravingStyle style,
) {
  final stored = plan.chord.articulations;
  if (stored.isEmpty) {
    return const [];
  }
  final headSide = plan.stem == StemSide.up ? Side.below : Side.above;
  final owner = ElementOwner(plan.timed.ref);
  final marks = <({Articulation kind, _Hung mark})>[];
  for (final kind in _nearestFirst) {
    if (!stored.contains(kind)) {
      continue;
    }
    final side = _sideOf(
      plan.timed.voice,
      voices,
      kind == Articulation.harmonic ? Side.above : headSide,
    );
    marks.add((
      kind: kind,
      mark: (
        row: _Row(style.font, owner: owner)
          ..glyph(_articulationGlyph(kind, side)),
        side: side,
        gap: _closeGap,
      ),
    ));
  }
  return marks;
}

/// One glyph per `Articulation` but the fermata, in the SMuFL `Above` or
/// `Below` variant, nearest the head in the order staccato, staccatissimo,
/// tenuto, accent, marcato, harmonic.
///
/// A voice alone on its staff ([voices] is 1) puts them on the head side,
/// and the harmonic above. Staccato and tenuto then sit in the next space
/// that is clear of the head, which is the next space for a head in a space
/// and the one after it for a head on a line, as long as that space is
/// inside the staff or between the staff and the head. Every other mark,
/// and every mark after the first that leaves the staff, stacks outside the
/// staff. With two voices or more every mark stacks outside the staff on
/// its voice's side, which is the stem side.
List<BarItem> articulationItems(
  PlacedChord chord,
  Skyline skyline, {
  required int voices,
  required List<double> xs,
  required EngravingStyle style,
}) {
  final plan = chord.plan;
  final marks = _articulations(plan, voices, style);
  if (marks.isEmpty) {
    return const [];
  }
  final font = style.font;
  final up = plan.stem == StemSide.up;
  final head = up ? plan.heads.first : plan.heads.last;
  final away = up ? -1 : 1;
  var step = voices < 2 ? head.step + (head.step.isOdd ? 2 : 3) * away : null;
  final items = <BarItem>[];
  for (final (:kind, :mark) in marks) {
    final inStaff =
        step != null &&
        (kind == Articulation.staccato || kind == Articulation.tenuto) &&
        (up ? step >= 1 : step <= 7);
    if (!inStaff) {
      step = null;
      items.addAll(_hangOnChord(mark, skyline, chord, xs, font));
      continue;
    }
    final box = mark.row.box;
    final x = _centreOf(plan.timed, chord, font) - (box.left + box.right) / 2;
    final y = yOfStep(step) - (box.top + box.bottom) / 2;
    skyline.add(box.shift(xs[chord.slice] + x, y));
    for (final part in mark.row.parts) {
      items.add(BarItem(chord.slice, chord.staff, part.shift(x, y)));
    }
    step += 2 * away;
  }
  return items;
}

_Hung? _fermata(TimedEvent timed, int voices, EngravingStyle style) {
  final event = timed.event;
  if (!event.articulations.contains(Articulation.fermata) ||
      (event is RestEvent && event.hidden)) {
    return null;
  }
  final side = _sideOf(timed.voice, voices, Side.above);
  return (
    row: _Row(style.font, owner: ElementOwner(timed.ref))
      ..glyph(_articulationGlyph(Articulation.fermata, side)),
    side: side,
    gap: _markGap,
  );
}

/// The fermata of a chord or a rest, outside every other mark of its event,
/// so the bar calls this after them. It goes above, and on a staff with two
/// voices or more on its voice's side, inverted below. A measure rest's is
/// centred in the bar with its rest and keeps the whole bar's width clear,
/// since a stretch moves it against the bar's slices. A hidden rest draws
/// none.
List<BarItem> fermataItems(
  TimedEvent timed,
  Skyline skyline, {
  required PlacedChord? chord,
  required int slice,
  required int staff,
  required int voices,
  required List<double> xs,
  required EngravingStyle style,
}) {
  final mark = _fermata(timed, voices, style);
  if (mark == null) {
    return const [];
  }
  if (timed.event is! MeasureRest) {
    return _hang(
      mark,
      skyline,
      timed,
      chord,
      slice: slice,
      staff: staff,
      xs: xs,
      font: style.font,
    );
  }
  final row = mark.row;
  final x = -(row.box.left + row.box.right) / 2;
  final box = row.box.shift((xs[slice] + xs.last) / 2 + x, 0);
  final left = math.min(box.left, xs[slice]);
  final right = math.max(box.right, xs.last);
  final dy = _clearance(skyline, mark.side, box, mark.gap, left, right);
  skyline.add(Box(left, box.top + dy, right, box.bottom + dy));
  return [
    for (final part in row.parts)
      BarItem(slice, staff, part.shift(x, dy), centred: true),
  ];
}

_Hung? _ornament(
  ChordPlan plan,
  int voices,
  EngravingStyle style, {
  required bool lineStarts,
}) {
  final ornament = plan.chord.ornament;
  if (ornament == null || (lineStarts && ornament == Ornament.trill)) {
    return null;
  }
  return (
    row: _Row(style.font, owner: ElementOwner(plan.timed.ref))
      ..glyph(
        switch (ornament) {
          Ornament.trill => Glyph.ornamentTrill,
          Ornament.mordent => Glyph.ornamentMordent,
          Ornament.invertedMordent => Glyph.ornamentShortTrill,
          Ornament.turn => Glyph.ornamentTurn,
          Ornament.invertedTurn => Glyph.ornamentTurnInverted,
        },
      ),
    side: _sideOf(plan.timed.voice, voices, Side.above),
    gap: _markGap,
  );
}

/// The events a trill line starts on. Such a chord leaves its trill sign to
/// the line, which draws one.
Set<EventId> trillLineStarts(MeasureView view) => {
  for (final segment in view.spanners)
    if (segment.startsHere && segment.spanner.kind is TrillLine)
      for (final staff in view.staves)
        if (staff.source.staff == segment.spanner.staff)
          ?pieceStart(segment, staff).event,
};

/// The ornament above the staff, centred on the chord, or on its voice's
/// side on a staff with two voices or more. A trill whose chord starts a
/// `TrillLine` ([lineStarts]) leaves the sign to the spanner.
List<BarItem> ornamentItems(
  PlacedChord chord,
  Skyline skyline, {
  required int voices,
  required bool lineStarts,
  required List<double> xs,
  required EngravingStyle style,
}) {
  final mark = _ornament(chord.plan, voices, style, lineStarts: lineStarts);
  return mark == null
      ? const []
      : _hangOnChord(mark, skyline, chord, xs, style.font);
}

const List<Glyph> _fingerings = [
  Glyph.fingering0,
  Glyph.fingering1,
  Glyph.fingering2,
  Glyph.fingering3,
  Glyph.fingering4,
  Glyph.fingering5,
  Glyph.fingering6,
  Glyph.fingering7,
  Glyph.fingering8,
  Glyph.fingering9,
];

const List<Glyph> _circled = [
  Glyph.guitarString0,
  Glyph.guitarString1,
  Glyph.guitarString2,
  Glyph.guitarString3,
  Glyph.guitarString4,
  Glyph.guitarString5,
  Glyph.guitarString6,
  Glyph.guitarString7,
  Glyph.guitarString8,
  Glyph.guitarString9,
];

Iterable<Glyph> _digits(int number, List<Glyph> glyphs) =>
    '$number'.codeUnits.map((unit) => glyphs[unit - 0x30]);

String _roman(int number) {
  const numerals = [
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  final text = StringBuffer();
  var rest = number;
  for (final (value, numeral) in numerals) {
    while (rest >= value) {
      text.write(numeral);
      rest -= value;
    }
  }
  return text.toString();
}

List<_Hung> _stringMarks(
  ChordPlan plan,
  int voices,
  int strings,
  EngravingStyle style,
  TextMeasurer text,
) {
  final chord = plan.chord;
  final side = _sideOf(plan.timed.voice, voices, Side.above);
  // Stacked marks read like the heads, the highest head's on top.
  final notes = [
    for (final head in side == Side.above ? plan.heads : plan.heads.reversed)
      if (chord.note(head.id) case final PitchedNote note) note,
  ];
  final marks = <_Hung>[];
  for (final note in notes) {
    final finger = note.fingering;
    if (finger == null) {
      continue;
    }
    final row = _Row(
      style.font,
      owner: ElementOwner(NoteRef(plan.timed.ref, note.id)),
    );
    _digits(finger, _fingerings).forEach(row.glyph);
    marks.add((row: row, side: side, gap: _closeGap));
  }
  for (final note in notes) {
    final string = note.string;
    final number = string == null ? 0 : strings - string;
    if (number < 1) {
      continue;
    }
    final row = _Row(
      style.font,
      owner: ElementOwner(NoteRef(plan.timed.ref, note.id)),
    );
    if (style.stringNumbers == StringNumbers.circled && number <= 9) {
      row.glyph(_circled[number]);
    } else {
      row.text(_roman(number), style.specOf(TextRole.stringNumber), text);
    }
    marks.add((row: row, side: side, gap: _closeGap));
  }
  if (chord.bowing case final bowing?) {
    marks.add((
      row: _Row(
        style.font,
        owner: ElementOwner(plan.timed.ref),
      )..glyph(bowing == Bowing.up ? Glyph.stringsUpBow : Glyph.stringsDownBow),
      side: side,
      gap: _markGap,
    ));
  }
  return marks;
}

/// The marks of a string player, nearest the chord first. Those are each
/// head's fingering, each head's string number, then the bowing. All go
/// above, or on their voice's side on a staff with two voices or more, and
/// the marks of several heads stack in head order with the highest head's
/// on top. A string number counts from the highest of the instrument's
/// [strings], as a circled digit or a roman numeral (`style.stringNumbers`).
/// A string the instrument does not have draws nothing.
List<BarItem> stringMarkItems(
  PlacedChord chord,
  Skyline skyline, {
  required int voices,
  required int strings,
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) => [
  for (final mark in _stringMarks(chord.plan, voices, strings, style, text))
    ..._hangOnChord(mark, skyline, chord, xs, style.font),
];

/// The glyph of a dynamic level. Each level is one glyph of the font, `fp`
/// and `sfz` included.
Glyph dynamicGlyph(Dynamic level) => switch (level) {
  Dynamic.pppp => Glyph.dynamicPPPP,
  Dynamic.ppp => Glyph.dynamicPPP,
  Dynamic.pp => Glyph.dynamicPP,
  Dynamic.p => Glyph.dynamicPiano,
  Dynamic.mp => Glyph.dynamicMP,
  Dynamic.mf => Glyph.dynamicMF,
  Dynamic.f => Glyph.dynamicForte,
  Dynamic.ff => Glyph.dynamicFF,
  Dynamic.fff => Glyph.dynamicFFF,
  Dynamic.ffff => Glyph.dynamicFFFF,
  Dynamic.sf => Glyph.dynamicSforzando1,
  Dynamic.sfz => Glyph.dynamicSforzato,
  Dynamic.fp => Glyph.dynamicFortePiano,
  Dynamic.rfz => Glyph.dynamicRinforzando2,
};

/// A chord symbol's root or bass as its staff prints it.
PitchName _spelled(PitchName stored, StaffView staff, EngravingStyle style) {
  final interval = staff.part.instrument.transposition;
  if (style.chordSymbols == ChordSymbolSpelling.asStored ||
      interval == Interval.unison) {
    return stored;
  }
  final written = Pitch(
    stored.step,
    4,
    stored.alter,
  ).transpose(-interval, key: staff.writtenKey);
  return PitchName(written.step, written.alter);
}

_Row _chordSymbol(
  ChordSymbol symbol,
  StaffView staff,
  EngravingStyle style,
  TextMeasurer text,
) {
  final font = style.font;
  final spec = style.specOf(TextRole.chordSymbol);
  // A SMuFL em is four staff spaces, so a glyph set beside text is scaled
  // by a quarter of the text's size.
  final scale = spec.size / 4;
  final row = _Row(font);
  void name(PitchName stored) {
    final name = _spelled(stored, staff, style);
    row.text(name.step.name.toUpperCase(), spec, text);
    switch (name.alter.quarterTones) {
      case 0:
        break;
      case 2:
        row.glyph(Glyph.csymAccidentalSharp, scale: scale);
      case -2:
        row.glyph(Glyph.csymAccidentalFlat, scale: scale);
      case -4:
        row
          ..glyph(Glyph.csymAccidentalFlat, scale: scale)
          ..glyph(Glyph.csymAccidentalFlat, scale: scale);
      default:
        // The font has no chord-symbol glyph for these, so the staff's
        // accidental stands on the baseline at the text's size.
        final glyph = accidentalGlyph(name.alter, style.quarterTones);
        row.glyph(glyph, scale: scale, dy: -font[glyph].box.bottom * scale);
    }
  }

  name(symbol.root);
  row.text(symbol.quality, spec, text);
  if (symbol.bass case final bass?) {
    row.text('/', spec, text);
    name(bass);
  }
  return row;
}

List<_Wide> _directions(
  StaffView view, {
  required int staff,
  required List<Moment> times,
  required EngravingStyle style,
  required TextMeasurer text,
}) {
  final directions = view.source.directions;
  if (directions.isEmpty) {
    return const [];
  }
  final font = style.font;
  final marks = <_Wide>[];
  void add(
    _Row row,
    StaffDirection direction,
    Side side,
    _Lane lane, {
    double x = 0,
  }) {
    if (!row.isEmpty) {
      marks.add((
        row: row,
        slice: times.indexOf(direction.offset),
        hold: _Hold.slice,
        x: x,
        side: side,
        lane: (staff, lane),
      ));
    }
  }

  final head = font[Glyph.noteheadBlack].box;
  for (final direction in directions) {
    if (direction is DynamicMark) {
      final glyph = dynamicGlyph(direction.level);
      final metrics = font[glyph];
      final centre =
          metrics.anchors[GlyphAnchor.opticalCenter]?.x ??
          (metrics.box.left + metrics.box.right) / 2;
      add(
        _Row(font)..glyph(glyph),
        direction,
        Side.below,
        _Lane.dynamics,
        x: (head.left + head.right) / 2 - centre,
      );
    }
  }
  for (final direction in directions) {
    if (direction is TextMark) {
      add(
        _Row(font)
          ..text(direction.text, style.specOf(TextRole.expression), text),
        direction,
        direction.above ? Side.above : Side.below,
        direction.above ? _Lane.textAbove : _Lane.textBelow,
      );
    }
  }
  for (final direction in directions) {
    if (direction is ChordSymbol) {
      add(
        _chordSymbol(direction, view, style, text),
        direction,
        Side.above,
        _Lane.chordSymbols,
      );
    }
  }
  return marks;
}

/// Stacks [mark] outside everything the skyline has over it and reserves
/// its room. [left] is the bar's content start, for a mark held there.
List<BarItem> _place(
  _Wide mark,
  Skyline skyline, {
  required int staff,
  required List<double> xs,
  required double left,
}) {
  final row = mark.row;
  final x = switch (mark.hold) {
    _Hold.slice => mark.x,
    _Hold.start => left - xs[mark.slice] - row.box.left,
    _Hold.end => -row.box.right - _endGap,
  };
  final box = row.box.shift(xs[mark.slice] + x, 0);
  final dy = _clearance(skyline, mark.side, box, _markGap, box.left, box.right);
  skyline.add(box.shift(0, dy));
  return [
    for (final part in row.parts) BarItem(mark.slice, staff, part.shift(x, dy)),
  ];
}

/// The directions of one staff at their slices, the dynamics first, then
/// the text marks, then the chord symbols, each kind in stored order.
/// Dynamics go below, with their `opticalCenter` under the middle of a
/// notehead on the slice. Text marks go on their stored side and chord
/// symbols above, both starting at the slice line. A chord symbol's
/// accidentals are `csym` glyphs, and its root and bass are spelled as
/// `style.chordSymbols` asks. An empty text draws nothing.
List<BarItem> directionItems(
  StaffView view,
  Skyline skyline, {
  required int staff,
  required List<Moment> times,
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) => [
  for (final mark in _directions(
    view,
    staff: staff,
    times: times,
    style: style,
    text: text,
  ))
    ..._place(mark, skyline, staff: staff, xs: xs, left: 0),
];

String _bpm(double bpm) =>
    bpm == bpm.roundToDouble() ? '${bpm.round()}' : '$bpm';

_Row _tempo(TempoMark mark, EngravingStyle style, TextMeasurer text) {
  final font = style.font;
  final spec = style.specOf(TextRole.tempo);
  final row = _Row(font)..text(mark.text ?? '', spec, text);
  final beat = mark.showMetronome
      ? metronomeGlyphs(mark.tempo.beat)
      : const <Glyph>[];
  if (beat.isEmpty) {
    return row;
  }
  if (!row.isEmpty) {
    row.space(_partGap);
  }
  final scale = spec.size / 4;
  // A metronome note's head is centred on its baseline. Lifted by half a
  // head it stands on the text's baseline, and its dots stay beside it.
  final lift = -font[beat.first].box.bottom * scale;
  for (final (index, glyph) in beat.indexed) {
    if (index > 0) {
      row.space(_partGap * scale);
    }
    row.glyph(glyph, scale: scale, dy: lift);
  }
  return row
    ..space(_partGap)
    ..text(
      '= ${_bpm(mark.tempo.bpm)}',
      TextSpec(size: spec.size, family: spec.family),
      text,
    );
}

List<_Wide> _systemMarks(
  MeasureView view, {
  required List<Moment> times,
  required EngravingStyle style,
  required TextMeasurer text,
}) {
  final column = view.column;
  if (column.tempos.isEmpty &&
      column.navigation.isEmpty &&
      column.rehearsal == null) {
    return const [];
  }
  final font = style.font;
  final marks = <_Wide>[];
  void add(_Row row, _Hold hold, {int slice = 0, Object? lane}) {
    if (!row.isEmpty) {
      marks.add((
        row: row,
        slice: slice,
        hold: hold,
        x: 0,
        side: Side.above,
        lane: lane,
      ));
    }
  }

  for (final tempo in column.tempos) {
    add(
      _tempo(tempo, style, text),
      _Hold.slice,
      slice: times.indexOf(tempo.offset),
      lane: _Lane.tempo,
    );
  }
  for (final mark in column.navigation) {
    final sign = switch (mark) {
      Segno() => Glyph.segno,
      Coda() => Glyph.coda,
      ToCoda() || Fine() || Jump() => null,
    };
    if (sign != null) {
      add(_Row(font)..glyph(sign), _Hold.start);
    }
  }
  for (final mark in column.navigation) {
    final label = switch (mark) {
      ToCoda() => mark.label,
      Fine() => mark.label,
      Jump() => mark.label,
      Segno() || Coda() => null,
    };
    if (label != null) {
      add(
        _Row(font)..text(label, style.specOf(TextRole.navigation), text),
        _Hold.end,
        slice: times.length - 1,
      );
    }
  }
  add(
    _Row(font)..text(
      column.rehearsal ?? '',
      style.specOf(TextRole.rehearsal),
      text,
      enclosure: _enclosurePad + font.defaults.textEnclosureThickness,
    ),
    _Hold.start,
  );
  return marks;
}

/// What the bar prints above its top staff, in the order it stacks. Each
/// tempo mark starts at its slice line, as its words, then its metronome
/// note, then `= ` and its number. Segno and coda start at [left], the
/// bar's content start. `ToCoda.label`, `Fine.label` and `Jump.label` end
/// just before the bar's end. The rehearsal mark starts at [left] in a box,
/// outside the rest. The items sit on staff 0, against [top]. A mark with
/// nothing to print draws nothing.
List<BarItem> systemMarkItems(
  MeasureView view,
  Skyline top, {
  required List<Moment> times,
  required List<double> xs,
  required double left,
  required EngravingStyle style,
  required TextMeasurer text,
}) => [
  for (final mark in _systemMarks(view, times: times, style: style, text: text))
    ..._place(mark, top, staff: 0, xs: xs, left: left),
];

/// Metronome glyphs for a beat value, which are the `metNote` of its base,
/// then one `metAugmentationDot` per dot. Empty for a breve and for a value
/// shorter than a sixteenth, which the font's table has no note for. A
/// tempo mark with such a beat prints its words alone.
List<Glyph> metronomeGlyphs(NoteValue beat) {
  final note = switch (beat.base) {
    DurationBase.whole => Glyph.metNoteWhole,
    DurationBase.half => Glyph.metNoteHalfUp,
    DurationBase.quarter => Glyph.metNoteQuarterUp,
    DurationBase.eighth => Glyph.metNote8thUp,
    DurationBase.sixteenth => Glyph.metNote16thUp,
    _ => null,
  };
  return note == null
      ? const []
      : [note, for (var i = 0; i < beat.dots; i++) Glyph.metAugmentationDot];
}

/// A tuplet's number and bracket, decided in bar space. The system draws
/// it, because a bracket spans slices that the stretch moves apart. Like a
/// beam between stems it belongs to no one event, so it has no owner.
final class TupletStub {
  const TupletStub({
    required this.first,
    required this.last,
    required this.digits,
    required this.bracket,
    required this.side,
  });

  /// The bracket's ends, at the left edge of the first event's heads or
  /// rest and the right edge of the last's, already clear of the skyline.
  /// Both are at one height, the bracket's line, which runs through the
  /// middle of the number.
  final BarAnchor first;
  final BarAnchor last;

  /// The number, or the ratio with `tupletColon` when the tuplet's ratio
  /// is not the usual one for its number.
  final List<Glyph> digits;

  /// False when the tuplet's events are exactly one beam group and it is
  /// `TupletBracket.auto`, or when it is `hidden`.
  final bool bracket;

  final Side side;

  @override
  bool operator ==(Object other) =>
      other is TupletStub &&
      other.first == first &&
      other.last == last &&
      other.digits.length == digits.length &&
      other.digits.indexed.every((digit) => digits[digit.$1] == digit.$2) &&
      other.bracket == bracket &&
      other.side == side;

  @override
  int get hashCode => Object.hash(first, last, bracket, side);
}

const List<Glyph> _tupletDigits = [
  Glyph.tuplet0,
  Glyph.tuplet1,
  Glyph.tuplet2,
  Glyph.tuplet3,
  Glyph.tuplet4,
  Glyph.tuplet5,
  Glyph.tuplet6,
  Glyph.tuplet7,
  Glyph.tuplet8,
  Glyph.tuplet9,
];

/// What a tuplet of [actual] notes usually stands in the time of, so that
/// its number alone says it. A number stands for the largest power of two
/// below it. A power of two is itself a tuplet only in compound time, where
/// two stand for three and any other for three quarters of itself.
int _usualNormal(int actual) {
  var below = 1;
  while (below * 2 < actual) {
    below *= 2;
  }
  if (below * 2 != actual) {
    return below;
  }
  return actual == 2 ? 3 : actual ~/ 4 * 3;
}

List<Glyph> _tupletNumber(TupletRatio ratio) => [
  ..._digits(ratio.actual, _tupletDigits),
  if (ratio.normal != _usualNormal(ratio.actual)) ...[
    Glyph.tupletColon,
    ..._digits(ratio.normal, _tupletDigits),
  ],
];

_Row _numberRow(List<Glyph> digits, SmuflFont font) {
  final row = _Row(font);
  digits.forEach(row.glyph);
  return row;
}

/// The slice and the x from it of each end of [tuplet].
({int first, double left, int last, double right}) _tupletEnds(
  TupletView tuplet,
  Map<EventId, TimedEvent> events,
  Map<EventId, PlacedChord> chords,
  List<Moment> times,
  SmuflFont font,
) {
  final first = events[tuplet.events.first]!;
  final last = events[tuplet.events.last]!;
  return (
    first: times.indexOf(first.onset),
    left: _inkOf(first, chords[first.event.id], font).left,
    last: times.indexOf(last.onset),
    right: _inkOf(last, chords[last.event.id], font).right,
  );
}

/// The tuplets of one voice, innermost first, so an inner bracket sits
/// nearer the notes. Each goes on the side most of its chords' stems point
/// to, which is the beam side of a beamed tuplet, above when the sides are
/// even, and on its voice's side when it holds rests alone. Each reserves
/// one row of [skyline] from its first event to its last, as high as its
/// number, where the number and the bracket are drawn at any stretch.
List<TupletStub> tupletStubs(
  VoiceView voice,
  Map<EventId, PlacedChord> chords,
  Skyline skyline, {
  required int staff,
  required List<Moment> times,
  required List<double> xs,
  required EngravingStyle style,
}) {
  if (voice.tuplets.isEmpty) {
    return const [];
  }
  final font = style.font;
  final events = {for (final timed in voice.events) timed.event.id: timed};
  final order = [for (var i = 0; i < voice.tuplets.length; i++) i]
    ..sort((a, b) {
      final deeper = voice.tuplets[b].depth - voice.tuplets[a].depth;
      return deeper != 0 ? deeper : a - b;
    });
  final stubs = <TupletStub>[];
  for (final index in order) {
    final tuplet = voice.tuplets[index];
    var up = 0;
    var down = 0;
    for (final id in tuplet.events) {
      switch (chords[id]?.plan.stem) {
        case StemSide.up:
          up++;
        case StemSide.down:
          down++;
        case null:
      }
    }
    final side = up + down == 0
        ? (voice.slot.stemsUp ? Side.above : Side.below)
        : (up >= down ? Side.above : Side.below);
    final digits = _tupletNumber(tuplet.tuplet.ratio);
    final number = _numberRow(digits, font).box;
    final ends = _tupletEnds(tuplet, events, chords, times, font);
    final from = xs[ends.first] + ends.left;
    final to = xs[ends.last] + ends.right;
    final left = math.min(from, (from + to - number.width) / 2);
    final right = math.max(to, (from + to + number.width) / 2);
    final half = number.height / 2;
    final line = switch (side) {
      Side.above => skyline.freeAbove(left, right) - _markGap - half,
      Side.below => skyline.freeBelow(left, right) + _markGap + half,
    };
    skyline.add(Box(left, line - half, right, line + half));
    stubs.add(
      TupletStub(
        first: (slice: ends.first, dx: ends.left, staff: staff, dy: line),
        last: (slice: ends.last, dx: ends.right, staff: staff, dy: line),
        digits: digits,
        bracket: switch (tuplet.tuplet.bracket) {
          TupletBracket.shown => true,
          TupletBracket.hidden => false,
          TupletBracket.auto => !voice.beams.any(
            (group) => _sameEvents(group.events, tuplet.events),
          ),
        },
        side: side,
      ),
    );
  }
  return stubs;
}

bool _sameEvents(List<EventId> a, List<EventId> b) =>
    a.length == b.length && a.indexed.every((id) => b[id.$1] == id.$2);

/// The number centred between the ends, and the bracket as two lines with
/// hooks, `tupletBracketThickness` thick, broken around the number. The
/// hooks point to the notes and are half as long as the number is high. A
/// bracket with no room for a line on each side of its number is left out.
List<Drawable> placeTuplet(
  TupletStub stub,
  BarFrame frame,
  EngravingStyle style,
) {
  final from = frame.at(stub.first);
  final to = frame.at(stub.last);
  final row = _numberRow(stub.digits, style.font);
  final box = row.box;
  final x = (from.x + to.x - box.left - box.right) / 2;
  final y = from.y - (box.top + box.bottom) / 2;
  final drawables = <Drawable>[for (final part in row.parts) part.shift(x, y)];
  final thickness = style.font.defaults.tupletBracketThickness;
  final left = x + box.left - _numberPad;
  final right = x + box.right + _numberPad;
  if (!stub.bracket || left - from.x < thickness || to.x - right < thickness) {
    return drawables;
  }
  final toNotes = stub.side == Side.above ? 1.0 : -1.0;
  final tip = from.y + toNotes * box.height / 2;
  final corner = from.y - toNotes * thickness / 2;
  LineDraw line(SpPoint a, SpPoint b) => LineDraw(a, b, thickness: thickness);
  return drawables
    ..add(
      line(
        SpPoint(from.x + thickness / 2, tip),
        SpPoint(from.x + thickness / 2, corner),
      ),
    )
    ..add(line(from, SpPoint(left, from.y)))
    ..add(line(SpPoint(right, to.y), to))
    ..add(
      line(
        SpPoint(to.x - thickness / 2, corner),
        SpPoint(to.x - thickness / 2, tip),
      ),
    );
}
