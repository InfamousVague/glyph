import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../net/crypto.dart';

/// One person's signed word that a friend's account is who they say (GMFB-33: "friends can mark you as verified, shown
/// as 'verified by 3 friends'"), or that they no longer say so ([on] false: taken back). The newest of one person's
/// words about one account stands ([t]); an older one, sent again by anyone, changes nothing.
///
/// Signed by the voucher's account key (P-256, as everything the account signs) over [signedBytes]:
/// `ghost-vouch v1`, a newline, then the voucher's name, the account's name, the account's key (base64), `yes` or `no`,
/// and the time in milliseconds, each on a line of its own. The account's key is in it, so a vouch for one key says
/// nothing of another key that later takes the same username.
///
/// A vouch is good for a year ([lasts]) from the time it was signed (Matt, 2026-11-23: "vouches expire after a year").
/// The time is in what is signed and the year is fixed here, so nobody can make one last longer; Vouch for again
/// renews it. An expired one is counted by nobody, carried to nobody, and dropped from what is kept. A taken-back word
/// is kept as long as the vouch it took back could have lasted, and dropped after.
@immutable
class Vouch {
  const Vouch({required this.by, required this.forId, required this.on, required this.t, required this.sig});

  /// Who said it (their account name) and of whom.
  final String by;
  final String forId;

  /// Said, or taken back.
  final bool on;

  /// When, in milliseconds since 1970, by the voucher's clock (always later than their word before it: [Vouches.make]).
  final int t;
  final Uint8List sig;

  static const words = 'ghost-vouch v1\n';

  /// How long a vouch is good for, from [t].
  static const lasts = Duration(days: 365);

  /// How far ahead of this device's clock a time may be and still be believed (another device's clock running fast).
  static const ahead = Duration(days: 1);

  /// When it stops being good, in milliseconds since 1970.
  int get until => t + lasts.inMilliseconds;

  /// Whether it has run out by [now].
  bool expiredAt(int now) => now >= until;

  /// Whether it is good at [now]: not run out, and not signed further ahead than a clock can be wrong by.
  bool goodAt(int now) => !expiredAt(now) && t <= now + ahead.inMilliseconds;

  static Uint8List signedBytes({required String by, required String forId, required String forKey, required bool on, required int t}) => Uint8List.fromList(utf8.encode('$words$by\n$forId\n$forKey\n${on ? 'yes' : 'no'}\n$t'));

  /// Whether this is the holder of [byKey]'s word about the holder of [forKey] (both base64, as friends' keys are kept):
  /// each key makes its name, and the signature is [byKey]'s.
  bool checks({required String byKey, required String forKey}) {
    try {
      final bk = base64Decode(byKey), fk = base64Decode(forKey);
      if (NetCrypto.idOf(bk) != by || NetCrypto.idOf(fk) != forId) return false;
      return NetCrypto.verifyOnce(bk, signedBytes(by: by, forId: forId, forKey: forKey, on: on, t: t), sig);
    } catch (_) {
      return false;
    }
  }

  static final _name = RegExp(r'^[0-9a-f]{32}$');

  /// As it is sent to the account vouched for (`vouch` envelopes) and kept: everything.
  Map<String, Object> toJson() => {'b': by, 'f': forId, 't': t, 's': base64Encode(sig), if (!on) 'x': 1};

  /// As a profile carries it to friends: without the account's name, which is the profile's own.
  Map<String, Object> carried() => {'b': by, 't': t, 's': base64Encode(sig), if (!on) 'x': 1};

  /// One read back from [j]; [forId] where the form carried leaves it out. Null where it isn't the shape of one (its
  /// signature is checked where it is counted: [checks]).
  static Vouch? fromJson(Object? j, {String? forId}) {
    if (j is! Map) return null;
    final b = j['b'], f = forId ?? j['f'], t = j['t'], s = j['s'];
    if (b is! String || f is! String || t is! int || s is! String || !_name.hasMatch(b) || !_name.hasMatch(f) || s.length > 100 || t <= 0) return null;
    try {
      final sig = base64Decode(s);
      if (sig.length != 64) return null;
      return Vouch(by: b, forId: f, on: j['x'] != 1, t: t, sig: sig);
    } catch (_) {
      return null;
    }
  }
}

/// The vouches this account gave, those it was given, and those its friends carry with their profiles
/// (lib/friends/buddies.dart sends and hears them; docs/friends.md says how they travel).
///
/// - **Given** ([given]): this account's newest word about each friend, so a profile can say "You vouch for them" and
///   a vouch taken back is always newer than the one it takes back.
/// - **Held** ([held]): friends' words about this account, sent by them, each checked against the key held for that
///   friend and for this account before it is kept. The newest of each friend's stands, taken-back ones too, so an old
///   vouch sent again never undoes its withdrawal. At most [most] said and [most] taken back are kept.
/// - **Carried** ([carried]): what each friend's profile said they hold, newest per voucher, kept as it came; counted
///   ([vouchersOf]) only for vouchers who are this account's own friends, checked against the key this account holds
///   for them. A friend's profile is read for at most `2 × most` of them.
/// - **Hidden** ([hidden]): the person chose not to carry the vouches they hold to their friends.
///
/// Nothing here is ever given to the relay or to anyone who isn't a friend; there is no count of anyone's anywhere but
/// on the screens of their friends, each counting only their own friends.
class Vouches extends ChangeNotifier {
  Vouches({required String Function(String key) read, required void Function(String key, String value) write, int Function()? now})
      : _read = read,
        _write = write,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Kept in memory only: for a port with nowhere to keep things (a test).
  factory Vouches.inMemory({int Function()? now}) {
    final m = <String, String>{};
    return Vouches(read: (k) => m[k] ?? '', write: (k, v) => m[k] = v, now: now);
  }

  final String Function(String key) _read;
  final void Function(String key, String value) _write;
  final int Function() _now;

  /// The most said vouches kept or carried, and as many taken back.
  static const most = 64;

  final Map<String, Vouch> given = {};
  final Map<String, Vouch> held = {};
  final Map<String, Map<String, Vouch>> carried = {};
  bool hidden = false;
  String? _for;

  static String _key(String me) => 'vouches:$me';

  /// Reads what is kept for the account [me] (another account on this device keeps its own).
  void load(String me) {
    if (_for == me) return;
    _for = me;
    given.clear();
    held.clear();
    carried.clear();
    hidden = false;
    try {
      final j = jsonDecode(_read(_key(me)));
      if (j is Map) {
        for (final v in (j['given'] as List? ?? const [])) {
          final x = Vouch.fromJson(v);
          if (x != null) given[x.forId] = x;
        }
        for (final v in (j['held'] as List? ?? const [])) {
          final x = Vouch.fromJson(v, forId: me);
          if (x != null) held[x.by] = x;
        }
        final c = j['carried'];
        if (c is Map) {
          for (final e in c.entries) {
            if (e.key is! String || e.value is! List) continue;
            final m = <String, Vouch>{};
            for (final v in e.value as List) {
              final x = Vouch.fromJson(v, forId: e.key as String);
              if (x != null) m[x.by] = x;
            }
            carried[e.key as String] = m;
          }
        }
        hidden = j['hide'] == true;
      }
    } catch (_) {}
    if (_prune()) _save();
    notifyListeners();
  }

  /// Drops every word that has run out; true where any was dropped.
  bool _prune() {
    final now = _now();
    var dropped = false;
    void from(Map<String, Vouch> m) {
      final before = m.length;
      m.removeWhere((_, v) => v.expiredAt(now));
      if (m.length != before) dropped = true;
    }

    from(given);
    from(held);
    for (final m in carried.values) {
      from(m);
    }
    carried.removeWhere((_, m) => m.isEmpty);
    return dropped;
  }

  void _save() {
    _prune();
    final me = _for;
    if (me != null) {
      _write(_key(me), jsonEncode({
        'given': [for (final v in given.values) v.toJson()],
        'held': [for (final v in held.values) v.carried()],
        'carried': {for (final e in carried.entries) e.key: [for (final v in e.value.values) v.carried()]},
        if (hidden) 'hide': true,
      }));
    }
    notifyListeners();
  }

  /// Keeps [v] in [into] (by voucher) where it is newer than the one there; true where it was.
  static bool _newer(Map<String, Vouch> into, Vouch v) {
    final had = into[v.by];
    if (had != null && had.t >= v.t) return false;
    into[v.by] = v;
    return true;
  }

  /// [all] cut to [most] said and [most] taken back, the newest of each.
  static void _cap(Map<String, Vouch> all) {
    for (final on in [true, false]) {
      final some = all.values.where((v) => v.on == on).toList()..sort((a, b) => b.t.compareTo(a.t));
      for (final v in some.skip(most)) {
        all.remove(v.by);
      }
    }
  }

  /// This account's word about [forId] (key [forKey]): [on] or taken back, signed with [sign], kept, and returned to be
  /// sent. Always later than the word it replaces, whatever the clock says.
  Future<Vouch> make({required String me, required String forId, required String forKey, required bool on, required Future<Uint8List> Function(List<int> message) sign}) async {
    load(me);
    final before = given[forId]?.t ?? 0;
    final t = _now() > before ? _now() : before + 1;
    final sig = await sign(Vouch.signedBytes(by: me, forId: forId, forKey: forKey, on: on, t: t));
    final v = Vouch(by: me, forId: forId, on: on, t: t, sig: sig);
    given[forId] = v;
    _save();
    return v;
  }

  /// A friend ([from], whose key this account holds as [fromKey]) sent their word about this account ([me], key
  /// [meKey]): kept where it is theirs, about this key, and newer than their word before. True where it changed what is
  /// held.
  bool heard(Object? body, {required String from, required String fromKey, required String me, required String meKey}) {
    load(me);
    if (_prune()) _save();
    final v = Vouch.fromJson(body);
    if (v == null || v.by != from || v.forId != me || !v.goodAt(_now()) || !v.checks(byKey: fromKey, forKey: meKey)) return false;
    if (!_newer(held, v)) return false;
    _cap(held);
    _save();
    return true;
  }

  /// What a friend's profile said they hold ([list], the carried form), in place of what it said before: a voucher it
  /// no longer names is gone (the friend dropped them, or hid them all), except that a word older than one seen before
  /// from the same voucher is passed over, and a taken-back word seen before is kept, so a vouch taken back and later
  /// carried again in its old form stays taken back. A voucher [keyOf] names a key for (a friend of this account's) is
  /// checked as it comes; the rest are kept as they came, and checked if that voucher becomes a friend.
  void tookCarried(String friend, Object? list, {String? Function(String id)? keyOf, String? friendKey}) {
    if (list is! List || _for == null) return;
    if (_prune()) _save();
    final had = carried[friend] ?? const <String, Vouch>{};
    final now = <String, Vouch>{};
    for (final j in list.take(2 * most)) {
      final v = Vouch.fromJson(j, forId: friend);
      if (v == null || v.by == friend || !v.goodAt(_now())) continue;
      final k = keyOf?.call(v.by);
      if (k != null && friendKey != null && !v.checks(byKey: k, forKey: friendKey)) continue;
      final seen = had[v.by];
      _newer(now, seen != null && seen.t > v.t ? seen : v);
    }
    for (final v in had.values) {
      if (!v.on && !now.containsKey(v.by)) now[v.by] = v;
    }
    _cap(now);
    String said(Map<String, Vouch> m) => jsonEncode([for (final v in m.values) v.carried()]);
    if (said(now) == said(had)) return;
    carried[friend] = now;
    _save();
  }

  /// What this account's profile carries to its friends: the newest said and taken back of those it holds, or nothing
  /// where the person hid them.
  List<Map<String, Object>> carry() {
    if (hidden) return const [];
    final now = _now();
    final all = held.values.where((v) => v.goodAt(now)).toList()..sort((a, b) => b.t.compareTo(a.t));
    return [for (final v in all) v.carried()];
  }

  void setHidden(bool hide) {
    if (hidden == hide) return;
    hidden = hide;
    _save();
  }

  /// [id] is no longer a friend (removed, blocked, or they ended it): their vouch for this account goes, this account's
  /// for them, and what their profile carried.
  void forget(String id) {
    final a = held.remove(id), b = given.remove(id), c = carried.remove(id);
    if (a != null || b != null || c != null) _save();
  }

  /// Of [friends] (id and key, base64, each one of this account's own friends), those whose newest word about the
  /// account [forId] (key [forKey]) is said and checks out against the key held for them. For this account itself
  /// ([forId] its own) what is held; for anyone else what their profile carried.
  List<T> vouchersOf<T>(String forId, String forKey, Iterable<T> friends, {required String Function(T) id, required String Function(T) key}) {
    final words = forId == _for ? held : (carried[forId] ?? const <String, Vouch>{});
    if (words.isEmpty) return const [];
    final now = _now();
    return [
      for (final f in friends)
        if (words[id(f)] case final v? when id(f) != forId && v.on && v.goodAt(now) && v.checks(byKey: key(f), forKey: forKey)) f,
    ];
  }

  /// This account's vouch for [forId] where it gave one and it is good now; null otherwise.
  Vouch? givenFor(String forId) {
    final v = given[forId];
    return v != null && v.on && v.goodAt(_now()) ? v : null;
  }
}
