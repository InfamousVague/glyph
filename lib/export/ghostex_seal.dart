/// A .ghostex sealed with a password (docs/INTEGRATIONS.md §5, "Protect with a password"): the whole ZIP sealed with
/// AES-256-GCM under a key that only the password opens, derived as the account's own password is
/// (lib/account/crypto_api.dart `derive`: PBKDF2-HMAC-SHA-256, 600,000 rounds), with a fresh random salt of its own.
///
/// The file, byte by byte:
///
/// ```
/// GHOSTEX1         8 bytes, the magic: a sealed export, where a ZIP starts PK
/// version          1 byte, 1
/// rounds           4 bytes, big-endian: PBKDF2's rounds, 600,000 outside tests
/// salt             16 random bytes, made for this file; the derivation is salted with `glyph/v1/ghostex/<them>`
/// key              60 bytes: iv (12) ‖ the ZIP's key under the password's (32) ‖ GCM's tag (16)
/// sealed ZIP       the rest: 1 ‖ iv (12) ‖ AES-256-GCM of the whole ZIP ‖ tag (16), bound to `ghostex`
/// ```
///
/// **Why a key of the ZIP's own, wrapped.** The Rust core holds every key and lets none of their bytes into Dart
/// (lib/account/crypto.dart); the half of a derived password it makes is a key that wraps, and wraps only. So the
/// ZIP is sealed under a fresh random key and that key is wrapped under the password's, exactly as the account key is
/// wrapped under the account's password (`account_key_wrap`): the same derivation, the same AES-256-GCM, and the
/// ZIP's iv in its own blob. A wrong password is GCM's tag refusing the wrap, before a byte of the ZIP is read.
///
/// The ZIP is sealed and opened file to file by the core (`seal_file`, `open_file`), so it never crosses into Dart.
/// The core reads the whole file once to seal it: one copy in memory, which for an export with long recordings is
/// the cost of sealing it whole.
library;

import 'dart:io';
import 'dart:typed_data';

import '../account/crypto.dart';
import '../account/crypto_api.dart' as api;
import '../core/bytes.dart';

/// A sealed export's first eight bytes.
const String ghostexMagic = 'GHOSTEX1';

/// The layout [GhostexSeal] writes.
const int ghostexSealVersion = 1;

/// What the ZIP is sealed as: a blob sealed for anything else does not open as one.
const String ghostexContext = 'ghostex';

const int _saltBytes = 16;

/// iv, the 32-byte key, and the tag.
const int _keyBytes = 12 + 32 + 16;

/// Everything before the sealed ZIP.
const int ghostexHeaderBytes = 8 + 1 + 4 + _saltBytes + _keyBytes;

/// What a .ghostex is, by its first bytes.
enum GhostexKind { zip, sealed, neither }

/// What [head] (a file's first bytes, eight or more) says it is.
GhostexKind ghostexKindOf(List<int> head) {
  if (head.length >= 8 && String.fromCharCodes(head.sublist(0, 8)) == ghostexMagic) return GhostexKind.sealed;
  if (head.length >= 4 && head[0] == 0x50 && head[1] == 0x4B && head[2] == 0x03 && head[3] == 0x04) return GhostexKind.zip;
  return GhostexKind.neither;
}

/// What the file at [path] is.
Future<GhostexKind> ghostexKindOfFile(String path) async {
  final file = await File(path).open();
  try {
    return ghostexKindOf(await file.read(8));
  } finally {
    await file.close();
  }
}

/// The salt the derivation is given: the file's own random bytes under the app's prefix.
String ghostexSalt(List<int> salt) => 'glyph/v1/ghostex/${toBase64Url(salt)}';

/// The password does not open this export.
class GhostexWrongPassword implements Exception {
  const GhostexWrongPassword();

  @override
  String toString() => 'That password does not open this export.';
}

/// Seals a ZIP into a .ghostex and opens one again. The app's is [CoreGhostexSeal].
abstract interface class GhostexSeal {
  /// The ZIP at [zip] sealed under [password] into the file at [out].
  Future<void> seal(String zip, String out, String password);

  /// The sealed export at [sealed] opened into the ZIP at [out]. Throws [GhostexWrongPassword] where the password
  /// is not the one it was sealed with, and a [StateError] where the file is not one or has been changed.
  Future<void> open(String sealed, String out, String password);
}

/// [GhostexSeal] by the Rust core, through the account's own crypto.
class CoreGhostexSeal implements GhostexSeal {
  CoreGhostexSeal(this.crypto, {this.rounds = api.rounds});

  final CoreCrypto crypto;

  /// PBKDF2's rounds for a new seal; an export says its own, which is what opens it.
  final int rounds;

  @override
  Future<void> seal(String zip, String out, String password) async {
    if (password.isEmpty) throw StateError('A password is needed to protect the export.');
    final salt = crypto.randomBytes(_saltBytes);
    final derived = await crypto.derive(password, ghostexSalt(salt), iterations: rounds);
    final key = await crypto.newAccountKey();
    final sealing = File('$out.sealing');
    final part = File('$out.part');
    try {
      final wrapped = fromBase64Url(await crypto.wrap(key, derived.wrapKey));
      if (wrapped.length != _keyBytes) throw StateError('The export’s key could not be wrapped.');
      await crypto.sealFile(key, ghostexContext, path: zip, out: sealing.path);
      final header = BytesBuilder(copy: false)
        ..add(ghostexMagic.codeUnits)
        ..addByte(ghostexSealVersion)
        ..add((ByteData(4)..setUint32(0, rounds)).buffer.asUint8List())
        ..add(salt)
        ..add(wrapped);
      final sink = part.openWrite();
      try {
        sink.add(header.takeBytes());
        await sink.addStream(sealing.openRead());
        await sink.flush();
      } finally {
        await sink.close();
      }
      await part.rename(out);
    } finally {
      await _gone(sealing);
      await _gone(part);
      await _forget(key);
      await _forget(derived.wrapKey);
    }
  }

  @override
  Future<void> open(String sealed, String out, String password) async {
    final file = await File(sealed).open();
    final Uint8List head;
    try {
      head = await file.read(ghostexHeaderBytes);
    } finally {
      await file.close();
    }
    if (head.length < ghostexHeaderBytes || ghostexKindOf(head) != GhostexKind.sealed) throw StateError('That is not a protected .ghostex file.');
    if (head[8] != ghostexSealVersion) throw StateError('This export was protected by a newer Ghost.md. Update the app to open it.');
    final at = ByteData.sublistView(head);
    final rounds = at.getUint32(9);
    final salt = head.sublist(13, 13 + _saltBytes);
    final wrapped = head.sublist(13 + _saltBytes, ghostexHeaderBytes);
    final derived = await crypto.derive(password, ghostexSalt(salt), iterations: rounds);
    final body = File('$out.sealed');
    api.SealKey? key;
    try {
      try {
        key = await crypto.unwrap(toBase64Url(wrapped), derived.wrapKey);
      } catch (_) {
        throw const GhostexWrongPassword();
      }
      // The core opens a file that starts with its own version byte: the header is left behind.
      final sink = body.openWrite();
      try {
        await sink.addStream(File(sealed).openRead(ghostexHeaderBytes));
      } finally {
        await sink.close();
      }
      try {
        await crypto.openFile(key, ghostexContext, path: body.path, out: out);
      } catch (_) {
        throw StateError('That export could not be opened: it has been changed since it was made.');
      }
    } finally {
      await _gone(body);
      if (key != null) await _forget(key);
      await _forget(derived.wrapKey);
    }
  }

  Future<void> _forget(api.KeyHandle key) async {
    try {
      await crypto.forget(key);
    } catch (_) {
      // Forgotten when Dart lets the handle go.
    }
  }
}

Future<void> _gone(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Left for the cache's own clearing.
  }
}
