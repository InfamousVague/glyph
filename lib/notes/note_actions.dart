/// Pin, archive, delete and the trash, each undoable. A port of `src/app/notes/useNoteActions.ts`, over a
/// [NoteLibrary], a [Trash] and a [WorkspaceStore].
///
/// Deleting a note puts it in the trash (lib/core/trash.dart; Matt: "Send deleted notes to a trash folder where we
/// can empty it to perma delete notes or restore notes"), which is a flag and so undone by clearing it. Only the
/// trash deletes for good: one note from it ([NoteActions.destroy]), or all of it ([NoteActions.emptyTrash]).
///
/// DELETING FOR GOOD IS DEFERRED, not done and then undone. Undoing a real delete would mean saving the note again,
/// which gives it a new `createdAt` and loses its pin; so a deleted note is hidden at once and removed from the
/// library only when its Undo runs out. The removal is also forced the moment anything could outlive the toast: a
/// second delete, the app going to the background, a capture starting over the list ([NoteActions.flushDeletes]),
/// and these actions being disposed of.
///
/// Archive and pin are real at once: they are flags, not edits, and undoing one is setting it back.
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

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/note.dart';
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
  NoteActions({required this.library, required this.workspaces, this.trash, required this.say, this.haptic, this.onForget, this.onTrashed, this.onRestored});

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

  /// Out of the trash, back where it was.
  void restore(Note note) {
    trash?.restoreNote(note.id);
    onRestored?.call(note);
    haptic?.call(HapticKind.success);
    say(NoteToast('${_capitalise(noteLabel(note))} is back in your notes.', duration: noteUndo));
  }

  /// Every note given, deleted for good now: the trash emptied, once the person has said so.
  Future<void> emptyTrash(List<Note> notes) async {
    unawaited(_commit());
    for (final note in notes) {
      try {
        await library.destroy(note.id);
        _forgetKept(note.id);
      } catch (error) {
        debugPrint('[glyph] delete failed: $error');
      }
    }
    trash?.forget([for (final note in notes) note.id]);
    try {
      await library.refresh();
    } catch (error) {
      debugPrint('[glyph] refresh after delete failed: $error');
    }
    haptic?.call(HapticKind.warning);
    say(NoteToast(notes.length == 1 ? 'Deleted 1 note for good.' : 'Deleted ${notes.length} notes for good.'));
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
    _gone = true;
    if (_watching) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
