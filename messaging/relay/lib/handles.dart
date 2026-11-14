import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'sha256.dart';
import 'texts.dart';

/// The handles people linked: where someone who has the app says "this Discord, Telegram, X, Bluesky, Mastodon or
/// GitHub account is mine", and where someone else who asked to be told hears that they joined (Matt, 2026-11-14:
/// "Add a 'me' section to settings and allow linking popular social like telegram, discord, x, etc to be notified
/// when one of your friends or followers joins ghost messaging"; docs/me.md in the app).
///
/// It is the first thing on this server that is about who someone is, so it is opt-in at every step, and it keeps
/// as little as it can:
///
/// - **Who.** The hub's own name for an install (hub.dart: made from a key, proved by a signature as it connects).
///   Everything here is said over that connection, so only the install itself links, lists and watches for itself.
/// - **A link** is proved, never typed and trusted. Discord and X by signing in there (OAuth: this server asks them
///   who signed in); Telegram by its login widget (signed with our bot's token); Bluesky, Mastodon and GitHub by a
///   code this server makes up, put in the account's public profile and read back from the network's own public
///   API. Those three have no secrets to set up, and their follow lists are public, so they can be imported.
/// - **A phone number** is a link too ("phone"), proved by a code texted to it by a service that makes and checks
///   the code itself (texts.dart; Matt, 2026-11-14: "send the text code to a number to verify so it can't be
///   spoofed"). It is the one link whose hash can be worked back, there being only so many numbers: this server
///   is to be thought of as knowing a linked number. So a number is told to nobody, listed or not ([_quiet]).
/// - **What is kept** (`handles.json`): for each install, per network, the SHA-256 of the handle and of the account's
///   number there, and the day. Never the handle itself, a name, a token, or anything else the network said. A watch
///   list is kept as the same hashes. So this file says "this install has some Discord account" and nothing about
///   which, to anyone who does not already know the handle to hash.
/// - **Listed** is a switch, off until the person turns it on. Only a listed install's links are told to anyone.
/// - **Joined.** When a listed link is made (or a linked install turns listing on), every install watching for that
///   handle's hash is told the hash. It knows which handle that is; this server never says. Someone not connected is
///   told when they next are (at most [maxPending] kept).
///
/// What it can see beyond the hub: that an install has an account on a network, and how many handles another is
/// watching for. What it cannot do: tell anyone a person's number, key or name. None of those are here.
class Handles {
  Handles({this.dataDir, this.config = const HandlesConfig(), Fetch? fetch, DateTime Function()? now, Random? random, TextCodes? texts, this.verbose = false})
      : _fetch = fetch ?? defaultFetch,
        _now = now ?? DateTime.now,
        _random = random ?? Random.secure(),
        _texts = texts ?? (config.texts ? TwilioVerify(fetch ?? defaultFetch, sid: config.twilioSid, token: config.twilioToken, service: config.twilioVerify) : null);

  /// Where `handles.json` is kept; null keeps nothing across restarts.
  final Directory? dataDir;
  final HandlesConfig config;
  final bool verbose;
  final Fetch _fetch;
  final DateTime Function() _now;
  final Random _random;

  /// Who texts a number its code; null where that is not set up, and a number cannot be linked.
  final TextCodes? _texts;

  static const networks = ['discord', 'telegram', 'x', 'bluesky', 'mastodon', 'github', 'phone'];
  static const _signIn = {'discord', 'telegram', 'x'};
  static const _proof = {'bluesky', 'mastodon', 'github'};

  /// Linked, and told to nobody: see the class's words on a phone number.
  static const _quiet = {'phone'};
  static const maxWatch = 5000;
  static const maxPending = 300;
  static const maxFollows = 5000;
  static const stateLife = Duration(minutes: 10);

  /// How many proofs, checks and imports one install may ask for in an hour: each makes this server fetch from
  /// someone else's.
  static const fetchesAnHour = 40;

  /// Texts cost money, and reach a phone whose owner may not have asked: how many codes one install may ask for,
  /// and one number be sent whoever asks, in an hour and in a day. (All installs together: [HandlesConfig.textsADay].)
  static const textsAnHour = 3;
  static const textsADay = 6;

  /// How many codes one install may try in an hour, and how long one is good for at the service.
  static const triesAnHour = 10;
  static const codeLife = Duration(minutes: 10);

  /// install -> network -> {k: the handle's hash, a: the account's hash, at: the day}
  final Map<String, Map<String, Map<String, String>>> _links = {};
  final Set<String> _listed = {};
  final Map<String, Set<String>> _watch = {};
  final Map<String, List<String>> _pending = {};

  /// What a sign-in that finished while its install was away has to tell it: install -> [{p, handle, k}].
  final Map<String, List<Map<String, String>>> _done = {};
  String _secret = '';

  // Made from the above as it is read and changed.
  final Map<String, Set<String>> _watchers = {};
  final Map<String, String> _account = {};
  final Map<String, void Function(Map<String, Object?>)> _here = {};
  final Map<String, _Asked> _asked = {};
  final Map<String, List<DateTime>> _fetched = {};

  // Codes by text, none of it kept: when each install asked, when each number (by its hash) was texted, when
  // anyone was, which installs a number's code was sent for, and when each tried one.
  final Map<String, List<DateTime>> _textedBy = {};
  final Map<String, List<DateTime>> _textedTo = {};
  final List<DateTime> _textedAll = [];
  final Map<String, Map<String, DateTime>> _codeFor = {};
  final Map<String, List<DateTime>> _tried = {};
  Timer? _saver;

  int get linked => _links.values.fold(0, (n, m) => n + m.length);
  int get listed => _listed.length;
  int get watched => _watch.values.fold(0, (n, s) => n + s.length);

  /// The hash a handle is kept and watched by: the same in the app (lib/me/me.dart).
  static String keyOf(String network, String handle) => hexOf(sha256(utf8.encode('ghost-handle v1|$network|${tidy(network, handle)}')));

  /// A handle as it is compared: no "@" in front, no spaces, lower case. A phone number: [tidyNumber].
  static String tidy(String network, String handle) {
    if (network == 'phone') return tidyNumber(handle);
    var h = handle.trim().toLowerCase();
    while (h.startsWith('@')) {
      h = h.substring(1);
    }
    return h;
  }

  /// A phone number as it is compared and texted: "+", the country's code, the digits (E.164). Ten digits, or
  /// eleven that start with 1, are read as a North American number, as people there write theirs. Empty where what
  /// was typed holds anything a number does not.
  static String tidyNumber(String typed) {
    final t = typed.trim();
    if (!RegExp(r'^\+?[0-9 ().\-]+$').hasMatch(t)) return '';
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    if (t.startsWith('+')) return '+$digits';
    if (digits.length == 10) return '+1$digits';
    if (digits.length == 11 && digits.startsWith('1')) return '+$digits';
    return digits;
  }

  static final _number = RegExp(r'^\+[1-9][0-9]{7,14}$');
  static final _northAmerican = RegExp(r'^\+1[2-9][0-9]{9}$');
  static final _plain = RegExp(r'^[a-z0-9._-]{1,64}$');
  static final _host = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,24}$');

  /// Whether [handle] (tidied) could be one on [network]: what is fetched is built from it.
  static bool wellFormed(String network, String handle) {
    switch (network) {
      case 'phone':
        return _number.hasMatch(handle) && (!handle.startsWith('+1') || _northAmerican.hasMatch(handle));
      case 'mastodon':
        final at = handle.indexOf('@');
        return at > 0 && _plain.hasMatch(handle.substring(0, at)) && _host.hasMatch(handle.substring(at + 1)) && handle.length <= 120;
      case 'bluesky':
        return _host.hasMatch(handle) && handle.length <= 120;
      default:
        return _plain.hasMatch(handle);
    }
  }

  void _say(String what) {
    // Never a handle, never a whole name.
    if (verbose) stdout.writeln('${_now().toIso8601String()} handles $what');
  }

  // --- what is kept ---------------------------------------------------------------------------------------------------

  File? get _file => dataDir == null ? null : File('${dataDir!.path}/handles.json');

  void load() {
    final file = _file;
    try {
      if (file != null && file.existsSync()) {
        final all = jsonDecode(file.readAsStringSync()) as Map;
        _secret = (all['secret'] as String?) ?? '';
        (all['links'] as Map? ?? const {}).forEach((id, nets) {
          _links[id as String] = {for (final e in (nets as Map).entries) e.key as String: (e.value as Map).cast<String, String>()};
        });
        _listed.addAll((all['listed'] as List? ?? const []).cast<String>());
        (all['watch'] as Map? ?? const {}).forEach((id, keys) => _watch[id as String] = (keys as List).cast<String>().toSet());
        (all['pending'] as Map? ?? const {}).forEach((id, keys) => _pending[id as String] = (keys as List).cast<String>().toList());
      }
    } catch (_) {
      // A file that cannot be read is started again from nothing rather than stopping the relay.
    }
    if (_secret.length != 64) _secret = hexOf([for (var i = 0; i < 32; i++) _random.nextInt(256)]);
    for (final e in _links.entries) {
      for (final link in e.value.values) {
        final a = link['a'];
        if (a != null) _account[a] = e.key;
      }
    }
    for (final e in _watch.entries) {
      for (final k in e.value) {
        (_watchers[k] ??= {}).add(e.key);
      }
    }
  }

  void save() {
    _saver?.cancel();
    _saver = null;
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode({
        'secret': _secret,
        'links': _links,
        'listed': _listed.toList(),
        'watch': {for (final e in _watch.entries) e.key: e.value.toList()},
        'pending': _pending,
      }));
      tmp.renameSync(file.path);
    } catch (_) {}
  }

  void _changed() => _saver ??= Timer(const Duration(seconds: 2), save);

  /// Forgets sign-ins that were started and never finished, and codes by text that have run out.
  void sweep() {
    final now = _now();
    final cutoff = now.subtract(stateLife);
    _asked.removeWhere((_, a) => a.at.isBefore(cutoff));
    for (final lists in [_textedBy, _textedTo, _tried]) {
      lists.removeWhere((_, list) => !list.any((t) => now.difference(t) <= const Duration(days: 1)));
    }
    _codeFor.removeWhere((_, who) {
      who.removeWhere((_, at) => now.difference(at) > codeLife);
      return who.isEmpty;
    });
  }

  // --- an install comes, speaks, and goes ---------------------------------------------------------------------------

  void came(String id, void Function(Map<String, Object?>) tell) => _here[id] = tell;

  void went(String id, void Function(Map<String, Object?>) tell) {
    if (identical(_here[id], tell)) _here.remove(id);
  }

  /// How each network is linked here: "signin" or "proof", "text" for a phone number, or "off" where what it
  /// needs has not been set up.
  Map<String, String> get ways => {
        for (final n in networks)
          n: n == 'phone'
              ? (_texts != null ? 'text' : 'off')
              : _proof.contains(n)
                  ? 'proof'
                  : switch (n) {
                      'discord' => config.discordId.isNotEmpty && config.discordSecret.isNotEmpty,
                      'x' => config.xId.isNotEmpty,
                      _ => config.telegramBot.isNotEmpty && config.telegramToken.isNotEmpty,
                    }
                      ? 'signin'
                      : 'off',
      };

  /// Whether [list] has room for one more: fewer than [anHour] in the last hour, and than [aDay] in the last day.
  static bool _room(List<DateTime>? list, DateTime now, int anHour, int aDay) {
    if (list == null) return true;
    list.removeWhere((t) => now.difference(t) > const Duration(days: 1));
    return list.length < aDay && list.where((t) => now.difference(t) <= const Duration(hours: 1)).length < anHour;
  }

  bool _mayFetch(String id) {
    final now = _now();
    final list = _fetched[id] ??= [];
    list.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    if (list.length >= fetchesAnHour) return false;
    list.add(now);
    return true;
  }

  /// Something an install said that starts `{"dir": …}`. [id] is who the hub knows it to be.
  Future<void> said(String id, Map said) async {
    final tell = _here[id];
    if (tell == null) return;
    final network = said['p'];
    void err(String why) => tell({'dir': 'err', 'about': said['dir'], 'p': network, 'err': why});
    final known = network is String && networks.contains(network);
    try {
      switch (said['dir']) {
        case 'hello':
          tell({
            'dir': 'hello',
            'ways': ways,
            'listed': _listed.contains(id),
            'links': [for (final e in (_links[id] ?? const {}).entries) {'p': e.key, 'k': e.value['k'], 'at': e.value['at']}],
            'watching': _watch[id]?.length ?? 0,
          });
          for (final done in _done.remove(id) ?? const <Map<String, String>>[]) {
            tell({'dir': 'linked', ...done});
          }
          final waiting = _pending.remove(id);
          if (waiting != null && waiting.isNotEmpty) {
            tell({'dir': 'joined', 'list': waiting});
            _changed();
          }
        case 'link':
          if (!known || !_signIn.contains(network)) return err('That network is not linked by signing in.');
          if (ways[network] != 'signin') return err('Signing in with that network is not set up on this server yet.');
          final state = hexOf([for (var i = 0; i < 16; i++) _random.nextInt(256)]);
          final verifier = base64Url.encode([for (var i = 0; i < 48; i++) _random.nextInt(256)]).replaceAll('=', '');
          _asked[state] = _Asked(id, network, verifier, _now());
          tell({'dir': 'link', 'p': network, 'url': '${config.publicUrl}/link/$network?s=$state'});
        case 'text':
          // A code, texted to a number by the service (texts.dart). Nothing is linked yet.
          if (network != 'phone') return err('Only a phone number is linked by a text.');
          final texts = _texts;
          if (texts == null) return err('Verifying a number by text is not set up on this server yet.');
          final number = said['handle'] is String ? tidyNumber(said['handle'] as String) : '';
          if (!wellFormed('phone', number)) return err('That does not look like a phone number. Write it with its country code, like +1 555 010 0199.');
          if (!config.textTo.any(number.startsWith)) return err('Numbers in that country cannot be verified yet.');
          final k = keyOf('phone', number);
          final now = _now();
          sweep();
          if (!_room(_textedBy[id], now, textsAnHour, textsADay)) return err('You have asked for a few codes already. Try again in an hour.');
          if (!_room(_textedTo[k], now, textsAnHour, textsADay)) return err('That number has been sent a few codes already. Try again in an hour.');
          if (!_room(_textedAll, now, config.textsADay, config.textsADay)) return err('No more codes can be sent today. Try again tomorrow.');
          // Counted before it is sent: one that fails is still one asked of the service.
          (_textedBy[id] ??= []).add(now);
          (_textedTo[k] ??= []).add(now);
          _textedAll.add(now);
          switch (await texts.send(number)) {
            case Texted.sent:
              (_codeFor[k] ??= {})[id] = now;
              _say('${id.substring(0, 6)} was texted a code');
              tell({'dir': 'text', 'p': 'phone', 'handle': number});
            case Texted.cannot:
              err('That number cannot be sent a text. Check it is a mobile number, with its country code.');
            case Texted.tooOften:
              err('That number has been sent a few codes already. Try again in ten minutes.');
            case Texted.down:
              _say('the text service did not send');
              err('The code could not be sent just now. Try again in a while.');
          }
        case 'code':
          // The code that reached the number, come back: the service says whether it is the one it sent.
          if (network != 'phone') return err('Only a phone number is linked by a text.');
          final texts = _texts;
          if (texts == null) return err('Verifying a number by text is not set up on this server yet.');
          final number = said['handle'] is String ? tidyNumber(said['handle'] as String) : '';
          final code = said['code'] is String ? (said['code'] as String).replaceAll(RegExp(r'[\s-]'), '') : '';
          if (!wellFormed('phone', number) || !RegExp(r'^[0-9]{4,10}$').hasMatch(code)) return err('That does not look like the code. It is the digits in the text.');
          final k = keyOf('phone', number);
          final now = _now();
          // Only an install the code was sent for may try it: nobody else's guesses are passed on.
          final asked = _codeFor[k]?[id];
          if (asked == null || now.difference(asked) > codeLife) return err('Ask for a code first. One lasts ten minutes.');
          if (!_room(_tried[id], now, triesAnHour, triesAnHour * 3)) return err('Too many tries. Ask for a new code in an hour.');
          (_tried[id] ??= []).add(now);
          final right = await texts.check(number, code);
          if (right == null) return err('The code could not be checked just now. Try again.');
          if (!right) return err('That is not the code. Look at the text again, or ask for a new one.');
          _codeFor[k]?.remove(id);
          if (_codeFor[k]?.isEmpty ?? false) _codeFor.remove(k);
          _link(id, 'phone', number, number);
        case 'proof':
        case 'check':
          final handle = said['handle'] is String ? tidy(network is String ? network : '', said['handle'] as String) : '';
          if (network == 'phone') return err('A phone number is linked by a code sent to it.');
          if (!known || _signIn.contains(network)) return err('That network is linked by signing in.');
          if (!wellFormed(network, handle)) return err('That does not look like a handle there.');
          final code = codeFor(id, network, handle);
          if (said['dir'] == 'proof') return tell({'dir': 'proof', 'p': network, 'handle': handle, 'code': code});
          if (!_mayFetch(id)) return err('Too many tries this hour. Try again later.');
          final found = await _profile(network, handle);
          if (found == null) return err('That account could not be read. Check the handle.');
          if (!found.text.contains(code)) return err('The code is not in that profile yet. It can take a minute to show.');
          _link(id, network, handle, found.account);
        case 'unlink':
          if (!known) return;
          final gone = _links[id]?.remove(network);
          if (gone != null) {
            if (_links[id]!.isEmpty) _links.remove(id);
            if (_account[gone['a']] == id) _account.remove(gone['a']);
            _changed();
          }
          tell({'dir': 'unlinked', 'p': network});
        case 'listed':
          final on = said['on'] == true;
          if (on && _listed.add(id)) {
            for (final link in (_links[id] ?? const <String, Map<String, String>>{}).entries) {
              if (!_quiet.contains(link.key)) _announce(id, link.value['k']!);
            }
          } else if (!on) {
            _listed.remove(id);
          }
          _changed();
          tell({'dir': 'listed', 'on': on});
        case 'watch':
          final mine = _watch[id] ??= {};
          for (final k in (said['remove'] as List? ?? const []).whereType<String>()) {
            if (mine.remove(k)) {
              _watchers[k]?.remove(id);
              if (_watchers[k]?.isEmpty ?? false) _watchers.remove(k);
            }
          }
          final here = <String>[];
          for (final k in (said['add'] as List? ?? const []).whereType<String>()) {
            if (k.length != 64 || mine.length >= maxWatch && !mine.contains(k)) continue;
            mine.add(k);
            (_watchers[k] ??= {}).add(id);
            if (_listedHolders(k).any((other) => other != id)) here.add(k);
          }
          if (mine.isEmpty) _watch.remove(id);
          _changed();
          tell({'dir': 'watching', 'n': mine.length});
          if (here.isNotEmpty) tell({'dir': 'joined', 'list': here, 'already': true});
        case 'forget':
          // Everything about this install, gone: its links, its listing, its watch list, what waited for it.
          for (final link in (_links.remove(id) ?? const <String, Map<String, String>>{}).values) {
            if (_account[link['a']] == id) _account.remove(link['a']);
          }
          _listed.remove(id);
          for (final k in _watch.remove(id) ?? const <String>{}) {
            _watchers[k]?.remove(id);
            if (_watchers[k]?.isEmpty ?? false) _watchers.remove(k);
          }
          _pending.remove(id);
          _done.remove(id);
          _changed();
          tell({'dir': 'forgotten'});
        case 'follows':
          final handle = said['handle'] is String ? tidy(network is String ? network : '', said['handle'] as String) : '';
          if (!_proof.contains(network)) return err('Who you follow there cannot be read.');
          // Only of the account this install proved is its own.
          if (_links[id]?[network]?['k'] != keyOf(network, handle)) return err('Link that account first.');
          if (!_mayFetch(id)) return err('Too many tries this hour. Try again later.');
          final found = await _following(network, handle);
          if (found == null) return err('Who that account follows could not be read.');
          tell({'dir': 'follows', 'p': network, 'handles': found});
      }
    } catch (e) {
      err('That did not work. Try again in a while.');
      _say('error in ${said['dir']}: ${e.runtimeType}');
    }
  }

  Iterable<String> _listedHolders(String k) sync* {
    for (final e in _links.entries) {
      if (_listed.contains(e.key) && e.value.entries.any((l) => l.value['k'] == k && !_quiet.contains(l.key))) yield e.key;
    }
  }

  /// The code [id] is to put in [handle]'s profile on [network]: made from a secret only this server has, so it need
  /// not be remembered, and nobody else's code is the same.
  String codeFor(String id, String network, String handle) =>
      'ghost-${hexOf(hmacSha256(utf8.encode(_secret), utf8.encode('$id|$network|$handle'))).substring(0, 10)}';

  /// [id] has proved [handle] on [network] is theirs. [account] is the network's own number for it, which stays
  /// the same when a handle is renamed and is what makes one account one install's: linked again from another
  /// install, the first one's link goes.
  void _link(String id, String network, String handle, String account) {
    final k = keyOf(network, handle);
    final a = hexOf(sha256(utf8.encode('ghost-account v1|$network|$account')));
    final before = _account[a];
    if (before != null && before != id) {
      _links[before]?.remove(network);
      if (_links[before]?.isEmpty ?? false) _links.remove(before);
    }
    final old = _links[id]?[network];
    if (old != null && old['a'] != a && _account[old['a']] == id) _account.remove(old['a']);
    (_links[id] ??= {})[network] = {'k': k, 'a': a, 'at': _now().toUtc().toIso8601String().substring(0, 10)};
    _account[a] = id;
    _changed();
    final told = {'p': network, 'handle': handle, 'k': k};
    final tell = _here[id];
    if (tell != null) {
      tell({'dir': 'linked', ...told});
    } else {
      (_done[id] ??= []).add(told);
    }
    _say('${id.substring(0, 6)} linked $network');
    if (_listed.contains(id) && old?['k'] != k && !_quiet.contains(network)) _announce(id, k);
  }

  /// Tells everyone watching for [k] that it is here now.
  void _announce(String id, String k) {
    for (final watcher in _watchers[k] ?? const <String>{}) {
      if (watcher == id) continue;
      final tell = _here[watcher];
      if (tell != null) {
        tell({'dir': 'joined', 'list': [k]});
      } else {
        final box = _pending[watcher] ??= [];
        if (!box.contains(k) && box.length < maxPending) box.add(k);
      }
    }
    _changed();
  }

  // --- reading a public profile: Bluesky, Mastodon, GitHub -------------------------------------------------------------

  Map<String, String> get _githubHeaders => {
        'User-Agent': 'ghost-messaging-relay',
        'Accept': 'application/vnd.github+json',
        if (config.githubToken.isNotEmpty) 'Authorization': 'Bearer ${config.githubToken}',
      };

  /// The words of [handle]'s public profile on [network], and the network's own number for the account.
  Future<({String text, String account})?> _profile(String network, String handle) async {
    switch (network) {
      case 'bluesky':
        final r = await _fetch('GET', Uri.https('public.api.bsky.app', '/xrpc/app.bsky.actor.getProfile', {'actor': handle}));
        if (r.status != 200) return null;
        final m = jsonDecode(r.body) as Map;
        return (text: '${m['description'] ?? ''} ${m['displayName'] ?? ''}', account: '${m['did']}');
      case 'mastodon':
        final at = handle.indexOf('@');
        final r = await _fetch('GET', Uri.https(handle.substring(at + 1), '/api/v1/accounts/lookup', {'acct': handle.substring(0, at)}), outside: true);
        if (r.status != 200) return null;
        final m = jsonDecode(r.body) as Map;
        final fields = [for (final f in (m['fields'] as List? ?? const [])) '${(f as Map)['name']} ${f['value']}'].join(' ');
        return (text: '${m['note'] ?? ''} $fields ${m['display_name'] ?? ''}', account: '${handle.substring(at + 1)}/${m['id']}');
      case 'github':
        final r = await _fetch('GET', Uri.https('api.github.com', '/users/$handle'), headers: _githubHeaders);
        if (r.status != 200) return null;
        final m = jsonDecode(r.body) as Map;
        return (text: '${m['bio'] ?? ''} ${m['blog'] ?? ''} ${m['company'] ?? ''}', account: '${m['id']}');
    }
    return null;
  }

  /// The handles [handle] follows on [network], at most [maxFollows].
  Future<List<String>?> _following(String network, String handle) async {
    final out = <String>[];
    switch (network) {
      case 'bluesky':
        String? cursor;
        for (var page = 0; page < 50 && out.length < maxFollows; page++) {
          final r = await _fetch('GET', Uri.https('public.api.bsky.app', '/xrpc/app.bsky.graph.getFollows', {'actor': handle, 'limit': '100', 'cursor': ?cursor}));
          if (r.status != 200) return page == 0 ? null : out;
          final m = jsonDecode(r.body) as Map;
          out.addAll([for (final f in (m['follows'] as List? ?? const [])) '${(f as Map)['handle']}']);
          cursor = m['cursor'] as String?;
          if (cursor == null) break;
        }
      case 'mastodon':
        final at = handle.indexOf('@');
        final host = handle.substring(at + 1);
        final who = await _fetch('GET', Uri.https(host, '/api/v1/accounts/lookup', {'acct': handle.substring(0, at)}), outside: true);
        if (who.status != 200) return null;
        final id = '${(jsonDecode(who.body) as Map)['id']}';
        if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) return null;
        String? maxId;
        for (var page = 0; page < 60 && out.length < maxFollows; page++) {
          final r = await _fetch('GET', Uri.https(host, '/api/v1/accounts/$id/following', {'limit': '80', 'max_id': ?maxId}), outside: true);
          if (r.status != 200) return page == 0 ? null : out;
          final list = jsonDecode(r.body) as List;
          if (list.isEmpty) break;
          out.addAll([for (final f in list) '${(f as Map)['acct']}'.contains('@') ? '${f['acct']}' : '${f['acct']}@$host']);
          // The next page is named in the Link header: <…max_id=123>; rel="next".
          maxId = RegExp(r'max_id=([A-Za-z0-9]+)[^>]*>;\s*rel="next"').firstMatch(r.headers['link'] ?? '')?.group(1);
          if (maxId == null) break;
        }
      case 'github':
        for (var page = 1; page <= 50 && out.length < maxFollows; page++) {
          final r = await _fetch('GET', Uri.https('api.github.com', '/users/$handle/following', {'per_page': '100', 'page': '$page'}), headers: _githubHeaders);
          if (r.status != 200) return page == 1 ? null : out;
          final list = jsonDecode(r.body) as List;
          out.addAll([for (final f in list) '${(f as Map)['login']}']);
          if (list.length < 100) break;
        }
      default:
        return null;
    }
    return [for (final h in out.take(maxFollows)) tidy(network, h)].where((h) => wellFormed(network, h)).toSet().toList();
  }

  // --- signing in: Discord, X, Telegram (a browser's requests, under /link/) -------------------------------------------

  String _redirect(String network) => '${config.publicUrl}/link/$network/callback';

  static String _page(String title, String words) => '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ghost Messaging</title>
<style>
  :root { color-scheme: light dark; --bg: #fdfdfd; --ink: #0e0e10; --ink2: #55565c; }
  @media (prefers-color-scheme: dark) { :root { --bg: #000; --ink: #f2f2f3; --ink2: #a3a4ab; } }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; font: 17px/1.5 Inter, system-ui, sans-serif; background: var(--bg); color: var(--ink); }
  main { max-width: 26rem; padding: 2rem 1.5rem; text-align: center; }
  h1 { font-size: 1.6rem; letter-spacing: -0.02em; margin: 0 0 0.5rem; }
  p { color: var(--ink2); margin: 0 0 1.25rem; }
</style></head>
<body><main><h1>${const HtmlEscape().convert(title)}</h1>$words</main></body></html>
''';

  Future<void> _html(HttpRequest request, int status, String title, String words) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.set('Cache-Control', 'no-store')
      ..headers.set('Referrer-Policy', 'no-referrer')
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..write(_page(title, words));
    await request.response.close();
  }

  Future<void> _sorry(HttpRequest request, String why) => _html(request, HttpStatus.badRequest, 'That didn\'t work', '<p>${const HtmlEscape().convert(why)}</p><p>Go back to Ghost Messaging and try again.</p>');

  Future<void> _thanks(HttpRequest request, String network, String handle) => _html(request, HttpStatus.ok, 'Linked',
      '<p>${const HtmlEscape().convert('@$handle')} on ${const HtmlEscape().convert(nameOf(network))} is linked to your Ghost Messaging.</p><p>You can close this page and go back to the app.</p>');

  static String nameOf(String network) => switch (network) {
        'x' => 'X',
        'github' => 'GitHub',
        _ => network[0].toUpperCase() + network.substring(1),
      };

  /// A browser's request under `/link/`: `/link/<network>?s=<state>` starts a sign-in, `/link/<network>/callback`
  /// ends one. Returns false where the address is not one of these.
  Future<bool> http(HttpRequest request) async {
    final parts = request.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.length < 2 || parts[0] != 'link' || !_signIn.contains(parts[1])) return false;
    final network = parts[1];
    final q = request.uri.queryParameters;
    sweep();
    try {
      if (parts.length == 2) {
        final asked = _asked[q['s']];
        if (asked == null || asked.network != network || ways[network] != 'signin') {
          await _sorry(request, 'This link is no longer good. They last ten minutes.');
          return true;
        }
        if (network == 'telegram') {
          // Telegram's own button, which sends the person back to the callback with who they are, signed.
          await _html(request, HttpStatus.ok, 'Link Telegram',
              '<p>Sign in with Telegram to show this account is yours.</p><script async src="https://telegram.org/js/telegram-widget.js?22" data-telegram-login="${const HtmlEscape().convert(config.telegramBot)}" data-size="large" data-auth-url="${const HtmlEscape().convert('${_redirect(network)}?state=${q['s']}')}"></script>');
          return true;
        }
        final to = network == 'discord'
            ? Uri.https('discord.com', '/oauth2/authorize', {'response_type': 'code', 'client_id': config.discordId, 'scope': 'identify', 'state': q['s'], 'redirect_uri': _redirect(network), 'prompt': 'consent'})
            : Uri.https('x.com', '/i/oauth2/authorize', {
                'response_type': 'code',
                'client_id': config.xId,
                'redirect_uri': _redirect(network),
                'scope': 'users.read tweet.read',
                'state': q['s'],
                'code_challenge': base64Url.encode(sha256(ascii.encode(asked.verifier))).replaceAll('=', ''),
                'code_challenge_method': 'S256',
              });
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('Location', to.toString())
          ..headers.set('Cache-Control', 'no-store');
        await request.response.close();
        return true;
      }
      if (parts.length != 3 || parts[2] != 'callback') return false;
      // A state is good once: taken as it is looked at.
      final asked = _asked.remove(q['state']);
      if (asked == null || asked.network != network) {
        await _sorry(request, 'This sign-in was not started from the app, or took longer than ten minutes.');
        return true;
      }
      final ({String account, String handle})? who;
      if (network == 'telegram') {
        who = _telegram(q);
      } else {
        final code = q['code'];
        if (code == null || code.isEmpty) {
          await _sorry(request, 'The sign-in was cancelled.');
          return true;
        }
        who = network == 'discord' ? await _discord(code) : await _x(code, asked.verifier);
      }
      if (who == null) {
        await _sorry(request, 'That account could not be confirmed.');
        return true;
      }
      if (who.handle.isEmpty) {
        await _sorry(request, 'That account has no username. Set one in ${nameOf(network)} first, then link it again.');
        return true;
      }
      final handle = tidy(network, who.handle);
      _link(asked.id, network, handle, who.account);
      await _thanks(request, network, handle);
    } catch (e) {
      _say('sign-in error on $network: ${e.runtimeType}');
      await _sorry(request, 'Something went wrong on the way.');
    }
    return true;
  }

  static String _form(Map<String, String> fields) => fields.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');

  Future<({String account, String handle})?> _discord(String code) async {
    final token = await _fetch('POST', Uri.https('discord.com', '/api/oauth2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded', 'Authorization': 'Basic ${base64Encode(utf8.encode('${config.discordId}:${config.discordSecret}'))}'},
        body: _form({'grant_type': 'authorization_code', 'code': code, 'redirect_uri': _redirect('discord')}));
    if (token.status != 200) return null;
    final access = (jsonDecode(token.body) as Map)['access_token'];
    if (access is! String) return null;
    final me = await _fetch('GET', Uri.https('discord.com', '/api/users/@me'), headers: {'Authorization': 'Bearer $access'});
    if (me.status != 200) return null;
    final m = jsonDecode(me.body) as Map;
    return (account: '${m['id']}', handle: '${m['username'] ?? ''}');
  }

  Future<({String account, String handle})?> _x(String code, String verifier) async {
    final token = await _fetch('POST', Uri.https('api.x.com', '/2/oauth2/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          // A confidential client signs in with its secret; a public one names itself in the form alone.
          if (config.xSecret.isNotEmpty) 'Authorization': 'Basic ${base64Encode(utf8.encode('${config.xId}:${config.xSecret}'))}',
        },
        body: _form({'grant_type': 'authorization_code', 'code': code, 'redirect_uri': _redirect('x'), 'code_verifier': verifier, 'client_id': config.xId}));
    if (token.status != 200) return null;
    final access = (jsonDecode(token.body) as Map)['access_token'];
    if (access is! String) return null;
    final me = await _fetch('GET', Uri.https('api.x.com', '/2/users/me'), headers: {'Authorization': 'Bearer $access'});
    if (me.status != 200) return null;
    final m = (jsonDecode(me.body) as Map)['data'] as Map?;
    if (m == null) return null;
    return (account: '${m['id']}', handle: '${m['username'] ?? ''}');
  }

  /// Who Telegram's button says signed in: every field it sent, in order, signed with a key made from our bot's
  /// token (core.telegram.org/widgets/login). Good for a day.
  ({String account, String handle})? _telegram(Map<String, String> q) {
    final hash = q['hash'];
    final when = int.tryParse(q['auth_date'] ?? '');
    if (hash == null || when == null || q['id'] == null) return null;
    const theirs = {'id', 'first_name', 'last_name', 'username', 'photo_url', 'auth_date'};
    final lines = [for (final k in q.keys.where(theirs.contains).toList()..sort()) '$k=${q[k]}'].join('\n');
    final want = hexOf(hmacSha256(sha256(utf8.encode(config.telegramToken)), utf8.encode(lines)));
    if (!_same(want, hash.toLowerCase())) return null;
    if (_now().toUtc().millisecondsSinceEpoch ~/ 1000 - when > 86400) return null;
    return (account: q['id']!, handle: q['username'] ?? '');
  }

  /// Compared without stopping at the first difference.
  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class _Asked {
  _Asked(this.id, this.network, this.verifier, this.at);
  final String id;
  final String network;
  final String verifier;
  final DateTime at;
}

/// What the networks' sign-ins need, from the server's environment (bin/relay.dart). A network whose values are
/// empty is "off": the app says its sign-in is not set up, and nothing else changes.
class HandlesConfig {
  const HandlesConfig({
    this.publicUrl = 'https://ghost-sms.com',
    this.discordId = '',
    this.discordSecret = '',
    this.xId = '',
    this.xSecret = '',
    this.telegramBot = '',
    this.telegramToken = '',
    this.githubToken = '',
    this.twilioSid = '',
    this.twilioToken = '',
    this.twilioVerify = '',
    this.textTo = const ['+1'],
    this.textsADay = 200,
  });

  factory HandlesConfig.fromEnvironment(Map<String, String> env) => HandlesConfig(
        publicUrl: (env['GHOST_PUBLIC_URL'] ?? 'https://ghost-sms.com').replaceAll(RegExp(r'/+$'), ''),
        discordId: env['GHOST_DISCORD_ID'] ?? '',
        discordSecret: env['GHOST_DISCORD_SECRET'] ?? '',
        xId: env['GHOST_X_ID'] ?? '',
        xSecret: env['GHOST_X_SECRET'] ?? '',
        telegramBot: env['GHOST_TELEGRAM_BOT'] ?? '',
        telegramToken: env['GHOST_TELEGRAM_TOKEN'] ?? '',
        githubToken: env['GHOST_GITHUB_TOKEN'] ?? '',
        twilioSid: env['GHOST_TWILIO_SID'] ?? '',
        twilioToken: env['GHOST_TWILIO_TOKEN'] ?? '',
        twilioVerify: env['GHOST_TWILIO_VERIFY'] ?? '',
        textTo: [
          for (final p in (env['GHOST_TEXT_TO'] ?? '+1').split(','))
            if (RegExp(r'^\+[0-9]{1,6}$').hasMatch(p.trim())) p.trim(),
        ],
        textsADay: int.tryParse(env['GHOST_TEXTS_A_DAY'] ?? '') ?? 200,
      );

  /// Where this server is reached from outside: what a sign-in comes back to.
  final String publicUrl;
  final String discordId;
  final String discordSecret;
  final String xId;
  final String xSecret;

  /// The bot's username, without "@", and its token.
  final String telegramBot;
  final String telegramToken;

  /// Optional: GitHub lets a server with a token read far more often than one without.
  final String githubToken;

  /// What texts a phone number its code (texts.dart, Twilio Verify): the account's SID and auth token, or an API
  /// key's SID and secret, and the Verify service's SID. With any of the three empty a number cannot be linked.
  final String twilioSid;
  final String twilioToken;
  final String twilioVerify;

  /// The numbers that may be texted, by how they start: North America unless said otherwise. Texts to some
  /// countries cost many times more, and are what people who make money from texts being sent ask for.
  final List<String> textTo;

  /// The most texts sent in a day, to everyone together: what a mistake or an attack can cost.
  final int textsADay;

  bool get texts => twilioSid.isNotEmpty && twilioToken.isNotEmpty && twilioVerify.isNotEmpty;
}

class Fetched {
  const Fetched(this.status, this.body, [this.headers = const {}]);
  final int status;
  final String body;
  final Map<String, String> headers;
}

/// One request to another server. [outside] marks an address a person typed (a Mastodon server): it is refused
/// unless it resolves to a public address, so this server cannot be pointed at its own network.
typedef Fetch = Future<Fetched> Function(String method, Uri url, {Map<String, String> headers, String? body, bool outside});

bool _private(InternetAddress a) {
  if (a.isLoopback || a.isLinkLocal || a.isMulticast) return true;
  final b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) {
    return b[0] == 10 || b[0] == 127 || b[0] == 0 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254) || (b[0] == 100 && b[1] >= 64 && b[1] <= 127) || b[0] >= 224;
  }
  // Unique local (fc00::/7), and IPv4 addresses written as IPv6.
  if ((b[0] & 0xfe) == 0xfc) return true;
  if (b.sublist(0, 10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff) return _private(InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))));
  return false;
}

/// Over https only, following no redirect, fifteen seconds and one megabyte at most.
Future<Fetched> defaultFetch(String method, Uri url, {Map<String, String> headers = const {}, String? body, bool outside = false}) async {
  if (url.scheme != 'https') return const Fetched(0, '');
  if (outside) {
    try {
      final found = await InternetAddress.lookup(url.host).timeout(const Duration(seconds: 5));
      if (found.isEmpty || found.any(_private)) return const Fetched(0, '');
    } catch (_) {
      return const Fetched(0, '');
    }
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.openUrl(method, url).timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    if (body != null) request.add(utf8.encode(body));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      bytes.addAll(chunk);
      if (bytes.length > 1 << 20) break;
    }
    return Fetched(response.statusCode, utf8.decode(bytes, allowMalformed: true), {'link': response.headers.value('link') ?? ''});
  } catch (_) {
    return const Fetched(0, '');
  } finally {
    client.close(force: true);
  }
}

/// HMAC-SHA256 (RFC 2104), with this folder's own SHA-256.
Uint8List hmacSha256(List<int> key, List<int> message) {
  var k = key.length > 64 ? sha256(key).toList() : key.toList();
  k = [...k, ...List.filled(64 - k.length, 0)];
  final inner = sha256([for (final b in k) b ^ 0x36, ...message]);
  return sha256([for (final b in k) b ^ 0x5c, ...inner]);
}
