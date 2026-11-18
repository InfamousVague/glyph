import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'handles.dart';
import 'p256.dart';
import 'secp256k1.dart';
import 'sha256.dart';

/// Ghost accounts (Matt, 2026-11-17: "We need to have a way to login to existing accounts. We might need to add password
/// based authentication as well as SMS verification for verified numbers"; "i also want accounts to be generated based on
/// ethereum type addresses with a recovery seed we can back up"). The app makes an account from twelve recovery words: an
/// Ethereum-style address is its id, and a backup of the Ghost identity is sealed twice on the phone, once with the
/// password and once with the words (lib/account/account_crypto.dart in the app). This keeps the two sealed blobs, and
/// can open neither.
///
/// - **An account** is kept by its address: the Ghost identity it belongs to (the hub's name for it and its P-256 key,
///   with that key's signature over the address as proof it agreed), the two blobs, and the devices signed in to it.
///   One account to an identity.
/// - **Writes** (`acct-put`, `acct-devices`, `acct-delete`, and reading the words' blob, `acct-seed`) carry `body`, a
///   JSON string, and `sig`, the account key's EIP-191 signature over it (65 bytes as hex). Whoever's signature
///   recovers to the address is the account. The body names its op, the address, the hub name it is said from (so it
///   cannot be replayed from another connection) and the time (ten minutes either way).
/// - **Signing in by username** (`acct-find`, then `acct-get`): the username's holder is looked up (handles.dart) and its
///   account found. Where that identity verified a phone number, the password's blob is handed over only after a fresh
///   code texted to that number is checked (handles.dart's texting and its limits; `acct-text` asks for it, with the
///   number typed, which has to be the one verified). Either way the blob goes only to an install that shows it knows
///   the password: `acct-find` gives the blob's Argon2id settings and salt, the install makes the key and from it a
///   proof (HKDF), and `acct-get` carries the proof, whose SHA-256 the account keeps (`pwv`). So nobody can take the
///   blob away and try passwords against it; guesses come here, a few an hour for each account.
/// - **Limited**: lookups and downloads per connection and per account each hour; [maxBlob] for each blob, [maxAccounts]
///   in all; [maxDevices] each.
///
/// An app from before this (0.9.4 and earlier) never says any `acct-` message, and nothing it does say is answered
/// differently: the hub sends these here and everything else where it went before.
class Accounts {
  Accounts({this.dataDir, this.handles, DateTime Function()? now, this.verbose = false}) : _now = now ?? DateTime.now;

  final Directory? dataDir;

  /// Usernames and verified numbers, and texting a code (handles.dart). Without it, signing in by username is off.
  final Handles? handles;
  final bool verbose;
  final DateTime Function() _now;

  /// What this answers.
  static const dirs = {'acct-put', 'acct-find', 'acct-text', 'acct-get', 'acct-seed', 'acct-devices', 'acct-hello', 'acct-delete'};

  /// A sealed blob as the app makes it: the backup is a few hundred bytes, friends and circles gzipped beside it.
  static const maxBlob = 64 * 1024;
  static const maxAccounts = 200000;
  static const maxDevices = 20;
  static const skew = Duration(minutes: 10);

  /// Lookups by username, and blobs handed over, per connection and per account, in an hour.
  static const findsAnHour = 30;
  static const getsAnHour = 6;
  static const getsForAccountAnHour = 10;
  static const writesAnHour = 60;

  /// A number typed for an account's verified one that is not it, per connection and per account in an hour: without
  /// these, trying numbers one after another would find out whose number an account has.
  static const numbersAnHour = 5;
  static const numbersForAccountAnHour = 5;

  /// After a right code, how long that connection may go on trying the password without another.
  static const passedFor = Duration(minutes: 10);

  /// All the blobs kept, in bytes: identities and addresses cost nothing to make, so [maxAccounts] alone would let one
  /// person fill the server's memory and disk.
  static const maxBytes = 256 << 20;

  /// address (lower case) -> {id, key, bind, pw, pwv, seed, at, devices: [{d, n, p, at, seen}]}
  final Map<String, Map<String, Object?>> _accounts = {};
  final Map<String, String> _byId = {};

  final Map<String, List<DateTime>> _finds = {};
  final Map<String, List<DateTime>> _gets = {};
  final Map<String, List<DateTime>> _getsFor = {};
  final Map<String, List<DateTime>> _writes = {};
  final Map<String, List<DateTime>> _numbers = {};
  final Map<String, List<DateTime>> _numbersFor = {};

  /// `connection|address` -> when a right code was checked for it ([passedFor]).
  final Map<String, DateTime> _passed = {};

  /// The SHA-256 of each signed body taken in the last [skew] twice over, and when: each is taken once, so one seen
  /// on the way (or said twice) cannot be said again inside its ten minutes.
  final Map<String, DateTime> _used = {};

  int _bytes = 0;
  static int _sizeOf(Map<String, Object?> a) => ((a['pw'] as String?)?.length ?? 0) + ((a['seed'] as String?)?.length ?? 0);

  int get count => _accounts.length;

  /// The address of [id]'s account, or null.
  String? accountOf(String id) => _byId[id];

  void _say(String what) {
    if (verbose) stdout.writeln('${_now().toIso8601String()} accounts $what');
  }

  // --- what is kept ----------------------------------------------------------------------------------------------------

  File? get _file => dataDir == null ? null : File('${dataDir!.path}/accounts.json');
  bool _dirty = false;

  void load() {
    final f = _file;
    if (f == null || !f.existsSync()) return;
    try {
      final all = (jsonDecode(f.readAsStringSync()) as Map)['accounts'] as Map;
      for (final e in all.entries) {
        final a = (e.value as Map).cast<String, Object?>();
        _accounts[e.key as String] = a;
        _byId[a['id'] as String] = e.key as String;
        _bytes += _sizeOf(a);
      }
    } catch (e) {
      stderr.writeln('accounts.json could not be read: $e');
    }
  }

  /// Written when something changed (the hub calls this every ten minutes and as it stops; [said] after each write too,
  /// since an account's blobs are not to be lost to a restart).
  void save() {
    final f = _file;
    if (f == null || !_dirty) return;
    try {
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.tmp')..writeAsStringSync(jsonEncode({'v': 1, 'accounts': _accounts}));
      tmp.renameSync(f.path);
      _dirty = false;
    } catch (e) {
      stderr.writeln('accounts.json could not be written: $e');
    }
  }

  DateTime? _savedAt;
  Timer? _saveSoon;

  /// Written now, or where it was written less than five seconds ago, in five seconds: the whole file is written each
  /// time, and a burst of writes would otherwise write it for each.
  void _changed() {
    _dirty = true;
    final now = DateTime.now();
    final last = _savedAt;
    if (last == null || now.difference(last) >= const Duration(seconds: 5)) {
      _savedAt = now;
      save();
    } else {
      _saveSoon ??= Timer(const Duration(seconds: 5), () {
        _saveSoon = null;
        _savedAt = DateTime.now();
        save();
      });
    }
  }

  static bool _room(Map<String, List<DateTime>> lists, String key, DateTime now, int anHour) {
    final list = lists[key] ??= [];
    list.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    if (list.length >= anHour) return false;
    list.add(now);
    return true;
  }

  /// Forgets counts older than an hour.
  void sweep() {
    final now = _now();
    for (final lists in [_finds, _gets, _getsFor, _writes, _numbers, _numbersFor]) {
      lists.removeWhere((_, l) => !l.any((t) => now.difference(t) <= const Duration(hours: 1)));
    }
    _passed.removeWhere((_, t) => now.difference(t) > passedFor);
    _used.removeWhere((_, t) => now.difference(t) > skew * 2);
  }

  /// Whether [a] and [b] are the same, in a time that does not depend on where they differ.
  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  /// The settings and salt of a password blob, without its sealed part: what an install needs to work out the proof
  /// that it knows the password; null where [blob] is not one.
  static Map<String, Object?>? _kdfOf(Object? blob) {
    try {
      final m = jsonDecode(blob as String) as Map;
      if (m['v'] != 1 || m['k'] != 'argon2id' || m['m'] is! int || m['t'] is! int || m['p'] is! int || m['s'] is! String) return null;
      return {'v': 1, 'k': 'argon2id', 'm': m['m'], 't': m['t'], 'p': m['p'], 's': m['s']};
    } catch (_) {
      return null;
    }
  }

  static final _hex = RegExp(r'^[0-9a-f]+$');
  static final _address = RegExp(r'^0x[0-9a-f]{40}$');
  static List<int>? _unhex(Object? s) {
    if (s is! String) return null;
    final t = s.startsWith('0x') ? s.substring(2) : s;
    if (t.length.isOdd || !_hex.hasMatch(t)) return null;
    return [for (var i = 0; i < t.length; i += 2) int.parse(t.substring(i, i + 2), radix: 16)];
  }

  /// The body of a signed message, where its signature is the account's, it is for [op] and from [id], and it is
  /// fresh; else why not.
  (Map<String, Object?>?, String?) _signed(Map said, String op, String id) {
    final text = said['body'];
    final sig = _unhex(said['sig']);
    if (text is! String || text.length > 3 * maxBlob || sig == null) return (null, 'That is not signed.');
    Map<String, Object?> body;
    try {
      body = (jsonDecode(text) as Map).cast<String, Object?>();
    } catch (_) {
      return (null, 'That is not signed.');
    }
    final address = body['a'];
    if (address is! String || !_address.hasMatch(address.toLowerCase())) return (null, 'That is not an account.');
    if (body['op'] != op || body['by'] != id) return (null, 'That is not signed for this.');
    final at = body['at'];
    if (at is! num || _now().difference(DateTime.fromMillisecondsSinceEpoch(at.toInt())).abs() > skew) return (null, 'Your clock is off. Set it to the right time and try again.');
    if (Secp256k1.signer(utf8.encode(text), sig) != address.toLowerCase()) return (null, 'That is not signed by the account.');
    // Taken once: by the body, not the signature, since v written 0/1 or 27/28 makes two signatures of one.
    final seen = hexOf(sha256(utf8.encode(text)));
    if (_used.containsKey(seen)) return (null, 'That was said already.');
    _used[seen] = _now();
    return (body, null);
  }

  // --- what an install says --------------------------------------------------------------------------------------------

  /// Something [id] (the hub's name for the connection) said that starts `{"dir": "acct-…"}`; answered with [tell].
  Future<void> said(String id, Map said, void Function(Map<String, Object?>) tell) async {
    final dir = said['dir'];
    void err(String why) => tell({'dir': 'err', 'about': dir, 'err': why});
    final now = _now();
    try {
      switch (dir) {
        case 'acct-put':
          // Made, or its blobs replaced (a new password): signed by the account, with the identity's proof.
          if (!_room(_writes, id, now, writesAnHour)) return err('Too many changes this hour. Try again later.');
          final (body, why) = _signed(said, 'put', id);
          if (body == null) return err(why!);
          final address = (body['a'] as String).toLowerCase();
          final pw = body['pw'], seed = body['seed'], identity = body['id'];
          List<int>? key, bind;
          try {
            key = base64Decode(body['key'] as String);
            bind = base64Decode(body['bind'] as String);
          } catch (_) {}
          if (pw is! String || seed is! String || pw.length > maxBlob || seed.length > maxBlob || pw.isEmpty || seed.isEmpty) return err('That backup is too big to keep.');
          // The password's blob is handed over only to someone who shows they know the password: the SHA-256 of the
          // proof the password makes ([pwv]), kept here, and the blob's settings and salt, which an install signing
          // in needs to make the proof. Without these anyone with the username could try passwords against the blob
          // on their own computer, as fast as they could buy them.
          final pwv = _unhex(body['pwv']);
          if (pwv == null || pwv.length != 32 || _kdfOf(pw) == null) return err('That backup is not one this server can keep. Update the app and try again.');
          if (identity is! String || key == null || bind == null || !P256.isKey(key) || hexOf(sha256(key).sublist(0, 16)) != identity) return err('That is not a Ghost identity.');
          if (!P256.verify(key, utf8.encode('ghost-account bind v1|$address'), bind)) return err('That identity did not agree to this account.');
          final had = _accounts[address];
          if (had != null && had['id'] != identity) return err('That account belongs to another Ghost identity.');
          final other = _byId[identity];
          if (other != null && other != address) return err('This Ghost identity already has an account.');
          final grows = pw.length + seed.length - (had == null ? 0 : _sizeOf(had));
          if ((had == null && _accounts.length >= maxAccounts) || _bytes + grows > maxBytes) return err('No more accounts can be made on this server just now.');
          _bytes += grows;
          _accounts[address] = {
            'id': identity,
            'key': base64Encode(key),
            'bind': base64Encode(bind),
            'pw': pw,
            'pwv': hexOf(pwv),
            'seed': seed,
            'at': (had?['at'] as String?) ?? now.toUtc().toIso8601String().substring(0, 10),
            'devices': had?['devices'] ?? <Object?>[],
          };
          _byId[identity] = address;
          _changed();
          _say('${address.substring(0, 8)} ${had == null ? 'made' : 'resealed'}');
          tell({'dir': 'acct-put', 'ok': true, 'a': address});
        case 'acct-find':
          // Whether a username has an account, whether a code texted to its number is needed, and the password blob's
          // settings and salt (`kdf`), to make the proof of the password from. No address, no number, no sealed part:
          // those come with the blob.
          final name = said['name'];
          if (!_room(_finds, id, now, findsAnHour)) return err('Too many lookups. Try again in a while.');
          final account = name is String ? _ofName(name) : null;
          if (account == null) return tell({'dir': 'acct-find', 'name': name, 'none': true});
          tell({'dir': 'acct-find', 'name': name, 'phone': _phoneOf(account.$2) != null, 'kdf': ?_kdfOf(account.$2['pw'])});
        case 'acct-text':
          final name = said['name'];
          final account = name is String ? _ofName(name) : null;
          final h = handles;
          if (account == null || h == null) return err('There is no account with that username.');
          final phone = _phoneOf(account.$2);
          if (phone == null) return err('That account has no verified number.');
          final number = said['number'] is String ? Handles.tidyNumber(said['number'] as String) : '';
          // The number has to be the one verified: this server texts no other on an account's behalf.
          final wrong = _wrongNumber(id, account.$1, phone, number, now);
          if (wrong != null) return err(wrong);
          final problem = await h.sendCode(id, number);
          if (problem != null) return err(problem);
          tell({'dir': 'acct-text', 'name': name, 'sent': true});
        case 'acct-get':
          // The password's blob, for the username, to an install that shows it knows the password (`auth`, whose
          // SHA-256 is the account's `pwv`); first a texted code where the account has a verified number.
          final name = said['name'];
          final account = name is String ? _ofName(name) : null;
          if (account == null) return err('There is no account with that username.');
          final phone = _phoneOf(account.$2);
          final passedKey = '$id|${account.$1}';
          final passed = _passed[passedKey];
          if (phone != null && (passed == null || now.difference(passed) > passedFor)) {
            final number = said['number'] is String ? Handles.tidyNumber(said['number'] as String) : '';
            if (said['code'] == null) return tell({'dir': 'acct-get', 'name': name, 'phone': true});
            final wrong = _wrongNumber(id, account.$1, phone, number, now);
            if (wrong != null) return err(wrong);
            final problem = await handles!.checkCode(id, number, said['code']);
            if (problem != null) return err(problem);
            // The code is used up: tries at the password for the next few minutes need no other.
            _passed[passedKey] = now;
          }
          if (!_room(_gets, id, now, getsAnHour) || !_room(_getsFor, account.$1, now, getsForAccountAnHour)) return err('Too many tries for this account. Try again in an hour.');
          final auth = _unhex(said['auth']);
          final pwv = _unhex(account.$2['pwv']);
          if (pwv == null) return err('Sign in to this account with its recovery words.');
          if (auth == null || auth.length != 32 || !_same(sha256(auth), pwv)) return err('That password isn\'t right.');
          _passed.remove(passedKey);
          _say('${account.$1.substring(0, 8)} handed out by username');
          tell({'dir': 'acct-get', 'name': name, 'a': account.$1, 'blob': account.$2['pw']});
        case 'acct-seed':
          // Both blobs, to whoever proves they hold the words (a signature by the account key).
          if (!_room(_gets, id, now, getsAnHour)) return err('Too many tries. Try again in an hour.');
          final (body, why) = _signed(said, 'seed', id);
          if (body == null) return err(why!);
          final address = (body['a'] as String).toLowerCase();
          final a = _accounts[address];
          if (a == null) return tell({'dir': 'acct-seed', 'a': address, 'none': true});
          tell({'dir': 'acct-seed', 'a': address, 'blob': a['seed'], 'pw': a['pw']});
        case 'acct-devices':
          // The devices signed in to the account: listed, one added (the device signing in), or one removed.
          if (!_room(_writes, id, now, writesAnHour)) return err('Too many changes this hour. Try again later.');
          final (body, why) = _signed(said, 'devices', id);
          if (body == null) return err(why!);
          final address = (body['a'] as String).toLowerCase();
          final a = _accounts[address];
          if (a == null) return err('There is no such account.');
          final list = [for (final d in (a['devices'] as List? ?? const [])) (d as Map).cast<String, Object?>()];
          final add = body['add'], remove = body['remove'];
          if (add is Map) {
            final d = add['d'];
            if (d is! String || d.length != 32 || !_hex.hasMatch(d)) return err('That is not a device.');
            list.removeWhere((x) => x['d'] == d);
            if (list.length >= maxDevices) return err('That account is signed in on $maxDevices devices. Remove one first.');
            final day = now.toUtc().toIso8601String().substring(0, 10);
            list.add({'d': d, 'n': _short(add['n'], 60), 'p': _short(add['p'], 20), 'at': day, 'seen': day});
          }
          if (remove is String) list.removeWhere((x) => x['d'] == remove);
          if (add is Map || remove is String) {
            a['devices'] = list;
            _changed();
          }
          tell({'dir': 'acct-devices', 'a': address, 'list': list});
        case 'acct-hello':
          // A device asking whether it is still signed in (it is not once removed): no signature, the device's own
          // number being 128 random bits only it and the account know.
          final address = said['a'] is String ? (said['a'] as String).toLowerCase() : '';
          final d = said['d'];
          final list = _accounts[address]?['devices'] as List?;
          final mine = list?.cast<Map>().where((x) => x['d'] == d).firstOrNull;
          if (mine != null) {
            final day = now.toUtc().toIso8601String().substring(0, 10);
            if (mine['seen'] != day) {
              mine['seen'] = day;
              _dirty = true;
            }
          }
          tell({'dir': 'acct-hello', 'a': address, 'known': mine != null, 'account': _accounts.containsKey(address)});
        case 'acct-delete':
          if (!_room(_writes, id, now, writesAnHour)) return err('Too many changes this hour. Try again later.');
          final (body, why) = _signed(said, 'delete', id);
          if (body == null) return err(why!);
          final address = (body['a'] as String).toLowerCase();
          final gone = _accounts.remove(address);
          if (gone != null) {
            _bytes -= _sizeOf(gone);
            _byId.remove(gone['id']);
            _changed();
          }
          tell({'dir': 'acct-delete', 'a': address, 'ok': true});
      }
    } catch (e) {
      err('That did not work. Try again in a while.');
      _say('error in $dir: ${e.runtimeType}');
    }
  }

  static String _short(Object? s, int n) {
    final t = s is String ? s.trim() : '';
    return t.length > n ? t.substring(0, n) : t;
  }

  /// The account of the install holding [name], as (address, record).
  (String, Map<String, Object?>)? _ofName(String name) {
    final holder = handles?.holderOf(name);
    final address = holder == null ? null : _byId[holder];
    final a = address == null ? null : _accounts[address];
    return a == null ? null : (address!, a);
  }

  /// Why [number] will not do for the account at [address] whose verified number hashes to [phone], or null where it
  /// is that number. A wrong one counts against the connection and the account, and once either has had its few,
  /// even the right one is refused for the hour: otherwise the answer would tell whose number an account has.
  String? _wrongNumber(String id, String address, String phone, String number, DateTime now) {
    bool full(Map<String, List<DateTime>> lists, String key, int most) => (lists[key] ?? const []).where((t) => now.difference(t) <= const Duration(hours: 1)).length >= most;
    if (full(_numbers, id, numbersAnHour) || full(_numbersFor, address, numbersForAccountAnHour)) return 'Too many tries for this account. Try again in an hour.';
    if (Handles.keyOf('phone', number) == phone) return null;
    _room(_numbers, id, now, numbersAnHour);
    _room(_numbersFor, address, now, numbersForAccountAnHour);
    return 'That isn\'t the number verified on this account.';
  }

  /// The hash of the number the account's identity verified, or null.
  String? _phoneOf(Map<String, Object?> account) => handles?.phoneKeyOf(account['id'] as String);
}
