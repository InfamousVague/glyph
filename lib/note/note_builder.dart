/// A note's screen as the app's shell wants it: the builder to hand `AppShell.noteBuilder` (shell/app_shell.dart),
/// in place of the stand-in of shell/placeholders.dart. What `App.tsx` passes its `<NoteScreen>`: the way back, the
/// delete with its Undo, pin and archive (notes/note_actions.dart), the note's book, every title that is taken, and
/// what the note was opened with (`at`, `caret`), your own templates for a blank page's cards, and the way a journal
/// on screen is written from outside it.
///
/// What differs: App.tsx is one component with everything in reach; here whoever wires the app (lib/root) makes
/// the pieces and names them once. The lookups a wiki link and a canvas card need (`onOpenTitle`, `hasTitle`,
/// `bodyOfTitle`), tickets and queries come in with those pieces, through [NoteSeams] (lib/root/note_desk.dart).
library;

import '../ai/review.dart' show ReviewHandoff;
import '../core/place_tags.dart';
import 'package:flutter/widgets.dart';

import '../core/book.dart';
import '../book/journal.dart' show JournalWriter;
import '../core/library.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/stored.dart';
import '../core/trash.dart';
import '../core/untouched.dart';
import '../core/versions_record.dart';
import '../core/workspaces.dart';
import '../notes/note_actions.dart';
import '../notes/note_templates.dart' show NoteTemplate;
import '../shell/app_shell.dart';
import 'note_editor.dart';
import 'note_screen.dart';

/// The builder for `AppShell.noteBuilder`.
///
/// [actions] is asked for when a note is pinned, archived or deleted, since it is made once there is a toast to say
/// them with; [say] is a toast of the screen's own (a version put back, a board made). [bookOf] is the note's place in
/// its notebook as the app reads it (App.tsx `placeInBook`: a journal's entries in the order they were written);
/// left out, it is the first book whose index names the note. [templates] and [onTemplates] are the blank page's
/// cards; [onJournal] is told of the journal on screen; [tags] is the places notes keep (lib/core/place_tags.dart).
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
  BookPlace? Function(Note note)? bookOf,
  List<NoteTemplate>? Function()? templates,
  VoidCallback? onTemplates,
  ValueChanged<JournalWriter?>? onJournal,
  PlaceTags? tags,
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
      book: bookOf != null ? bookOf(note) : placeOf(bookIndex(all), note),
      // Every other note's title key, archived and in the Trash too: a name another note has is not offered. Not this
      // note's own, which an undo back to its blank page would otherwise find taken.
      takenTitles: {
        for (final each in all)
          if (each.id != note.id) titleKey(noteTitle(each.body)),
      }..remove(''),
      templates: templates?.call(),
      onTemplates: onTemplates,
      onJournal: onJournal,
      tags: tags,
      // The review a recording handed this note, while it has a job to hand back: its tag waits for it.
      reviewing: switch (screen.review?.value) { final ReviewHandoff handoff => handoff.job != null, _ => false },
      readOnly: trash?.isTrashed(note.id) ?? false,
      editorBuilder: editor,
      seams: seams,
      say: say == null ? null : (message) => say(context, message),
    );
  };
}
