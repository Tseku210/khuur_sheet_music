/// Standard MIDI File export, from the playback script.
///
/// The file holds what `PlaybackCompiler` plays, so repeats, endings,
/// jumps, ties, slurs, dynamics, ornaments and the pedal come out as they
/// play. It is a format 1 file at 960 ticks a quarter. The first track
/// holds the tempo, the time signature and the key signature. Each part has
/// a track after it, in score order, on the channel the script gives it,
/// with its bank and program.
///
/// Ticks count notated time along the play order, so every played bar
/// starts on a barline in another program. A file states no tempo under
/// 3.58 quarters a minute, so a slower stretch takes as many more ticks as
/// its time needs, and the bars from there on start that much later. The
/// tempo is written where it
/// changes: once where it holds, and every sixteenth where a tempo line
/// moves it, at the mean tempo of that sixteenth. A note starts and ends at
/// its script times in those tempos, so it lands within a tick of when the
/// player plays it. Under a moving tempo, a note between two sixteenths can
/// sit a few ticks off its notated place.
///
/// A quarter tone is a pitch bend before the note, with the wheel's end at
/// two semitones. A track that bends sets that
/// range first. The pedal is in the notes it holds, which the script
/// already lengthens, and not a controller. Each track sets its channel's
/// expression, controller 11, at its start and wherever the script's
/// [ChannelSetup.expression] changes, so a held note of a part that swells
/// follows a hairpin.
///
/// A bank under 128 is a bank select with the bank as its most significant
/// byte, which is how a GS synthesizer and FluidSynth read a SoundFont
/// bank. A larger bank, such as the percussion bank 128 of a SoundFont, is
/// left to the channel.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../pitch.dart';
import '../playback.dart';
import '../refs.dart';
import '../score.dart';
import '../stable_sort.dart';
import '../time.dart';

/// [score] as the bytes of a Standard MIDI File of how it plays.
Uint8List scoreToMidi(Score score) {
  final script = PlaybackCompiler().compile(score);
  final conductor = _Track();
  if (score.meta.title.isNotEmpty) {
    conductor.text(0, score.meta.title);
  }
  final tempo = _TempoMap();
  var played = Fraction.zero;
  _TimeSignature? meter;
  KeySignature? key;
  for (final clock in barClocks(script)) {
    final downbeat = tempo.tickOf(_ticks(played));
    final column = score.column(clock.played.measure);
    final signature = _TimeSignature.of(column.meter, clock.length);
    if (signature != null && signature != meter) {
      meter = signature;
      conductor.meta(downbeat, 0x58, signature.bytes);
    }
    if (column.key != key) {
      key = column.key;
      conductor.meta(downbeat, 0x59, [
        key.fifths & 0xFF,
        if (key.mode == KeyMode.minor) 1 else 0,
      ]);
    }
    final paces = clock.paces;
    for (final (i, (:at, :steady)) in paces.indexed) {
      final end = i + 1 < paces.length ? paces[i + 1].at : clock.length;
      final cuts = [at, if (!steady) ..._sixteenthsBetween(at, end), end];
      for (var c = 1; c < cuts.length; c++) {
        tempo.hold(
          _ticks(played + cuts[c - 1].wholeNotes),
          _ticks(played + cuts[c].wholeNotes),
          clock.secondsAt(cuts[c - 1]),
          clock.secondsAt(cuts[c]),
        );
      }
    }
    played += clock.length.wholeNotes;
  }
  for (final (:tick, :micros, seconds: _) in tempo.changes) {
    conductor.meta(tick, 0x51, [
      micros >> 16,
      micros >> 8 & 0xFF,
      micros & 0xFF,
    ]);
  }

  final parts = {for (final part in score.parts) part.id: part};
  final tracks = <PartId, _Track>{};
  for (final ChannelSetup(:channel, :part, :program, :bank, :expression)
      in script.channels) {
    final track = tracks[part] = _Track()..text(0, parts[part]!.name);
    if (bank < 128) {
      track
        ..add(0, _Rank.setup, [0xB0 | channel, 0, bank])
        ..add(0, _Rank.setup, [0xB0 | channel, 32, 0]);
    }
    track.add(0, _Rank.setup, [0xC0 | channel, program]);
    for (final ExpressionPoint(:seconds, :value) in expression.points) {
      track.add(tempo.tickAt(seconds), _Rank.expression, [
        0xB0 | channel,
        11,
        value,
      ]);
    }
  }
  // A bend holds a whole channel, as in the player, so it is kept by
  // channel and not by track.
  final bends = <int, int>{};
  for (final note in script.notesBetween(0, double.infinity)) {
    final track = tracks[score.partOf(note.source.staff).id]!;
    final channel = note.channel;
    final on = tempo.tickAt(note.start);
    final off = max(
      on + 1,
      tempo.tickAt(note.start + note.duration + note.overlap),
    );
    if (note.cents != (bends[channel] ?? 0)) {
      if (!bends.containsKey(channel)) {
        track.bendRange(channel);
      }
      final wheel = _bendCentre + note.cents * _bendCentre ~/ _bendRangeCents;
      track.add(on, _Rank.bend, [0xE0 | channel, wheel & 0x7F, wheel >> 7]);
      bends[channel] = note.cents;
    }
    track
      ..add(on, _Rank.on, [
        0x90 | channel,
        note.key,
        note.velocity.clamp(1, 127),
      ])
      ..add(off, _Rank.off, [0x80 | channel, note.key, 0]);
  }

  final chunks = [conductor, ...tracks.values];
  final end = _inReach(chunks, tempo.tickOf(_ticks(played)));
  final bytes = <int>[
    ...ascii.encode('MThd'),
    ..._u32(6),
    0,
    1,
    ..._u16(chunks.length),
    ..._u16(_ticksPerQuarter),
    for (final track in chunks) ...track.chunk(end),
  ];
  return Uint8List.fromList(bytes);
}

const _ticksPerQuarter = 960;

/// The pitch wheel at rest, of 0 to 16383.
const _bendCentre = 8192;

/// How far the wheel's end bends, as the player assumes.
const _bendRangeCents = 200;

int _ticks(Fraction wholes) =>
    (wholes.toDouble() * 4 * _ticksPerQuarter).round();

/// The sixteenths strictly between [from] and [to].
Iterable<Length> _sixteenthsBetween(Length from, Length to) sync* {
  final sixteenths = from.wholeNotes * Fraction(16);
  for (var k = sixteenths.floor() + 1; Length(Fraction(k, 16)) < to; k++) {
    yield Length(Fraction(k, 16));
  }
}

/// The tempo of the file, as microseconds a quarter from each tick where it
/// changes, with the seconds that tick falls at in those tempos.
///
/// A file's tempo stops at [_slowest], 3.58 quarters a minute. A stretch of
/// the score that is slower takes more ticks than its notes count, as many
/// as its seconds last at that tempo, and everything after it comes that
/// many ticks later. So the tempo after a slow stretch starts when the
/// stretch ends, and a long wait is counted in the longest ticks a file
/// has, which is the fewest.
final class _TempoMap {
  final List<({int tick, int micros, double seconds})> changes = [];

  /// How many more ticks the stretches held so far take than their notes
  /// count.
  int _stretched = 0;

  /// The file's tick of [notated], a tick of notated time at or after the
  /// last stretch held.
  int tickOf(int notated) => notated + _stretched;

  /// Makes `[from, to)` in ticks of notated time last from [start] to [end]
  /// in seconds.
  void hold(int from, int to, double start, double end) {
    if (to <= from) {
      return;
    }
    final quarterMicros = (end - start) * 1e6 * _ticksPerQuarter;
    final ticks = max(
      to - from,
      _whole((quarterMicros / _slowest).ceilToDouble()),
    );
    final at = tickOf(from);
    _stretched = min(_stretched + ticks - (to - from), _farthest);
    final exact = quarterMicros / ticks;
    final micros = exact < _slowest ? max(1, exact.round()) : _slowest;
    final last = changes.lastOrNull;
    if (last?.micros == micros) {
      return;
    }
    changes.add((
      tick: at,
      micros: micros,
      seconds: last == null
          ? 0
          : last.seconds + _seconds(at - last.tick, last.micros),
    ));
  }

  /// The tick that [seconds] falls nearest. It is 0 while the map holds no
  /// tempo, which is a script that plays no bar, so nothing has a time.
  int tickAt(double seconds) {
    if (changes.isEmpty) {
      return 0;
    }
    var low = 1;
    var high = changes.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (changes[mid].seconds > seconds) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    final at = changes[low - 1];
    return at.tick +
        _whole(
          ((seconds - at.seconds) * 1e6 * _ticksPerQuarter / at.micros)
              .roundToDouble(),
        );
  }
}

/// The most microseconds a quarter a file's tempo states.
const int _slowest = 0xFFFFFF;

/// The most ticks a stretch or a time is counted as, which is 1.3 billion
/// years at the slowest tempo. A tempo may be any number above 0, so a
/// score can ask for more, and its ticks stop here, where they still add up
/// without leaving the integers.
const int _farthest = 1 << 61;

/// [ticks] as an integer, held to [_farthest]. A tempo near none asks for
/// more ticks than an integer counts, or for no number at all.
int _whole(double ticks) => ticks < _farthest ? ticks.toInt() : _farthest;

double _seconds(int ticks, int micros) =>
    ticks * micros / _ticksPerQuarter / 1e6;

/// A time signature meta event: the bar as a count of a power-of-two unit,
/// and the MIDI clocks of its beat.
final class _TimeSignature {
  const _TimeSignature(this.count, this.unit, this.clocks);

  /// [meter], or the [length] of a pickup or a cadenza bar in its unit or a
  /// smaller one. Null when no power-of-two unit counts [length].
  static _TimeSignature? of(Meter meter, Length length) {
    final clocks = max(1, 96 * (meter.isCompound ? 3 : 1) ~/ meter.unit);
    if (length == meter.length) {
      return _TimeSignature(meter.numerator, meter.unit, clocks);
    }
    final Fraction(:numerator, :denominator) = length.wholeNotes;
    if (denominator & (denominator - 1) != 0) {
      return null;
    }
    final unit = max(denominator, meter.unit);
    final count = numerator * unit ~/ denominator;
    return count > 255 ? null : _TimeSignature(count, unit, clocks);
  }

  final int count;
  final int unit;
  final int clocks;

  List<int> get bytes => [count, unit.bitLength - 1, clocks, 8];

  @override
  bool operator ==(Object other) =>
      other is _TimeSignature &&
      other.count == count &&
      other.unit == unit &&
      other.clocks == clocks;

  @override
  int get hashCode => Object.hash(count, unit, clocks);
}

/// The order of events at one tick: a key is let go before it is struck
/// again, and an expression or a bend comes before the note it shapes.
enum _Rank { off, setup, expression, bend, on }

final class _Track {
  final List<({int tick, _Rank rank, List<int> bytes})> _events = [];

  void add(int tick, _Rank rank, List<int> bytes) =>
      _events.add((tick: tick, rank: rank, bytes: bytes));

  void meta(int tick, int type, List<int> data) =>
      add(tick, _Rank.setup, [0xFF, type, ..._vlq(data.length), ...data]);

  void text(int tick, String name) => meta(tick, 0x03, utf8.encode(name));

  /// Registered parameter 0, the bend range, at two semitones.
  void bendRange(int channel) {
    for (final (controller, value) in const [
      (101, 0),
      (100, 0),
      (6, _bendRangeCents ~/ 100),
      (38, 0),
      (101, 127),
      (100, 127),
    ]) {
      add(0, _Rank.setup, [0xB0 | channel, controller, value]);
    }
  }

  /// The tick of each event.
  Iterable<int> get ticks => _events.map((event) => event.tick);

  /// Moves each event to the tick [moved] gives its own.
  void move(int Function(int tick) moved) {
    for (final (i, (:tick, :rank, :bytes)) in _events.indexed) {
      _events[i] = (tick: moved(tick), rank: rank, bytes: bytes);
    }
  }

  /// The track chunk, ending at [end] or at its last event.
  List<int> chunk(int end) {
    final body = <int>[];
    var tick = 0;
    for (final (tick: at, rank: _, :bytes) in stableSorted(
      _events,
      (a, b) =>
          a.tick != b.tick ? a.tick - b.tick : a.rank.index - b.rank.index,
    )) {
      body
        ..addAll(_wait(at - tick))
        ..addAll(bytes);
      tick = at;
    }
    body.addAll([..._wait(max(end - tick, 0)), 0xFF, 0x2F, 0]);
    return [...ascii.encode('MTrk'), ..._u32(body.length), ...body];
  }
}

/// The most ticks one delta time counts, which is four bytes of seven bits.
const _longestDelta = 0x0FFFFFFF;

/// The most delta times one wait is written as. At the slowest tempo a
/// file states, 16.8 seconds a quarter, they last 38 years.
const _mostDeltas = 256;

/// The most ticks one wait is written as.
const int _longestWait = _mostDeltas * _longestDelta;

/// Cuts every silence of [tracks] that is longer than a wait is written
/// as, and answers where [end] is then.
///
/// A file counts time in ticks and has no slower tempo than [_slowest], so
/// a silence takes eight bytes for every 54 days it lasts, and a tempo may
/// be any number above 0. So no file of a bounded size keeps every time. A
/// stretch in which no track has an event for more than [_longestWait]
/// ticks is cut to that in every track alike. The tracks stay in step, and
/// what follows a silence of more than 38 years comes that much early. A
/// track that is silent while another plays waits for as long as the other
/// plays, in at most [_mostDeltas] delta times for each event of the
/// other.
int _inReach(List<_Track> tracks, int end) {
  final all = [0, end, for (final track in tracks) ...track.ticks];
  if (all.reduce(max) <= _longestWait) {
    return end;
  }
  final ticks = SplayTreeSet.of(all);
  final moved = <int, int>{};
  var before = 0;
  var cut = 0;
  for (final tick in ticks) {
    cut += max(tick - before - _longestWait, 0);
    moved[tick] = tick - cut;
    before = tick;
  }
  for (final track in tracks) {
    track.move((tick) => moved[tick]!);
  }
  return moved[end]!;
}

/// The delta time before an event [ticks] after the one before it. A wait
/// longer than [_longestDelta] is several delta times with an empty text
/// event after each but the last, so the event keeps its time.
List<int> _wait(int ticks) {
  var left = ticks;
  final bytes = <int>[];
  for (; left > _longestDelta; left -= _longestDelta) {
    bytes.addAll([..._vlq(_longestDelta), 0xFF, 0x01, 0]);
  }
  return bytes..addAll(_vlq(left));
}

/// [value] as a variable-length quantity: seven bits a byte, most
/// significant first, with the top bit set on all but the last.
List<int> _vlq(int value) {
  final bytes = [value & 0x7F];
  for (var rest = value >> 7; rest > 0; rest >>= 7) {
    bytes.insert(0, rest & 0x7F | 0x80);
  }
  return bytes;
}

List<int> _u32(int value) => [
  value >> 24 & 0xFF,
  value >> 16 & 0xFF,
  value >> 8 & 0xFF,
  value & 0xFF,
];

List<int> _u16(int value) => [value >> 8 & 0xFF, value & 0xFF];
