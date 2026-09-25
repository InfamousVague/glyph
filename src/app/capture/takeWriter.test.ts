import { beforeEach, describe, expect, it } from 'vitest';
import { createNote, getNote, type Note } from '../core/store.ts';
import { TakeWriter, type NamedNote } from './takeWriter.ts';

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

beforeEach(() => localStorage.clear());

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
