import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'p256.dart';
import 'sha256.dart';

/// A home record: where an account lives, signed by the account (docs/OPEN_NETWORK.md, section 1; Matt, 2026-11-22:
/// "I'd like the relays to be able to talk to each other"). It is the one thing a relay believes about where someone
/// is: nobody's say-so, the account's own key over these bytes.
///
///     {"v":1, "a": account name, "k": public key (33 bytes, base64), "h": [1 to 3 relay addresses],
///      "n": a count that only goes up, "t": made (ms), "s": signature (r then s, base64)}
///
/// What is signed ([signedBytes]): the words `ghost-home v1` and a newline, then the name (16 bytes), the count (4
/// bytes, big end first), the time (8 bytes), how many addresses (1 byte), and each address as its length (1 byte)
/// and its bytes. The app makes and checks the same bytes (lib/net/home_record.dart), and both are held to
/// test/home_record_vectors.json.
///
/// An address is a hub's (`wss://host/hub`), or a relay hosted from an app's (`ghost-relay://<relay name>?n=<node
/// id>&via=<the public relay it stays linked to>`): [HomeAddress].
class HomeRecord {
  HomeRecord._(this.a, this.k, this.h, this.n, this.t, this.s);

  /// The account's name: the first 16 bytes of the SHA-256 of [k], in hex.
  final String a;

  /// The account's public key, 33 bytes.
  final Uint8List k;

  /// Where it lives, as it wrote them.
  final List<String> h;

  /// The count: of two records for one account the higher is the one believed.
  final int n;

  /// When it was made, in milliseconds.
  final int t;

  /// The account's signature over [signedBytes]: r then s, 64 bytes.
  final Uint8List s;

  static const words = 'ghost-home v1\n';
  static const maxAddresses = 3;
  static const maxAddress = 200;
  static const maxCount = 0xffffffff;

  /// The furthest ahead of this relay's clock a record's time may be: a clock a little fast is forgiven, a record
  /// dated next year is not.
  static const ahead = Duration(minutes: 5);

  /// The longest a record is as JSON: what a store of them is counted by.
  static const maxJson = 1100;

  static final _hex32 = RegExp(r'^[0-9a-f]{32}$');

  /// Printable ASCII and nothing else: an address is compared and logged as it is.
  static bool _plain(String s) => s.isNotEmpty && s.length <= maxAddress && s.codeUnits.every((c) => c > 0x20 && c < 0x7f);

  /// What an account signs to say it lives at [h], as record number [n], made at [t].
  static Uint8List signedBytes({required String a, required int n, required int t, required List<String> h}) {
    final out = BytesBuilder()
      ..add(utf8.encode(words))
      ..add([for (var i = 0; i < 32; i += 2) int.parse(a.substring(i, i + 2), radix: 16)])
      ..add((ByteData(4)..setUint32(0, n)).buffer.asUint8List())
      ..add((ByteData(8)..setUint64(0, t)).buffer.asUint8List())
      ..addByte(h.length);
    for (final address in h) {
      final bytes = ascii.encode(address);
      out
        ..addByte(bytes.length)
        ..add(bytes);
    }
    return out.toBytes();
  }

  /// The record [json] is, where every part of it is as the plan lays it out and the signature is the account's own;
  /// else why not, in a word (`shape`, `name`, `addresses`, `count`, `time`, `future`, `signature`).
  ///
  /// [verify] false passes over the signature and the time: for what this relay checked before it kept it.
  static ({HomeRecord? rec, String? err}) read(Object? json, {required DateTime now, bool verify = true}) {
    ({HomeRecord? rec, String? err}) no(String why) => (rec: null, err: why);
    if (json is! Map || json['v'] != 1) return no('shape');
    final a = json['a'], k = json['k'], h = json['h'], n = json['n'], t = json['t'], s = json['s'];
    if (a is! String || k is! String || h is! List || s is! String || k.length > 64 || s.length > 128) return no('shape');
    final Uint8List key, sig;
    try {
      key = base64Decode(k);
      sig = base64Decode(s);
    } catch (_) {
      return no('shape');
    }
    if (!_hex32.hasMatch(a) || key.length != 33 || sig.length != 64) return no('shape');
    if (hexOf(sha256(key).sublist(0, 16)) != a) return no('name');
    if (h.isEmpty || h.length > maxAddresses || !h.every((x) => x is String && _plain(x))) return no('addresses');
    if (n is! int || n < 1 || n > maxCount) return no('count');
    if (t is! int || t < 0 || t > 0x1fffffffffffff) return no('time');
    final addresses = List<String>.unmodifiable(h.cast<String>());
    if (verify) {
      if (t > now.add(ahead).millisecondsSinceEpoch) return no('future');
      if (!P256.verify(key, signedBytes(a: a, n: n, t: t, h: addresses), sig)) return no('signature');
    }
    return (rec: HomeRecord._(a, key, addresses, n, t, sig), err: null);
  }

  Map<String, Object> toJson() => {'v': 1, 'a': a, 'k': base64Encode(k), 'h': h, 'n': n, 't': t, 's': base64Encode(s)};

  /// The addresses a relay can read, in the record's order; one it can't read is passed over.
  late final List<HomeAddress> addresses = [for (final x in h) ?HomeAddress.parse(x)];

  /// Whether [other] is this very record: the same account, count and signature.
  bool same(HomeRecord other) => a == other.a && n == other.n && _equal(s, other.s);

  static bool _equal(List<int> x, List<int> y) {
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}

/// One address of a home record as a relay reads it: a hub's, or a relay hosted from an app's.
class HomeAddress {
  const HomeAddress.hub(String this.url)
      : relay = null,
        via = null;
  const HomeAddress.hosted(String this.relay, this.via) : url = null;

  /// A hub's address, as two relays compare them ([canonicalHub]); null for a hosted relay's.
  final String? url;

  /// A hosted relay's name (32 hex); null for a hub's address.
  final String? relay;

  /// The public relay a hosted one stays linked to, as [canonicalHub] writes it; null where it names none (it is then
  /// reached over the direct network alone, which no relay does).
  final String? via;

  static final _hex32 = RegExp(r'^[0-9a-f]{32}$');

  /// What [address] names, or null where it is neither kind.
  static HomeAddress? parse(String address) {
    final Uri u;
    try {
      u = Uri.parse(address);
    } catch (_) {
      return null;
    }
    if (u.scheme == 'ghost-relay') {
      if (!_hex32.hasMatch(u.host) || u.hasPort || u.userInfo.isNotEmpty) return null;
      String? via;
      try {
        final said = u.queryParameters['via'];
        via = said == null ? null : canonicalHub(said);
      } catch (_) {}
      return HomeAddress.hosted(u.host, via);
    }
    final url = canonicalHub(address);
    return url == null ? null : HomeAddress.hub(url);
  }
}

/// A hub's address as two relays compare them: `wss` or `ws`, the host in lower case, the port only where it is not
/// the scheme's own, the path without a slash at its end, and nothing else (no user, query or fragment). Null where
/// [address] is not a hub's address at all. The app writes the same (lib/net/home_record.dart).
String? canonicalHub(String address) {
  if (address.length > HomeRecord.maxAddress) return null;
  final Uri u;
  try {
    u = Uri.parse(address);
  } catch (_) {
    return null;
  }
  final scheme = u.scheme;
  if ((scheme != 'wss' && scheme != 'ws') || u.host.isEmpty || u.userInfo.isNotEmpty || u.hasQuery || u.hasFragment) return null;
  final port = u.hasPort && u.port != (scheme == 'wss' ? 443 : 80) ? ':${u.port}' : '';
  final host = u.host.contains(':') ? '[${u.host}]' : u.host;
  return '$scheme://$host$port${u.path.replaceAll(RegExp(r'/+$'), '')}';
}

/// The home records a relay holds (federation.dart).
///
/// - **Its own people's**: of everyone who gave theirs here themselves, over their own signed-in connection. Kept in
///   `homes.json` in the data folder, across restarts, [maxOwn] at most: one more lets go of whoever gave theirs
///   longest ago (they give it again each time their app signs in).
/// - **Others'** (a friend's record an app gave so the relay can route to them, one another relay gave to show it
///   speaks for someone): in memory, the [maxOthers] used most lately.
///
/// Of two records for one account the higher count is held, whoever gave it; nothing here is ever made by the relay.
class HomeBook {
  HomeBook({this.file, this.maxOwn = 50000, this.maxOthers = 20000});

  /// Where the relay's own people's records are kept; null keeps nothing across restarts.
  final File? file;
  final int maxOwn;
  final int maxOthers;

  final LinkedHashMap<String, HomeRecord> _own = LinkedHashMap();
  final LinkedHashMap<String, HomeRecord> _others = LinkedHashMap();

  /// Whether anything kept across restarts has changed since it was last written.
  bool dirty = false;

  int get own => _own.length;
  int get others => _others.length;

  /// Whether [a] gave their own record here.
  bool isOwn(String a) => _own.containsKey(a);

  /// The record held for [a], or null. One of the others' is used a moment ago for it.
  HomeRecord? of(String a) {
    final mine = _own[a];
    if (mine != null) return mine;
    final other = _others.remove(a);
    if (other != null) _others[a] = other;
    return other;
  }

  /// Whether exactly [rec] is held: then it need not be checked again.
  bool holds(String a, int n, List<int> s) {
    final held = _own[a] ?? _others[a];
    return held != null && held.n == n && HomeRecord._equal(held.s, s);
  }

  /// Keeps [rec], already checked, where it is newer than what is held for its account; true where it was kept.
  /// [byOwner]: the account gave it itself, here: it is one of this relay's own from now on.
  bool keep(HomeRecord rec, {bool byOwner = false}) {
    final a = rec.a;
    final held = _own[a] ?? _others[a];
    final newer = held == null || rec.n > held.n;
    if (byOwner) {
      // Given by its owner, here: one of this relay's own, and the last of them to be let go.
      final had = _own.remove(a);
      _others.remove(a);
      _own[a] = newer ? rec : held;
      while (_own.length > maxOwn) {
        _own.remove(_own.keys.first);
      }
      if (newer || had == null) dirty = true;
      return newer;
    }
    if (_own.containsKey(a)) {
      // A newer copy of one of this relay's own people's, from someone else: in the older one's place.
      if (newer) {
        _own[a] = rec;
        dirty = true;
      }
      return newer;
    }
    _others.remove(a);
    _others[a] = newer ? rec : held;
    while (_others.length > maxOthers) {
      _others.remove(_others.keys.first);
    }
    return newer;
  }

  void load() {
    final f = file;
    if (f == null) return;
    try {
      if (!f.existsSync()) return;
      final all = jsonDecode(f.readAsStringSync());
      final list = all is Map && all['own'] is List ? all['own'] as List : const [];
      for (final j in list.length > maxOwn ? list.sublist(list.length - maxOwn) : list) {
        // Checked when it was kept; read back for its shape alone (a signature is seven milliseconds of arithmetic,
        // and there may be tens of thousands).
        final rec = HomeRecord.read(j, now: DateTime.fromMillisecondsSinceEpoch(0), verify: false).rec;
        if (rec != null) _own[rec.a] = rec;
      }
    } catch (_) {
      // A file that cannot be read is started again from nothing: each app gives its record again as it signs in.
    }
    dirty = false;
  }

  void save() {
    final f = file;
    if (f == null || !dirty) return;
    try {
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.tmp')..writeAsStringSync(jsonEncode({'v': 1, 'own': [for (final r in _own.values) r.toJson()]}));
      tmp.renameSync(f.path);
      dirty = false;
    } catch (_) {}
  }
}
