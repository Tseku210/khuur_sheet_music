import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khuur_sheet_music/src/midi_output.dart';
import 'package:khuur_sheet_music/src/sound_font.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeMidiPlatform extends FlutterMidiProPlatform
    with MockPlatformInterfaceMixin {
  final calls = <String>[];
  final loaded = <List<int>>[];
  String? selectError;

  @override
  Future<void> init(int sampleRate, int bufferSize, int polyphony) async {}

  @override
  Future<int> loadSoundfont(String path, int bank, int program) async {
    loaded.add(File(path).readAsBytesSync());
    return 7;
  }

  @override
  Future<void> selectInstrument(
    int sfId,
    int channel,
    int bank,
    int program,
  ) async {
    calls.add('select sf$sfId $channel = $bank/$program');
    if (selectError case final code?) {
      throw PlatformException(code: code);
    }
  }

  @override
  Future<void> playNote(int channel, int key, int velocity, int sfId) async =>
      calls.add('on sf$sfId $channel:$key v$velocity');

  @override
  Future<void> stopNote(int channel, int key, int sfId) async =>
      calls.add('off sf$sfId $channel:$key');

  @override
  Future<void> stopAllNotes(int sfId) async => calls.add('all off sf$sfId');

  @override
  Future<void> pitchBend(int sfId, int channel, int value) async =>
      calls.add('bend sf$sfId $channel = $value');

  @override
  Future<void> unloadSoundfont(int sfId) async => calls.add('unload sf$sfId');

  @override
  Future<void> dispose() async {}
}

/// A platform whose `init` waits for [endInit] and fails with [initError].
/// Its [calls] also tell when `init` begins and ends and when a SoundFont
/// is loaded.
class GatedMidiPlatform extends FakeMidiPlatform {
  PlatformException? initError;

  // Made by `init`. A future answers in the zone it was made in, and a
  // test's body is not in the zone its `runAsync` waits in.
  late Completer<void> _initGate;

  void endInit() => _initGate.complete();

  @override
  Future<void> init(int sampleRate, int bufferSize, int polyphony) async {
    calls.add('init begins');
    _initGate = Completer<void>();
    await _initGate.future;
    if (initError case final error?) {
      throw error;
    }
    calls.add('init ends');
  }

  @override
  Future<int> loadSoundfont(String path, int bank, int program) {
    calls.add('load');
    return super.loadSoundfont(path, bank, program);
  }
}

class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getTemporaryPath() async => dir.path;
}

void main() {
  late FakeMidiPlatform midi;
  late Directory tmp;
  late SoundFont soundFont;

  /// The app's asset bundle, by asset key. A path that is not a key here is
  /// not an asset.
  late Map<String, List<int>> assets;

  setUp(() {
    assets = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'flutter/assets',
          (message) async => switch (assets[utf8.decode(
            message!.buffer.asUint8List(),
          )]) {
            final bytes? => ByteData.sublistView(Uint8List.fromList(bytes)),
            null => null,
          },
        );
    tmp = Directory.systemTemp.createTempSync('midi_output_test');
    final sf2 = File('${tmp.path}/piano.sf2')..writeAsBytesSync([1, 2, 3]);
    soundFont = FileSoundFont(sf2.path);
    midi = FakeMidiPlatform();
    FlutterMidiProPlatform.instance = midi;
    PathProviderPlatform.instance = FakePathProvider(tmp);
  });

  tearDown(() async {
    // The plugin is one synthesizer for the whole process, so a test shuts
    // down the one it started.
    if (MidiPro().isInitialized) {
      await MidiPro().dispose();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    tmp.deleteSync(recursive: true);
  });

  testWidgets('loads a file SoundFont and plays through it', (tester) async {
    final output = FlutterMidiOutput();
    await tester.runAsync(() => output.load(soundFont));
    await output.program(channel: 1, program: 71, bank: 2);
    output
      ..noteOn(channel: 1, key: 60, velocity: 80, cents: 0)
      ..noteOff(channel: 1, key: 60)
      ..allNotesOff()
      ..dispose();

    expect(midi.loaded, [
      [1, 2, 3],
    ]);
    expect(midi.calls, [
      'bend sf7 1 = 8192',
      'select sf7 1 = 2/71',
      'on sf7 1:60 v80',
      'off sf7 1:60',
      'all off sf7',
      'unload sf7',
    ]);
  });

  testWidgets('loads an asset SoundFont by its app asset key', (tester) async {
    assets['assets/soundfonts/piano.sf2'] = [4, 5, 6];
    final output = FlutterMidiOutput();
    await tester.runAsync(
      () => output.load(const AssetSoundFont('assets/soundfonts/piano.sf2')),
    );

    expect(midi.loaded, [
      [4, 5, 6],
    ]);
    output.dispose();
  });

  testWidgets('a preset the SoundFont lacks is not a failure', (tester) async {
    final output = FlutterMidiOutput();
    await tester.runAsync(() => output.load(soundFont));

    for (final code in ['SOUND_FONT_LOAD_FAILED', 'SOUND_FONT_LOAD_FAILED2']) {
      midi.selectError = code;
      await output.program(channel: 0, program: 40, bank: 0);
    }

    midi.selectError = 'NOT_INITIALIZED';
    await expectLater(
      output.program(channel: 0, program: 40, bank: 0),
      throwsA(isA<PlatformException>()),
    );
    output.dispose();
  });

  testWidgets(
    'a bank the plugin cannot take is a preset the SoundFont lacks, and the '
    'largest it can take is asked for',
    (tester) async {
      final output = FlutterMidiOutput();
      await tester.runAsync(() => output.load(soundFont));

      await output.program(channel: 0, program: 40, bank: 255);
      await output.program(channel: 1, program: 40, bank: 256);
      await output.program(channel: 2, program: 40, bank: 15360);
      output
        ..noteOn(channel: 1, key: 60, velocity: 80, cents: 0)
        ..dispose();

      expect(midi.calls, [
        'bend sf7 0 = 8192',
        'select sf7 0 = 255/40',
        'bend sf7 1 = 8192',
        'bend sf7 2 = 8192',
        'on sf7 1:60 v80',
        'unload sf7',
      ]);
    },
  );

  testWidgets(
    'bends a channel for a quarter tone, and back for the next note that '
    'is not one',
    (tester) async {
      final output = FlutterMidiOutput();
      await tester.runAsync(() => output.load(soundFont));
      await output.program(channel: 0, program: 0, bank: 0);
      await output.program(channel: 1, program: 0, bank: 0);
      midi.calls.clear();
      output
        ..noteOn(channel: 0, key: 60, velocity: 80, cents: 0)
        ..noteOn(channel: 0, key: 62, velocity: 80, cents: 50)
        ..noteOn(channel: 0, key: 64, velocity: 80, cents: 50)
        ..noteOn(channel: 1, key: 48, velocity: 80, cents: 0)
        ..noteOn(channel: 0, key: 65, velocity: 80, cents: 0)
        ..dispose();

      expect(midi.calls, [
        'on sf7 0:60 v80',
        'bend sf7 0 = 10240',
        'on sf7 0:62 v80',
        'on sf7 0:64 v80',
        'on sf7 1:48 v80',
        'bend sf7 0 = 8192',
        'on sf7 0:65 v80',
        'unload sf7',
      ]);
    },
  );

  testWidgets(
    'puts a channel at rest before its first program, since an output '
    'before it may have left it bent, and not again while it is at rest',
    (tester) async {
      final output = FlutterMidiOutput();
      await tester.runAsync(() => output.load(soundFont));
      await output.program(channel: 3, program: 0, bank: 0);
      output.noteOn(channel: 3, key: 60, velocity: 80, cents: 0);
      await output.program(channel: 3, program: 5, bank: 0);
      output.dispose();

      expect(midi.calls, [
        'bend sf7 3 = 8192',
        'select sf7 3 = 0/0',
        'on sf7 3:60 v80',
        'select sf7 3 = 0/5',
        'unload sf7',
      ]);
    },
  );

  testWidgets(
    'puts a bent channel at rest before a new program, and bends it again '
    'for the next quarter tone',
    (tester) async {
      final output = FlutterMidiOutput();
      await tester.runAsync(() => output.load(soundFont));
      await output.program(channel: 0, program: 0, bank: 0);
      output.noteOn(channel: 0, key: 60, velocity: 80, cents: 50);
      await output.program(channel: 0, program: 0, bank: 0);
      output
        ..noteOn(channel: 0, key: 60, velocity: 80, cents: 50)
        ..dispose();

      expect(midi.calls, [
        'bend sf7 0 = 8192',
        'select sf7 0 = 0/0',
        'bend sf7 0 = 10240',
        'on sf7 0:60 v80',
        'bend sf7 0 = 8192',
        'select sf7 0 = 0/0',
        'bend sf7 0 = 10240',
        'on sf7 0:60 v80',
        'unload sf7',
      ]);
    },
  );

  testWidgets('disposed while loading, unloads the SoundFont once it arrives', (
    tester,
  ) async {
    final output = FlutterMidiOutput();
    await tester.runAsync(() async {
      final loading = output.load(soundFont);
      output
        ..allNotesOff()
        ..dispose();
      expect(midi.calls, isEmpty);
      await loading;
    });

    expect(midi.calls, ['unload sf7']);
  });

  testWidgets(
    'two outputs that load at once share one init, and neither loads its '
    'SoundFont before it ends',
    (tester) async {
      final gated = GatedMidiPlatform();
      FlutterMidiProPlatform.instance = gated;
      final first = FlutterMidiOutput();
      final second = FlutterMidiOutput();

      await tester.runAsync(() async {
        final loading = [first.load(soundFont), second.load(soundFont)];
        // An output that did not wait for the init would load its SoundFont
        // in this time.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        gated.endInit();
        await Future.wait(loading);
      });

      expect(gated.calls, ['init begins', 'init ends', 'load', 'load']);
      first.dispose();
      second.dispose();
    },
  );

  testWidgets('a load after an init that failed starts init again', (
    tester,
  ) async {
    final gated = GatedMidiPlatform()
      ..initError = PlatformException(code: 'INIT_FAILED');
    FlutterMidiProPlatform.instance = gated;
    final first = FlutterMidiOutput();
    final second = FlutterMidiOutput();

    await tester.runAsync(() async {
      final loading = [first.load(soundFont), second.load(soundFont)];
      gated.endInit();
      await Future.wait([
        for (final load in loading)
          expectLater(load, throwsA(isA<PlatformException>())),
      ]);
      gated.initError = null;
      final again = second.load(soundFont);
      gated.endInit();
      await again;
    });

    expect(gated.calls, ['init begins', 'init begins', 'init ends', 'load']);
    first.dispose();
    second.dispose();
  });
}
