/// Workspaces: a name a note can be filed under, and the list shown one workspace at a time. A port of
/// `src/app/core/workspaces.ts`, with the id helpers of `core/orgs/types.ts` it re-exports.
///
/// A workspace is only a name; a note is in at most one, or in none. The chosen one is remembered, a note made while
/// one is chosen is filed there, and removing a workspace unfiles its notes and deletes nothing. An organization's
/// workspace has the id `org-<orgId>`, follows the organization's name and hue, and refuses a rename, a recolour or a
/// removal by hand.
///
/// What differs:
/// - The web kept one module-level sheet in the preferences and one filter in localStorage; here it is a
///   [WorkspaceStore] over a [WorkspaceStorage], so a test or a screen makes its own. The app's storage is the
///   preferences and the device's own key, as on the web (lib/core/kept_workspaces.dart); [MemoryWorkspaceStorage]
///   is one for this run. The function names are the web's, as methods.
/// - The web's module reaches for `core/noteFolders.ts` and the trash itself; here both are handed in. A note's file
///   follows its filing through [WorkspaceStore.onFiled] (lib/core/note_folders.dart gives the function), and
///   `deleteWorkspace` puts the notes in the [Trash] the store was made with. Without them nothing moves and nothing
///   is trashed, as in a browser with no library.
/// - The move of a set kept under the old `glyph-workspaces` key into the preferences is the web's own history and
///   is not carried.
/// - **Folders inside folders** are the port's own (2026-10-16): a personal workspace may have a [Workspace.parent],
///   kept beside its name as `parent` in the preferences, and its folder on disk is inside its parent's
///   (`workspaces/Work/Clients/`, lib/core/note_folders.dart). Choosing a workspace shows the notes of the folders
///   inside it too ([WorkspaceStore.inWorkspace]); renaming or moving one moves the files of every folder under it;
///   removing one keeps the folders inside it, a level up. A build without this reads `parent` as nothing and shows
///   every folder at the top.
/// - **Folders inside an organization's workspace** (GHST-107, 2026-10-19): an organization's workspace may be a
///   parent, never a child, and the folders under it, to any depth, are ordinary workspaces with `parent` set, their
///   ids random and kept per account as any folder's. They are the team's: a note's folder is its file's path
///   (`orgs/<the organization>/Clients/Acme/`), which rides inside the sealed team note, so every member's device
///   files it the same (lib/team/folders.dart). Whether a workspace is in an organization is read by walking its
///   parents ([orgOfWorkspace]); the id's prefix ([isOrgWorkspace]) says only whether it is the organization's own.
///   Nothing is moved into or out of an organization: [canMove] keeps a folder in the organization it is in, or out
///   of every one. The organization's workspace gone ([dropOrgWorkspace]) takes its folders with it.
/// - **A folder's id is its place's** (2026-10-23; Matt: "When creating multiple folders it seems like it's syncing
///   then duplicating the folder I created a meetings folder and got one with no notes but the color i chose and then
///   one with no color but the note i placed inside"). A folder was given a random id as it was made, and a folder
///   of an organization's is also made by the team's channel, by name, for a note whose path names one this device
///   has not got (lib/team/folders.dart). His Mac made Meetings in HelloTrade, in a colour, and filed a note in it;
///   the note's row reached his phone in a team pass, which syncs no settings, so the phone had no Meetings yet and
///   made one of its own, with another id and no colour, and filed the note there. The settings merged both lists by
///   id, so both folders stood, and the note's filing went to the phone's, which sent last. Now a folder is given
///   the id its place says ([folderIdFor]): who it is under (the account, or the organization) and the names of the
///   folders down to it, cleaned and in lower case, as its folder on disk is named. So every device that makes
///   Meetings in HelloTrade makes the same one, by hand or by a note's path, and the settings meet it as one
///   ([mergeTwinFolders] heals the twins made before this). The id is the old shape (`w-` and six letters); one
///   already taken by another folder, a folder renamed since, is passed over for a random one.
library;

import 'dart:convert' show utf8;
import 'dart:math';

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/foundation.dart';

import 'note_folders.dart' show folderName;
import 'trash.dart';

/// The hues a workspace can wear (`WORKSPACE_HUES`). A name, not a colour: what each looks like is ink.css `[data-hue]`.
const List<String> workspaceHues = ['ink', 'ember', 'amber', 'moss', 'sea', 'violet', 'rose'];

bool _isHue(Object? value) => value is String && workspaceHues.contains(value);

/// A hue as a workspace wears it: one this build does not know, and ink, which is no hue, read as none.
String? _wornHue(Object? hue) => _isHue(hue) && hue != 'ink' ? hue as String : null;

const String _orgWorkspace = 'org-';

/// The id of an organization's workspace: `org-<orgId>`, so every device makes the same one.
String orgWorkspaceId(String orgId) => '$_orgWorkspace$orgId';

/// The organization a workspace stands for, by its id; null for a personal workspace.
String? orgIdOf(String workspaceId) =>
    workspaceId.startsWith(_orgWorkspace) && workspaceId.length > _orgWorkspace.length ? workspaceId.substring(_orgWorkspace.length) : null;

/// Whether a workspace is an organization's own: the id's prefix, which is the truth. A folder inside one is not
/// (its id is any folder's); [orgOfWorkspace] says whether a workspace is in an organization at all.
bool isOrgWorkspace(String workspaceId) => orgIdOf(workspaceId) != null;

/// The organization a workspace is in, by id, walking its parents up to an organization's own workspace: the
/// organization's for its own workspace, the same for a folder under it however deep, and null for a personal
/// workspace or an id [all] does not have.
String? orgOfWorkspace(List<Workspace> all, String id) {
  final byId = {for (final w in all) w.id: w};
  final seen = <String>{};
  var at = byId[id];
  while (at != null && seen.add(at.id)) {
    final org = orgIdOf(at.id);
    if (org != null) return org;
    at = at.parent == null ? null : byId[at.parent];
  }
  return null;
}

/// A workspace (`Workspace`).
@immutable
class Workspace {
  const Workspace({required this.id, required this.name, this.hue, this.parent});

  /// A workspace as it is kept, with a hue this build does not know, and ink, read as none.
  factory Workspace.kept({required String id, required String name, Object? hue, Object? parent}) =>
      Workspace(id: id, name: name, hue: _wornHue(hue), parent: parent is String && parent.isNotEmpty ? parent : null);

  final String id;
  final String name;

  /// Its colour, worn by its pill and its tag on a note. Null is `ink`, the app's own.
  final String? hue;

  /// The workspace this one is a folder inside, by id; null at the top (docs/FEATURES_2_1.md, organize). Its
  /// folder on disk is inside its parent's: `workspaces/Work/Clients/`, or `orgs/Ghost.md/Clients/` under an
  /// organization's. An organization's own workspace has none.
  final String? parent;

  /// The organization it stands for, by id; null for a personal one, and for a folder inside an organization's,
  /// which stands for none ([orgOfWorkspace] says which it is in). Read from the id, never kept.
  String? get org => orgIdOf(id);

  /// The same workspace with another name, hue or parent; [parent] is a function so null can be said.
  Workspace copyWith({String? name, String? hue, String? Function()? parent}) => Workspace(id: id, name: name ?? this.name, hue: hue ?? this.hue, parent: parent == null ? this.parent : parent());

  @override
  bool operator ==(Object other) => other is Workspace && other.id == id && other.name == name && other.hue == hue && other.parent == parent;

  @override
  int get hashCode => Object.hash(id, name, hue, parent);

  @override
  String toString() => 'Workspace($id, $name${hue == null ? '' : ', $hue'}${parent == null ? '' : ', in $parent'})';
}

/// The workspaces [id] stands over, itself first, then every folder inside it however deep, in [list]'s order.
List<String> workspaceFamily(List<Workspace> list, String id) {
  final out = <String>[id];
  for (var at = 0; at < out.length; at += 1) {
    for (final w in list) {
      if (w.parent == out[at] && !out.contains(w.id)) out.add(w.id);
    }
  }
  return out;
}

/// The workspaces from the top down to [id], itself last; empty for an id [list] does not have.
List<Workspace> workspacePath(List<Workspace> list, String id) {
  final byId = {for (final w in list) w.id: w};
  final path = <Workspace>[];
  var at = byId[id];
  while (at != null && !path.contains(at)) {
    path.insert(0, at);
    at = at.parent == null ? null : byId[at.parent];
  }
  return path;
}

/// A workspace's name with its parents' before it, as a list that holds folders inside folders says it:
/// "Work › Clients".
String workspacePathName(List<Workspace> list, String id) => workspacePath(list, id).map((w) => w.name).join(' › ');

/// What makes two folders the same folder: who they are under, by id, and their names as their folders on disk are
/// named, in lower case, as the team's channel finds a folder by its path (lib/team/folders.dart `_find`). Null for
/// an organization's own workspace, which is one of its kind by its id, and for a name that cleans away to nothing.
String? _twinKey(Workspace w) {
  if (isOrgWorkspace(w.id)) return null;
  final name = folderName(w.name).toLowerCase();
  return name.isEmpty ? null : '${w.parent ?? ''}\u0000$name';
}

const String _idLetters = '0123456789abcdefghijklmnopqrstuvwxyz';

/// The id a folder called [name] inside [parent] (null, the top) is given, the same on every device of the account
/// (see the library's doc, "A folder's id is its place's"): read from who it is under, the account or the
/// organization, and the names of the folders from there down to it, cleaned and in lower case. Null where a name
/// on the way cleans away to nothing, or [parent] is not in [list]: such a folder has a random id, as before.
String? folderIdFor(List<Workspace> list, String name, String? parent) {
  final path = parent == null ? const <Workspace>[] : workspacePath(list, parent);
  if (parent != null && path.isEmpty) return null;
  final org = path.isEmpty ? null : orgIdOf(path.first.id);
  final names = [
    for (final w in path)
      if (!isOrgWorkspace(w.id)) folderName(w.name).toLowerCase(),
    folderName(name).toLowerCase(),
  ];
  if (names.any((each) => each.isEmpty)) return null;
  final digest = sha1.convert(utf8.encode('glyph/folder/v1\u0000${org == null ? 'account' : 'org:$org'}\u0000${names.join('/')}')).bytes;
  return 'w-${[for (var at = 0; at < 6; at += 1) _idLetters[digest[at] % _idLetters.length]].join()}';
}

/// What the page reads of the workspaces at a moment (`Workspaces`).
@immutable
class Workspaces {
  const Workspaces({this.list = const [], this.of = const {}, this.current});

  /// Every workspace, in the order they were made.
  final List<Workspace> list;

  /// Which workspace each filed note is in, by note id.
  final Map<String, String> of;

  /// The list's filter: the chosen workspace, or null for all notes.
  final Workspace? current;
}

/// The sheet as it is kept: the workspaces, the filings, and which one the list is filtered by.
@immutable
class WorkspaceSheet {
  const WorkspaceSheet({this.list = const [], this.notes = const {}, this.current});
  final List<Workspace> list;
  final Map<String, String> notes;
  final String? current;
}

/// Where the sheet is kept. On the web the list and the filings are a preference, so they travel, and the filter
/// stays on the device; one small interface stands for both here.
///
/// A storage that is also a [Listenable] is one whose sheet can change without the store's doing (settings from
/// another device landing in the preferences): the store listens, and reads the sheet again when it is told.
abstract class WorkspaceStorage {
  WorkspaceSheet read();
  void write(WorkspaceSheet sheet);
}

/// Kept for this run only.
class MemoryWorkspaceStorage implements WorkspaceStorage {
  MemoryWorkspaceStorage([this._sheet = const WorkspaceSheet()]);
  WorkspaceSheet _sheet;

  @override
  WorkspaceSheet read() => _sheet;

  @override
  void write(WorkspaceSheet sheet) => _sheet = sheet;
}

/// What of an organization its workspace follows: its id, its name, and its hue (`OrgLike`).
@immutable
class OrgLike {
  const OrgLike({required this.id, required this.name, this.hue});
  final String id;
  final String name;
  final String? hue;
}

String _tidy(String name) => name.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Moves notes' files to the folder of the workspace they are now filed in, or back to the inbox for null
/// (`fileNotesInFolder`, core/noteFolders.ts). Asked for and not waited on: the pill changes now, and the file
/// catches up when the library answers.
typedef NotesFiled = void Function(List<String> noteIds, Workspace? workspace);

/// The workspaces, and everything done to them. Listen to it as a [ValueListenable]: its value is the same snapshot
/// until something changes, and each change tells its listeners once.
class WorkspaceStore extends ChangeNotifier implements ValueListenable<Workspaces> {
  WorkspaceStore({WorkspaceStorage? storage, Random? random, this.trash, this.onFiled, int Function()? clock})
      : _storage = storage ?? MemoryWorkspaceStorage(),
        _random = random ?? Random(),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    final storage = _storage;
    if (storage is Listenable) (storage as Listenable).addListener(reloadWorkspaces);
  }

  final WorkspaceStorage _storage;
  final Random _random;
  final int Function() _clock;

  /// The trash [deleteWorkspace] puts a workspace's notes in, and [notesInWorkspace] leaves out; none, and nothing
  /// is trashed and every filed note counts.
  final Trash? trash;

  /// Told each time notes' filing changed where their files should be: a note filed or unfiled, a workspace renamed
  /// or removed.
  final NotesFiled? onFiled;
  WorkspaceSheet? _sheet;
  Workspaces? _snapshot;

  WorkspaceSheet _read() {
    final held = _storage.read();
    final kept = [for (final w in held.list) Workspace.kept(id: w.id, name: w.name, hue: w.hue, parent: w.parent)];
    final ids = {for (final w in kept) w.id};
    // A parent that is gone, one on an organization's own workspace, or a loop back to itself is no parent: the
    // folder is at the top. An organization's workspace as a parent is a folder of the team's (GHST-107).
    final list = [
      for (final w in kept)
        w.parent != null && (!ids.contains(w.parent) || isOrgWorkspace(w.id) || _loops(kept, w)) ? w.copyWith(parent: () => null) : w,
    ];
    // The filings that point at one of the list's workspaces.
    final notes = {
      for (final entry in held.notes.entries)
        if (ids.contains(entry.value)) entry.key: entry.value,
    };
    return WorkspaceSheet(list: list, notes: notes, current: held.current != null && ids.contains(held.current) ? held.current : null);
  }

  WorkspaceSheet get _current => _sheet ??= _read();

  /// Whether following [w]'s parents comes back to it.
  static bool _loops(List<Workspace> list, Workspace w) {
    final byId = {for (final each in list) each.id: each};
    final seen = <String>{w.id};
    var at = w.parent == null ? null : byId[w.parent];
    while (at != null) {
      if (!seen.add(at.id)) return true;
      at = at.parent == null ? null : byId[at.parent];
    }
    return false;
  }

  void _write(WorkspaceSheet next) {
    _sheet = next;
    _snapshot = null;
    _storage.write(next);
    notifyListeners();
  }

  /// Reads the sheet again: after a reset, or when another device's settings have landed (`reloadWorkspaces`).
  void reloadWorkspaces() {
    _sheet = null;
    _snapshot = null;
    notifyListeners();
  }

  /// `workspaces()`.
  @override
  Workspaces get value {
    final snapshot = _snapshot;
    if (snapshot != null) return snapshot;
    final sheet = _current;
    Workspace? chosen;
    for (final w in sheet.list) {
      if (w.id == sheet.current) chosen = w;
    }
    return _snapshot = Workspaces(list: List.unmodifiable(sheet.list), of: Map.unmodifiable(sheet.notes), current: chosen);
  }

  /// The workspace [noteId] is filed in, or null.
  Workspace? workspaceOf(String noteId) {
    final sheet = _current;
    final id = sheet.notes[noteId];
    if (id == null) return null;
    for (final w in sheet.list) {
      if (w.id == id) return w;
    }
    return null;
  }

  String _freshId(List<Workspace> taken) {
    const letters = '0123456789abcdefghijklmnopqrstuvwxyz';
    for (;;) {
      final id = 'w-${List.generate(6, (_) => letters[_random.nextInt(letters.length)]).join()}';
      if (!taken.any((w) => w.id == id)) return id;
    }
  }

  /// The id a new folder called [name] inside [parent] is given: its place's ([folderIdFor]) unless another folder
  /// has that id already, then a random one.
  String _idFor(List<Workspace> list, String name, String? parent) {
    final placed = folderIdFor(list, name, parent);
    if (placed != null && !list.any((w) => w.id == placed)) return placed;
    return _freshId(list);
  }

  /// A new workspace called [name], in [hue], or the one already called that; null for an empty name. With
  /// [parent], a folder inside that workspace, a personal one or an organization's (GHST-107), and the one already
  /// called that inside the same parent is the one. Without, the personal one already called that, wherever it is,
  /// as before folders were nested; an organization's workspace of that name, or a folder inside one, is never the
  /// one, since those are the team's. A parent the list does not have is no parent.
  Workspace? addWorkspace(String name, [String hue = 'ink', String? parent]) {
    final clean = _tidy(name);
    if (clean.isEmpty) return null;
    final sheet = _current;
    final inside = parent != null && sheet.list.any((w) => w.id == parent) ? parent : null;
    for (final w in sheet.list) {
      if (w.name.toLowerCase() != clean.toLowerCase()) continue;
      if (inside != null ? w.parent == inside : orgOfWorkspace(sheet.list, w.id) == null) return w;
    }
    final made = Workspace(id: _idFor(sheet.list, clean, inside), name: clean, hue: _wornHue(hue), parent: inside);
    _write(WorkspaceSheet(list: [...sheet.list, made], notes: sheet.notes, current: sheet.current));
    return made;
  }

  /// That workspace in [hue]; `ink` takes its colour off again. Unknown workspace, unknown hue, or an organization's
  /// workspace: nothing happens.
  void setWorkspaceHue(String id, String hue) {
    final sheet = _current;
    if (!_isHue(hue) || !sheet.list.any((w) => w.id == id) || isOrgWorkspace(id)) return;
    _write(WorkspaceSheet(
      list: [for (final w in sheet.list) w.id == id ? Workspace(id: w.id, name: w.name, hue: _wornHue(hue), parent: w.parent) : w],
      notes: sheet.notes,
      current: sheet.current,
    ));
  }

  /// Renames the workspace. Not an organization's, whose name is the organization's.
  void renameWorkspace(String id, String name) {
    if (isOrgWorkspace(id)) return;
    _rename(id, name);
  }

  void _rename(String id, String name) {
    final clean = _tidy(name);
    final sheet = _current;
    Workspace? was;
    for (final w in sheet.list) {
      if (w.id == id) was = w;
    }
    if (clean.isEmpty || was == null) return;
    final renamed = was.copyWith(name: clean);
    _write(WorkspaceSheet(
      list: [for (final w in sheet.list) w.id == id ? renamed : w],
      notes: sheet.notes,
      current: sheet.current,
    ));
    // The folder is named after the workspace, so renaming one moves its notes into a folder of the new name, and
    // the notes of every folder inside it, whose folders are inside that one.
    _refile(id);
  }

  /// Tells [onFiled] where the notes of [id] and of every folder inside it now belong.
  void _refile(String id) {
    final sheet = _current;
    for (final each in workspaceFamily(sheet.list, id)) {
      final notes = _filedIn(sheet.notes, each);
      final space = sheet.list.where((w) => w.id == each).firstOrNull;
      if (notes.isNotEmpty && space != null) onFiled?.call(notes, space);
    }
  }

  /// The workspaces inside [id], one level down, in the order they were made; the ones at the top for null.
  List<Workspace> childrenOf(String? id) => [for (final w in _current.list) if (w.parent == id) w];

  /// Whether [id] may be put inside [parent] (null, the top): not an organization's own workspace, which is always
  /// at the top; [parent] not [id] itself nor any folder inside it; and in the same organization as [id] is now, or
  /// in none, so a folder is never dragged into an organization or out of one (GHST-107: its notes would change
  /// hands). A folder of an organization's may go to any folder of the same, or to the organization's workspace,
  /// never to the top.
  bool canMove(String id, String? parent) {
    if (isOrgWorkspace(id)) return false;
    final list = _current.list;
    if (!list.any((w) => w.id == id)) return false;
    final org = orgOfWorkspace(list, id);
    if (parent == null) return org == null;
    if (!list.any((w) => w.id == parent) || orgOfWorkspace(list, parent) != org) return false;
    return !workspaceFamily(list, id).contains(parent);
  }

  /// Puts workspace [id] inside [parent], or at the top with null: its folder, and every folder inside it, move with
  /// it on disk, and their notes with them. Not an organization's own; never into itself or a folder inside it;
  /// never into or out of an organization ([canMove]).
  void moveWorkspace(String id, String? parent) {
    if (!canMove(id, parent)) return;
    final sheet = _current;
    final was = sheet.list.firstWhere((w) => w.id == id);
    if (was.parent == parent) return;
    _write(WorkspaceSheet(
      list: [for (final w in sheet.list) w.id == id ? w.copyWith(parent: () => parent) : w],
      notes: sheet.notes,
      current: sheet.current,
    ));
    _refile(id);
  }

  /// The notes filed in workspace [id], from the sheet's filings (`filedIn`).
  static List<String> _filedIn(Map<String, String> notes, String id) => [
        for (final entry in notes.entries)
          if (entry.value == id) entry.key,
      ];

  /// The notes filed in workspace [id] that are not already in the trash: what deleting it would ask about
  /// (`notesInWorkspace`).
  List<String> notesInWorkspace(String id) {
    final held = trash?.value ?? const <String, int>{};
    return [
      for (final note in _filedIn(_current.notes, id))
        if (!held.containsKey(note)) note,
    ];
  }

  /// The notes filed in workspace [id] or in any folder under it, however deep, that are not in the trash: what a
  /// folder holds, as its count says (GHST-107).
  List<String> notesUnder(String id) {
    final sheet = _current;
    final family = workspaceFamily(sheet.list, id).toSet();
    final held = trash?.value ?? const <String, int>{};
    return [
      for (final entry in sheet.notes.entries)
        if (family.contains(entry.value) && !held.containsKey(entry.key)) entry.key,
    ];
  }

  /// The organization workspace [workspaceId] is in, walking its parents ([orgOfWorkspace]); null for a personal
  /// one. Not the note's: [workspaceOf] finds a note's workspace first.
  String? orgOf(String workspaceId) => orgOfWorkspace(_current.list, workspaceId);

  /// Deletes the workspace, asked each time what becomes of its notes: kept, in its parent or unfiled, as [removeWorkspace]
  /// leaves them, or put in the trash with it, where they wait to be restored or emptied like any deleted note
  /// (`deleteWorkspace`). Nothing is deleted for good here. Not an organization's, which goes when the person leaves.
  void deleteWorkspace(String id, {required bool trashNotes}) {
    if (isOrgWorkspace(id)) return;
    if (trashNotes) {
      final now = _clock();
      for (final note in notesInWorkspace(id)) {
        trash?.trashNote(note, now);
      }
    }
    _remove(id);
  }

  /// Removes the workspace; its notes go into its parent, or at the top are simply not filed any more, and the list
  /// shows all notes if it was chosen.
  /// Not an organization's, which goes when the person leaves it.
  void removeWorkspace(String id) {
    if (isOrgWorkspace(id)) return;
    _remove(id);
  }

  void _remove(String id) {
    final sheet = _current;
    final gone = sheet.list.where((w) => w.id == id).firstOrNull;
    // Its notes go a level up with the folders inside it: into its parent, where it has one (Matt, 2026-10-23: a
    // folder of an organization's deleted keeps its notes the team's, where unfiling them took them out of the
    // organization and so from every other member); at the top, they are not filed any more and their files go back to
    // the inbox.
    final parent = gone?.parent == null ? null : sheet.list.where((w) => w.id == gone!.parent).firstOrNull;
    onFiled?.call(_filedIn(sheet.notes, id), parent);
    if (gone == null) return;
    // The folders inside it are kept, one level up: inside its parent, or at the top.
    final inside = [for (final w in sheet.list) if (w.parent == id) w.id];
    _write(WorkspaceSheet(
      list: [
        for (final w in sheet.list)
          if (w.id != id) w.parent == id ? w.copyWith(parent: () => gone.parent) : w,
      ],
      notes: {
        for (final entry in sheet.notes.entries)
          if (entry.value != id) entry.key: entry.value else if (parent != null) entry.key: parent.id,
      },
      current: sheet.current == id ? null : sheet.current,
    ));
    for (final child in inside) {
      _refile(child);
    }
  }

  /// The organization's workspace, made if this device has none: `org-<orgId>`, named and coloured after it. Found, it
  /// is brought up to date the same way.
  Workspace ensureOrgWorkspace(OrgLike org) {
    final id = orgWorkspaceId(org.id);
    if (_current.list.any((w) => w.id == id)) {
      renameOrgWorkspace(org);
      return _current.list.firstWhere((w) => w.id == id);
    }
    final sheet = _current;
    final name = _tidy(org.name);
    final made = Workspace(id: id, name: name.isEmpty ? org.name : name, hue: _wornHue(org.hue));
    _write(WorkspaceSheet(list: [...sheet.list, made], notes: sheet.notes, current: sheet.current));
    return made;
  }

  /// The organization's workspace renamed and re-coloured with it; nothing happens when this device has none.
  void renameOrgWorkspace(OrgLike org) {
    final id = orgWorkspaceId(org.id);
    final sheet = _current;
    Workspace? was;
    for (final w in sheet.list) {
      if (w.id == id) was = w;
    }
    if (was == null) return;
    final hue = _wornHue(org.hue);
    if (was.hue != hue) {
      _write(WorkspaceSheet(
        list: [for (final w in sheet.list) w.id == id ? Workspace(id: w.id, name: w.name, hue: hue) : w],
        notes: sheet.notes,
        current: sheet.current,
      ));
    }
    final clean = _tidy(org.name);
    if (clean.isNotEmpty && clean != was.name) _rename(id, clean);
  }

  /// The organization's workspace gone, as when the person leaves it, and every folder under it with it (GHST-107:
  /// a folder of a team the person has left is nobody's): their notes are unfiled, never deleted, and the list shows
  /// all notes if one of them was chosen.
  void dropOrgWorkspace(String orgId) {
    final sheet = _current;
    final gone = workspaceFamily(sheet.list, orgWorkspaceId(orgId)).toSet();
    if (!sheet.list.any((w) => gone.contains(w.id))) return;
    onFiled?.call([for (final entry in sheet.notes.entries) if (gone.contains(entry.value)) entry.key], null);
    _write(WorkspaceSheet(
      list: [for (final w in sheet.list) if (!gone.contains(w.id)) w],
      notes: {
        for (final entry in sheet.notes.entries)
          if (!gone.contains(entry.value)) entry.key: entry.value,
      },
      current: gone.contains(sheet.current) ? null : sheet.current,
    ));
  }

  /// Folders that are one folder made twice, made one again: two or more inside the same parent whose names name the
  /// same folder on disk (2026-10-23, Matt's Meetings and Agents in HelloTrade: see the library's doc, "A folder's
  /// id is its place's", for how they were made). Answers how many went.
  ///
  /// Of each set, the one kept is the one in a colour, the colour being what the person chose and the only thing a
  /// folder has besides its name; among those alike, the lowest id. So every device that has the same twins keeps the
  /// same one, and their settings meet with nothing to argue over. The kept one takes a colour from another where it
  /// has none. Every note filed in the others is filed in it, the trashed among them, and the folders inside them
  /// are put inside it, where they may be twins in turn and are made one the same way. The others then go. A note is
  /// never deleted, unfiled or taken out of its organization here: twins share a parent, so they are in the same
  /// organization or in none, and their notes' files are moved as any filing moves them ([onFiled], where nothing
  /// moves when the names were the same, so a team note's row is put again only when its path's case changed).
  int mergeTwinFolders() {
    var gone = 0;
    final kept = <String>{};
    // A pass a level at a time: twins inside twins are siblings only once their parents are one.
    for (var pass = 0; pass < 32; pass += 1) {
      final sheet = _current;
      final sets = <String, List<Workspace>>{};
      for (final w in sheet.list) {
        final key = _twinKey(w);
        if (key != null) (sets[key] ??= []).add(w);
      }
      final into = <String, Workspace>{};
      for (final set in sets.values) {
        if (set.length < 2) continue;
        final ordered = [...set]..sort((a, b) => a.hue != null && b.hue == null ? -1 : (a.hue == null && b.hue != null ? 1 : a.id.compareTo(b.id)));
        final keep = ordered.first;
        final hue = keep.hue ?? ordered.map((w) => w.hue).nonNulls.firstOrNull;
        into[keep.id] = keep.copyWith(hue: hue);
        for (final other in ordered.skip(1)) {
          into[other.id] = into[keep.id]!;
        }
        kept.add(keep.id);
      }
      if (into.isEmpty) break;
      String to(String id) => into[id]?.id ?? id;
      final list = <Workspace>[];
      for (final w in sheet.list) {
        final keep = into[w.id];
        // A twin that goes is not listed; every other folder is, the kept one in its colour, and each inside a
        // twin that went is put inside the one kept.
        if (keep != null && keep.id != w.id) continue;
        final it = keep ?? w, parent = it.parent;
        list.add(parent != null && into.containsKey(parent) ? it.copyWith(parent: () => to(parent)) : it);
      }
      _write(WorkspaceSheet(
        list: list,
        notes: {for (final entry in sheet.notes.entries) entry.key: to(entry.value)},
        current: sheet.current == null ? null : to(sheet.current!),
      ));
      gone += into.entries.where((entry) => entry.key != entry.value.id).length;
    }
    // Where the kept ones' notes belong now, and their folders' under them: the same place, unless a name's case was
    // another.
    for (final id in kept) {
      if (_current.list.any((w) => w.id == id)) _refile(id);
    }
    return gone;
  }

  /// Files [noteId] in a workspace, or in none with null. The note's file follows its filing: into
  /// `workspaces/<the workspace>/`, or back to `Inbox/` ([onFiled]).
  void fileNote(String noteId, String? id) {
    final sheet = _current;
    if (id != null && !sheet.list.any((w) => w.id == id)) return;
    if (sheet.notes[noteId] == id) return;
    final next = {...sheet.notes};
    if (id == null) {
      next.remove(noteId);
    } else {
      next[noteId] = id;
    }
    _write(WorkspaceSheet(list: sheet.list, notes: next, current: sheet.current));
    Workspace? to;
    for (final w in sheet.list) {
      if (w.id == id) to = w;
    }
    onFiled?.call([noteId], to);
  }

  /// Files several notes in one workspace, or in none with null, as one change: an import's notes, filed as they
  /// are made, a batch at a time ([fileNote] once per note writes the whole sheet each time).
  void fileNotes(List<String> noteIds, String? id) {
    final sheet = _current;
    if (id != null && !sheet.list.any((w) => w.id == id)) return;
    final moved = [for (final noteId in noteIds) if (sheet.notes[noteId] != id) noteId];
    if (moved.isEmpty) return;
    final next = {...sheet.notes};
    for (final noteId in moved) {
      if (id == null) {
        next.remove(noteId);
      } else {
        next[noteId] = id;
      }
    }
    _write(WorkspaceSheet(list: sheet.list, notes: next, current: sheet.current));
    Workspace? to;
    for (final w in sheet.list) {
      if (w.id == id) to = w;
    }
    onFiled?.call(moved, to);
  }

  /// A note just made: filed in the chosen workspace, if there is one and the note is not filed yet.
  void fileNewNote(String noteId) {
    final sheet = _current;
    final chosen = sheet.current;
    if (chosen != null && !sheet.notes.containsKey(noteId)) fileNote(noteId, chosen);
  }

  /// The note is gone: so is its filing.
  void forgetNote(String noteId) {
    final sheet = _current;
    if (!sheet.notes.containsKey(noteId)) return;
    _write(WorkspaceSheet(list: sheet.list, notes: {...sheet.notes}..remove(noteId), current: sheet.current));
  }

  /// The list's filter.
  void chooseWorkspace(String? id) {
    final sheet = _current;
    final next = id != null && sheet.list.any((w) => w.id == id) ? id : null;
    if (next == sheet.current) return;
    _write(WorkspaceSheet(list: sheet.list, notes: sheet.notes, current: next));
  }

  /// Of [notes], those filed in workspace [id] or in a folder inside it; all of them for null. [idOf] reads a
  /// note's id.
  List<T> inWorkspace<T>(Iterable<T> notes, String? id, String Function(T note) idOf) {
    if (id == null) return [...notes];
    final filed = _current.notes;
    final family = workspaceFamily(_current.list, id);
    if (family.length == 1) return [for (final note in notes) if (filed[idOf(note)] == id) note];
    final ids = family.toSet();
    return [for (final note in notes) if (ids.contains(filed[idOf(note)])) note];
  }

  @override
  void dispose() {
    final storage = _storage;
    if (storage is Listenable) (storage as Listenable).removeListener(reloadWorkspaces);
    super.dispose();
  }
}
