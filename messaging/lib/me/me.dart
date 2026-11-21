import 'dart:async';
import 'dart:io' show Platform;
import '../names.dart';
export '../names.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'picture_make.dart';
import 'pictures.dart';

import '../account/account_crypto.dart' show AccountCrypto;
import '../app_state.dart';
import '../invites/invite_seal.dart' show WaitingInvite;
import '../invites/text_invites.dart';
import '../inbox/curl_sync.dart';
import '../kept_lists.dart';
import '../net/carrier.dart';
import '../net/crypto.dart';
import '../net/hub_carrier.dart';
import '../plugins/codes.dart' show signInCode;
import '../sms.dart' show Sms;

/// A network an account can be linked on (Matt, 2026-11-14: "allow linking popular social like telegram, discord, x,
/// etc"). Discord, Telegram and X are proved by signing in there; Bluesky, Mastodon and GitHub by a code put in the
/// account's public profile, and those three say who an account follows, which the others do not let an app read.
class Network {
  const Network(this.id, this.name, this.hue, this.mark, {required this.signIn, this.example = 'username', this.where = '', this.soon = false});
  final String id;
  final String name;

  /// Its colour among Settings' (kit/settings_css.dart), and the letter on its chip where its logo is not to hand
  /// (its logo is lib/me/network_marks.g.dart's).
  final String hue;
  final String mark;

  /// Proved by signing in there; otherwise by a code in the profile.
  final bool signIn;
  final String example;

  /// Where in the account the code goes, for a network proved by code.
  final String where;

  /// Shown as "Coming soon", and neither linked nor watched for yet (Matt, 2026-11-14: "remove mastadon and the
  /// other options to link or mark them as 'coming soon'", once Discord, X and Telegram had their keys).
  final bool soon;

  /// Who you follow there can be read, and so brought into the watch list.
  bool get follows => !signIn && !soon;

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
  Network('bluesky', 'Bluesky', 'blue', 'B', signIn: false, example: 'you.bsky.social', where: 'your Bluesky bio (Edit profile › Description)', soon: true),
  Network('mastodon', 'Mastodon', 'purple', 'M', signIn: false, example: 'you@mastodon.social', where: 'your Mastodon bio, or one of its profile fields (Edit profile)', soon: true),
  Network('github', 'GitHub', 'slate', 'G', signIn: false, where: 'your GitHub bio (Edit profile › Bio)', soon: true),
];

/// The networks that can be linked and watched for now.
List<Network> get openNetworks => [for (final n in networks) if (!n.soon) n];

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

/// A phone number as it is compared and texted: "+", the country's code, the digits. Ten digits, or eleven that
/// start with 1, are read as a North American number. Empty where what was typed holds anything a number does not
/// (the server's `Handles.tidyNumber`; test/me_test.dart holds the two to the same answer).
String tidyNumber(String typed) {
  final t = typed.trim();
  if (!RegExp(r'^\+?[0-9 ().\-]+$').hasMatch(t)) return '';
  final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (t.startsWith('+')) return '+$digits';
  if (digits.length == 10) return '+1$digits';
  if (digits.length == 11 && digits.startsWith('1')) return '+$digits';
  return digits;
}

final _number = RegExp(r'^\+[1-9][0-9]{7,14}$');
final _northAmerican = RegExp(r'^\+1[2-9][0-9]{9}$');

/// Whether [number] (tidied) is a whole phone number.
bool numberFits(String number) => _number.hasMatch(number) && (!number.startsWith('+1') || _northAmerican.hasMatch(number));

/// A tidied number as it is read: "+1 (555) 010-0199" for a North American one, as it is for any other.
String showNumber(String number) =>
    _northAmerican.hasMatch(number) ? '+1 (${number.substring(2, 5)}) ${number.substring(5, 8)}-${number.substring(8)}' : number;

/// The code in a text, where the text is the one asked for with [Me.textCode]: a sign-in code in a text that names
/// the app. Another company's code that arrives meanwhile is not read as ours, so it never leaves the phone.
String? ownCodeIn(String text) => text.toLowerCase().contains('ghost') ? signInCode(text) : null;

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
  void Function(bool yes)? _needHub;

  /// Settings › Me has been opened since the app started: the server is said hello to as soon as it can be.
  bool _woken = false;
  HubCarrier? _hub;
  StreamSubscription<Map<String, dynamic>>? _sub;
  VoidCallback? _stateListener;

  /// network -> handle, for the accounts proved; and "phone" -> this phone's number, once a code texted to it
  /// came back ([textCode], [tryCode]).
  Map<String, String> links = {};

  /// This phone's number, where it has been shown to be: nobody is told it, listed or not.
  String? get number => links['phone'];

  /// The accounts linked: every link but the number.
  Map<String, String> get accounts => {
        for (final e in links.entries)
          if (e.key != 'phone') e.key: e.value,
      };

  /// Whether the server we are connected to can text a number its code.
  bool get texts => ways['phone'] == 'text';

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
      // A number verified before the phone was told it (the separate "Your number" setting is gone).
      _tellPhoneItsNumber();
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
    _tellPhoneItsNumber();
    notifyListeners();
  }

  /// The verified number is this phone's own (Matt, 2026-11-19: "remove the duplicate "your number" setting it's
  /// already handled under me"): told to Android's side, which leaves it out of a group picture message's people
  /// where Android itself doesn't know the phone's number. Only on the phone; once for each number.
  String? _toldNumber;
  void _tellPhoneItsNumber() {
    final n = number;
    if (n == null || n == _toldNumber || kIsWeb || !Platform.isAndroid || Sms.remote) return;
    _toldNumber = n;
    unawaited(Sms.instance.setOwnNumber(n).catchError((_) {}));
  }

  // --- the server ----------------------------------------------------------------------------------------------------

  /// Follows the app's routes: whichever relay server the app is connected to is the one spoken to. [routes] says
  /// when that may have changed, and [hub] which it is now (the app: its routes, lib/net/net.dart, and their hub).
  /// [needHub] is told whether the relay server must be kept connected for this (the app: Net.want): from the
  /// start where anything has ever been said to it, and from the moment Settings › Me is opened.
  Future<void> start(MeStore app, Listenable routes, HubCarrier? Function() hub, {void Function(bool yes)? needHub}) async {
    _app = app;
    _hubNow = hub;
    _needHub = needHub;
    _read();
    // Woken before it started (the first page, lib/standalone/welcome.dart, drawn the moment the walkthrough ends).
    if (_inUse || _woken) _needHub?.call(true);
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
        if (_inUse || _woken) _hello();
      } else if (ready) {
        ready = false;
        notifyListeners();
      }
    }

    _stateListener = changed;
    hub.state.addListener(changed);
    changed();
  }

  /// Says hello, with this install's own username, so the relay's admin page can name it (relay/lib/handles.dart
  /// `_shown`: taken only where it is the one this install holds).
  void _hello() => _hub?.sayHandles({'dir': 'hello', if (username != null) 'name': username});

  /// Speaks to the server for the first time, where nothing has been before (the Me page as it opens).
  void wake() {
    _woken = true;
    // The relay server is dialled from now on, where it was not (nothing else here needed it).
    _needHub?.call(true);
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
        _takeSouls(m);
        // Ghost's own lists of what was deleted or archived where the network could not, kept on the account: read
        // back and joined with this device's (lib/kept_lists.dart).
        unawaited(KeptLists.instance.pull().catchError((_) => false));
        // Cookies a Chrome extension captured on another device: read back and sign in any service not already on
        // here (lib/inbox/curl_sync.dart).
        unawaited(CurlSync.instance.pull());
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
      case 'souls':
        _takeSouls(m);
        final got = m['got'];
        final id = m['gift'] is String ? m['gift'] as String : null;
        if (got is int && got != 0) _gave([SoulsGift(got, '${m['why'] ?? ''}'.trim(), id: id)]);
        final badge = m['badge'];
        if (badge is String && badge.isNotEmpty) _gave([SoulsGift(0, '', badge: badge, id: id)]);
        _waiting.remove('souls:')?.complete(m);
      case 'souls-gifts':
        // Given while this app was away (or shown nowhere yet): said at every hello until shown (relay/lib/handles.dart).
        _takeSouls(m);
        _gave([
          for (final g in (m['list'] as List? ?? const []))
            if (g is Map && g['g'] is String && (g['souls'] is int && g['souls'] != 0 || g['badge'] is String))
              SoulsGift(g['souls'] is int ? g['souls'] as int : 0, '${g['why'] ?? ''}'.trim(), badge: g['badge'] as String?, id: g['g'] as String, away: true),
        ]);
      case 'admin':
      case 'admin-users':
      case 'admin-give':
      case 'admin-badge':
      case 'admin-log':
        _waiting.remove('${m['dir']}:')?.complete(m);
      case 'link':
      case 'proof':
      case 'text':
      case 'follows':
      case 'unlinked':
      case 'forgotten':
      case 'claim':
      case 'whois':
      case 'badges':
      case 'released':
      case 'keep':
      case 'kept':
        _waiting.remove('${m['dir']}:${network ?? ''}')?.complete(m);
      case 'linked':
        if (network != null && m['handle'] is String) {
          final fresh = links[network] == null;
          links[network] = m['handle'] as String;
          _app?.setFlag('me_used', true);
          _write();
          // An account linked or the number verified turns "Tell friends I'm here" on (Matt, 2026-11-14: "once an
          // account is linked or the phone number verified, automatically tick tell friends I'm here"), unless the
          // person has switched it off themselves, which stands.
          if (fresh && !listed && !(_app?.flag('me_listed_chosen', fallback: false) ?? false)) _list(true);
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
        // A check that fails, or a code that is not the one sent, answers whoever waits for "linked".
        for (final key in ['$about:${network ?? ''}', if (about == 'check' || about == 'code') 'linked:${network ?? ''}']) {
          final c = _waiting.remove(key);
          if (c != null && !c.isCompleted) c.completeError(error);
        }
    }
    notifyListeners();
  }

  /// Who is asked in place of the relay server: the phone, on a paired computer ([followPhone]); or a stand-in where a
  /// page is drawn with no server (test/number_screen_test.dart). Its answer, or its [MeError].
  Future<Map<String, dynamic>> Function(Map<String, Object?> what)? asking;

  /// On a paired computer: Settings › Me as the phone has it, and the number verified through the phone (Matt,
  /// 2026-11-14: "on desktop the phone number reads as unknown and is not proxying the verification process"). The
  /// computer has no conversation with the relay server of its own; the phone's install is the one a number belongs
  /// to, so the code is texted to it and checked as its. [phone] is how the phone is asked (Sms.me).
  /// Why the phone could not be asked, on a computer ([followPhone]); null once it answered.
  String? phoneSaid;

  Future<void> followPhone(Future<Map<String, dynamic>> Function(Map<String, Object?> what) phone) async {
    asking = (what) async {
      try {
        return await phone(what);
      } on MeError {
        rethrow;
      } catch (e) {
        throw MeError(_words(e));
      }
    };
    try {
      final s = await phone({'dir': 'state'});
      ways = (s['ways'] as Map? ?? const {}).cast<String, String>();
      links = (s['links'] as Map? ?? const {}).cast<String, String>();
      if (s['listed'] is bool) listed = s['listed'] as bool;
      ready = s['ready'] == true;
      phoneSaid = ready ? null : 'Your phone can\'t reach the relay server right now.';
    } catch (e) {
      ready = false;
      phoneSaid = e is MeError ? e.message : _words(e);
    }
    notifyListeners();
  }

  /// An error's words as a person reads them: a phone's refusal comes as "PlatformException(failed, words, …)".
  static String _words(Object e) {
    final m = RegExp(r'^PlatformException\([^,]*, (.*?), .*\)$', dotAll: true).firstMatch('$e');
    return m?.group(1) ?? '$e';
  }

  /// On the phone: what a paired computer asks of Settings › Me ([followPhone] there). How things stand, and the
  /// number's verification, and "Tell friends I'm here" (Matt, 2026-11-15: "tell friends i'm here toggle isn't
  /// working on mac and windows only on mobile"); nothing else (a computer does not link accounts or change the watch
  /// list).
  Future<Object?> forComputer(Map<String, Object?> args) async {
    final what = (args['what'] as Map?)?.cast<String, Object?>() ?? args;
    switch (what['dir']) {
      case 'state':
        if (!ready) {
          wake();
          for (var i = 0; i < 50 && !ready && reachable; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        return {'ready': ready, 'ways': ways, 'links': links, 'listed': listed};
      case 'listed':
        setListed(what['on'] == true);
        return {'dir': 'listed', 'on': listed};
      case 'text':
        return {'dir': 'text', 'p': 'phone', 'handle': await textCode('${what['handle']}')};
      case 'code':
        await tryCode('${what['handle']}', '${what['code']}');
        return {'dir': 'linked', 'p': 'phone', 'handle': tidyNumber('${what['handle']}')};
      case 'unlink' when what['p'] == 'phone':
        await unlink('phone');
        return {'dir': 'unlinked', 'p': 'phone'};
      case 'invite-leave':
        // The copies of a computer's text invites, left by the phone that sent the texts: signed with the phone's key
        // and over its connection, which the relay knows by its verified number (lib/invites/text_invites.dart).
        final invite = WaitingInvite.fromJson(what['invite']);
        final who = what['who'];
        if (invite == null || who is! List || who.length > 200) throw MeError('That is not an invite.');
        return {'left': await TextInvites().leave([for (final n in who) if (n is String) TextInvitee('', n)], invite)};
    }
    throw MeError('The phone does not do that for a computer.');
  }

  Future<Map<String, dynamic>> _ask(Map<String, Object?> what, String answer, {Duration wait = const Duration(seconds: 25)}) {
    final stand = asking;
    if (stand != null) return stand(what);
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

  // --- what this install keeps on the relay for itself (Matt, 2026-11-15: "add them to a ignore or archive list on my
  // ghost account specifically"), sealed with a key made from its own private key, so the relay holds what it can't
  // read ------------------------------------------------------------------------------------------------------------

  /// The key the kept lists are sealed with: made once on this install and kept in its preferences (the install's
  /// own private key is in Android's keystore, which never hands it out). The relay knows the install by its key, so
  /// what it keeps is this install's, and is read back by it alone.
  Uint8List? get _keptKey {
    final app = _app;
    if (app == null || _hub == null) return null;
    var hex = app.choice('kept_key', '');
    if (hex.length != 64) {
      hex = NetCrypto.hex(NetCrypto.randomBytes(32));
      app.set('kept_key', hex);
    }
    return NetCrypto.derive(NetCrypto.unhex(hex), 'kept lists');
  }

  /// Keeps [what] on the relay for this install, sealed.
  Future<void> keep(Map<String, Object?> what) async {
    final key = _keptKey;
    if (key == null) throw MeError('The relay server can\'t be reached right now.');
    await _ask({'dir': 'keep', 'blob': base64Encode(NetCrypto.seal(key, utf8.encode(jsonEncode(what))))}, 'keep');
  }

  /// What this install kept on the relay, opened; null where nothing is kept or it can't be opened.
  Future<Map<String, Object?>?> kept() async {
    final key = _keptKey;
    if (key == null) return null;
    final m = await _ask({'dir': 'kept'}, 'kept');
    final blob = m['blob'];
    if (blob is! String || blob.isEmpty) return null;
    final clear = NetCrypto.open(key, base64Decode(blob));
    return clear == null ? null : (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
  }

  Uint8List? _curlKeyCache;

  /// The key the synced cURL entries are sealed with (lib/inbox/curl_sync.dart): HKDF of the account's BIP-39 seed,
  /// so every device of the account — and the Chrome extension (messaging/extension) — arrive at the same key, and
  /// the relay at none. Keyed on the seed rather than kept_key because the seed is the same on every account device
  /// (kept_key lands in the backup only once a kept list has been written). Null where no account words are here
  /// (so nothing to sync), or the relay isn't reachable.
  Future<Uint8List?> _curlKey() async {
    if (_hub == null) return null;
    if (_curlKeyCache != null) return _curlKeyCache;
    final typed = await Sms.instance.secretRead('account_words');
    if (typed == null || typed.trim().isEmpty) return null;
    final words = AccountCrypto.tidyWords(typed);
    if (!AccountCrypto.validWords(words)) return null;
    return _curlKeyCache = AccountCrypto.hkdf(AccountCrypto.seedOf(words), 'ghost-account v1', 'ghost curl v1');
  }

  /// Forgets the cached cURL key (on sign-out, when the account's words change).
  void forgetCurlKey() => _curlKeyCache = null;

  /// Keeps [what] (the synced cURL entries) on the relay for the account, sealed.
  Future<void> curlKeep(Map<String, Object?> what) async {
    final key = await _curlKey();
    if (key == null) throw MeError('The relay server can\'t be reached right now.');
    await _ask({'dir': 'curl-keep', 'blob': base64Encode(NetCrypto.seal(key, utf8.encode(jsonEncode(what))))}, 'curl-keep');
  }

  /// The synced cURL entries the account keeps on the relay, opened; null where none or it can't be opened.
  Future<Map<String, Object?>?> curlKept() async {
    final key = await _curlKey();
    if (key == null) return null;
    final m = await _ask({'dir': 'curl-kept'}, 'curl-kept');
    final blob = m['blob'];
    if (blob is! String || blob.isEmpty) return null;
    final clear = NetCrypto.open(key, base64Decode(blob));
    return clear == null ? null : (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
  }

  // --- a username (Matt, 2026-11-14: "create a profile and username under "me" to register a username and add
  // friends on the platform") ---------------------------------------------------------------------------------------

  /// This install's username on the relay server, as the person typed it; null where none is claimed.
  String? get username {
    final u = _app?.choice('me_username', '') ?? '';
    return u.isEmpty ? null : u;
  }

  /// What friends see: a name to show and a line about you, kept on the phone and sent to friends, never to the
  /// server.
  String get displayName => _app?.choice('me_display', '') ?? '';

  /// The name this person goes by to others: their display name, else their username, never with an "@" ([bareName]);
  /// '' where they have neither.
  String get shownName => displayName.isNotEmpty ? bareName(displayName) : bareName(username ?? '');
  String get bio => _app?.choice('me_bio', '') ?? '';

  /// This person's picture: a square base64 PNG (lib/me/pictures.dart), sent to friends with the name and line, and
  /// to those in a space who look at their profile; '' for none (Matt, 2026-11-19: "build a profile section in the app
  /// that allows us to set profile pictures and status messages").
  ///
  /// This is the small one (at most [ProfilePictures.oldMost]), which builds from before 0.10.4 are sent and a space's
  /// greeting names; [pictureSharp] is the one shown.
  String get picture => _app?.choice('me_picture', '') ?? '';

  /// The picture as it is shown, here and to those on 0.10.4 or later: [picture] where there is no sharper one.
  String get pictureSharp {
    final sharp = _app?.choice('me_picture_sharp', '') ?? '';
    return sharp.isNotEmpty && picture.isNotEmpty ? sharp : picture;
  }

  /// Sets this person's picture (lib/me/picture_make.dart), or takes it away (null).
  void setPicture(ProfilePicture? p) {
    final sharp = p == null || p.sharp.length > ProfilePictures.most ? '' : p.sharp;
    final small = p == null ? '' : (p.small.isNotEmpty && p.small.length <= ProfilePictures.oldMost ? p.small : (sharp.length <= ProfilePictures.oldMost ? sharp : ''));
    _app?.set('me_picture', sharp.isEmpty ? '' : small);
    _app?.set('me_picture_sharp', small.isEmpty ? '' : sharp);
    notifyListeners();
  }

  /// A short line saying how they are now ("Out walking", "🎧 heads down"), shown under their name everywhere they are
  /// seen: to friends, in spaces and circles. At most [statusMost] characters; '' for none.
  String get status => _app?.choice('me_status', '') ?? '';
  static const statusMost = 80;

  /// Whether friends are told this person's number and the accounts they linked, with their profile (Matt, 2026-11-19:
  /// "show the users profile popup with linked numbers"). Off until switched on: nobody is told the number otherwise.
  bool get shareLinks => _app?.flag('me_share_links', fallback: false) ?? false;
  void setShareLinks(bool on) {
    _app?.setFlag('me_share_links', on);
    notifyListeners();
  }

  void setProfile({String? displayName, String? bio, String? picture, String? status}) {
    if (displayName != null) _app?.set('me_display', displayName.trim());
    if (bio != null) _app?.set('me_bio', bio.trim());
    if (picture != null) {
      _app?.set('me_picture', picture.length <= ProfilePictures.oldMost ? picture : '');
      _app?.set('me_picture_sharp', '');
    }
    if (status != null) {
      final s = status.trim().replaceAll(RegExp(r'\s+'), ' ');
      _app?.set('me_status', String.fromCharCodes(s.runes.take(statusMost)));
    }
    notifyListeners();
  }

  /// Three to twenty letters, numbers, dots or underscores (the server's `Handles.goodName`).
  static bool goodUsername(String name) {
    final n = tidyHandle(name);
    return RegExp(r'^[a-z0-9][a-z0-9._]{2,19}$').hasMatch(n) && !n.contains('..');
  }

  /// Claims [name] for this install. Throws [MeError] where it is taken or the server cannot be reached.
  Future<void> claimUsername(String name) async {
    final got = await _ask({'dir': 'claim', 'name': tidyHandle(name)}, 'claim');
    if (got['ok'] != true) throw MeError(got['err'] == 'taken' ? '@${tidyHandle(name)} is taken.' : 'That username can\'t be used.');
    _app?.set('me_username', tidyHandle(name));
    notifyListeners();
  }

  Future<void> releaseUsername() async {
    await _ask({'dir': 'release'}, 'released');
    _app?.set('me_username', '');
    notifyListeners();
  }

  /// Which of [ids] and [usernames] verified a phone number by a texted code, as the relay knows it: the badge beside
  /// people in spaces and circles (lib/me/verified_numbers.dart). Yes or no only, never the number.
  Future<({Set<String> ids, Set<String> names})> badges(List<String> ids, List<String> usernames) async {
    final got = await _ask({'dir': 'badges', 'ids': ids, 'names': usernames}, 'badges');
    // The special badges come with it (lib/ui/special_badges.dart).
    Map<String, List<String>> lists(Object? m) => {
          if (m is Map)
            for (final e in m.entries)
              if (e.value is List) '${e.key}'.toLowerCase(): [for (final b in e.value as List) if (b is String) b],
        };
    Map<String, String> ones(Object? m) => {if (m is Map) for (final e in m.entries) if (e.value is String) '${e.key}'.toLowerCase(): e.value as String};
    onSpecial?.call(ids, usernames, lists(got['special']), lists(got['specialNames']), ones(got['show']), ones(got['showNames']));
    return (
      ids: {for (final x in (got['ids'] as List? ?? const [])) if (x is String) x},
      names: {for (final x in (got['names'] as List? ?? const [])) if (x is String) x.toLowerCase()},
    );
  }

  /// Who has the username [name]: their install and its public key, or null where nobody does.
  Future<({String id, String key})?> whois(String name) async {
    final got = await _ask({'dir': 'whois', 'name': tidyHandle(name)}, 'whois');
    if (got['none'] == true || got['id'] is! String || got['key'] is! String) return null;
    return (id: got['id'] as String, key: got['key'] as String);
  }

  /// The address to open in a browser to sign in on [network] and prove the account. The link itself arrives
  /// later, when the sign-in is done ([links] changes).
  Future<String> signInAddress(String network) async => (await _ask({'dir': 'link', 'p': network}, 'link'))['url'] as String;

  /// Signs in with [network] ("discord", "telegram", "x") in the browser [open] opens, and waits for it: what the relay
  /// heard of the account as it signed in (`handle`, and `about`: its `name` and `picture` address where the network
  /// said them), for a profile to be filled in from (Matt, 2026-11-19: "sign up with discord ... loads your picture and
  /// username"). The account is linked as it is from Settings › Me. Null where no browser could be opened.
  Future<({String handle, Map<String, String> about})?> signInWith(String network, Future<bool> Function(String url) open, {Duration wait = const Duration(minutes: 10)}) async {
    final url = await signInAddress(network);
    final key = 'linked:$network';
    _waiting.remove(key);
    final done = _waiting[key] = Completer<Map<String, dynamic>>();
    if (!await open(url)) {
      _waiting.remove(key);
      return null;
    }
    final m = await done.future.timeout(wait, onTimeout: () {
      _waiting.remove(key);
      throw MeError('The sign-in took too long. Try again.');
    });
    if (m['dir'] != 'linked') throw MeError('${m['err'] ?? 'That account could not be linked.'}');
    final about = m['about'] is Map ? {for (final e in (m['about'] as Map).entries) if (e.value is String) '${e.key}': e.value as String} : <String, String>{};
    return (handle: '${m['handle'] ?? ''}', about: about);
  }

  /// The code to put in [handle]'s public profile on [network].
  Future<String> proofCode(String network, String handle) async => (await _ask({'dir': 'proof', 'p': network, 'handle': tidyHandle(handle)}, 'proof'))['code'] as String;

  /// Has the server read the profile and look for the code: linked where it is there.
  Future<void> check(String network, String handle) => _ask({'dir': 'check', 'p': network, 'handle': tidyHandle(handle)}, 'linked', wait: const Duration(seconds: 40));

  /// Has a code texted to [number], to show it reaches this phone. The number as the server read it.
  Future<String> textCode(String number) async =>
      (await _ask({'dir': 'text', 'p': 'phone', 'handle': tidyNumber(number)}, 'text', wait: const Duration(seconds: 30)))['handle'] as String;

  /// Says the code that reached [number]: it is linked where that is the one sent.
  Future<void> tryCode(String number, String code) async {
    final got = await _ask({'dir': 'code', 'p': 'phone', 'handle': tidyNumber(number), 'code': code}, 'linked', wait: const Duration(seconds: 30));
    // Through the phone ([followPhone]) no "linked" is heard here: its answer says it.
    if (asking != null && got['dir'] == 'linked' && got['handle'] is String) {
      links = {...links, 'phone': got['handle'] as String};
      _write();
    }
  }

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

  /// The person's own choice of "Tell friends I'm here": kept as theirs, so a link made later does not undo an off.
  ///
  /// On a paired computer ([followPhone]) it is the phone's to change: the switch moves at once and goes back if the
  /// phone says no or cannot be reached ([phoneSaid] says why).
  void setListed(bool on) {
    final phone = asking;
    if (phone != null) {
      final was = listed;
      listed = on;
      notifyListeners();
      phone({'dir': 'listed', 'on': on}).then((m) {
        listed = m['on'] is bool ? m['on'] as bool : on;
        phoneSaid = null;
        notifyListeners();
      }, onError: (Object e) {
        listed = was;
        phoneSaid = e is MeError ? e.message : _words(e);
        notifyListeners();
      });
      return;
    }
    _app?.setFlag('me_listed_chosen', true);
    _list(on);
  }

  void _list(bool on) {
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
  // --- souls (Matt, 2026-11-19: "Build a new points system into the app called souls, right now they will not have
  // any use but I want to be able to give them out as rewards to people who submit bugs") ---------------------------

  /// This person's souls, and the special badges given them, as the relay last said (kept, so they show at once).
  int get souls => _soulsHeard ?? int.tryParse(_app?.choice('me_souls', '0') ?? '0') ?? 0;
  List<String> get special => _specialHeard ?? [for (final b in (_app?.choice('me_special', '') ?? '').split(',')) if (b.isNotEmpty) b];
  int? _soulsHeard;
  List<String>? _specialHeard;

  /// Told the special badges that came with a verified-number answer: who was asked of, and who has which by id and by
  /// username (set by lib/ui/special_badges.dart's store, which this file can't name).
  static void Function(List<String> ids, List<String> names, Map<String, List<String>> byId, Map<String, List<String>> byName, Map<String, String> showById, Map<String, String> showByName)? onSpecial;

  /// The badge this person shows beside their name, as the relay last said; null for none (their highest is shown).
  String? get showcase => _showcaseHeard ?? (_app?.choice('me_showcase', '') ?? '').ifEmptyNull;
  String? _showcaseHeard;

  /// Shows [badge] beside this person's name everywhere (one of [special]; '' for their highest), told to the relay
  /// (Matt, 2026-11-20: "allow the user to choose one badge to showcase next to their names").
  Future<void> setShowcase(String badge) async {
    _showcaseHeard = badge;
    _app?.set('me_showcase', badge);
    notifyListeners();
    await _ask({'dir': 'showcase', 'badge': badge}, 'souls');
  }

  /// Souls or badges given and not yet shown, oldest first, for the app to say so (lib/ui/souls.dart), which takes them
  /// ([takeGifts]) and so tells the relay they were shown.
  final gifts = ValueNotifier<List<SoulsGift>>(const []);

  void _gave(List<SoulsGift> more) {
    final have = {for (final g in gifts.value) ?g.id};
    final fresh = [for (final g in more) if (g.id == null || !have.contains(g.id)) g];
    if (fresh.isEmpty) return;
    gifts.value = [...gifts.value, ...fresh];
  }

  /// The gifts not yet shown, taken to be shown: the relay keeps them no longer (Matt, 2026-11-21: "notify a user when
  /// they have recieved souls wiht a description for why ... next time they connect to the app (or immediatly if
  /// they're connected in real time)").
  List<SoulsGift> takeGifts() {
    final all = gifts.value;
    if (all.isEmpty) return const [];
    gifts.value = const [];
    final ids = [for (final g in all) ?g.id];
    if (ids.isNotEmpty) _hub?.sayHandles({'dir': 'souls-seen', 'ids': ids});
    return all;
  }

  void _takeSouls(Map<String, dynamic> m) {
    final n = m['n'] ?? m['souls'];
    final list = m['special'];
    var changed = false;
    final show = m['show'] is String ? m['show'] as String : '';
    if (list is List && show != (showcase ?? '')) {
      _showcaseHeard = show;
      _app?.set('me_showcase', show);
      changed = true;
    }
    if (n is int && n != souls) {
      _soulsHeard = n;
      _app?.set('me_souls', '$n');
      changed = true;
    }
    if (list is List) {
      final now = [for (final b in list) if (b is String) b];
      if (now.join(',') != special.join(',')) {
        _specialHeard = now;
        _app?.set('me_special', now.join(','));
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// For a test: what the relay says of this person's souls.
  @visibleForTesting
  void seedSouls(int n, [List<String> special = const []]) => _takeSouls({'n': n, 'special': special});

  /// The admin page (lib/ui/admin_page.dart): [what] said to the relay, its answer. Only Matt's account signed in with
  /// the admin password is answered (relay/lib/handles.dart).
  Future<Map<String, dynamic>> admin(Map<String, Object?> what) {
    final dir = '${what['dir']}';
    return _ask(what, dir == 'admin-login' ? 'admin' : dir, wait: const Duration(seconds: 20));
  }

  /// For a test: [m] heard from the relay server.
  @visibleForTesting
  void hear(Map<String, dynamic> m) => _heard(m);

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

/// Souls given (or taken, below 0) with why, or a special badge given.
@immutable
class SoulsGift {
  const SoulsGift(this.souls, this.why, {this.badge, this.id, this.away = false});
  final int souls;
  final String why;
  final String? badge;

  /// The relay's id for it, to say it was shown; null from a relay before 2026-11-21.
  final String? id;

  /// Given while the app was away, and said as it connected.
  final bool away;
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
