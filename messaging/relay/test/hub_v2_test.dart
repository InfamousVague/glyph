import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/p256.dart';
import 'package:test/test.dart';

import 'fed_support.dart';

/// A sign-in bound to the relay (relay/lib/hub.dart `greetingV2`; found in the review of relays that talk,
/// 2026-11-23). A v1 signature is the greeting and the hub's number, and says nothing of where it was made: a relay an
/// app was pointed at, or asked a name of, could pass along the number of the app's own relay and sign in there as the
/// app with what it was given. A v2 signature names the host the app dialled, and a relay takes it only for a host it
/// is reached at; and from a key it has seen sign in with v2 it takes no v1 again.
void main() {
  /// Signs in to [hub] over memory as [scalar]'s key: v2 for [host] where given (and asked for by the hub's hello, or
  /// [anyway]), else v1. What the hub said back, and its hello.
  Future<({Map hello, Map answer, MemSocket socket})> signIn(Hub hub, List<int> scalar, {String? host, bool peek = false, List<int>? nonceFrom}) async {
    final (mine, theirs) = MemSocket.pair();
    final heard = <Map>[];
    final second = Completer<void>();
    mine.incoming.listen((d) {
      if (d is! String) return;
      heard.add(jsonDecode(d) as Map);
      if (heard.length == 2 && !second.isCompleted) second.complete();
    }, onDone: () {
      if (!second.isCompleted) second.complete();
    });
    hub.attach(theirs);
    await pumpEventQueue();
    final hello = heard.first;
    final nonce = nonceFrom ?? unhex(hello['hello'] as String);
    final key = P256.publicOf(scalar);
    final sig = P256.sign(scalar, host == null ? [...utf8.encode(Hub.greeting), ...nonce] : Hub.signedV2(host, nonce), someBytes(32));
    mine.add(jsonEncode({'id': Hub.nameOf(key), 'key': base64Encode(key), 'sig': base64Encode(sig), if (host != null) 'v': 2, 'host': ?host, if (peek) 'peek': true}));
    await second.future.timeout(const Duration(seconds: 5));
    return (hello: hello, answer: heard.length > 1 ? heard[1] : {'closed': true}, socket: mine);
  }

  test('a hub that knows the names it is reached at says it takes v2; one that doesn\'t says what it always said', () async {
    final plain = await signIn(Hub(), someBytes(32));
    expect(plain.hello.keys, ['hello', 'peek', 'react']);
    expect(plain.answer, {'ok': true, 'held': 0});
    final named = Hub(names: ['Gogho.st', 'www.gogho.st:443', 'ghost-sms.com', '10.0.0.5:8787']);
    expect(named.names, {'gogho.st', 'www.gogho.st', 'ghost-sms.com', '10.0.0.5:8787'});
    final v2 = await signIn(named, someBytes(32), host: 'gogho.st');
    expect(v2.hello['v2'], isTrue);
    expect(v2.answer, {'ok': true, 'held': 0});
  });

  test('a v2 signature is taken only for a host the hub is reached at, and only for the host it was made for', () async {
    final hub = Hub(names: ['gogho.st', 'ghost-sms.com']);
    final me = someBytes(32);
    expect((await signIn(hub, me, host: 'ghost-sms.com')).answer, {'ok': true, 'held': 0});
    expect((await signIn(hub, someBytes(32), host: 'evil.test')).answer, {'ok': false, 'err': 'This relay isn\'t reached as evil.test.'});
    // Made for one host, said with another.
    final (mine, theirs) = MemSocket.pair();
    final heard = <Map>[];
    mine.incoming.listen((d) => heard.add(jsonDecode(d as String) as Map));
    hub.attach(theirs);
    await pumpEventQueue();
    final key = P256.publicOf(me);
    final sig = P256.sign(me, Hub.signedV2('evil.test', unhex(heard.first['hello'] as String)), someBytes(32));
    mine.add(jsonEncode({'id': Hub.nameOf(key), 'key': base64Encode(key), 'sig': base64Encode(sig), 'v': 2, 'host': 'gogho.st'}));
    await pumpEventQueue();
    expect(heard.last, {'ok': false, 'err': 'bad hello'});
  });

  test('from a key that has signed in with v2, v1 is refused (a look too); a key that never has signs in with v1 as before', () async {
    final hub = Hub(names: ['gogho.st']);
    final upgraded = someBytes(32), old = someBytes(32);
    expect((await signIn(hub, old)).answer, {'ok': true, 'held': 0}, reason: 'an app from before, on a hub that takes v2');
    expect((await signIn(hub, upgraded, host: 'gogho.st')).answer['ok'], isTrue);
    expect(hub.signsV2(Hub.nameOf(P256.publicOf(upgraded))), isTrue);
    final refused = {'ok': false, 'err': 'This account signs in a newer way now: update Ghost Messaging on this device.'};
    expect((await signIn(hub, upgraded)).answer, refused);
    expect((await signIn(hub, upgraded, peek: true)).answer, refused);
    expect((await signIn(hub, old)).answer, {'ok': true, 'held': 0});
  });

  test('the number of the app\'s own relay passed on through another relay is worth nothing there, whichever way the app is asked to sign', () async {
    // The app's own relay, which takes v2 and has seen the account sign in with it.
    final home = Hub(names: ['gogho.st']);
    final victim = someBytes(32);
    expect((await signIn(home, victim, host: 'gogho.st')).answer['ok'], isTrue);
    // evil.test dials the app's relay, and hands the app its number as though it were its own.
    final (eve, evesEnd) = MemSocket.pair();
    final atHome = <Map>[];
    eve.incoming.listen((d) => atHome.add(jsonDecode(d as String) as Map));
    home.attach(evesEnd);
    await pumpEventQueue();
    final number = unhex(atHome.first['hello'] as String);
    final key = P256.publicOf(victim);
    // Saying v2: the app signs v2 for the host it dialled, evil.test.
    final forEvil = P256.sign(victim, Hub.signedV2('evil.test', number), someBytes(32));
    eve.add(jsonEncode({'id': Hub.nameOf(key), 'key': base64Encode(key), 'sig': base64Encode(forEvil), 'v': 2, 'host': 'evil.test'}));
    await pumpEventQueue();
    expect(atHome.last['ok'], isFalse);
    // Pretending to be from before: the app signs v1, which the relay takes from this key no more.
    final (eve2, evesEnd2) = MemSocket.pair();
    final again = <Map>[];
    eve2.incoming.listen((d) => again.add(jsonDecode(d as String) as Map));
    home.attach(evesEnd2);
    await pumpEventQueue();
    final v1 = P256.sign(victim, [...utf8.encode(Hub.greeting), ...unhex(again.first['hello'] as String)], someBytes(32));
    eve2.add(jsonEncode({'id': Hub.nameOf(key), 'key': base64Encode(key), 'sig': base64Encode(v1)}));
    await pumpEventQueue();
    expect(again.last['ok'], isFalse);
    expect(home.connected, 1, reason: 'the app\'s own connection, and evil.test signed in as nobody');
  });

  test('the keys that signed in with v2 are kept across restarts', () async {
    final dir = Directory.systemTemp.createTempSync('ghost-hub-v2-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final upgraded = someBytes(32);
    final first = Hub(names: ['gogho.st'], dataDir: dir)..start();
    expect((await signIn(first, upgraded, host: 'gogho.st')).answer['ok'], isTrue);
    first.stop();
    expect((jsonDecode(File('${dir.path}/hub-v2.json').readAsStringSync()) as Map)['ids'], [Hub.nameOf(P256.publicOf(upgraded))]);
    final second = Hub(names: ['gogho.st'], dataDir: dir)..start();
    expect((await signIn(second, upgraded)).answer['ok'], isFalse);
    second.stop();
    expect(Hub.maxSignsV2, 200000);
  });
}
