/// Ties, spanners and volta brackets. Everything that can cross a barline. Not
/// exported.
///
/// A cross-bar piece is drawn by the system, because only the system knows
/// where it starts and ends on the line. It is decided by the bar. Each bar
/// a piece passes through stores a stub with its resolved anchors and
/// reserves the piece's room in its own skyline, so the bar's extents, and
/// through them the system's planned height, already hold the piece. The
/// system then draws inside that room and never outside it.
///
/// The reservation order is fixed. Ties come first, then slurs, then lines in
/// kind order, then the volta. Pieces come after every mark of the bar, so a
/// line that a neighbouring bar pushes outward moves away from the notes and
/// marks, never into them.
library;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'chords.dart';
import 'drawable.dart';
import 'geometry.dart';
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

/// The side a slur or a trill line is drawn on, in every bar it crosses.
///
/// It comes from the spanner alone, never from the stems of one bar. A bar
/// sees only its own stems, so a slur over a barline between a stems-up
/// bar and a stems-down bar would be given two sides and would have room on
/// neither. A slur is above its notes, and below them in voices two and
/// four, whose stems point down when a staff has more than one voice. A
/// trill line is above.
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

  /// Away from the stem. In a chord the upper notes curve up and the lower
  /// notes down.
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

/// No head to land on, which is a let-ring tie of [letRingLength]. The model
/// gives the tie no target, or its target's chord is in this bar but has no
/// head of that note.
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
/// from its head to the bar's edge, or between its two heads. An arriving
/// end reserves on both sides, because the bar it comes from chose the side
/// from its own chord and this bar cannot see it. [left] is the bar's
/// content start in bar space, where an arriving half tie begins.
List<TieEnd> tieEnds(
  StaffView view,
  Map<EventId, PlacedChord> chords,
  Skyline skyline, {
  required int staff,
  required List<double> xs,
  required double left,
}) => throw UnimplementedError();

/// The slice and right reach of every let-ring tie of [view]. The stub is
/// content to the right of its chord, like a dot or a flag, so spacing makes
/// room for it before the next slice. A tie whose target is in the bar but
/// has no head of that note lets ring too, as [tieEnds] draws it.
List<({int slice, double right})> letRingReach(
  StaffView view,
  Map<EventId, PlacedChord> chords,
) => throw UnimplementedError();

/// The slice and right reach of what every line starting in [view] starts
/// with: a tempo line's text, a pedal line's "Ped.", an octave line's glyph
/// and a trill line's sign. It is content right of the line's start, like a
/// dot or a flag, so spacing makes room for it before the next slice, and a
/// line that starts on a system's last beat has room for its text inside
/// the system. It needs the planned chords, since a trill line starts at
/// its chord's centre, so [markReach] does not fold it in. The bar merges
/// both.
List<({int slice, double right})> lineStartReach(
  MeasureView view,
  Map<EventId, PlacedChord> chords, {
  required List<Moment> times,
  required EngravingStyle style,
  required TextMeasurer text,
}) => throw UnimplementedError();

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
}) => throw UnimplementedError();

/// The ties of one system.
///
/// [TieWithin] is one curve. [TieLeaving] joins the [TieArriving] of the
/// same note in the next bar when that bar is on this system, and
/// otherwise runs as a half tie to [right] of its staff. [TieArriving] in
/// the first bar of the system is a half tie from [left]. In any other bar
/// the bar before drew it. [TieOpen] is a curve of fixed length. Every
/// curve comes from [curveBetween] with a rise of at most [tieRise].
List<Drawable> placeTies(
  List<Framed<List<TieEnd>>> bars, {
  required double left,
  required List<double> right,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The tie of a grace note from its head [from] to the head [to] of the
/// same tone, or a let-ring tie when [to] is null. Both boxes are in one
/// space. It curves below, since grace stems are up, at the style's grace
/// scale.
CurveDraw graceTie(
  Box from,
  Box? to, {
  required Owner owner,
  required EngravingStyle style,
}) => throw UnimplementedError();

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

  /// Where the piece starts in this bar, by [pieceStart]. With [startsHere]
  /// it is the spanner's own start. That is the outline of the event
  /// sounding at `SpannerSegment.from` for a slur, its heads for a
  /// glissando or a trill line, and the x of `from` on the piece's baseline
  /// for a line. Without it, the bar's first slice.
  final BarAnchor from;

  /// Where the piece ends in this bar, by [pieceEnd]. That is the event
  /// sounding at `to` for a slur, glissando or trill line, and the end of
  /// the event `to` lands in for a hairpin, octave, pedal or tempo line.
  /// Without [endsHere], the bar's last slice.
  final BarAnchor until;

  final bool startsHere;
  final bool endsHere;

  /// By [curveSide] for a slur and a trill line, and by kind for a line.
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

  /// A tempo line's text as the bar measured it. Null for every other kind.
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
/// its staff:
/// - a slur, [slurRise] outside its notes and marks over the piece's x
///   range, on its [curveSide];
/// - a hairpin, its opening's height below the staff;
/// - an octave line, its glyph's height above (8va, 15ma, 22ma) or below;
/// - a pedal line, the `keyboardPedalPed` glyph's height below;
/// - a trill line, the trill sign and the wiggle's height above;
/// - a tempo line, its text's height above;
/// - a glissando, nothing, because it runs between two heads in the notes.
///
/// Every piece of a line kind reserves one height, computed from everything
/// the kind can draw, so a continuation has room for its restated sign.
List<SpannerPiece> spannerPieces(
  MeasureView view,
  List<Skyline> skylines,
  Map<EventId, PlacedChord> chords, {
  required List<Moment> times,
  required List<double> xs,
  required EngravingStyle style,
  required TextMeasurer text,
}) => throw UnimplementedError();

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
/// A segment that does not start here starts with the bar. One that does
/// starts by the model's own rule. A spanner's point may lie inside an
/// event, because an overwrite can lengthen the note under it. So a slur,
/// glissando or trill line starts at the onset of the event sounding at
/// `from`, and a line starts at `from` itself.
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
///
/// A segment that does not end here runs to the bar's end. One that does
/// ends by the model's own rules, read from the bar's view:
/// - a slur, glissando or trill line ends at the onset of the event
///   sounding at `to` (`Score.anchorAt`);
/// - a hairpin, octave, pedal or tempo line ends at the end of the voice-one
///   event `to` falls in (`Score.lineEnd`), so an 8va whose last point is
///   the onset of a dotted half runs over all of it.
///
/// The bar's view holds every event these rules read, so the bar needs no
/// `Score` and no field the model does not have.
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
/// at [right]. Each run draws by kind:
/// - a slur is one [curveBetween], outside the outermost `clear` of its
///   pieces and inside their outermost `limit`. Every piece has the same
///   side. A run cut by the system end stops at a point level with its
///   last note;
/// - a hairpin is two lines `hairpinThickness` thick. A cut end is half
///   open instead of a point or the full opening;
/// - an octave line is the glyph, then a dashed line with a hook at its
///   true end. A continuation restates the glyph in parentheses;
/// - a pedal line is "Ped." and a line with a hook at its true end;
/// - a trill line is the trill sign, then `wiggleTrill` repeated as a
///   `GlyphRunDraw`;
/// - a tempo line is the text, then a dashed line;
/// - a glissando is a straight line between the heads.
/// A line is straight across its run, at the outermost baseline its pieces
/// ask for, which is inside the room every one of them reserved or further
/// out and never past the system's band. Every x stays inside [left] to
/// [right] of its staff, and a cut end stops inside them by its ink's half
/// thickness.
List<Drawable> placeSpanners(
  List<Framed<List<SpannerPiece>>> bars, {
  required double left,
  required List<double> right,
  required EngravingStyle style,
}) => throw UnimplementedError();

/// A bar under a volta bracket.
typedef VoltaStub = ({
  /// "1.", "1, 2." and so on, from `Volta.endings`.
  String label,

  /// The label as the bar measured it.
  TextExtent extent,

  /// From `MeasureView.voltaStarts`. The bracket's left hook and label go
  /// here.
  bool starts,

  /// `MeasureView.voltaEnds`.
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
) => throw UnimplementedError();

/// The least width of the bar a volta starts in that holds [label] between
/// the bracket's hooks, or 0 when no volta starts in [view]. The bracket of
/// a volta one bar long ends with the bar, so the label has no other room.
/// `layoutBar` widens the bar's rods to it with `widenedTo`.
double voltaLabelRoom(MeasureView view, VoltaLabel? label) =>
    throw UnimplementedError();

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
}) => throw UnimplementedError();

/// The volta brackets of one system, above its top staff.
///
/// Consecutive bars with a stub form one bracket, and a stub that `starts`
/// begins a new one. The line is `repeatEndingLineThickness` thick, at the
/// outermost `dy` of its bars, from the first bar's left to the last bar's
/// barline (`BarFrame.barline`), over any clef that stands before that
/// barline. It has a left hook and the label where the volta starts, and a
/// right hook where it ends unless it is `open`. A bracket continued from
/// the system before has neither a left hook nor a label. A hook's outer
/// edge is flush with the bracket's end.
List<Drawable> placeVoltas(
  List<Framed<VoltaStub?>> bars, {
  required EngravingStyle style,
}) => throw UnimplementedError();

/// The crescent from [from] to [to], bulging to [side].
///
/// The arc's rise grows with its length up to [rise]. It is then raised
/// until the middle half of the curve lies outside [clear], and clamped so
/// its outer edge never passes [limit]. Both are a y in the points' space.
/// [clear] is the inner edge of the room the bars under the curve reserved,
/// and [limit] its outer edge. A tie passes its own anchors' y as [clear].
///
/// The clamp is what keeps a slur inside the band its system planned. The
/// raise is what keeps it off the notes it passes over. Only the middle
/// half is raised, since the ends must come down to their notes, so a tall
/// note beside a low end note can still touch the curve.
///
/// The control points sit a quarter and three quarters of the way along,
/// each the same distance outward from its own end, so the arc is at most
/// three quarters of that distance outside the line between the ends. The
/// raise reads the curve's inner edge at a quarter and three quarters,
/// where the control points pull least, and the clamp its outer edge
/// against the outer end.
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
}) => throw UnimplementedError();
