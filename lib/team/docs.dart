/// Where a device keeps a team note's document (docs/SHARED.md, S5): the CRDT's state, how far along the note's log
/// on the service it has read ([TeamDocRecord.seq]), the seq its last snapshot covered, and the updates made here
/// that the service has not been given yet. A port of `src/app/core/team/docs.ts`.
///
/// What differs:
/// - The page keeps them in IndexedDB (`glyph-team`); here they are **files in the app's data folder**
///   ([FileDocs]), one a note, as JSON with the bytes in base64url. NOT in the library folder: a document is this
///   device's bookkeeping, not a note, and the backup of the library has no use for it. A document lost with the
///   folder is read again from the organization's row on the next pass, nothing of the team's lost with it; only
///   words typed here and never sent would be, and those are still in the note.
/// - A file is written whole or not at all (a file beside it, then a rename), and one that cannot be read is no
///   document, never a throw: the pass adopts the row again.
/// - [MemoryDocs] is `memoryDocs()`: the tests', and a device with nowhere to write.
library;

import 'dart:convert';
import 'dart:io' hide Platform;
import 'dart:typed_data';

import '../core/bytes.dart';
import '../core/host_platform.dart';

/// One note's document as kept (`TeamDocRecord`).
class TeamDocRecord {
  const TeamDocRecord({required this.state, required this.seq, required this.snapshotSeq, this.pending = const []});

  /// What [toJson] wrote, or null for anything else.
  static TeamDocRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final state = raw['state'], seq = raw['seq'], snapshotSeq = raw['snapshotSeq'], pending = raw['pending'];
    if (state is! String || seq is! num || snapshotSeq is! num) return null;
    try {
      return TeamDocRecord(
        state: fromBase64Url(state),
        seq: seq.toInt(),
        snapshotSeq: snapshotSeq.toInt(),
        pending: [
          if (pending is List)
            for (final update in pending)
              if (update is String) fromBase64Url(update),
        ],
      );
    } on FormatException {
      return null;
    }
  }

  /// The document as `Y.encodeStateAsUpdate` gives it.
  final Uint8List state;

  /// The last seq of the note's log applied here.
  final int seq;

  /// The seq the organization's row for this note covered when this device last put or read it.
  final int snapshotSeq;

  /// Updates made here, in order, not yet posted to the log.
  final List<Uint8List> pending;

  Map<String, Object?> toJson() => {
        'v': 1,
        'state': toBase64Url(state),
        'seq': seq,
        'snapshotSeq': snapshotSeq,
        'pending': [for (final update in pending) toBase64Url(update)],
      };
}

/// Where the documents are kept (`TeamDocStore`).
abstract interface class TeamDocStore {
  Future<TeamDocRecord?> read(String noteId);
  Future<void> write(String noteId, TeamDocRecord record);
  Future<void> remove(String noteId);
}

/// The same, in memory (`memoryDocs`): for tests, and for a device with nowhere to write.
class MemoryDocs implements TeamDocStore {
  /// By note id.
  final Map<String, TeamDocRecord> held = {};

  @override
  Future<TeamDocRecord?> read(String noteId) async => held[noteId];

  @override
  Future<void> write(String noteId, TeamDocRecord record) async => held[noteId] = record;

  @override
  Future<void> remove(String noteId) async => held.remove(noteId);
}

final RegExp _plainId = RegExp(r'^[A-Za-z0-9_-]{1,62}$');

/// The documents as files in [folder], `<note id>.json` each (`deviceDocs`). [forAccount] names the folder the app
/// gives one account's: `<data>/team/<account id>`, so signing in as somebody else never reads another's.
class FileDocs implements TeamDocStore {
  FileDocs(this.folder);

  /// `<dataDir>/team/<accountId>`: beside the library, never in it.
  factory FileDocs.forAccount(String dataDir, int accountId) => FileDocs(Directory('$dataDir${Platform.pathSeparator}team${Platform.pathSeparator}$accountId'));

  final Directory folder;

  /// Every account's documents on this device, gone (`<dataDir>/team`): a reset's, with the notes they are the
  /// documents of. The page kept them in the WebView's own database, which its reset left; here they are files
  /// beside the library, and a reset that left them left every team note's words on the phone.
  static Future<void> forgetAll(String dataDir) async {
    final all = Directory('$dataDir${Platform.pathSeparator}team');
    if (await all.exists()) await all.delete(recursive: true);
  }

  /// A note id is the service's own shape, which is a safe file name; anything else is no document.
  File? _file(String noteId) => _plainId.hasMatch(noteId) ? File('${folder.path}${Platform.pathSeparator}$noteId.json') : null;

  @override
  Future<TeamDocRecord?> read(String noteId) async {
    final file = _file(noteId);
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      return TeamDocRecord.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      // Cut short, or not ours: no document, and the row is adopted again.
      return null;
    }
  }

  @override
  Future<void> write(String noteId, TeamDocRecord record) async {
    final file = _file(noteId);
    if (file == null) return;
    await folder.create(recursive: true);
    final beside = File('${file.path}.new');
    await beside.writeAsString(jsonEncode(record.toJson()), flush: true);
    await beside.rename(file.path);
  }

  @override
  Future<void> remove(String noteId) async {
    final file = _file(noteId);
    if (file == null) return;
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  /// Every document of this account's, gone: signing out.
  Future<void> clear() async {
    try {
      await folder.delete(recursive: true);
    } on FileSystemException {
      // Never made.
    }
  }
}
