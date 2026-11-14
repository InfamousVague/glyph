import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../net/carrier.dart';
import '../net/crypto.dart';
import '../net/hub_carrier.dart';

/// A network an account can be linked on (Matt, 2026-11-14: "allow linking popular social like telegram, discord, x,
/// etc"). Discord, Telegram and X are proved by signing in there; Bluesky, Mastodon and GitHub by a code put in the
/// account's public profile, and those three say who an account follows, which the others do not let an app read.
class Network {
  const Network(this.id, this.name, this.hue, this.mark, {required this.signIn, this.example = 'username', this.where = ''});
  final String id;
  final String name;

  /// Its colour among Settings' (kit/settings_css.dart), and the letters on its chip. No network's own logo is drawn.
  final String hue;
  final String mark;

  /// Proved by signing in there; otherwise by a code in the profile.
  final bool signIn;
  final String example;

  /// Where in the account the code goes, for a network proved by code.
  final String where;

  /// Who you follow there can be read, and so brought into the watch list.
  bool get follows => !signIn;

  /// The page of [handle]'s account, or null where a username alone does not make an address (Discord).
  String? profile(String handle) => switch (id) {
        'telegram' => 'https://t.me/$handle',
        'x' => 'https://x.com/$handle',
        'bluesky' => 'https://bsky.app/profile/$handle',
        'github' => 'https://github.com/$handle',
        'mastodon' => handle.contains('@') ? 'https://${handle.split('@')[1]}/@${handle.split('@')[0]}' : null,
        _ => null,
      };
}

const networks = [
  Network('discord', 'Discord', 'indigo', 'D', signIn: true),
  Network('telegram', 'Telegram', 'cyan', 'T', signIn: true),
  Network('x', 'X', 'graphite', 'X', signIn: true),
  Network('bluesky', 'Bluesky', 'blue', 'B', signIn: false, example: 'you.bsky.social', where: 'your Bluesky bio (Edit profile › Description)'),
  Network('mastodon', 'Mastodon', 'purple', 'M', signIn: false, example: 'you@mastodon.social', where: 'your Mastodon bio, or one of its profile fields (Edit profile)'),
  Network('github', 'GitHub', 'slate', 'G', signIn: false, where: 'your GitHub bio (Edit profile › Bio)'),
];

Network networkOf(String id) => networks.firstWhere((n) => n.id == id, orElse: () => networks.first);

/// A handle as it is compared: no "@" in front, no spaces around, lower case (the server's `Handles.tidy`).
String tidyHandle(String handle) {
  var h = handle.trim().toLowerCase();
  while (h.startsWith('@')) {
    h = h.substring(1);
  }
  return h;
}

final _plain = RegExp(r'^[a-z0-9._-]{1,64}$');
final _host = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,24}$');

/// Whether [handle] (tidied) could be one on [network].
bool handleFits(String network, String handle) {
  switch (network) {
    case 'mastodon':
      final at = handle.indexOf('@');
      return at > 0 && _plain.hasMatch(handle.substring(0, at)) && _host.hasMatch(handle.substring(at + 1));
    case 'bluesky':
      return _host.hasMatch(handle);
    default:
      return _plain.hasMatch(handle);
  }
}

/// What a handle is kept and watched by on the server: a hash, so its lists name nobody (the server's
/// `Handles.keyOf`; relay/test/handles_test.dart holds the two to the same answer).
String handleKey(String network, String handle) => NetCrypto.hex(NetCrypto.sha256(utf8.encode('ghost-handle v1|$network|${tidyHandle(handle)}')));

/// Someone being watched for.
@immutable
class Watched {
  const Watched(this.network, this.handle);
  final String network;
  final String handle;

  String get key => handleKey(network, handle);
  String get id => '$network:$handle';

  @override
  bool operator ==(Object other) => other is Watched && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Someone watched for who is on Ghost Messaging.
class Joined {
  const Joined(this.network, this.handle, this.at, {this.seen = false});
  final String network;
  final String handle;
  final DateTime at;
  final bool seen;
}

/// Where what is kept on the phone is kept: the app's preferences ([AppMeStore]), or a map (a test).
abstract class MeStore {
  String choice(String key, String fallback);
  bool flag(String key, {bool fallback = true});
  void set(String key, String value);
  void setFlag(String key, bool on);
}

class AppMeStore implements MeStore {
  AppMeStore(this.app);
  final AppState app;
  @override
  String choice(String key, String fallback) => app.choice(key, fallback);
  @override
  bool flag(String key, {bool fallback = true}) => app.flag(key, fallback: fallback);
  @override
  void set(String key, String value) => app.set(key, value);
  @override
  void setFlag(String key, bool on) => app.setFlag(key, on);
}

class MemoryMeStore implements MeStore {
  final Map<String, String> kept = {};
  @override
  String choice(String key, String fallback) => kept[key] ?? fallback;
  @override
  bool flag(String key, {bool fallback = true}) => kept[key] == null ? fallback : kept[key] == 'on';
  @override
  void set(String key, String value) => kept[key] = value;
  @override
  void setFlag(String key, bool on) => kept[key] = on ? 'on' : 'off';
}

class MeError implements Exception {
  MeError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// You, to the people who know you somewhere else: the accounts you proved are yours, whether friends are told you
/// are here, the handles you asked to be told about, and who of them has joined.
///
/// Everything is kept on the phone. What the relay server keeps of it is hashes (relay/lib/handles.dart), and only
/// once an account is linked or a handle watched for: until then nothing about this is said to it at all.
class Me extends ChangeNotifier {
  Me._();
  static final Me instance = Me._();

  /// A fresh one, for a test.
  @visibleForTesting
  factory Me.forTest() => Me._();

  MeStore? _app;
  HubCarrier? Function()? _hubNow;
  HubCarrier? _hub;
  StreamSubscription<Map<String, dynamic>>? _sub;
  VoidCallback? _stateListener;

  /// network -> handle, for the accounts proved.
  Map<String, String> links = {};

  /// Whether friends who watch for one of [links] are told. Off until switched on.
  bool listed = false;
  List<Watched> watch = [];
  List<Joined> joined = [];

  /// How each network is linked on the server we are connected to: "signin", "proof" or "off". Empty until it says.
  Map<String, String> ways = {};

  /// The relay server has answered: linking and watching work.
  bool ready = false;

  int get unseen => joined.where((j) => !j.seen).length;

  /// Whether anything has ever been said to the server about this install: only then is it spoken to as the app opens.
  bool get _inUse => links.isNotEmpty || watch.isNotEmpty || listed || (_app?.flag('me_used', fallback: false) ?? false);

  final Map<String, Completer<Map<String, dynamic>>> _waiting = {};

  /// Networks unlinked while the server could not be told.
  Set<String> get _dropped => (_app?.choice('me_dropped', '') ?? '').split(',').where((p) => p.isNotEmpty).toSet();

  // --- kept on the phone --------------------------------------------------------------------------------------------

  void _read() {
    final app = _app;
    if (app == null) return;
    try {
      links = (jsonDecode(app.choice('me_links', '{}')) as Map).cast<String, String>();
      watch = [for (final w in jsonDecode(app.choice('me_watch', '[]')) as List) Watched((w as String).substring(0, w.indexOf(':')), w.substring(w.indexOf(':') + 1))];
      joined = [for (final j in jsonDecode(app.choice('me_joined', '[]')) as List) Joined((j as Map)['p'] as String, j['h'] as String, DateTime.fromMillisecondsSinceEpoch(j['at'] as int), seen: j['seen'] == true)];
      listed = app.flag('me_listed', fallback: false);
    } catch (_) {}
  }

  void _write() {
    final app = _app;
    if (app == null) return;
    app.set('me_links', jsonEncode(links));
    app.set('me_watch', jsonEncode([for (final w in watch) w.id]));
    app.set('me_joined', jsonEncode([for (final j in joined) {'p': j.network, 'h': j.handle, 'at': j.at.millisecondsSinceEpoch, 'seen': j.seen}]));
    app.setFlag('me_listed', listed);
    notifyListeners();
  }

  // --- the server ----------------------------------------------------------------------------------------------------

  /// Follows the app's routes: whichever relay server the app is connected to is the one spoken to. [routes] says
  /// when that may have changed, and [hub] which it is now (the app: its routes, lib/net/net.dart, and their hub).
  Future<void> start(MeStore app, Listenable routes, HubCarrier? Function() hub) async {
    _app = app;
    _hubNow = hub;
    _read();
    routes.addListener(_attach);
    _attach();
    notifyListeners();
  }

  void _attach() {
    final hub = _hubNow?.call();
    if (identical(hub, _hub)) return;
    _sub?.cancel();
    if (_stateListener != null) _hub?.state.removeListener(_stateListener!);
    _hub = hub;
    ready = false;
    if (hub == null) return;
    _sub = hub.handles.listen(_heard);
    void changed() {
      if (hub.state.value == CarrierState.up) {
        if (_inUse) _hello();
      } else if (ready) {
        ready = false;
        notifyListeners();
      }
    }

    _stateListener = changed;
    hub.state.addListener(changed);
    changed();
  }

  void _hello() => _hub?.sayHandles({'dir': 'hello'});

  /// Speaks to the server for the first time, where nothing has been before (the Me page as it opens).
  void wake() {
    if (ready || _hub == null) return;
    _hello();
  }

  bool get reachable => _hub != null && _hub!.state.value == CarrierState.up;

  void _heard(Map<String, dynamic> m) {
    final network = m['p'] as String?;
    switch (m['dir']) {
      case 'hello':
        ways = (m['ways'] as Map? ?? const {}).cast<String, String>();
        ready = true;
        // The server is the word on what is linked there; the phone is the word on which handle each is.
        final there = {for (final l in (m['links'] as List? ?? const [])) (l as Map)['p'] as String: l['k'] as String?};
        links.removeWhere((p, h) => there[p] != handleKey(p, h));
        for (final p in _dropped) {
          _hub?.sayHandles({'dir': 'unlink', 'p': p});
        }
        if (_dropped.isNotEmpty) _app?.set('me_dropped', '');
        if ((m['listed'] == true) != listed) _hub?.sayHandles({'dir': 'listed', 'on': listed});
        // The whole list again, in case the server was started afresh: said twice, a handle is watched once.
        final keys = [for (final w in watch) w.key];
        for (var i = 0; i < keys.length; i += 400) {
          _hub?.sayHandles({'dir': 'watch', 'add': keys.sublist(i, i + 400 > keys.length ? keys.length : i + 400)});
        }
        _write();
      case 'link':
      case 'proof':
      case 'follows':
      case 'unlinked':
      case 'forgotten':
        _waiting.remove('${m['dir']}:${network ?? ''}')?.complete(m);
      case 'linked':
        if (network != null && m['handle'] is String) {
          links[network] = m['handle'] as String;
          _app?.setFlag('me_used', true);
          _write();
        }
        _waiting.remove('linked:${network ?? ''}')?.complete(m);
      case 'listed':
        listed = m['on'] == true;
        _write();
      case 'joined':
        final keys = (m['list'] as List? ?? const []).cast<String>().toSet();
        var changed = false;
        for (final w in watch) {
          if (!keys.contains(w.key) || joined.any((j) => j.network == w.network && j.handle == w.handle)) continue;
          joined.insert(0, Joined(w.network, w.handle, DateTime.now()));
          changed = true;
        }
        if (changed) _write();
      case 'err':
        final about = m['about'] as String?;
        final error = MeError((m['err'] as String?) ?? 'That did not work.');
        // A check that fails answers whoever waits for "linked".
        for (final key in ['$about:${network ?? ''}', if (about == 'check') 'linked:${network ?? ''}']) {
          final c = _waiting.remove(key);
          if (c != null && !c.isCompleted) c.completeError(error);
        }
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> _ask(Map<String, Object?> what, String answer, {Duration wait = const Duration(seconds: 25)}) {
    final hub = _hub;
    if (hub == null || !hub.sayHandles(what)) return Future.error(MeError('The relay server can\'t be reached right now.'));
    _app?.setFlag('me_used', true);
    final key = '$answer:${what['p'] ?? ''}';
    _waiting.remove(key);
    final done = _waiting[key] = Completer<Map<String, dynamic>>();
    return done.future.timeout(wait, onTimeout: () {
      _waiting.remove(key);
      throw MeError('The relay server did not answer.');
    });
  }

  /// The address to open in a browser to sign in on [network] and prove the account. The link itself arrives
  /// later, when the sign-in is done ([links] changes).
  Future<String> signInAddress(String network) async => (await _ask({'dir': 'link', 'p': network}, 'link'))['url'] as String;

  /// The code to put in [handle]'s public profile on [network].
  Future<String> proofCode(String network, String handle) async => (await _ask({'dir': 'proof', 'p': network, 'handle': tidyHandle(handle)}, 'proof'))['code'] as String;

  /// Has the server read the profile and look for the code: linked where it is there.
  Future<void> check(String network, String handle) => _ask({'dir': 'check', 'p': network, 'handle': tidyHandle(handle)}, 'linked', wait: const Duration(seconds: 40));

  Future<void> unlink(String network) async {
    links.remove(network);
    _write();
    try {
      await _ask({'dir': 'unlink', 'p': network}, 'unlinked', wait: const Duration(seconds: 8));
    } catch (_) {
      // Not heard: written down, and said again as the server next answers.
      final waiting = {..._dropped, network};
      _app?.set('me_dropped', waiting.join(','));
    }
  }

  void setListed(bool on) {
    listed = on;
    _app?.setFlag('me_used', true);
    _write();
    _hub?.sayHandles({'dir': 'listed', 'on': on});
  }

  /// Splits what was typed or pasted into handles: by spaces, commas, semicolons and new lines.
  static List<String> split(String text) => text.split(RegExp(r'[\s,;]+')).map(tidyHandle).where((h) => h.isNotEmpty).toSet().toList();

  static const maxWatch = 5000;

  /// Adds [handles] on [network] to the watch list; how many were new. Ones that could not be a handle there are
  /// left out.
  int addWatch(String network, Iterable<String> handles) {
    final mine = links[network];
    final fresh = <Watched>[];
    for (final h in handles.map(tidyHandle)) {
      if (!handleFits(network, h) || h == mine) continue;
      final w = Watched(network, h);
      if (watch.contains(w) || fresh.contains(w)) continue;
      if (watch.length + fresh.length >= maxWatch) break;
      fresh.add(w);
    }
    if (fresh.isEmpty) return 0;
    watch = [...fresh, ...watch];
    _app?.setFlag('me_used', true);
    _write();
    final keys = [for (final w in fresh) w.key];
    for (var i = 0; i < keys.length; i += 400) {
      _hub?.sayHandles({'dir': 'watch', 'add': keys.sublist(i, i + 400 > keys.length ? keys.length : i + 400)});
    }
    return fresh.length;
  }

  void removeWatch(Watched w) {
    watch = [for (final x in watch) if (x != w) x];
    joined = [for (final j in joined) if (!(j.network == w.network && j.handle == w.handle)) j];
    _write();
    _hub?.sayHandles({'dir': 'watch', 'remove': [w.key]});
  }

  /// Brings who the linked account on [network] follows into the watch list; how many were new.
  Future<int> importFollows(String network) async {
    final handle = links[network];
    if (handle == null) throw MeError('Link your ${networkOf(network).name} account first.');
    final got = await _ask({'dir': 'follows', 'p': network, 'handle': handle}, 'follows', wait: const Duration(seconds: 90));
    return addWatch(network, (got['handles'] as List? ?? const []).cast<String>());
  }

  void markSeen() {
    if (unseen == 0) return;
    joined = [for (final j in joined) Joined(j.network, j.handle, j.at, seen: true)];
    _write();
  }

  /// What the pages show, set by hand: a picture of them with no server (test/screens_test.dart).
  @visibleForTesting
  void seed({Map<String, String>? links, bool? listed, List<Watched>? watch, List<Joined>? joined, Map<String, String>? ways, bool? ready}) {
    this.links = links ?? this.links;
    this.listed = listed ?? this.listed;
    this.watch = watch ?? this.watch;
    this.joined = joined ?? this.joined;
    this.ways = ways ?? this.ways;
    this.ready = ready ?? this.ready;
    notifyListeners();
  }

  /// Takes everything about this install off the server, and off the phone.
  Future<void> forgetEverything() async {
    try {
      await _ask({'dir': 'forget'}, 'forgotten', wait: const Duration(seconds: 8));
    } finally {
      links = {};
      watch = [];
      joined = [];
      listed = false;
      _app?.setFlag('me_used', false);
      _write();
    }
  }
}
