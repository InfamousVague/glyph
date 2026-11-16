import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;

import '../app_state.dart';
import '../desktop/store.dart';
import '../sms.dart';
import 'inbox.dart';

/// What the Signal helper is to the app: lines out, lines in. A process in the app; a stand-in in a test.
abstract class SignalLink {
  Stream<Map<String, Object?>> get heard;
  void say(Map<String, Object?> line);
  Future<void> close();
}

/// Signal, linked to the person's account as another device, as Signal Desktop is (Matt, 2026-11-15: "Lets wire it
/// up for signal through the mautrix"): the helper `signal-sidecar` (sidecar/signal, on mautrix-signal's signalmeow and
/// Signal's libsignal, GNU AGPL) runs as a child process and speaks sidecar/signal/PROTOCOL.md.
///
/// Signing in is Signal's own linking: the helper gives a `sgnl://linkdevice` address, drawn as a QR code that Signal
/// on the person's phone scans (Settings › Linked devices › Link new device). Signal keeps no history for a new linked
/// device, so this keeps what arrives from then on, in its own file ([_file]). Signal has no API for other apps; this
/// is the way Signal Desktop and mautrix-signal go, and may need mending when Signal changes. Offered as Coming soon
/// until it has been proven.
class Signal extends InboxNetwork {
  Signal({this.soon = false, this.link, this.folder});

  @override
  final bool soon;

  /// The helper, in a test. Null: the process, once [start] finds it.
  final Future<SignalLink?> Function()? link;

  /// Where the helper's store and the chats kept here are. Null: this app's own folder.
  final String? folder;

  @override
  String get id => 'signal';
  @override
  String get name => 'Signal';

  SignalLink? _link;
  StreamSubscription<Map<String, Object?>>? _sub;
  AppState? _app;
  InboxState _state = InboxState.unavailable;
  String? _error, _account, _qr;
  int _asked = 0;
  final Map<int, Completer<Object?>> _waiting = {};

  /// The chats kept here, and each one's messages, oldest first.
  final Map<String, Map<String, Object?>> _chats = {};
  final Map<String, List<Map<String, Object?>>> _messages = {};

  /// Who is who: names by ACI, and groups' titles.
  final Map<String, String> _names = {};
  final Map<String, String?> _avatars = {};
  final Set<String> _groups = {};

  /// Attachments by the number the screens know them by, and their files once brought down.
  final Map<int, Map<String, Object?>> _pointers = {};
  final Map<int, String> _files = {};

  @override
  InboxState get state => _state;
  @override
  InboxStep get step => _state == InboxState.signedOut || _state == InboxState.signingIn ? InboxStep.code : InboxStep.none;
  @override
  String? get error => _error;
  @override
  String? get account => _account;

  /// The `sgnl://linkdevice` address to draw as a QR code, while linking.
  String? get qr => _qr;

  String get _dir => folder ?? (Platform.isAndroid ? '${Directory.systemTemp.parent.path}/files/signal' : '${DeskStore.defaultDir().path}/signal');
  File get _file => File('$_dir/chats.json');

  @override
  Future<void> start(AppState app) async {
    _app = app;
    if (soon) return;
    final link = await (this.link ?? _process)();
    if (link == null) {
      _state = InboxState.unavailable;
      _error = 'The Signal helper isn\'t in this build.';
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

  /// The helper: beside the app on a computer (Contents/Helpers on a Mac), the phone's native libraries on Android.
  Future<SignalLink?> _process() async {
    String? binary;
    if (Platform.isAndroid) {
      try {
        binary = await const MethodChannel('ghost_messaging/sms').invokeMethod<String>('helperPath', {'name': 'signalsidecar'});
      } catch (_) {}
    } else if (Platform.isMacOS || Platform.isWindows) {
      final named = Platform.environment['GHOST_SIGNALSIDECAR'];
      final exe = File(Platform.resolvedExecutable).parent.path;
      for (final c in [
        ?named,
        if (Platform.isWindows) '$exe\\signal-sidecar.exe' else '$exe/../Helpers/signal-sidecar',
        '${Directory.current.path}/build/signal-sidecar/${Platform.isWindows ? 'windows/signal-sidecar.exe' : 'mac/signal-sidecar'}',
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
      // On the phone libsignal needs Android's shared C++ library, which goes beside the helper
      // (tool/build-signalsidecar.sh): the helper is started with its folder on the library path.
      final env = Platform.isAndroid ? {'LD_LIBRARY_PATH': File(binary).parent.path} : null;
      return _ProcessLink(await Process.start(binary, ['--dir', _dir], environment: env));
    } catch (_) {
      return null;
    }
  }

  // --- linking ------------------------------------------------------------------------------------------------------

  /// Asks the helper for a QR code to link this device with ([qr]).
  Future<void> begin() async {
    if (_link == null) return;
    _error = null;
    _qr = null;
    _state = InboxState.signingIn;
    notifyListeners();
    try {
      await _ask('link', {'name': 'Ghost Messaging'});
    } catch (e) {
      _error = '$e';
      _state = InboxState.signedOut;
      notifyListeners();
    }
  }

  void _signedIn(Map s) {
    _account = (s['number'] as String?)?.ifEmpty((s['name'] as String?) ?? '') ?? s['name'] as String?;
    _aci = s['aci'] as String?;
    _qr = null;
    _state = InboxState.ready;
    _error = null;
    notifyListeners();
    unawaited(_who());
  }

  @override
  Future<void> signOut() async {
    try {
      await _ask('unlink');
    } catch (_) {}
    _chats.clear();
    _messages.clear();
    _contacts.clear();
    _account = null;
    _state = InboxState.signedOut;
    _save();
    notifyListeners();
  }

  /// When names and groups were last asked for.
  DateTime? _whoAt;

  void _takeGroup(Map m) {
    final gid = m['id'] as String?;
    if (gid == null) return;
    _groups.add(gid);
    final title = (m['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) {
      _names[gid] = title;
    } else {
      _names.putIfAbsent(gid, () => 'Signal group');
    }
    if (m['avatar'] is String) _avatars[gid] = m['avatar'] as String;
  }

  /// Names and groups, from Signal's contact sync and profiles.
  Future<void> _who() async {
    _whoAt = DateTime.now();
    try {
      _takeContacts((await _ask('contacts')) as List? ?? const []);
      for (final g in (await _ask('groups')) as List? ?? const []) {
        _takeGroup(g as Map);
      }
      notifyListeners();
    } catch (_) {}
  }

  void _takeContacts(List list) {
    for (final c in list) {
      final m = c as Map;
      final aci = m['aci'] as String?;
      if (aci == null) continue;
      final name = (m['name'] as String?)?.trim();
      _names[aci] = name == null || name.isEmpty ? ((m['number'] as String?) ?? 'Someone') : name;
      _avatars[aci] = m['avatar'] as String?;
      final number = (m['number'] as String?)?.trim();
      _contacts[aci] = number == null || number.isEmpty ? null : number;
    }
  }

  // --- contacts (Matt, 2026-11-16: "Show telegram and signal contacts when linked") ---------------------------------

  /// This account's own ACI: Signal's contact sync names the person themself too.
  String? _aci;

  /// The people in Signal's contact sync, by ACI, with their numbers where Signal gives one.
  final Map<String, String?> _contacts = {};

  @override
  List<InboxContact> get contacts => [
        for (final e in _contacts.entries)
          if (e.key != _aci) InboxContact(network: id, id: e.key, name: _names[e.key] ?? e.value ?? 'Someone', number: e.value, avatar: _avatars[e.key]),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// A chat with someone on Signal is named by their ACI: it is in the list from the first message sent.
  @override
  Future<String?> chatWith(InboxContact contact) async => _state == InboxState.ready ? contact.id : null;

  // --- what the helper says ---------------------------------------------------------------------------------------

  void _heard(Map<String, Object?> m) {
    final id = m['id'];
    if (id is num && m.containsKey('ok')) {
      final w = _waiting.remove(id.toInt());
      if (w == null) return;
      m['ok'] == true ? w.complete(m['result']) : w.completeError(StateError('${m['error'] ?? 'Signal did not answer'}'));
      return;
    }
    switch (m['ev']) {
      case 'qr':
        _qr = m['url'] as String?;
        _state = InboxState.signingIn;
        notifyListeners();
      case 'linked':
        _signedIn(m);
      case 'link_failed':
        _qr = null;
        _state = InboxState.signedOut;
        _error = (m['error'] as String?) ?? 'Linking did not finish. Try again.';
        notifyListeners();
      case 'unlinked':
        _account = null;
        _state = InboxState.signedOut;
        _error = 'Signal removed this device. Link it again to carry on.';
        notifyListeners();
      case 'contacts':
        _takeContacts((m['list'] as List?) ?? const []);
        notifyListeners();
      case 'group':
        // A group first heard from: its name, as the groups op gives it (sidecar/signal announceGroup).
        _takeGroup(m);
        notifyListeners();
      case 'connected':
        // Back on Signal: names and groups asked for again, at most once a minute.
        final now = DateTime.now();
        if (_whoAt == null || now.difference(_whoAt!) > const Duration(minutes: 1)) unawaited(_who());
      case 'message':
        _message(m);
      case 'receipt':
        final kind = m['kind'] == 'read' ? 'read' : 'delivered';
        final times = {for (final t in (m['ts'] as List? ?? const [])) '$t'};
        // A receipt names who read, not the group: the message is found by its time in any chat (sidecar/signal).
        for (final list in _messages.values) {
          for (final x in list) {
            if (x['mine'] == true && times.contains('${x['ts']}') && x['state'] != 'read') x['state'] = kind;
          }
        }
        _save();
        notifyListeners();
      case 'deleted':
        final chat = '${m['chat']}';
        _messages[chat]?.removeWhere((x) => '${x['ts']}' == '${m['target_ts']}');
        _save();
        notifyListeners();
    }
  }

  void _message(Map<String, Object?> m) {
    final chat = '${m['chat']}';
    final group = m['group'] == true;
    if (group) _groups.add(chat);
    final from = '${m['from'] ?? ''}';
    final name = (m['name'] as String?)?.trim();
    if (!group && name != null && name.isNotEmpty && m['mine'] != true) _names[chat] = name;
    if (group && name != null && name.isNotEmpty) _names[from] = name;
    final list = _messages.putIfAbsent(chat, () => []);
    final ts = (m['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    if (list.any((x) => x['ts'] == ts && x['from'] == from)) return;
    list.add({
      'ts': ts,
      'from': from,
      'mine': m['mine'] == true,
      'text': m['text'] ?? '',
      'media': m['media'] ?? const [],
      'state': m['mine'] == true ? 'sent' : 'received',
    });
    list.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    final c = _chats.putIfAbsent(chat, () => {'unread': 0});
    c['last'] = ts;
    if (m['mine'] != true) c['unread'] = ((c['unread'] as int?) ?? 0) + 1;
    _save();
    notifyListeners();
  }

  // --- the chats and their messages, as the screens have them -----------------------------------------------------

  @override
  List<InboxChat> get chats {
    final out = <InboxChat>[];
    for (final e in _chats.entries) {
      final msgs = _messages[e.key] ?? const <Map<String, Object?>>[];
      final last = msgs.isEmpty ? null : msgs.last;
      final group = _groups.contains(e.key);
      out.add(InboxChat(
        network: id,
        id: e.key,
        title: _names[e.key] ?? (group ? 'Signal group' : 'Signal'),
        date: DateTime.fromMillisecondsSinceEpoch((e.value['last'] as int?) ?? 0),
        snippet: last == null ? '' : _snippet(last),
        unread: (e.value['unread'] as int?) ?? 0,
        group: group,
        avatar: _avatars[e.key],
        lastFromMe: last?['mine'] == true,
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
            id: '${m['ts']}',
            text: '${m['text'] ?? ''}',
            date: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
            mine: m['mine'] == true,
            sender: m['mine'] == true ? '' : (_names['${m['from']}'] ?? ''),
            state: switch (m['state']) { 'sending' => 'sending', 'failed' => 'failed', _ => 'sent' },
            media: [for (final a in (m['media'] as List? ?? const [])) _media(a as Map)],
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

  @override
  Future<void> load(String chatId, {bool older = false}) async {}

  @override
  set watching(String? chatId) {}

  @override
  Future<void> send(String chatId, String text) async {
    text = text.trim();
    if (text.isEmpty || _state != InboxState.ready) return;
    final local = <String, Object?>{'ts': DateTime.now().millisecondsSinceEpoch, 'from': '', 'mine': true, 'text': text, 'media': const [], 'state': 'sending'};
    _messages.putIfAbsent(chatId, () => []).add(local);
    _chats.putIfAbsent(chatId, () => {'unread': 0})['last'] = local['ts'];
    notifyListeners();
    try {
      final r = (await _ask('send', {'to': chatId, 'text': text}) as Map?) ?? const {};
      local['ts'] = (r['ts'] as num?)?.toInt() ?? local['ts'];
      local['state'] = 'sent';
      _error = null;
    } catch (e) {
      local['state'] = 'failed';
      _error = '$e';
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
      final mime = voice || ext == 'm4a'
          ? 'audio/mp4'
          : const {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic', 'mp4': 'video/mp4', 'mov': 'video/quicktime', 'pdf': 'application/pdf'}[ext] ??
              'application/octet-stream';
      try {
        final r = (await _ask('send_media', {'to': chatId, 'path': path, 'mime': mime, 'name': path.split(Platform.pathSeparator).last, 'text': i == paths.length - 1 ? caption : ''}) as Map?) ?? const {};
        final ts = (r['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        _messages.putIfAbsent(chatId, () => []).add({'ts': ts, 'from': '', 'mine': true, 'text': i == paths.length - 1 ? caption : '', 'media': [{'local': path, 'mime': mime, 'name': path.split(Platform.pathSeparator).last, 'pointer': {'local': path}}], 'state': 'sent'});
        _files[jsonEncode({'local': path}).hashCode & 0x3fffffff] = path;
        _chats.putIfAbsent(chatId, () => {'unread': 0})['last'] = ts;
      } catch (e) {
        _error = '$e';
        break;
      }
    }
    _save();
    notifyListeners();
  }

  @override
  void wantFile(int fileId) => unawaited(fileOf(fileId));

  @override
  Future<String?> fileOf(int fileId) async {
    final known = _files[fileId];
    if (known != null) return known;
    final a = _pointers[fileId];
    if (a == null) return null;
    final ext = '${a['name'] ?? ''}'.contains('.') ? '.${'${a['name']}'.split('.').last}' : '';
    final path = '$_dir/files/$fileId$ext';
    if (File(path).existsSync()) return _files[fileId] = path;
    try {
      await Directory('$_dir/files').create(recursive: true);
      await _ask('download', {'pointer': a['pointer'], 'path': path});
      _files[fileId] = path;
      notifyListeners();
      return path;
    } catch (e) {
      _error = '$e';
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
    final unread = [for (final m in _messages[chatId] ?? const <Map<String, Object?>>[]) if (m['mine'] != true) m].reversed.take(20).toList();
    final byAuthor = <String, List<int>>{};
    for (final m in unread) {
      byAuthor.putIfAbsent('${m['from']}', () => []).add(m['ts'] as int);
    }
    for (final e in byAuthor.entries) {
      try {
        await _ask('read', {'to': chatId, 'author': e.key, 'ts': e.value});
      } catch (_) {}
    }
  }

  /// Your own message can be deleted for everyone; anyone else's only here.
  @override
  bool canDeleteForEveryone(String chatId, InboxMessage message) => message.mine;

  @override
  Future<void> deleteMessage(String chatId, String messageId, {bool forEveryone = false}) async {
    if (forEveryone) {
      try {
        await _ask('delete', {'to': chatId, 'ts': int.parse(messageId)});
      } catch (e) {
        _error = '$e';
      }
    }
    _messages[chatId]?.removeWhere((m) => '${m['ts']}' == messageId);
    _save();
    notifyListeners();
  }

  /// Gone from here: Signal keeps no conversations on its servers to delete.
  @override
  Future<void> deleteChat(String chatId) async {
    _chats.remove(chatId);
    _messages.remove(chatId);
    _save();
    notifyListeners();
  }

  // --- keeping ------------------------------------------------------------------------------------------------------

  void _read() {
    try {
      if (!_file.existsSync()) return;
      final all = jsonDecode(_file.readAsStringSync()) as Map;
      (all['chats'] as Map? ?? const {}).forEach((k, v) => _chats['$k'] = (v as Map).cast<String, Object?>());
      (all['messages'] as Map? ?? const {}).forEach((k, v) => _messages['$k'] = [for (final m in v as List) (m as Map).cast<String, Object?>()]);
      (all['names'] as Map? ?? const {}).forEach((k, v) => _names['$k'] = '$v');
      _groups.addAll((all['groups'] as List? ?? const []).map((g) => '$g'));
    } catch (_) {}
  }

  Timer? _saving;
  void _save() {
    _saving?.cancel();
    _saving = Timer(const Duration(milliseconds: 400), () {
      try {
        _file.parent.createSync(recursive: true);
        final tmp = File('${_file.path}.tmp');
        tmp.writeAsStringSync(jsonEncode({'chats': _chats, 'messages': _messages, 'names': _names, 'groups': _groups.toList()}));
        tmp.renameSync(_file.path);
      } catch (_) {}
    });
  }

  /// Writes what is kept now (a test's end, the app going).
  @visibleForTesting
  void flush() {
    if (_saving?.isActive ?? false) {
      _saving!.cancel();
      _saving = Timer(Duration.zero, () {});
      try {
        _file.parent.createSync(recursive: true);
        _file.writeAsStringSync(jsonEncode({'chats': _chats, 'messages': _messages, 'names': _names, 'groups': _groups.toList()}));
      } catch (_) {}
    }
  }

  Future<Object?> _ask(String op, [Map<String, Object?> args = const {}]) {
    final link = _link;
    if (link == null) return Future.error(StateError('Signal isn\'t running'));
    final id = ++_asked;
    final done = Completer<Object?>();
    _waiting[id] = done;
    link.say({'id': id, 'op': op, ...args});
    // Longer than the helper gives each (sidecar/signal's do: a minute, three for files), so its own reason arrives.
    final wait = switch (op) { 'download' || 'send_media' => 190, 'send' || 'react' || 'delete' || 'read' || 'groups' => 75, _ => 30 };
    return done.future.timeout(Duration(seconds: wait), onTimeout: () {
      _waiting.remove(id);
      throw StateError('Signal took too long to answer');
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

  /// The app's preferences, for later use (a chat's own settings).
  AppState? get app => _app;
}

/// The helper's log, as the Developer log keeps it (_ProcessLink).
abstract final class SignalLog {
  /// One line of the helper's log, shortened, where it is worth keeping: the helper's own lines about requests and
  /// sends, and anything signalmeow warns of; null for the rest.
  static String? keep(String line) => _ProcessLink.keep(line);
}

class _ProcessLink implements SignalLink {
  _ProcessLink(this.p) {
    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      try {
        final m = jsonDecode(line);
        if (m is Map) _in.add(m.cast<String, Object?>());
      } catch (_) {}
    });
    // The helper's log (sidecar/signal: also signal.log beside its store): what matters goes to the Developer log, so
    // a send that stalls says where (Matt, 2026-11-16: "Sending signal messages get stuck on sending"). signalmeow logs
    // no message's words at this level, and the helper's own lines name an op, a chat and a time, never the text.
    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(logLine);
  }

  /// One line of the helper's log, for the Developer log where it is worth keeping.
  @visibleForTesting
  static String? keep(String line) {
    Map? m;
    try {
      final d = jsonDecode(line);
      if (d is Map) m = d;
    } catch (_) {}
    if (m == null) return line.trim().isEmpty ? null : (line.length > 300 ? line.substring(0, 300) : line);
    final level = '${m['level'] ?? ''}';
    final message = '${m['message'] ?? ''}';
    const ours = {'asked', 'answered', 'send', 'sent', 'send to group', 'sent to group', 'group not described', 'send: not connected to Signal; trying anyway'};
    // A send's own steps (trace: true, sidecar/signal send): kept whatever their level, with their time, so the
    // Developer log shows which step a slow send waited on.
    final traced = m['trace'] == true;
    if (!traced && level != 'warn' && level != 'error' && level != 'fatal' && !ours.contains(message)) return null;
    const fields = ['op', 'req', 'took', 'sent_to', 'failed', 'error', 'action', 'component', 'authed_ws', 'unauthed_ws', 'response_status', 'retry_count'];
    final parts = [if (traced && m['time'] != null) '${m['time']}', level, message, for (final k in fields) if (m[k] != null) '$k=${m[k]}'];
    final out = parts.join(' ');
    return out.length > 300 ? out.substring(0, 300) : out;
  }

  static void logLine(String line) {
    final kept = keep(line);
    if (kept != null) Sms.instance.devLog('signal', kept);
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

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
