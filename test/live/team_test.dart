// A team's rooms (lib/live/team.dart), the store of who is where (lib/live/presence.dart) and the word that there
// is something to fetch (lib/live/nudge.dart), with the real crypto, the real CRDT and its awareness over a relay
// in memory: the cases of the web's core/live/team.test.ts, presence.test.ts and nudge.test.ts.
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/live/hub.dart';
import 'package:ghost_md/live/nudge.dart';
import 'package:ghost_md/live/presence.dart';
import 'package:ghost_md/live/team.dart';
import 'package:ghost_md/live/transport.dart';
import 'package:ghost_md/live/wire.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';

import 'support.dart';

const String org = 'org-1';

void main() {
  late GhostCore core;
  late CoreCrypto crypto;
  late Crdt crdt;

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await openCore();
    crypto = CoreCrypto(core.invoke);
    crdt = Crdt(core.invoke);
  });
  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  /// A device's hub on the relay.
  LiveHub hubOn(Relay relay) => LiveHub(LiveHubDeps(url: 'ws://relay.test/live', token: () => 't', crypto: crypto, crdt: crdt, connect: relay.line));

  /// A team note's document on a device: seeded with words, or adopted from the organization's row.
  Future<TeamDoc> document(Object from) async {
    final docs = TeamDocs(crdt: crdt, store: MemoryDocs(), rest: const Duration(days: 1));
    return from is String ? (await docs.doc('n1', seedWords: from))! : docs.adopt('n1', from as Uint8List, 0);
  }

  TeamRoom open(Relay relay, SealKey key, String room, Me me, [TeamDoc? doc]) {
    final hub = hubOn(relay);
    final made = TeamRoom(org, room, me, RoomDeps(key: key, crypto: crypto, crdt: crdt, doc: doc, hold: hub.holdRoom, release: hub.releaseRoom, catchUp: const Duration(milliseconds: 50)));
    relay.waits.add(made.sent);
    return made;
  }

  /// The others in a room, by handle.
  Map<String, Map<String, Object?>> others(TeamRoom room) => {
        for (final MapEntry(key: client, value: state) in room.states.entries)
          if (client != room.clientId && Me.of(state['user']) != null) Me.of(state['user'])!.name: {'hue': Me.of(state['user'])!.hue, 'cursor': state['cursor'], 'at': state['at']},
      };

  group('a team note live between members', () {
    test('carries typing as it is made, and catches a device up both ways when it joins', () async {
      final relay = Relay();
      final key = await crypto.newOrgKey();
      final a = await document('Hello');
      // The note as the organization's row first had it: what every member's device adopted.
      final original = await a.snapshot();
      final roomA = open(relay, key, 'n1', const Me(name: 'matt', hue: 'rose'), a);
      await relay.settled();
      final b = await document(original);
      final roomB = open(relay, key, 'n1', const Me(name: 'sam', hue: 'sea'), b);
      await relay.settled();
      expect(roomA.others, 1);
      expect(roomB.others, 1);

      await a.edit([const CrdtEdit(5, insert: ' world')], base: a.rev);
      await relay.settled();
      expect(b.words, 'Hello world');
      await b.edit([const CrdtEdit(0, insert: 'Oh. ')], base: b.rev);
      await relay.settled();
      expect(a.words, 'Oh. Hello world');

      // lee's device was away with the note as it first was, and typed into it offline. Joining, it asks for what
      // it lacks and is asked for what the others lack, and all three agree without a pass.
      final c = await document(original);
      await c.edit([const CrdtEdit(2, insert: '-')]);
      final roomC = open(relay, key, 'n1', const Me(name: 'lee'), c);
      await relay.settled();
      expect(c.words, 'Oh. He-llo world');
      expect(a.words, 'Oh. He-llo world');
      expect(b.words, 'Oh. He-llo world');
      expect(roomA.others, 2);
      await roomC.caughtUp();
      roomA.close();
      roomB.close();
      roomC.close();
    }, skip: coreSkip);

    test('shows each member\'s caret in their colour with their handle, and drops it the moment their connection leaves', () async {
      final relay = Relay();
      final key = await crypto.newOrgKey();
      final a = await document('Hello world');
      final roomA = open(relay, key, 'n1', const Me(name: 'matt', hue: 'rose'), a);
      final b = await document(await a.snapshot());
      final roomB = open(relay, key, 'n1', const Me(name: 'sam', hue: 'sea'), b);
      final c = await document(await a.snapshot());
      final roomC = open(relay, key, 'n1', const Me(name: 'lee'), c);
      await relay.settled();
      expect(others(roomA).keys.toList()..sort(), ['lee', 'sam']);
      expect(others(roomB)['matt'], {'hue': 'rose', 'cursor': null, 'at': null});
      // What a member on the web draws this device's caret with: the page's own CSS, said as the page says it.
      final said = roomB.states.values.firstWhere((state) => (state['user'] as Map)['name'] == 'matt')['user'] as Map;
      expect(said['color'], 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 355)');
      expect(said['colorLight'], 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 355 / 0.24)');

      // matt's caret after "Hello", as the binding would say it: relative to the document, so it holds as words
      // change.
      final at = await a.crdt.relative(5);
      roomA.setField('cursor', {'anchor': at, 'head': at});
      await relay.settled();
      final seen = others(roomB)['matt']?['cursor'];
      expect(seen, isNotNull);
      expect(await b.crdt.caretIndexes(seen), (anchor: 5, head: 5));
      // Words typed before it on sam's device move it along.
      await b.edit([const CrdtEdit(0, insert: 'Oh. ')]);
      await relay.settled();
      expect(await b.crdt.caretIndexes(seen), (anchor: 9, head: 9));

      roomA.close();
      await relay.settled();
      expect(others(roomB).keys.toList(), ['lee']);
      expect(others(roomC).keys.toList(), ['sam']);
      expect(roomB.others, 1);
      roomB.close();
      roomC.close();
    }, skip: coreSkip);

    test('ignores a message it cannot open: sealed for another room, or under another key', () async {
      final relay = Relay();
      final key = await crypto.newOrgKey();
      final a = await document('Hello');
      final roomA = open(relay, key, 'n1', const Me(name: 'matt'), a);
      final b = await document(await a.snapshot());
      final roomB = open(relay, key, 'n1', const Me(name: 'sam'), b);
      await relay.settled();
      // A device that somehow sends into n1 what it sealed for n2, and one with another organization's key.
      final stray = await crdt.room(424242);
      final presence = Envelope(Kind.presence, await stray.setField('user', const Me(name: 'stranger').toJson()));
      final forN2 = await sealTeamEnvelope(crypto, key, org, 'n2', presence);
      final otherKey = await sealTeamEnvelope(crypto, await crypto.newOrgKey(), org, 'n1', presence);
      final forN2Update = await sealTeamEnvelope(crypto, key, org, 'n2', Envelope(Kind.update, await (await crdt.open(words: 'Not this')).snapshot()));
      await Future.wait([roomB.message(9, forN2), roomB.message(9, otherKey), roomB.message(9, forN2Update)]);
      await relay.settled();
      expect(others(roomB).keys.toList(), ['matt']);
      expect(b.words, 'Hello');
      // And the same word sealed for this room is heard.
      await roomB.message(9, await sealTeamEnvelope(crypto, key, org, 'n1', presence));
      await relay.settled();
      expect(others(roomB).keys.toList()..sort(), ['matt', 'stranger']);
      roomA.close();
      roomB.close();
    }, skip: coreSkip);
  });

  group('an organization\'s own room', () {
    test('says where each device is, and forgets a device with its connection', () async {
      final relay = Relay();
      final key = await crypto.newOrgKey();
      final roomA = open(relay, key, presenceRoom, const Me(name: 'matt', hue: 'rose'));
      final roomB = open(relay, key, presenceRoom, const Me(name: 'sam', hue: 'sea'));
      await relay.settled();
      const where = Whereabouts(note: 'n1', title: 'Roadmap');
      roomA.setField('at', where.toJson());
      await relay.settled();
      expect(others(roomB)['matt']?['at'], {'note': 'n1', 'title': 'Roadmap', 'kind': 'note', 'cursor': null, 'pointer': null});
      expect(others(roomA)['sam'], {'hue': 'sea', 'cursor': null, 'at': null});
      // A colour picked while the room is open.
      roomA.setMe(const Me(name: 'matt', hue: 'moss'));
      await relay.settled();
      expect(others(roomB)['matt']?['hue'], 'moss');
      roomA.close();
      await relay.settled();
      expect(others(roomB), isEmpty);
      roomB.close();
    }, skip: coreSkip);
  });

  group('what a room reads', () {
    test('knows when another device\'s state vector holds something this one lacks', () async {
      final a = await crdt.open(words: 'a');
      final b = await crdt.open(state: await a.snapshot());
      expect(await crdt.lacks(await a.stateVector(), await b.stateVector()), isFalse);
      await b.edit([const CrdtEdit(1, insert: 'b')]);
      expect(await crdt.lacks(await a.stateVector(), await b.stateVector()), isTrue);
      expect(await crdt.lacks(await b.stateVector(), await a.stateVector()), isFalse);
    }, skip: coreSkip);

    test('places a caret from the same lineage, and not one from another document', () async {
      final a = await crdt.open(words: 'Hello world');
      final caret = {'anchor': await a.relative(6), 'head': await a.relative(11)};
      expect(await a.caretIndexes(caret), (anchor: 6, head: 11));
      final b = await crdt.open(state: await a.snapshot());
      expect(await b.caretIndexes(caret), (anchor: 6, head: 11));
      final stranger = await crdt.open(words: 'Hello world');
      expect(await stranger.caretIndexes(caret), isNull);
      expect(await a.caretIndexes({'anchor': 'nonsense', 'head': null}), isNull);
    }, skip: coreSkip);
  });

  group('presence in an organization', () {
    test('holds the organization\'s own room for each organization joined with a key in hand, says where this device is even when said before the room came, and reads where the others are', () async {
      final relay = Relay();
      final key = await crypto.newOrgKey();
      final changes = ChangeNotifier();
      var signedIn = true, localOnly = false;
      final keys = <String>{};
      String? colour = 'rose';

      final hubA = hubOn(relay);
      final rooms = TeamRooms(hub: hubA, crypto: crypto, crdt: crdt, orgKeyOf: (id) => keys.contains(id) ? key : null, handle: () => signedIn ? 'matt' : null, colourIn: (_) => colour, tick: null);
      final presence = Presence(rooms);
      var told = 0;
      presence.addListener(() => told += 1);
      // Said before the room came.
      presence.announce('o1', const Whereabouts(note: 'n1', title: 'Roadmap'));
      final stop = presence.watch(PresenceWatch(signedIn: () => signedIn, localOnly: () => localOnly, joined: () => ['o1', 'o2'], hasKey: keys.contains, changes: [changes]));
      // No key yet: no room.
      expect(presence.heldPresence(), isEmpty);
      keys.add('o1');
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      changes.notifyListeners();
      expect(presence.heldPresence(), ['o1']);
      expect(hubA.heldRooms(), ['o1/presence']);

      // sam, on another device, in the same organization's room.
      final hubB = hubOn(relay);
      final sam = TeamRoom('o1', presenceRoom, const Me(name: 'sam', hue: 'sea'), RoomDeps(key: key, crypto: crypto, crdt: crdt, hold: hubB.holdRoom, release: hubB.releaseRoom));
      relay.waits.add(sam.sent);
      sam.setField('at', const Whereabouts(note: 'n2', title: 'Plan', kind: 'canvas', pointer: Spot(3, 4)).toJson());
      for (var i = 0; i < 5; i += 1) {
        await relay.settled();
        await pumpEventQueue();
      }
      final seen = presence.presenceIn('o1');
      expect([for (final each in seen) (each.handle, each.hue, each.at?.note, each.at?.title, each.at?.kind, each.at?.pointer?.x)], [('sam', 'sea', 'n2', 'Plan', 'canvas', 3.0)]);
      expect(told, greaterThan(0));
      final mine = sam.states.values.firstWhere((state) => (state['user'] as Map?)?['name'] == 'matt');
      expect((mine['at'] as Map)['title'], 'Roadmap');
      expect((mine['user'] as Map)['hue'], 'rose');

      // The colour worn is said again when it changes.
      colour = 'moss';
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      changes.notifyListeners();
      for (var i = 0; i < 3; i += 1) {
        await relay.settled();
        await pumpEventQueue();
      }
      expect((sam.states.values.firstWhere((state) => (state['user'] as Map?)?['name'] == 'matt')['user'] as Map)['hue'], 'moss');

      // Local-only, and it is let go; back, and signed out, the same.
      localOnly = true;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      changes.notifyListeners();
      expect(presence.heldPresence(), isEmpty);
      expect(presence.presenceIn('o1'), isEmpty);
      localOnly = false;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      changes.notifyListeners();
      expect(presence.heldPresence(), ['o1']);
      stop();
      expect(presence.heldPresence(), isEmpty);
      expect(hubA.heldRooms(), isEmpty);
      sam.close();
    }, skip: coreSkip);

    test('turns a hue into a caret\'s colours, and ink into the page\'s', () {
      expect(caretColours('sea'), (color: 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 230)', colorLight: 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 230 / 0.24)'));
      expect(caretColours(null).color, 'var(--app-ink)');
      expect(caretColours('nonsense').colorLight, 'color-mix(in oklch, var(--app-ink) 20%, transparent)');
    });
  });

  group('the word that there is something to fetch', () {
    late Relay relay;
    late LiveHub hub;
    late RelayLine line;
    late Set<String> keys;
    late int askedKeys, askedNotes;
    late void Function() onKeys;
    late Nudges nudges;
    late NudgeHooks hooks;
    final watch = NudgeWatch(signedIn: () => true, localOnly: () => false, joined: () => ['o1'], changes: const []);

    setUp(() {
      relay = Relay();
      hub = LiveHub(LiveHubDeps(url: 'ws://relay.test/live', token: () => 't', crypto: crypto, crdt: crdt, connect: (events) => line = relay.line(events)));
      keys = {};
      askedKeys = askedNotes = 0;
      onKeys = () {};
      nudges = Nudges(hub: hub, hasKey: keys.contains, settle: Duration.zero);
      hooks = NudgeHooks(
        keys: () async {
          askedKeys += 1;
          onKeys();
        },
        notes: () async => askedNotes += 1,
      );
    });

    Future<void> settled() async {
      await relay.settled();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await relay.settled();
    }

    /// Someone else in the organization's `sync` room.
    RelayLine other() {
      final line = relay.line(LiveEvents(ready: (_) {}, joined: (_, _, _, _) {}, peers: (_, _, _, _) {}, message: (_, _, _, _) {}, down: (_) {}));
      line.join('sync', 'o1');
      return line;
    }

    test('holds each joined organization\'s room, key or no key, and asks for the key when someone is there to give it', () async {
      final someone = other();
      final stop = nudges.watch(hooks, watch);
      expect(nudges.heldNudges(), ['o1']);
      await settled();
      // Its own keys step first (the key pair registered, a wrap read if one is there), then the question.
      expect(askedKeys, 1);
      expect(line.sent, ['sync@o1:$nudgeNeed']);
      // A wrap was made: the keys step again, which brings the key, and the team's notes are fetched.
      onKeys = () => keys.add('o1');
      someone.send('sync', nudgeKeys, org: 'o1');
      await settled();
      expect(askedKeys, 2);
      expect(askedNotes, greaterThanOrEqualTo(1));
      stop();
      expect(nudges.heldNudges(), isEmpty);
    }, skip: coreSkip);

    test('wraps for whoever asks when it holds the key and says so, fetches when told something changed, and tells when it wrote', () async {
      keys.add('o1');
      final stop = nudges.watch(hooks, watch);
      final someone = other();
      await settled();
      final fetched = askedNotes;
      someone.send('sync', nudgeNeed, org: 'o1');
      await settled();
      expect(askedKeys, 1);
      expect(line.sent, ['sync@o1:$nudgeKeys']);
      someone.send('sync', nudgeChanged, org: 'o1');
      someone.send('sync', nudgeChanged, org: 'o1');
      await settled();
      expect(askedNotes, fetched + 1);
      nudges.tellChanged('o1');
      nudges.tellChanged('o9');
      expect(line.sent, ['sync@o1:$nudgeKeys', 'sync@o1:$nudgeChanged']);
      stop();
    }, skip: coreSkip);
  });
}
