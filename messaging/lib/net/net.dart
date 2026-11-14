import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../sms.dart';
import 'carrier.dart';
import 'hub_carrier.dart';
import 'packet.dart';
import 'sms_carrier.dart';
import 'switchboard.dart';

/// Something the routes did, for Settings › Network to show: what, to or from whom, by which route, and when.
class NetEvent {
  NetEvent(this.words, {this.via}) : at = DateTime.now();
  final String words;
  final String? via;
  final DateTime at;
}

/// The app's routes as the app holds them (Matt, 2026-11-14: "implement a full relay system for the app that's
/// replacable and swappable", "multiple sources to feed data to eachother from wifi locally, p2p, internet, sms,
/// etc"): the switchboard (switchboard.dart), the routes this phone has (the relay server's hub and SMS data texts
/// now; the local network and a peer-to-peer one are made room for), and the people they reach.
///
/// The people are the ones encryption is on with: exchanging keys by text is what introduces two phones, and the
/// phone's own key pair is who it is (android/.../Net.kt). Nothing dials out until there is someone to reach and
/// the person has not switched the network off (Settings › Network).
///
/// What the person chooses is kept with their other choices: `net_on`, `net_hub` (the relay server's address),
/// `net_off` (the routes switched off, by name).
class Net extends ChangeNotifier implements PeerBook {
  Net._();
  static final Net instance = Net._();

  /// The relay server the app is given: ours. Anyone can run their own (relay/README.md) and put its address here.
  static const defaultHub = 'wss://ghost-sms.com/hub';

  AppState? _app;
  Switchboard? _board;
  HubCarrier? _hub;
  SmsCarrier? _sms;
  final Map<String, Peer> _peers = {};
  final List<StreamSubscription<dynamic>> _subs = [];

  /// This phone's name to the others; null until the phone has said.
  String? id;

  /// Why the routes could not be set up, in words; null when they were.
  String? error;

  /// The last things the routes did, newest first.
  final List<NetEvent> recent = [];

  Switchboard? get board => _board;
  HubCarrier? get hub => _hub;
  SmsCarrier? get sms => _sms;
  List<Peer> get people => _peers.values.toList();
  bool get on => _app?.flag('net_on') ?? true;
  String get hubUrl {
    final own = _app?.choice('net_hub', '') ?? '';
    return own.trim().isEmpty ? defaultHub : own.trim();
  }

  @override
  Peer? byId(String id) => _peers[id];
  @override
  Peer? byAddress(String address) {
    final want = _digits(address);
    for (final p in _peers.values) {
      if (_digits(p.address ?? '') == want) return p;
    }
    return null;
  }

  /// A number as two phones agree on it whatever each wrote before it: its last ten digits.
  static String _digits(String address) {
    final d = address.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 7 ? (d.length > 10 ? d.substring(d.length - 10) : d) : address.trim().toLowerCase();
  }

  void _note(String words, {String? via}) {
    recent.insert(0, NetEvent(words, via: via));
    if (recent.length > 30) recent.removeLast();
    notifyListeners();
  }

  /// Sets the routes up. On a computer there are none yet: it speaks through the phone it is paired with.
  /// [carriers] stands in for the phone's own routes (a test).
  Future<void> start(AppState app, {List<Carrier>? carriers}) async {
    if (Sms.remote || _board != null) return;
    _app = app;
    try {
      final me = await Sms.instance.netIdentity();
      id = me.id;
      await _readPeers();
      final List<Carrier> routes;
      if (carriers != null) {
        routes = carriers;
      } else {
        final hub = _hub = HubCarrier(url: hubUrl, signer: _PhoneSigner(me.id, me.key));
        final sms = _sms = SmsCarrier(_PhoneSms());
        routes = [hub, sms];
      }
      final board = _board = Switchboard(me: me.id, peers: this, carriers: routes);
      board.off.addAll(app.choice('net_off', '').split(',').where((s) => s.isNotEmpty));
      board.changed.addListener(notifyListeners);
      _subs.add(board.received.listen(_received));
      // People come and go as keys are exchanged and encryption is turned on and off.
      _subs.add(Sms.instance.prefsChanged.stream.listen((_) => refresh()));
      error = null;
      await _apply();
      // What came by text while the app was closed.
      for (final kept in await Sms.instance.netSmsDrain()) {
        Sms.instance.netSms.add(kept);
      }
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> _readPeers() async {
    final list = await Sms.instance.netPeers();
    final found = <String, Peer>{};
    for (final p in list) {
      // Their name as the phone's contacts have it, where they do.
      String? name;
      try {
        name = (await Sms.instance.contact(p.address)).name;
      } catch (_) {}
      found[p.id] = Peer(id: p.id, key: p.key, address: p.address, name: name);
    }
    _peers
      ..clear()
      ..addAll(found);
  }

  /// Stops the routes and forgets them: the app is closing, or a test is over.
  Future<void> shutdown() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final board = _board;
    _board = null;
    _hub = null;
    _sms = null;
    if (board != null) {
      board.changed.removeListener(notifyListeners);
      await board.stop();
      await board.dispose();
    }
    _peers.clear();
    recent.clear();
    id = null;
  }

  /// Reads the people again, and starts or stops the routes to suit: after encryption was turned on with someone,
  /// or off.
  Future<void> refresh() async {
    if (_board == null) return;
    try {
      await _readPeers();
    } catch (_) {}
    await _apply();
    notifyListeners();
  }

  /// Starts or stops the routes to match the person's choices. With nobody to reach, nothing dials out.
  Future<void> _apply() async {
    final board = _board;
    if (board == null) return;
    if (on && _peers.isNotEmpty) {
      await board.start();
      _hub?.watch(_peers.keys);
    } else {
      await board.stop();
    }
  }

  Future<void> setOn(bool value) async {
    _app?.setFlag('net_on', value);
    await _apply();
    notifyListeners();
  }

  Future<void> setRoute(String id, bool value) async {
    final board = _board;
    if (board == null) return;
    await board.setOn(id, value && on && _peers.isNotEmpty);
    if (!value) board.off.add(id);
    _app?.set('net_off', board.off.join(','));
    notifyListeners();
  }

  /// Uses another relay server ([url] empty: ours again). The route is taken out and one for the new address put
  /// in its place: the rest of the app does not know.
  Future<void> setHub(String url) async {
    _app?.set('net_hub', url.trim());
    final board = _board, old = _hub, me = id;
    if (board == null || old == null || me == null) return;
    await old.stop();
    final hub = _hub = HubCarrier(url: hubUrl, signer: old.signer);
    board.add(hub);
    await _apply();
    notifyListeners();
  }

  void _received(Received r) {
    final who = r.peer.name ?? r.peer.address ?? r.peer.id.substring(0, 6);
    if (r.envelope.kind == 'ping') _note('A test came from $who', via: r.via);
    for (final l in _listeners.toList()) {
      l(r);
    }
  }

  final List<void Function(Received)> _listeners = [];

  /// What comes by the routes, for whoever in the app it is for (calls, receipts).
  void listen(void Function(Received) onReceived) => _listeners.add(onReceived);
  void unlisten(void Function(Received) onReceived) => _listeners.remove(onReceived);

  /// Sends [envelope] to [peer] by the routes (Switchboard.send).
  Future<Delivery> send(Peer peer, Envelope envelope, {bool metered = false, bool urgent = false, Set<String>? only}) {
    final board = _board;
    if (board == null) return Future.value(Delivery(envelope.id, tried: const ['the routes are not set up']));
    return board.send(peer, envelope, metered: metered, urgent: urgent, only: only);
  }

  /// Sends a test to [peer], by [only] those routes where given, and says what became of it and how long the
  /// answer took. One sent by SMS is a text on the person's plan, and is not answered (an answer would be one on
  /// theirs): the other phone shows that it came, in its own Settings › Network.
  Future<({Delivery delivery, Duration took})> test(Peer peer, {String? only}) async {
    final began = DateTime.now();
    final d = await send(peer, Envelope(kind: 'ping'), metered: only == 'sms', only: only == null ? null : {only});
    final took = DateTime.now().difference(began);
    final who = peer.name ?? peer.address ?? peer.id.substring(0, 6);
    _note(
      d.sent ? (d.acked ? 'A test reached $who in ${took.inMilliseconds} ms' : d.handed == Handed.held ? 'A test is kept for $who, who is away' : 'A test was sent to $who') : 'A test to $who could not be sent: ${d.tried.join('; ')}',
      via: d.via,
    );
    return (delivery: d, took: took);
  }
}

class _PhoneSigner implements NetSigner {
  _PhoneSigner(this.id, this.publicKey);
  @override
  final String id;
  @override
  final Uint8List publicKey;
  @override
  Future<Uint8List> sign(List<int> message) => Sms.instance.netSign(message);
}

class _PhoneSms implements SmsBridge {
  @override
  Future<bool> available() => Sms.instance.netSmsAvailable();
  @override
  Future<void> send(String address, Uint8List bytes) => Sms.instance.netSmsSend(address, bytes);
  @override
  Stream<({String address, Uint8List bytes})> get incoming => Sms.instance.netSms.stream;
}
