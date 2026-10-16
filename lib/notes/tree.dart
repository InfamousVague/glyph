/// The notes as the sidebar shows them: a folder for each workspace, then the notes filed in none, then the archive
/// (notes/note_tree.dart). A port of `src/app/notes/tree.ts`.
///
/// Pure, so the rules of what goes where are tests rather than something to click through. The order inside each
/// group is the list's own (pinned first, then the most recently touched), so a note sits in the same order in the
/// tree as it does on the home screen.
///
/// What differs: `listOrder` and `archiveOrder` are the web's `core/store.ts`'s, ported here because lib/core has no
/// store yet; they move there with it. The three switches are read from and written to a [Stored]
/// (core/stored.dart), the app's own unless one is handed in, where the web asked `localStorage` itself.
library;

import '../core/note.dart';
import '../core/stored.dart';
import '../core/workspaces.dart' show Workspace, Workspaces;

/// A sort that keeps equal notes in the order they came in, as JavaScript's does and Dart's need not.
List<Note> _stably(Iterable<Note> notes, int Function(Note a, Note b) compare) {
  final numbered = [for (final (at, note) in notes.indexed) (at, note)];
  numbered.sort((a, b) {
    final by = compare(a.$2, b.$2);
    return by != 0 ? by : a.$1.compareTo(b.$1);
  });
  return [for (final (_, note) in numbered) note];
}

/// The list as the list screen shows it: starred notes first, each group newest edit first, archived notes left out
/// (`listOrder`, core/store.ts).
List<Note> listOrder(Iterable<Note> notes) => _stably(
      notes.where((n) => (n.archivedAt ?? 0) == 0),
      (a, b) {
        final pinned = (b.starred ? 1 : 0) - (a.starred ? 1 : 0);
        return pinned != 0 ? pinned : b.updatedAt.compareTo(a.updatedAt);
      },
    );

/// The archive: the reverse selection, most recently archived first (`archiveOrder`, core/store.ts).
List<Note> archiveOrder(Iterable<Note> notes) => _stably(
      notes.where((n) => (n.archivedAt ?? 0) != 0),
      (a, b) => (b.archivedAt ?? 0).compareTo(a.archivedAt ?? 0),
    );

/// A workspace as a folder of the tree (`TreeFolder`), with the folders inside it (lib/core/workspaces.dart
/// `Workspace.parent`; the port's own since 2026-10-16).
class TreeFolder {
  const TreeFolder({required this.id, required this.name, this.hue, required this.notes, this.folders = const []});
  final String id;
  final String name;
  final String? hue;

  /// The notes filed in this folder itself.
  final List<Note> notes;

  /// The folders inside it, in the order they were made.
  final List<TreeFolder> folders;

  /// Its notes and those of every folder inside it, as its count says.
  int get count => notes.length + folders.fold(0, (sum, folder) => sum + folder.count);

  /// This folder and every folder inside it, top down.
  Iterable<TreeFolder> get all sync* {
    yield this;
    for (final folder in folders) {
      yield* folder.all;
    }
  }
}

/// The whole tree (`Tree`).
class Tree {
  const Tree({required this.folders, required this.loose, required this.archived});
  final List<TreeFolder> folders;

  /// Notes filed in no workspace, or in one that has since gone.
  final List<Note> loose;
  final List<Note> archived;
}

/// The notes sorted into the tree (`noteTree`). [list] is every workspace, in the order they were made, and [of]
/// which workspace each filed note is in, by note id: a [Workspaces]' two halves.
///
/// A workspace inside another is a folder inside its parent's ([TreeFolder.folders]); one whose parent is not in
/// [list] is at the top.
Tree noteTree(Iterable<Note> notes, {required List<Workspace> list, required Map<String, String> of}) {
  final live = listOrder(notes);
  final known = {for (final space in list) space.id};
  final byFolder = <String, List<Note>>{};
  for (final note in live) {
    final filed = of[note.id];
    if (filed != null && known.contains(filed)) (byFolder[filed] ??= <Note>[]).add(note);
  }
  final seen = <String>{};
  TreeFolder folderOf(Workspace space) {
    seen.add(space.id);
    return TreeFolder(
      id: space.id,
      name: space.name,
      hue: space.hue,
      notes: byFolder[space.id] ?? const <Note>[],
      folders: [for (final inside in list) if (inside.parent == space.id && !seen.contains(inside.id)) folderOf(inside)],
    );
  }

  return Tree(
    folders: [for (final space in list) if (space.parent == null || !known.contains(space.parent)) folderOf(space)],
    loose: [for (final note in live) if (!known.contains(of[note.id] ?? '')) note],
    archived: archiveOrder(notes),
  );
}

/// [noteTree] of a [Workspaces] as its store answers it.
Tree noteTreeOf(Iterable<Note> notes, Workspaces spaces) => noteTree(notes, list: spaces.list, of: spaces.of);

/// The archive's place among the folders, for remembering whether it is open (`ARCHIVE_FOLDER`).
const String archiveFolder = 'archive';

/// Which folders are closed, per device: how a sidebar is left is a matter of the screen it is on, not something to
/// carry to another device. The archive starts closed, everything else open.
const String _closedKey = 'glyph-tree-closed';

Set<String> readClosed([Stored? on]) => {
      ...(on ?? stored).read<List<String>>(_closedKey, const [archiveFolder], (parsed) => parsed is List ? [...parsed.whereType<String>()] : null),
    };

/// Where storage refuses, the sidebar just opens as it was for this run.
void writeClosed(Set<String> closed, [Stored? on]) => (on ?? stored).write(_closedKey, [...closed]);

/// Whether the trash's folder is open, per device, and shut until it is opened. Kept apart from the folders' own
/// list: that list stores which are shut, and a device that stored it before there was a trash would show the trash
/// open.
const String _trashKey = 'glyph-tree-trash-open';

bool readTrashOpen([Stored? on]) => (on ?? stored).readText(_trashKey) == '1';

/// Where storage refuses, it opens shut next time.
void writeTrashOpen(bool open, [Stored? on]) => (on ?? stored).writeText(_trashKey, open ? '1' : '0');

/// Whether the sidebar lists names only (notes/note_tree.dart), per device, and not until asked.
const String _compactKey = 'glyph-tree-compact';

bool readCompact([Stored? on]) => (on ?? stored).readText(_compactKey) == '1';

/// Where storage refuses, names only for this run.
void writeCompact(bool on, [Stored? where]) => (where ?? stored).writeText(_compactKey, on ? '1' : '0');
