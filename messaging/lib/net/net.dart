import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../friends/buddies.dart' show Buddy;
import '../me/me.dart' show Me;
import '../platform_info.dart';
import '../sms.dart';
import 'carrier.dart';
import 'crypto.dart';
import 'forward_secrecy.dart';
import 'homes.dart';
import 'hub_carrier.dart';
import 'hub_link.dart';
import 'kept_files.dart';
import 'ledger.dart';
import 'p2p/node.dart';
import 'p2p/node_factory.dart' show letP2pNodeGo;
import 'p2p/p2p.dart';
import 'p2p/p2p_carrier.dart' show P2pCarrier;
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
/// `net_off` (the routes switched off, by name), `net_direct` (Direct switched on or off: [directName]).
///
/// **The direct route** (lib/net/p2p; docs/OPEN_NETWORK.md, section 2) is offered where the build has its core
/// ([p2pNode]) and is there only while the person has switched Direct on ([directOn]): after the relay's hub in the
/// order, linking only with this account's own devices and with friends ([friends]), and kept in step with the people,
/// how the person chose to be shown, the app being put away and coming back, and the relay in use. Until it is
/// switched on nothing of it is made or run, the core least of all: no library opened, no node, no ledger.
class Net extends ChangeNotifier implements PeerBook {
  Net._();
  static final Net instance = Net._();

  /// Makes this device's node on the direct network: the core's own (makeP2pNode, lib/net/p2p/node_factory.dart), set
  /// where the app starts on a platform whose builds carry the core (Android, the Mac, Windows, Linux). Asked for a
  /// node only once the person has switched Direct on ([directOn]), and once for as long as the app runs: until then
  /// nothing of the core runs, not so much as its library being opened (docs/OPEN_NETWORK.md, section 2: "a person who
  /// never switches Direct on runs none of it"). Null: there is no core here, no direct route is ever made, and
  /// Settings › Routes shows no Direct. Answering null where Direct is switched on: the build left its core out, and
  /// Settings › Routes says so ([directProblem]).
  static P2pNode? Function()? p2pNode;

  /// Whether Direct is on where the person has not chosen ([directName]): off in the first release that carries the
  /// core, so each person switches it on themselves; the default once Matt has used it, when this turns true and
  /// whoever switched it off stays off.
  static const directByDefault = false;

  /// The person's choice of Direct, kept with their other choices: 'on' or 'off', nothing where they have not chosen.
  /// Direct is the one route that starts off, so its choice is its own, never in `net_off`, which lists the routes
  /// switched off of those that start on: someone who never chose is told apart from someone who switched it off, and
  /// a later default ([directByDefault]) reaches the first and not the second. Seeding `net_off` with Direct instead
  /// would have made the two one.
  static const directName = 'net_direct';

  /// Whether this build offers Direct at all: it was given a way to make the core's node ([p2pNode]).
  bool get directOffered => p2pNode != null;

  /// Whether Direct is switched on: the person's choice ([directName]), or where they have not chosen,
  /// [directByDefault]. Never in a build that offers no Direct.
  bool get directOn {
    if (p2pNode == null) return false;
    final chosen = _app?.choice(directName, '') ?? '';
    return chosen == 'on' || (chosen != 'off' && directByDefault);
  }

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

  /// This account's home record and what the relay is told of where friends live (homes.dart; docs/OPEN_NETWORK.md,
  /// section 4): what lets someone on another relay be a friend. Null until the routes are set up, and where the
  /// routes are a test's own.
  Homes? get homes => _homes;
  Homes? _homes;

  /// Something small kept with the app's choices, and read back, without drawing anything again.
  String recall(String key) => _app?.choice(key, '') ?? '';
  void remember(String key, String value) => _app?.keep(key, value);

  // --- the direct route (lib/net/p2p) ---------------------------------------------------------------------------------

  P2p? _p2p;

  /// The app's hold on the direct network; null where this build has no core, Direct is switched off, or the routes
  /// are not set up.
  P2p? get p2p => _p2p;

  /// The node [p2pNode] made, kept for as long as these routes run (and [_nodeBy], what made it, and [_nodeOf], whose
  /// it is): switching Direct off stops it, and switching it on again starts the same one, so the core never holds one
  /// for each time. Never another account's: the routes going (sign-out) let it go, and so does another account, so
  /// that nothing of the core (its port least of all) links one account on this device with the next.
  P2pNode? _node;
  P2pNode? Function()? _nodeBy;
  String? _nodeOf;

  /// Who this account is to the routes, and which of its devices this is, as [start] found them: what a direct
  /// network made later, when Direct is switched on, is made with.
  NetSigner? _signer;
  String? _device;

  /// Switching Direct on and off, one change after another ([setDirect]).
  Future<void> _directTurn = Future.value();

  /// Goes up whenever what Settings › Routes shows of the direct route changes: the devices known, the links, the
  /// link helpers, what the ledger's comparisons found. Apart from the routes' own changes, which friends' unanswered
  /// words are sent again on.
  final ValueNotifier<int> direct = ValueNotifier(0);

  /// Heard from the direct network, the ledger and its check: [direct] goes up.
  void _directChanged() => direct.value++;

  /// Goes up whenever the route that last carried something to or from someone changes (Switchboard.used): Settings ›
  /// Routes draws which route each person is on from it.
  final ValueNotifier<int> routesUsed = ValueNotifier(0);

  void _routesUsedChanged() => routesUsed.value++;

  // --- checking the relay (lib/net/ledger.dart; docs/OPEN_NETWORK.md, section 3) -------------------------------------

  Ledger? _ledger;
  LedgerCheck? _check;

  /// What went to each friend and came from them, and what comparing it over direct links found of the relay; null
  /// where this build has no direct route (nothing could compare it), or the routes are not set up.
  Ledger? get ledger => _ledger;
  LedgerCheck? get check => _check;

  /// Who else holds what was sent and is unanswered, to send it again where a friend's device says it never came
  /// (Friends' list: lib/friends/friends.dart); kept here, so a check made later is given them too.
  final List<Envelope? Function(String peer, String id)> _holders = [];

  /// Adds one of them, once; the check running now is given it too.
  void addHolder(Envelope? Function(String peer, String id) holder) {
    if (_holders.contains(holder)) return;
    _holders.add(holder);
    _check?.holders.add(holder);
  }

  /// Those of [people] who are friends: whom the direct route links with, and tells where this device is. Never
  /// someone who has only asked or been asked, nor the other members of a group.
  List<Peer> get friends => [for (final p in _peers.values) if (_friendIds.contains(p.id)) p];
  Set<String> _friendIds = {};

  /// The relay's route whose link helpers are listened for ([_followHelpers]).
  HubCarrier? _helpersOf;

  /// The relay named its link helpers as the app signed in to it ([HubCarrier.helpers]).
  void _helpersSaid() {
    final hub = _helpersOf;
    if (hub != null) _p2p?.setHelpers(hub.helpers.value);
  }

  /// Listens for the link helpers [hub] names, in place of the route listened to before.
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

  // Whether the app is put away, and the names watched beside the phone's own people: told to each hub route as it
  // is made.
  bool _away = false;
  final Set<String> _alsoWatch = {};

  /// Who the relay says is connected changed.
  void _presenceChanged() {
    presence.value++;
    // Whoever came is told this device's card now, where they had not been while away.
    _p2p?.presenceChanged();
  }

  /// [hub], set up for presence: listened to, told whether the app is away, and asked about the extra names.
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
    // Put away, the app may not come back: what the ledger listed is written now.
    if (away) unawaited(_ledger?.flush());
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

  /// What [setPush] was last given.
  Map<String, Object?>? get push => _push;
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

  /// Notes something the routes did, for Settings › Network; the newest thirty are kept.
  void _note(String words, {String? via}) {
    recent.insert(0, NetEvent(words, via: via));
    if (recent.length > 30) recent.removeLast();
    notifyListeners();
  }

  /// Sets the routes up. On a computer there are none yet: it speaks through the phone it is paired with.
  /// [carriers] stands in for the phone's own routes (a test).
  ///
  /// Direct's choice is read once, here, for who is a friend ([_readPeers]), and again where the direct route is made,
  /// with nothing awaited between that and the switchboard holding it: a switch made while the routes are set up
  /// (Settings open as the app starts, a sign-in) is taken once they are, as [setDirect] takes it after, never left
  /// half made (the review of Direct's switch, 2026-11-23: switched on then, no direct network was ever made and
  /// Settings said "Starting…" for ever; switched off, the node was made and friends told all the same).
  Future<void> start(AppState app, {List<Carrier>? carriers}) async {
    if ((Sms.paired && !Sms.ownNetwork) || _board != null) return;
    _app = app;
    final wantDirect = directOn;
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
    _device = device;
    try {
      final me = await Sms.instance.netIdentity();
      id = me.id;
      await _readPeers(direct: wantDirect);
      final signer = _signer = _PhoneSigner(me.id, me.key);
      final List<Carrier> routes;
      if (carriers != null) {
        routes = [...carriers];
      } else {
        final hub = _hub = _presenceOf(HubCarrier(url: hubUrl, signer: signer)..push = _push);
        // Where this account lives, said to the relay at every sign-in with where its friends on other relays do; its
        // changes are the routes' (Settings › Routes says when the record couldn't be made).
        _homes = Homes(signer: signer, read: (key) => app.choice(key, ''), write: app.keep)
          ..attach(hub)
          ..addListener(notifyListeners);
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
      // The direct route, where this build has the core and the person has switched Direct on ([directOn]), and had
      // when the people were read (who is a friend is asked only then); otherwise nothing of it is made, the core's
      // library not even opened, until it is ([setDirect], below where it was switched on meanwhile). Its node key in
      // the secret store beside the account's words, never in the account's backup; a computer's node up whenever the
      // route is on, a phone's only while there is something to say. Made apart from the other routes: a core that
      // fails to load (a library missing, or built for another machine) costs the direct route alone, and Settings ›
      // Routes says why (second review, M3). From here to the switchboard holding it nothing is awaited.
      final madeDirect = wantDirect && directOn;
      final p2p = _p2p = madeDirect ? _makeDirect(signer, device, app) : null;
      if (p2p != null) routes.add(p2p.carrier);
      final board = _board = Switchboard(me: me.id, peers: this, carriers: routes, fs: fs);
      // The routes the person switched off; Direct by its own choice, whatever `net_off` says of it.
      board.off.addAll(app.choice('net_off', '').split(',').where((s) => s.isNotEmpty && s != P2pCarrier.routeId));
      if (!madeDirect) board.off.add(P2pCarrier.routeId);
      board.changed.addListener(notifyListeners);
      board.usedChanged.addListener(_routesUsedChanged);
      _subs.add(board.received.listen(_received));
      if (p2p != null) _holdDirect(board, p2p, me.id, device);
      // People come and go as keys are exchanged and encryption is turned on and off.
      _subs.add(Sms.instance.prefsChanged.stream.listen((_) => refresh()));
      error = null;
      await _apply();
      // What came by text while the app was closed.
      for (final kept in await Sms.instance.netSmsDrain()) {
        Sms.instance.netSms.add(kept);
      }
      // Direct switched while the routes were set up: taken now, in its turn, as a switch after would be.
      if (identical(board, _board) && directOn != madeDirect) await setDirect(directOn);
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

  /// This device's hold on the direct network, made once Direct is switched on, where the build has a core
  /// ([p2pNode]); null where it has none, or where the core could not be made or held (then [directProblem] says why).
  /// The node is made the first time and kept ([_node]): a direct network made again holds the same one.
  P2p? _makeDirect(NetSigner signer, String device, AppState app) {
    directProblem = null;
    try {
      final make = p2pNode;
      if (make == null) return null;
      var node = _nodeBy == make && _nodeOf == signer.id ? _node : null;
      if (node == null) {
        // Another account's, or another maker's: let go of, not started again for this one.
        final other = _node;
        _node = null;
        if (other != null) letP2pNodeGo(other);
        node = make();
        _node = node;
        _nodeBy = make;
        _nodeOf = signer.id;
      }
      if (node == null) {
        directProblem = 'This build of the app doesn\'t carry the direct network\'s core, so Direct can\'t be switched on here. The other routes work as before.';
        return null;
      }
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

  /// Why the direct route is not there, in words to show (Settings › Routes).
  static String _couldNot(Object e) => 'The direct route could not be started on this device ($e). The other routes work as before.';

  /// Holds [p2p], whose route is on [board] already: it hears the routes, is told how the person chose to be shown,
  /// whether the app is put away and the link helpers of the relay in use, reads what it keeps, and the ledger is
  /// started over it. As the routes are set up, and when Direct is switched on later. Where the core breaks its word on
  /// the way, nothing of it is held, and Settings › Routes says why.
  void _holdDirect(Switchboard board, P2p p2p, String me, String device) {
    try {
      p2p
        ..attach(board)
        ..setMode(_mode)
        ..setAway(_away)
        ..addListener(_directChanged);
      _followHelpers(_hub);
      // The relay names its link helpers as the app signs in to it. Signed in to already (Direct switched on after),
      // it will not name them again until the next sign-in: they are given now.
      final hub = _hub;
      if (hub != null && hub.signedInAt > 0) p2p.setHelpers(hub.helpers.value);
      _loadDirect(p2p);
    } catch (e) {
      board.remove(p2p.carrier.id);
      _followHelpers(null);
      p2p.removeListener(_directChanged);
      unawaited(p2p.shutdown().catchError((Object _) {}));
      _p2p = null;
      directProblem = _couldNot(e);
      return;
    }
    // The ledger, where there is a direct route to compare it over (docs/OPEN_NETWORK.md, section 3): told by the
    // switchboard what went and came, kept with the choices of this device only, and compared with friends' devices as
    // direct links are proved. Without a direct route nothing could compare it, so nothing is listed.
    _startLedger(board, p2p, me, device);
  }

  /// Switches Direct on or off (Settings › Routes), kept as the person's choice ([directName]), without the app
  /// starting again. On: the node, the route and the ledger are made as a start with Direct on makes them, and the
  /// route is started where there is anyone to reach (a computer's node comes up with it, a phone's when there is
  /// something to say). Off: every link is closed, the node stopped, nobody let in, and the route and the ledger taken
  /// out, so nothing of the direct network runs or is heard until Direct is switched on again. One change at a time,
  /// in the order asked; before the routes are set up, the choice alone, which they read.
  Future<void> setDirect(bool on) {
    final turn = _directTurn.then((_) => _setDirect(on));
    _directTurn = turn.catchError((Object _) {});
    return turn;
  }

  Future<void> _setDirect(bool on) async {
    if (p2pNode == null) return;
    _app?.set(directName, on ? 'on' : 'off');
    final board = _board, me = id, signer = _signer, device = _device, app = _app;
    if (board == null || me == null || signer == null || device == null || app == null) return notifyListeners();
    if (on) {
      board.off.remove(P2pCarrier.routeId);
      if (_p2p == null) {
        // Who is a friend, which only the direct route asks: asked now, as the people are read with Direct on.
        Set<String>? friends;
        try {
          friends = await _friendsAmong(Map.of(_peers));
        } catch (_) {}
        if (!identical(board, _board) || !directOn || _p2p != null) return;
        if (friends != null) _friendIds = friends;
        final p2p = _p2p = _makeDirect(signer, device, app);
        if (p2p != null) {
          board.add(p2p.carrier);
          _holdDirect(board, p2p, me, device);
        }
      }
    } else {
      board.off.add(P2pCarrier.routeId);
      directProblem = null;
      await _dropDirect(board);
    }
    if (!identical(board, _board)) return;
    await _apply();
    notifyListeners();
  }

  /// Takes the direct route out of [board], and the ledger with it: every link closed, the node stopped and nobody let
  /// in (P2p.shutdown), nothing of the direct network heard. The node itself is kept, stopped, for Direct switched on
  /// again. The ledger's lists stay, marked as not kept from now on (Ledger.pause): what comes while Direct is off is
  /// listed nowhere, and is never taken for something the relay dropped.
  Future<void> _dropDirect(Switchboard board) async {
    final p2p = _p2p, ledger = _ledger, check = _check;
    _p2p = null;
    _ledger = null;
    _check = null;
    _p2pTimer?.cancel();
    _p2pTimer = null;
    _followHelpers(null);
    if (p2p != null) board.remove(p2p.carrier.id);
    if (check != null) {
      check.removeListener(_directChanged);
      await check.stop();
    }
    if (ledger != null) {
      ledger.removeListener(_directChanged);
      if (identical(board.log, ledger)) board.log = null;
      await ledger.pause();
      await ledger.shutdown();
    }
    if (p2p != null) {
      p2p.removeListener(_directChanged);
      await p2p.shutdown();
    }
    _directChanged();
  }

  /// "Only through link helpers" (Settings › Routes › Direct): kept as the direct network keeps it
  /// ([P2p.helpersOnlyName]), so it can be chosen before Direct is ever switched on, and the first link already shows
  /// friends' devices the link helper's address and never this one's; told to the direct network where it runs.
  bool get helpersOnly => _p2p?.helpersOnly ?? _app?.choice(P2p.helpersOnlyName, '') == 'on';

  Future<void> setHelpersOnly(bool only) async {
    final p2p = _p2p;
    if (p2p != null) return p2p.setHelpersOnly(only);
    _app?.keep(P2p.helpersOnlyName, only ? 'on' : 'off');
    notifyListeners();
  }

  /// The link helpers the relay in use named as the app last signed in to it (HubCarrier.helpers); null until it has
  /// signed in to it once. What Settings › Routes says of Direct before it is on: where the relay names none, devices
  /// link only where they can reach each other as they are.
  List<String>? get relayHelpers {
    final hub = _hub;
    return hub == null || hub.signedInAt <= 0 ? null : hub.helpers.value;
  }

  /// Where the ledger is kept: files of its own, out of any backup (kept_files.dart; the review, D6); under a test,
  /// memory, so nothing is written where this computer's own app keeps its files (a test gives its own folder where
  /// that is what it looks at). Null where there is nowhere (a browser): then no ledger is kept.
  static FsStore? Function() ledgerStore = defaultLedgerStore;
  static FsStore? defaultLedgerStore() => PlatformInfo.environment.containsKey('FLUTTER_TEST') ? MemoryFsStore() : ledgerFiles();

  /// Sets up the ledger and its check over [board] and [p2p], where there is somewhere to keep it: the board writes
  /// what goes and comes in it, and the check compares it over direct links.
  void _startLedger(Switchboard board, P2p p2p, String me, String device) {
    try {
      final store = ledgerStore();
      if (store == null) return;
      // Friends as they are each time it asks: the set is made anew whenever the people are read again.
      final ledger = _ledger = Ledger(store: store, me: me, device: device, isFriend: (id) => _friendIds.contains(id));
      board.log = ledger;
      ledger.addListener(_directChanged);
      unawaited(ledger.load());
      final check = _check = LedgerCheck(ledger: ledger, board: board, p2p: p2p, relay: () => _hub);
      check.holders.addAll(_holders);
      check.addListener(_directChanged);
      check.start();
    } catch (_) {
      board.log = null;
      _ledger = null;
      _check = null;
    }
  }

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

  /// Reads from the phone who the routes reach, each with their name as the contacts have it. [direct]: whether Direct
  /// is on for who is a friend; where it is now, unless said.
  Future<void> _readPeers({bool? direct}) async {
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
    // Who of them is a friend, which is the direct route's question, asked only where Direct is switched on: whom the
    // records that say so name, by the id their key makes, and never by an address. On Android the people come from
    // those encryption is on with, the members of this phone's groups and friends by username together (MainActivity's
    // netPeers), and a group member's address is whatever the group's admin wrote: "@anything", or a real friend's
    // number (second review, M1).
    final friends = (direct ?? directOn) ? await _friendsAmong(found) : <String>{};
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
    final board = _board, p2p = _p2p, ledger = _ledger, check = _check;
    _board = null;
    _hub = null;
    _sms = null;
    _p2p = null;
    _ledger = null;
    _check = null;
    _followHelpers(null);
    _homes?.dispose();
    _homes = null;
    if (check != null) {
      check.removeListener(_directChanged);
      await check.stop();
    }
    if (ledger != null) {
      ledger.removeListener(_directChanged);
      board?.log = null;
      await ledger.shutdown();
    }
    if (board != null) {
      board.changed.removeListener(notifyListeners);
      board.usedChanged.removeListener(_routesUsedChanged);
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
    _signer = null;
    _device = null;
    // The node goes with the routes (stopped by P2p.shutdown above), let go of in the core: the next account signed in
    // here has one of its own, with nothing of this one's (its port least of all).
    final node = _node;
    _node = null;
    _nodeBy = null;
    _nodeOf = null;
    if (node != null) letP2pNodeGo(node);
    // A switch of Direct still under way belongs to the routes as they were (it sees they are gone): the next routes'
    // switching waits on none of it.
    _directTurn = Future.value();
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

  /// Turns the whole network on or off, and keeps the choice.
  Future<void> setOn(bool value) async {
    _app?.setFlag('net_on', value);
    await _apply();
    notifyListeners();
  }

  /// Switches the route [id] on or off, and keeps the choice.
  Future<void> setRoute(String id, bool value) async {
    // Direct starts off, and its choice is its own ([setDirect], [directName]).
    if (id == P2pCarrier.routeId) return setDirect(value);
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
    _app?.set('net_off', board.off.where((r) => r != P2pCarrier.routeId).join(','));
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
    await setHub(url, relay: check.relay);
    return (problem: null, declined: false);
  }

  /// Uses another relay server ([url] empty: ours again). The route is taken out and one for the new address put
  /// in its place: the rest of the app does not know. Settings › Routes goes through [useRelay], which checks first.
  ///
  /// Moving is signing a home record with the next count (homes.dart): it is made here, for the address the new relay
  /// is known by ([relay], what it said of itself when it was checked, where it said anything), and given to the relay
  /// being left while it is still connected, so that relay knows where this account lives now. The new relay is given
  /// it as the app signs in there, and friends are told a few at a time (lib/friends/buddies.dart).
  Future<void> setHub(String url, {HubRelay? relay}) async {
    final next = Homes.addressOf(relay, url.trim().isEmpty ? defaultHub : url.trim());
    try {
      // (The relay being left answers the new record, and friends on it are told, before it is left: ten seconds.)
      if (next != null) await _homes?.moveTo(next).timeout(const Duration(seconds: 10));
    } catch (_) {}
    _app?.set('net_hub', url.trim());
    final board = _board, old = _hub, me = id;
    if (board == null || old == null || me == null) return;
    await old.stop();
    old.presence.removeListener(_presenceChanged);
    final hub = _hub = _presenceOf(HubCarrier(url: hubUrl, signer: old.signer)..push = _push);
    _homes?.attach(hub);
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

/// Data texts by the phone's native side, for the SMS route.
class _PhoneSms implements SmsBridge {
  @override
  Future<bool> available() => Sms.instance.netSmsAvailable();
  @override
  Future<void> send(String address, Uint8List bytes) => Sms.instance.netSmsSend(address, bytes);
  @override
  Stream<({String address, Uint8List bytes})> get incoming => Sms.instance.netSms.stream;
}
