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
String? folderFor(Workspace? workspace) {
  if (workspace == null) return inboxFolder;
  final folder = folderName(workspace.name);
  return folder.isEmpty ? null : '${isOrgWorkspace(workspace.id) ? orgsFolder : workspacesFolder}/$folder';
}

/// The file's own name, without the folders: `workspaces/Home/Weekend trip.md` is `Weekend trip.md`.
String _fileName(String path) {
  final at = path.lastIndexOf('/');
  return at < 0 ? path : path.substring(at + 1);
}

/// Moves notes' files to where their workspaces say (`fileNoteInFolder`, `fileNotesInFolder`).
class NoteFolders {
  NoteFolders(this.library, {void Function(String message)? log}) : _log = log ?? debugPrint;

  final NoteLibrary library;
  final void Function(String message) _log;

  /// The moves asked for, one after another, so two filings of the same note land in the order they were made.
  Future<void> _moves = Future<void>.value();

  /// Moves one note's file into the folder its workspace names, if it is not there already.
  ///
  /// Quiet about everything it cannot do: a note with no file yet (a draft), a name that cleans away to nothing, or
  /// a library that refuses the move. The note's words are never touched, only where the file sits.
  Future<void> fileNoteInFolder(String noteId, Workspace? workspace) async {
    final folder = folderFor(workspace);
    if (folder != null) await _fileNoteAt(noteId, folder);
  }

  Future<void> _fileNoteAt(String noteId, String folder) async {
    try {
      final note = await library.get(noteId);
      final from = note?.path;
      if (note == null || from == null || from.isEmpty) return;
      // Already under that folder, at any depth, stays where it is: an import keeps a vault's own folders inside
      // its workspace's (lib/importer/import_paths.dart), and filing its notes must not flatten them.
      if (from.startsWith('$folder/')) return;
      final path = '$folder/${_fileName(from)}';
      if (path == from) return;
      await library.apply(note.copyWith(path: () => path));
    } catch (failure) {
      _log('[glyph] the note stayed where it was: $failure');
    }
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
