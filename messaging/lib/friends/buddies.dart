import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../invites/pending_invites.dart';
import '../me/me.dart';
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
  const Buddy({required this.username, required this.id, required this.key, this.name = '', this.bio = '', this.state = 'yes', this.at = 0});

  /// Their username, as the relay server's directory has it.
  final String username;

  /// Their install's name (NetCrypto.idOf their key) and their public key in base64: what packets to them are sealed
  /// with, as the phone works it out (android Buddies.kt).
  final String id;
  final String key;

  /// What they said about themselves: sent by them, kept here, never asked of the server.
  final String name;
  final String bio;

  /// Where the two stand: `asked` (this phone asked them), `invited` (they asked this phone), `yes`.
  final String state;
  final int at;

  String get shown => name.isEmpty ? '@$username' : name;

  Buddy copyWith({String? name, String? bio, String? state}) => Buddy(username: username, id: id, key: key, name: name ?? this.name, bio: bio ?? this.bio, state: state ?? this.state, at: at);

  Map<String, Object> toJson() => {'u': username, 'i': id, 'k': key, 'n': name, 'b': bio, 's': state, 'a': at};

  static Buddy? fromJson(Object? j) {
    if (j is! Map) return null;
    final u = j['u'], i = j['i'], k = j['k'];
    if (u is! String || i is! String || k is! String) return null;
    return Buddy(username: u, id: i, key: k, name: '${j['n'] ?? ''}', bio: '${j['b'] ?? ''}', state: '${j['s'] ?? 'yes'}', at: (j['a'] as num?)?.toInt() ?? 0);
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
/// What [Buddies.lookup] found.
enum BuddyLookup { nobody, you, someone }

class Buddies extends ChangeNotifier {
  Buddies(this._port);

  static Buddies? _instance;
  static Buddies get instance => _instance ??= Buddies(_AppBuddiesPort());

  @visibleForTesting
  static set instance(Buddies? b) => _instance = b;

  final BuddiesPort _port;
  final List<StreamSubscription<Object?>> _subs = [];
  List<Buddy> all = [];
  bool _started = false;

  List<Buddy> get friends => [for (final b in all) if (b.state == 'yes') b];
  List<Buddy> get requests => [for (final b in all) if (b.state == 'invited') b];
  List<Buddy> get asked => [for (final b in all) if (b.state == 'asked') b];

  Buddy? byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return null;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
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
  }

  Future<void> _save() async {
    await _port.keep(jsonEncode([for (final b in all) b.toJson()]));
    notifyListeners();
  }

  void _put(Buddy b) {
    all = [for (final o in all) if (o.id != b.id) o, b];
  }

  Map<String, Object> _profile() => {'u': _port.username ?? '', 'n': _port.displayName, 'b': _port.bio};

  /// Who [username] is, as the add-friend drawer shows it while it is typed: nobody, this install itself, or someone
  /// (lib/ui/add_friend_drawer.dart). Asks the same server [add] asks.
  Future<BuddyLookup> lookup(String username) async {
    final found = await _port.whois(tidyHandle(username));
    if (found == null) return BuddyLookup.nobody;
    if (found.id == (await _port.me()).id) return BuddyLookup.you;
    return BuddyLookup.someone;
  }

  /// Asks [username] to be friends. Throws a [MeError] where nobody has that username, or it is this install's.
  Future<Buddy> add(String username) async {
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

  Future<Buddy> accept(Buddy b) async {
    final yes = b.copyWith(state: 'yes');
    _put(yes);
    await _save();
    await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'yes', ..._profile()}));
    return yes;
  }

  Future<void> decline(Buddy b) async {
    all = [for (final o in all) if (o.id != b.id) o];
    await _save();
    await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'no'}));
  }

  /// No longer friends: removed here, and they are told.
  Future<void> remove(Buddy b) async {
    await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'end'}));
    all = [for (final o in all) if (o.id != b.id) o];
    await _save();
  }

  /// Tells every friend this phone's name and line, after they changed.
  Future<void> shareProfile() async {
    for (final b in friends) {
      await _port.send(b.id, Envelope(kind: 'buddy', body: {'s': 'me', ..._profile()}));
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
    final name = '${e.body['n'] ?? ''}', bio = '${e.body['b'] ?? ''}';
    if (had?.state == 'yes') return;
    if (had?.state == 'asked') {
      // Both asked: friends.
      unawaited(accept(had!.copyWith(name: name, bio: bio)));
      return;
    }
    // A request new to this phone: the friend request's sound (lib/sounds.dart), once.
    if (had?.state != 'invited') Sounds.instance.play(UiSound.friendRequest);
    _put(Buddy(username: tidyHandle(username), id: from, key: key, name: name, bio: bio, state: 'invited', at: DateTime.now().millisecondsSinceEpoch));
    unawaited(_save());
  }

  void _sealed(String from, Envelope e) {
    if (e.kind != 'buddy') return;
    final had = byId(from);
    if (had == null) return;
    final name = e.body['n'] is String ? e.body['n'] as String : null, bio = e.body['b'] is String ? e.body['b'] as String : null;
    switch (e.body['s']) {
      case 'yes':
        if (had.state == 'asked') Sounds.instance.play(UiSound.friendAccepted);
        if (had.state == 'asked' || had.state == 'yes') _put(had.copyWith(state: 'yes', name: name, bio: bio));
      case 'me':
        if (had.state == 'yes') _put(had.copyWith(name: name, bio: bio));
      case 'no':
      case 'end':
        all = [for (final o in all) if (o.id != from) o];
      default:
        return;
    }
    unawaited(_save());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

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
