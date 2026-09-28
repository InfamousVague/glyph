import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Note } from '../core/store.ts';
import { makeNote } from '../../test/notes.ts';

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

const { linkFor, openShare, readShareLink, refreshShares, shareNote, shareWithPlace, shareWithPlaces, sharingPlaces } = await import('./share.ts');
const { preferences, reloadPreferences, setPreferences } = await import('../core/preferences.ts');

beforeEach(() => {
  localStorage.clear();
  setPreferences({ shares: {} });
  notes.length = 0;
  onDevice.clear();
  puts.length = 0;
});

describe('a share and the pictures it lacked', () => {
  it('is sent again when a picture it lacked arrives, and not before or after', async () => {
    const note = makeNote('n1', `# Orders\n\n![The ticket](image/${PICTURE})`);
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
    const note = makeNote('n2', '# Words\n\nNo pictures.');
    notes.push(note);
    await shareNote(note, notes);
    // As 1.6.0-13 left it: the older digest, and no list.
    const kept = { ...preferences().shares };
    kept.n2 = { ...kept.n2!, sent: 'older' };
    delete kept.n2.lacked;
    setPreferences({ shares: kept });
    expect(await refreshShares()).toBe(1);
    expect(await refreshShares()).toBe(0);
  });
});

describe('a share of a note that says where it was written', () => {
  const TAG = '---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n';
  const sentBody = async (at: number, key: string) => (await openShare(puts[at]!.blob, key)).pages[0]!.body;

  it('sends the words without the tag, and the tag only once the note says to carry it', async () => {
    const note = makeNote('n1', `${TAG}# Walk\n\nThe river.`);
    notes.push(note);
    await shareNote(note, notes);
    const { key } = readShareLink(linkFor('n1')!)!;
    // What the server holds, opened as a reader would: no location, no place.
    expect(await sentBody(0, key)).toBe('# Walk\n\nThe river.');
    // Nothing changed: the tag's absence is what was sent, so nothing goes again.
    expect(await refreshShares()).toBe(0);
    // Ticked: sent again at once, carrying both keys.
    await shareWithPlace('n1', true);
    expect(puts).toHaveLength(2);
    expect(await sentBody(1, key)).toBe(`${TAG}# Walk\n\nThe river.`);
    expect(preferences().shares.n1?.place).toBe(true);
    // Unticked: sent again without them.
    await shareWithPlace('n1', false);
    expect(puts).toHaveLength(3);
    expect(await sentBody(2, key)).toBe('# Walk\n\nThe river.');
    expect(preferences().shares.n1?.place).toBeUndefined();
  });

  it('carries the tag and never a place added later, when only the tag was ticked', async () => {
    const note = makeNote('n3', `${TAG}# Walk\n\nThe river.`);
    notes.push(note);
    await shareNote(note, notes);
    const { key } = readShareLink(linkFor('n3')!)!;
    await shareWithPlace('n3', true);
    // A place added with the + beside the line after the tick was given: the re-seal carries the tag, not the place.
    notes[0] = { ...note, body: `${TAG}# Walk\n\nThe river.\n\n[Cais](geo:38.7057,-9.1446)\n\nThe bridge.` };
    expect(await refreshShares()).toBe(1);
    const body = await sentBody(puts.length - 1, key);
    expect(body).toContain('location: 51.5074,-0.1278');
    expect(body).not.toMatch(/geo:/);
    expect(body).toContain('The bridge.');
  });

  it('carries the places once they are ticked, as a switch of their own that the settings keep', async () => {
    const note = makeNote('n4', '# Lisbon\n\n[Cais](geo:38.7057,-9.1446)');
    notes.push(note);
    await shareNote(note, notes);
    const { key } = readShareLink(linkFor('n4')!)!;
    expect(await sentBody(0, key)).toBe('# Lisbon');
    expect(sharingPlaces('n4')).toBe(false);
    await shareWithPlaces('n4', true);
    expect(await sentBody(1, key)).toBe('# Lisbon\n\n[Cais](geo:38.7057,-9.1446)');
    expect(preferences().shares.n4?.places).toBe(true);
    expect(preferences().shares.n4?.place).toBeUndefined();
    // Kept through the settings being read again, as another device reads them.
    reloadPreferences();
    expect(sharingPlaces('n4')).toBe(true);
    await shareWithPlaces('n4', false);
    expect(await sentBody(2, key)).toBe('# Lisbon');
    expect(preferences().shares.n4?.places).toBeUndefined();
  });

  it('follows a tag added after the share went, without publishing it', async () => {
    const note = makeNote('n2', '# Walk\n\nThe river.');
    notes.push(note);
    await shareNote(note, notes);
    const { key } = readShareLink(linkFor('n2')!)!;
    // "Add my location" on a note shared last week, or a tag arriving by sync: the words did not change for the reader.
    notes[0] = { ...note, body: `${TAG}# Walk\n\nThe river.` };
    expect(await refreshShares()).toBe(0);
    // A change to the words goes, still without the tag.
    notes[0] = { ...note, body: `${TAG}# Walk\n\nThe river, and the bridge.` };
    expect(await refreshShares()).toBe(1);
    expect(await sentBody(1, key)).toBe('# Walk\n\nThe river, and the bridge.');
  });
});
