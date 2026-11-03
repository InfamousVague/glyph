/// The ticked suggestions applied, checked and recorded, and a whole run taken back (docs/CLEANUP.md, "Applying" and
/// "Undo and the record"; Matt, 2026-11-02).
///
/// The rules, each a test (test/plugins/cleanup/apply_test.dart):
/// - **Over the revision that was read.** Every note is read again first; one changed since the plan, gone, or in the
///   Trash is skipped and named, never written over. A note's changes (tidy, title, tags and links, a merge into it)
///   are one write.
/// - **Nothing deleted.** A merged-away note goes to the Trash ([Trash.trashNote]); a stale one to the Archive.
/// - **An organization's notes stay in it.** A move is made by the drag's own move (lib/notes/folder_drag.dart
///   `moveCarried`) and only where `folderVerdict` says it simply moves: same organization, or none. Never one that
///   asks, never to the top. The target must be in the scope's organization too.
/// - **Verified by reading back.** Each moved note is read again: there, out of the Trash, filed where the plan said,
///   in the same organization. Each written note must read back as written. What is not is [CleanupApplied.misplaced],
///   never counted as done.
/// - **Recorded**, so the run can be taken back in one action ([undoCleanup]), now or later.
library;

import 'dart:async';
import 'dart:math';

import '../../core/library.dart';
import '../../core/note_text.dart' show noteTitle;
import '../../core/workspaces.dart';
import '../../core/trash.dart';
import '../../notes/folder_drag.dart' show FolderCarry, FolderLanding, folderVerdict, moveCarried;
import 'plan.dart';
import 'records.dart';
import 'text.dart';

/// What applying came to.
class CleanupApplied {
  CleanupApplied({required this.record, required this.applied, required this.skipped, required this.misplaced});

  /// What was done, kept for Undo.
  final CleanupRecord record;

  /// How many ticked items were applied.
  final int applied;

  /// Each ticked item not applied, and why: "“Plan” changed since the plan was made".
  final List<String> skipped;

  /// Each note that is not where the plan said once applied, read back: "“Plan” is not in Work › Clients".
  final List<String> misplaced;
}

/// A run's id's tail, so two runs in one instant (or on two devices sharing the Library) are two records.
final Random _random = Random();

/// What a note's title is, for the words said about it.
String _named(String title) => title.trim().isEmpty ? 'Untitled' : (title.length > 40 ? '“${title.substring(0, 38)}…”' : '“${title.trim()}”');

/// Applies the items of [plan] whose ids are in [ticked] (see the library doc), as [library], [workspaces] and
/// [trash] have them. [aiName] and [now] are for the record.
Future<CleanupApplied> applyCleanup({
  required CleanupPlan plan,
  required Set<String> ticked,
  required NoteLibrary library,
  required WorkspaceStore workspaces,
  required Trash trash,
  required String aiName,
  required DateTime now,
}) async {
  final scope = plan.scope;
  final items = [for (final item in plan.items) if (ticked.contains(item.id)) item];
  final changes = <CleanupChange>[];
  final skipped = <String>[];
  final misplaced = <String>[];
  var applied = 0;
  String titleOf(String id) => scope.note(id)?.title ?? '';

  // ---- new folders: only those a ticked move goes into.
  final made = <String, String>{}; // NewFolderItem.id → the folder's id
  final movesInto = {for (final item in items) if (item is MoveItem && item.intoNew) item.to};
  for (final item in items.whereType<NewFolderItem>()) {
    if (!movesInto.contains(item.id)) continue;
    if (!workspaces.value.list.any((w) => w.id == item.parentId)) {
      skipped.add('the folder ${item.name}: ${scope.pathOf(item.parentId)} is gone');
      continue;
    }
    final had = {for (final w in workspaces.value.list) w.id};
    final folder = workspaces.addWorkspace(item.name, 'ink', item.parentId);
    if (folder == null || workspaces.orgOf(folder.id) != scope.org) {
      skipped.add('the folder ${item.name}: it could not be made there');
      continue;
    }
    made[item.id] = folder.id;
    if (!had.contains(folder.id)) changes.add(CleanupChange.folder(folder.id, workspacePathName(workspaces.value.list, folder.id)));
    applied += 1;
  }

  // ---- the notes' words: one write a note.
  final tidy = {for (final i in items.whereType<EditItem>()) if (i.pass == CleanupPass.tidy) i.noteId: i};
  final links = {for (final i in items.whereType<EditItem>()) if (i.pass == CleanupPass.links) i.noteId: i};
  final titles = {for (final i in items.whereType<TitleItem>()) i.noteId: i};
  // No merge in an organization's folders, whoever made the plan (plan.dart `optionsFor`): a team note put in this
  // member's Trash would stay every other member's.
  final merges = {
    for (final i in items.whereType<MergeItem>())
      if (scope.org == null) i.keepId: i,
  };
  if (scope.org != null) {
    for (final i in items.whereType<MergeItem>()) {
      skipped.add('the merge into ${_named(titleOf(i.keepId))}: merges are not made in an organization’s folders');
    }
  }
  final trashed = <String>{};
  final written = <String>{};
  for (final id in {...tidy.keys, ...titles.keys, ...links.keys, ...merges.keys}) {
    final read = scope.note(id);
    final count = [tidy[id], titles[id], links[id], merges[id]].whereType<CleanupItem>().length;
    final fresh = await library.get(id);
    if (read == null || fresh == null || trashedNote(fresh, trash.value)) {
      skipped.add('$count ${count == 1 ? 'change' : 'changes'} to ${_named(titleOf(id))}: it is gone or in the Trash');
      continue;
    }
    if (fresh.revision != read.revision || fresh.body != read.body) {
      skipped.add('$count ${count == 1 ? 'change' : 'changes'} to ${_named(read.title)}: it changed since the plan was made');
      continue;
    }
    var body = tidy[id]?.after ?? fresh.body;
    if (titles[id] case final title?) body = titledBody(body, title.to);
    if (links[id] case final link?) body = withRelated(withTags(body, link.tags), link.links);
    final merge = merges[id];
    final others = <String>[];
    if (merge != null) {
      final bodies = <({String title, String body})>[];
      var whole = true;
      for (final other in merge.others) {
        final was = scope.note(other);
        final now = await library.get(other);
        if (was == null || now == null || trashedNote(now, trash.value) || now.revision != was.revision || now.body != was.body) {
          whole = false;
          break;
        }
        bodies.add((title: was.title, body: now.body));
      }
      if (whole) {
        body = mergedBody(body, bodies).body;
        others.addAll(merge.others);
      } else {
        skipped.add('the merge into ${_named(read.title)}: a copy changed since the plan was made');
      }
    }
    if (body == fresh.body && others.isEmpty) continue;
    try {
      final after = body == fresh.body ? fresh : await library.update(id, body, fresh.revision);
      if (body != fresh.body) {
        changes.add(CleanupChange.body(id, before: fresh.body, after: body, revision: after.revision));
        written.add(id);
      }
      applied += count - (merge != null && others.isEmpty ? 1 : 0);
      // The copies go to the Trash only once their lines are safe in the kept note.
      for (final other in others) {
        trash.trashNote(other);
        trashed.add(other);
        changes.add(CleanupChange.trash(other));
      }
    } catch (failure) {
      skipped.add('$count ${count == 1 ? 'change' : 'changes'} to ${_named(read.title)}: $failure');
    }
  }

  // ---- stale notes into the Archive.
  for (final item in items.whereType<ArchiveItem>()) {
    final fresh = await library.get(item.noteId);
    if (fresh == null || trashedNote(fresh, trash.value) || trashed.contains(item.noteId)) {
      skipped.add('the archive of ${_named(titleOf(item.noteId))}: it is gone or in the Trash');
      continue;
    }
    if (fresh.archivedAt != null && fresh.archivedAt != 0) continue;
    try {
      await library.archive(item.noteId, archived: true);
      changes.add(CleanupChange.archive(item.noteId));
      applied += 1;
    } catch (failure) {
      skipped.add('the archive of ${_named(titleOf(item.noteId))}: $failure');
    }
  }

  // ---- moves, last, so each note is checked where it ends.
  final moved = <({String note, String to})>[];
  for (final item in items.whereType<MoveItem>()) {
    final to = item.intoNew ? made[item.to] : item.to;
    final title = titleOf(item.noteId);
    if (to == null) {
      skipped.add('the move of ${_named(title)}: its new folder was not made');
      continue;
    }
    if (trashed.contains(item.noteId)) continue;
    final fresh = await library.get(item.noteId);
    if (fresh == null || trashedNote(fresh, trash.value)) {
      skipped.add('the move of ${_named(title)}: it is gone or in the Trash');
      continue;
    }
    final from = workspaces.workspaceOf(item.noteId)?.id;
    if (from != item.from) {
      skipped.add('the move of ${_named(title)}: it was moved since the plan was made');
      continue;
    }
    // An organization's note stays in it, a personal one stays personal: the scope's organization, both ends.
    if (workspaces.orgOf(to) != scope.org || (from != null && workspaces.orgOf(from) != scope.org)) {
      skipped.add('the move of ${_named(title)}: it would leave ${scope.org == null ? 'your own notes' : 'the organization'}');
      continue;
    }
    final carry = FolderCarry.note(item.noteId, title);
    if (folderVerdict(workspaces, carry, to).landing != FolderLanding.moves || moveCarried(workspaces, carry, to) == null) {
      skipped.add('the move of ${_named(title)}: it can’t go to ${workspacePathName(workspaces.value.list, to)}');
      continue;
    }
    changes.add(CleanupChange.move(item.noteId, from: from, to: to));
    moved.add((note: item.noteId, to: to));
    applied += 1;
  }

  // ---- read back: every move where the plan said, every write as written.
  for (final move in moved) {
    final title = titleOf(move.note);
    final fresh = await library.get(move.note);
    final at = workspaces.workspaceOf(move.note)?.id;
    final where = workspacePathName(workspaces.value.list, move.to);
    if (fresh == null) {
      misplaced.add('${_named(title)} can’t be read after its move to $where');
    } else if (trashedNote(fresh, trash.value)) {
      misplaced.add('${_named(title)} is in the Trash, not in $where');
    } else if (at != move.to) {
      misplaced.add('${_named(title)} is not in $where${at == null ? '' : ' (it is in ${workspacePathName(workspaces.value.list, at)})'}');
    } else if (workspaces.orgOf(move.to) != scope.org) {
      misplaced.add('${_named(title)} is no longer in the same organization');
    }
  }
  for (final change in changes.where((c) => c.kind == CleanupChangeKind.body)) {
    final fresh = await library.get(change.note!);
    if (fresh == null || fresh.body != change.after) misplaced.add('${_named(titleOf(change.note!))} doesn’t read back as it was written');
  }
  for (final id in trashed) {
    if (!trash.isTrashed(id)) misplaced.add('${_named(titleOf(id))} didn’t go to the Trash');
  }

  final record = CleanupRecord(
    id: 'cleanup-${now.microsecondsSinceEpoch.toRadixString(36)}-${_random.nextInt(1 << 30).toRadixString(36)}',
    at: now,
    folderId: scope.rootId,
    folderPath: scope.root.path,
    aiName: aiName,
    changes: changes,
    org: scope.org,
    misplaced: misplaced,
  );
  return CleanupApplied(record: record, applied: applied, skipped: skipped, misplaced: misplaced);
}

/// What taking a run back came to: how many changes went back, and each left as it is, with why.
class CleanupUndone {
  CleanupUndone({required this.undone, required this.left});
  final int undone;
  final List<String> left;
}

/// Takes [record] back, the last change first (docs/CLEANUP.md, "Undo and the record"): each move back where it was
/// (by the same move, within the same organization), each archive out, each note out of the Trash, each body written
/// back over the revision the run left (a note changed since is left as it is and named), each folder the run made
/// removed if nothing is filed in it and nothing is inside it.
Future<CleanupUndone> undoCleanup({required CleanupRecord record, required NoteLibrary library, required WorkspaceStore workspaces, required Trash trash}) async {
  var undone = 0;
  final left = <String>[];
  String titleOf(String id) {
    final body = library.noteOf(id)?.body;
    return body == null ? id : _named(noteTitle(body));
  }

  for (final change in record.changes.reversed) {
    switch (change.kind) {
      case CleanupChangeKind.move:
        final note = change.note!;
        if (workspaces.workspaceOf(note)?.id != change.to) {
          left.add('${titleOf(note)} was moved again since');
          continue;
        }
        final title = library.noteOf(note) == null ? '' : noteTitle(library.noteOf(note)!.body);
        // Back by the same move, which keeps it in the organization it is in; a note the run found filed nowhere
        // was never moved by it.
        if (change.from == null || moveCarried(workspaces, FolderCarry.note(note, title), change.from) == null) {
          left.add('${titleOf(note)} can’t go back${change.from == null ? '' : ' to ${workspacePathName(workspaces.value.list, change.from!)}'}');
          continue;
        }
        undone += 1;
      case CleanupChangeKind.archive:
        try {
          await library.archive(change.note!, archived: false);
          undone += 1;
        } catch (failure) {
          left.add('${titleOf(change.note!)}: $failure');
        }
      case CleanupChangeKind.trash:
        if (trash.isTrashed(change.note!)) {
          trash.restoreNote(change.note!);
          undone += 1;
        }
      case CleanupChangeKind.body:
        final note = change.note!;
        final fresh = await library.get(note);
        if (fresh == null) {
          left.add('${titleOf(note)} is gone');
          continue;
        }
        if (fresh.revision != change.revision || fresh.body != change.after) {
          left.add('${_named(noteTitle(fresh.body))} changed since, so its words are left as they are');
          continue;
        }
        try {
          await library.update(note, change.before!, fresh.revision);
          undone += 1;
        } catch (failure) {
          left.add('${_named(noteTitle(fresh.body))}: $failure');
        }
      case CleanupChangeKind.folder:
        final id = change.folder!;
        final spaces = workspaces.value;
        if (!spaces.list.any((w) => w.id == id)) continue;
        final holds = spaces.of.values.contains(id) || spaces.list.any((w) => w.parent == id);
        if (holds) {
          left.add('the folder ${change.path ?? ''} stays: something is in it');
          continue;
        }
        workspaces.removeWorkspace(id);
        undone += 1;
    }
  }
  return CleanupUndone(undone: undone, left: left);
}
