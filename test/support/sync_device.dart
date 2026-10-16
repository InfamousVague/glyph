/// A device signed in to the service in memory (fake_service.dart), for a test of the note sync pass. A port of
/// `src/test/syncDevice.ts`.
///
/// Its notes, its pictures, its recordings and its versions files in maps behind the two stores the pass is given,
/// what it remembers of the account, and a [SyncDevice.sync] that runs one pass. [SyncDevice.clock] is the device's
/// time, for the waits the pass keeps (a picture not asked for again for a while); a test moves it by hand.
/// [SyncDevice.fetcher] stands between this device and the service, for a test that has another device write at a
/// moment of its choosing - between this one's pull and its push, say.
///
/// What differs: [DeviceNotes] and [DeviceFiles] are the pass's own `LocalNotes` and `LocalFiles`
/// (lib/sync/notes.dart), with [FileKind] and [FileDigest] from there. What the device remembers of the account is
/// still a type parameter, [S] (`SyncState` for the notes' pass), and [SyncDevice.sync] still takes the pass as a
/// function of the device, where the web's calls `syncNotes` itself: test/sync/support.dart has the one line that
/// does. [DeviceFiles.tapeReads] counts how often a recording was read, where the web's tests wrap the map's `get`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/sync/notes.dart' show FileDigest, FileKind, LocalFiles, LocalNotes;

import 'fake_service.dart';

export 'package:ghost_md/sync/notes.dart' show FileDigest, FileKind, RecordingDigest;

/// This device's notes (`LocalNotes`).
class DeviceNotes implements LocalNotes {
  /// By id.
  final Map<String, Note> held = {};

  @override
  Future<List<Note>> list() async => held.values.toList();
  @override
  Future<Note?> get(String id) async => held[id];
  @override
  Future<Note> apply(Note note) async => held[note.id] = note;
  @override
  Future<void> remove(String id) async => held.remove(id);
}

/// This device's recordings and versions files (by note id) and pictures (by name) (`LocalFiles`).
class DeviceFiles implements LocalFiles {
  DeviceFiles({Map<String, Uint8List> pictures = const {}, this.digest}) : pictures = {...pictures};

  /// Pictures by name.
  final Map<String, Uint8List> pictures;

  /// Recordings by note id.
  final Map<String, Uint8List> tapes = {};

  /// Files notes link, by name, and the words read in a picture or a file, by `image/<name>` or `file/<name>`.
  final Map<String, Uint8List> attachments = {};
  final Map<String, Uint8List> texts = {};

  /// Versions files by note id, as text, and the notes whose file changed here since it was sent.
  final Map<String, String> versions = {};
  final Set<String> owing = {};

  /// A recording's fingerprint made without reading the file, where the test gives one; null where this device
  /// cannot say, and the pass reads and hashes the file itself (the web's `digest?`, left out).
  @override
  final FileDigest? digest;

  /// How many times a recording was read.
  int tapeReads = 0;

  @override
  Future<Uint8List?> read(FileKind kind, String name) async {
    if (kind == FileKind.versions) {
      final text = versions[name];
      return text == null ? null : utf8.encode(text);
    }
    if (kind == FileKind.recording) tapeReads += 1;
    if (kind == FileKind.attachment) attachmentReads += 1;
    return _mapOf(kind)[name];
  }

  Map<String, Uint8List> _mapOf(FileKind kind) => switch (kind) {
        FileKind.image => pictures,
        FileKind.attachment => attachments,
        FileKind.text => texts,
        _ => tapes,
      };

  @override
  Future<void> write(FileKind kind, String name, Uint8List bytes) async {
    if (kind == FileKind.versions) {
      versions[name] = utf8.decode(bytes);
    } else {
      _mapOf(kind)[name] = bytes;
    }
  }

  /// How many times a file a note links was read whole.
  int attachmentReads = 0;

  @override
  Future<int?> lengthOf(FileKind kind, String name) async {
    if (kind == FileKind.versions) return versions[name]?.length;
    return _mapOf(kind)[name]?.length;
  }

  /// The notes whose versions file changed here since it was last sent.
  @override
  List<String> owed() => owing.toList();

  /// Note [name]'s versions file is with the account now.
  @override
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
