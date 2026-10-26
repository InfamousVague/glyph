// What the team notes' tests share: the Mac's core for the REAL CRDT (tool/build-native.sh host), and a member's
// device with its notes, files, documents and state in maps (the `device()` of the web's core/team/sync.test.ts).
import 'dart:io';
import 'dart:typed_data';

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_folders.dart' show folderFor;
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/sync/engine.dart' show TeamOutcome;
import 'package:ghost_md/sync/notes.dart' show LocalFiles, LocalNotes;
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';
import 'package:ghost_md/team/folders.dart';
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
///
/// Made with [folders], the device has the organization's workspace and folders in a [WorkspaceStore] instead of
/// the set (GHST-107): a note filed there has its path moved as the app's `NoteFolders` would move its file, at
/// once, and the pass is handed the store's [OrgFolders]. The organization is called Ghost, as the tests make it.
class TeamDevice {
  TeamDevice({required this.crdt, required this.api, required this.crypto, required this.token, required this.orgId, required this.orgKey, TeamDocStore? store, bool folders = false})
      : docs = TeamDocs(crdt: crdt, store: store ?? MemoryDocs()),
        _folders = folders;

  final Crdt crdt;
  final Api api;
  final AccountCrypto crypto;
  final String Function() token;
  final String orgId;
  final SealKey orgKey;

  final DeviceNotes local = DeviceNotes();
  final DeviceFiles files = DeviceFiles();
  final Set<String> filed = {};
  final bool _folders;

  /// The organization's workspace and folders, on a device made with folders; null on one without.
  late final WorkspaceStore? workspaces = _folders ? (WorkspaceStore(onFiled: _refile)..ensureOrgWorkspace(OrgLike(id: orgId, name: 'Ghost'))) : null;

  /// The organization's own workspace's id.
  String get root => orgWorkspaceId(orgId);
  TeamDocs docs;
  TeamSyncState state = emptyTeamState();
  int clock = 1000;

  Map<String, Note> get notes => local.held;
  Map<String, Uint8List> get pictures => files.pictures;
  Map<String, String> get versions => files.versions;
  Set<String> get owed => files.owing;

  /// A note on this device, filed in the organization's workspace, or with folders in [into] (a workspace id).
  void put(String id, String body, {bool starred = false, int? archivedAt, String? into}) {
    final spaces = workspaces;
    notes[id] = Note(id: id, body: body, createdAt: clock, updatedAt: clock, starred: starred, archivedAt: archivedAt, path: spaces == null ? null : 'orgs/Ghost/$id.md');
    if (spaces == null) {
      filed.add(id);
    } else {
      spaces.fileNote(id, into ?? root);
    }
  }

  /// The notes' paths moved to the folder their workspace names, as lib/core/note_folders.dart moves their files:
  /// into `<folder>/<file name>`, unless already in that folder.
  void _refile(List<String> ids, Workspace? workspace) {
    final folder = folderFor(workspace, workspaces!.value.list);
    if (folder == null) return;
    for (final id in ids) {
      final note = notes[id];
      if (note == null) continue;
      final from = note.path ?? '$id.md';
      final path = '$folder/${from.substring(from.lastIndexOf('/') + 1)}';
      if (path != from) notes[id] = note.copyWith(path: () => path);
    }
  }

  /// Notes filed in a personal workspace on a device with no [workspaces]: out of the organization, by evidence.
  final Set<String> personal = <String>{};

  /// Whether a note still here has left the team, as the engine says it (lib/sync/engine.dart `leftTeam`): filed in a
  /// workspace this device knows outside the organization; never because it is unfiled or its folder is unknown.
  bool leftTeam(String id) {
    final spaces = workspaces;
    if (spaces == null) return personal.contains(id);
    final space = spaces.workspaceOf(id);
    return space != null && spaces.orgOf(space.id) != orgId;
  }

  /// Whether a note is the team's: filed in the organization's workspace or a folder under it.
  bool isTeamNote(String id) {
    final spaces = workspaces;
    if (spaces == null) return filed.contains(id);
    final space = spaces.workspaceOf(id);
    return space != null && spaces.orgOf(space.id) == orgId;
  }

  /// A note from the team filed in the organization's workspace.
  void file(String id) {
    final spaces = workspaces;
    if (spaces == null) {
      filed.add(id);
    } else {
      spaces.fileNote(id, root);
    }
  }

  /// The channel's folders, on a device with them.
  TeamFolders? get folders => workspaces == null ? null : OrgFolders(workspaces!, orgId);

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
        isTeamNote: isTeamNote,
        leftTeam: leftTeam,
        file: file,
        folders: folders,
        generation: generation,
        olderKey: olderKey,
        meetings: () => meetings,
        syncMeetingRecordings: () => syncMeetingRecordings,
      );

  /// Which of this device's notes are meetings, and the person's Sync meeting recordings (on, as the app's default).
  Map<String, num> meetings = const {};
  bool syncMeetingRecordings = true;

  /// A recording on note [id]: its tape on this device, and its length on the note.
  void tape(String id, Uint8List bytes, {required int ms}) {
    final was = notes[id]!;
    notes[id] = Note(id: id, body: was.body, createdAt: was.createdAt, updatedAt: clock, starred: was.starred, archivedAt: was.archivedAt, recordingMs: ms, path: was.path);
    files.tapes[id] = bytes;
  }

  Map<String, Uint8List> get tapes => files.tapes;

  Future<TeamOutcome> sync({SealKey? key, int? generation, Future<SealKey?> Function(int generation)? olderKey, Api? through}) =>
      syncTeamNotes(context(key: key, generation: generation, olderKey: olderKey, through: through));
}
