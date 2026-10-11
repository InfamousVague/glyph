import { announceNotesChanged, getNote, listNotes, noteTitle, updateNote } from '../core/store.ts';
import { sameTitle } from '../core/titleKey.ts';
import { chaptersOf, isBookBody, withChapterRenamed } from './book.ts';

/**
 * A page renamed keeps its place in its notebooks and journals (Matt, 2026-09-29: "notebook and journal notes are
 * based on the title of the note not some unique ID so when changing the title of a page it gets removed from the
 * journal / notebook"). An index lists its pages as `[[Title]]` links, which stay what Obsidian and every Markdown
 * reader follow, so a rename is followed as Obsidian follows one: every index that lists the old title is written with
 * the new one (book.ts `withChapterRenamed`).
 *
 * Only while the old title is this note's alone: a line naming a title another note still has means that note, and is
 * left. Called by the editor's saving (editor/useNoteSaving.ts) when a save changes the note's title, so a heading
 * retyped letter by letter is followed step by step, each save from the last title it had. A notebook written
 * elsewhere meanwhile is read again once.
 */
export async function followRename(noteId: string, from: string, to: string): Promise<number> {
  if (!from.trim() || !to.trim() || sameTitle(from, to)) return 0;
  const notes = await listNotes().catch(() => []);
  if (notes.some((n) => n.id !== noteId && sameTitle(noteTitle(n.body), from))) return 0;
  let changed = 0;
  for (const book of notes) {
    if (book.id === noteId || !isBookBody(book.body) || !chaptersOf(book.body).some((c) => sameTitle(c.title, from))) continue;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const fresh = attempt === 0 ? book : await getNote(book.id).catch(() => null);
      if (!fresh) break;
      const next = withChapterRenamed(fresh.body, from, to);
      if (next === fresh.body) break;
      try {
        await updateNote(fresh.id, next, fresh.revision ?? 1);
        changed += 1;
        break;
      } catch {
        // Another writer won: read it again and rename in what it holds now.
      }
    }
  }
  if (changed) announceNotesChanged();
  return changed;
}
