import { useMemo } from 'react';
import type { Note } from '../core/store.ts';
import { inTrash, outOfTrash, useTrash } from '../core/trash.ts';

/**
 * The library as every screen sees it, which is not the library as the store has it.
 *
 * A note deleted for good and still undoable is hidden at once (notes/useNoteActions.ts), and removed from the store
 * only when its Undo runs out. The old list filtered by this; the home page, the sidebar's tree and the drawer took
 * the full list, so a deleted note sat there until the timer, or a second delete, made it final (Matt: "Notes need to
 * be deleted twice before the UI updates"). So the filtering is done once, here, and every screen is handed the
 * answer.
 *
 * And a note in the trash (core/trash.ts) is out of all of them - the home page, the tree, tabs, links and search -
 * and only in the tree's Trash folder, until it is brought back or deleted for good.
 */
export interface VisibleNotes {
  /** Every note a screen may show: not hidden by a pending delete, not in the trash. */
  visible: Note[];
  /** The notes in the trash, for its folder in the tree. */
  trashed: Note[];
  /** `visible`'s ids: what a tab, a place on the trail or a link can still land on. */
  live: ReadonlySet<string>;
}

/** `notes` as the store has them; `hidden` the ids a pending delete is holding back (notes/useNoteActions.ts). */
export function useVisibleNotes(notes: Note[], hidden: ReadonlySet<string>): VisibleNotes {
  const kept = useMemo(() => (hidden.size ? notes.filter((n) => !hidden.has(n.id)) : notes), [notes, hidden]);
  const thrown = useTrash();
  const visible = useMemo(() => outOfTrash(kept, thrown), [kept, thrown]);
  const trashed = useMemo(() => inTrash(kept, thrown), [kept, thrown]);
  const live = useMemo(() => new Set(visible.map((n) => n.id)), [visible]);
  return { visible, trashed, live };
}
