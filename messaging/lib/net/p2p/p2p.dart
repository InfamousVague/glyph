import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../carrier.dart';
import '../crypto.dart';
import '../forward_secrecy.dart' show FsStore;
import '../hub_carrier.dart' show NetSigner;
import '../packet.dart';
import '../switchboard.dart';
import 'card.dart';
import 'node.dart';
import 'p2p_carrier.dart';

/// What makes a timer: `Timer.new`, or a test's clock.
typedef P2pTimer = Timer Function(Duration after, void Function() then);

/// When a device's node runs and how long the direct route waits for things. A phone's and a computer's differ in
/// one thing, [stayUp]; a test shortens the rest.
@immutable
class P2pPolicy {
  const P2pPolicy({
    this.stayUp = false,
    this.idle = const Duration(minutes: 2),
    this.relayGone = const Duration(seconds: 15),
    this.quiet = const Duration(seconds: 90),
    this.dialFor = const Duration(seconds: 5),
    this.redialAfter = const Duration(seconds: 30),
    this.meetsAnHour = 6,
    this.saysAnHour = 12,
    this.takesAnHour = 30,
    this.mostDials = 12,
    this.ackWait = const Duration(seconds: 4),
  });

  /// A computer's: its node is up whenever Direct is on.
  const P2pPolicy.computer() : this(stayUp: true);

  /// The node is up whenever Direct is on (a computer). Where false (a phone) it is started only when there is
  /// something to say, and stopped [idle] after its last stream closed: a node keeps every path warm every few
  /// seconds, which is megabytes a day and a radio that never sleeps (docs/OPEN_NETWORK.md, section 2).
  final bool stayUp;
  final Duration idle;

  /// How long the relay must be away, with the app in use, before a device brings its node up by itself and dials by
  /// what it last heard: with the relay gone there is nothing to ask through.
  final Duration relayGone;

  /// A stream is let go after this long with nothing said on it.
  final Duration quiet;

  /// How long a send has, in all, to get a packet to a device: bringing the node up, dialling, and the device proving
  /// whose it is.
  final Duration dialFor;

  /// A device that could not be reached is not dialled again for this long, unless it says anew where it is. A node
  /// that could not start is tried again after as long.
  final Duration redialAfter;

  /// A `meet` is answered at most this many times an hour for one friend, and sent as often at most.
  final int meetsAnHour;

  /// The most cards and asks sent to one account in an hour, whatever it sends: nothing someone else's device says
  /// can make this one say more.
  final int saysAnHour;

  /// The most cards looked at from one account in an hour. Checking one is a signature's arithmetic and keeping one
  /// is a write: an account that sends them without end is not let cost this device more than that.
  final int takesAnHour;

  /// The most devices dialled at once when the relay has gone ([relayGone]), the ones heard from latest first.
  final int mostDials;

  /// How long the switchboard waits for an answer to what went by the direct route before it tries the next.
  final Duration ackWait;
}

/// One device a card is held for: whose it is, where it last said it was, and when it was last heard from.
@immutable
class P2pDevice {
  const P2pDevice(this.card, {this.where, this.heard = 0});
  final DeviceCard card;

  /// Where it last said it can be found; null where it has not said (a phone's node is mostly down).
  final Whereabouts? where;

  /// When its card or its whereabouts last came, by this device's clock, in milliseconds.
  final int heard;

  String get account => card.account;
  String get nodeId => card.nodeId;

  Map<String, dynamic> toJson() => {'c': card.toJson(), 'w': ?where?.toJson(), 'h': heard};

  /// Null where [j] isn't one, or its card is no longer good at [now].
  static P2pDevice? fromJson(Object? j, {required int now}) {
    if (j is! Map) return null;
    final card = DeviceCard.fromJson(j['c'], now: now);
    if (card == null) return null;
    final h = j['h'];
    return P2pDevice(card, where: P2p.whereOf(j['w'], now: now), heard: h is int ? h : 0);
  }
}

/// The app's hold on the direct network (docs/OPEN_NETWORK.md, section 2; Matt, 2026-11-22: "p2p delivery with the
/// relay as a primary source but have p2p as a secondary back up"): this device's node key and card, the cards of the
/// devices it links with, what it has told whom, and when its node runs. The route that carries packets over it is
/// [carrier] (p2p_carrier.dart); the node itself is [node] (node.dart), the Rust core or a test's stand-in.
///
/// **Who a device links with.** Its own account's other devices and its friends' devices, and nobody else: [friends]
/// says who the friends are (never someone who has only asked, or a group's other members), and the account's own
/// devices are reached through the account's own name ([mine]). Only they are told this device's card and where it is,
/// in sealed envelopes of kind [kind], never asking for an answer, never by a route that carries only small packets
/// and never by the direct route itself:
///
///     {"t":"card", "c": device card, "w": {"r": link helper address, "a": [addresses], "t": ms}, "h": [card names]}
///     {"t":"card?", "h": […]}          tell me yours
///     {"t":"meet", "c": …, "w": …}     I am up, here: bring your node up and link, and tell me where you are
///
/// A card is taken only from a sealed envelope whose sender is the account the card names. For each account at most
/// [mostDevices] devices are kept (`p2p_cards`), dropped when the card runs out or the friend is one no longer. What
/// was told to whom is kept too (`p2p_told`), so a card is sent once and not at every start: to a friend never told
/// this card, when asked, and in answer to a device of theirs that does not hold it.
///
/// `h` is how a device knows that: the names ([DeviceCard.tag]) of the cards the sender holds for the account it is
/// writing to. A relay hands a packet to the devices of an account that are connected, and one it kept to whichever
/// comes first, so a card told to an account need not have reached every device of it. A device that hears from one
/// that does not list its own card answers with it; one that is listed says nothing. So two devices settle in at
/// most a card each and an answer each, and nothing more is said at any later start.
///
/// **The node key** is 32 random bytes made here and kept where the install keeps its keys (`p2p_node`), never in the
/// account's backup. The node id it makes is learned once ([P2pNode.idOf]) and kept with the app's choices, so a card
/// can be made while the node is down. A key made under one account is never carried to another: an install that has
/// become someone else makes a new one, and signing out deletes it ([wipe]).
///
/// **When the node runs** is [P2pPolicy]'s: a computer's whenever Direct is on, a phone's only while there is
/// something to say.
class P2p extends ChangeNotifier {
  P2p({
    required this.node,
    required this.signer,
    required this.device,
    required FsStore secrets,
    required FsStore plain,
    required List<Peer> Function() friends,
    Future<Peer?> Function()? mine,
    this.policy = const P2pPolicy(),
    DateTime Function()? now,
    P2pTimer? timer,
  })  : _secrets = secrets,
        _plain = plain,
        _friends = friends,
        _mine = mine,
        _now = now ?? DateTime.now,
        timer = timer ?? Timer.new {
    if (!_hex32.hasMatch(device)) throw ArgumentError('a device is named by 32 hex digits');
    carrier = P2pCarrier(this);
    node.state.addListener(_nodeState);
    _paths = node.paths.listen((_) {
      if (!_gone) notifyListeners();
    }, onError: (Object _) {});
  }

  /// The envelope kind devices tell each other where they are with.
  static const kind = 'p2p';

  /// Where the node key is kept, in the install's secret store.
  static const keyName = 'p2p_node';

  /// What is kept with the app's choices: the node id, this device's card, the cards held, what was told to whom,
  /// and the link helpers the relay last named. All of it goes at sign-out ([keptNames]).
  static const idName = 'p2p_id';
  static const cardName = 'p2p_card';
  static const cardsName = 'p2p_cards';
  static const toldName = 'p2p_told';
  static const helpersName = 'p2p_helpers';
  static const keptNames = [idName, cardName, cardsName, toldName, helpersName];

  /// The person's choice of "Only through link helpers": 'on' or not. A choice, so it stays at sign-out.
  static const helpersOnlyName = 'p2p_helpers_only';

  /// The most devices kept for one account; the one heard from longest ago goes first.
  static const mostDevices = 8;

  /// The most link helpers taken from a relay, and the longest address one may have.
  static const mostHelpers = 4;
  static const longestHelper = 200;

  /// Someone who was told this device's card and of whom none is held is asked for theirs half a minute after (their
  /// own telling did not cross it: they hold this device's card already, or what the relay kept was lost), and then
  /// once a week at most: a friend whose build has no direct route never answers.
  static const askAfter = Duration(seconds: 30);
  static const askEvery = Duration(days: 7);

  static const _hour = 60 * 60 * 1000;
  static final _hex32 = RegExp(r'^[0-9a-f]{32}$');
  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');

  final P2pNode node;

  /// The account: its name, its key, and a way to sign with it (on a phone, the keystore's).
  final NetSigner signer;

  /// Which of the account's devices this is (`hub_device`).
  final String device;
  final P2pPolicy policy;
  final FsStore _secrets;
  final FsStore _plain;
  final List<Peer> Function() _friends;
  final Future<Peer?> Function()? _mine;
  final DateTime Function() _now;

  /// What the direct network's waits are timed by.
  final P2pTimer timer;

  /// The route that carries packets over the direct network.
  late final P2pCarrier carrier;

  Uint8List? _key;
  String? _nodeId;
  DeviceCard? _card;
  final Map<String, List<P2pDevice>> _cards = {};
  final Map<String, _Told> _told = {};
  Map<String, Peer> _friendsNow = const {};
  Peer? _minePeer;
  final Set<String> _allowed = {};
  List<String> _helpers = const [];
  bool _helpersSaid = false;
  bool _helpersOnly = false;
  bool _helpersOnlySaid = false;
  bool _loaded = false;
  Future<void>? _loading;
  bool _on = false;
  bool _invisible = false;
  bool _away = false;
  bool _gone = false;
  bool _wiped = false;

  Switchboard? _board;
  StreamSubscription<Received>? _heard;
  StreamSubscription<P2pPath>? _paths;
  bool _relayWasUp = false;

  P2pConfig? _running;
  Future<void>? _starting;
  bool _failed = false;
  String? _problem;
  int _busy = 0;
  Timer? _idle, _relayTimer, _retry, _due, _askTimer;
  bool _telling = false, _tellAgain = false;
  Future<bool>? _renewing;

  /// When this device last said something to each account, answered or sent a `meet`, and looked at a card of
  /// theirs, within the hour.
  final Map<String, List<int>> _said = {}, _meetsAnswered = {}, _meetsSent = {}, _looked = {};

  /// Until when an answer to a `meet` may still come from each account.
  final Map<String, int> _awaited = {};

  /// What came before [load] was done, at most [mostEarly] of it.
  final List<Received> _early = [];
  static const mostEarly = 64;

  // --- what the route and the screens ask ---------------------------------------------------------------------------

  /// This account's name.
  String get me => signer.id;
  int get nowMs => _now().millisecondsSinceEpoch;

  /// Whether what is kept has been read ([load]). Until then nothing is carried.
  bool get loaded => _loaded;

  /// Signed out of ([wipe]): nothing is read, made or carried again until the app has started anew.
  bool get wiped => _wiped;

  /// Direct is switched on: the route is started (Settings › Routes).
  bool get on => _on;

  /// The app is in use, not put away, as it was last told ([setAway]): only then does a device go looking for the
  /// others by itself when the relay has gone.
  bool get inUse => !_away;

  /// This device's node id, once read; and its card, once made.
  String? get nodeId => _nodeId;
  DeviceCard? get card => _card;

  /// The node could not start, and why, in words to show.
  bool get failed => _failed;
  String? get problem => _problem;

  /// The link helpers in use, as the relay last named them; none: links are made on one network only.
  List<String> get helpers => _helpers;

  /// Never a straight path: a friend's device sees the link helper's address, not this one's.
  bool get helpersOnly => _helpersOnly;

  /// Whether this device links with [account] at all now: its own, or a friend's while the person is not Invisible.
  bool mayLink(String account) => account == me ? _minePeer != null : !_invisible && _friendsNow.containsKey(account);

  /// The devices of [account] a card is held for and still good: this account's own other devices for [me].
  List<P2pDevice> devicesOf(String account) {
    final list = _cards[account];
    if (list == null) return const [];
    final now = nowMs;
    return [for (final d in list) if (!d.card.expired(now)) d];
  }

  /// The device of [account] at [nodeId], where a good card says so.
  P2pDevice? deviceAt(String account, String nodeId) => devicesOf(account).where((d) => d.nodeId == nodeId).firstOrNull;

  /// The accounts this device links with whose cards name [nodeId]: whose device a node that dials in may be. Which
  /// of them it is, the device proves on the stream (p2p_carrier.dart).
  List<String> accountsOf(String nodeId) => [
        for (final e in _cards.entries)
          if (mayLink(e.key) && devicesOf(e.key).any((d) => d.nodeId == nodeId)) e.key,
      ];

  /// The key two devices prove themselves to each other with on a stream: made from what this account and [account]
  /// seal their packets with (the account's own for [me]), and used for nothing else. Null where no key is held.
  Uint8List? linkKey(String account) {
    final key = (account == me ? _minePeer : _friendsNow[account])?.key;
    return key == null ? null : NetCrypto.derive(key, 'p2p link');
  }

  /// Where [d] is dialled: where it last said it was, with no address of its own where the person chose "Only through
  /// link helpers". A link helper only where it is one this device was given by its own relay: a device does not
  /// connect to a server someone else names. Where [d] named none of them (a phone tells its card with its node
  /// down, so it says nothing of where it is), this device's own first one is tried: a relay names the same helpers
  /// to everyone on it.
  Whereabouts? hintFor(P2pDevice d) {
    final w = d.where;
    final hint = Whereabouts(helper: _helpers.contains(w?.helper) ? w!.helper : _helpers.firstOrNull, addresses: _helpersOnly || w == null ? const [] : w.addresses, at: w?.at ?? 0);
    return hint.isEmpty ? null : hint;
  }

  /// Whether an answer to a `meet` may still come from [account]: a dial that failed may yet be made again.
  bool awaited(String account) => nowMs < (_awaited[account] ?? 0);

  /// How many friends' devices are known, and how many of this account's own.
  int get friendsDevices => _cards.keys.where((a) => a != me).fold(0, (n, a) => n + devicesOf(a).length);
  int get ownDevices => devicesOf(me).length;

  /// Something is under way that needs the node: it is not stopped for being idle meanwhile.
  void busy(bool yes) {
    _busy += yes ? 1 : -1;
    if (_busy <= 0) {
      _busy = 0;
      _idleSoon();
    }
  }

  /// A stream opened, proved whose it is, or closed (p2p_carrier.dart).
  void linesChanged() {
    _idleSoon();
    if (!_gone) notifyListeners();
  }

  // --- reading what is kept --------------------------------------------------------------------------------------------

  /// [load], answering whether it worked instead of throwing: the app tries again until it does (a secret store that
  /// can't be read yet, as an iPhone's before its first unlock).
  Future<bool> tryLoad() async {
    if (_loaded) return true;
    try {
      await load();
      return _loaded;
    } catch (_) {
      return false;
    }
  }

  /// Reads the node key (making one where there is none), the node id, this device's card and the cards held. Throws
  /// where the secret store can't be read: no key is made that can't be kept.
  Future<void> load() => _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    if (_loaded || _gone || _wiped) return;
    final keptKey = await _secrets.read(keyName);
    var key = keptKey != null && _hex64.hasMatch(keptKey) ? NetCrypto.unhex(keptKey) : null;
    Map? id;
    try {
      id = jsonDecode(await _plain.read(idName) ?? '') as Map;
    } catch (_) {}
    // A node key made while this install was another account is never carried over: the two would be one device to
    // anyone who knew both.
    if (id != null && id['a'] is String && id['a'] != me) {
      await forget(_secrets, _plain);
      key = null;
      id = null;
    }
    if (key == null) {
      key = NetCrypto.randomBytes(32);
      await _secrets.write(keyName, NetCrypto.hex(key));
    }
    final tag = NetCrypto.hex(NetCrypto.sha256([...utf8.encode('ghost-p2p node key '), ...key]).sublist(0, 8));
    var nodeId = id != null && id['g'] == tag && isNodeId(id['n']) ? id['n'] as String : null;
    if (nodeId == null) {
      nodeId = await _answered(node.idOf(key));
      if (!isNodeId(nodeId)) throw StateError('the direct network gave no node id');
      await _plain.write(idName, jsonEncode({'a': me, 'g': tag, 'n': nodeId}));
    }
    final now = nowMs;
    // The link helpers the relay last named, until it names them again: a start while it is away still has them.
    if (!_helpersSaid) {
      try {
        _helpers = tidyHelpers(jsonDecode(await _plain.read(helpersName) ?? '') as List);
      } catch (_) {}
    }
    if (!_helpersOnlySaid) _helpersOnly = await _plain.read(helpersOnlyName) == 'on';
    // The cards held, each checked again as it was when it came: a device's, of the account it is kept under.
    final cards = <String, List<P2pDevice>>{};
    var checked = 0;
    try {
      final kept = jsonDecode(await _plain.read(cardsName) ?? '');
      if (kept is Map) {
        for (final e in kept.entries) {
          final account = e.key, list = e.value;
          if (account is! String || list is! List) continue;
          final devices = <P2pDevice>[];
          for (final j in list.take(mostDevices)) {
            final d = P2pDevice.fromJson(j, now: now);
            if (d != null && d.account == account && d.nodeId != nodeId && !devices.any((o) => o.nodeId == d.nodeId || o.card.device == d.card.device)) devices.add(d);
            // A signature is some milliseconds of arithmetic: with many kept, the screen is drawn between them.
            if (++checked % 8 == 0) await Future<void>.delayed(Duration.zero);
          }
          if (devices.isNotEmpty) cards[account] = devices;
        }
      }
    } catch (_) {}
    final told = <String, _Told>{};
    try {
      final kept = jsonDecode(await _plain.read(toldName) ?? '');
      if (kept is Map) {
        for (final e in kept.entries) {
          final t = _Told.fromJson(e.value);
          if (e.key is String && t != null) told[e.key as String] = t;
        }
      }
    } catch (_) {}
    DeviceCard? card;
    try {
      card = DeviceCard.fromJson(jsonDecode(await _plain.read(cardName) ?? ''), now: now);
    } catch (_) {}
    if (_gone || _wiped) return;
    _key = key;
    _nodeId = nodeId;
    _card = card != null && card.account == me && card.device == device && card.nodeId == nodeId ? card : null;
    _cards
      ..clear()
      ..addAll(cards);
    _told
      ..clear()
      ..addAll(told);
    _friendsNow = _readFriends();
    _loaded = true;
    carrier.restate();
    // What came while this was being read is looked at before anything is told: whoever is then told is told with
    // their own card already held.
    final early = List.of(_early);
    _early.clear();
    early.forEach(_received);
    await refresh();
    if (!_loaded) return;
    if (_on) _wake();
    _watchRelay();
  }

  Map<String, Peer> _readFriends() {
    try {
      return {for (final p in _friends()) if (p.key != null && p.id != me) p.id: p};
    } catch (_) {
      return _friendsNow;
    }
  }

  // --- keeping in step with the people, and telling them -----------------------------------------------------------------

  /// The people changed, or Direct was switched on: the cards of those who are friends no longer go (removed or
  /// blocked), those run out go, this device's card is made again where it is due, and whoever has not been told it
  /// is told.
  Future<void> refresh() async {
    if (!_loaded) return;
    // This account's own devices as one peer; where that can't be asked now, as it was.
    var mine = _minePeer;
    try {
      mine = await _mine?.call();
    } catch (_) {}
    if (!_loaded) return;
    _minePeer = mine != null && mine.id == me && mine.key != null ? mine : null;
    _friendsNow = _readFriends();
    var changed = false;
    for (final account in _cards.keys.toList()) {
      if (account == me ? _minePeer != null : _friendsNow.containsKey(account)) continue;
      _cards.remove(account);
      changed = true;
    }
    for (final account in _told.keys.toList()) {
      if (account == me ? _minePeer != null : _friendsNow.containsKey(account)) continue;
      _told.remove(account);
      _saveTold();
    }
    // Nothing is kept of anyone who is not one of them: what was counted of them goes too.
    for (final counted in [_said, _meetsAnswered, _meetsSent, _looked]) {
      counted.removeWhere((account, _) => account != me && !_friendsNow.containsKey(account));
    }
    _awaited.removeWhere((account, _) => account != me && !_friendsNow.containsKey(account));
    if (_dropRunOut()) changed = true;
    if (changed) _saveCards();
    _allow();
    await _renew();
    if (!_loaded) return;
    _watchDue();
    if (changed) notifyListeners();
    _quietly(_tell());
  }

  bool _dropRunOut() {
    final now = nowMs;
    var changed = false;
    for (final account in _cards.keys.toList()) {
      final list = _cards[account]!;
      final before = list.length;
      list.removeWhere((d) => d.card.expired(now));
      if (list.length != before) changed = true;
      if (list.isEmpty) _cards.remove(account);
    }
    return changed;
  }

  /// Lets in the nodes cards are held for, and nobody else. While the person is Invisible, only this account's own:
  /// a friend's device linked would know this one is here.
  void _allow() {
    final want = <String>{};
    for (final account in _cards.keys) {
      if (!mayLink(account)) continue;
      for (final d in devicesOf(account)) {
        want.add(d.nodeId);
      }
    }
    for (final gone in _allowed.difference(want)) {
      _allowed.remove(gone);
      try {
        node.disallow(gone);
      } catch (_) {}
      carrier.forget(gone);
    }
    for (final fresh in want.difference(_allowed)) {
      try {
        node.allow(fresh, const {P2pChannel.packets});
        _allowed.add(fresh);
      } catch (_) {}
    }
  }

  /// Makes this device's card where it has none, a week or less is left on it, or the node id is another.
  Future<bool> _renew() => _renewing ??= _renewNow().whenComplete(() => _renewing = null);

  Future<bool> _renewNow() async {
    final nodeId = _nodeId;
    if (nodeId == null) return false;
    final had = _card;
    if (had != null && !had.due(nowMs, nodeId: nodeId, device: device, account: me)) return false;
    try {
      final made = await DeviceCard.make(signer, device: device, nodeId: nodeId, now: _now());
      if (!_loaded) return false;
      _card = made;
      _signFailed = 0;
      await _plain.write(cardName, jsonEncode(made.toJson()));
      return true;
    } catch (_) {
      // Not signed now (a keystore that would not): the one held serves while it is good, and it is tried again
      // [signAgain] later.
      _signFailed = nowMs;
      if (had != null && (had.expired(nowMs) || had.nodeId != nodeId)) _card = null;
      return false;
    }
  }

  /// When this device's card last could not be signed, in milliseconds; 0 where the last try made one.
  int _signFailed = 0;

  /// Looks again when the next card runs out, or this device's own is due. A card of its own that could not be made
  /// (a keystore that would not sign) is tried again [signAgain] later, not at once.
  void _watchDue() {
    _due?.cancel();
    _due = null;
    if (!_loaded) return;
    final now = nowMs;
    int? next;
    void at(int ms) => next = next == null || ms < next! ? ms : next;
    final own = _card, due = own == null ? now : own.until - DeviceCard.renewWith.inMilliseconds;
    at(due <= now && _signFailed > 0 ? _signFailed + signAgain.inMilliseconds : due);
    for (final list in _cards.values) {
      for (final d in list) {
        at(d.card.until);
      }
    }
    final wait = next! - now;
    _due = timer(Duration(milliseconds: wait < 1000 ? 1000 : wait + 1000), () {
      _due = null;
      _quietly(refresh());
    });
  }

  /// How long after this device's card could not be signed it is tried again.
  static const signAgain = Duration(minutes: 10);

  /// Runs [work] without waiting for it; what goes wrong in it stays in it.
  static void _quietly(Future<void> work) => unawaited(work.then((_) {}, onError: (Object _) {}));

  /// Whether a route other than this one, that carries big packets and costs nothing, is up: what cards and meets go
  /// by.
  bool get _through => _throughRoutes.any((c) => c.state.value == CarrierState.up);

  Iterable<Carrier> get _throughRoutes {
    final board = _board;
    if (board == null) return const [];
    return board.carriers.where((c) => c.id != carrier.id && !board.off.contains(c.id) && !c.traits.metered && c.traits.maxPacket > Switchboard.smallRoute);
  }

  bool get _relayUp => _board?.carrier('hub')?.state.value == CarrierState.up;

  /// Says [body] to [peer], sealed, by a route that is not this one. False where none took it, or this device has
  /// said as much to them as it will in an hour.
  Future<bool> _say(Peer peer, Map<String, dynamic> body, {bool limited = true}) async {
    final board = _board;
    if (board == null || !_on) return false;
    final only = {for (final c in _throughRoutes) c.id};
    if (only.isEmpty) return false;
    final now = nowMs;
    final times = _said[peer.id] ??= [];
    times.removeWhere((t) => now - t >= _hour);
    if (limited && times.length >= policy.saysAnHour) return false;
    times.add(now);
    try {
      return (await board.send(peer, Envelope(kind: kind, body: body, ack: false, at: now), only: only)).sent;
    } catch (_) {
      return false;
    }
  }

  /// This device's card for [to], with where it is now where its node is up, and which of their cards it holds.
  Map<String, dynamic> _message(String what, String to) => {'t': what, 'c': _card!.toJson(), 'w': ?_whereNow()?.toJson(), 'h': _held(to)};

  /// The names of the cards held for [account]: what tells its devices whether this one has heard of them.
  List<String> _held(String account) => [for (final d in devicesOf(account).take(mostDevices)) d.card.tag];

  /// Whether the device that said [body] holds this device's card, by its own word.
  bool _holdsMine(Map<String, dynamic> body) {
    final h = body['h'], mine = _card?.tag;
    return mine != null && h is List && h.take(2 * mostDevices).contains(mine);
  }

  /// Where this device can be found now, as it tells it: nothing while its node is down, no address of its own where
  /// the person chose "Only through link helpers", and no link helper but one its relay named.
  Whereabouts? _whereNow() {
    if (node.state.value != P2pState.up) return null;
    final w = node.whereabouts.value;
    if (w == null) return null;
    final said = Whereabouts(
      helper: _helpers.contains(w.helper) ? w.helper : null,
      addresses: _helpersOnly ? const [] : List.unmodifiable(w.addresses.where(isAddress).take(Whereabouts.mostAddresses)),
      at: nowMs,
    );
    return said.isEmpty ? null : said;
  }

  /// Tells whoever has not been told this device's card: its own account's devices, and each friend (none while the
  /// person is Invisible). Whoever was told and has not said theirs is asked, half a minute after and then once a
  /// week; whoever was asked before is asked once a week, with the cards held, so a device of theirs not among them
  /// says its own.
  Future<void> _tell() async {
    if (_telling) {
      _tellAgain = true;
      return;
    }
    _telling = true;
    try {
      do {
        _tellAgain = false;
        if (!_loaded || !_on || _card == null || !_through) break;
        // A computer's node is up whenever Direct is on: its card goes with where it is.
        if (policy.stayUp) {
          try {
            await up();
            await _whereKnown(nowMs + 1000);
          } catch (_) {}
        }
        final card = _card;
        if (!_loaded || !_on || card == null) break;
        final tag = card.tag;
        for (final peer in [?_minePeer, if (!_invisible) ..._friendsNow.values]) {
          if (!_loaded || !_on || !identical(card, _card)) break;
          if (!mayLink(peer.id)) continue;
          final told = _told[peer.id];
          final now = nowMs;
          if (told?.card != tag) {
            if (await _say(peer, _message('card', peer.id))) _wasTold(peer.id, tag, asked: told?.asked ?? 0);
          } else if (now - told!.asked >= askEvery.inMilliseconds && (told.asked > 0 || (devicesOf(peer.id).isEmpty && now - told.at >= askAfter.inMilliseconds))) {
            // Asked with the cards held: only a device of theirs that is not among them answers.
            if (await _say(peer, {'t': 'card?', 'h': _held(peer.id)}) && _loaded) {
              _told[peer.id] = _Told(tag, told.at, now);
              _saveTold();
            }
          }
        }
        // Whoever was just told and holds this device's card already will not answer by themselves: looked at again
        // once theirs has had time to come.
        if (_loaded && _on && _askTimer == null && _told.entries.any((e) => e.value.asked == 0 && devicesOf(e.key).isEmpty && mayLink(e.key))) {
          _askTimer = timer(askAfter + const Duration(seconds: 1), () {
            _askTimer = null;
            _quietly(_tell());
          });
        }
      } while (_tellAgain);
    } finally {
      _telling = false;
    }
  }

  void _wasTold(String account, String tag, {int asked = 0}) {
    if (!_loaded) return;
    _told[account] = _Told(tag, nowMs, asked);
    _saveTold();
  }

  /// Sends [peer] this device's card, with where it is: an answer to their asking, to a device of theirs that does
  /// not hold it, or to a `meet`.
  Future<void> _answer(Peer peer, {bool limited = true}) async {
    final card = _card;
    if (card == null || !_on || !mayLink(peer.id)) return;
    if (await _say(peer, _message('card', peer.id), limited: limited)) _wasTold(peer.id, card.tag, asked: _told[peer.id]?.asked ?? 0);
  }

  // --- what others say ---------------------------------------------------------------------------------------------------

  /// Hears the routes [board] brings and speaks through them. The route itself is added to the board by whoever made
  /// both ([Switchboard.add] of [carrier]).
  void attach(Switchboard board) {
    detach();
    _board = board;
    _heard = board.received.listen(_received);
    board.changed.addListener(_routesChanged);
    _relayWasUp = _relayUp;
    _watchRelay();
  }

  void detach() {
    _heard?.cancel();
    _heard = null;
    _board?.changed.removeListener(_routesChanged);
    _board = null;
  }

  void _received(Received r) {
    final e = r.envelope;
    if (e.kind != kind || !r.sealed || _gone || _wiped) return;
    // Before what is kept has been read (the relay hands over what it held as soon as the app signs in): looked at
    // once it has.
    if (!_loaded) {
      if (_early.length < mostEarly) _early.add(r);
      return;
    }
    final from = r.peer.id, own = from == me;
    // Only this account's own devices and friends: a card in an envelope from anyone else is not looked at.
    if (own) {
      if (r.peer.key == null) return;
      _minePeer ??= r.peer;
    } else if (!_friendsNow.containsKey(from)) {
      _friendsNow = _readFriends();
      if (!_friendsNow.containsKey(from)) return;
    }
    // Never by a route that carries only small packets (a data text).
    if ((_board?.carrier(r.via)?.traits.maxPacket ?? 0) <= Switchboard.smallRoute) return;
    final peer = own ? _minePeer! : _friendsNow[from]!;
    switch (e.body['t']) {
      case 'card':
        // A device that does not hold this one's card is told it.
        if (_take(from, e.body) != null && !_holdsMine(e.body)) _answerOrLater(peer);
      case 'card?':
        if (!_holdsMine(e.body)) _answerOrLater(peer);
      case 'meet':
        final took = _take(from, e.body);
        if (took == null) break;
        // One the relay kept for a while is no longer "I am up": its card is taken, and it is answered as a card is.
        if ((nowMs - e.at).abs() <= Switchboard.freshFor.inMilliseconds && _mayMeet(peer)) {
          _quietly(_met(peer, took));
        } else if (!_holdsMine(e.body)) {
          _answerOrLater(peer);
        }
    }
  }

  /// Answers [peer] with this device's card. Not while Direct is off, and not a friend while the person is Invisible
  /// (an answer now says this device is here): they are told when that ends.
  void _answerOrLater(Peer peer) {
    if (!_on || (_invisible && peer.id != me)) {
      if (_told.remove(peer.id) != null) _saveTold();
      return;
    }
    _quietly(_answer(peer));
  }

  /// Takes the card in [body], and where its device is, as [from]'s: only a card that names [from], checked whole
  /// (card.dart), newer than or the same as the one held for that device. The device as it is held now; null where
  /// nothing was taken.
  P2pDevice? _take(String from, Map<String, dynamic> body) {
    final now = nowMs;
    // No more of one account's cards are looked at in an hour than [P2pPolicy.takesAnHour].
    final looked = _looked[from] ??= [];
    looked.removeWhere((t) => now - t >= _hour);
    if (looked.length >= policy.takesAnHour) return null;
    looked.add(now);
    final card = DeviceCard.fromJson(body['c'], now: now);
    if (card == null || card.account != from) return null;
    // Never this device itself, under anyone's name; nor, under a friend's, a device of this account's own.
    if (card.nodeId == _nodeId || (from == me && card.device == device)) return null;
    if (from != me && devicesOf(me).any((d) => d.nodeId == card.nodeId)) return null;
    // This account's own word for one of its devices: a friend's that it is his goes.
    if (from == me) {
      for (final e in _cards.entries) {
        if (e.key != me) e.value.removeWhere((d) => d.nodeId == card.nodeId);
      }
      _cards.removeWhere((account, list) => list.isEmpty);
    }
    final list = _cards[from] ?? <P2pDevice>[];
    final at = list.indexWhere((d) => d.card.device == card.device);
    final had = at < 0 ? null : list[at];
    // An older card than the one held is a copy from before.
    if (had != null && card.made < had.card.made) return null;
    final sameNode = had != null && had.nodeId == card.nodeId;
    var where = whereOf(body['w'], now: now);
    // Where it is: what it says now, unless that is older than what is held for the same node.
    if (sameNode && had.where != null && (where == null || where.at < had.where!.at)) where = had.where;
    final taken = P2pDevice(card, where: where, heard: now);
    if (had != null) {
      list[at] = taken;
    } else {
      list.add(taken);
    }
    // One node, one device of an account; and no more than [mostDevices] of them, the longest unheard going first.
    list.removeWhere((d) => !identical(d, taken) && d.nodeId == card.nodeId);
    while (list.length > mostDevices) {
      list.remove(list.where((d) => !identical(d, taken)).reduce((a, b) => a.heard <= b.heard ? a : b));
    }
    _cards[from] = list;
    _saveCards();
    _allow();
    _watchDue();
    carrier.heard(card.nodeId);
    notifyListeners();
    return taken;
  }

  /// Where a device says it is, from [j]: as node.dart reads it, with only addresses that are addresses (an IP and a
  /// port), and its time held to this device's clock. Null where it says nothing usable.
  static Whereabouts? whereOf(Object? j, {required int now}) {
    final w = Whereabouts.fromJson(j);
    if (w == null) return null;
    final said = Whereabouts(helper: w.helper, addresses: List.unmodifiable(w.addresses.where(isAddress)), at: w.at <= 0 || w.at > now ? now : w.at);
    return said.isEmpty ? null : said;
  }

  /// Whether [a] is an address a node can be dialled at: `1.2.3.4:5678` or `[2001:db8::1]:5678`.
  static bool isAddress(String a) {
    final colon = a.lastIndexOf(':');
    if (colon <= 0 || !RegExp(r'^[0-9]{1,5}$').hasMatch(a.substring(colon + 1))) return false;
    final port = int.parse(a.substring(colon + 1));
    if (port < 1 || port > 65535) return false;
    final host = a.substring(0, colon);
    try {
      if (host.startsWith('[') && host.endsWith(']')) {
        Uri.parseIPv6Address(host.substring(1, host.length - 1));
      } else {
        Uri.parseIPv4Address(host);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The link helpers in [said], as they are used: https addresses with a host and nobody's name or password in
  /// them, at most [longestHelper] long, the first [mostHelpers].
  static List<String> tidyHelpers(Iterable<Object?> said) {
    final out = <String>[];
    for (final h in said) {
      if (h is! String || h.length > longestHelper || !h.startsWith('https://') || out.contains(h)) continue;
      final uri = Uri.tryParse(h);
      if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) continue;
      out.add(h);
      if (out.length == mostHelpers) break;
    }
    return List.unmodifiable(out);
  }

  // --- meeting -----------------------------------------------------------------------------------------------------------

  /// Asks [account]'s devices to bring their nodes up and link (a `meet`, by a route that is not this one), and holds
  /// that an answer may come until [until]. At most [P2pPolicy.meetsAnHour] an hour to one account, and not twice in
  /// the time a dial has.
  Future<void> meet(String account, int until) async {
    final peer = account == me ? _minePeer : _friendsNow[account];
    if (peer == null || _card == null || !_on || !mayLink(account) || !_through) return;
    final now = nowMs;
    final sent = _meetsSent[account] ??= [];
    sent.removeWhere((t) => now - t >= _hour);
    if (sent.length >= policy.meetsAnHour || (sent.isNotEmpty && now - sent.last < policy.dialFor.inMilliseconds)) return;
    sent.add(now);
    _awaited[account] = until;
    await _whereKnown(now + 1000 < until ? now + 1000 : until);
    if (!await _say(peer, _message('meet', account), limited: false)) {
      // Not asked after all: nobody waits for an answer.
      _awaited.remove(account);
      carrier.poke();
    }
  }

  /// Whether a `meet` from [peer] is answered now: at most [P2pPolicy.meetsAnHour] times an hour for one account, and
  /// not at all while Direct is off or the person chose Invisible. Counted as answered where it is.
  bool _mayMeet(Peer peer) {
    if (!_on || _card == null || !mayLink(peer.id)) return false;
    final now = nowMs;
    final answered = _meetsAnswered[peer.id] ??= [];
    answered.removeWhere((t) => now - t >= _hour);
    if (answered.length >= policy.meetsAnHour) return false;
    answered.add(now);
    return true;
  }

  /// A friend's device (or one of this account's own) said it is up and where: this one brings its node up, answers
  /// with where it is, and dials.
  Future<void> _met(Peer peer, P2pDevice from) async {
    final now = nowMs;
    busy(true);
    try {
      await up();
      await _whereKnown(now + 1000);
      await _answer(peer, limited: false);
      carrier.reach(from.nodeId, peer.id);
    } catch (_) {
    } finally {
      busy(false);
    }
  }

  /// Waits until the node says where it is, or [until].
  Future<void> _whereKnown(int until) {
    if (node.whereabouts.value != null || nowMs >= until) return Future.value();
    final done = Completer<void>();
    late final Timer wait;
    void heard() {
      if (node.whereabouts.value == null || done.isCompleted) return;
      wait.cancel();
      node.whereabouts.removeListener(heard);
      done.complete();
    }

    wait = timer(Duration(milliseconds: until - nowMs), () {
      node.whereabouts.removeListener(heard);
      if (!done.isCompleted) done.complete();
    });
    node.whereabouts.addListener(heard);
    return done.future;
  }

  // --- when the node runs ---------------------------------------------------------------------------------------------------

  P2pConfig _config() => P2pConfig(secret: _key!, helpers: _helpers, helpersOnly: _helpersOnly);

  /// Brings the node up where it is not, with the link helpers and the choices of now. Throws [CarrierError] where
  /// Direct is off or it can't be started.
  Future<void> up() async {
    while (true) {
      if (!_loaded || !_on) throw CarrierError('Direct is switched off');
      // It could not start a moment ago: not tried again until a while has passed ([P2pPolicy.redialAfter]).
      if (_failed) throw CarrierError(_problem ?? 'The direct network could not start');
      final config = _config();
      if (node.state.value == P2pState.up && _running == config) return;
      await (_starting ??= _start(config).whenComplete(() => _starting = null));
      if (!_loaded || !_on) throw CarrierError('Direct is switched off');
      if (node.state.value != P2pState.up) throw CarrierError(_problem ?? 'The direct network could not start');
      if (_running == _config()) return;
    }
  }

  Future<void> _start(P2pConfig config) async {
    _running = config;
    // Waited for until it has answered and is no longer starting, and no longer than a dial may take whatever the
    // core does.
    final done = Completer<void>();
    var answered = false;
    void look() {
      if (answered && node.state.value != P2pState.starting && !done.isCompleted) done.complete();
    }

    final wait = timer(policy.dialFor, () {
      if (!done.isCompleted) done.complete();
    });
    node.state.addListener(look);
    void said([Object? wrong]) {
      if (wrong != null) _problem = '$wrong';
      answered = true;
      look();
    }

    try {
      node.start(config).then((_) => said(), onError: (Object e) => said(e));
    } catch (e) {
      said(e);
    }
    await done.future;
    wait.cancel();
    node.state.removeListener(look);
    if (node.state.value == P2pState.up) return _idleSoon();
    // Not up, and it has not said it is down either: held to have failed, so the next thing that wants it does not
    // wait as long again, and tried again after a while as a node that said so is.
    if (!_failed && _loaded && _on && identical(_running, config)) {
      _failed = true;
      _problem ??= 'The direct network did not start';
      _retry ??= timer(policy.redialAfter, _again);
      carrier.restate();
      notifyListeners();
    }
  }

  /// Stops the node, waiting no longer than a dial may take for it to have stopped.
  Future<void> _stop() {
    final done = Completer<void>();
    final wait = timer(policy.dialFor, () {
      if (!done.isCompleted) done.complete();
    });
    void stopped([Object? _]) {
      wait.cancel();
      if (!done.isCompleted) done.complete();
    }

    try {
      node.stop().then((_) => stopped(), onError: stopped);
    } catch (_) {
      stopped();
    }
    return done.future;
  }

  /// What the node answers, waited for no longer than twice the time a dial may take; null where it has not by then.
  Future<T?> _answered<T extends Object>(Future<T> asked) {
    final done = Completer<T?>();
    final wait = timer(policy.dialFor * 2, () {
      if (!done.isCompleted) done.complete(null);
    });
    asked.then((answer) {
      wait.cancel();
      if (!done.isCompleted) done.complete(answer);
    }, onError: (Object e, StackTrace at) {
      wait.cancel();
      if (!done.isCompleted) done.completeError(e, at);
    });
    return done.future;
  }

  void _nodeState() {
    if (_gone) return;
    switch (node.state.value) {
      case P2pState.up:
        _failed = false;
        _problem = null;
        _retry?.cancel();
        _retry = null;
        _idleSoon();
      case P2pState.down:
        _failed = true;
        _problem = node.problem ?? 'The direct network could not start';
        // Tried again after a while: a computer's by itself, a phone's when there is next something to say.
        _retry ??= timer(policy.redialAfter, _again);
      case P2pState.off || P2pState.starting:
        break;
    }
    carrier.restate();
    notifyListeners();
  }

  void _again() {
    _retry = null;
    if (!_failed) return;
    _failed = false;
    _problem = null;
    carrier.restate();
    notifyListeners();
    if (_on) _wake();
  }

  /// A computer's node is up whenever Direct is on.
  void _wake() {
    if (policy.stayUp && _loaded && _on) unawaited(up().then((_) {}, onError: (Object _) {}));
  }

  /// A phone's node is stopped [P2pPolicy.idle] after its last stream closed, or after it came up with none.
  void _idleSoon() {
    _idle?.cancel();
    _idle = null;
    if (policy.stayUp || _gone || node.state.value != P2pState.up || _busy > 0 || carrier.lines > 0) return;
    _idle = timer(policy.idle, () {
      _idle = null;
      if (policy.stayUp || _busy > 0 || carrier.lines > 0 || node.state.value != P2pState.up) return;
      unawaited(_stop());
    });
  }

  /// The route was switched on or off (Settings › Routes, or the network as a whole).
  void setOn(bool on) {
    if (on == _on) return;
    _on = on;
    if (on) {
      if (_loaded) {
        _wake();
        _quietly(refresh());
      }
      _watchRelay();
    } else {
      _relayTimer?.cancel();
      _relayTimer = null;
      _idle?.cancel();
      _idle = null;
      _retry?.cancel();
      _retry = null;
      _failed = false;
      _problem = null;
      _running = null;
      unawaited(_stop());
    }
    carrier.restate();
    notifyListeners();
  }

  /// How the person chose to be shown (Net.setMode). Invisible: no friend's device is linked, dialled, answered or
  /// let in, since a link says this device is here; this account's own devices go on as ever.
  void setMode(String mode) {
    final invisible = mode == 'invisible';
    if (invisible == _invisible) return;
    _invisible = invisible;
    if (!_loaded) return;
    _allow();
    notifyListeners();
    // Seen again: whoever was not told while hidden is told now.
    if (!invisible) _quietly(_tell());
  }

  /// The app put away, or in use again (Net.setAway).
  void setAway(bool away) {
    if (away == _away) return;
    _away = away;
    if (away) {
      _relayTimer?.cancel();
      _relayTimer = null;
    } else {
      _watchRelay();
    }
  }

  /// The device's network may have changed: the relay's link dropped or came back, or the app came back to the screen
  /// (Net.resume). The node looks at its paths again, and devices that could not be reached are dialled afresh.
  void networkChanged() {
    carrier.networkChanged();
    try {
      if (node.state.value == P2pState.up) node.networkChanged();
    } catch (_) {}
    if (_failed) _again();
  }

  /// The link helpers the relay named as this app signed in (HubCarrier.helpers). A change restarts a running node.
  void setHelpers(List<String> said) {
    final next = tidyHelpers(said);
    _helpersSaid = true;
    if (listEquals(next, _helpers)) return;
    _helpers = next;
    unawaited(_plain.write(helpersName, jsonEncode(next)).catchError((Object _) {}));
    _reconfigure();
    notifyListeners();
  }

  /// "Only through link helpers" (Settings › Routes), kept as `p2p_helpers_only`. A change restarts a running node.
  Future<void> setHelpersOnly(bool only) async {
    _helpersOnlySaid = true;
    if (only == _helpersOnly) return;
    _helpersOnly = only;
    _reconfigure();
    notifyListeners();
    try {
      await _plain.write(helpersOnlyName, only ? 'on' : 'off');
    } catch (_) {}
  }

  /// The node's config is another now: one that is running is started again with it.
  void _reconfigure() {
    if (!_loaded || !_on) return;
    final state = node.state.value;
    if (state == P2pState.up || state == P2pState.starting) unawaited(up().then((_) {}, onError: (Object _) {}));
  }

  void _routesChanged() {
    final up = _relayUp;
    if (up == _relayWasUp) return;
    _relayWasUp = up;
    networkChanged();
    if (up) {
      _relayTimer?.cancel();
      _relayTimer = null;
      // What could not be told, or made, while it was away.
      _quietly(refresh());
    } else {
      _watchRelay();
    }
  }

  /// With the relay away there is nothing to ask through: once it has been away [P2pPolicy.relayGone] with the app in
  /// use, this device brings its node up by itself and dials by what it last heard.
  void _watchRelay() {
    if (_relayTimer != null || !_loaded || !_on || _away || _relayUp || _board == null) return;
    _relayTimer = timer(policy.relayGone, () {
      _relayTimer = null;
      if (!_loaded || !_on || _away || _relayUp) return;
      _quietly(_reachOut());
    });
  }

  Future<void> _reachOut() async {
    // This account's own devices first, then friends', each by when it was last heard from; only those that said
    // where they are, and no more than a handful at once.
    final all = [
      for (final account in _cards.keys)
        if (mayLink(account))
          for (final d in devicesOf(account))
            if (hintFor(d) != null && !carrier.linkedTo(account, d.nodeId)) d,
    ]..sort((a, b) {
        final own = (b.account == me ? 1 : 0) - (a.account == me ? 1 : 0);
        return own != 0 ? own : b.heard.compareTo(a.heard);
      });
    if (all.isEmpty) return;
    busy(true);
    try {
      await up();
      for (final d in all.take(policy.mostDials)) {
        carrier.reach(d.nodeId, d.account);
      }
    } catch (_) {
    } finally {
      busy(false);
    }
  }

  // --- keeping, and forgetting -------------------------------------------------------------------------------------------------

  void _saveCards() {
    if (!_loaded) return;
    unawaited(_plain.write(cardsName, jsonEncode({for (final e in _cards.entries) e.key: [for (final d in e.value) d.toJson()]})).catchError((Object _) {}));
  }

  void _saveTold() {
    if (!_loaded) return;
    unawaited(_plain.write(toldName, jsonEncode({for (final e in _told.entries) e.key: e.value.toJson()})).catchError((Object _) {}));
  }

  /// Signing out: the node is stopped and nobody is let in, and the node key, the node id, this device's card, the
  /// cards held and what was told are deleted. Nothing of the account is left on the direct network's side.
  Future<void> wipe() async {
    _loaded = false;
    _wiped = true;
    _stopTimers();
    for (final n in _allowed.toList()) {
      node.disallow(n);
    }
    _allowed.clear();
    carrier.closeAll();
    _cards.clear();
    _told.clear();
    _said.clear();
    _meetsAnswered.clear();
    _meetsSent.clear();
    _looked.clear();
    _awaited.clear();
    _early.clear();
    _card = null;
    _key = null;
    _nodeId = null;
    _running = null;
    _minePeer = null;
    carrier.restate();
    await _stop();
    await forget(_secrets, _plain);
    if (!_gone) notifyListeners();
  }

  /// Deletes what the direct network keeps on a device, where none is running to [wipe] itself.
  static Future<void> forget(FsStore secrets, FsStore plain) async {
    await secrets.write(keyName, '');
    for (final name in keptNames) {
      await plain.write(name, '');
    }
  }

  void _stopTimers() {
    for (final t in [_idle, _relayTimer, _retry, _due, _askTimer]) {
      t?.cancel();
    }
    _idle = _relayTimer = _retry = _due = _askTimer = null;
  }

  /// The app is closing, or the routes are being set up anew: the node is stopped and nothing more is heard. What is
  /// kept stays.
  Future<void> shutdown() async {
    _gone = true;
    _loaded = false;
    detach();
    _stopTimers();
    node.state.removeListener(_nodeState);
    await _paths?.cancel();
    carrier.closeAll();
    await carrier.dispose();
    await _stop();
  }
}

/// What an account was told: which of this device's cards, when, and when it was last asked for its own.
class _Told {
  const _Told(this.card, this.at, this.asked);
  final String card;
  final int at;
  final int asked;

  Map<String, dynamic> toJson() => {'c': card, 't': at, if (asked > 0) 'q': asked};

  static _Told? fromJson(Object? j) {
    if (j is! Map) return null;
    final c = j['c'], t = j['t'], q = j['q'];
    if (c is! String || c.length > 32 || t is! int) return null;
    return _Told(c, t, q is int ? q : 0);
  }
}
