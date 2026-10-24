// The service's word that something came for the account (lib/live/poke.dart, server/src/live.rs POKES), over a
// socket the test plays the relay through: the connection held while signed in with no room at all, let go signed
// out, local-only and behind; each poke turned into the fetch it asks for, a burst settled into one; a drop in front
// made up for on coming back; and a service from before pokes, which sends none, changing nothing.
import 'dart:convert';

// flutter_test's own, which it does not hand on.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/live/hub.dart';
import 'package:ghost_md/live/poke.dart';
import 'package:ghost_md/live/transport.dart';
import 'package:ghost_md/team/crdt.dart';

import '../support/fake_crypto.dart';

/// A socket that records what a device sends and lets the test play the relay.
class FakeSocket extends LiveSocket {
  FakeSocket(this.url) {
    made.add(this);
  }

  static List<FakeSocket> made = [];
  final String url;
  final List<Object?> sent = [];
  bool closed = false;

  @override
  void send(String text) => sent.add(jsonDecode(text));

  @override
  void close() => closed = true;

  // The relay's side.
  void opens() => onOpen?.call();
  void says(Map<String, Object?> frame) => onMessage?.call(jsonEncode(frame));
  void drops([int code = 1006]) => onClose?.call(code);

  /// Opened and signed in, as the relay answers a token it takes.
  void ready([int id = 1]) {
    opens();
    says({'t': 'ready', 'id': id});
  }
}

/// One device: its hub over [FakeSocket]s, the account's two switches, and what the pokes asked of it.
class Rig {
  Rig({bool signedIn = true}) : signedIn = ValueNotifier(signedIn) {
    FakeSocket.made = [];
    hub = LiveHub(LiveHubDeps(
      url: 'wss://example/live',
      token: () => this.signedIn.value ? 'tok' : null,
      crypto: FakeCrypto(),
      crdt: Crdt((command, [args = const {}]) async => throw UnsupportedError('no documents here')),
      connect: (events) => WebSocketTransport(url: 'wss://example/live', token: () => this.signedIn.value ? 'tok' : null, events: events, socket: FakeSocket.new, schedule: (run, ms) {
        retries.add(run);
        return null;
      }),
    ));
    pokes = Pokes(hub: hub);
    stop = pokes.watch(
      PokeHooks(
        sync: () async => synced += 1,
        meetings: () => read += 1,
      ),
      PokeWatch(signedIn: () => this.signedIn.value, localOnly: () => localOnly.value, changes: [this.signedIn, localOnly, session]),
    );
  }

  final ValueNotifier<bool> signedIn;
  final ValueNotifier<bool> localOnly = ValueNotifier(false);

  /// The account changing otherwise: a token renewed.
  final ValueNotifier<int> session = ValueNotifier(0);
  late final LiveHub hub;
  late final Pokes pokes;
  late final void Function() stop;
  final List<void Function()> retries = [];
  int synced = 0;
  int read = 0;

  FakeSocket get socket => FakeSocket.made.last;

  void poke(String what) => socket.says({'t': 'poke', 'what': what});

  void dispose() {
    stop();
    hub.dispose();
  }
}

void main() {
  test('signed in with nothing open and no organization, the device holds a socket; a poke is a fetch', () {
    fakeAsync((async) {
      final rig = Rig();
      expect(rig.hub.heldRooms(), isEmpty, reason: 'no note open, no organization');
      expect(FakeSocket.made, hasLength(1), reason: 'a socket all the same, for the pokes');
      rig.socket.ready();
      expect(rig.socket.sent, [
        {'t': 'auth', 'token': 'tok'},
      ], reason: 'it signs in and asks for no room');

      // A meeting's recording kept: the sync (its Meetings step files it) and the list, once the burst has settled.
      rig.poke('take');
      expect((rig.synced, rig.read), (0, 0), reason: 'settled first');
      async.elapse(const Duration(milliseconds: 399));
      expect((rig.synced, rig.read), (0, 0));
      async.elapse(const Duration(milliseconds: 1));
      expect((rig.synced, rig.read), (1, 1));

      // The list changed (the bot joining, in the call, a skip from the Mac): read again, once, and no sync.
      rig.poke('meet');
      rig.poke('meet');
      rig.poke('meet');
      async.elapse(const Duration(milliseconds: 400));
      expect((rig.synced, rig.read), (1, 2));

      // A mail: the sync, its Mail step.
      rig.poke('mail');
      async.elapse(const Duration(milliseconds: 400));
      expect((rig.synced, rig.read), (2, 2));

      // A burst of every kind is one sync and one read.
      rig
        ..poke('meet')
        ..poke('take')
        ..poke('mail')
        ..poke('meet');
      async.elapse(const Duration(milliseconds: 400));
      expect((rig.synced, rig.read), (3, 3));

      // A word from a newer service: the sync fetches whatever it is.
      rig.poke('something-new');
      async.elapse(const Duration(milliseconds: 400));
      expect((rig.synced, rig.read), (4, 3));
      rig.dispose();
    });
  });

  test('no socket signed out, nor local-only, nor while the app is behind; and back as each ends', () {
    fakeAsync((async) {
      final rig = Rig(signedIn: false);
      expect(rig.hub.connected, isFalse, reason: 'signed out: nothing is held');
      expect(FakeSocket.made, isEmpty);

      rig.signedIn.value = true;
      expect((rig.hub.connected, FakeSocket.made.length), (true, 1));
      rig.socket.ready();

      // Behind: the socket let go, and nothing knocks until the app is in front again.
      rig.hub.rest();
      expect(rig.socket.closed, isTrue);
      async.elapse(const Duration(minutes: 5));
      for (final retry in rig.retries) {
        retry();
      }
      expect(FakeSocket.made, hasLength(1), reason: 'no socket while behind');
      rig.hub.wake();
      expect(FakeSocket.made, hasLength(2));
      rig.socket.ready(2);
      // The app's own resume syncs (the engine's `resumed`); coming back to the front is no poke's to make up for.
      async.elapse(const Duration(seconds: 1));
      expect((rig.synced, rig.read), (0, 0));

      // Settings that keep everything on the device: let go.
      rig.localOnly.value = true;
      expect((rig.hub.connected, rig.socket.closed), (false, true));
      rig.localOnly.value = false;
      expect((rig.hub.connected, FakeSocket.made.length), (true, 3));

      // Signed out: let go, and a poke on the old socket asks nothing.
      final old = rig.socket..ready(3);
      rig.signedIn.value = false;
      expect((rig.hub.connected, old.closed), (false, true));
      rig.dispose();
    });
  });

  test('a room held is unchanged by the pokes, and the socket stays for the pokes when the last room goes', () {
    fakeAsync((async) {
      final rig = Rig();
      rig.socket.ready();
      rig.hub.holdRoom('note-1', const RoomFunctions());
      expect(rig.socket.sent.last, {'t': 'join', 'room': 'note-1'});
      rig.hub.releaseRoom('note-1');
      expect((rig.hub.connected, rig.socket.closed), (true, false), reason: 'the last room gone, the socket stays while signed in');
      rig.dispose();
      expect(rig.socket.closed, isTrue);
    });
  });

  test('a token the relay turns away is knocked with no more, until the account has a new one', () {
    fakeAsync((async) {
      final rig = Rig();
      rig.socket.ready();
      rig.socket.drops(closeSignIn);
      expect(rig.retries, isEmpty, reason: 'no point knocking with the same token');
      expect(FakeSocket.made, hasLength(1));
      // The session renewed: the account says it changed, and the socket is tried again with the token there is now.
      rig.session.value += 1;
      expect(FakeSocket.made, hasLength(2));
      rig.socket.ready(2);
      rig.poke('take');
      async.elapse(const Duration(milliseconds: 400));
      expect((rig.synced, rig.read), (1, 1));
      rig.dispose();
    });
  });

  test('a drop with the app in front is made up for once the socket is back: what came meanwhile is fetched', () {
    fakeAsync((async) {
      final rig = Rig();
      rig.socket.ready();
      rig.socket.drops();
      expect(rig.retries, hasLength(1));
      rig.retries.single();
      rig.socket.ready(2);
      async.elapse(const Duration(milliseconds: 400));
      expect((rig.synced, rig.read), (1, 1), reason: 'one sync and one read for whatever the pokes missed');
      rig.dispose();
    });
  });

  test('a service from before pokes sends none: nothing is fetched, and its frames read as they did', () {
    fakeAsync((async) {
      final heard = <String>[];
      FakeSocket.made = [];
      // The transport alone, with no poke listener, as every caller before the pokes made it.
      final t = WebSocketTransport(
        url: 'wss://example/live',
        token: () => 'tok',
        events: LiveEvents(
          ready: (id) => heard.add('ready $id'),
          joined: (room, first, peers, org) => heard.add('joined $room'),
          peers: (room, peers, org, left) => heard.add('peers $room $peers'),
          message: (room, from, data, org) => heard.add('msg $room $data'),
          down: (why) => heard.add('down $why'),
        ),
        socket: FakeSocket.new,
        schedule: (run, ms) => null,
      );
      final socket = FakeSocket.made.single..ready(4);
      // A poke reaching a caller that listens for none is nothing at all.
      socket.says({'t': 'poke', 'what': 'take'});
      t.join('note');
      socket.says({'t': 'joined', 'room': 'note', 'first': true, 'peers': 0});
      expect(heard, ['ready 4', 'joined note']);
      t.close();

      // And a device over an older service: held, signed in, told nothing, and so it fetches nothing until its passes.
      final rig = Rig();
      rig.socket.ready();
      rig.socket.says({'t': 'error', 'message': 'That frame could not be read.'});
      // A poke with no word, or not a word, is not one.
      rig.socket.says({'t': 'poke'});
      rig.socket.says({'t': 'poke', 'what': 7});
      async.elapse(const Duration(minutes: 5));
      expect((rig.synced, rig.read), (0, 0));
      rig.dispose();
    });
  });
}
