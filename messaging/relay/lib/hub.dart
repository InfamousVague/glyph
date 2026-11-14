import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'p256.dart';
import 'sha256.dart';

/// The hub: where two people's apps find each other through this server (Matt, 2026-11-14: "implement a full relay
/// system for the app that's replacable and swappable so that for right now we can use our servers to negotiate
/// calls through the app, video chats"). It is one of the app's routes (lib/net/hub_carrier.dart in the app), made
/// to be taken out and a peer-to-peer one put in its place: it holds no account, no name and no number.
///
/// - **Who someone is.** A key pair made on their phone. Their name here is the first 16 bytes of the SHA-256 of
///   the public key, in hex. To connect they sign a number the hub has just made up, so only the holder of the
///   private key connects under that name. One connection per name: a newer one replaces the older.
/// - **A packet to someone** is passed to them if they are connected. If not it is **held** (at most
///   [mailboxFrames] and [mailboxBytes] for one person, for [holdFor]) and handed over when they next connect. The
///   sender is told which happened. Held packets live in memory: a restart of the hub loses them, and the app's own
///   routes are what a sender falls back on (lib/net/switchboard.dart).
/// - **Who is here.** A connection may ask to be told when some names come and go (`watch`).
/// - **Rooms** (a voice room, a group): named by 32 hex digits with a token of 64, both made by its members from a
///   key only they hold; the first to name a room sets its token. Whoever holds the token may join and leave at any
///   time, is told who is in it, and what one member sends to the room goes to the others. A room nobody is in is
///   forgotten.
/// - **What it can see:** which names talk to which, when, and how much. Never what: packets are sealed by the apps
///   with keys the hub never has. It logs no addresses.
/// - **What it does not carry:** a call's sound and picture. Those go between the phones directly (or through a
///   media relay); the hub carries only what sets a call up.
class Hub {
  Hub({DateTime Function()? now, this.verbose = false, Random? random})
      : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  final bool verbose;
  final DateTime Function() _now;
  final Random _random;

  /// What is signed to connect: these words, then the hub's number.
  static const greeting = 'ghost-hub v1 ';

  static const maxPacket = 64 * 1024;
  static const mailboxFrames = 200;
  static const mailboxBytes = 1 << 20;
  static const holdFor = Duration(days: 7);
  static const maxRoom = 64;
  static const maxRooms = 50000;
  static const maxWatched = 500;
  static const authWait = Duration(seconds: 10);

  /// A packet to one person, and one to a room: the first byte of a binary message.
  static const toPeer = 1;
  static const toRoom = 2;

  final Map<String, _End> _here = {};
  final Map<String, List<_Held>> _mail = {};
  final Map<String, _Room> _rooms = {};
  final Map<String, Set<_End>> _watching = {};
  Timer? _sweeper;

  int get connected => _here.length;
  int get rooms => _rooms.length;
  int heldFor(String id) => _mail[id]?.length ?? 0;

  void start() => _sweeper ??= Timer.periodic(const Duration(minutes: 10), (_) => sweep());

  void stop() {
    _sweeper?.cancel();
    _sweeper = null;
    for (final end in _here.values.toList()) {
      end.ws.close(WebSocketStatus.goingAway);
    }
  }

  static final _hexOnly = RegExp(r'^[0-9a-f]+$');
  static bool _hex(Object? text, int length) => text is String && text.length == length && _hexOnly.hasMatch(text);
  static List<int> _unhex(String text) => [for (var i = 0; i + 1 < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)];

  /// The name a public key is known by here.
  static String nameOf(List<int> publicKey) => hexOf(sha256(publicKey).sublist(0, 16));

  void _say(String what) {
    // Never an address, never a whole name.
    if (verbose) stdout.writeln('${_now().toIso8601String()} hub $what');
  }

  void _tell(WebSocket? ws, Map<String, Object?> what) {
    if (ws == null || ws.readyState != WebSocket.open) return;
    try {
      ws.add(jsonEncode(what));
    } catch (_) {}
  }

  /// Takes a connection that asked for the hub (the relay hands over any address ending in `/hub`).
  Future<void> accept(HttpRequest request) async {
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      return;
    }
    ws.pingInterval = const Duration(seconds: 30);
    final nonce = [for (var i = 0; i < 32; i++) _random.nextInt(256)];
    _End? end;
    final waiting = Timer(authWait, () {
      if (end == null) ws.close(4401, 'no hello');
    });
    _tell(ws, {'hello': hexOf(nonce)});

    void leave() {
      waiting.cancel();
      final e = end;
      if (e == null) return;
      end = null;
      for (final room in e.rooms.toList()) {
        _leave(e, room);
      }
      for (final id in e.watches) {
        final set = _watching[id];
        set?.remove(e);
        if (set != null && set.isEmpty) _watching.remove(id);
      }
      if (!identical(_here[e.id], e)) return; // replaced by a newer connection under the same name
      _here.remove(e.id);
      for (final w in _watching[e.id] ?? const <_End>{}) {
        _tell(w.ws, {'went': e.id});
      }
      _say('${e.id.substring(0, 6)} left');
    }

    ws.listen((data) {
      final e = end;
      if (e == null) {
        // The first thing said: who this is, and the hub's number signed with their key.
        Map? hello;
        try {
          hello = data is String ? jsonDecode(data) as Map : null;
        } catch (_) {}
        List<int>? key, sig;
        try {
          key = base64Decode(hello?['key'] as String);
          sig = base64Decode(hello?['sig'] as String);
        } catch (_) {}
        final id = hello?['id'];
        if (key == null || sig == null || !_hex(id, 32) || nameOf(key) != id || !P256.verify(key, [...utf8.encode(greeting), ...nonce], sig)) {
          _tell(ws, {'ok': false, 'err': 'bad hello'});
          ws.close(4400, 'bad hello');
          return;
        }
        waiting.cancel();
        final made = _End(id as String, ws);
        _here[made.id]?.ws.close(4409, 'replaced');
        _here[made.id] = made;
        end = made;
        final held = _mail.remove(made.id) ?? const <_Held>[];
        final cutoff = _now().subtract(holdFor);
        final fresh = held.where((h) => h.at.isAfter(cutoff)).toList();
        _tell(ws, {'ok': true, 'held': fresh.length});
        for (final h in fresh) {
          ws.add(h.frame);
        }
        for (final w in _watching[made.id] ?? const <_End>{}) {
          _tell(w.ws, {'came': made.id});
        }
        _say('${made.id.substring(0, 6)} came${fresh.isEmpty ? '' : ', ${fresh.length} held'}');
        return;
      }
      if (data is List<int>) {
        _packet(e, data);
        return;
      }
      Map? said;
      try {
        said = jsonDecode(data as String) as Map;
      } catch (_) {}
      if (said == null) return;
      if (said.containsKey('ping')) {
        _tell(ws, {'pong': said['ping']});
      } else if (said['watch'] is List) {
        final ids = (said['watch'] as List).where((i) => _hex(i, 32)).cast<String>().take(maxWatched).toList();
        for (final id in ids) {
          if (e.watches.length >= maxWatched && !e.watches.contains(id)) break;
          e.watches.add(id);
          (_watching[id] ??= {}).add(e);
        }
        _tell(ws, {'here': [for (final id in ids) if (_here.containsKey(id)) id]});
      } else if (said.containsKey('join')) {
        _join(e, said['join'], said['token']);
      } else if (said.containsKey('leave')) {
        final room = said['leave'];
        if (room is String && e.rooms.contains(room)) _leave(e, room);
      }
    }, onDone: leave, onError: (_) => leave(), cancelOnError: true);
  }

  void _packet(_End from, List<int> data) {
    if (data.length > maxPacket + 32 || data.isEmpty) {
      from.ws.close(WebSocketStatus.messageTooBig, 'too big');
      return;
    }
    if (data[0] == toPeer && data.length > 21) {
      // [1][a number the sender made, 4 bytes][to, 16 bytes][the packet]
      final seq = ByteData.sublistView(Uint8List.fromList(data.sublist(1, 5))).getUint32(0);
      final to = hexOf(data.sublist(5, 21));
      final frame = Uint8List.fromList([toPeer, ..._unhex(from.id), ...data.sublist(21)]);
      final there = _here[to];
      if (there != null && there.ws.readyState == WebSocket.open) {
        there.ws.add(frame);
        _tell(from.ws, {'ack': seq, 'here': true});
        return;
      }
      final box = _mail[to] ??= [];
      final size = box.fold<int>(0, (n, h) => n + h.frame.length);
      if (box.length >= mailboxFrames || size + frame.length > mailboxBytes) {
        _tell(from.ws, {'nak': seq, 'err': 'full'});
        return;
      }
      box.add(_Held(frame, _now()));
      _tell(from.ws, {'ack': seq, 'here': false});
    } else if (data[0] == toRoom && data.length > 17) {
      // [2][the room, 16 bytes][the packet]: to everyone else in it.
      final name = hexOf(data.sublist(1, 17));
      final room = _rooms[name];
      if (room == null || !room.members.containsKey(from.id)) return;
      final frame = Uint8List.fromList([toRoom, ...data.sublist(1, 17), ..._unhex(from.id), ...data.sublist(17)]);
      for (final m in room.members.values) {
        if (!identical(m, from) && m.ws.readyState == WebSocket.open) m.ws.add(frame);
      }
    }
  }

  void _join(_End e, Object? name, Object? token) {
    if (!_hex(name, 32) || !_hex(token, 64)) {
      _tell(e.ws, {'room': name, 'ok': false, 'err': 'bad room'});
      return;
    }
    final hash = hexOf(sha256(utf8.encode(token as String)));
    var room = _rooms[name as String];
    if (room == null) {
      if (_rooms.length >= maxRooms) {
        _tell(e.ws, {'room': name, 'ok': false, 'err': 'full'});
        return;
      }
      room = _rooms[name] = _Room(hash);
    }
    if (room.hash != hash || (room.members.length >= maxRoom && !room.members.containsKey(e.id))) {
      _tell(e.ws, {'room': name, 'ok': false, 'err': room.hash != hash ? 'refused' : 'full'});
      return;
    }
    final others = room.members.keys.where((id) => id != e.id).toList();
    room.members[e.id] = e;
    e.rooms.add(name);
    _tell(e.ws, {'room': name, 'ok': true, 'members': others});
    for (final id in others) {
      _tell(room.members[id]?.ws, {'room': name, 'came': e.id});
    }
    _say('${e.id.substring(0, 6)} joined room ${name.substring(0, 6)} (${room.members.length} in it)');
  }

  void _leave(_End e, String name) {
    e.rooms.remove(name);
    final room = _rooms[name];
    if (room == null || !identical(room.members[e.id], e)) return;
    room.members.remove(e.id);
    if (room.members.isEmpty) {
      _rooms.remove(name);
    } else {
      for (final m in room.members.values) {
        _tell(m.ws, {'room': name, 'went': e.id});
      }
    }
    _say('${e.id.substring(0, 6)} left room ${name.substring(0, 6)}');
  }

  /// Forgets packets held longer than [holdFor].
  void sweep() {
    final cutoff = _now().subtract(holdFor);
    for (final id in _mail.keys.toList()) {
      final box = _mail[id]!..removeWhere((h) => !h.at.isAfter(cutoff));
      if (box.isEmpty) _mail.remove(id);
    }
  }
}

class _End {
  _End(this.id, this.ws);
  final String id;
  final WebSocket ws;
  final Set<String> rooms = {};
  final Set<String> watches = {};
}

class _Held {
  _Held(this.frame, this.at);
  final Uint8List frame;
  final DateTime at;
}

class _Room {
  _Room(this.hash);

  /// SHA-256 of the room's token, in hex.
  final String hash;
  final Map<String, _End> members = {};
}
