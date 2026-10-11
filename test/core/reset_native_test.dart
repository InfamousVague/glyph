import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/reset_native.dart';

/// The phone's half of a reset (lib/core/reset_native.dart): the order it asks the phone and the core in, what it
/// refuses, and what it does where there is no phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> asked;
  Future<Object?> core(String command, [Map<String, Object?> args = const {}]) async {
    asked.add('core:$command $args');
    return null;
  }

  void phone(Future<Object?> Function(MethodCall call) answer) => messenger.setMockMethodCallHandler(resetChannel, (call) {
        asked.add('phone:${call.method}');
        return answer(call);
      });

  setUp(() => asked = []);
  tearDown(() => messenger.setMockMethodCallHandler(resetChannel, null));

  test('speaks on the channel reset.dart names', () {
    expect(resetChannel.name, 'ghost.md/reset');
  });

  test('asks the service, waits for the write-ups to let go, wipes the files, then forgets the secrets', () async {
    final letGo = Completer<void>();
    phone((call) async {
      if (call.method == 'recording') return false;
      if (call.method == 'cancelWriteUps') await letGo.future;
      return null;
    });
    final reset = PhoneReset(invoke: core);
    expect(await reset.hasGeneration(11), isTrue);
    reset.cancelWriteUps();
    final done = reset.resetLocalData(models: true);
    await pumpEventQueue();
    expect(asked, ['phone:cancelWriteUps', 'phone:recording'], reason: 'no file goes while a write-up still runs');
    letGo.complete();
    await done;
    expect(asked, ['phone:cancelWriteUps', 'phone:recording', 'core:reset_local_data {models: true}', 'phone:forgetSecrets']);
  });

  test('refuses while the service is recording, whatever the app last heard, with nothing wiped', () async {
    phone((call) async => call.method == 'recording');
    final reset = PhoneReset(invoke: core, recordingNow: () => false);
    expect(reset.recording(), isFalse);
    await expectLater(reset.resetLocalData(models: false), throwsA(isA<StateError>().having((e) => e.message, 'message', 'Stop the meeting first.')));
    expect(asked, ['phone:recording']);
    expect(PhoneReset(invoke: core, recordingNow: () => true).recording(), isTrue);
  });

  test('says the core’s own sentence, and leaves the secrets when the files did not go', () async {
    phone((call) async => call.method == 'recording' ? false : null);
    final reset = PhoneReset(invoke: (command, [args = const {}]) async => throw const CoreError('could not remove the recordings at /data: denied'));
    await expectLater(reset.resetLocalData(models: false), throwsA(isA<CoreError>().having((e) => e.message, 'message', startsWith('could not remove the recordings'))));
    expect(asked, ['phone:recording']);
  });

  test('a secure store that would not empty fails the reset in its own words', () async {
    phone((call) async {
      if (call.method == 'forgetSecrets') throw PlatformException(code: 'secure_store', message: 'A kept sign-in could not be forgotten.');
      return call.method == 'recording' ? false : null;
    });
    await expectLater(PhoneReset(invoke: core).resetLocalData(models: false), throwsA(isA<StateError>().having((e) => e.message, 'message', 'A kept sign-in could not be forgotten.')));
    expect(asked.last, 'phone:forgetSecrets');
  });

  test('with no phone half, the core’s wipe is the whole of it', () async {
    final reset = PhoneReset(invoke: core);
    reset.cancelWriteUps();
    await reset.resetLocalData(models: false);
    expect(asked, ['core:reset_local_data {models: false}']);
  });
}
