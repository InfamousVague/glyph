import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'carrier.dart';
import 'crypto.dart';

/// Who this install is to a hub: its name, its public key, and a way to sign with the private one, which stays
/// wherever it is kept (Android's keystore on a phone).
abstract class NetSigner {
  String get id;
  Uint8List get publicKey;

  /// A signature over [message]: r then s, 64 bytes.
  Future<Uint8List> sign(List<int> message);
}

/// A signer whose key pair is held in Dart: a computer, and the tests.
class KeysSigner implements NetSigner {
  KeysSigner(this.keys);
  final NetKeys keys;
  @override
  String get id => keys.id;
  @override
  Uint8List get publicKey => keys.public;
  @override
  Future<Uint8List> sign(List<int> message) async => NetCrypto.sign(keys, message);
}

/// Something that happened in a room: who is in it on joining, then who came and went.
class RoomEvent {
  const RoomEvent(this.room, {this.members, this.came, this.went, this.closed = false});
  final String room;
  final List<String>? members;
  final String? came;
  final String? went;

  /// The route was lost: nobody in the room can be reached by it until it is joined again.
  final bool closed;
}

/// The route through a server's hub (relay/lib/hub.dart): this install dials out to it and is found there by its
/// name. It is the one that works between any two networks today, and the one a peer-to-peer route is meant to
/// take the place of (Matt, 2026-11-14: "for right now we can use our servers ... but in the future id like to be
/// able to use a P2P decentralized relay").
///
/// A packet for someone who is not connected is kept by the hub and handed over when they next are. The hub sees
/// names and sizes, never contents. It also keeps rooms ([join]), which a voice room and a group are made on.
class HubCarrier implements Carrier {
  HubCarrier({required this.url, required this.signer, Duration? retry}) : _retry = retry ?? const Duration(seconds: 3);

  /// The hub's address: `wss://ghost-sms.com/hub`.
  final String url;
  final NetSigner signer;
  final Duration _retry;

  static const greeting = 'ghost-hub v1 ';

  @override
  String get id => 'hub';
  @override
  String get name => 'Relay server';
  @override
  String get about => 'Through a server on the internet. Works between any two networks; the server sees who talks to whom, never what is said.';
  @override
  CarrierTraits get traits => const CarrierTraits(maxPacket: 60 * 1024);
  @override
  final ValueNotifier<CarrierState> state = ValueNotifier(CarrierState.off);
  @override
  String? problem;

  final _arrived = StreamController<Arrived>.broadcast();
  final _rooms = StreamController<RoomEvent>.broadcast();
  final _roomPackets = StreamController<({String room, String from, Uint8List bytes})>.broadcast();
  @override
  Stream<Arrived> get arrived => _arrived.stream;

  /// Who came and went in the rooms this install is in.
  Stream<RoomEvent> get roomEvents => _rooms.stream;

  /// What the others in a room sent to it.
  Stream<({String room, String from, Uint8List bytes})> get roomPackets => _roomPackets.stream;

  /// The names, of those asked about ([watch]), that are connected to the hub now.
  final ValueNotifier<Set<String>> here = ValueNotifier(const {});

  WebSocket? _ws;
  bool _wanted = false;
  bool _ready = false;
  Timer? _again;
  int _seq = 0;
  int _tries = 0;
  final Map<int, Completer<Handed>> _sent = {};
  final Set<String> _watched = {};
  final Map<String, String> _joined = {};
  final Map<String, Completer<List<String>>> _joining = {};

  @override
  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    _connect();
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    _again?.cancel();
    _drop('stopped');
    state.value = CarrierState.off;
  }

  void _drop(String why) {
    final ws = _ws;
    _ws = null;
    _ready = false;
    ws?.close().catchError((_) => null);
    for (final c in _sent.values) {
      if (!c.isCompleted) c.completeError(CarrierError(why));
    }
    _sent.clear();
    for (final c in _joining.values) {
      if (!c.isCompleted) c.completeError(CarrierError(why));
    }
    _joining.clear();
    for (final room in _joined.keys) {
      _rooms.add(RoomEvent(room, closed: true));
    }
    if (here.value.isNotEmpty) here.value = const {};
  }

  Future<void> _connect() async {
    if (!_wanted || _ws != null) return;
    state.value = CarrierState.connecting;
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(url).timeout(const Duration(seconds: 10));
    } catch (e) {
      _lost('The relay server could not be reached');
      return;
    }
    if (!_wanted) {
      ws.close().catchError((_) => null);
      return;
    }
    _ws = ws;
    ws.pingInterval = const Duration(seconds: 25);
    ws.listen((data) => _said(ws, data), onDone: () => _gone(ws), onError: (_) => _gone(ws), cancelOnError: true);
  }

  void _gone(WebSocket ws) {
    if (!identical(_ws, ws)) return;
    _drop('the connection was lost');
    _lost('The connection to the relay server was lost');
  }

  void _lost(String why) {
    if (!_wanted) return;
    problem = why;
    state.value = CarrierState.down;
    _again?.cancel();
    // Sooner at first, then every half minute: a phone that is offline for hours does not hammer at it.
    final wait = _retry * (_tries < 4 ? 1 << _tries : 10);
    _tries++;
    _again = Timer(wait, _connect);
  }

  Future<void> _said(WebSocket ws, dynamic data) async {
    if (!identical(_ws, ws)) return;
    if (data is List<int>) {
      if (data.length > 17 && data[0] == 1) {
        _arrived.add(Arrived(id, Uint8List.fromList(data.sublist(17))));
      } else if (data.length > 33 && data[0] == 2) {
        _roomPackets.add((room: NetCrypto.hex(data.sublist(1, 17)), from: NetCrypto.hex(data.sublist(17, 33)), bytes: Uint8List.fromList(data.sublist(33))));
      }
      return;
    }
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(data as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    if (m['hello'] is String && !_ready) {
      // The hub's number, signed: only the holder of this install's key connects under its name.
      final sig = await signer.sign([...utf8.encode(greeting), ...NetCrypto.unhex(m['hello'] as String)]);
      if (!identical(_ws, ws)) return;
      ws.add(jsonEncode({'id': signer.id, 'key': base64Encode(signer.publicKey), 'sig': base64Encode(sig)}));
    } else if (m.containsKey('ok') && !_ready) {
      if (m['ok'] != true) {
        _drop('refused');
        _lost('The relay server refused this app: ${m['err'] ?? 'no reason given'}');
        return;
      }
      _ready = true;
      _tries = 0;
      problem = null;
      state.value = CarrierState.up;
      if (_watched.isNotEmpty) ws.add(jsonEncode({'watch': _watched.toList()}));
      for (final e in _joined.entries) {
        ws.add(jsonEncode({'join': e.key, 'token': e.value}));
      }
    } else if (m.containsKey('ack')) {
      _sent.remove(m['ack'])?.complete(m['here'] == true ? Handed.passed : Handed.held);
    } else if (m.containsKey('nak')) {
      _sent.remove(m['nak'])?.completeError(CarrierError(m['err'] == 'full' ? 'the relay server is holding too much for them already' : 'the relay server would not take it'));
    } else if (m['room'] is String) {
      final room = m['room'] as String;
      if (m.containsKey('ok')) {
        final c = _joining.remove(room);
        if (m['ok'] == true) {
          final members = (m['members'] as List? ?? const []).cast<String>();
          c?.complete(members);
          _rooms.add(RoomEvent(room, members: members));
        } else {
          _joined.remove(room);
          c?.completeError(CarrierError(m['err'] == 'full' ? 'that room is full' : 'the room would not let this app in'));
        }
      } else if (m['came'] is String) {
        _rooms.add(RoomEvent(room, came: m['came'] as String));
      } else if (m['went'] is String) {
        _rooms.add(RoomEvent(room, went: m['went'] as String));
      }
    } else if (m['here'] is List) {
      // Who, of those asked about, is connected now; then each as they come and go. (A room's coming and going
      // names its room, and is the branch above.)
      here.value = {...here.value, ...(m['here'] as List).cast<String>()};
    } else if (m['came'] is String) {
      here.value = {...here.value, m['came'] as String};
    } else if (m['went'] is String) {
      here.value = {...here.value}..remove(m['went']);
    }
  }

  /// A hub reaches anyone: someone who is not connected to it is kept for.
  @override
  bool reaches(Peer peer) => _ready;

  @override
  Future<Handed> send(Peer peer, Uint8List packet) {
    final ws = _ws;
    if (ws == null || !_ready) throw CarrierError('not connected to the relay server');
    final seq = _seq = (_seq + 1) & 0x7fffffff;
    final head = ByteData(5)
      ..setUint8(0, 1)
      ..setUint32(1, seq);
    final done = _sent[seq] = Completer<Handed>();
    ws.add([...head.buffer.asUint8List(), ...NetCrypto.unhex(peer.id), ...packet]);
    return done.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _sent.remove(seq);
      throw CarrierError('the relay server did not answer');
    });
  }

  /// Asks to be told when these names come and go ([here]).
  void watch(Iterable<String> ids) {
    final fresh = ids.where(_watched.add).toList();
    if (fresh.isNotEmpty && _ready) _ws?.add(jsonEncode({'watch': fresh}));
  }

  /// Joins a room, giving who is in it. It is joined again by itself after the route is lost and comes back.
  Future<List<String>> join(String room, String token) {
    final ws = _ws;
    if (ws == null || !_ready) return Future.error(CarrierError('not connected to the relay server'));
    _joined[room] = token;
    final done = _joining[room] = Completer<List<String>>();
    ws.add(jsonEncode({'join': room, 'token': token}));
    return done.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _joining.remove(room);
      throw CarrierError('the relay server did not answer');
    });
  }

  void leave(String room) {
    if (_joined.remove(room) != null && _ready) _ws?.add(jsonEncode({'leave': room}));
  }

  /// Sends a packet to everyone else in a room this install is in.
  void sendRoom(String room, Uint8List packet) {
    if (!_ready || !_joined.containsKey(room)) throw CarrierError('not in that room');
    _ws?.add([2, ...NetCrypto.unhex(room), ...packet]);
  }
}
