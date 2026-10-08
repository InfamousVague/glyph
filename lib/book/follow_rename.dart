/// A page renamed keeps its place in its notebooks and journals (Matt, 2026-09-29: "notebook and journal notes are
/// based on the title of the note not some unique ID so when changing the title of a page it gets removed from the
/// journal / notebook"). A port of `src/app/book/followRename.ts`. An index lists its pages as `[[Title]]` links,
/// which stay what Obsidian and every Markdown reader follow, so a rename is followed as Obsidian follows one: every
/// index that lists the old title is written with the new one (lib/core/book.dart `withChapterRenamed`).
///
/// Only while the old title is this note's alone: a line naming a title another note still has means that note, and
/// is left. Called by the editor's saving when a save changes the note's title, so a heading retyped letter by
/// letter is followed step by step, each save from the last title it had. A notebook written elsewhere meanwhile is
/// read again once.
///
/// What differs: the store is the [NoteLibrary] handed in, where the page has one module of functions. Its list is
/// the notes as it holds them (`listNotes`), a notebook read again is [NoteLibrary.get], and the list is read again
/// after a change ([NoteLibrary.refresh], the page's `announceNotesChanged`).
library;

import '../core/book.dart' show chaptersOf, isBookBody, withChapterRenamed;
import '../core/item_syntax.dart' show jsTrim;
import '../core/library.dart' show NoteLibrary;
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle;
import '../core/title_key.dart' show sameTitle;

/// Follows note [noteId]'s rename from [from] to [to] into every notebook that lists it; answers how many were
/// written.
Future<int> followRename(NoteLibrary library, String noteId, String from, String to) async {
  if (jsTrim(from).isEmpty || jsTrim(to).isEmpty || sameTitle(from, to)) return 0;
  final notes = [...library.value];
  if (notes.any((n) => n.id != noteId && sameTitle(noteTitle(n.body), from))) return 0;
  var changed = 0;
  for (final book in notes) {
    if (book.id == noteId || !isBookBody(book.body) || !chaptersOf(book.body).any((c) => sameTitle(c.title, from))) continue;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      Note? fresh = book;
      if (attempt > 0) {
        try {
          fresh = await library.get(book.id);
        } catch (_) {
          fresh = null;
        }
      }
      if (fresh == null) break;
      final next = withChapterRenamed(fresh.body, from, to);
      if (next == fresh.body) break;
      try {
        await library.update(fresh.id, next, fresh.revision);
        changed += 1;
        break;
      } catch (_) {
        // Another writer won: read it again and rename in what it holds now.
      }
    }
  }
  if (changed > 0) {
    try {
      await library.refresh();
    } catch (_) {
      // The notebooks are written; a list that will not read again reads the next time anything asks.
    }
  }
  return changed;
}
