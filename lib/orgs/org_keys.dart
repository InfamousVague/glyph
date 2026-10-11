/// The organization key on this device (docs/SHARED.md, S2). A port of `src/app/core/orgs/orgKeys.ts`.
///
/// Fetched as this account's wrap and opened with its encryption key pair, made here when the organization has none
/// yet, and wrapped by this device for whichever members the service says lack one. **Held in memory for the
/// session, by organization, and nowhere else** (docs/STAGE7.md, "Device storage"); [OrgKeys.orgKeyOf] is what team
/// notes seal and open with.
///
/// The service arbitrates: a first generation posted when one already stands is answered 409 with the one in force,
/// and this device then reads its wrap instead. What the list already says (`OrgRow.keys`) spares the calls: an
/// organization whose generation this device holds, with nobody missing, is not asked about.
///
/// The key turns when a member goes (S11): the list says `stale`, and the next member device holding the generation
/// in force makes the one after it ([OrgKeys.turnOrgKey]), wrapped for everyone who remains, and re-seals the team's
/// notes under it (the team channel's, run by the engine). The generations before are kept for the session and read
/// from this account's older wraps on demand ([OrgKeys.orgKeyAt]), for a row sealed before a turn that no device has
/// re-sealed yet.
///
/// What differs:
/// - The page's module is [OrgKeys], made with the crypto and the [Api], and a [Listenable] where the page has
///   `onOrgKeys`.
/// - `wrapFor` and `unwrapWith` (core/orgs/wrap.ts) are the [AccountCrypto]'s, and WebCrypto's `importKey` is its
///   `importSealKey`; nothing here names an algorithm. The raw key is kept beside its handle for as long as it is
///   held, as on the page, since wrapping it for a member who joins needs the bytes.
library;

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import 'types.dart';

class _Held {
  _Held({required this.generation, required this.raw, required this.key, required this.older});
  final int generation;
  final Uint8List raw;
  final SealKey key;

  /// Earlier generations, as read from this account's wraps at them; null for one it has no wrap at.
  final Map<int, SealKey?> older;
}

/// The service's answer about one organization's key (`Keys`).
class _Keys {
  _Keys(Map<String, Object?> raw)
      : generation = raw['generation'] is num ? (raw['generation'] as num).toInt() : 0,
        mine = raw['mine'] is String ? raw['mine'] as String : null,
        missing = [
          if (raw['missing'] is List)
            for (final each in raw['missing'] as List)
              if (each is Map && each['handle'] is String && each['pub'] is String) (handle: each['handle'] as String, pub: each['pub'] as String),
        ];
  final int generation;
  final String? mine;
  final List<({String handle, String pub})> missing;
}

/// What the keys' step is handed (`OrgKeysContext`).
class OrgKeysContext {
  const OrgKeysContext({required this.token, this.api, required this.pair, this.list = const [], this.randomKey});
  final String token;

  /// The service through another fetcher; the [OrgKeys]' own when null.
  final Api? api;

  /// This account's encryption key pair.
  final EncryptionKey pair;

  /// The organizations as the list last said them: which need a look.
  final List<OrgRow> list;

  /// For tests: the key's bytes, instead of random ones.
  final Uint8List Function()? randomKey;
}

/// Whether an organization's key wants seeing to by this device now, from what the list says (`keyWork`): none made
/// yet, not in hand here (a wrap to read, or this account's key pair still to register so that one can be made), or
/// a member this device, holding the key, could wrap for.
bool keyWork(OrgRow row, {required bool held}) {
  if (row.state != 'member') return false;
  // Not held is always work: a wrap to read, or - none yet - this account's key pair to register so one can be made.
  return row.keys.generation == 0 || !held || row.keys.missing > 0;
}

/// The organizations' keys this device holds, for the session.
class OrgKeys extends ChangeNotifier {
  OrgKeys({required this.crypto, required this.api});

  final AccountCrypto crypto;
  final Api api;
  final Map<String, _Held> _held = {};

  /// The organization key as a key for sealing, if this device holds it (`orgKeyOf`).
  SealKey? orgKeyOf(String orgId) => _held[orgId]?.key;

  /// The generation this device holds for an organization: 0 for none (`orgKeyGeneration`).
  int orgKeyGeneration(String orgId) => _held[orgId]?.generation ?? 0;

  /// Forgotten, on signing out (`forgetOrgKeys`).
  void forgetOrgKeys() {
    _held.clear();
    notifyListeners();
  }

  Future<_Held> _hold(String orgId, int generation, Uint8List raw) async {
    final key = await crypto.importSealKey(raw);
    final was = _held[orgId];
    final older = <int, SealKey?>{...?was?.older};
    if (was != null && was.generation != generation) older[was.generation] = was.key;
    final entry = _Held(generation: generation, raw: raw, key: key, older: older);
    _held[orgId] = entry;
    notifyListeners();
    return entry;
  }

  static String _path(String orgId) => 'orgs/${Uri.encodeComponent(orgId)}/keys';

  /// The key at an older generation (S11; `orgKeyAt`): held from before a turn, or read now from this account's wrap
  /// at it; null where the account has none - a member who joined after that generation, who could never read what
  /// was sealed under it.
  Future<SealKey?> orgKeyAt(OrgKeysContext ctx, String orgId, int generation) async {
    final have = _held[orgId];
    if (have == null || generation < 1 || generation >= have.generation) return have?.generation == generation ? have?.key : null;
    if (have.older.containsKey(generation)) return have.older[generation];
    SealKey? key;
    try {
      final keys = _Keys(await (ctx.api ?? api).callMap('GET', '${_path(orgId)}?generation=$generation', token: ctx.token));
      final mine = keys.mine;
      if (mine != null) key = await crypto.importSealKey(await crypto.unwrapWith(ctx.pair, mine, wrapContext(orgId, generation)));
    } catch (_) {
      // Not readable now: asked again next time.
      return null;
    }
    have.older[generation] = key;
    return key;
  }

  /// Whether the key owes a turn this device can make (`turnDue`): the list says so, and this device holds the
  /// generation in force.
  bool turnDue(OrgRow row) {
    final have = _held[row.id];
    return row.keys.stale && have != null && have.generation == row.keys.generation;
  }

  Uint8List _fresh(Uint8List Function()? randomKey) => randomKey != null ? randomKey() : crypto.randomBytes(32);

  /// The next generation, made here and wrapped for every member who remains and has a public key, brought into
  /// force and held; the one before stays for the session, for what is not yet re-sealed (`turnOrgKey`). Null when
  /// another member's device made it first (its wrap is read on the next pass) or when nobody could be wrapped for.
  /// [pair] is not needed to turn; the context carries it for the calls that read.
  Future<int?> turnOrgKey(String orgId, List<Member> members, {required String token, Api? api, Uint8List Function()? randomKey}) async {
    final have = _held[orgId];
    if (have == null) return null;
    final generation = have.generation + 1;
    final raw = _fresh(randomKey);
    final wraps = <Map<String, Object?>>[];
    for (final member in members) {
      final pub = member.pub;
      if (member.state != 'member' || pub == null || pub.isEmpty) continue;
      wraps.add({'handle': member.handle, 'wrapped': await crypto.wrapFor(pub, raw, wrapContext(orgId, generation))});
    }
    if (wraps.isEmpty) return null;
    try {
      await (api ?? this.api).call('POST', _path(orgId), token: token, body: {'generation': generation, 'make': true, 'wraps': wraps});
    } on ApiError catch (failure) {
      if (failure.status == 409) return null;
      rethrow;
    }
    await _hold(orgId, generation, raw);
    return generation;
  }

  Future<List<Map<String, Object?>>> _wraps(String orgId, int generation, Uint8List raw, List<({String handle, String pub})> missing) async => [
        for (final (:handle, :pub) in missing) {'handle': handle, 'wrapped': await crypto.wrapFor(pub, raw, wrapContext(orgId, generation))},
      ];

  /// One organization's key seen to: read, made, or filled for the missing (`settle`).
  Future<void> _settle(OrgKeysContext ctx, String orgId) async {
    final service = ctx.api ?? api;
    final path = _path(orgId);
    var keys = _Keys(await service.callMap('GET', path, token: ctx.token));
    if (keys.generation == 0) {
      // Nothing made yet: this device makes the first generation and wraps it for everyone who can be wrapped for.
      final raw = _fresh(ctx.randomKey);
      try {
        await service.call('POST', path, token: ctx.token, body: {'generation': 1, 'make': true, 'wraps': await _wraps(orgId, 1, raw, keys.missing)});
        await _hold(orgId, 1, raw);
        return;
      } on ApiError catch (failure) {
        // Another member's device made one first: that one stands, and this device's wrap is read below.
        if (failure.status != 409) rethrow;
        keys = _Keys(await service.callMap('GET', path, token: ctx.token));
      }
    }
    final have = _held[orgId];
    var entry = have != null && have.generation == keys.generation ? have : null;
    if (entry == null) {
      // No wrap for this account yet: another member's device will make one on its next pass, and this one reads it
      // then.
      final mine = keys.mine;
      if (mine == null) return;
      entry = await _hold(orgId, keys.generation, await crypto.unwrapWith(ctx.pair, mine, wrapContext(orgId, keys.generation)));
    }
    if (keys.missing.isNotEmpty) {
      await service.call('POST', path, token: ctx.token, body: {'generation': keys.generation, 'wraps': await _wraps(orgId, keys.generation, entry.raw, keys.missing)});
    }
  }

  /// The step of the sync pass (`syncOrgKeys`): every organization the account is a member of seen to, those the
  /// list says are in hand skipped. An organization that fails is left for the next pass; a service without the
  /// routes yet stops the step.
  Future<void> syncOrgKeys(OrgKeysContext ctx) async {
    for (final row in ctx.list) {
      if (row.state != 'member') continue;
      final have = _held[row.id];
      if (have != null && have.generation == row.keys.generation && row.keys.missing == 0) continue;
      try {
        await _settle(ctx, row.id);
      } catch (failure) {
        if (notYet(failure)) return;
      }
    }
    // Organizations the account has left take their keys with them.
    final members = {for (final row in ctx.list) if (row.state == 'member') row.id};
    _held.removeWhere((orgId, _) => !members.contains(orgId));
  }
}
