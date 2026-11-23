import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../games/game_activity.dart';
import '../invites/pending_invites.dart';
import '../me/me.dart';
import '../me/cosmetics.dart';
import '../me/pictures.dart';
import '../net/carrier.dart';
import '../net/crypto.dart';
import '../net/home_record.dart';
import '../net/homes.dart';
import '../net/net.dart';
import '../net/packet.dart';
import '../net/switchboard.dart';
import '../sms.dart';
import '../sounds.dart';

/// Someone added by their username on Ghost Messaging, with no phone number between the two (Matt, 2026-11-14:
/// "create a profile and username under "me" to register a username and add friends on the platform").
@immutable
class Buddy {
  const Buddy({required this.username, required this.id, required this.key, this.name = '', this.bio = '', this.state = 'yes', this.at = 0, this.picture = '', this.status = '', this.links = const {}, this.cosmetics = Cosmetics.none, this.home});

  /// Their username, as the relay server's directory has it: `maya`, or `maya@relay.example` for someone who was
  /// added on another relay (lib/net/home_record.dart, splitUsername).
  final String username;

  /// Their home record, as they signed it (lib/net/home_record.dart): where they live, which this app's relay is
  /// given so it can pass packets on to theirs. Checked before it is kept; null where they have said none (a build
  /// from before relays talked to each other).
  final Map<String, Object?>? home;

  /// The count of their home record; 0 with none.
  int get homeCount => home?['n'] is int ? home!['n'] as int : 0;

  /// The relay their record names, as a person reads it (`relay.example`); '' with no record.
  String get homeHost {
    final h = home?['h'];
    if (h is! List) return '';
    return h.whereType<String>().map(hostOfHome).firstWhere((x) => x.isNotEmpty, orElse: () => '');
  }

  /// Their install's name (NetCrypto.idOf their key) and their public key in base64: what packets to them are sealed
  /// with, as the phone works it out (android Buddies.kt).
  final String id;
  final String key;

  /// What they said about themselves: sent by them, kept here, never asked of the server.
  final String name;
  final String bio;

  /// Their picture (a square base64 PNG: lib/me/pictures.dart) and how they are now, as they last said; '' for none.
  final String picture;
  final String status;

  /// Their number (`phone`) and the accounts they linked (network to handle), where they chose to tell friends.
  final Map<String, String> links;

  /// Where the two stand: `asked` (this phone asked them), `invited` (they asked this phone), `yes`; or `blocked`
  /// (GMFB-40): kept only so their friend requests and messages are dropped, never given a sealing key (android
  /// Buddies.kt and Chats.peersOf take only the other three).
  final String state;
  final int at;

  /// Their name, else their username, with no "@" in front (bareName).
  String get shown => name.isEmpty ? bareName(username) : bareName(name);

  /// What their profile wears, as they last said (lib/me/cosmetics.dart).
  final Cosmetics cosmetics;

  Buddy copyWith({String? name, String? bio, String? state, String? picture, String? status, Map<String, String>? links, Cosmetics? cosmetics, Map<String, Object?>? home}) => Buddy(
      username: username,
      id: id,
      key: key,
      name: name ?? this.name,
      bio: bio ?? this.bio,
      state: state ?? this.state,
      at: at,
      picture: picture ?? this.picture,
      status: status ?? this.status,
      links: links ?? this.links,
      cosmetics: cosmetics ?? this.cosmetics,
      home: home ?? this.home);

  Map<String, Object> toJson() => {'u': username, 'i': id, 'k': key, 'n': name, 'b': bio, 's': state, 'a': at, if (picture.isNotEmpty) 'p': picture, if (status.isNotEmpty) 'st': status, if (links.isNotEmpty) 'l': links, if (!cosmetics.isEmpty) 'cx': cosmetics.toJson(), 'h': ?home};

  /// Links as sent or kept: network to handle, short strings only; null where none were said.
  static Map<String, String>? _linksOf(Object? l) {
    if (l is! Map) return null;
    return {for (final e in l.entries.take(12)) if (e.key is String && e.value is String && (e.value as String).length <= 80) e.key as String: e.value as String};
  }

  static Buddy? fromJson(Object? j) {
    if (j is! Map) return null;
    final u = j['u'], i = j['i'], k = j['k'];
    if (u is! String || i is! String || k is! String) return null;
    final p = j['p'] is String && (j['p'] as String).length <= ProfilePictures.most ? j['p'] as String : '';
    return Buddy(username: u, id: i, key: k, name: '${j['n'] ?? ''}', bio: '${j['b'] ?? ''}', state: '${j['s'] ?? 'yes'}', at: (j['a'] as num?)?.toInt() ?? 0, picture: p, status: '${j['st'] ?? ''}', links: _linksOf(j['l']) ?? const {}, cosmetics: Cosmetics.fromJson(j['cx']) ?? Cosmetics.none, home: j['h'] is Map ? (j['h'] as Map).cast<String, Object?>() : null);
  }
}

/// What [Buddies] stands on: the directory, the routes, the phone. The app's is [_AppBuddiesPort]; a test gives
/// two that reach each other.
abstract class BuddiesPort {
  /// This install's name and public key (base64).
  Future<({String id, String key})> me();
  String? get username;
  String get displayName;
  String get bio;
  Future<({String id, String key})?> whois(String username);

  /// Keeps the list where the phone works out each one's sealing key from, and reads the people again.
  Future<void> keep(String json);
  Future<String> kept();

  /// Sends [envelope]: sealed to someone a key is held for, or in the clear ([sealed] false, a request).
  Future<bool> send(String id, Envelope envelope, {bool sealed = true});

  /// What comes sealed from someone a key is held for, and the greetings in the clear from anyone.
  Stream<({String from, Envelope envelope})> get received;
  Stream<({String from, Envelope envelope})> get greetings;
}

/// What a [BuddiesPort] adds where relays talk to each other (docs/OPEN_NETWORK.md, section 4): this account's home
/// record and the giving of friends' records to the relay ([Homes]), and whether what was sent someone crossed to their
/// relay. A port without it knows one relay only, as every port did before: nobody on another relay can be added
/// through it, and nothing else changes.
abstract class BuddiesAcross {
  /// This account's home record and what the relay is told of where friends live; null until the routes are set up.
  Homes? get homes;

  /// Tells when [homes] is another one, or this account's record in it changed.
  Listenable get homesChanged;

  /// Whether the last thing sent to [id] was passed by this app's relay to another relay (or is kept for one). False
  /// where the relay only kept it here, as it does for someone who lives on it.
  bool passedOn(String id);

  /// Something small kept with the app's choices, and read back.
  String recall(String key);
  void remember(String key, String value);
}

/// Friends by username. Becoming friends is said over the routes as envelopes of kind `buddy`:
///
/// - **ask**, in the clear, as a greeting (`hello` with `buddy: ask`), carrying the asker's username, name, line and
///   public key. Anyone can send it; the hub says who sent it, and the key is checked against that name, so it can't
///   be sent in someone else's name. It is shown as a request, and nothing more is taken from it.
/// - **yes**, sealed: the other said yes. Their name and line come with it. Two who ask each other are friends.
/// - **no** and **end**, sealed: no, or no longer.
/// - **me**, sealed: a friend changed their name or line.
///
/// The list is kept on the phone (`buddies`), and the phone works out the key each pair seals with from it, so the
/// routes reach them as they reach anyone encryption is on with.
///
/// **Friends on another relay** (docs/OPEN_NETWORK.md, section 4; Matt, 2026-11-22: "I'd like the relays to be able to
/// talk to each other"). `maya@relay.example` is asked of that relay ([Homes.whois]) and kept with her home record,
/// which this app's relay is given so it can pass packets on to hers; nothing else about sending changes. The ask
/// carries the asker's own record (`h`), so the answer can find its way back, and friends tell each other their
/// record with a sealed envelope of kind `home` (`{"rec": …}`): when two become friends, and whenever it changes (the
/// account moved to another relay), a friend at a time ([spread]). A record is kept only where it is that friend's
/// own, by their key, and newer than the one held.
/// What [Buddies.lookup] found.
enum BuddyLookup { nobody, you, someone }

class Buddies extends ChangeNotifier {
  /// What the phone last said its friends are, as it said it ([refresh]).
  String? _lastSaid;

  Buddies(this._port, {this.spread = const Duration(seconds: 2)});

  /// How long between one friend being told this account's new home record and the next: not all at once.
  final Duration spread;

  static Buddies? _instance;
  static Buddies get instance => _instance ??= Buddies(_AppBuddiesPort());

  @visibleForTesting
  static set instance(Buddies? b) => _instance = b;

  final BuddiesPort _port;
  final List<StreamSubscription<Object?>> _subs = [];
  List<Buddy> all = [];
  bool _started = false;

  List<Buddy> get friends => [for (final b in all) if (b.state == 'yes') b];

  /// [friends] as a list shows them: one each, by username (Matt, 2026-11-19: "my friends are duplicated I have two
  /// copies of all my friends on the app"). The same person can be here twice, under two ids (an install of theirs
  /// that came again with a new key, or a list put together from a phone's and a computer's); the newest stands for
  /// them. [friends] keeps every id, for what is sent to each.
  List<Buddy> get shownFriends => onePerUsername(friends);

  /// [list] with one [Buddy] for each username (letters' case aside), the latest ([Buddy.at]) of each, in [list]'s order.
  static List<Buddy> onePerUsername(List<Buddy> list) {
    final best = <String, Buddy>{};
    for (final b in list) {
      final k = b.username.toLowerCase();
      final had = best[k];
      if (had == null || b.at > had.at) best[k] = b;
    }
    final seen = <String>{};
    return [
      for (final b in list)
        if (identical(best[b.username.toLowerCase()], b) && seen.add(b.username.toLowerCase())) b,
    ];
  }
  List<Buddy> get requests => [for (final b in all) if (b.state == 'invited') b];
  List<Buddy> get asked => [for (final b in all) if (b.state == 'asked') b];

  /// Ghost people this phone blocked (GMFB-40: "Reporting a person also offers to block them").
  List<Buddy> get blocked => [for (final b in all) if (b.state == 'blocked') b];

  bool isBlocked(String id) => byId(id)?.state == 'blocked';

  /// Blocks the Ghost person [id] ([username], [key] where known): no longer friends (they are told, as removing a
  /// friend tells them), and their friend requests and messages are dropped here from now on. Asking them to be friends
  /// again ([add]) takes the block away.
  Future<void> block(String id, {String username = '', String key = ''}) async {
    if (_remote) {
      await _ask({'op': 'block', 'id': id, 'u': username, 'k': key});
      return;
    }
    final had = byId(id);
    if (had?.state == 'yes' || had?.state == 'asked') await _port.send(id, Envelope(kind: 'buddy', body: {'s': 'end'}));
    if (had?.state == 'invited') await _port.send(id, Envelope(kind: 'buddy', body: {'s': 'no'}));
    GameActivities.instance.heard(id, null);
    final b = had == null
        ? Buddy(username: tidyHandle(username), id: id, key: key, state: 'blocked', at: DateTime.now().millisecondsSinceEpoch)
        : Buddy(username: had.username, id: id, key: had.key, name: had.name, state: 'blocked', at: DateTime.now().millisecondsSinceEpoch, picture: had.picture);
    all = [for (final o in all) if (o.id != id) o, b];
    _homes?.forget(id);
    _unreached.remove(id);
    await _save();
  }

  /// Takes the block on [b] away: they are forgotten here, as if never met.
  Future<void> unblock(Buddy b) async {
    if (_remote) {
      await _ask({'op': 'unblock', 'id': b.id});
      return;
    }
    all = [for (final o in all) if (o.id != b.id) o];
    await _save();
  }

  Buddy? byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return null;
  }

  // --- on a computer paired with a phone (Matt, 2026-11-18: "I don't see the ability to add friends on desktop") ------
  //
  // Friends by username are the phone's: its routes reach them and its keys seal to them. A paired computer asks the
  // phone for each thing done (android DeskCalls "buddies", answered by the phone's [forComputer]) and holds the list
  // the phone answers with, asked again every little while so a request made to the phone shows here.

  /// Whether this is a computer's, speaking through its phone.
  bool get _remote => !Sms.ownNetwork && _port is _AppBuddiesPort;
  Timer? _poll;

  /// Asks again, now and then, for a friend request not yet answered ([askAgain]).
  Timer? _again;

  /// How long an unanswered request is asked again for.
  static const askFor = Duration(days: 14);

  /// How often.
  static const askEvery = Duration(minutes: 5);

  Future<Map<String, Object?>> _ask(Map<String, Object?> what) async {
    final Map<String, dynamic> r;
    try {
      r = await Sms.instance.buddies(what);
    } on MeError {
      rethrow;
    } catch (e) {
      final m = RegExp(r'^PlatformException\([^,]*, (.*?), .*\)$', dotAll: true).firstMatch('$e');
      throw MeError(m?.group(1) ?? '$e');
    }
    final list = r['list'];
    if (list is List) {
      // Asked of the phone every twenty seconds: the listeners (the rail, people's faces) are told only when the
      // friends are different from the last asking (docs/performance-audit.md, finding 8).
      final said = jsonEncode(list);
      final same = said == _lastSaid;
      _lastSaid = said;
      all = [for (final j in list) ?Buddy.fromJson(j)];
      if (!same) notifyListeners();
    }
    // What the phone's friends are playing (lib/games/game_activity.dart): said to the phone, so told here by it.
    if (r['ga'] is Map) GameActivities.instance.heardAll(r['ga']);
    return r;
  }

  /// Takes [json] as the whole list (a paired computer's and this phone's, put together: lib/friends/handover.dart).
  Future<void> takeAll(String json) async {
    try {
      all = [for (final j in jsonDecode(json) as List) ?Buddy.fromJson(j)];
    } catch (_) {
      return;
    }
    // Where each lives, for the relay to route by.
    for (final b in all) {
      if (b.home != null && b.state != 'blocked') _homes?.give(b.home!);
    }
    await _save();
  }

  /// The phone's list read again, on a computer; nothing anywhere else.
  Future<void> refresh() async {
    if (!_remote) return;
    try {
      await _ask({'op': 'list'});
    } catch (_) {}
  }

  /// On the phone: what a paired computer asks of friends by username ([_ask] there). Each answer carries the list.
  Future<Object?> forComputer(Map<String, Object?> what) async {
    Buddy want() => byId('${what['id']}') ?? (throw MeError('That friend request is no longer here.'));
    List<Object> list() => [for (final b in all) b.toJson()];
    switch (what['op']) {
      case 'lookup':
        return {'found': (await lookup('${what['u'] ?? ''}')).name, 'list': list()};
      case 'add':
        final b = await add('${what['u'] ?? ''}');
        return {'buddy': b.toJson(), 'list': list()};
      case 'accept':
        final b = await accept(want());
        return {'buddy': b.toJson(), 'list': list()};
      case 'decline':
        await decline(want());
      case 'remove':
        await remove(want());
      case 'block':
        await block('${what['id'] ?? ''}', username: '${what['u'] ?? ''}', key: '${what['k'] ?? ''}');
      case 'unblock':
        await unblock(want());
      case 'share':
        await shareProfile();
      case 'ga':
        // The computer's game, said to friends in this phone's name: the phone is who they are friends with.
        await sayActivity(GameActivity.fromJson(what['ga']));
    }
    return {'list': list(), 'ga': GameActivities.instance.all()};
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (_remote) {
      await refresh();
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
      return;
    }
    // Invites texted to this phone's number before it had the app, waiting on the relay: taken once the number is
    // verified in Settings › Me (lib/invites/pending_invites.dart; Matt, 2026-11-17: "a link that eventually follows
    // through after they setup their account"). Started with the app's friends, on the phone or an iPhone of its own.
    if (identical(this, _instance) && _port is _AppBuddiesPort) PendingInvites.instance.start();
    try {
      all = [for (final j in jsonDecode(await _port.kept()) as List) ?Buddy.fromJson(j)];
    } catch (_) {
      all = [];
    }
    _subs.add(_port.greetings.listen((g) => _greeting(g.from, g.envelope)));
    _subs.add(_port.received.listen((r) => _sealed(r.from, r.envelope)));
    // Home records: friends' are given to the relay, and friends are told this account's when it changes.
    final across = _across;
    if (across != null) {
      try {
        final told = jsonDecode(across.recall(_toldKey));
        if (told is Map) _told.addAll({for (final e in told.entries) if (e.value is int) '${e.key}': e.value as int});
      } catch (_) {}
      across.homesChanged.addListener(_homesChanged);
      _homesChanged();
    }
    notifyListeners();
    // A request the hub was holding for someone away is lost when the relay restarts, and so is an answer, and nothing
    // asked again (Matt, 2026-11-19: "my friend request to morgan never went through i also sent one from her phone and
    // it didn't go out"; the relay restarted five times that evening, one deploy each). Each unanswered request is
    // asked again: a little after starting, once the hub is reached, and every few minutes, for two weeks. The other
    // side takes a request it holds already as the same one, and answers one it has said yes to again.
    Timer(const Duration(seconds: 15), () => unawaited(askAgain()));
    _again = Timer.periodic(askEvery, (_) {
      unawaited(askAgain());
      // And whoever has not heard this account's home record yet (the relay was away when they were to be told).
      _tellSoon();
    });
  }

  // --- home records (docs/OPEN_NETWORK.md, section 4) ---------------------------------------------------------------

  BuddiesAcross? get _across => _port is BuddiesAcross ? _port as BuddiesAcross : null;
  Homes? get _homes => _across?.homes;

  static const _toldKey = 'buddies_home_told';

  /// The count of this account's home record each friend was last told, by their id.
  final Map<String, int> _told = {};

  /// Those still to be told the record there is now, a friend at a time.
  final List<String> _toTell = [];
  Timer? _teller;
  Homes? _givenTo;

  /// Those whose friend request the relay could not pass to their relay when it was last sent.
  final Set<String> _unreached = {};

  /// Whether [b] lives on another relay than this app's, by their home record.
  bool elsewhere(Buddy b) {
    final homes = _homes;
    final h = b.home?['h'];
    return homes != null && h is List && h.isNotEmpty && !homes.namesHere(h.whereType<String>());
  }

  /// The relay [b] is on where it isn't this app's (`relay.example`), for their card; '' where it is, or isn't known.
  String relayOf(Buddy b) => elsewhere(b) ? b.homeHost : '';

  /// Whether the friend request to [b], who lives on another relay, could not be passed to their relay when it was
  /// last sent: this app's relay doesn't talk to theirs. It is sent again by itself ([askAgain]), and goes when it can.
  bool unreached(Buddy b) => _unreached.contains(b.id);

  /// A username as it can be added: `maya`, or `maya@relay.example` (with or without an `@` in front).
  static bool goodAddress(String typed) {
    final t = splitUsername(typed);
    return Me.goodUsername(t.name) && (t.relay == null || goodRelayHost(t.relay!));
  }

  /// The routes were set up, or this account's home record changed.
  void _homesChanged() {
    final homes = _homes;
    if (homes == null) return;
    if (!identical(homes, _givenTo)) {
      _givenTo = homes;
      for (final b in all) {
        if (b.home != null && b.state != 'blocked') homes.give(b.home!);
      }
    }
    _tellSoon();
  }

  /// Queues every friend who has not been told this account's record as it is now, and starts telling them, one each
  /// [spread].
  void _tellSoon() {
    final mine = _homes?.mine;
    if (mine == null) return;
    for (final b in friends) {
      if ((_told[b.id] ?? 0) < mine.n && !_toTell.contains(b.id)) _toTell.add(b.id);
    }
    if (_toTell.isNotEmpty) _teller ??= Timer.periodic(spread, (_) => unawaited(tellNext()));
  }

  /// Tells the next friend waiting this account's home record; true where there was one to tell. The timer calls it;
  /// a test calls it itself.
  @visibleForTesting
  Future<bool> tellNext() async {
    if (_toTell.isEmpty) {
      _teller?.cancel();
      _teller = null;
      return false;
    }
    final id = _toTell.removeAt(0);
    if (_toTell.isEmpty) {
      _teller?.cancel();
      _teller = null;
    }
    await _tellHome(id);
    return true;
  }

  /// How many friends are still to be told, for a test.
  @visibleForTesting
  int get waitingToHear => _toTell.length;

  /// Tells [id] this account's home record, sealed; kept as told where it was sent.
  Future<void> _tellHome(String id) async {
    final across = _across;
    final mine = across?.homes?.mine;
    if (across == null || mine == null || byId(id)?.state != 'yes') return;
    final bool sent;
    try {
      sent = await _port.send(id, Envelope(kind: 'home', body: {'rec': mine.toJson()}));
    } catch (_) {
      return;
    }
    if (!sent) return;
    _told[id] = mine.n;
    _told.removeWhere((k, _) => byId(k) == null);
    across.remember(_toldKey, jsonEncode(_told));
  }

  /// A friend said where they live: kept where it is their own record, by their key, and newer than the one held; and
  /// given to the relay, which routes by it.
  void _heardHome(String from, Object? said) {
    final had = byId(from);
    if (had == null || had.state == 'blocked') return;
    final rec = HomeRecord.check(said, forId: from, forKey: had.key);
    if (rec == null || rec.n <= had.homeCount) return;
    _put(had.copyWith(home: rec.toJson()));
    _homes?.give(rec.toJson());
    unawaited(_save());
  }

  /// The record [body] carries as `h`, where it is [from]'s own by the key [key], and newer than [had]'s; else null.
  Map<String, Object?>? _homeIn(Map body, String from, String key, Buddy? had) {
    final rec = HomeRecord.check(body['h'], forId: from, forKey: key);
    return rec == null || rec.n <= (had?.homeCount ?? 0) ? null : rec.toJson();
  }

  /// Sends each request still unanswered, newer than [askFor], again.
  @visibleForTesting
  Future<int> askAgain() async {
    if (_remote) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final waiting = [for (final b in all) if (b.state == 'asked' && now - b.at < askFor.inMilliseconds) b];
    if (waiting.isEmpty) return 0;
    final ({String id, String key}) me;
    try {
      me = await _port.me();
    } catch (_) {
      return 0;
    }
    var sent = 0;
    for (final b in waiting) {
      try {
        if (await _sendAsk(b, me.key)) sent++;
      } catch (_) {}
    }
    return sent;
  }

  Future<void> _save() async {
    await _port.keep(jsonEncode([for (final b in all) b.toJson()]));
    notifyListeners();
  }

  void _put(Buddy b) {
    all = [for (final o in all) if (o.id != b.id) o, b];
    ProfilePictures.instance.keep(b.id, b.picture);
  }

  /// What friends are told of this person. The picture and status since 2026-11-19 (`p`, `st`); a build from before
  /// passes over them.
  Map<String, Object> _profile() {
    final me = Me.instance;
    // `p`, the small picture, for builds from before 0.10.4; `pp`, the sharp one shown, for the rest.
    final sharp = me.pictureSharp;
    return {'u': _port.username ?? '', 'n': _port.displayName, 'b': _port.bio, if (me.picture.isNotEmpty) 'p': me.picture, if (sharp != me.picture) 'pp': sharp, 'st': me.status, 'l': me.shareLinks ? me.links : const <String, String>{}, 'cx': me.cosmetics.toJson()};
  }

  /// A picture and status said in [body], where it says them: null for each it does not (a build from before).
  @visibleForTesting
  static ({String? picture, String? status, Map<String, String>? links, Cosmetics? cosmetics}) saidOf(Map body) => _said(body);

  static ({String? picture, String? status, Map<String, String>? links, Cosmetics? cosmetics}) _said(Map body) {
    final pp = body['pp'], p = body['p'];
    final picture = pp is String && pp.isNotEmpty && pp.length <= ProfilePictures.most ? pp : p;
    return (picture: picture is String && picture.length <= ProfilePictures.most ? picture : (body.containsKey('st') ? '' : null), status: body['st'] is String ? body['st'] as String : null, links: Buddy._linksOf(body['l']), cosmetics: Cosmetics.fromJson(body['cx']));
  }

  /// Who [username] is, as the add-friend drawer shows it while it is typed: nobody, this install itself, or someone
  /// (lib/ui/add_friend_drawer.dart). Asks the same server [add] asks.
  Future<BuddyLookup> lookup(String username) async {
    if (_remote) return BuddyLookup.values.asNameMap()['${(await _ask({'op': 'lookup', 'u': username}))['found']}'] ?? BuddyLookup.nobody;
    final typed = splitUsername(username);
    final homes = _homes;
    final String? foundId;
    if (typed.relay != null && !(homes?.isHere(typed.relay!) ?? false)) {
      // On another relay: asked of that relay, through this app's own where it talks to it.
      if (homes == null || !goodAddress(username)) return BuddyLookup.nobody;
      try {
        foundId = (await homes.whois(typed.name, typed.relay!))?.id;
      } on HomeError catch (e) {
        throw MeError(e.message);
      }
    } else {
      foundId = (await _port.whois(typed.name))?.id;
    }
    if (foundId == null) return BuddyLookup.nobody;
    if (foundId == (await _port.me()).id) return BuddyLookup.you;
    return BuddyLookup.someone;
  }

  /// Asks [username] to be friends. Throws a [MeError] where nobody has that username, or it is this install's.
  Future<Buddy> add(String username) async {
    if (_remote) return Buddy.fromJson((await _ask({'op': 'add', 'u': username}))['buddy'])!;
    final typed = splitUsername(username);
    var name = typed.name;
    if (_port.username == null) throw MeError('Choose your own username first.');
    final homes = _homes;
    final String id, key;
    Map<String, Object?>? home;
    if (typed.relay != null && !(homes?.isHere(typed.relay!) ?? false)) {
      // Someone on another relay (`maya@relay.example`): asked of that relay, and kept with where they live.
      final host = typed.relay!;
      if (!goodAddress(username)) throw MeError('That isn\'t a username on another relay. It looks like maya@relay.example.');
      if (homes == null) throw MeError('People on other relays can\'t be added from here.');
      final FoundOnRelay? found;
      try {
        found = await homes.whois(name, host);
      } on HomeError catch (e) {
        throw MeError(e.message);
      }
      if (found == null) throw MeError('Nobody has the username @$name on $host.');
      id = found.id;
      key = found.key;
      final rec = found.home;
      if (!found.here && (rec == null || !homes.livesHere(rec))) {
        // Without their record no relay knows where to pass a packet for them.
        if (rec == null) throw MeError('@$name@$host can\'t be reached from another relay yet. They need a newer version of Ghost Messaging.');
        name = '$name@$host';
      }
      home = rec?.toJson();
    } else {
      final found = await _port.whois(name);
      if (found == null) throw MeError('Nobody has the username @$name.');
      id = found.id;
      key = found.key;
    }
    final me = await _port.me();
    if (id == me.id) throw MeError('That\'s you.');
    final had = byId(id);
    if (had != null && had.state == 'yes') return had;
    // They asked first: this is a yes.
    if (had != null && had.state == 'invited') return accept(had);
    final b = Buddy(username: name, id: id, key: key, state: 'asked', at: DateTime.now().millisecondsSinceEpoch, home: home ?? had?.home);
    _put(b);
    await _save();
    // The relay is told where they live before the request goes, so it can pass it on.
    if (b.home != null) homes?.give(b.home!);
    await _sendAsk(b, me.key);
    return b;
  }

  /// Sends [b] the friend request: this account's key, how it shows itself, and its own home record, so the answer
  /// can find its way back from another relay. Where [b] lives on another relay, whether this app's relay passed it
  /// on is kept ([unreached]).
  Future<bool> _sendAsk(Buddy b, String myKey) async {
    final mine = _homes?.mine;
    final sent = await _port.send(b.id, Envelope(kind: 'hello', body: {'buddy': 'ask', 'k': myKey, ..._profile(), 'h': ?mine?.toJson()}), sealed: false);
    if (elsewhere(b) && !(sent && (_across?.passedOn(b.id) ?? false))) {
      if (_unreached.add(b.id)) notifyListeners();
    } else if (_unreached.remove(b.id)) {
      notifyListeners();
    }
    return sent;
  }

  Future<Buddy> accept(Buddy b) async {
    if (_remote) return Buddy.fromJson((await _ask({'op': 'accept', 'id': b.id}))['buddy'])!;
    final yes = b.copyWith(state: 'yes');
    _put(yes);
    await _save();
    await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'yes', ..._profile()}));
    // Friends now: they are told where this account lives.
    await _tellHome(b.id);
    return yes;
  }

  Future<void> decline(Buddy b) async {
    if (_remote) {
      await _ask({'op': 'decline', 'id': b.id});
      return;
    }
    all = [for (final o in all) if (o.id != b.id) o];
    _homes?.forget(b.id);
    await _save();
    await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'no'}));
  }

  /// No longer friends: removed here, and they are told.
  Future<void> remove(Buddy b) async {
    if (_remote) {
      await _ask({'op': 'remove', 'id': b.id});
      return;
    }
    await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'end'}));
    all = [for (final o in all) if (o.id != b.id) o];
    _homes?.forget(b.id);
    _unreached.remove(b.id);
    await _save();
  }

  /// Tells every friend this phone's name and line, after they changed.
  Future<void> shareProfile() async {
    if (_remote) {
      await _ask({'op': 'share'});
      return;
    }
    for (final b in friends) {
      await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'me', ..._profile()}));
    }
  }

  /// Tells every friend what this person is playing ([game]), or that they are not (null): lib/games/game_activity.dart.
  /// A small envelope of its own, so a game starting doesn't send the whole profile, picture and all.
  Future<void> sayActivity(GameActivity? game) async {
    if (_remote) {
      await _ask({'op': 'ga', 'ga': game?.toJson()});
      return;
    }
    for (final b in friends) {
      await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'ga', if (game != null) 'ga': game.toJson()}));
    }
  }

  void _greeting(String from, Envelope e) {
    if (e.body['buddy'] != 'ask') return;
    final key = e.body['k'], username = e.body['u'];
    if (key is! String || username is! String || !Me.goodUsername(username)) return;
    // The key must be the one the hub knows this name by: nobody asks in someone else's name.
    try {
      if (NetCrypto.idOf(base64Decode(key)) != from) return;
    } catch (_) {
      return;
    }
    final had = byId(from);
    // Blocked: their friend requests go nowhere.
    if (had?.state == 'blocked') return;
    final name = '${e.body['n'] ?? ''}', bio = '${e.body['b'] ?? ''}';
    final said = _said(e.body);
    // Where they live, as they signed it: the relay is given it before anything is answered, so the answer is passed
    // on to theirs.
    final home = _homeIn(e.body, from, key, had);
    if (home != null) _homes?.give(home);
    if (had?.state == 'yes') {
      // Asked again by a friend already: our yes was lost on its way (askAgain). Said again.
      if (home != null) {
        _put(had!.copyWith(home: home));
        unawaited(_save());
      }
      unawaited(_port.send(from, Envelope(kind: 'buddy', body: {'s': 'yes', ..._profile()})));
      return;
    }
    if (had?.state == 'asked') {
      // Both asked: friends.
      unawaited(accept(had!.copyWith(name: name, bio: bio, picture: said.picture, status: said.status, links: said.links, cosmetics: said.cosmetics, home: home)));
      return;
    }
    // A request new to this phone: the friend request's sound (lib/sounds.dart), once.
    if (had?.state != 'invited') Sounds.instance.play(UiSound.friendRequest);
    final asked = Buddy(username: tidyHandle(username), id: from, key: key, name: name, bio: bio, state: 'invited', at: DateTime.now().millisecondsSinceEpoch, picture: said.picture ?? '', status: said.status ?? '', links: said.links ?? const {}, cosmetics: said.cosmetics ?? Cosmetics.none, home: home ?? had?.home);
    // Someone on another relay is kept as name@relay, by the relay their own record names.
    final host = elsewhere(asked) ? asked.homeHost : '';
    _put(host.isEmpty ? asked : Buddy(username: '${asked.username}@$host', id: from, key: key, name: name, bio: bio, state: 'invited', at: asked.at, picture: asked.picture, status: asked.status, links: asked.links, cosmetics: asked.cosmetics, home: asked.home));
    unawaited(_save());
  }

  void _sealed(String from, Envelope e) {
    // Where a friend lives, as they signed it (kind `home`).
    if (e.kind == 'home') return _heardHome(from, e.body['rec']);
    if (e.kind != 'buddy') return;
    final had = byId(from);
    if (had == null || had.state == 'blocked') return;
    final name = e.body['n'] is String ? e.body['n'] as String : null, bio = e.body['b'] is String ? e.body['b'] as String : null;
    final said = _said(e.body);
    switch (e.body['s']) {
      case 'yes':
        if (had.state == 'asked') Sounds.instance.play(UiSound.friendAccepted);
        if (had.state == 'asked' || had.state == 'yes') _put(had.copyWith(state: 'yes', name: name, bio: bio, picture: said.picture, status: said.status, links: said.links, cosmetics: said.cosmetics));
        // Friends now: they are told where this account lives (they heard it with the request; again costs little).
        if (had.state == 'asked') {
          _unreached.remove(from);
          unawaited(_tellHome(from));
        }
      case 'me':
        if (had.state == 'yes') _put(had.copyWith(name: name, bio: bio, picture: said.picture, status: said.status, links: said.links, cosmetics: said.cosmetics));
      case 'ga':
        // What a friend is playing, or that they stopped: kept in memory, never with the list.
        if (had.state == 'yes') GameActivities.instance.heard(from, e.body['ga']);
        return;
      case 'no':
      case 'end':
        GameActivities.instance.heard(from, null);
        all = [for (final o in all) if (o.id != from) o];
        _homes?.forget(from);
        _unreached.remove(from);
      default:
        return;
    }
    unawaited(_save());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _again?.cancel();
    _teller?.cancel();
    _across?.homesChanged.removeListener(_homesChanged);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

class _AppBuddiesPort implements BuddiesPort, BuddiesAcross {
  _AppBuddiesPort() {
    Net.instance.listen((r) => _in.add((from: r.peer.id, envelope: r.envelope)));
    Net.instance.addListener(_follow);
    _follow();
  }

  /// Tells when the routes' [Homes] is another one, or this account's record changed.
  final _homesChanged = ValueNotifier<int>(0);
  Homes? _homes;
  void _homeMoved() => _homesChanged.value++;

  @override
  Homes? get homes => Net.instance.homes;
  @override
  Listenable get homesChanged => _homesChanged;
  @override
  bool passedOn(String id) => Net.instance.hub?.passedOn(id) ?? false;
  @override
  String recall(String key) => Net.instance.recall(key);
  @override
  void remember(String key, String value) => Net.instance.remember(key, value);

  final _in = StreamController<({String from, Envelope envelope})>.broadcast();
  final _hellos = StreamController<({String from, Envelope envelope})>.broadcast();
  Switchboard? _board;
  StreamSubscription<Object?>? _boardSub;

  void _follow() {
    final homes = Net.instance.homes;
    if (!identical(homes, _homes)) {
      _homes?.removeListener(_homeMoved);
      _homes = homes;
      homes?.addListener(_homeMoved);
      _homeMoved();
    }
    final board = Net.instance.board;
    if (identical(board, _board)) return;
    _boardSub?.cancel();
    _board = board;
    _boardSub = board?.strangers.listen((s) => _hellos.add((from: s.from, envelope: s.envelope)));
  }

  @override
  Future<({String id, String key})> me() async {
    final m = await Sms.instance.netIdentity();
    return (id: m.id, key: base64Encode(m.key));
  }

  @override
  String? get username => Me.instance.username;
  @override
  String get displayName => Me.instance.displayName;
  @override
  String get bio => Me.instance.bio;
  @override
  Future<({String id, String key})?> whois(String username) => Me.instance.whois(username);

  @override
  Future<void> keep(String json) async {
    await Sms.instance.buddiesKeep(json);
    await Net.instance.refresh();
  }

  @override
  Future<String> kept() => Sms.instance.buddiesKept();

  @override
  Future<bool> send(String id, Envelope envelope, {bool sealed = true}) async {
    final board = Net.instance.board;
    if (board == null) return false;
    final peer = Net.instance.byId(id) ?? Peer(id: id);
    final d = await board.send(peer, envelope, sealed: sealed, only: const {'hub'});
    return d.sent;
  }

  @override
  Stream<({String from, Envelope envelope})> get received => _in.stream;
  @override
  Stream<({String from, Envelope envelope})> get greetings => _hellos.stream;
}
