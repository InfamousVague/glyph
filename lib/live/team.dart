/// A room of an organization's on this device (docs/SHARED.md, S6; docs/LIVE.md, "The team's rooms"). A port of
/// `src/app/core/live/team.ts`.
///
/// A team note's room carries its document's changes between the members who have it open; the organization's own
/// carries only who is in the app and where. Both carry the awareness protocol (y-protocols): each device's state
/// (who it is, and its caret or its pointer) sent as it changes, and dropped the moment its connection leaves the
/// room.
///
/// Unlike an account's note (session.dart), a team note's document is never made in the room: it is the document
/// of record (lib/team/doc.dart), one lineage on every member's devices since the organization channel adopted it,
/// so the devices in a room trade only what each lacks (a state vector asked, the difference answered) and the
/// merge is exact. What arrives here is applied as the channel applies a log, and what is typed here goes out as
/// it is made; the channel still posts it to the log, so a member who was not in the room reads it on their next
/// pass.
///
/// What differs:
/// - The awareness is the Rust core's ([CrdtRoom]), a call away: what a room says and hears goes one at a time
///   behind [TeamRoom.sent], and everyone's state as last heard is kept here beside it ([TeamRoom.states], at
///   once), with [TeamRoom.onChange] for y-protocols' `change`.
/// - y-protocols says a device is still here every fifteen seconds and forgets one unheard for thirty, on a timer
///   of its own; the same timer is the room's ([RoomDeps.tick], three seconds; none in a test that gives none).
/// - `openTeamRoom` and `openPresenceRoom` read the page's modules; here they are [TeamRooms], made once with the
///   account.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../account/crypto_api.dart';
import '../team/crdt.dart';
import '../team/doc.dart';
import 'hub.dart';
import 'transport.dart';
import 'wire.dart';

/// The room name of an organization's own room: not a note id, which is what every other room is.
const String presenceRoom = 'presence';

/// The hues' angles, as ink.css sets them (`[data-hue]`, "the workspace hues").
const Map<String, int> hueAngles = {'ember': 32, 'amber': 75, 'moss': 150, 'sea': 230, 'violet': 295, 'rose': 355};

/// A hue as the CSS the page's carets are drawn with (`caretColours`): said in this device's presence exactly as
/// the page says it, since a member on the web draws this device's caret from these two strings.
({String color, String colorLight}) caretColours(String? hue) {
  final angle = hueAngles[hue];
  if (angle == null) return (color: 'var(--app-ink)', colorLight: 'color-mix(in oklch, var(--app-ink) 20%, transparent)');
  return (color: 'oklch(var(--app-hue-lift) var(--app-hue-chroma) $angle)', colorLight: 'oklch(var(--app-hue-lift) var(--app-hue-chroma) $angle / 0.24)');
}

/// What a device says of itself in a room's awareness (`Me`); y-codemirror's carets read `name`, `color` and
/// `colorLight`, and this app's read `name` and `hue`.
class Me {
  const Me({required this.name, this.hue});

  /// What a state's `user` holds, or null for one that names nobody.
  static Me? of(Object? user) {
    if (user is! Map) return null;
    final name = user['name'], hue = user['hue'];
    if (name is! String || name.isEmpty) return null;
    return Me(name: name, hue: hue is String ? hue : null);
  }

  final String name;

  /// One of the app's hues, or null for ink: what the member rows and the profile card read.
  final String? hue;

  Map<String, Object?> toJson() {
    final css = caretColours(hue);
    return {'name': name, 'hue': hue, 'color': css.color, 'colorLight': css.colorLight};
  }

  @override
  bool operator ==(Object other) => other is Me && other.name == name && other.hue == hue;

  @override
  int get hashCode => Object.hash(name, hue);
}

/// What a room stands on (`RoomDeps`).
class RoomDeps {
  const RoomDeps({required this.key, required this.crypto, required this.crdt, required this.hold, required this.release, this.doc, this.tick, this.catchUp = const Duration(milliseconds: catchUpMs)});

  final SealKey key;
  final AccountCrypto crypto;
  final Crdt crdt;

  /// The document carried over this room; none for the organization's own room.
  final TeamDoc? doc;

  /// The rooms: the hub's two ([LiveHub.holdRoom], [LiveHub.releaseRoom]).
  final LiveTransport Function(String room, RoomListener listener, String org) hold;
  final void Function(String room, String org) release;

  /// How often the awareness is looked over; null for never (a test's).
  final Duration? tick;
  final Duration catchUp;
}

/// How long a device that asked waits for an answer before it goes on without one.
const int catchUpMs = 2500;

final Random _random = Random.secure();

/// One room of an organization's (`TeamRoom`).
class TeamRoom implements RoomListener {
  TeamRoom(this.orgId, this.room, Me me, this._deps) : clientId = _deps.doc?.crdt.clientId ?? _random.nextInt(1 << 32) {
    _me = me;
    _states[clientId] = {'user': me.toJson()};
    _aware = _deps.crdt.room(clientId);
    unawaited(_aware.then<void>((_) {}, onError: (Object _) {}));
    // Before anything is sent: the room's first word of this device carries who it is.
    unawaited(_next((aware) async {
      await aware.setField('user', me.toJson());
    }).catchError((Object _) {}));
    _transport = _deps.hold(room, this, orgId);
    _stopUpdates = _deps.doc?.onUpdate((update) => _post(() async => Envelope(Kind.update, update)));
    final every = _deps.tick;
    if (every != null) _timer = Timer.periodic(every, (_) => _tick());
  }

  final String orgId;
  final String room;
  final RoomDeps _deps;

  /// This device in the room's awareness: its document's own client in a note's room.
  final int clientId;

  /// How many other devices are in the room.
  int others = 0;

  late Me _me;
  late final Future<CrdtRoom> _aware;
  late final LiveTransport _transport;
  void Function()? _stopUpdates;
  Timer? _timer;
  bool _closed = false;

  /// Outgoing messages, one after another: sealing is asynchronous, and the order they were made in is kept.
  Future<void> _sending = Future<void>.value();

  /// Incoming ones the same, so an answer to a query is never read before the state it follows; and everything
  /// asked of the awareness.
  Future<void> _receiving = Future<void>.value();
  Future<void> _ops = Future<void>.value();

  /// Which awareness clients each connection in the room spoke for: dropped with the connection when it leaves.
  final Map<int, Set<int>> _spokeFor = {};
  final Map<int, Map<String, Object?>> _states = {};
  final Set<void Function()> _listeners = {};

  /// Settled once the room has nothing to catch this device up on: alone in it, a state arrived, or long enough
  /// waited.
  final Completer<void> _settled = Completer<void>();
  Timer? _settleTimer;

  Future<T> _next<T>(Future<T> Function(CrdtRoom aware) op) {
    final done = _ops.then((_) async => op(await _aware));
    _ops = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  /// Everyone in the room as last heard, this device included, by awareness client: `user` ([Me]), `cursor`
  /// (`{anchor, head}`), `at` (presence.dart), `pointer` and `card` on a canvas.
  Map<int, Map<String, Object?>> get states => Map.unmodifiable(_states);

  /// What this device says of itself now.
  Map<String, Object?> get local => _states[clientId] ?? const {};

  Me get me => _me;

  /// Told when who is here, or what any of them says, is different (y-protocols `change`). Answers the way to stop
  /// hearing.
  void Function() onChange(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _told() {
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  /// Who this device is, said again: a colour picked while the room is open (`setMe`).
  void setMe(Me me) {
    _me = me;
    setField('user', me.toJson());
  }

  /// One field of what this device says of itself (`setLocalStateField`): `cursor`, `at`, `pointer`, `card`. Said to the
  /// room as it is set.
  void setField(String field, Object? value) {
    if (_closed) return;
    _states[clientId] = {...local, field: value};
    unawaited(_next((aware) async {
      final update = await aware.setField(field, value);
      if (update != null) _post(() async => Envelope(Kind.presence, update));
    }).catchError((Object _) {}));
    _told();
  }

  /// Settles once every message taken so far has been read and every message posted is sealed and handed to the
  /// transport: what a test of a room waits on.
  Future<void> sent() async {
    for (;;) {
      final receiving = _receiving, ops = _ops, sending = _sending;
      await receiving;
      await ops;
      await _deps.doc?.settled();
      await sending;
      if (identical(receiving, _receiving) && identical(ops, _ops) && identical(sending, _sending)) return;
    }
  }

  /// Settles once the others have had their say: alone in the room, or the first answer to this device's query
  /// applied, or [RoomDeps.catchUp] gone by without one; and at once when the room is closed. What a canvas waits
  /// on before seeding its structure from the words, so it does not seed over a structure about to arrive.
  Future<void> caughtUp() => _settled.future;

  void _settle() {
    if (!_settled.isCompleted) _settled.complete();
  }

  /// In the room, first or not, and again after a drop: say who this device is, and ask what the others have.
  @override
  void joined(bool first, int peers) {
    others = peers;
    if (peers == 0) {
      _forget();
      _settle();
      return;
    }
    _say();
    _post(() async => Envelope(Kind.query, await _vector()));
    _settleTimer ??= Timer(_deps.catchUp, _settle);
  }

  @override
  void peersChanged(int peers, [int? left]) {
    others = peers;
    if (left != null) _forget(left);
    if (peers == 0) _forget();
  }

  @override
  Future<void> message(int from, String data) {
    return _receiving = _receiving.then((_) => _take(from, data)).catchError((Object _) {});
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _settleTimer?.cancel();
    _timer?.cancel();
    _settle();
    _stopUpdates?.call();
    _listeners.clear();
    unawaited(_next((aware) => aware.close()).catchError((Object _) {}));
    _deps.release(room, orgId);
  }

  Future<void> _take(int from, String data) async {
    if (_closed) return;
    final Envelope envelope;
    try {
      envelope = await openTeamEnvelope(_deps.crypto, _deps.key, orgId, room, data);
    } catch (_) {
      // A message this device cannot read is one it should not act on: the wrong key, or sealed for another room.
      return;
    }
    if (_closed) return;
    final doc = _deps.doc;
    switch (envelope.kind) {
      case Kind.query:
        _say(from);
        if (doc == null) return;
        final theirs = envelope.bytes;
        _post(() async => Envelope(Kind.state, await doc.crdt.stateFor(theirs.isEmpty ? null : theirs)), from);
        // Their vector says they hold something this device lacks: ask them, now, rather than wait for a pass.
        if (await _deps.crdt.lacks(await _vector(), theirs)) _post(() async => Envelope(Kind.query, await _vector()), from);
      case Kind.state:
        try {
          await doc?.applyRemote([envelope.bytes]);
        } finally {
          _settle();
        }
      case Kind.update:
        await doc?.applyRemote([envelope.bytes]);
      case Kind.presence:
        await _heard(from, envelope.bytes);
    }
  }

  /// An awareness update from a connection in the room, applied and remembered as its, to drop the moment it leaves.
  Future<void> _heard(int from, Uint8List update) async {
    await _next((aware) async {
      final change = await aware.apply(update);
      final spoken = _spokeFor.putIfAbsent(from, () => <int>{});
      // A connection is one device, and a device is one client in a room: a new client from it (its document made
      // again after a reload) replaces the one it spoke for before, whose caret would otherwise stand where it was
      // left.
      final stale = change.added.isEmpty ? const <int>[] : [for (final id in spoken) if (!change.added.contains(id) && !change.touched.contains(id)) id];
      spoken
        ..addAll(change.added)
        ..addAll(change.touched);
      var gone = change.removed.isNotEmpty;
      if (stale.isNotEmpty) {
        spoken.removeAll(stale);
        gone = (await aware.remove(stale)).isNotEmpty || gone;
      }
      if (change.changed || gone) await _read(aware);
    });
  }

  /// Everyone's state, read from the core again, and the listeners told.
  Future<void> _read(CrdtRoom aware) async {
    final all = await aware.states();
    if (_closed) return;
    final mine = _states[clientId];
    _states
      ..clear()
      ..addEntries([for (final one in all) MapEntry(one.client, one.state)]);
    // What was said here and is still on its way to the core is not unsaid.
    if (mine != null) _states[clientId] = mine;
    _told();
  }

  void _tick() {
    if (_closed) return;
    unawaited(_next((aware) async {
      final ticked = await aware.tick();
      final update = ticked.update;
      if (update != null) _post(() async => Envelope(Kind.presence, update));
      if (ticked.removed.isNotEmpty) await _read(aware);
    }).catchError((Object _) {}));
  }

  /// This device's own state, to everyone, or to the one connection that asked.
  void _say([int? to]) {
    unawaited(_next((aware) async {
      final update = await aware.encode([clientId]);
      _post(() async => Envelope(Kind.presence, update), to);
    }).catchError((Object _) {}));
  }

  Future<Uint8List> _vector() async => await _deps.doc?.crdt.stateVector() ?? Uint8List(0);

  /// The states a connection spoke for, dropped; or, with no connection named, every other device's.
  void _forget([int? left]) {
    final gone = left == null ? [for (final id in _states.keys) if (id != clientId) id] : [...?_spokeFor[left]];
    if (left == null) {
      _spokeFor.clear();
    } else {
      _spokeFor.remove(left);
    }
    if (gone.isEmpty) return;
    for (final id in gone) {
      _states.remove(id);
    }
    _told();
    unawaited(_next((aware) async {
      await aware.remove(gone);
    }).catchError((Object _) {}));
  }

  void _post(Future<Envelope> Function() make, [int? to]) {
    if (_closed) return;
    _sending = _sending.then((_) async {
      final data = await sealTeamEnvelope(_deps.crypto, _deps.key, orgId, room, await make());
      if (!_closed) _transport.send(room, data, to: to, org: orgId);
    }).catchError((Object _) {});
  }
}

/// The rooms of the organizations this account is in (`openTeamRoom`, `openPresenceRoom`, `meIn`).
class TeamRooms {
  TeamRooms({required this.hub, required this.crypto, required this.crdt, required this.orgKeyOf, required this.handle, required this.colourIn, this.tick = const Duration(seconds: 3)});

  final LiveHub hub;
  final AccountCrypto crypto;
  final Crdt crdt;

  /// The organization key, if this device holds it (lib/orgs/org_keys.dart).
  final SealKey? Function(String orgId) orgKeyOf;

  /// The handle signed in, or null when signed out.
  final String? Function() handle;

  /// The colour this account wears in an organization (the override, else the account's), or null for ink.
  final String? Function(String orgId) colourIn;
  final Duration? tick;

  /// This account in an organization: its handle, and the colour it wears there (`meIn`).
  Me meIn(String orgId) => Me(name: handle() ?? '', hue: colourIn(orgId));

  TeamRoom? _open(String orgId, String room, TeamDoc? doc) {
    final key = orgKeyOf(orgId);
    if (key == null || handle() == null) return null;
    return TeamRoom(orgId, room, meIn(orgId), RoomDeps(key: key, crypto: crypto, crdt: crdt, doc: doc, hold: hub.holdRoom, release: hub.releaseRoom, tick: tick));
  }

  /// A team note's room, for its editor: the document's changes and the carets of the members who have it open.
  /// Null when this device cannot seal a word in it: signed out, or without the organization key yet.
  TeamRoom? openTeamRoom(String orgId, String noteId, TeamDoc doc) => _open(orgId, noteId, doc);

  /// The organization's own room: who is in the app and where (presence.dart holds one per organization).
  TeamRoom? openPresenceRoom(String orgId) => _open(orgId, presenceRoom, null);
}
