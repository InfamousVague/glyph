/// Where an import puts each note, and what it calls the group it makes. Pure, so the rules are tests.
///
/// An import makes one workspace, "Imported from Obsidian 2026-10-16" (lib/importer/import_target.dart says why a
/// workspace and not a folder of its own), and its notes are filed there. A workspace is a folder on disk
/// (lib/core/note_folders.dart: `workspaces/<name>/`), so the notes are written under it from the start, and a
/// vault's own folders are kept inside it: `workspaces/Imported from Obsidian 2026-10-16/Projects/Alpha.md`.
///
/// A name is made the way the library makes a note's file name (tauri/src-tauri/src/library/names.rs `file_stem`):
/// what a file system refuses goes, and so do `#`, `^`, `[` and `]`, spaces are collapsed, a leading dot and a
/// trailing dot or space are trimmed, and the stem is at most 80 characters. A folder's name is made the same way,
/// and a name that cleans away to nothing is `Untitled`.
///
/// **Nothing is ever written over.** [ImportPaths] knows every path the library holds and every path this import
/// has given out, ignoring case (a Mac's disk does), and a name already taken gets ` 2`, ` 3` and on, as the
/// library's own clash does. Each such rename is kept, for the import's report to say.
library;

import '../core/note_folders.dart' show folderName, workspacesFolder;

/// The most characters a file's stem may have (names.rs `MAX_STEM`).
const int maxStem = 80;

final RegExp _refused = RegExp(r'[/\\:*?"<>|#^\[\]\x00-\x1f\x7f]');
final RegExp _spaces = RegExp(r'\s+');

/// [name] as a file's or a folder's name in the library (names.rs `file_stem`, for a name rather than a title).
String cleanStem(String name) {
  var stem = name.replaceAll(_refused, '').replaceAll('**', '').replaceAll('__', '').replaceAll(_spaces, ' ').trim();
  if (stem.length > maxStem) {
    final cut = stem.substring(0, maxStem);
    final space = cut.lastIndexOf(' ');
    stem = space > maxStem ~/ 2 ? cut.substring(0, space) : cut;
  }
  stem = stem.replaceFirst(RegExp(r'[. ]+$'), '').replaceFirst(RegExp(r'^\.+'), '').trim();
  return stem.isEmpty ? 'Untitled' : stem;
}

/// The day an import is named for: `2026-10-16`.
String importDay(DateTime at) => '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';

/// The group an import of [from] makes on [at]: `Imported from Obsidian 2026-10-16`. The first of that, then
/// `… (2)`, `… (3)`, that no workspace in [taken] is already called (ignoring case), so a second import the same
/// day is a group of its own and can be taken away on its own.
String importGroupName(String from, DateTime at, Iterable<String> taken) {
  final names = {for (final name in taken) name.toLowerCase()};
  final base = 'Imported from $from ${importDay(at)}';
  if (!names.contains(base.toLowerCase())) return base;
  for (var n = 2;; n += 1) {
    final next = '$base ($n)';
    if (!names.contains(next.toLowerCase())) return next;
  }
}

/// A note's file given a new name because its own was taken: what the report says.
typedef Renamed = ({String from, String to});

/// The paths an import may write, each one free.
class ImportPaths {
  /// [taken] is every path the library holds now; [group] the workspace's name, whose folder holds the import.
  ImportPaths({required Iterable<String> taken, required String group}) : root = '$workspacesFolder/${folderName(group)}' {
    for (final path in taken) {
      _taken.add(path.toLowerCase());
    }
  }

  /// The import's own folder: `workspaces/<the group>`.
  final String root;
  final Set<String> _taken = {};

  /// Every name this import had to change, in the order it did.
  final List<Renamed> renamed = [];

  /// A free path for a note whose place in what was imported is [folders] (the folders it was in, outermost
  /// first, each cleaned) and whose name is [stem]: `workspaces/<group>/<folders>/<stem>.md`, or with ` 2`, ` 3`
  /// where that is taken. [original] is what the report calls it when it had to be renamed.
  String place(List<String> folders, String stem, {String? original}) {
    final dir = [root, for (final folder in folders) cleanStem(folder)].join('/');
    final clean = cleanStem(stem);
    var path = '$dir/$clean.md';
    if (_taken.contains(path.toLowerCase())) {
      for (var n = 2;; n += 1) {
        final next = '$dir/$clean $n.md';
        if (!_taken.contains(next.toLowerCase())) {
          renamed.add((from: original ?? '$clean.md', to: '$clean $n.md'));
          path = next;
          break;
        }
      }
    }
    _taken.add(path.toLowerCase());
    return path;
  }
}
