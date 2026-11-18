import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../friends/buddies.dart';
import '../net/crypto.dart';
import '../sms.dart';
import '../standalone/chats.dart';
import '../standalone/overlay.dart';
import 'platform.dart';
import 'remote.dart';

/// A computer paired with a phone, with friends and circles of its own (Matt, 2026-11-18: "I want desktop to be able to
/// run standalone for internal friends and circles please fix that even if the desktop is linked").
///
/// Texts are the phone's, asked across the link ([LinkCalls], [inner]). Friends by username are this computer's: the
/// phone hands over its identity, its friends and its conversations with them once ([adopt], over the pairing's own
/// sealed link), and from then on this computer is on the relay server's hub as a device of that identity beside the
/// phone (relay/lib/hub.dart: a name's devices are each handed what is sent to it), so friends reach it with the phone
/// switched off. What is about an `@username` address, or a conversation kept here, is answered here, as on the phone
/// ([UsernameOverlay]); the routes' identity and the list of friends are this computer's too.
class DeskOwnCalls extends UsernameOverlay implements CapableCalls, OwnNetworkCalls {
  DeskOwnCalls(LinkCalls link, this.dir, {this.keychain = true}) : super(link, File('${dir.path}/chats.json'));

  /// Where this computer keeps them: its own folder beside the pairing.
  final Directory dir;

  /// Whether the identity is kept in the Keychain (a release build) or in the folder (a test, a build of one's own).
  final bool keychain;

  static const _account = 'desk-own-identity';

  NetKeys? _keys;
  String _buddyJson = '[]';

  LinkCalls get link => inner as LinkCalls;

  @override
  Set<String> get caps => link.caps;

  File get _buddyFile => File('${dir.path}/buddies.json');
  File get _keyFile => File('${dir.path}/identity.key');

  /// Whether the phone's identity has been taken on here: only then is this used (lib/desktop/main.dart).
  static bool adoptedIn(Directory dir) => File('${dir.path}/adopted.json').existsSync();

  @override
  Future<void> load() async {
    dir.createSync(recursive: true);
    await super.load();
    try {
      _buddyJson = await _buddyFile.readAsString();
    } catch (_) {
      _buddyJson = '[]';
    }
    keepBuddies(_buddyJson);
    String? kept = keychain ? await MacPlatform.keyRead(_account) : null;
    if (kept == null && _keyFile.existsSync()) kept = _keyFile.readAsStringSync().trim();
    if (kept != null && kept.length == 64) {
      try {
        _keys = NetKeys.fromScalar(NetCrypto.unhex(kept));
      } catch (_) {}
    }
  }

  /// Takes on what the phone handed over ([handover]): its identity, its friends by username and its conversations
  /// with them. The identity is kept as the phone keeps it, in the Keychain (or this folder, for a build of one's own).
  static Future<void> adopt(Directory dir, Map<String, Object?> handover, {bool keychain = true}) async {
    dir.createSync(recursive: true);
    final scalar = '${handover['scalar'] ?? ''}';
    final keys = NetKeys.fromScalar(NetCrypto.unhex(scalar));
    if (!keychain || !await MacPlatform.keyWrite(_account, scalar)) File('${dir.path}/identity.key').writeAsStringSync(scalar);
    File('${dir.path}/buddies.json').writeAsStringSync('${handover['buddies'] ?? '[]'}');
    final chats = handover['chats'];
    if (chats is Map && !File('${dir.path}/chats.json').existsSync()) File('${dir.path}/chats.json').writeAsStringSync(jsonEncode(chats));
    File('${dir.path}/adopted.json').writeAsStringSync(jsonEncode({'id': keys.id, 'at': DateTime.now().millisecondsSinceEpoch}));
  }

  /// Friends by username the phone has and this computer does not, or has as less far along, taken in (asked of the
  /// phone each time the two connect): the two keep each other's lists, neither losing one the other made.
  static String mergeBuddies(String mine, String theirs) {
    List<Buddy> read(String j) {
      try {
        return [for (final b in jsonDecode(j) as List) ?Buddy.fromJson(b)];
      } catch (_) {
        return const [];
      }
    }

    int rank(String state) => state == 'yes' ? 2 : 1;
    final out = <String, Buddy>{for (final b in read(mine)) b.id: b};
    for (final b in read(theirs)) {
      final had = out[b.id];
      if (had == null || rank(b.state) > rank(had.state)) out[b.id] = b;
    }
    return jsonEncode([for (final b in out.values) b.toJson()]);
  }

  /// The phone's list taken in ([mergeBuddies]).
  void takeBuddies(String theirs) => _keepBuddyJson(mergeBuddies(_buddyJson, theirs));

  /// This computer's list, for the phone to take in.
  String get buddyJson => _buddyJson;

  void _keepBuddyJson(String json) {
    _buddyJson = json;
    keepBuddies(json);
    try {
      _buddyFile.writeAsStringSync(json);
    } catch (_) {}
    Sms.instance.prefsChanged.add(null);
  }

  @override
  Future<Object?> answerOwn(String method, Map a) async {
    final keys = _keys;
    switch (method) {
      // Who this computer is on the routes: the phone's identity, taken on.
      case 'netIdentity' when keys != null:
        return {'id': keys.id, 'key': base64Encode(keys.public)};
      case 'netSign' when keys != null:
        return NetCrypto.sign(keys, (a['message'] as List).cast<int>());
      case 'netPeers' when keys != null:
        return UsernameChats.peersOf(buddyList, keys);
      // Friends by username, kept here.
      case 'buddiesKeep':
        _keepBuddyJson((a['json'] as String?) ?? '[]');
        return null;
      case 'buddiesKept':
        return _buddyJson;
      // Where encryption stands: the phone's for its numbers, these for friends by username.
      case 'e2eList':
        List<Object?> phone;
        try {
          phone = [...?(await inner.invokeMethod<List>('e2eList'))];
        } catch (_) {
          phone = const [];
        }
        return [...phone, ...chats.states()];
      // The computer has no texts route of its own: what a friend is sent goes by the hub.
      case 'netSmsAvailable':
        return false;
      case 'netSmsDrain':
        return const [];
      // A new message from a friend: told of on this computer, not by the phone.
      case 'notifyChat' || 'cancelChat':
        return null;
    }
    return UsernameOverlay.pass;
  }

  @visibleForTesting
  NetKeys? get keys => _keys;
}
