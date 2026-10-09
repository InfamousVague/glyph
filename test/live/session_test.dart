// One note live on an account's own devices (lib/live/session.dart, lib/live/hub.dart), with the real crypto and
// the real CRDT over a relay in memory: the cases of the web's core/live/session.test.ts, session.rules.test.ts
// and hub.test.ts.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/live/hub.dart';
import 'package:ghost_md/live/session.dart';
import 'package:ghost_md/live/shared.dart';
import 'package:ghost_md/live/transport.dart';
import 'package:ghost_md/live/wire.dart';
import 'package:ghost_md/team/crdt.dart';

import 'support.dart';

class Opened {
  late LiveSession session;
  String? ready;
  final List<String> copies = [];
  final List<int> peers = [];
  late RelayLine line;
}

/// A transport that records what a session asked of it, and lets the test speak as the relay.
class Recorded implements LiveTransport {
  final List<String> asked = [];
  final List<({String data, int? to})> sent = [];

  @override
  void join(String room, [String? org]) => asked.add('join $room');

  @override
  void leave(String room, [String? org]) => asked.add('leave $room');

  @override
  void send(String room, String data, {int? to, String? org}) => sent.add((data: data, to: to));

  @override
  void wake() {}

  @override
  void rest() {}

  @override
  void close() {}
}

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

  Future<SealKey> accountKey() async => crypto.settle(await crypto.newAccountKey());

  Opened open(Relay relay, SealKey key, String words, {bool unsynced = false, SharedLive? shared}) {
    final opened = Opened();
    late final LiveSession session;
    opened.line = relay.line(LiveEvents(
      ready: (_) {},
      joined: (room, first, peers, org) => session.joined(first, peers),
      peers: (room, peers, org, left) => session.peersChanged(peers, left),
      message: (room, from, data, org) => session.message(from, data),
      down: (_) {},
    ));
    session = LiveSession(
      'note-1',
      words,
      SessionDeps(transport: opened.line, key: key, crypto: crypto, crdt: crdt, hasUnsynced: (_) async => unsynced, keepCopy: (_, kept) async => opened.copies.add(kept), shared: shared, schedule: (run, ms) => null),
      SessionListener(ready: (shown) => opened.ready = shown, peers: opened.peers.add),
    );
    opened.session = session;
    relay.waits.add(session.sent);
    return opened;
  }

  /// A key pressed on a device: [insert] at [index], with [remove] taken first.
  Future<void> type(Opened on, int index, String insert, {int remove = 0}) => on.session.edit([CrdtEdit(index, remove: remove, insert: insert)], base: on.session.rev);

  group('a note live on two devices', () {
    test('is made by the first device and adopted by the second, never built twice', () async {
      final relay = Relay();
      final key = await accountKey();
      final phone = open(relay, key, 'Groceries\n- milk');
      await relay.settled();
      final mac = open(relay, key, 'Groceries\n- milk');
      await relay.settled();
      expect(phone.ready, 'Groceries\n- milk');
      expect(mac.ready, 'Groceries\n- milk');
      // The trap this avoids: two documents each built from the same words, merged, hold the words twice.
      expect(mac.session.words, 'Groceries\n- milk');
      expect(mac.session.seed, phone.session.seed);
    }, skip: coreSkip);

    test('carries typing both ways, a character at a time', () async {
      final relay = Relay();
      final key = await accountKey();
      final phone = open(relay, key, 'Groceries');
      await relay.settled();
      final mac = open(relay, key, 'Groceries');
      await relay.settled();
      final heard = <String>[];
      mac.session.onSplice((splice) => heard.add('${splice.at}:${splice.removed}:${splice.inserted}'));
      var at = 9;
      for (final rune in '\n- milk 🥛'.runes) {
        final char = String.fromCharCode(rune);
        await type(phone, at, char);
        at += char.length;
      }
      await relay.settled();
      expect(mac.session.words, 'Groceries\n- milk 🥛');
      expect(heard.first, '9:0:\n');
      await type(mac, 0, '# ');
      await relay.settled();
      expect(phone.session.words, '# Groceries\n- milk 🥛');
    }, skip: coreSkip);

    test('keeps both people typing into the same spot at the same moment', () async {
      final relay = Relay();
      final key = await accountKey();
      final phone = open(relay, key, 'ab');
      await relay.settled();
      final mac = open(relay, key, 'ab');
      await relay.settled();
      // Neither has heard the other yet.
      final one = type(phone, 1, 'PHONE');
      final two = type(mac, 1, 'MAC');
      await Future.wait([one, two]);
      await relay.settled();
      expect(phone.session.words, mac.session.words);
      expect(phone.session.words, contains('PHONE'));
      expect(phone.session.words, contains('MAC'));
      expect(phone.session.words, hasLength(10));
    }, skip: coreSkip);

    test('adopts the room when this device was only behind, and keeps no copy', () async {
      final relay = Relay();
      final key = await accountKey();
      open(relay, key, 'new words');
      await relay.settled();
      final mac = open(relay, key, 'old words');
      await relay.settled();
      expect(mac.ready, 'new words');
      expect(mac.copies, isEmpty);
    }, skip: coreSkip);

    test('keeps this device\'s own unsent changes as a copy, rather than losing them or undoing the room', () async {
      final relay = Relay();
      final key = await accountKey();
      final phone = open(relay, key, 'the room');
      await relay.settled();
      final mac = open(relay, key, 'typed offline', unsynced: true);
      await relay.settled();
      expect(mac.ready, 'the room');
      expect(mac.copies, ['typed offline']);
      expect(phone.session.words, 'the room');
    }, skip: coreSkip);

    test('makes the document itself when everyone else left before answering', () async {
      final relay = Relay();
      final key = await accountKey();
      final shared = SharedLive();
      // Someone is in the room who will never answer: a device with another key.
      final silent = open(relay, await accountKey(), 'x');
      await relay.settled();
      final mac = open(relay, key, 'mine', shared: shared);
      await relay.settled();
      expect(mac.session.state, SessionState.waiting);
      expect(mac.ready, isNull);
      silent.session.close();
      await relay.settled();
      expect(mac.session.state, SessionState.ready);
      expect(mac.ready, 'mine');
      // Alone in it: the pass sync need not leave the note alone.
      expect(shared.isShared('note-1'), isFalse);
      open(relay, key, 'mine');
      await relay.settled();
      expect(shared.isShared('note-1'), isTrue);
      mac.session.close();
      expect(shared.isShared('note-1'), isFalse);
    }, skip: coreSkip);

    test('ignores a message it cannot open', () async {
      final relay = Relay();
      final key = await accountKey();
      final phone = open(relay, key, 'words');
      await relay.settled();
      await phone.session.message(9, 'not-a-sealed-message');
      await phone.session.message(9, await sealEnvelope(crypto, await accountKey(), 'note-1', Envelope(Kind.update, Uint8List.fromList([1]))));
      await relay.settled();
      expect(phone.session.words, 'words');
      expect(phone.session.state, SessionState.ready);
    }, skip: coreSkip);
  });

  group('the rules of a session', () {
    ({LiveSession session, Recorded transport, List<void Function()> retries, List<String> ready}) alone(SealKey key, String words) {
      final transport = Recorded();
      final retries = <void Function()>[];
      final ready = <String>[];
      final session = LiveSession(
        'note-1',
        words,
        SessionDeps(
          transport: transport,
          key: key,
          crypto: crypto,
          crdt: crdt,
          hasUnsynced: (_) async => false,
          keepCopy: (_, kept) async {},
          schedule: (run, ms) {
            retries.add(run);
            return null;
          },
        ),
        SessionListener(ready: ready.add, peers: (_) {}),
      );
      return (session: session, transport: transport, retries: retries, ready: ready);
    }

    Future<List<int>> kinds(SealKey key, Recorded transport) async => [for (final sent in transport.sent) (await openEnvelope(crypto, key, 'note-1', sent.data)).kind];

    test('asks three times and then makes the document itself, when nobody else is in the room', () async {
      final key = await accountKey();
      final (:session, :transport, :retries, :ready) = alone(key, 'mine');
      session.joined(false, 1);
      // The one who was there goes without a word; the count says so only later.
      for (var i = 0; i < 3; i += 1) {
        await session.sent();
        retries.removeAt(0)();
      }
      await session.sent();
      expect(await kinds(key, transport), [Kind.query, Kind.query, Kind.query]);
      expect(session.state, SessionState.waiting);
      session.peersChanged(0);
      expect(session.state, SessionState.ready);
      expect(ready, ['mine']);
    }, skip: coreSkip);

    test('stays out of the room when somebody is there who will not answer, rather than risk a second history', () async {
      final key = await accountKey();
      final (:session, transport: _, :retries, :ready) = alone(key, 'mine');
      session.joined(false, 1);
      for (var i = 0; i < 3; i += 1) {
        retries.removeAt(0)();
      }
      expect(retries, isEmpty);
      expect(session.state, SessionState.waiting);
      expect(ready, isEmpty);
    }, skip: coreSkip);

    test('answers a question with its document, to the one who asked and nobody else', () async {
      final key = await accountKey();
      final (:session, :transport, retries: _, ready: _) = alone(key, 'mine');
      session.joined(true, 0);
      await session.message(4, await sealEnvelope(crypto, key, 'note-1', const Envelope(Kind.query)));
      await session.sent();
      expect(transport.sent, hasLength(1));
      expect(transport.sent.single.to, 4);
      final answer = await openEnvelope(crypto, key, 'note-1', transport.sent.single.data);
      expect(answer.kind, Kind.state);
      expect(unpackState(answer.bytes).seed, session.seed);
    }, skip: coreSkip);

    test('trades whole documents with the room when it comes back after a drop', () async {
      final key = await accountKey();
      final (:session, :transport, retries: _, ready: _) = alone(key, 'mine');
      session.joined(true, 0);
      // Alone again after a drop: the document here is the room's, and nothing is said.
      session.joined(true, 0);
      await session.sent();
      expect(transport.sent, isEmpty);
      session.joined(false, 1);
      await session.sent();
      expect(await kinds(key, transport), [Kind.query, Kind.state]);
      expect([for (final sent in transport.sent) sent.to], [null, null]);
    }, skip: coreSkip);

    test('merges a document from its own history, and ends rather than merge one from another', () async {
      final key = await accountKey();
      final (:session, :transport, retries: _, ready: _) = alone(key, 'mine');
      session.joined(true, 0);
      await session.sent();
      // The same seed, with a change this device has not seen.
      final other = await crdt.open();
      final asked = (session: session, transport: transport);
      session.joined(false, 1);
      await session.sent();
      final whole = unpackState((await openEnvelope(crypto, key, 'note-1', asked.transport.sent.last.data)).bytes);
      await other.applyRemote([whole.state]);
      await other.edit([const CrdtEdit(4, insert: ' and theirs')]);
      await session.message(2, await sealEnvelope(crypto, key, 'note-1', Envelope(Kind.state, packState(session.seed!, await other.snapshot()))));
      await session.sent();
      expect(session.words, 'mine and theirs');
      expect(session.state, SessionState.ready);
      // Another seed: the room was made again while this device was away.
      await session.message(2, await sealEnvelope(crypto, key, 'note-1', Envelope(Kind.state, packState(newSeed(), await other.snapshot()))));
      await session.sent();
      expect(session.state, SessionState.closed);
      await other.close();
    }, skip: coreSkip);

    test('a session that has ended leaves the room, sends nothing more, and takes no more messages', () async {
      final key = await accountKey();
      final (:session, :transport, retries: _, ready: _) = alone(key, 'mine');
      session.joined(true, 0);
      await session.sent();
      session.close();
      expect(transport.asked, ['join note-1', 'leave note-1']);
      await session.edit([const CrdtEdit(0, insert: 'x')], base: 0);
      await session.message(4, await sealEnvelope(crypto, key, 'note-1', const Envelope(Kind.query)));
      await session.sent();
      expect(transport.sent, isEmpty);
      session.close();
      expect(transport.asked, hasLength(2));
    }, skip: coreSkip);
  });

  group('a note made live', () {
    late List<({LiveEvents events, List<String> joined, List<bool> closed})> connections;
    late SealKey? key;
    late String? token;
    late bool enabled;
    late LiveHub hub;

    setUp(() async {
      if (!coreBuilt) return;
      connections = [];
      key = await accountKey();
      token = 't1';
      enabled = true;
      hub = LiveHub(LiveHubDeps(
        url: liveUrl('http://127.0.0.1:1/api'),
        token: () => token,
        crypto: crypto,
        crdt: crdt,
        accountKey: () async => key,
        enabled: () => enabled,
        connect: (events) {
          final made = (events: events, joined: <String>[], closed: <bool>[]);
          connections.add(made);
          return _Stand(made.joined, made.closed);
        },
      ));
    });

    const hooks = SyncHooks(hasUnsynced: _never, keepCopy: _nothing);
    ({SessionListener listener, List<String> ready, List<int> peers}) listener() {
      final ready = <String>[], peers = <int>[];
      return (listener: SessionListener(ready: ready.add, peers: peers.add), ready: ready, peers: peers);
    }

    test('is not, with the switch off, signed out, or without the key to seal a word', () async {
      enabled = false;
      expect(await hub.openLive('a', 'words', listener().listener, hooks), isNull);
      enabled = true;
      token = null;
      expect(await hub.openLive('a', 'words', listener().listener, hooks), isNull);
      token = 't1';
      key = null;
      expect(await hub.openLive('a', 'words', listener().listener, hooks), isNull);
      expect(connections, isEmpty);
    }, skip: coreSkip);

    test('shares one connection with every other live note, and hears only its own room', () async {
      final one = listener(), two = listener();
      final a = await hub.openLive('a', 'words of a', one.listener, hooks);
      final b = await hub.openLive('b', 'words of b', two.listener, hooks);
      expect(connections, hasLength(1));
      expect(connections[0].joined, ['a', 'b']);
      connections[0].events.joined('b', true, 0, null);
      expect(b?.state, SessionState.ready);
      expect(a?.state, SessionState.joining);
      expect(two.ready, ['words of b']);
      connections[0].events.peers('a', 2, null, null);
      expect(one.peers, [2]);
      expect(two.peers, [0]);
      hub.closeLive('a');
      hub.closeLive('b');
    }, skip: coreSkip);

    test('opened again, closes the session it had', () async {
      final first = await hub.openLive('a', 'words', listener().listener, hooks);
      final second = await hub.openLive('a', 'words', listener().listener, hooks);
      expect(first?.state, SessionState.closed);
      expect(second?.state, SessionState.joining);
      hub.closeLive('a');
    }, skip: coreSkip);

    test('holds an organization\'s room on the same connection, told apart from the account\'s own of that name', () async {
      final heard = <String>[];
      final room = RoomFunctions(
        onJoined: (first, peers) => heard.add('joined first=$first peers=$peers'),
        onPeers: (peers, left) => heard.add('peers $peers left=$left'),
        onMessage: (from, data) => heard.add('msg $from $data'),
      );
      hub.holdRoom('n', room, 'org-1');
      final own = await hub.openLive('n', 'words', listener().listener, hooks);
      expect(connections, hasLength(1));
      expect(connections[0].joined, ['org-1/n', 'n']);
      expect(hub.heldRooms(), ['org-1/n', 'n']);
      connections[0].events.joined('n', false, 2, 'org-1');
      connections[0].events.peers('n', 1, 'org-1', 9);
      connections[0].events.message('n', 9, 'sealed', 'org-1');
      // The account's own room of the same name hears none of it.
      connections[0].events.joined('n', true, 0, null);
      expect(heard, ['joined first=false peers=2', 'peers 1 left=9', 'msg 9 sealed']);
      expect(own?.state, SessionState.ready);
      hub.releaseRoom('n', 'org-1');
      expect(connections[0].joined, ['n']);
      expect(connections[0].closed, isEmpty);
      hub.closeLive('n');
      expect(connections[0].closed, [true]);
      // Releasing a room not held does nothing, and the last release takes the connection down.
      hub.releaseRoom('n', 'org-1');
      hub.holdRoom('p', room, 'org-1');
      expect(connections, hasLength(2));
      hub.releaseRoom('p', 'org-1');
      expect(connections[1].closed, [true]);
    }, skip: coreSkip);

    test('leaves the connection up while any note is live, and takes it down with the last', () async {
      await hub.openLive('a', 'words', listener().listener, hooks);
      await hub.openLive('b', 'words', listener().listener, hooks);
      hub.closeLive('a');
      expect(connections[0].closed, isEmpty);
      hub.closeLive('b');
      expect(connections[0].closed, [true]);
      // The next live note has a connection of its own.
      await hub.openLive('c', 'words', listener().listener, hooks);
      expect(connections, hasLength(2));
      hub.closeLive('c');
    }, skip: coreSkip);
  });
}

Future<bool> _never(String _) async => false;
Future<void> _nothing(String _, String _) async {}

/// A connection that records what it was asked.
class _Stand implements LiveTransport {
  _Stand(this.joined, this.closed);
  final List<String> joined;
  final List<bool> closed;

  @override
  void join(String room, [String? org]) => joined.add(roomKey(room, org));

  @override
  void leave(String room, [String? org]) => joined.remove(roomKey(room, org));

  @override
  void send(String room, String data, {int? to, String? org}) {}

  @override
  void wake() {}

  @override
  void rest() {}

  @override
  void close() => closed.add(true);
}
