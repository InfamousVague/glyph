// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { aNote, connected, WRITTEN } from './testKit.ts';

/**
 * The tools themselves, called as Claude calls them, against an account on the sync service in memory: what each
 * one answers, what it writes, and what it refuses and says instead. The end-to-end run (mcp.e2e.test.ts) calls them
 * against a real service; this is every rule they keep, without one.
 */

type Listed = { count: number; notes: { id: string; title: string; preview: string; folder: string | null; pinned: boolean; archived: boolean; hasRecording: boolean; updated: string }[] };

describe('listing and reading', () => {
  it('lists the notes newest change first, by title, with a line of preview past a picture, and leaves the archived out', async () => {
    const { service, call } = await connected();
    const long = 'word '.repeat(40).trim();
    await service.deviceWrites(aNote('a', '# Groceries\n\nWe need:\n- eggs', { updatedAt: WRITTEN + 3, path: 'Home/Groceries.md', starred: true }));
    await service.deviceWrites(aNote('b', `![](image/cover.jpg)\n# Trip\n\n${long}`, { updatedAt: WRITTEN + 2, recordingMs: 4_000 }));
    await service.deviceWrites(aNote('c', '', { updatedAt: WRITTEN + 1 }));
    await service.deviceWrites(aNote('d', '# Old\n\nGone by.', { updatedAt: WRITTEN + 4, archivedAt: WRITTEN }));
    const listed = JSON.parse((await call('list_notes')).text) as Listed;
    expect(listed.count).toBe(3);
    expect(listed.notes.map((n) => [n.id, n.title])).toEqual([
      ['a', 'Groceries'],
      ['b', 'Trip'],
      ['c', 'Untitled'],
    ]);
    expect(listed.notes[0]).toMatchObject({ preview: 'We need: - eggs', folder: 'Home', pinned: true, archived: false, hasRecording: false, updated: new Date(WRITTEN + 3).toISOString() });
    // The picture line is not the note's first line; the words after the title are cut to 140 with an ellipsis.
    expect(listed.notes[1]!.preview).toBe(`${long.slice(0, 139)}…`);
    expect(listed.notes[1]!.hasRecording).toBe(true);
    expect(listed.notes[1]!.folder).toBeNull();

    const archived = JSON.parse((await call('list_notes', { include_archived: true, query: 'O', limit: 1 })).text) as Listed;
    // Every title with an o in it, archived too, but only the first.
    expect(archived.count).toBe(2);
    expect(archived.notes.map((n) => n.id)).toEqual(['d']);
  });

  it('reads a note by its id, its exact title, or the one title that holds the words, and says which it could be', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('a', '# Groceries\n\n- eggs'));
    await service.deviceWrites(aNote('b', '# Trip to the coast'));
    await service.deviceWrites(aNote('c', '# Trip home'));
    const read = async (args: Record<string, unknown>) => {
      const { text, isError } = await call('read_note', args);
      return isError ? text : (JSON.parse(text) as { id: string; body: string; rev: number }).id;
    };
    expect(await read({ id: 'a' })).toBe('a');
    expect(await read({ title: 'groceries' })).toBe('a');
    expect(await read({ title: 'coast' })).toBe('b');
    expect(await read({ title: 'Trip' })).toBe('Several notes could be "Trip": Trip to the coast (b), Trip home (c). Say which by id.');
    expect(await read({ title: 'Nowhere' })).toBe('No note titled "Nowhere". Use list_notes or search_notes to find it.');
    expect(await read({ id: 'zz' })).toBe('No note with the id zz. Use list_notes to find it.');
    expect(await read({})).toBe('Say which note: its id (from list_notes) or its title.');
    const whole = JSON.parse((await call('read_note', { id: 'a' })).text) as { body: string; rev: number };
    expect(whole).toMatchObject({ body: '# Groceries\n\n- eggs', rev: 1 });
  });

  it('finds words in titles and bodies alike, with the words around the first match', async () => {
    const { service, call } = await connected();
    const before = 'a'.repeat(100);
    await service.deviceWrites(aNote('a', `# Notes\n\n${before} the cabin key ${'z'.repeat(100)}`));
    await service.deviceWrites(aNote('b', '# Cabin\n\nShort.'));
    await service.deviceWrites(aNote('c', '# Other'));
    const found = JSON.parse((await call('search_notes', { query: 'CABIN' })).text) as { count: number; notes: { id: string; snippet: string }[] };
    expect(found.count).toBe(2);
    const long = found.notes.find((n) => n.id === 'a')!;
    // Eighty characters either side, the ends marked where the note goes on.
    expect(long.snippet).toBe(`…${'a'.repeat(75)} the cabin key ${'z'.repeat(75)}…`);
    expect(found.notes.find((n) => n.id === 'b')!.snippet).toBe('# Cabin Short.');
    expect(JSON.parse((await call('search_notes', { query: 'cabin', limit: 1 })).text)).toMatchObject({ count: 2, notes: [{}] });
  });
});

describe('writing', () => {
  it('makes a note with its title as a heading where the words have none, pinned when asked, and signed by Claude', async () => {
    const { service, call } = await connected();
    const made = JSON.parse((await call('create_note', { title: 'Packing', body: '  - tent\n', pinned: true })).text) as { created: { id: string; pinned: boolean; title: string } };
    expect(made.created).toMatchObject({ pinned: true, title: 'Packing' });
    expect((await service.stored(made.created.id))?.note.body).toBe('---\nauthors: matt, Claude\n---\n# Packing\n\n- tent');
    // A body that has its heading already keeps it, and the title given is not put over it.
    const own = JSON.parse((await call('create_note', { title: 'Ignored', body: '# Mine\n\nWords.', author: 'Sonnet' })).text) as { created: { id: string } };
    expect((await service.stored(own.created.id))?.note.body).toBe('---\nauthors: matt, Sonnet\n---\n# Mine\n\nWords.');
    expect(await call('create_note', { body: '   ' })).toEqual({ isError: true, text: 'A note needs some words.' });
  });

  it('rewrites a note whole, keeping every author it had, and will not empty one', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('a', '---\nauthors: matt, Ada\n---\n# Plan\n\nOld words.'));
    const written = JSON.parse((await call('update_note', { id: 'a', body: '# Plan\n\nNew words.' })).text) as { updated: { rev: number } };
    expect(written.updated.rev).toBe(2);
    expect((await service.stored('a'))?.note.body).toBe('---\nauthors: matt, Ada, Claude\n---\n# Plan\n\nNew words.');
    expect(await call('update_note', { id: 'a', body: '\n' })).toEqual({ isError: true, text: 'A note needs some words. To remove a note, archive it with set_note_flags.' });
    expect((await call('update_note', { id: 'nope', body: 'Words' })).text).toBe("Ghost.md's sync service refused: No note nope.");
  });

  it('refuses a rewrite another device got to first, and shows that device’s words rather than writing over them', async () => {
    let before: (() => Promise<void>) | null = null;
    const { service, call } = await connected({
      hooks: {
        // Between the tool's read and its write, the phone writes the same note.
        fetcher: (service) => async (input, init) => {
          if (init?.method === 'PUT' && before) {
            const step = before;
            before = null;
            await step();
          }
          return service.fetcher(input, init);
        },
      },
    });
    await service.deviceWrites(aNote('a', '# Plan\n\nMine.'));
    before = async () => {
      await service.deviceWrites(aNote('a', '# Plan\n\nThe phone’s.'));
    };
    const refused = await call('update_note', { id: 'a', body: '# Plan\n\nClaude’s.' });
    expect(refused.isError).toBe(true);
    expect(refused.text).toContain('Another device changed this note first; read it again before writing.');
    expect(refused.text).toContain('Their version (read it with read_note and try again):');
    const theirs = JSON.parse(refused.text.slice(refused.text.indexOf('{'))) as { body: string; rev: number };
    expect(theirs).toMatchObject({ body: '# Plan\n\nThe phone’s.', rev: 2 });
    expect((await service.stored('a'))?.note.body).toBe('# Plan\n\nThe phone’s.');
  });

  it('adds a task to a note’s list in the list’s style, and a paragraph on the end', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('a', '# Trip\n\n- [ ] Book the cabin'));
    const task = JSON.parse((await call('append_to_note', { title: 'Trip', text: 'pack the charger', as: 'task' })).text) as { added: string[]; note: { id: string } };
    expect(task.added).toEqual(['- [ ] Pack the charger']);
    await call('append_to_note', { id: 'a', text: 'We leave Friday.', as: 'paragraph' });
    // The task joins the list; the paragraph stands on its own under it; Claude is named for writing both.
    expect((await service.stored('a'))?.note.body).toBe('---\nauthors: matt, Claude\n---\n# Trip\n\n- [ ] Book the cabin\n- [ ] Pack the charger\n\nWe leave Friday.\n');
  });

  it('pins and archives a note, undoes either, and says what to set when given nothing', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('a', '# Plan'));
    expect(await call('set_note_flags', { id: 'a' })).toEqual({ isError: true, text: 'Say what to set: pinned, archived, or both.' });
    const set = JSON.parse((await call('set_note_flags', { id: 'a', pinned: true, archived: true })).text) as { note: { pinned: boolean; archived: boolean } };
    expect(set.note).toMatchObject({ pinned: true, archived: true });
    const archivedAt = (await service.stored('a'))?.note.archivedAt;
    expect(archivedAt).toBeGreaterThan(WRITTEN);
    // Archived again, it keeps when it was first archived.
    await call('set_note_flags', { id: 'a', archived: true });
    expect((await service.stored('a'))?.note.archivedAt).toBe(archivedAt);
    await call('set_note_flags', { id: 'a', pinned: false, archived: false });
    expect((await service.stored('a'))?.note).toMatchObject({ starred: false, archivedAt: null });
    // Flags are not words: nobody is added as an author for setting them.
    expect((await service.stored('a'))?.note.body).toBe('# Plan');
  });
});

describe('the account', () => {
  it('says which account it is, what it holds, and that the local server is one connection with nothing to sign out', async () => {
    const { service, client, call } = await connected();
    await service.deviceWrites(aNote('a', '# One', { starred: true }));
    await service.deviceWrites(aNote('b', '# Two', { archivedAt: WRITTEN }));
    const status = JSON.parse((await call('account_status')).text) as Record<string, unknown>;
    expect(status).toEqual({ handle: 'matt', service: 'https://fake.test/glyph/api', notes: 2, archived: 1, pinned: 1, changedSinceLastRead: 2, connections: 1 });
    const { tools } = await client.listTools();
    expect(tools.map((t) => t.name)).toEqual(['list_notes', 'read_note', 'search_notes', 'create_note', 'update_note', 'append_to_note', 'set_note_flags', 'account_status']);
  });

  it('counts and ends the hosted server’s connections through its hooks', async () => {
    let ended = 0;
    const { client, call } = await connected({ hosted: { connections: () => 3, signOutEverywhere: () => (ended += 3) } });
    expect((JSON.parse((await call('account_status')).text) as { connections: number }).connections).toBe(3);
    expect((await client.listTools()).tools.map((t) => t.name)).toContain('sign_out_everywhere');
    expect(JSON.parse((await call('sign_out_everywhere')).text)).toEqual({ endedConnections: 3 });
    expect(ended).toBe(3);
  });

  it('says in words when the session has lapsed past renewing, rather than failing the call', async () => {
    const { service, session, call } = await connected();
    // No device key to renew with, and every token gone: the password is needed again.
    session.deviceKey = null;
    service.expireAllTokens();
    const lapsed = await call('list_notes');
    expect(lapsed).toEqual({ isError: true, text: "Ghost.md's sync service refused: This session has lapsed. Sign in again with `login`." });
  });
});
