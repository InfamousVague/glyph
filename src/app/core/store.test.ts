import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import {
  applyCommandMutation,
  applyNote,
  archiveOrder,
  createNote,
  deleteNote,
  getNote,
  latestCommandMutation,
  listNotes,
  listOrder,
  NOTE_SAVED,
  noteTitle,
  setNoteArchived,
  setNoteRecording,
  setNoteStarred,
  undoCommandMutation,
  updateNote,
} from './store.ts';

describe('the list labels', () => {
  it('titles a note by its first line, without heading marks', () => {
    expect(noteTitle('# Groceries\nmilk')).toBe('Groceries');
    expect(noteTitle('Plain first line')).toBe('Plain first line');
    // A bookmark set on the first line is where the note opens, not part of its name.
    expect(noteTitle('# Weekend trip §§\nmilk')).toBe('Weekend trip');
    expect(noteTitle('Half §§ way')).toBe('Half way');
  });

});

describe('the list order', () => {
  it('puts starred notes first and hides the archived', () => {
    const notes = [makeNote('old', 'old', { updatedAt: 1 }), makeNote('new', 'new', { updatedAt: 3 }), makeNote('starred-old', 'starred-old', { updatedAt: 0, starred: true }), makeNote('gone', 'gone', { updatedAt: 9, archivedAt: 5 })];
    expect(listOrder(notes).map((n) => n.id)).toEqual(['starred-old', 'new', 'old']);
  });

  it('shows the archive most recently archived first', () => {
    const notes = [makeNote('a', 'a', { updatedAt: 1, archivedAt: 10 }), makeNote('b', 'b', { updatedAt: 2, archivedAt: 20 }), makeNote('live', 'live', { updatedAt: 3 })];
    expect(archiveOrder(notes).map((n) => n.id)).toEqual(['b', 'a']);
  });
});

describe('a note that opens with front matter', () => {
  it('is named by its own title key, not by the fence', () => {
    expect(noteTitle('---\ntitle: The deposit\ntags: cabin\n---\n\nWords.')).toBe('The deposit');
    expect(noteTitle('---\ntitle: "Quoted name"\n---\n\nWords.')).toBe('Quoted name');
  });

  it('falls back to the first words under the fence when there is no title key', () => {
    expect(noteTitle('---\ntags: cabin\n---\n\n# The deposit\n\nWords.')).toBe('The deposit');
  });

  it('leaves a rule in the middle of a note alone, and an unclosed fence', () => {
    expect(noteTitle('Words first\n\n---\n\nMore.')).toBe('Words first');
    expect(noteTitle('---\nnot really front matter, just words\n\nMore.')).toBe('---');
  });
});

/*
 * The browser half of the store: a real store, since `npm run dev` is where most of the editor is built (store.ts's
 * header says why), and jsdom's localStorage is enough to run all of it.
 */
describe('the store in a browser', () => {
  /** Every NOTE_SAVED the store has sent since the test began: what tells sync a note changed here. */
  let saved = 0;
  const onSaved = () => {
    saved += 1;
  };

  beforeEach(() => {
    localStorage.clear();
    saved = 0;
    window.addEventListener(NOTE_SAVED, onSaved);
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(1_000);
  });

  afterEach(() => {
    window.removeEventListener(NOTE_SAVED, onSaved);
    vi.useRealTimers();
  });

  it('makes a note at revision 1, lists newest first, and will not make one twice', async () => {
    await createNote('a', '# First');
    vi.setSystemTime(2_000);
    const b = await createNote('b', '# Second', 'capture');
    expect(b).toEqual({ id: 'b', body: '# Second', createdAt: 2_000, updatedAt: 2_000, source: 'capture', revision: 1 });
    expect((await listNotes()).map((n) => n.id)).toEqual(['b', 'a']);
    await expect(createNote('a', 'again')).rejects.toThrow('the note id already exists');
    expect(saved).toBe(2);
  });

  it('writes an edit only over the revision it read, keeping when the note was made', async () => {
    await createNote('a', 'one');
    vi.setSystemTime(5_000);
    expect(await updateNote('a', 'two', 1)).toMatchObject({ body: 'two', createdAt: 1_000, updatedAt: 5_000, revision: 2 });
    // A save from a screen that read revision 1 is stale now, and a deleted note is not brought back by one.
    await expect(updateNote('a', 'stale', 1)).rejects.toThrow('the note was deleted or changed');
    await deleteNote('a');
    await expect(updateNote('a', 'resurrected', 2)).rejects.toThrow('the note was deleted or changed');
    expect(await getNote('a')).toBeNull();
  });

  it('pins, archives and keeps a recording without counting as an edit', async () => {
    await createNote('a', 'words');
    vi.setSystemTime(9_000);
    expect(await setNoteStarred('a', true)).toMatchObject({ starred: true, updatedAt: 1_000 });
    expect(await setNoteArchived('a', true)).toMatchObject({ archivedAt: 9_000, updatedAt: 1_000 });
    expect(await setNoteArchived('a', false)).toMatchObject({ archivedAt: null });
    const segments = [{ text: 'hello', startMs: 0, endMs: 400 }];
    expect(await setNoteRecording('a', 400, segments)).toMatchObject({ recordingMs: 400, segments });
    // Forgetting the recording forgets its phrases with it.
    expect(await setNoteRecording('a', null, segments)).toMatchObject({ recordingMs: null, segments: null });
    expect((await getNote('a'))?.body).toBe('words');
    expect(await setNoteStarred('gone', true)).toBeNull();
  });

  it('takes a note from another device whole, and does not tell sync it changed here', async () => {
    await createNote('a', 'mine');
    saved = 0;
    const theirs = makeNote('a', 'theirs', { createdAt: 10, updatedAt: 20, starred: true, revision: 7 });
    expect(await applyNote(theirs)).toBe(theirs);
    expect(await getNote('a')).toEqual(theirs);
    expect(saved).toBe(0);
  });

  it('forgets a deleted note, and tells sync', async () => {
    await createNote('a', 'one');
    await createNote('b', 'two');
    saved = 0;
    await deleteNote('a');
    expect((await listNotes()).map((n) => n.id)).toEqual(['b']);
    expect(saved).toBe(1);
  });

  it('reads a store it cannot parse as empty, and a note from before revisions as revision 1', async () => {
    localStorage.setItem('glyph-notes', '{not json');
    expect(await listNotes()).toEqual([]);
    localStorage.setItem('glyph-notes', JSON.stringify([makeNote('old', 'from an older build')]));
    expect((await getNote('old'))?.revision).toBe(1);
    expect((await updateNote('old', 'edited', 1)).revision).toBe(2);
  });
});

describe('a command’s write, and its undo, in a browser', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(100_000);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  /** An append to note `a`, as it was previewed over `before` at `beforeRevision`. */
  const append = (mutationId: string, before: string | null, after: string, beforeRevision: number | null = 1) => ({
    mutationId,
    noteId: 'a',
    kind: 'append' as 'append' | 'create',
    beforeRevision,
    beforeBody: before,
    afterBody: after,
    source: 'capture' as const,
  });

  it('applies exactly the body previewed while the note is as it was, and refuses once it has changed', async () => {
    await createNote('a', 'milk');
    expect(await applyCommandMutation(append('m1', 'milk', 'milk\neggs'))).toMatchObject({ status: 'applied', mutationId: 'm1', note: { body: 'milk\neggs', revision: 2 } });
    expect(await applyCommandMutation(append('m2', 'milk', 'milk\nbread'))).toMatchObject({ status: 'conflict', current: { body: 'milk\neggs' } });
  });

  it('makes a new note only where there is none', async () => {
    const create = { ...append('m1', null, 'Groceries', null), kind: 'create' as const };
    expect(await applyCommandMutation(create)).toMatchObject({ status: 'applied', note: { id: 'a', body: 'Groceries', source: 'capture', revision: 1 } });
    expect(await applyCommandMutation({ ...create, mutationId: 'm2' })).toMatchObject({ status: 'conflict' });
  });

  it('offers the latest undo only while its result stands, and for ten minutes', async () => {
    await createNote('a', 'milk');
    await applyCommandMutation(append('m1', 'milk', 'milk\neggs'));
    expect(await latestCommandMutation()).toEqual({ mutationId: 'm1', noteId: 'a', kind: 'append', createdAt: 100_000 });
    vi.setSystemTime(100_000 + 10 * 60_000 + 1);
    expect(await latestCommandMutation()).toBeNull();
    vi.setSystemTime(100_000);
    await updateNote('a', 'milk\neggs\nand more', 2);
    expect(await latestCommandMutation()).toBeNull();
  });

  it('undoes an append back to the words before it, once, and an undone create takes the note away', async () => {
    await createNote('a', 'milk');
    await applyCommandMutation(append('m1', 'milk', 'milk\neggs'));
    expect(await undoCommandMutation('m1')).toMatchObject({ status: 'undone', note: { body: 'milk', revision: 3 } });
    expect(await undoCommandMutation('m1')).toEqual({ status: 'already-undone' });
    expect(await undoCommandMutation('never')).toEqual({ status: 'not-found' });

    await applyCommandMutation({ ...append('m2', null, 'Groceries', null), noteId: 'b', kind: 'create' });
    expect(await undoCommandMutation('m2')).toEqual({ status: 'undone', mutationId: 'm2', note: null });
    expect(await getNote('b')).toBeNull();
  });

  it('will not undo over an edit made since', async () => {
    await createNote('a', 'milk');
    await applyCommandMutation(append('m1', 'milk', 'milk\neggs'));
    await updateNote('a', 'milk\neggs\nbread', 2);
    expect(await undoCommandMutation('m1')).toMatchObject({ status: 'conflict', current: { body: 'milk\neggs\nbread' } });
  });
});
