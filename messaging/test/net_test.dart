import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/net/packet.dart';
import 'package:ghost_messaging/net/sms_carrier.dart';
import 'package:ghost_messaging/net/switchboard.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/p256.dart';
import 'package:ghost_relay/relay.dart';

/// The app's routes (lib/net): the cryptography, a packet in pieces, the switchboard's choosing, and two installs
/// talking through the real hub (relay/lib/hub.dart) on this machine.

/// A route made of nothing: what one end sends, the other end's twin is handed. It can be told to lose things, to
/// keep them, to be down, and it counts what it carried.
class FakeCarrier implements Carrier {
  FakeCarrier(this.id, {this.traits = const CarrierTraits(maxPacket: 4096, ackWait: Duration(milliseconds: 200)), bool up = true})
      : state = ValueNotifier(up ? CarrierState.up : CarrierState.down);
  @override
  final String id;
  @override
  String get name => id;
  @override
  String get about => '';
  @override
  final CarrierTraits traits;
  @override
  final ValueNotifier<CarrierState> state;
  @override
  String? problem;
  FakeCarrier? twin;
  bool lose = false;
  bool hold = false;
  bool fail = false;
  bool Function(Peer)? reach;
  final carried = <Uint8List>[];
  final _arrived = StreamController<Arrived>.broadcast();
  @override
  Stream<Arrived> get arrived => _arrived.stream;
  @override
  Future<void> start() async => state.value = CarrierState.up;
  @override
  Future<void> stop() async => state.value = CarrierState.off;
  @override
  bool reaches(Peer peer) => reach?.call(peer) ?? true;
  @override
  Future<Handed> send(Peer peer, Uint8List packet) async {
    if (fail) throw CarrierError('it broke');
    carried.add(packet);
    if (hold) return Handed.held;
    if (!lose) twin?._arrived.add(Arrived(id, packet, address: 'the-other-number'));
    return Handed.passed;
  }

  static (FakeCarrier, FakeCarrier) pair(String id, {CarrierTraits traits = const CarrierTraits(maxPacket: 4096, ackWait: Duration(milliseconds: 200))}) {
    final a = FakeCarrier(id, traits: traits), b = FakeCarrier(id, traits: traits);
    a.twin = b;
    b.twin = a;
    return (a, b);
  }
}

class Book implements PeerBook {
  final Map<String, Peer> all = {};
  @override
  Peer? byId(String id) => all[id];
  @override
  Peer? byAddress(String address) => all.values.where((p) => p.address == address).firstOrNull;
}

/// Two installs that have exchanged keys, each with a switchboard over the routes given.
class Two {
  Two(List<(FakeCarrier, FakeCarrier)> routes) {
    final key = NetCrypto.netKey(NetCrypto.conversationKey(a, b.public)!);
    expect(NetCrypto.netKey(NetCrypto.conversationKey(b, a.public)!), key, reason: 'both arrive at one key');
    toB = Peer(id: b.id, key: key, address: '+15550000002', name: 'B');
    toA = Peer(id: a.id, key: key, address: '+15550000001', name: 'A');
    final bookA = Book()..all[b.id] = toB, bookB = Book()..all[a.id] = toA;
    left = Switchboard(me: a.id, peers: bookA, carriers: [for (final r in routes) r.$1]);
    right = Switchboard(me: b.id, peers: bookB, carriers: [for (final r in routes) r.$2]);
    right.received.listen(got.add);
  }
  final a = NetKeys.generate(), b = NetKeys.generate();
  late final Peer toA, toB;
  late final Switchboard left, right;
  final got = <Received>[];
}

Future<void> _tick([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('cryptography', () {
    test('a fixed pair of keys makes the key the phone\'s Kotlin makes (NetCryptoTest.kt holds the same bytes)', () {
      final a = NetKeys.fromScalar(List.generate(32, (i) => i + 1));
      final b = NetKeys.fromScalar(List.generate(32, (i) => 0xa0 + i));
      expect(NetCrypto.hex(a.public), '02515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f');
      expect(NetCrypto.hex(b.public), '020d0918a04198474605615b6df90fdcb34791fb3ecb822f4b26eb6e4fc4511b9d');
      expect(a.id, 'd284f0626fd0836ce4b1731793fa6905');
      final conversation = NetCrypto.conversationKey(a, b.public)!;
      expect(NetCrypto.hex(conversation), 'c6e3cd9e9784467bdff6aafce3d2c1864597a24c4cf9f78e0634b9b6aa8fa5d4');
      expect(NetCrypto.conversationKey(b, a.public), conversation, reason: 'both arrive at one key');
      expect(NetCrypto.hex(NetCrypto.netKey(conversation)), 'd150804ceef8aff0a7bf0a5c383fa178430f5d7bc5e81f8f79851bf26d283c57');
    });

    test('sealed is opened by the same key and by no other, and not once changed', () {
      final key = NetCrypto.randomBytes(32);
      final sealed = NetCrypto.seal(key, utf8.encode('see you at 7'));
      expect(utf8.decode(NetCrypto.open(key, sealed)!), 'see you at 7');
      expect(NetCrypto.open(NetCrypto.randomBytes(32), sealed), isNull);
      expect(NetCrypto.open(key, Uint8List.fromList(sealed)..[20] ^= 1), isNull);
      expect(NetCrypto.open(key, sealed.sublist(0, 20)), isNull);
      expect(NetCrypto.seal(key, utf8.encode('see you at 7')), isNot(sealed), reason: 'sealed twice, it is not the same bytes twice');
    });

    test('a signature made here is taken by the hub\'s own check, and the other way', () {
      final keys = NetKeys.generate();
      final message = utf8.encode('${Hub.greeting}abc');
      final sig = NetCrypto.sign(keys, message);
      expect(NetCrypto.verify(keys.public, message, sig), isTrue);
      expect(P256.verify(keys.public, message, sig), isTrue, reason: 'the hub checks with its own arithmetic');
      expect(P256.verify(keys.public, utf8.encode('other words'), sig), isFalse);
      final theirs = P256.sign(keys.scalar, message, NetCrypto.randomBytes(32));
      expect(NetCrypto.verify(keys.public, message, theirs), isTrue);
      expect(hexOfList(P256.publicOf(keys.scalar)), NetCrypto.hex(keys.public));
      expect(Hub.nameOf(keys.public), keys.id);
    });
  });

  group('a packet', () {
    test('an envelope goes into bytes and comes back', () {
      final e = Envelope(kind: 'call', body: {'o': 'ring', 'c': 'ab12'}, ack: false);
      final back = Envelope.decode(e.encode())!;
      expect([back.id, back.kind, back.body, back.at, back.ack], [e.id, 'call', {'o': 'ring', 'c': 'ab12'}, e.at, false]);
      expect(Envelope.decode(utf8.encode('not json')), isNull);
    });

    test('a ringing call, sealed, fits one data text', () {
      final from = NetKeys.generate().id;
      // A call's ring: the envelope's own name is the call's.
      final e = Envelope(kind: 'call', body: {'o': 'ring', 'm': 'a'});
      final packet = Packet.wrap(from: from, sealed: true, payload: NetCrypto.seal(NetCrypto.randomBytes(32), e.encode()));
      expect(packet.length, lessThanOrEqualTo(SmsCarrier.perText), reason: '${packet.length} bytes');
    });

    test('one too long for a route crosses in pieces, in any order, and is whole again', () {
      final from = NetKeys.generate().id;
      final payload = NetCrypto.randomBytes(500);
      final packet = Packet.wrap(from: from, sealed: true, payload: payload);
      final pieces = Packet.split(packet, 133, maxParts: 6)!;
      expect(pieces.length, 5);
      expect(pieces.every((p) => p.length <= 133), isTrue);
      final joiner = PartJoiner();
      Packet? whole;
      for (final p in pieces.reversed) {
        expect(whole, isNull);
        whole = joiner.add(Packet.parse(p)!);
      }
      expect(whole!.payload, payload);
      expect([whole.from, whole.sealed, whole.isPart], [from, true, false]);
      expect(Packet.split(packet, 133, maxParts: 4), isNull, reason: 'more pieces than the route will carry');
      expect(Packet.split(Packet.wrap(from: from, sealed: false, payload: [1, 2, 3]), 133)!.single.length, 20);
    });

    test('pieces of a packet that never finishes are forgotten', () {
      var now = DateTime(2026, 11, 14, 12);
      final joiner = PartJoiner(now: () => now, maxOpen: 2);
      final from = NetKeys.generate().id;
      final pieces = Packet.split(Packet.wrap(from: from, sealed: true, payload: NetCrypto.randomBytes(300)), 133)!;
      expect(joiner.add(Packet.parse(pieces[0])!), isNull);
      now = now.add(const Duration(minutes: 11));
      for (final p in pieces.skip(1)) {
        expect(joiner.add(Packet.parse(p)!), isNull, reason: 'its first piece was dropped ten minutes on');
      }
    });
  });

  group('the switchboard', () {
    test('sends by the first route in the person\'s order, sealed, and is told it arrived', () async {
      final lan = FakeCarrier.pair('lan'), hub = FakeCarrier.pair('hub');
      final two = Two([hub, lan]);
      final d = await two.left.send(two.toB, Envelope(kind: 'text', body: {'t': 'hello'}));
      expect([d.via, d.acked], ['lan', true]);
      expect(two.got.single.envelope.body['t'], 'hello');
      expect(two.got.single.via, 'lan');
      expect(hub.$1.carried, isEmpty);
      expect(utf8.decode(lan.$1.carried.single, allowMalformed: true).contains('hello'), isFalse, reason: 'what the route carried is sealed');
      two.left.order = ['hub', 'lan'];
      expect((await two.left.send(two.toB, Envelope(kind: 'text'))).via, 'hub');
    });

    test('with no answer on one route the next is tried, and the other end passes it on once', () async {
      final lan = FakeCarrier.pair('lan'), hub = FakeCarrier.pair('hub');
      final two = Two([lan, hub]);
      // The local network takes it and the answer is lost on the way back: sent again through the hub.
      lan.$2.lose = true;
      final d = await two.left.send(two.toB, Envelope(kind: 'text', body: {'t': 'once'}));
      expect([d.via, d.acked], ['hub', true]);
      expect(d.tried, ['lan', 'hub']);
      await _tick();
      expect(two.got.length, 1, reason: 'it came twice and was passed on once');
    });

    test('a route that is off, down, broken or cannot reach them is passed over', () async {
      final lan = FakeCarrier.pair('lan'), p2p = FakeCarrier.pair('p2p'), hub = FakeCarrier.pair('hub');
      final two = Two([lan, p2p, hub]);
      await two.left.setOn('lan', false);
      p2p.$1.fail = true;
      var d = await two.left.send(two.toB, Envelope(kind: 'text'));
      expect(d.via, 'hub');
      expect(d.tried, ['p2p: it broke', 'hub']);
      await two.left.setOn('lan', true);
      lan.$1.reach = (_) => false;
      p2p.$1.state.value = CarrierState.down;
      d = await two.left.send(two.toB, Envelope(kind: 'text'));
      expect(d.via, 'hub');
      hub.$1.state.value = CarrierState.down;
      d = await two.left.send(two.toB, Envelope(kind: 'text'));
      expect(d.sent, isFalse);
      expect(d.tried.single, 'no route reaches them now');
    });

    test('a route that costs money carries only what may cost money', () async {
      const text = CarrierTraits(maxPacket: 133, maxParts: 6, metered: true, live: false, wakes: true);
      final sms = FakeCarrier.pair('sms', traits: text);
      final two = Two([sms]);
      expect((await two.left.send(two.toB, Envelope(kind: 'typing', ack: false))).sent, isFalse);
      final d = await two.left.send(two.toB, Envelope(kind: 'text', body: {'t': 'x' * 200}), metered: true);
      expect([d.via, d.acked], ['sms', false]);
      expect(sms.$1.carried.length, greaterThan(1), reason: 'too long for one text, it went in pieces');
      await _tick();
      expect(two.got.single.envelope.body['t'], 'x' * 200);
      // No answer goes back by a route that costs money.
      expect(sms.$2.carried, isEmpty);
    });

    test('kept for someone who is away is enough, unless it is urgent: then the route that wakes them is tried too', () async {
      const text = CarrierTraits(maxPacket: 133, maxParts: 6, metered: true, live: false, wakes: true);
      final hub = FakeCarrier.pair('hub'), sms = FakeCarrier.pair('sms', traits: text);
      final two = Two([hub, sms]);
      hub.$1.hold = true;
      var d = await two.left.send(two.toB, Envelope(kind: 'text'), metered: true);
      expect([d.via, d.handed], ['hub', Handed.held]);
      expect(sms.$1.carried, isEmpty);
      d = await two.left.send(two.toB, Envelope(kind: 'call', body: {'o': 'ring'}), metered: true, urgent: true);
      expect(d.tried, ['hub', 'sms']);
      await _tick();
      expect(two.got.single.envelope.kind, 'call');
      expect(two.got.single.via, 'sms');
    });

    test('nothing unsealed is taken from someone a key is held for, and nothing at all from a stranger but a greeting', () async {
      final hub = FakeCarrier.pair('hub');
      final two = Two([hub]);
      final strangers = <String>[];
      two.right.strangers.listen((s) => strangers.add('${s.envelope.kind} from ${s.from.substring(0, 4)} at ${s.address}'));
      // In the clear, from the name a key is held for: dropped.
      hub.$2._arrived.add(Arrived('hub', Packet.wrap(from: two.a.id, sealed: false, payload: Envelope(kind: 'text', body: {'t': 'forged'}).encode())));
      // From a name nobody knows: a greeting is shown to the app, anything else is not.
      final who = NetKeys.generate();
      hub.$2._arrived.add(Arrived('hub', Packet.wrap(from: who.id, sealed: false, payload: Envelope(kind: 'text').encode())));
      hub.$2._arrived.add(Arrived('hub', Packet.wrap(from: who.id, sealed: false, payload: Envelope(kind: 'hello', body: {'k': base64Encode(who.public)}).encode()), address: '+15559990000'));
      // Sealed under some other key.
      hub.$2._arrived.add(Arrived('hub', Packet.wrap(from: two.a.id, sealed: true, payload: NetCrypto.seal(NetCrypto.randomBytes(32), Envelope(kind: 'text').encode()))));
      await _tick();
      expect(two.got, isEmpty);
      expect(strangers, ['hello from ${who.id.substring(0, 4)} at +15559990000']);
      // And to send sealed with no key held is refused, not sent in the clear.
      final d = await two.left.send(Peer(id: who.id), Envelope(kind: 'text'));
      expect(d.sent, isFalse);
    });

    test('a route is taken out and another put in its place', () async {
      final hub = FakeCarrier.pair('hub');
      final two = Two([hub]);
      expect((await two.left.send(two.toB, Envelope(kind: 'text'))).via, 'hub');
      // The peer-to-peer route this is all made to make room for: same name of thing, different way.
      final p2p = FakeCarrier.pair('p2p');
      two.left.add(p2p.$1);
      two.right.add(p2p.$2);
      two.left.remove('hub');
      expect(two.left.carriers.map((c) => c.id), ['p2p']);
      final d = await two.left.send(two.toB, Envelope(kind: 'text', body: {'t': 'no server'}));
      expect([d.via, d.acked], ['p2p', true]);
      expect(two.got.last.via, 'p2p');
    });
  });

  group('through the real hub', () {
    late Relay relay;
    late String url;
    setUp(() async {
      relay = Relay(hub: Hub());
      url = 'ws://127.0.0.1:${await relay.start(port: 0)}/hub';
    });
    tearDown(() => relay.stop());

    Future<void> up(HubCarrier c) async {
      await c.start();
      for (var i = 0; i < 200 && c.state.value != CarrierState.up; i++) {
        await _tick(10);
      }
      expect(c.state.value, CarrierState.up, reason: c.problem);
    }

    test('two installs find each other by name, and what one sends the other gets, sealed all the way', () async {
          final a = NetKeys.generate(), b = NetKeys.generate();
          final key = NetCrypto.netKey(NetCrypto.conversationKey(a, b.public)!);
          final hubA = HubCarrier(url: url, signer: KeysSigner(a)), hubB = HubCarrier(url: url, signer: KeysSigner(b));
          final left = Switchboard(me: a.id, peers: Book()..all[b.id] = Peer(id: b.id, key: key), carriers: [hubA]);
          final right = Switchboard(me: b.id, peers: Book()..all[a.id] = Peer(id: a.id, key: key), carriers: [hubB]);
          final got = <Received>[];
          right.received.listen(got.add);
          await up(hubA);
          // B is away: kept for them, and handed over when they come.
          hubA.watch([b.id]);
          var d = await left.send(Peer(id: b.id, key: key), Envelope(kind: 'text', body: {'t': 'are you there'}));
          expect([d.via, d.handed, d.acked], ['hub', Handed.held, false]);
          expect(relay.hub!.heldFor(b.id), 1);
          final acked = left.acked.first;
          await up(hubB);
          await acked.timeout(const Duration(seconds: 3));
          expect(got.single.envelope.body['t'], 'are you there');
          expect(relay.hub!.heldFor(b.id), 0);
          await _tick(50);
          expect(hubA.here.value, {b.id}, reason: 'A asked to be told when B came');
          // Both there: passed and answered at once.
          d = await left.send(Peer(id: b.id, key: key), Envelope(kind: 'text', body: {'t': 'good'}));
          expect([d.handed, d.acked], [Handed.passed, true]);
          expect(got.last.envelope.body['t'], 'good');
          await hubB.stop();
          await _tick(50);
          expect(hubA.here.value, isEmpty);
          await hubA.stop();
        });

    test('a name is only its key holder\'s to connect under', () async {
          final real = NetKeys.generate(), thief = NetKeys.generate();
          final c = HubCarrier(url: url, signer: _Impostor(real, thief), retry: const Duration(hours: 1));
          await c.start();
          for (var i = 0; i < 100 && c.state.value != CarrierState.down; i++) {
            await _tick(10);
          }
          expect(c.state.value, CarrierState.down);
          expect(c.problem, contains('refused'));
          expect(relay.hub!.connected, 0);
          await c.stop();
        });

    test('a room is joined and left at any time by whoever holds its token, and each is told of the others', () async {
          final keys = [for (var i = 0; i < 3; i++) NetKeys.generate()];
          final hubs = [for (final k in keys) HubCarrier(url: url, signer: KeysSigner(k))];
          for (final h in hubs) {
            await up(h);
          }
          final roomKey = NetCrypto.randomBytes(32);
          final room = NetCrypto.hex(NetCrypto.derive(roomKey, 'room name').sublist(0, 16));
          final token = NetCrypto.hex(NetCrypto.derive(roomKey, 'room token'));
          final events = <String>[];
          hubs[0].roomEvents.listen((e) => events.add(e.came != null ? 'came ${keys.indexWhere((k) => k.id == e.came)}' : e.went != null ? 'went ${keys.indexWhere((k) => k.id == e.went)}' : 'in with ${e.members!.length}'));
          final heard = <String>[];
          hubs[0].roomPackets.listen((p) => heard.add('${keys.indexWhere((k) => k.id == p.from)}: ${utf8.decode(p.bytes)}'));
          expect(await hubs[0].join(room, token), isEmpty);
          expect(await hubs[1].join(room, token), [keys[0].id]);
          expect((await hubs[2].join(room, token)).toSet(), {keys[0].id, keys[1].id});
          hubs[1].sendRoom(room, Uint8List.fromList(utf8.encode('hello room')));
          hubs[1].leave(room);
          await _tick(80);
          expect(events, ['in with 0', 'came 1', 'came 2', 'went 1']);
          expect(heard, ['1: hello room']);
          // A wrong token is refused; someone not in the room is not heard in it.
          final outsider = HubCarrier(url: url, signer: KeysSigner(NetKeys.generate()));
          await up(outsider);
          await expectLater(outsider.join(room, 'f' * 64), throwsA(isA<CarrierError>()));
          expect(() => outsider.sendRoom(room, Uint8List(3)), throwsA(isA<CarrierError>()));
          // A connection that drops leaves its rooms.
          await hubs[2].stop();
          await _tick(80);
          expect(events.last, 'went 2');
          expect(relay.hub!.rooms, 1);
          hubs[0].leave(room);
          await _tick(80);
          expect(relay.hub!.rooms, 0, reason: 'a room nobody is in is forgotten');
          for (final h in [hubs[0], hubs[1], outsider]) {
            await h.stop();
          }
        });
  });
}

String hexOfList(List<int> bytes) => NetCrypto.hex(bytes);

/// Says it is one install and signs as another.
class _Impostor implements NetSigner {
  _Impostor(this.claimed, this.actual);
  final NetKeys claimed, actual;
  @override
  String get id => claimed.id;
  @override
  Uint8List get publicKey => claimed.public;
  @override
  Future<Uint8List> sign(List<int> message) async => NetCrypto.sign(actual, message);
}
