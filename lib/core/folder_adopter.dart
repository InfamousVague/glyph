/// Folders restored from the directory tree (docs/MARKDOWN_FIRST.md §5, gap 2). The port's own, 2026-10-31.
///
/// A note filed in a personal folder has its file at `workspaces/<A>/<B>/<Title>.md` (lib/core/note_folders.dart),
/// and a team note at `orgs/<Org>/<A>/<Title>.md`; but until now nothing read a personal folder back from a path.
/// The folders and the filings lived in the synced preferences alone, so a Library folder cloned onto a fresh device
/// opened with no folders and every note unfiled, its files still sitting in `workspaces/Work/`.
///
/// [adoptFolders] is the adopter that runs as the library is opened (lib/root/ghost_root.dart `_open`): for every
/// note the preferences have no filing for, the folders its path names are found by the name their directory is
/// given, or made (with the id their place gives them, lib/core/workspaces.dart `folderIdFor`, so two devices
/// restoring the same tree make the same folders), nested as the path nests them, and the note is filed in the
/// deepest. A team note's path is read the same way once its organization is known: `orgs/<Org>/` is matched to the
/// committed config's `orgs` section (lib/core/library_config.dart), else to an organization's workspace whose
/// folder is named that; before sign-in it is left for the next open.
///
/// Nothing is deleted, unfiled or moved by this. A note the preferences already file is left as they say, so a
/// filing another device made and synced here is never undone by a path that lagged it; a path that names no folder
/// (`Inbox/`, a draft with no file) files nothing. The files are not touched: filing a note where its path already
/// is asks the library for no move (note_folders.dart `_fileNoteAt` sees the folder is the same).
///
/// The trash: a note found in the files with no trash entry is live, which is what it is today (the trash is a
/// preference, lib/core/kept_trash.dart). Matt chose a `.trash/` folder for it (docs/MARKDOWN_FIRST.md §11, 2026-10-31:
/// trashing moves the file to `Library/.trash/<its path>`, as Obsidian does). A dot folder is never indexed, so once
/// that is built a trashed note is not among the notes this is handed at all; were one ever listed, its path's first
/// part would be [trashFolder], and that is where it would be put in the trash instead of filed.
library;

import 'package:flutter/foundation.dart';

import '../team/folders.dart' show OrgFolders;
import 'note.dart';
import 'note_folders.dart';
import 'workspaces.dart';

/// The folder a trashed note's file will sit under once the library moves it there (`Library/.trash/<its path>`,
/// §11). Read by nothing yet: the seam for the trash on disk.
const String trashFolder = '.trash';

/// What one pass of the adopter did.
@immutable
class FolderAdoption {
  const FolderAdoption({this.folders = 0, this.filed = 0, this.waiting = 0});

  /// Folders made.
  final int folders;

  /// Notes filed from their paths.
  final int filed;

  /// Team notes left for later: their organization is not known here yet.
  final int waiting;

  bool get isEmpty => folders == 0 && filed == 0;

  @override
  String toString() => 'FolderAdoption(folders: $folders, filed: $filed, waiting: $waiting)';
}

/// Files every unfiled note of [notes] where its path says, making the folders on the way (see the header).
/// [orgFolders] is the config's `orgs` section as folder to organization id (`orgs/Acme` to the id), for team notes
/// whose organization's workspace is not here under that name.
FolderAdoption adoptFolders(WorkspaceStore workspaces, Iterable<Note> notes, {Map<String, String> orgFolders = const {}}) {
  var made = 0, filed = 0, waiting = 0;
  // Grouped by the folder they go in, so each folder's notes are filed with one write of the sheet (`fileNotes`).
  final personal = <String, List<String>>{};
  final team = <String, List<(String, List<String>)>>{};
  for (final note in notes) {
    final path = note.path;
    if (path == null) continue;
    final parts = path.split('/');
    if (parts.length < 3) continue;
    final names = [for (final part in parts.sublist(1, parts.length - 1)) if (part.isNotEmpty) part];
    final unfiled = workspaces.workspaceOf(note.id) == null;
    if (parts.first == workspacesFolder) {
      // The folders are made for every path, filed or not: a directory is a folder whether or not the preferences
      // know where its notes go. The note is filed only where they do not.
      final (folder, added) = _personalFolderAt(workspaces, names);
      made += added;
      if (folder != null && unfiled) (personal[folder] ??= []).add(note.id);
    } else if (!unfiled) {
      continue;
    } else if (parts.first == orgsFolder && names.isNotEmpty) {
      final org = _orgFor(workspaces, names.first, orgFolders);
      if (org == null) {
        waiting += 1;
        continue;
      }
      (team[org] ??= []).add((note.id, orgFolderNames(path)));
    }
  }
  for (final entry in personal.entries) {
    workspaces.fileNotes(entry.value, entry.key);
    filed += entry.value.length;
  }
  for (final entry in team.entries) {
    final before = workspaces.value.list.length;
    final folders = OrgFolders(workspaces, entry.key);
    for (final (id, names) in entry.value) {
      folders.fileAt(id, names);
      filed += 1;
    }
    made += workspaces.value.list.length - before;
  }
  return FolderAdoption(folders: made, filed: filed, waiting: waiting);
}

/// The personal folder at [names] from the top, each found by the name its directory is given or made inside the
/// one before; its id, and how many were made. Null where a name cleans away to nothing, or where a folder of that
/// name is not where the path says (`addWorkspace` with no parent answers the personal one already called that,
/// wherever it is, as it has since before folders were nested).
(String?, int) _personalFolderAt(WorkspaceStore workspaces, List<String> names) {
  String? at;
  var made = 0;
  for (final name in names) {
    var found = _find(workspaces, at, name);
    if (found == null) {
      final before = workspaces.value.list.length;
      found = workspaces.addWorkspace(name, 'ink', at);
      if (workspaces.value.list.length > before) made += 1;
    }
    if (found == null || found.parent != at) return (null, made);
    at = found.id;
  }
  return (at, made);
}

/// The folder called [name] inside [parent] (null, the top): the one whose directory is named that, in any case,
/// as the team's channel finds an organization's folders (lib/team/folders.dart `_find`). A personal folder only:
/// an organization's own workspace, or a folder in one, is never a personal path's.
Workspace? _find(WorkspaceStore workspaces, String? parent, String name) {
  final wanted = name.toLowerCase();
  for (final w in workspaces.childrenOf(parent)) {
    if (isOrgWorkspace(w.id) || (parent == null && workspaces.orgOf(w.id) != null)) continue;
    if (folderName(w.name) == name) return w;
  }
  for (final w in workspaces.childrenOf(parent)) {
    if (isOrgWorkspace(w.id) || (parent == null && workspaces.orgOf(w.id) != null)) continue;
    if (folderName(w.name).toLowerCase() == wanted) return w;
  }
  return null;
}

/// The organization whose folder is `orgs/<folder>`: the config's word first, then the organization's workspace
/// whose folder on disk is named that; null until the organization is known here.
String? _orgFor(WorkspaceStore workspaces, String folder, Map<String, String> orgFolders) {
  final said = orgFolders['$orgsFolder/$folder'];
  if (said != null && workspaces.value.list.any((w) => w.id == orgWorkspaceId(said))) return said;
  final wanted = folder.toLowerCase();
  for (final w in workspaces.value.list) {
    final org = orgIdOf(w.id);
    if (org != null && folderName(w.name).toLowerCase() == wanted) return org;
  }
  return null;
}
