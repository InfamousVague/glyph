/// What the Notion-like sidebar asks of the app, and the writes it makes over the page tree (docs/TEAMSPACES.md;
/// Matt, 2026-10-31, his choice for the sidebar: "A space switcher at the top (Personal, then each organization)
/// scoping the tree; above the tree, fixed rows: Home, Search, My tickets, Triage, Updates; then sections:
/// Favorites, Teamspace (the organization's pages) or Private (your own), Shared with me").
///
/// The sidebar itself is lib/notes/note_tree.dart's, drawn as spaces when it is handed a [SidebarSpaces]
/// (note_tree_spaces.dart); here is what has no drawing: the bundle of what the root does for it, which space this
/// device last chose and which pages it left unfolded (both the device's, never synced: TEAMSPACES.md, "what is one
/// person's (favorites, folds, which space is chosen) lives in their synced settings or on the device"), a new page
/// made inside another, a page retitled from its row, and a refused drag said in words.
///
/// **Shared with me is not drawn.** Nothing in the library says a note came to this person from someone else: a
/// share link (lib/share/share.dart `forkShared`) saves an ordinary copy with nothing on it to say so, and a note
/// filed into an organization is that organization's, which its space already lists. The section waits for a mark
/// to read (a `shared-by:` key, or the share's id kept with the copy).
library;

import 'package:flutter/foundation.dart';

import '../core/folder_adopter.dart' show fileByFolder;
import '../core/front_matter.dart';
import '../core/note_folders.dart' show inboxFolder;
import '../core/page_tree.dart';
import '../core/properties.dart' show withProperty;
import '../core/stored.dart';

/// What the root does for the sidebar's spaces; every part left out is a row or a button not drawn.
@immutable
class SidebarSpaces {
  const SidebarSpaces({this.mover, this.favorites = const [], this.onFavorite, this.onHome, this.onTriage, this.onUpdates, this.onRename, this.onSay});

  /// Writes a drag and a new page (lib/core/page_tree.dart `PageMover`); without it the rows are not dragged and
  /// have no +.
  final PageMover? mover;

  /// The favorites' note ids, in order (lib/core/favorites.dart), and the switch for one.
  final List<String> favorites;
  final void Function(String noteId, bool on)? onFavorite;

  /// The space's home: Personal's is the home page, an organization's its own page (its `Home.md` drawn with its
  /// members, lib/orgs/ui/organization_screen.dart).
  final ValueChanged<Space>? onHome;

  /// The triage list (lib/tickets/ui/tickets_screen.dart), and the Updates (the bell's card).
  final VoidCallback? onTriage;
  final VoidCallback? onUpdates;

  /// A page's new title, from Rename… on its row.
  final void Function(String noteId, String title)? onRename;

  /// Says a line to the person (the app's toast); the kit's toast where it is left out.
  final ValueChanged<String>? onSay;

  @override
  bool operator ==(Object other) =>
      other is SidebarSpaces &&
      other.mover == mover &&
      listEquals(other.favorites, favorites) &&
      other.onFavorite == onFavorite &&
      other.onHome == onHome &&
      other.onTriage == onTriage &&
      other.onUpdates == onUpdates &&
      other.onRename == onRename &&
      other.onSay == onSay;

  @override
  int get hashCode => Object.hash(mover, Object.hashAll(favorites), onHome, onTriage, onUpdates, onRename, onSay, onFavorite);
}

// ---- kept on the device ----------------------------------------------------------------------------------------------

const String _spaceKey = 'glyph-sidebar-space';
const String _openKey = 'glyph-tree-pages-open';

/// The space this device's sidebar last showed ([Space.id]); Personal's until one is chosen.
String readSidebarSpace([Stored? on]) => (on ?? stored).readText(_spaceKey) ?? personalSpaceId;

/// Where storage refuses, the sidebar shows the space for this run only.
void writeSidebarSpace(String id, [Stored? on]) => (on ?? stored).writeText(_spaceKey, id);

/// The pages this device left unfolded, by [PageNode.id]: shut until opened, as Notion's are, so a library of
/// thousands opens as its tops.
Set<String> readOpenPages([Stored? on]) => {
      ...(on ?? stored).read<List<String>>(_openKey, const [], (parsed) => parsed is List ? [...parsed.whereType<String>()] : null),
    };

void writeOpenPages(Set<String> open, [Stored? on]) => (on ?? stored).write(_openKey, [...open]);

// ---- words -----------------------------------------------------------------------------------------------------------

/// Why a drag into a page was refused, as the toast says it.
String refusalWords(MoveRefusal why) => switch (why) {
      MoveRefusal.noFile => 'That page has no file yet: write something in it first.',
      MoveRefusal.isFolder => 'A folder moves with Move to in its menu, not into a page.',
      MoveRefusal.intoItself => 'A page cannot go inside itself.',
      MoveRefusal.acrossSpaces => 'Pages stay in their space: file a note into an organization to share it.',
      MoveRefusal.noFolder => 'Drop it into Inbox or a folder.',
      MoveRefusal.alreadyThere => 'It is in that page already.',
    };

// ---- a page's title --------------------------------------------------------------------------------------------------

/// The body titled [title] (Rename… on a page's row): its front matter's `title:` where that names it, else its
/// first heading's words where it opens with one, else a heading put over its first line. Blank leaves it as it was.
String withPageTitle(String body, String title) {
  final clean = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return body;
  final span = frontMatterSpan(body);
  final named = frontMatterValueIn(body, span, 'title');
  if (named != null && named.trim().isNotEmpty) return withProperty(body, 'title', clean);
  final head = body.substring(0, span.offset);
  final lines = body.substring(span.offset).split('\n');
  final at = lines.indexWhere((line) => line.trim().isNotEmpty);
  if (at < 0) return '$head# $clean\n';
  if (RegExp(r'^\s{0,3}#{1,6}\s').hasMatch(lines[at])) {
    lines[at] = '${RegExp(r'^\s{0,3}#{1,6}').firstMatch(lines[at])!.group(0)!.trim()} $clean';
  } else {
    lines.insert(at, '# $clean');
  }
  return head + lines.join('\n');
}

// ---- a new page inside another ---------------------------------------------------------------------------------------

String _dirOf(String path) {
  final at = path.lastIndexOf('/');
  return at < 0 ? '' : path.substring(0, at);
}

String _baseOf(String path) => path.substring(path.lastIndexOf('/') + 1);

String _stemOf(String path) {
  final name = _baseOf(path);
  return name.toLowerCase().endsWith('.md') ? name.substring(0, name.length - 3) : name;
}

String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

/// The folder a new page made inside [under] goes in (the + on its row): a folder's, the folder; a plain note's,
/// the folder it becomes the page of, `D/Plan.md`'s `D/Plan` (`Plan 2` where a folder of that name has a page
/// already), as [planMoveInto] plans for a drop; the top of [space] for none, an organization's folder or the
/// inbox. Null for a note with no file.
String? subPageFolder(PageTree tree, Space space, PageNode? under) {
  if (under == null) return space.folder ?? inboxFolder;
  if (under.folder != null) return under.folder;
  final at = under.note?.path;
  if (at == null) return null;
  final dir = _dirOf(at), stem = _stemOf(at);
  var name = stem;
  for (var n = 2; tree.folderNode(_join(dir, name))?.note != null; n += 1) {
    name = '$stem $n';
  }
  return _join(dir, name);
}

/// Makes a page inside [under] (the + on its row, or on a section's head for the top of [space]) and answers its
/// note's id, or null where nothing was made. A plain note is made its folder's page first (`Plan.md` to
/// `Plan/index.md`, through the library's own move, which takes its `.versions` and `.canvas` along, and filed
/// there as [PageMover.run] files a move), so the new page is its sub-page on every device; the new note is then
/// made with a heading, since a blank one is a draft with no file (lib/core/library.dart `createNote`), given the
/// folder's next free name, and filed in the folder's workspace (folder_adopter.dart `fileByFolder`).
Future<String?> newPageIn(PageMover mover, PageTree tree, Space space, {PageNode? under, String title = 'Untitled'}) async {
  final library = mover.library;
  final folder = subPageFolder(tree, space, under);
  if (folder == null) return null;
  final made = under?.note;
  if (under != null && under.folder == null && made != null) {
    final whole = await library.get(made.id);
    if (whole == null || whole.path != made.path) return null;
    final to = '$folder/$folderPageFile';
    final moved = await library.apply(whole.copyWith(path: () => to));
    if (moved.path != to) return null;
    fileByFolder(mover.workspaces, made.id, folder, orgFolders: mover.orgFolders);
  }
  final taken = <String>{
    folderPageFile,
    for (final node in tree.readingOrder(space))
      if (node.path != null && _dirOf(node.path!) == folder) _baseOf(node.path!).toLowerCase(),
  };
  var name = '$title.md';
  for (var n = 2; taken.contains(name.toLowerCase()); n += 1) {
    name = '$title $n.md';
  }
  final note = await library.createNote('# $title\n');
  final whole = await library.get(note.id) ?? note;
  final to = '$folder/$name';
  await library.apply(whole.copyWith(path: () => to));
  fileByFolder(mover.workspaces, note.id, folder, orgFolders: mover.orgFolders);
  return note.id;
}
