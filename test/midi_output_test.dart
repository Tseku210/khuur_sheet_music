import 'package:flutter_test/flutter_test.dart';
import 'package:khuur_sheet_music/khuur_sheet_music.dart';
import 'package:khuur_synth/khuur_synth.dart' show Preset;
import 'package:khuur_synth/testing.dart';

const piano = AssetSoundFont('piano.sf2');
const reed = FileSoundFont('/fonts/reed.sf2');
const hall = Reverb(roomSize: 0.5, level: 0.3);

/// A [SynthOutput] over a silent synth, and every event that synth hears.
final class Rig {
  Rig({Reverb? reverb, double gain = SynthOutput.defaultGain}) {
    output = SynthOutput(
      reverb: reverb,
      gain: gain,
      open: () {
        opens++;
        return Synth.silent(onEvent: events.add, presets: presets);
      },
    );
  }

  late final SynthOutput output;
  final List<SynthEvent> events = [];
  int opens = 0;

  /// What a load finds in each SoundFont, General MIDI's bank 0 unless a
  /// test says otherwise.
  List<Preset> Function(SoundFont source) presets = (_) => [
    for (var program = 0; program < 128; program++)
      Preset(bank: 0, program: program, name: ''),
  ];

  /// The events since the last call.
  List<SynthEvent> take() {
    final taken = [...events];
    events.clear();
    return taken;
  }
}

/// Long enough for a silent synth to ring out, which it does after two
/// quiet ticks of 50 ms.
Future<void> ringOut() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  test(
    'the first load opens one synth at the output reverb and gain',
    () async {
      final rig = Rig(reverb: hall, gain: 0.5);
      await Future.wait([rig.output.load(piano), rig.output.load(reed)]);
      expect(rig.opens, 1);
      expect(rig.take(), [
        const ReverbChanged(hall),
        const GainChanged(0.5),
        const Loaded(piano),
        const Loaded(reed),
      ]);
      rig.output.dispose();
    },
  );

  test('the default gain is 0.8 with no reverb', () async {
    final rig = Rig();
    await rig.output.load(piano);
    expect(rig.take(), [
      const ReverbChanged(null),
      const GainChanged(0.8),
      const Loaded(piano),
    ]);
    rig.output.dispose();
  });

  test('a gain out of 0 to 10 is refused', () {
    expect(() => SynthOutput(gain: -0.1), throwsRangeError);
    expect(() => SynthOutput(gain: 10.5), throwsRangeError);
    expect(() => SynthOutput(gain: double.nan), throwsRangeError);
  });

  test('each SoundFont plays on its own 16 channels', () async {
    final rig = Rig();
    final output = rig.output;
    await output.load(piano);
    await output.load(reed);
    rig.take();
    await output.program(soundFont: piano, channel: 0, program: 0, bank: 0);
    await output.program(soundFont: reed, channel: 0, program: 71, bank: 0);
    output
      ..noteOn(soundFont: piano, channel: 0, key: 60, velocity: 80, cents: 0)
      ..noteOn(soundFont: reed, channel: 0, key: 67, velocity: 90, cents: 50)
      ..noteOff(soundFont: piano, channel: 0, key: 60);
    await pumpEventQueue();
    expect(rig.take(), [
      const Selected(channel: 0, source: piano, bank: 0, program: 0),
      const Started(),
      const Selected(channel: 16, source: reed, bank: 0, program: 71),
      const NoteOn(channel: 0, key: 60, velocity: 80, cents: 0),
      const NoteOn(channel: 16, key: 67, velocity: 90, cents: 50),
      const NoteOff(channel: 0, key: 60),
    ]);
    output.dispose();
  });

  test('a velocity outside 1 to 127 is held to it', () async {
    final rig = Rig();
    final output = rig.output;
    await output.load(piano);
    await output.program(soundFont: piano, channel: 3, program: 0, bank: 0);
    rig.take();
    output
      ..noteOn(soundFont: piano, channel: 3, key: 60, velocity: 0, cents: 0)
      ..noteOn(
        soundFont: piano,
        channel: 3,
        key: 62,
        velocity: 200,
        cents: -50,
      );
    await pumpEventQueue();
    expect(rig.take(), [
      const NoteOn(channel: 3, key: 60, velocity: 1, cents: 0),
      const NoteOn(channel: 3, key: 62, velocity: 127, cents: -50),
    ]);
    output.dispose();
  });

  test('a preset the SoundFont lacks leaves its channel silent', () async {
    final rig = Rig()
      ..presets = (_) => const [Preset(bank: 0, program: 0, name: '')];
    final output = rig.output;
    await output.load(piano);
    rig.take();
    await output.program(soundFont: piano, channel: 1, program: 40, bank: 0);
    await output.program(soundFont: piano, channel: 0, program: 0, bank: 0);
    expect(rig.take(), [
      const Started(),
      const Selected(channel: 0, source: piano, bank: 0, program: 0),
    ]);
    output.dispose();
  });

  test('all notes off cuts every sound at once', () async {
    final rig = Rig();
    await rig.output.load(piano);
    rig.take();
    rig.output.allNotesOff();
    await pumpEventQueue();
    expect(rig.take(), [const AllSoundsOff()]);
    rig.output.dispose();
  });

  test('a rest closes the device once the notes have rung out', () async {
    final rig = Rig();
    final output = rig.output;
    await output.load(piano);
    await output.program(soundFont: piano, channel: 0, program: 0, bank: 0);
    rig.take();
    output.rest();
    await ringOut();
    expect(rig.take(), [const Stopped(ringOut: true)]);
    output.dispose();
  });

  test('a program after a rest keeps the device open', () async {
    final rig = Rig();
    final output = rig.output;
    await output.load(piano);
    final first = output.program(
      soundFont: piano,
      channel: 0,
      program: 0,
      bank: 0,
    );
    output.rest();
    final second = output.program(
      soundFont: piano,
      channel: 0,
      program: 0,
      bank: 0,
    );
    await Future.wait([first, second]);
    await ringOut();
    expect(rig.events, contains(const Started()));
    expect(rig.events, isNot(contains(const Stopped(ringOut: true))));

    rig.take();
    output.rest();
    await ringOut();
    expect(rig.take(), [const Stopped(ringOut: true)]);
    output.dispose();
  });

  test('a rest before the first program does nothing', () async {
    final rig = Rig();
    rig.output.rest();
    await rig.output.load(piano);
    rig.output.rest();
    await ringOut();
    expect(rig.events.whereType<Stopped>(), isEmpty);
    rig.output.dispose();
  });

  test('a new reverb reaches the synth', () async {
    final rig = Rig();
    final output = rig.output..reverb = hall;
    await output.load(piano);
    expect(rig.take().first, const ReverbChanged(hall));
    output.reverb = null;
    await pumpEventQueue();
    expect(rig.take(), [const ReverbChanged(null)]);
    expect(output.reverb, isNull);
    output.dispose();
  });

  test('a failed open lets the next load open again', () async {
    var opens = 0;
    final events = <SynthEvent>[];
    final output = SynthOutput(
      open: () {
        if (opens++ == 0) {
          return Future.error(StateError('no audio'));
        }
        return Synth.silent(onEvent: events.add);
      },
    );
    await expectLater(output.load(piano), throwsStateError);
    await output.load(piano);
    expect(opens, 2);
    expect(events, contains(const Loaded(piano)));
    output.dispose();
  });

  test('dispose closes the synth', () async {
    final rig = Rig();
    await rig.output.load(piano);
    rig.take();
    rig.output.dispose();
    await pumpEventQueue();
    expect(rig.take(), [const Closed()]);
  });

  test('dispose while the synth opens closes it once it is open', () async {
    final rig = Rig();
    final loading = rig.output.load(piano);
    rig.output.dispose();
    await loading;
    await pumpEventQueue();
    expect(rig.events, [const Closed()]);
  });

  test('an output plays from at most 16 SoundFonts', () async {
    final rig = Rig();
    for (var i = 0; i < 16; i++) {
      await rig.output.load(FileSoundFont('/fonts/$i.sf2'));
    }
    await expectLater(
      rig.output.load(const FileSoundFont('/fonts/16.sf2')),
      throwsStateError,
    );
    rig.output.dispose();
  });
}
