import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../desktop/platform.dart';
import '../friends/buddies.dart';
import '../net/crypto.dart';
import '../sms.dart';
import 'chats.dart';

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
  StandaloneCalls(this.dir, {this.keychain = true}) {
    chats = UsernameChats(save: _save, buddies: () => _buddyList);
  }

  /// The folder everything of this install's is kept in ([defaultDir] on an iPhone).
  final Directory dir;

  /// Whether the identity is kept in the Keychain (a build for a device) or in the folder (a test).
  final bool keychain;

  /// The name the identity is kept under in the Keychain.
  static const _account = 'standalone-identity';

  /// Who this iPhone is, once [load] has run; the person's choices; and the friends by username, as the JSON
  /// [Buddies] gave to be kept.
  NetKeys? _keys;
  Map<String, String> _prefs = {};
  String _buddies = '[]';

  /// The conversations: every one an iPhone has is with a friend by username.
  late final UsernameChats chats;

  /// The files in [dir]: everything kept, the identity where the Keychain does not hold it, and a secret by its
  /// name (cut down to lower-case letters, digits and _, so a name cannot reach outside the folder).
  File get _file => File('${dir.path}/standalone.json');
  File get _keyFile => File('${dir.path}/identity.key');
  File _secretFile(String name) => File('${dir.path}/secret-${name.replaceAll(RegExp(r'[^a-z0-9_]'), '')}.key');

  /// Starts the app again: on a Mac a new copy of the app is opened and this one ends; an iPhone cannot, and says so
  /// (false), and the person is asked to. Never under a test.
  Future<bool> Function() restart = _restartHere;

  static Future<bool> _restartHere() async {
    if (Platform.environment.containsKey('FLUTTER_TEST') || !Platform.isMacOS) return false;
    // …/Ghost Messaging.app/Contents/MacOS/Ghost Messaging, three folders up.
    final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
    if (!app.endsWith('.app')) return false;
    await Process.start('/bin/sh', ['-c', 'sleep 1; /usr/bin/open -n "\$0"', app], mode: ProcessStartMode.detached);
    exit(0);
  }

  /// The address a friend by username is spoken of by: `@` and their username.
  static String addressOf(String username) => UsernameChats.addressOf(username);

  /// Where an iPhone keeps it: the app's Application Support folder, which iOS keeps and backs up. iOS gives a Flutter
  /// app no HOME, so the container is found from its tmp folder, which is in it.
  static Directory defaultDir() {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.parent.path;
    return Directory('$home/Library/Application Support/Ghost Messaging');
  }

  /// Where the first builds kept it by mistake: inside tmp, which iOS may empty. Moved from once, if it is there.
  static Directory get _misplaced => Directory('${Directory.systemTemp.path}/Library/Application Support/Ghost Messaging');

  /// Reads what is kept and the identity, making one where there is none. Before anything is drawn.
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
      chats.load(j);
    } catch (_) {}
    _keys = await _identity();
  }

  /// The key kept (32 bytes as 64 hex digits), from the Keychain or the folder; a new one, kept, where none is.
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

  /// The write before this one: each waits for the last, so the file is never written by two at once.
  Future<void> _last = Future.value();

  /// Writes everything kept, as it is now, to a new file that then takes the old one's place: a write cut short
  /// leaves the old file whole.
  void _save() {
    final text = jsonEncode({'prefs': _prefs, 'buddies': _buddies, ...chats.toJson()});
    _last = _last.catchError((_) {}).then((_) async {
      final temp = File('${_file.path}.new');
      await temp.writeAsString(text, flush: true);
      await temp.rename(_file.path);
    });
  }

  /// Every write done, for a test.
  @visibleForTesting
  Future<void> flushed() => _last;

  List<Buddy> get _buddyList {
    try {
      return [for (final j in jsonDecode(_buddies) as List) ?Buddy.fromJson(j)];
    } catch (_) {
      return const [];
    }
  }

  // --- the calls ---------------------------------------------------------------------------------------------------

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    final a = arguments is Map ? arguments : const {};
    return (await _answer(method, a)) as T?;
  }

  /// Answers one of the phone's calls by its name, in the shape the phone answers in.
  Future<Object?> _answer(String method, Map a) async {
    int thread() => (a['thread'] as num).toInt();
    switch (method) {
      // Who this iPhone is, and who it reaches.
      case 'netIdentity':
        final k = _keys!;
        return {'id': k.id, 'key': base64Encode(k.public)};
      case 'netSign':
        return NetCrypto.sign(_keys!, (a['message'] as List).cast<int>());
      case 'netPeers':
        return UsernameChats.peersOf(_buddyList, _keys!);

      // A Ghost account (lib/account; Matt, 2026-11-17: "We need to have a way to login to existing accounts"): this
      // install's key to seal into the account's backup, a restored key put in its place, the account's words kept
      // beside the key in the Keychain, and a clean start once a device has signed in.
      case 'identityExport':
        return _keys!.scalar;
      case 'identityImport':
        final made = NetKeys.fromScalar((a['scalar'] as List).cast<int>());
        final hex = NetCrypto.hex(made.scalar);
        if (!keychain || !await MacPlatform.keyWrite(_account, hex)) {
          _keyFile.writeAsStringSync(hex, flush: true);
        } else if (_keyFile.existsSync()) {
          // The Keychain took it: a key left in the folder from before would be read first on a build without it.
          _keyFile.deleteSync();
        }
        _keys = made;
        return null;
      case 'secretKeep':
        final name = '${a['name']}', value = '${a['value'] ?? ''}';
        final file = _secretFile(name);
        if (value.isEmpty) {
          if (keychain) await MacPlatform.keyDelete('standalone-secret-$name');
          if (file.existsSync()) file.deleteSync();
          return null;
        }
        // The Keychain where it takes it; else the app's own folder, as the identity's key itself is kept then.
        if (!keychain || !await MacPlatform.keyWrite('standalone-secret-$name', value)) file.writeAsStringSync(value, flush: true);
        return null;
      case 'secretRead':
        final name = '${a['name']}';
        final kept = keychain ? await MacPlatform.keyRead('standalone-secret-$name') : null;
        if (kept != null) return kept;
        final file = _secretFile(name);
        return file.existsSync() ? file.readAsStringSync() : null;
      case 'restartApp':
        await flushed();
        return restart();
      case 'buddiesKeep':
        _buddies = (a['json'] as String?) ?? '[]';
        _save();
        Sms.instance.prefsChanged.add(null);
        return null;
      case 'buddiesKept':
        return _buddies;
      case 'e2eList':
        return chats.states();
      case 'e2e':
        final address = '${a['address']}';
        return chats.states().firstWhere((s) => s['address'] == address, orElse: () => {'address': address, 'state': 'none'});
      case 'friendSet':
        return null;

      // What friends write, kept here ([Friends] by the routes).
      case 'netTextOut':
        return chats.textOut('${a['address']}', '${a['body']}');
      case 'netTextState':
        chats.textState((a['id'] as num).toInt(), '${a['state']}');
        return null;
      case 'netTextDrop':
        chats.dropRow((a['id'] as num).toInt());
        return null;
      case 'netTextIn':
        chats.textIn('${a['address']}', '${a['body']}', (a['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch);
        return null;

      // The list and a conversation.
      case 'conversations':
        return [for (final t in chats.sorted()) chats.conversation(t)];
      case 'conversationsPage':
        // `pinned` asks for the pinned ones as well as the newest, as Android's does (pinnedToo): they head the list
        // however old they are.
        final all = chats.sorted(archived: a['archived'] == true);
        final offset = (a['offset'] as num?)?.toInt() ?? 0, limit = (a['limit'] as num?)?.toInt() ?? 0;
        final page = limit <= 0 ? all.skip(offset).toList() : all.skip(offset).take(limit).toList();
        if (a['pinned'] == true && offset == 0) page.addAll(all.where((t) => t.pinned && !page.contains(t)));
        final next = limit > 0 && offset + limit < all.length ? offset + limit : null;
        return {'items': [for (final t in page) chats.conversation(t)], 'next': next};
      case 'conversation':
        final t = chats.threads[thread()];
        return t == null ? null : chats.conversation(t);
      case 'archivedCount':
        return chats.sorted(archived: true).length;
      case 'messages':
        return chats.messages(thread(), (a['limit'] as num?)?.toInt() ?? 0);
      case 'people':
        final t = chats.threads[thread()];
        return t == null ? const [] : [chats.person(t.address)];
      case 'threadFor':
        final addresses = ((a['addresses'] as List?) ?? const []).map((x) => '$x').toList();
        if (addresses.length != 1) return -1;
        final t = chats.threadWith(addresses.first);
        _save();
        return t.id;
      case 'send':
        final addresses = ((a['addresses'] as List?) ?? const []).map((x) => '$x').toList();
        if (addresses.length != 1) throw StateError('Only words to one friend can be sent from this iPhone yet');
        return chats.send(addresses.first, '${a['body'] ?? ''}');
      case 'markRead':
        chats.markRead(thread());
        return null;
      case 'setOpenThread':
        chats.open = (a['thread'] as num?)?.toInt() ?? -1;
        return null;
      case 'deleteThread':
        chats.delete([thread()]);
        return null;
      case 'deleteThreads':
        chats.delete([for (final id in (a['threads'] as List? ?? const [])) (id as num).toInt()]);
        return null;
      case 'deleteMessage':
        chats.deleteRow((a['id'] as num).toInt());
        return null;
      case 'archive':
        chats.archive(thread(), a['archived'] == true);
        return null;
      case 'threadFlag':
        chats.flag('${a['name']}', thread(), a['on'] == true);
        return null;
      case 'draft':
        return chats.draft(thread());
      case 'setDraft':
        chats.setDraft(thread(), '${a['text'] ?? ''}');
        return null;
      case 'contact':
        return chats.person('${a['address']}');
      case 'searchContacts':
        return chats.search('${a['query'] ?? ''}');

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

      // A link opened in this device's own browser: a link in a message, and signing up with Discord (Matt,
      // 2026-11-20: "when clicking sign up with discord it says "no browser could be opened""), which had nothing here.
      case 'openLink':
        return MacPlatform.openLink('${a['url'] ?? ''}');

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

/// Sets the app up as an iPhone of its own, before anything is drawn: the calls answered here, and the routes,
/// directory and calls run here ([Sms.standalone]).
Future<void> standaloneSetup({Directory? dir, bool? keychain}) async {
  final calls = StandaloneCalls(dir ?? StandaloneCalls.defaultDir(), keychain: keychain ?? kReleaseMode);
  await calls.load();
  Sms.calls = calls;
  Sms.standalone = true;
}
