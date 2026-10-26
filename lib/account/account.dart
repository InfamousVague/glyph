/// An account on this device (docs/SYNC.md): making one, the three ways in, and what signing out takes away. A port
/// of `src/app/core/account/account.ts`.
///
/// A password or a recovery code is split on the device, the half the service may see goes to it, and the other
/// half unwraps the account key, which then stays on the device and is never asked for again. A device also
/// registers its own signing key, so an expired session renews itself without the password.
///
/// What differs:
/// - The page has one account state for the whole module, and every function takes the device's `Deps` as its last
///   argument. Here an [Account] IS a device's account: it is made with its [KeyStore], its [Api], its
///   [AccountCrypto] and its round count, holds the state itself as a [ValueListenable], and the flows are its
///   methods. Two devices in a test are two [Account]s, each with its own state; the page's tests share one.
/// - The state starts signed out and is filled by [Account.resume] (or [Account.restore], which asks the service
///   nothing), since the session is read from the key store with a wait (keystore.dart); the page reads it from
///   `localStorage` as the module loads.
/// - There is no `live` default: the page's `deviceKeys()` and its fixed service are a key store and an [Api] that
///   whoever wires the app must give (docs/STAGE7.md: a development build is given the fake or a local server).
/// - [recover] words a code that will not open the key as the service's refusal would be, where the page lets
///   WebCrypto's own error through.
/// - The device's label is the platform's, not a user agent's.
library;


import 'package:flutter/foundation.dart';

import 'api.dart';
import 'crypto_api.dart';
import 'keystore.dart';
import 'session.dart';
import '../core/host_platform.dart';

export 'session.dart';

/// The service's handle rule, checked here too so a mistake is said before a round trip (`handleProblem`).
String? handleProblem(String handle) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,23}$').hasMatch(handle.trim()) ? null : 'A handle is 3 to 24 letters, digits, . _ or -, starting with a letter or digit.';

/// `passwordProblem`. Counted in UTF-16 units, as the page's `length` counts.
String? passwordProblem(String password) => password.length >= 8 ? null : 'A password is at least 8 characters.';

/// What this device is called on the account's list of devices (`deviceLabel`).
String deviceLabel() {
  if (kIsWeb) return 'Web';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iPhone';
  if (Platform.isMacOS) return 'Mac';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isLinux) return 'Linux';
  return 'Web';
}

/// The service's answer to a sign-in or a renewal (`SignedIn`), `wrapped` being the account key under the password.
class SignedIn {
  const SignedIn({required this.token, required this.accountId, required this.handle, this.wrapped});

  /// The answer as the service gives it: `{ token, account: { id, handle }, wrapped? }`. Throws [ApiError] for one
  /// with no token or no account, which the page would find out about a line later.
  factory SignedIn.fromJson(Object? raw) {
    final account = raw is Map ? raw['account'] : null;
    final token = raw is Map ? raw['token'] : null;
    if (token is! String || account is! Map || account['id'] is! num || account['handle'] is! String) {
      throw const ApiError(500, 'The service answered without a session.');
    }
    final wrapped = raw is Map ? raw['wrapped'] : null;
    return SignedIn(token: token, accountId: (account['id'] as num).toInt(), handle: account['handle'] as String, wrapped: wrapped is String && wrapped.isNotEmpty ? wrapped : null);
  }

  final String token;
  final int accountId;
  final String handle;
  final String? wrapped;

  Session get session => Session(token: token, handle: handle, accountId: accountId);
}

/// What making an account, or recovering one, hands back (`Made`).
class Made {
  const Made(this.codes);

  /// The recovery sheet: shown to the person once, never kept on the device or sent anywhere.
  final List<String> codes;
}

/// The account on one device, and the flows that change it. Its value is what the app shows: the session, and
/// whether the account key is here (`accountState`, `useAccount`, `onAccount`).
class Account extends ValueNotifier<AccountState> implements AccountSource {
  /// [iterations] is PBKDF2's rounds: the real number ([rounds]), except in tests. [label] is what this device is
  /// called on the account.
  Account({required this.keys, required this.api, required this.crypto, this.iterations = rounds, String? label})
      : label = label ?? deviceLabel(),
        super(AccountState.none);

  final KeyStore keys;
  final Api api;
  final AccountCrypto crypto;
  final int iterations;
  final String label;

  @override
  Session? get session => value.session;

  /// The account key, for sync: null when this device has none (`accountKey`).
  @override
  Future<SealKey?> accountKey() => keys.accountKey();

  /// Tells the app what this device holds now: the session, and whether the account key is here (`settleState`).
  Future<void> _settle(Session? session) async {
    await keys.setSession(session);
    value = AccountState(session: session, unlocked: session != null && await keys.accountKey() != null);
  }

  /// What this device kept, shown without asking the service anything: for the first frame, before [resume].
  Future<void> restore() async {
    final session = await keys.session();
    value = AccountState(session: session, unlocked: session != null && await keys.accountKey() != null);
  }

  /// This device's signing key, made and registered on the account if it has none (`enrolDevice`).
  Future<void> _enrolDevice(String token) async {
    if (await keys.deviceKey() != null) return;
    final pair = await crypto.newDeviceKey();
    await api.call('POST', 'device', token: token, body: {'devicePublicKey': await crypto.publicKeyOf(pair), 'label': label});
    await keys.setDeviceKey(pair);
  }

  Session _signedIn() => value.session ?? (throw const ApiError(401, 'Sign in first.'));

  // --- the flows --------------------------------------------------------------------------------------------------

  /// A new account on this device, and its recovery sheet (`signUp`).
  Future<Made> signUp(String handle, String password) async {
    final problem = handleProblem(handle) ?? passwordProblem(password);
    if (problem != null) throw ApiError(400, problem);
    final accountKey = await crypto.newAccountKey();
    final derived = await crypto.derive(password, passwordSalt(handle), iterations: iterations);
    final device = await crypto.newDeviceKey();
    final sheet = await crypto.newSheet(handle, accountKey, iterations: iterations);
    final answer = SignedIn.fromJson(await api.call('POST', 'signup', body: {
      'handle': handle.trim(),
      'loginSecret': derived.login,
      'wrapped': await crypto.wrap(accountKey, derived.wrapKey),
      'devicePublicKey': await crypto.publicKeyOf(device),
      'deviceLabel': label,
      'recovery': [for (final entry in sheet.entries) entry.toJson()],
    }));
    await keys.setAccountKey(await crypto.settle(accountKey));
    await keys.setDeviceKey(device);
    await _settle(answer.session);
    return Made(sheet.codes);
  }

  /// In with a password: the account key is unwrapped here and kept (`signIn`).
  Future<void> signIn(String handle, String password) async {
    final derived = await crypto.derive(password, passwordSalt(handle), iterations: iterations);
    final answer = SignedIn.fromJson(await api.call('POST', 'login', body: {'handle': handle.trim(), 'loginSecret': derived.login}));
    final wrapped = answer.wrapped;
    if (wrapped == null) throw const ApiError(500, 'The service answered without this account’s key.');
    final SealKey accountKey;
    try {
      accountKey = await crypto.unwrap(wrapped, derived.wrapKey);
    } catch (_) {
      throw const ApiError(500, 'This account’s key would not open with that password.');
    }
    await keys.setAccountKey(accountKey);
    await _enrolDevice(answer.token);
    await _settle(answer.session);
  }

  /// In with a recovery code, which is spent, and a new password set at once - the old one is presumably what was
  /// lost (`recover`). A code used is a code gone, so a fresh sheet is made too, and answered for the person to keep.
  Future<Made> recover(String handle, String code, String newPassword) async {
    final problem = passwordProblem(newPassword);
    if (problem != null) throw ApiError(400, problem);
    final derived = await crypto.derive(normaliseCode(code), recoverySalt(handle), iterations: iterations);
    final answer = SignedIn.fromJson(await api.call('POST', 'login/recovery', body: {'handle': handle.trim(), 'login': derived.login}));
    final wrapped = answer.wrapped;
    if (wrapped == null) throw const ApiError(500, 'The service answered without this account’s key.');
    final SealKey accountKey;
    try {
      accountKey = await crypto.unwrap(wrapped, derived.wrapKey, extractable: true);
    } catch (_) {
      throw const ApiError(500, 'This account’s key would not open with that code.');
    }
    final next = await crypto.derive(newPassword, passwordSalt(handle), iterations: iterations);
    await api.call('PUT', 'password', token: answer.token, body: {'loginSecret': next.login, 'wrapped': await crypto.wrap(accountKey, next.wrapKey)});
    final sheet = await crypto.newSheet(handle, accountKey, iterations: iterations);
    await api.call('POST', 'recovery', token: answer.token, body: {
      'codes': [for (final entry in sheet.entries) entry.toJson()],
    });
    await keys.setAccountKey(await crypto.settle(accountKey));
    await _enrolDevice(answer.token);
    await _settle(answer.session);
    return Made(sheet.codes);
  }

  /// The account key under a new password (`changePassword`). Needs the current one: the key has to be opened to be
  /// wrapped again.
  Future<void> changePassword(String current, String next) async {
    final session = _signedIn();
    final problem = passwordProblem(next);
    if (problem != null) throw ApiError(400, problem);
    final accountKey = await _openWithPassword(session, current);
    final derived = await crypto.derive(next, passwordSalt(session.handle), iterations: iterations);
    await api.call('PUT', 'password', token: session.token, body: {'loginSecret': derived.login, 'wrapped': await crypto.wrap(accountKey, derived.wrapKey)});
  }

  /// A new recovery sheet in place of the old (`newRecoveryCodes`). Needs the password, for the same reason.
  Future<Made> newRecoveryCodes(String password) async {
    final session = _signedIn();
    final accountKey = await _openWithPassword(session, password);
    final sheet = await crypto.newSheet(session.handle, accountKey, iterations: iterations);
    await api.call('POST', 'recovery', token: session.token, body: {
      'codes': [for (final entry in sheet.entries) entry.toJson()],
    });
    return Made(sheet.codes);
  }

  Future<SealKey> _openWithPassword(Session session, String password) async {
    final answer = await api.callMap('GET', 'keys', token: session.token);
    final wrapped = answer['wrapped'];
    final derived = await crypto.derive(password, passwordSalt(session.handle), iterations: iterations);
    try {
      return await crypto.unwrap(wrapped is String ? wrapped : '', derived.wrapKey, extractable: true);
    } catch (_) {
      throw const ApiError(401, 'That is not the password.');
    }
  }

  /// On launch (`resume`): the session renewed, and, if it had lapsed, renewed again with this device's own key -
  /// the way a signed-in phone stays signed in without anyone typing anything. A session that cannot be renewed
  /// either way is signed out, keys and all.
  Future<void> resume() async {
    final session = await keys.session();
    if (session == null) return _settle(null);
    try {
      final answer = SignedIn.fromJson(await api.call('POST', 'refresh', token: session.token));
      return await _settle(answer.session);
    } catch (failure) {
      // Offline, or the service is down: still signed in, as it was, until it can be asked.
      if (failure is! ApiError || failure.status != 401) return _settle(session);
    }
    final device = await keys.deviceKey();
    if (device != null) {
      try {
        final challenge = await api.callMap('POST', 'login/challenge', body: {'handle': session.handle});
        final nonce = challenge['nonce'] as String;
        final String signature;
        try {
          signature = await crypto.signNonce(device, nonce);
        } catch (_) {
          // A key that cannot sign is no key: refused here as the service would refuse it, and signed out below.
          throw const ApiError(401, 'This device could not be verified.');
        }
        final answer = SignedIn.fromJson(await api.call('POST', 'login/device', body: {'handle': session.handle, 'nonce': nonce, 'signature': signature}));
        return await _settle(answer.session);
      } catch (failure) {
        // Only the service's own no signs this device out. The network going between the refresh that said the
        // session had lapsed and the asking again says nothing about the key, and neither does a service that is
        // down or busy: still signed in, as it was, keys and all, until it can be asked. (The original signs out
        // here whatever went wrong; a phone on a train lost its keys to that.)
        if (!_refused(failure)) return _settle(session);
      }
    }
    await signOut();
  }

  /// Whether [failure] is the service saying no to who is asking: its 401 (what `login/device` answers a key the
  /// account does not have, and a nonce that took too long) or a 403. Anything else is not its word on the key: no
  /// answer at all, the service down (5xx) or busy (429), or a proxy's page in its place (an HTML 404).
  static bool _refused(Object failure) => failure is ApiError && (failure.status == 401 || failure.status == 403);

  /// The account deleted from the service, and everything it kept there (`deleteAccount`): the notes, settings,
  /// recordings and pictures synced to it, the links shared from it, its devices and its recovery codes. Needs the
  /// password, as a phone left unlocked shouldn't be able to lose its owner's account. Then signed out here, as the
  /// account is gone. The notes on this device stay; they are the person's own files.
  Future<void> deleteAccount(String password) async {
    final session = _signedIn();
    final derived = await crypto.derive(password, passwordSalt(session.handle), iterations: iterations);
    await api.call('DELETE', 'account', token: session.token, body: {'loginSecret': derived.login});
    await signOut();
  }

  /// Off this device: the session and every key (`signOut`). Notes on the device stay; only what made it an account
  /// goes.
  Future<void> signOut() async {
    await keys.setAccountKey(null);
    await keys.setDeviceKey(null);
    await keys.setEncryptionKey(null);
    await _settle(null);
  }
}
