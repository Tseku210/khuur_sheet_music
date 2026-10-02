/// Ties, spanners and volta brackets. Everything that can cross a barline. Not
/// exported.
///
/// A cross-bar piece is drawn by the system, because only the system knows
/// where it starts and ends on the line. It is decided by the bar. Each bar
/// a piece passes through stores a stub with its resolved anchors and
/// reserves the piece's room in its own skyline, so the bar's extents, and
/// through them the system's planned height, already hold the piece. The
/// system then draws inside that room and never outside it.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'chords.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'glyphs.dart';
import 'smufl_font.dart';
import 'style.dart';
import 'text.dart';

/// The most a tie's arc rises from its ends, in staff spaces.
const double tieRise = 0.75;

/// The room a bar reserves outside its notes and marks for a slur passing
/// over it, in staff spaces. A slur's arc is kept inside it, so a long slur
/// is flatter than an engraver would draw it and never leaves its band.
const double slurRise = 2;

/// The length of a let-ring tie, which has no head to land on.
const double letRingLength = 1.5;

/// Clear space between a head's edge and the end of a tie or a glissando.
const double _tieGap = 0.2;

/// Clear space between a slur's end and the outline of its chord.
const double _slurGap = 0.5;

/// Clear space between a line or a volta and what it clears.
const double _lineGap = 0.5;

/// How far apart a hairpin's lines are at its open end.
const double _hairpinOpening = 1.2;

/// Clear space after the glyph or text a line starts with.
const double _startGap = 0.3;

/// How far a line's end stays before the slice it ends at.
const double _endPad = 0.5;

/// The least height of a volta bracket's hooks.
const double _voltaHook = 2;

/// Clear space between a volta's line and its label.
const double _voltaPad = 0.3;

/// The side a slur or a trill line is drawn on, in every bar it crosses.
///
/// It comes from the spanner alone, never from the stems of one bar. A bar
/// sees only its own stems, so a slur over a barline between a stems-up
/// bar and a stems-down bar would be given two sides and would have room on
/// neither.
Side curveSide(Spanner spanner) => switch (spanner.kind) {
  Slur() when !(spanner.voice ?? VoiceSlot.one).stemsUp => Side.below,
  _ => Side.above,
};

/// One end of a tie, or both, as one bar sees it.
sealed class TieEnd {
  const TieEnd({required this.owner, required this.side});

  /// The note the tie starts from, or for [TieArriving] the note it lands
  /// on.
  final Owner owner;

  final Side side;
}

/// Both heads are in this bar.
final class TieWithin extends TieEnd {
  const TieWithin({
    required this.from,
    required this.to,
    required super.owner,
    required super.side,
  });

  final BarAnchor from;
  final BarAnchor to;

  @override
  bool operator ==(Object other) =>
      other is TieWithin &&
      other.from == from &&
      other.to == to &&
      other.owner == owner &&
      other.side == side;

  @override
  int get hashCode => Object.hash(from, to, owner, side);
}

/// The tie leaves for note [to] in the next bar (`TieView.crossesBarline`).
final class TieLeaving extends TieEnd {
  const TieLeaving({
    required this.from,
    required this.to,
    required super.owner,
    required super.side,
  });

  final BarAnchor from;
  final NoteId to;

  @override
  bool operator ==(Object other) =>
      other is TieLeaving &&
      other.from == from &&
      other.to == to &&
      other.owner == owner &&
      other.side == side;

  @override
  int get hashCode => Object.hash(from, to, owner, side);
}

/// A tie from the previous bar lands on [note] (`StaffView.tiedIn`).
final class TieArriving extends TieEnd {
  const TieArriving({
    required this.note,
    required this.to,
    required super.owner,
    required super.side,
  });

  final NoteId note;
  final BarAnchor to;

  @override
  bool operator ==(Object other) =>
      other is TieArriving &&
      other.note == note &&
      other.to == to &&
      other.owner == owner &&
      other.side == side;

  @override
  int get hashCode => Object.hash(note, to, owner, side);
}

/// No head to land on, which is a let-ring tie of [letRingLength].
final class TieOpen extends TieEnd {
  const TieOpen({
    required this.from,
    required super.owner,
    required super.side,
  });

  final BarAnchor from;

  @override
  bool operator ==(Object other) =>
      other is TieOpen &&
      other.from == from &&
      other.owner == owner &&
      other.side == side;

  @override
  int get hashCode => Object.hash(from, owner, side);
}

/// The tie ends of one staff of a bar, from `StaffView.ties` and
/// `StaffView.tiedIn`. Each anchor is the head's edge at its vertical
/// middle, a little outside it. Each end reserves [tieRise] in [skyline]
/// from its head to the bar's edge, or between its two heads. [left] is the
/// bar's content start in bar space, where an arriving half tie begins.
List<TieEnd> tieEnds(
  StaffView view,
  Map<EventId, PlacedChord> chords,
  Skyline skyline, {
  required int staff,
  required List<double> xs,
  required double left,
}) {
  final holders = _holders(view, chords);

  double x(BarAnchor anchor) => xs[anchor.slice] + anchor.dx;
  void reserve(double x0, double x1, double y, Side side) {
    final lo = math.min(x0, x1);
    final hi = math.max(x0, x1);
    skyline.add(switch (side) {
      Side.above => Box(lo, y - tieRise, hi, y),
      Side.below => Box(lo, y, hi, y + tieRise),
    });
  }

  final ends = <TieEnd>[];
  for (final tie in view.ties) {
    final placed = holders[tie.from]!;
    final side = _tieSide(placed.plan, tie.from);
    final owner = ElementOwner(NoteRef(placed.plan.timed.ref, tie.from));
    final from = _tieAnchor(placed, tie.from, staff: staff, leaving: true);
    if (_letsRing(tie, chords)) {
      ends.add(TieOpen(from: from, owner: owner, side: side));
      reserve(x(from), x(from) + letRingLength, from.dy, side);
      continue;
    }
    final target = tie.to!;
    if (tie.crossesBarline) {
      ends.add(
        TieLeaving(from: from, to: target.note, owner: owner, side: side),
      );
      reserve(x(from), xs.last, from.dy, side);
      continue;
    }
    final to = _tieAnchor(
      chords[target.event.id]!,
      target.note,
      staff: staff,
      leaving: false,
    );
    ends.add(TieWithin(from: from, to: to, owner: owner, side: side));
    final y = switch (side) {
      Side.above => math.min(from.dy, to.dy),
      Side.below => math.max(from.dy, to.dy),
    };
    reserve(x(from), x(to), y, side);
  }
  for (final note in view.tiedIn) {
    final placed = holders[note]!;
    final to = _tieAnchor(placed, note, staff: staff, leaving: false);
    ends.add(
      TieArriving(
        note: note,
        to: to,
        owner: ElementOwner(NoteRef(placed.plan.timed.ref, note)),
        side: _tieSide(placed.plan, note),
      ),
    );
    for (final side in Side.values) {
      reserve(left, x(to), to.dy, side);
    }
  }
  return ends;
}

/// The slice and right reach of every let-ring tie of [view]. The stub is
/// content to the right of its chord, like a dot or a flag, so spacing makes
/// room for it before the next slice.
List<({int slice, double right})> letRingReach(
  StaffView view,
  Map<EventId, PlacedChord> chords,
) {
  final holders = _holders(view, chords);
  return [
    for (final tie in view.ties)
      if (_letsRing(tie, chords))
        if (holders[tie.from] case final placed?)
          (
            slice: placed.slice,
            right:
                placed.plan.headBoxes[tie.from]!.right +
                _tieGap +
                letRingLength,
          ),
  ];
}

/// The slice and right reach of what every line starting in [view] starts
/// with: a tempo line's text, a pedal line's "Ped.", an octave line's glyph
/// and a trill line's sign. It is content right of the line's start, like a
/// dot or a flag, so spacing makes room for it before the next slice, and a
/// line that starts on a system's last beat has room for its text inside
/// the system.
List<({int slice, double right})> lineStartReach(
  MeasureView view,
  Map<EventId, PlacedChord> chords, {
  required List<Moment> times,
  required EngravingStyle style,
  required TextMeasurer text,
}) => [
  for (final segment in view.spanners)
    if (segment.startsHere)
      for (final staffView in view.staves)
        if (staffView.source.staff == segment.spanner.staff)
          ?_startReach(
            segment,
            staffView,
            chords,
            times: times,
            style: style,
            text: text,
          ),
];

/// The slice and right reach of what the line of [segment] starts with, or
/// null for a kind that starts with nothing.
({int slice, double right})? _startReach(
  SpannerSegment segment,
  StaffView staffView,
  Map<EventId, PlacedChord> chords, {
  required List<Moment> times,
  required EngravingStyle style,
  required TextMeasurer text,
}) {
  final kind = segment.spanner.kind;
  final width = switch (kind) {
    TempoLine(text: final label) =>
      text.measure(label, style.specOf(TextRole.expression)).width,
    OctaveLine() || PedalLine() || TrillLine() => _rowWidth(
      _startGlyphs(kind),
      style.font,
    ),
    Slur() || Glissando() || Hairpin() => null,
  };
  if (width == null) {
    return null;
  }
  final start = pieceStart(segment, staffView);
  final chord = start.event == null ? null : chords[start.event];
  final (:slice, :dx) = _lineStart(start, chord, times);
  return (slice: slice, right: dx + width);
}

/// The width the system head grows by when a tie, slur or octave line
/// arrives in the bar from an earlier system. An arriving tie or slur gets
/// a stub at least [letRingLength] long before the head it lands on. An
/// arriving octave line restates its glyph in parentheses, which ends at or
/// before the bar's first slice. Both start where the head glyphs end and
/// run through the bar's [lead] in front of its first slice.
double arrivingRoom(
  List<TieEnd> ends,
  List<SpannerPiece> pieces, {
  required List<double> xs,
  required double lead,
  required EngravingStyle style,
}) {
  final defaults = style.font.defaults;
  double shortfall(BarAnchor to, double inset) =>
      letRingLength - (xs[to.slice] + to.dx + lead - inset);
  return [
    0.0,
    for (final end in ends)
      if (end case TieArriving(:final to)) shortfall(to, _tieInset(defaults)),
    for (final piece in pieces)
      if (!piece.startsHere)
        switch (piece.kind) {
          Slur() => shortfall(piece.until, _inset(piece.kind, defaults)),
          OctaveLine() =>
            _inset(piece.kind, defaults) +
                _rowWidth(_restatedGlyphs(piece.kind), style.font) -
                lead,
          _ => 0.0,
        },
  ].reduce(math.max);
}

double _tieInset(EngravingDefaults defaults) =>
    (defaults.tieMidpointThickness + defaults.tieEndpointThickness) / 2;

/// Whether [tie] has no head to land on, which is when the model gives it
/// no target, or its target's chord is in this bar but has no head of that
/// note.
bool _letsRing(TieView tie, Map<EventId, PlacedChord> chords) =>
    switch (tie.to) {
      null => true,
      final target => !tie.crossesBarline && !_holds(chords, target),
    };

/// The chord of [view] holding each note.
Map<NoteId, PlacedChord> _holders(
  StaffView view,
  Map<EventId, PlacedChord> chords,
) {
  final holders = <NoteId, PlacedChord>{};
  for (final voice in view.voices) {
    for (final timed in voice.events) {
      if (timed.event case ChordEvent(:final id, :final notes)) {
        final placed = chords[id];
        if (placed != null) {
          for (final note in notes) {
            holders[note.id] = placed;
          }
        }
      }
    }
  }
  return holders;
}

/// Whether the chord of [target] is in this bar and has its head.
bool _holds(Map<EventId, PlacedChord> chords, NoteRef target) =>
    chords[target.event.id]?.plan.headBoxes.containsKey(target.note) ?? false;

BarAnchor _tieAnchor(
  PlacedChord placed,
  NoteId note, {
  required int staff,
  required bool leaving,
}) {
  final head = placed.plan.headBoxes[note]!;
  return (
    slice: placed.slice,
    dx: leaving ? head.right + _tieGap : head.left - _tieGap,
    staff: staff,
    dy: (head.top + head.bottom) / 2,
  );
}

/// The side a tie from [note] curves to. A single note curves away from its
/// stem. In a chord the lower half of the heads curve down, the upper half
/// up, and an odd middle head away from the stem.
Side _tieSide(ChordPlan plan, NoteId note) {
  final count = plan.heads.length;
  final index = plan.heads.indexWhere((head) => head.id == note);
  if (index < count ~/ 2) {
    return Side.below;
  }
  if (index > (count - 1) ~/ 2) {
    return Side.above;
  }
  return plan.stem == StemSide.up ? Side.below : Side.above;
}

/// The ties of one system.
List<Drawable> placeTies(
  List<Framed<List<TieEnd>>> bars, {
  required double left,
  required double right,
  required EngravingStyle style,
}) {
  final inset = _tieInset(style.font.defaults);
  final drawables = <Drawable>[];
  for (final (index, (:of, :frame)) in bars.indexed) {
    for (final end in of) {
      switch (end) {
        case TieWithin(:final from, :final to):
          drawables.add(
            _tie(
              frame.at(from),
              frame.at(to),
              side: end.side,
              owner: end.owner,
              style: style,
            ),
          );
        case TieLeaving(:final from, :final to):
          final start = frame.at(from);
          var stop = SpPoint(right - inset, start.y);
          if (bars.elementAtOrNull(index + 1) case (
            of: final nextEnds,
            frame: final nextFrame,
          )) {
            final arriving = nextEnds
                .whereType<TieArriving>()
                .where((end) => end.note == to)
                .firstOrNull;
            if (arriving != null) {
              stop = nextFrame.at(arriving.to);
            }
          }
          drawables.add(
            _tie(start, stop, side: end.side, owner: end.owner, style: style),
          );
        case TieArriving(:final to) when index == 0:
          final stop = frame.at(to);
          drawables.add(
            _tie(
              SpPoint(left + inset, stop.y),
              stop,
              side: end.side,
              owner: end.owner,
              style: style,
            ),
          );
        case TieArriving():
          break;
        case TieOpen(:final from):
          final start = frame.at(from);
          drawables.add(
            _tie(
              start,
              SpPoint(start.x + letRingLength, start.y),
              side: end.side,
              owner: end.owner,
              style: style,
            ),
          );
      }
    }
  }
  return drawables;
}

/// The tie of a grace note from its head [from] to the head [to] of the
/// same tone, or a let-ring tie when [to] is null. Both boxes are in one
/// space. It curves below, since grace stems are up, at the style's grace
/// scale.
CurveDraw graceTie(
  Box from,
  Box? to, {
  required Owner owner,
  required EngravingStyle style,
}) {
  final scale = style.graceScale;
  final start = SpPoint(from.right + _tieGap * scale, _middle(from));
  final stop = to == null
      ? SpPoint(start.x + letRingLength * scale, start.y)
      : SpPoint(to.left - _tieGap * scale, _middle(to));
  return _tie(
    start,
    stop,
    side: Side.below,
    owner: owner,
    style: style,
    scale: scale,
  );
}

double _middle(Box box) => (box.top + box.bottom) / 2;

/// A tie from [from] to [to], outside its own anchors by at most [tieRise]
/// at [scale].
CurveDraw _tie(
  SpPoint from,
  SpPoint to, {
  required Side side,
  required Owner owner,
  required EngravingStyle style,
  double scale = 1,
}) {
  final defaults = style.font.defaults;
  final rise = tieRise * scale;
  final clear = switch (side) {
    Side.above => math.min(from.y, to.y),
    Side.below => math.max(from.y, to.y),
  };
  return curveBetween(
    from,
    to,
    side: side,
    rise: rise,
    clear: clear,
    limit: side == Side.above ? clear - rise : clear + rise,
    endThickness: defaults.tieEndpointThickness * scale,
    midThickness: defaults.tieMidpointThickness * scale,
    owner: owner,
  );
}

/// The part of one spanner inside one bar, resolved from the bar's
/// `SpannerSegment` alone.
final class SpannerPiece {
  const SpannerPiece({
    required this.owner,
    required this.kind,
    required this.from,
    required this.until,
    required this.startsHere,
    required this.endsHere,
    required this.side,
    required this.clear,
    required this.limit,
    required this.textExtent,
  });

  final SpannerOwner owner;
  final SpannerKind kind;

  /// Where the piece starts in this bar, by [pieceStart].
  final BarAnchor from;

  /// Where the piece ends in this bar, by [pieceEnd].
  final BarAnchor until;

  final bool startsHere;
  final bool endsHere;

  /// The same in every bar the spanner crosses.
  final Side side;

  /// The y, from the top line of the piece's staff, of the inner edge of
  /// the room this bar reserved for the piece. Everything the bar has on
  /// [side] over the piece's x range lies inside it, so a curve that stays
  /// outside it touches no note and no mark of this bar.
  final double clear;

  /// The y of the outer edge of that room. Nothing of the piece is drawn
  /// past it.
  final double limit;

  /// A tempo line's text as the bar measured it.
  final TextExtent? textExtent;

  @override
  bool operator ==(Object other) =>
      other is SpannerPiece &&
      other.owner == owner &&
      other.kind == kind &&
      other.from == from &&
      other.until == until &&
      other.startsHere == startsHere &&
      other.endsHere == endsHere &&
      other.side == side &&
      other.clear == clear &&
      other.limit == limit &&
      other.textExtent == textExtent;

  @override
  int get hashCode => Object.hash(
    owner,
    kind,
    from,
    until,
    startsHere,
    endsHere,
    side,
    clear,
    limit,
    textExtent,
  );
}

/// The spanner pieces of a bar, one per `SpannerSegment` on a visible
/// staff, in reservation order. Each reserves its room in the skyline of
/// its staff.
List<SpannerPiece> spannerPieces(
  MeasureView view,
  List<Skyline> skylines,
  Map<EventId, PlacedChord> chords, {
  required List<Moment> times,
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) {
  final segments = <(SpannerSegment, int)>[];
  for (final segment in view.spanners) {
    final staff = view.staves.indexWhere(
      (staff) => staff.source.staff == segment.spanner.staff,
    );
    if (staff >= 0) {
      segments.add((segment, staff));
    }
  }
  return [
    for (var rank = 0; rank <= _lastRank; rank++)
      for (final (segment, staff) in segments)
        if (_rank(segment.spanner.kind) == rank)
          _piece(
            segment,
            view.staves[staff],
            skylines[staff],
            chords,
            staff: staff,
            barLength: view.column.length,
            times: times,
            xs: xs,
            style: style,
            text: text,
          ),
  ];
}

const int _lastRank = 6;

/// The reservation order of the kinds.
int _rank(SpannerKind kind) => switch (kind) {
  Slur() => 0,
  Hairpin() => 1,
  OctaveLine() => 2,
  PedalLine() => 3,
  TrillLine() => 4,
  TempoLine() => 5,
  Glissando() => _lastRank,
};

SpannerPiece _piece(
  SpannerSegment segment,
  StaffView staffView,
  Skyline sky,
  Map<EventId, PlacedChord> chords, {
  required int staff,
  required Length barLength,
  required List<Moment> times,
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) {
  final spanner = segment.spanner;
  final kind = spanner.kind;
  final side = _sideOf(spanner);
  final s = side == Side.above ? -1.0 : 1.0;
  final start = pieceStart(segment, staffView);
  final end = pieceEnd(segment, staffView, barLength);
  final startChord = start.event == null ? null : chords[start.event];
  final endChord = end.event == null ? null : chords[end.event];
  double free(double x0, double x1) => switch (side) {
    Side.above => sky.freeAbove(math.min(x0, x1), math.max(x0, x1)),
    Side.below => sky.freeBelow(math.min(x0, x1), math.max(x0, x1)),
  };
  void reserve(double x0, double x1, double clear, double limit) {
    final lo = math.min(x0, x1);
    final hi = math.max(x0, x1);
    sky.add(
      side == Side.above
          ? Box(lo, limit, hi, clear)
          : Box(lo, clear, hi, limit),
    );
  }

  SpannerPiece piece({
    required BarAnchor from,
    required BarAnchor until,
    required double clear,
    required double limit,
    TextExtent? textExtent,
  }) => SpannerPiece(
    owner: SpannerOwner(spanner.id),
    kind: kind,
    from: from,
    until: until,
    startsHere: segment.startsHere,
    endsHere: segment.endsHere,
    side: side,
    clear: clear,
    limit: limit,
    textExtent: textExtent,
  );

  switch (kind) {
    case Slur():
      final (slice: fromSlice, dx: fromDx) = _lineStart(
        start,
        startChord,
        times,
      );
      final untilSlice = endChord?.slice ?? times.indexOf(end.at);
      final untilDx = endChord == null ? 0.0 : _centre(endChord.plan);
      final x0 = xs[fromSlice] + fromDx;
      final x1 = xs[untilSlice] + untilDx;
      final clear = free(x0, x1);
      final limit = clear + s * slurRise;
      double dy(PlacedChord? chord) {
        if (chord == null) {
          return clear + s * _slurGap;
        }
        final heads = chord.plan.headsBox.shift(xs[chord.slice], 0);
        return free(heads.left, heads.right) + s * _slurGap;
      }

      final from = (
        slice: fromSlice,
        dx: fromDx,
        staff: staff,
        dy: dy(startChord),
      );
      final until = (
        slice: untilSlice,
        dx: untilDx,
        staff: staff,
        dy: dy(endChord),
      );
      reserve(x0, x1, clear, limit);
      return piece(from: from, until: until, clear: clear, limit: limit);
    case Glissando():
      final from = startChord == null
          ? (
              slice: times.indexOf(start.at),
              dx: 0.0,
              staff: staff,
              dy: yOfStep(4),
            )
          : (
              slice: startChord.slice,
              dx: startChord.plan.headsBox.right + _tieGap,
              staff: staff,
              dy: _middle(startChord.plan.headsBox),
            );
      final until = endChord == null
          ? (
              slice: times.indexOf(end.at),
              dx: 0.0,
              staff: staff,
              dy: yOfStep(4),
            )
          : (
              slice: endChord.slice,
              dx: endChord.plan.headsBox.left - _tieGap,
              staff: staff,
              dy: _middle(endChord.plan.headsBox),
            );
      return piece(from: from, until: until, clear: from.dy, limit: from.dy);
    case Hairpin() || OctaveLine() || PedalLine() || TrillLine() || TempoLine():
      final extent = kind is TempoLine
          ? text.measure(kind.text, style.specOf(TextRole.expression))
          : null;
      final room = _roomOf(kind, style, extent)!;
      final (slice: fromSlice, dx: fromDx) = _lineStart(
        start,
        startChord,
        times,
      );
      final untilSlice = segment.endsHere
          ? endChord?.slice ?? times.indexOf(end.at)
          : times.length - 1;
      final untilDx = endChord != null
          ? _centre(endChord.plan)
          : segment.endsHere
          ? -_endPad
          : 0.0;
      final x0 = xs[fromSlice] + fromDx;
      final x1 = xs[untilSlice] + untilDx;
      final clear = free(x0, x1);
      final limit = clear + s * (_lineGap + room.bottom - room.top);
      reserve(x0, x1, clear, limit);
      return piece(
        from: (slice: fromSlice, dx: fromDx, staff: staff, dy: clear),
        until: (slice: untilSlice, dx: untilDx, staff: staff, dy: clear),
        clear: clear,
        limit: limit,
        textExtent: extent,
      );
  }
}

/// Where a piece starts in its bar, as its slice and the offset from that
/// slice's line, from where [pieceStart] put it and the [chord] it anchors
/// on. A piece anchored on a chord starts at the chord's centre. The others
/// start on the line.
({int slice, double dx}) _lineStart(
  ({Moment at, EventId? event}) start,
  PlacedChord? chord,
  List<Moment> times,
) => (
  slice: chord?.slice ?? times.indexOf(start.at),
  dx: chord == null ? 0.0 : _centre(chord.plan),
);

/// The side every piece of [spanner] reserves on and is drawn on.
Side _sideOf(Spanner spanner) => switch (spanner.kind) {
  Slur() || TrillLine() => curveSide(spanner),
  OctaveLine(:final shift) => shift.octaves > 0 ? Side.above : Side.below,
  Hairpin() || PedalLine() => Side.below,
  TempoLine() || Glissando() => Side.above,
};

/// The x of the middle of a chord's heads against its slice line.
double _centre(ChordPlan plan) =>
    (plan.headsBox.left + plan.headsBox.right) / 2;

/// The vertical extent of everything a line of [kind] can draw, from its
/// baseline. Every piece of the kind reserves it, so a continuation's
/// restated glyph has room too.
({double top, double bottom})? _roomOf(
  SpannerKind kind,
  EngravingStyle style,
  TextExtent? extent,
) {
  final font = style.font;
  final defaults = font.defaults;
  switch (kind) {
    case Slur() || Glissando():
      return null;
    case Hairpin():
      final height = _hairpinOpening + defaults.hairpinThickness;
      return (top: -height / 2, bottom: height / 2);
    case OctaveLine(:final shift):
      return _glyphRoom(font, [
        _octaveGlyph(shift),
        Glyph.octaveParensLeft,
        Glyph.octaveParensRight,
      ], lineThickness: defaults.octaveLineThickness);
    case PedalLine():
      return _glyphRoom(font, [
        Glyph.keyboardPedalPed,
      ], lineThickness: defaults.pedalLineThickness);
    case TrillLine():
      return _glyphRoom(font, [Glyph.ornamentTrill, Glyph.wiggleTrill]);
    case TempoLine():
      return (top: -extent!.ascent, bottom: extent.descent);
  }
}

/// The vertical union of [glyphs] on one baseline, and of a line
/// [lineThickness] thick on it.
({double top, double bottom}) _glyphRoom(
  SmuflFont font,
  List<Glyph> glyphs, {
  double lineThickness = 0,
}) {
  var top = -lineThickness / 2;
  var bottom = lineThickness / 2;
  for (final glyph in glyphs) {
    top = math.min(top, font[glyph].box.top);
    bottom = math.max(bottom, font[glyph].box.bottom);
  }
  return (top: top, bottom: bottom);
}

Glyph _octaveGlyph(OctaveShift shift) => switch (shift) {
  OctaveShift.up8 => Glyph.ottavaAlta,
  OctaveShift.down8 => Glyph.ottavaBassaVb,
  OctaveShift.up15 => Glyph.quindicesimaAlta,
  OctaveShift.down15 => Glyph.quindicesimaBassaMb,
  OctaveShift.up22 => Glyph.ventiduesimaAlta,
  OctaveShift.down22 => Glyph.ventiduesimaBassaMb,
};

/// The glyphs a line of [kind] starts with at its own start. A tempo line
/// starts with text instead.
List<Glyph> _startGlyphs(SpannerKind kind) => switch (kind) {
  OctaveLine(:final shift) => [_octaveGlyph(shift)],
  PedalLine() => const [Glyph.keyboardPedalPed],
  TrillLine() => const [Glyph.ornamentTrill],
  _ => const [],
};

/// The glyphs a line of [kind] restates when it continues onto a new system.
List<Glyph> _restatedGlyphs(SpannerKind kind) => switch (kind) {
  OctaveLine(:final shift) => [
    Glyph.octaveParensLeft,
    _octaveGlyph(shift),
    Glyph.octaveParensRight,
  ],
  _ => const [],
};

/// The event sounding at [at] in voice [slot] of [staff], as
/// `Score.eventAt` finds it.
TimedEvent? _sounding(StaffView staff, VoiceSlot slot, Moment at) => staff
    .voices
    .where((voice) => voice.slot == slot)
    .expand((voice) => voice.events)
    .where((e) => e.onset <= at && at < e.onset + e.duration)
    .firstOrNull;

/// The event a slur, glissando or trill line attaches to at [at], which is
/// the one sounding there in the spanner's voice, or in voice one when that
/// voice has none there (`Score.anchorAt`).
TimedEvent? _anchor(StaffView staff, Spanner spanner, Moment at) =>
    _sounding(staff, spanner.voice ?? VoiceSlot.one, at) ??
    _sounding(staff, VoiceSlot.one, at);

/// Where the piece of [segment] starts in its bar, and on which event.
///
/// This and [pieceEnd] apply `Score.anchorAt` and `Score.lineEnd` to the
/// bar's view, so the bar needs no `Score`.
({Moment at, EventId? event}) pieceStart(
  SpannerSegment segment,
  StaffView staff,
) {
  if (!segment.startsHere) {
    return (at: Moment.zero, event: null);
  }
  switch (segment.spanner.kind) {
    case Slur() || Glissando() || TrillLine():
      final anchor = _anchor(staff, segment.spanner, segment.from);
      return (at: anchor?.onset ?? segment.from, event: anchor?.event.id);
    case Hairpin() || OctaveLine() || PedalLine() || TempoLine():
      return (at: segment.from, event: null);
  }
}

/// Where the piece of [segment] ends in its bar, and on which event.
({Moment at, EventId? event}) pieceEnd(
  SpannerSegment segment,
  StaffView staff,
  Length barLength,
) {
  if (!segment.endsHere) {
    return (at: Moment.zero + barLength, event: null);
  }
  switch (segment.spanner.kind) {
    case Slur() || Glissando() || TrillLine():
      final anchor = _anchor(staff, segment.spanner, segment.to);
      return (at: anchor?.onset ?? segment.to, event: anchor?.event.id);
    case Hairpin() || OctaveLine() || PedalLine() || TempoLine():
      final last = _sounding(staff, VoiceSlot.one, segment.to);
      return (
        at: last == null ? segment.to : last.onset + last.duration,
        event: null,
      );
  }
}

/// The spanners of one system.
///
/// Pieces of one spanner in consecutive bars form one run. A run starts at
/// its first piece's `from` when that piece `startsHere`, else at [left],
/// and ends at its last piece's `until` when that piece `endsHere`, else
/// at [right].
///
/// A line is straight across its run, at the outermost baseline its pieces
/// ask for, which is inside the room every one of them reserved or further
/// out and never past the system's band. Every x stays inside [left] to
/// [right], and a cut end stops inside them by its ink's half thickness.
List<Drawable> placeSpanners(
  List<Framed<List<SpannerPiece>>> bars, {
  required double left,
  required double right,
  required EngravingStyle style,
}) => [
  for (final run in _runs(bars))
    ..._placeRun(run, left: left, right: right, style: style),
];

typedef _Placed = ({SpannerPiece piece, BarFrame frame});

/// The pieces of [bars] grouped by spanner. A piece continues the run of
/// the same spanner in the bar before, and starts one otherwise.
List<List<_Placed>> _runs(List<Framed<List<SpannerPiece>>> bars) {
  final runs = <List<_Placed>>[];
  var open = <SpannerOwner, List<_Placed>>{};
  for (final (:of, :frame) in bars) {
    final next = <SpannerOwner, List<_Placed>>{};
    for (final piece in of) {
      final run = open[piece.owner] ?? <_Placed>[];
      if (run.isEmpty) {
        runs.add(run);
      }
      run.add((piece: piece, frame: frame));
      next[piece.owner] = run;
    }
    open = next;
  }
  return runs;
}

List<Drawable> _placeRun(
  List<_Placed> run, {
  required double left,
  required double right,
  required EngravingStyle style,
}) {
  final first = run.first;
  final last = run.last;
  final piece = first.piece;
  final kind = piece.kind;
  final owner = piece.owner;
  final side = piece.side;
  final font = style.font;
  final defaults = font.defaults;
  final top = first.frame.tops[piece.from.staff];

  final inset = _inset(kind, defaults);
  final lo = left + inset;
  final hi = math.max(lo, right - inset);
  double within(double x) => math.max(lo, math.min(hi, x));
  final startX = within(
    piece.startsHere ? first.frame.at(piece.from).x : lo,
  );
  final endX = math.max(
    startX,
    within(last.piece.endsHere ? last.frame.at(last.piece.until).x : hi),
  );

  var clear = piece.clear;
  var limit = piece.limit;
  for (final (:piece, frame: _) in run) {
    clear = side == Side.above
        ? math.min(clear, piece.clear)
        : math.max(clear, piece.clear);
    limit = side == Side.above
        ? math.min(limit, piece.limit)
        : math.max(limit, piece.limit);
  }
  clear += top;
  limit += top;

  switch (kind) {
    case Slur(:final dashed):
      return [
        curveBetween(
          SpPoint(startX, first.frame.at(piece.from).y),
          SpPoint(endX, last.frame.at(last.piece.until).y),
          side: side,
          rise: slurRise,
          clear: clear,
          limit: limit,
          endThickness: defaults.slurEndpointThickness,
          midThickness: defaults.slurMidpointThickness,
          owner: owner,
          dashed: dashed,
        ),
      ];
    case Glissando():
      return [
        LineDraw(
          SpPoint(startX, first.frame.at(piece.from).y),
          SpPoint(endX, last.frame.at(last.piece.until).y),
          thickness: defaults.stemThickness,
          owner: owner,
        ),
      ];
    case Hairpin(:final crescendo):
      final room = _roomOf(kind, style, null)!;
      final centre = limit - room.bottom;
      double half({required bool point, required bool cut}) => cut
          ? _hairpinOpening / 4
          : point
          ? 0.0
          : _hairpinOpening / 2;
      final startHalf = half(point: crescendo, cut: !piece.startsHere);
      final endHalf = half(point: !crescendo, cut: !last.piece.endsHere);
      return [
        for (final sign in const [-1, 1])
          LineDraw(
            SpPoint(startX, centre + sign * startHalf),
            SpPoint(endX, centre + sign * endHalf),
            thickness: defaults.hairpinThickness,
            owner: owner,
          ),
      ];
    case OctaveLine():
      final room = _roomOf(kind, style, null)!;
      final baseline = _baselineOf(room, side, limit);
      final (glyphs, edge) = _glyphRow(
        piece.startsHere ? _startGlyphs(kind) : _restatedGlyphs(kind),
        x: startX,
        baseline: baseline,
        font: font,
        owner: owner,
      );
      final lineY = baseline + (room.top + room.bottom) / 2;
      final lineStart = edge + _startGap;
      return [
        ...glyphs,
        if (lineStart < endX)
          LineDraw(
            SpPoint(lineStart, lineY),
            SpPoint(endX, lineY),
            thickness: defaults.octaveLineThickness,
            dash: LineDash.dashed,
            owner: owner,
          ),
        if (last.piece.endsHere)
          LineDraw(
            SpPoint(endX, lineY),
            SpPoint(
              endX,
              baseline + (side == Side.above ? room.bottom : room.top),
            ),
            thickness: defaults.octaveLineThickness,
            owner: owner,
          ),
      ];
    case PedalLine():
      final room = _roomOf(kind, style, null)!;
      final baseline = _baselineOf(room, side, limit);
      var lineStart = startX;
      final glyphs = <GlyphDraw>[];
      if (piece.startsHere) {
        final (row, edge) = _glyphRow(
          _startGlyphs(kind),
          x: startX,
          baseline: baseline,
          font: font,
          owner: owner,
        );
        glyphs.addAll(row);
        lineStart = edge + _startGap;
      }
      return [
        ...glyphs,
        if (lineStart < endX)
          LineDraw(
            SpPoint(lineStart, baseline),
            SpPoint(endX, baseline),
            thickness: defaults.pedalLineThickness,
            owner: owner,
          ),
        if (last.piece.endsHere)
          LineDraw(
            SpPoint(endX, baseline),
            SpPoint(endX, baseline + room.top),
            thickness: defaults.pedalLineThickness,
            owner: owner,
          ),
      ];
    case TrillLine():
      final room = _roomOf(kind, style, null)!;
      final baseline = _baselineOf(room, side, limit);
      var runStart = startX;
      final glyphs = <GlyphDraw>[];
      if (piece.startsHere) {
        final (row, edge) = _glyphRow(
          _startGlyphs(kind),
          x: startX,
          baseline: baseline,
          font: font,
          owner: owner,
        );
        glyphs.addAll(row);
        runStart = edge + _startGap;
      }
      final wiggle = font[Glyph.wiggleTrill];
      runStart = math.max(runStart, left - wiggle.box.left);
      final count =
          ((endX - runStart - wiggle.box.right) / wiggle.advance).floor() + 1;
      return [
        ...glyphs,
        if (count >= 1)
          GlyphRunDraw(
            Glyph.wiggleTrill,
            from: SpPoint(runStart, baseline),
            to: SpPoint(runStart + count * wiggle.advance, baseline),
            count: count,
            bounds: Box(
              runStart + wiggle.box.left,
              baseline + wiggle.box.top,
              runStart + (count - 1) * wiggle.advance + wiggle.box.right,
              baseline + wiggle.box.bottom,
            ),
            owner: owner,
          ),
      ];
    case TempoLine(:final text):
      final extent = piece.textExtent!;
      final baseline = limit + extent.ascent;
      var lineStart = startX;
      TextDraw? label;
      if (piece.startsHere && text.isNotEmpty) {
        label = TextDraw(
          text,
          SpPoint(startX, baseline),
          spec: style.specOf(TextRole.expression),
          bounds: Box(
            startX,
            baseline - extent.ascent,
            startX + extent.width,
            baseline + extent.descent,
          ),
          owner: owner,
        );
        lineStart = startX + extent.width + _startGap;
      }
      final lineY = baseline - extent.ascent / 2;
      return [
        ?label,
        if (lineStart < endX)
          LineDraw(
            SpPoint(lineStart, lineY),
            SpPoint(endX, lineY),
            thickness: defaults.octaveLineThickness,
            dash: LineDash.dashed,
            owner: owner,
          ),
      ];
  }
}

/// Half the thickness of a run's ink, which a cut end stays inside the
/// band by.
double _inset(SpannerKind kind, EngravingDefaults defaults) => switch (kind) {
  Slur() =>
    (defaults.slurMidpointThickness + defaults.slurEndpointThickness) / 2,
  Glissando() => defaults.stemThickness / 2,
  Hairpin() => defaults.hairpinThickness / 2,
  OctaveLine() || TempoLine() => defaults.octaveLineThickness / 2,
  PedalLine() => defaults.pedalLineThickness / 2,
  TrillLine() => 0,
};

/// The baseline that puts [room]'s outer edge at [limit].
double _baselineOf(
  ({double top, double bottom}) room,
  Side side,
  double limit,
) => side == Side.above ? limit - room.top : limit - room.bottom;

/// The width of [glyphs] laid out by their advances, to the right edge of
/// the last one's ink.
double _rowWidth(List<Glyph> glyphs, SmuflFont font) {
  var width = 0.0;
  for (final (index, glyph) in glyphs.indexed) {
    final metrics = font[glyph];
    width += index == glyphs.length - 1 ? metrics.box.right : metrics.advance;
  }
  return width;
}

/// [glyphs] laid out by their advances from [x] on [baseline], and the
/// right edge of their ink. The bar made room for the row where it starts,
/// through [lineStartReach] or [arrivingRoom], so nothing moves it.
(List<GlyphDraw>, double) _glyphRow(
  List<Glyph> glyphs, {
  required double x,
  required double baseline,
  required SmuflFont font,
  required Owner owner,
}) {
  var at = x;
  final row = <GlyphDraw>[];
  for (final glyph in glyphs) {
    final metrics = font[glyph];
    final origin = SpPoint(at, baseline);
    row.add(
      GlyphDraw(
        glyph,
        origin,
        bounds: metrics.box.shift(origin.x, origin.y),
        owner: owner,
      ),
    );
    at += metrics.advance;
  }
  return (row, row.last.bounds.right);
}

/// A bar under a volta bracket.
typedef VoltaStub = ({
  /// "1.", "1, 2." and so on, from `Volta.endings`.
  String label,

  /// The label as the bar measured it.
  TextExtent extent,

  /// From `MeasureView.voltaStarts`. The bracket's left hook and label go
  /// here.
  bool starts,

  bool ends,

  /// From `Volta.open`. No right hook where the bracket ends.
  bool open,

  /// The y of the bracket's line from the top staff's top line, clear of
  /// everything else the bar has above that staff.
  double dy,

  /// How far the hooks reach down from the line. Enough for the label.
  double hook,
});

/// The label of a volta, "1.", "1, 2." and so on, as the bar measured it.
typedef VoltaLabel = ({String text, TextExtent extent});

/// The label of the volta [view] is under, or null when it is under none.
VoltaLabel? voltaLabel(
  MeasureView view,
  EngravingStyle style,
  TextMeasurer text,
) {
  final volta = view.column.volta;
  if (volta == null) {
    return null;
  }
  final label = '${volta.endings.join(', ')}.';
  return (
    text: label,
    extent: text.measure(label, style.specOf(TextRole.volta)),
  );
}

/// The least width of the bar a volta starts in that holds [label] between
/// the bracket's hooks, or 0 when no volta starts in [view]. The bracket of
/// a volta one bar long ends with the bar, so the label has no other room.
double voltaLabelRoom(MeasureView view, VoltaLabel? label) =>
    label == null || !view.voltaStarts ? 0 : label.extent.width + 2 * _voltaPad;

/// The bar's volta stub, or null when [label] is null, which is when the
/// bar is under no volta. Reserves the bracket and its label above [top],
/// outside everything placed before and outside the bar's heads, which
/// reach [headAbove] above the staff and are not in the skyline. [left] is
/// the bar's content start in bar space.
VoltaStub? voltaStub(
  MeasureView view,
  Skyline top, {
  required List<double> xs,
  required double left,
  required double headAbove,
  required VoltaLabel? label,
  required EngravingStyle style,
}) {
  if (label == null) {
    return null;
  }
  final extent = label.extent;
  final hook = math.max(
    _voltaHook,
    extent.ascent + extent.descent + 2 * _voltaPad,
  );
  final free = math.min(top.freeAbove(left, xs.last), -headAbove);
  final dy = free - _lineGap - hook;
  top.add(
    Box(
      left,
      dy - style.font.defaults.repeatEndingLineThickness / 2,
      xs.last,
      free,
    ),
  );
  return (
    label: label.text,
    extent: extent,
    starts: view.voltaStarts,
    ends: view.voltaEnds,
    open: view.column.volta!.open,
    dy: dy,
    hook: hook,
  );
}

/// The volta brackets of one system, above its top staff.
List<Drawable> placeVoltas(
  List<Framed<VoltaStub?>> bars, {
  required EngravingStyle style,
}) {
  final thickness = style.font.defaults.repeatEndingLineThickness;
  final drawables = <Drawable>[];
  var bracket = <Framed<VoltaStub>>[];

  void close() {
    if (bracket.isEmpty) {
      return;
    }
    final first = bracket.first;
    final last = bracket.last;
    final x0 = first.frame.left;
    final x1 = last.frame.right;
    final dy =
        first.frame.tops.first +
        bracket.map((bar) => bar.of.dy).reduce(math.min);
    drawables.add(
      LineDraw(SpPoint(x0, dy), SpPoint(x1, dy), thickness: thickness),
    );
    if (first.of.starts) {
      final hookX = x0 + thickness / 2;
      drawables.add(
        LineDraw(
          SpPoint(hookX, dy),
          SpPoint(hookX, dy + first.of.hook),
          thickness: thickness,
        ),
      );
      final extent = first.of.extent;
      final x = x0 + _voltaPad;
      final baseline = dy + _voltaPad + extent.ascent;
      drawables.add(
        TextDraw(
          first.of.label,
          SpPoint(x, baseline),
          spec: style.specOf(TextRole.volta),
          bounds: Box(
            x,
            baseline - extent.ascent,
            x + extent.width,
            baseline + extent.descent,
          ),
        ),
      );
    }
    if (last.of.ends && !last.of.open) {
      final hookX = x1 - thickness / 2;
      drawables.add(
        LineDraw(
          SpPoint(hookX, dy),
          SpPoint(hookX, dy + last.of.hook),
          thickness: thickness,
        ),
      );
    }
    bracket = [];
  }

  for (final (:of, :frame) in bars) {
    if (of == null) {
      close();
      continue;
    }
    if (of.starts) {
      close();
    }
    bracket.add((of: of, frame: frame));
  }
  close();
  return drawables;
}

/// The crescent from [from] to [to], bulging to [side].
///
/// The arc's rise grows with its length up to [rise]. It is then raised
/// until the middle half of the curve lies outside [clear], and clamped so
/// its outer edge never passes [limit]. Both are a y in the points' space.
/// [clear] is the inner edge of the room the bars under the curve reserved,
/// and [limit] its outer edge.
CurveDraw curveBetween(
  SpPoint from,
  SpPoint to, {
  required Side side,
  required double rise,
  required double clear,
  required double limit,
  required double endThickness,
  required double midThickness,
  required Owner owner,
  bool dashed = false,
}) {
  final s = side == Side.above ? -1.0 : 1.0;
  double o(double y) => s * y;
  final allowance = (midThickness + endThickness) / 2;
  final span = (to.x - from.x).abs();
  double base(double t) {
    final u = 1 - t;
    return (u * u * u + 3 * u * u * t) * from.y +
        (3 * u * t * t + t * t * t) * to.y;
  }

  final d0 = math.min(rise, span / 4) / _pull(0.5);
  final dClear = math.max(
    0,
    (o(clear) + allowance - math.min(o(base(0.25)), o(base(0.75)))) /
        _pull(0.25),
  );
  final dMax = math.max(
    0,
    (o(limit) - allowance - math.max(o(from.y), o(to.y))) / _pull(0.5),
  );
  final d = math.min(math.max(d0, dClear), dMax);
  return CurveDraw(
    start: from,
    control1: SpPoint(from.x + (to.x - from.x) / 4, from.y + s * d),
    control2: SpPoint(from.x + 3 * (to.x - from.x) / 4, to.y + s * d),
    end: to,
    endThickness: endThickness,
    midThickness: midThickness,
    dashed: dashed,
    owner: owner,
  );
}

/// How far the curve at [t] moves when both control points move one unit,
/// `3t(1 - t)`. It peaks at the middle and is least over the middle half at
/// its ends.
double _pull(double t) => 3 * t * (1 - t);
