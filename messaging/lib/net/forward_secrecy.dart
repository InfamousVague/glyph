import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'crypto.dart';
import 'fast_gcm.dart';

/// Forward secrecy for what goes between friends, and between an account's own devices (GMFB-26, from the Uplink gap
/// review: "Forward secrecy and key rotation for friends and circles"). docs/FORWARD_SECRECY.md is the whole design;
/// this is its working part.
///
/// **Why it is needed.** Until now a packet to a friend was sealed with the pair's key (NetCrypto.netKey), which comes
/// from the two accounts' long-term keys alone, and a copy to the account's own devices with a key from the account's
/// words (Me.mineKey). Whoever later learns the words, or takes a device, and has kept the packets (the relay, or
/// anyone on the way) could open every one of them, back to the first.
///
/// **What is done instead.** Each device makes a key pair of its own (a "prekey") that is never written into the
/// account's backup and can't be worked out from the account's words. It makes a new one every [rotateEvery], and
/// deletes each one's private half [keepFor] after making it. It offers its newest to everyone it talks to, inside the
/// sealed envelopes it sends (Envelope.fs), so no server is needed and a relay that knows nothing of this carries it.
///
/// A packet to someone whose devices have offered a prekey is sealed under a fresh key pair made for that packet alone
/// and forgotten once it is sealed: for each of their devices, ECDH of the one-off key with that device's prekey,
/// through HKDF salted with the pair's key, wraps a random key the envelope is sealed with. So opening it needs a
/// prekey's private half (deleted after [keepFor]) or the one-off key's (never kept): the account's words and the
/// long-term key are not enough. The pair's key in the salt is what says who sent it, as before.
///
/// One account is the same identity on several devices, and the relay hands a packet for an id to every device of
/// it that is connected, or keeps it for whichever comes first. So a packet carries one wrapped key per device of the
/// account that has offered a prekey, and any of them can open it; a device's own copies to its siblings (GMFB-21)
/// are sealed the same way, to the siblings' prekeys.
///
/// Wire layout of a forward-secret packet's last field (Packet flag 4):
///
///     [1: how many devices, n][33: the one-off public key]
///     n × [16: the device's name][4: its prekey's name][60: the content key, sealed: 12 nonce, 32, 16 tag]
///     [the envelope, sealed with the content key: 12 nonce, the bytes, 16 tag]
///
/// Each entry's key: HKDF-SHA256(salt: the pair's key, ikm: ECDH(one-off, prekey), info: "ghost fs v1 wrap" | from |
/// to | device | prekey | one-off public). The envelope is sealed with AES-256-GCM under the content key, with every
/// byte before it, from and to as its additional data, so no entry can be swapped for another's.
class ForwardSecrecy {
  ForwardSecrecy({required this.device, required FsStore secrets, required FsStore plain, DateTime Function()? now})
      : _secrets = secrets,
        _plain = plain,
        _now = now ?? DateTime.now {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(device)) throw ArgumentError('a device is named by 32 hex digits');
  }

  /// This device's name among its identity's devices (HubCarrier.device): 32 hex digits.
  final String device;
  final FsStore _secrets;
  final FsStore _plain;
  final DateTime Function() _now;

  /// How often a device makes a new prekey.
  static const rotateEvery = Duration(days: 1);

  /// How long after a prekey is made others still seal to it, where they have heard nothing newer. Past this a
  /// packet to that device goes sealed the old way (and its answer brings the newer prekey).
  static const useFor = Duration(days: 7);

  /// How long after it is made a prekey's private half is kept: [useFor], then the relay's longest hold (7 days,
  /// relay/lib/hub.dart holdFor) and a day more. Deleted after; what was sealed to it can't be opened by anyone.
  static const keepFor = Duration(days: 15);

  /// The most devices of one identity kept for it; the ones heard from longest ago go first.
  static const mostDevices = 8;

  /// The most one-off keys remembered, to tell a packet seen before ([open]'s replay).
  static const mostSeen = 5000;

  static const secretsName = 'fs_prekeys';
  static const peersName = 'fs_peers';
  static const seenName = 'fs_seen';
  static const oldName = 'fs_old';

  /// How long a packet sealed the old way without a prekey (a build from before, or a device whose forward secrecy
  /// couldn't load) from an id is taken to mean that id has such a device: everything to it is sealed the old way
  /// too, so that device can read it (GMFB-26 review, finding 2).
  static const oldDeviceFor = Duration(days: 7);

  /// Whether sealing and opening run on an isolate of their own, off the one that draws the screens (finding 9).
  static bool offThread = true;

  static final _wrapInfo = utf8.encode('ghost fs v1 wrap');
  static final _wrapAad = Uint8List.fromList(utf8.encode('ghost fs v1 key'));
  static final _bodyAad = utf8.encode('ghost fs v1');
  static const _entry = 16 + 4 + 60;

  final List<_Prekey> _mine = [];
  final Map<String, Map<String, FsBundle>> _peers = {};

  /// One-off keys of packets opened (a tag of each), by the prekey they came under: dropped with it.
  final LinkedHashMap<String, String> _seen = LinkedHashMap();

  /// When a packet sealed the old way, with no prekey in it, last came from each id (ms).
  final Map<String, int> _old = {};
  bool _loaded = false;
  Future<void>? _refreshing;
  Timer? _seenTimer;

  bool get loaded => _loaded;

  /// [load], answering whether it worked instead of throwing: the app tries again until it does (an iPhone's Keychain
  /// can't be read before its first unlock).
  Future<bool> tryLoad() async {
    if (_loaded) return true;
    try {
      await load();
      return true;
    } catch (_) {
      _loaded = false;
      return false;
    }
  }

  /// Reads what is kept. Throws where the secret store can't be read: nothing is sealed for forward secrecy until it
  /// can be, rather than make keys it can't keep.
  Future<void> load() async {
    final kept = await _secrets.read(secretsName);
    _mine.clear();
    if (kept != null && kept.isNotEmpty) {
      for (final j in jsonDecode(kept) as List) {
        final p = _Prekey.fromJson(j);
        if (p != null) _mine.add(p);
      }
    }
    _peers.clear();
    try {
      final j = jsonDecode(await _plain.read(peersName) ?? '{}') as Map;
      for (final e in j.entries) {
        final devices = <String, FsBundle>{};
        if (e.value is Map) {
          for (final b in (e.value as Map).values) {
            final bundle = FsBundle.fromJson(b);
            if (bundle != null) devices[bundle.device] = bundle;
          }
        }
        if (devices.isNotEmpty) _peers['${e.key}'] = devices;
      }
    } catch (_) {}
    _seen.clear();
    try {
      final j = jsonDecode(await _plain.read(seenName) ?? '[]') as List;
      for (final x in j) {
        if (x is List && x.length == 2 && x[0] is String && x[1] is String) _seen[x[0] as String] = x[1] as String;
      }
    } catch (_) {}
    _old.clear();
    try {
      for (final e in (jsonDecode(await _plain.read(oldName) ?? '{}') as Map).entries) {
        if (e.value is int) _old['${e.key}'] = e.value as int;
      }
    } catch (_) {}
    _loaded = true;
    await refresh();
  }

  /// Deletes prekeys past [keepFor] and makes a new one where the newest is [rotateEvery] old. The new one is kept
  /// before it is offered to anyone.
  Future<void> refresh() {
    final running = _refreshing;
    if (running != null) return running;
    final f = _refresh();
    _refreshing = f;
    return f.whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    if (!_loaded) return;
    final now = _now().millisecondsSinceEpoch;
    final gone = _mine.where((p) => now - p.made >= keepFor.inMilliseconds).toList();
    final next = [for (final p in _mine) if (!gone.contains(p)) p];
    var changed = gone.isNotEmpty;
    final newest = next.isEmpty ? null : next.reduce((a, b) => b.made > a.made ? b : a);
    if (newest == null || now - newest.made >= rotateEvery.inMilliseconds || newest.made > now + const Duration(days: 1).inMilliseconds) {
      String id;
      do {
        id = NetCrypto.hex(NetCrypto.randomBytes(4));
      } while (next.any((p) => p.id == id));
      next.add(_Prekey(id, NetKeys.generate(), now));
      changed = true;
    }
    if (!changed) return;
    // Kept first: a prekey is never offered, nor an old one forgotten here, until the secret store has the new list. If
    // the write fails, nothing changes (and an expired prekey is still not used: [open] checks its age).
    await _secrets.write(secretsName, jsonEncode([for (final p in next) p.toJson()]));
    _mine
      ..clear()
      ..addAll(next);
    if (gone.isNotEmpty) {
      final ids = {for (final p in gone) p.id};
      _seen.removeWhere((_, prekey) => ids.contains(prekey));
      _saveSeenSoon();
    }
  }

  _Prekey? get _newest => _mine.isEmpty ? null : _mine.reduce((a, b) => b.made > a.made ? b : a);

  /// Whether a prekey needs making or deleting now: [refresh] has work.
  bool get due {
    final now = _now().millisecondsSinceEpoch, newest = _newest;
    return newest == null || now - newest.made >= rotateEvery.inMilliseconds || _mine.any((p) => now - p.made >= keepFor.inMilliseconds);
  }

  /// What this device offers: its newest prekey's public half. Null before [load].
  FsBundle? get bundle {
    final p = _newest;
    return p == null ? null : FsBundle(device: device, prekey: p.id, key: p.keys.public, made: p.made);
  }

  /// The names of the prekeys this device still holds the private half of, for a test.
  List<String> get heldPrekeys => [for (final p in _mine) p.id];

  /// Takes a prekey [said] by a device of [peer] (an id): the sealed envelope it came in is what says it is theirs.
  /// One of this device's own is passed over. True where it is newer than what was held for that device.
  bool heard(String peer, Object? said) {
    final b = FsBundle.fromJson(said);
    if (b == null || b.device == device) return false;
    final now = _now().millisecondsSinceEpoch;
    // A prekey made, by its maker's clock, more than a day ahead of this one's is not believed: it would be sealed to
    // for longer than its maker keeps it.
    if (b.made > now + const Duration(days: 1).inMilliseconds) return false;
    final devices = _peers[peer] ??= {};
    final had = devices[b.device];
    if (had != null && had.made >= b.made) return false;
    devices[b.device] = b;
    while (devices.length > mostDevices) {
      devices.remove(devices.values.reduce((x, y) => y.made < x.made ? y : x).device);
    }
    unawaited(_savePeers());
    return true;
  }

  /// Whether any device of [peer] has offered a prekey this build may seal to now.
  bool canSealTo(String peer) => targets(peer).isNotEmpty;

  /// Notes that a packet sealed the old way with no prekey in it came from [peer] by a route that carries prekeys: they
  /// have a device without forward secrecy.
  void sawOld(String peer) {
    final now = _now().millisecondsSinceEpoch;
    final had = _old[peer];
    _old[peer] = now;
    // Written at most once an hour per id: it is a matter of days.
    if (had == null || now - had > const Duration(hours: 1).inMilliseconds) unawaited(_plain.write(oldName, jsonEncode(_old)));
  }

  /// Whether what goes to [peer] must be sealed the old way, so every device of theirs can read it: one of their
  /// devices sent without forward secrecy within [oldDeviceFor], or one has gone quiet past [useFor] (its prekey may
  /// be sealed to no longer) without yet being forgotten at [keepFor]. Never silently leaving a device out (finding 1).
  bool needsOld(String peer) {
    final now = _now().millisecondsSinceEpoch;
    final old = _old[peer];
    if (old != null && now - old < oldDeviceFor.inMilliseconds) return true;
    return (_peers[peer] ?? const <String, FsBundle>{}).values.any((b) => b.device != device && now - b.made >= useFor.inMilliseconds && now - b.made < keepFor.inMilliseconds);
  }

  /// The devices of [peer] a packet to them is sealed for: each one's newest prekey that is younger than [useFor].
  List<FsBundle> targets(String peer) {
    final now = _now().millisecondsSinceEpoch;
    return [
      for (final b in (_peers[peer] ?? const <String, FsBundle>{}).values)
        if (b.device != device && now - b.made < useFor.inMilliseconds) b,
    ]..sort((a, b) => a.device.compareTo(b.device));
  }

  /// Forgets every device of [peer].
  void forget(String peer) {
    if (_peers.remove(peer) != null) unawaited(_savePeers());
  }

  /// [clear] sealed from [from] to [to] (ids) for [targets], under the pair's key [pairKey]. The one-off key is made
  /// here and dropped as this returns.
  static Uint8List seal({required String from, required String to, required List<int> pairKey, required List<int> clear, required List<FsBundle> targets}) {
    if (targets.isEmpty || targets.length > 255) throw ArgumentError('sealed for 1 to 255 devices');
    final once = NetKeys.generate();
    final content = NetCrypto.randomBytes(32);
    final fromB = NetCrypto.unhex(from), toB = NetCrypto.unhex(to);
    final head = BytesBuilder(copy: false)
      ..addByte(targets.length)
      ..add(once.public);
    for (final t in targets) {
      final shared = NetCrypto.agree(once, t.key);
      if (shared == null) throw ArgumentError('a prekey that is no key');
      final deviceB = NetCrypto.unhex(t.device), prekeyB = NetCrypto.unhex(t.prekey);
      final k = NetCrypto.hkdf(salt: pairKey, ikm: shared, info: [..._wrapInfo, ...fromB, ...toB, ...deviceB, ...prekeyB, ...once.public]);
      final nonce = NetCrypto.randomBytes(12);
      head
        ..add(deviceB)
        ..add(prekeyB)
        ..add(nonce)
        ..add(FastGcm(k).seal(nonce, _wrapAad, content));
    }
    final header = head.toBytes();
    final nonce = NetCrypto.randomBytes(12);
    final body = FastGcm(content).seal(nonce, Uint8List.fromList([..._bodyAad, ...fromB, ...toB, ...header]), Uint8List.fromList(clear));
    return Uint8List.fromList([...header, ...nonce, ...body]);
  }

  /// [seal], on an isolate of its own where [offThread]: a packet for several devices is several EC multiplications.
  static Future<Uint8List> sealAway({required String from, required String to, required List<int> pairKey, required List<int> clear, required List<FsBundle> targets}) {
    if (!offThread) return Future.value(seal(from: from, to: to, pairKey: pairKey, clear: clear, targets: targets));
    final key = Uint8List.fromList(pairKey), bytes = Uint8List.fromList(clear), list = List<FsBundle>.of(targets);
    return Isolate.run(() => seal(from: from, to: to, pairKey: key, clear: bytes, targets: list));
  }

  /// [open], with its EC multiplication on an isolate of its own where [offThread].
  Future<FsOpened> openAway({required String from, required String to, required List<int> pairKey, required List<int> payload}) async {
    final found = _find(payload);
    if (found.result != null) return FsOpened(found.result!);
    final bytes = Uint8List.fromList(payload);
    final args = (scalar: found.prekey!.keys.scalar, device: device, from: from, to: to, key: Uint8List.fromList(pairKey), payload: bytes, at: found.at!, head: found.headLength!);
    final clear = offThread ? await _unwrapAway(args) : _unwrap(args.scalar, args.device, from, to, args.key, bytes, args.at, args.head);
    return _finish(clear, found.prekey!, bytes);
  }

  /// [_unwrap] on an isolate of its own: static, so the closure holds nothing but [a].
  static Future<Uint8List?> _unwrapAway(({Uint8List scalar, String device, String from, String to, Uint8List key, Uint8List payload, int at, int head}) a) =>
      Isolate.run(() => _unwrap(a.scalar, a.device, a.from, a.to, a.key, a.payload, a.at, a.head));

  /// Opens [payload], sealed from [from] to [to] under the pair's key [pairKey], with this device's prekeys.
  FsOpened open({required String from, required String to, required List<int> pairKey, required List<int> payload}) {
    final found = _find(payload);
    if (found.result != null) return FsOpened(found.result!);
    return _finish(_unwrap(found.prekey!.keys.scalar, device, from, to, pairKey, payload, found.at!, found.headLength!), found.prekey!, payload);
  }

  ({FsResult? result, _Prekey? prekey, int? at, int? headLength}) _find(List<int> payload) {
    if (payload.length < 1 + 33 + 28) return (result: FsResult.bad, prekey: null, at: null, headLength: null);
    final n = payload[0];
    final headLength = 1 + 33 + n * _entry;
    if (n == 0 || payload.length < headLength + 28) return (result: FsResult.bad, prekey: null, at: null, headLength: null);
    final mine = NetCrypto.unhex(device);
    int? at;
    for (var i = 0; i < n; i++) {
      final o = 34 + i * _entry;
      if (_same(payload, o, mine)) {
        at = o;
        break;
      }
    }
    if (at == null) return (result: FsResult.notForThisDevice, prekey: null, at: null, headLength: null);
    final prekeyName = NetCrypto.hex(payload.sublist(at + 16, at + 20));
    final now = _now().millisecondsSinceEpoch;
    final prekey = _mine.where((p) => p.id == prekeyName && now - p.made < keepFor.inMilliseconds).firstOrNull;
    if (prekey == null) return (result: FsResult.noPrekey, prekey: null, at: null, headLength: null);
    return (result: null, prekey: prekey, at: at, headLength: headLength);
  }

  static Uint8List? _unwrap(Uint8List scalar, String device, String from, String to, List<int> pairKey, List<int> payload, int at, int headLength) {
    final onceKey = payload.sublist(1, 34);
    final shared = NetCrypto.agree(NetKeys.fromScalar(scalar), onceKey);
    if (shared == null) return null;
    final mine = NetCrypto.unhex(device);
    final fromB = NetCrypto.unhex(from), toB = NetCrypto.unhex(to);
    final k = NetCrypto.hkdf(salt: pairKey, ikm: shared, info: [..._wrapInfo, ...fromB, ...toB, ...mine, ...payload.sublist(at + 16, at + 20), ...onceKey]);
    try {
      final content = FastGcm(k).open(Uint8List.fromList(payload.sublist(at + 20, at + 32)), _wrapAad, Uint8List.fromList(payload.sublist(at + 32, at + _entry)));
      if (content == null || content.length != 32) return null;
      final header = payload.sublist(0, headLength);
      return FastGcm(content).open(Uint8List.fromList(payload.sublist(headLength, headLength + 12)), Uint8List.fromList([..._bodyAad, ...fromB, ...toB, ...header]), Uint8List.fromList(payload.sublist(headLength + 12)));
    } catch (_) {
      return null;
    }
  }

  FsOpened _finish(Uint8List? clear, _Prekey prekey, List<int> payload) {
    if (clear == null) return const FsOpened(FsResult.bad);
    final onceKey = payload.sublist(1, 34);
    // Seen before: the same one-off key, so the same packet, come again (a replay, or a second route's copy).
    final tag = NetCrypto.hex(NetCrypto.sha256(onceKey).sublist(0, 8));
    if (_seen.containsKey(tag)) return FsOpened(FsResult.replay, clear: clear);
    _seen[tag] = prekey.id;
    while (_seen.length > mostSeen) {
      _seen.remove(_seen.keys.first);
    }
    _saveSeenSoon();
    return FsOpened(FsResult.opened, clear: clear);
  }

  static bool _same(List<int> bytes, int at, List<int> want) {
    for (var i = 0; i < want.length; i++) {
      if (bytes[at + i] != want[i]) return false;
    }
    return true;
  }

  Future<void> _savePeers() => _plain.write(peersName, jsonEncode({for (final e in _peers.entries) e.key: {for (final b in e.value.values) b.device: b.toJson()}}));

  void _saveSeenSoon() {
    _seenTimer ??= Timer(const Duration(seconds: 2), () => unawaited(flush()));
  }

  /// Writes what is waiting to be written now (the seen one-off keys), for a test and for closing.
  Future<void> flush() async {
    _seenTimer?.cancel();
    _seenTimer = null;
    await _plain.write(seenName, jsonEncode([for (final e in _seen.entries) [e.key, e.value]]));
  }

  /// Deletes everything: this device's prekeys and what it knows of others'. For signing out.
  Future<void> wipe() async {
    _mine.clear();
    _peers.clear();
    _seen.clear();
    _old.clear();
    _seenTimer?.cancel();
    _seenTimer = null;
    await _secrets.write(secretsName, '');
    await _plain.write(peersName, '');
    await _plain.write(seenName, '');
    await _plain.write(oldName, '');
  }
}

/// Where [ForwardSecrecy] keeps things: a secret store for this device's prekeys (the Keychain, Android's vault), and
/// an ordinary one for what others offered and what was seen.
abstract class FsStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
}

/// An [FsStore] in memory, for a test.
class MemoryFsStore implements FsStore {
  final Map<String, String> kept = {};
  int writes = 0;
  @override
  Future<String?> read(String name) async => kept[name];
  @override
  Future<void> write(String name, String value) async {
    writes++;
    kept[name] = value;
  }
}

/// A device's prekey, as it offers it: whose device, which prekey, its public half (33 bytes), when it was made.
class FsBundle {
  const FsBundle({required this.device, required this.prekey, required this.key, required this.made});
  final String device;
  final String prekey;
  final Uint8List key;
  final int made;

  Map<String, dynamic> toJson() => {'d': device, 'p': prekey, 'k': base64Encode(key), 'm': made};

  static FsBundle? fromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['d'], p = j['p'], k = j['k'], m = j['m'];
    if (d is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(d) || p is! String || !RegExp(r'^[0-9a-f]{8}$').hasMatch(p) || k is! String || m is! int) return null;
    try {
      final key = base64Decode(k);
      if (key.length != 33 || (key[0] != 2 && key[0] != 3)) return null;
      return FsBundle(device: d, prekey: p, key: key, made: m);
    } catch (_) {
      return null;
    }
  }
}

class _Prekey {
  _Prekey(this.id, this.keys, this.made);
  final String id;
  final NetKeys keys;
  final int made;

  Map<String, Object> toJson() => {'i': id, 's': NetCrypto.hex(keys.scalar), 'm': made};

  static _Prekey? fromJson(Object? j) {
    if (j is! Map) return null;
    final i = j['i'], s = j['s'], m = j['m'];
    if (i is! String || s is! String || s.length != 64 || m is! int) return null;
    try {
      return _Prekey(i, NetKeys.fromScalar(NetCrypto.unhex(s)), m);
    } catch (_) {
      return null;
    }
  }
}

/// What became of opening a forward-secret packet.
enum FsResult {
  /// Opened, for the first time.
  opened,

  /// Opened, and seen before: passed over, answered at most.
  replay,

  /// It carries no key for this device: sealed before the sender heard of it.
  notForThisDevice,

  /// For this device, under a prekey it no longer holds (deleted, or from before a reinstall).
  noPrekey,

  /// Changed, cut short, or not from whom it says.
  bad,
}

class FsOpened {
  const FsOpened(this.result, {this.clear});
  final FsResult result;
  final Uint8List? clear;
}
