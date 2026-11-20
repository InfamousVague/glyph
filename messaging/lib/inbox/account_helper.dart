import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;

import '../app_state.dart';
import '../desktop/store.dart';
import '../sms.dart';
import 'cookie_paste.dart';
import 'inbox.dart';
import 'signal.dart' show signalReactions;

/// What an account helper is to the app: lines out, lines in. A process in the app; a stand-in in a test.
abstract class HelperLink {
  Stream<Map<String, Object?>> get heard;
  void say(Map<String, Object?> line);
  Future<void> close();
}

/// One of the services reached by an account helper (sidecar/ACCOUNT_HELPERS.md): what it is called, which helper
/// runs it, and how the person signs in (the cookies of a browser signed in to it).
@immutable
class HelperService {
  const HelperService({
    required this.id,
    required this.name,
    required this.helper,
    required this.library,
    required this.signInUrl,
    required this.cookieSite,
    required this.needed,
    this.optional = const [],
    required this.copyFrom,
    this.also = '',
  });

  /// The network's id in the app ("messenger"), and its name as people know it.
  final String id;
  final String name;

  /// The helper's name: `<helper>-sidecar` beside the app on a computer, `lib<helper>sidecar.so` on the phone.
  final String helper;

  /// The open-source library the helper is built on, for the warning.
  final String library;

  /// Where the person signs in, in a private window, and the site whose cookies are copied.
  final String signInUrl;
  final String cookieSite;

  /// The cookies the helper cannot do without, and those it takes too where they are there.
  final List<String> needed;
  final List<String> optional;

  /// Which request to copy in the browser's developer tools, in words.
  final String copyFrom;

  /// Something more this service's sign-in does that the person should know first, added to the warning.
  final String also;

  /// What the person is told before signing in, and in its Settings. None of these services allows other apps.
  String get warning =>
      '$name doesn\'t support or allow other apps. Ghost signs in as you, with the session of a browser signed in to your account, through the open-source $library library, and behaves as the website does. $name may ask you to confirm it\'s you, sign that session out, or restrict accounts it finds using unofficial apps.${also.isEmpty ? '' : ' $also'}';
}

/// Facebook Messenger, Instagram and LinkedIn (Matt, 2026-11-20: "Let's do the feasible ones but skip X and google
/// voice").
const messengerService = HelperService(
  id: 'messenger',
  name: 'Messenger',
  helper: 'messenger',
  library: 'mautrix-meta',
  signInUrl: 'https://www.messenger.com/',
  cookieSite: 'messenger.com or facebook.com',
  needed: ['xs', 'c_user', 'datr'],
  optional: ['sb', 'fr', 'wd', 'presence', 'oo', 'dpr'],
  copyFrom: 'any request to www.messenger.com (or www.facebook.com)',
  // sidecar/messenger: encrypted chats need a device of their own on the account (README, "End-to-end encrypted chats").
  also: 'To read end-to-end encrypted chats Ghost is added to your account as another device, which Messenger lists among your devices; encrypted messages from before you sign in stay in Messenger.',
);
const instagramService = HelperService(
  id: 'instagram',
  name: 'Instagram',
  helper: 'instagram',
  library: 'mautrix-meta',
  signInUrl: 'https://www.instagram.com/direct/inbox/',
  cookieSite: 'instagram.com',
  needed: ['sessionid', 'csrftoken', 'ds_user_id'],
  optional: ['mid', 'ig_did', 'rur', 'shbid', 'shbts', 'datr', 'dpr'],
  copyFrom: 'any request to www.instagram.com',
);
const linkedInService = HelperService(
  id: 'linkedin',
  name: 'LinkedIn',
  helper: 'linkedin',
  library: 'mautrix-linkedin',
  signInUrl: 'https://www.linkedin.com/messaging/',
  cookieSite: 'linkedin.com',
  needed: ['li_at', 'JSESSIONID'],
  // The helper takes every cookie of the site it is given: LinkedIn checks more than the two that sign it in.
  optional: [],
  copyFrom: 'any request to www.linkedin.com/voyager',
);

/// A network reached by an account helper: Messenger, Instagram or LinkedIn. The helper (sidecar/messenger,
/// sidecar/instagram, sidecar/linkedin) runs as a child process and speaks sidecar/ACCOUNT_HELPERS.md; this class is
/// the same for all three, told apart by [service].
///
/// Signing in is the cookies of a browser signed in to the account, pasted as a copied request ([signIn]), after the
/// warning ([HelperService.warning]) is agreed to. The service lists the chats (`chat` events) and sends what is said
/// from then on; older messages of a chat are asked for as it is opened and scrolled ([load]). What has come is kept
/// here ([_file]), the newest [_mostKept] of a chat, so the list is there before the helper has connected.
class AccountHelper extends InboxNetwork {
  AccountHelper(this.service, {this.soon = false, this.link, this.folder});

  final HelperService service;

  @override
  final bool soon;

  /// The helper, in a test. Null: the process, once [start] finds it.
  final Future<HelperLink?> Function()? link;

  /// Where the helper's session and the chats kept here are. Null: this app's own folder.
  final String? folder;

  @override
  String get id => service.id;
  @override
  String get name => service.name;

  static const _mostKept = 400;

  HelperLink? _link;
  StreamSubscription<Map<String, Object?>>? _sub;
  AppState? _app;
  InboxState _state = InboxState.unavailable;
  String? _error, _account, _me;
  bool _busy = false;
  int _asked = 0;
  final Map<int, Completer<Object?>> _waiting = {};

  /// The chats, as the service describes each, and each one's messages kept here, oldest first.
  final Map<String, Map<String, Object?>> _chats = {};
  final Map<String, List<Map<String, Object?>>> _messages = {};

  /// Names and pictures by the service's id for a person.
  final Map<String, String> _names = {};
  final Map<String, String> _avatars = {};

  /// Chats whose older messages have all come, and those being asked for now.
  final Set<String> _exhausted = {};
  final Set<String> _loading = {};

  /// Attachments by the number the screens know them by, and their files once brought down.
  final Map<int, Map<String, Object?>> _pointers = {};
  final Map<int, String> _files = {};

  @override
  InboxState get state => _state;
  @override
  InboxStep get step => _state == InboxState.signedOut || _state == InboxState.signingIn ? InboxStep.credentials : InboxStep.none;
  @override
  String? get error => _error;
  @override
  String? get account => _account;

  /// The cookies are with the service, being checked.
  bool get signingIn => _busy;

  String get _dir => folder ?? (Platform.isAndroid ? '${Directory.systemTemp.parent.path}/files/${service.id}' : '${DeskStore.defaultDir().path}/${service.id}');
  File get _file => File('$_dir/chats.json');

  @override
  Future<void> start(AppState app) async {
    _app = app;
    if (soon) return;
    final link = await (this.link ?? _process)();
    if (link == null) {
      _state = InboxState.unavailable;
      _error = 'The ${service.name} helper isn\'t in this build.';
      notifyListeners();
      return;
    }
    _link = link;
    _read();
    _sub = link.heard.listen(_heard);
    _state = InboxState.signedOut;
    notifyListeners();
    try {
      final s = (await _ask('status') as Map?) ?? const {};
      if (s['linked'] == true) _signedIn(s);
    } catch (_) {}
  }

  /// The helper: beside the app on a computer (Contents/Helpers on a Mac, the program's folder on Windows and Linux),
  /// the phone's native libraries on Android.
  Future<HelperLink?> _process() async {
    String? binary;
    final h = service.helper;
    if (Platform.isAndroid) {
      try {
        binary = await const MethodChannel('ghost_messaging/sms').invokeMethod<String>('helperPath', {'name': '${h}sidecar'});
      } catch (_) {}
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final named = Platform.environment['GHOST_${h.toUpperCase()}SIDECAR'];
      final exe = File(Platform.resolvedExecutable).parent.path;
      final os = Platform.isWindows ? 'windows' : (Platform.isLinux ? 'linux' : 'mac');
      final file = Platform.isWindows ? '$h-sidecar.exe' : '$h-sidecar';
      for (final c in [
        ?named,
        if (Platform.isWindows) '$exe\\$file' else if (Platform.isLinux) '$exe/$file' else '$exe/../Helpers/$file',
        '${Directory.current.path}/build/$h-sidecar/$os/$file',
      ]) {
        if (File(c).existsSync()) {
          binary = c;
          break;
        }
      }
    }
    if (binary == null || !File(binary).existsSync()) return null;
    await Directory(_dir).create(recursive: true);
    try {
      return _ProcessLink(await Process.start(binary, ['--dir', _dir]), service.id);
    } catch (_) {
      return null;
    }
  }

  // --- signing in ---------------------------------------------------------------------------------------------------

  /// The cookies in what was pasted that this service's helper takes: the needed and the optional ones, or every
  /// cookie where the service names no optional ones (LinkedIn's helper is given the whole site's).
  Map<String, String> cookiesOf(String pasted) =>
      cookiesIn(pasted, names: service.optional.isEmpty ? const {} : {...service.needed, ...service.optional});

  /// Signs in with what was pasted (a copied request, a Cookie header, or the pairs): only after the person has
  /// agreed to the warning (lib/ui/inbox_signin_helper.dart). False, with [error] saying why, where it did not.
  Future<bool> signIn(String pasted) async {
    if (_link == null) return false;
    final cookies = cookiesOf(pasted);
    final missing = cookiesMissing(cookies, service.needed);
    if (missing.isNotEmpty) {
      _error = cookies.isEmpty
          ? 'No ${service.name} cookies in that. Copy ${service.copyFrom} as cURL, and paste all of it.'
          : 'That is missing ${missing.join(', ')}. Make sure you\'re signed in, then copy ${service.copyFrom} again.';
      notifyListeners();
      return false;
    }
    _error = null;
    _busy = true;
    _state = InboxState.signingIn;
    notifyListeners();
    try {
      final s = (await _ask('sign_in', {'cookies': cookies}) as Map?) ?? const {};
      _busy = false;
      if (_state != InboxState.ready) _signedIn(s);
      return true;
    } catch (e) {
      _busy = false;
      _error = _words(e);
      _state = InboxState.signedOut;
      notifyListeners();
      return false;
    }
  }

  static String _words(Object e) => e is StateError ? e.message : '$e';

  void _signedIn(Map s) {
    final handle = (s['handle'] as String?)?.trim() ?? '';
    final name = (s['name'] as String?)?.trim() ?? '';
    _account = handle.isNotEmpty ? '@$handle' : (name.isNotEmpty ? name : null);
    _me = (s['me'] as String?)?.trim();
    _state = InboxState.ready;
    _error = null;
    notifyListeners();
    unawaited(_listChats());
  }

  /// The service's own list of chats, asked for as the helper connects.
  Future<void> _listChats() async {
    try {
      for (final c in (await _ask('chats')) as List? ?? const []) {
        _takeChat((c as Map).cast<String, Object?>());
      }
      _save();
      notifyListeners();
    } catch (_) {}
  }

  @override
  Future<void> signOut() async {
    try {
      await _ask('unlink');
    } catch (_) {}
    _forget();
    _state = _link == null ? InboxState.unavailable : InboxState.signedOut;
    _error = null;
    _save();
    notifyListeners();
  }

  void _forget() {
    _chats.clear();
    _messages.clear();
    _names.clear();
    _avatars.clear();
    _exhausted.clear();
    _account = null;
    _me = null;
  }

  // --- what the helper says ---------------------------------------------------------------------------------------

  void _heard(Map<String, Object?> m) {
    final id = m['id'];
    if (id is num && m.containsKey('ok')) {
      final w = _waiting.remove(id.toInt());
      if (w == null) return;
      m['ok'] == true ? w.complete(m['result']) : w.completeError(StateError('${m['error'] ?? '${service.name} did not answer'}'));
      return;
    }
    switch (m['ev']) {
      case 'linked':
        _signedIn(m);
      case 'unlinked':
        // The service ended the session: what is kept stays to be read, and signing in again carries on.
        _account = null;
        _state = InboxState.signedOut;
        final why = (m['error'] as String?)?.trim() ?? '';
        _error = why.isNotEmpty ? why : '${service.name} signed this session out. Sign in again to carry on.';
        notifyListeners();
      case 'connected':
        if (_state == InboxState.ready) unawaited(_listChats());
      case 'chat':
        _takeChat(m);
        _save();
        notifyListeners();
      case 'name':
        _takeName(m);
        _save();
        notifyListeners();
      case 'message':
        if (_take(m)) {
          final chat = '${m['chat']}';
          if (m['mine'] != true && chat != _watching) _chats[chat]!['unread'] = ((_chats[chat]!['unread'] as int?) ?? 0) + 1;
          _save();
          notifyListeners();
        }
      case 'edited':
        final msg = _find('${m['chat']}', '${m['target']}');
        if (msg != null) {
          msg['text'] = m['text'] ?? '';
          msg['edited'] = true;
          _save();
          notifyListeners();
        }
      case 'reaction':
        _reaction(m);
      case 'receipt':
        final chat = '${m['chat']}';
        // This account's own, read in the service's own app: the chat is read here too.
        if (_me != null && '${m['from'] ?? ''}' == _me) {
          final c = _chats[chat];
          if (c != null && (c['unread'] as int? ?? 0) != 0) {
            c['unread'] = 0;
            _save();
            notifyListeners();
          }
          break;
        }
        // Read up to a message (by its id, or where the service gives only a time, `ts`): every one of this account's
        // own up to it, in time.
        final list = _messages[chat] ?? const <Map<String, Object?>>[];
        final upTo = (_find(chat, '${m['id'] ?? ''}')?['ts'] as int?) ?? (m['ts'] as num?)?.toInt();
        final kind = m['kind'] == 'read' ? 'read' : 'delivered';
        for (final x in list) {
          if (x['mine'] != true || x['state'] == 'read' || x['state'] == 'sending' || x['state'] == 'failed') continue;
          if (upTo == null ? x['id'] == '${m['id']}' : (x['ts'] as int) <= upTo) x['state'] = kind;
        }
        _save();
        notifyListeners();
      case 'deleted':
        _messages['${m['chat']}']?.removeWhere((x) => x['id'] == '${m['target']}');
        _save();
        notifyListeners();
    }
  }

  /// A chat as the service describes it: its title, who is in it, its picture, what is unread.
  void _takeChat(Map<String, Object?> m) {
    final chat = (m['id'] as String?) ?? '';
    if (chat.isEmpty) return;
    final c = _chats.putIfAbsent(chat, () => {'unread': 0, 'last': 0});
    final title = (m['title'] as String?)?.trim() ?? '';
    if (title.isNotEmpty) c['title'] = title;
    if (m.containsKey('group')) c['group'] = m['group'] == true;
    if (m['avatar'] is String && (m['avatar'] as String).isNotEmpty) c['avatar'] = m['avatar'];
    if (m['unread'] is num && chat != _watching) c['unread'] = (m['unread'] as num).toInt();
    final last = (m['last'] as num?)?.toInt() ?? 0;
    if (last > ((c['last'] as int?) ?? 0)) c['last'] = last;
    final snippet = (m['snippet'] as String?)?.trim() ?? '';
    if (snippet.isNotEmpty) {
      c['snippet'] = snippet;
      c['snippet_mine'] = m['snippet_mine'] == true;
      c['snippet_at'] = last;
    }
    final members = <Map<String, Object?>>[];
    for (final p in (m['members'] as List? ?? const [])) {
      if (p is! Map) continue;
      final who = '${p['id'] ?? ''}';
      if (who.isEmpty) continue;
      final name = (p['name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty) _names[who] = name;
      members.add({'id': who});
    }
    if (members.isNotEmpty) c['members'] = members;
  }

  /// Someone's name, as the helper found it. An empty name never stands in for one.
  void _takeName(Map m) {
    final who = '${m['id'] ?? ''}';
    if (who.isEmpty) return;
    final name = (m['name'] as String?)?.trim() ?? '';
    final handle = (m['handle'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) {
      _names[who] = name;
    } else if (handle.isNotEmpty) {
      _names.putIfAbsent(who, () => '@$handle');
    }
    if (m['avatar'] is String && (m['avatar'] as String).isNotEmpty) _avatars[who] = m['avatar'] as String;
  }

  /// Keeps a message in its chat; false if it was here already.
  bool _take(Map<String, Object?> m) {
    final chat = '${m['chat'] ?? ''}';
    if (chat.isEmpty) return false;
    final from = '${m['from'] ?? ''}';
    final name = (m['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty && m['mine'] != true && from.isNotEmpty) _names.putIfAbsent(from, () => name);
    final list = _messages.putIfAbsent(chat, () => []);
    final mid = '${m['id'] ?? ''}';
    final ts = (m['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    if (mid.isNotEmpty) {
      final had = list.where((x) => x['id'] == mid).firstOrNull;
      if (had != null) return false;
      // This account's own, sent from here a moment ago and now said back by the service: the one bubble, confirmed.
      if (m['mine'] == true) {
        final pending = list.where((x) => x['state'] == 'sending' && x['text'] == (m['text'] ?? '')).firstOrNull;
        if (pending != null) {
          pending['id'] = mid;
          pending['ts'] = ts;
          pending['state'] = 'sent';
          return true;
        }
      }
    }
    list.add({
      'id': mid.isEmpty ? 'in-$ts' : mid,
      'ts': ts,
      'from': from,
      'mine': m['mine'] == true,
      'text': m['text'] ?? '',
      'media': m['media'] ?? const [],
      'state': m['mine'] == true ? 'sent' : 'received',
      if (m['quote'] is Map) 'quote': m['quote'],
      // The reactions it already has: who → which, or a list of `{"from", "emoji"}` as a helper's history gives them.
      if (m['reactions'] is Map) 'reactions': m['reactions'],
      if (m['reactions'] is List)
        'reactions': {for (final r in m['reactions'] as List) if (r is Map && '${r['emoji'] ?? ''}'.isNotEmpty) '${r['from'] ?? ''}': '${r['emoji']}'},
    });
    list.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    final c = _chats.putIfAbsent(chat, () => {'unread': 0, 'last': 0});
    if (m.containsKey('group')) c.putIfAbsent('group', () => m['group'] == true);
    if (ts > ((c['last'] as int?) ?? 0)) c['last'] = ts;
    return true;
  }

  Map<String, Object?>? _find(String chatId, String messageId) => (_messages[chatId] ?? const []).where((x) => x['id'] == messageId).firstOrNull;

  void _reaction(Map<String, Object?> m) {
    final msg = _find('${m['chat']}', '${m['target']}');
    if (msg == null) return;
    final from = '${m['from'] ?? ''}';
    final reactions = Map<String, Object?>.from(msg['reactions'] as Map? ?? const {});
    if (m['remove'] == true || '${m['emoji'] ?? ''}'.isEmpty) {
      reactions.remove(from);
    } else {
      reactions[from] = '${m['emoji']}';
    }
    msg['reactions'] = reactions;
    _save();
    notifyListeners();
  }

  // --- sending ------------------------------------------------------------------------------------------------------

  @override
  bool get canReact => true;

  @override
  Future<void> react(String chatId, String messageId, String emoji, {bool remove = false}) async {
    if (_state != InboxState.ready) throw StateError('${service.name} isn\'t connected');
    await _ask('react', {'to': chatId, 'target': messageId, 'emoji': emoji, 'remove': remove});
    _reaction({'chat': chatId, 'target': messageId, 'from': _me ?? '', 'emoji': emoji, 'remove': remove});
  }

  @override
  bool get canReply => true;

  @override
  Future<void> reply(String chatId, String messageId, String text) {
    final quoted = _find(chatId, messageId);
    // What is quoted, with who wrote it and when: some services (LinkedIn) need those to make the reply.
    return _send(chatId, text, quote: quoted == null ? null : {'id': messageId, 'text': '${quoted['text'] ?? ''}', 'author': quoted['mine'] == true ? (_me ?? '') : '${quoted['from'] ?? ''}', 'ts': quoted['ts']});
  }

  @override
  Future<void> send(String chatId, String text) => _send(chatId, text);

  Future<void> _send(String chatId, String text, {Map<String, Object?>? quote}) async {
    text = text.trim();
    if (text.isEmpty || _state != InboxState.ready) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final local = <String, Object?>{'id': 'local-$now', 'ts': now, 'from': _me ?? '', 'mine': true, 'text': text, 'media': const [], 'state': 'sending', 'quote': ?quote};
    _messages.putIfAbsent(chatId, () => []).add(local);
    final c = _chats.putIfAbsent(chatId, () => {'unread': 0, 'last': 0});
    c['last'] = now;
    notifyListeners();
    try {
      final r = (await _ask('send', {'to': chatId, 'text': text, 'quote': ?quote}) as Map?) ?? const {};
      // Said back by the service already (its `message` event came first): that took this bubble's place.
      if (local['state'] == 'sending') {
        final sent = '${r['id'] ?? ''}';
        // The same message twice, once from here and once said back: the one from here goes.
        if (sent.isNotEmpty && _messages[chatId]!.any((x) => !identical(x, local) && x['id'] == sent)) {
          _messages[chatId]!.remove(local);
        } else {
          if (sent.isNotEmpty) local['id'] = sent;
          local['ts'] = (r['ts'] as num?)?.toInt() ?? local['ts'];
          local['state'] = 'sent';
        }
      }
      _error = null;
    } catch (e) {
      local['state'] = 'failed';
      _error = _words(e);
    }
    _save();
    notifyListeners();
  }

  @override
  bool get canSendFiles => true;

  @override
  Future<void> sendFiles(String chatId, List<String> paths, {String caption = '', bool voice = false}) async {
    if (_state != InboxState.ready) return;
    for (final (i, path) in paths.indexed) {
      final ext = path.split('.').last.toLowerCase();
      final mime = const {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic', 'mp4': 'video/mp4', 'mov': 'video/quicktime', 'm4a': 'audio/mp4', 'ogg': 'audio/ogg', 'pdf': 'application/pdf'}[ext] ??
          'application/octet-stream';
      final text = i == paths.length - 1 ? caption : '';
      try {
        final name = path.split(Platform.pathSeparator).last;
        final r = (await _ask('send_media', {'to': chatId, 'path': path, 'mime': mime, 'name': name, 'text': text}) as Map?) ?? const {};
        final ts = (r['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        final mid = '${r['id'] ?? 'local-$ts-$i'}';
        if (_find(chatId, mid) == null) {
          // What was sent is kept for its bubble: a copy in this network's own folder.
          final kept = await _keepSent(path, ts, i, name);
          final pointer = {'local': kept};
          _messages.putIfAbsent(chatId, () => []).add({
            'id': mid,
            'ts': ts,
            'from': _me ?? '',
            'mine': true,
            'text': text,
            'media': [{'local': kept, 'mime': mime, 'name': name, 'pointer': pointer}],
            'state': 'sent',
          });
          _files[jsonEncode(pointer).hashCode & 0x3fffffff] = kept;
        }
        _chats.putIfAbsent(chatId, () => {'unread': 0, 'last': 0})['last'] = ts;
        _error = null;
      } catch (e) {
        // The helper's own words: "Instagram files can't be sent from here yet".
        _error = _words(e);
        notifyListeners();
        rethrow;
      }
    }
    _save();
    notifyListeners();
  }

  Future<String> _keepSent(String path, int ts, int i, String name) async {
    try {
      final ext = name.contains('.') ? '.${name.split('.').last}' : '';
      final kept = '$_dir/files/sent-$ts-$i$ext';
      await Directory('$_dir/files').create(recursive: true);
      await File(path).copy(kept);
      return kept;
    } catch (_) {
      return path;
    }
  }

  // --- the chats and their messages, as the screens have them -----------------------------------------------------

  /// What a chat is called: the service's title for it; else the other person's name; else plainly what it is. Never
  /// an id.
  String _titleOf(String chat, Map<String, Object?> c) {
    final title = (c['title'] as String?)?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final others = [
      for (final p in (c['members'] as List? ?? const []))
        if (p is Map && (_names['${p['id']}']?.isNotEmpty ?? false)) _names['${p['id']}']!,
    ];
    if (others.isNotEmpty) return others.join(', ');
    final direct = _names[chat];
    if (direct != null && direct.isNotEmpty) return direct;
    return c['group'] == true ? '${service.name} group' : '${service.name} chat';
  }

  @override
  List<InboxChat> get chats {
    final out = <InboxChat>[];
    for (final e in _chats.entries) {
      final c = e.value;
      final msgs = _messages[e.key] ?? const <Map<String, Object?>>[];
      final last = msgs.isEmpty ? null : msgs.last;
      // The newest words: the last message kept, unless the service's own line for the chat is newer.
      final lastAt = (last?['ts'] as int?) ?? 0;
      final fromService = ((c['snippet_at'] as int?) ?? 0) > lastAt && '${c['snippet'] ?? ''}'.isNotEmpty;
      final members = (c['members'] as List? ?? const []);
      final one = members.length == 1 && members.first is Map ? '${(members.first as Map)['id']}' : null;
      out.add(InboxChat(
        network: id,
        id: e.key,
        title: _titleOf(e.key, c),
        date: DateTime.fromMillisecondsSinceEpoch((c['last'] as int?) ?? 0),
        snippet: fromService ? '${c['snippet']}' : (last == null ? '${c['snippet'] ?? ''}' : _snippet(last)),
        unread: (c['unread'] as int?) ?? 0,
        group: c['group'] == true,
        avatar: (c['avatar'] as String?) ?? (one == null ? null : _avatars[one]),
        lastFromMe: fromService || last == null ? c['snippet_mine'] == true : last['mine'] == true,
      ));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  static String _snippet(Map<String, Object?> m) {
    final text = '${m['text'] ?? ''}'.trim();
    if (text.isNotEmpty) return text;
    final media = (m['media'] as List?) ?? const [];
    if (media.isEmpty) return '';
    final mime = '${(media.first as Map)['mime'] ?? ''}';
    return mime.startsWith('image/') ? 'Photo' : mime.startsWith('video/') ? 'Video' : mime.startsWith('audio/') ? 'Voice message' : 'File';
  }

  @override
  List<InboxMessage> messagesOf(String chatId) => [
        for (final m in _messages[chatId] ?? const <Map<String, Object?>>[])
          InboxMessage(
            id: '${m['id']}',
            text: '${m['text'] ?? ''}',
            date: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
            mine: m['mine'] == true,
            sender: m['mine'] == true ? '' : (_names['${m['from']}'] ?? ''),
            senderId: '${m['from'] ?? ''}',
            state: switch (m['state']) { 'sending' => 'sending', 'failed' => 'failed', _ => 'sent' },
            media: [for (final a in (m['media'] as List? ?? const [])) _media(a as Map)],
            reactions: signalReactions(m['reactions'] as Map?, me: _me),
            replyTo: (m['quote'] as Map?)?['id']?.toString(),
            replyText: (m['quote'] as Map?)?['text'] as String?,
            edited: m['edited'] == true,
          ),
      ];

  InboxMedia _media(Map a) {
    final key = jsonEncode(a['pointer']).hashCode & 0x3fffffff;
    _pointers[key] = a.cast<String, Object?>();
    final mime = '${a['mime'] ?? ''}';
    return InboxMedia(
      kind: mime.startsWith('image/') ? 'photo' : mime.startsWith('video/') ? 'video' : mime.startsWith('audio/') ? 'audio' : 'file',
      fileId: key,
      path: _files[key],
      name: a['name'] as String?,
      size: (a['size'] as num?)?.toInt() ?? 0,
      width: (a['width'] as num?)?.toInt() ?? 0,
      height: (a['height'] as num?)?.toInt() ?? 0,
    );
  }

  /// Whether [chatId] may have messages before the oldest kept here.
  bool hasOlder(String chatId) => !_exhausted.contains(chatId);

  /// Brings [chatId]'s recent messages from the service where few are kept, and with [older] the ones before the
  /// oldest kept.
  @override
  Future<void> load(String chatId, {bool older = false}) async {
    if (_state != InboxState.ready || _loading.contains(chatId)) return;
    final held = _messages[chatId] ?? const <Map<String, Object?>>[];
    if (!older && held.length >= 20) return;
    if (older && _exhausted.contains(chatId)) return;
    // Older than the oldest the service itself named (one sent from here and not yet said back has no id of its).
    final oldest = held.where((m) => !'${m['id']}'.startsWith('local-') && !'${m['id']}'.startsWith('in-')).firstOrNull;
    _loading.add(chatId);
    try {
      // The oldest kept, by its id and by its time: a helper pages by whichever its service does.
      final r = (await _ask('history', {'chat': chatId, if (older && oldest != null) ...{'before': '${oldest['id']}', 'before_ts': oldest['ts']}}) as Map?) ?? const {};
      var took = 0;
      for (final x in (r['messages'] as List? ?? const [])) {
        if (_take({...(x as Map).cast<String, Object?>(), 'chat': chatId})) took++;
      }
      if (r['more'] != true || (older && took == 0)) _exhausted.add(chatId);
      if (took > 0) {
        _save();
        notifyListeners();
      }
    } catch (e) {
      _error = _words(e);
      notifyListeners();
    } finally {
      _loading.remove(chatId);
    }
  }

  String? _watching;

  @override
  set watching(String? chatId) => _watching = chatId;

  @override
  void wantFile(int fileId) => unawaited(fileOf(fileId));

  @override
  Future<String?> fileOf(int fileId) async {
    final known = _files[fileId];
    if (known != null) return known;
    final a = _pointers[fileId];
    if (a == null) return null;
    final local = a['local'] as String?;
    if (local != null && File(local).existsSync()) return _files[fileId] = local;
    final pointer = a['pointer'];
    if (pointer is! Map || pointer.containsKey('local')) return null;
    final ext = switch ('${a['mime'] ?? ''}'.split(';').first) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      'video/mp4' => '.mp4',
      'audio/ogg' => '.ogg',
      'audio/mp4' => '.m4a',
      'application/pdf' => '.pdf',
      _ => '${a['name'] ?? ''}'.contains('.') ? '.${'${a['name']}'.split('.').last}' : '',
    };
    final path = '$_dir/files/$fileId$ext';
    if (File(path).existsSync()) return _files[fileId] = path;
    try {
      await Directory('$_dir/files').create(recursive: true);
      await _ask('download', {'pointer': pointer, 'path': path});
      _files[fileId] = path;
      notifyListeners();
      return path;
    } catch (e) {
      _error = _words(e);
      return null;
    }
  }

  @override
  Future<void> markRead(String chatId) async {
    final c = _chats[chatId];
    if (c == null || (c['unread'] as int? ?? 0) == 0) return;
    c['unread'] = 0;
    _save();
    notifyListeners();
    final newest = (_messages[chatId] ?? const <Map<String, Object?>>[]).where((m) => m['mine'] != true).lastOrNull;
    try {
      await _ask('read', {'to': chatId, 'upto': ?newest?['id']});
    } catch (_) {}
  }

  /// Your own message can be unsent for everyone; anyone else's is hidden only here.
  @override
  bool canDeleteForEveryone(String chatId, InboxMessage message) => message.mine;

  @override
  Future<void> deleteMessage(String chatId, String messageId, {bool forEveryone = false}) async {
    if (forEveryone) {
      try {
        await _ask('delete', {'to': chatId, 'target': messageId});
      } catch (e) {
        _error = _words(e);
        notifyListeners();
        return;
      }
    }
    _messages[chatId]?.removeWhere((m) => m['id'] == messageId);
    _save();
    notifyListeners();
  }

  /// Gone from here only: the chat stays on the service.
  @override
  Future<void> deleteChat(String chatId) async {
    await super.deleteChat(chatId);
    _messages.remove(chatId);
    _save();
  }

  // --- keeping ------------------------------------------------------------------------------------------------------

  void _read() {
    try {
      if (!_file.existsSync()) return;
      final all = jsonDecode(_file.readAsStringSync()) as Map;
      (all['chats'] as Map? ?? const {}).forEach((k, v) => _chats['$k'] = (v as Map).cast<String, Object?>());
      (all['messages'] as Map? ?? const {}).forEach((k, v) => _messages['$k'] = [for (final m in v as List) (m as Map).cast<String, Object?>()]);
      (all['names'] as Map? ?? const {}).forEach((k, v) {
        if (v is String && v.trim().isNotEmpty) _names['$k'] = v;
      });
      (all['avatars'] as Map? ?? const {}).forEach((k, v) => _avatars['$k'] = '$v');
    } catch (_) {}
  }

  /// What is kept: every chat, and the newest [_mostKept] messages of each (older ones are the service's to give
  /// again), so the file does not grow for ever (docs/performance-audit.md, finding 4).
  String _kept() => jsonEncode({
        'chats': _chats,
        'messages': {for (final e in _messages.entries) e.key: e.value.length > _mostKept ? e.value.sublist(e.value.length - _mostKept) : e.value},
        'names': _names,
        'avatars': _avatars,
      });

  Timer? _saving;
  Future<void> _writing = Future.value();

  /// Written two seconds after the last change, off the frame: the file is written without waiting on it.
  void _save() {
    _saving?.cancel();
    _saving = Timer(const Duration(seconds: 2), () {
      final text = _kept();
      _writing = _writing.then((_) async {
        try {
          await _file.parent.create(recursive: true);
          final tmp = File('${_file.path}.tmp');
          await tmp.writeAsString(text);
          await tmp.rename(_file.path);
        } catch (_) {}
      });
    });
  }

  /// Writes what is kept now (a test's end, the app going).
  @visibleForTesting
  void flush() {
    if (_saving?.isActive ?? false) {
      _saving!.cancel();
      _saving = null;
      try {
        _file.parent.createSync(recursive: true);
        _file.writeAsStringSync(_kept());
      } catch (_) {}
    }
  }

  Future<Object?> _ask(String op, [Map<String, Object?> args = const {}]) {
    final link = _link;
    if (link == null) return Future.error(StateError('${service.name} isn\'t running'));
    final id = ++_asked;
    final done = Completer<Object?>();
    _waiting[id] = done;
    // The request's own id last: nothing in [args] may take its place (a `read` once named its message `id`).
    link.say({...args, 'id': id, 'op': op});
    // Longer than a helper gives each, so its own reason arrives.
    final wait = switch (op) { 'download' || 'send_media' => 190, 'status' || 'who' => 30, _ => 90 };
    return done.future.timeout(Duration(seconds: wait), onTimeout: () {
      _waiting.remove(id);
      throw StateError('${service.name} took too long to answer');
    });
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    flush();
    _sub?.cancel();
    unawaited(_link?.close());
    super.dispose();
  }

  /// The app's preferences, for later use.
  AppState? get app => _app;
}

class _ProcessLink implements HelperLink {
  _ProcessLink(this.p, String network) {
    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      try {
        final m = jsonDecode(line);
        if (m is Map) _in.add(m.cast<String, Object?>());
      } catch (_) {}
    });
    // The helper's log (also beside its session): warnings and its own lines about requests go to the Developer log.
    // A helper's own lines name an op and a request number, never a message's words.
    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final kept = helperLogLine(line);
      if (kept != null) Sms.instance.devLog(network, kept);
    });
  }

  final Process p;
  final _in = StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get heard => _in.stream;

  @override
  void say(Map<String, Object?> line) {
    try {
      p.stdin.writeln(jsonEncode(line));
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    try {
      await p.stdin.close();
    } catch (_) {}
    p.kill();
  }
}

/// One line of an account helper's log, shortened, where it is worth keeping in the Developer log: its own lines about
/// requests, and anything warned of; null for the rest.
@visibleForTesting
String? helperLogLine(String line) {
  Map? m;
  try {
    final d = jsonDecode(line);
    if (d is Map) m = d;
  } catch (_) {}
  if (m == null) return line.trim().isEmpty ? null : (line.length > 300 ? line.substring(0, 300) : line);
  final level = '${m['level'] ?? ''}';
  final message = '${m['message'] ?? ''}';
  const ours = {'asked', 'answered'};
  if (level != 'warn' && level != 'error' && level != 'fatal' && !ours.contains(message)) return null;
  const fields = ['op', 'req', 'took', 'error', 'component'];
  final out = [level, message, for (final k in fields) if (m[k] != null) '$k=${m[k]}'].join(' ');
  return out.length > 300 ? out.substring(0, 300) : out;
}
