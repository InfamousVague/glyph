/// An organization's folders on this device, as the team's channel files into them and tidies them (GHST-107,
/// 2026-10-19). The port's own: the web had no folders inside an organization's workspace.
///
/// A folder of an organization's is shared by every member, and no service knows of it: a note's folder is its
/// file's path (`orgs/Ghost.md/Clients/Acme/Plan.md`), which rides inside the sealed team note and which the
/// library writes as it is when the row lands (lib/team/sync.dart `_takeRow`, library/mod.rs `apply_note`). So a
/// note from the team is filed here by its path: the folders between `orgs/<the organization>/` and the file name
/// are the folder workspaces to find, by name, under the organization's workspace and then under each in turn, or
/// to make; the note is filed in the deepest ([TeamFolders.fileAt]). Renaming or moving a folder on one device
/// moves its files, which changes their paths, which puts their rows again, and every other member's device files
/// them the same way on its next pass.
///
/// What a pass empties, it drops ([TeamFolders.prune]): a folder that held a note as the pass began and holds none
/// at its end, named by no team note's path, was renamed, moved or deleted by another member, and would otherwise
/// stand empty here for good. A folder empty before the pass is not touched: one just made here, with nothing filed
/// in it yet, or one made on another of this account's devices and landed through the preferences, or one the
/// person emptied on purpose. (A pass cut short after its rows moved a folder's notes out can leave that folder
/// standing; the person deletes it by hand, as any empty folder.) What a folder holds is read against the notes on
/// the device, not the filings alone: a note a pull took away leaves its filing behind until the page hears of it.
///
/// [TeamFolders] is what the channel is handed (lib/sync/engine.dart `TeamPass.folders`, beside `file` for a note
/// at the organization's own folder); [OrgFolders] is the app's, over the [WorkspaceStore]. A test's device gives
/// its own.
library;

import '../core/note.dart';
import '../core/note_folders.dart';
import '../core/workspaces.dart';

/// What the channel asks of an organization's folders on this device.
abstract class TeamFolders {
  /// Files a note from the team in the folder [folderNames] say, under the organization's workspace, each found by
  /// name or made: `['Clients', 'Acme']` for a note at `orgs/Ghost.md/Clients/Acme/Plan.md`.
  void fileAt(String noteId, List<String> folderNames);

  /// The organization's folders that hold one of [notes] now, in them or under them: taken as a pass begins, with
  /// the notes on the device then, for [prune] at its end.
  Set<String> filled(Iterable<Note> notes);

  /// Drops the folders of [had] that hold none of [notes] any more and that none of their paths names; [notes] are
  /// the device's at the pass's end.
  void prune(Set<String> had, Iterable<Note> notes);
}

/// The app's [TeamFolders], over the workspaces.
class OrgFolders implements TeamFolders {
  OrgFolders(this.workspaces, this.orgId);

  final WorkspaceStore workspaces;
  final String orgId;

  String get _root => orgWorkspaceId(orgId);

  /// The organization's folders, the ones under its workspace however deep, deepest last.
  List<Workspace> _folders() {
    final list = workspaces.value.list;
    final byId = {for (final w in list) w.id: w};
    return [for (final id in workspaceFamily(list, _root)) if (id != _root && byId[id] != null) byId[id]!];
  }

  /// The folder called [name] inside [parent]: the one whose folder on disk is named that, so a name the file
  /// system could not hold matches the folder it was cleaned to. One named that in another case is renamed to the
  /// path's: left as it is, its own notes' files would be moved to its case and put again, and the member who
  /// named it the other way would move them back, without end.
  Workspace? _find(String parent, String name) {
    final inside = workspaces.childrenOf(parent);
    for (final w in inside) {
      if (folderName(w.name) == name) return w;
    }
    final wanted = name.toLowerCase();
    for (final w in inside) {
      if (folderName(w.name).toLowerCase() != wanted) continue;
      workspaces.renameWorkspace(w.id, name);
      return workspaces.value.list.where((each) => each.id == w.id).firstOrNull;
    }
    return null;
  }

  @override
  void fileAt(String noteId, List<String> folderNames) {
    if (!workspaces.value.list.any((w) => w.id == _root)) return;
    var at = _root;
    for (final name in folderNames) {
      final found = _find(at, name) ?? workspaces.addWorkspace(name, 'ink', at);
      // A name that cleans away to nothing makes no folder: the note is filed as deep as the names go.
      if (found == null || found.parent != at) break;
      at = found.id;
    }
    workspaces.fileNote(noteId, at);
  }

  /// Whether one of [ids] is filed in the folder, or under it.
  bool _holds(Workspace folder, Set<String> ids) => workspaces.notesUnder(folder.id).any(ids.contains);

  @override
  Set<String> filled(Iterable<Note> notes) {
    final ids = {for (final note in notes) note.id};
    return {for (final w in _folders()) if (_holds(w, ids)) w.id};
  }

  @override
  void prune(Set<String> had, Iterable<Note> notes) {
    if (had.isEmpty) return;
    final ids = {for (final note in notes) note.id};
    final paths = [for (final note in notes) ?note.path];
    // Deepest first, so a folder goes before the one it is in, which is then empty itself.
    for (final folder in _folders().reversed) {
      if (!had.contains(folder.id) || _holds(folder, ids)) continue;
      final disk = folderFor(folder, workspaces.value.list);
      if (disk != null && paths.any((path) => path.startsWith('$disk/'))) continue;
      workspaces.removeWorkspace(folder.id);
    }
  }
}
