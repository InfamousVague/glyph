// @vitest-environment node
import { beforeEach, describe, expect, it } from 'vitest';
import type { Note } from '../tauri/src/app/core/store.ts';
import { fromBase64Url, open, openBytes, seal, sealBytes } from '../tauri/src/app/core/sync/crypto.ts';
import { forgetTeamDocs } from '../tauri/src/app/core/team/doc.ts';
import { fakeService, FAST } from '../tauri/src/test/fakeService.ts';
import { GlyphAccount } from './glyph.ts';
import { aNote, anOrganization, API, connected, registerPair, teamDevice, WRITTEN } from './testKit.ts';

/**
 * An organization's notes through the connector (mcp/team.ts; docs/SHARED.md): read as a member's device wrote
 * them, written as updates to the team's document that a device then merges, filed into the team and out of it, and
 * said to be unreadable - with the reason - where this account has no wrap of the key they are sealed under.
 *
 * The device here is the app's own organization channel (core/team/sync.ts, through testKit.ts `teamDevice`), so
 * what the connector writes is read by the code a phone reads it with, and the other way about.
 */

type Listed = { count: number; notes: { id: string; title: string; archived: boolean; pinned: boolean; workspace: { id: string; name: string; organization: boolean; accountOnly?: string } | null }[]; notReadable?: string[] };
type Read = { id: string; body: string; rev: number; archived: boolean; pinned: boolean; workspace: Listed['notes'][number]['workspace'] };
type Spaces = { workspaces: { id: string; name: string; organization: boolean; notes: number; archived: number; notReadable?: { notes: number; why: string }; accountOnly?: number }[]; notReadable?: string[] };

/** A team note's row on the service, opened as a member opens it. */
async function rowOf(service: Awaited<ReturnType<typeof fakeService>>, org: { id: string; key: CryptoKey }, id: string, key = org.key) {
  const row = service.teamNotes(org.id).get(id);
  if (!row?.blob) return null;
  return { rev: row.rev, ...(await open<{ note: Note; state: string; seq: number; images?: string[] }>(key, row.blob, `org:${org.id}:note:${id}`)) };
}

beforeEach(() => {
  forgetTeamDocs();
});

describe('reading an organization’s notes', () => {
  it('lists, reads and searches what a member’s device wrote, live and archived, and counts them as list_workspaces does', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service, 'Ghost');
    const phone = teamDevice(service, org);
    phone.put('t1', '# Roadmap\n\n- ship the connector');
    phone.put('t2', '# Retro\n\nWhat went well.', { archivedAt: WRITTEN, starred: true });
    await phone.sync();
    await service.deviceWrites(aNote('p1', '# Groceries\n\n- eggs'));

    const listed = JSON.parse((await call('list_notes', { include_archived: true })).text) as Listed;
    expect(listed.notReadable).toBeUndefined();
    expect(Object.fromEntries(listed.notes.map((n) => [n.id, n.workspace]))).toEqual({
      t1: { id: `org-${org.id}`, name: 'Ghost', organization: true },
      t2: { id: `org-${org.id}`, name: 'Ghost', organization: true },
      p1: null,
    });
    // The archive and the pin are the team's, as the row says them.
    expect(listed.notes.find((n) => n.id === 't2')).toMatchObject({ archived: true, pinned: true });
    expect((JSON.parse((await call('list_notes')).text) as Listed).notes.map((n) => n.id).sort()).toEqual(['p1', 't1']);

    const read = JSON.parse((await call('read_note', { title: 'Roadmap' })).text) as Read;
    expect(read).toMatchObject({ id: 't1', body: '# Roadmap\n\n- ship the connector', workspace: { name: 'Ghost', organization: true } });
    const found = JSON.parse((await call('search_notes', { query: 'went well', include_archived: true })).text) as Listed;
    expect(found.notes.map((n) => n.id)).toEqual(['t2']);

    const spaces = JSON.parse((await call('list_workspaces')).text) as Spaces;
    const ghost = spaces.workspaces.find((w) => w.name === 'Ghost')!;
    expect(ghost).toEqual({ id: `org-${org.id}`, name: 'Ghost', path: 'Ghost', organization: true, notes: 2, notesUnder: 2, archived: 1 });
    const inGhost = JSON.parse((await call('list_notes', { workspace: 'Ghost', include_archived: true })).text) as Listed;
    expect(inGhost.count).toBe(ghost.notes);
    const status = JSON.parse((await call('account_status')).text) as { notes: number; organizations: unknown };
    expect(status).toMatchObject({ notes: 3, organizations: [{ id: org.id, name: 'Ghost', notes: 2 }] });
  });

  it('reads what a device typed since the row, from the note’s log, asking only for the logs that moved', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('t1', '# Roadmap\n\n- one');
    phone.put('t2', '# Quiet');
    await phone.sync();
    expect((JSON.parse((await call('read_note', { id: 't1' })).text) as Read).body).toBe('# Roadmap\n\n- one');
    const rev = service.teamNotes(org.id).get('t1')!.rev;
    // Typed on the phone: an update on the log, the row as it was.
    phone.put('t1', '# Roadmap\n\n- one\n- two');
    await phone.sync();
    expect(service.teamNotes(org.id).get('t1')!.rev).toBe(rev);
    service.calls.length = 0;
    expect((JSON.parse((await call('read_note', { id: 't1' })).text) as Read).body).toBe('# Roadmap\n\n- one\n- two');
    const logs = service.calls.filter((c) => c.endsWith('/updates'));
    expect(logs).toEqual([`GET orgs/${org.id}/notes/t1/updates`]);
    // And a read with nothing new asks for the list, the feed and the heads, and no log at all.
    service.calls.length = 0;
    await call('read_note', { id: 't1' });
    expect(service.calls.filter((c) => c.includes('orgs'))).toEqual(['GET orgs', `GET orgs/${org.id}/notes`, `GET orgs/${org.id}/heads`]);
  });

  it('passes over the account’s own leftover of a note the team holds, and says which filed notes the team does not hold', async () => {
    const { service, call, account } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('t1', '# Claude Rules\n\nThe live ones.');
    await phone.sync();
    // What the account's feed still holds: the same note from before it went to the team, and another filed there
    // that no device ever put to the team.
    await service.deviceWrites(aNote('t1', '# Claude Rules\n\nStale.', { archivedAt: WRITTEN }));
    await service.deviceWrites(aNote('x9', '# Orphan'));
    await account.changePrefs(() => ({ workspaces: { list: [{ id: `org-${org.id}`, name: 'Ghost' }], notes: { t1: `org-${org.id}`, x9: `org-${org.id}` } } }));

    const read = JSON.parse((await call('read_note', { id: 't1' })).text) as Read;
    expect(read).toMatchObject({ body: '# Claude Rules\n\nThe live ones.', archived: false });
    const listed = JSON.parse((await call('list_notes', { include_archived: true })).text) as Listed;
    expect(listed.notes.map((n) => n.id).sort()).toEqual(['t1', 'x9']);
    expect(listed.notes.find((n) => n.id === 'x9')!.workspace?.accountOnly).toContain('In the account only');
    const ghost = (JSON.parse((await call('list_workspaces')).text) as Spaces).workspaces[0]!;
    expect(ghost).toMatchObject({ notes: 1, accountOnly: 1 });
    expect((JSON.parse((await call('list_notes', { workspace: 'Ghost', include_archived: true })).text) as Listed).notes.map((n) => n.id)).toEqual(['t1']);
  });

  it('answers the account’s own notes from a service without organizations, and says nothing of any', async () => {
    const service = await fakeService({ handle: 'matt', password: 'correct horse' }, { teams: false });
    await service.deviceWrites(aNote('p1', '# Groceries'));
    const account = new GlyphAccount(await GlyphAccount.signIn(API, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher }), { fetcher: service.fetcher });
    await account.pull();
    expect((await account.list()).map((r) => r.note.id)).toEqual(['p1']);
    expect(account.notices()).toEqual([]);
    expect(account.organizations()).toEqual([]);
  });
});

describe('what it cannot read', () => {
  it('says how many notes wait on a wrap and why, never leaves them out silently, and reads them once a device has made the wrap', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service, 'HelloTrade', { wrap: false });
    const phone = teamDevice(service, org);
    phone.put('t1', '# Pricing');
    phone.put('t2', '# Hiring');
    await phone.sync();

    const why = 'this account has no wrap of its key at generation 1 yet; one of its members’ devices makes it at their next sync';
    const notice = `2 notes in HelloTrade are not readable by this connector: ${why}.`;
    const listed = JSON.parse((await call('list_notes')).text) as Listed;
    expect(listed).toMatchObject({ count: 0, notReadable: [notice] });
    expect((JSON.parse((await call('search_notes', { query: 'Pricing' })).text) as Listed).notReadable).toEqual([notice]);
    expect(await call('read_note', { id: 't1' })).toEqual({ isError: true, text: `The note t1 is in the organization HelloTrade, and is not readable by this connector: ${why}.` });
    expect(await call('update_note', { id: 't1', body: '# Mine now' })).toMatchObject({ isError: true });
    expect((await call('delete_notes', { ids: ['t1'] })).text).toBe(`None of those notes could be read. The note t1 is in the organization HelloTrade, and is not readable by this connector: ${why}.`);
    const spaces = JSON.parse((await call('list_workspaces')).text) as Spaces;
    expect(spaces.workspaces).toEqual([{ id: `org-${org.id}`, name: 'HelloTrade', path: 'HelloTrade', organization: true, notes: 0, notesUnder: 0, archived: 0, notReadable: { notes: 2, why } }]);
    // It makes no key and no wrap of its own: the organization's keys are as the device left them.
    expect(service.keysOf(org.id)).toEqual({ generation: 1, wraps: {} });
    expect(service.calls.filter((c) => c.startsWith('POST orgs/') && c.endsWith('/keys'))).toHaveLength(1);
    // A new note cannot be sealed for the team either, and says so rather than landing somewhere else.
    expect((await call('create_note', { body: '# New', workspace: 'HelloTrade' })).text).toBe(`HelloTrade’s notes cannot be written by this connector: ${why}.`);

    await org.wrapNow();
    const now = JSON.parse((await call('list_notes')).text) as Listed;
    expect(now.notReadable).toBeUndefined();
    expect(now.notes.map((n) => n.title).sort()).toEqual(['Hiring', 'Pricing']);
  });

  it('says an organization has no key yet, and that the account has no encryption key yet, each in its words', async () => {
    const { service, call, account } = await connected();
    // An organization made, and no device has made its key: nothing to read, and nothing to write under.
    const response = await service.fetcher(`${API}/v1/orgs`, { method: 'POST', headers: { Authorization: `Bearer ${service.signedIn()}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ name: 'Fresh' }) });
    const { org } = (await response.json()) as { org: { id: string } };
    await account.pull();
    expect(account.notices()).toEqual([]);
    expect((await call('create_note', { body: '# New', workspace: `org-${org.id}` })).text).toBe('Fresh’s notes cannot be written by this connector: no key has been made for it yet; one of its members’ devices makes it at their next sync.');
    expect(service.encryption).toBeNull();
    expect(service.keysOf(org.id).generation).toBe(0);
  });

  it('reads a row still sealed under the generation before a turn, from this account’s wrap at it, and does not put it again', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('t1', '# Old words');
    await phone.sync();
    const sealedAt = service.teamNotes(org.id).get('t1')!;
    // A member left and the key turned; no device has sealed the row again yet.
    await org.turn();
    const read = JSON.parse((await call('read_note', { id: 't1' })).text) as Read;
    expect(read.body).toBe('# Old words');
    expect(service.calls).toContain(`GET orgs/${org.id}/keys`);
    expect(service.teamNotes(org.id).get('t1')).toBe(sealedAt);
    // What it writes is under the key in force, named by its generation, and the row is still the device's to seal again.
    await call('append_to_note', { id: 't1', text: 'A new line', as: 'paragraph' });
    const [update] = service.teamUpdates(org.id, 't1');
    await expect(openBytes(org.keyAt(2), fromBase64Url(update!.blob), `org:${org.id}:note:t1:update`)).resolves.toBeInstanceOf(Uint8Array);
    expect(service.teamNotes(org.id).get('t1')).toBe(sealedAt);
    expect((JSON.parse((await call('read_note', { id: 't1' })).text) as Read).body).toContain('A new line');
  });

  it('counts the rows sealed under a generation it has no wrap at, while it reads the rest', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service, 'Ghost', { wrap: false });
    const phone = teamDevice(service, org);
    phone.put('t1', '# Before I joined');
    await phone.sync();
    // The key turned, and this account has a wrap at the new generation only: a member who joined after the first.
    // No device that could read the old row has sealed it again yet.
    await org.turn();
    const other = teamDevice(service, org);
    other.put('t2', '# After');
    await other.sync();
    const listed = JSON.parse((await call('list_notes')).text) as Listed;
    expect(listed.notes.map((n) => n.id)).toEqual(['t2']);
    expect(listed.notReadable).toEqual(['1 note in Ghost is not readable by this connector: they are sealed under a generation of its key this account has no wrap at.']);
    expect((JSON.parse((await call('list_workspaces')).text) as Spaces).workspaces[0]).toMatchObject({ notes: 1, notReadable: { notes: 1 } });
  });
});

describe('writing an organization’s notes', () => {
  it('writes an edit as an update on the note’s log, which a device merges with what it typed apart', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('t1', '# Plan\n\n- first\n- second');
    await phone.sync();
    const row = service.teamNotes(org.id).get('t1')!;

    // The phone types a line at the top, not yet synced; Claude adds a task at the end.
    phone.put('t1', '# Plan\n\nFrom the phone.\n\n- first\n- second');
    const added = JSON.parse((await call('append_to_note', { id: 't1', text: 'third', as: 'item' })).text) as { added: string[]; note: { workspace: { name: string } } };
    expect(added.added).toEqual(['- Third']);
    expect(added.note.workspace.name).toBe('Ghost');
    // On the wire: one sealed update on the log, the row untouched, nothing in the account's own feed.
    expect(service.teamUpdates(org.id, 't1')).toHaveLength(1);
    expect(service.teamNotes(org.id).get('t1')).toBe(row);
    expect(service.notes.has('t1')).toBe(false);
    expect(service.calls.filter((c) => c.startsWith('POST orgs/') || c.startsWith('PUT orgs/'))).toEqual([`POST orgs/${org.id}/keys`, `PUT orgs/${org.id}/notes/t1`, `POST orgs/${org.id}/ais`, `POST orgs/${org.id}/notes/t1/updates`]);

    await phone.sync();
    const merged = phone.notes.get('t1')!.body;
    expect(merged).toContain('From the phone.');
    expect(merged).toContain('- Third');
    expect(merged).toContain('authors: matt, Claude');
    // And the connector reads the same words back.
    expect((JSON.parse((await call('read_note', { id: 't1' })).text) as Read).body).toBe(merged);
  });

  it('replaces a team note’s body as a change to its document, keeping what makes it what it is', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('t1', '---\ntype: ticket\nid: GHO-7\nstatus: Todo\n---\n# Fix sync\n\nIt drops notes.');
    await phone.sync();
    const updated = JSON.parse((await call('update_note', { id: 't1', body: '---\ntype: ticket\nid: GHO-7\nstatus: In review\n---\n# Fix sync\n\nIt dropped notes; fixed.' })).text) as { updated: Read };
    expect(updated.updated.body).toBe('---\ntype: ticket\nid: GHO-7\nstatus: In review\nauthors: matt, Claude\n---\n# Fix sync\n\nIt dropped notes; fixed.');
    await phone.sync();
    expect(phone.notes.get('t1')!.body).toBe(updated.updated.body);
    expect((JSON.parse((await call('read_note', { title: 'GHO-7' })).text) as Read).id).toBe('t1');
  });

  it('pins and archives for the whole team, as a row a device then takes', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('t1', '# Plan');
    await phone.sync();
    const flagged = JSON.parse((await call('set_note_flags', { id: 't1', pinned: true, archived: true })).text) as { note: Read };
    expect(flagged.note).toMatchObject({ pinned: true, archived: true });
    expect((await rowOf(service, org, 't1'))!.note).toMatchObject({ starred: true, body: '# Plan' });
    await phone.sync();
    expect(phone.notes.get('t1')).toMatchObject({ starred: true, body: '# Plan' });
    expect(phone.notes.get('t1')!.archivedAt).toBeGreaterThan(0);
    // Set back from the phone, and the connector says what the app says.
    phone.put('t1', '# Plan', { archivedAt: null });
    await phone.sync();
    expect(JSON.parse((await call('read_note', { id: 't1' })).text)).toMatchObject({ pinned: true, archived: false });
  });

  it('merges with a row another member put first, rather than writing over it', async () => {
    const { service, account } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('t1', '# Plan\n\nOne.');
    await phone.sync();
    await account.pull();
    // The phone archives it and adds a line, and puts the row, after the connector last read.
    phone.put('t1', '# Plan\n\nOne.\n\nTwo.', { path: 'Work/Plan.md' });
    await phone.sync();
    await account.edit('t1', (note) => ({ ...note, starred: true }));
    const row = (await rowOf(service, org, 't1'))!;
    expect(row.note).toMatchObject({ starred: true, path: 'Work/Plan.md', body: '# Plan\n\nOne.\n\nTwo.' });
  });

  it('keeps what else the app’s row carries - the recording, files, texts, `from`, and fields it does not know - when it puts the row again', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('t1', '# Standup\n\n## Summary\n\nShipped.');
    await phone.sync();
    // As the app's own channel puts a meeting's row (lib/team/sync.dart `_putRow`): more than this connector writes.
    const carried = { recording: 'rec-digest', files: ['deck.pdf'], texts: ['deck.pdf'], from: { account: 7, rev: 41 }, later: { anything: [1, 2] } };
    const asApp = async (extra: Record<string, unknown>, rev?: number) => {
      const row = service.teamNotes(org.id).get('t1')!;
      const opened = await open<Record<string, unknown>>(org.key, row.blob!, `org:${org.id}:note:t1`);
      const blob = await seal(org.key, { ...opened, ...extra }, `org:${org.id}:note:t1`);
      service.teamNotes(org.id).set('t1', { ...row, blob, ...(rev ? { rev } : {}) });
    };
    await asApp(carried);

    // A pin puts the row; a picture named in the words puts it too (the row lists a note's pictures).
    await call('set_note_flags', { id: 't1', pinned: true });
    let row = (await rowOf(service, org, 't1')) as unknown as Record<string, unknown> & { note: Note };
    expect(row).toMatchObject(carried);
    expect(row.note.starred).toBe(true);
    await call('append_to_note', { id: 't1', text: '![](image/pic-1.png)', as: 'paragraph' });
    row = (await rowOf(service, org, 't1')) as unknown as Record<string, unknown> & { note: Note };
    expect(row).toMatchObject({ ...carried, images: ['pic-1.png'] });
    expect(row.note.body).toContain('![](image/pic-1.png)');

    // A member's row put after the connector last read, carrying newer fields: the merge takes theirs, not the old ones.
    const newer = { recording: 'rec-digest-2', files: [], from: { account: 7, rev: 42 }, later: 'changed' };
    await asApp(newer, (service.teamNotes(org.id).get('t1')!.rev ?? 0) + 100);
    await call('set_note_flags', { id: 't1', archived: true });
    row = (await rowOf(service, org, 't1')) as unknown as Record<string, unknown> & { note: Note };
    expect(row).toMatchObject({ ...newer, texts: ['deck.pdf'] });
    expect(row.note.archivedAt).toBeGreaterThan(0);

    // And the app's own channel still reads the row it put.
    await phone.sync();
    expect(phone.notes.get('t1')).toMatchObject({ starred: true });
    expect(phone.notes.get('t1')!.body).toContain('Shipped.');
  });

  it('reads this account’s wrap at the new generation when the key turns under a write, and writes once more', async () => {
    const { service, account } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('t1', '# Plan');
    await phone.sync();
    await account.pull();
    await org.turn();
    const written = await account.edit('t1', (note) => ({ ...note, body: '# Plan\n\nAfter the turn.' }));
    expect(written.note.body).toBe('# Plan\n\nAfter the turn.');
    expect(service.calls.filter((c) => c === `POST orgs/${org.id}/notes/t1/updates`)).toHaveLength(2);
    await phone.sync({ key: org.key, generation: 2, olderKey: async () => org.keyAt(1) });
    expect(phone.notes.get('t1')!.body).toBe('# Plan\n\nAfter the turn.');
    // Turned again with no wrap for this account: refused in words, and nothing written.
    await org.turn({ wrap: false });
    await expect(account.edit('t1', (note) => ({ ...note, body: '# Lost?' }))).rejects.toThrow('Ghost’s notes cannot be written by this connector: this account has no wrap of its key at generation 3 yet');
  });

  it('makes a note in an organization the team’s from its first word, and a journal’s entry where the journal is', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('j', '---\ntitle: "Standup"\nbook: true\njournal: true\n---\n# Standup\n');
    await phone.sync();
    const made = JSON.parse((await call('create_note', { title: 'Launch', body: 'Soon.', workspace: 'ghost' })).text) as { created: Read };
    expect(made.created.workspace).toEqual({ id: `org-${org.id}`, name: 'Ghost', organization: true });
    expect(service.notes.has(made.created.id)).toBe(false);
    const entry = JSON.parse((await call('add_journal_entry', { journal: 'Standup', text: 'Shipped it.', at: '2026-10-12T09:30' })).text) as { created: Read; journal: Read };
    expect(entry.created.workspace?.name).toBe('Ghost');
    expect(service.notes.has(entry.created.id)).toBe(false);
    await phone.sync();
    expect(phone.notes.get(made.created.id)!.body).toBe('---\nauthors: matt, Claude\n---\n# Launch\n\nSoon.');
    expect(phone.notes.get(entry.created.id)!.body).toContain('Shipped it.');
    expect(phone.notes.get('j')!.body).toContain('[[2026-10-12 09.30]]');
  });
});

describe('filing', () => {
  it('puts a note to the team when it is filed in an organization, and still reads and writes it after a device edits it', async () => {
    const { service, call, account } = await connected();
    const org = await anOrganization(service);
    await account.changePrefs(() => ({ workspaces: { list: [{ id: `org-${org.id}`, name: 'Ghost' }], notes: {} } }));
    const made = JSON.parse((await call('create_note', { title: 'Claude Rules', body: 'Be brief.' })).text) as { created: Read };
    const id = made.created.id;
    expect(made.created.workspace).toBeNull();

    const filed = JSON.parse((await call('file_notes', { ids: [id], workspace: 'Ghost' })).text);
    expect(filed).toEqual({ workspace: { id: `org-${org.id}`, name: 'Ghost', organization: true }, filed: [{ id, title: 'Claude Rules' }] });
    // The team has it, the account's own row is gone as a device's would be, and the settings file it there.
    expect((await rowOf(service, org, id))!.note.body).toBe(made.created.body);
    expect(service.notes.get(id)).toMatchObject({ deleted: true });
    expect(((await account.readPrefs()).prefs.workspaces as { notes: unknown }).notes).toEqual({ [id]: `org-${org.id}` });
    expect((JSON.parse((await call('read_note', { id })).text) as Read).workspace).toEqual({ id: `org-${org.id}`, name: 'Ghost', organization: true });

    // The phone opens it, edits it and syncs: the very thing that made it vanish before.
    const phone = teamDevice(service, org);
    await phone.sync();
    phone.put(id, `${phone.notes.get(id)!.body}\n\nAnd kind.`);
    await phone.sync();
    const read = JSON.parse((await call('read_note', { id })).text) as Read;
    expect(read.body).toContain('And kind.');
    expect((JSON.parse((await call('search_notes', { query: 'kind' })).text) as Listed).notes.map((n) => n.id)).toEqual([id]);
    expect(await call('update_note', { id, body: '# Claude Rules\n\nBe brief, and kind, always.' })).toMatchObject({ isError: false });
    await phone.sync();
    expect(phone.notes.get(id)!.body).toContain('Be brief, and kind, always.');
  });

  it('carries a note’s pictures to the team, sealed again under the organization key', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    await service.deviceWrites(aNote('p1', '# Trip\n\n![](image/abc.png)\n\n![](image/missing.jpg)'));
    const picture = new Uint8Array([1, 2, 3, 4]);
    service.files.set('i-png-abc', { rev: 1, bytes: await sealBytes(service.accountKey, picture, 'file:i-png-abc') });
    const filed = JSON.parse((await call('file_notes', { ids: ['p1'], workspace: `org-${org.id}` })).text) as { picturesNotCarried?: unknown };
    expect(filed.picturesNotCarried).toEqual([{ id: 'p1', pictures: ['missing.jpg'] }]);
    expect(await openBytes(org.key, service.teamFiles(org.id).get('i-png-abc')!.bytes, 'file:i-png-abc')).toEqual(picture);
    expect((await rowOf(service, org, 'p1'))!.images).toEqual(['abc.png', 'missing.jpg']);
  });

  it('takes a note out of the team when it is unfiled, back to the account alone, and files it over a row deleted before', async () => {
    const { service, call, account } = await connected();
    const org = await anOrganization(service);
    await account.changePrefs(() => ({ workspaces: { list: [{ id: `org-${org.id}`, name: 'Ghost' }, { id: 'w1', name: 'Home' }], notes: {} } }));
    const phone = teamDevice(service, org);
    phone.put('t1', '# Plan\n\nThe team’s words.');
    await phone.sync();

    const unfiled = JSON.parse((await call('file_notes', { ids: ['t1'], workspace: 'Home' })).text);
    expect(unfiled).toEqual({ workspace: { id: 'w1', name: 'Home', organization: false }, filed: [{ id: 't1', title: 'Plan' }] });
    expect(service.teamNotes(org.id).get('t1')).toMatchObject({ deleted: true });
    expect((await service.stored('t1'))!.note.body).toBe('# Plan\n\nThe team’s words.');
    const read = JSON.parse((await call('read_note', { id: 't1' })).text) as Read;
    expect(read.workspace).toEqual({ id: 'w1', name: 'Home', organization: false });

    // And back again: over the team's deleted row, and the account's own goes.
    await call('append_to_note', { id: 't1', text: 'Mine for a while.', as: 'paragraph' });
    expect(JSON.parse((await call('file_notes', { ids: ['t1'], workspace: 'Ghost' })).text)).toMatchObject({ filed: [{ id: 't1', title: 'Plan' }] });
    expect((await rowOf(service, org, 't1'))!.note.body).toContain('Mine for a while.');
    expect(service.notes.get('t1')).toMatchObject({ deleted: true });
    expect((JSON.parse((await call('list_notes', { workspace: 'Ghost' })).text) as Listed).notes.map((n) => n.id)).toEqual(['t1']);
  });

  it('says why a note was not filed where it cannot write, and leaves it and its filing as they were', async () => {
    const { service, call, account } = await connected();
    const org = await anOrganization(service, 'HelloTrade', { wrap: false });
    await registerPair(service);
    await service.deviceWrites(aNote('p1', '# Pricing'));
    const refused = await call('file_notes', { ids: ['p1'], workspace: `org-${org.id}` });
    expect(refused.isError).toBe(true);
    expect(refused.text).toContain('Pricing (p1): HelloTrade’s notes cannot be written by this connector: this account has no wrap of its key at generation 1 yet');
    expect(service.notes.get('p1')).toMatchObject({ deleted: false });
    expect((await account.readPrefs()).prefs.workspaces).toBeUndefined();
  });
});

describe('an AI in an organization', () => {
  const posts = (service: { calls: string[] }) => service.calls.filter((c) => c.startsWith('POST orgs/') && c.endsWith('/ais'));

  it('is told to each organization it reads, by the name its app gave, once a session and not once a call', async () => {
    const { service, call, account } = await connected();
    const ghost = await anOrganization(service, 'Ghost');
    const trade = await anOrganization(service, 'HelloTrade');
    // An organization it cannot read has not been accessed, and is told nothing.
    const sealed = await anOrganization(service, 'Sealed', { wrap: false });
    await call('list_notes');
    await call('search_notes', { query: 'anything' });
    await call('account_status');
    expect(posts(service).sort()).toEqual([`POST orgs/${ghost.id}/ais`, `POST orgs/${trade.id}/ais`].sort());
    expect(service.aisOf(ghost.id)).toMatchObject([{ name: 'Claude', via: 'matt' }]);
    expect(service.aisOf(trade.id)).toMatchObject([{ name: 'Claude', via: 'matt' }]);
    expect(service.aisOf(sealed.id)).toEqual([]);
    // It is a record: no member, no wrap, nothing owed by the key.
    expect(service.orgs.get(ghost.id)!.rows.size).toBe(1);
    expect(service.keysOf(ghost.id)).toMatchObject({ generation: 1 });
    expect(Object.keys(service.keysOf(ghost.id).wraps)).toEqual(['matt']);

    // Its wrap made, the third is read, and told then; and the others are told again only hours on.
    await sealed.wrapNow();
    await call('list_notes');
    expect(posts(service)).toHaveLength(3);
    const first = service.aisOf(ghost.id)[0]!;
    const teams = (account as unknown as { teams: { announce(name: string, now: number): Promise<void> } }).teams;
    await teams.announce('Claude', Date.now() + 5 * 60 * 60_000);
    expect(posts(service)).toHaveLength(3);
    await teams.announce('Claude', Date.now() + 7 * 60 * 60_000);
    expect(posts(service)).toHaveLength(6);
    expect(service.aisOf(ghost.id)).toMatchObject([{ id: first.id, firstSeen: first.firstSeen }]);
  });

  it('carries what another app calls itself', async () => {
    const { service, call } = await connected({ clientName: 'Cursor' });
    const org = await anOrganization(service);
    await call('list_notes');
    expect(service.aisOf(org.id)).toMatchObject([{ name: 'Cursor', via: 'matt' }]);
  });

  it('never fails a tool: a service without the route, and one that refuses or drops the call, answer the notes all the same', async () => {
    for (const how of ['no route', 'refused', 'dropped'] as const) {
      const service = await fakeService({ handle: 'matt', password: 'correct horse' }, { ais: how !== 'no route' ? true : false });
      const org = await anOrganization(service);
      const phone = teamDevice(service, org);
      phone.put('t1', '# Plan');
      await phone.sync();
      const fetcher: typeof fetch = async (input, init) => {
        if (how !== 'no route' && String(input).endsWith('/ais')) {
          if (how === 'dropped') throw new TypeError('Failed to fetch');
          return new Response(JSON.stringify({ error: 'Too many changes in a minute. Try again shortly.' }), { status: 429 });
        }
        return service.fetcher(input, init);
      };
      const account = new GlyphAccount(await GlyphAccount.signIn(API, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher }), { fetcher });
      account.actsAs('Claude');
      await account.pull();
      expect((await account.get('t1'))?.note.body, how).toBe('# Plan');
      expect(account.notices(), how).toEqual([]);
      const written = await account.edit('t1', (note) => ({ ...note, body: '# Plan\n\nStill written.' }));
      expect(written.note.body, how).toBe('# Plan\n\nStill written.');
      expect(service.aisOf(org.id), how).toEqual([]);
    }
  });
});
