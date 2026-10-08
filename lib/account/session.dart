/// What makes a device a signed-in one, as values: the session, and what the app shows of the account. The shapes of
/// `src/app/core/account/keystore.ts` (`Session`) and `src/app/core/account/account.ts` (`AccountState`), with the
/// one seam everything else reads the account through ([AccountSource]).
///
/// What differs: the web's modules read the account by importing `accountState`, `accountKey` and `onAccount` from
/// account.ts, and its tests swap that module out (`vi.mock`). Here those three are an interface, [AccountSource],
/// which [Account] (account.dart) is and a test writes in a few lines; the notifications feed, the comments' author
/// and a version's keeper take one.
library;

import 'package:flutter/foundation.dart';

import 'crypto_api.dart';

/// A session with the service (`Session`): the token, and whose it is.
@immutable
class Session {
  const Session({required this.token, required this.handle, required this.accountId});

  /// A session as kept, only when it is whole (`readSession`'s check): a token, a handle and a numeric id, and
  /// nothing else carried over. Null for anything less.
  static Session? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final token = raw['token'], handle = raw['handle'], accountId = raw['accountId'];
    if (token is! String || handle is! String || accountId is! num) return null;
    return Session(token: token, handle: handle, accountId: accountId.toInt());
  }

  final String token;
  final String handle;
  final int accountId;

  Map<String, Object?> toJson() => {'token': token, 'handle': handle, 'accountId': accountId};

  @override
  bool operator ==(Object other) => other is Session && other.token == token && other.handle == handle && other.accountId == accountId;

  @override
  int get hashCode => Object.hash(token, handle, accountId);

  @override
  String toString() => 'Session($handle, $accountId)';
}

/// What the app shows of the account on this device (`AccountState`).
@immutable
class AccountState {
  const AccountState({this.session, this.unlocked = false});

  /// Signed out, with no key.
  static const AccountState none = AccountState();

  final Session? session;

  /// Whether this device holds the account key, and so can read and write synced notes.
  final bool unlocked;

  @override
  bool operator ==(Object other) => other is AccountState && other.session == session && other.unlocked == unlocked;

  @override
  int get hashCode => Object.hash(session, unlocked);

  @override
  String toString() => 'AccountState($session, unlocked: $unlocked)';
}

/// The account, as the rest of the app reads it: who is signed in (`accountState().session`), the key that opens
/// what is synced (`accountKey()`), and a way to hear either change (`onAccount`, as a [Listenable]).
abstract interface class AccountSource implements Listenable {
  /// The session now; null signed out.
  Session? get session;

  /// The account key, for sync: null when this device has none.
  Future<SealKey?> accountKey();
}
