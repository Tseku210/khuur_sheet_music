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
import 'chords.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'spacing.dart';
import 'style.dart';
import 'text.dart';

/// A hyphen is repeated along a gap so that no two of them, or a hyphen and
/// a syllable, are further apart than this, in staff spaces.
const double _hyphenPeriod = 10;

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

/// The right edge of the last note an extender runs to, as a slice and an x
/// from it.
typedef MelismaEnd = ({int slice, double dx});

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

  /// Where an extender open at the bar's start ends here, which is the last
  /// note before the lane's first syllable or a rest. Null when the bar's
  /// first event is one of those, so the extender reaches no note here.
  MelismaEnd? heldTo,
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
    required this.joins,
    required this.leaves,
    required this.extendTo,
    required this.extendsOn,
    required this.trail,
    required this.pad,
  });

  final LyricLane lane;
  final int slice;

  /// x of the text's origin from the slice line. A syllable is centred on
  /// its head, and one whose extender reaches past that note is aligned
  /// left with it.
  final double dx;

  final String text;
  final TextExtent extent;
  final Owner owner;

  /// Whether this syllable is the middle or the end of a word, so a hyphen
  /// open before it runs up to it.
  final bool joins;

  /// What the syllable leaves after it. A hyphen for the first or a middle
  /// syllable of a word, an extender for a complete one with `Lyric.extend`,
  /// else nothing.
  final OpenLyric? leaves;

  /// The right edge of the last note after its own in this bar that the
  /// extender it leaves reaches, which is the last before the lane's next
  /// syllable or a rest. Null when it leaves no extender, or one that reaches
  /// no later note here. An extender under its own note alone is not drawn.
  final MelismaEnd? extendTo;

  /// Whether the extender reaches the bar's end, so the next bar says where
  /// it ends. When it does not, it ends at [extendTo].
  final bool extendsOn;

  /// Room kept after the text for the hyphen it leaves, so two syllables of
  /// one word never meet without one. 0 when it leaves no hyphen.
  final double trail;

  /// Clear space kept on each side of the text, so neighbouring syllables
  /// read as words apart and not as one.
  final double pad;

  /// A syllable's width is a rod, so spacing keeps two syllables of one lane
  /// from touching.
  SliceReach get reach => (
    left: math.max(0, pad - dx),
    right: math.max(0, dx + extent.width + trail + pad),
  );

  @override
  bool operator ==(Object other) =>
      other is Syllable &&
      other.lane == lane &&
      other.slice == slice &&
      other.dx == dx &&
      other.text == text &&
      other.extent == extent &&
      other.owner == owner &&
      other.joins == joins &&
      other.leaves == leaves &&
      other.extendTo == extendTo &&
      other.extendsOn == extendsOn &&
      other.trail == trail &&
      other.pad == pad;

  @override
  int get hashCode => Object.hash(
    lane,
    slice,
    dx,
    text,
    extent,
    owner,
    joins,
    leaves,
    extendTo,
    extendsOn,
    trail,
    pad,
  );
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
  /// step of the fold that gives every system its carry-in, which runs over
  /// every bar of the score at each break, so it allocates nothing for the
  /// common bar that has no lyrics and follows none.
  LyricCarry after(LyricCarry before) {
    if (before.open.isEmpty && lanes.isEmpty) {
      return before;
    }
    return LyricCarry({
      for (final lane
          in before.open.isEmpty
              ? lanes.keys
              : {...before.open.keys, ...lanes.keys})
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

  @override
  bool operator ==(Object other) =>
      other is BarLyrics &&
      other.syllables.length == syllables.length &&
      syllables.indexed.every((item) => other.syllables[item.$1] == item.$2) &&
      _sameMap(other.lanes, lanes) &&
      _sameMap(other.voices, voices);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(syllables), lanes.length, voices.length);
}

bool _sameMap<K, V>(Map<K, V> a, Map<K, V> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

const BarLane _resting = (
  start: LaneStart.rest,
  end: LaneEnd.hyphenAsBefore,
  joins: false,
  ascent: 0,
  descent: 0,
  heldTo: null,
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

  /// This carry without the hyphens no later syllable joins and the
  /// extenders [next], the first bar after the edge, does not hold. [ahead]
  /// holds the lanes whose next syllable from here on is the middle or the
  /// end of a word (`BarLane.joins`).
  ///
  /// A hyphen joins two syllables of one word. A word left unfinished,
  /// which is every state between two typed syllables, has no second one,
  /// so its hyphen is drawn once after its syllable and carried nowhere.
  /// An extender needs no syllable to end at, but it ends before a rest or
  /// a syllable, so one that reaches a bar starting with either stops at the
  /// edge and the next system has no row for it.
  LyricCarry closing(Set<LyricLane> ahead, BarLyrics next) {
    if (open.isEmpty) {
      return none;
    }
    final kept = {
      for (final MapEntry(key: lane, value: kind) in open.entries)
        if (switch (kind) {
          OpenLyric.hyphen => ahead.contains(lane),
          OpenLyric.extender => next.laneOf(lane).start == LaneStart.held,
        })
          lane: kind,
    };
    return kept.isEmpty ? none : LyricCarry(kept);
  }

  @override
  bool operator ==(Object other) =>
      identical(other, this) ||
      other is LyricCarry && _sameMap(other.open, open);

  /// Order-free, and 0 for an empty carry, which is most of them. A system's
  /// key is hashed several times an update.
  @override
  int get hashCode {
    if (open.isEmpty) {
      return 0;
    }
    var hash = 0;
    for (final MapEntry(key: lane, value: kind) in open.entries) {
      hash ^= Object.hash(lane, kind);
    }
    return hash;
  }
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
/// A syllable is measured here because spacing needs its width. `Syllabic`
/// gives what it leaves (`begin` and `middle` leave a hyphen), and
/// `Lyric.extend` an extender, which ends at the last note before the
/// lane's next syllable or a rest, or leaves the bar when neither follows.
/// A gap in a voice ends it as a rest does. [chords] places each syllable
/// against its chord's head.
BarLyrics lyricsOf(
  MeasureView view,
  List<Moment> times,
  Map<EventId, PlacedChord> chords,
  EngravingStyle style,
  TextMeasurer text,
) {
  final spec = style.specOf(TextRole.lyric);
  final hyphen = text.measure('-', spec).width;
  // A quarter of the size is about the width of a space in most text faces.
  final pad = spec.size / 4;
  final end = Moment.zero + view.column.length;
  final syllables = <Syllable>[];
  final lanes = <LyricLane, BarLane>{};
  final voices = <(StaffId, VoiceSlot), BarLane>{};
  for (final staffView in view.staves) {
    final staff = staffView.source.staff;
    for (final voice in staffView.voices) {
      final events = voice.events;
      if (events.isEmpty) {
        continue;
      }
      final sung = <LyricLane, List<Syllable>>{};
      for (final (index, timed) in events.indexed) {
        final event = timed.event;
        if (event is! ChordEvent) {
          continue;
        }
        final placed = chords[event.id]!;
        final slice = times.indexOf(timed.onset);
        for (final lyric in event.lyrics) {
          final lane = (staff: staff, voice: voice.slot, verse: lyric.verse);
          final leaves = switch (lyric.syllabic) {
            Syllabic.begin || Syllabic.middle => OpenLyric.hyphen,
            Syllabic.single ||
            Syllabic.end => lyric.extend ? OpenLyric.extender : null,
          };
          final melisma = leaves == OpenLyric.extender
              ? _run(events, index + 1, lyric.verse, chords, end)
              : null;
          final extent = text.measure(lyric.text, spec);
          final syllable = Syllable(
            lane: lane,
            slice: slice,
            dx: _dxOf(
              placed.plan,
              extent,
              melisma:
                  melisma != null &&
                  (melisma.to != null ||
                      !melisma.stops && _holds(voice.nextOpening, lyric.verse)),
            ),
            text: lyric.text,
            extent: extent,
            owner: ElementOwner(timed.ref),
            joins:
                lyric.syllabic == Syllabic.middle ||
                lyric.syllabic == Syllabic.end,
            leaves: leaves,
            extendTo: melisma?.to,
            extendsOn: melisma != null && !melisma.stops,
            trail: leaves == OpenLyric.hyphen ? hyphen : 0,
            pad: pad,
          );
          syllables.add(syllable);
          sung.putIfAbsent(lane, () => []).add(syllable);
        }
      }
      for (final MapEntry(key: lane, value: here) in sung.entries) {
        final last = here.last;
        final heldTo = _run(events, 0, lane.verse, chords, end).to;
        lanes[lane] = (
          start: heldTo != null
              ? LaneStart.held
              : events.first.onset.isZero && events.first.event is ChordEvent
              ? LaneStart.syllable
              : LaneStart.rest,
          end: switch (last.leaves) {
            OpenLyric.hyphen => LaneEnd.hyphen,
            OpenLyric.extender when last.extendsOn => LaneEnd.extender,
            _ => LaneEnd.closed,
          },
          joins: here.first.joins,
          ascent: here.map((s) => s.extent.ascent).reduce(math.max),
          descent: here.map((s) => s.extent.descent).reduce(math.max),
          heldTo: heldTo,
        );
      }
      final through = _run(events, 0, null, chords, end);
      voices[(staff, voice.slot)] = (
        start: through.to != null ? LaneStart.held : LaneStart.rest,
        end: through.stops ? LaneEnd.hyphenAsBefore : LaneEnd.asBefore,
        joins: false,
        ascent: 0,
        descent: 0,
        heldTo: through.to,
      );
    }
  }
  return BarLyrics(syllables: syllables, lanes: lanes, voices: voices);
}

/// Walks [events] from [from] to the first rest or gap, or the first chord
/// that sings [verse] when one is given. Gives the right edge of the last
/// chord before that stop, null when there is none, and whether a stop was
/// found before [end], the bar's end.
({MelismaEnd? to, bool stops}) _run(
  List<TimedEvent> events,
  int from,
  int? verse,
  Map<EventId, PlacedChord> chords,
  Moment end,
) {
  MelismaEnd? to;
  var at = from == 0
      ? Moment.zero
      : events[from - 1].onset + events[from - 1].duration;
  for (final timed in events.skip(from)) {
    if (timed.onset != at || !_holds(timed, verse)) {
      return (to: to, stops: true);
    }
    to = _endOf(chords[timed.event.id]!);
    at = timed.onset + timed.duration;
  }
  return (to: to, stops: at != end);
}

/// Whether [timed] is a chord that sings no syllable of [verse], so an
/// extender of that verse runs on under it.
bool _holds(TimedEvent? timed, int? verse) => switch (timed?.event) {
  ChordEvent(:final lyrics) => !lyrics.any((lyric) => lyric.verse == verse),
  _ => false,
};

MelismaEnd _endOf(PlacedChord placed) => (
  slice: placed.slice,
  dx: placed.plan.headsBox.right,
);

/// The text's x from the slice line. It is centred on the head at the
/// stem's foot, which is never a displaced head of a second. A syllable
/// whose extender reaches past its own note ([melisma]) is aligned left
/// with that head instead.
double _dxOf(ChordPlan plan, TextExtent extent, {required bool melisma}) {
  final head = plan.stem == StemSide.up ? plan.heads.first : plan.heads.last;
  final box = plan.headBoxes[head.id]!;
  return melisma ? box.left : (box.left + box.right - extent.width) / 2;
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
/// on the last system. [left] is where the system head ends and [right]
/// where a courtesy signature starts.
///
/// A hyphen is centred between the two syllables of its word, and repeated
/// when the gap is wide. At a system's edge, [left] or [right] stands in
/// for the syllable on the other side, so a word split by the break has a
/// hyphen on each side. A syllable that leaves a hyphen nothing joins is an
/// unfinished word, and gets one hyphen right after its text.
///
/// An extender runs on the baseline from its syllable's right edge to the
/// last note before the lane's next syllable or a rest. One that reaches
/// the system's end runs to [right] when the next system's first bar holds
/// the note, else it stops at the last note of the system. One carried in
/// starts at the first slice. None is drawn that would end where it starts.
///
/// [bars] holds every unit of the system. A rest run stands in with its
/// first bar, whose rest stops an extender.
List<Drawable> placeLyrics(
  List<Framed<BarLyrics>> bars, {
  required List<LyricRow> rows,
  required List<double> baselines,
  required LyricCarry carry,
  required LyricCarry carryOut,
  required BarLyrics? next,
  required double left,
  required double right,
  required EngravingStyle style,
  required TextMeasurer text,
}) {
  final spec = style.specOf(TextRole.lyric);
  final hyphen = text.measure('-', spec);
  final thickness = style.font.defaults.lyricLineThickness;
  final drawables = <Drawable>[];

  TextDraw hyphenAt(double x, double y) => TextDraw(
    '-',
    SpPoint(x, y),
    spec: spec,
    bounds: Box(x, y - hyphen.ascent, x + hyphen.width, y + hyphen.descent),
  );
  List<TextDraw> hyphensBetween(double from, double to, double y) {
    final gap = to - from;
    final count = math.max(1, (gap / _hyphenPeriod).ceil());
    return [
      for (var i = 0; i < count; i++)
        hyphenAt(
          math.max(
            from,
            math.min(
              from + gap * (i + 0.5) / count - hyphen.width / 2,
              to - hyphen.width,
            ),
          ),
          y,
        ),
    ];
  }

  void extender(double from, double? to, double y, Owner? owner) {
    if (to != null && to > from) {
      drawables.add(
        LineDraw(
          SpPoint(from, y),
          SpPoint(to, y),
          thickness: thickness,
          owner: owner,
        ),
      );
    }
  }

  for (final (index, row) in rows.indexed) {
    final lane = row.lane;
    final y = baselines[index];
    var open = carry.open[lane] == OpenLyric.hyphen ? left : null;
    if (carry.open[lane] == OpenLyric.extender) {
      extender(
        bars.first.frame.xs.first,
        _extenderEnd(bars, 0, lane, next, right),
        y,
        null,
      );
    }
    for (final (bar, (of: lyrics, :frame)) in bars.indexed) {
      for (final syllable in lyrics.syllables) {
        if (syllable.lane != lane) {
          continue;
        }
        final x = frame.xs[syllable.slice] + syllable.dx;
        final end = x + syllable.extent.width;
        drawables.add(
          TextDraw(
            syllable.text,
            SpPoint(x, y),
            spec: spec,
            bounds: Box(
              x,
              y - syllable.extent.ascent,
              end,
              y + syllable.extent.descent,
            ),
            owner: syllable.owner,
          ),
        );
        if (open case final from?) {
          if (syllable.joins) {
            drawables.addAll(hyphensBetween(from, x, y));
          } else {
            drawables.add(hyphenAt(from, y));
          }
        }
        open = syllable.leaves == OpenLyric.hyphen ? end : null;
        if (syllable.leaves == OpenLyric.extender) {
          final here = switch (syllable.extendTo) {
            final to? => frame.xs[to.slice] + to.dx,
            null => null,
          };
          extender(
            end,
            syllable.extendsOn
                ? _extenderEnd(bars, bar + 1, lane, next, right) ?? here
                : here,
            y,
            syllable.owner,
          );
        }
      }
    }
    if (open case final from?) {
      if (carryOut.open[lane] == OpenLyric.hyphen) {
        drawables.addAll(hyphensBetween(from, right, y));
      } else {
        drawables.add(hyphenAt(from, y));
      }
    }
  }
  return drawables;
}

/// x where an extender of [lane] open at the start of bar [from] ends, or
/// null when it reaches no note. It ends in the first bar that stops it,
/// at that bar's `heldTo`. Past the system it runs to [right] when the
/// next system's first bar holds its note, else it stops at the last note
/// it reached.
double? _extenderEnd(
  List<Framed<BarLyrics>> bars,
  int from,
  LyricLane lane,
  BarLyrics? next,
  double right,
) {
  double? to;
  for (final (of: lyrics, :frame) in bars.skip(from)) {
    final here = lyrics.laneOf(lane);
    if (here.heldTo case final held?) {
      to = frame.xs[held.slice] + held.dx;
    }
    if (here.heldTo == null || here.end != LaneEnd.asBefore) {
      return to;
    }
  }
  return next?.laneOf(lane).start == LaneStart.held ? right : to;
}
