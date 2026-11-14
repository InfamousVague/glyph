import 'dart:convert';
import 'dart:io';

import 'link/link.dart';
import 'platform.dart';

/// Where the Mac keeps what it must between runs: the pairing (who the phone is, how the two connect, and the
/// pairing's key) and the person's choices (the theme, the relay's address). What was read from the phone is kept
/// apart, sealed with a key made from the pairing's (cache.dart; docs/desktop.md, "What the Mac keeps").
///
/// The key is kept in the Keychain. Where the Keychain will not take it (a build signed to run on this Mac alone
/// loses its Keychain items' trust with every rebuild, and macOS would ask for the password each time), it is kept
/// in the app's own folder, in a file only the person's account can read: [keychain] false.
class DeskStore implements LinkStore {
  DeskStore(this.dir, {this.keychain = true});

  final Directory dir;
  final bool keychain;

  static const _account = 'pairing-key';

  /// The app's own folder: inside its sandbox container on a Mac.
  static Directory defaultDir() {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return Directory('$home/Library/Application Support/Ghost Messaging');
  }

  File get _pairing => File('${dir.path}/pairing.json');
  File get _prefs => File('${dir.path}/prefs.json');

  Future<void> _last = Future.value();
  int _writes = 0;

  /// Written whole to a file beside it and moved into place, one write after another: two choices changed at once
  /// are two writes, and the later is what is kept.
  Future<void> _write(File file, Object value) {
    final text = jsonEncode(value);
    return _last = _last.catchError((_) {}).then((_) async {
      await dir.create(recursive: true);
      final tmp = File('${file.path}.${_writes++}.tmp');
      await tmp.writeAsString(text, flush: true);
      // The person's account alone: the pairing's key may be in it.
      try {
        await Process.run('/bin/chmod', ['600', tmp.path]);
      } catch (_) {}
      await tmp.rename(file.path);
    });
  }

  @override
  Future<PairedPhone?> load() async {
    try {
      if (!await _pairing.exists()) return null;
      final o = jsonDecode(await _pairing.readAsString()) as Map<String, dynamic>;
      final key = (o['key'] as String?) ?? (keychain ? await MacPlatform.keyRead(_account) : null);
      if (key == null) return null;
      return PairedPhone(
        id: o['id'] as String,
        name: (o['name'] as String?) ?? 'Your phone',
        key: base64.decode(key),
        mode: (o['mode'] as String?) ?? 'both',
        relay: (o['relay'] as String?) ?? '',
        since: DateTime.fromMillisecondsSinceEpoch((o['since'] as num?)?.toInt() ?? 0),
        host: o['host'] as String?,
        port: (o['port'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PairedPhone p) async {
    final key = base64.encode(p.key);
    final kept = keychain && await MacPlatform.keyWrite(_account, key);
    await _write(_pairing, {
      'id': p.id, 'name': p.name, 'mode': p.mode, 'relay': p.relay, 'since': p.since.millisecondsSinceEpoch, 'host': p.host, 'port': p.port,
      // In the file only where the Keychain did not take it.
      if (!kept) 'key': key,
    });
  }

  @override
  Future<void> clear() async {
    if (keychain) await MacPlatform.keyDelete(_account);
    try {
      if (await _pairing.exists()) await _pairing.delete();
    } catch (_) {}
  }

  /// The person's choices on this Mac, by name.
  Future<Map<String, String>> prefs() async {
    try {
      if (!await _prefs.exists()) return {};
      return {for (final e in (jsonDecode(await _prefs.readAsString()) as Map).entries) '${e.key}': '${e.value}'};
    } catch (_) {
      return {};
    }
  }

  Future<void> savePrefs(Map<String, String> prefs) => _write(_prefs, prefs);
}
