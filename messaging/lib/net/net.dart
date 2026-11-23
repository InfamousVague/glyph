import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../me/me.dart' show Me;
import '../sms.dart';
import 'carrier.dart';
import 'crypto.dart';
import 'forward_secrecy.dart';
import 'hub_carrier.dart';
import 'hub_link.dart';
import 'packet.dart';
import 'relay_choice.dart';
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
  static const defaultHub = 'wss://gogho.st/hub';

  /// The relay server an install uses where the person has chosen none: ours ([defaultHub]) on every phone and
  /// computer. A page in a browser may speak only to the address it came from, so there it is that address's own hub,
  /// put here before the routes start (lib/web/app.dart).
  static String homeHub = defaultHub;

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

  Map<String, Object?>? _push;

  // --- who is here: presence of people on our own system ------------------------------------------------------------

  /// Goes up whenever anyone's presence on the hub changes (HubCarrier.presence).
  final ValueNotifier<int> presence = ValueNotifier(0);
  bool _away = false;
  final Set<String> _alsoWatch = {};

  void _presenceChanged() => presence.value++;

  HubCarrier _presenceOf(HubCarrier hub) {
    hub.presence.addListener(_presenceChanged);
    hub.awayNow = _away;
    hub.mode = _mode;
    if (_alsoWatch.isNotEmpty) hub.watch(_alsoWatch);
    return hub;
  }

  String _mode = 'online';

  /// How this person chose to be shown (GMFB-34; Me.presenceMode): Online, Away, Busy or Invisible, told to the hub
  /// now and with every sign-in after.
  void setMode(String mode) {
    _mode = mode;
    _hub?.mode = mode;
  }

  /// This app put away or in use (main.dart, as it goes to the background and comes back): friends see it (Matt,
  /// 2026-11-17: "presense sensing ... for users who have signed up for a username and are part of our own system").
  void setAway(bool away) {
    _away = away;
    _hub?.awayNow = away;
  }

  /// Watches these names too (friends by username, lib/friends/buddies.dart), beside those the phone has keys with.
  void watchToo(Iterable<String> ids) {
    final fresh = ids.where(_alsoWatch.add).toList();
    if (fresh.isNotEmpty) _hub?.watch(fresh);
  }

  /// Whether someone on our own system, by their install's name, is using the app now, or when they last were; null
  /// where the hub has said nothing of them.
  ({bool online, DateTime? lastSeen, bool away, bool busy})? presenceOfId(String id) {
    final hub = _hub;
    if (hub == null) return null;
    final here = hub.here.value.contains(id);
    final away = hub.away.value.contains(id);
    final busy = here && hub.busy.value.contains(id);
    final seen = hub.seen[id];
    if (!here && seen == null) return null;
    // Busy shows as busy whether the app is in use or put away; away only where here.
    return (online: here && !away, lastSeen: here && !away ? null : seen, away: here && away && !busy, busy: busy);
  }

  /// How the relay server may wake this app while it is closed (an iPhone's push token; [HubCarrier.push]): kept here
  /// too, so a hub route made later (another server, [setHub]) says it as well.
  void setPush(Map<String, Object?>? value) {
    _push = value;
    _hub?.push = value;
  }
  SmsCarrier? get sms => _sms;
  List<Peer> get people => _peers.values.toList();
  bool get on => _app?.flag('net_on') ?? true;
  String get hubUrl {
    final own = _app?.choice('net_hub', '') ?? '';
    return own.trim().isEmpty ? homeHub : own.trim();
  }

  @override
  Peer? byId(String id) => id == this.id && _mineKey != null ? Peer(id: id, key: _mineKey) : _peers[id];

  /// The key this account's devices seal copies to each other with (GMFB-21; Friends.copyKind), once read.
  Uint8List? _mineKey;

  /// This account's own other devices, as one peer: this install's name and the account's key. Null where no Ghost
  /// account is signed in to here (or the routes aren't set up).
  Future<Peer?> mine() async {
    final me = id;
    if (me == null) return null;
    _mineKey ??= await Me.instance.mineKey();
    final key = _mineKey;
    return key == null ? null : Peer(id: me, key: key);
  }
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
    if ((Sms.paired && !Sms.ownNetwork) || _board != null) return;
    _app = app;
    // This install's own name among its identity's devices, made once and kept.
    var device = app.choice('hub_device', '');
    if (device.length != 32) {
      device = NetCrypto.hex(NetCrypto.randomBytes(16));
      app.set('hub_device', device);
    }
    HubCarrier.device = device;
    try {
      final me = await Sms.instance.netIdentity();
      id = me.id;
      await _readPeers();
      final List<Carrier> routes;
      if (carriers != null) {
        routes = carriers;
      } else {
        final hub = _hub = _presenceOf(HubCarrier(url: hubUrl, signer: _PhoneSigner(me.id, me.key))..push = _push);
        final sms = _sms = SmsCarrier(_PhoneSms());
        routes = [hub, sms];
      }
      // This device's forward secrecy (GMFB-26): its prekeys in the secret store beside the account's words, never in
      // the account's backup. Where that store can't be read, none: everything is sealed the old way, as before.
      // Where it can't be read yet (an iPhone's Keychain before its first unlock), tried again every half minute and as
      // the app comes back; until then everything is sealed the old way, with no prekey, which tells friends to do the
      // same (ForwardSecrecy.sawOld), and forward-secret packets are passed on to a sibling device, not answered.
      final fs = ForwardSecrecy(device: device, secrets: _SecretFsStore(), plain: _ChoiceFsStore(app));
      if (!await fs.tryLoad()) _fsAgain(fs);
      final board = _board = Switchboard(me: me.id, peers: this, carriers: routes, fs: fs);
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

  /// The app has come back after [away] (main.dart): the relay server's connection is made again where it may have
  /// died meanwhile, and what friends were sent and have not answered goes again once it is up (Friends).
  void resume(Duration away) {
    _hub?.nudge(away: away);
    final fs = _board?.fs;
    if (fs != null && !fs.loaded) unawaited(fs.tryLoad());
  }

  Timer? _fsTimer;

  /// Tries [fs]'s load again every half minute until it works.
  void _fsAgain(ForwardSecrecy fs) {
    _fsTimer?.cancel();
    _fsTimer = Timer.periodic(const Duration(seconds: 30), (t) async {
      if (fs.loaded || await fs.tryLoad()) t.cancel();
    });
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
    _fsTimer?.cancel();
    _fsTimer = null;
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

  /// What else needs the relay server's hub besides the people encryption is on with: Settings › Me, which links
  /// accounts and verifies the number through it ([want]).
  final Set<String> _wanting = {};

  /// Says whether [who] needs the relay server connected. While anything does, the hub is dialled even with nobody
  /// to reach: it was dialled only for people encryption is on with, so a phone with none never reached the relay
  /// and Settings › Me said it wasn't connected (Matt, 2026-11-14: "it's not conecting to the relay it seems it
  /// says I can't verify my number until it connects to the relay which should be live").
  Future<void> want(String who, bool yes) async {
    final changed = yes ? _wanting.add(who) : _wanting.remove(who);
    if (changed) await _apply();
  }

  /// Starts or stops the routes to match the person's choices. With nobody to reach and nothing that needs the
  /// relay server, nothing dials out; with nobody to reach but something that needs it, the hub alone does.
  Future<void> _apply() async {
    final board = _board;
    if (board == null) return;
    if (on && _peers.isNotEmpty) {
      await board.start();
      _hub?.watch([..._peers.keys, ..._alsoWatch]);
    } else if (_wanting.isNotEmpty && !board.off.contains('hub')) {
      for (final c in board.carriers) {
        await (c.id == 'hub' ? c.start() : c.stop()).catchError((_) {});
      }
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
    // The person's choice is kept whatever happens to be running; then the routes are started or stopped to suit.
    // It was handed straight to the route as "on only if there is someone to reach", and with nobody encrypted that
    // was "off", which the switchboard writes down as switched off: the switch flipped back and could never be
    // turned on again (Matt, 2026-11-14: "I also can't toggle the relay server back on or SMS").
    if (value) {
      board.off.remove(id);
    } else {
      board.off.add(id);
    }
    _app?.set('net_off', board.off.join(','));
    if (!value) await board.setOn(id, false);
    await _apply();
    notifyListeners();
  }

  /// Whether the relay in use is Ghost Messaging's own default one.
  bool get onDefaultHub => hubUrl == defaultHub;

  /// Moves to the relay at [typed] (GMFB-25; relay_choice.dart), but only once a Ghost Messaging relay answers there:
  /// the address is tidied ([tidyRelayAddress]), asked ([checkRelay]), and [confirm], where given, asked with the
  /// tidied address before anything changes. Empty, or our own address, is ours again and needs no check. Says why
  /// it didn't move, or null where it did (or the person said no at [confirm]: then declined is true).
  Future<({String? problem, bool declined})> useRelay(String typed, {HubDial? connect, Duration timeout = const Duration(seconds: 8), Future<bool> Function(String url)? confirm}) async {
    final url = tidyRelayAddress(typed);
    if (url == null) return (problem: 'That isn\'t a relay server\'s address. It looks like relay.example.com or wss://relay.example.com/hub.', declined: false);
    if (url.isEmpty || url == defaultHub) {
      if (!onDefaultHub) await setHub('');
      return (problem: null, declined: false);
    }
    if (url == hubUrl) return (problem: null, declined: false);
    final check = await checkRelay(url, connect: connect, timeout: timeout);
    if (!check.ok) return (problem: check.problem, declined: false);
    if (confirm != null && !await confirm(url)) return (problem: null, declined: true);
    await setHub(url);
    return (problem: null, declined: false);
  }

  /// Uses another relay server ([url] empty: ours again). The route is taken out and one for the new address put
  /// in its place: the rest of the app does not know. Settings › Routes goes through [useRelay], which checks first.
  Future<void> setHub(String url) async {
    _app?.set('net_hub', url.trim());
    final board = _board, old = _hub, me = id;
    if (board == null || old == null || me == null) return;
    await old.stop();
    old.presence.removeListener(_presenceChanged);
    final hub = _hub = _presenceOf(HubCarrier(url: hubUrl, signer: old.signer)..push = _push);
    presence.value++;
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

/// Where this device's prekeys are kept: the Keychain, Android's vault, as the account's words are (Sms.secretKeep).
class _SecretFsStore implements FsStore {
  @override
  Future<String?> read(String name) => Sms.instance.secretRead(name);
  @override
  Future<void> write(String name, String value) => Sms.instance.secretKeep(name, value);
}

/// Where what others offered, and the packets seen, are kept: with the app's choices, drawing nothing again.
class _ChoiceFsStore implements FsStore {
  _ChoiceFsStore(this.app);
  final AppState app;
  @override
  Future<String?> read(String name) async => app.choice(name, '');
  @override
  Future<void> write(String name, String value) async => app.keep(name, value);
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
