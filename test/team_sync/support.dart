// What the team notes' tests share: the Mac's core for the REAL CRDT (tool/build-native.sh host), and a member's
// device with its notes, files, documents and state in maps (the `device()` of the web's core/team/sync.test.ts).
import 'dart:io';
import 'dart:typed_data';

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/sync/engine.dart' show TeamOutcome;
import 'package:ghost_md/sync/notes.dart' show LocalFiles, LocalNotes;
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';
import 'package:ghost_md/team/sync.dart';

import '../support/sync_device.dart';

export 'package:ghost_md/sync/engine.dart' show TeamOutcome;
export '../support/sync_device.dart' show DeviceFiles, DeviceNotes;

/// The Mac's build of the core, which a test opens for its CRDT and, where it asks, its crypto.
const String coreLibrary = 'native/target/debug/libghost_core.dylib';

bool get coreBuilt => File(coreLibrary).existsSync();

/// Why a test that needs the core is skipped, or null when it is there.
String? get coreSkip => coreBuilt ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $coreLibrary)';

/// The core, opened. No `init`: a document and a key ask nothing of the library.
Future<GhostCore> openCore() => GhostCore.open(libraryPath: File(coreLibrary).absolute.path);

/// An outcome, as text two of them can be compared by.
String saidOutcome(TeamOutcome outcome) => 'changed ${outcome.changed}, sent ${outcome.sent}, unsent ${outcome.unsent}, reason ${outcome.reason}';

/// A device of a member: its notes and files in maps, which notes it has filed in the organization, and one pass.
class TeamDevice {
  TeamDevice({required this.crdt, required this.api, required this.crypto, required this.token, required this.orgId, required this.orgKey, TeamDocStore? store})
      : docs = TeamDocs(crdt: crdt, store: store ?? MemoryDocs());

  final Crdt crdt;
  final Api api;
  final AccountCrypto crypto;
  final String Function() token;
  final String orgId;
  final SealKey orgKey;

  final DeviceNotes local = DeviceNotes();
  final DeviceFiles files = DeviceFiles();
  final Set<String> filed = {};
  TeamDocs docs;
  TeamSyncState state = emptyTeamState();
  int clock = 1000;

  Map<String, Note> get notes => local.held;
  Map<String, Uint8List> get pictures => files.pictures;
  Map<String, String> get versions => files.versions;
  Set<String> get owed => files.owing;

  /// A note on this device, filed in the organization's workspace.
  void put(String id, String body, {bool starred = false, int? archivedAt}) {
    notes[id] = Note(id: id, body: body, createdAt: clock, updatedAt: clock, starred: starred, archivedAt: archivedAt);
    filed.add(id);
  }

  /// The note's words changed on this device, without the editor.
  void write(String id, String body) => notes[id] = notes[id]!.copyWith(body: body);

  /// The app closed and opened again: what was held in memory is gone, what was kept is read back.
  Future<void> reopened() async {
    final store = docs.store;
    await docs.forget();
    docs = TeamDocs(crdt: crdt, store: store);
  }

  /// The channel's context, under the key (and generation) given, or the organization's.
  TeamSyncContext context({SealKey? key, int? generation, Future<SealKey?> Function(int generation)? olderKey, Api? through, LocalNotes? notes, LocalFiles? files}) => TeamSyncContext(
        token: token(),
        orgId: orgId,
        key: key ?? orgKey,
        notes: notes ?? local,
        files: files ?? this.files,
        docs: docs,
        state: state,
        save: (next) => state = next,
        api: through ?? api,
        crypto: crypto,
        now: () => clock,
        isTeamNote: filed.contains,
        file: filed.add,
        generation: generation,
        olderKey: olderKey,
      );

  Future<TeamOutcome> sync({SealKey? key, int? generation, Future<SealKey?> Function(int generation)? olderKey, Api? through}) =>
      syncTeamNotes(context(key: key, generation: generation, olderKey: olderKey, through: through));
}
