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

  it('finds a filled blank by its answer and titles a note by its words, never by the hidden bracket (docs/DESIGN.md §145)', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('a', '# Trip to ??Tokyo??(Qwen3.5 4B from memory, 2026-09-28. Asked: capital of Japan)\n\nCheapest on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day)'));
    const found = JSON.parse((await call('search_notes', { query: 'midweek' })).text) as { count: number; notes: { snippet: string; title: string }[] };
    expect(found.notes[0]).toMatchObject({ title: 'Trip to Tokyo', snippet: '# Trip to Tokyo Cheapest on midweek' });
    expect(JSON.parse((await call('search_notes', { query: 'memory' })).text)).toMatchObject({ count: 0 });
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

  it('keeps the keys that make a notebook, a journal and an entry through a rewrite, and a name Claude gives', async () => {
    const { service, call } = await connected();
    const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: "**{{time}}** "\nentry-place: true\n---\n# Diary\n\n- [[2026-09-28 14.05]]\n';
    await service.deviceWrites(aNote('j', journal));
    await call('update_note', { id: 'j', body: '# Diary\n\nWhat I keep.\n\n- [[2026-09-28 14.05]]\n' });
    expect((await service.stored('j'))?.note.body).toBe(
      '---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: "**{{time}}** "\nentry-place: true\nauthors: matt, Claude\n---\n# Diary\n\nWhat I keep.\n\n- [[2026-09-28 14.05]]\n',
    );
    await service.deviceWrites(aNote('e', '---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n**14:05** Walked.'));
    await call('update_note', { id: 'e', body: '---\ntitle: "A walk"\n---\n**14:05** Walked by the river.' });
    expect((await service.stored('e'))?.note.body).toBe('---\ntitle: "A walk"\ndate: 2026-09-28T14:05\nauthors: matt, Claude\n---\n**14:05** Walked by the river.');
    // A plain note the app renamed is renamed by the heading Claude writes, as it always was: its old name is not put back.
    await service.deviceWrites(aNote('p', '---\ntitle: "Old name"\ndate: 2026-01-02\n---\n# Old name\n\nWords.'));
    await call('update_note', { id: 'p', body: '# New name\n\nWords.' });
    expect((await service.stored('p'))?.note.body).toBe('---\nauthors: matt, Claude\n---\n# New name\n\nWords.');
  });

  it('keeps how a note looks through a rewrite without front matter', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('r', '---\nlook: reading\n---\n# The long road\n\nA walk.\n'));
    await call('update_note', { id: 'r', body: '# The long road\n\nA longer walk.\n' });
    expect((await service.stored('r'))?.note.body).toBe('---\nlook: reading\nauthors: matt, Claude\n---\n# The long road\n\nA longer walk.\n');
    // Your Templates notebook stays the one they are kept in.
    await service.deviceWrites(aNote('t', '---\ntitle: "Templates"\nbook: true\ntemplates: true\n---\n# Templates\n\n- [[A day]]\n'));
    await call('update_note', { id: 't', body: '# Templates\n\n- [[A day]]\n- [[A walk]]\n' });
    expect((await service.stored('t'))?.note.body).toContain('templates: true');
    // And a page of it stays one of its pages, by its mark.
    await service.deviceWrites(aNote('d', '---\ntitle: "A day"\ntemplates: page\n---\n# {{date:YYYY-MM-DD}}\n\n- [ ] \n'));
    await call('update_note', { id: 'd', body: '# {{date:YYYY-MM-DD}}\n\n- [ ] Water the plants\n' });
    expect((await service.stored('d'))?.note.body).toContain('templates: page');
  });

  it('says in the rewrite’s description that a notebook’s links are its pages', async () => {
    const { client } = await connected();
    const { tools } = await client.listTools();
    expect(tools.find((t) => t.name === 'update_note')?.description).toContain('A notebook’s or a journal’s list of [[links]] is its pages: a link left out of the new body takes that page or entry out of it, though its note stays.');
    // The co-author's field says where the name shows, in a notebook's words.
    const author = (tools.find((t) => t.name === 'create_note')?.inputSchema.properties as Record<string, { description?: string }>).author;
    expect(author?.description).toContain('on the note, its notebook and a shared page');
  });

  it('turns a journal down for append_to_note, and says what writes an entry', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('j', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n'));
    expect(await call('append_to_note', { title: 'Diary', text: 'Walked.' })).toEqual({
      isError: true,
      text: '“Diary” is a journal: its words are the list of its entries. Use add_journal_entry to write one.',
    });
    expect((await service.stored('j'))?.note.body).toBe('---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n');
  });

  it('writes a journal entry as the app does: named by the minute, from its template, on from its time, with its line', async () => {
    const { service, call } = await connected();
    const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: "# {{date}}\\n\\n**{{time}}** "\nentry-place: true\n---\n# Diary\n\n';
    await service.deviceWrites(aNote('j', journal));
    const made = JSON.parse((await call('add_journal_entry', { journal: 'Diary', text: 'Walked along the river after lunch.', at: '2026-09-28T14:05' })).text) as { created: { id: string; title: string } };
    expect(made.created.title).toBe('2026-09-28 14.05');
    const body = (await service.stored(made.created.id))?.note.body;
    expect(body).toBe(
      `---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\nauthors: matt, Claude\n---\n# ${new Intl.DateTimeFormat(undefined, { weekday: 'long', month: 'long', day: 'numeric' }).format(new Date(2026, 8, 28))}\n\n**14:05** Walked along the river after lunch.`,
    );
    // Never a place: the server does not know where anyone is.
    expect(body).not.toContain('location:');
    expect((await service.stored('j'))?.note.body).toBe(`${journal}- [[2026-09-28 14.05]]\n`);
    // The same minute again, by the journal's id: " (2)", and its line after the first.
    const again = JSON.parse((await call('add_journal_entry', { journal: 'j', text: 'And again.', at: '2026-09-28T14:05' })).text) as { created: { title: string } };
    expect(again.created.title).toBe('2026-09-28 14.05 (2)');
    expect((await service.stored('j'))?.note.body).toBe(`${journal}- [[2026-09-28 14.05]]\n- [[2026-09-28 14.05 (2)]]\n`);
  });

  it('turns down a time that is not one, rather than rolling it on into another day', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('j', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n'));
    for (const at of ['2026-13-45T99:99', '2026-02-30T12:00', '2026-09-28T24:00']) {
      expect(await call('add_journal_entry', { journal: 'Diary', text: 'Walked.', at })).toEqual({ isError: true, text: `${at} is not a time. Give it as YYYY-MM-DDTHH:MM.` });
    }
    expect((await service.stored('j'))?.note.body).toBe('---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n');
  });

  it('names an entry past a note of that minute put away in the archive', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('j', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n'));
    await service.deviceWrites(aNote('old', '---\ntitle: "2026-09-28 14.05"\n---\nArchived.', { archivedAt: WRITTEN }));
    const made = JSON.parse((await call('add_journal_entry', { journal: 'Diary', text: 'Walked.', at: '2026-09-28T14:05' })).text) as { created: { title: string } };
    expect(made.created.title).toBe('2026-09-28 14.05 (2)');
  });

  it('makes nothing when another device changed the journal first, so a second try is clean', async () => {
    let before: (() => Promise<void>) | null = null;
    const { service, call } = await connected({
      hooks: {
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
    const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n';
    await service.deviceWrites(aNote('j', journal));
    await call('list_notes', {});
    // The phone writes the journal between the tool's read and its write.
    before = async () => {
      await service.deviceWrites(aNote('j', `${journal}- [[2026-09-28 08.10]]\n`));
    };
    const refused = await call('add_journal_entry', { journal: 'j', text: 'Walked.', at: '2026-09-28T14:05' });
    expect(refused.isError).toBe(true);
    expect(refused.text).toContain('Another device changed this note first');
    const listed = JSON.parse((await call('list_notes', {})).text) as Listed;
    expect(listed.notes.map((n) => n.title)).toEqual(['Diary']);
    // Tried again, the entry and its line, once each.
    const made = JSON.parse((await call('add_journal_entry', { journal: 'j', text: 'Walked.', at: '2026-09-28T14:05' })).text) as { created: { title: string } };
    expect(made.created.title).toBe('2026-09-28 14.05');
    expect((await service.stored('j'))?.note.body).toBe(`${journal}- [[2026-09-28 08.10]]\n- [[2026-09-28 14.05]]\n`);
  });

  it('makes a day’s to-dos from what is said, and turns down a note that is not a journal', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('j', '---\ntitle: "Days"\nbook: true\njournal: true\ntemplate: "## To do\\n\\n- [ ] "\n---\n# Days\n'));
    await service.deviceWrites(aNote('n', '# Groceries'));
    const made = JSON.parse((await call('add_journal_entry', { journal: 'Days', text: 'Call Sam. Buy bread.', at: '2026-01-02T07:09' })).text) as { created: { id: string } };
    expect((await service.stored(made.created.id))?.note.body).toBe('---\ntitle: "2026-01-02 07.09"\ndate: 2026-01-02T07:09\nauthors: matt, Claude\n---\n## To do\n\n- [ ] Call Sam\n- [ ] Buy bread\n');
    expect(await call('add_journal_entry', { journal: 'Groceries', text: 'Eggs.' })).toEqual({ isError: true, text: '“Groceries” is not a journal. Use append_to_note or create_note for it.' });
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
    expect(tools.map((t) => t.name)).toEqual(['list_notes', 'read_note', 'search_notes', 'create_note', 'update_note', 'append_to_note', 'add_journal_entry', 'set_note_flags', 'account_status']);
  });

  it('asks the hosted server’s caller when an entry was written, since its clock is not the person’s', async () => {
    const { service, client, call } = await connected({ hosted: { connections: () => 1, signOutEverywhere: () => 0 } });
    await service.deviceWrites(aNote('j', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n'));
    expect(await call('add_journal_entry', { journal: 'Diary', text: 'Walked.' })).toEqual({
      isError: true,
      text: 'Say when, as `at`: the person’s local time, YYYY-MM-DDTHH:MM. This server’s clock is not theirs.',
    });
    // Nothing was made, and the journal is as it was.
    expect((await service.stored('j'))?.note.body).toBe('---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n');
    const tool = (await client.listTools()).tools.find((t) => t.name === 'add_journal_entry')!;
    expect(JSON.stringify(tool.inputSchema)).toContain('Needed: this server’s clock is not the person’s');
    const made = JSON.parse((await call('add_journal_entry', { journal: 'Diary', text: 'Walked.', at: '2026-09-28T14:05' })).text) as { created: { title: string } };
    expect(made.created.title).toBe('2026-09-28 14.05');
    // The local server runs on the person's own computer, and takes its clock.
    const local = await connected();
    await local.service.deviceWrites(aNote('j', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n'));
    const now = JSON.parse((await local.call('add_journal_entry', { journal: 'Diary', text: 'Walked.' })).text) as { created: { title: string } };
    expect(now.created.title).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}\.\d{2}$/);
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

describe('where a note was written, as the tools see it', () => {
  it('is kept across a rewrite that dropped it, and read whole', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('a', '---\nlocation: 51.5074,-0.1278\nplace: "London"\n---\n# Plan\n\nOld words.'));
    const read = JSON.parse((await call('read_note', { id: 'a' })).text) as { body: string };
    expect(read.body).toContain('location: 51.5074,-0.1278');
    await call('update_note', { id: 'a', body: '# Plan\n\nNew words.' });
    expect((await service.stored('a'))?.note.body).toBe('---\nlocation: 51.5074,-0.1278\nplace: "London"\nauthors: matt, Claude\n---\n# Plan\n\nNew words.');
    // A rewrite that says where itself is left as it says.
    await call('update_note', { id: 'a', body: '---\nlocation: 48.8566,2.3522\n---\n# Plan\n\nMoved.' });
    expect((await service.stored('a'))?.note.body).toBe('---\nlocation: 48.8566,2.3522\nauthors: matt, Claude\n---\n# Plan\n\nMoved.');
  });
});
