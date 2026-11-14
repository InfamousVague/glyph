import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../sms.dart';
import 'link/crypto.dart';
import 'link/link.dart';
import 'link/session.dart';
import 'store.dart';

/// The phone's screens, on the Mac: every call they make of Android (lib/sms.dart) is answered here, by the phone
/// over the link where it is the phone's to answer, and by the Mac itself where it is the Mac's own (its theme, its
/// choices). What only the phone may do (delete, block, change encryption, send a picture) is refused in words.
///
/// The Mac keeps conversations in memory only. While the phone cannot be reached, what was read last is still shown,
/// and what is typed waits here, drawn as "Waiting for your phone", and goes when the phone is back. Each text has a
/// name the phone remembers, so one sent twice (its answer lost with the connection) is sent once.
class LinkCalls implements SmsCalls {
  LinkCalls(this.link, this.store);

  final PhoneLink link;
  final DeskStore store;

  Map<String, String> _prefs = {};
  List<dynamic>? _conversations;
  final Map<int, List<dynamic>> _messages = {};
  final Map<int, String> _drafts = {};
  final List<_Waiting> _waiting = [];
  int _localId = -1;
  bool _flushing = false;
  StreamSubscription<dynamic>? _events;
  StreamSubscription<void>? _connected;

  /// How many texts are waiting for the phone.
  int get waiting => _waiting.where((w) => !w.failed).length;

  Future<void> init() async {
    _prefs = await store.prefs();
    // On a computer Enter sends, as every desktop messenger has it; the choice can still be changed.
    _prefs.putIfAbsent('enter_sends', () => 'on');
    _events = link.events.stream.listen((e) {
      if (e.name == 'changed') Sms.instance.changes.add((e.args['thread'] as num?)?.toInt() ?? -1);
    });
    _connected = link.connected.stream.listen((_) async {
      await _flush();
      // Whatever changed while the phone was away is read again.
      Sms.instance.changes.add(-1);
    });
  }

  void dispose() {
    _events?.cancel();
    _connected?.cancel();
  }

  /// The pairing is gone: nothing of the old phone's is kept.
  void forget() {
    _conversations = null;
    _messages.clear();
    _drafts.clear();
    _waiting.clear();
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async => (await _call(method, (arguments as Map?)?.cast<String, dynamic>() ?? const {})) as T?;

  Future<dynamic> _call(String method, Map<String, dynamic> a) async {
    switch (method) {
      // --- the phone's -------------------------------------------------------------------------------------------------
      case 'conversations':
        // Every conversation: asked for a lot at a time, since a phone with thousands has more than a frame carries.
        final all = <dynamic>[];
        int? at = 0;
        while (at != null) {
          final page = (await _call('conversationsPage', {'limit': lot, 'offset': at, 'pinned': at == 0})) as Map;
          all.addAll(page['items'] as List);
          at = (page['next'] as num?)?.toInt();
        }
        final seen = <Object?>{};
        return [for (final c in all) if (seen.add((c as Map)['id'])) c];
      case 'conversationsPage':
        try {
          final page = (await link.request('conversationsPage', a)) as Map;
          _remember(page['items'] as List);
          return page;
        } on LinkDown {
          // The phone is away: what was read last, all of it, as one lot.
          final had = _conversations;
          if (had == null) rethrow;
          final archived = a['archived'] == true;
          return {'items': [for (final c in had) if (!archived || (c as Map)['archived'] == true) c], 'next': null};
        }
      case 'conversation':
        final thread = (a['thread'] as num).toInt();
        try {
          final c = await link.request('conversation', a);
          if (c is Map) _remember([c]);
          return c;
        } on LinkDown {
          return _cached(thread);
        }
      case 'archivedCount':
        try {
          return await link.request('archivedCount');
        } on LinkDown {
          return (_conversations ?? const []).where((c) => (c as Map)['archived'] == true).length;
        }
      case 'messages':
        final thread = (a['thread'] as num).toInt();
        List<dynamic> list;
        try {
          list = _messages[thread] = (await link.request('messages', {'thread': thread, 'limit': a['limit'] ?? 300})) as List;
        } on LinkDown {
          list = _messages[thread] ?? const [];
        }
        // Newest first: what waits for the phone is the newest of all.
        return [for (final w in _waiting.reversed) if (w.thread == thread) w.message, ...list];
      case 'people':
        try {
          return await link.request('people', a);
        } on LinkDown {
          return _cached((a['thread'] as num).toInt())?['people'] ?? const [];
        }
      case 'send':
        return _send(a);
      case 'markRead':
        final thread = (a['thread'] as num).toInt();
        try {
          await link.request('markRead', {'thread': thread});
        } on LinkDown {
          return null;
        }
        final c = _cached(thread);
        if (c != null && c['unread'] == true) {
          c['unread'] = false;
          Sms.instance.changes.add(-1);
        }
        return null;
      case 'threadFor':
      case 'searchContacts':
        return link.request(method, a);
      case 'contact':
        try {
          return await link.request('contact', a);
        } on LinkDown {
          return {'address': a['address']};
        }
      case 'photo':
        try {
          final data = await link.request('photo', a);
          return data is String ? base64.decode(data) : null;
        } catch (_) {
          return null;
        }
      case 'part':
        return _part((a['id'] as num).toInt());
      case 'threadFlag':
      case 'archive':
        await link.request(method, a);
        return null;
      case 'draft':
        final thread = (a['thread'] as num).toInt();
        try {
          return await link.request('draft', a);
        } on LinkDown {
          return _drafts[thread];
        }
      case 'setDraft':
        final thread = (a['thread'] as num).toInt();
        _drafts[thread] = '${a['text'] ?? ''}';
        try {
          await link.request('setDraft', a);
        } catch (_) {}
        return null;
      case 'e2e':
        try {
          return await link.request('e2e', a);
        } catch (_) {
          return {'address': a['address'], 'state': 'none'};
        }

      // --- the Mac's own -----------------------------------------------------------------------------------------------
      case 'prefs':
        return Map<String, String>.of(_prefs);
      case 'setPref':
        _prefs['${a['key']}'] = '${a['value']}';
        await store.savePrefs(_prefs);
        return null;
      case 'status':
        return {'isDefault': true, 'contacts': true, 'notifications': true, 'phone': true};
      case 'update':
        return {'phase': 'disabled', 'current': link.app};
      case 'arriving':
        return <String, dynamic>{};
      case 'perfOn' || 'keyboardHere' || 'ghostPeers' || 'deskUnrestricted':
        return false;
      case 'e2eList' || 'blockedNumbers' || 'deskList':
        return const [];
      case 'deskState':
        return {'phase': 'none'};
      case 'setOpenThread' || 'openRequest' || 'systemPalette' || 'ownNumber' || 'e2eMine' || 'updateBackground' || 'updatePage' || 'updateCheck' || 'setAutoUpdate':
        return null;
      default:
        throw const PhoneError('That is done on the phone.');
    }
  }

  /// The most conversations asked of the phone at once (the phone hands over no more: android DeskCalls.LOT).
  static const lot = 250;

  /// Keeps [items] among the conversations read last, each in place of the one held under its id, newest first.
  void _remember(List<dynamic> items) {
    final byId = <Object?, dynamic>{for (final c in _conversations ?? const []) (c as Map)['id']: c, for (final c in items) (c as Map)['id']: c};
    _conversations = byId.values.toList()..sort((x, y) => (((y as Map)['date'] as num?) ?? 0).compareTo(((x as Map)['date'] as num?) ?? 0));
  }

  Map<String, dynamic>? _cached(int thread) {
    for (final c in _conversations ?? const []) {
      if (((c as Map)['id'] as num?)?.toInt() == thread) return c.cast<String, dynamic>();
    }
    return null;
  }

  /// A picture, fetched in pieces (the phone hands over at most a frame's worth at a time).
  Future<Uint8List?> _part(int id) async {
    try {
      final whole = BytesBuilder(copy: false);
      var total = -1;
      while (total < 0 || whole.length < total) {
        final piece = await link.request('part', {'id': id, 'offset': whole.length});
        if (piece is! Map) return null;
        total = (piece['total'] as num).toInt();
        final data = base64.decode(piece['data'] as String);
        if (data.isEmpty) break;
        whole.add(data);
      }
      return whole.takeBytes();
    } catch (_) {
      return null;
    }
  }

  static String _digits(String address) {
    final d = address.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 7 ? (d.length > 10 ? d.substring(d.length - 10) : d) : address.trim().toLowerCase();
  }

  /// The conversation with exactly these people, among those read last; -1 when it is not known.
  int _threadOf(List<String> addresses) {
    final want = addresses.map(_digits).toSet();
    for (final c in _conversations ?? const []) {
      final people = {for (final p in ((c as Map)['people'] as List? ?? const [])) _digits('${(p as Map)['address']}')};
      if (people.length == want.length && people.containsAll(want)) return (c['id'] as num).toInt();
    }
    return -1;
  }

  Future<int> _send(Map<String, dynamic> a) async {
    final addresses = [for (final x in (a['addresses'] as List? ?? const [])) '$x'];
    final body = '${a['body'] ?? ''}';
    if ((a['attachments'] as List?)?.isNotEmpty ?? false) throw const PhoneError('Pictures are sent from the phone.');
    final key = DeskCrypto.hex(DeskCrypto.randomBytes(12));
    try {
      final r = (await link.request('send', {'key': key, 'addresses': addresses, 'body': body})) as Map;
      return (r['thread'] as num).toInt();
    } on LinkDown {
      // The phone could not be reached (or went before it answered): the text waits here, under the same name, so
      // the phone sends it once however many times it is asked.
      final thread = _threadOf(addresses);
      if (thread < 0) throw const LinkDown('Your phone isn\'t reachable, and this would start a new conversation. Try again when it is back.');
      _waiting.add(_Waiting(key: key, thread: thread, addresses: addresses, body: body, id: _localId--));
      Sms.instance.changes.add(thread);
      return thread;
    }
  }

  /// The phone is back: what waited goes, oldest first.
  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      for (final w in List.of(_waiting)) {
        if (w.failed) continue;
        try {
          await link.request('send', {'key': w.key, 'addresses': w.addresses, 'body': w.body});
          _waiting.remove(w);
        } on LinkDown {
          return;
        } on PhoneError {
          w.failed = true;
        }
        Sms.instance.changes.add(w.thread);
      }
    } finally {
      _flushing = false;
    }
  }
}

/// A text typed while the phone could not be reached.
class _Waiting {
  _Waiting({required this.key, required this.thread, required this.addresses, required this.body, required this.id}) : date = DateTime.now();
  final String key;
  final int thread;
  final List<String> addresses;
  final String body;
  final int id;
  final DateTime date;
  bool failed = false;

  /// As the conversation draws it, among the phone's own messages.
  Map<String, dynamic> get message => {'id': id, 'kind': 'waiting', 'address': '', 'body': body, 'date': date.millisecondsSinceEpoch, 'outgoing': true, 'state': failed ? 'failed' : 'waiting', 'parts': const []};
}
