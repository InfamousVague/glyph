/// The account's encryption key pair (docs/SHARED.md, S3), on this device. A port of
/// `src/app/core/account/encKey.ts`.
///
/// Read from the key store; else from the service, where the account's other device left it sealed under the
/// account key; else made here and registered. Two devices making one at once are settled by the service, which
/// keeps the first and answers the second 409 with it, so the second throws its own away and adopts the one that
/// stands. The pair is kept non-extractable, as the account key is.
///
/// `PUT account/key` is FIRST-WINS AND PERMANENT on the real service (docs/STAGE7.md): this is one of the calls a
/// development build must only ever make against the fake or a local server.
///
/// What differs: the page's context carries an optional `fetcher`; here it carries the [Api] and the
/// [AccountCrypto], which nothing has a default for.
library;

import 'api.dart';
import 'crypto_api.dart';
import 'keystore.dart';

/// The private half is sealed under the account key with this as its context (`CONTEXT`).
const String encryptionKeyContext = 'encryption-key';

/// What [ensureEncryptionKey] works with (`EncryptionKeyContext`).
class EncryptionKeyContext {
  const EncryptionKeyContext({required this.token, required this.accountKey, required this.keys, required this.api, required this.crypto});
  final String token;
  final SealKey accountKey;
  final KeyStore keys;
  final Api api;
  final AccountCrypto crypto;
}

/// This device's copy of the account's pair, with its public key as the service keeps it (`EncryptionKey` on the
/// web, where the crypto's own handle has that name here).
class KeptEncryptionKey {
  const KeptEncryptionKey({required this.pair, required this.pub});
  final EncryptionKey pair;
  final String pub;
}

/// A pair as the service holds it: `{ pub, sealed }`, or null for a body that is not one (`isRegistered`).
({String pub, String sealed})? _registered(Object? body) {
  if (body is! Map) return null;
  final pub = body['pub'], sealed = body['sealed'];
  return pub is String && sealed is String ? (pub: pub, sealed: sealed) : null;
}

Future<KeptEncryptionKey> _adopt(EncryptionKeyContext ctx, ({String pub, String sealed}) registered) async {
  final jwk = await ctx.crypto.open(ctx.accountKey, registered.sealed, encryptionKeyContext);
  if (jwk is! Map) throw const FormatException('The account’s key pair could not be read.');
  final pair = await ctx.crypto.importEncryptionKey(jwk.cast<String, Object?>());
  await ctx.keys.setEncryptionKey(pair);
  return KeptEncryptionKey(pair: pair, pub: registered.pub);
}

/// The pair, from wherever it is: this device, the service, or made now (`ensureEncryptionKey`).
Future<KeptEncryptionKey> ensureEncryptionKey(EncryptionKeyContext ctx) async {
  final crypto = ctx.crypto;
  final kept = await ctx.keys.encryptionKey();
  if (kept != null) return KeptEncryptionKey(pair: kept, pub: await crypto.encryptionPublicKeyOf(kept));
  try {
    final held = _registered(await ctx.api.call('GET', 'account/key', token: ctx.token));
    if (held == null) throw const ApiError(500, 'The service answered without the account’s key pair.');
    return await _adopt(ctx, held);
  } on ApiError catch (failure) {
    if (failure.status != 404) rethrow;
  }
  // None registered: this device makes one, and registers it with the private half sealed for the account's others.
  final made = await crypto.newEncryptionKey();
  final pub = await crypto.encryptionPublicKeyOf(made);
  final sealed = await crypto.seal(ctx.accountKey, await crypto.exportPrivateKey(made), encryptionKeyContext);
  try {
    await ctx.api.call('PUT', 'account/key', token: ctx.token, body: {'pub': pub, 'sealed': sealed});
  } on ApiError catch (failure) {
    // Another device registered first: its pair stands, and this one is forgotten.
    final theirs = failure.status == 409 ? _registered(failure.body) : null;
    if (theirs != null) return _adopt(ctx, theirs);
    rethrow;
  }
  final pair = await crypto.settleEncryptionKey(made);
  await ctx.keys.setEncryptionKey(pair);
  return KeptEncryptionKey(pair: pair, pub: pub);
}
