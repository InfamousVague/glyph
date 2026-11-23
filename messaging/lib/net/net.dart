import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../friends/buddies.dart' show Buddy;
import '../me/me.dart' show Me;
import '../sms.dart';
import 'carrier.dart';
import 'crypto.dart';
import 'forward_secrecy.dart';
import 'hub_carrier.dart';
import 'hub_link.dart';
import 'p2p/node.dart';
import 'p2p/p2p.dart';
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
///
/// **The direct route** (lib/net/p2p; docs/OPEN_NETWORK.md, section 2) is there where the build has its core
/// ([p2pNode]): after the relay's hub in the order, linking only with this account's own devices and with friends
/// ([friends]), and kept in step with the people, how the person chose to be shown, the app being put away and
/// coming back, and the relay in use.
class Net extends ChangeNotifier implements PeerBook {
  Net._();
  static final Net instance = Net._();

  /// Makes this device's node on the direct network: the core's own (native/p2p, over lib/net/p2p/node_ffi.dart), set
  /// before the routes are set up in a build that has it. Null, or answering null, there is no core here: no direct
  /// route is made, and Settings › Routes shows none.
  static P2pNode? Function()? p2pNode;

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

  /// Why this build's direct route is not there though it has a core, in words for Settings › Routes; null where it is
  /// there, or where the build has none.
  String? directProblem;

  /// The last things the routes did, newest first.
  final List<NetEvent> recent = [];

  Switchboard? get board => _board;
  HubCarrier? get hub => _hub;

  // --- the direct route (lib/net/p2p) ---------------------------------------------------------------------------------

  P2p? _p2p;

  /// The app's hold on the direct network; null where this build has no core, or the routes are not set up.
  P2p? get p2p => _p2p;

  /// Goes up whenever what Settings › Routes shows of the direct route changes: the devices known, the links, the
  /// link helpers. Apart from the routes' own changes, which friends' unanswered words are sent again on.
  final ValueNotifier<int> direct = ValueNotifier(0);

  void _directChanged() => direct.value++;

  /// Those of [people] who are friends: whom the direct route links with, and tells where this device is. Never
  /// someone who has only asked or been asked, nor the other members of a group.
  List<Peer> get friends => [for (final p in _peers.values) if (_friendIds.contains(p.id)) p];
  Set<String> _friendIds = {};

  HubCarrier? _helpersOf;

  /// The relay named its link helpers as the app signed in to it ([HubCarrier.helpers]).
  void _helpersSaid() {
    final hub = _helpersOf;
    if (hub != null) _p2p?.setHelpers(hub.helpers.value);
  }

  void _followHelpers(HubCarrier? hub) {
    _helpersOf?.helpers.removeListener(_helpersSaid);
    _helpersOf = hub;
    hub?.helpers.addListener(_helpersSaid);
  }

  Timer? _p2pTimer;

  /// Reads what the direct network keeps, now and every half minute until it can be read (a secret store that is
  /// locked, as [_fsAgain] waits out).
  void _loadDirect(P2p p2p) {
    unawaited(p2p.tryLoad().then((ok) {
      if (ok || !identical(p2p, _p2p)) return;
      _p2pTimer?.cancel();
      _p2pTimer = Timer.periodic(const Duration(seconds: 30), (t) async {
        if (!identical(p2p, _p2p) || p2p.loaded || await p2p.tryLoad()) t.cancel();
      });
    }));
  }

  Map<String, Object?>? _push;

  // --- who is here: presence of people on our own system ------------------------------------------------------------

  /// Goes up whenever anyone's presence on the hub changes (HubCarrier.presence).
  final ValueNotifier<int> presence = ValueNotifier(0);
  bool _away = false;
  final Set<String> _alsoWatch = {};

  void _presenceChanged() {
    presence.value++;
    // Whoever came is told this device's card now, where they had not been while away.
    _p2p?.presenceChanged();
  }

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
    _p2p?.setMode(mode);
  }

  /// This app put away or in use (main.dart, as it goes to the background and comes back): friends see it (Matt,
  /// 2026-11-17: "presense sensing ... for users who have signed up for a username and are part of our own system").
  void setAway(bool away) {
    _away = away;
    _hub?.awayNow = away;
    _p2p?.setAway(away);
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

  // No one is found here by an address (found in review, 2026-11-23). The people come from more than one list, and on
  // Android a member of a group is among them under whatever address the group's admin wrote: a friend's number, or
  // "@friend". The first address that matched sent a friend's words to that member. Who an address is, is the record
  // for it to say (Friends.idOf, by the id its key makes), and the routes are asked by that id ([byId]).

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
    // This install's own name among its identity's devices, made once and kept. Where the choices it is kept with came
    // from another device (a backup restored here), a new one: they bring the name with them, so two devices would be
    // one to the hub, to forward secrecy and to the circles' keys. It is known by the direct network's node key, which is
    // kept where the install keeps its keys and does not come with a backup, while the node id made from it does.
    var device = app.choice('hub_device', '');
    if (device.length == 32 && await _restoredHere(app)) {
      device = '';
      // What the other device said of its own place on the direct network is not this one's.
      for (final name in [P2p.idName, P2p.cardName, P2p.toldName]) {
        app.set(name, '');
      }
    }
    if (device.length != 32) {
      device = NetCrypto.hex(NetCrypto.randomBytes(16));
      app.set('hub_device', device);
    }
    HubCarrier.device = device;
    try {
      final me = await Sms.instance.netIdentity();
      id = me.id;
      await _readPeers();
      final signer = _PhoneSigner(me.id, me.key);
      final List<Carrier> routes;
      if (carriers != null) {
        routes = [...carriers];
      } else {
        final hub = _hub = _presenceOf(HubCarrier(url: hubUrl, signer: signer)..push = _push);
        final sms = _sms = SmsCarrier(_PhoneSms());
        routes = [hub, sms];
      }
      // The direct route, where this build has the core: its node key in the secret store beside the account's words,
      // never in the account's backup; a computer's node up whenever the route is on, a phone's only while there is
      // something to say. Made apart from the other routes: a core that fails to load (a library missing, or built for
      // another machine) costs the direct route alone, and Settings › Routes says why (second review, M3).
      var p2p = _p2p = _makeDirect(signer, device, app);
      if (p2p != null) routes.add(p2p.carrier);
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
      if (p2p != null) {
        try {
          p2p
            ..attach(board)
            ..setMode(_mode)
            ..setAway(_away)
            ..addListener(_directChanged);
          _followHelpers(_hub);
          _loadDirect(p2p);
        } catch (e) {
          board.remove(p2p.carrier.id);
          _followHelpers(null);
          p2p.removeListener(_directChanged);
          unawaited(p2p.shutdown().catchError((Object _) {}));
          p2p = _p2p = null;
          directProblem = _couldNot(e);
        }
      }
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

  /// Whether the choices came here from another device: they say a node id was made here, and no node key is kept
  /// here. A secret store that can't be read says nothing either way.
  static Future<bool> _restoredHere(AppState app) async {
    if (app.choice(P2p.idName, '').isEmpty) return false;
    try {
      return (await Sms.instance.secretRead(P2p.keyName) ?? '').isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// This device's hold on the direct network, where the build has a core ([p2pNode]); null where it has none, or
  /// where the core could not be made or held (then [directProblem] says why).
  P2p? _makeDirect(NetSigner signer, String device, AppState app) {
    directProblem = null;
    try {
      final node = p2pNode?.call();
      if (node == null) return null;
      return P2p(
        node: node,
        signer: signer,
        device: device,
        secrets: _SecretFsStore(),
        plain: _ChoiceFsStore(app),
        friends: () => friends,
        mine: mine,
        // Whom the relay says is connected now: nothing about the direct network is said to anyone it would only keep it
        // for. Where there is no relay's route (a test's routes), anyone.
        present: (id) => _hub == null || _hub!.here.value.contains(id),
        policy: Sms.computer ? const P2pPolicy.computer() : const P2pPolicy(),
      );
    } catch (e) {
      directProblem = _couldNot(e);
      return null;
    }
  }

  static String _couldNot(Object e) => 'The direct route could not be started on this device ($e). The other routes work as before.';

  /// The app has come back after [away] (main.dart): the relay server's connection is made again where it may have
  /// died meanwhile, and what friends were sent and have not answered goes again once it is up (Friends).
  void resume(Duration away) {
    _hub?.nudge(away: away);
    final fs = _board?.fs;
    if (fs != null && !fs.loaded) unawaited(fs.tryLoad());
    // The network may be another than when the app was put away: the direct route's node looks at its paths again.
    final p2p = _p2p;
    if (p2p != null) {
      if (p2p.loaded) {
        p2p.networkChanged();
      } else {
        unawaited(p2p.tryLoad());
      }
    }
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
    // Who of them is a friend, which is the direct route's question, asked only where there is a direct route to ask
    // for: whom the records that say so name, by the id their key makes, and never by an address. On Android the
    // people come from those encryption is on with, the members of this phone's groups and friends by username
    // together (MainActivity's netPeers), and a group member's address is whatever the group's admin wrote: "@anything",
    // or a real friend's number (second review, M1).
    final friends = p2pNode == null ? <String>{} : await _friendsAmong(found);
    _peers
      ..clear()
      ..addAll(found);
    _friendIds = friends;
  }

  /// Those of [found] the records say are friends: friends by username in the state `yes` (lib/friends/buddies.dart),
  /// by their id and only where their key makes it; and friends by number (E2eState.isFriend), by the id the key on
  /// their record makes (android E2e.state). A record that can't be read now leaves whoever was a friend by it one.
  Future<Set<String>> _friendsAmong(Map<String, Peer> found) async {
    final friends = <String>{};
    try {
      for (final j in jsonDecode(await Sms.instance.buddiesKept()) as List) {
        final b = Buddy.fromJson(j);
        if (b == null || b.state != 'yes') continue;
        try {
          if (NetCrypto.idOf(base64Decode(b.key)) == b.id) friends.add(b.id);
        } catch (_) {}
      }
    } catch (_) {
      friends.addAll(_friendIds);
    }
    try {
      for (final s in await Sms.instance.e2eList()) {
        if (s.isFriend && s.id != null) friends.add(s.id!);
      }
    } catch (_) {
      friends.addAll(_friendIds);
    }
    return friends.where(found.containsKey).toSet();
  }

  /// Stops the routes and forgets them: the app is closing, or a test is over.
  Future<void> shutdown() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _fsTimer?.cancel();
    _fsTimer = null;
    _p2pTimer?.cancel();
    _p2pTimer = null;
    final board = _board, p2p = _p2p;
    _board = null;
    _hub = null;
    _sms = null;
    _p2p = null;
    _followHelpers(null);
    if (board != null) {
      board.changed.removeListener(notifyListeners);
      await board.stop();
    }
    if (p2p != null) {
      p2p.removeListener(_directChanged);
      await p2p.shutdown();
    }
    await board?.dispose();
    _peers.clear();
    _friendIds = {};
    recent.clear();
    id = null;
    directProblem = null;
  }

  /// Reads the people again, and starts or stops the routes to suit: after encryption was turned on with someone,
  /// or off.
  Future<void> refresh() async {
    if (_board == null) return;
    try {
      await _readPeers();
    } catch (_) {}
    await _apply();
    // Someone became a friend, or is one no longer: the direct route tells the one its card and forgets the other's.
    unawaited(_p2p?.refresh());
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
    // Another relay names its own link helpers as the app signs in to it; the one left behind's are not used on.
    _p2p?.setHelpers(const []);
    _followHelpers(hub);
    board.add(hub);
    await _apply();
    notifyListeners();
  }

  /// What [p] is called in what the routes did ([recent]): their name, else their address, else the start of their
  /// install's name. An empty address is none: a member of a group known here only by the group has one.
  static String _who(Peer p) {
    final name = p.name ?? '', address = p.address ?? '';
    return name.isNotEmpty ? name : (address.isNotEmpty ? address : p.id.substring(0, p.id.length < 6 ? p.id.length : 6));
  }

  void _received(Received r) {
    final who = _who(r.peer);
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
    final who = _who(peer);
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
