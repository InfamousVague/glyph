import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../desktop/platform.dart';
import '../friends/buddies.dart';
import '../friends/friends.dart';
import '../net/crypto.dart';
import '../sms.dart';

/// Ghost Messaging on an iPhone of its own (Matt, 2026-11-15: "investigate if we can within apples rules make a
/// bridge for messaging through RCS like we're doing with mautrix on android and if not we'll want to roll a version
/// of the app that works without sms"; "it's unlikely the user will ever have two phones").
///
/// iOS lets no app read or send texts (outside the EU, where iOS 26 gives the default messaging app a framework for
/// it), and the Google Messages bridge needs an Android phone running Google Messages. So here there are no texts:
/// people are reached by username, over the relay server, sealed as the phone seals its routes' packets.
///
/// This stands where the Android phone's channel stands ([SmsCalls]): the same calls by the same names, answered
/// here, so the phone's own screens and start-up run unchanged ([Sms.standalone]).
///
/// - **Who this iPhone is**: a P-256 key made here, kept in the Keychain ([NetKeys]); the same arithmetic the phone's
///   E2eCrypto does, so an iPhone and an Android phone seal to each other.
/// - **Friends by username** ([Buddies]): their list is kept here, and each one's sealing key is made here from it,
///   as android Buddies.kt does. Each friend is a conversation, addressed `@username` ([addressOf]), so what
///   [Friends] does for a phone-number friend (send, acknowledge, take back) it does for them.
/// - **The conversations** are kept in a file of this app's (`standalone.json`): what was written and what came, and
///   each conversation's read, archived, pinned and muted.
class StandaloneCalls implements SmsCalls {
  StandaloneCalls(this.dir, {this.keychain = true});

  final Directory dir;

  /// Whether the identity is kept in the Keychain (a build for a device) or in the folder (a test).
  final bool keychain;

  static const _account = 'standalone-identity';

  NetKeys? _keys;
  Map<String, String> _prefs = {};
  String _buddies = '[]';
  final Map<int, _Thread> _threads = {};
  int _nextRow = 1;

  /// The thread open on the screen: what comes into it is not unread.
  int _open = -1;

  File get _file => File('${dir.path}/standalone.json');
  File get _keyFile => File('${dir.path}/identity.key');

  /// The address a friend by username is spoken of by: `@` and their username.
  static String addressOf(String username) => '@$username';

  /// Where an iPhone keeps it: the app's Application Support folder, which iOS keeps and backs up. iOS gives a Flutter
  /// app no HOME, so the container is found from its tmp folder, which is in it.
  static Directory defaultDir() {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.parent.path;
    return Directory('$home/Library/Application Support/Ghost Messaging');
  }

  /// Where the first builds kept it by mistake: inside tmp, which iOS may empty. Moved from once, if it is there.
  static Directory get _misplaced => Directory('${Directory.systemTemp.path}/Library/Application Support/Ghost Messaging');

  Future<void> load() async {
    // What a first build left in tmp is carried over: who this iPhone is (its username is held by that key) and
    // what was written.
    final old = _misplaced;
    if (!File('${dir.path}/standalone.json').existsSync() && old.existsSync() && old.path != dir.path) {
      dir.createSync(recursive: true);
      for (final name in ['standalone.json', 'identity.key']) {
        final f = File('${old.path}/$name');
        if (f.existsSync()) f.copySync('${dir.path}/$name');
      }
    }
    dir.createSync(recursive: true);
    try {
      final j = jsonDecode(await _file.readAsString()) as Map;
      _prefs = {for (final e in ((j['prefs'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
      _buddies = (j['buddies'] as String?) ?? '[]';
      _nextRow = (j['next'] as num?)?.toInt() ?? 1;
      for (final t in (j['threads'] as List?) ?? const []) {
        final thread = _Thread.fromJson(t as Map);
        _threads[thread.id] = thread;
      }
    } catch (_) {}
    _keys = await _identity();
  }

  Future<NetKeys> _identity() async {
    String? kept = keychain ? await MacPlatform.keyRead(_account) : null;
    if (kept == null && _keyFile.existsSync()) kept = _keyFile.readAsStringSync().trim();
    if (kept != null && kept.length == 64) {
      try {
        return NetKeys.fromScalar(NetCrypto.unhex(kept));
      } catch (_) {}
    }
    final made = NetKeys.generate();
    final hex = NetCrypto.hex(made.scalar);
    // The Keychain where it takes it; else the app's own folder, which iOS keeps to this app alone.
    if (!keychain || !await MacPlatform.keyWrite(_account, hex)) _keyFile.writeAsStringSync(hex);
    return made;
  }

  Future<void> _last = Future.value();

  void _save() {
    final text = jsonEncode({
      'prefs': _prefs,
      'buddies': _buddies,
      'next': _nextRow,
      'threads': [for (final t in _threads.values) t.toJson()],
    });
    _last = _last.catchError((_) {}).then((_) async {
      final temp = File('${_file.path}.new');
      await temp.writeAsString(text, flush: true);
      await temp.rename(_file.path);
    });
  }

  /// Every write done, for a test.
  @visibleForTesting
  Future<void> flushed() => _last;

  // --- friends by username ---------------------------------------------------------------------------------------

  List<Buddy> get _buddyList {
    try {
      return [for (final j in jsonDecode(_buddies) as List) ?Buddy.fromJson(j)];
    } catch (_) {
      return const [];
    }
  }

  Buddy? _buddyAt(String address) {
    if (!address.startsWith('@')) return null;
    final name = address.substring(1).toLowerCase();
    for (final b in _buddyList) {
      if (b.username.toLowerCase() == name) return b;
    }
    return null;
  }

  /// Those the routes reach, as android Buddies.peers has them: friends who said yes, and those asked or asking, so
  /// a sealed yes can be opened.
  List<Map<String, Object>> _peers() {
    final keys = _keys;
    if (keys == null) return const [];
    final out = <Map<String, Object>>[];
    for (final b in _buddyList) {
      if (b.state != 'yes' && b.state != 'asked' && b.state != 'invited') continue;
      final pub = _decode(b.key);
      if (pub == null || pub.length != 33 || NetCrypto.idOf(pub) != b.id) continue;
      final pair = NetCrypto.conversationKey(keys, pub);
      if (pair == null) continue;
      out.add({'id': b.id, 'address': b.state == 'yes' ? addressOf(b.username) : '', 'key': NetCrypto.netKey(pair)});
    }
    return out;
  }

  static Uint8List? _decode(String b64) {
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Where things stand with each friend, as the phone's encryption record has it: on, and friends.
  List<Map<String, Object?>> _states() => [
        for (final b in _buddyList)
          if (b.state == 'yes')
            {'address': addressOf(b.username), 'state': 'on', 'friend': 'yes', 'hasGhost': true, 'person': _person(addressOf(b.username))},
      ];

  Map<String, Object?> _person(String address) {
    final b = _buddyAt(address);
    return {'address': address, 'name': b == null ? null : (b.name.isEmpty ? '@${b.username}' : b.name)};
  }

  // --- the conversations -----------------------------------------------------------------------------------------

  /// The thread with [address], made where there is none.
  _Thread _threadWith(String address) {
    for (final t in _threads.values) {
      if (t.address.toLowerCase() == address.toLowerCase()) return t;
    }
    var id = (address.toLowerCase().hashCode & 0x3fffffff) | 1;
    while (_threads.containsKey(id)) {
      id = (id + 2) & 0x3fffffff;
    }
    final made = _Thread(id: id, address: address);
    _threads[id] = made;
    return made;
  }

  _Row? _row(int id) {
    for (final t in _threads.values) {
      for (final r in t.rows) {
        if (r.id == id) return r;
      }
    }
    return null;
  }

  _Thread? _threadOfRow(int id) {
    for (final t in _threads.values) {
      if (t.rows.any((r) => r.id == id)) return t;
    }
    return null;
  }

  void _changed(int thread) {
    _save();
    Sms.instance.changes.add(thread);
  }

  Map<String, Object?> _conversation(_Thread t) {
    final last = t.rows.isEmpty ? null : t.rows.last;
    return {
      'id': t.id,
      'date': (last?.at ?? t.made),
      'people': [_person(t.address)],
      'snippet': last == null ? '' : (last.out ? 'You: ${last.body}' : last.body),
      'unread': t.unread,
      'error': last?.state == 'failed',
      'archived': t.archived,
      'pinned': t.pinned,
      'muted': t.muted,
      'blocked': false,
      'draft': t.draft,
      'encrypted': true,
    };
  }

  List<_Thread> _sorted({bool archived = false}) {
    final list = [
      for (final t in _threads.values)
        if (t.archived == archived && (t.rows.isNotEmpty || t.draft != null)) t,
    ];
    list.sort((a, b) => (b.rows.isEmpty ? b.made : b.rows.last.at).compareTo(a.rows.isEmpty ? a.made : a.rows.last.at));
    return list;
  }

  // --- the calls ---------------------------------------------------------------------------------------------------

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    final a = arguments is Map ? arguments : const {};
    return (await _answer(method, a)) as T?;
  }

  Future<Object?> _answer(String method, Map a) async {
    switch (method) {
      // Who this iPhone is, and who it reaches.
      case 'netIdentity':
        final k = _keys!;
        return {'id': k.id, 'key': base64Encode(k.public)};
      case 'netSign':
        return NetCrypto.sign(_keys!, (a['message'] as List).cast<int>());
      case 'netPeers':
        return _peers();
      case 'buddiesKeep':
        _buddies = (a['json'] as String?) ?? '[]';
        _save();
        Sms.instance.prefsChanged.add(null);
        return null;
      case 'buddiesKept':
        return _buddies;
      case 'e2eList':
        return _states();
      case 'e2e':
        final address = '${a['address']}';
        return _states().firstWhere((s) => s['address'] == address, orElse: () => {'address': address, 'state': 'none'});
      case 'friendSet':
        return null;

      // What friends write, kept here ([Friends] by the routes).
      case 'netTextOut':
        final t = _threadWith('${a['address']}');
        final row = _Row(id: _nextRow++, body: '${a['body']}', at: DateTime.now().millisecondsSinceEpoch, out: true, state: 'sending');
        t.rows.add(row);
        t.draft = null;
        _changed(t.id);
        return row.id;
      case 'netTextState':
        final row = _row((a['id'] as num).toInt());
        if (row != null) {
          row.state = '${a['state']}';
          _changed(_threadOfRow(row.id)!.id);
        }
        return null;
      case 'netTextDrop':
        final id = (a['id'] as num).toInt();
        final t = _threadOfRow(id);
        if (t != null) {
          t.rows.removeWhere((r) => r.id == id);
          _changed(t.id);
        }
        return null;
      case 'netTextIn':
        final t = _threadWith('${a['address']}');
        t.rows.add(_Row(id: _nextRow++, body: '${a['body']}', at: (a['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch, out: false, state: 'received'));
        if (t.id != _open) t.unread = true;
        _changed(t.id);
        return null;

      // The list and a conversation.
      case 'conversations':
        return [for (final t in _sorted()) _conversation(t)];
      case 'conversationsPage':
        // `pinned` asks for the pinned ones as well as the newest, as Android's does (pinnedToo): they head the list
        // however old they are.
        final all = _sorted(archived: a['archived'] == true);
        final offset = (a['offset'] as num?)?.toInt() ?? 0, limit = (a['limit'] as num?)?.toInt() ?? 0;
        final page = limit <= 0 ? all.skip(offset).toList() : all.skip(offset).take(limit).toList();
        if (a['pinned'] == true && offset == 0) page.addAll(all.where((t) => t.pinned && !page.contains(t)));
        final next = limit > 0 && offset + limit < all.length ? offset + limit : null;
        return {'items': [for (final t in page) _conversation(t)], 'next': next};
      case 'conversation':
        final t = _threads[(a['thread'] as num).toInt()];
        return t == null ? null : _conversation(t);
      case 'archivedCount':
        return _sorted(archived: true).length;
      case 'messages':
        final t = _threads[(a['thread'] as num).toInt()];
        if (t == null) return const [];
        final limit = (a['limit'] as num?)?.toInt() ?? 0;
        final rows = limit > 0 && t.rows.length > limit ? t.rows.sublist(t.rows.length - limit) : t.rows;
        return [
          for (final r in rows.reversed)
            {'id': r.id, 'kind': 'sms', 'address': t.address, 'body': r.body, 'date': r.at, 'outgoing': r.out, 'state': r.state, 'encrypted': true, 'via': 'net'},
        ];
      case 'people':
        final t = _threads[(a['thread'] as num).toInt()];
        return t == null ? const [] : [_person(t.address)];
      case 'threadFor':
        final addresses = ((a['addresses'] as List?) ?? const []).map((x) => '$x').toList();
        if (addresses.length != 1) return -1;
        final t = _threadWith(addresses.first);
        _save();
        return t.id;
      case 'send':
        // To a friend by username: by the routes ([Friends.sendText] keeps it here as it goes). Pictures and groups
        // are not yet carried this way.
        final addresses = ((a['addresses'] as List?) ?? const []).map((x) => '$x').toList();
        final body = '${a['body'] ?? ''}';
        if (addresses.length != 1 || body.isEmpty) throw StateError('Only words to one friend can be sent from this iPhone yet');
        final t = _threadWith(addresses.first);
        if (!await Friends.instance.sendText(addresses.first, body)) {
          t.rows.add(_Row(id: _nextRow++, body: body, at: DateTime.now().millisecondsSinceEpoch, out: true, state: 'failed'));
          _changed(t.id);
        }
        return t.id;
      case 'markRead':
        final t = _threads[(a['thread'] as num).toInt()];
        if (t != null && t.unread) {
          t.unread = false;
          _changed(t.id);
        }
        return null;
      case 'setOpenThread':
        _open = (a['thread'] as num?)?.toInt() ?? -1;
        return null;
      case 'deleteThread':
        _threads.remove((a['thread'] as num).toInt());
        _changed(-1);
        return null;
      case 'deleteThreads':
        for (final id in (a['threads'] as List? ?? const [])) {
          _threads.remove((id as num).toInt());
        }
        _changed(-1);
        return null;
      case 'deleteMessage':
        final id = (a['id'] as num).toInt();
        final t = _threadOfRow(id);
        if (t != null) {
          t.rows.removeWhere((r) => r.id == id);
          _changed(t.id);
        }
        return null;
      case 'archive':
        final t = _threads[(a['thread'] as num).toInt()];
        if (t != null) {
          t.archived = a['archived'] == true;
          _changed(t.id);
        }
        return null;
      case 'threadFlag':
        final t = _threads[(a['thread'] as num).toInt()];
        if (t != null) {
          final on = a['on'] == true;
          switch (a['name']) {
            case 'pinned':
              t.pinned = on;
            case 'muted':
              t.muted = on;
          }
          _changed(t.id);
        }
        return null;
      case 'draft':
        return _threads[(a['thread'] as num).toInt()]?.draft;
      case 'setDraft':
        final t = _threads[(a['thread'] as num).toInt()];
        if (t != null) {
          final text = '${a['text'] ?? ''}';
          t.draft = text.isEmpty ? null : text;
          _save();
        }
        return null;
      case 'contact':
        return _person('${a['address']}');
      case 'searchContacts':
        final q = '${a['query'] ?? ''}'.toLowerCase().replaceAll('@', '');
        return [
          for (final b in _buddyList)
            if (b.state == 'yes' && (q.isEmpty || b.username.toLowerCase().contains(q) || b.name.toLowerCase().contains(q)))
              {'name': b.name.isEmpty ? '@${b.username}' : b.name, 'address': addressOf(b.username)},
        ];

      // The app's choices, kept with the rest.
      case 'prefs':
        return Map<String, String>.from(_prefs);
      case 'setPref':
        _prefs['${a['key']}'] = '${a['value']}';
        _save();
        return null;

      // Where it stands: set up (there is nothing to be made the default for), no texts, nothing waiting.
      case 'status':
        return {'isDefault': true, 'contacts': true, 'notifications': true, 'phone': false, 'sms': false};
      case 'netSmsAvailable':
        return false;
      case 'netSmsDrain':
        return const [];
      case 'ownNumber':
        return null;
      case 'groups':
        return const [];
      case 'computers':
      case 'deskList':
      case 'blockedNumbers':
        return const [];

      // The iPhone's own: pictures, the microphone, playing (ios/Runner/DeskChannels.swift, as on a Mac).
      case 'pickImages':
        return await MacPlatform.pickPictures(most: (a['most'] as num?)?.toInt() ?? 5);
      case 'voiceLength':
        final bytes = a['bytes'];
        return bytes is Uint8List ? await MacPlatform.voiceLength(bytes) : 0;
    }
    // Everything else is the Android phone's alone (texts, MMS, the default app, its updates): nothing here.
    return null;
  }
}

class _Thread {
  _Thread({required this.id, required this.address, int? made}) : made = made ?? DateTime.now().millisecondsSinceEpoch;
  final int id;
  final String address;
  final int made;
  final List<_Row> rows = [];
  bool unread = false;
  bool archived = false;
  bool pinned = false;
  bool muted = false;
  String? draft;

  Map<String, Object?> toJson() => {
        'id': id,
        'a': address,
        'm': made,
        'u': unread,
        'ar': archived,
        'p': pinned,
        'mu': muted,
        'd': draft,
        'rows': [for (final r in rows) r.toJson()],
      };

  factory _Thread.fromJson(Map j) {
    final t = _Thread(id: (j['id'] as num).toInt(), address: '${j['a']}', made: (j['m'] as num?)?.toInt());
    t.unread = j['u'] == true;
    t.archived = j['ar'] == true;
    t.pinned = j['p'] == true;
    t.muted = j['mu'] == true;
    t.draft = j['d'] as String?;
    for (final r in (j['rows'] as List?) ?? const []) {
      t.rows.add(_Row.fromJson(r as Map));
    }
    return t;
  }
}

class _Row {
  _Row({required this.id, required this.body, required this.at, required this.out, required this.state});
  final int id;
  final String body;
  final int at;
  final bool out;
  String state;

  Map<String, Object?> toJson() => {'i': id, 'b': body, 't': at, 'o': out, 's': state};

  factory _Row.fromJson(Map j) => _Row(id: (j['i'] as num).toInt(), body: '${j['b']}', at: (j['t'] as num).toInt(), out: j['o'] == true, state: '${j['s']}');
}

/// Sets the app up as an iPhone of its own, before anything is drawn: the calls answered here, and the routes,
/// directory and calls run here ([Sms.standalone]).
Future<void> standaloneSetup({Directory? dir, bool? keychain}) async {
  final calls = StandaloneCalls(dir ?? StandaloneCalls.defaultDir(), keychain: keychain ?? kReleaseMode);
  await calls.load();
  Sms.calls = calls;
  Sms.standalone = true;
}
