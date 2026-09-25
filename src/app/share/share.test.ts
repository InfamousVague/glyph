import { describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { noteTitle } from '../core/store.ts';
import { bookNoteBody, chaptersOf } from '../book/book.ts';
import { forkShared, newShareId, newShareKey, openShare, readShareLink, sealShare, shareLink, sharedAsFile, sharedOf, withPictures, type Shared } from './share.ts';
import { crc32, zipFiles } from './zip.ts';


describe('a share sealed by its link', () => {
  it('opens with its own key and with no other, and the link carries both halves after the #', async () => {
    const shared: Shared = { v: 1, kind: 'note', title: 'Packing', pages: [{ title: 'Packing', body: '# Packing\n\n- [ ] Tent' }], at: 1 };
    const key = newShareKey();
    const blob = await sealShare(shared, key);
    expect(blob).not.toContain('Tent');
    expect(await openShare(blob, key)).toEqual(shared);
    await expect(openShare(blob, newShareKey())).rejects.toThrow();
    const id = newShareId();
    const link = shareLink(id, key);
    expect(link.split('#')[0]).not.toContain(key);
    expect(readShareLink(link)).toEqual({ id, key });
    // Pasted with words round it, or as only what follows the #.
    expect(readShareLink(`Here it is: ${link} - enjoy`)).toEqual({ id, key });
    expect(readShareLink(`${id}.${key}`)).toEqual({ id, key });
    expect(readShareLink('https://example.com/nothing')).toBeNull();
  });
});

describe('what a note or a book shares', () => {
  const book = makeNote('b', bookNoteBody('Cabin trip', ['Packing', 'Route map', 'Not written']));
  const notes = [book, makeNote('p', '# Packing\n\n- [ ] Tent'), makeNote('r', '---\ntitle: "Route map"\n---\n{"nodes":[],"edges":[]}'), makeNote('x', '# Elsewhere')];

  it('shares a note as itself, and a book as its index then every chapter that has a note, in order', () => {
    expect(sharedOf(notes[1]!, notes)).toMatchObject({ kind: 'note', title: 'Packing', pages: [{ title: 'Packing' }] });
    const shared = sharedOf(book, notes);
    expect(shared.kind).toBe('book');
    expect(shared.pages.map((p) => p.title)).toEqual(['Cabin trip', 'Packing', 'Route map']);
  });

  it('forks into a library as the reader own copies, renaming what would clash and pointing the index at the copies', async () => {
    const shared = sharedOf(book, notes);
    const saved: string[] = [];
    const first = await forkShared(shared, {
      notes: async () => [makeNote('mine', '# Packing\n\nMy own list.')],
      save: async (body) => {
        saved.push(body);
        return makeNote(`s${saved.length}`, body);
      },
    });
    expect(noteTitle(first.body)).toBe('Cabin trip');
    expect(saved.map((b) => noteTitle(b))).toEqual(['Cabin trip', 'Packing (shared)', 'Route map']);
    expect(chaptersOf(saved[0]!).map((c) => c.title)).toEqual(['Packing (shared)', 'Route map', 'Not written']);
  });

  it('downloads a note as its Markdown and a book as a zip of its pages', async () => {
    const one = sharedAsFile(sharedOf(notes[1]!, notes));
    expect(one.name).toBe('Packing.md');
    expect(await one.blob.text()).toBe('# Packing\n\n- [ ] Tent');
    const many = sharedAsFile(sharedOf(book, notes));
    expect(many.name).toBe('Cabin trip.zip');
    const bytes = new Uint8Array(await many.blob.arrayBuffer());
    // A zip: its first local file header, and its end record naming three files.
    expect([...bytes.slice(0, 4)]).toEqual([0x50, 0x4b, 0x03, 0x04]);
    const end = bytes.length - 22;
    expect([...bytes.slice(end, end + 4)]).toEqual([0x50, 0x4b, 0x05, 0x06]);
    expect(bytes[end + 8]).toBe(3);
  });
});

describe('the zip', () => {
  it('checks each file with the CRC-32 zip expects', () => {
    expect(crc32(new TextEncoder().encode('The quick brown fox jumps over the lazy dog'))).toBe(0x414fa339);
    const zip = zipFiles([{ name: 'a.md', bytes: new TextEncoder().encode('hi') }]);
    expect(new DataView(zip.buffer).getUint32(14, true)).toBe(crc32(new TextEncoder().encode('hi')));
  });
});

describe('the pictures a share carries', () => {
  const jpeg = (n: number, size = 8) => new Uint8Array(size).fill(n);
  const A = 'aaaa1111-0000-4000-8000-000000000001.jpg';
  const B = 'bbbb2222-0000-4000-8000-000000000002.jpg';
  const C = 'cccc3333-0000-4000-8000-000000000003.jpg';
  const paged: Shared = {
    v: 1,
    kind: 'book',
    title: 'Trading',
    pages: [
      { title: 'Trading', body: '# Trading\n\n- [[Orders]]\n- [[Fills]]' },
      { title: 'Orders', body: `# Orders\n\n![The ticket](image/${A})\n\n![Again](image/${A})` },
      { title: 'Fills', body: `# Fills\n\n![The fill](image/${B})\n\n![Gone](image/${C})` },
    ],
    at: 1,
  };

  it('seals them with the words and opens them byte for byte, and a share without any is sealed as before', async () => {
    const key = newShareKey();
    const shared: Shared = { ...paged, pictures: { [A]: jpeg(1, 300), [B]: jpeg(2, 40) } };
    const opened = await openShare(await sealShare(shared, key), key);
    expect(opened.pages).toEqual(paged.pages);
    expect(opened.pictures?.[A]).toEqual(jpeg(1, 300));
    expect(opened.pictures?.[B]).toEqual(jpeg(2, 40));
    expect(await openShare(await sealShare(paged, key), key)).toEqual(paged);
  });

  it('refuses a picture named to reach outside the picture store', async () => {
    const key = newShareKey();
    const opened = await openShare(await sealShare({ ...paged, pictures: { '../../evil.jpg': jpeg(9), [B]: jpeg(2) } }, key), key);
    expect(Object.keys(opened.pictures ?? {})).toEqual([B]);
    expect(opened.pictures?.[B]).toEqual(jpeg(2));
  });

  it('carries the pictures the pages show, once each, leaving out one this device lacks', async () => {
    const read = vi.fn(async (name: string) => (name === C ? null : jpeg(name === A ? 1 : 2)));
    const { shared, lacked } = await withPictures(paged, { read, smaller: async (bytes) => bytes });
    expect(Object.keys(shared.pictures ?? {})).toEqual([A, B]);
    expect(lacked).toEqual([C]);
    expect(read.mock.calls.map((c) => c[0])).toEqual([A, B, C]);
  });

  it('draws them smaller when they would not fit, and then keeps as many as fit', async () => {
    const words = new TextEncoder().encode(JSON.stringify(paged)).length;
    const read = async (name: string) => (name === C ? null : jpeg(1, 1000));
    // Room for both only once each is drawn at a tenth.
    const shrunk = (await withPictures(paged, { read, smaller: async (bytes) => bytes.slice(0, 100) }, words + 500)).shared;
    expect(Object.values(shrunk.pictures ?? {}).map((b) => b.length)).toEqual([100, 100]);
    // Room for one, even smaller: the first the pages show.
    const one = await withPictures(paged, { read, smaller: async (bytes) => bytes.slice(0, 400) }, words + 500);
    expect(Object.keys(one.shared.pictures ?? {})).toEqual([A]);
    // Left out for room, not lacked: B is here, so it is not looked for again.
    expect(one.lacked).toEqual([C]);
  });

  it('downloads the pictures beside the pages, and a note with pictures as a zip', async () => {
    const note: Shared = { v: 1, kind: 'note', title: 'Orders', pages: [paged.pages[1]!], at: 1, pictures: { [A]: jpeg(1) } };
    const file = sharedAsFile(note);
    expect(file.name).toBe('Orders.zip');
    const bytes = new Uint8Array(await file.blob.arrayBuffer());
    const text = new TextDecoder('latin1').decode(bytes);
    expect(text).toContain('Orders.md');
    expect(text).toContain(`image/${A}`);
    expect(bytes[bytes.length - 22 + 8]).toBe(2);
  });

  it('keeps them in a saved copy, under their own names', async () => {
    const kept: string[] = [];
    await forkShared(
      { ...paged, pictures: { [A]: jpeg(1), [B]: jpeg(2) } },
      {
        notes: async () => [],
        save: async (body) => makeNote(`s-${body.length}`, body),
        keep: async (name) => {
          kept.push(name);
        },
      },
    );
    expect(kept).toEqual([A, B]);
  });
});
