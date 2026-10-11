/// The files sync carries besides the notes (docs/STAGE7.md, "Sync"): a note's recording, the pictures notes show,
/// and a note's versions file, as the Rust core keeps them (native/src/files.rs). What `deviceFiles` in
/// `src/app/core/sync/engine.ts` did with the page's `img` and `rec` schemes and Tauri's `sync_put_file`: the
/// device's half of `LocalFiles` (`read`, `write`, `digest`).
///
/// **Two roads for a file, by its size.**
///
/// - Small (a picture, a versions file): [read] and [write] carry the bytes, as the page's did.
/// - Large (a recording can be an hour): the bytes never reach Dart. [where] says where the file lies, the crypto
///   seals it from there into a file to upload (lib/account/crypto.dart `sealFile`); what is downloaded is opened
///   to a file (`openFile`) and [adopt] moves it into place, under the same rules [write] checks.
///
/// A name is the core's to check (a note id for a recording or a versions file, a picture's own name): one that may
/// not name a file reads as null and is refused on a write, with the Tauri command's own sentence.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../bytes.dart';
import 'core.dart';

/// Which of a device's files (`FileKind`, core/sync/notes.ts): a recording or a versions file, by note id, or a
/// picture, by name.
enum CoreFileKind { recording, image, versions }

/// A device's recordings, pictures and versions files, through the core.
class CoreFiles {
  const CoreFiles(this._invoke);

  final CoreInvoke _invoke;

  Map<String, Object?> _named(CoreFileKind kind, String name) => {'kind': kind.name, 'name': name};

  /// The file's bytes, or null where this device has none (`LocalFiles.read`). A versions file's are its text as
  /// UTF-8, as the page encoded it.
  Future<Uint8List?> read(CoreFileKind kind, String name) async {
    final said = await _invoke('read_file', _named(kind, name)) as String?;
    return said == null ? null : base64.decode(said);
  }

  /// Keeps a file that arrived by sync (`LocalFiles.write`): a recording under its note's id (it must be a RIFF
  /// file), a picture under its own name (it must be the kind of picture its name says), a versions file beside
  /// its note. Written whole or not at all. Answers false only for a versions file whose note is not here.
  Future<bool> write(CoreFileKind kind, String name, Uint8List bytes) async {
    if (kind == CoreFileKind.versions) {
      return await _invoke('versions_write', {'id': name, 'text': utf8.decode(bytes)}) as bool;
    }
    // Standard base64, which is what the Tauri command read.
    await _invoke('sync_put_file', {..._named(kind, name), 'base64': toBase64(bytes)});
    return true;
  }

  /// Keeps a recording or a picture that was opened to the file at [path], which is moved into place: [write]
  /// without the bytes crossing. A file that is refused is left where it was.
  Future<void> adopt(CoreFileKind kind, String name, String path) async {
    await _invoke('sync_put_file_path', {..._named(kind, name), 'path': path});
  }

  /// Where a recording or a picture lies and how long it is, to be sealed from there; null where this device has
  /// none. A versions file has no path to give (its folder may be one Android's picker chose): [read] it.
  Future<({String path, int bytes})?> where(CoreFileKind kind, String name) async {
    final said = await _invoke('file_path', _named(kind, name)) as Map?;
    return said == null ? null : (path: said['path'] as String, bytes: said['bytes'] as int);
  }

  /// The file's fingerprint as sync keeps it (`LocalFiles.digest`, core/sync/notes.ts `sha`): the first sixteen
  /// bytes of its SHA-256 as hex, hashed by the core without the file being read into Dart. Null with no file.
  Future<String?> digest(CoreFileKind kind, String name) async => await _invoke('file_digest', _named(kind, name)) as String?;

  /// Whether this device has the file.
  Future<bool> exists(CoreFileKind kind, String name) async => await _invoke('file_exists', _named(kind, name)) as bool;
}
