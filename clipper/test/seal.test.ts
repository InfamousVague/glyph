import { describe, expect, it } from 'vitest';
import { GlyphAccount } from '../../mcp/glyph.ts';
import { bookNoteBody } from '../../tauri/src/app/book/book.ts';
import { API_BASE } from '../../tauri/src/app/core/account/api.ts';
import { fromBase64Url, open, openBytes } from '../../tauri/src/app/core/sync/crypto.ts';
import { fileId, type NotePayload } from '../../tauri/src/app/core/sync/notes.ts';
import { fakeService, FAST } from '../../tauri/src/test/fakeService.ts';
import { makeNote } from '../../tauri/src/test/notes.ts';
import { ClipperAccount } from '../src/core/account.ts';
import { keeper, memoryRooms } from '../src/core/keep.ts';
import { extract } from '../src/core/page.ts';
import type { Fetched } from '../src/core/pictures.ts';
import { saveClip } from '../src/core/save.ts';
import { loadPage } from './support.ts';

/**
 * A clip saved through the clipper's account and read back by everything else that holds the account: the app's
 * own crypto (core/sync/crypto.ts) opening what the service keeps, and the connector's `GlyphAccount` (mcp/glyph.ts)
 * reading the note, its filing and its notebook as Claude would. And the service, which is the fake service the
 * app's and the connector's tests use (src/test/fakeService.ts), never sees a word of it, or the password.
 */

const AT = new Date(2026, 9, 16, 17, 42);
const JPEG = Uint8Array.of(0xff, 0xd8, 0xff, 0xe0, 0, 16, 74, 70, 73, 70, 0xff, 0xd9) as Uint8Array<ArrayBuffer>;

async function world() {
  const service = await fakeService({ handle: 'matt', password: 'correct horse' });
  // What travels, as the service is handed it: every request body, to look for words in.
  const sent: string[] = [];
  const fetcher: typeof fetch = async (input, init) => {
    const body = init?.body;
    sent.push(typeof body === 'string' ? body : body instanceof Uint8Array ? new TextDecoder('latin1').decode(body) : '');
    return service.fetcher(input, init);
  };
  // The connector, as another client of the account: a workspace in the settings, and a notebook with a page.
  const claude = new GlyphAccount(await GlyphAccount.signIn(API_BASE, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher }), { fetcher: service.fetcher });
  await claude.changePrefs((prefs) => ({ ...prefs, workspaces: { list: [{ id: 'w-garden', name: 'Garden' }, { id: 'org-team1', name: 'The team' }], notes: {}, current: null } }));
  await service.deviceWrites(makeNote('book-reading', bookNoteBody('Reading list', ['An older page']), { createdAt: 1, updatedAt: 1 }));
  sent.length = 0;
  const clipper = await ClipperAccount.signIn('matt', 'correct horse', { stay: false, keeper: keeper({ ...memoryRooms(), api: API_BASE }), rounds: FAST, fetcher });
  return { service, sent, claude, clipper };
}

describe('a clip, sealed', () => {
  it('is opened by the app’s own crypto, with its pictures, and filed as the connector reads it', async () => {
    const { service, sent, clipper } = await world();
    const page = extract(loadPage('article'), 'article');
    const png: Fetched = { type: 'image/png', bytes: Uint8Array.of(0x89, 0x50, 0x4e, 0x47) as Uint8Array<ArrayBuffer> };
    const saved = await saveClip(
      clipper,
      { ...page, tags: ['reading', 'garden'], comment: 'For the spring planting.', workspace: 'w-garden', notebook: 'book-reading' },
      { fetchers: [async () => png], shrink: async () => JPEG, now: () => AT },
    );
    expect(saved).toMatchObject({ title: 'The Quiet Garden', stored: 2, linked: [], workspace: 'w-garden', notebook: 'book-reading' });

    // The note, opened as any device of the account opens one.
    const payload = (await service.stored(saved.id)) as NotePayload;
    const body = payload.note.body;
    expect(body.startsWith('---\nsource: https://field.example/2026/10/the-quiet-garden\nclipped: 2026-10-16\ntags: [reading, garden]\n---\n# The Quiet Garden\n\nFor the spring planting.\n\n---\n\nMost of the work')).toBe(true);
    expect(payload.note).toMatchObject({ id: saved.id, source: 'editor', starred: false, archivedAt: null, createdAt: AT.getTime() });
    expect(payload.images).toHaveLength(2);
    expect(body).toContain(`![Three raised beds under straw](image/${payload.images![0]})`);
    expect(body).not.toContain('ghost-clip:');

    // Each picture, sealed as the app seals a file, under its own id.
    for (const name of payload.images!) {
      const id = fileId('image', name)!;
      const kept = service.files.get(id)!;
      expect(await openBytes(service.accountKey, kept.bytes, `file:${id}`)).toEqual(JPEG);
    }

    // Nothing the service was handed says what the page says, or what the password was.
    const everything = sent.join('\n');
    // The note, both pictures, the settings and the notebook were all sent: the search below has something to search.
    expect(sent.filter((b) => b.includes('"blob"')).length).toBeGreaterThanOrEqual(3);
    expect(everything.length).toBeGreaterThan(2000);
    for (const words of ['Quiet Garden', 'spring planting', 'twice the harvest', 'correct horse', 'field.example']) expect(everything).not.toContain(words);
    const blob = fromBase64Url(service.notes.get(saved.id)!.blob!);
    expect(new TextDecoder('latin1').decode(blob)).not.toContain('Garden');
  });

  it('reads back through the connector: the note, its workspace and its page in the notebook', async () => {
    const { service, clipper } = await world();
    const page = extract(loadPage('table-code', 'https://docs.example/sorting/'), 'page');
    const saved = await saveClip(clipper, { ...page, tags: [], comment: '', workspace: 'w-garden', notebook: 'book-reading' }, { fetchers: [], shrink: async () => JPEG, now: () => AT });
    const claude = new GlyphAccount(await GlyphAccount.signIn(API_BASE, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher }), { fetcher: service.fetcher });
    const read = await claude.get(saved.id);
    expect(read?.note.body).toContain('| Method | Average | Stable |');
    expect(read?.note.body).toContain('```js\nfunction insertionSort(a) {');
    const { prefs } = await claude.readPrefs();
    expect((prefs.workspaces as { notes: Record<string, string> }).notes[saved.id]).toBe('w-garden');
    const book = await claude.get('book-reading');
    expect(book?.note.body).toContain('- [[An older page]]\n- [[Sorting in place]]');
    // The settings the clipper did not touch are as the connector left them.
    expect((prefs.workspaces as { list: unknown[] }).list).toHaveLength(2);
  });

  it('takes a title no other note has when it goes into a notebook, whose pages are linked by title', async () => {
    const { service, clipper } = await world();
    await service.deviceWrites(makeNote('same', '# The Quiet Garden\n\nAlready here.'));
    const page = extract(loadPage('article'), 'bookmark');
    const saved = await saveClip(clipper, { ...page, tags: [], comment: '', workspace: null, notebook: 'book-reading' }, { fetchers: [], shrink: async () => JPEG, now: () => AT });
    expect(saved.title).toBe('The Quiet Garden (2)');
    expect(saved.linked).toEqual([{ url: 'https://field.example/pictures/garden-wide.png', why: 'not-reachable' }]);
    const payload = (await service.stored(saved.id))!;
    expect(payload.note.body).toContain('# The Quiet Garden (2)\n\n[field.example/2026/10/the-quiet-garden](https://field.example/2026/10/the-quiet-garden)\n\nHow a small city garden');
    expect(payload.note.body).toContain('![The Quiet Garden](https://field.example/pictures/garden-wide.png)');
    expect((await service.stored('book-reading'))!.note.body).toContain('- [[The Quiet Garden (2)]]');
  });

  it('is never filed in an organization’s workspace, which only the team’s own channel writes', async () => {
    const { clipper, claude } = await world();
    const page = extract(loadPage('article'), 'bookmark');
    const saved = await saveClip(clipper, { ...page, tags: [], comment: '', workspace: 'org-team1', notebook: null }, { fetchers: [], shrink: async () => JPEG, now: () => AT });
    const { prefs } = await claude.readPrefs();
    expect((prefs.workspaces as { notes: Record<string, string> }).notes[saved.id]).toBeUndefined();
  });

  it('is sealed so another account’s key, or another note’s context, cannot open it', async () => {
    const { service, clipper } = await world();
    const saved = await saveClip(clipper, { mode: 'page', url: 'https://x.example/', title: 'X', markdown: 'Words.\n', pictures: [], tags: [], comment: '', workspace: null, notebook: null }, { fetchers: [], shrink: async () => JPEG });
    const blob = service.notes.get(saved.id)!.blob!;
    await expect(open(service.accountKey, blob, 'note:another-id')).rejects.toThrow();
    const stranger = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
    await expect(open(stranger, blob, `note:${saved.id}`)).rejects.toThrow();
  });
});
