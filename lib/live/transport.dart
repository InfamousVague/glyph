/// How live sync's sealed messages travel (docs/LIVE.md, "The transport"). A port of
/// `src/app/core/live/transport.ts`.
///
/// One interface, so the relay is one way to carry them and a peer-to-peer channel can be another later: nothing
/// above this file knows which it has. [WebSocketTransport] is the relay: one socket per device, signed in with
/// its first frame, its rooms rejoined whenever it comes back.
///
/// What differs:
/// - The page listens to its window for the network and the page coming back; a phone's app is told by whoever
///   watches its lifecycle (lib/root), through [LiveTransport.wake] and [LiveTransport.rest]. **[rest] has no
///   counterpart**: a browser drops a hidden page's socket by itself in time, and a phone's app in the background
///   should hold none, so the socket is let go and nothing knocks until [wake].
/// - The socket is `dart:io`'s ([ioLiveSocket]); a test hands in its own ([LiveSocket]).
/// - Every listener is told by events in a [LiveEvents] of functions, as the page's object of them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// What the relay says (`LiveEvents`).
class LiveEvents {
  const LiveEvents({required this.ready, required this.joined, required this.peers, required this.message, required this.down});

  /// Signed in: this socket's connection id, which is what `from` means on a message.
  final void Function(int id) ready;

  /// In a room. `first`: the room was empty until now, so this device makes the document (LIVE.md, Seeding).
  final void Function(String room, bool first, int peers, String? org) joined;

  /// Another device came into a room or left it: how many others are there now, and which connection left, if one
  /// did.
  final void Function(String room, int peers, String? org, int? left) peers;

  /// A sealed message from another device, not yet opened.
  final void Function(String room, int from, String data, String? org) message;

  /// The connection is gone. `signIn`: the relay refused the token, so there is no point trying again until it
  /// changes. `network` otherwise.
  final void Function(String why) down;
}

/// The rooms, each the account's own or an organization's (docs/SHARED.md, S6: `org` names whose, and the relay
/// checks the device's account is a member). Every event about an organization's room carries its `org` back.
abstract interface class LiveTransport {
  void join(String room, [String? org]);
  void leave(String room, [String? org]);

  /// To every other device in the room, or to one of them. Dropped while disconnected: a room is whole again on
  /// rejoin.
  void send(String room, String data, {int? to, String? org});

  /// Now rather than after the backoff: the app came back to the front, or the network did.
  void wake();

  /// The app left the front: the socket is let go, the rooms remembered, and nothing knocks until [wake].
  void rest();

  void close();
}

/// A room's key on this side: the organization's id and the room, or the room alone for the account's own.
String roomKey(String room, [String? org]) => org != null && org.isNotEmpty ? '$org/$room' : room;

/// The relay's address, from the service's: `https://attack.fm/api` becomes `wss://attack.fm/api/v1/live`.
String liveUrl(String apiBase) => '${apiBase.replaceFirstMapped(RegExp(r'^http(s?)://'), (found) => 'ws${found[1]}://')}/v1/live';

/// The close code the relay sends when the token is refused or has run out (server/src/live.rs CLOSE_AUTH).
const int closeSignIn = 4401;

/// Waits between attempts: quick at first, since a phone on a train drops and comes back often, then no faster
/// than this.
const int firstWaitMs = 500;
const int longestWaitMs = 30000;

/// A socket as the transport drives one: the page's `WebSocket`, the four handlers and two calls of it.
abstract class LiveSocket {
  void Function()? onOpen;
  void Function(Object? data)? onMessage;
  void Function(int? code)? onClose;

  void send(String text);
  void close();
}

/// `dart:io`'s socket to [url]. A connection that never opens is a close, as the page's is.
class _IoSocket extends LiveSocket {
  _IoSocket(String url) {
    WebSocket.connect(url).then((socket) {
      if (_closed) {
        socket.close();
        return;
      }
      _socket = socket;
      socket.listen((data) => onMessage?.call(data), onError: (Object _) {}, onDone: () => onClose?.call(socket.closeCode), cancelOnError: false);
      onOpen?.call();
    }, onError: (Object _) {
      if (!_closed) onClose?.call(null);
    });
  }

  WebSocket? _socket;
  bool _closed = false;

  @override
  void send(String text) => _socket?.add(text);

  @override
  void close() {
    _closed = true;
    _socket?.close();
  }
}

/// The real socket.
LiveSocket ioLiveSocket(String url) => _IoSocket(url);

/// The relay (`WebSocketTransport`).
class WebSocketTransport implements LiveTransport {
  /// [token] is the session token now, or null when signed out: read at every connect, so a renewed token is
  /// picked up. [socket], [schedule] and [random] are a test's.
  WebSocketTransport({required this.url, required this.token, required this.events, LiveSocket Function(String url)? socket, this.schedule, double Function()? random})
      : _make = socket ?? ioLiveSocket,
        _random = random ?? Random().nextDouble {
    _connect();
  }

  final String url;
  final String? Function() token;
  final LiveEvents events;

  /// When to try again, so a test need not wait out real backoff. Answers something to cancel it by, or nothing.
  final Object? Function(void Function() run, int ms)? schedule;
  final LiveSocket Function(String url) _make;
  final double Function() _random;

  LiveSocket? _socket;
  bool _open = false;
  bool _closed = false;
  bool _resting = false;
  int _attempt = 0;
  Object? _retry;

  /// The rooms joined, by key, with the frame that joins each: sent again whenever the socket comes back.
  final Map<String, ({String room, String? org})> _rooms = {};

  static Map<String, Object?> _about(String t, String room, String? org) => {'t': t, 'room': room, if (org != null && org.isNotEmpty) 'org': org};

  @override
  void join(String room, [String? org]) {
    _rooms[roomKey(room, org)] = (room: room, org: org);
    _frame(_about('join', room, org));
  }

  @override
  void leave(String room, [String? org]) {
    if (_rooms.remove(roomKey(room, org)) == null) return;
    _frame(_about('leave', room, org));
  }

  @override
  void send(String room, String data, {int? to, String? org}) {
    if (!_rooms.containsKey(roomKey(room, org))) return;
    _frame({..._about('msg', room, org), 'data': data, 'to': ?to});
  }

  @override
  void close() {
    _closed = true;
    _clearRetry();
    _socket?.close();
    _socket = null;
    _open = false;
  }

  @override
  void rest() {
    if (_closed || _resting) return;
    _resting = true;
    _clearRetry();
    final socket = _socket;
    _socket = null;
    _open = false;
    socket?.close();
    if (socket != null) events.down('network');
  }

  /// Now rather than after the backoff (`soon`).
  @override
  void wake() {
    if (_closed) return;
    _resting = false;
    if (_socket != null) return;
    _clearRetry();
    _attempt = 0;
    _connect();
  }

  void _frame(Map<String, Object?> value) {
    if (_open) _socket?.send(jsonEncode(value));
  }

  void _connect() {
    if (_closed || _resting || _socket != null) return;
    final token = this.token();
    if (token == null) {
      events.down('signIn');
      return;
    }
    final socket = _make(url);
    _socket = socket;
    socket.onOpen = () => socket.send(jsonEncode({'t': 'auth', 'token': token}));
    socket.onMessage = _receive;
    socket.onClose = (code) {
      if (!identical(_socket, socket)) return;
      _socket = null;
      _open = false;
      if (_closed) return;
      if (code == closeSignIn) {
        events.down('signIn');
        return;
      }
      events.down('network');
      _later();
    };
  }

  void _receive(Object? raw) {
    final Object? frame;
    try {
      frame = jsonDecode('$raw');
    } on FormatException {
      return;
    }
    if (frame is! Map) return;
    final room = frame['room'], org = frame['org'];
    final where = room is String && room.isNotEmpty ? room : null;
    final whose = org is String ? org : null;
    int number(Object? value) => value is num ? value.toInt() : 0;
    switch (frame['t']) {
      case 'ready':
        _open = true;
        _attempt = 0;
        events.ready(number(frame['id']));
        // Back in every room it was in. The relay answers each with `joined`, and the document above catches up.
        for (final held in _rooms.values.toList()) {
          _frame(_about('join', held.room, held.org));
        }
      case 'joined':
        if (where != null) events.joined(where, frame['first'] == true, number(frame['peers']), whose);
      case 'peers':
        if (where != null) events.peers(where, number(frame['peers']), whose, frame['left'] is num ? number(frame['left']) : null);
      case 'msg':
        final data = frame['data'];
        if (where != null && data is String) events.message(where, number(frame['from']), data, whose);
      default:
        // `error` frames say a request was refused; the socket stays, and there is nothing a device can do about
        // one.
        break;
    }
  }

  void _later() {
    _clearRetry();
    final wait = _attempt >= 16 ? longestWaitMs : min(longestWaitMs, firstWaitMs * pow(2, _attempt).toInt());
    _attempt += 1;
    // Jittered, so a relay restart is not met by every device at the same instant.
    final ms = (wait / 2 + _random() * (wait / 2)).round();
    void again() {
      _retry = null;
      _connect();
    }

    _retry = schedule != null ? (schedule!(again, ms) ?? again) : Timer(Duration(milliseconds: ms), again);
  }

  void _clearRetry() {
    final retry = _retry;
    if (retry is Timer) retry.cancel();
    _retry = null;
  }
}
