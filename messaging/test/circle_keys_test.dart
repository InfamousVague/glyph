import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/circles/circles.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/forward_secrecy.dart' show MemoryFsStore;
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/voice/hangout.dart';
import 'package:ghost_messaging/voice/voice.dart';

/// A circle's key changed when someone is put out (GMFB-26, lib/circles/circle_keys.dart, docs/FORWARD_SECRECY.md):
/// the keys on their own, then circles on a stand-in for the relay's rooms, with a listener that keeps hearing what is
/// said after a ban, as a changed app could.

class _Hub {
  final Map<String, List<_Route>> rooms = {};
}

class _Route implements VoiceRoute {
  _Route(this.hub, this.me);
  final _Hub hub;
  @override
  final String me;
  final _events = StreamController<RoomEvent>.broadcast();
  final _packets = StreamController<({String room, String from, Uint8List bytes})>.broadcast();
  final _looks = StreamController<({String room, List<String> members})>.broadcast();

  /// Everything this route heard, by room: what a listener that never leaves keeps.
  final Map<String, List<Uint8List>> heard = {};

  @override
  Future<List<String>> join(String room, String token) async {
    final r = hub.rooms[room] ??= [];
    final first = !r.any((o) => o.me == me);
    final others = {for (final o in r) if (o.me != me) o.me}.toList();
    if (!r.contains(this)) r.add(this);
    if (first) {
      for (final o in r) {
        if (o.me != me) scheduleMicrotask(() => o._events.add(RoomEvent(room, came: me)));
      }
    }
    return others;
  }

  @override
  void leave(String room) {
    final r = hub.rooms[room];
    if (r == null || !r.remove(this)) return;
    if (r.any((o) => o.me == me)) return;
    for (final o in r) {
      scheduleMicrotask(() => o._events.add(RoomEvent(room, went: me)));
    }
  }

  @override
  void send(String room, Uint8List bytes) {
    for (final o in [...?hub.rooms[room]]) {
      if (!identical(o, this)) {
        scheduleMicrotask(() {
          (o.heard[room] ??= []).add(bytes);
          o._packets.add((room: room, from: me, bytes: bytes));
        });
      }
    }
  }

  @override
  void look(String room, String token) {}
  @override
  void unlook(String room) {}
  @override
  Stream<RoomEvent> get events => _events.stream;
  @override
  Stream<({String room, String from, Uint8List bytes})> get packets => _packets.stream;
  @override
  Stream<({String room, List<String> members})> get looks => _looks.stream;
}

Future<void> _until(bool Function() ok, {int seconds = 5}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _settle([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));

Circle _copy(Circle c) => Circle.fromJson(jsonDecode(jsonEncode(c.toJson())))!;

/// Whether [bytes] opens for anyone holding only the seeds (what a banned member keeps): the circle's own key or a
/// space's, the old way, or under an epoch [keys] holds.
bool _opensWithSeedsOnly(Circle c, Uint8List bytes, {CircleKeys? keys}) {
  if (NetCrypto.open(c.key, bytes) != null) return true;
  for (final s in c.spaces) {
    if (NetCrypto.open(c.channelOf(s).key, bytes) != null) return true;
  }
  if (keys != null) {
    if (keys.open(c.seed, c.key, 'circle', bytes).clear != null) return true;
    for (final s in c.spaces) {
      if (keys.open(c.seed, c.channelOf(s).key, 'space', bytes).clear != null) return true;
    }
  }
  return false;
}

void main() {
  group('the keys', () {
    late NetKeys owner, maya, sam;
    late Circles mine;
    late Circle c;

    setUp(() async {
      owner = NetKeys.generate();
      maya = NetKeys.generate();
      sam = NetKeys.generate();
      mine = Circles.forTest(signer: KeysSigner(owner), route: _Route(_Hub(), owner.id));
      c = (await mine.make(name: 'Book club'))!;
    });
    tearDown(() => mine.clear());

    Future<CircleInbox> inboxOf(CircleKeys keys, NetKeys who) async => CircleKeys.inboxOf(c.seed, who.id, await keys.inboxSaid(c.seed, KeysSigner(who)))!;

    test('an inbox is only its identity\'s: another name, or a changed key, is refused', () async {
      final k = CircleKeys.fresh();
      final said = await k.inboxSaid(c.seed, KeysSigner(maya));
      expect(CircleKeys.inboxOf(c.seed, maya.id, said), isNotNull);
      expect(CircleKeys.inboxOf(c.seed, sam.id, said), isNull, reason: 'said as someone else');
      expect(CircleKeys.inboxOf('${c.seed.substring(1)}0', maya.id, said), isNull, reason: 'another circle');
      expect(CircleKeys.inboxOf(c.seed, maya.id, {...said, 'b': NetCrypto.hex(NetKeys.generate().public)}), isNull, reason: 'another inbox under her signature');
    });

    test('after a change the seed alone opens nothing, an older key opens nothing newer, and the old sealing still opens', () async {
      final ownerKeys = mine.keys!, mayaKeys = CircleKeys.fresh(), samKeys = CircleKeys.fresh();
      final said = (await ownerKeys.rotate(c, KeysSigner(owner), [await inboxOf(mayaKeys, maya)]))!;
      expect(said.single['t'], 'rk');
      expect(mayaKeys.take(c, maya.id, said.single), isTrue);
      expect(samKeys.take(c, sam.id, said.single), isFalse, reason: 'no box for Sam');
      expect(mayaKeys.current(c.seed)!.epoch, 1);
      expect(samKeys.lacking(c.seed), isTrue, reason: 'he knows a newer key exists, and has none');

      final one = ownerKeys.seal(c.seed, c.key, 'circle', utf8.encode('said in epoch 1'));
      expect(utf8.decode(mayaKeys.open(c.seed, c.key, 'circle', one).clear!), 'said in epoch 1');
      expect(_opensWithSeedsOnly(c, one, keys: samKeys), isFalse);
      expect(samKeys.open(c.seed, c.key, 'circle', one).unknown, isTrue);
      expect(mayaKeys.open(c.seed, c.key, 'space', one).clear, isNull, reason: 'a room\'s and a space\'s keys are apart');

      // Changed again without her: what she holds opens nothing of epoch 2, and all of epoch 1 still.
      await ownerKeys.rotate(c, KeysSigner(owner), const []);
      final two = ownerKeys.seal(c.seed, c.key, 'circle', utf8.encode('said in epoch 2'));
      expect(mayaKeys.open(c.seed, c.key, 'circle', two).clear, isNull);
      expect(mayaKeys.open(c.seed, c.key, 'circle', two).unknown, isTrue);
      expect(mayaKeys.open(c.seed, c.key, 'circle', one).clear, isNotNull);
      expect(ownerKeys.open(c.seed, c.key, 'circle', one).clear, isNotNull, reason: 'the owner keeps every epoch it held');

      // What a build from before says, the old way, opens for everyone.
      final old = NetCrypto.seal(c.key, utf8.encode('from an old build'));
      for (final k in [ownerKeys, mayaKeys, samKeys]) {
        expect(k.open(c.seed, c.key, 'circle', old).clear, isNotNull);
      }
      // Changed by a byte: nothing.
      expect(mayaKeys.open(c.seed, c.key, 'circle', Uint8List.fromList(one)..[30] ^= 1).clear, isNull);
    });

    test('only the owner or an admin can change the key, and nobody can hand out a key of their own making', () async {
      final mayaKeys = CircleKeys.fresh(), samKeys = CircleKeys.fresh();
      final mayaInbox = await inboxOf(mayaKeys, maya);
      expect(await samKeys.rotate(c, KeysSigner(sam), [mayaInbox]), isNull, reason: 'Sam may not change the circle');

      // A header Sam signs himself is not believed even where it is put together by hand.
      final key = NetCrypto.randomBytes(32);
      final forged = CircleEpoch(seed: c.seed, epoch: 5, commit: CircleKeys.commitOf(c.seed, 5, key), by: sam.id, byKey: NetCrypto.hex(sam.public), at: 1, sig: '');
      final signedBySam = forged.withSig(NetCrypto.hex(NetCrypto.sign(sam, forged.signed)));
      expect(mayaKeys.take(c, maya.id, {'t': 'kb', 'h': signedBySam.toJson(), 'x': []}), isFalse);
      expect(mayaKeys.newest(c.seed), isNull);

      // The owner's real header, with a box Sam made for Maya holding a key of his: refused, it is not the key the
      // owner committed to.
      final real = (await mine.keys!.rotate(c, KeysSigner(owner), const []))!.single;
      final h = CircleEpoch.fromJson(real['h'])!;
      final once = NetKeys.generate();
      final shared = NetCrypto.agree(once, mayaInbox.key)!;
      final k = NetCrypto.hkdf(salt: c.key, ikm: shared, info: utf8.encode('ghost-circle box v1|${c.seed}|${h.epoch}|${h.commit}|${maya.id}|${mayaInbox.device}'));
      final box = {'i': maya.id, 'd': mayaInbox.device, 'o': NetCrypto.hex(once.public), 's': base64Encode(NetCrypto.seal(k, NetCrypto.randomBytes(32)))};
      expect(mayaKeys.take(c, maya.id, {'t': 'kb', 'h': real['h'], 'x': [box]}), isFalse);
      expect(mayaKeys.current(c.seed), isNull);
      // The real key, handed on by anyone who holds it: taken.
      final handed = mine.keys!.handOn(c, mayaInbox)!;
      expect(mayaKeys.take(c, maya.id, handed), isTrue);
      expect(mayaKeys.current(c.seed)!.epoch, h.epoch);
    });

    test('kept across a start, in the secret store; forgotten with the circle', () async {
      final store = MemoryFsStore();
      final k = CircleKeys(secrets: store);
      await k.load();
      final inbox = NetCrypto.hex(k.inboxKey);
      final said = (await mine.keys!.rotate(c, KeysSigner(owner), [await inboxOf(k, maya)]))!;
      expect(k.take(c, maya.id, said.single), isTrue);
      await k.flushed();
      final again = CircleKeys(secrets: store);
      await again.load();
      expect(NetCrypto.hex(again.inboxKey), inbox);
      expect(again.device, k.device);
      expect(again.current(c.seed)!.epoch, 1);
      final sealed = mine.keys!.seal(c.seed, c.key, 'space', [1, 2, 3]);
      expect(again.open(c.seed, c.key, 'space', sealed).clear, [1, 2, 3]);
      await again.forget(c.seed);
      await again.flushed();
      final third = CircleKeys(secrets: store);
      await third.load();
      expect(third.current(c.seed), isNull);
    });

    test('many members: the boxes go in several messages, each with the header', () async {
      final inboxes = [for (var i = 0; i < CircleKeys.boxesPerMessage + 5; i++) CircleInbox(id: NetCrypto.hex(NetCrypto.randomBytes(16)), device: NetCrypto.hex(NetCrypto.randomBytes(16)), key: NetKeys.generate().public)];
      final said = (await mine.keys!.rotate(c, KeysSigner(owner), inboxes))!;
      expect(said.map((m) => m['t']), ['rk', 'kb']);
      expect([for (final m in said) (m['x'] as List).length], [CircleKeys.boxesPerMessage, 5]);
      expect(utf8.encode(jsonEncode(said.first)).length, lessThan(64 * 1024));
    });
  });

  group('in circles', () {
    late _Hub hub;
    late NetKeys owner, maya, sam;
    late Circles mine, hers, his;
    late Circle c;
    final closing = <Future<void> Function()>[];

    setUp(() async {
      hub = _Hub();
      owner = NetKeys.generate();
      maya = NetKeys.generate();
      sam = NetKeys.generate();
      mine = Circles.forTest(signer: KeysSigner(owner), route: _Route(hub, owner.id));
      c = (await mine.make(name: 'Book club'))!;
      hers = Circles.forTest(signer: KeysSigner(maya), route: _Route(hub, maya.id));
      his = Circles.forTest(signer: KeysSigner(sam), route: _Route(hub, sam.id));
      hers.join(_copy(mine.bySeed(c.seed)!));
      his.join(_copy(mine.bySeed(c.seed)!));
      // Everyone in, and each one's inbox heard by the owner.
      await _until(() => mine.roomOf(c)!.inboxes.length == 2);
      expect(mine.roomOf(c)!.inboxes.keys.map((k) => k.split(':').first).toSet(), {maya.id, sam.id});
    });

    tearDown(() async {
      for (final f in closing.reversed) {
        await f();
      }
      closing.clear();
      for (final x in [mine, hers, his]) {
        await x.clear();
      }
    });

    /// A listener in [c]'s rooms under Sam's name that never leaves: what a changed app of his could keep hearing.
    Future<_Route> eavesdropper() async {
      final ear = _Route(hub, sam.id);
      await ear.join(c.room, c.token);
      for (final s in c.spaces) {
        await ear.join(c.channelOf(s).chatRoom, c.channelOf(s).chatToken);
      }
      return ear;
    }

    Future<HangoutRoom> space(Circles device, NetKeys who, String name) async {
      final text = mine.bySeed(c.seed)!.spaces.firstWhere((s) => s.kind == SpaceKind.text);
      final room = HangoutRoom(channel: mine.bySeed(c.seed)!.channelOf(text), route: _Route(hub, who.id), name: name, signer: KeysSigner(who))..circleKeys = device.keys;
      await room.open();
      closing.add(room.close);
      return room;
    }

    test('banned: everyone else gets the new key, and nothing said after opens for him, in the circle\'s room or its spaces', () async {
      final ear = await eavesdropper();
      final ownerSpace = await space(mine, owner, 'Owner'), hersSpace = await space(hers, maya, 'Maya');
      expect(ownerSpace.send('before the ban'), isTrue);
      await _until(() => hersSpace.messages.any((m) => m.text == 'before the ban'));

      expect(await mine.removeMember(mine.bySeed(c.seed)!, sam.id), isTrue);
      await _until(() => his.bySeed(c.seed) == null);
      expect(his.bySeed(c.seed), isNull, reason: 'his own app left, as before');
      await _until(() => hers.keys!.current(c.seed) != null);
      expect(hers.keys!.current(c.seed)!.epoch, 1);
      expect(his.keys!.current(c.seed), isNull);

      final heardBefore = {for (final e in ear.heard.entries) e.key: e.value.length};
      await mine.edit(mine.bySeed(c.seed)!, name: 'Book club (new)');
      await _until(() => hers.bySeed(c.seed)!.name == 'Book club (new)');
      expect(hers.bySeed(c.seed)!.name, 'Book club (new)', reason: 'the manifest under the new key reaches her');
      expect(ownerSpace.send('after the ban'), isTrue);
      await _until(() => hersSpace.messages.any((m) => m.text == 'after the ban'));
      expect(hersSpace.messages.map((m) => m.text), contains('after the ban'));
      await _settle();

      final after = [
        for (final e in ear.heard.entries)
          ...e.value.skip(heardBefore[e.key] ?? 0),
      ];
      expect(after, isNotEmpty, reason: 'he still hears the packets');
      // The key's own messages (inboxes, boxes) are sealed with the seed's key: what he can open of those says nothing.
      final opened = [
        for (final b in after)
          if (_opensWithSeedsOnly(c, b, keys: his.keys)) jsonDecode(utf8.decode(NetCrypto.open(c.key, b) ?? [])) as Map,
      ];
      expect(opened.map((m) => m['t']).toSet().difference({'ik', 'k?', 'kb', 'rk'}), isEmpty, reason: 'no manifest, no message: only inboxes and boxes not his');
      expect(opened.any((m) => jsonEncode(m).contains('after the ban') || jsonEncode(m).contains('Book club (new)')), isFalse);
    });

    test('a banned member asking for the key is not answered; a second device of a member is', () async {
      expect(await mine.removeMember(mine.bySeed(c.seed)!, sam.id), isTrue);
      await _until(() => hers.keys!.current(c.seed) != null);

      // Sam's changed app asks, with a real inbox of his.
      final samKeys = CircleKeys.fresh();
      final ear = await eavesdropper();
      ear.send(c.room, NetCrypto.seal(c.key, utf8.encode(jsonEncode({'t': 'k?', 'ik': await samKeys.inboxSaid(c.seed, KeysSigner(sam))}))));
      await _settle(400);
      for (final b in ear.heard[c.room] ?? const <Uint8List>[]) {
        final clear = NetCrypto.open(c.key, b);
        if (clear != null) samKeys.take(c, sam.id, jsonDecode(utf8.decode(clear)) as Map);
      }
      expect(samKeys.current(c.seed), isNull);

      // Nor is he under a new key of his, slipped into the room with its token and never seen come in.
      final eve = NetKeys.generate(), eveKeys = CircleKeys.fresh();
      final eveEar = _Route(hub, eve.id);
      await eveEar.join(c.room, c.token);
      eveEar.send(c.room, NetCrypto.seal(c.key, utf8.encode(jsonEncode({'t': 'k?', 'ik': await eveKeys.inboxSaid(c.seed, KeysSigner(eve))}))));
      await _settle(400);
      for (final b in eveEar.heard[c.room] ?? const <Uint8List>[]) {
        final clear = NetCrypto.open(c.key, b);
        if (clear != null) eveKeys.take(c, eve.id, jsonDecode(utf8.decode(clear)) as Map);
      }
      expect(eveKeys.current(c.seed), isNull);
      expect(mine.mayHaveKey(c.seed, eve.id), isFalse);

      // Maya's computer comes in after the change: it asks, is answered, and reads what is said.
      final hersToo = Circles.forTest(signer: KeysSigner(maya), route: _Route(hub, maya.id));
      closing.add(hersToo.clear);
      hersToo.join(_copy(hers.bySeed(c.seed)!));
      await _until(() => hersToo.keys!.current(c.seed) != null);
      expect(hersToo.keys!.current(c.seed)!.epoch, 1);
      await mine.edit(mine.bySeed(c.seed)!, name: 'Read on her computer');
      await _until(() => hersToo.bySeed(c.seed)!.name == 'Read on her computer');
      expect(hersToo.bySeed(c.seed)!.name, 'Read on her computer');
    });

    test('kicked: a new key too; coming back openly by the link, he is given it again', () async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await mine.kickMember(mine.bySeed(c.seed)!, sam.id), isTrue);
      await _until(() => his.bySeed(c.seed) == null);
      await _until(() => hers.keys!.current(c.seed) != null);
      expect(his.keys!.current(c.seed), isNull);
      expect(mine.mayHaveKey(c.seed, sam.id), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      his.removedFrom.value = null;
      his.join(Circle.fromLink(mine.bySeed(c.seed)!.link)!);
      await _until(() => his.keys!.current(c.seed) != null);
      expect(mine.mayHaveKey(c.seed, sam.id), isTrue, reason: 'he said he came, after the kick');
      expect(his.keys!.current(c.seed)!.epoch, 1);
      expect(his.bySeed(c.seed), isNotNull);
    });
  });
}
