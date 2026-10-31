/// A note's workspace decides which folder holds its file. A port of `src/app/core/noteFolders.ts`.
///
/// Matt: "Setting a workspace should dictate the folder the note is saved in on disk
/// (`workspaces/<workspace_name>/<note>.md`)". A new note is written into `Inbox/`, named after its title. Filing it in
/// a workspace moves that file into `workspaces/<the workspace>/`, and taking it out of one moves it back to
/// `Inbox/`, so the folders a person sees in Obsidian or a file manager say what the pills in the app say. An
/// organization's workspace files under `orgs/<the organization>/` instead: its name is another account's choice,
/// and a personal workspace may be called the same.
///
/// The move is the library's own: `store_apply` takes a note carrying the path it should have, and the Rust side
/// renames the file and re-indexes it (library/mod.rs `apply_note`). So this asks for a path and nothing here
/// touches the disk. The note handed back is always the one `get_note` just answered, whole, never the list's:
/// `store_apply` writes what is kept beside the note too, and the list's copy has none of it (docs/STAGE3.md).
///
/// What differs: the web's functions are module functions over `core/store.ts`; here they are [NoteFolders] over a
/// [NoteLibrary], whose [NoteFolders.fileNotesInFolder] is what a [WorkspaceStore] is given as its `onFiled`. Where
/// the web asks `isTauri()`, a library whose notes have no path (the invented one in memory) is the browser's case:
/// nothing happens. The list is read again by the library's own write, where the web announces the change.
library;

import 'package:flutter/foundation.dart';

import 'library.dart';
import 'note.dart' show livePathOf, trashedPathOf;
import 'workspaces.dart';

/// Where notes with no workspace live: the library's own landing folder (library/mod.rs `INBOX`).
const String inboxFolder = 'Inbox';

/// The folder the workspaces' folders sit in, as Matt asked for it.
const String workspacesFolder = 'workspaces';

/// The folder the organizations' workspaces' folders sit in.
const String orgsFolder = 'orgs';

final RegExp _unholdable = RegExp(r'[/\\:*?"<>|]');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _ends = RegExp(r'^[.\s]+|[.\s]+$');

/// A workspace's name as a folder name: what a file name may not hold is dropped, and the ends are trimmed
/// (`folderName`).
String folderName(String name) {
  final clean = name.replaceAll(_unholdable, '').replaceAll(_spaces, ' ').replaceAll(_ends, '');
  return (clean.length > 60 ? clean.substring(0, 60) : clean).trim();
}

/// The folder a note belongs in: its workspace's, or the inbox with no workspace. Null when the name is unusable
/// (`folderFor`). The folder is decided from the workspace, not from a name, so no caller can file an
/// organization's note under `workspaces/`.
///
/// A workspace inside another ([Workspace.parent]) is a folder inside its parent's, as deep as they go:
/// `workspaces/Work/Clients/`, or under an organization's, `orgs/Ghost.md/Clients/` (GHST-107: the same on every
/// member's device, since the organization's folder is named after it and a folder after its workspace, so the
/// path a team note's row carries files it the same everywhere). [all] is every workspace, for the parents' names;
/// without it, or where a parent's name cleans away to nothing, the workspace's folder is at the top, as before
/// folders were nested.
String? folderFor(Workspace? workspace, [List<Workspace> all = const []]) {
  if (workspace == null) return inboxFolder;
  final folder = folderName(workspace.name);
  if (folder.isEmpty) return null;
  if (isOrgWorkspace(workspace.id)) return '$orgsFolder/$folder';
  final path = all.isEmpty || workspace.parent == null ? [workspace] : workspacePath(all, workspace.id);
  final names = [for (final each in path.isEmpty ? [workspace] : path) folderName(each.name)];
  if (names.any((name) => name.isEmpty)) return '$workspacesFolder/$folder';
  final top = path.isEmpty ? workspace : path.first;
  return '${isOrgWorkspace(top.id) ? orgsFolder : workspacesFolder}/${names.join('/')}';
}

/// The folders a team note's path names inside its organization's, in order, as the folder workspaces to file it
/// under (GHST-107): `orgs/Ghost.md/Clients/Acme/Plan.md` is `['Clients', 'Acme']`. Empty for a note at the
/// organization's own folder, for one whose path is not under `orgs/` at all, and for no path.
List<String> orgFolderNames(String? path) {
  if (path == null) return const [];
  // A member's trashed copy is still filed where it was: its row never carries the `.trash/` (lib/team/sync.dart),
  // and one that did is read as the path under it.
  final parts = livePathOf(path)!.split('/');
  if (parts.length < 4 || parts.first != orgsFolder) return const [];
  return [for (final part in parts.sublist(2, parts.length - 1)) if (part.isNotEmpty) part];
}

/// The file's own name, without the folders: `workspaces/Home/Weekend trip.md` is `Weekend trip.md`.
String _fileName(String path) {
  final at = path.lastIndexOf('/');
  return at < 0 ? path : path.substring(at + 1);
}

/// Moves notes' files to where their workspaces say (`fileNoteInFolder`, `fileNotesInFolder`).
class NoteFolders {
  NoteFolders(this.library, {void Function(String message)? log, this.workspaces}) : _log = log ?? debugPrint;

  final NoteLibrary library;
  final void Function(String message) _log;

  /// Every workspace as it is now, for the folders a nested one sits inside ([folderFor]); left out, each folder is
  /// at the top.
  final List<Workspace> Function()? workspaces;

  /// The moves asked for, one after another, so two filings of the same note land in the order they were made.
  Future<void> _moves = Future<void>.value();

  /// Moves one note's file into the folder its workspace names, if it is not there already.
  ///
  /// Quiet about everything it cannot do: a note with no file yet (a draft), a name that cleans away to nothing, or
  /// a library that refuses the move. The note's words are never touched, only where the file sits.
  Future<void> fileNoteInFolder(String noteId, Workspace? workspace) async {
    final all = workspaces?.call() ?? const <Workspace>[];
    final folder = folderFor(workspace, all);
    if (folder != null) await _fileNoteAt(noteId, folder, all);
  }

  Future<void> _fileNoteAt(String noteId, String folder, List<Workspace> all) async {
    try {
      final note = await library.get(noteId);
      final from = note?.path;
      if (note == null || from == null || from.isEmpty) return;
      // Judged by where it is, or was before the trash: `.trash/workspaces/Work/Plan.md` is in `workspaces/Work`.
      final at = livePathOf(from)!;
      final dir = at.contains('/') ? at.substring(0, at.lastIndexOf('/')) : '';
      if (dir == folder) return;
      // Under that folder in a folder of the vault's own stays where it is: an import keeps a vault's folders inside
      // its workspace's (lib/importer/import_paths.dart), and filing its notes must not flatten them. Under it in
      // another workspace's folder, it moves: a note filed up out of a folder inside its workspace's (2026-10-19,
      // GHST-107: left there, the other members would still see it in the folder, since its path is its folder).
      if (dir.startsWith('$folder/') && !_inAnotherWorkspaceFolder(dir, folder, all)) return;
      // A note in the trash keeps its filing (its folder is where Restore puts it back), so its file is filed inside
      // the trash, `.trash/<folder>/`, never pulled out of it by a folder renamed or moved (library/trash.rs).
      final path = note.inTrash ? trashedPathOf('$folder/${_fileName(from)}') : '$folder/${_fileName(from)}';
      if (path == from) return;
      await library.apply(note.copyWith(path: () => path));
    } catch (failure) {
      _log('[glyph] the note stayed where it was: $failure');
    }
  }

  /// Whether [dir] is, or is inside, the folder of a workspace other than the one whose folder is [folder].
  static bool _inAnotherWorkspaceFolder(String dir, String folder, List<Workspace> all) {
    for (final w in all) {
      final each = folderFor(w, all);
      if (each == null || each == folder) continue;
      if (dir == each || dir.startsWith('$each/')) return true;
    }
    return false;
  }

  /// The same for several notes at once: a workspace renamed, or taken away. What a [WorkspaceStore] is given as its
  /// `onFiled`; the future is there for whoever would wait, and the store does not.
  Future<void> fileNotesInFolder(List<String> noteIds, Workspace? workspace) {
    final ids = [...noteIds];
    return _moves = _moves.then((_) async {
      for (final id in ids) {
        await fileNoteInFolder(id, workspace);
      }
    });
  }
}
