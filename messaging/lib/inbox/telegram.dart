import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../desktop/store.dart';
import 'inbox.dart';
import 'td_json.dart';

/// Telegram, as a Telegram app: TDLib (Telegram's own client library, lib/inbox/td_json.dart) signed in to the
/// person's account, its private chats and groups in a tab of the list, and replies sent from here.
///
/// Signing in is Telegram's own: a phone number, the code Telegram sends to the person's other Telegram apps (or by
/// text), and the two-step password where the account has one. TDLib keeps the session in its database in this app's
/// own folder; nothing about it leaves the device but to Telegram.
///
/// A Telegram app needs an app id and hash of its own, registered at my.telegram.org (Telegram's API terms: one per
/// developer; never the sample ones). They are given to the build (`--dart-define=TELEGRAM_API_ID=…` and
/// `TELEGRAM_API_HASH`, which tool/release.mjs and tool/release-mac.mjs read from ~/.config/ghostmessaging/telegram.env)
/// and are never in the repository. Without them, or without the library in the app, Telegram is [InboxState.unavailable].
class Telegram extends InboxNetwork {
  Telegram({this.transport, this.apiId = const int.fromEnvironment('TELEGRAM_API_ID'), this.apiHash = const String.fromEnvironment('TELEGRAM_API_HASH'), this.folder});

  /// A stand-in for TDLib, in tests. Null: TDLib itself, once [start] finds it.
  final Future<TdTransport?> Function()? transport;
  final int apiId;
  final String apiHash;

  /// Where TDLib keeps its database. Null: this app's own folder.
  final String? folder;

  @override
  String get id => 'telegram';
  @override
  String get name => 'Telegram';

  TdTransport? _td;
  StreamSubscription<Map<String, Object?>>? _sub;
  AppState? _app;
  InboxState _state = InboxState.unavailable;
  InboxStep _step = InboxStep.none;
  String? _error, _account, _passwordHint, _codeWhere;
  int _asked = 0;
  final Map<String, Completer<Map<String, Object?>>> _waiting = {};

  /// What TDLib has said of each chat and user, by id.
  final Map<int, Map<String, Object?>> _chatsById = {};
  final Map<int, int> _order = {};
  final Map<int, String> _users = {};
  final Map<String, List<InboxMessage>> _messages = {};
  final Set<String> _exhausted = {};
  List<InboxChat> _chats = const [];
  String? _watching;

  @override
  InboxState get state => _state;
  @override
  InboxStep get step => _step;
  @override
  String? get error => _error;
  @override
  String? get account => _account;
  @override
  List<InboxChat> get chats => _chats;
  @override
  List<InboxMessage> messagesOf(String chatId) => _messages[chatId] ?? const [];

  /// The hint for the two-step password, where Telegram has one.
  String? get passwordHint => _passwordHint;

  /// Where the code was sent ("your Telegram app", "a text to …"), once asked.
  String? get codeWhere => _codeWhere;

  /// Whether this build can run Telegram at all: it has an app id, and (on a Mac or Android) the library.
  bool get configured => apiId != 0 && apiHash.isNotEmpty;

  @override
  Future<void> start(AppState app) async {
    _app = app;
    if (!configured) return;
    // TDLib is started only for someone who began signing in: until then the app does not load it at all.
    if (!app.flag('tg_used', fallback: false)) {
      _state = InboxState.signedOut;
      notifyListeners();
      return;
    }
    await _open();
  }

  /// Begins signing in (or, after an app restart, carries on where it was).
  Future<void> begin() async {
    if (!configured) {
      _state = InboxState.unavailable;
      _error = 'Telegram isn\'t in this build of the app.';
      notifyListeners();
      return;
    }
    _app?.setFlag('tg_used', true);
    _error = null;
    if (_td == null) {
      await _open();
    } else {
      notifyListeners();
    }
  }

  Future<void> _open() async {
    if (_td != null) return;
    final td = await (transport ?? TdJson.start)();
    if (td == null) {
      _state = InboxState.unavailable;
      _error = 'Telegram isn\'t in this build of the app.';
      notifyListeners();
      return;
    }
    _td = td;
    _sub = td.received.listen(_received);
    _state = InboxState.signingIn;
    notifyListeners();
    // Asking for the state makes TDLib say it (updateAuthorizationState follows).
    td.send({'@type': 'getAuthorizationState'});
  }

  // --- signing in ----------------------------------------------------------------------------------------------------

  Future<void> sendPhone(String phone) => _auth({'@type': 'setAuthenticationPhoneNumber', 'phone_number': phone.trim()});
  Future<void> sendCode(String code) => _auth({'@type': 'checkAuthenticationCode', 'code': code.trim()});
  Future<void> sendPassword(String password) => _auth({'@type': 'checkAuthenticationPassword', 'password': password});

  Future<void> _auth(Map<String, Object?> request) async {
    _error = null;
    notifyListeners();
    final r = await _ask(request);
    if (r['@type'] == 'error') {
      _error = _plain(r);
      notifyListeners();
    }
  }

  @override
  Future<void> signOut() async {
    final td = _td;
    _app?.setFlag('tg_used', false);
    if (td != null && _state == InboxState.ready) {
      await _ask({'@type': 'logOut'}).timeout(const Duration(seconds: 10), onTimeout: () => const {});
    }
    _forget();
    _state = configured ? InboxState.signedOut : InboxState.unavailable;
    _step = InboxStep.none;
    notifyListeners();
  }

  void _forget() {
    _chatsById.clear();
    _order.clear();
    _users.clear();
    _messages.clear();
    _exhausted.clear();
    _chats = const [];
    _account = null;
  }

  void _authState(Map<String, Object?> s) {
    _step = InboxStep.none;
    switch (s['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        _parameters();
        return;
      case 'authorizationStateWaitPhoneNumber':
        _state = InboxState.signingIn;
        _step = InboxStep.phone;
      case 'authorizationStateWaitCode':
        _state = InboxState.signingIn;
        _step = InboxStep.code;
        final info = s['code_info'] as Map?;
        _codeWhere = switch ((info?['type'] as Map?)?['@type']) {
          'authenticationCodeTypeTelegramMessage' => 'your Telegram app on another device',
          'authenticationCodeTypeSms' || 'authenticationCodeTypeSmsWord' || 'authenticationCodeTypeSmsPhrase' => 'a text to ${info?['phone_number'] ?? 'your phone'}',
          'authenticationCodeTypeCall' => 'a phone call',
          'authenticationCodeTypeFragment' => 'Fragment',
          'authenticationCodeTypeFirebaseAndroid' || 'authenticationCodeTypeFirebaseIos' => 'a text to ${info?['phone_number'] ?? 'your phone'}',
          _ => 'Telegram',
        };
      case 'authorizationStateWaitPassword':
        _state = InboxState.signingIn;
        _step = InboxStep.password;
        final hint = (s['password_hint'] as String?)?.trim();
        _passwordHint = hint == null || hint.isEmpty ? null : hint;
      case 'authorizationStateWaitEmailAddress' || 'authorizationStateWaitEmailCode' || 'authorizationStateWaitRegistration':
        _state = InboxState.signingIn;
        _step = InboxStep.phone;
        _error = 'Finish setting up this account in Telegram\'s own app first, then sign in here.';
      case 'authorizationStateWaitOtherDeviceConfirmation':
        _state = InboxState.signingIn;
        _step = InboxStep.phone;
        _error = 'Telegram asked to confirm this on another device. Sign in with your number here instead.';
      case 'authorizationStateReady':
        _state = InboxState.ready;
        _error = null;
        _ready();
      case 'authorizationStateLoggingOut' || 'authorizationStateClosing':
        _state = InboxState.signingIn;
      case 'authorizationStateClosed':
        // TDLib closes for good after a log out: a new client is made for the next sign-in.
        _sub?.cancel();
        _td?.close();
        _td = null;
        _forget();
        _state = configured ? InboxState.signedOut : InboxState.unavailable;
    }
    notifyListeners();
  }

  void _parameters() {
    final dir = folder ?? _folder();
    _td?.send({
      '@type': 'setTdlibParameters',
      'use_test_dc': false,
      'database_directory': '$dir/db',
      'files_directory': '$dir/files',
      'database_encryption_key': '',
      'use_file_database': false,
      'use_chat_info_database': true,
      'use_message_database': true,
      'use_secret_chats': false,
      'api_id': apiId,
      'api_hash': apiHash,
      'system_language_code': 'en',
      'device_model': Platform.isMacOS ? 'Mac' : 'Android',
      'system_version': Platform.operatingSystemVersion,
      'application_version': const String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: 'Ghost Messaging'),
    });
  }

  /// This app's own folder: Android's private data folder (the cache folder's parent), the Mac's support folder.
  static String _folder() {
    if (Platform.isAndroid) return '${Directory.systemTemp.parent.path}/files/tdlib';
    return '${DeskStore.defaultDir().path}/tdlib';
  }

  void _ready() {
    _ask({'@type': 'getMe'}).then((me) {
      if (me['@type'] != 'user') return;
      final name = [me['first_name'], me['last_name']].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      final usernames = (me['usernames'] as Map?)?['active_usernames'] as List?;
      _account = usernames != null && usernames.isNotEmpty ? '@${usernames.first}' : (name.isEmpty ? null : name);
      notifyListeners();
    });
    unawaited(_loadAll());
  }

  /// Every chat, not only the first hundred (Matt, 2026-11-15: "import telegram chats sorted by most recent with the
  /// profile pictures and all"): TDLib is asked for more until it says there are none (a 404).
  Future<void> _loadAll() async {
    for (var i = 0; i < 50; i++) {
      final r = await _ask({'@type': 'loadChats', 'chat_list': {'@type': 'chatListMain'}, 'limit': 100});
      if (r['@type'] == 'error') break;
    }
    // And Telegram's archive, which Ghost's Archived page shows among archived texts.
    for (var i = 0; i < 20; i++) {
      final r = await _ask({'@type': 'loadChats', 'chat_list': {'@type': 'chatListArchive'}, 'limit': 100});
      if (r['@type'] == 'error') break;
    }
  }

  /// The file ids of chats' pictures asked for, so each is asked for once.
  final Set<int> _photosAsked = {};

  /// The chat's picture as a file on this device, once TDLib has brought it down; asked for the first time it is seen.
  String? _photo(Map<String, Object?> c) {
    final small = ((c['photo'] as Map?)?['small'] as Map?);
    if (small == null) return null;
    final local = small['local'] as Map?;
    final path = local?['path'] as String?;
    if (local?['is_downloading_completed'] == true && path != null && path.isNotEmpty) return path;
    final file = (small['id'] as num?)?.toInt();
    if (file != null && _photosAsked.add(file)) {
      _td?.send({'@type': 'downloadFile', 'file_id': file, 'priority': 1, 'offset': 0, 'limit': 0, 'synchronous': false});
    }
    return null;
  }

  /// A file TDLib brought down: the chats whose picture it is take it.
  void _fileUpdated(Map file) {
    final fileId = (file['id'] as num?)?.toInt();
    if (fileId == null || (file['local'] as Map?)?['is_downloading_completed'] != true) return;
    var changed = false;
    for (final e in _chatsById.entries.toList()) {
      final photo = e.value['photo'] as Map?;
      if ((((photo?['small'] as Map?)?['id']) as num?)?.toInt() != fileId) continue;
      _chatsById[e.key] = {...e.value, 'photo': {...photo!, 'small': file}};
      changed = true;
    }
    if (changed) _rebuild();
  }

  // --- chats and messages --------------------------------------------------------------------------------------------

  void _received(Map<String, Object?> m) {
    final extra = m['@extra'];
    if (extra is String && _waiting.containsKey(extra)) {
      _waiting.remove(extra)!.complete(m);
      return;
    }
    switch (m['@type']) {
      case 'updateAuthorizationState':
        _authState((m['authorization_state'] as Map).cast<String, Object?>());
      case 'updateUser':
        final u = m['user'] as Map;
        if ((u['type'] as Map?)?['@type'] == 'userTypeBot') _bots.add((u['id'] as num).toInt());
        final name = [u['first_name'], u['last_name']].whereType<String>().where((s) => s.isNotEmpty).join(' ');
        _users[(u['id'] as num).toInt()] = name.isEmpty ? 'Someone' : name;
      case 'updateNewChat':
        final c = (m['chat'] as Map).cast<String, Object?>();
        final id = (c['id'] as num).toInt();
        _chatsById[id] = c;
        for (final p in (c['positions'] as List? ?? const [])) {
          _position(id, p as Map);
        }
        _rebuild();
      case 'updateChatTitle':
        _patch(m, {'title': m['title']});
      case 'updateChatPhoto':
        _patch(m, {'photo': m['photo']});
      case 'updateFile':
        _fileUpdated(m['file'] as Map);
      case 'updateChatLastMessage':
        _patch(m, {'last_message': m['last_message']});
        for (final p in (m['positions'] as List? ?? const [])) {
          _position((m['chat_id'] as num).toInt(), p as Map);
        }
        _rebuild();
      case 'updateChatPosition':
        _position((m['chat_id'] as num).toInt(), m['position'] as Map);
        _rebuild();
      case 'updateChatReadInbox':
        _patch(m, {'unread_count': m['unread_count']});
      case 'updateNewMessage':
        final msg = (m['message'] as Map).cast<String, Object?>();
        _add('${msg['chat_id']}', [_message(msg)]);
      case 'updateMessageSendSucceeded':
        final msg = (m['message'] as Map).cast<String, Object?>();
        final chat = '${msg['chat_id']}';
        final old = '${m['old_message_id']}';
        _messages[chat] = [for (final x in messagesOf(chat)) if (x.id != old) x];
        _add(chat, [_message(msg)]);
      case 'updateMessageSendFailed':
        final msg = (m['message'] as Map).cast<String, Object?>();
        final chat = '${msg['chat_id']}';
        final old = '${m['old_message_id']}';
        _messages[chat] = [for (final x in messagesOf(chat)) x.id == old ? InboxMessage(id: x.id, text: x.text, date: x.date, mine: true, state: 'failed') : x];
        _error = _plain(m['error'] as Map? ?? const {});
        notifyListeners();
      case 'updateDeleteMessages':
        if (m['is_permanent'] == true) {
          final chat = '${m['chat_id']}';
          final gone = {for (final i in (m['message_ids'] as List? ?? const [])) '$i'};
          _messages[chat] = [for (final x in messagesOf(chat)) if (!gone.contains(x.id)) x];
          notifyListeners();
        }
    }
  }

  void _patch(Map<String, Object?> m, Map<String, Object?> fields) {
    final id = (m['chat_id'] as num).toInt();
    final c = _chatsById[id];
    if (c == null) return;
    _chatsById[id] = {...c, ...fields};
    _rebuild();
  }

  void _position(int chat, Map p) {
    final list = (p['list'] as Map?)?['@type'];
    final orders = switch (list) { 'chatListMain' => _order, 'chatListArchive' => _archOrder, _ => null };
    if (orders == null) return;
    final order = int.tryParse('${p['order']}') ?? 0;
    if (order == 0) {
      orders.remove(chat);
    } else {
      orders[chat] = order;
    }
    if (list == 'chatListMain') {
      if (p['is_pinned'] == true && order != 0) {
        _pinned.add(chat);
      } else {
        _pinned.remove(chat);
      }
    }
  }

  /// The users that are bots, which sign-in codes may come from as Telegram's own account's do.
  final Set<int> _bots = {};

  /// Pinned chats in the main list.
  final Set<int> _pinned = {};

  @override
  Future<void> pin(String chatId, bool pinned) async {
    final r = await _ask({'@type': 'toggleChatIsPinned', 'chat_list': {'@type': 'chatListMain'}, 'chat_id': int.parse(chatId), 'is_pinned': pinned});
    if (r['@type'] == 'error') _error = _plain(r);
    notifyListeners();
  }

  /// The chats in Telegram's own archive, by their order there.
  final Map<int, int> _archOrder = {};
  List<InboxChat> _archived = const [];

  @override
  List<InboxChat> get archivedChats => _archived;

  bool _writable(int id) {
    final type = (_chatsById[id]?['type'] as Map?);
    if (type == null) return false;
    return !(type['@type'] == 'chatTypeSupergroup' && type['is_channel'] == true);
  }

  /// Into Telegram's archive, or back to the main list, as Telegram's own Archive does.
  @override
  Future<void> archive(String chatId, bool archived) async {
    final r = await _ask({'@type': 'addChatToList', 'chat_id': int.parse(chatId), 'chat_list': {'@type': archived ? 'chatListArchive' : 'chatListMain'}});
    if (r['@type'] == 'error') _error = _plain(r);
    notifyListeners();
  }

  /// Deleted for this account, as Telegram's Delete chat does: a group is left first, then its history goes.
  @override
  Future<void> deleteChat(String chatId) async {
    final id = int.parse(chatId);
    final type = (_chatsById[id]?['type'] as Map?)?['@type'];
    if (type == 'chatTypeBasicGroup' || type == 'chatTypeSupergroup') await _ask({'@type': 'leaveChat', 'chat_id': id});
    final r = await _ask({'@type': 'deleteChatHistory', 'chat_id': id, 'remove_from_chat_list': true, 'revoke': false});
    if (r['@type'] == 'error') {
      _error = _plain(r);
    } else {
      _order.remove(id);
      _archOrder.remove(id);
      _messages.remove(chatId);
      _rebuild();
    }
    notifyListeners();
  }

  /// The messages Telegram says can be deleted for everyone.
  final Set<String> _forAll = {};

  @override
  bool canDeleteForEveryone(String chatId, InboxMessage message) => _forAll.contains('$chatId/${message.id}');

  @override
  Future<void> deleteMessage(String chatId, String messageId, {bool forEveryone = false}) async {
    final r = await _ask({'@type': 'deleteMessages', 'chat_id': int.parse(chatId), 'message_ids': [int.parse(messageId)], 'revoke': forEveryone});
    if (r['@type'] == 'error') {
      _error = _plain(r);
    } else {
      _messages[chatId] = [for (final x in messagesOf(chatId)) if (x.id != messageId) x];
    }
    notifyListeners();
  }

  /// The chats the list shows: those in the main list that can be written in (private chats and groups, not
  /// channels), the newest first, as they stand among the texts.
  void _rebuild() {
    final ids = _order.keys.where(_writable).toList();
    _chats = [for (final id in ids) _chat(_chatsById[id]!)]..sort((a, b) => b.date.compareTo(a.date));
    _archived = [for (final id in _archOrder.keys.where((id) => _writable(id) && !_order.containsKey(id))) _chat(_chatsById[id]!)]..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  InboxChat _chat(Map<String, Object?> c) {
    final last = c['last_message'] as Map?;
    final type = (c['type'] as Map?)?['@type'];
    return InboxChat(
      network: id,
      id: '${c['id']}',
      title: (c['title'] as String?)?.trim().isNotEmpty == true ? c['title'] as String : 'Telegram',
      date: last == null ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.fromMillisecondsSinceEpoch(((last['date'] as num?) ?? 0).toInt() * 1000),
      snippet: last == null ? '' : _text(last),
      unread: (c['unread_count'] as num?)?.toInt() ?? 0,
      group: type == 'chatTypeBasicGroup' || type == 'chatTypeSupergroup',
      lastFromMe: last?['is_outgoing'] == true,
      avatar: _photo(c),
      pinned: _pinned.contains(c['id']),
      // Telegram's own account (777000, which sends its sign-in codes) and bots.
      service: type == 'chatTypePrivate' && (((c['type'] as Map)['user_id'] as num?)?.toInt() == 777000 || _bots.contains(((c['type'] as Map)['user_id'] as num?)?.toInt())),
    );
  }

  InboxMessage _message(Map<String, Object?> m) {
    if (m['can_be_deleted_for_all_users'] == true) _forAll.add('${m['chat_id']}/${m['id']}');
    final sender = m['sender_id'] as Map?;
    final user = (sender?['user_id'] as num?)?.toInt();
    final sending = (m['sending_state'] as Map?)?['@type'];
    return InboxMessage(
      id: '${m['id']}',
      text: _text(m),
      date: DateTime.fromMillisecondsSinceEpoch(((m['date'] as num?) ?? 0).toInt() * 1000),
      mine: m['is_outgoing'] == true,
      sender: user == null ? '' : (_users[user] ?? ''),
      state: sending == 'messageSendingStatePending' ? 'sending' : (sending == 'messageSendingStateFailed' ? 'failed' : 'sent'),
    );
  }

  /// A message's words, or what it is where it has none to show (a picture, a voice message…).
  static String _text(Map m) {
    final c = m['content'] as Map? ?? const {};
    String caption(String what) {
      final t = ((c['caption'] as Map?)?['text'] as String?)?.trim();
      return t == null || t.isEmpty ? what : '$what: $t';
    }

    return switch (c['@type']) {
      'messageText' => ((c['text'] as Map?)?['text'] as String?) ?? '',
      'messagePhoto' => caption('Photo'),
      'messageVideo' => caption('Video'),
      'messageAnimation' => caption('GIF'),
      'messageDocument' => caption('File'),
      'messageAudio' => caption('Audio'),
      'messageVoiceNote' => caption('Voice message'),
      'messageVideoNote' => 'Video message',
      'messageSticker' => '${(c['sticker'] as Map?)?['emoji'] ?? ''} Sticker'.trim(),
      'messageLocation' || 'messageVenue' => 'Location',
      'messageContact' => 'Contact',
      'messagePoll' => 'Poll',
      'messageCall' => 'Call',
      _ => 'Message',
    };
  }

  void _add(String chat, List<InboxMessage> got) {
    final held = {for (final m in messagesOf(chat)) m.id: m};
    for (final m in got) {
      held[m.id] = m;
    }
    _messages[chat] = held.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
  }

  @override
  Future<void> load(String chatId, {bool older = false}) async {
    if (_state != InboxState.ready) return;
    final held = messagesOf(chatId);
    if (older && _exhausted.contains(chatId)) return;
    var from = older && held.isNotEmpty ? int.tryParse(held.first.id) ?? 0 : 0;
    // TDLib may answer with fewer than asked (often one, the first time): asked again from the oldest got, a few
    // times, so a chat opens with a screenful.
    var got = 0;
    for (var round = 0; round < 4 && got < 30; round++) {
      final r = await _ask({'@type': 'getChatHistory', 'chat_id': int.parse(chatId), 'from_message_id': from, 'offset': 0, 'limit': 50, 'only_local': false});
      if (r['@type'] != 'messages') break;
      final list = [for (final m in (r['messages'] as List? ?? const [])) (m as Map).cast<String, Object?>()];
      if (list.isEmpty) {
        _exhausted.add(chatId);
        break;
      }
      _add(chatId, [for (final m in list) _message(m)]);
      got += list.length;
      from = (list.last['id'] as num).toInt();
    }
  }

  /// Whether [chatId] may have messages before the oldest held.
  bool hasOlder(String chatId) => !_exhausted.contains(chatId);

  @override
  Future<void> send(String chatId, String text) async {
    text = text.trim();
    if (text.isEmpty || _state != InboxState.ready) return;
    final r = await _ask({
      '@type': 'sendMessage',
      'chat_id': int.parse(chatId),
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': text},
      },
    });
    if (r['@type'] == 'message') {
      _add(chatId, [_message(r)]);
    } else {
      _error = _plain(r);
      notifyListeners();
    }
  }

  @override
  Future<void> markRead(String chatId) async {
    if (_state != InboxState.ready) return;
    final ids = [for (final m in messagesOf(chatId)) if (!m.mine) int.tryParse(m.id)].whereType<int>().toList();
    if (ids.isEmpty) return;
    _td?.send({'@type': 'viewMessages', 'chat_id': int.parse(chatId), 'message_ids': ids.length > 100 ? ids.sublist(ids.length - 100) : ids, 'force_read': true});
  }

  @override
  set watching(String? chatId) {
    final was = _watching;
    _watching = chatId;
    if (_state != InboxState.ready) return;
    // An open chat is told to TDLib, so its updates come and reading it counts as read.
    if (was != null && was != chatId) _td?.send({'@type': 'closeChat', 'chat_id': int.parse(was)});
    if (chatId != null && chatId != was) _td?.send({'@type': 'openChat', 'chat_id': int.parse(chatId)});
  }

  Future<Map<String, Object?>> _ask(Map<String, Object?> request) {
    final td = _td;
    if (td == null) return Future.value(const {'@type': 'error', 'message': 'Telegram isn\'t running'});
    final key = 'q${++_asked}';
    final done = Completer<Map<String, Object?>>();
    _waiting[key] = done;
    td.send({...request, '@extra': key});
    return done.future.timeout(const Duration(seconds: 30), onTimeout: () {
      _waiting.remove(key);
      return const {'@type': 'error', 'message': 'Telegram took too long to answer'};
    });
  }

  /// An error from TDLib, in words for the page.
  static String _plain(Map e) {
    final said = '${e['message'] ?? ''}';
    return switch (said) {
      'PHONE_NUMBER_INVALID' => 'That phone number isn\'t one Telegram knows. Include the country code, like +1.',
      'PHONE_CODE_INVALID' => 'That code isn\'t right.',
      'PHONE_CODE_EXPIRED' => 'That code has run out. Ask for a new one.',
      'PASSWORD_HASH_INVALID' => 'That password isn\'t right.',
      'PHONE_NUMBER_BANNED' => 'Telegram has banned this number.',
      'API_ID_INVALID' || 'API_ID_PUBLISHED_FLOOD' => 'This build\'s Telegram app id was refused.',
      'CHAT_WRITE_FORBIDDEN' || 'USER_IS_BLOCKED' => 'You can\'t write in this chat.',
      _ when said.startsWith('Too Many Requests') || said.startsWith('FLOOD_WAIT') => 'Telegram asks to wait before trying again.',
      _ => said.isEmpty ? 'Telegram said no.' : said,
    };
  }

  bool _disposed = false;

  /// Answers still coming after the app let go of it (a sign-out, a test's end) change nothing.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _td?.close();
    super.dispose();
  }
}

@visibleForTesting
String telegramPlain(Map e) => Telegram._plain(e);
