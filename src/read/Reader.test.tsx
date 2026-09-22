import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import type { Shared } from '../app/share/share.ts';

/**
 * The reader page draws a shared note's pictures from the share itself (Matt: "Images for notes are not loading on
 * the attack.fm/glyph/read.html"): the page has no account and no picture store of its own.
 */

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

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: Root | null = null;
let host: HTMLDivElement | null = null;

afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  root = null;
  host = null;
});

describe('the reader page', () => {
  it('draws a shared note with the pictures its share carries, and downloads it as a zip', async () => {
    const lent: Blob[] = [];
    URL.createObjectURL = vi.fn((blob: Blob) => {
      lent.push(blob);
      return `blob:lent-${lent.length}`;
    });
    // The page follows the system's light or dark setting.
    window.matchMedia = vi.fn(() => ({ matches: false, addEventListener: () => undefined, removeEventListener: () => undefined }) as unknown as MediaQueryList);
    history.replaceState(null, '', `/read.html#${'a'.repeat(22)}.${'b'.repeat(43)}`);
    const { Reader } = await import('./Reader.tsx');
    host = document.createElement('div');
    document.body.appendChild(host);
    root = createRoot(host);
    await act(async () => {
      root!.render(<Reader />);
    });
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 20));
    });
    const img = document.querySelector<HTMLImageElement>('.cm-editor figure img');
    expect(img?.getAttribute('src')).toBe('blob:lent-1');
    expect(lent[0]?.type).toBe('image/jpeg');
    expect(document.querySelector('button[aria-label="Download as Markdown (.zip)"]')).toBeTruthy();
  });
});
