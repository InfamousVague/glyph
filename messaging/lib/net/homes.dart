import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'carrier.dart';
import 'home_record.dart';
import 'hub_carrier.dart';
import 'hub_link.dart';
import 'relay_ask.dart';

/// Someone found by their username on a relay ([Homes.whois]).
class FoundOnRelay {
  const FoundOnRelay({required this.id, required this.key, this.home, this.here = false});

  /// Their name (NetCrypto.idOf their key) and their public key in base64.
  final String id;
  final String key;

  /// Their home record, checked: it is theirs, by their own signature. Null where the relay asked holds none, and
  /// they then can't be reached from another relay.
  final HomeRecord? home;

  /// The relay asked turned out to be this app's own: they are someone here.
  final bool here;
}

/// Why a home record could not be made, given or looked up, in words to show.
class HomeError implements Exception {
  HomeError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// This account's home record and what the relay is told of where people live (docs/OPEN_NETWORK.md, section 4;
/// Matt, 2026-11-22: "I'd like the relays to be able to talk to each other").
///
/// - **This account's own record** ([mine]): says it lives on the relay this app uses, as that relay names itself in
///   its hub's hello (the address the app dialled where it names none). Made the first time the relay is reached,
///   and anew with the next count whenever that address changes (the app moved to another relay). The record and its
///   count are kept with the app's choices (`net_home`, `net_home_n`), so it is ready at every sign-in.
/// - **At every sign-in** the relay is given this account's record first, then the record of each friend who lives on
///   another relay ([give]), before anything else can be sent: a relay learns where someone lives only from their
///   record, and without it keeps a packet for them as though they lived here.
/// - **Names on another relay** ([whois]): asked of this app's own relay where it talks to others, and of the other
///   relay itself where it doesn't (or couldn't).
///
/// It tells its listeners when [mine] changes, so friends can be told (lib/friends/buddies.dart).
class Homes extends ChangeNotifier {
  Homes({required this.signer, required String Function(String key) read, required void Function(String key, String value) write, DateTime Function()? now, HubDial? dial, this.busyAgain = const Duration(seconds: 3), this.answerWithin = const Duration(seconds: 12)})
      : _read = read,
        _write = write,
        _now = now ?? DateTime.now,
        _dial = dial {
    mine = HomeRecord.check(_json(read('net_home')), forId: signer.id, now: _now());
  }

  final NetSigner signer;
  final String Function(String key) _read;
  final void Function(String key, String value) _write;
  final DateTime Function() _now;

  /// How another relay is dialled when it is asked itself; the platform's WebSocket where null.
  final HubDial? _dial;

  /// How long before a record the relay was too busy to check is given again, and how long the app's own relay has to
  /// answer a name asked of another.
  final Duration busyAgain;
  final Duration answerWithin;

  /// This account's own record; null until one is made.
  HomeRecord? mine;

  HubCarrier? _hub;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final Map<String, Map<String, Object?>> _friends = {};
  final Map<String, int> _busy = {};
  final List<Timer> _timers = [];
  Future<void>? _making;
  bool _disposed = false;

  static Object? _json(String text) {
    try {
      return text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// The highest count this account is known to have used: the next record it makes is one more.
  int get count {
    final kept = int.tryParse(_read('net_home_n')) ?? 0;
    final own = mine?.n ?? 0;
    return kept > own ? kept : own;
  }

  /// Follows [hub]: gives it the records at each sign-in, and makes this account's own where it has none for it.
  void attach(HubCarrier hub) {
    if (identical(hub, _hub)) return;
    detach();
    _hub = hub;
    hub.onSignIn = _first;
    _sub = hub.homes.listen(_heard);
    hub.state.addListener(_state);
    _state();
  }

  void detach() {
    final hub = _hub;
    if (hub == null) return;
    if (identical(hub.onSignIn, _first)) hub.onSignIn = null;
    hub.state.removeListener(_state);
    _sub?.cancel();
    _sub = null;
    _hub = null;
  }

  @override
  void dispose() {
    _disposed = true;
    detach();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  bool get _up => _hub != null && _hub!.state.value == CarrierState.up;

  /// Whether the relay this app uses passes packets to other relays, as it said in its hello.
  bool get relayTalks => _hub?.relay?.fed ?? false;

  /// The address this account's record names: the relay this app uses, as it names itself (its own hub's address, or
  /// for one hosted from an app its name and the public relay it stays linked to), else the address the app dialled.
  String? get here {
    final hub = _hub;
    return hub == null ? null : addressOf(hub.relay, hub.url);
  }

  /// The address a home record names for the relay dialled at [dialled], given what that relay said of itself
  /// ([relay]; null from one from before): its own hub's address where it claims one, its name and the public relay
  /// it stays linked to where it has no address of its own, else the address dialled. Null where none of them is one.
  static String? addressOf(HubRelay? relay, String dialled) {
    final own = relay?.url == null ? null : canonicalHub(relay!.url!);
    if (own != null) return own;
    final via = relay?.via == null ? null : canonicalHub(relay!.via!);
    if (relay != null && via != null) return hostedAddress(relay.id, via);
    return canonicalHub(dialled);
  }

  /// Whether [rec] names the relay this app uses: its address as it names itself, the address the app dialled, or
  /// (for a relay hosted from an app) its name.
  bool livesHere(HomeRecord rec) => namesHere(rec.h);

  /// Whether one of [addresses] (a home record's) is the relay this app uses.
  bool namesHere(Iterable<String> addresses) {
    final hub = _hub;
    if (hub == null) return false;
    final mine = here, dialled = canonicalHub(hub.url), id = hub.relay?.id;
    return addresses.any((x) => x == mine || canonicalHub(x) == mine || (dialled != null && canonicalHub(x) == dialled) || (id != null && (x == 'ghost-relay://$id' || x.startsWith('ghost-relay://$id?'))));
  }

  /// Whether the relay at [host] (as written after a username's `@`) is the one this app uses.
  bool isHere(String host) {
    final hub = _hub;
    final url = hubOfHost(host);
    return hub != null && url != null && (url == here || url == canonicalHub(hub.url));
  }

  /// What is said first at each sign-in: this account's record where it names this relay, then each friend's who
  /// lives on another.
  List<Map<String, Object?>> _first() => [
        if (mine != null && livesHere(mine!)) {'dir': 'home', 'rec': mine!.toJson()},
        for (final rec in _friends.values)
          if (_elsewhere(rec)) {'dir': 'home', 'rec': rec},
      ];

  bool _elsewhere(Map<String, Object?> json) {
    final h = json['h'];
    return h is List && _hub != null && !namesHere(h.whereType<String>());
  }

  void _state() {
    if (_up) unawaited(ensure());
  }

  /// Makes this account's record where there is none that names the relay in use, with the next count, keeps it, gives
  /// it to the relay and tells the listeners. Nothing where the record held is the one for this relay.
  Future<void> ensure() => _making ??= _ensure().whenComplete(() => _making = null);

  Future<void> _ensure() async {
    final address = here;
    if (address == null || _disposed) return;
    final had = mine;
    if (had != null && had.h.length == 1 && had.h.single == address) return;
    await _make(address);
  }

  Future<HomeRecord?> _make(String address) async {
    final HomeRecord rec;
    try {
      rec = await HomeRecord.make(signer, addresses: [address], count: count + 1, now: _now());
    } catch (_) {
      return null;
    }
    if (_disposed) return null;
    mine = rec;
    _write('net_home', jsonEncode(rec.toJson()));
    _write('net_home_n', '${rec.n}');
    if (_up) _hub!.sayHandles({'dir': 'home', 'rec': rec.toJson()});
    notifyListeners();
    return rec;
  }

  /// The account is about to move to the relay at [address] (what a record names for it: [addressOf]): a record with
  /// the next count is made for it and given to the relay being left, while it is still connected, so that relay
  /// knows where the account lives now. The new relay is given it as the app signs in there.
  Future<void> moveTo(String address) async {
    final to = address.startsWith('ghost-relay://') ? address : canonicalHub(address);
    if (to == null || (mine != null && mine!.h.length == 1 && mine!.h.single == to)) return;
    await _make(to);
  }

  /// A friend's record ([rec], already checked): given to the relay now where they live on another, and again at
  /// every sign-in, so the relay can route to them.
  void give(Map<String, Object?> rec) {
    final a = rec['a'];
    if (a is! String) return;
    _friends[a] = rec;
    if (_up && _elsewhere(rec)) _hub!.sayHandles({'dir': 'home', 'rec': rec});
  }

  /// [id] is no longer a friend: their record is no longer given.
  void forget(String id) => _friends.remove(id);

  void _heard(Map<String, dynamic> m) {
    if (m['dir'] != 'home') return;
    final a = m['a'], n = m['n'];
    if (m['ok'] == true) {
      if (a is String) _busy.remove(a);
      // Another device of this account made a newer one: the next this device makes is newer still.
      if (a == signer.id && n is int && n > count) _write('net_home_n', '$n');
      return;
    }
    // Too many checks just now: given again in a while, a few times.
    if (m['err'] == 'busy' && a is String) {
      final tries = (_busy[a] ?? 0) + 1;
      if (tries > 5) return;
      _busy[a] = tries;
      late final Timer t;
      t = Timer(busyAgain * tries, () {
        _timers.remove(t);
        final rec = a == signer.id ? mine?.toJson() : _friends[a];
        if (rec != null && _up) _hub!.sayHandles({'dir': 'home', 'rec': rec});
      });
      _timers.add(t);
    }
  }

  /// Who has the username [name] on the relay at [host] (`relay.example`, as written after the `@`). Asked of this
  /// app's own relay where it talks to other relays; where it doesn't, or couldn't reach that one, of that relay
  /// itself. Null where nobody has the name there; a [HomeError] where nobody could be asked.
  Future<FoundOnRelay?> whois(String name, String host) async {
    final url = hubOfHost(host);
    if (url == null) throw HomeError('"$host" isn\'t a relay\'s address.');
    final hub = _hub;
    if (hub != null && _up && relayTalks) {
      final got = await _askOwn(hub, name, host);
      if (got != null) {
        if (got['dir'] == 'err') throw HomeError('${got['err'] ?? 'That did not work.'}');
        final id = got['id'], key = got['key'];
        if (id is String && key is String) return FoundOnRelay(id: id, key: key, home: HomeRecord.check(got['home'], forId: id, forKey: key, now: _now()), here: got['here'] == true);
        // Nobody has that name there; unless it says why it couldn't ask, and then that relay is asked itself.
        if (got['why'] == null) return null;
      }
    }
    final ({String id, String key, Object? home})? found;
    try {
      found = await whoisAt(url, name, signer: signer, dial: _dial, onPacket: (from, packet) => _hub?.adopt(from, packet));
    } on RelayAskError catch (e) {
      throw HomeError(e.message);
    }
    if (found == null) return null;
    return FoundOnRelay(id: found.id, key: found.key, home: HomeRecord.check(found.home, forId: found.id, forKey: found.key, now: _now()));
  }

  /// Asks this app's own relay who has [name] on the relay at [host]; its answer, or null where none came in time.
  Future<Map<String, dynamic>?> _askOwn(HubCarrier hub, String name, String host) async {
    final answer = Completer<Map<String, dynamic>?>();
    final sub = hub.handles.listen((m) {
      if (answer.isCompleted) return;
      if ((m['dir'] == 'whois' && m['name'] == name && m['at'] == host) || (m['dir'] == 'err' && m['about'] == 'whois')) answer.complete(m);
    });
    try {
      if (!hub.sayHandles({'dir': 'whois', 'name': name, 'at': host})) return null;
      return await answer.future.timeout(answerWithin, onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }
}
