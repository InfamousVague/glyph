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
///   [WorkspaceStore] over a [WorkspaceStorage], which is in memory until the preferences and the library arrive, so
///   a test or a screen makes its own. The function names are the web's, as methods.
/// - A note's file does not follow its filing yet (`core/noteFolders.ts`), and `deleteWorkspace`'s trash is the
///   library's to port.
/// - The move of a set kept under the old `glyph-workspaces` key into the preferences is the web's own history and
///   is not carried.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

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

/// Whether a workspace is an organization's: the id's prefix, which is the truth.
bool isOrgWorkspace(String workspaceId) => orgIdOf(workspaceId) != null;

/// A workspace (`Workspace`).
@immutable
class Workspace {
  const Workspace({required this.id, required this.name, this.hue});

  /// A workspace as it is kept, with a hue this build does not know, and ink, read as none.
  factory Workspace.kept({required String id, required String name, Object? hue}) => Workspace(id: id, name: name, hue: _wornHue(hue));

  final String id;
  final String name;

  /// Its colour, worn by its pill and its tag on a note. Null is `ink`, the app's own.
  final String? hue;

  /// The organization it stands for, by id; null for a personal one. Read from the id, never kept.
  String? get org => orgIdOf(id);

  @override
  bool operator ==(Object other) => other is Workspace && other.id == id && other.name == name && other.hue == hue;

  @override
  int get hashCode => Object.hash(id, name, hue);

  @override
  String toString() => 'Workspace($id, $name${hue == null ? '' : ', $hue'})';
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

/// The workspaces, and everything done to them. Listen to it as a [ValueListenable]: its value is the same snapshot
/// until something changes, and each change tells its listeners once.
class WorkspaceStore extends ChangeNotifier implements ValueListenable<Workspaces> {
  WorkspaceStore({WorkspaceStorage? storage, Random? random})
      : _storage = storage ?? MemoryWorkspaceStorage(),
        _random = random ?? Random();

  final WorkspaceStorage _storage;
  final Random _random;
  WorkspaceSheet? _sheet;
  Workspaces? _snapshot;

  WorkspaceSheet _read() {
    final held = _storage.read();
    final list = [for (final w in held.list) Workspace.kept(id: w.id, name: w.name, hue: w.hue)];
    final ids = {for (final w in list) w.id};
    // The filings that point at one of the list's workspaces.
    final notes = {
      for (final entry in held.notes.entries)
        if (ids.contains(entry.value)) entry.key: entry.value,
    };
    return WorkspaceSheet(list: list, notes: notes, current: held.current != null && ids.contains(held.current) ? held.current : null);
  }

  WorkspaceSheet get _current => _sheet ??= _read();

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

  /// A new workspace called [name], in [hue], or the personal one already called that; null for an empty name. An
  /// organization's workspace of that name is not the one.
  Workspace? addWorkspace(String name, [String hue = 'ink']) {
    final clean = _tidy(name);
    if (clean.isEmpty) return null;
    final sheet = _current;
    for (final w in sheet.list) {
      if (!isOrgWorkspace(w.id) && w.name.toLowerCase() == clean.toLowerCase()) return w;
    }
    final made = Workspace(id: _freshId(sheet.list), name: clean, hue: _wornHue(hue));
    _write(WorkspaceSheet(list: [...sheet.list, made], notes: sheet.notes, current: sheet.current));
    return made;
  }

  /// That workspace in [hue]; `ink` takes its colour off again. Unknown workspace, unknown hue, or an organization's
  /// workspace: nothing happens.
  void setWorkspaceHue(String id, String hue) {
    final sheet = _current;
    if (!_isHue(hue) || !sheet.list.any((w) => w.id == id) || isOrgWorkspace(id)) return;
    _write(WorkspaceSheet(
      list: [for (final w in sheet.list) w.id == id ? Workspace(id: w.id, name: w.name, hue: _wornHue(hue)) : w],
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
    if (clean.isEmpty || !sheet.list.any((w) => w.id == id)) return;
    _write(WorkspaceSheet(
      list: [for (final w in sheet.list) w.id == id ? Workspace(id: w.id, name: clean, hue: w.hue) : w],
      notes: sheet.notes,
      current: sheet.current,
    ));
  }

  /// Removes the workspace; its notes are simply not filed any more, and the list shows all notes if it was chosen.
  /// Not an organization's, which goes when the person leaves it.
  void removeWorkspace(String id) {
    if (isOrgWorkspace(id)) return;
    _remove(id);
  }

  void _remove(String id) {
    final sheet = _current;
    if (!sheet.list.any((w) => w.id == id)) return;
    _write(WorkspaceSheet(
      list: [for (final w in sheet.list) if (w.id != id) w],
      notes: {
        for (final entry in sheet.notes.entries)
          if (entry.value != id) entry.key: entry.value,
      },
      current: sheet.current == id ? null : sheet.current,
    ));
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

  /// The organization's workspace gone, as when the person leaves it: its notes are unfiled, never deleted.
  void dropOrgWorkspace(String orgId) => _remove(orgWorkspaceId(orgId));

  /// Files [noteId] in a workspace, or in none with null.
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

  /// Of [notes], those filed in workspace [id]; all of them for null. [idOf] reads a note's id.
  List<T> inWorkspace<T>(Iterable<T> notes, String? id, String Function(T note) idOf) {
    if (id == null) return [...notes];
    final filed = _current.notes;
    return [for (final note in notes) if (filed[idOf(note)] == id) note];
  }
}
