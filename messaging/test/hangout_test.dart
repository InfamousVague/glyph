import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/voice/hangout.dart';
import 'package:ghost_messaging/voice/roles.dart';
import 'package:ghost_messaging/voice/voice.dart';

/// Hangouts' chat and roles (lib/voice/hangout.dart, lib/voice/roles.dart). Matt, 2026-11-15: "Implement a
/// permissions system similar to discord for hangouts and add a chat to hangouts so the whole group can send messages
/// to the hangout as well as voice and video, make default roles such as admin, moderator, member".
///
/// The hub is stood in for (rooms: join, leave, a packet to everyone else, who came and went), as in
/// voice_channels_test, and each install has a real key, so rosters are really signed and checked.
class _Hub {
  final Map<String, Map<String, _Route>> rooms = {};
}

class _Route implements VoiceRoute {
  _Route(this.hub, this.me);
  final _Hub hub;
  @override
  final String me;
  final _events = StreamController<RoomEvent>.broadcast();
  final _packets = StreamController<({String room, String from, Uint8List bytes})>.broadcast();
  final _looks = StreamController<({String room, List<String> members})>.broadcast();

  /// Everything this install sent, to see a forged packet go in.
  @override
  Future<List<String>> join(String room, String token) async {
    final r = hub.rooms[room] ??= {};
    final others = r.keys.toList();
    r[me] = this;
    for (final o in r.values) {
      if (o != this) scheduleMicrotask(() => o._events.add(RoomEvent(room, came: me)));
    }
    return others;
  }

  @override
  void leave(String room) {
    final r = hub.rooms[room];
    r?.remove(me);
    for (final o in r?.values ?? const <_Route>[]) {
      scheduleMicrotask(() => o._events.add(RoomEvent(room, went: me)));
    }
  }

  @override
  void send(String room, Uint8List bytes) {
    for (final o in hub.rooms[room]?.values ?? const <_Route>[]) {
      if (o != this) scheduleMicrotask(() => o._packets.add((room: room, from: me, bytes: bytes)));
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

class _Install {
  _Install(this.hub, this.name) : keys = NetKeys.generate();
  final _Hub hub;
  final String name;
  final NetKeys keys;
  final store = MemoryHangoutStore();
  late final route = _Route(hub, keys.id);
  String get id => keys.id;
  String get key => NetCrypto.hex(keys.public);

  HangoutRoom room(VoiceChannel c) => HangoutRoom(channel: c, route: route, name: name, signer: KeysSigner(keys), store: store);
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Hub hub;
  late _Install owner, ann, bob, cat;
  late VoiceChannel channel;

  setUp(() {
    hub = _Hub();
    owner = _Install(hub, 'Matt');
    ann = _Install(hub, 'Ann');
    bob = _Install(hub, 'Bob');
    cat = _Install(hub, 'Cat');
    channel = VoiceChannel.make('Friday hang', owner: owner.key);
  });

  group('roles', () {
    test('a hangout starts with admin, moderator and member; the owner can do anything, a newcomer is a member', () {
      final r = Roster.first(owner.key);
      expect(r.ranked.map((x) => x.id), [Role.admin, Role.moderator, Role.member]);
      expect(r.isOwner(owner.id), isTrue);
      expect(r.roleOf(owner.id).id, Role.admin);
      expect(r.roleOf(ann.id).id, Role.member);
      for (final p in Perm.values) {
        expect(r.can(owner.id, p), isTrue, reason: '$p');
      }
      expect(r.can(ann.id, Perm.speak), isTrue);
      expect(r.can(ann.id, Perm.chat), isTrue);
      expect(r.can(ann.id, Perm.removeMembers), isFalse);
      expect(r.can(ann.id, Perm.ban), isFalse);
      // A moderator: mute, remove and delete messages; not ban, not roles.
      final mod = r.next(assigned: {bob.id: Role.moderator});
      expect(mod.can(bob.id, Perm.muteOthers), isTrue);
      expect(mod.can(bob.id, Perm.removeMembers), isTrue);
      expect(mod.can(bob.id, Perm.manageMessages), isTrue);
      expect(mod.can(bob.id, Perm.ban), isFalse);
      expect(mod.canManage(bob.id), isFalse);
      expect(mod.outranks(bob.id, ann.id), isTrue);
      expect(mod.outranks(ann.id, bob.id), isFalse);
      expect(mod.outranks(bob.id, owner.id), isFalse, reason: 'no one acts on the owner');
    });

    test('a roster is believed only when the owner, or an admin the owner made, signed it', () async {
      final first = Roster.first(owner.key);
      final byOwner = await first.next(assigned: {ann.id: Role.moderator}).signedBy(owner.id, owner.keys.public, (m) async => NetCrypto.sign(owner.keys, m));
      expect(byOwner.trustedFor(owner.key), isTrue);
      expect(Roster.fromJson(byOwner.toJson())!.trustedFor(owner.key), isTrue, reason: 'it travels as JSON');

      // Ann signs one making herself admin: not believed, she was never granted it.
      final forged = await byOwner.next(assigned: {ann.id: Role.admin}).signedBy(ann.id, ann.keys.public, (m) async => NetCrypto.sign(ann.keys, m));
      expect(forged.trustedFor(owner.key), isFalse);
      // One changed after it was signed: not believed.
      final changed = Roster.fromJson({...byOwner.toJson(), 'b': [owner.id]})!;
      expect(changed.trustedFor(owner.key), isFalse);
      // Signed by the owner of another hangout: not this one's.
      expect(byOwner.trustedFor(bob.key), isFalse);

      // The owner makes Bob an admin (a grant only the owner can sign); Bob's own rosters are then believed.
      final grant = NetCrypto.hex(NetCrypto.sign(owner.keys, Roster.grantMessage(owner.key, bob.id)));
      final withBob = await byOwner.next(assigned: {...byOwner.assigned, bob.id: Role.admin}, adminGrants: {bob.id: grant}).signedBy(owner.id, owner.keys.public, (m) async => NetCrypto.sign(owner.keys, m));
      expect(withBob.trustedFor(owner.key), isTrue);
      final bobs = await withBob.next(assigned: {...withBob.assigned, cat.id: Role.moderator}).signedBy(bob.id, bob.keys.public, (m) async => NetCrypto.sign(bob.keys, m));
      expect(bobs.trustedFor(owner.key), isTrue);
      // But Bob can't make Cat an admin: he has no grant to give.
      final bobMakesAdmin = await withBob.next(assigned: {...withBob.assigned, cat.id: Role.admin}).signedBy(bob.id, bob.keys.public, (m) async => NetCrypto.sign(bob.keys, m));
      expect(bobMakesAdmin.trustedFor(owner.key), isFalse);
      // A grant copied to someone else is not theirs.
      final stolen = await withBob.next(assigned: {...withBob.assigned, cat.id: Role.admin}, adminGrants: {...withBob.adminGrants, cat.id: grant}).signedBy(owner.id, owner.keys.public, (m) async => NetCrypto.sign(owner.keys, m));
      expect(stolen.trustedFor(owner.key), isFalse);
    });

    test('a hangout from before roles: everyone a member, no one can change anything', () {
      final r = Roster.first('');
      expect(r.can(ann.id, Perm.speak), isTrue);
      expect(r.can(ann.id, Perm.ban), isFalse);
      expect(r.canManage(ann.id), isFalse);
    });
  });

  group('chat', () {
    test('the whole hangout sees what is written, and someone coming in later gets what they missed', () async {
      final o = owner.room(channel), a = ann.room(channel);
      await o.open();
      await a.open();
      await _settle();
      expect(o.present[ann.id]?.name, 'Ann');
      expect(a.present[owner.id]?.name, 'Matt');

      expect(o.send('Who is around?'), isTrue);
      // The answer is written a moment later, as a person's would be: two messages in the same millisecond have no
      // order of their own, and every device puts them in the same one by id (HangoutRoom._add), which need not be
      // the order they were written in. Sent back to back here they sometimes shared a millisecond.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(a.send('Me!'), isTrue);
      await _settle();
      expect(o.messages.map((m) => m.text), ['Who is around?', 'Me!']);
      expect(a.messages.map((m) => m.text), ['Who is around?', 'Me!']);
      expect(a.messages.first.from, owner.id);

      // Bob comes later: one copy of the history, from the lowest id there, not one from each.
      final b = bob.room(channel);
      await b.open();
      await _settle();
      expect(b.messages.map((m) => m.text), ['Who is around?', 'Me!']);
    });

    test('a member deletes their own message; a moderator deletes anyone\'s below them; a member can\'t delete others\'', () async {
      final o = owner.room(channel), a = ann.room(channel), b = bob.room(channel);
      for (final r in [o, a, b]) {
        await r.open();
      }
      await _settle();
      a.send('first');
      b.send('second');
      await _settle();
      // Ann tries Bob's: not hers, she can't.
      final bobs = a.messages.firstWhere((m) => m.text == 'second');
      expect(a.canDelete(bobs), isFalse);
      // Ann deletes her own.
      a.delete(a.messages.firstWhere((m) => m.text == 'first'));
      await _settle();
      expect(o.messages.map((m) => m.text), ['second']);
      // The owner makes Ann a moderator; she deletes Bob's, everywhere.
      expect(await o.setRole(ann.id, Role.moderator), isTrue);
      await _settle();
      expect(a.roster.roleOf(ann.id).id, Role.moderator);
      expect(a.canDelete(bobs), isTrue);
      a.delete(bobs);
      await _settle();
      expect(b.messages, isEmpty);
      expect(o.messages, isEmpty);
    });

    test('a role without Send messages can\'t write, and what it sends anyway is not shown', () async {
      final o = owner.room(channel), a = ann.room(channel);
      await o.open();
      await a.open();
      await _settle();
      final member = o.roster.roleById(Role.member)!;
      expect(await o.saveRole(member.copyWith(perms: {...member.perms}..remove(Perm.chat))), isTrue);
      await _settle();
      expect(a.can(Perm.chat), isFalse);
      expect(a.send('hello?'), isFalse);
      expect(o.messages, isEmpty);
    });
  });

  group('moderation', () {
    test('the roster reaches someone who comes in later, and a forged one sent to the room is ignored', () async {
      final o = owner.room(channel), a = ann.room(channel);
      await o.open();
      await a.open();
      await _settle();
      expect(await o.setRole(ann.id, Role.moderator), isTrue);
      await o.close();
      await _settle();
      // The owner is gone; Bob comes in and takes the roster from Ann.
      final b = bob.room(channel);
      await b.open();
      await _settle();
      expect(b.roster.version, o.roster.version);
      expect(b.roster.roleOf(ann.id).id, Role.moderator);

      // Cat signs a roster making himself admin and banning Ann: no one takes it.
      final c = cat.room(channel);
      await c.open();
      await _settle();
      final forged = await b.roster.next(assigned: {cat.id: Role.admin}, banned: {ann.id}).signedBy(cat.id, cat.keys.public, (m) async => NetCrypto.sign(cat.keys, m));
      expect(await c.setRole(ann.id, Role.member), isFalse, reason: 'a member can\'t change roles');
      expect(await c.ban(ann.id), isFalse);
      // Sent by hand, as a modified app would.
      cat.route.send(channel.chatRoom, NetCrypto.seal(channel.key, utf8.encode(jsonEncode({'t': 'roster', 'r': forged.toJson()}))));
      cat.route.send(channel.chatRoom, NetCrypto.seal(channel.key, utf8.encode(jsonEncode({'t': 'kick', 'to': ann.id}))));
      await _settle();
      expect(b.roster.banned, isEmpty);
      expect(a.putOut, isNull);
    });

    test('a moderator removes a member, who leaves; a member can\'t remove anyone', () async {
      final o = owner.room(channel), a = ann.room(channel), b = bob.room(channel);
      for (final r in [o, a, b]) {
        await r.open();
      }
      await _settle();
      expect(b.remove(ann.id), isFalse);
      await o.setRole(bob.id, Role.moderator);
      await _settle();
      expect(b.remove(ann.id), isTrue);
      await _settle();
      expect(a.putOut, contains('removed'));
      // And she can't remove him back.
      expect(a.remove(bob.id), isFalse);
    });

    test('a ban keeps someone out for good: put out now, their messages not shown, refused next time', () async {
      final o = owner.room(channel), a = ann.room(channel), b = bob.room(channel);
      for (final r in [o, a, b]) {
        await r.open();
      }
      await _settle();
      expect(await o.ban(bob.id), isTrue);
      await _settle();
      expect(b.putOut, contains('banned'));
      expect(a.roster.banned, contains(bob.id));
      expect(b.send('let me back'), isFalse);
      await b.close();
      await _settle();
      final again = bob.room(channel);
      await again.open();
      expect(again.putOut, contains('banned'), reason: 'his own device kept the roster that bans him');
    });

    test('muted for everyone: a moderator\'s mute holds while they are there, an admin\'s stands in the roster', () async {
      final o = owner.room(channel), a = ann.room(channel), b = bob.room(channel);
      for (final r in [o, a, b]) {
        await r.open();
      }
      await _settle();
      await o.setRole(ann.id, Role.moderator);
      await _settle();
      expect(await a.muteForAll(bob.id, true), isTrue);
      await _settle();
      expect(o.heard(bob.id), isFalse);
      expect(b.heard(bob.id), isFalse, reason: 'his own device locks his microphone');
      await a.muteForAll(bob.id, false);
      await _settle();
      expect(o.heard(bob.id), isTrue);
      // The owner's mute is in the roster.
      expect(await o.muteForAll(bob.id, true), isTrue);
      await _settle();
      expect(a.roster.muted, contains(bob.id));
      expect(a.heard(bob.id), isFalse);
      // A moderator can't unmute what an admin muted in the roster: the roster still says so.
      await a.muteForAll(bob.id, false);
      await _settle();
      expect(o.heard(bob.id), isFalse);
    });

    test('an admin edits a role and adds one; the newcomers\' role can be changed', () async {
      final o = owner.room(channel), a = ann.room(channel);
      await o.open();
      await a.open();
      await _settle();
      expect(await o.saveRole(const Role(id: 'dj', name: 'DJ', rank: 15, perms: {Perm.speak, Perm.chat, Perm.video})), isTrue);
      expect(await o.setNewcomer('dj'), isTrue);
      await _settle();
      expect(a.roster.ranked.map((r) => r.name), ['Admin', 'Moderator', 'DJ', 'Member']);
      expect(a.roster.roleOf(ann.id).id, 'dj');
      expect(a.can(Perm.invite), isFalse);
      // Admin keeps every permission whatever is saved: every one a space of this kind has. Adding and managing files
      // are a Files space's alone (Perm.of, HangoutRoom.saveRole), so this voice space's admin is not given them; the
      // test asked for Perm.values from before those two were added.
      await o.saveRole(o.roster.roleById(Role.admin)!.copyWith(perms: {Perm.chat}));
      expect(o.roster.roleById(Role.admin)!.perms, Perm.of(channel.kind));
      expect(o.roster.roleById(Role.admin)!.perms.intersection(Perm.files), isEmpty);
      expect(await o.deleteRole('dj'), isFalse, reason: 'newcomers have it');
      await o.setNewcomer(Role.member);
      expect(await o.deleteRole('dj'), isTrue);
    });
  });
}
