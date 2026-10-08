import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/system_sound.dart';

/// A meeting's own sound (lib/capture/system_sound.dart): where it can be had, by platform and by the binary's
/// generation, the words each platform says it in, and the Mac's tap commands answering safely when they fail. Case
/// for case with the web's `capture/systemSound.test.ts`.

class Platform implements SystemSoundBackend {
  bool tauri = false;
  bool android = false;
  bool mac = false;
  int generation = 0;
  SoundSupport available_ = const SoundSupport(supported: true, reason: null);
  SoundSupport? onHost;
  final List<String> invoked = [];

  @override
  Future<SoundSupport> available() async {
    invoked.add('system_audio_available');
    return available_;
  }

  @override
  Future<SoundStarted> start() async {
    invoked.add('system_audio_start');
    throw Exception('coreaudiod went away');
  }

  @override
  Future<void> stop() async {
    invoked.add('system_audio_stop');
    throw Exception('no system_audio_stop here');
  }

  @override
  Future<({bool capturing, bool heard})> status() async {
    invoked.add('system_audio_status');
    throw Exception('no system_audio_status here');
  }
}

void main() {
  var platform = Platform();

  /// The module, as this platform loads it afresh.
  SystemSound fresh() => SystemSound(
        backend: platform.tauri ? platform : null,
        isAndroid: platform.android,
        isMacApp: platform.mac,
        hasNativeGeneration: (wanted) async => platform.tauri && platform.generation >= wanted,
        meetingSoundOnHost: () => platform.onHost,
      );

  setUp(() => platform = Platform());

  group('where a meeting can have its own sound', () {
    test('is nowhere in a browser, and nowhere on a binary before generation 25', () async {
      expect(meetingSoundGeneration, 25);
      expect(await fresh().meetingSoundSupport(), isNull);
      platform.tauri = true;
      platform.mac = true;
      platform.generation = 24;
      expect(await fresh().meetingSoundSupport(), isNull);
      expect(platform.invoked, isNot(contains('system_audio_available')));
    });

    test('is the Mac’s answer on a Mac, which can be a no with the reason', () async {
      platform.tauri = true;
      platform.mac = true;
      platform.generation = 25;
      final sound = fresh();
      expect(await sound.meetingSoundSupport(), const SoundSupport(supported: true, reason: null));
      platform.available_ = const SoundSupport(supported: false, reason: 'Recording the computer’s sound needs macOS 14.2 or later.');
      expect(await sound.meetingSoundSupport(), platform.available_);
    });

    test('is the activity’s answer on Android, and asked of the service only with the switch on', () async {
      platform.tauri = true;
      platform.android = true;
      platform.generation = 25;
      platform.onHost = const SoundSupport(supported: true, reason: null);
      final sound = fresh();
      expect(await sound.meetingSoundSupport(), const SoundSupport(supported: true, reason: null));
      expect(await sound.wantsOtherApps(true), true);
      expect(await sound.wantsOtherApps(false), false);
      platform.onHost = const SoundSupport(supported: false, reason: 'Android 10 or later.');
      expect(await sound.wantsOtherApps(true), false);
    });
  });

  group('what it is called', () {
    test('says Android’s limit plainly on Android, and both sides of a call on the Mac', () async {
      platform.android = true;
      final android = fresh().meetingSoundWords();
      expect(android.label, 'Include sound from other apps');
      expect(android.hint, contains('Android lets Ghost.md hear media and games, never calls.'));
      platform.android = false;
      final mac = fresh().meetingSoundWords();
      expect(mac.label, "Record the computer's sound too");
      expect(mac.hint, contains('Both sides of a call'));
    });
  });

  group('the Mac’s tap', () {
    test('answers a start that failed as not capturing, with why, and a status it could not read as null', () async {
      platform.tauri = true;
      final sound = fresh();
      expect(await sound.startComputerSound(), const SoundStarted(capturing: false, reason: 'Error: coreaudiod went away'));
      expect(await sound.computerSoundStatus(), isNull);
      await expectLater(sound.stopComputerSound(), completes);
    });
  });
}
