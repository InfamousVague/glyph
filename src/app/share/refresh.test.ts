import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Note } from '../core/store.ts';

/**
 * A share follows its pictures as well as its pages (the Glyph session, after Matt's HelloTrade link showed no
 * pictures his phone had): a picture that reaches the sharing device after the share went, by sync, changes no page,
 * so the share has to remember which it lacked and go again when one arrives - and only then.
 */

const PICTURE = 'aaaa1111-0000-4000-8000-000000000001.jpg';
const notes: Note[] = [];
const onDevice = new Map<string, Uint8Array<ArrayBuffer>>();
const puts: { path: string; blob: string }[] = [];

vi.mock('../core/store.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/store.ts')>()),
  listNotes: vi.fn(async () => notes),
}));
vi.mock('../core/account/account.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/account/account.ts')>()),
  accountState: () => ({ session: { token: 't', accountId: 1 } }),
}));
vi.mock('../core/account/api.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/account/api.ts')>()),
  call: vi.fn(async (_method: string, path: string, options: { body?: { blob?: string } }) => {
    puts.push({ path, blob: options.body?.blob ?? '' });
    return {};
  }),
}));
vi.mock('../core/images.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/images.ts')>()),
  imageBytes: vi.fn(async (name: string) => onDevice.get(name) ?? null),
}));

const { linkFor, openShare, readShareLink, refreshShares, shareNote } = await import('./share.ts');

beforeEach(() => {
  localStorage.clear();
  notes.length = 0;
  onDevice.clear();
  puts.length = 0;
});

describe('a share and the pictures it lacked', () => {
  it('is sent again when a picture it lacked arrives, and not before or after', async () => {
    const note: Note = { id: 'n1', body: `# Orders\n\n![The ticket](image/${PICTURE})`, createdAt: 0, updatedAt: 0, source: 'editor' };
    notes.push(note);
    await shareNote(note, notes);
    const { key } = readShareLink(linkFor('n1')!)!;
    expect(puts).toHaveLength(1);
    expect((await openShare(puts[0]!.blob, key)).pictures).toBeUndefined();

    // Nothing changed and the picture is still not here: nothing goes.
    expect(await refreshShares()).toBe(0);

    // It arrives by sync: the share goes again, carrying it.
    onDevice.set(PICTURE, new Uint8Array([0xff, 0xd8, 1, 2]));
    expect(await refreshShares()).toBe(1);
    expect((await openShare(puts[1]!.blob, key)).pictures?.[PICTURE]).toEqual(new Uint8Array([0xff, 0xd8, 1, 2]));

    // Sent with it: nothing more to send.
    expect(await refreshShares()).toBe(0);
    expect(puts).toHaveLength(2);
  });

  it('sends once more a share recorded before shares remembered what they lacked', async () => {
    const note: Note = { id: 'n2', body: '# Words\n\nNo pictures.', createdAt: 0, updatedAt: 0, source: 'editor' };
    notes.push(note);
    await shareNote(note, notes);
    // As 1.6.0-13 left it: the older digest, and no list.
    const kept = JSON.parse(localStorage.getItem('glyph-shares')!) as Record<string, { sent: string; lacked?: string[] }>;
    kept.n2 = { ...kept.n2!, sent: 'older' };
    delete kept.n2.lacked;
    localStorage.setItem('glyph-shares', JSON.stringify(kept));
    expect(await refreshShares()).toBe(1);
    expect(await refreshShares()).toBe(0);
  });
});
