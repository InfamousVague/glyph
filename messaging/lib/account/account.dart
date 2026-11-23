import 'dart:async';
import 'dart:convert';
import '../platform_info.dart';

import 'package:flutter/foundation.dart';

import '../circles/circles.dart';
import '../friends/buddies.dart';
import '../me/me.dart';
import '../net/carrier.dart';
import '../net/crypto.dart';
import '../net/hub_carrier.dart';
import '../net/net.dart';
import '../sms.dart';
import '../voice/channels.dart' show Voice;
import 'account_crypto.dart';

/// A Ghost account on this install (Matt, 2026-11-17: "We need to have a way to login to existing accounts. We might
/// need to add password based authentication as well as SMS verification for verified numbers"; "I like your
/// recommendation let's do it for now"; "i also want accounts to be generated based on ethereum type addresses with a
/// recovery seed we can back up").
///
/// - **Making one** ([draft], then [create]): twelve recovery words, the address they make (the account's id), a password.
///   The Ghost identity is the words' own where this install has nothing yet (no username, friends or circles), and
///   then the install takes it on and starts again; elsewhere it is the key the install already has, so nobody who
///   knows it has to add it again. Either way the identity and the words go in a backup sealed with the password and
///   with the words, kept on the relay (relay/lib/accounts.dart), and the device is listed under the account.
/// - **Signing in** ([findByName], [textCode], [signInWithPassword]; or [signInWithWords]) opens the backup, then
///   [finish] makes its identity this install's, puts its profile, friends and circles in place, and starts the app
///   again from nothing, so nothing goes on as the fresh install it was.
/// - **On this device**: the address and this device's number in the preferences, the password's sealed copy there
///   too (it is sealed; it is what "show my recovery words" and a new password open), and the words in the install's
///   secure storage (Android's Keystore-sealed vault, the Keychain), never in the preferences.
class Account extends ChangeNotifier {
  Account({required this.relay, required this.port, required this.store, required this.profiles});

  static Account? _instance;
  static Account get instance => _instance ??= Account(relay: HubAccountRelay(), port: SmsAccountPort(), store: _NoStore(), profiles: AppAccountProfiles());
  static set instance(Account? a) => _instance = a;

  final AccountRelay relay;
  final AccountPort port;
  MeStore store;
  final AccountProfiles profiles;

  /// Puts the app's preferences in place (people.dart) and asks the relay whether this device is still signed in; or,
  /// where a sign-in here was cut short, finishes it ([resume]).
  void start(MeStore store) {
    this.store = store;
    notifyListeners();
    unawaited(signedIn ? check() : resume());
  }

  // --- what this device keeps -----------------------------------------------------------------------------------------

  static const _words = 'account_words';
  static const _pwKey = 'account_pwkey';

  /// The account's address, EIP-55 capitals; null where this device is in none.
  String? get address {
    final a = store.choice('acct_address', '');
    return a.isEmpty ? null : a;
  }

  bool get signedIn => address != null;

  /// This device's number under the account (32 hex digits), what the devices list knows it by.
  String get device {
    var d = store.choice('acct_device', '');
    if (d.length != 32) {
      d = NetCrypto.hex(NetCrypto.randomBytes(16));
      store.set('acct_device', d);
    }
    return d;
  }

  /// 'seed' where the identity is the words' own, 'bound' where it was the install's before the account.
  String get mode => store.choice('acct_mode', 'seed');

  /// The relay said this device was removed from the account (from another device), or the account is gone.
  bool removedHere = false;

  Future<List<String>?> _keptWords() async {
    final w = await port.secretRead(_words);
    if (w == null || w.isEmpty) return null;
    final words = w.split(' ');
    return AccountCrypto.validWords(words) ? words : null;
  }

  void _keepHere({required String address, required String mode, required String sealed}) {
    store.set('acct_address', address);
    store.set('acct_mode', mode);
    store.set('acct_sealed', sealed);
    notifyListeners();
  }

  // --- making an account -----------------------------------------------------------------------------------------------

  /// New recovery words and the address they make, to be written down and confirmed before anything is sent anywhere.
  AccountDraft draft() {
    final words = AccountCrypto.newWords();
    return AccountDraft(words, _keysOf(words).address);
  }

  static ({Uint8List seed, Uint8List key, String address}) _keysOf(List<String> words) {
    final seed = AccountCrypto.seedOf(words);
    final key = AccountCrypto.derive(seed, AccountCrypto.ethPath);
    return (seed: seed, key: key, address: AccountCrypto.addressOf(AccountCrypto.publicOf(key)));
  }

  /// Makes the account [draft] names, sealed with [password]. True where this install took on the words' identity and
  /// is to start again ([restart]); false where it keeps its own and goes on as it was.
  Future<bool> create(AccountDraft draft, String password) async {
    final keys = _keysOf(draft.words);
    final fresh = profiles.fresh;
    final NetKeys identity = fresh ? AccountCrypto.identityOf(keys.seed) : NetKeys.fromScalar(await port.identityExport());
    final backup = profiles.fill(AccountBackup(words: draft.words, identity: NetCrypto.hex(identity.scalar), mode: fresh ? 'seed' : 'bound'));
    final pk = await PasswordKey.make(password);
    final sealed = await _put(keys, identity, backup, pk);
    await port.secretKeep(_words, draft.words.join(' '));
    await port.secretKeep(_pwKey, pk.toJson());
    _keepHere(address: keys.address, mode: backup.mode, sealed: sealed);
    await _addDevice(keys.key, keys.address);
    if (fresh) await port.identityImport(identity.scalar, identity.public);
    return fresh;
  }

  /// Seals [backup] both ways and keeps it on the relay; the password's copy, to keep here too.
  Future<String> _put(({Uint8List seed, Uint8List key, String address}) keys, NetKeys identity, AccountBackup backup, PasswordKey password) async {
    final pw = AccountCrypto.sealWithPasswordKey(backup, password, keys.address);
    final seed = AccountCrypto.sealWithSeed(backup, keys.seed, keys.address);
    await relay.ask(_signed('acct-put', 'put', keys, {
      'id': identity.id,
      'key': base64Encode(identity.public),
      'bind': base64Encode(AccountCrypto.bindProof(identity, keys.address)),
      'pw': pw,
      // What the relay checks the proof of the password against before it hands the password's copy to anyone.
      'pwv': password.verifier,
      'seed': seed,
    }));
    return pw;
  }

  Map<String, Object?> _signed(String dir, String op, ({Uint8List seed, Uint8List key, String address}) keys, Map<String, Object?> more) {
    final body = jsonEncode({'op': op, 'a': keys.address, 'by': relay.hubId, 'at': DateTime.now().millisecondsSinceEpoch, ...more});
    return {'dir': dir, 'body': body, 'sig': NetCrypto.hex(AccountCrypto.sign(keys.key, utf8.encode(body)))};
  }

  static String get _platform => PlatformInfo.isAndroid ? 'android' : PlatformInfo.isIOS ? 'ios' : PlatformInfo.isMacOS ? 'macos' : PlatformInfo.isWindows ? 'windows' : 'linux';

  Future<List<AccountDevice>> _addDevice(Uint8List key, String address) async {
    final m = await relay.ask(_signed('acct-devices', 'devices', (seed: Uint8List(0), key: key, address: address), {
      'add': {'d': device, 'n': profiles.deviceName, 'p': _platform},
    }));
    return AccountDevice.list(m['list'], device);
  }

  // --- signing in --------------------------------------------------------------------------------------------------

  /// Whether [username] has an account, and whether its number has to be sent a code first.
  Future<({bool phone})> findByName(String username) async {
    final m = await relay.ask({'dir': 'acct-find', 'name': tidyHandle(username)});
    if (m['none'] == true) throw AccountError('No account has that username.');
    return (phone: m['phone'] == true);
  }

  /// Texts a code to the number verified on [username]'s account; [number] has to be that number.
  Future<void> textCode(String username, String number) async {
    await relay.ask({'dir': 'acct-text', 'name': tidyHandle(username), 'number': number});
  }

  /// The account [username] opened with [password] ([number] and [code] where its number is verified). Throws
  /// [AccountNeedsCode] where a code is wanted first and [AccountError] where the password is not the one.
  ///
  /// The password is stretched here with the settings and salt the relay gives (`acct-find`), and only the proof it
  /// makes ([PasswordKey.auth]) is sent; the relay hands the sealed copy over only for the right one, so nobody can
  /// take the copy away and try passwords against it.
  Future<AccountRestore> signInWithPassword(String username, String password, {String? number, String? code}) async {
    final name = tidyHandle(username);
    final found = await relay.ask({'dir': 'acct-find', 'name': name});
    if (found['none'] == true) throw AccountError('No account has that username.');
    if (found['phone'] == true && code == null) throw AccountNeedsCode();
    final kdf = found['kdf'];
    // Never weaker than an account is made with: a relay offering cheaper settings would be after a proof it could
    // try passwords against more cheaply than the copy it keeps.
    if (kdf is! Map || kdf['m'] is! int || kdf['t'] is! int || (kdf['m'] as int) < AccountCrypto.argonMemoryKiB || (kdf['t'] as int) < AccountCrypto.argonPasses) {
      throw AccountError('That account could not be read.');
    }
    final pk = await PasswordKey.forKdf(kdf, password);
    if (pk == null) throw AccountError('That account could not be read.');
    final m = await relay.ask({'dir': 'acct-get', 'name': name, 'number': ?number, 'code': ?code, 'auth': NetCrypto.hex(pk.auth)});
    if (m['blob'] is! String) {
      if (m['phone'] == true) throw AccountNeedsCode();
      throw AccountError('That account could not be read.');
    }
    final blob = m['blob'] as String;
    final address = AccountCrypto.checksummed(m['a'] as String);
    final backup = AccountCrypto.openWithPasswordKey(blob, pk, address);
    if (backup == null) throw AccountError('That password isn\'t right.');
    if (_keysOf(backup.words).address != address) throw AccountError('That backup is not this account\'s.');
    return AccountRestore(address, backup, blob, passwordKey: pk);
  }

  /// The account [words] make, opened with them: no password and no code, the words being the account itself. Where
  /// the relay has no backup for it ([AccountRestore.backedUp] false) the words still make the address and the Ghost
  /// identity of an account that began with them; a new password is then needed to keep a backup again.
  Future<AccountRestore> signInWithWords(List<String> words) async {
    if (!AccountCrypto.validWords(words)) throw AccountError('Those words don\'t add up. Check each one, and their order.');
    final keys = _keysOf(words);
    final m = await relay.ask(_signed('acct-seed', 'seed', keys, const {}));
    if (m['none'] == true) {
      final identity = AccountCrypto.identityOf(keys.seed);
      return AccountRestore(keys.address, AccountBackup(words: words, identity: NetCrypto.hex(identity.scalar)), null, backedUp: false);
    }
    final backup = AccountCrypto.openWithSeed(m['blob'] as String, keys.seed, keys.address);
    if (backup == null) throw AccountError('The backup kept for these words could not be opened.');
    return AccountRestore(keys.address, backup, m['pw'] as String?);
  }

  /// Makes [restore] this install: its identity in place of this one's, its profile, friends and circles, this
  /// device listed under it, and the app started again ([restart]). [password] is needed where nothing was backed up.
  /// True where the app is starting again; false where it cannot by itself (an iPhone) and the person is to.
  Future<bool> finish(AccountRestore restore, {String? password}) async {
    final keys = _keysOf(restore.backup.words);
    final identity = NetKeys.fromScalar(NetCrypto.unhex(restore.backup.identity));
    var sealed = restore.sealed;
    var pk = restore.passwordKey;
    if (!restore.backedUp || sealed == null) {
      if (password == null) throw AccountError('Choose a password to keep a backup.');
      pk = await PasswordKey.make(password);
      sealed = await _put(keys, identity, restore.backup, pk);
    }
    await _addDevice(keys.key, keys.address);
    await port.secretKeep(_words, restore.backup.words.join(' '));
    if (pk != null) await port.secretKeep(_pwKey, pk.toJson());
    // The identity this install had until now, where it is another and its own: kept beside the words, so what it was in
    // circles becomes the account's (Voice.carryOver) rather than someone else beside it. Not a paired computer's: the
    // identity it took on is its phone's, still the phone's after this, and never to be folded into another.
    try {
      final before = NetKeys.fromScalar(await port.identityExport());
      // Only an identity with no friends of its own: one that has them is someone people know, perhaps another person
      // who used this computer, and not to be made the account's in anyone's eyes.
      if (!Sms.paired && Buddies.instance.all.isEmpty && before.id != identity.id) await port.secretKeep(Voice.wasKey, NetCrypto.hex(before.scalar));
    } catch (_) {}
    // The new identity, then everything that hangs off it, then this device's account; the old identity is gone
    // from the moment the first is written, so nothing below may fail half way and leave this install between the two.
    await port.identityImport(identity.scalar, identity.public);
    await profiles.apply(restore.backup);
    _keepHere(address: restore.address, mode: restore.backup.mode, sealed: sealed);
    return restart();
  }

  /// Whether making [restore] this install would change who it is: its identity is not the one here now. On a computer
  /// paired with a phone, whose identity is the phone's, that splits the two into different people to everyone who
  /// writes to them, so Settings asks first (Matt, 2026-11-18: "messages from desktop are coming through differently
  /// than messages on mobile even though they're both me").
  Future<bool> wouldChangeIdentity(AccountRestore restore) async {
    try {
      return NetKeys.fromScalar(await port.identityExport()).id != NetKeys.fromScalar(NetCrypto.unhex(restore.backup.identity)).id;
    } catch (_) {
      return true;
    }
  }

  /// Starts the app again; false where it cannot by itself.
  Future<bool> restart() async {
    await profiles.stopAll();
    return port.restart();
  }

  // --- on a signed-in device -----------------------------------------------------------------------------------------

  /// The recovery words, for [password]: what is kept here is opened with it, so the words are shown only to someone
  /// who knows it.
  Future<List<String>> revealWords(String password) async {
    final address = this.address;
    if (address == null) throw AccountError('This device is not signed in.');
    final blob = store.choice('acct_sealed', '');
    final pk = await PasswordKey.forBlob(blob, password);
    final backup = pk == null ? null : AccountCrypto.openWithPasswordKey(blob, pk, address);
    if (backup == null) throw AccountError('That password isn\'t right.');
    // Typed here at last (a device signed in by its words): kept, so the backup can be brought up to date from now on.
    await port.secretKeep(_pwKey, pk!.toJson());
    return backup.words;
  }

  /// A new password: the backup opened with [old], its profile brought up to now, and sealed again both ways.
  Future<void> changePassword(String old, String next) async {
    final address = this.address;
    if (address == null) throw AccountError('This device is not signed in.');
    final backup = await AccountCrypto.openWithPassword(store.choice('acct_sealed', ''), old, address);
    if (backup == null) throw AccountError('That password isn\'t right.');
    final keys = _keysOf(backup.words);
    final identity = NetKeys.fromScalar(NetCrypto.unhex(backup.identity));
    final pk = await PasswordKey.make(next);
    final sealed = await _put(keys, identity, profiles.fill(backup), pk);
    store.set('acct_sealed', sealed);
    await port.secretKeep(_pwKey, pk.toJson());
    notifyListeners();
  }

  /// Seals the backup again with this install's profile, friends and circles as they are now, both ways, with the
  /// password's key kept here: at most once a day, as the app starts ([check]). Nothing where the password has not
  /// been typed on this device (signed in by its words, and the words not yet shown or the password not changed).
  Future<bool> refresh({bool force = false}) async {
    final address = this.address;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (address == null || (!force && store.choice('acct_refreshed', '') == today)) return false;
    final words = await _keptWords();
    final pk = PasswordKey.fromJson(await port.secretRead(_pwKey));
    if (words == null || pk == null) return false;
    final keys = _keysOf(words);
    if (keys.address != address) return false;
    final identity = NetKeys.fromScalar(await port.identityExport());
    final mine = profiles.fill(AccountBackup(words: words, identity: NetCrypto.hex(identity.scalar), mode: mode));
    var backup = mine;
    // Put together with what is kept now: every device of the account seals it again in its turn, and the last used to
    // decide alone, so one in fewer circles (or with fewer friends) took the others' out of what the next device signing
    // in is given (2026-11-19, found as the check below began to reach the relay at all).
    // Not read (the relay away, too many asks): nothing sealed now rather than this device's alone over the others'.
    final got = await relay.ask(_signed('acct-seed', 'seed', keys, const {}));
    final blob = got['blob'];
    final kept = blob is String ? AccountCrypto.openWithSeed(blob, keys.seed, keys.address) : null;
    if (blob is String && kept == null) return false;
    // A circle left here stays left: not brought back from the copy kept before it was.
    if (kept != null) {
      backup = mine.copyWith(circles: _union(mine.circles, [for (final c in kept.circles) if (!(c is Map && c['s'] is String && Circles.instance.removed(c['s'] as String))) c], 's'), friends: _union(mine.friends, kept.friends, 'i'));
    }
    String sealed;
    try {
      sealed = await _put(keys, identity, backup, pk);
    } on AccountError catch (e) {
      // Too much put together to keep (a backup is at most so big on the relay): this device's own, as before.
      if (identical(backup, mine) || !e.message.contains('too big')) rethrow;
      sealed = await _put(keys, identity, mine, pk);
    }
    store.set('acct_sealed', sealed);
    store.set('acct_refreshed', today);
    return true;
  }

  /// [mine], then each of [theirs] whose [key] none of [mine] has: this device's own copy of anything both have.
  static List<Object?> _union(List<Object?> mine, List<Object?> theirs, String key) {
    final have = {for (final x in mine) if (x is Map && x[key] is String) x[key]};
    return [...mine, for (final x in theirs) if (x is Map && x[key] is String && !have.contains(x[key])) x];
  }

  Future<({Uint8List seed, Uint8List key, String address})> _keys() async {
    final words = await _keptWords();
    if (words == null || address == null) throw AccountError('This device\'s copy of the account can\'t be read. Sign in again.');
    return _keysOf(words);
  }

  /// The devices signed in to the account.
  Future<List<AccountDevice>> devices() async {
    final m = await relay.ask(_signed('acct-devices', 'devices', await _keys(), const {}));
    return AccountDevice.list(m['list'], device);
  }

  Future<List<AccountDevice>> removeDevice(String d) async {
    final m = await relay.ask(_signed('acct-devices', 'devices', await _keys(), {'remove': d}));
    return AccountDevice.list(m['list'], device);
  }

  /// A sign-in cut short by the app starting again (2026-11-19: on a computer the account's own choices were still being
  /// written as the app closed, so it came back signed out, with the account's words in its vault and the relay listing
  /// it): finished now, where the relay still lists this device under the words' account and the identity here is that
  /// account's. True where it was; anything else is left as it is, for the person to sign in again.
  Future<bool> resume() async {
    try {
      final words = await _keptWords();
      if (words == null || signedIn) return false;
      // Tried once a day: where it cannot be taken up (another identity here), not asked of the relay at every start.
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      if (store.choice('acct_resumed', '') == today) return false;
      store.set('acct_resumed', today);
      // Asked as the app starts: the hub it is asked through is made a moment after (Net.start reads the identity first).
      final r = relay;
      if (r is HubAccountRelay && !await r.hubMade()) return false;
      final keys = _keysOf(words);
      final hello = await relay.ask({'dir': 'acct-hello', 'a': keys.address, 'd': device});
      if (hello['known'] != true || signedIn) return false;
      final got = await relay.ask(_signed('acct-seed', 'seed', keys, const {}));
      final blob = got['blob'];
      if (got['none'] == true || blob is! String) return false;
      final backup = AccountCrypto.openWithSeed(blob, keys.seed, keys.address);
      if (backup == null) return false;
      final here = NetKeys.fromScalar(await port.identityExport());
      if (here.id != NetKeys.fromScalar(NetCrypto.unhex(backup.identity)).id || signedIn) return false;
      _keepHere(address: keys.address, mode: backup.mode, sealed: (got['pw'] as String?) ?? '');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether the relay still has this device under the account; where it does not, this device forgets the account.
  Future<void> check() async {
    final address = this.address;
    if (address == null) return;
    // Asked as the app starts, before the hub it goes through is made (Net.start reads the identity first): it used to
    // fail there every time, unsaid, so the backup was never sealed again and a device taken off was never told.
    final r = relay;
    if (r is HubAccountRelay && !await r.hubMade()) return;
    try {
      final m = await relay.ask({'dir': 'acct-hello', 'a': address, 'd': device});
      if (m['known'] == false) {
        removedHere = true;
        await _forgetHere();
      } else {
        await refresh();
      }
    } catch (_) {}
  }

  Future<void> _forgetHere() async {
    store.set('acct_address', '');
    store.set('acct_sealed', '');
    store.set('acct_mode', '');
    await port.secretKeep(_words, '');
    await port.secretKeep(_pwKey, '');
    // Out of the account, this install is no longer whoever it was before signing in either (Voice.carryOver).
    await port.secretKeep(Voice.wasKey, '');
    // And this device's forward-secrecy prekeys and what it knew of others' (GMFB-26): nothing of the account left.
    try {
      await Net.instance.board?.fs?.wipe();
    } catch (_) {}
    try {
      await Circles.instance.keys?.wipe();
    } catch (_) {}
    notifyListeners();
  }

  /// Signs this device out: taken off the account's list, the words forgotten here, and a new identity of its own in
  /// place of the account's, so it is no longer the account to anyone; then the app starts again.
  Future<bool> signOut() async {
    try {
      await relay.ask(_signed('acct-devices', 'devices', await _keys(), {'remove': device}));
    } catch (_) {}
    await _forgetHere();
    // A computer paired with a phone goes back to the phone's identity (it is taken on again as the app starts);
    // anywhere else, a new identity of its own.
    if (!await port.identityForget()) {
      final fresh = NetKeys.generate();
      await port.identityImport(fresh.scalar, fresh.public);
    }
    await profiles.forget();
    return restart();
  }
}

class AccountDraft {
  const AccountDraft(this.words, this.address);
  final List<String> words;
  final String address;
}

/// An account opened on a new device, not yet made its own ([Account.finish]).
class AccountRestore {
  const AccountRestore(this.address, this.backup, this.sealed, {this.backedUp = true, this.passwordKey});
  final String address;
  final AccountBackup backup;

  /// The password's copy, to keep on this device; null where the relay had none.
  final String? sealed;
  final bool backedUp;

  /// The key the password made, where it was typed: kept with the words, so the backup can be sealed again.
  final PasswordKey? passwordKey;
}

class AccountDevice {
  const AccountDevice({required this.id, required this.name, required this.platform, required this.since, required this.seen, this.here = false});
  final String id;
  final String name;
  final String platform;
  final String since;
  final String seen;

  /// This device.
  final bool here;

  static List<AccountDevice> list(Object? list, String mine) => [
        for (final d in (list as List? ?? const []).whereType<Map>())
          AccountDevice(id: '${d['d']}', name: '${d['n'] ?? ''}', platform: '${d['p'] ?? ''}', since: '${d['at'] ?? ''}', seen: '${d['seen'] ?? ''}', here: d['d'] == mine),
      ];
}

class AccountError implements Exception {
  AccountError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The account has a verified number, and a code texted to it is wanted before its backup is handed over.
class AccountNeedsCode extends AccountError {
  AccountNeedsCode() : super('A code texted to the account\'s number is needed.');
}

// --- what the account is spoken through --------------------------------------------------------------------------------

/// The relay's accounts (relay/lib/accounts.dart): [ask] says something and gives back its answer, or throws
/// [AccountError] with the relay's words.
abstract class AccountRelay {
  Future<Map<String, dynamic>> ask(Map<String, Object?> what);

  /// The hub's name for this connection: written into what is signed, so it can't be said again from another.
  String get hubId;
}

/// Through the app's hub connection, as Settings › Me speaks to handles (lib/me/me.dart).
class HubAccountRelay implements AccountRelay {
  HubAccountRelay({HubCarrier? Function()? hub}) : _hub = hub ?? (() => Net.instance.hub);
  final HubCarrier? Function() _hub;

  @override
  String get hubId => _hub()?.signer.id ?? Net.instance.id ?? '';

  /// Waits for the app's hub to be made (Net.start makes it once the identity is read, a moment after the app starts);
  /// false where it is not within [within].
  Future<bool> hubMade({Duration within = const Duration(seconds: 20)}) async {
    const step = Duration(milliseconds: 250);
    for (var waited = Duration.zero; _hub() == null; waited += step) {
      if (waited >= within) return false;
      await Future<void>.delayed(step);
    }
    return true;
  }

  @override
  Future<Map<String, dynamic>> ask(Map<String, Object?> what, {Duration wait = const Duration(seconds: 25)}) async {
    unawaited(Net.instance.want('account', true));
    final hub = _hub();
    if (hub == null) throw AccountError('The relay server can\'t be reached right now.');
    if (hub.state.value != CarrierState.up) {
      final up = Completer<void>();
      void changed() {
        if (hub.state.value == CarrierState.up && !up.isCompleted) up.complete();
      }

      hub.state.addListener(changed);
      try {
        await up.future.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        throw AccountError('The relay server can\'t be reached right now.');
      } finally {
        hub.state.removeListener(changed);
      }
    }
    final dir = what['dir'];
    final answer = hub.handles.firstWhere((m) => m['dir'] == dir || (m['dir'] == 'err' && m['about'] == dir)).timeout(wait, onTimeout: () => throw AccountError('The relay server did not answer.'));
    if (!hub.sayHandles(what)) throw AccountError('The relay server can\'t be reached right now.');
    final m = await answer;
    if (m['dir'] == 'err') throw AccountError((m['err'] as String?) ?? 'That did not work.');
    return m;
  }
}

/// What the account asks of the install: its key, keeping a secret, starting again.
abstract class AccountPort {
  Future<Uint8List> identityExport();
  Future<void> identityImport(List<int> scalar, List<int> public);
  Future<void> secretKeep(String name, String value);
  Future<String?> secretRead(String name);
  Future<bool> restart();

  /// Lets go of this install's identity where it has one to go back to (a computer paired with a phone takes the
  /// phone's on again); false where it has none, and signing out makes a new one.
  Future<bool> identityForget();
}

class SmsAccountPort implements AccountPort {
  /// A paired computer that has not taken on an identity of its own asks everything of the phone: an account's calls
  /// would change the phone's identity and vault from the computer, so none is made from there.
  static Future<T> _own<T>(Future<T> Function() call) async {
    if (Sms.followsPhone) throw AccountError('This computer hasn\'t become the same you as your phone yet.');
    return call();
  }

  @override
  Future<Uint8List> identityExport() => _own(() => Sms.instance.identityExport());
  @override
  Future<void> identityImport(List<int> scalar, List<int> public) => _own(() => Sms.instance.identityImport(scalar, public));
  @override
  Future<void> secretKeep(String name, String value) => _own(() => Sms.instance.secretKeep(name, value));
  @override
  Future<String?> secretRead(String name) => _own(() => Sms.instance.secretRead(name));
  @override
  Future<bool> restart() => _own(() => Sms.instance.restartApp());
  @override
  Future<bool> identityForget() => Sms.instance.identityForget();
}

/// What an account carries besides its identity: the profile, friends by username, circles, the key Ghost's own kept
/// lists are sealed with.
abstract class AccountProfiles {
  /// Nothing here yet that anyone knows this install's key by: no username, friends or circles.
  bool get fresh;

  /// What this device is called in the account's list.
  String get deviceName;

  /// [backup] with this install's profile, friends and circles as they are now.
  AccountBackup fill(AccountBackup backup);

  /// [backup]'s profile, friends and circles put in place here.
  Future<void> apply(AccountBackup backup);

  /// This install's profile, friends and circles forgotten (signing out).
  Future<void> forget();

  /// Everything that speaks as this install stopped, before it starts again as another.
  Future<void> stopAll();
}

class AppAccountProfiles implements AccountProfiles {
  MeStore? get _store => Account.instance.store is _NoStore ? null : Account.instance.store;

  @override
  // A computer paired with a phone is never fresh: its identity is the phone's, and an account made there keeps it
  // (bound), so the two stay one person rather than the computer taking the words' identity alone.
  bool get fresh => !Sms.paired && Me.instance.username == null && Buddies.instance.all.isEmpty && Circles.instance.all.isEmpty && Me.instance.links.isEmpty;

  @override
  String get deviceName {
    final host = PlatformInfo.localHostname;
    final kind = PlatformInfo.isAndroid ? 'Android phone' : PlatformInfo.isIOS ? 'iPhone' : PlatformInfo.isMacOS ? 'Mac' : PlatformInfo.isWindows ? 'Windows PC' : 'Computer';
    return host.isEmpty || host == 'localhost' ? kind : '$kind · $host';
  }

  @override
  AccountBackup fill(AccountBackup backup) => backup.copyWith(
        username: Me.instance.username ?? '',
        displayName: Me.instance.displayName,
        bio: Me.instance.bio,
        keptKey: _store?.choice('kept_key', '') ?? '',
        friends: [for (final b in Buddies.instance.friends) b.toJson()],
        circles: [for (final c in Circles.instance.all) c.toJson()],
      );

  @override
  Future<void> apply(AccountBackup b) async {
    final store = _store;
    if (store == null) return;
    store.set('me_username', b.username);
    store.set('me_display', b.displayName);
    store.set('me_bio', b.bio);
    if (b.keptKey.length == 64) store.set('kept_key', b.keptKey);
    store.set('circles', jsonEncode(b.circles));
    store.set('circles_gone', '[]');
    await Sms.instance.buddiesKeep(jsonEncode(b.friends));
  }

  @override
  Future<void> forget() async {
    final store = _store;
    if (store == null) return;
    for (final k in ['me_username', 'me_display', 'me_bio', 'kept_key']) {
      store.set(k, '');
    }
    store.set('circles', '[]');
    await Sms.instance.buddiesKeep('[]');
  }

  @override
  Future<void> stopAll() async {
    try {
      await Net.instance.shutdown();
    } catch (_) {}
  }
}

class _NoStore implements MeStore {
  final Map<String, String> _kept = {};
  @override
  String choice(String key, String fallback) => _kept[key] ?? fallback;
  @override
  bool flag(String key, {bool fallback = true}) => _kept[key] == null ? fallback : _kept[key] == 'on';
  @override
  void set(String key, String value) => _kept[key] = value;
  @override
  void setFlag(String key, bool on) => set(key, on ? 'on' : 'off');
}
