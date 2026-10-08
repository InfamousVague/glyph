/// A note's screen as the app's shell wants it: the builder to hand `AppShell.noteBuilder` (shell/app_shell.dart),
/// in place of the stand-in of shell/placeholders.dart. What `App.tsx` passes its `<NoteScreen>`: the way back, the
/// delete with its Undo, pin and archive (notes/note_actions.dart), the note's book, every title that is taken, and
/// what the note was opened with (`at`, `caret`).
///
/// What differs: App.tsx is one component with everything in reach; here whoever wires the app (lib/root) makes
/// the pieces and names them once. The lookups a wiki link and a canvas card need (`onOpenTitle`, `hasTitle`,
/// `bodyOfTitle`), the journal's writer, tickets, queries and templates come in with those pieces, through
/// [NoteSeams] or as new fields.
library;

import 'package:flutter/widgets.dart';

import '../core/book.dart';
import '../core/library.dart';
import '../core/note_text.dart';
import '../core/stored.dart';
import '../core/trash.dart';
import '../core/untouched.dart';
import '../core/versions_record.dart';
import '../core/workspaces.dart';
import '../notes/note_actions.dart';
import '../shell/app_shell.dart';
import 'note_editor.dart';
import 'note_screen.dart';

/// The builder for `AppShell.noteBuilder`.
///
/// [actions] is asked for when a note is pinned, archived or deleted, since it is made once there is a toast to say
/// them with; [say] is a toast of the screen's own (a version put back, a board made).
ShellNoteBuilder noteScreenBuilder({
  required NoteLibrary library,
  required WorkspaceStore workspaces,
  required NoteActions Function() actions,
  VersionsRecord? versions,
  Trash? trash,
  Stored? device,
  UntouchedNotes? untouched,
  NoteEditorBuilder editor = readOnlyNoteEditor,
  NoteSeams seams = const NoteSeams(),
  void Function(BuildContext context, String message)? say,
  ValueChanged<String>? onSpeak,
}) {
  return (context, shell, screen) {
    final note = screen.note;
    final all = library.value;
    return NoteScreen(
      note: note,
      library: library,
      workspaces: workspaces,
      versions: versions,
      device: device,
      untouched: untouched,
      onBack: shell.backToList,
      // The tab goes, the note is left, and it is in the trash with an Undo.
      onDelete: (id) {
        shell.dropTab(id);
        final gone = library.noteOf(id);
        if (gone != null) actions().remove(gone);
      },
      onPin: actions().pin,
      onArchive: (archived) {
        shell.dropTab(archived.id);
        actions().archive(archived, archived: true);
      },
      onSpeak: onSpeak,
      at: screen.at,
      caret: screen.caret,
      book: placeOf(bookIndex(all), note),
      // Every note's title key, archived and in the Trash too: a name another note has is not offered.
      takenTitles: {for (final each in all) titleKey(noteTitle(each.body))}..remove(''),
      readOnly: trash?.isTrashed(note.id) ?? false,
      editorBuilder: editor,
      seams: seams,
      say: say == null ? null : (message) => say(context, message),
    );
  };
}
