// @vitest-environment node
import { ResourceUpdatedNotificationSchema } from '@modelcontextprotocol/sdk/types.js';
import { describe, expect, it, vi } from 'vitest';
import { INBOX_BODY } from './prompts.ts';
import { aNote, connected, told, WRITTEN } from './testKit.ts';

/**
 * The tools and the rest that came with Claude, live (docs/CLAUDE_LIVE.md): suggest mode on update_note and
 * append_to_note, the comment tools, the notes as resources and their subscriptions, and the prompts - called as
 * Claude calls them, against an account on the sync service in memory.
 */

type Thread = { id: string; on: string | null; resolved: { by: string; at: string } | null; messages: { author: string; at: string; text: string }[] };

describe('suggest mode', () => {
  it('writes update_note’s change as marks signed by the AI, the front matter it signs with written directly', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('a', '# Trip\n\nWe leave on Monday morning by train.\n\n- pack\n'));
    const { text, isError } = await call('update_note', { id: 'a', body: '# Trip\n\nWe leave on Tuesday evening by train.\n\n- pack\n- book seats\n', suggest: true });
    expect(isError).toBe(false);
    expect((JSON.parse(text) as { suggestions: number }).suggestions).toBe(2);
    const body = (await service.stored('a'))!.note.body;
    expect(body).toBe('---\nauthors: matt, Claude\n---\n# Trip\n\nWe leave on {~~Monday morning~>Tuesday evening~~}{>>Claude<<} by train.\n\n- pack\n- {++book seats++}{>>Claude<<}\n');
    // Told as an edit, as any rewrite is.
    expect((await told(service)).map((row) => row.kind)).toEqual(['note-edited']);
  });

  it('makes the change itself without `suggest`, and says nothing of suggestions', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('a', '# Trip\n\nMonday.\n'));
    const { text } = await call('update_note', { id: 'a', body: '# Trip\n\nTuesday.\n' });
    expect(JSON.parse(text)).not.toHaveProperty('suggestions');
    expect((await service.stored('a'))!.note.body).toBe('---\nauthors: matt, Claude\n---\n# Trip\n\nTuesday.\n');
  });

  it('writes append_to_note’s item as a suggestion in the note’s list', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('g', '# Groceries\n\n- [ ] eggs\n'));
    const { text } = await call('append_to_note', { title: 'Groceries', text: 'bread', as: 'task', suggest: true });
    expect((JSON.parse(text) as { suggestions: number }).suggestions).toBe(1);
    expect((await service.stored('g'))!.note.body).toBe('---\nauthors: matt, Claude\n---\n# Groceries\n\n- [ ] eggs\n- [ ] {++Bread++}{>>Claude<<}\n');
  });

  it('says what suggest does in both tools’ descriptions', async () => {
    const { client } = await connected();
    const { tools } = await client.listTools();
    for (const name of ['update_note', 'append_to_note']) {
      const field = (tools.find((t) => t.name === name)?.inputSchema.properties as Record<string, { description?: string }>).suggest;
      expect(field?.description).toContain('{~~old~>new~~}');
    }
  });
});

describe('comments', () => {
  it('comments on words, lists the thread, replies to it and resolves it, as the AI, each told as an edit', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('t', '# Trip\n\nThe venue needs confirming.\n'));
    const added = await call('add_comment', { title: 'Trip', on: 'The venue', text: 'The hall or the barn?' });
    expect(added.isError).toBe(false);
    const comment = (JSON.parse(added.text) as { comment: Thread }).comment;
    expect(comment).toMatchObject({ on: 'The venue', resolved: null, messages: [{ author: 'Claude', text: 'The hall or the barn?' }] });
    const id = comment.id;
    expect((await service.stored('t'))!.note.body).toContain(`==The venue==[^${id}] needs confirming.`);

    expect((await call('reply_to_comment', { id: 't', comment: id, text: 'The hall, I think.' })).isError).toBe(false);
    expect((await call('resolve_comment', { id: 't', comment: id })).isError).toBe(false);
    const listed = JSON.parse((await call('list_comments', { id: 't' })).text) as { note: { id: string; title: string }; count: number; open: number; threads: Thread[] };
    expect(listed).toMatchObject({ note: { id: 't', title: 'Trip' }, count: 1, open: 0 });
    expect(listed.threads[0]!.messages.map((m) => [m.author, m.text])).toEqual([
      ['Claude', 'The hall or the barn?'],
      ['Claude', 'The hall, I think.'],
    ]);
    expect(listed.threads[0]!.resolved?.by).toBe('Claude');
    expect((await told(service)).map((row) => row.kind)).toEqual(['note-edited', 'note-edited', 'note-edited']);
  });

  it('comments on the whole note, and names the author it is given', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('t', '# Trip\n\nWords.'));
    const added = JSON.parse((await call('add_comment', { id: 't', text: 'Looks good.', author: 'Claude Code' })).text) as { comment: Thread };
    expect(added.comment).toMatchObject({ on: 'Trip', messages: [{ author: 'Claude-Code', text: 'Looks good.' }] });
  });

  it('refuses words the note lacks and threads it does not have, writing nothing', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('t', '# Trip\n\nWords.'));
    expect(await call('add_comment', { id: 't', on: 'nowhere', text: 'x' })).toMatchObject({ isError: true, text: expect.stringContaining('do not read “nowhere”') });
    expect(await call('reply_to_comment', { id: 't', comment: 'c1', text: 'x' })).toEqual({ isError: true, text: 'The note has no comment c1. It has no comments.' });
    expect(await call('resolve_comment', { id: 't', comment: 'c1' })).toEqual({ isError: true, text: 'The note has no comment c1. It has no comments.' });
    expect((await service.stored('t'))!.note.body).toBe('# Trip\n\nWords.');
    expect(await told(service)).toEqual([]);
  });

  it('reads a thread a member’s phone wrote', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('t', '# Trip\n\nThe venue.[^c1]\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nBooked?\n```\n'));
    const listed = JSON.parse((await call('list_comments', { title: 'Trip' })).text) as { threads: Thread[] };
    expect(listed.threads).toEqual([{ id: 'c1', on: 'The venue.', resolved: null, messages: [{ author: 'sam', at: '2026-10-04T19:00:12Z', text: 'Booked?' }] }]);
  });
});

describe('resources', () => {
  it('lists the notes newest first as ghost://note/{id}, titled, with where they are, and leaves the Trash out', async () => {
    const { service, client, call } = await connected();
    await service.deviceWrites(aNote('a', '# Groceries\n\n- eggs', { updatedAt: WRITTEN + 3, path: 'Home/Groceries.md' }));
    await service.deviceWrites(aNote('b', '# Trip', { updatedAt: WRITTEN + 2 }));
    await service.deviceWrites(aNote('c', '# Gone', { updatedAt: WRITTEN + 1 }));
    await call('delete_notes', { ids: ['c'] });
    const { resources } = await client.listResources();
    expect(resources).toEqual([
      { uri: 'ghost://note/a', name: 'Groceries', mimeType: 'text/markdown', description: 'Changed 2023-11-14 · Folder: Home', title: 'A Ghost.md note' },
      { uri: 'ghost://note/b', name: 'Trip', mimeType: 'text/markdown', description: 'Changed 2023-11-14', title: 'A Ghost.md note' },
    ]);
    const { resourceTemplates } = await client.listResourceTemplates();
    expect(resourceTemplates.map((t) => t.uriTemplate)).toEqual(['ghost://note/{id}']);
  });

  it('lists at most a hundred', async () => {
    const { service, client } = await connected();
    for (let i = 0; i < 105; i += 1) await service.deviceWrites(aNote(`n${i}`, `# Note ${i}`, { updatedAt: WRITTEN + i }));
    const { resources } = await client.listResources();
    expect(resources.length).toBe(100);
    expect(resources[0]!.name).toBe('Note 104');
  });

  it('reads a note’s markdown, and refuses an id no note has', async () => {
    const { service, client } = await connected();
    await service.deviceWrites(aNote('a', '# Groceries\n\n- eggs'));
    expect(await client.readResource({ uri: 'ghost://note/a' })).toEqual({ contents: [{ uri: 'ghost://note/a', mimeType: 'text/markdown', text: '# Groceries\n\n- eggs' }] });
    await expect(client.readResource({ uri: 'ghost://note/zz' })).rejects.toThrow('No note with the id zz');
  });

  it('offers no subscriptions unless the server is the local one', async () => {
    const { client } = await connected();
    expect(client.getServerCapabilities()?.resources?.subscribe).toBeUndefined();
    const local = await connected({ subscriptions: true });
    expect(local.client.getServerCapabilities()?.resources?.subscribe).toBe(true);
  });

  it('tells a subscriber when the note changes on another device, and stops when it unsubscribes', async () => {
    const { service, client } = await connected({ subscriptions: { everyMs: 10 } });
    await service.deviceWrites(aNote('a', '# Groceries\n\n- eggs'));
    await service.deviceWrites(aNote('b', '# Trip'));
    const heard: string[] = [];
    client.setNotificationHandler(ResourceUpdatedNotificationSchema, (notification) => {
      heard.push(notification.params.uri);
    });
    await client.subscribeResource({ uri: 'ghost://note/a' });
    await service.deviceWrites(aNote('b', '# Trip\n\nChanged, but not watched.', { updatedAt: WRITTEN + 5 }));
    await service.deviceWrites(aNote('a', '# Groceries\n\n- eggs\n- milk', { updatedAt: WRITTEN + 5 }));
    await vi.waitFor(() => expect(heard).toEqual(['ghost://note/a']), { timeout: 5000, interval: 10 });
    await client.unsubscribeResource({ uri: 'ghost://note/a' });
    await service.deviceWrites(aNote('a', '# Groceries\n\n- eggs\n- milk\n- bread', { updatedAt: WRITTEN + 6 }));
    // Nothing is watched, so nothing reads the account: a later change is not told.
    await client.subscribeResource({ uri: 'ghost://note/b' });
    await service.deviceWrites(aNote('b', '# Trip\n\nAgain.', { updatedAt: WRITTEN + 7 }));
    await vi.waitFor(() => expect(heard).toEqual(['ghost://note/a', 'ghost://note/b']), { timeout: 5000, interval: 10 });
    await expect(client.subscribeResource({ uri: 'ghost://note/zz' })).rejects.toThrow('No note with the id zz');
    await client.close();
  });
});

describe('prompts', () => {
  it('offers the four, and each tells Claude what to do with which tools', async () => {
    const { client } = await connected();
    const { prompts } = await client.listPrompts();
    expect(prompts.map((p) => p.name)).toEqual(['weekly-review', 'plan-my-day', 'tidy-note', 'ask-claude-inbox']);
    expect(prompts.find((p) => p.name === 'tidy-note')?.arguments).toEqual([{ name: 'title', description: 'The note’s title.', required: true }]);
    const words = async (name: string, args?: Record<string, string>) => {
      const { messages } = await client.getPrompt({ name, ...(args ? { arguments: args } : {}) });
      expect(messages.every((m) => m.role === 'user')).toBe(true);
      return (messages[0]!.content as { text: string }).text;
    };
    expect(await words('weekly-review')).toContain('list_notes');
    expect(await words('plan-my-day')).toContain('📅');
    const tidy = await words('tidy-note', { title: 'Trip' });
    expect(tidy).toContain('“Trip”');
    expect(tidy).toContain('`suggest: true`');
    const inbox = await words('ask-claude-inbox');
    expect(inbox).toContain(INBOX_BODY);
    expect(inbox).toContain('- [x]');
  });
});
