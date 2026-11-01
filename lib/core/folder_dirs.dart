/// A deleted folder's directories taken off the disk once they are empty (Matt, 2026-11-01: "add ability to context
/// menu delete folders and items inside them"). Markdown first (docs/MARKDOWN_FIRST.md): a folder is a directory
/// under the library, `workspaces/Plans/` or `orgs/Ghost.md/Plans/`, so a folder deleted with its notes leaves no
/// empty directory behind for a file browser, Obsidian or a clone to show. The notes are gone from it by then: in the
/// library's `.trash/`, which keeps them under the path they had, or deleted (lib/notes/note_actions.dart
/// `deleteFolder`).
///
/// Only an empty directory goes: one with anything in it but the Mac's `.DS_Store` is left as it is, so a file
/// another app put there, or a note whose move into the trash has not landed, is never lost. A path with an empty,
/// a dot or a `..` part is never touched. Where Dart cannot reach the library (an Android SAF tree, the web) nothing
/// is done: the empty directory stays, as a folder emptied by hand always has.
library;

import 'dart:io';

import 'library_folder.dart' show LibraryStatus;

/// The library's root on disk for [status], as lib/core/library_config.dart `configFileFor` finds it: a chosen folder
/// that can be reached, else the app's own; null for an Android SAF tree and for a status that names no folder.
String? libraryRootOf(LibraryStatus status) {
  if (status.kind == 'tree') return null;
  final root = status.kind == 'folder' && status.reachable && status.path != null ? status.path : status.own;
  return root == null || root.isEmpty ? null : root;
}

/// Each of [folders] (library-relative, the deepest first) removed from under [root] where it is there and empty.
/// Answers how many went. Quiet about everything it cannot do.
Future<int> removeEmptyFolderDirs(String root, Iterable<String> folders) async {
  var gone = 0;
  for (final folder in folders) {
    final parts = folder.split('/');
    if (folder.isEmpty || parts.any((part) => part.isEmpty || part.startsWith('.'))) continue;
    final dir = Directory('$root/$folder');
    try {
      if (!await dir.exists()) continue;
      final inside = await dir.list(followLinks: false).toList();
      if (inside.any((each) => each.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull != '.DS_Store')) continue;
      for (final each in inside) {
        await each.delete();
      }
      await dir.delete();
      gone += 1;
    } catch (_) {
      // Taken by something else meanwhile, or not ours to remove: left as it is.
    }
  }
  return gone;
}
