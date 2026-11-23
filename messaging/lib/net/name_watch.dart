import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'crypto.dart';
import 'ledger.dart' show LedgerTimer;
import 'packet.dart';

/// A friend added by username, as the name watch knows them: the username they were found by, and the account name
/// and key the relay answered with then, which is who they are from then on (lib/friends/buddies.dart).
@immutable
class WatchedName {
  const WatchedName(this.username, this.id, this.key);
  final String username;
  final String id;
  final String key;
}

/// The relay gave a username to a key other than the one held for it: which username, the account name of the key
/// it gave (the first 16 bytes of the key's SHA-256, in hex), when that was seen (ms), and, for a friend's word about
/// this person's own username, which friend's app saw it.
@immutable
class NameChange {
  const NameChange({required this.username, required this.other, required this.at, this.by});
  final String username;
  final String other;
  final int at;
  final String? by;

  List<Object?> toJson() => [username, other, at, by];

  static NameChange? fromJson(Object? j) {
    if (j is! List || j.length < 3 || j[0] is! String || j[1] is! String || j[2] is! int) return null;
    return NameChange(username: j[0] as String, other: j[1] as String, at: j[2] as int, by: j.length > 3 && j[3] is String ? j[3] as String : null);
  }
}

/// The name watch (docs/OPEN_NETWORK.md, section 3): what checks the relay's "@name is this key", and needs no direct
/// route. A friend added by username was found by asking the relay who has that username; each friend's app asks the
/// same again once a day ([every], each friend at a time of its own through the day, no more than [mostAnHour] an hour
/// and [gap] apart: the relay answers an install 120 lookups an hour, relay/lib/handles.dart, and the rest are left to
/// the person), and asks of its own username each time it signs in to the relay ([signedIn]).
///
/// - An answer that names another key than the one held for a friend is shown on that friend ([changeFor]: "The relay
///   now says @maya is a different key; you are still talking to the Maya you added"), and the friend is told by every
///   route, sealed, in an envelope of kind [kind], at most once a day while it lasts:
///
///       {"u": the username, "i": the account name the relay gave it to, "at": when (ms)}
///
///   so their app can say a friend's app saw the relay give their username to another key ([toldMe]).
/// - Its own username answered with another key is shown to the person at once ([own], [notice]).
///
/// Nothing here changes who a friend is: a friend stays the key that was added, whatever the relay says after.
class NameWatch extends ChangeNotifier {
  NameWatch({required this.me, required this.username, required this.friends, required this.whois, required this.tell, required this.read, required this.write, DateTime Function()? now, LedgerTimer? timer})
      : _now = now ?? DateTime.now,
        _timer = timer ?? Timer.new;

  /// The app's own, once started (lib/people.dart): the screens read it, and signing out wipes it.
  static NameWatch? instance;

  /// The envelope a friend is told with.
  static const kind = 'name';

  /// How often each friend's username is asked again, how many lookups an hour this may make at most, and how far
  /// apart they are.
  static const every = Duration(days: 1);
  static const mostAnHour = 20;
  static const gap = Duration(minutes: 1);

  /// Its own username is asked at each sign-in, but not more often than this.
  static const ownEvery = Duration(minutes: 10);

  /// A friend is told again while the relay goes on giving their username to another key, at most this often; and a
  /// friend's word is taken at most this often from them.
  static const tellEvery = Duration(days: 1);
  static const heardEvery = Duration(hours: 1);

  /// How long a friend's word about this person's username is shown, and the most kept.
  static const toldFor = Duration(days: 7);
  static const mostTold = 8;

  /// When the relay could not be asked, how long before it is tried again.
  static const retryAfter = Duration(minutes: 10);

  /// Where what it found is kept, with the app's choices.
  static const keptName = 'name_watch';
  static const keptNames = [keptName];

  /// This account's name; its username on the relay, where it has one.
  final String? Function() me;
  final String? Function() username;

  /// Friends added by username, as kept.
  final List<WatchedName> Function() friends;

  /// Asks the relay who has a username (Me.whois): their account name and key, or null for nobody. Throws where it
  /// can't be asked now.
  final Future<({String id, String key})?> Function(String username) whois;

  /// Sends an envelope to a friend by every route there is, sealed.
  final Future<void> Function(String id, Envelope envelope) tell;

  /// Where it keeps what it found: the app's choices.
  final String Function(String name) read;
  final void Function(String name, String value) write;
  final DateTime Function() _now;
  final LedgerTimer _timer;

  final Map<String, int> _checked = {}, _told = {}, _heard = {}, _firstSeen = {};
  final Map<String, NameChange> _changes = {};
  final List<NameChange> _toldMe = [];
  NameChange? _own;
  final List<int> _asked = [];
  int _ownAsked = 0, _lastAsked = 0, _retry = 0;
  Timer? _next;
  bool _started = false, _asking = false, _gone = false;

  /// What to show the person at once: its own username given to another key, by the relay or by a friend's word.
  final ValueNotifier<NameChange?> notice = ValueNotifier(null);

  /// The app's own watch's [notice]s as they come, for the frame to show (lib/ui/shell.dart), whichever watch is the
  /// app's by then.
  static Stream<NameChange> get notices => _notices.stream;
  static final _notices = StreamController<NameChange>.broadcast();

  void _say(NameChange change) {
    notice.value = change;
    if (identical(this, instance)) _notices.add(change);
  }

  int get nowMs => _now().millisecondsSinceEpoch;

  /// What the relay said of [friendId]'s username where it named another key; null where it has not, or names theirs
  /// again.
  NameChange? changeFor(String friendId) => _changes[friendId];

  /// Every friend whose username the relay gave to another key, with what it said.
  List<({String friend, NameChange change})> get changes => List.unmodifiable([for (final e in _changes.entries) (friend: e.key, change: e.value)]);

  /// The relay gave this person's own username to another key, as it last answered.
  NameChange? get own => _own;

  /// Friends' apps that saw the relay give this person's username to another key, newest last.
  List<NameChange> get toldMe {
    final now = nowMs;
    return List.unmodifiable(_toldMe.where((t) => now - t.at < toldFor.inMilliseconds));
  }

  /// When a friend's username was last asked and answered (ms; 0 never), as kept; and how many were asked in the day
  /// before now.
  int get lastAsked => _checked.values.fold(0, (a, b) => b > a ? b : a);
  int get askedInDay {
    final now = nowMs;
    return _checked.values.where((t) => now - t < every.inMilliseconds).length;
  }

  /// How many friends added by username are watched.
  int get watching => _friends().length;

  List<WatchedName> _friends() {
    try {
      return friends();
    } catch (_) {
      return const [];
    }
  }

  void start() {
    if (_started || _gone) return;
    _started = true;
    _load();
    _plan();
  }

  void stop() {
    _started = false;
    _next?.cancel();
    _next = null;
  }

  /// The friends changed: the watch plans again.
  void friendsChanged() {
    if (_started) _plan();
  }

  // --- asking -----------------------------------------------------------------------------------------------------------

  /// When [f]'s username is next due: a day after it was last asked, or, never asked, at a time of the day of its own
  /// after it was first seen here, so the friends are spread out through the day and not asked all at once.
  int _dueAt(WatchedName f) {
    final last = _checked[f.id];
    if (last != null) return last + every.inMilliseconds;
    final seen = _firstSeen[f.id] ??= nowMs;
    return seen + _spread(f.id);
  }

  int _spread(String id) {
    final h = NetCrypto.sha256(utf8.encode('ghost name watch ${me() ?? ''} $id'));
    final n = (h[0] << 24 | h[1] << 16 | h[2] << 8 | h[3]) & 0x7fffffff;
    return n % every.inMilliseconds;
  }

  /// Whether one more lookup may be made now: no more than [mostAnHour] in the last hour, [gap] apart.
  bool _mayAsk() {
    final now = nowMs;
    _asked.removeWhere((t) => now - t >= const Duration(hours: 1).inMilliseconds);
    return _asked.length < mostAnHour && now - _lastAsked >= gap.inMilliseconds;
  }

  /// When the next lookup may be made, by [_mayAsk].
  int _nextSlot() {
    final now = nowMs;
    _asked.removeWhere((t) => now - t >= const Duration(hours: 1).inMilliseconds);
    var at = _lastAsked + gap.inMilliseconds;
    if (_asked.length >= mostAnHour) {
      final free = _asked[_asked.length - mostAnHour] + const Duration(hours: 1).inMilliseconds;
      if (free > at) at = free;
    }
    if (_retry > at) at = _retry;
    return at;
  }

  /// Sets the timer for the next friend due, no sooner than a lookup may be made.
  void _plan() {
    _next?.cancel();
    _next = null;
    if (!_started || _gone || _asking) return;
    final list = _friends();
    if (list.isEmpty) return;
    var due = list.map(_dueAt).reduce((a, b) => a < b ? a : b);
    final slot = _nextSlot();
    if (slot > due) due = slot;
    final wait = due - nowMs;
    _next = _timer(Duration(milliseconds: wait < 0 ? 0 : wait), () {
      _next = null;
      unawaited(_askDue());
    });
  }

  Future<void> _askDue() async {
    if (!_started || _gone || _asking) return;
    final now = nowMs;
    final due = [for (final f in _friends()) if (_dueAt(f) <= now) f]..sort((a, b) => _dueAt(a).compareTo(_dueAt(b)));
    if (due.isEmpty || !_mayAsk()) return _plan();
    await _askFriend(due.first);
    _plan();
  }

  /// Asks the relay who has [f]'s username, and weighs the answer against the key held for them.
  Future<void> _askFriend(WatchedName f) async {
    _asking = true;
    final now = nowMs;
    _asked.add(now);
    _lastAsked = now;
    try {
      final got = await whois(f.username);
      _retry = 0;
      _checked[f.id] = nowMs;
      if (got == null) return;
      if (_sameKey(got, f.id)) {
        // The relay gives it to the key held for them again.
        if (_changes.remove(f.id) != null) {
          _told.remove(f.id);
          notifyListeners();
        }
        return;
      }
      final change = NameChange(username: f.username, other: got.id, at: nowMs);
      _changes[f.id] = change;
      notifyListeners();
      // Told by every route, at most once a day while it lasts: their app can say so.
      if (nowMs - (_told[f.id] ?? 0) >= tellEvery.inMilliseconds) {
        _told[f.id] = nowMs;
        try {
          await tell(f.id, Envelope(kind: kind, body: {'u': f.username, 'i': got.id, 'at': change.at}));
        } catch (_) {}
      }
    } catch (_) {
      // Not asked after all (the relay can't be reached now): tried again a while on, or at the next sign-in.
      _retry = nowMs + retryAfter.inMilliseconds;
    } finally {
      _asking = false;
      _save();
    }
  }

  /// Whether [got] names [id]'s key: the relay's account name is [id], and the key it gave makes that name.
  static bool _sameKey(({String id, String key}) got, String id) {
    if (got.id != id) return false;
    try {
      return NetCrypto.idOf(base64Decode(got.key)) == id;
    } catch (_) {
      return false;
    }
  }

  /// The relay was signed in to again: its own username is asked (at most every [ownEvery]), and the friends' lookups
  /// that waited for it go on.
  Future<void> signedIn() async {
    if (!_started || _gone) return;
    _retry = 0;
    final name = username(), mine = me();
    if (name != null && name.isNotEmpty && mine != null && nowMs - _ownAsked >= ownEvery.inMilliseconds && _mayAsk() && !_asking) {
      _ownAsked = nowMs;
      _asked.add(nowMs);
      _lastAsked = nowMs;
      _asking = true;
      try {
        final got = await whois(name);
        if (got != null && !_sameKey(got, mine)) {
          final change = NameChange(username: _tidy(name), other: got.id, at: nowMs);
          _own = change;
          _say(change);
          notifyListeners();
        } else if (got != null && _own != null) {
          _own = null;
          notifyListeners();
        }
      } catch (_) {
      } finally {
        _asking = false;
        _save();
      }
    }
    _plan();
  }

  // --- what friends say -----------------------------------------------------------------------------------------------

  /// A sealed envelope from [from]: where it is a friend by username's word that the relay gave this person's username
  /// to another key, kept and shown.
  void heard(String from, Envelope e, {bool sealed = true}) {
    if (e.kind != kind || !sealed || _gone) return;
    final name = username(), mine = me();
    if (name == null || name.isEmpty || mine == null) return;
    if (!_friends().any((f) => f.id == from)) return;
    final u = e.body['u'], i = e.body['i'];
    if (u is! String || _tidy(u) != _tidy(name) || i is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(i) || i == mine) return;
    final now = nowMs;
    if (now - (_heard[from] ?? -heardEvery.inMilliseconds) < heardEvery.inMilliseconds) return;
    _heard[from] = now;
    final change = NameChange(username: _tidy(name), other: i, at: now, by: from);
    _toldMe
      ..removeWhere((t) => t.by == from || now - t.at >= toldFor.inMilliseconds)
      ..add(change);
    while (_toldMe.length > mostTold) {
      _toldMe.removeAt(0);
    }
    _say(change);
    _save();
    notifyListeners();
  }

  static String _tidy(String name) {
    var n = name.trim().toLowerCase();
    while (n.startsWith('@')) {
      n = n.substring(1);
    }
    return n;
  }

  // --- keeping ----------------------------------------------------------------------------------------------------------

  void _load() {
    try {
      final j = jsonDecode(read(keptName));
      if (j is! Map) return;
      void ints(Object? m, Map<String, int> into) {
        if (m is! Map) return;
        for (final e in m.entries) {
          if (e.key is String && e.value is int) into[e.key as String] = e.value as int;
        }
      }

      ints(j['c'], _checked);
      ints(j['t'], _told);
      final x = j['x'];
      if (x is Map) {
        for (final e in x.entries) {
          final c = NameChange.fromJson(e.value);
          if (e.key is String && c != null) _changes[e.key as String] = c;
        }
      }
      for (final m in (j['m'] is List ? j['m'] as List : const [])) {
        final c = NameChange.fromJson(m);
        if (c != null && c.by != null) _toldMe.add(c);
      }
      _own = NameChange.fromJson(j['o']);
    } catch (_) {}
  }

  void _save() {
    if (_gone) return;
    // Only of friends now: nothing is kept of anyone else.
    final ids = {for (final f in _friends()) f.id};
    _checked.removeWhere((id, _) => !ids.contains(id));
    _told.removeWhere((id, _) => !ids.contains(id));
    _changes.removeWhere((id, _) => !ids.contains(id));
    final now = nowMs;
    _toldMe.removeWhere((t) => now - t.at >= toldFor.inMilliseconds);
    try {
      write(keptName, jsonEncode({'c': _checked, 't': _told, 'x': {for (final e in _changes.entries) e.key: e.value.toJson()}, 'm': [for (final t in _toldMe) t.toJson()], 'o': ?_own?.toJson()}));
    } catch (_) {}
  }

  /// Signing out: nothing it found is kept.
  void wipe() {
    _gone = true;
    stop();
    _checked.clear();
    _told.clear();
    _heard.clear();
    _changes.clear();
    _toldMe.clear();
    _own = null;
    notice.value = null;
    try {
      write(keptName, '');
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _gone = true;
    notice.dispose();
    super.dispose();
  }
}
