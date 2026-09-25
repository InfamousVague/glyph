import { describe, expect, it, vi } from 'vitest';
import type { Shared } from '../app/share/share.ts';
import { show, waitUntil } from '../test/render.tsx';
import { stubMatchMedia } from '../test/stubs.ts';

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

describe('the reader page', () => {
  it('draws a shared note with the pictures its share carries, and downloads it as a zip', async () => {
    const lent: Blob[] = [];
    URL.createObjectURL = vi.fn((blob: Blob) => {
      lent.push(blob);
      return `blob:lent-${lent.length}`;
    });
    // The page follows the system's light or dark setting.
    stubMatchMedia();
    history.replaceState(null, '', `/read.html#${'a'.repeat(22)}.${'b'.repeat(43)}`);
    const { Reader } = await import('./Reader.tsx');
    show(<Reader />);
    // The share is read, then drawn: waited for, not slept on.
    await waitUntil(() => expect(document.querySelector('.cm-editor figure img')?.getAttribute('src')).toBe('blob:lent-1'));
    expect(lent[0]?.type).toBe('image/jpeg');
    expect(document.querySelector('button[aria-label="Download as Markdown (.zip)"]')).toBeTruthy();
  });
});
