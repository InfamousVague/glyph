import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ghost_relay/federation.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/p256.dart';
import 'package:ghost_relay/ws_door.dart' show WireBudget;
import 'package:test/test.dart';

import 'fed_support.dart';

/// What a relay hosted from the app asks of the hub (the app's lib/relay_host; docs/OPEN_NETWORK.md, section 5), each an
/// option that does nothing unless it is set, so a relay on a server, gogho.st's, says and does exactly what it did:
///
/// - a pass phrase people must give to use it ([Hub.passKeyOf], [Hub.passProof]), with the wrong ones counted;
/// - a hello that says it runs in someone's app ([Hub.hosted]);
/// - less kept for rooms than a server keeps ([Hub.roomKeepBytes]);
/// - no word believed of whom a connection came through, with nobody in front of it ([Hub.trustsProxy]);
/// - and, on the relay it stays linked to, a word on whether it may stay, which the hosted one shows its keeper
///   ([Federation.viaLink]).

/// A connection's answers as a test reads them: the hello, then whatever came after, and how it was closed.
class _Signing {
  _Signing(this.hub, {this.from = ''}) {
    final (mine, theirs) = MemSocket.pair();
    socket = mine;
    mine.incoming.listen((d) {
      if (d is! String) return;
      final m = jsonDecode(d) as Map;
      if (!hello.isCompleted) {
        hello.complete(m);
      } else {
        said.add(m);
        if (!answer.isCompleted) answer.complete(m);
      }
    });
    hub.attach(theirs, from: from);
  }

  final Hub hub;
  final String from;
  late final MemSocket socket;
  final hello = Completer<Map>();
  final answer = Completer<Map>();
  final said = <Map>[];

  /// Signs in as [who] (v1, as every hub takes without names), with `"pass"` where [pass] is given (hex), or a proof made
  /// from [phrase] for this connection's number and [proofFor]'s name (who's own by default). What the hub answered.
  Future<Map> signIn(Install who, {String? pass, String? phrase, Install? proofFor, bool peek = false}) async {
    final h = await hello.future;
    final nonce = unhex(h['hello'] as String);
    final sig = P256.sign(who.scalar, [...utf8.encode(Hub.greeting), ...nonce], someBytes(32));
    final proof = pass ?? (phrase == null ? null : _hex(Hub.passProof(Hub.passKeyOf(phrase), nonce, (proofFor ?? who).id)));
    socket.add(jsonEncode({'id': who.id, 'key': base64Encode(who.key), 'sig': base64Encode(sig), 'pass': ?proof, if (peek) 'peek': true}));
    return withoutClock(await answer.future.timeout(const Duration(seconds: 5)));
  }
}

String _hex(List<int> b) => [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();

void main() {
  group('with none of it set', () {
    test('the hello and the sign-in are exactly as before: no pass, nothing said of being hosted, 256 MB kept for rooms', () async {
      final hub = Hub();
      final s = _Signing(hub);
      final h = await s.hello.future;
      expect(h.keys.toSet(), {'hello', 'peek', 'react'}, reason: 'a hub with no options says what it always said');
      expect(await s.signIn(Install()), {'ok': true, 'held': 0});
      expect([hub.asksPass, hub.hosted, hub.roomKeepBytes], [false, false, 256 * 1024 * 1024]);
      // A "pass" said to a hub that asks none is passed over, as anything it doesn't know is.
      final t = _Signing(hub);
      expect(await t.signIn(Install(), pass: 'ab' * 32), {'ok': true, 'held': 0});
    });
  });

  group('a pass phrase', () {
    const phrase = 'correct horse battery staple';

    test('the hello says one is asked for; none given is refused and said so, and the connection is closed', () async {
      final hub = Hub(pass: phrase);
      final s = _Signing(hub);
      expect((await s.hello.future)['pass'], true);
      expect(await s.signIn(Install()), {'ok': false, 'err': 'This relay asks for a pass phrase.', 'pass': 'needed'});
      await pumpEventQueue();
      expect([s.socket.isOpen, s.socket.other.code], [false, 4401]);
      expect(hub.connected, 0);
    });

    test('the right one signs in; a wrong one is refused, said as wrong', () async {
      final hub = Hub(pass: phrase);
      expect(await _Signing(hub).signIn(Install(), phrase: phrase), {'ok': true, 'held': 0});
      expect(await _Signing(hub).signIn(Install(), phrase: 'correct horse battery stapler'), {'ok': false, 'err': 'That pass phrase isn\'t this relay\'s.', 'pass': 'wrong'});
      expect(await _Signing(hub).signIn(Install(), pass: 'not hex at all'), containsPair('pass', 'wrong'));
      expect(hub.connected, 1);
    });

    test('a proof is good for its own connection and its own install alone: another connection\'s, or one made for someone else, is wrong', () async {
      final hub = Hub(pass: phrase);
      final maya = Install(), alex = Install();
      // Made for one connection's number, given on another.
      final first = _Signing(hub);
      final nonce = unhex((await first.hello.future)['hello'] as String);
      final proof = _hex(Hub.passProof(Hub.passKeyOf(phrase), nonce, maya.id));
      expect(await first.signIn(maya, pass: proof), {'ok': true, 'held': 0});
      expect(await _Signing(hub).signIn(maya, pass: proof), containsPair('pass', 'wrong'), reason: 'seen once, it is worth nothing again');
      // Made for Maya's name, given by Alex.
      expect(await _Signing(hub).signIn(alex, phrase: phrase, proofFor: maya), containsPair('pass', 'wrong'));
    });

    test('a closed app\'s look needs it too', () async {
      final hub = Hub(pass: phrase);
      expect(await _Signing(hub).signIn(Install(), peek: true), containsPair('pass', 'needed'));
      expect(await _Signing(hub).signIn(Install(), phrase: phrase, peek: true), {'ok': true, 'held': 0, 'peek': true, 'here': false});
    });

    test('wrong ones are counted for each place and for everyone: past either, even the right one waits an hour; none given counts for nothing', () async {
      var t = DateTime.utc(2026, 11, 23, 9);
      final hub = Hub(now: () => t, pass: phrase, passGuessesAnHour: 3, passGuessesAll: 5);
      Future<Map> at(String place, {String? said}) => _Signing(hub, from: place).signIn(Install(), phrase: said);
      // An app not told the phrase yet tries again and again: that is no guess.
      for (var i = 0; i < 10; i++) {
        expect(await at('10.0.0.2'), containsPair('pass', 'needed'));
      }
      expect(await at('10.0.0.2', said: phrase), containsPair('ok', true));
      // Three wrong from one place, and that place is done for the hour, the right phrase too.
      for (var i = 0; i < 3; i++) {
        expect(await at('10.0.0.3', said: 'guess $i'), containsPair('pass', 'wrong'));
      }
      expect(await at('10.0.0.3', said: phrase), {'ok': false, 'err': 'Too many wrong pass phrases lately. Try again in a while.', 'pass': 'busy'});
      // Another place still may, until everyone together has had five wrong.
      expect(await at('10.0.0.4', said: phrase), containsPair('ok', true));
      expect(await at('10.0.0.4', said: 'guess 3'), containsPair('pass', 'wrong'));
      expect(await at('10.0.0.5', said: 'guess 4'), containsPair('pass', 'wrong'));
      expect(await at('10.0.0.6', said: phrase), containsPair('pass', 'busy'), reason: 'five wrong in all this hour: nobody\'s is looked at');
      t = t.add(const Duration(minutes: 61));
      expect(await at('10.0.0.3', said: phrase), containsPair('ok', true), reason: 'an hour on, it may try again');
    });

    test('with nothing in front of it, what a connection says it came through is not believed: one place stays one place', () async {
      // Over real sockets, from this machine: a relay hosted from the app has nobody in front of it, so anyone on its
      // network could name a new place in X-Forwarded-For with each try, and guess as many times as they liked.
      Future<Map> signInOver(int port, String forwarded, String said) async {
        final ws = await WebSocket.connect('ws://127.0.0.1:$port/hub', headers: {'x-forwarded-for': forwarded});
        final answers = StreamIterator(ws);
        await answers.moveNext();
        final nonce = unhex((jsonDecode(answers.current as String) as Map)['hello'] as String);
        final who = Install();
        final sig = P256.sign(who.scalar, [...utf8.encode(Hub.greeting), ...nonce], someBytes(32));
        ws.add(jsonEncode({'id': who.id, 'key': base64Encode(who.key), 'sig': base64Encode(sig), 'pass': _hex(Hub.passProof(Hub.passKeyOf(said), nonce, who.id))}));
        await answers.moveNext();
        final m = jsonDecode(answers.current as String) as Map;
        await ws.close();
        return m;
      }

      for (final trusts in [true, false]) {
        final hub = Hub(pass: phrase, passGuessesAnHour: 1, trustsProxy: trusts, wire: WireBudget());
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen(hub.accept);
        expect(await signInOver(server.port, '203.0.113.1', 'wrong'), containsPair('pass', 'wrong'));
        final second = await signInOver(server.port, '203.0.113.2', phrase);
        expect(second['ok'] == true, trusts, reason: trusts ? 'behind a proxy it is the proxy\'s word: another place' : 'nobody in front: still 127.0.0.1, which has had its one wrong guess');
        await server.close(force: true);
      }
    });

    test('another relay\'s hello is not asked for it: whether relays link is their keepers\' own choice', () async {
      final net = FakeNet();
      final v = TestRelay(net, 'v.test', seed: 1);
      final passHub = Hub(now: net.now, pass: phrase, federation: v.fed);
      net.hubs[v.url] = passHub;
      final r = TestRelay(net, 'r.test', seed: 3, public: false, via: v.url);
      await net.settle();
      expect(r.fed.linkedWith(v.id), isTrue);
      expect((net.made[v.url]!.first.heard.first as Map)['pass'], true, reason: 'the hub it dialled does ask apps for one');
    });

    test('the key is PBKDF2-HMAC-SHA256 over the phrase, salted with the words, 20,000 rounds: the app makes the same', () {
      // RFC 7914's vector for PBKDF2-HMAC-SHA256 holds the arithmetic (P = "passwd", S = "salt", c = 1: its first 32
      // bytes); the app (test/relay_host_test.dart) is held to the same value for this phrase.
      expect(_hex(Hub.pbkdf2Sha256(utf8.encode('passwd'), utf8.encode('salt'), 1)), '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc');
      expect([Hub.passWords, Hub.passRounds], ['ghost-hub pass v1', 20000]);
      expect(_hex(Hub.passKeyOf(phrase)), '52ccc74cd79a05d60949ba3cdec7e131217245002c9eb91c062a3839c0a7ea1f');
      expect(Hub.passKeyOf(phrase), isNot(Hub.passKeyOf('$phrase.')));
    });
  });

  group('a hub hosted from the app', () {
    test('says so in its hello, and only where it is', () async {
      expect((await _Signing(Hub(hosted: true)).hello.future)['hosted'], true);
      expect((await _Signing(Hub()).hello.future).containsKey('hosted'), isFalse);
    });

    test('keeps no more for rooms than it is given, the oldest of the busiest room going first', () async {
      final hub = Hub(roomKeepBytes: 2000);
      final room = 'ab' * 16, token = 'cd' * 32;
      final a = _Signing(hub), b = _Signing(hub);
      final ana = Install(), ben = Install();
      await a.signIn(ana);
      await b.signIn(ben);
      for (final s in [a, b]) {
        s.socket.add(jsonEncode({'join': room, 'token': token}));
      }
      await pumpEventQueue();
      // Five kept packets of 600 bytes: 3,000 in all, past the 2,000 it keeps.
      for (var i = 0; i < 5; i++) {
        a.socket.add(Uint8List.fromList([Hub.toRoomKept, ...unhex(room), ...List.filled(600, i)]));
      }
      await pumpEventQueue();
      expect(hub.keptIn(room), 3, reason: 'each kept frame carries the room and who sent it: three fit in 2,000 bytes');
    });
  });

  group('the link a hosted relay keeps to its public one (viaLink)', () {
    test('a public relay with relays switched off answers no, and the hosted one says why and when it tries again', () async {
      final net = FakeNet();
      // gogho.st today: a hub with no federation at all.
      net.hubs['wss://v.test/hub'] = Hub(now: net.now);
      final r = TestRelay(net, 'r.test', seed: 3, public: false, via: 'wss://v.test/hub');
      expect(r.fed.viaLink, (linked: false, stays: false, why: null, next: null), reason: 'not dialled yet');
      await net.settle();
      final link = r.fed.viaLink!;
      expect([link.linked, link.stays, link.why], [false, false, 'not a relay that talks to others']);
      expect(link.next, net.clock.add(const Duration(seconds: 5)));
      // Nothing answers there at all: down.
      net.hubs.remove('wss://v.test/hub');
      await net.pass(const Duration(seconds: 6));
      expect(r.fed.viaLink!.why, 'down');
      // A relay with no via has nothing to say.
      expect(TestRelay(net, 'p.test', seed: 4).fed.viaLink, isNull);
    });

    test('linked, it says whether the public relay lets it stay: told so only where it does', () async {
      final net = FakeNet();
      final v = TestRelay(net, 'v.test', seed: 1);
      final r = TestRelay(net, 'r.test', seed: 3, public: false, via: v.url);
      await net.settle();
      expect(r.fed.viaLink, (linked: true, stays: false, why: null, next: null), reason: 'v talks to other relays, and keeps no standing links');
      final w = TestRelay(net, 'w.test', seed: 5, standingOpen: true);
      final s = TestRelay(net, 's.test', seed: 6, public: false, via: w.url);
      await net.settle();
      expect(s.fed.viaLink, (linked: true, stays: true, why: null, next: null));
      // What w answered: the yes, with "stay"; v's said nothing of it.
      final answers = [for (final url in [v.url, w.url]) net.made[url]!.first.heard.whereType<Map>().firstWhere((m) => m['ok'] == true)];
      expect([answers[0].containsKey('stay'), answers[1]['stay']], [false, true]);
    });
  });
}
