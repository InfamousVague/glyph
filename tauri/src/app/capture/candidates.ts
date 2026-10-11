import { isCanvasBody } from '../canvas/jsonCanvas.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { guidePages } from '../guidebook/guidebook.ts';
import { templatePages } from '../notes/ownTemplates.ts';
import type { NamedNote } from './takeWriter.ts';

/**
 * The notes a spoken command can name, read once as the recorder opens: every note out of the archive that has a
 * title, newest first, less two kinds a person never means by name while talking.
 *
 * - The Guide's chapters (guidebook/guidebook.ts `guidePages`). Added, its forty-four pages would stand beside the
 *   person's own notes, and "the to-do list" would tie with its chapter Lists and to-dos.
 * - The pages of a Templates notebook (notes/ownTemplates.ts): "add milk to A checklist" means a note of the person's,
 *   never the template a checklist is made from.
 * - Canvases (canvas/jsonCanvas.ts): their body is JSON, so words written into one would break it.
 *
 * Books stay: a book named is refused by name ("… is a book"), rather than mistaken for a note called something like it.
 */
export function commandCandidates(notes: readonly Note[]): NamedNote[] {
  const guide = guidePages(notes);
  const templates = templatePages(notes);
  return notes
    .filter((note) => !note.archivedAt && !guide.has(note.id) && !templates.has(note.id) && !isCanvasBody(note.body))
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .map((note) => ({ id: note.id, title: noteTitle(note.body), note }))
    .filter((candidate) => candidate.title);
}
