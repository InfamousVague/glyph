/// The app's own Claude over the folders (GHST-108; Matt, 2026-10-19: "Make it so the AI can manage folders and
/// sorting of files into folders and organize all my organizations into neat logical folders"): list them, make,
/// rename, move and delete one, and file notes in one or out of every one (docs/CLAUDE_APP.md, "Folders").
///
/// A folder is a [Workspace] with a parent (docs/FEATURES_2_1.md, "Folders inside folders", GHST-107), and every
/// change here is the [WorkspaceStore]'s own, so a note's file follows its filing ([WorkspaceStore.onFiled]) and an
/// organization's folders reach the team as the sidebar's do (lib/team/folders.dart).
///
/// **Nothing crosses an organization's edge.** A note filed in an organization's workspace, or in a folder under it,
/// is the team's: filing one in from outside shares it with every member, and filing one out takes it from them. The
/// app asks twice before either (lib/note/workspace_picker.dart), and a run has no way to ask the person in the
/// middle of it, so [ClaudeFolders] refuses both and says to do it from the note's Workspace picker. Within one
/// organization, and among the person's own folders, Claude files freely. A folder moves only where
/// [WorkspaceStore.canMove] lets it, which is the same edge. Deleting a folder of an organization's files the notes
/// in it in the folder above it first, so they stay the team's; deleting a personal one leaves its notes in no
/// folder, as the store does. Nothing here deletes or trashes a note.
library;

import 'dart:convert';

import '../core/workspaces.dart';
import 'claude_tools.dart' show ClaudeNotes;

/// A folder tool's refusal, said back to Claude as the tool's error.
class ClaudeFolderProblem implements Exception {
  const ClaudeFolderProblem(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The folder tools' names.
abstract final class ClaudeFolderTool {
  static const list = 'list_folders';
  static const create = 'create_folder';
  static const rename = 'rename_folder';
  static const move = 'move_folder';
  static const delete = 'delete_folder';
  static const file = 'file_notes';

  static const Set<String> all = {list, create, rename, move, delete, file};
}

Map<String, Object?> _string(String description) => {'type': 'string', 'description': description};

Map<String, Object?> _tool(String name, String description, Map<String, Object?> properties, List<String> required) => {
      'name': name,
      'description': description,
      'input_schema': {'type': 'object', 'properties': properties, 'required': required},
    };

const String _folderArg = 'The folder: its id, its path as list_folders gives it (“Work › Clients”, or “Work/Clients”), or its bare name where only one folder has it.';

/// The folder tools, as the API is told them; sent where the run has [ClaudeFolders].
final List<Map<String, Object?>> claudeFolderTools = [
  _tool(
    ClaudeFolderTool.list,
    'Every folder in this Ghost.md account, top-level ones and the folders inside them: id, name, path (“Work › Clients”), the folder it is inside, the organization it belongs to if any, how many notes are filed in it and how many in it and under it. An organization’s own workspace is a folder at the top (`organization_root: true`): it cannot be renamed, moved or deleted, but folders can be made inside it.',
    const {},
    const [],
  ),
  _tool(
    ClaudeFolderTool.create,
    'Makes a folder, or answers the one already of that name in the same place. Inside an organization’s workspace or one of its folders, the folder is the team’s: every member sees it once a note is filed in it.',
    {
      'name': _string('The new folder’s name.'),
      'parent': _string('The folder to make it inside; leave out for the top. $_folderArg'),
    },
    const ['name'],
  ),
  _tool(
    ClaudeFolderTool.rename,
    'Renames a folder; its notes’ files and the folders inside it follow. Not an organization’s own workspace, whose name is the organization’s. In an organization, every member sees the new name.',
    {
      'folder': _string(_folderArg),
      'name': _string('Its new name.'),
    },
    const ['folder', 'name'],
  ),
  _tool(
    ClaudeFolderTool.move,
    'Puts a folder inside another, or at the top; its notes and the folders inside it go with it. Never into itself or a folder inside it, and never into or out of an organization: a personal folder stays among personal ones, and an organization’s folder stays in the same organization (its workspace or another of its folders, never the top).',
    {
      'folder': _string(_folderArg),
      'parent': _string('Where it goes; leave out for the top. $_folderArg'),
    },
    const ['folder'],
  ),
  _tool(
    ClaudeFolderTool.delete,
    'Deletes a folder. No note is deleted: the folders inside it move up into its place, and the notes filed directly in it end up in no folder (a personal folder) or in the folder above it (a folder in an organization, so they stay the team’s). Not an organization’s own workspace.',
    {'folder': _string(_folderArg)},
    const ['folder'],
  ),
  _tool(
    ClaudeFolderTool.file,
    'Files notes in a folder, or with `unfile` takes them out of every folder; each note’s file moves with it. Notes may be moved freely among personal folders, and among the folders of one organization. Filing a note into an organization from outside it would share it with every member, and taking one out of an organization would take it from them: those notes are refused and left where they are, and the person must move them from the note’s Workspace picker, which asks them first. Say so when it happens.',
    {
      'ids': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'The notes’ ids, from list_notes or search_notes.',
      },
      'folder': _string('Where to file them. $_folderArg'),
      'unfile': {'type': 'boolean', 'description': 'True to take them out of every folder instead.'},
    },
    const ['ids'],
  ),
];

/// The system prompt's line about the folder tools.
const String claudeFolderSystem =
    'Notes can be sorted into folders, folders inside folders: list_folders to see them, create_folder, rename_folder, move_folder and delete_folder to arrange them, and file_notes to put notes in one. list_notes says each note’s folder. Organize in a few clear steps and say what you moved. Never move a note into or out of an organization: that shares or unshares it with the team, and only the person does it, from the note’s Workspace picker.';

/// The folders as Claude's tools reach them: the app's [WorkspaceStore], and the notes to check an id against.
class ClaudeFolders {
  ClaudeFolders(this.store);

  final WorkspaceStore store;

  List<Workspace> get _list => store.value.list;

  String _path(String id) => workspacePathName(_list, id);

  /// The organization's name a workspace is in: its own workspace's, which follows the organization's.
  String? _orgName(String id) {
    final org = store.orgOf(id);
    if (org == null) return null;
    return _list.where((w) => w.id == orgWorkspaceId(org)).firstOrNull?.name;
  }

  Map<String, Object?> _brief(Workspace w) {
    final org = store.orgOf(w.id);
    return {
      'id': w.id,
      'name': w.name,
      'path': _path(w.id),
      if (w.parent != null) 'parent': w.parent,
      if (org != null) 'organization': _orgName(w.id) ?? org,
      if (w.org != null) 'organization_root': true,
      'notes': store.notesInWorkspace(w.id).length,
      'notes_under': store.notesUnder(w.id).length,
    };
  }

  /// A folder by its id, its path (› or / between the names), or a bare name only one folder has.
  Workspace resolve(String asked) {
    final key = asked.trim();
    if (key.isEmpty) throw const ClaudeFolderProblem('Name the folder.');
    final list = _list;
    final byId = list.where((w) => w.id == key).firstOrNull;
    if (byId != null) return byId;
    String tidy(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    // The whole path as list_folders says it first, so a name with a slash in it is found.
    final whole = [for (final w in list) if (tidy(_path(w.id)) == tidy(key)) w];
    if (whole.length == 1) return whole.single;
    final parts = [for (final part in key.split(RegExp(r'\s*[›/]\s*'))) if (part.trim().isNotEmpty) tidy(part)];
    final List<Workspace> found;
    if (parts.length > 1) {
      found = [
        for (final w in list)
          if (_matches(workspacePath(list, w.id).map((each) => tidy(each.name)).toList(), parts)) w,
      ];
    } else {
      found = whole.isNotEmpty ? whole : [for (final w in list) if (tidy(w.name) == tidy(key)) w];
    }
    if (found.length == 1) return found.single;
    if (found.isEmpty) throw ClaudeFolderProblem('No folder “$key”. list_folders shows them all.');
    throw ClaudeFolderProblem('More than one folder is “$key”: ${[for (final w in found) '“${_path(w.id)}” (${w.id})'].join(', ')}. Give its path or id.');
  }

  static bool _matches(List<String> path, List<String> parts) {
    if (path.length != parts.length) return false;
    for (var i = 0; i < path.length; i += 1) {
      if (path[i] != parts[i]) return false;
    }
    return true;
  }

  /// Answers [tool] with [input]: what it says back to Claude, as JSON. [notes] reads a note to check its id.
  /// Throws [ClaudeFolderProblem] for what it refuses.
  Future<({String said, String step})> answer(String tool, Map<String, Object?> input, ClaudeNotes notes) async {
    switch (tool) {
      case ClaudeFolderTool.list:
        final list = _list;
        return (said: jsonEncode({'count': list.length, 'folders': [for (final w in list) _brief(w)]}), step: 'Looked through the folders');
      case ClaudeFolderTool.create:
        final name = (input['name'] as String? ?? '').trim();
        if (name.isEmpty) throw const ClaudeFolderProblem('Give the folder a `name`.');
        final parentAsked = (input['parent'] as String?)?.trim();
        final parent = parentAsked == null || parentAsked.isEmpty ? null : resolve(parentAsked);
        final before = {for (final w in _list) w.id};
        final made = store.addWorkspace(name, 'ink', parent?.id);
        if (made == null) throw const ClaudeFolderProblem('Give the folder a `name`.');
        final fresh = !before.contains(made.id);
        return (
          said: jsonEncode({
            ..._brief(made),
            'made': fresh,
            if (!fresh && made.parent != parent?.id)
              'note': 'A personal folder of that name already exists at “${_path(made.id)}”, and Ghost.md keeps one of a name outside any parent; use it, move it with move_folder, or choose another name.',
          }),
          step: fresh ? 'Made the folder ${_path(made.id)}' : 'Found the folder ${_path(made.id)}',
        );
      case ClaudeFolderTool.rename:
        final folder = resolve(input['folder'] as String? ?? '');
        final name = (input['name'] as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (name.isEmpty) throw const ClaudeFolderProblem('Give the new `name`.');
        if (folder.org != null) throw ClaudeFolderProblem('“${folder.name}” is an organization’s own workspace: it is named after the organization, and is renamed there.');
        final clash = _list.where((w) => w.id != folder.id && w.parent == folder.parent && w.name.toLowerCase() == name.toLowerCase()).firstOrNull;
        if (clash != null) throw ClaudeFolderProblem('There is already a folder “${_path(clash.id)}” beside it. Choose another name, or file its notes there and delete this one.');
        final was = _path(folder.id);
        store.renameWorkspace(folder.id, name);
        return (said: jsonEncode({..._brief(_list.firstWhere((w) => w.id == folder.id)), 'was': was}), step: 'Renamed $was to $name');
      case ClaudeFolderTool.move:
        final folder = resolve(input['folder'] as String? ?? '');
        final parentAsked = (input['parent'] as String?)?.trim();
        final parent = parentAsked == null || parentAsked.isEmpty ? null : resolve(parentAsked);
        if (folder.org != null) throw ClaudeFolderProblem('“${folder.name}” is an organization’s own workspace, always at the top.');
        if (!store.canMove(folder.id, parent?.id)) {
          final from = store.orgOf(folder.id), to = parent == null ? null : store.orgOf(parent.id);
          if (parent != null && workspaceFamily(_list, folder.id).contains(parent.id)) {
            throw ClaudeFolderProblem('“${_path(parent.id)}” is “${_path(folder.id)}” or inside it: a folder cannot go inside itself.');
          }
          if (from != to) {
            throw ClaudeFolderProblem(from != null
                ? '“${_path(folder.id)}” is ${_orgName(folder.id)}’s, and moving it ${parent == null ? 'to the top' : 'there'} would take its notes from the team. It can go only inside ${_orgName(folder.id)}’s workspace or its folders.'
                : '“${_path(parent!.id)}” is in ${_orgName(parent.id)}, and moving a personal folder there would share its notes with the team. Only the person moves notes into an organization, from each note’s Workspace picker.');
          }
          throw ClaudeFolderProblem('“${_path(folder.id)}” cannot go there.');
        }
        final was = _path(folder.id);
        store.moveWorkspace(folder.id, parent?.id);
        return (said: jsonEncode({..._brief(_list.firstWhere((w) => w.id == folder.id)), 'was': was}), step: 'Moved $was to ${parent == null ? 'the top' : _path(parent.id)}');
      case ClaudeFolderTool.delete:
        final folder = resolve(input['folder'] as String? ?? '');
        if (folder.org != null) throw ClaudeFolderProblem('“${folder.name}” is an organization’s own workspace: it goes only when the person leaves the organization.');
        final path = _path(folder.id);
        final inside = [for (final w in _list) if (w.parent == folder.id) w.id];
        final filed = store.notesInWorkspace(folder.id);
        final shared = store.orgOf(folder.id) != null;
        // An organization's folder hands its notes to the folder above it first: unfiled, they would leave the team.
        if (shared && filed.isNotEmpty) store.fileNotes(filed, folder.parent);
        store.removeWorkspace(folder.id);
        final above = folder.parent == null ? null : _path(folder.parent!);
        return (
          said: jsonEncode({
            'deleted': path,
            'notes_moved': filed.length,
            'notes_now_in': shared ? above : null,
            'folders_moved_up': [for (final id in inside) _path(id)],
          }),
          step: 'Deleted the folder $path',
        );
      case ClaudeFolderTool.file:
        final ids = [for (final id in (input['ids'] as List? ?? const [])) if (id is String && id.trim().isNotEmpty) id.trim()];
        if (ids.isEmpty) throw const ClaudeFolderProblem('Give the notes’ `ids`.');
        final unfile = input['unfile'] == true;
        final asked = (input['folder'] as String?)?.trim();
        if (unfile == (asked != null && asked.isNotEmpty)) throw const ClaudeFolderProblem('Give a `folder`, or `unfile: true`, not both.');
        final to = unfile ? null : resolve(asked!);
        final toOrg = to == null ? null : store.orgOf(to.id);
        final filed = <Map<String, Object?>>[], refused = <Map<String, Object?>>[], missing = <String>[];
        for (final id in ids.toSet()) {
          final note = await notes.read(id: id);
          if (note == null) {
            missing.add(id);
            continue;
          }
          final from = store.workspaceOf(id);
          final fromOrg = from == null ? null : store.orgOf(from.id);
          if (fromOrg != toOrg) {
            refused.add({
              'id': id,
              'title': note.title,
              'why': fromOrg != null
                  ? 'It is ${_orgName(from!.id)}’s; ${to == null ? 'unfiling it' : 'filing it there'} would take it from the team. The person can move it from the note’s Workspace picker.'
                  : 'Filing it in ${_orgName(to!.id)} would share it with the team. The person can do that from the note’s Workspace picker.',
            });
            continue;
          }
          filed.add({'id': id, 'title': note.title, if (from != null) 'was': _path(from.id)});
        }
        if (filed.isNotEmpty) store.fileNotes([for (final note in filed) note['id']! as String], to?.id);
        if (filed.isEmpty && refused.isEmpty) throw ClaudeFolderProblem('No such notes: ${missing.join(', ')}. List or search to find their ids.');
        final where = to == null ? 'out of every folder' : 'in ${_path(to.id)}';
        return (
          said: jsonEncode({
            'folder': to == null ? null : _path(to.id),
            'filed': filed,
            if (refused.isNotEmpty) 'refused': refused,
            if (missing.isNotEmpty) 'missing': missing,
          }),
          step: filed.isEmpty
              ? 'Left ${refused.length == 1 ? 'a note' : '${refused.length} notes'} where ${refused.length == 1 ? 'it was' : 'they were'}: moving them would cross an organization'
              : 'Filed ${filed.length == 1 ? filed.single['title'] : '${filed.length} notes'} $where',
        );
    }
    throw ClaudeFolderProblem('There is no tool called $tool.');
  }
}
