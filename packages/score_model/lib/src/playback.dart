/// Playback compilation (access pattern 6).
///
/// The score is compiled bar by bar. A bar's notes are compiled once into a
/// fragment in whole-note time and cached on the column object itself, so a
/// one-note edit recompiles one fragment. The part that runs on every
/// compile unrolls the repeats into a play order, folds tempo and each
/// part's dynamics over the bars, and places each played bar's fragment in
/// seconds, merging tie chains across the bars as they are played.
/// Dynamics are folded on every compile because a hairpin is stored beside
/// the columns it spans, not in them.
library;

import 'dart:math';

import 'events.dart';
import 'measure.dart';
import 'pitch.dart';
import 'refs.dart';
import 'score.dart';
import 'seq.dart';
import 'time.dart';
import 'views.dart';
import 'voice_walk.dart';

/// Long-lived. Keep one per composer screen so its fragment cache survives
/// across edits.
final class PlaybackCompiler {
  PlaybackCompiler();

  /// Fragments keyed by column identity. A column that an edit did not touch
  /// is the same object in the new score, so its fragment is reused. Entries
  /// die with their columns.
  final Expando<_Fragment> _fragments = Expando('playback fragments');

  PlaybackScript compile(
    Score score, [
    PlaybackOptions options = const PlaybackOptions(),
  ]) {
    final measures = score.measures;
    final entries = <Tempo>[];
    final starts = <Length>[];
    var tempo = Tempo.unmarked;
    var elapsed = Length.zero;
    for (final column in measures) {
      entries.add(tempo);
      starts.add(elapsed);
      tempo = column.tempos.lastOrNull?.tempo ?? tempo;
      elapsed += column.length;
    }
    final channels = <ChannelSetup>[];
    final sounds = <StaffId, _Sound>{};
    var melodic = 0;
    for (final Part(:id, :instrument, :staves) in score.parts) {
      final channel = instrument.isPercussion
          ? 9
          : _melodicChannels[melodic++ % _melodicChannels.length];
      if (!options.muted.contains(id)) {
        channels.add(
          ChannelSetup(
            channel: channel,
            part: id,
            program: instrument.program,
            bank: instrument.bank,
          ),
        );
        final loudness = _Loudness(score, staves, starts);
        for (final staff in staves) {
          sounds[staff.id] = (
            channel: channel,
            instrument: instrument,
            loudness: loudness,
          );
        }
      }
    }
    final trills = <StaffId, List<(Moment, Moment)>>{};
    for (final Spanner(:kind, :staff, :first, :last) in score.spanners) {
      if (kind is TrillLine) {
        (trills[staff] ??= []).add((
          _place(score, starts, first.measure, first.offset),
          _place(score, starts, last.measure, last.offset),
        ));
      }
    }
    final windows = options.from == null && options.to == null
        ? [
            for (final (:index, :pass) in _playOrder(measures))
              (
                index: index,
                pass: pass,
                from: Moment.zero,
                to: Moment.zero + measures[index].length,
              ),
          ]
        : _range(score, options.from, options.to);
    final timeline = <_Bar>[];
    final sounding = <_Sounding>[];
    final ties = <(StaffId, VoiceSlot, Pitch), (_Sounding, int, Moment)>{};
    var seconds = 0.0;
    for (final (k, (:index, :pass, :from, :to)) in windows.indexed) {
      final column = measures[index];
      final fragment = _fragments[column] ??= _compileBar(column);
      final clock = _Clock(entries[index], column.tempos, fragment.holds);
      final start = seconds;
      seconds += clock.at(to) - clock.at(from);
      final bar = _Bar(
        PlayedBar(
          measure: column.id,
          pass: pass,
          start: start,
          end: seconds,
        ),
        from: from,
        to: to,
        clock: clock,
        heard: [
          for (final chord in fragment.chords)
            if (sounds.containsKey(chord.timed.ref.staff) &&
                from <= chord.timed.onset &&
                chord.timed.onset < to)
              chord,
        ],
      );
      timeline.add(bar);
      for (final chord in bar.heard) {
        final TimedEvent(:onset, :voice, ref: EventRef(:staff)) = chord.timed;
        final (:channel, :instrument, :loudness) = sounds[staff]!;
        final position = onset + starts[index];
        final level = loudness.at(position);
        final trilled =
            trills[staff]?.any((t) => t.$1 <= position && position <= t.$2) ??
            false;
        for (final attack
            in trilled
                ? _attacks(chord.timed, chord.event, column.key, trill: true)
                : chord.attacks) {
          final key = _key(attack.note, instrument);
          if (key == null) {
            continue;
          }
          final start = bar.secondsAt(attack.onset);
          final end = bar.secondsAt(attack.onset + attack.length);
          final release = (end - start) * (1 - attack.gate);
          final lane = (staff, voice, attack.note.pitch);
          final _Sounding note;
          if (ties.remove(lane) case (final held, final window, final expected)
              when window == k && expected == attack.onset) {
            note = held
              ..end = end
              ..release = release;
          } else {
            note = _Sounding(
              start: start,
              end: end,
              release: release,
              key: key,
              cents: attack.note.pitch.cents,
              velocity: min((level * attack.stress).round(), 127),
              channel: channel,
              source: attack.source,
            );
            sounding.add(note);
          }
          if (attack.note.tie) {
            final after = attack.onset + attack.length;
            ties[lane] = after == Moment.zero + column.length
                ? (note, k + 1, Moment.zero)
                : (note, k, after);
          }
        }
      }
    }
    return PlaybackScript._(
      timeline,
      _stableSorted(
        [for (final note in sounding) note.played],
        (a, b) => a.start.compareTo(b.start),
      ),
      totalSeconds: seconds,
      channels: channels,
      bars: [for (final bar in timeline) bar.played],
    );
  }
}

/// Where a staff's notes go and how loud its part plays.
typedef _Sound = ({int channel, Instrument instrument, _Loudness loudness});

/// Channels for pitched parts, in order. Channel 9 is General MIDI's
/// percussion channel.
const _melodicChannels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15];

_Fragment _compileBar(MeasureColumn column) {
  final chords = <_Chord>[];
  final holds = <(Moment, Moment)>[];
  for (final measure in column.staves) {
    for (final voice in measure.voices) {
      for (final timed in timedEvents(
        voice,
        measure: column.id,
        staff: measure.staff,
      )) {
        final TimedEvent(:event, :onset, :duration) = timed;
        if (event.articulations.contains(Articulation.fermata)) {
          holds.add((onset, onset + duration));
        }
        if (event is ChordEvent) {
          chords.add(_Chord(timed, event, _attacks(timed, event, column.key)));
        }
      }
    }
  }
  return _Fragment(chords, holds);
}

/// What [chord] plays, in whole-note time from the bar's downbeat. Its
/// graces play first, on the beat. Acciaccaturas take a 32nd each and any
/// appoggiatura takes half the chord, and together they take at most half.
/// Its notes then play the figure of its ornament, or of a trill when
/// [trill] and it has none, or of its tremolo.
List<_Attack> _attacks(
  TimedEvent timed,
  ChordEvent chord,
  KeySignature key, {
  bool trill = false,
}) {
  final TimedEvent(:onset, :duration, :ref) = timed;
  final graces = chord.graces;
  final half = duration * Fraction(1, 2);
  final steal = graces.isEmpty
      ? Length.zero
      : graces.any((g) => g.kind == GraceKind.appoggiatura)
      ? half
      : _shorter(_thirtySecond * Fraction(graces.length), half);
  final attacks = [
    for (final (i, grace) in graces.indexed)
      for (final note in grace.notes)
        _Attack(
          onset: onset + steal * Fraction(i, graces.length),
          length: steal * Fraction(1, graces.length),
          note: note,
          stress: 1,
          gate: _gate(const {}),
          source: EventRef(
            measure: ref.measure,
            staff: ref.staff,
            id: grace.id,
          ),
        ),
  ];
  final figure = _figure(
    chord.ornament ?? (trill ? Ornament.trill : null),
    chord,
    duration - steal,
  );
  for (final note in chord.notes) {
    var at = onset + steal;
    for (final (i, (steps, length)) in figure.indexed) {
      final last = i == figure.length - 1;
      attacks.add(
        _Attack(
          onset: at,
          length: length,
          note: steps == 0
              ? note.copyWith(tie: last && note.tie)
              : note.copyWith(
                  pitch: _neighbour(note.pitch, steps, key),
                  tie: false,
                ),
          stress: i == 0 ? _stress(chord.articulations) : 1,
          gate: _gate(last ? chord.articulations : const {}),
          source: ref,
        ),
      );
      at += length;
    }
  }
  return attacks;
}

/// How a chord plays over [length], as each piece's scale steps from the
/// written note and its length. A trill alternates with the note above in
/// 32nds. Mordents and turns play their notes in 32nds, or in equal shares
/// of a shorter chord, and hold the last. A tremolo repeats in the value
/// its strokes add to the chord's own flags.
List<(int, Length)> _figure(
  Ornament? ornament,
  ChordEvent chord,
  Length length,
) {
  List<(int, Length)> repeat(List<int> steps, Length span, Length each) {
    final ratio = span / each;
    final count = max(1, ratio.numerator ~/ ratio.denominator);
    return [
      for (var i = 0; i < count; i++)
        (steps[i % steps.length], length * Fraction(1, count)),
    ];
  }

  List<(int, Length)> quick(List<int> steps) {
    final each = _shorter(
      _thirtySecond,
      length * Fraction(1, steps.length + 1),
    );
    return [
      for (final step in steps) (step, each),
      (0, length - each * Fraction(steps.length)),
    ];
  }

  return switch (ornament) {
    Ornament.trill => repeat([0, 1], length, _thirtySecond),
    Ornament.mordent => quick([0, -1]),
    Ornament.invertedMordent => quick([0, 1]),
    Ornament.turn => quick([1, 0, -1]),
    Ornament.invertedTurn => quick([-1, 0, 1]),
    null when chord.tremolo > 0 => repeat(
      [0],
      chord.value.length,
      _shorter(chord.value.base.length, NoteValue.quarter.length) *
          Fraction(1, 1 << chord.tremolo),
    ),
    null => [(0, length)],
  };
}

final Length _thirtySecond = NoteValue.thirtySecond.length;

Length _shorter(Length a, Length b) => a < b ? a : b;

/// The note [steps] scale steps from [pitch] in [key].
Pitch _neighbour(Pitch pitch, int steps, KeySignature key) {
  final diatonic = pitch.diatonic + steps;
  final step = Step.values[diatonic % 7];
  return Pitch(step, (diatonic - step.index) ~/ 7, key.alterFor(step));
}

/// A point in notated time from the start of the score.
Moment _place(
  Score score,
  List<Length> starts,
  MeasureId measure,
  Moment offset,
) => offset + starts[score.indexOf(measure)];

/// The share of its time a note sounds, by the marks on the last note of
/// its chain. A staccato under a tenuto is a portato.
double _gate(Set<Articulation> marks) => switch ((
  marks.contains(Articulation.staccatissimo),
  marks.contains(Articulation.staccato),
  marks.contains(Articulation.tenuto),
)) {
  (true, _, _) => 0.25,
  (_, true, true) => 0.75,
  (_, true, _) => 0.5,
  (_, _, true) => 1,
  _ => 0.9,
};

/// How much harder than its dynamic a note strikes, by the marks on the
/// first note of its chain.
double _stress(Set<Articulation> marks) =>
    (marks.contains(Articulation.accent) ? 1.25 : 1) *
    (marks.contains(Articulation.marcato) ? 1.5 : 1);

/// The MIDI key [note] plays on [instrument]. A drum note plays the sound
/// at its position with its head, or else the first at its position, and
/// nothing when no sound sits there.
int? _key(Note note, Instrument instrument) {
  if (!instrument.isPercussion) {
    return note.pitch.midiKey;
  }
  final there = instrument.drums.where((d) => d.position == note.pitch);
  return (there.where((d) => d.head == note.head).firstOrNull ??
          there.firstOrNull)
      ?.midiKey;
}

/// Unrolls repeats, voltas and navigation into (bar index, pass) pairs,
/// where pass counts the times the bar has played, this one included.
///
/// An end repeat returns to the last start repeat, or to the bar after the
/// previous repeated section, or to the score start. A bar under a volta
/// plays on the passes its endings list. A section being repeated ends
/// after its end repeat, or after the last bar of the endings that hold its
/// end repeat. A [Jump] is taken once, after the repeats of its bar are
/// done. A D.S. without a [Segno] goes to the start. After the jump,
/// repeats are not taken, a bar under a volta plays only if it is under
/// the last ending of its run, and the jump's [JumpThen] says whether [Fine] stops or
/// [ToCoda] leaves for the [Coda], once. A loop guard stops at 64 × bar
/// count.
List<({int index, int pass})> _playOrder(Seq<MeasureColumn> measures) {
  final segno = measures.indexWhere(
    (c) => c.navigation.contains(const Segno()),
  );
  final coda = measures.indexWhere((c) => c.navigation.contains(const Coda()));
  final plays = List.filled(measures.length, 0);
  final order = <({int index, int pass})>[];
  var i = 0;
  var pass = 1;
  var start = 0;
  int? sectionEnd;
  Jump? jump;
  var codaTaken = false;
  while (i < measures.length && order.length < 64 * measures.length) {
    final column = measures[i];
    if ((sectionEnd != null && i > sectionEnd) ||
        (column.repeatStart && i != start)) {
      pass = 1;
      start = i;
      sectionEnd = null;
    }
    final volta = column.volta;
    if (volta != null &&
        (jump == null
            ? !volta.endings.contains(pass)
            : volta != measures[_endingsEnd(measures, i)].volta)) {
      i++;
      continue;
    }
    order.add((index: i, pass: ++plays[i]));
    final marks = column.navigation;
    if (jump != null) {
      if (jump.then == JumpThen.toFine && marks.contains(const Fine())) {
        break;
      }
      if (jump.then == JumpThen.toCoda &&
          marks.contains(const ToCoda()) &&
          coda >= 0 &&
          !codaTaken) {
        codaTaken = true;
        i = coda;
        continue;
      }
    } else {
      final end = column.repeatEnd;
      if (end != null && pass < end.times) {
        pass++;
        sectionEnd = _endingsEnd(measures, i);
        i = start;
        continue;
      }
      jump = marks.whereType<Jump>().firstOrNull;
      if (jump != null) {
        i = jump.target == JumpTarget.segno && segno >= 0 ? segno : 0;
        continue;
      }
    }
    i++;
  }
  return order;
}

/// The last bar of the run of volta bars holding bar [i], or [i] when it
/// has no volta.
int _endingsEnd(Seq<MeasureColumn> measures, int i) {
  var end = i;
  while (measures[end].volta != null &&
      end + 1 < measures.length &&
      measures[end + 1].volta != null) {
    end++;
  }
  return end;
}

/// The bars of `[from, to)` in notated order, once, each with the part of
/// it that plays.
List<({int index, int pass, Moment from, Moment to})> _range(
  Score score,
  ScorePoint? from,
  ScorePoint? to,
) {
  final first = from == null ? 0 : score.indexOf(from.measure);
  final last = to == null
      ? score.measures.length - 1
      : score.indexOf(to.measure);
  return [
    for (var i = first; i <= last; i++)
      if ((
            index: i,
            pass: 1,
            from: i == first && from != null ? from.offset : Moment.zero,
            to: i == last && to != null
                ? to.offset
                : Moment.zero + score.measures[i].length,
          )
          case final window when window.from < window.to)
        window,
  ];
}

/// Seconds from a bar's downbeat, at the tempo in effect there and then at
/// each of the bar's tempo marks. Time under a fermata on any staff passes
/// at half speed, so the held event lasts twice its length.
final class _Clock {
  factory _Clock(
    Tempo entry,
    Seq<TempoMark> marks,
    List<(Moment, Moment)> holds,
  ) {
    final cuts = {
      Moment.zero,
      for (final mark in marks) mark.offset,
      for (final (from, to) in holds) ...[from, to],
    }.toList()..sort((a, b) => a.compareTo(b));
    return _Clock._([
      for (final cut in cuts)
        (
          cut,
          marks.where((m) => m.offset <= cut).lastOrNull?.tempo ?? entry,
          holds.any((h) => h.$1 <= cut && cut < h.$2) ? 2 : 1,
        ),
    ]);
  }

  _Clock._(this._segments);

  /// Where each stretch of steady time starts, its tempo, and how many
  /// times slower than its tempo it passes.
  final List<(Moment, Tempo, int)> _segments;

  double at(Moment offset) {
    var seconds = 0.0;
    for (final (k, (from, tempo, stretch)) in _segments.indexed) {
      if (from >= offset) {
        break;
      }
      final next = k + 1 < _segments.length ? _segments[k + 1].$1 : offset;
      seconds +=
          tempo.secondsFor(from.until(next < offset ? next : offset)) * stretch;
    }
    return seconds;
  }
}

/// How loud one part plays through the score, read in notated order like
/// tempo: the dynamics on any of its staves, and its hairpins. Positions
/// count from the start of the score.
final class _Loudness {
  factory _Loudness(Score score, Seq<Staff> staves, List<Length> starts) {
    final ids = {for (final staff in staves) staff.id};
    Moment place(MeasureId measure, Moment offset) =>
        _place(score, starts, measure, offset);
    final strikes = <Moment, Dynamic>{};
    final marks = <(Moment, Dynamic)>[];
    for (final column in score.measures) {
      for (final measure in column.staves) {
        if (!ids.contains(measure.staff)) {
          continue;
        }
        for (final direction in measure.directions) {
          if (direction case DynamicMark(:final offset, :final level)) {
            final position = place(column.id, offset);
            switch (level) {
              case Dynamic.fp:
                strikes[position] = level;
                marks.add((position, Dynamic.p));
              case Dynamic.sf || Dynamic.sfz || Dynamic.rfz:
                strikes[position] = level;
              case Dynamic.pppp ||
                  Dynamic.ppp ||
                  Dynamic.pp ||
                  Dynamic.p ||
                  Dynamic.mp ||
                  Dynamic.mf ||
                  Dynamic.f ||
                  Dynamic.ff ||
                  Dynamic.fff ||
                  Dynamic.ffff:
                marks.add((position, level));
            }
          }
        }
      }
    }
    final written = _stableSorted(marks, (a, b) => a.$1.compareTo(b.$1));
    final levels = [...written];
    final hairpins = _stableSorted(
      [
        for (final spanner in score.spanners)
          if (spanner.kind case Hairpin(:final crescendo)
              when ids.contains(spanner.staff))
            (
              from: place(spanner.first.measure, spanner.first.offset),
              spanner: spanner,
              crescendo: crescendo,
            ),
      ],
      (a, b) => a.from.compareTo(b.from),
    );
    final ramps = <_Ramp>[];
    for (final (:from, :spanner, :crescendo) in hairpins) {
      final last = score.eventAt(
        VoicePoint(
          staff: spanner.staff,
          voice: VoiceSlot.one,
          at: spanner.last,
        ),
      )!;
      final end = place(spanner.last.measure, last.onset + last.duration);
      final start = _levelAt(levels, from);
      final arrival = written
          .where((l) => from < l.$1 && l.$1 <= end)
          .firstOrNull;
      final (to, target) = arrival ?? (end, _step(start, louder: crescendo));
      ramps.add(_Ramp(from, to, start.velocity, target.velocity));
      if (arrival == null) {
        levels.insert(
          _partition(levels.length, (i) => levels[i].$1 > end),
          (end, target),
        );
      }
    }
    return _Loudness._(strikes, levels, ramps);
  }

  _Loudness._(this._strikes, this._levels, this._ramps);

  /// sf, sfz, fp and rfz by position. Each strikes the chords there, and
  /// fp then leaves the level at p.
  final Map<Moment, Dynamic> _strikes;

  /// Level dynamics and the levels hairpins arrive at, by position.
  final List<(Moment, Dynamic)> _levels;

  /// By start.
  final List<_Ramp> _ramps;

  /// The velocity a chord starting at [position] strikes at, before its
  /// own marks. A strike there comes first, then the latest hairpin
  /// running there, then the level.
  double at(Moment position) {
    if (_strikes[position] case final strike?) {
      return strike.velocity.toDouble();
    }
    final started = _partition(_ramps.length, (i) => _ramps[i].from > position);
    for (var i = started - 1; i >= 0; i--) {
      if (position < _ramps[i].to) {
        return _ramps[i].at(position);
      }
    }
    return _levelAt(_levels, position).velocity.toDouble();
  }
}

/// The last level at or before [position], or mf before the first.
Dynamic _levelAt(List<(Moment, Dynamic)> levels, Moment position) {
  final after = _partition(levels.length, (i) => levels[i].$1 > position);
  return after == 0 ? Dynamic.mf : levels[after - 1].$2;
}

/// The level one step louder or softer, within pppp to ffff, which lead
/// the [Dynamic] values in order.
Dynamic _step(Dynamic level, {required bool louder}) =>
    Dynamic.values[(level.index + (louder ? 1 : -1)).clamp(
      Dynamic.pppp.index,
      Dynamic.ffff.index,
    )];

/// A hairpin's velocity, moving straight from [start] at [from] to
/// [target] at [to].
final class _Ramp {
  const _Ramp(this.from, this.to, this.start, this.target);

  final Moment from;
  final Moment to;
  final int start;
  final int target;

  double at(Moment position) =>
      start +
      (target - start) * (from.until(position) / from.until(to)).toDouble();
}

/// A played bar with what the script needs to place times in it.
final class _Bar {
  const _Bar(
    this.played, {
    required this.from,
    required this.to,
    required this.clock,
    required this.heard,
  });

  final PlayedBar played;

  /// The part of the bar that plays: all of it, or the ends of a range.
  final Moment from;
  final Moment to;
  final _Clock clock;

  /// The chords that start in the played part, on parts not muted.
  final List<_Chord> heard;

  double secondsAt(Moment offset) =>
      played.start + clock.at(offset) - clock.at(from);
}

final class PlaybackOptions {
  const PlaybackOptions({this.from, this.to, this.muted = const {}});

  /// Play only `[from, to)` in notated order, ignoring repeats. The player
  /// loops the returned script when the user asked for a loop.
  final ScorePoint? from;
  final ScorePoint? to;

  final Set<PartId> muted;
}

/// A compiled score. Immutable; recompile after an edit (cheap, see the
/// library doc).
final class PlaybackScript {
  const PlaybackScript._(
    this._timeline,
    this._notes, {
    required this.totalSeconds,
    required this.channels,
    required this.bars,
  });

  final double totalSeconds;

  /// Program to load on each channel before playing.
  final List<ChannelSetup> channels;

  /// The unrolled play order with timings. The UI can show "2nd time".
  final List<PlayedBar> bars;

  final List<_Bar> _timeline;

  /// Sorted by start.
  final List<PlaybackNote> _notes;

  /// Notes whose start falls in `[from, to)` seconds, sorted by start. The
  /// player pulls windows ahead of a monotonic clock.
  Iterable<PlaybackNote> notesBetween(double from, double to) => _notes
      .skip(_partition(_notes.length, (i) => _notes[i].start >= from))
      .takeWhile((note) => note.start < to);

  /// Events sounding at [seconds], one per voice, for highlighting. An
  /// event sounds for its notated length, and rests sound nothing.
  List<EventRef> sourcesAt(double seconds) {
    final at = _partition(
      _timeline.length,
      (i) => _timeline[i].played.end > seconds,
    );
    if (at == _timeline.length) {
      return const [];
    }
    final bar = _timeline[at];
    final voices = <(StaffId, VoiceSlot)>{};
    return [
      for (final _Chord(timed: TimedEvent(:onset, :duration, :voice, :ref))
          in bar.heard)
        if (bar.secondsAt(onset) <= seconds &&
            seconds < bar.secondsAt(onset + duration) &&
            voices.add((ref.staff, voice)))
          ref,
    ];
  }

  /// When [point] is first reached, for starting playback at the cursor.
  /// Null if the point is not in the played range.
  double? secondsAt(ScorePoint point) {
    for (final bar in _timeline) {
      if (bar.played.measure == point.measure &&
          bar.from <= point.offset &&
          point.offset < bar.to) {
        return bar.secondsAt(point.offset);
      }
    }
    return null;
  }
}

final class PlaybackNote {
  const PlaybackNote({
    required this.start,
    required this.duration,
    required this.key,
    required this.velocity,
    required this.channel,
    required this.source,
    this.cents = 0,
  });

  /// Seconds from the script start.
  final double start;
  final double duration;

  /// MIDI key 0–127.
  final int key;

  /// 0 or 50 (quarter tones). The player applies pitch bend.
  final int cents;

  final int velocity;
  final int channel;

  /// The event that produced this note. A tie chain reports its first
  /// event; a grace note reports the grace chord's id.
  final EventRef source;
}

final class ChannelSetup {
  const ChannelSetup({
    required this.channel,
    required this.part,
    required this.program,
    this.bank = 0,
  });

  final int channel;
  final PartId part;
  final int program;
  final int bank;
}

final class PlayedBar {
  const PlayedBar({
    required this.measure,
    required this.pass,
    required this.start,
    required this.end,
  });

  final MeasureId measure;

  /// How many times the bar has played, counting this time: 1 for the
  /// first time through.
  final int pass;
  final double start;
  final double end;
}

/// A bar compiled in whole-note time relative to the bar. Depends on the
/// column alone, so it can be cached on the column. Hidden parts are
/// compiled too, because they play.
final class _Fragment {
  const _Fragment(this.chords, this.holds);

  /// In staff, voice and time order.
  final List<_Chord> chords;

  /// The time under each fermata, on any staff.
  final List<(Moment, Moment)> holds;
}

final class _Chord {
  const _Chord(this.timed, this.event, this.attacks);

  final TimedEvent timed;
  final ChordEvent event;

  /// What it plays when no trill line covers it.
  final List<_Attack> attacks;
}

/// One note struck, in whole-note time from the bar's downbeat.
final class _Attack {
  const _Attack({
    required this.onset,
    required this.length,
    required this.note,
    required this.stress,
    required this.gate,
    required this.source,
  });

  final Moment onset;
  final Length length;

  /// As played. Inside a figure only the last note keeps its tie.
  final Note note;

  /// The factor on its dynamic's velocity.
  final double stress;

  /// The share of [length] it sounds.
  final double gate;

  /// Its chord, or its grace chord.
  final EventRef source;
}

/// A note being placed in seconds. A tie chain extends it.
final class _Sounding {
  _Sounding({
    required this.start,
    required this.end,
    required this.release,
    required this.key,
    required this.cents,
    required this.velocity,
    required this.channel,
    required this.source,
  });

  final double start;
  double end;

  /// Seconds cut from the end, set by the chain's last note.
  double release;
  final int key;
  final int cents;
  final int velocity;
  final int channel;
  final EventRef source;

  PlaybackNote get played => PlaybackNote(
    start: start,
    duration: end - start - release,
    key: key,
    cents: cents,
    velocity: velocity,
    channel: channel,
    source: source,
  );
}

/// [items] sorted by [compare], keeping their order where it finds them
/// equal.
List<T> _stableSorted<T>(List<T> items, int Function(T a, T b) compare) {
  final order = [for (var i = 0; i < items.length; i++) i]
    ..sort((a, b) {
      final by = compare(items[a], items[b]);
      return by != 0 ? by : a.compareTo(b);
    });
  return [for (final i in order) items[i]];
}

/// The first index in `[0, length)` where [reached] holds, given that it
/// holds from some index on, or [length] when it never does.
int _partition(int length, bool Function(int i) reached) {
  var low = 0;
  var high = length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (reached(mid)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}
