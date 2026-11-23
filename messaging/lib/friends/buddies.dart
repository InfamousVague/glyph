import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../games/game_activity.dart';
import '../invites/pending_invites.dart';
import '../me/me.dart';
import '../me/pictures.dart';
import '../net/carrier.dart';
import '../net/crypto.dart';
import '../net/net.dart';
import '../net/packet.dart';
import '../net/switchboard.dart';
import '../sms.dart';
import '../sounds.dart';

/// Someone added by their username on Ghost Messaging, with no phone number between the two (Matt, 2026-11-14:
/// "create a profile and username under "me" to register a username and add friends on the platform").
@immutable
class Buddy {
  const Buddy({required this.username, required this.id, required this.key, this.name = '', this.bio = '', this.state = 'yes', this.at = 0, this.picture = '', this.status = '', this.links = const {}});

  /// Their username, as the relay server's directory has it.
  final String username;

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

  /// Where the two stand: `asked` (this phone asked them), `invited` (they asked this phone), `yes`.
  final String state;

  /// When this phone asked them or was asked, ms since 1970.
  final int at;

  /// Their name, else their username, with no "@" in front (bareName).
  String get shown => name.isEmpty ? bareName(username) : bareName(name);

  Buddy copyWith({String? name, String? bio, String? state, String? picture, String? status, Map<String, String>? links}) => Buddy(
      username: username, id: id, key: key, name: name ?? this.name, bio: bio ?? this.bio, state: state ?? this.state, at: at, picture: picture ?? this.picture, status: status ?? this.status, links: links ?? this.links);

  /// As kept on the phone, handed to a paired computer, and put in an account's backup.
  Map<String, Object> toJson() => {'u': username, 'i': id, 'k': key, 'n': name, 'b': bio, 's': state, 'a': at, if (picture.isNotEmpty) 'p': picture, if (status.isNotEmpty) 'st': status, if (links.isNotEmpty) 'l': links};

  /// Links as sent or kept: network to handle, short strings only; null where none were said.
  static Map<String, String>? _linksOf(Object? l) {
    if (l is! Map) return null;
    return {for (final e in l.entries.take(12)) if (e.key is String && e.value is String && (e.value as String).length <= 80) e.key as String: e.value as String};
  }

  /// The buddy [j] is; null without a username, an id and a key. A picture over the limit is left out.
  static Buddy? fromJson(Object? j) {
    if (j is! Map) return null;
    final u = j['u'], i = j['i'], k = j['k'];
    if (u is! String || i is! String || k is! String) return null;
    final p = j['p'] is String && (j['p'] as String).length <= ProfilePictures.most ? j['p'] as String : '';
    return Buddy(username: u, id: i, key: k, name: '${j['n'] ?? ''}', bio: '${j['b'] ?? ''}', state: '${j['s'] ?? 'yes'}', at: (j['a'] as num?)?.toInt() ?? 0, picture: p, status: '${j['st'] ?? ''}', links: _linksOf(j['l']) ?? const {});
  }
}

/// What [Buddies] stands on: the directory, the routes, the phone. The app's is [_AppBuddiesPort]; a test gives
/// two that reach each other.
abstract class BuddiesPort {
  /// This install's name and public key (base64).
  Future<({String id, String key})> me();

  /// This person's own username, name and line; and who has [username] in the relay's directory (null for nobody).
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

/// What [Buddies.lookup] found.
enum BuddyLookup { nobody, you, someone }

/// Friends by username on this install: the list, the requests either way, and what friends are told of this
/// person. On a computer paired with a phone it asks the phone for everything.
///
/// Becoming friends is said over the routes as envelopes of kind `buddy`:
/// - **ask**, in the clear, as a greeting (`hello` with `buddy: ask`), carrying the asker's username, name, line
///   and public key. Anyone can send it; the hub says who sent it, and the key is checked against that name, so it
///   can't be sent in someone else's name. It is shown as a request, and nothing more is taken from it.
/// - **yes**, sealed: the other said yes; their name and line come with it. Two who ask each other are friends.
/// - **no** and **end**, sealed: no, or no longer. **me**, sealed: a friend changed their name or line.
///
/// The list is kept on the phone (`buddies`), and the phone works out the key each pair seals with from it, so
/// the routes reach them as they reach anyone encryption is on with.
class Buddies extends ChangeNotifier {
  Buddies(this._port);

  static Buddies? _instance;
  static Buddies get instance => _instance ??= Buddies(_AppBuddiesPort());

  @visibleForTesting
  static set instance(Buddies? b) => _instance = b;

  final BuddiesPort _port;
  final List<StreamSubscription<Object?>> _subs = [];

  /// Everyone a request has passed between, whatever its state.
  List<Buddy> all = [];
  bool _started = false;

  /// Those who said yes, or were said yes to.
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

  /// Those who asked this person and wait for an answer; and those this person asked.
  List<Buddy> get requests => [for (final b in all) if (b.state == 'invited') b];
  List<Buddy> get asked => [for (final b in all) if (b.state == 'asked') b];

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

  /// On a computer: asks the phone to do [what], and takes the list it answers with. A refusal comes as a [MeError].
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
      all = [for (final j in list) ?Buddy.fromJson(j)];
      notifyListeners();
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
      case 'share':
        await shareProfile();
      case 'ga':
        // The computer's game, said to friends in this phone's name: the phone is who they are friends with.
        await sayActivity(GameActivity.fromJson(what['ga']));
    }
    return {'list': list(), 'ga': GameActivities.instance.all()};
  }

  /// On a phone: reads the kept list, listens to the routes, and begins asking unanswered requests again. On a
  /// paired computer: reads the phone's list, now and every twenty seconds.
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
    notifyListeners();
    // A request the hub was holding for someone away is lost when the relay restarts, and so is an answer, and nothing
    // asked again (Matt, 2026-11-19: "my friend request to morgan never went through i also sent one from her phone and
    // it didn't go out"; the relay restarted five times that evening, one deploy each). Each unanswered request is
    // asked again: a little after starting, once the hub is reached, and every few minutes, for two weeks. The other
    // side takes a request it holds already as the same one, and answers one it has said yes to again.
    Timer(const Duration(seconds: 15), () => unawaited(askAgain()));
    _again = Timer.periodic(askEvery, (_) => unawaited(askAgain()));
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
        if (await _port.send(b.id, Envelope(kind: 'hello', body: {'buddy': 'ask', 'k': me.key, ..._profile()}), sealed: false)) sent++;
      } catch (_) {}
    }
    return sent;
  }

  /// Keeps the list on the phone and tells listeners.
  Future<void> _save() async {
    await _port.keep(jsonEncode([for (final b in all) b.toJson()]));
    notifyListeners();
  }

  /// Puts [b] in the list in place of whoever had its id, and keeps their picture.
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
    return {'u': _port.username ?? '', 'n': _port.displayName, 'b': _port.bio, if (me.picture.isNotEmpty) 'p': me.picture, if (sharp != me.picture) 'pp': sharp, 'st': me.status, 'l': me.shareLinks ? me.links : const <String, String>{}};
  }

  /// A picture and status said in [body], where it says them: null for each it does not (a build from before).
  @visibleForTesting
  static ({String? picture, String? status, Map<String, String>? links}) saidOf(Map body) => _said(body);

  static ({String? picture, String? status, Map<String, String>? links}) _said(Map body) {
    final pp = body['pp'], p = body['p'];
    final picture = pp is String && pp.isNotEmpty && pp.length <= ProfilePictures.most ? pp : p;
    return (picture: picture is String && picture.length <= ProfilePictures.most ? picture : (body.containsKey('st') ? '' : null), status: body['st'] is String ? body['st'] as String : null, links: Buddy._linksOf(body['l']));
  }

  /// Who [username] is, as the add-friend drawer shows it while it is typed: nobody, this install itself, or someone
  /// (lib/ui/add_friend_drawer.dart). Asks the same server [add] asks.
  Future<BuddyLookup> lookup(String username) async {
    if (_remote) return BuddyLookup.values.asNameMap()['${(await _ask({'op': 'lookup', 'u': username}))['found']}'] ?? BuddyLookup.nobody;
    final found = await _port.whois(tidyHandle(username));
    if (found == null) return BuddyLookup.nobody;
    if (found.id == (await _port.me()).id) return BuddyLookup.you;
    return BuddyLookup.someone;
  }

  /// Asks [username] to be friends. Throws a [MeError] where nobody has that username, or it is this install's.
  Future<Buddy> add(String username) async {
    if (_remote) return Buddy.fromJson((await _ask({'op': 'add', 'u': username}))['buddy'])!;
    final name = tidyHandle(username);
    if (_port.username == null) throw MeError('Choose your own username first.');
    final found = await _port.whois(name);
    if (found == null) throw MeError('Nobody has the username @$name.');
    final me = await _port.me();
    if (found.id == me.id) throw MeError('That\'s you.');
    final had = byId(found.id);
    if (had != null && had.state == 'yes') return had;
    // They asked first: this is a yes.
    if (had != null && had.state == 'invited') return accept(had);
    final b = Buddy(username: name, id: found.id, key: found.key, state: 'asked', at: DateTime.now().millisecondsSinceEpoch);
    _put(b);
    await _save();
    await _port.send(found.id, Envelope(kind: 'hello', body: {'buddy': 'ask', 'k': me.key, ..._profile()}), sealed: false);
    return b;
  }

  /// Yes to [b]: friends from now, and they are told, with this person's profile.
  Future<Buddy> accept(Buddy b) async {
    if (_remote) return Buddy.fromJson((await _ask({'op': 'accept', 'id': b.id}))['buddy'])!;
    final yes = b.copyWith(state: 'yes');
    _put(yes);
    await _save();
    await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'yes', ..._profile()}));
    return yes;
  }

  /// No to [b], who asked: off the list, and they are told.
  Future<void> decline(Buddy b) async {
    if (_remote) {
      await _ask({'op': 'decline', 'id': b.id});
      return;
    }
    all = [for (final o in all) if (o.id != b.id) o];
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

  /// A request in the clear from [from]: checked, then kept as a request, or taken as a yes where this phone had
  /// asked them too.
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
    final name = '${e.body['n'] ?? ''}', bio = '${e.body['b'] ?? ''}';
    final said = _said(e.body);
    if (had?.state == 'yes') {
      // Asked again by a friend already: our yes was lost on its way (askAgain). Said again.
      unawaited(_port.send(from, Envelope(kind: 'buddy', body: {'s': 'yes', ..._profile()})));
      return;
    }
    if (had?.state == 'asked') {
      // Both asked: friends.
      unawaited(accept(had!.copyWith(name: name, bio: bio, picture: said.picture, status: said.status, links: said.links)));
      return;
    }
    // A request new to this phone: the friend request's sound (lib/sounds.dart), once.
    if (had?.state != 'invited') Sounds.instance.play(UiSound.friendRequest);
    _put(Buddy(username: tidyHandle(username), id: from, key: key, name: name, bio: bio, state: 'invited', at: DateTime.now().millisecondsSinceEpoch, picture: said.picture ?? '', status: said.status ?? '', links: said.links ?? const {}));
    unawaited(_save());
  }

  /// A sealed `buddy` envelope from someone on the list: their yes, no or end, a changed profile, or their game.
  void _sealed(String from, Envelope e) {
    if (e.kind != 'buddy') return;
    final had = byId(from);
    if (had == null) return;
    final name = e.body['n'] is String ? e.body['n'] as String : null, bio = e.body['b'] is String ? e.body['b'] as String : null;
    final said = _said(e.body);
    switch (e.body['s']) {
      case 'yes':
        if (had.state == 'asked') Sounds.instance.play(UiSound.friendAccepted);
        if (had.state == 'asked' || had.state == 'yes') _put(had.copyWith(state: 'yes', name: name, bio: bio, picture: said.picture, status: said.status, links: said.links));
      case 'me':
        if (had.state == 'yes') _put(had.copyWith(name: name, bio: bio, picture: said.picture, status: said.status, links: said.links));
      case 'ga':
        // What a friend is playing, or that they stopped: kept in memory, never with the list.
        if (had.state == 'yes') GameActivities.instance.heard(from, e.body['ga']);
        return;
      case 'no':
      case 'end':
        GameActivities.instance.heard(from, null);
        all = [for (final o in all) if (o.id != from) o];
      default:
        return;
    }
    unawaited(_save());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _again?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

/// The app's own: the routes (lib/net/net.dart), Settings › Me and the phone.
class _AppBuddiesPort implements BuddiesPort {
  _AppBuddiesPort() {
    Net.instance.listen((r) => _in.add((from: r.peer.id, envelope: r.envelope)));
    Net.instance.addListener(_follow);
    _follow();
  }

  final _in = StreamController<({String from, Envelope envelope})>.broadcast();
  final _hellos = StreamController<({String from, Envelope envelope})>.broadcast();
  Switchboard? _board;
  StreamSubscription<Object?>? _boardSub;

  /// Listens to the switchboard's strangers (greetings in the clear), and again each time the routes are set up anew.
  void _follow() {
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
