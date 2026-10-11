import { externalStore } from '../externalStore.ts';

/**
 * "Add a comment" from a note's menu in a list (notes/NoteMenu.tsx; Matt: "add them to the context menu for a note ...
 * so we can quickly click to add comments"): the note is opened, and its screen starts a comment on its first line
 * once its editor is there (editor/useNoteComments.ts). Said through here rather than through the screen's route, so
 * a note already open hears it too; taken by the one screen it names, once.
 */

const asking = externalStore<{ noteId: string; at: number } | null>(null);

/** A comment wanted on `noteId`'s first line, as soon as it is open. */
export function askComment(noteId: string, now = Date.now()): void {
  asking.set({ noteId, at: now });
}

/** Whether a comment was asked for on `noteId`, the ask taken so nothing hears it twice. */
export function takeCommentAsk(noteId: string): boolean {
  const ask = asking.get();
  if (!ask || ask.noteId !== noteId) return false;
  asking.set(null);
  return true;
}

export const useCommentAsk = asking.use;
