import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createNote, deleteNote, getNote, listNotes, setNoteRecording, updateNote, type Note } from '../core/store.ts';
import { placingFor } from './place.ts';
import { TakeWriter, type NamedNote } from './takeWriter.ts';

/** What happens to a note between `writeInto`'s read of it and its guarded write: someone typing, a sync, a delete. */
const meanwhile = vi.hoisted(() => [] as (() => Promise<unknown>)[]);
vi.mock('../core/store.ts', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../core/store.ts')>();
  return {
    ...actual,
    applyCommandMutation: async (request: Parameters<typeof actual.applyCommandMutation>[0]) => {
      await meanwhile.shift()?.();
      return actual.applyCommandMutation(request);
    },
  };
});

/**
 * The recorder's writes (capture/takeWriter.ts), against the page's own note store - its browser half, which jsdom's
 * localStorage holds - so what is checked is what a note reads afterwards. Each rule here is one a bug taught: drafts
 * that raced each other, a Discard that left the words behind, and the words written twice under a command's change.
 */

function writerFor(words: () => string, candidates: NamedNote[] = []) {
  const shown: (Note | null)[] = [];
  const writer = new TakeWriter({
    markdown: () => words(),
    hasWords: () => words() !== '',
    candidates: () => candidates,
    targetChanged: (note) => shown.push(note),
  });
  return { writer, shown };
}

beforeEach(() => {
  localStorage.clear();
  meanwhile.length = 0;
});

describe('a recording added to a note', () => {
  it('writes its words once under the note’s own text, however many drafts race', async () => {
    const trip = await createNote('trip', '# Trip\n\nBook the cabin.');
    const { writer } = writerFor(() => 'Ask Sam about the dog.');
    writer.aim(trip);
    await Promise.all([writer.flushDraft(), writer.flushDraft()]);
    expect((await getNote('trip'))?.body).toBe('# Trip\n\nBook the cabin.\n\nAsk Sam about the dog.');
  });

  it('gives the note its own text back on Discard', async () => {
    const trip = await createNote('trip', '# Trip\n\nBook the cabin.');
    const { writer } = writerFor(() => 'Ask Sam.');
    writer.aim(trip);
    await writer.flushDraft();
    await writer.undoDraft();
    expect((await getNote('trip'))?.body).toBe('# Trip\n\nBook the cabin.');
    expect(writer.savedDraft).toBe(false);
  });

  it('puts a command’s change into the text under the words, and the words stay written once', async () => {
    const shop = await createNote('shop', '# Shopping\n\n- Eggs');
    let words = 'Pick up the parcel.';
    const { writer, shown } = writerFor(() => words);
    writer.aim(shop);
    await writer.flushDraft();
    const changed = await writer.updateNote('shop', (body) => `${body}\n- Milk`);
    expect(changed).toBe('# Shopping\n\n- Eggs\n- Milk');
    expect((await getNote('shop'))?.body).toBe('# Shopping\n\n- Eggs\n- Milk\n\nPick up the parcel.');
    // The page is shown the change as it lands, above the words.
    expect(shown.at(-1)?.body).toBe('# Shopping\n\n- Eggs\n- Milk');
    words = 'Pick up the parcel. And bin bags.';
    await writer.flushDraft();
    expect((await getNote('shop'))?.body).toBe('# Shopping\n\n- Eggs\n- Milk\n\nPick up the parcel. And bin bags.');
  });

  it('says nothing changed when the change changes nothing', async () => {
    const shop = await createNote('shop', '# Shopping');
    const { writer } = writerFor(() => 'Words.');
    writer.aim(shop);
    expect(await writer.updateNote('shop', (body) => body)).toBeNull();
    expect(await writer.updateNote('gone', () => 'anything')).toBeNull();
    expect((await getNote('shop'))?.body).toBe('# Shopping');
  });
});

describe('a new recording', () => {
  it('drafts into a note of its own id, and Discard takes it away', async () => {
    const { writer } = writerFor(() => '# Grocery run');
    await writer.flushDraft();
    expect((await getNote(writer.noteId))?.body).toBe('# Grocery run');
    await writer.undoDraft();
    expect(await getNote(writer.noteId)).toBeNull();
  });

  it('writes nothing when nothing has been said', async () => {
    const { writer } = writerFor(() => '');
    await writer.flushDraft();
    expect(await getNote(writer.noteId)).toBeNull();
    expect(writer.savedDraft).toBe(false);
  });

  it('starts over under a fresh id when aimed at no note, and at the note’s own id when aimed at one', async () => {
    const trip = await createNote('trip', '# Trip');
    const { writer, shown } = writerFor(() => 'Words.');
    const first = writer.noteId;
    writer.aim(trip);
    expect(writer.noteId).toBe('trip');
    writer.aim(null);
    expect(writer.noteId).not.toBe(first);
    expect(writer.noteId).not.toBe('trip');
    expect(shown).toEqual([trip, null]);
  });
});

describe('a recording that moves to another note', () => {
  it('composes under the second note’s text, never the first’s, once it is aimed there', async () => {
    const trip = await createNote('trip', '# Trip\n\nBook the cabin.');
    const work = await createNote('work', '# Work\n\n- Email Jo');
    const { writer } = writerFor(() => 'Call Sam.');
    writer.aim(trip);
    expect(await writer.compose('Call Sam.')).toBe('# Trip\n\nBook the cabin.\n\nCall Sam.');
    writer.aim(work);
    expect(await writer.compose('Call Sam.')).toBe('# Work\n\n- Email Jo\n\nCall Sam.');
    await writer.flushDraft();
    expect((await getNote('work'))?.body).toBe('# Work\n\n- Email Jo\n\nCall Sam.');
    expect((await getNote('trip'))?.body).toBe('# Trip\n\nBook the cabin.');
  });

  it('leaves what was said so far where it was said, beyond the reach of a later Discard', async () => {
    const trip = await createNote('trip', '# Trip\n\nBook the cabin.');
    let words = 'For the dog.';
    const { writer } = writerFor(() => words);
    writer.aim(trip);
    await writer.flushDraft();
    expect(writer.savedDraft).toBe(true);
    writer.keepDraft();
    expect(writer.savedDraft).toBe(false);
    expect(writer.baseBody).toBeNull();
    words = 'Call Sam.';
    writer.aim(null);
    await writer.undoDraft();
    expect((await getNote('trip'))?.body).toBe('# Trip\n\nBook the cabin.\n\nFor the dog.');
  });
});

describe('commands on other notes', () => {
  it('rewrite that note alone, and keep the command list’s copy of it current', async () => {
    const trip = await createNote('trip', '# Trip');
    const work = await createNote('work', '# Work\n\n- Email Jo');
    const candidates: NamedNote[] = [{ id: 'work', title: 'Work', note: work }];
    const { writer } = writerFor(() => 'Words.', candidates);
    writer.aim(trip);
    await writer.updateNote('work', (body) => `${body}\n- Call Sam`);
    expect((await getNote('work'))?.body).toBe('# Work\n\n- Email Jo\n- Call Sam');
    expect(candidates[0]?.note.body).toBe('# Work\n\n- Email Jo\n- Call Sam');
    expect((await getNote('trip'))?.body).toBe('# Trip');
  });
});

describe('the chain', () => {
  it('runs each write after the one before it, even one that failed', async () => {
    const { writer } = writerFor(() => '');
    const order: string[] = [];
    const failing = writer.queue(async () => {
      await new Promise((resolve) => setTimeout(resolve, 5));
      order.push('first');
      throw new Error('the store said no');
    });
    const second = writer.queue(async () => {
      order.push('second');
      return 'kept';
    });
    await expect(failing).rejects.toThrow('the store said no');
    await expect(second).resolves.toBe('kept');
    await writer.settled();
    expect(order).toEqual(['first', 'second']);
  });
});

describe('words written into a note a command named, once, at Done', () => {
  const HOUSE = '# House TODOs\n\n- [ ] Fix the gutter\n';
  const edit = (body: string) => async () => {
    const now = await getNote('house');
    await updateNote('house', body, now!.revision ?? 1);
  };

  it('goes onto the note as it is when written, and reads it again when it changed between the read and the write', async () => {
    await createNote('house', HOUSE);
    meanwhile.push(edit(`${HOUSE}- [ ] Clear the drains\n`));
    const { writer } = writerFor(() => '');
    const written = await writer.writeInto({ id: 'house' }, 'Call Sam.', placingFor(HOUSE), () => '# Call Sam');
    expect(written).toMatchObject({ own: false, blocks: ['- [ ] Call Sam'], mutationId: expect.any(String) });
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Clear the drains\n- [ ] Call Sam\n');
  });

  it('makes the words a note of their own when it changed twice, leaving both changes as they were', async () => {
    await createNote('house', HOUSE);
    meanwhile.push(edit(`${HOUSE}- [ ] One\n`), edit(`${HOUSE}- [ ] One\n- [ ] Two\n`));
    const { writer } = writerFor(() => '');
    const written = await writer.writeInto({ id: 'house' }, 'Call Sam.', placingFor(HOUSE), () => '# Call Sam');
    expect(written).toMatchObject({ own: true, mutationId: null, saved: { body: '# Call Sam' } });
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] One\n- [ ] Two\n');
  });

  it('makes the words a note of their own when the note was deleted meanwhile', async () => {
    await createNote('house', HOUSE);
    meanwhile.push(async () => deleteNote('house'));
    const { writer } = writerFor(() => '');
    const written = await writer.writeInto({ id: 'house' }, 'Call Sam.', placingFor(HOUSE), () => '# Call Sam');
    expect(written.own).toBe(true);
    expect((await listNotes()).map((note) => note.body)).toEqual(['# Call Sam']);
  });

  it('reads a note switched to again in the background, and keeps it only while the take is still aimed there', async () => {
    const full = await createNote('house', HOUSE);
    const other = await createNote('other', '# Other');
    const candidate = { ...full, recordingMs: undefined, segments: undefined } as Note;
    const { writer } = writerFor(() => '');
    await setNoteRecording(full.id, 4000, [{ text: 'Fix the gutter.', startMs: 0, endMs: 900 }]);
    writer.aim(candidate, placingFor(HOUSE), { routed: true });
    writer.refresh('house');
    await writer.refreshed();
    expect(writer.target).toMatchObject({ id: 'house', recordingMs: 4000 });

    writer.aim(candidate, placingFor(HOUSE), { routed: true });
    writer.refresh('house');
    writer.aim(other);
    await writer.refreshed();
    expect(writer.target?.id).toBe('other');
  });
});

