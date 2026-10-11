// @vitest-environment node
import { describe, expect, it } from 'vitest';
import type { Note } from '../store.ts';
import { fakeService, type FakeService } from '../../../test/fakeService.ts';
import { makeNote } from '../../../test/notes.ts';
import { syncDevice } from '../../../test/syncDevice.ts';
import { openBytes, type Bytes } from './crypto.ts';
import { ASK_AGAIN_MS, emptyState, fileId, mark } from './notes.ts';

/**
 * Pictures reach every device, whatever road they took to the first one. Matt's HelloTrade book: another program wrote
 * the chapters through the MCP and dropped their JPEGs into the Mac's picture folder, so the Mac drew them and the
 * phone showed every one broken - the Mac had marked each as sent without sending it, and the phone, having asked once
 * when the note arrived, never asked again.
 */

/** The account both devices are signed in to, on the sync service in memory. */
const ACCOUNT = { handle: 'matt', password: 'correct horse' };

const PICTURE = 'a1b2c3d4-0000-4000-8000-000000000001.jpg';
const bytes: Bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
/** What the account holds for a file, opened: it only ever holds it sealed. */
const opened = async (key: CryptoKey, stored: { bytes: Bytes } | undefined, id: string) => (stored ? openBytes(key, stored.bytes, `file:${id}`) : null);
const chapter = makeNote('ch-1', `# Signing the order\n\n![The limit price](image/${PICTURE})\n`, { createdAt: 1, updatedAt: 2 });

/** A note written as the MCP writes one: sealed, naming its pictures, with no file sent. */
const writtenElsewhere = (api: FakeService, note: Note) => api.deviceWrites(note, { images: [PICTURE] });

describe('pictures that reached a device some other way than sync', () => {
  it('are sent by the Mac that holds them, and fetched by a phone that asked before they were there', async () => {
    const clock = { at: 1_000_000 };
    const api = await fakeService(ACCOUNT);
    const phone = syncDevice(api, { clock });
    const mac = syncDevice(api, { clock, pictures: { [PICTURE]: bytes } });
    await writtenElsewhere(api, chapter);

    // The phone reads the chapter first: the picture is not in the account, so it has nothing to draw.
    await phone.sync();
    expect(phone.notes.has('ch-1')).toBe(true);
    expect(phone.held.has(PICTURE)).toBe(false);

    // The Mac reads it, finds the picture in its own folder, and sends it.
    await mac.sync();
    const id = fileId('image', PICTURE)!;
    expect(api.files.get(id)).toBeTruthy();
    expect(mac.state.files[id]?.rev).toBeGreaterThan(0);

    // The phone's next pass a keystroke later does not ask again; the next timed pass does, and gets it.
    await phone.sync();
    expect(phone.held.has(PICTURE)).toBe(false);
    clock.at += ASK_AGAIN_MS;
    await phone.sync();
    expect(phone.held.get(PICTURE)).toEqual(bytes);
    expect(phone.state.files[id]?.rev).toBeGreaterThan(0);
  });

  it('repairs a Mac that marked a picture sent without sending it, as the older app did', async () => {
    const clock = { at: 5_000_000 };
    const api = await fakeService(ACCOUNT);
    const key = api.accountKey;
    const mac = syncDevice(api, { clock, pictures: { [PICTURE]: bytes } });
    await writtenElsewhere(api, chapter);
    await mac.sync();
    // Put back as the older app left it: the note seen, the picture at revision 0, nothing in the account.
    const id = fileId('image', PICTURE)!;
    api.files.clear();
    mac.state = { ...mac.state, files: { [id]: { rev: 0 } } };
    await mac.sync();
    expect(await opened(key, api.files.get(id), id)).toEqual(bytes);
  });

  it('does not send a picture the account already holds, and settles it by asking for its head', async () => {
    const clock = { at: 9_000_000 };
    const api = await fakeService(ACCOUNT);
    const first = syncDevice(api, { clock, pictures: { [PICTURE]: bytes } });
    first.notes.set('ch-1', chapter);
    await first.sync();
    const id = fileId('image', PICTURE)!;
    expect(api.files.get(id)).toBeTruthy();

    // Signed in again with nothing remembered, holding the same picture: one HEAD, no upload.
    api.calls.length = 0;
    first.state = emptyState();
    await first.sync();
    expect(api.calls.filter((c) => c === `PUT recordings/${id}`)).toEqual([]);
    expect(api.calls).toContain(`HEAD recordings/${id}`);
    expect(first.state.files[id]?.rev).toBeGreaterThan(0);
    // Settled: the pass after asks nothing about it.
    api.calls.length = 0;
    await first.sync();
    expect(api.calls.some((c) => c.includes(id))).toBe(false);
  });

  it('sends anyway where a HEAD cannot be asked, and a picture already there is taken as there', async () => {
    const clock = { at: 13_000_000 };
    const api = await fakeService(ACCOUNT, { head: false });
    const key = api.accountKey;
    const mac = syncDevice(api, { clock, pictures: { [PICTURE]: bytes } });
    await writtenElsewhere(api, chapter);
    await mac.sync();
    const id = fileId('image', PICTURE)!;
    expect(await opened(key, api.files.get(id), id)).toEqual(bytes);
    // Asked again with nothing remembered: the upload meets the one already there, and that settles it.
    mac.state = { ...mac.state, files: {} };
    await mac.sync();
    expect(mac.state.files[id]?.rev).toBe(api.files.get(id)?.rev);
    expect(mark(mac.notes.get('ch-1')!)).toBe(mark(chapter));
  });
});
