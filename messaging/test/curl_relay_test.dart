import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/account/account_crypto.dart';
import 'package:ghost_messaging/me/me.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_relay/handles.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/relay.dart';

/// Me.curlKeep / Me.curlKept against a real relay over a real socket: the relay's `curl-keep` / `curl-kept` answers
/// have to reach the one waiting for them. They didn't (Me._heard had no case for either), so every read timed out,
/// CurlSync.pull swallowed it, and no device ever picked up what the browser extension synced. The other tests of the
/// blob (plugin_sync_test) go through a FakeRelay that never touches Me._heard, so this one goes through the real one.

Future<void> _until(bool Function() done, {String? reason}) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Relay relay;
  late int port;
  late Directory dir;
  final words = AccountCrypto.wordsOf(List.filled(16, 3));

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('ghost_messaging/sms'),
      (call) async => call.method == 'secretRead' && (call.arguments as Map)['name'] == 'account_words' ? words.join(' ') : null,
    );
    dir = Directory.systemTemp.createTempSync('curl');
    relay = Relay(hub: Hub(handles: Handles(dataDir: dir, config: const HandlesConfig(publicUrl: 'http://127.0.0.1'))));
    port = await relay.start(port: 0);
  });
  tearDown(() async {
    await relay.stop();
    dir.deleteSync(recursive: true);
  });

  test('a blob kept on the relay is read back by Me, within the wait, by another device of the same identity', () async {
    final keys = NetKeys.generate();
    Future<Me> device() async {
      final hub = HubCarrier(url: 'ws://127.0.0.1:$port/hub', signer: KeysSigner(keys));
      await hub.start();
      await _until(() => hub.state.value == CarrierState.up, reason: hub.problem);
      final me = Me.forTest();
      await me.start(MemoryMeStore(), ChangeNotifier(), () => hub);
      return me;
    }

    // One after the other: both connect with no device name, so the relay treats the second as the first reconnecting.
    final desktop = await device();
    expect(await desktop.curlKept().timeout(const Duration(seconds: 5)), isNull);
    final blob = {
      'v': 1,
      'entries': {
        'discord': {'cookies': {'token': 'x' * 40}, 'at': 1, 'from': 'Chrome'},
      },
    };
    await desktop.curlKeep(blob).timeout(const Duration(seconds: 5));
    final phone = await device();
    expect(await phone.curlKept(strict: true).timeout(const Duration(seconds: 5)), blob);
  });
}
