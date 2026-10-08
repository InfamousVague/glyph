/// The notes a spoken command can name, read once as the recorder opens: every note out of the archive that has a
/// title, newest first, less two kinds a person never means by name while talking. A port of
/// `src/app/capture/candidates.ts`.
///
/// - The Guide's chapters (core/book.dart `guidePages`). Added, its forty-four pages would stand beside the person's
///   own notes, and "the to-do list" would tie with its chapter Lists and to-dos.
/// - The pages of a Templates notebook (core/book.dart `templatePages`): "add milk to A checklist" means a note of the
///   person's, never the template a checklist is made from.
/// - Canvases (core/canvas_body.dart): their body is JSON, so words written into one would break it.
///
/// Books stay: a book named is refused by name ("… is a book"), rather than mistaken for a note called something
/// like it.
///
/// What differs: the web answers the take writer's `NamedNote[]` (`Candidate & { note: Note }`); that shape is
/// `TakeCandidate<Note>` here (take_types.dart). The Guide's pages, the templates' pages, a canvas's body and a
/// note's title are read from `lib/core`, where this port keeps what the web has in `guidebook/`, `notes/`,
/// `canvas/` and `core/store.ts`.
library;

import '../core/book.dart' show guidePages, templatePages;
import '../core/canvas_body.dart' show isCanvasBody;
import '../core/note.dart' show Note;
import '../core/note_text.dart' show noteTitle;
import 'take_types.dart' show TakeCandidate;

/// The notes a command can name: see the library's comment.
List<TakeCandidate<Note>> commandCandidates(List<Note> notes) {
  final guide = guidePages(notes);
  final templates = templatePages(notes);
  // Newest first, equals in the order they came, as JavaScript's stable sort leaves them.
  final kept = <Note>[];
  for (final note in notes) {
    if (note.archivedAt != null || guide.contains(note.id) || templates.contains(note.id) || isCanvasBody(note.body)) continue;
    var at = kept.length;
    while (at > 0 && kept[at - 1].updatedAt < note.updatedAt) {
      at -= 1;
    }
    kept.insert(at, note);
  }
  return [
    for (final note in kept)
      if (noteTitle(note.body) case final title when title.isNotEmpty) TakeCandidate<Note>(id: note.id, title: title, note: note),
  ];
}
