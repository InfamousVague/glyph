import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../sms.dart';
import 'cache.dart';
import 'link/crypto.dart';
import 'link/link.dart';
import 'link/session.dart';
import 'platform.dart';
import 'store.dart';
import 'updates.dart';

/// The phone's screens, on the Mac: every call they make of Android (lib/sms.dart) is answered here, by the phone
/// over the link where it is the phone's to answer, and by the Mac itself where it is the Mac's own (its theme, its
/// choices). What only the phone may do (delete, block, change encryption, send a picture) is refused in words.
///
/// **What was read is kept** (Matt, 2026-11-14: "cache messages on the desktop app so that we don't need to fetch
/// them all from the phone every time, just fetching updates in the background"): the conversations and each
/// conversation's messages, in memory and sealed on this computer's disk (cache.dart). The screens are answered from
/// what is kept, at once, the phone there or not. What is new is fetched behind them: the whole of a conversation
/// once each time the app runs (so what was deleted or changed far back is put right), and after that only its
/// newest few ([window]) each time the phone says it changed, joined to what is kept ([merged]). The screens are
/// told when what is kept has changed, and read it again. The phone is waited for only where nothing is kept, where
/// more is asked for than is kept (reading back), or after something done from here (a picture sent, a message
/// deleted), which must show what the phone made of it.
///
/// While the phone cannot be reached what is typed waits here, drawn as "Waiting for your phone", and goes when the
/// phone is back. Each text has a name the phone remembers, so one sent twice (its answer lost with the connection)
/// is sent once.
class LinkCalls implements SmsCalls, CapableCalls {
  LinkCalls(this.link, this.store);

  final PhoneLink link;
  final DeskStore store;

  Map<String, String> _prefs = {};

  /// What the phone does for a computer beyond the first few (android DeskCalls.CAPS): asked each time it is reached,
  /// since it may have been updated since. A phone from before there were any does none of them, and the screens
  /// offer none ([Sms.can]).
  @override
  Set<String> get caps => _caps;
  Set<String> _caps = const {};

  Future<void> _askCaps() async {
    Set<String> next;
    try {
      next = {for (final c in ((await link.request('caps')) as List? ?? const [])) '$c'};
    } on LinkDown {
      return;
    } catch (_) {
      next = const {};
    }
    if (next.length != _caps.length || !next.containsAll(_caps)) {
      _caps = next;
      Sms.instance.changes.add(-1);
    }
  }

  /// The app's own updates, once the app has handed them over ([attachUpdates]); none in a test that has none.
  MacUpdates? _updates;
  DateTime _looked = DateTime.fromMillisecondsSinceEpoch(0);

  /// Hands over the app's own updates: where they stand is told to the phone's screens (`Sms.instance.updates`), in
  /// the words the phone's own updater uses, each time it moves.
  void attachUpdates(MacUpdates updates) {
    _updates = updates;
    updates.addListener(() => Sms.instance.updates.add(UpdateState.from(updateState())));
  }

  /// Where the app's own update stands, as the phone's updater says it (android/.../Updater.kt): `ready` is the new
  /// version in place beside this one, and installing it is a restart.
  Map<String, Object?> updateState() {
    final u = _updates;
    final here = u?.installed;
    if (u == null || here == null) return {'phase': 'disabled', 'current': link.app};
    return {
      'phase': switch (u.phase) {
        MacUpdatePhase.idle => 'idle',
        MacUpdatePhase.checking => 'checking',
        MacUpdatePhase.downloading => 'downloading',
        MacUpdatePhase.ready => 'ready',
        MacUpdatePhase.restarting => 'installing',
        // There is a newer one this copy cannot put in place itself.
        MacUpdatePhase.manual => 'available',
        MacUpdatePhase.failed => 'failed',
      },
      'current': here.version,
      'available': u.release?.version,
      'progress': u.phase == MacUpdatePhase.downloading ? u.progress : null,
      'error': u.problem,
      'auto': true,
      'canInstall': u.phase != MacUpdatePhase.manual,
      'source': u.feed.host,
    };
  }

  List<dynamic>? _conversations;
  final Map<int, List<dynamic>> _messages = {};

  // --- what is kept, and how current it is ----------------------------------------------------------------------------

  /// What is kept on this computer's disk, sealed with a key made from the pairing's (cache.dart).
  late final DeskCache cache = DeskCache(Directory('${store.dir.path}/cache'), () {
    final phone = link.phone;
    return phone == null ? null : DeskCrypto.derive(phone.key, 'cache');
  });

  /// How many of a conversation's newest messages are asked for when the phone says it changed.
  static const window = 40;

  /// How many messages a conversation asks for as it opens (lib/ui/thread.dart): what is fetched ahead for the
  /// conversations at the top of the list.
  static const opening = 120;

  /// How many conversations at the top of the list have their messages fetched ahead, so they open at once.
  static const ahead = 8;

  /// How many times each conversation has been said to have changed, and the count it was last read at: it is
  /// current while the two agree. [_allChanged] counts the times everything may have ("the phone is back").
  final Map<int, int> _changed = {};
  final Map<int, int> _readAt = {};
  int _allChanged = 0;

  /// The conversations read whole since the app opened, how many messages each was asked for, and those whose next
  /// reading waits for the phone (something was done to them from here).
  final Set<int> _whole = {};
  final Map<int, int> _got = {};
  final Set<int> _hold = {};

  /// The conversations the phone has nothing older of than what is kept: asked for more, it gave fewer.
  final Set<int> _ended = {};
  final Map<int, Future<void>> _reading = {};

  /// The list is as the phone last gave it since it last said anything changed; the disk has been asked for it.
  bool _listCurrent = false;
  bool _listRead = false;

  /// Every conversation is among those kept (read whole from the phone, now or when the disk's were written), not
  /// just the first lot of them.
  bool _listWhole = false;
  Future<void>? _listReading;
  Timer? _listSaving;
  bool _fetchingAhead = false;

  int _count(int thread) => (_changed[thread] ?? 0) + _allChanged * 1000003;
  bool _current(int thread) => _readAt[thread] == _count(thread);
  void _stale(int thread) => _changed[thread] = (_changed[thread] ?? 0) + 1;

  static bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

  /// A conversation's newest messages ([recent], as the phone just gave them, newest first) joined to the ones kept
  /// ([had]): the newest are the phone's, and what is kept older than them stays. One that is kept among the newest
  /// and is no longer the phone's was deleted, and goes. Null where none of [recent] is among [had] though [recent]
  /// is a full [window]: more is new than was asked for, and the conversation is to be read whole.
  static List<dynamic>? merged(List<dynamic> had, List<dynamic> recent, {int window = LinkCalls.window}) {
    if (recent.isEmpty) return const [];
    String key(dynamic m) => '${(m as Map)['kind']}:${m['id']}';
    int date(dynamic m) => (((m as Map)['date'] as num?) ?? 0).toInt();
    final keys = {for (final m in recent) key(m)};
    if (recent.length >= window && had.isNotEmpty && !had.any((m) => keys.contains(key(m)))) return null;
    final oldest = recent.map(date).reduce(math.min);
    return [...recent, for (final m in had) if (!keys.contains(key(m)) && date(m) <= oldest) m];
  }

  /// Reads a conversation's messages from the phone and keeps them: whole the first time since the app opened (or
  /// where [limit] asks for more than is kept), its newest [window] after that. One reading at a time for a
  /// conversation. The screens are told when what is kept changed, unless [quiet] (the caller tells them). The
  /// phone away, what is kept stands.
  Future<void> _read(int thread, {int? limit, bool quiet = false}) {
    final next = (_reading[thread] ?? Future<void>.value()).catchError((_) {}).then((_) => _readNow(thread, limit: limit, quiet: quiet));
    _reading[thread] = next;
    return next.whenComplete(() {
      if (identical(_reading[thread], next)) _reading.remove(thread);
    });
  }

  Future<void> _readNow(int thread, {int? limit, required bool quiet}) async {
    final count = _count(thread);
    final had = _messages[thread];
    final want = math.max(limit ?? 0, _got[thread] ?? opening);
    // Read already since it last changed, with as many as are wanted.
    if (had != null && _readAt[thread] == count && want <= (_got[thread] ?? 0)) return;
    List<dynamic> next;
    try {
      List<dynamic>? joined;
      if (had != null && _whole.contains(thread) && want <= (_got[thread] ?? 0) && had.length > window) {
        joined = merged(had, (await link.request('messages', {'thread': thread, 'limit': window})) as List);
      }
      next = joined ?? (await link.request('messages', {'thread': thread, 'limit': want})) as List;
      if (joined == null) {
        _whole.add(thread);
        // Fewer than were asked for: that is all of it.
        next.length < want ? _ended.add(thread) : _ended.remove(thread);
      }
    } on LinkDown {
      return;
    } on PhoneError {
      return;
    }
    if (next.length > want) next = next.sublist(0, want);
    _got[thread] = want;
    _readAt[thread] = count;
    _hold.remove(thread);
    if (had == null || !_same(had, next)) {
      _messages[thread] = next;
      unawaited(cache.saveMessages(thread, next, want, ended: _ended.contains(thread)));
      if (!quiet) Sms.instance.changes.add(thread);
    }
  }

  /// What is kept of a conversation on the disk, brought into memory where it is not there yet.
  Future<void> _recall(int thread) async {
    if (_messages.containsKey(thread)) return;
    final kept = await cache.messages(thread);
    if (kept != null && !_messages.containsKey(thread)) {
      _messages[thread] = kept.items;
      _got[thread] = kept.limit;
      if (kept.ended) _ended.add(thread);
    }
  }

  /// The list as the disk has it, once, where the phone has not been asked yet.
  Future<void> _recallList() async {
    if (_listRead) return;
    _listRead = true;
    final kept = await cache.conversations();
    if (kept != null && _conversations == null) {
      _conversations = kept;
      _listWhole = true;
    }
  }

  void _saveListSoon() {
    // Only a whole list is kept on the disk: the first lot of one would be taken for all of it next time.
    if (!_listWhole) return;
    _listSaving?.cancel();
    _listSaving = Timer(const Duration(milliseconds: 300), () {
      final list = _conversations;
      if (list != null) unawaited(cache.saveConversations(list));
    });
  }

  /// Reads every conversation from the phone, a lot at a time, in place of the list kept. One that is gone from the
  /// phone is gone from here, with its messages. Throws [LinkDown] where the phone is away.
  Future<void> _readList({bool quiet = false}) => _listReading ??= _readListNow(quiet: quiet).whenComplete(() => _listReading = null);

  Future<void> _readListNow({required bool quiet}) async {
    final count = _allChanged;
    final all = <dynamic>[];
    int? at = 0;
    while (at != null) {
      final page = (await link.request('conversationsPage', {'limit': lot, 'offset': at, 'pinned': at == 0})) as Map;
      all.addAll(page['items'] as List);
      at = (page['next'] as num?)?.toInt();
    }
    final byId = <Object?, dynamic>{for (final c in all) (c as Map)['id']: c};
    final next = byId.values.toList()..sort((x, y) => (((y as Map)['date'] as num?) ?? 0).compareTo(((x as Map)['date'] as num?) ?? 0));
    final had = _conversations;
    for (final c in had ?? const []) {
      final id = ((c as Map)['id'] as num?)?.toInt();
      if (id != null && !byId.containsKey(c['id'])) _dropThread(id);
    }
    _conversations = next;
    _listWhole = true;
    _listCurrent = count == _allChanged;
    if (had == null || !_same(had, next)) {
      _saveListSoon();
      if (!quiet) Sms.instance.changes.add(-1);
    }
    unawaited(_fetchAhead());
  }

  /// One conversation's line in the list, read again from the phone; gone from here where it is gone from there.
  Future<void> _readOne(int thread) async {
    try {
      final c = await link.request('conversation', {'thread': thread});
      if (c is Map) {
        _remember([c]);
      } else if (_conversations != null) {
        _conversations = [for (final x in _conversations!) if (((x as Map)['id'] as num?)?.toInt() != thread) x];
        _dropThread(thread);
      }
      _saveListSoon();
    } on LinkDown {
      return;
    } on PhoneError {
      return;
    }
  }

  void _dropThread(int thread) {
    _messages.remove(thread);
    _got.remove(thread);
    _whole.remove(thread);
    _ended.remove(thread);
    unawaited(cache.forget(thread));
  }

  /// The conversations at the top of the list have their messages read behind the screens, one after another, so
  /// each opens at once: the ones kept get what is new, the ones never opened get what a conversation opens with.
  Future<void> _fetchAhead() async {
    if (_fetchingAhead) return;
    _fetchingAhead = true;
    try {
      for (final c in (_conversations ?? const []).take(ahead).toList()) {
        if (!link.online) return;
        final thread = ((c as Map)['id'] as num?)?.toInt();
        if (thread == null) continue;
        await _recall(thread);
        if (!_current(thread)) await _read(thread);
      }
    } finally {
      _fetchingAhead = false;
    }
  }

  /// The phone says a conversation changed (or, with -1, that something did): what is new is read behind the
  /// screens, and then they are told, and read what is kept.
  Future<void> _changedOnPhone(int thread) async {
    if (thread < 0) {
      _allChanged++;
      _listCurrent = false;
      try {
        await _readList(quiet: true);
      } on LinkDown {
        // Away again already: what is kept stands.
      } catch (_) {}
    } else {
      _stale(thread);
      await _recall(thread);
      await Future.wait([
        _readOne(thread),
        if (_messages.containsKey(thread)) _read(thread, quiet: true),
      ]);
    }
    Sms.instance.changes.add(thread);
  }

  /// Everything kept on this computer is thrown away, in memory and on the disk: the person asked. The screens read
  /// from the phone again.
  Future<void> clearKept() async {
    _forgetKept();
    await cache.clear();
    Sms.instance.changes.add(-1);
  }

  void _forgetKept() {
    _conversations = null;
    _messages.clear();
    _changed.clear();
    _readAt.clear();
    _whole.clear();
    _got.clear();
    _hold.clear();
    _ended.clear();
    _listCurrent = false;
    _listWhole = false;
    _listRead = true;
    _listSaving?.cancel();
  }
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
      if (e.name == 'changed') unawaited(_changedOnPhone((e.args['thread'] as num?)?.toInt() ?? -1));
    });
    if (link.online) unawaited(_askCaps());
    _connected = link.connected.stream.listen((_) async {
      await _askCaps();
      await _flush();
      // Whatever changed while the phone was away is read again: nothing kept is taken for current. The screens
      // read what is kept, and what is new comes in behind them.
      _allChanged++;
      _listCurrent = false;
      Sms.instance.changes.add(-1);
    });
  }

  void dispose() {
    _events?.cancel();
    _connected?.cancel();
    _listSaving?.cancel();
  }

  /// The pairing is gone: nothing of the old phone's is kept.
  void forget() {
    _forgetKept();
    unawaited(cache.clear());
    _drafts.clear();
    _waiting.clear();
    _videos.clear();
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async => (await _call(method, (arguments as Map?)?.cast<String, dynamic>() ?? const {})) as T?;

  Future<dynamic> _call(String method, Map<String, dynamic> a) async {
    switch (method) {
      // --- the phone's -------------------------------------------------------------------------------------------------
      case 'conversations':
        // Every conversation. Kept whole: answered at once, and read again behind the screens where it may have
        // changed. Not kept yet: read from the phone a lot at a time (a phone with thousands has more than a frame
        // carries) and waited for; away with only some of them read, those.
        await _recallList();
        if (!_listWhole) {
          try {
            await _readList(quiet: true);
          } on LinkDown {
            if (_conversations == null) rethrow;
          }
        } else if (!_listCurrent && link.online) {
          unawaited(_readList().catchError((_) {}));
        }
        return List<dynamic>.of(_conversations ?? const []);
      case 'conversationsPage':
        await _recallList();
        if (!_listWhole) {
          // The first time, with nothing whole kept: the phone is asked for the lot the list asks for, so the list
          // has something to show at once, and all of it is read behind that for the next time.
          try {
            final page = (await link.request('conversationsPage', a)) as Map;
            _remember(page['items'] as List);
            unawaited(_readList(quiet: true).catchError((_) {}));
            return page;
          } on LinkDown {
            if (_conversations == null) rethrow;
          }
        } else if (!_listCurrent && link.online) {
          // Kept whole: read again behind the screens where it may have changed; they are told if it differs.
          unawaited(_readList().catchError((_) {}));
        }
        // What is kept, all of it as one lot: there is nothing to wait for.
        if (((a['offset'] as num?)?.toInt() ?? 0) > 0) return {'items': const [], 'next': null};
        final archived = a['archived'] == true;
        return {'items': [for (final c in _conversations ?? const []) if (!archived || (c as Map)['archived'] == true) c], 'next': null};
      case 'conversation':
        final thread = (a['thread'] as num).toInt();
        await _recallList();
        // Its line in the list is kept current by what the phone says changed (_readOne).
        final kept = _cached(thread);
        if (kept != null) return kept;
        try {
          final c = await link.request('conversation', a);
          if (c is Map) {
            _remember([c]);
            _saveListSoon();
          }
          return c;
        } on LinkDown {
          return null;
        }
      case 'archivedCount':
        await _recallList();
        if (_conversations != null) return _conversations!.where((c) => (c as Map)['archived'] == true).length;
        try {
          return await link.request('archivedCount');
        } on LinkDown {
          return 0;
        }
      case 'messages':
        final thread = (a['thread'] as num).toInt();
        final limit = (a['limit'] as num?)?.toInt() ?? 300;
        await _recall(thread);
        final had = _messages[thread];
        if (had == null || (limit > (_got[thread] ?? 0) && !_ended.contains(thread)) || _hold.contains(thread)) {
          // Nothing kept, more asked for than is kept (reading back), or something was done to it from here: the
          // phone is waited for. Away, what is kept stands.
          await _read(thread, limit: limit, quiet: true);
        } else if (!_current(thread) && link.online) {
          // Kept: shown at once. What is new is read behind it, and the screens are told if it differs.
          unawaited(_read(thread));
        }
        // Newest first: what waits for the phone is the newest of all.
        return [for (final w in _waiting.reversed) if (w.thread == thread) w.message, ...?_messages[thread]];
      case 'people':
        await _recallList();
        final people = _cached((a['thread'] as num).toInt())?['people'];
        if (people != null) return people;
        try {
          return await link.request('people', a);
        } on LinkDown {
          return const [];
        }
      case 'send':
        return ((a['attachments'] as List?)?.isNotEmpty ?? false) ? _sendPictures(a) : _send(a);

      // --- what the message field has (Matt, 2026-11-14: "Add an emoji picker, file upload, voice memo and sticker
      // selector to the desktop app as well"): the Mac chooses, records and holds; the phone sends. What is sent is
      // handed over in pieces first ([_handOver]).
      case 'pickImages':
        return MacPlatform.pickPictures();
      case 'emoji':
        await MacPlatform.emoji();
        return null;
      case 'sendSticker':
        final sticker = a['picture'] as Uint8List;
        final sent = (await link.request('sendSticker', {'key': _name(), 'addresses': a['addresses'], 'name': a['name'], 'upload': await _handOver(sticker)})) as Map;
        return _went(sent);
      case 'voiceStart':
        // How long one may run is the phone's carrier's to say; the Mac's recorder stops itself there.
        final limit = (await link.request('voiceLimit')) as Map;
        final began = await MacPlatform.voiceStart((limit['bytes'] as num).toInt());
        if (began['ok'] == true) return {'ok': true, 'seconds': (limit['seconds'] as num).toInt()};
        if (began['denied'] == true) return {'ok': false, 'denied': true};
        throw PhoneError('${began['error'] ?? 'The microphone could not be started'}');
      case 'voiceLevel':
        final heard = await MacPlatform.voiceLevel();
        if (heard['full'] == true) Sms.instance.voiceFull.add(null);
        return (heard['level'] as num?)?.toDouble() ?? 0.0;
      case 'voiceCancel':
        await MacPlatform.voiceCancel();
        return null;
      case 'voiceSend':
        final sound = await MacPlatform.voiceStop();
        if (sound == null) throw const PhoneError('That was too short to send');
        final sent = (await link.request('sendVoice', {'key': _name(), 'addresses': a['addresses'], 'name': 'voice.m4a', 'upload': await _handOver(sound)})) as Map;
        return {'thread': _went(sent), 'millis': 0};
      case 'voicePlay':
        final part = (a['part'] as num).toInt();
        final sound = await _video(part);
        if (sound == null) throw const LinkDown('Your phone isn\'t reachable, and the voice message is on it. Try again when it is back.');
        final why = await MacPlatform.voicePlay(part, sound);
        if (why != null) throw PhoneError('Couldn\'t play it: $why.');
        return null;
      case 'voicePause':
        await MacPlatform.voicePause();
        return null;
      case 'voiceStop':
        await MacPlatform.voiceHalt();
        return null;
      case 'voiceLength':
        final sound = await _video((a['part'] as num).toInt());
        return sound == null ? 0 : await MacPlatform.voiceLength(sound);

      // --- what the phone's screens do to what is kept, done through the phone (android DeskCalls) ----------------
      case 'deleteMessage' || 'editMessage' || 'setBlocked' || 'e2eOff' || 'e2eVerify' || 'e2ePlainSeen':
        await link.request(method, a);
        _reread();
        return null;
      case 'deleteThread':
        await link.request('deleteThreads', {'threads': [a['thread']]});
        _reread();
        return null;
      case 'deleteThreads' || 'resendMms' || 'e2eOffer':
        final done = await link.request(method, a);
        _reread();
        return done;
      case 'e2eList' || 'blockedNumbers':
        if (!_caps.contains(method)) return const [];
        try {
          return await link.request(method, a);
        } on LinkDown {
          return const [];
        }
      case 'mmsStatus':
        if (!_caps.contains(method)) return const <String, dynamic>{};
        try {
          return await link.request(method, a);
        } on LinkDown {
          return const <String, dynamic>{};
        }
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
        // A picture chosen on this Mac for a message not yet sent (its path, where the phone's is an address of
        // Android's): drawn from where it is.
        if ('${a['uri']}'.startsWith('/')) {
          try {
            final file = File('${a['uri']}');
            return await file.length() > mostBytes ? null : await file.readAsBytes();
          } catch (_) {
            return null;
          }
        }
        try {
          final data = await link.request('photo', a);
          return data is String ? base64.decode(data) : null;
        } catch (_) {
          return null;
        }
      case 'part':
        return _part((a['id'] as num).toInt());
      // A video (lib/ui/video.dart): its bytes are the phone's, brought over as a picture's are; the Mac makes the
      // picture of where it starts, and plays it in a window of its own (macos/Runner/DeskVideo.swift).
      case 'videoPreview':
        final id = (a['part'] as num).toInt();
        final bytes = await _video(id);
        if (bytes == null) return null;
        final preview = await MacPlatform.videoPreview(id, bytes, '${a['ending'] ?? 'mp4'}');
        // How large its file is: the Mac holds it, having fetched it.
        return preview is Map ? {...preview, 'bytes': bytes.length} : preview;
      case 'videoPlay':
        final id = (a['part'] as num).toInt();
        final bytes = await _video(id);
        if (bytes == null) throw const LinkDown('Your phone isn\'t reachable, and the video is on it. Try again when it is back.');
        final why = await MacPlatform.videoPlay(id, bytes, '${a['ending'] ?? 'mp4'}', 'Video');
        if (why != null) throw PhoneError('Couldn\'t play it: $why.');
        return null;
      case 'threadFlag':
      case 'threadName':
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
      case 'openLink':
        // A link pressed in a message opens in this computer's own browser (Matt, 2026-11-14: "I can't click to
        // open links in the desktop app"): `open` on a Mac, handed the address alone, and only a web address.
        final url = '${a['url'] ?? ''}';
        final uri = Uri.tryParse(url);
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return false;
        final opener = Platform.isMacOS ? 'open' : Platform.isWindows ? 'explorer' : 'xdg-open';
        try {
          return (await Process.run(opener, [url])).exitCode == 0 || Platform.isWindows;
        } catch (_) {
          return false;
        }
      case 'prefs':
        return Map<String, String>.of(_prefs);
      case 'setPref':
        _prefs['${a['key']}'] = '${a['value']}';
        await store.savePrefs(_prefs);
        return null;
      case 'status':
        return {'isDefault': true, 'contacts': true, 'notifications': true, 'phone': true};
      // The app's own updates (updates.dart), told to the phone's screens in the phone's words, so the banner and
      // the Settings a phone has are the ones a computer has (Matt, 2026-11-14: "bring the same update banner we
      // have on mobile to the desktop app").
      case 'update':
        return updateState();
      case 'updateCheck':
        final u = _updates;
        if (u == null) return null;
        if (a['install'] == true && u.phase == MacUpdatePhase.ready) {
          await u.restart();
        } else {
          _looked = DateTime.now();
          unawaited(u.check());
        }
        return null;
      case 'updateInstall':
        await _updates?.restart();
        return null;
      case 'updatePage' || 'updateBackground':
        // As a page opens: a look, no oftener than every five minutes (the phone's Updater.pageCheck).
        final u = _updates;
        if (u != null && DateTime.now().difference(_looked) >= const Duration(minutes: 5)) {
          _looked = DateTime.now();
          unawaited(u.check());
        }
        return null;
      case 'arriving':
        return <String, dynamic>{};
      case 'perfOn' || 'keyboardHere' || 'ghostPeers' || 'deskUnrestricted':
        return false;
      case 'deskList':
        return const [];
      case 'deskState':
        return {'phase': 'none'};
      case 'ownNumber':
        // The phone's own (android DeskCalls), where it answers it; a phone before that has none to give.
        if (!_caps.contains('ownNumber')) return null;
        try {
          return await link.request('ownNumber');
        } on LinkDown {
          return null;
        }
      case 'me':
        // Settings › Me's number, verified through the phone (Me.followPhone); a code takes the phone a while.
        if (!_caps.contains('me')) throw const PhoneError('Update Ghost Messaging on your phone to verify your number from here.');
        return link.request('me', a, const Duration(seconds: 45));
      case 'setOpenThread' || 'openRequest' || 'systemPalette' || 'e2eMine' || 'setAutoUpdate':
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
  /// The last few videos brought over, so the one a picture was just made of is not fetched again to be played.
  final _videos = <int, Uint8List>{};

  Future<Uint8List?> _video(int id) async {
    final had = _videos.remove(id);
    final bytes = had ?? await _part(id);
    if (bytes == null || bytes.isEmpty) return null;
    _videos[id] = bytes;
    while (_videos.length > 4) {
      _videos.remove(_videos.keys.first);
    }
    return bytes;
  }

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

  /// A name for something sent, so the phone sends it once however many times it is asked.
  String _name() => DeskCrypto.hex(DeskCrypto.randomBytes(12));

  /// Hands [bytes] over to the phone a piece at a time under a name of their own, which the call that sends them
  /// gives: a frame carries less than a megabyte, and a picture is more.
  Future<String> _handOver(Uint8List bytes) async {
    if (bytes.isEmpty) throw const PhoneError('There is nothing in that to send');
    if (bytes.length > mostBytes) throw PhoneError('That is too large to send (${mostBytes ~/ (1024 * 1024)} MB at most)');
    final id = DeskCrypto.hex(DeskCrypto.randomBytes(8));
    for (var at = 0; at < bytes.length; at += piece) {
      final end = math.min(bytes.length, at + piece);
      await link.request('put', {'upload': id, 'offset': at, 'total': bytes.length, 'data': base64.encode(Uint8List.sublistView(bytes, at, end))});
    }
    return id;
  }

  /// As much as one frame carries, and the most the phone takes (android DeskCalls.PIECE, MOST_BYTES).
  static const piece = 384 * 1024;
  static const mostBytes = 12 * 1024 * 1024;

  /// Where what was sent went: read again, since it is in the conversation now.
  int _went(Map sent) {
    final thread = (sent['thread'] as num).toInt();
    // Its next reading waits for the phone: what was sent is to be seen as the phone has it.
    _stale(thread);
    _hold.add(thread);
    Sms.instance.changes.add(thread);
    return thread;
  }

  /// Something the phone keeps was changed from here: what was read is read again.
  void _reread() {
    // Nothing kept is taken for current, and each conversation's next reading waits for the phone, so what was
    // deleted or changed from here is not shown again from what is kept.
    _allChanged++;
    _listCurrent = false;
    _hold.addAll(_messages.keys);
    Sms.instance.changes.add(-1);
  }

  /// What a picture's file is, by its name's ending; null for what is not one the phone can make ready.
  static String? pictureType(String name) {
    final dot = name.lastIndexOf('.');
    return switch (dot < 0 ? '' : name.substring(dot + 1).toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/heic',
      'bmp' => 'image/bmp',
      _ => null,
    };
  }

  /// Pictures chosen on the Mac ([a]'s `attachments` are their paths), handed to the phone and sent as it sends its
  /// own: made to fit the carrier there, with the words beside them.
  Future<int> _sendPictures(Map<String, dynamic> a) async {
    final files = <Map<String, String>>[];
    for (final path in (a['attachments'] as List)) {
      final name = '$path'.split('/').last;
      final type = pictureType(name);
      if (type == null) throw PhoneError('$name isn\'t a picture. Only pictures can be sent from here for now.');
      final Uint8List bytes;
      try {
        bytes = await File('$path').readAsBytes();
      } catch (_) {
        throw PhoneError('$name couldn\'t be read.');
      }
      files.add({'upload': await _handOver(bytes), 'name': name, 'type': type});
    }
    final sent = (await link.request('sendPictures', {'key': _name(), 'addresses': a['addresses'], 'body': '${a['body'] ?? ''}', 'files': files})) as Map;
    return _went(sent);
  }

  Future<int> _send(Map<String, dynamic> a) async {
    final addresses = [for (final x in (a['addresses'] as List? ?? const [])) '$x'];
    final body = '${a['body'] ?? ''}';
    final key = _name();
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
