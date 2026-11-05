/// What a press on Wrapped's review does (docs/WRAPPED.md, "The review"), and how each is taken back. Nothing here
/// runs but from a press.
///
/// Every change goes through the paths the app's own edits take, so it syncs, keeps its versions and counts as an
/// edit:
/// - **A to-do checked off or removed**: the note read again, the line found where it is now, the note written over
///   the revision just read ([NoteLibrary.update]), and counted as an edit (`trackNoteEdited`). Several in one note are
///   one write.
/// - **A stale note archived** ([NoteLibrary.archive]) or **put in the Trash** ([Trash.trashNote]), never deleted.
/// - **A suggestion applied** by Cleanup's own apply (lib/plugins/cleanup/apply.dart `applyCleanup`): a move by the
///   drag's own move, checked and read back; a merge written over the revision read, the copies to the Trash; a link
///   as a `Related:` line. A note filed in no folder is moved by the same drag's move (`moveCarried`), which Cleanup
///   never meets, and a new folder at the top is made first, since Cleanup's are made inside the folder it cleans.
///
/// Each press is recorded as Cleanup records a run ([CleanupRecord]), and Undo takes it back whole: the words written
/// back over the revision the press left (a note changed since is left and named), out of the Archive, out of the
/// Trash, back to its folder (or to none), and a folder it made removed while nothing is in it ([undoWrapped]).
library;

import 'dart:math';

import '../../core/library.dart';
import '../../core/metrics.dart' show trackNoteEdited;
import '../../core/note_text.dart' show noteTitle;
import '../../core/trash.dart';
import '../../core/workspaces.dart';
import '../../notes/folder_drag.dart' show FolderCarry, moveCarried;
import '../cleanup/apply.dart' show CleanupUndone, applyCleanup, undoCleanup;
import '../cleanup/plan.dart';
import '../cleanup/records.dart';
import '../cleanup/text.dart' show withRelated;
import 'state.dart';
import 'todos.dart';

/// What a press did, for the review's line and the analytics.
enum WrappedActionKind {
  checkOff('check_off'),
  removeTodo('remove_todo'),
  keep('keep'),
  archive('archive'),
  trash('trash'),
  later('later'),
  move('move'),
  merge('merge'),
  link('link'),
  superseded('superseded'),
  notConflict('not_conflict'),
  dismiss('dismiss'),
  undo('undo'),
  share('share');

  const WrappedActionKind(this.wire);

  /// Its word in the analytics (lib/core/metrics.dart `wrappedActionKinds`).
  final String wire;
}

/// What applying came to: the record to keep for Undo (null where nothing changed), how many were done, and each one
/// not done, with why.
class WrappedDone {
  WrappedDone({this.record, this.done = 0, this.skipped = const []});
  final CleanupRecord? record;
  final int done;
  final List<String> skipped;
}

final Random _random = Random();

String _named(String title) => title.trim().isEmpty ? '“Untitled”' : (title.length > 40 ? '“${title.substring(0, 38)}…”' : '“${title.trim()}”');

/// The library, the folders and the Trash every press goes through.
class WrappedEditing {
  WrappedEditing({required this.library, required this.workspaces, required this.trash, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final NoteLibrary library;
  final WorkspaceStore workspaces;
  final Trash trash;
  final DateTime Function() _clock;

  CleanupRecord _record(List<CleanupChange> changes, String what) => CleanupRecord(
        id: 'wrapped-${_clock().microsecondsSinceEpoch.toRadixString(36)}-${_random.nextInt(1 << 30).toRadixString(36)}',
        at: _clock(),
        folderId: '',
        folderPath: what,
        aiName: 'Wrapped',
        changes: changes,
      );

  /// [todos] each checked off ([remove] false) or taken out of its note: one write a note.
  Future<WrappedDone> todos(List<WrappedTodo> todos, {required bool remove}) async {
    final byNote = <String, List<WrappedTodo>>{};
    for (final todo in todos) {
      (byNote[todo.noteId] ??= []).add(todo);
    }
    final changes = <CleanupChange>[];
    final skipped = <String>[];
    var done = 0;
    for (final MapEntry(key: id, value: these) in byNote.entries) {
      final fresh = await library.get(id);
      if (fresh == null || trashedNote(fresh, trash.value)) {
        skipped.add('${_named('')}: the note is gone or in the Trash');
        continue;
      }
      final body = remove ? withoutTodos(fresh.body, these) : checkedOff(fresh.body, these);
      if (body == null) {
        skipped.add('${_named(noteTitle(fresh.body))}: the to-do isn’t there any more');
        continue;
      }
      try {
        final after = await library.update(id, body, fresh.revision);
        trackNoteEdited(id);
        changes.add(CleanupChange.body(id, before: fresh.body, after: body, revision: after.revision));
        done += these.where((t) => lineOfTodo(fresh.body, t) != null).length;
      } catch (failure) {
        skipped.add('${_named(noteTitle(fresh.body))}: $failure');
      }
    }
    return WrappedDone(record: changes.isEmpty ? null : _record(changes, remove ? 'To-dos removed' : 'To-dos checked off'), done: done, skipped: skipped);
  }

  /// [ids] each into the Archive ([toTrash] false) or the Trash.
  Future<WrappedDone> stale(List<String> ids, {required bool toTrash}) async {
    final changes = <CleanupChange>[];
    final skipped = <String>[];
    for (final id in ids) {
      final fresh = await library.get(id);
      if (fresh == null || trashedNote(fresh, trash.value)) {
        skipped.add('a note is gone or already in the Trash');
        continue;
      }
      if (toTrash) {
        trash.trashNote(id);
        changes.add(CleanupChange.trash(id));
      } else {
        if (fresh.archivedAt != null && fresh.archivedAt != 0) continue;
        try {
          await library.archive(id, archived: true);
          changes.add(CleanupChange.archive(id));
        } catch (failure) {
          skipped.add('${_named(noteTitle(fresh.body))}: $failure');
        }
      }
    }
    return WrappedDone(record: changes.isEmpty ? null : _record(changes, toTrash ? 'Put in the Trash' : 'Archived'), done: changes.length, skipped: skipped);
  }

  /// The scope Cleanup's apply reads [ids] in: the person's own folders, the notes as they read now.
  Future<CleanupScope> _scope(Iterable<String> ids) async {
    final spaces = workspaces.value;
    final personal = [for (final w in spaces.list) if (workspaces.orgOf(w.id) == null) w];
    final notes = <CleanupNote>[];
    for (final id in ids.toSet()) {
      final note = await library.get(id);
      if (note == null || trashedNote(note, trash.value)) continue;
      notes.add(CleanupNote(id: id, title: noteTitle(note.body), body: note.body, revision: note.revision, folderId: spaces.of[id] ?? '', updatedAt: note.updatedAt));
    }
    return CleanupScope(
      rootId: '',
      org: null,
      folders: [
        const CleanupFolder(id: '', name: 'Your notes', parent: null, path: 'Your notes', depth: 0),
        for (final w in personal) CleanupFolder(id: w.id, name: w.name, parent: w.parent, path: workspacePathName(spaces.list, w.id), depth: 1),
      ],
      notes: notes,
    );
  }

  /// [s] applied (see the library doc).
  Future<WrappedDone> suggestion(WrappedSuggestion s) async {
    final skipped = <String>[];
    final changes = <CleanupChange>[];
    var done = 0;
    // Only the person's own notes, and only their own folders.
    for (final id in s.notes) {
      final at = workspaces.workspaceOf(id)?.id;
      if (at != null && workspaces.orgOf(at) != null) return WrappedDone(skipped: ['a note is an organization’s now']);
    }
    String? to = s.folderId;
    if (s.kind == SuggestionKind.newFolder) {
      final name = s.folderName ?? '';
      final parent = s.parentId;
      if (parent != null && !workspaces.value.list.any((w) => w.id == parent)) return WrappedDone(skipped: ['the folder it would go in is gone']);
      final had = {for (final w in workspaces.value.list) w.id};
      final made = workspaces.value.list.where((w) => w.parent == parent && w.name.trim().toLowerCase() == name.trim().toLowerCase()).firstOrNull ?? workspaces.addWorkspace(name, 'ink', parent);
      if (made == null) return WrappedDone(skipped: ['the folder $name could not be made']);
      if (!had.contains(made.id)) changes.add(CleanupChange.folder(made.id, workspacePathName(workspaces.value.list, made.id)));
      to = made.id;
    }
    if ((s.kind == SuggestionKind.move || s.kind == SuggestionKind.newFolder) && (to == null || workspaces.orgOf(to) != null || !workspaces.value.list.any((w) => w.id == to))) {
      return WrappedDone(skipped: ['the folder is gone']);
    }
    final scope = await _scope(s.notes);
    final items = <CleanupItem>[];
    switch (s.kind) {
      case SuggestionKind.move || SuggestionKind.newFolder:
        for (final id in s.notes) {
          final note = scope.note(id);
          if (note == null) {
            skipped.add('a note is gone or in the Trash');
            continue;
          }
          if (note.folderId == to) continue;
          if (note.folderId.isEmpty) {
            // Filed nowhere: the drag's own move, which Cleanup never meets.
            if (moveCarried(workspaces, FolderCarry.note(id, note.title), to) == null || workspaces.workspaceOf(id)?.id != to) {
              skipped.add('${_named(note.title)} can’t go there');
              continue;
            }
            changes.add(CleanupChange.move(id, from: null, to: to!));
            done += 1;
          } else {
            items.add(MoveItem(noteId: id, from: note.folderId, to: to!, why: s.why));
          }
        }
      case SuggestionKind.merge:
        items.add(MergeItem(keepId: s.notes.first, others: s.notes.sublist(1), why: s.why));
      case SuggestionKind.link:
        final from = scope.note(s.notes.first), target = scope.note(s.notes.last);
        if (from == null || target == null || target.title.trim().isEmpty) return WrappedDone(skipped: ['a note is gone or in the Trash']);
        final after = withRelated(from.body, [target.title.trim()]);
        if (after != from.body) items.add(EditItem(noteId: from.id, pass: CleanupPass.links, before: from.body, after: after, why: s.why, links: [target.title.trim()]));
    }
    if (items.isNotEmpty) {
      final plan = CleanupPlan(scope: scope, options: const CleanupOptions(passes: {CleanupPass.sort, CleanupPass.duplicates, CleanupPass.links}), items: items);
      final applied = await applyCleanup(plan: plan, ticked: {for (final i in items) i.id}, library: library, workspaces: workspaces, trash: trash, aiName: 'Wrapped', now: _clock());
      changes.addAll(applied.record.changes);
      skipped.addAll([...applied.skipped, ...applied.misplaced]);
      done += applied.applied;
      for (final change in applied.record.changes) {
        if (change.kind == CleanupChangeKind.body) trackNoteEdited(change.note!);
      }
    }
    final what = switch (s.kind) { SuggestionKind.merge => 'Merged', SuggestionKind.link => 'Linked', _ => 'Moved' };
    return WrappedDone(record: changes.isEmpty ? null : _record(changes, what), done: done, skipped: skipped);
  }

  /// [record] taken back (see the library doc): a note moved from no folder is filed in none again, the rest by
  /// Cleanup's own undo.
  Future<CleanupUndone> undo(CleanupRecord record) async {
    var undone = 0;
    final left = <String>[];
    final rest = <CleanupChange>[];
    for (final change in record.changes) {
      if (change.kind == CleanupChangeKind.move && change.from == null) {
        if (workspaces.workspaceOf(change.note!)?.id != change.to) {
          left.add('a note was moved again since');
          continue;
        }
        workspaces.fileNote(change.note!, null);
        undone += 1;
      } else {
        rest.add(change);
      }
    }
    final back = await undoCleanup(record: CleanupRecord(id: record.id, at: record.at, folderId: record.folderId, folderPath: record.folderPath, aiName: record.aiName, changes: rest), library: library, workspaces: workspaces, trash: trash);
    for (final change in rest) {
      if (change.kind == CleanupChangeKind.body) trackNoteEdited(change.note!);
    }
    return CleanupUndone(undone: undone + back.undone, left: [...left, ...back.left]);
  }
}

/// [record] marked taken back, for the state's list.
CleanupRecord undoneRecord(CleanupRecord record) =>
    CleanupRecord(id: record.id, at: record.at, folderId: record.folderId, folderPath: record.folderPath, aiName: record.aiName, changes: record.changes, misplaced: record.misplaced, undone: true);
