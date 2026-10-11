import type { Note } from '../app/core/store.ts';

/**
 * A note for a test: an id, the words, and whatever else the test is about - everything else a note typed in the
 * editor at the start of time, so a fixture says only what matters to it.
 *
 * Nine test files each wrote their own `note()` with these defaults, varying only in which fields they took as
 * arguments. Typed as `Note`, never loosened: a fixture that stops matching the shape it pretends to be should fail
 * to compile, not pass a test.
 */
export function makeNote(id: string, body = `# ${id}`, over: Partial<Note> = {}): Note {
  return { id, body, createdAt: 0, updatedAt: 0, source: 'editor', ...over };
}
