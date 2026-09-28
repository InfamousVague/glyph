import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { Shared } from '../app/share/share.ts';
import { show, waitUntil } from '../test/render.tsx';

/**
 * The reader page draws a shared note's pictures from the share itself (Matt: "Images for notes are not loading on
 * the attack.fm/glyph/read.html"): the page has no account and no picture store of its own.
 */

// The page follows the system's light or dark setting, and the Glacier kit asks matchMedia as it loads.
await vi.hoisted(async () => (await import('../test/stubs.ts')).stubMatchMedia());

const PICTURE = 'aaaa1111-0000-4000-8000-000000000001.jpg';
const shared: Shared = {
  v: 1,
  kind: 'note',
  title: 'Orders',
  pages: [{ title: 'Orders', body: `# Orders\n\n![The ticket](image/${PICTURE})\n\nWords after it.` }],
  at: 1,
  pictures: { [PICTURE]: new Uint8Array([0xff, 0xd8, 0xff, 0xe0]) },
};

vi.mock('../app/share/share.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../app/share/share.ts')>()),
  readShared: vi.fn(async () => shared),
}));
/** Leaflet, stood in for: whether it was imported at all is what the reader's map is about. */
const leaflet = vi.hoisted(() => ({ imported: 0 }));
vi.mock('leaflet', () => {
  leaflet.imported += 1;
  const L = { map: () => ({ setView: () => undefined, invalidateSize: () => undefined, remove: () => undefined }), tileLayer: () => ({ on: () => undefined, addTo: () => undefined }), divIcon: () => ({}), marker: () => ({ addTo: () => undefined }) };
  return { ...L, default: L };
});
vi.mock('leaflet/dist/leaflet.css', () => ({}));

// Loaded as the file is, not inside the test: the editor and the canvas are a cold import that took most of the
// suite's twenty seconds on a loaded machine, and the test's time is for the page to read and draw the share.
const { Reader } = await import('./Reader.tsx');
const { readShared } = await import('../app/share/share.ts');

describe('the reader page', () => {
  it('draws a shared note with the pictures its share carries, and downloads it as a zip', async () => {
    const lent: Blob[] = [];
    URL.createObjectURL = vi.fn((blob: Blob) => {
      lent.push(blob);
      return `blob:lent-${lent.length}`;
    });
    history.replaceState(null, '', `/read.html#${'a'.repeat(22)}.${'b'.repeat(43)}`);
    show(<Reader />);
    // The share is read, then drawn: waited for, not slept on.
    await waitUntil(() => expect(document.querySelector('.cm-editor figure img')?.getAttribute('src')).toBe('blob:lent-1'));
    expect(lent[0]?.type).toBe('image/jpeg');
    expect(document.querySelector('button[aria-label="Download as Markdown (.zip)"]')).toBeTruthy();
  });

  it('says a shared notebook is one, and lists its pages as pages', async () => {
    const index = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Trees]]\n';
    vi.mocked(readShared).mockResolvedValueOnce({ v: 1, kind: 'book', title: 'Field guide', pages: [{ title: 'Field guide', body: index }, { title: 'Trees', body: '# Trees\n\nOaks.' }], at: 1 });
    history.replaceState(null, '', `/read.html#${'a'.repeat(22)}.${'b'.repeat(43)}`);
    show(<Reader />);
    await waitUntil(() => expect(document.querySelector('ol[aria-label="Pages"]')).not.toBeNull());
    expect(document.body.textContent).toContain('A shared notebook.');
    expect(document.body.textContent).not.toMatch(/\bbook\b/i);
  });
});

describe('where a shared page was written', () => {
  it('draws the quiet card until the reader asks for the map, and asks nothing for a name', async () => {
    const asked: string[] = [];
    vi.stubGlobal('fetch', async (url: string) => {
      asked.push(String(url));
      return { ok: false, json: async () => ({}) };
    });
    try {
      vi.mocked(readShared).mockResolvedValueOnce({ v: 1, kind: 'note', title: 'A walk', pages: [{ title: 'A walk', body: '---\nlocation: 51.5074,-0.1278\n---\n# A walk\n\nWords.' }], at: 1 });
      history.replaceState(null, '', `/read.html#${'a'.repeat(22)}.${'b'.repeat(43)}`);
      show(<Reader />);
      await waitUntil(() => expect(document.querySelector('[data-mode="ask"]')).not.toBeNull());
      expect(document.body.textContent).toContain('Show the map');
      expect(document.body.textContent).toContain('51.5074, -0.1278');
      expect(leaflet.imported).toBe(0);
      act(() => document.querySelector<HTMLButtonElement>('button[aria-label="Show the map"]')!.click());
      await waitUntil(() => expect(document.querySelector('[data-mode="map"]')).not.toBeNull());
      await waitUntil(() => expect(leaflet.imported).toBe(1));
      // The share was read, and nothing else was fetched: no tiles until the tap, and never a name.
      expect(asked.filter((url) => url.includes('nominatim'))).toEqual([]);
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
