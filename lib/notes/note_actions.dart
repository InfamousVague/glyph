/// Pin, archive, delete and the trash, each undoable. A port of `src/app/notes/useNoteActions.ts`, over a
/// [NoteLibrary], a [Trash] and a [WorkspaceStore].
///
/// Deleting a note puts it in the trash (lib/core/trash.dart; Matt: "Send deleted notes to a trash folder where we
/// can empty it to perma delete notes or restore notes"), which is a flag and so undone by clearing it. Only the
/// trash deletes for good: one note from it ([NoteActions.destroy]), or all of it ([NoteActions.emptyTrash]).
///
/// EMPTYING A FULL TRASH IS A JOB (Matt, 2026-11-02, with some 1,300 notes in his after a cleanup: "paginate the trash
/// and add a 'delete forever' button at the top"): the notes go [NoteActions.emptyBatch] at a time, the frame given a
/// turn between batches, their filing and the trash's record let go once a batch rather than once a note, and the
/// run is on the Activity tray's record (lib/core/background_jobs.dart, [NoteActions.emptyJobId]) with how far it is
/// and a Stop, which leaves the rest in the Trash.
///
/// DELETING FOR GOOD IS DEFERRED, not done and then undone. Undoing a real delete would mean saving the note again,
/// which gives it a new `createdAt` and loses its pin; so a deleted note is hidden at once and removed from the
/// library only when its Undo runs out. The removal is also forced the moment anything could outlive the toast: a
/// second delete, the app going to the background, a capture starting over the list ([NoteActions.flushDeletes]),
/// and these actions being disposed of.
///
/// Archive and pin are real at once: they are flags, not edits, and undoing one is setting it back.
///
/// A folder deleted with everything in it ([NoteActions.deleteFolder]; Matt, 2026-11-01) is every note under it put
/// in the trash at once with one Undo that also puts the folders back; an organization's is deleted for every member,
/// with none, since a team's deletes skip the Trash.
///
/// What differs:
/// - The hook is a class, [NoteActions], which can be listened to for [NoteActions.hidden] (the hook's state). Its
///   toasts go through [NoteActions.say], so it holds no `BuildContext`; [NoteActions.toaster] makes one from the
///   kit's toast.
/// - **What the app keeps beside a note** (its gist, its AI runs and marks, its summary and the job to write one, a
///   tag waiting to say where it was written: `forgetKept`) is not ported, so only its filing in a workspace is let
///   go here, and the rest is [NoteActions.onForget] for whoever brings those.
/// - **A meeting's write-up** (cancelled as the meeting goes in the trash, asked for again as it comes out:
///   `resumeWriteUp`, `cancelWriteUpOnHost`) waits for the recorder: [NoteActions.onTrashed] and
///   [NoteActions.onRestored] are where it goes.
/// - **Without a [Trash]** the delete is what the home page did before there was one (lib/home/library_home.dart):
///   the note is taken out of the library, and Undo puts it back where it was with its workspace. The words in the
///   toast are the web's either way.
/// - A pin and an archive are asked for and not waited on, where the web's handlers await them before the haptic
///   and the toast; the list is read again once the library has answered, as there. Deleting for good is
///   [NoteLibrary.destroy], awaited, as the web awaits `deleteNote`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/background_jobs.dart';
import '../core/note.dart';
import '../core/note_folders.dart' show folderFor;
import '../core/note_text.dart';
import '../core/sample_library.dart';
import '../core/swipe.dart';
import '../core/trash.dart';
import '../core/workspaces.dart';

/// How long an Undo is offered (`UNDO_MS`).
const Duration noteUndo = Duration(milliseconds: 5000);

/// A note as a toast names it (`label`): its title in quotes, or "the note" where it has none or a long one. A long
/// title is not cut short with an ellipsis: it is simply not named.
String noteLabel(Note note) {
  final title = noteTitle(note.body);
  return title.isNotEmpty && title.length <= 28 ? '“$title”' : 'the note';
}

/// `capitalise` (core/text.ts): the first letter in upper case.
String _capitalise(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// What an action says in a toast: its words, how long they stand, and its Undo where it has one.
@immutable
class NoteToast {
  const NoteToast(this.message, {this.duration, this.undo});

  final String message;

  /// How long the toast stands; the kit's own time where null.
  final Duration? duration;

  /// What its Undo does; no action on the toast where null.
  final VoidCallback? undo;
}

/// Star, archive, delete and the trash, each undoable (`useNoteActions`, src/app/notes/useNoteActions.ts). See the
/// library doc for what differs: the meeting's write-up and what is kept beside a note are callbacks, and with no
/// [trash] a delete takes the note out of the library.
class NoteActions extends ChangeNotifier with WidgetsBindingObserver {
  NoteActions({required this.library, required this.workspaces, this.trash, required this.say, this.haptic, this.onForget, this.onTrashed, this.onRestored, this.onFoldersGone});

  final NoteLibrary library;
  final WorkspaceStore workspaces;

  /// Where a deleted note waits. Without one a delete takes the note out of the library (see the library doc).
  final Trash? trash;

  /// Shows a toast (`useToast().toast`).
  final void Function(NoteToast toast) say;

  /// The phone's buzz (`fireNativeHaptic`); none where null.
  final HapticFn? haptic;

  /// A note deleted for good: let go of whatever else is kept about it (`forgetKept`, less its filing).
  final ValueChanged<String>? onForget;

  /// A note gone into the trash: a meeting's write-up stops, a tag waiting for it is dropped.
  final ValueChanged<Note>? onTrashed;

  /// A note out of the trash, by Restore or by Undo: a meeting's write-up is asked for again (`resumeWriteUp`).
  final ValueChanged<Note>? onRestored;

  /// A folder deleted with its notes for good (its Undo run out, or none to wait for): its directories, as the
  /// library names them, the deepest first, to be taken off the disk once empty (lib/core/folder_dirs.dart).
  final void Function(List<String> folders)? onFoldersGone;

  /// A [say] that shows the kit's toast from [context] (`GlacierToast.of`), with Undo as its action.
  static void Function(NoteToast toast) toaster(BuildContext context) {
    final toasts = GlacierToast.of(context);
    return (toast) => toasts.toast(
          message: Text(toast.message),
          duration: toast.duration,
          action: toast.undo == null ? null : GlacierToastAction(label: 'Undo', onPress: toast.undo!),
        );
  }

  Set<String> _hidden = const {};
  ({String id, Timer timer})? _pending;
  Future<void> _committing = Future<void>.value();
  bool _gone = false;

  /// Whether the app's going to the background is being listened for: from the first delete that waits.
  bool _watching = false;

  /// Notes deleted but still undoable: hidden from every list meanwhile.
  Set<String> get hidden => _hidden;

  void _unhide(String id) {
    if (!_hidden.contains(id)) return;
    _hidden = Set.unmodifiable({..._hidden}..remove(id));
    if (!_gone) notifyListeners();
  }

  /// What the app kept about a note beside the note itself, let go once the note is deleted for good.
  void _forgetKept(String id) {
    workspaces.forgetNote(id);
    onForget?.call(id);
  }

  Future<void> _commit() {
    final due = _pending;
    if (due == null) return _committing;
    _pending = null;
    due.timer.cancel();
    final run = _committing.then((_) async {
      try {
        await library.destroy(due.id);
        _forgetKept(due.id);
        trash?.forget([due.id]);
      } catch (error) {
        debugPrint('[glyph] delete failed: $error');
      } finally {
        try {
          await library.refresh();
        } catch (error) {
          debugPrint('[glyph] refresh after delete failed: $error');
        }
        _unhide(due.id);
      }
    });
    _committing = run.catchError((Object _) {});
    return run;
  }

  /// Make any pending delete final now.
  Future<void> flushDeletes() => _commit();

  /// The app going to the background: Android freezes a cached app's timers, and a note that was "deleted" would
  /// come back next launch (`visibilitychange`, `pagehide`).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached) unawaited(_commit());
  }

  /// Into the trash, with an Undo.
  void remove(Note note) {
    final trash = this.trash;
    if (trash == null) {
      _take(note);
      return;
    }
    trash.trashNote(note.id);
    onTrashed?.call(note);
    haptic?.call(HapticKind.warning);
    say(NoteToast(
      'Moved ${noteLabel(note)} to the Trash.',
      duration: noteUndo,
      undo: () {
        trash.restoreNote(note.id);
        onRestored?.call(note);
        haptic?.call(HapticKind.success);
      },
    ));
  }

  /// A delete with no trash to wait in: out of the library, and back where it was by Undo.
  void _take(Note note) {
    final gone = library.delete(note.id);
    if (gone == null) return;
    final filed = workspaces.workspaceOf(note.id)?.id;
    workspaces.forgetNote(note.id);
    haptic?.call(HapticKind.warning);
    say(NoteToast(
      'Moved ${noteLabel(note)} to the Trash.',
      duration: noteUndo,
      undo: () {
        library.restore(gone);
        if (filed != null) workspaces.fileNote(gone.id, filed);
        haptic?.call(HapticKind.success);
      },
    ));
  }

  /// The directories of folders deleted with their notes whose Undo still stands: taken off the disk when it runs
  /// out, or at once as these actions go.
  final Map<Timer, List<String>> _dirsWaiting = {};

  void _dirsGone(List<String> folders) {
    if (folders.isNotEmpty) onFoldersGone?.call(folders);
  }

  /// A folder deleted with everything in it, once the person has said so (Matt, 2026-11-01: "add ability to context
  /// menu delete folders and items inside them"; lib/notes/workspace_sheet.dart asks): every note in it and in every
  /// folder under it, however deep, and then the folders.
  ///
  /// A personal folder's notes go to the Trash as any deleted note does, each its own entry there, and the folders
  /// go from the list in one change; the toast's Undo brings the notes out of the Trash and puts the folders back
  /// where they stood, each note filed where it was. Their directories leave the disk once the Undo has run out and
  /// they are empty ([onFoldersGone]); the trashed files keep their paths under `.trash/`.
  ///
  /// An organization's folder is the team's, and its notes are deleted for every member: an organization's deletes
  /// skip the Trash (lib/team/sync.dart deletes the rows, and every member's device drops the note outright and,
  /// with the folder emptied, the folder; lib/team/folders.dart `prune`). So nothing comes back, and the toast has no
  /// Undo; the question said so before anything went. A team note already in this person's Trash under the folder
  /// goes with them, since it is still in the folder for everyone else. The notes are deleted first and the folders
  /// after, so no note is ever refiled on the way and put to the team at another path.
  Future<void> deleteFolder(String folderId) async {
    final contents = workspaces.folderContents(folderId, has: (id) => library.noteOf(id) != null);
    final list = workspaces.value.list;
    final folder = list.where((w) => w.id == folderId).firstOrNull;
    if (contents == null || folder == null) return;
    // The directories, worked out while the folders are still listed: the deepest first.
    final dirs = [
      for (final id in workspaceFamily(list, folderId).reversed)
        if (list.where((w) => w.id == id).firstOrNull case final each?) ?folderFor(each, list),
    ];
    final said = folderDeletePhrase(folder.name, folders: contents.folders.length, notes: contents.notes.length);
    if (contents.team) {
      unawaited(_commit());
      final gone = [...contents.notes, ...contents.trashed];
      for (final id in gone) {
        try {
          await library.destroy(id);
          _forgetKept(id);
        } catch (error) {
          debugPrint('[glyph] delete failed: $error');
        }
      }
      trash?.forget(gone);
      workspaces.removeFolderFamily(folderId);
      try {
        await library.refresh();
      } catch (error) {
        debugPrint('[glyph] refresh after delete failed: $error');
      }
      haptic?.call(HapticKind.warning);
      say(NoteToast('Deleted $said for every member.'));
      _dirsGone(dirs);
      return;
    }
    final bin = trash;
    final notes = [for (final id in contents.notes) ?library.noteOf(id)];
    final taken = <Note>[];
    for (final note in notes) {
      if (bin != null) {
        bin.trashNote(note.id);
        onTrashed?.call(note);
      } else if (library.delete(note.id) case final gone?) {
        // No trash to wait in: out of the library, and back by Undo, as [_take] does.
        taken.add(gone);
      }
    }
    final removed = workspaces.removeFolderFamily(folderId);
    late final Timer waiting;
    waiting = Timer(noteUndo, () {
      if (_dirsWaiting.remove(waiting) != null) _dirsGone(dirs);
    });
    _dirsWaiting[waiting] = dirs;
    haptic?.call(HapticKind.warning);
    say(NoteToast(
      notes.isEmpty ? 'Deleted $said.' : 'Deleted $said. ${notes.length == 1 ? 'It is' : 'They are'} in the Trash.',
      duration: noteUndo,
      undo: () {
        waiting.cancel();
        _dirsWaiting.remove(waiting);
        if (removed != null) workspaces.putBackFolders(removed);
        for (final note in notes) {
          if (bin != null) {
            bin.restoreNote(note.id);
            onRestored?.call(note);
          }
        }
        for (final note in taken) {
          library.restore(note);
        }
        haptic?.call(HapticKind.success);
      },
    ));
  }

  /// Out of the trash, back where it was.
  void restore(Note note) {
    trash?.restoreNote(note.id);
    onRestored?.call(note);
    haptic?.call(HapticKind.success);
    say(NoteToast('${_capitalise(noteLabel(note))} is back in your notes.', duration: noteUndo));
  }

  /// Every note given out of the trash at once, each back where it was: the Trash's Restore all, once asked.
  void restoreAll(List<Note> notes) {
    if (notes.isEmpty) return;
    trash?.forget([for (final note in notes) note.id]);
    for (final note in notes) {
      onRestored?.call(note);
    }
    haptic?.call(HapticKind.success);
    say(NoteToast(notes.length == 1 ? '${_capitalise(noteLabel(notes.single))} is back in your notes.' : '${groupedCount(notes.length)} notes are back in your notes.', duration: noteUndo));
  }

  /// How many notes the Trash is emptied by at a time ([emptyTrash]).
  static const int emptyBatch = 50;

  /// The job a Trash emptied over more than one batch is on the record as.
  static const String emptyJobId = 'trash-empty';

  /// The emptying under way, and how many are asked for: a second Empty waits for the first.
  Future<void> _emptying = Future<void>.value();
  int _empties = 0;

  /// Every note given, deleted for good now: the trash emptied, once the person has said so. [emptyBatch] at a time,
  /// with the frame given a turn between batches, and on the Activity tray's record when it takes more than one (see
  /// the library doc). A note brought out of the Trash while it runs (Restore, or another device's) is left alone.
  Future<void> emptyTrash(List<Note> notes) {
    // In the Trash as it is asked: one that has left it by the time its batch comes stays.
    final held = {
      for (final note in notes)
        if (trash?.isTrashed(note.id) ?? false) note.id,
    };
    final waits = _empties > 0;
    _empties += 1;
    final run = (waits ? _emptying.then((_) => _empty(notes, held)) : _empty(notes, held)).whenComplete(() => _empties -= 1);
    _emptying = run.catchError((Object _) {});
    return run;
  }

  Future<void> _empty(List<Note> notes, Set<String> held) async {
    unawaited(_commit());
    final bin = trash;
    final total = notes.length;
    var stop = false;
    String steps(int done) => '${groupedCount(done)} of ${groupedCount(total)} notes';
    final job = total > emptyBatch
        ? activity.begin(emptyJobId, kind: JobKind.sync, title: 'Emptying the Trash', line: 'Deleting notes forever', steps: steps(0), fraction: 0, personStarted: true, onStop: () => stop = true)
        : null;
    var gone = 0, done = 0;
    for (var start = 0; start < total && !stop && !_gone; start += emptyBatch) {
      final went = <String>[];
      for (final note in notes.sublist(start, math.min(start + emptyBatch, total))) {
        done += 1;
        if (held.contains(note.id) && !(bin?.isTrashed(note.id) ?? false)) continue;
        try {
          await library.destroy(note.id);
          onForget?.call(note.id);
          went.add(note.id);
        } catch (error) {
          debugPrint('[glyph] delete failed: $error');
        }
      }
      // Once a batch: the filing and the trash's record are each a write of the whole map.
      workspaces.forgetNotes(went);
      bin?.forget(went);
      gone += went.length;
      job?.progress(done: done, total: total, steps: steps(done));
      if (done < total) await Future<void>.delayed(Duration.zero);
    }
    try {
      await library.refresh();
    } catch (error) {
      debugPrint('[glyph] refresh after delete failed: $error');
    }
    final tally = JobTally('note deleted for good', 'notes deleted for good', gone);
    if (done < total) {
      job?.stopped(tally: tally);
      if (_gone) return;
      say(NoteToast('Deleted ${groupedCount(gone)} of ${groupedCount(total)} notes for good. The rest are still in the Trash.'));
      return;
    }
    job?.done(tally: tally);
    haptic?.call(HapticKind.warning);
    say(NoteToast(gone == 1 ? 'Deleted 1 note for good.' : 'Deleted ${groupedCount(gone)} notes for good.'));
  }

  /// The notes whose thirty days in the trash are up, deleted for good as Empty Trash deletes them, without a word:
  /// nobody asked for it just now, and the Trash's foot said it would happen (lib/core/trash.dart `trashKeeps`).
  /// Answers how many went.
  Future<int> purge(List<Note> notes) async {
    var gone = 0;
    for (final note in notes) {
      // Brought back on another device and synced here since the list was made: it stays.
      if (!(trash?.isTrashed(note.id) ?? false)) continue;
      try {
        await library.destroy(note.id);
        _forgetKept(note.id);
        trash?.forget([note.id]);
        gone += 1;
      } catch (error) {
        debugPrint('[glyph] the trash kept a note it should have let go: $error');
      }
    }
    if (gone > 0) {
      try {
        await library.refresh();
      } catch (error) {
        debugPrint('[glyph] refresh after the trash let go failed: $error');
      }
    }
    return gone;
  }

  /// Deleted for good, from the trash: hidden at once, and gone from the library when its Undo runs out.
  void destroy(Note note) {
    // One undo at a time: the toast is latest-wins, so an earlier delete whose Undo is about to disappear from the
    // screen becomes final now.
    unawaited(_commit());
    _hidden = Set.unmodifiable({..._hidden, note.id});
    notifyListeners();
    if (!_watching) {
      _watching = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _pending = (id: note.id, timer: Timer(noteUndo, () => unawaited(_commit())));
    haptic?.call(HapticKind.warning);
    say(NoteToast(
      'Deleted ${noteLabel(note)} for good.',
      duration: noteUndo,
      undo: () {
        final pending = _pending;
        if (pending == null || pending.id != note.id) return;
        pending.timer.cancel();
        _pending = null;
        _unhide(note.id);
        haptic?.call(HapticKind.success);
      },
    ));
  }

  /// A pin or an archive asked of the library, and the list read again once it has answered. A library that refuses
  /// is said and no more: the list still shows the note as it is.
  Future<void> _flag(Future<void> Function() change) async {
    try {
      await change();
      await library.refresh();
    } catch (error) {
      debugPrint('[glyph] the note could not be changed: $error');
    }
  }

  /// Into the archive or out of it, with an Undo that sets it back.
  void archive(Note note, {required bool archived}) {
    unawaited(_flag(() => library.archive(note.id, archived: archived)));
    haptic?.call(HapticKind.success);
    say(NoteToast(
      archived ? 'Archived ${noteLabel(note)}.' : '${_capitalise(noteLabel(note))} is back in your notes.',
      duration: noteUndo,
      undo: () => unawaited(_flag(() => library.archive(note.id, archived: !archived))),
    ));
  }

  /// Pin or unpin: a pinned note sits at the top of the list (stored as `starred`).
  void pin(Note note) {
    unawaited(_flag(() => library.pin(note.id, pinned: !note.starred)));
    haptic?.call(HapticKind.success);
  }

  /// What a card's swipe does (`notes/swipe.ts`, as App.tsx wires it): pin or unpin, into the archive, into the
  /// trash.
  void swipe(Note note, NoteSwipe action) {
    switch (action) {
      case NoteSwipe.pin:
        pin(note);
      case NoteSwipe.archive:
        archive(note, archived: true);
      case NoteSwipe.delete:
        remove(note);
    }
  }

  /// The screen that asked is going: a delete still waiting is made final.
  @override
  void dispose() {
    unawaited(_commit());
    // A deleted folder's Undo goes with these actions: its directories go now.
    for (final entry in _dirsWaiting.entries.toList()) {
      entry.key.cancel();
      _dirsGone(entry.value);
    }
    _dirsWaiting.clear();
    _gone = true;
    if (_watching) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
