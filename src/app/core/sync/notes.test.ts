// @vitest-environment node
import { afterEach, describe, expect, it } from 'vitest';
import { fakeService } from '../../../test/fakeService.ts';
import { makeNote } from '../../../test/notes.ts';
import { syncDevice, type SyncDevice } from '../../../test/syncDevice.ts';
import { markShared } from '../live/shared.ts';
import type { Note } from '../store.ts';
import { fileId, mark } from './notes.ts';

/*
 * The note sync pass (notes.ts) between two devices on the service in memory: the rules a person would feel break -
 * a note typed on one arriving on the other, an edit made on both kept twice rather than lost, a deletion never
 * taking words written since, a push that lost a race merged and sent again, a blank note not sent, a note live on
 * two devices left to the live session, and a recording sent once and fetched by the other. Until this file they ran
 * only in sync.e2e.test.ts, against a real glyph-api behind an environment variable.
 */

const ACCOUNT = { handle: 'matt', password: 'correct horse' };

/** Two devices on one account. */
async function pair(): Promise<{ phone: SyncDevice; mac: SyncDevice; api: Awaited<ReturnType<typeof fakeService>> }> {
  const api = await fakeService(ACCOUNT);
  return { api, phone: syncDevice(api), mac: syncDevice(api) };
}

/** A note as a device edits it: new words, a later time. */
function edited(note: Note, body: string, at: number): Note {
  return { ...note, body, updatedAt: at };
}

afterEach(() => {
  markShared('a', false);
});

describe('a note on two devices', () => {
  it('arrives on the other device, and so does an edit to it', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', '# Groceries\n\nmilk', { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    expect(await mac.sync()).toEqual({ changed: 1, conflicts: 0 });
    expect(mac.notes.get('a')).toEqual(note);

    mac.notes.set('a', edited(note, '# Groceries\n\nmilk\neggs', 2));
    await mac.sync();
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe('# Groceries\n\nmilk\neggs');
  });

  it('does not come back to the device that wrote it as a change', async () => {
    const { phone } = await pair();
    phone.notes.set('a', makeNote('a', 'words'));
    await phone.sync();
    expect(await phone.sync()).toEqual({ changed: 0, conflicts: 0 });
  });

  it('keeps both versions when both devices changed the words, the other device’s keeping the id', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', 'shared', { createdAt: 1, updatedAt: 1, path: 'Inbox/shared.md', recordingMs: 900 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.set('a', edited(note, 'the phone’s words', 2));
    mac.notes.set('a', edited(note, 'the Mac’s words', 3));
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ conflicts: 1 });

    expect(mac.notes.get('a')?.body).toBe('the phone’s words');
    const copy = [...mac.notes.values()].find((n) => n.id !== 'a');
    expect(copy?.body).toBe('the Mac’s words');
    // The copy is the words: its recording is filed under the note's id, which the other version keeps.
    expect(copy).toMatchObject({ recordingMs: null, segments: null, path: undefined });
    // And the copy reaches the phone too, so neither device loses a word.
    await phone.sync();
    expect([...phone.notes.values()].map((n) => n.body).sort()).toEqual(['the Mac’s words', 'the phone’s words']);
  });

  it('takes the other device’s pin or archive without a copy, when only those changed on both', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', 'words', { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.set('a', { ...note, starred: true });
    mac.notes.set('a', { ...note, archivedAt: 5 });
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ conflicts: 0 });
    expect(mac.notes.size).toBe(1);
    expect(mac.notes.get('a')).toMatchObject({ starred: true });
  });
});

describe('a deletion', () => {
  it('takes the note off the other device when it had not changed there', async () => {
    const { phone, mac } = await pair();
    phone.notes.set('a', makeNote('a', 'words'));
    await phone.sync();
    await mac.sync();
    phone.notes.delete('a');
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ changed: 1 });
    expect(mac.notes.has('a')).toBe(false);
  });

  it('never takes words written since on the other device: they stand, and come back to the first', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', 'words', { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.delete('a');
    await phone.sync();
    mac.notes.set('a', edited(note, 'words written after', 4));
    await mac.sync();
    expect(mac.notes.get('a')?.body).toBe('words written after');
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe('words written after');
  });
});

describe('a push that lost a race', () => {
  /**
   * The Mac, with `meanwhile` run by another device just before the Mac's first write of note `a` reaches the service:
   * after its pull, so the push is refused with what won.
   */
  async function racing(meanwhile: (api: Awaited<ReturnType<typeof fakeService>>) => Promise<unknown>) {
    const api = await fakeService(ACCOUNT);
    let raced = false;
    const fetcher: typeof fetch = async (input, init) => {
      if (!raced && init?.method === 'PUT' && String(input).endsWith('/v1/notes/a')) {
        raced = true;
        await meanwhile(api);
      }
      return api.fetcher(input, init);
    };
    return { api, phone: syncDevice(api), mac: syncDevice(api, { fetcher }) };
  }

  it('keeps its own words as a copy when what won changed them too, and sends the copy on the next pass', async () => {
    const note = makeNote('a', 'first', { createdAt: 1, updatedAt: 1 });
    const { api, phone, mac } = await racing((service) => service.deviceWrites(edited(note, 'written elsewhere', 2)));
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    mac.notes.set('a', edited(note, 'the Mac’s edit', 3));
    expect(await mac.sync()).toMatchObject({ conflicts: 1 });
    expect(mac.notes.get('a')?.body).toBe('written elsewhere');
    expect([...mac.notes.values()].map((n) => n.body)).toContain('the Mac’s edit');
    await mac.sync();
    await phone.sync();
    expect([...phone.notes.values()].map((n) => n.body).sort()).toEqual(['the Mac’s edit', 'written elsewhere']);
    expect(api.notes.size).toBe(2);
  });

  it('sends its edit again from the deletion’s revision when what won was a deletion', async () => {
    const note = makeNote('a', 'first', { createdAt: 1, updatedAt: 1 });
    const { api, phone, mac } = await racing(async (service) => {
      const body = JSON.stringify({ base: service.notes.get('a')!.rev });
      await service.fetcher('https://glyph.test/v1/notes/a', { method: 'DELETE', headers: { Authorization: `Bearer ${service.signedIn()}` }, body });
    });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    mac.notes.set('a', edited(note, 'the Mac’s edit', 3));
    api.calls.length = 0;
    await mac.sync();
    expect(api.calls.filter((call) => call === 'PUT notes/a')).toHaveLength(2);
    expect((await api.stored('a'))?.note.body).toBe('the Mac’s edit');
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe('the Mac’s edit');
  });
});

describe('what is not sent', () => {
  it('a note opened and left empty, until it has words', async () => {
    const { api, phone, mac } = await pair();
    phone.notes.set('a', makeNote('a', '   '));
    await phone.sync();
    expect(api.notes.has('a')).toBe(false);
    phone.notes.set('a', makeNote('a', 'now words'));
    await phone.sync();
    await mac.sync();
    expect(mac.notes.get('a')?.body).toBe('now words');
  });

  it('a note live on two devices right now, neither pushed nor merged until the session ends', async () => {
    const { api, phone, mac } = await pair();
    const note = makeNote('a', 'words', { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    markShared('a', true);
    phone.notes.set('a', edited(note, 'typed live', 2));
    const before = api.notes.get('a')?.rev;
    await phone.sync();
    expect(api.notes.get('a')?.rev).toBe(before);
    await api.deviceWrites(edited(note, 'from a third device', 3));
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe('typed live');
    markShared('a', false);
    await phone.sync();
    expect(api.notes.get('a')?.rev).not.toBe(before);
  });
});

describe('a recording', () => {
  it('goes with its note, once, and is fetched by the other device', async () => {
    const { api, phone, mac } = await pair();
    const tape = new Uint8Array([82, 73, 70, 70, 1, 2, 3]);
    const note = makeNote('a', 'spoken', { createdAt: 1, updatedAt: 1, recordingMs: 1_200 });
    phone.notes.set('a', note);
    phone.tapes.set('a', tape);
    await phone.sync();
    const id = fileId('recording', 'a')!;
    expect(api.files.has(id)).toBe(true);
    await mac.sync();
    expect(mac.tapes.get('a')).toEqual(tape);

    // An edit to the words sends the note again, and not the recording, whose bytes did not move.
    api.calls.length = 0;
    phone.notes.set('a', edited(note, 'spoken, and edited', 2));
    await phone.sync();
    expect(api.calls).toContain('PUT notes/a');
    expect(api.calls.some((call) => call.startsWith(`PUT recordings/${id}`))).toBe(false);
    expect(mark(phone.notes.get('a')!)).toBe(phone.state.notes.a?.mark);
  });
});
