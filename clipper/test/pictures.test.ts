import { describe, expect, it } from 'vitest';
import { fileId } from '../../tauri/src/app/core/sync/notes.ts';
import { fromDataUrl, linkedWords, pictureName, placePictures, resolvePictures, type Fetched, type PictureFetcher } from '../src/core/pictures.ts';

/** The pictures of a clip: which are stored and which stay links, and the words each leaves in the note. */

const JPEG = Uint8Array.of(0xff, 0xd8, 0xff, 0xe0, 1, 2, 3) as Uint8Array<ArrayBuffer>;
const shrink = async (picture: Fetched) => (picture.type === 'image/svg+xml' ? null : JPEG);

function fetcher(table: Record<string, Fetched | 'too-big'>): PictureFetcher {
  return async (url) => table[url] ?? null;
}

describe('pictures', () => {
  it('are stored, or linked with a reason, in the order the page has them', async () => {
    const png: Fetched = { type: 'image/png', bytes: new Uint8Array(10) as Uint8Array<ArrayBuffer> };
    const placed = await resolvePictures(
      [
        { url: 'https://a.example/one.png', alt: 'one' },
        { url: 'https://a.example/huge.png', alt: 'huge' },
        { url: 'https://cdn.example/two.png', alt: 'two' },
        { url: 'https://a.example/logo.svg', alt: 'logo' },
        { url: 'https://nowhere.example/x.png', alt: 'gone' },
      ],
      {
        // The page first, then the clipper itself where the person allowed a site: the second has what the first could not.
        fetchers: [fetcher({ 'https://a.example/one.png': png, 'https://a.example/huge.png': 'too-big', 'https://a.example/logo.svg': { type: 'image/svg+xml', bytes: png.bytes } }), fetcher({ 'https://cdn.example/two.png': png })],
        shrink,
      },
    );
    expect(placed.stored.map((s) => s.index)).toEqual([0, 2]);
    expect(placed.stored.every((s) => s.bytes === JPEG)).toBe(true);
    expect(placed.linked).toEqual([
      { index: 1, url: 'https://a.example/huge.png', why: 'too-big' },
      { index: 3, url: 'https://a.example/logo.svg', why: 'unreadable' },
      { index: 4, url: 'https://nowhere.example/x.png', why: 'not-reachable' },
    ]);
  });

  it('past the most a clip keeps, and over the size limit after fetching, are links', async () => {
    const big: Fetched = { type: 'image/png', bytes: new Uint8Array(20) as Uint8Array<ArrayBuffer> };
    const placed = await resolvePictures(
      [
        { url: 'https://a.example/1.png', alt: '' },
        { url: 'https://a.example/2.png', alt: '' },
      ],
      { fetchers: [async () => big], shrink, limit: 10, most: 1 },
    );
    expect(placed.linked.map((l) => l.why)).toEqual(['too-big', 'too-many']);
  });

  it('carried inline by the page are read without a fetch, and left out where they cannot be stored', async () => {
    expect(fromDataUrl('data:image/png;base64,iVBORw0K')?.bytes.slice(0, 4)).toEqual(Uint8Array.of(0x89, 0x50, 0x4e, 0x47));
    expect(fromDataUrl('data:text/html,hi')).toBeNull();
    const pictures = [{ url: 'data:image/svg+xml,%3Csvg%3E', alt: 'inline' }];
    const placed = await resolvePictures(pictures, { fetchers: [], shrink });
    expect(placed.linked[0]!.why).toBe('unreadable');
    expect(placePictures('Before\n\n![inline](ghost-clip:picture/0)\n\nAfter\n', pictures, placed)).toBe('Before\n\nAfter\n');
  });

  it('are written where they now are: image/<name> as the app writes it, or their own address', () => {
    const pictures = [
      { url: 'https://a.example/one.png', alt: 'one' },
      { url: 'https://a.example/a (b).png', alt: 'two' },
    ];
    const words = placePictures('![one](ghost-clip:picture/0) and ![two](ghost-clip:picture/1)', pictures, {
      stored: [{ index: 0, name: 'clip-abc.jpg', bytes: JPEG }],
      linked: [{ index: 1, url: pictures[1]!.url, why: 'not-reachable' }],
    });
    expect(words).toBe('![one](image/clip-abc.jpg) and ![two](https://a.example/a%20%28b%29.png)');
  });

  it('are named so the service takes the name and the phone keeps the file', () => {
    const name = pictureName();
    expect(name).toMatch(/^clip-[A-Za-z0-9_-]+\.jpg$/);
    const id = fileId('image', name);
    expect(id).not.toBeNull();
    expect(id!.length).toBeLessThanOrEqual(64);
    expect(pictureName()).not.toBe(name);
  });

  it('are counted in words', () => {
    expect(linkedWords(1)).toBe('1 picture stays a link');
    expect(linkedWords(3)).toBe('3 pictures stay links');
  });
});
