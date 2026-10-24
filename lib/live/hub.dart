/// Live sync's one connection on this device, shared by every room that is live on it (docs/LIVE.md). A port of
/// `src/app/core/live/hub.ts`.
///
/// Made when the first room opens, closed when the last one does, and the relay's messages handed to whoever has
/// the room: a note of the account's own ([LiveSession]), or a team's note, an organization's presence or its
/// `sync` room (lib/live/team.dart, presence.dart, nudge.dart; docs/SHARED.md, S6), which have rooms of the
/// organization's. And held with no room at all while [keepOpen] asks it to be (Matt, 2026-10-24: "meetings don't
/// load on the phone app right away I have to wait several minutes for them to sync"): the service's word that
/// something came for the account, a poke, reaches a signed-in socket in no room as well, and is handed to whoever
/// [listenPokes] (lib/live/poke.dart).
///
/// What differs:
/// - The page's module state (one transport, a map of rooms) is a [LiveHub] made once with the account
///   (lib/root/live_wiring.dart); two of them in one test are two devices.
/// - [LiveHub.wake] and [LiveHub.rest] pass the app's coming to the front and leaving it to the connection
///   (transport.dart says why a phone needs the second).
/// - What `openLive` read from the page's account, its switch and its crypto is in [LiveHubDeps].
library;

import '../account/crypto_api.dart';
import '../team/crdt.dart';
import 'session.dart';
import 'shared.dart';
import 'transport.dart';

/// What the pass sync knows that a joining note needs: whether it has unsent changes, and how to keep a copy
/// (`SyncHooks`).
class SyncHooks {
  const SyncHooks({required this.hasUnsynced, required this.keepCopy});
  final Future<bool> Function(String noteId) hasUnsynced;
  final Future<void> Function(String noteId, String words) keepCopy;
}

/// Whoever holds a room: told when it is joined, when the others come and go, and each sealed message.
abstract interface class RoomListener {
  void joined(bool first, int peers);

  /// How many others are in the room now; [left], the connection that just went, when one did.
  void peersChanged(int peers, [int? left]);
  Future<void> message(int from, String data);
}

/// A room held by functions: what the `sync` room and a test hand the hub.
class RoomFunctions implements RoomListener {
  const RoomFunctions({this.onJoined, this.onPeers, this.onMessage});
  final void Function(bool first, int peers)? onJoined;
  final void Function(int peers, int? left)? onPeers;
  final void Function(int from, String data)? onMessage;

  @override
  void joined(bool first, int peers) => onJoined?.call(first, peers);

  @override
  void peersChanged(int peers, [int? left]) => onPeers?.call(peers, left);

  @override
  Future<void> message(int from, String data) async => onMessage?.call(from, data);
}

/// What the hub reads of the device.
class LiveHubDeps {
  const LiveHubDeps({required this.url, required this.token, required this.crypto, required this.crdt, this.accountKey, this.enabled, this.shared, this.connect});

  /// The relay's address ([liveUrl] of the service's base).
  final String url;

  /// The session token now, or null when signed out.
  final String? Function() token;
  final AccountCrypto crypto;
  final Crdt crdt;

  /// The account key, for the account's own notes; null where this device cannot seal a word.
  final Future<SealKey?> Function()? accountKey;

  /// The switch (lib/live/enabled.dart); off where it is not given.
  final bool Function()? enabled;
  final SharedLive? shared;

  /// The connection, for tests; the relay's socket otherwise.
  final LiveTransport Function(LiveEvents events)? connect;
}

/// The one connection, and who holds each room on it.
class LiveHub {
  LiveHub(this.deps);

  final LiveHubDeps deps;
  LiveTransport? _transport;
  final Map<String, RoomListener> _rooms = {};
  bool _resting = false;

  /// Held with no room ([keepOpen]).
  bool _kept = false;

  /// The connection went while the app was in front (not let go by [rest]): the next `ready` is a coming back, after
  /// which whatever came meanwhile is fetched ([listenPokes]' `back`).
  bool _dropped = false;

  /// The relay turned the token away (it ran out, or the device was signed out): the transport knocks no more until
  /// it is woken, which [keepOpen] does when the account is signed in again.
  bool _refused = false;
  void Function(String what)? _poked;
  void Function()? _back;

  LiveTransport _connect() {
    final held = _transport;
    if (held != null) return held;
    final events = LiveEvents(
      // The connection id means something to the relay, which stamps it on messages; nothing here needs it. A coming
      // back after a drop is told, for whatever the pokes missed meanwhile.
      ready: (_) {
        _refused = false;
        if (!_dropped) return;
        _dropped = false;
        _back?.call();
      },
      joined: (room, first, peers, org) => _rooms[roomKey(room, org)]?.joined(first, peers),
      peers: (room, peers, org, left) => _rooms[roomKey(room, org)]?.peersChanged(peers, left),
      message: (room, from, data, org) => _rooms[roomKey(room, org)]?.message(from, data),
      // Nothing to do: the transport comes back by itself and rejoins, and each room catches up on `joined`. A drop in
      // front is remembered for the pokes; the app going behind is not one (the resume's own sync fetches).
      down: (why) {
        if (why == 'network' && !_resting) _dropped = true;
        if (why == 'signIn') _refused = true;
      },
      poke: (what) => _poked?.call(what),
    );
    final made = deps.connect?.call(events) ?? WebSocketTransport(url: deps.url, token: deps.token, events: events);
    if (_resting) made.rest();
    return _transport = made;
  }

  void _lastGone() {
    if (_rooms.isNotEmpty || _kept) return;
    _transport?.close();
    _transport = null;
  }

  /// A room held by [listener], on the one connection: the account's own, or an organization's with [org]. Answers
  /// the transport to send through. The connection goes with the last room, so a device with nothing open holds no
  /// socket (`holdRoom`).
  LiveTransport holdRoom(String room, RoomListener listener, [String? org]) {
    _rooms[roomKey(room, org)] = listener;
    final over = _connect();
    over.join(room, org);
    return over;
  }

  /// `releaseRoom`.
  void releaseRoom(String room, [String? org]) {
    if (_rooms.remove(roomKey(room, org)) == null) return;
    _transport?.leave(room, org);
    _lastGone();
  }

  /// Holds the connection with no room ([held] true), so the service's pokes reach this device while the app is in
  /// front and signed in with nothing open, or lets it go with the last room ([held] false). The rooms are as they
  /// were either way, and [rest] still lets the socket go while the app is behind.
  ///
  /// Asked again while held, as it is whenever the account changes: a connection the relay turned away for its token
  /// tries again, with the token there is now.
  void keepOpen(bool held) {
    if (_kept == held) {
      if (held && _refused && !_resting) {
        _refused = false;
        _transport?.wake();
      }
      return;
    }
    _kept = held;
    if (!held) {
      _lastGone();
      return;
    }
    final had = _transport;
    _connect();
    // Held already, but given up on (signed out when it last tried): tried again now, unless the app is behind.
    if (had != null && !_resting) {
      _refused = false;
      had.wake();
    }
  }

  /// Whether the connection is held with no room, for tests.
  bool get keptOpen => _kept;

  /// Whether there is a connection at all, for tests.
  bool get connected => _transport != null;

  /// [poked] is told each poke's word as it comes; [back], that the connection came back after a drop in front, when
  /// any poke meanwhile was missed. One listener; answers the way to stop.
  void Function() listenPokes({required void Function(String what) poked, required void Function() back}) {
    _poked = poked;
    _back = back;
    return () {
      if (identical(_poked, poked)) _poked = null;
      if (identical(_back, back)) _back = null;
    };
  }

  /// The rooms held right now, for tests (`heldRooms`).
  List<String> heldRooms() => _rooms.keys.toList();

  /// The app came back to the front, or the network did: the connection is tried now.
  void wake() {
    _resting = false;
    _transport?.wake();
  }

  /// The app left the front: no socket is held until [wake]. The rooms stay, and are joined again then.
  void rest() {
    _resting = true;
    _transport?.rest();
  }

  /// Makes a note live on this device, or answers null when it will not be: the switch is off, the device is
  /// signed out, or it does not hold the account key (it could not seal a word). [words] is the note as the editor
  /// has it now (`openLive`).
  Future<LiveSession?> openLive(String noteId, String words, SessionListener listener, SyncHooks hooks) async {
    if (!(deps.enabled?.call() ?? false) || deps.token() == null) return null;
    final key = await deps.accountKey?.call();
    if (key == null) return null;
    closeLive(noteId);
    // A LiveSession joins as it is made; the hub must know the room by then, so the entry is made first and
    // replaced by the session itself.
    final over = _connect();
    _rooms[roomKey(noteId)] = const RoomFunctions();
    final session = LiveSession(
      noteId,
      words,
      SessionDeps(transport: over, key: key, crypto: deps.crypto, crdt: deps.crdt, hasUnsynced: hooks.hasUnsynced, keepCopy: hooks.keepCopy, shared: deps.shared),
      listener,
    );
    _rooms[roomKey(noteId)] = session;
    return session;
  }

  /// Takes a note out of live sync. The connection goes with the last room (`closeLive`).
  void closeLive(String noteId) {
    final held = _rooms.remove(roomKey(noteId));
    if (held is LiveSession) held.close();
    _lastGone();
  }

  /// Every room let go and the connection closed: signing out, and the app's end.
  void dispose() {
    for (final held in _rooms.values.toList()) {
      if (held is LiveSession) held.close();
    }
    _rooms.clear();
    _kept = false;
    _poked = null;
    _back = null;
    _transport?.close();
    _transport = null;
  }
}
