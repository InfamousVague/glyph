/// Done written into the library: the item found in its note as the library has it now, ticked (tick_item.dart),
/// and saved over exactly that revision, as any other write from outside a note's own screen is (lib/root's
/// `_writeNote`). The one writer for a reminder's Done and the Today widget's tick, whether the app is running
/// (lib/root/phone_extras.dart, which hands a note that is open on screen to its editor instead) or not
/// (background_tick.dart).
library;

import '../book/tickets.dart' show notebookFinder;
import '../core/library.dart';
import '../core/note_facts.dart';
import 'tick_item.dart';

/// Ticks the item said as [words] on [line] of note [noteId] (0 for a ticket). True where it was written; false
/// where the note is gone, nothing there can be ticked, or it is ticked already.
Future<bool> writeDone(NoteLibrary library, String noteId, int line, String words) async {
  final note = await library.get(noteId);
  if (note == null) return false;
  List<String>? statuses;
  if (line == 0) {
    final notebook = notebookFinder(library.value)(note);
    statuses = notebook == null ? null : NoteFacts.of(notebook).statuses;
  }
  final next = doneIn(note.body, line: line, words: words, statuses: statuses);
  if (next == null || next == note.body) return false;
  await library.update(noteId, next, note.revision);
  return true;
}
