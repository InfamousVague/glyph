import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'carrier.dart';
import 'crypto.dart';
import 'hub_link.dart';

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
  HubCarrier({required this.url, required this.signer, Duration? retry, HubDial? dial}) : _retry = retry ?? const Duration(seconds: 3), _dial = dial ?? dialHub;

  /// Which of its identity's devices this install is, said in the hello (Net.start sets it): a phone and its computer
  /// can be here at once under one identity, each handed what is sent to it (relay/lib/hub.dart). Empty, as an app
  /// from before said nothing: then another such connection takes this one's place.
  static String device = '';

  /// The hub's address: `wss://gogho.st/hub`.
  final String url;
  final NetSigner signer;
  final Duration _retry;

  /// How the hub is reached (hub_link.dart): a WebSocket to [url] where nothing else was given.
  final HubDial _dial;

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
  final _handles = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Arrived> get arrived => _arrived.stream;

  /// Who came and went in the rooms this install is in.
  Stream<RoomEvent> get roomEvents => _rooms.stream;

  /// What the others in a room sent to it.
  Stream<({String room, String from, Uint8List bytes})> get roomPackets => _roomPackets.stream;

  /// Reactions in rooms (relay/lib/hub.dart toRoomReaction), apart from other room packets.
  final _roomReactions = StreamController<({String room, String from, Uint8List bytes})>.broadcast();
  Stream<({String room, String from, Uint8List bytes})> get roomReactions => _roomReactions.stream;

  /// Whether the relay server connected to takes reactions as a packet of their own ([sendReaction]); a server from
  /// before keeps them as an ordinary kept packet instead.
  bool takesReactions = false;

  /// Sends a reaction to a room this install is in, kept for whoever comes later (relay/lib/hub.dart toRoomReaction).
  void sendReaction(String room, Uint8List packet) {
    if (!_ready || !_joined.containsKey(room)) throw CarrierError('not in that room');
    _ws?.say([4, ...NetCrypto.unhex(room), ...packet]);
  }

  /// What the server's keeper of handles says to this install (relay/lib/handles.dart): every message that starts
  /// `{"dir": …}`. lib/me/me.dart listens.
  Stream<Map<String, dynamic>> get handles => _handles.stream;

  /// Says something to the keeper of handles; false where the route is not up.
  bool sayHandles(Map<String, Object?> what) {
    final ws = _ws;
    if (ws == null || !_ready) return false;
    ws.say(jsonEncode(what));
    return true;
  }

  /// The names, of those asked about ([watch]), that are connected to the hub now.
  final ValueNotifier<Set<String>> here = ValueNotifier(const {});

  /// Of those [here], the ones with the app put away (relay/lib/hub.dart's `away`).
  final ValueNotifier<Set<String>> away = ValueNotifier(const {});

  /// Of those [here], the ones who chose Busy (relay/lib/hub.dart's `busy`; GMFB-34).
  final ValueNotifier<Set<String>> busy = ValueNotifier(const {});

  /// When each of those asked about was last using the app, where the hub knows (`went`, `seen`, `away`).
  final Map<String, DateTime> seen = {};

  /// Goes up whenever [here], [away] or [seen] changes: the one thing a face's presence listens to.
  final ValueNotifier<int> presence = ValueNotifier(0);

  bool _awayNow = false;

  /// This app put away (true) or in use (false), told to the hub so friends watching see it; said again after every
  /// sign-in (Matt, 2026-11-17: "presense sensing ... for users who have signed up for a username").
  bool get awayNow => _awayNow;
  set awayNow(bool value) {
    if (value == _awayNow) return;
    final was = _awaySaid;
    _awayNow = value;
    if (_ready && _awaySaid != was) _ws?.say(jsonEncode({'away': _awaySaid}));
  }

  /// How this person chose to be shown (GMFB-34): 'online', 'away', 'busy' or 'invisible'. Away is said as the app put
  /// away, whatever it is doing; busy and invisible are the hub's own (`mode`), said with every hello too, so someone
  /// invisible never shows as come.
  String get mode => _mode;
  String _mode = 'online';
  set mode(String value) {
    final m = const {'online', 'away', 'busy', 'invisible'}.contains(value) ? value : 'online';
    if (m == _mode) return;
    final wasAway = _awaySaid;
    _mode = m;
    if (!_ready) return;
    _ws?.say(jsonEncode({'mode': _hubMode}));
    if (_awaySaid != wasAway) _ws?.say(jsonEncode({'away': _awaySaid}));
  }

  bool get _awaySaid => _awayNow || _mode == 'away';
  String get _hubMode => _mode == 'busy' || _mode == 'invisible' ? _mode : 'online';

  HubLink? _ws;
  bool _wanted = false;
  bool _ready = false;
  Timer? _again;
  int _seq = 0;
  int _tries = 0;
  final Map<int, Completer<Handed>> _sent = {};
  final Set<String> _watched = {};
  final Map<String, String> _joined = {};
  final Map<String, String> _looked = {};
  final _looks = StreamController<({String room, List<String> members})>.broadcast();

  /// The relay's TURN server for calls, with a username and password good for a day, as the hub handed it out with the
  /// last room joined (relay/lib/turn.dart): an RTCIceServer entry. Null where the hub has none (or is from before).
  Map<String, Object>? callRelay;

  /// Who is in each room this install looks at ([look]), as the hub last said.
  final Map<String, List<String>> looking = {};

  /// Who is in a room looked at, each time that changes.
  Stream<({String room, List<String> members})> get looks => _looks.stream;

  /// Asks to be told who is in [room] without joining it: a voice channel's list. Asked again by itself after the
  /// route is lost and comes back. [token] is the room's own: a wrong one is told nothing.
  void look(String room, String token) {
    _looked[room] = token;
    if (_ready) _ws?.say(jsonEncode({'look': room, 'token': token}));
  }

  void unlook(String room) {
    looking.remove(room);
    if (_looked.remove(room) != null && _ready) _ws?.say(jsonEncode({'unlook': room}));
  }
  final Map<String, Completer<List<String>>> _joining = {};

  @override
  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    _connect();
  }

  /// The app has come back to the screen (Matt, 2026-11-16: "fix delivery"): a connection that is down is tried now,
  /// not at the end of its wait, and one held while the app was away for [stale] or longer is made again, since the
  /// phone may have let it die without saying so (the relay server would hand it messages that go nowhere).
  void nudge({Duration away = Duration.zero, Duration stale = const Duration(seconds: 45)}) {
    if (!_wanted) return;
    if (_ws != null && away < stale) return;
    _again?.cancel();
    _tries = 0;
    if (_ws != null) _drop('made again after the app was away');
    unawaited(_connect());
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
    // Lost: nobody is known to be here until the hub says again.
    if (here.value.isNotEmpty || away.value.isNotEmpty || busy.value.isNotEmpty) {
      here.value = const {};
      away.value = const {};
      busy.value = const {};
      presence.value++;
    }
  }

  Future<void> _connect() async {
    if (!_wanted || _ws != null) return;
    state.value = CarrierState.connecting;
    final HubLink ws;
    try {
      ws = await _dial(url);
    } catch (e) {
      _lost('The relay server could not be reached');
      return;
    }
    if (!_wanted) {
      ws.close().catchError((_) => null);
      return;
    }
    _ws = ws;
    ws.said.listen((data) => _said(ws, data), onDone: () => _gone(ws), onError: (_) => _gone(ws), cancelOnError: true);
  }

  void _gone(HubLink ws) {
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

  Future<void> _said(HubLink ws, Object data) async {
    if (!identical(_ws, ws)) return;
    if (data is List<int>) {
      if (data.length > 17 && data[0] == 1) {
        _arrived.add(Arrived(id, Uint8List.fromList(data.sublist(17)), from: NetCrypto.hex(data.sublist(1, 17))));
      } else if (data.length > 33 && data[0] == 2) {
        _roomPackets.add((room: NetCrypto.hex(data.sublist(1, 17)), from: NetCrypto.hex(data.sublist(17, 33)), bytes: Uint8List.fromList(data.sublist(33))));
      } else if (data.length > 33 && data[0] == 4) {
        // A reaction in a room (relay/lib/hub.dart toRoomReaction): nothing but a reaction is taken from one.
        _roomReactions.add((room: NetCrypto.hex(data.sublist(1, 17)), from: NetCrypto.hex(data.sublist(17, 33)), bytes: Uint8List.fromList(data.sublist(33))));
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
      takesReactions = m['react'] == true;
      // The hub's number, signed: only the holder of this install's key connects under its name.
      final sig = await signer.sign([...utf8.encode(greeting), ...NetCrypto.unhex(m['hello'] as String)]);
      if (!identical(_ws, ws)) return;
      ws.say(jsonEncode({'id': signer.id, 'key': base64Encode(signer.publicKey), 'sig': base64Encode(sig), if (device.isNotEmpty) 'device': device, if (_hubMode != 'online') 'mode': _hubMode}));
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
      if (_watched.isNotEmpty) ws.say(jsonEncode({'watch': _watched.toList()}));
      if (_awaySaid) ws.say(jsonEncode({'away': true}));
      if (_push != null) ws.say(jsonEncode({'push': _push}));
      for (final e in _joined.entries) {
        ws.say(jsonEncode({'join': e.key, 'token': e.value, 'ro': ?_readOnly[e.key]}));
      }
      for (final e in _looked.entries) {
        ws.say(jsonEncode({'look': e.key, 'token': e.value}));
      }
    } else if (m['dir'] is String) {
      _handles.add(m);
    } else if (m.containsKey('ack')) {
      _sent.remove(m['ack'])?.complete(m['here'] == true ? Handed.passed : Handed.held);
    } else if (m.containsKey('nak')) {
      _sent.remove(m['nak'])?.completeError(CarrierError(m['err'] == 'full' ? 'the relay server is holding too much for them already' : 'the relay server would not take it'));
    } else if (m['room'] is String && m['look'] is List) {
      // Who is in a room this install looks at without being in it.
      final room = m['room'] as String;
      final members = (m['look'] as List).cast<String>();
      looking[room] = members;
      _looks.add((room: room, members: members));
    } else if (m['room'] is String) {
      final room = m['room'] as String;
      if (m.containsKey('ok')) {
        final c = _joining.remove(room);
        if (m['ok'] == true) {
          final members = (m['members'] as List? ?? const []).cast<String>();
          if (m['ice'] is Map) callRelay = (m['ice'] as Map).cast<String, Object>();
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
      // names its room, and is the branch above.) With them, who has the app put away, and when those not here were
      // last there (a hub before 2026-11-17 says neither).
      final now = (m['here'] as List).cast<String>();
      here.value = {...here.value, ...now};
      away.value = {...away.value.where((id) => !now.contains(id)), ...((m['away'] as List?) ?? const []).cast<String>()};
      busy.value = {...busy.value.where((id) => !now.contains(id)), ...((m['busy'] as List?) ?? const []).cast<String>()};
      (m['seen'] as Map?)?.forEach((id, at) {
        if (at is num) seen['$id'] = DateTime.fromMillisecondsSinceEpoch(at.toInt());
      });
      presence.value++;
    } else if (m['came'] is String) {
      here.value = {...here.value, m['came'] as String};
      away.value = {...away.value}..remove(m['came']);
      busy.value = {...busy.value}..remove(m['came']);
      presence.value++;
    } else if (m['went'] is String) {
      final id = m['went'] as String;
      here.value = {...here.value}..remove(id);
      away.value = {...away.value}..remove(id);
      busy.value = {...busy.value}..remove(id);
      seen[id] = m['at'] is num ? DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()) : DateTime.now();
      presence.value++;
    } else if (m['away'] is String) {
      // Someone watched put the app away, or came back to it.
      final id = m['away'] as String;
      if (m['is'] == true) {
        away.value = {...away.value, id};
        if (m['at'] is num) seen[id] = DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt());
      } else {
        away.value = {...away.value}..remove(id);
      }
      presence.value++;
    } else if (m['busy'] is String) {
      // Someone watched chose Busy, or stopped (GMFB-34).
      final id = m['busy'] as String;
      busy.value = m['is'] == true ? {...busy.value, id} : ({...busy.value}..remove(id));
      presence.value++;
    }
  }

  Map<String, Object?>? _push;

  /// How the hub may wake this app when something is held for it and it is closed: an iPhone's Apple push token
  /// (`{'apns': hex, 'sandbox': bool}`; relay/lib/pushes.dart). Said on every sign-in, so a hub that restarted or
  /// lost it hears it again; null tells it to forget.
  Map<String, Object?>? get push => _push;
  set push(Map<String, Object?>? value) {
    final had = _push;
    _push = value;
    final ws = _ws;
    if (_ready && ws != null && (value != null || had != null)) ws.say(jsonEncode({'push': value}));
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
    ws.say([...head.buffer.asUint8List(), ...NetCrypto.unhex(peer.id), ...packet]);
    return done.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _sent.remove(seq);
      throw CarrierError('the relay server did not answer');
    });
  }

  /// Asks to be told when these names come and go ([here]).
  void watch(Iterable<String> ids) {
    final fresh = ids.where(_watched.add).toList();
    if (fresh.isNotEmpty && _ready) _ws?.say(jsonEncode({'watch': fresh}));
  }

  /// Joins a room, giving who is in it. It is joined again by itself after the route is lost and comes back.
  ///
  /// Asked before the relay server is connected (a circle's spaces are held as the app starts), the room is joined as
  /// soon as it is, as every room this install is in is on reconnecting, and this answers then (Matt, 2026-11-18: a
  /// circle's members' messages seen on no device: each room asked for too early was never joined, so nothing came
  /// from it and what was written in it went nowhere). Unanswered once connected, it stays asked for, and is asked again
  /// on the next connection.
  ///
  /// [ro]: a circle's read-only space's room, bound to its owner's key (relay/lib/hub.dart; lib/circles/welcome.dart),
  /// said with each join.
  Future<List<String>> join(String room, String token, {Map<String, Object?>? ro}) {
    _joined[room] = token;
    if (ro != null) {
      _readOnly[room] = ro;
    } else {
      _readOnly.remove(room);
    }
    final done = _joining[room] ??= Completer<List<String>>();
    final ws = _ws;
    if (ws == null || !_ready) return done.future;
    ws.say(jsonEncode({'join': room, 'token': token, 'ro': ?ro}));
    return done.future.timeout(const Duration(seconds: 8), onTimeout: () {
      if (identical(_joining[room], done)) _joining.remove(room);
      throw CarrierError('the relay server did not answer');
    });
  }

  void leave(String room) {
    _readOnly.remove(room);
    if (_joined.remove(room) != null && _ready) _ws?.say(jsonEncode({'leave': room}));
  }

  /// What each read-only room this install is in was joined with ([join]'s `ro`), to join it so again on reconnecting.
  final Map<String, Map<String, Object?>> _readOnly = {};

  /// Tells the relay a read-only room's newer admin list ([grants]: `gv`, `g`, `gs`), kept for the next join too.
  void anchorRoom(String room, Map<String, Object?> grants) {
    final ro = _readOnly[room];
    if (ro == null) return;
    _readOnly[room] = {...ro, ...grants};
    if (_ready) _ws?.say(jsonEncode({'anchor': room, ...grants}));
  }

  /// Sends a packet to everyone else in a room this install is in.
  ///
  /// [keep]: the hub keeps it too, sealed as it is, for whoever joins the room later (relay/lib/hub.dart toRoomKept):
  /// what a space's members wrote reaches a phone that was closed at the time.
  void sendRoom(String room, Uint8List packet, {bool keep = false}) {
    if (!_ready || !_joined.containsKey(room)) throw CarrierError('not in that room');
    _ws?.say([keep ? 3 : 2, ...NetCrypto.unhex(room), ...packet]);
  }
}
