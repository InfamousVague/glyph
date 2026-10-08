/// A device signed in to the service in memory (fake_service.dart), for a test of the note sync pass. A port of
/// `src/test/syncDevice.ts`.
///
/// Its notes, its pictures, its recordings and its versions files in maps behind the two stores the pass is given,
/// what it remembers of the account, and a [SyncDevice.sync] that runs one pass. [SyncDevice.clock] is the device's
/// time, for the waits the pass keeps (a picture not asked for again for a while); a test moves it by hand.
/// [SyncDevice.fetcher] stands between this device and the service, for a test that has another device write at a
/// moment of its choosing - between this one's pull and its push, say.
///
/// What differs, and why: THE PASS IS NOT PORTED YET (`core/sync/notes.ts` `syncNotes`; docs/STAGE7.md, piece F).
/// So this is the device WITHOUT the engine's types, shaped so the engine has nothing to change here but two
/// `implements` clauses and one line:
/// - [DeviceNotes] has the methods of the web's `LocalNotes` (`list`, `get`, `apply`, `remove`) and [DeviceFiles]
///   those of `LocalFiles` (`read`, `write`, `owed`, `settled`, and `digest` when the test gives one), by the same
///   names and with the same answers; [FileKind] is the web's three words.
/// - What the device remembers of the account (`SyncState`: a cursor, each note's revision and mark, each file's) is
///   the engine's to define, so it is a type parameter, [S], with the empty one handed in.
/// - [SyncDevice.sync] takes the pass as a function of the device, where the web's calls `syncNotes` with the
///   device's token, key, stores, state, `save`, fetcher and `now`: a test of the engine writes
///   `device.sync((d) => syncNotes(SyncContext(token: d.token, key: d.key, notes: d.local, files: d.files, state:
///   d.state, save: d.save, api: d.api, now: d.now)))`, or the engine's own helper does.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/note.dart';

import 'fake_service.dart';

/// Which of a device's files (`FileKind`): a recording or a versions file, by note id, or a picture, by name.
enum FileKind { recording, image, versions }

/// A recording's fingerprint without reading it into the page (`LocalFiles.digest`): null with no file.
typedef FileDigest = Future<String?> Function(String name);

/// This device's notes (`LocalNotes`).
class DeviceNotes {
  /// By id.
  final Map<String, Note> held = {};

  Future<List<Note>> list() async => held.values.toList();
  Future<Note?> get(String id) async => held[id];
  Future<Note> apply(Note note) async => held[note.id] = note;
  Future<void> remove(String id) async => held.remove(id);
}

/// This device's recordings and versions files (by note id) and pictures (by name) (`LocalFiles`).
class DeviceFiles {
  DeviceFiles({Map<String, Uint8List> pictures = const {}, this.digest}) : pictures = {...pictures};

  /// Pictures by name.
  final Map<String, Uint8List> pictures;

  /// Recordings by note id.
  final Map<String, Uint8List> tapes = {};

  /// Versions files by note id, as text, and the notes whose file changed here since it was sent.
  final Map<String, String> versions = {};
  final Set<String> owing = {};

  /// A recording's fingerprint made without reading the file, where the test gives one; null where this device
  /// cannot say, and the pass reads and hashes the file itself (the web's `digest?`, left out).
  final FileDigest? digest;

  Future<Uint8List?> read(FileKind kind, String name) async {
    if (kind == FileKind.versions) {
      final text = versions[name];
      return text == null ? null : utf8.encode(text);
    }
    return (kind == FileKind.image ? pictures : tapes)[name];
  }

  Future<void> write(FileKind kind, String name, Uint8List bytes) async {
    if (kind == FileKind.versions) {
      versions[name] = utf8.decode(bytes);
    } else {
      (kind == FileKind.image ? pictures : tapes)[name] = bytes;
    }
  }

  /// The notes whose versions file changed here since it was last sent.
  List<String> owed() => owing.toList();

  /// Note [name]'s versions file is with the account now.
  void settled(String name) => owing.remove(name);
}

/// A device of the seeded account (`syncDevice`). [S] is what the engine keeps between passes.
class SyncDevice<S> {
  /// [state] is the engine's empty state. [clock] is the device's time in ms, 0 unless given; [fetcher] stands
  /// between the device and the service.
  SyncDevice(this.service, {required this.state, this.clock = 0, Map<String, Uint8List> pictures = const {}, Fetcher? fetcher, FileDigest? digest})
      : fetcher = fetcher ?? service.fetcher,
        key = service.accountKey,
        token = service.signedIn(),
        files = DeviceFiles(pictures: pictures, digest: digest);

  final FakeService service;
  final Fetcher fetcher;

  /// The account key, and a live token: what a device that signed in earlier holds.
  final SealKey key;
  final String token;

  /// The device's time, in ms: a test moves it by hand.
  int clock;

  final DeviceNotes local = DeviceNotes();
  final DeviceFiles files;

  Map<String, Note> get notes => local.held;
  Map<String, Uint8List> get held => files.pictures;
  Map<String, Uint8List> get tapes => files.tapes;
  Map<String, String> get versions => files.versions;
  Set<String> get owed => files.owing;

  /// The crypto the service seals with: the device's too.
  AccountCrypto get crypto => service.crypto;

  /// The service through this device's fetcher.
  late final Api api = Api(base: 'http://service.test/api', fetcher: fetcher);

  /// What the device remembers of the account.
  S state;

  /// Called by the pass after each page of the feed and each push, so an interrupted sync resumes where it stopped.
  void save(S next) => state = next;

  /// The device's time, as the pass asks for it.
  int now() => clock;

  /// Keeps a versions file here as the app does when a version is kept: owed to the account until sent.
  void keepVersions(String noteId, String text) {
    files.versions[noteId] = text;
    files.owing.add(noteId);
  }

  /// One pass: [pass] is the engine's, handed this device.
  Future<T> sync<T>(Future<T> Function(SyncDevice<S> device) pass) => pass(this);
}
