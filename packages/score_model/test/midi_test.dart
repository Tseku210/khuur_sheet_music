import 'dart:convert';
import 'dart:typed_data';

import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'showcase.dart';
import 'support.dart';

/// A Standard MIDI File read back, as far as the tests look into one.
final class MidiFile {
  factory MidiFile.read(Uint8List bytes) {
    final reader = _Reader(bytes);
    expect(reader.text(4), 'MThd');
    expect(reader.u32(), 6);
    final format = reader.u16();
    final count = reader.u16();
    final division = reader.u16();
    final tracks = [
      for (var i = 0; i < count; i++) reader.track(),
    ];
    expect(reader.atEnd, isTrue, reason: 'nothing after the last track');
    return MidiFile._(format, division, tracks);
  }

  MidiFile._(this.format, this.division, this.tracks);

  final int format;
  final int division;
  final List<List<MidiEvent>> tracks;

  /// The tempo changes of the first track, as (tick, microseconds a
  /// quarter).
  late final List<(int, int)> tempos = [
    for (final event in tracks.first)
      if (event.meta == 0x51)
        (event.tick, event.data[0] << 16 | event.data[1] << 8 | event.data[2]),
  ];

  List<List<int>> metas(int type, [int track = 0]) => [
    for (final event in tracks[track])
      if (event.meta == type) [event.tick, ...event.data],
  ];

  int _microsAt(int tick) {
    var micros = 500000;
    for (final (at, value) in tempos) {
      if (at > tick) {
        break;
      }
      micros = value;
    }
    return micros;
  }

  double secondsAt(int tick) {
    var seconds = 0.0;
    var from = 0;
    var micros = 500000;
    for (final (at, value) in tempos) {
      if (at >= tick) {
        break;
      }
      seconds += (at - from) * micros / division / 1e6;
      from = at;
      micros = value;
    }
    return seconds + (tick - from) * micros / division / 1e6;
  }

  /// How long one tick lasts at [tick].
  double tickSecondsAt(int tick) => _microsAt(tick) / division / 1e6;

  /// The notes of [track], each struck key paired with the next release of
  /// that key on that channel.
  List<MidiNote> notes(int track) {
    final held = <(int, int), List<MidiEvent>>{};
    final notes = <MidiNote>[];
    for (final event in tracks[track]) {
      if (event.status case final status? when status & 0xE0 == 0x80) {
        final channel = status & 0x0F;
        final [key, velocity] = event.data;
        final lane = (channel, key);
        if (status & 0xF0 == 0x90 && velocity > 0) {
          (held[lane] ??= []).add(event);
        } else {
          final on = held[lane]!.removeAt(0);
          notes.add(
            MidiNote(channel, key, on.data[1], on.tick, event.tick),
          );
        }
      }
    }
    expect(held.values.every((keys) => keys.isEmpty), isTrue);
    return notes;
  }

  List<MidiNote> get allNotes => [
    for (var i = 0; i < tracks.length; i++) ...notes(i),
  ];

  /// The channel messages of [track] with [kind] as their top four bits,
  /// each as its tick, its channel and its data.
  List<List<int>> messages(int track, int kind) => [
    for (final event in tracks[track])
      if (event.status case final status? when status >> 4 == kind)
        [event.tick, status & 0x0F, ...event.data],
  ];

  String? name(int track) => [
    for (final event in tracks[track])
      if (event.meta == 0x03) utf8.decode(event.data),
  ].firstOrNull;
}

/// A channel message has a status byte; a meta event has a meta type.
typedef MidiEvent = ({int tick, int? status, int? meta, List<int> data});

final class MidiNote {
  const MidiNote(this.channel, this.key, this.velocity, this.on, this.off);

  final int channel;
  final int key;
  final int velocity;
  final int on;
  final int off;
}

final class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  var _at = 0;

  bool get atEnd => _at == _bytes.length;

  int byte() => _bytes[_at++];

  List<int> take(int count) => [..._bytes.sublist(_at, _at += count)];

  String text(int count) => ascii.decode(take(count));

  int u16() => byte() << 8 | byte();

  int u32() => u16() << 16 | u16();

  int vlq() {
    var value = 0;
    int next;
    do {
      next = byte();
      value = value << 7 | next & 0x7F;
    } while (next & 0x80 != 0);
    return value;
  }

  List<MidiEvent> track() {
    expect(text(4), 'MTrk');
    final end = u32() + _at;
    final events = <MidiEvent>[];
    var tick = 0;
    int? running;
    while (_at < end) {
      tick += vlq();
      var status = _bytes[_at];
      if (status == 0xFF) {
        _at++;
        final type = byte();
        events.add((tick: tick, status: null, meta: type, data: take(vlq())));
        if (type == 0x2F) {
          break;
        }
        continue;
      }
      if (status & 0x80 != 0) {
        _at++;
        running = status;
      } else {
        status = running!;
      }
      final size = status >> 4 == 0xC || status >> 4 == 0xD ? 1 : 2;
      events.add((tick: tick, status: status, meta: null, data: take(size)));
    }
    expect(_at, end, reason: 'the end of track closes the chunk');
    expect(events.last.meta, 0x2F);
    return events;
  }
}

MidiFile exported(Score score) => MidiFile.read(scoreToMidi(score));

/// Every note the script plays is in the file, with the same key, channel
/// and velocity, and starts and ends within a tick of the script's time.
/// The file has no other note.
void expectPlaysAsScript(Score score) {
  final script = PlaybackCompiler().compile(score);
  final file = exported(score);
  final unmatched = file.allNotes;
  final scripted = script.notesBetween(0, double.infinity).toList();
  bool near(double seconds, int tick) =>
      (file.secondsAt(tick) - seconds).abs() <= file.tickSecondsAt(tick) + 1e-9;
  for (final note in scripted) {
    final found = unmatched.indexWhere(
      (heard) =>
          heard.channel == note.channel &&
          heard.key == note.key &&
          heard.velocity == note.velocity &&
          near(note.start, heard.on),
    );
    expect(
      found,
      isNot(-1),
      reason: 'key ${note.key} on channel ${note.channel} at ${note.start}',
    );
    unmatched.removeAt(found);
  }
  expect(unmatched, isEmpty);

  // Ticks count notated time, so each played bar starts at its script time
  // on the tick its length puts it at.
  var wholes = Fraction.zero;
  for (final bar in script.bars) {
    final downbeat = (wholes.toDouble() * whole).round();
    expect(
      near(bar.start, downbeat),
      isTrue,
      reason: 'bar ${bar.measure.value} at ${bar.start}, tick $downbeat',
    );
    wholes += score.column(bar.measure).length.wholeNotes;
  }

  // A key struck again while held lets go at the first release, so ends are
  // compared per key and channel, in order.
  final ends = <(int, int), List<double>>{};
  for (final note in scripted) {
    (ends[(note.channel, note.key)] ??= []).add(note.start + note.duration);
  }
  final releases = <(int, int), List<int>>{};
  for (final note in file.allNotes) {
    (releases[(note.channel, note.key)] ??= []).add(note.off);
  }
  for (final MapEntry(key: lane, value: times) in ends.entries) {
    final heard = releases[lane]!..sort();
    times.sort();
    for (final (i, seconds) in times.indexed) {
      expect(
        near(seconds, heard[i]),
        isTrue,
        reason: 'release of $lane at $seconds, heard at ${heard[i]}',
      );
    }
  }
}

const quarter = 960;
const int whole = 4 * quarter;

/// A blank score of [bars] bars of four C4 quarters, with bar one at 60
/// quarters a minute.
Score quarters(int bars, {List<PartTemplate> parts = const [morinKhuur]}) {
  var score = blankScore(parts: parts, bars: bars);
  for (var i = 0; i < bars; i++) {
    score = fill(score, i, [
      for (var beat = 1; beat <= 4; beat++) chordOf(10 * (i + 1) + beat, 'C4'),
    ]);
  }
  return tempoAt(score, 0, Moment.zero, const Tempo(60));
}

Score tempoAt(Score score, int bar, Moment offset, Tempo tempo) => changeBar(
  score,
  bar,
  (column) => column.copyWith(
    tempos: Seq([
      for (final mark in column.tempos)
        if (mark.offset != offset) mark,
      TempoMark(offset: offset, tempo: tempo),
    ]),
  ),
);

List<int> onsets(MidiFile file, [int track = 1]) => [
  for (final note in file.notes(track)) note.on,
];

void main() {
  group('scoreToMidi', () {
    test('writes the showcase as its playback script plays it', () {
      final score = showcase();
      expectPlaysAsScript(score);

      final file = exported(score);
      final script = PlaybackCompiler().compile(score);
      expect(file.format, 1);
      expect(file.division, quarter);
      expect(file.tracks, hasLength(script.channels.length + 1));
      expect(file.name(0), 'Showcase');
      for (final (i, setup) in script.channels.indexed) {
        final track = i + 1;
        expect(
          file.name(track),
          score.parts.firstWhere((part) => part.id == setup.part).name,
        );
        expect(file.messages(track, 0xC), [
          [0, setup.channel, setup.program],
        ]);
        expect({
          for (final note in file.notes(track)) note.channel,
        }, anyOf(isEmpty, {setup.channel}));
      }
    });

    test('writes the bank of a part under 128 and leaves larger ones', () {
      final file = exported(showcase());

      expect(
        [
          for (final [_, channel, ...data] in file.messages(1, 0xB))
            [channel, ...data],
        ],
        containsAllInOrder([
          [0, 0, 0],
          [0, 32, 0],
        ]),
      );
      expect(
        [
          for (final [_, _, controller, _] in file.messages(3, 0xB)) controller,
        ],
        isNot(anyOf(contains(0), contains(32))),
        reason: 'the drums are bank 128',
      );
    });

    test('writes each played bar\'s time and key signature', () {
      final file = exported(showcase());

      // The pickup, the bar after it, the pickup again on the repeat, a 6/8
      // bar and a 3+2+2/8 bar.
      expect(file.metas(0x58), [
        [0, 1, 2, 24, 8],
        [quarter, 4, 2, 24, 8],
        [5 * quarter, 1, 2, 24, 8],
        [6 * quarter, 6, 3, 36, 8],
        [9 * quarter, 7, 3, 12, 8],
      ]);
      expect(file.metas(0x59), [
        [0, 2, 0],
        [6 * quarter, 0xFD, 1],
      ]);
    });

    test('plays a repeat twice', () {
      final score = changeBar(
        quarters(2),
        1,
        (column) => column.copyWith(repeatEnd: () => const RepeatEnd()),
      );
      expectPlaysAsScript(score);

      expect(onsets(exported(score)), [
        for (var beat = 0; beat < 16; beat++) beat * quarter,
      ]);
    });

    test('writes a tempo mark in the middle of a bar as a tempo change', () {
      final score = tempoAt(
        quarters(2),
        1,
        Moment(Fraction(1, 2)),
        const Tempo(120),
      );
      expectPlaysAsScript(score);

      final file = exported(score);
      expect(file.tempos, [(0, 1000000), (whole + 2 * quarter, 500000)]);
      expect(onsets(file), [
        for (var beat = 0; beat < 8; beat++) beat * quarter,
      ]);
      expect(file.secondsAt(2 * whole), 7);
    });

    test('a tempo of a dotted beat is in quarters', () {
      final score = tempoAt(
        quarters(1),
        0,
        Moment.zero,
        Tempo(40, beat: NoteValue.quarter.dotted),
      );
      expectPlaysAsScript(score);

      expect(exported(score).tempos, [(0, 1000000)]);
    });

    test('steps a tempo line by sixteenths and keeps notes on their beats', () {
      final first = quarters(2);
      final score = withSpanner(
        first,
        const TempoLine(text: 'accel.', factor: 2),
        ScorePoint(first.measures[0].id, Moment.zero),
        ScorePoint(first.measures[1].id, Moment(Fraction(3, 4))),
      );
      expectPlaysAsScript(score);

      final file = exported(score);
      expect(file.tempos.length, greaterThan(16));
      expect([
        for (final (tick, _) in file.tempos) tick % (quarter ~/ 4),
      ], everyElement(0));
      final micros = [for (final (_, micros) in file.tempos) micros];
      expect(
        micros,
        [...micros]..sort((a, b) => b - a),
        reason: 'it only gets faster',
      );
      expect(onsets(file), [
        for (var beat = 0; beat < 8; beat++) beat * quarter,
      ]);
    });

    test('writes a tie chain as one note', () {
      var score = quarters(2);
      score = fill(score, 0, [
        chordOf(1, 'E4', value: NoteValue.whole, tie: true),
      ]);
      score = fill(score, 1, [chordOf(2, 'E4', value: NoteValue.whole)]);
      expectPlaysAsScript(score);

      final notes = exported(score).notes(1);
      expect([for (final note in notes) (note.key, note.on)], [(64, 0)]);
      expect(notes.single.off, greaterThan(whole));
    });

    test('bends a quarter tone and bends back for the next note', () {
      var score = quarters(1);
      score = fill(score, 0, [
        chordOf(1, 'C+4'),
        chordOf(2, 'C4'),
        chordOf(3, 'Ed4'),
        chordOf(4, 'Ed4'),
      ]);
      expectPlaysAsScript(score);

      final file = exported(score);
      expect(
        [
          for (final [tick, channel, low, high] in file.messages(1, 0xE))
            (tick, channel, high << 7 | low),
        ],
        [(0, 0, 10240), (quarter, 0, 8192), (2 * quarter, 0, 10240)],
      );
      expect(
        [for (final [_, _, ...data] in file.messages(1, 0xB)) data],
        containsAllInOrder([
          [101, 0],
          [100, 0],
          [6, 2],
          [38, 0],
        ]),
        reason: 'the bend range is two semitones',
      );
    });

    test('gives each of two parts its track, channel and program', () {
      var score = quarters(1, parts: const [morinKhuur, clarinet]);
      score = fill(score, 0, [
        chordOf(5, 'G4', value: NoteValue.whole),
      ], staff: 1);
      expectPlaysAsScript(score);

      final file = exported(score);
      expect(file.tracks, hasLength(3));
      expect([file.name(1), file.name(2)], ['Морин хуур', 'Clarinet in B♭']);
      expect(file.messages(1, 0xC), [
        [0, 0, 110],
      ]);
      expect(file.messages(2, 0xC), [
        [0, 1, 71],
      ]);
      expect(
        [for (final note in file.notes(1)) (note.channel, note.key)],
        [
          for (var beat = 0; beat < 4; beat++) (0, 60),
        ],
      );
      expect(
        [for (final note in file.notes(2)) (note.channel, note.key)],
        [
          (1, 67),
        ],
      );
    });
  });
}
