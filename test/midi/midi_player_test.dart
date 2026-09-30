import 'dart:io';

import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';

class FakeMidiPlatform extends FlutterMidiProPlatform
    with MockPlatformInterfaceMixin {
  final events = <String>[];

  @override
  Future<void> init(int sampleRate, int bufferSize, int polyphony) async {}

  @override
  Future<int> loadSoundfont(String path, int bank, int program) async => 7;

  @override
  Future<void> playNote(int channel, int key, int velocity, int sfId) async =>
      events.add('on $key sf$sfId');

  @override
  Future<void> stopNote(int channel, int key, int sfId) async =>
      events.add('off $key sf$sfId');

  @override
  Future<void> unloadSoundfont(int sfId) async => events.add('unload sf$sfId');
}

class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getTemporaryPath() async => dir.path;

  @override
  Future<String?> getApplicationCachePath() async => dir.path;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

void main() {
  late FakeMidiPlatform midi;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('midi_player_test');
    midi = FakeMidiPlatform();
    FlutterMidiProPlatform.instance = midi;
    PathProviderPlatform.instance = FakePathProvider(tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('releases each note when its duration ends and on pause',
      (tester) async {
    const c4 = 60;
    const d4 = 62;
    final player = MidiPlayer();
    await tester.runAsync(player.initialize);
    player
      ..loadMeasures([
        Measure([Note(Pitch.c4), Rest(RestType.quarter), Note(Pitch.d4)]),
      ])
      ..play();
    expect(midi.events, ['on $c4 sf7']);

    await tester.pump(const Duration(milliseconds: 500));
    expect(midi.events, ['on $c4 sf7', 'off $c4 sf7'],
        reason: 'a rest silences the previous note');

    await tester.pump(const Duration(milliseconds: 500));
    player.pause();
    expect(midi.events,
        ['on $c4 sf7', 'off $c4 sf7', 'on $d4 sf7', 'off $d4 sf7']);

    player.dispose();
    expect(midi.events.last, 'unload sf7');
  });
}
