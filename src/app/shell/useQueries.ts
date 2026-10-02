import { useMemo, useRef } from 'react';
import type { QueryNote, RecordKind } from '../core/query/records.ts';
import type { Note } from '../core/store.ts';
import type { QueryOptions } from '../editor/queries.ts';
import { isTemplatePageBody } from '../notes/ownTemplates.ts';

/**
 * The library a ```query fence reads, as App hands it to the note on screen (editor/queries.ts; docs/DESIGN.md §159):
 * the notes every screen shows - none in the Trash, none a pending delete is holding back (shell/useVisibleNotes.ts) -
 * less the archive, which is put away, and the templates' pages, which are patterns and not things to do. Read once
 * per change to the notes, as the tickets are (shell/useTickets.ts), and kept as one object while they stay the same,
 * so a note's queries are only run again when something they read could have changed.
 *
 * `open` opens a note at a to-do's line (or where it opens), `tick` ticks a to-do in another note, and `move` sets a
 * record's grouped field when a board card is dragged to another lane; all three are App's, and change with every
 * draw, so they are read through a ref.
 */
export function useQueries(
  notes: readonly Note[],
  open: (noteId: string, line: number | null) => void,
  tick: (noteId: string, line: number, source: string, done: boolean) => void,
  move: (noteId: string, line: number, source: string, kind: RecordKind, field: string, value: string | null) => void,
): Omit<QueryOptions, 'noteId'> {
  const acts = useRef({ open, tick, move });
  acts.current = { open, tick, move };
  const library = useMemo((): QueryNote[] => notes.filter((note) => !note.archivedAt && !isTemplatePageBody(note.body)), [notes]);
  return useMemo(
    () => ({
      notes: () => library,
      open: (noteId, line) => acts.current.open(noteId, line),
      tick: (noteId, line, source, done) => acts.current.tick(noteId, line, source, done),
      move: (noteId, line, source, kind, field, value) => acts.current.move(noteId, line, source, kind, field, value),
    }),
    [library],
  );
}
