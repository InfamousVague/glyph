import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/forward_secrecy.dart';
import 'package:ghost_messaging/net/packet.dart';
import 'package:ghost_messaging/net/switchboard.dart';

/// Forward secrecy between friends and between an account's own devices (GMFB-26, lib/net/forward_secrecy.dart,
/// docs/FORWARD_SECRECY.md): the sealing on its own, then switchboards talking over a stand-in for the relay's hub that
/// hands a packet for an id to every device of it that is connected, or keeps it for the first to come.

String _device() => NetCrypto.hex(NetCrypto.randomBytes(16));

/// A clock a test moves on by hand.
class Clock {
  DateTime t = DateTime(2026, 11, 22, 12);
  DateTime now() => t;
  void pass(Duration d) => t = t.add(d);
}

/// One device's forward secrecy with its own stores, as the app keeps them.
class Dev {
  Dev(this.clock, {String? device, MemoryFsStore? secrets}) : device = device ?? _device(), secrets = secrets ?? MemoryFsStore();
  final Clock clock;
  final String device;
  final MemoryFsStore secrets;
  final plain = MemoryFsStore();
  late ForwardSecrecy fs = ForwardSecrecy(device: device, secrets: secrets, plain: plain, now: clock.now);

  /// The app started again: a new ForwardSecrecy reading the same stores.
  Future<ForwardSecrecy> restart() async {
    await fs.flush();
    fs = ForwardSecrecy(device: device, secrets: secrets, plain: plain, now: clock.now);
    await fs.load();
    return fs;
  }
}

/// A secret store that can be made to fail, as an iPhone's Keychain does before its first unlock.
class FlakyStore extends MemoryFsStore {
  bool failReads = false, failWrites = false;
  @override
  Future<String?> read(String name) async {
    if (failReads) throw StateError('locked');
    return super.read(name);
  }

  @override
  Future<void> write(String name, String value) async {
    if (failWrites) throw StateError('locked');
    return super.write(name, value);
  }
}

/// The relay's hub, as far as this needs: a packet for an id goes to every connected device of that id but the one
/// that sent it, or is held for whichever device of it connects first (relay/lib/hub.dart).
class Bus {
  final Map<String, List<BusCarrier>> here = {};
  final Map<String, List<(String, Uint8List)>> held = {};

  /// Every packet carried, by who sent it, for a test to look at or play again.
  final List<Uint8List> carried = [];
}

class BusCarrier implements Carrier {
  BusCarrier(this.bus, this.owner, {this.id = 'hub', this.traits = const CarrierTraits(maxPacket: 64 * 1024, ackWait: Duration(milliseconds: 150))});
  final Bus bus;
  final String owner;
  @override
  final String id;
  @override
  String get name => id;
  @override
  String get about => '';
  @override
  final CarrierTraits traits;
  @override
  final ValueNotifier<CarrierState> state = ValueNotifier(CarrierState.off);
  @override
  String? problem;
  final _arrived = StreamController<Arrived>.broadcast();
  @override
  Stream<Arrived> get arrived => _arrived.stream;

  /// Whatever is sent is dropped while this is set (a packet lost on the way).
  bool lose = false;

  void take(Uint8List packet) => _arrived.add(Arrived(id, packet));

  @override
  Future<void> start() async {
    state.value = CarrierState.up;
    final list = bus.here[owner] ??= [];
    if (!list.contains(this)) list.add(this);
    for (final h in bus.held.remove(owner) ?? const <(String, Uint8List)>[]) {
      take(h.$2);
    }
  }

  @override
  Future<void> stop() async {
    state.value = CarrierState.off;
    bus.here[owner]?.remove(this);
  }

  @override
  bool reaches(Peer peer) => true;

  @override
  Future<Handed> send(Peer peer, Uint8List packet) async {
    bus.carried.add(packet);
    if (lose) return Handed.passed;
    final there = [for (final c in bus.here[peer.id] ?? const <BusCarrier>[]) if (!identical(c, this)) c];
    if (there.isEmpty) {
      (bus.held[peer.id] ??= []).add((owner, packet));
      return Handed.held;
    }
    for (final c in there) {
      scheduleMicrotask(() => c.take(packet));
    }
    return Handed.passed;
  }
}

class Book implements PeerBook {
  final Map<String, Peer> all = {};
  @override
  Peer? byId(String id) => all[id];
  @override
  Peer? byAddress(String address) => all.values.where((p) => p.address == address).firstOrNull;
}

/// An account: one identity, the words' key its devices seal copies to each other with, and its devices.
class Account {
  Account(this.name);
  final String name;
  final keys = NetKeys.generate();
  final mineKey = NetCrypto.randomBytes(32);
  String get id => keys.id;
}

/// One device of an account on the bus: its switchboard, its forward secrecy (or none: a build from before), and
/// what reached it.
class Phone {
  Phone(this.account, this.bus, this.clock, {bool fs = true, List<Carrier> extra = const [], MemoryFsStore? secrets}) : dev = Dev(clock, secrets: secrets) {
    hub = BusCarrier(bus, account.id);
    book.all[account.id] = Peer(id: account.id, key: account.mineKey);
    _fs = fs;
    _extra = extra;
  }
  final Account account;
  final Bus bus;
  final Clock clock;
  final Dev dev;
  late final BusCarrier hub;
  final book = Book();
  late final bool _fs;
  late final List<Carrier> _extra;
  late Switchboard board;
  final got = <Received>[];

  Future<Phone> up() async {
    if (_fs) await dev.fs.tryLoad();
    board = Switchboard(me: account.id, peers: book, carriers: [hub, ..._extra], now: clock.now, fs: _fs ? dev.fs : null);
    board.received.listen(got.add);
    await board.start();
    return this;
  }

  /// Knows [other] as a friend: the pair's key from the two identities.
  void befriend(Account other) => book.all[other.id] = Peer(id: other.id, key: NetCrypto.netKey(NetCrypto.conversationKey(account.keys, other.keys.public)!), name: other.name);

  Peer peerOf(Account other) => book.all[other.id]!;
  Peer get mine => book.all[account.id]!;

  Future<Delivery> say(Account to, String words, {String? id}) => board.send(peerOf(to), Envelope(id: id, kind: 'text', body: {'t': words}));

  List<String> get words => [for (final r in got) if (r.envelope.kind == 'text') r.envelope.body['t'] as String];

  /// Starts again, as after the app was closed: a new switchboard, its forward secrecy read from what was kept.
  Future<void> restart() async {
    await board.dispose();
    got.clear();
    if (_fs) await dev.restart();
    board = Switchboard(me: account.id, peers: book, carriers: [hub, ..._extra], now: clock.now, fs: _fs ? dev.fs : null);
    board.received.listen(got.add);
  }
}

bool _isFs(Uint8List packet) => Packet.parse(packet)!.fs;

Future<void> _tick([int ms = 40]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  // Sealing and opening off the screens' isolate is held to in one test below; the rest run inline, for speed.
  ForwardSecrecy.offThread = false;

  group('the sealing', () {
    late Clock clock;
    late Dev a, b1, b2;
    final from = _device(), to = _device();
    late Uint8List pairKey;

    setUp(() async {
      clock = Clock();
      a = Dev(clock);
      b1 = Dev(clock);
      b2 = Dev(clock);
      for (final d in [a, b1, b2]) {
        await d.fs.load();
      }
      pairKey = NetCrypto.randomBytes(32);
    });

    Uint8List sealFor(List<Dev> devices, String words) => ForwardSecrecy.seal(from: from, to: to, pairKey: pairKey, clear: utf8.encode(words), targets: [for (final d in devices) d.fs.bundle!]);

    test('what is sealed for a device opens there, for each device of the account it was sealed for, and nowhere else', () async {
      final sealed = sealFor([b1, b2], 'see you at 7');
      for (final d in [b1, b2]) {
        final o = d.fs.open(from: from, to: to, pairKey: pairKey, payload: sealed);
        expect(o.result, FsResult.opened);
        expect(utf8.decode(o.clear!), 'see you at 7');
      }
      expect(a.fs.open(from: from, to: to, pairKey: pairKey, payload: sealed).result, FsResult.notForThisDevice);
    });

    test('the pair\'s key, who it is from and to, and every byte are part of it', () async {
      final sealed = sealFor([b1], 'hello');
      expect(b1.fs.open(from: from, to: to, pairKey: NetCrypto.randomBytes(32), payload: sealed).result, FsResult.bad, reason: 'another pair\'s key');
      expect(b1.fs.open(from: to, to: from, pairKey: pairKey, payload: sealed).result, FsResult.bad, reason: 'from and to the other way');
      for (final at in [1, 40, 60, sealed.length - 30, sealed.length - 1]) {
        final changed = Uint8List.fromList(sealed)..[at] ^= 1;
        expect(b1.fs.open(from: from, to: to, pairKey: pairKey, payload: changed).result, isNot(FsResult.opened), reason: 'byte $at changed');
      }
      expect(b1.fs.open(from: from, to: to, pairKey: pairKey, payload: sealed.sublist(0, 60)).result, FsResult.bad);
      expect(b1.fs.open(from: from, to: to, pairKey: pairKey, payload: sealed).result, FsResult.opened, reason: 'unchanged, it still opens');
    });

    test('the long-term keys are not enough: neither the pair\'s key alone nor the device again without its kept prekeys opens it', () async {
      final sealed = sealFor([b1], 'what the words alone must not open');
      // Whoever has the account's words has the identity, so the pair's key: the old sealing would open with it.
      expect(NetCrypto.open(pairKey, sealed), isNull);
      expect(NetCrypto.open(pairKey, sealed.sublist(34 + 80)), isNull);
      // The same device's name, the same pair's key, but not the prekeys it kept: a device restored from the words.
      final restored = ForwardSecrecy(device: b1.device, secrets: MemoryFsStore(), plain: MemoryFsStore(), now: clock.now);
      await restored.load();
      expect(restored.open(from: from, to: to, pairKey: pairKey, payload: sealed).result, FsResult.noPrekey);
    });

    test('a one-off key is made for each packet and kept nowhere', () async {
      final writes = b1.secrets.writes + b1.plain.writes + a.secrets.writes + a.plain.writes;
      final one = sealFor([b1], 'same words'), two = sealFor([b1], 'same words');
      expect(one.sublist(1, 34), isNot(two.sublist(1, 34)), reason: 'a new one-off key each time');
      expect(b1.secrets.writes + b1.plain.writes + a.secrets.writes + a.plain.writes, writes, reason: 'sealing keeps nothing');
    });

    test('a new prekey every day; the old one still opens what was sealed to it until it is deleted, then nothing does', () async {
      final first = b1.fs.bundle!;
      final early = sealFor([b1], 'sealed to the first prekey');
      clock.pass(const Duration(days: 1, minutes: 1));
      expect(b1.fs.due, isTrue);
      await b1.fs.refresh();
      expect(b1.fs.bundle!.prekey, isNot(first.prekey));
      expect(b1.fs.heldPrekeys, contains(first.prekey));
      expect(b1.fs.open(from: from, to: to, pairKey: pairKey, payload: early).result, FsResult.opened);
      final kept = b1.secrets.kept[ForwardSecrecy.secretsName]!;
      expect(kept, contains(first.prekey));
      // Fifteen days after it was made, its private half is gone from memory and from what is kept.
      clock.pass(ForwardSecrecy.keepFor - const Duration(days: 1));
      expect(b1.fs.open(from: from, to: to, pairKey: pairKey, payload: early).result, FsResult.noPrekey, reason: 'past keepFor it is not used even before it is deleted');
      await b1.fs.refresh();
      expect(b1.fs.heldPrekeys, isNot(contains(first.prekey)));
      expect(b1.secrets.kept[ForwardSecrecy.secretsName]!, isNot(contains(first.prekey)));
      final again = await b1.restart();
      expect(again.open(from: from, to: to, pairKey: pairKey, payload: early).result, FsResult.noPrekey);
    });

    test('a packet opened once is a replay after, also once the app has started again', () async {
      final sealed = sealFor([b1], 'once');
      expect(b1.fs.open(from: from, to: to, pairKey: pairKey, payload: sealed).result, FsResult.opened);
      expect(b1.fs.open(from: from, to: to, pairKey: pairKey, payload: sealed).result, FsResult.replay);
      final again = await b1.restart();
      expect(again.open(from: from, to: to, pairKey: pairKey, payload: sealed).result, FsResult.replay);
      expect(again.open(from: from, to: to, pairKey: pairKey, payload: sealFor([b1], 'twice')).result, FsResult.opened, reason: 'the same words sealed again are another packet');
    });

    test('what is heard of others: newer only, never this device\'s own, never far in the future, never past the most devices', () async {
      final peer = NetCrypto.hex(NetCrypto.randomBytes(16));
      expect(a.fs.heard(peer, b1.fs.bundle!.toJson()), isTrue);
      expect(a.fs.heard(peer, b1.fs.bundle!.toJson()), isFalse, reason: 'the same again is nothing new');
      expect(a.fs.heard(peer, a.fs.bundle!.toJson()), isFalse, reason: 'its own');
      expect(a.fs.heard(peer, {'d': 'x', 'p': '00', 'k': '', 'm': 0}), isFalse);
      final future = FsBundle(device: _device(), prekey: '01020304', key: NetKeys.generate().public, made: clock.now().add(const Duration(days: 3)).millisecondsSinceEpoch);
      expect(a.fs.heard(peer, future.toJson()), isFalse);
      final older = FsBundle(device: b1.device, prekey: '01020304', key: NetKeys.generate().public, made: b1.fs.bundle!.made - 1000);
      expect(a.fs.heard(peer, older.toJson()), isFalse);
      expect(a.fs.targets(peer).single.prekey, b1.fs.bundle!.prekey);
      for (var i = 0; i < ForwardSecrecy.mostDevices + 3; i++) {
        a.fs.heard(peer, FsBundle(device: _device(), prekey: '0000000$i', key: NetKeys.generate().public, made: clock.now().millisecondsSinceEpoch + i).toJson());
      }
      expect(a.fs.targets(peer).length, ForwardSecrecy.mostDevices);
      // Kept across a start.
      final again = await a.restart();
      expect(again.targets(peer).length, ForwardSecrecy.mostDevices);
    });

    test('a prekey heard of is sealed to for a week, and not after', () async {
      final peer = NetCrypto.hex(NetCrypto.randomBytes(16));
      a.fs.heard(peer, b1.fs.bundle!.toJson());
      clock.pass(ForwardSecrecy.useFor - const Duration(minutes: 1));
      expect(a.fs.canSealTo(peer), isTrue);
      clock.pass(const Duration(minutes: 2));
      expect(a.fs.canSealTo(peer), isFalse);
    });

    test('signing out deletes it all', () async {
      final peer = NetCrypto.hex(NetCrypto.randomBytes(16));
      b1.fs.heard(peer, a.fs.bundle!.toJson());
      await b1.fs.wipe();
      expect(b1.fs.heldPrekeys, isEmpty);
      expect(b1.secrets.kept[ForwardSecrecy.secretsName], '');
      expect(b1.fs.canSealTo(peer), isFalse);
    });
  });

  group('between friends, through the switchboard', () {
    late Clock clock;
    late Bus bus;
    late Account alice, bob;

    setUp(() {
      clock = Clock();
      bus = Bus();
      alice = Account('Alice');
      bob = Account('Bob');
    });

    Future<Phone> phone(Account who, List<Account> friends, {bool fs = true, List<Carrier> extra = const []}) async {
      final p = Phone(who, bus, clock, fs: fs, extra: extra);
      for (final f in friends) {
        p.befriend(f);
      }
      return p.up();
    }

    test('the first message goes the old way carrying the prekey; the answer brings theirs; from then on it is forward secret', () async {
      final a = await phone(alice, [bob]), b = await phone(bob, [alice]);
      var d = await a.say(bob, 'hi bob');
      expect(d.acked, isTrue);
      expect(_isFs(bus.carried.first), isFalse, reason: 'nothing heard of Bob\'s devices yet');
      expect(b.dev.fs.canSealTo(alice.id), isTrue, reason: 'Alice\'s prekey came with it');
      expect(a.dev.fs.canSealTo(bob.id), isTrue, reason: 'Bob\'s came with his answer');
      final before = bus.carried.length;
      d = await a.say(bob, 'now forward secret');
      expect(d.acked, isTrue);
      expect(_isFs(bus.carried[before]), isTrue);
      await b.say(alice, 'and back');
      await _tick();
      expect(b.words, ['hi bob', 'now forward secret']);
      expect(a.words, ['and back']);
      final kinds = [for (final p in bus.carried.skip(before)) (fs: _isFs(p), ack: !_isFs(p))];
      expect(kinds.where((k) => k.fs).length, 2, reason: 'the two texts');
      expect(kinds.where((k) => !k.fs).length, 2, reason: 'the two answers go the old way: nothing in them to keep');
    });

    test('an old build on one side: everything goes the old way, both ways, and nothing is lost', () async {
      final a = await phone(alice, [bob]), b = await phone(bob, [alice], fs: false);
      for (var i = 0; i < 3; i++) {
        expect((await a.say(bob, 'new to old $i')).acked, isTrue);
        expect((await b.say(alice, 'old to new $i')).acked, isTrue);
      }
      await _tick();
      expect(b.words, ['new to old 0', 'new to old 1', 'new to old 2']);
      expect(a.words, ['old to new 0', 'old to new 1', 'old to new 2']);
      expect(bus.carried.any(_isFs), isFalse);
      expect(a.dev.fs.canSealTo(bob.id), isFalse);
    });

    test('lost and out of order: each packet opens on its own', () async {
      final a = await phone(alice, [bob]), b = await phone(bob, [alice]);
      await a.say(bob, 'warm up');
      await b.hub.stop();
      // Bob away: three are held, then the middle one is lost, and the others come last first.
      for (final w in ['one', 'two', 'three']) {
        await a.say(bob, w);
      }
      final held = bus.held.remove(bob.id)!;
      expect(held.map((h) => _isFs(h.$2)), everyElement(isTrue));
      await b.hub.start();
      b.hub.take(held[2].$2);
      b.hub.take(held[0].$2);
      await _tick();
      expect(b.words, ['warm up', 'three', 'one']);
    });

    test('a prekey rotated meanwhile: what was sealed to the old one still opens; what comes after is sealed to the new one', () async {
      final a = await phone(alice, [bob]), b = await phone(bob, [alice]);
      await a.say(bob, 'warm up');
      final old = b.dev.fs.bundle!.prekey;
      await b.hub.stop();
      await a.say(bob, 'sealed to the old prekey');
      clock.pass(const Duration(days: 2));
      await b.dev.fs.refresh();
      expect(b.dev.fs.bundle!.prekey, isNot(old));
      await b.hub.start();
      await _tick();
      expect(b.words, contains('sealed to the old prekey'));
      await b.say(alice, 'my new prekey goes with this');
      await _tick();
      expect(a.dev.fs.targets(bob.id).single.prekey, b.dev.fs.bundle!.prekey);
    });

    test('a replayed packet is answered but not passed on, also after the app started again', () async {
      final a = await phone(alice, [bob]), b = await phone(bob, [alice]);
      await a.say(bob, 'warm up');
      final before = bus.carried.length;
      await a.say(bob, 'pay me 5');
      final packet = bus.carried[before];
      expect(_isFs(packet), isTrue);
      await _tick();
      b.hub.take(packet);
      await _tick();
      expect(b.words.where((w) => w == 'pay me 5').length, 1);
      await b.restart();
      await b.board.start();
      b.hub.take(packet);
      await _tick();
      expect(b.words, isEmpty, reason: 'the switchboard forgot it, the prekey\'s record did not');
    });

    test('silence past a week: the prekey heard is stale, so one goes the old way, and its answer makes the next forward secret', () async {
      final a = await phone(alice, [bob]), b = await phone(bob, [alice]);
      await a.say(bob, 'warm up');
      clock.pass(ForwardSecrecy.useFor + const Duration(hours: 1));
      await b.dev.fs.refresh();
      final before = bus.carried.length;
      await a.say(bob, 'after a long time');
      expect(_isFs(bus.carried[before]), isFalse);
      await a.say(bob, 'and again');
      await _tick();
      expect(bus.carried.skip(before + 2).where((p) => Packet.parse(p)!.from == alice.id).any(_isFs), isTrue);
      expect(b.words, ['warm up', 'after a long time', 'and again']);
    });

    test('a route that carries only small packets takes the old sealing, with no prekey', () async {
      final smsA = BusCarrier(bus, alice.id, id: 'sms', traits: const CarrierTraits(maxPacket: 133, maxParts: 8, metered: true, live: false));
      final smsB = BusCarrier(bus, bob.id, id: 'sms', traits: const CarrierTraits(maxPacket: 133, maxParts: 8, metered: true, live: false));
      final a = await phone(alice, [bob], extra: [smsA]);
      await phone(bob, [alice], extra: [smsB]);
      await a.say(bob, 'warm up');
      final before = bus.carried.length;
      await a.board.send(a.peerOf(bob), Envelope(kind: 'call', body: {'r': 1}), metered: true, only: {'sms'});
      final sent = bus.carried.skip(before).toList();
      expect(sent, hasLength(1), reason: 'one data text');
      expect(_isFs(sent.single), isFalse);
      expect(sent.single.length, lessThanOrEqualTo(133));
    });
  });

  group('one account on several devices', () {
    late Clock clock;
    late Bus bus;
    late Account alice, bob;

    setUp(() {
      clock = Clock();
      bus = Bus();
      alice = Account('Alice');
      bob = Account('Bob');
    });

    Future<Phone> phone(Account who, List<Account> friends, {bool fs = true}) async {
      final p = Phone(who, bus, clock, fs: fs);
      for (final f in friends) {
        p.befriend(f);
      }
      return p.up();
    }

    test('a packet for an account opens on each of its devices that has offered a prekey', () async {
      final a = await phone(alice, [bob]);
      final phoneB = await phone(bob, [alice]), macB = await phone(bob, [alice]);
      await phoneB.say(alice, 'from the phone');
      await macB.say(alice, 'from the mac');
      await _tick();
      expect(a.dev.fs.targets(bob.id).map((t) => t.device).toSet(), {phoneB.dev.device, macB.dev.device});
      final before = bus.carried.length;
      await a.say(bob, 'to both');
      await _tick();
      expect(_isFs(bus.carried[before]), isTrue);
      expect(phoneB.words, contains('to both'));
      expect(macB.words, contains('to both'));
    });

    test('held for an account while it is away: whichever of its devices comes first opens it', () async {
      final a = await phone(alice, [bob]);
      final phoneB = await phone(bob, [alice]), macB = await phone(bob, [alice]);
      await phoneB.say(alice, 'p');
      await macB.say(alice, 'm');
      await _tick();
      await phoneB.hub.stop();
      await macB.hub.stop();
      expect((await a.say(bob, 'kept for bob')).handed, Handed.held);
      await macB.hub.start();
      await _tick();
      expect(macB.words, contains('kept for bob'));
      expect(phoneB.words, isNot(contains('kept for bob')), reason: 'the relay gave it to the first device to come (GMFB-21 copies take it on)');
    });

    test('a device the sender has not heard of yet answers with its prekey, and the next try reaches it', () async {
      final a = await phone(alice, [bob]);
      final phoneB = await phone(bob, [alice]);
      await phoneB.say(alice, 'p');
      await _tick();
      await phoneB.hub.stop();
      final windowsB = await phone(bob, [alice]);
      // Sealed for the phone alone; the new device can't open it, answers with its prekey, and the switchboard sends it
      // again at once, sealed for it too: answered within the same wait.
      final first = await a.say(bob, 'are you there', id: 'aaaaaaaaaaaaaaaa');
      await _tick();
      expect(a.dev.fs.targets(bob.id).map((t) => t.device), contains(windowsB.dev.device), reason: 'its prekey came back');
      expect(first.acked, isTrue);
      expect(windowsB.words, ['are you there']);
      expect(a.board.unanswered, 0);
    });

    test('copies to the account\'s own devices (GMFB-21) are forward secret too, once the devices have heard of each other', () async {
      final phoneB = await phone(bob, []), macB = await phone(bob, []);
      expect((await phoneB.board.send(phoneB.mine, Envelope(kind: 'mine', body: {'t': 'copy one'}))).acked, isTrue);
      await _tick();
      expect(macB.got.single.envelope.body['t'], 'copy one');
      expect(_isFs(bus.carried.first), isFalse, reason: 'nothing heard of the mac yet');
      expect(phoneB.dev.fs.targets(bob.id).single.device, macB.dev.device, reason: 'the mac\'s answer said its prekey');
      final before = bus.carried.length;
      await phoneB.board.send(phoneB.mine, Envelope(kind: 'mine', body: {'t': 'copy two'}));
      await _tick();
      expect(_isFs(bus.carried[before]), isTrue);
      expect(macB.got.map((r) => r.envelope.body['t']), ['copy one', 'copy two']);
      // Not opened by the words' key, which is what sealed copies until now.
      expect(NetCrypto.open(bob.mineKey, Packet.parse(bus.carried[before])!.payload), isNull);
    });

    test('an old build on one of the account\'s devices goes on with the old sealing for copies to it', () async {
      final phoneB = await phone(bob, []), oldMac = await phone(bob, [], fs: false);
      for (final t in ['one', 'two']) {
        await phoneB.board.send(phoneB.mine, Envelope(kind: 'mine', body: {'t': t}));
      }
      await _tick();
      expect(oldMac.got.map((r) => r.envelope.body['t']), ['one', 'two']);
      expect(bus.carried.any(_isFs), isFalse);
    });
    test('a call ringing (not sent again by Friends) reaches a device the sender had not heard of, the only one online', () async {
      final a = await phone(alice, [bob]);
      final phoneB = await phone(bob, [alice]);
      await phoneB.say(alice, 'p');
      await _tick();
      await phoneB.hub.stop();
      final macB = await phone(bob, [alice]);
      final d = await a.board.send(a.peerOf(bob), Envelope(kind: 'voice', body: {'t': 'call', 'i': 'c1'}), urgent: true);
      await _tick(80);
      expect(macB.got.where((r) => r.envelope.kind == 'voice').length, 1, reason: 'sent again by the switchboard, sealed for the mac too');
      expect(d.sent, isTrue);
      expect(a.board.unanswered, 0);
    });

    test('a device that can\'t open a packet passes it on, still sealed, to its own account: the sleeping phone opens it later', () async {
      final a = await phone(alice, [bob]);
      final phoneB = await phone(bob, [alice]);
      await phoneB.say(alice, 'p');
      await _tick();
      await phoneB.hub.stop();
      final macB = await phone(bob, [alice]);
      // Nothing is sent again here: only the passing on can bring it to the phone.
      a.hub.lose = false;
      await a.board.send(a.peerOf(bob), Envelope(kind: 'group', body: {'g': 'x', 'do': 'text', 't': 'for the group'}, ack: false));
      await _tick(80);
      expect(macB.got.where((r) => r.envelope.kind == 'group'), isEmpty, reason: 'not sealed for the mac, and not answered, so not sent again');
      expect(bus.held[bob.id], isNotEmpty, reason: 'passed on to Bob\'s own name, held for his phone');
      await phoneB.hub.start();
      await _tick(80);
      expect(phoneB.got.where((r) => r.envelope.kind == 'group').single.envelope.body['t'], 'for the group');
    });

    test('an old build on the account: once it is heard from, what goes to the account is sealed the old way so it can read it', () async {
      final a = await phone(alice, [bob]);
      final phoneB = await phone(bob, [alice]), oldTablet = await phone(bob, [alice], fs: false);
      await phoneB.say(alice, 'from the phone');
      await _tick();
      expect(a.dev.fs.canSealTo(bob.id), isTrue);
      await oldTablet.say(alice, 'from the tablet');
      await _tick();
      expect(a.dev.fs.needsOld(bob.id), isTrue);
      final before = bus.carried.length;
      await a.say(bob, 'to everyone of bob\'s');
      await _tick();
      expect(_isFs(bus.carried[before]), isFalse);
      expect(oldTablet.words, contains('to everyone of bob\'s'));
      expect(phoneB.words, contains('to everyone of bob\'s'));
      // And the phone's copies to its own devices, once the tablet has sent one of its own.
      await oldTablet.board.send(oldTablet.mine, Envelope(kind: 'mine', body: {'t': 'tablet copy'}));
      await _tick();
      final mark = bus.carried.length;
      await phoneB.board.send(phoneB.mine, Envelope(kind: 'mine', body: {'t': 'phone copy'}));
      await _tick();
      expect(_isFs(bus.carried[mark]), isFalse);
      expect(oldTablet.got.map((r) => r.envelope.body['t']), contains('phone copy'));
      // A week without hearing it: forward secret again.
      clock.pass(ForwardSecrecy.oldDeviceFor + const Duration(hours: 1));
      await phoneB.say(alice, 'refresh');
      await _tick();
      expect(a.dev.fs.needsOld(bob.id), isFalse);
    });

    test('a device of theirs gone quiet past a week is not left out: the old way, until it is forgotten', () async {
      final a = await phone(alice, [bob]);
      final phoneB = await phone(bob, [alice]), macB = await phone(bob, [alice]);
      await phoneB.say(alice, 'p');
      await macB.say(alice, 'm');
      await _tick();
      await macB.hub.stop();
      clock.pass(ForwardSecrecy.useFor + const Duration(hours: 1));
      await phoneB.dev.fs.refresh();
      await phoneB.say(alice, 'still here');
      await _tick();
      expect(a.dev.fs.targets(bob.id).map((t) => t.device), [phoneB.dev.device]);
      expect(a.dev.fs.needsOld(bob.id), isTrue, reason: 'the mac\'s prekey is stale, not yet forgotten');
      final before = bus.carried.length;
      await a.say(bob, 'for the mac too');
      expect(_isFs(bus.carried[before]), isFalse);
      clock.pass(ForwardSecrecy.keepFor);
      await phoneB.dev.fs.refresh();
      await phoneB.say(alice, 'and still');
      await _tick();
      expect(a.dev.fs.needsOld(bob.id), isFalse, reason: 'past keepFor the mac is forgotten');
    });

    test('forward secrecy that can\'t load yet: nothing it can\'t open is answered or lost, and it loads when it can', () async {
      final a = await phone(alice, [bob]);
      final phoneB = await phone(bob, [alice]);
      await phoneB.say(alice, 'p');
      await a.say(bob, 'warm');
      await _tick();
      final locked = FlakyStore()..failReads = true;
      final ipad = await Phone(bob, bus, clock, secrets: locked).up();
      ipad.befriend(alice);
      expect(ipad.dev.fs.loaded, isFalse);
      await phoneB.hub.stop();
      await a.board.send(a.peerOf(bob), Envelope(kind: 'voice', body: {'t': 'call'}, ack: false));
      await _tick(80);
      expect(ipad.got, isEmpty);
      expect(bus.held[bob.id], isNotEmpty, reason: 'passed on for the phone');
      locked.failReads = false;
      expect(await ipad.dev.fs.tryLoad(), isTrue);
      expect(ipad.dev.fs.bundle, isNotNull);
    });

    test('a new prekey is never offered before the secret store has it', () async {
      final store = FlakyStore();
      final d = Dev(clock, secrets: store);
      await d.fs.load();
      final first = d.fs.bundle!.prekey;
      store.failWrites = true;
      clock.pass(const Duration(days: 2));
      await expectLater(d.fs.refresh(), throwsA(isA<StateError>()));
      expect(d.fs.bundle!.prekey, first, reason: 'the one that could not be kept is not offered');
      store.failWrites = false;
      await d.fs.refresh();
      expect(d.fs.bundle!.prekey, isNot(first));
      expect(store.kept[ForwardSecrecy.secretsName], contains(d.fs.bundle!.prekey));
    });

    test('sealing and opening on an isolate of their own give the same bytes back', () async {
      ForwardSecrecy.offThread = true;
      addTearDown(() => ForwardSecrecy.offThread = false);
      final b = Dev(clock);
      await b.fs.load();
      final key = NetCrypto.randomBytes(32), from = _device(), to = _device();
      final sealed = await ForwardSecrecy.sealAway(from: from, to: to, pairKey: key, clear: utf8.encode('away'), targets: [b.fs.bundle!]);
      final o = await b.fs.openAway(from: from, to: to, pairKey: key, payload: sealed);
      expect(o.result, FsResult.opened);
      expect(utf8.decode(o.clear!), 'away');
      expect((await b.fs.openAway(from: from, to: to, pairKey: key, payload: sealed)).result, FsResult.replay);
    });
  });
}
