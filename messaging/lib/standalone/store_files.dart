import 'dart:io';

import '../desktop/platform.dart';
import 'store.dart';

/// [StandaloneStore] on a computer and an iPhone: a folder of this app's, and the Keychain where the build has it.
///
/// - `standalone.json` is the JSON, written beside itself and moved into place.
/// - The identity's key is in the Keychain ([keychain]: a build for a device), or in `identity.key` (a test, a build
///   signed to run on one Mac alone, a Keychain that would not take it).
/// - A secret is in the Keychain as `standalone-secret-<name>`, or in `secret-<name>.key`.
class StandaloneFiles implements StandaloneStore {
  StandaloneFiles(this.dir, {this.keychain = true});

  final Directory dir;

  /// Whether the identity is kept in the Keychain (a build for a device) or in the folder (a test).
  final bool keychain;

  static const _account = 'standalone-identity';

  File get _file => File('${dir.path}/standalone.json');
  File get _keyFile => File('${dir.path}/identity.key');
  File _secretFile(String name) => File('${dir.path}/secret-${name.replaceAll(RegExp(r'[^a-z0-9_]'), '')}.key');

  /// Where the first builds kept it by mistake: inside tmp, which iOS may empty. Moved from once, if it is there.
  static Directory get _misplaced => Directory('${Directory.systemTemp.path}/Library/Application Support/Ghost Messaging');

  @override
  Future<void> open() async {
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
  }

  @override
  Future<String?> readState() => _file.readAsString();

  @override
  Future<void> writeState(String text) async {
    final temp = File('${_file.path}.new');
    await temp.writeAsString(text, flush: true);
    await temp.rename(_file.path);
  }

  @override
  Future<String?> readIdentity() async {
    String? kept = keychain ? await MacPlatform.keyRead(_account) : null;
    if (kept == null && _keyFile.existsSync()) kept = _keyFile.readAsStringSync().trim();
    return kept;
  }

  @override
  Future<void> writeIdentity(String hex, {bool imported = false}) async {
    if (!imported) {
      // The Keychain where it takes it; else the app's own folder, which iOS keeps to this app alone.
      if (!keychain || !await MacPlatform.keyWrite(_account, hex)) _keyFile.writeAsStringSync(hex);
      return;
    }
    if (!keychain || !await MacPlatform.keyWrite(_account, hex)) {
      _keyFile.writeAsStringSync(hex, flush: true);
    } else if (_keyFile.existsSync()) {
      // The Keychain took it: a key left in the folder from before would be read first on a build without it.
      _keyFile.deleteSync();
    }
  }

  @override
  Future<String?> readSecret(String name) async {
    final kept = keychain ? await MacPlatform.keyRead('standalone-secret-$name') : null;
    if (kept != null) return kept;
    final file = _secretFile(name);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  Future<void> writeSecret(String name, String value) async {
    // The Keychain where it takes it; else the app's own folder, as the identity's key itself is kept then.
    if (!keychain || !await MacPlatform.keyWrite('standalone-secret-$name', value)) _secretFile(name).writeAsStringSync(value, flush: true);
  }

  @override
  Future<void> deleteSecret(String name) async {
    final file = _secretFile(name);
    if (keychain) await MacPlatform.keyDelete('standalone-secret-$name');
    if (file.existsSync()) file.deleteSync();
  }
}
