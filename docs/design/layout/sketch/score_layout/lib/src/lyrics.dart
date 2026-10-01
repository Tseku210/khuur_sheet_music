/// Lyrics. Syllables, hyphens and extenders, and what a lyric line carries from
/// one bar to the next. Not exported.
///
/// A syllable belongs to a bar. Its row does not, because every syllable of one
/// lane sits on one baseline across a system. So a bar measures its syllables
/// and says what each lane does at its edges, planning turns that into rows and
/// a carry-in per system, and assembly places the text.
library;

import 'dart:math' as math;

import 'package:score_model/score_model.dart';

import 'bar_space.dart';
import 'drawable.dart';
import 'spacing.dart';
import 'style.dart';
import 'text.dart';

/// One lyric line, which is a verse of a voice of a staff.
typedef LyricLane = ({StaffId staff, VoiceSlot voice, int verse});

/// What a lane does at a bar's first event. The system before reads it to
/// decide whether an open extender runs to its end.
enum LaneStart { syllable, rest, held }

/// What a lane leaves open at a bar's end.
enum LaneEnd {
  /// Nothing. The last syllable is complete and has no extender.
  closed,

  /// The last syllable starts or continues a word.
  hyphen,

  /// The last syllable has an extender and no rest follows it in the bar.
  extender,

  /// No syllable and no rest here. Whatever was open before is still open.
  asBefore,

  /// No syllable, and a rest. A rest ends an extender, and a hyphen stays
  /// open until the word's next syllable.
  hyphenAsBefore,
}

/// A lane in one bar. It holds what the lane does at the bar's edges, and the
/// room its syllables need above and below their baseline.
typedef BarLane = ({
  LaneStart start,
  LaneEnd end,

  /// Whether the lane's first syllable here is the middle or the end of a
  /// word, so a hyphen open before this bar runs up to it.
  bool joins,
  double ascent,
  double descent,
});

/// One measured syllable, placed against its slice. Its y comes from its
/// lane's row, which only the system knows.
final class Syllable {
  const Syllable({
    required this.lane,
    required this.slice,
    required this.dx,
    required this.text,
    required this.extent,
    required this.owner,
  });

  final LyricLane lane;
  final int slice;

  /// x of the text's origin from the slice line. A single syllable is
  /// centred on its head, and a syllable that starts a melisma is aligned
  /// left with it.
  final double dx;

  final String text;
  final TextExtent extent;
  final Owner owner;

  /// A syllable's width is a rod, so spacing keeps two syllables of one lane
  /// from touching.
  SliceReach get reach =>
      (left: math.max(0, -dx), right: math.max(0, dx + extent.width));
}

/// A bar's lyrics, which are its syllables and how every lane flows through it.
final class BarLyrics {
  const BarLyrics({
    required this.syllables,
    required this.lanes,
    required this.voices,
  });

  static const none = BarLyrics(syllables: [], lanes: {}, voices: {});

  final List<Syllable> syllables;

  /// Every lane with a syllable in this bar.
  final Map<LyricLane, BarLane> lanes;

  /// What a voice does to a verse that has no syllable in this bar. It starts
  /// [LaneStart.rest] or [LaneStart.held], and ends [LaneEnd.asBefore] or
  /// [LaneEnd.hyphenAsBefore]. A voice missing here counts as resting.
  final Map<(StaffId, VoiceSlot), BarLane> voices;

  BarLane laneOf(LyricLane lane) =>
      lanes[lane] ?? voices[(lane.staff, lane.voice)] ?? _resting;

  /// What is open after this bar when [before] was open at its start. The
  /// step of the fold that gives every system its carry-in.
  LyricCarry after(LyricCarry before) => LyricCarry({
    for (final lane in {...before.open.keys, ...lanes.keys})
      lane: ?switch (laneOf(lane).end) {
        LaneEnd.closed => null,
        LaneEnd.hyphen => OpenLyric.hyphen,
        LaneEnd.extender => OpenLyric.extender,
        LaneEnd.asBefore => before.open[lane],
        LaneEnd.hyphenAsBefore =>
          before.open[lane] == OpenLyric.hyphen ? OpenLyric.hyphen : null,
      },
  });
}

const BarLane _resting = (
  start: LaneStart.rest,
  end: LaneEnd.hyphenAsBefore,
  joins: false,
  ascent: 0,
  descent: 0,
);

/// Lyric hyphens and extenders open at a system's edge, per lane.
///
/// It is the fold of [BarLyrics.after] over every earlier bar, cut down by
/// [closing] to what a later bar closes. So it needs no assembled system.
/// Compared by value in the system's key.
final class LyricCarry {
  const LyricCarry(this.open);

  static const none = LyricCarry({});

  final Map<LyricLane, OpenLyric> open;

  /// This carry without the hyphens no later syllable joins. [ahead] holds
  /// the lanes whose next syllable from here on is the middle or the end of
  /// a word (`BarLane.joins`).
  ///
  /// A hyphen joins two syllables of one word. A word left unfinished,
  /// which is every state between two typed syllables, has no second one,
  /// so its hyphen is drawn once after its syllable and carried nowhere.
  /// An extender needs no syllable to end at. It runs to the next rest or
  /// the end of the score.
  LyricCarry closing(Set<LyricLane> ahead) => LyricCarry({
    for (final MapEntry(key: lane, value: kind) in open.entries)
      if (kind == OpenLyric.extender || ahead.contains(lane)) lane: kind,
  });

  @override
  bool operator ==(Object other) =>
      other is LyricCarry &&
      other.open.length == open.length &&
      open.entries.every((entry) => other.open[entry.key] == entry.value);

  @override
  int get hashCode => Object.hashAllUnordered(
    open.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

enum OpenLyric { hyphen, extender }

/// One lyric row of a staff on a system.
typedef LyricRow = ({LyricLane lane, double ascent, double descent});

/// The lyric rows under [staff] on a system of [bars], top row first. There is
/// a row for every lane a bar has a syllable in and every lane [carry] holds
/// open. A row is as tall as its tallest syllable in the system. A lane that is
/// only carried in has no syllable here, so its hyphen sets the height.
List<LyricRow> lyricRows(
  Iterable<BarLyrics> bars,
  LyricCarry carry,
  StaffId staff,
  EngravingStyle style,
  TextMeasurer text,
) {
  final hyphen = text.measure('-', style.specOf(TextRole.lyric));
  final rows = <LyricLane, LyricRow>{
    for (final lane in carry.open.keys)
      if (lane.staff == staff)
        lane: (lane: lane, ascent: hyphen.ascent, descent: hyphen.descent),
  };
  for (final bar in bars) {
    for (final MapEntry(key: lane, value: here) in bar.lanes.entries) {
      if (lane.staff != staff) {
        continue;
      }
      final row = rows[lane];
      rows[lane] = (
        lane: lane,
        ascent: math.max(row?.ascent ?? 0, here.ascent),
        descent: math.max(row?.descent ?? 0, here.descent),
      );
    }
  }
  return rows.values.toList()..sort(
    (a, b) => a.lane.voice.index != b.lane.voice.index
        ? a.lane.voice.index.compareTo(b.lane.voice.index)
        : a.lane.verse.compareTo(b.lane.verse),
  );
}

/// The room [rows] take below a staff's other content.
double lyricRoom(List<LyricRow> rows, EngravingStyle style) => rows.fold(
  0,
  (room, row) => room + style.lyricGap + row.ascent + row.descent,
);

/// The syllables of [view] and each lane's flow.
///
/// A syllable is measured here because spacing needs its width.
/// `Syllabic` gives the lane's end (`begin` and `middle` leave a hyphen),
/// and `Lyric.extend` leaves an extender unless a rest follows in the bar.
BarLyrics lyricsOf(
  MeasureView view,
  List<Moment> times,
  EngravingStyle style,
  TextMeasurer text,
) {
  // TODO, per visible staff and voice:
  // - for each ChordEvent.lyrics entry: measure text with the lyric spec,
  //   make a Syllable at the event's slice;
  // - lanes[lane] = start (syllable when the voice's first event carries
  //   this verse, else rest or held), end, joins (the lane's first
  //   syllable here is Syllabic.middle or Syllabic.end), and the largest
  //   ascent and descent of the lane's syllables;
  // - voices[(staff, voice)] = start rest or held by the first event, end
  //   hyphenAsBefore when any RestEvent or MeasureRest is in the voice,
  //   else asBefore.
  throw UnimplementedError();
}

/// The baseline y of each of [rows] when the lyric room starts at [from].
List<double> lyricBaselines(
  List<LyricRow> rows,
  double from,
  EngravingStyle style,
) {
  final baselines = <double>[];
  var y = from;
  for (final row in rows) {
    baselines.add(y + style.lyricGap + row.ascent);
    y += style.lyricGap + row.ascent + row.descent;
  }
  return baselines;
}

/// Syllables, hyphens and extenders of one staff on one system.
///
/// [baselines] holds the y of each row of [rows] in system space. [carry]
/// is what is open at the system's start and [carryOut] what is open at its
/// end. [next] is the lyrics of the first bar of the next system, or null
/// on the last system.
List<Drawable> placeLyrics(
  List<Framed<BarLyrics>> bars, {
  required List<LyricRow> rows,
  required List<double> baselines,
  required LyricCarry carry,
  required LyricCarry carryOut,
  required BarLyrics? next,
  required double right,
  required EngravingStyle style,
  required TextMeasurer text,
}) {
  // TODO, per row:
  // - each syllable as a TextDraw at frame.xs[slice] + dx on the baseline;
  // - a hyphen centred between two syllables of one word, repeated when
  //   the gap is wide. A hyphen in carry draws one before the row's first
  //   syllable. A hyphen in carryOut draws one at [right]. A syllable that
  //   leaves a hyphen open which nothing joins (the lane's next syllable
  //   on this system starts a word, or there is none and carryOut does not
  //   hold the hyphen) is an unfinished word, and draws one hyphen right
  //   after its text;
  // - an extender as a LineDraw of lyricLineThickness on the baseline,
  //   from the syllable's right edge to the last note before the lane's
  //   next syllable or rest (style.extenders). An extender in carry starts
  //   at the first slice. An extender in carryOut runs to [right] when
  //   next.laneOf(lane).start is held, else it stops at the last note of
  //   the system.
  // Every piece lies between its row's ascent and descent, which planning
  // already counted into the system's height.
  throw UnimplementedError();
}
