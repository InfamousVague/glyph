import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { Shared } from '../app/share/share.ts';
import { show, unmount, waitUntil } from '../test/render.tsx';

/*
 * Read | Markdown on the reader page (Matt, 2026-10-29: "make code view a segmented toggle that's off by default on the
 * web preview page"): a shared page opens drawn as a page (Rendered.tsx), Markdown is its source in the app's editor,
 * and the choice is this browser's, kept in localStorage and read as Read where storage cannot be read. Drawn from the
 * tree the app's parser makes, so nothing in a note runs.
 */

await vi.hoisted(async () => (await import('../test/stubs.ts')).stubMatchMedia());

const PICTURE = 'aaaa1111-0000-4000-8000-000000000001.jpg';
const sample = [
  '---',
  'location: 51.5074,-0.1278',
  '---',
  '# Field notes',
  '',
  'Some **bold** words, some *slanted*, `code`, ~~gone~~, and [a link](https://example.com/page) and [a trap](javascript:alert(1)).',
  '',
  '## To do',
  '',
  '- [ ] Book the venue',
  '- [x] Pick the weekend',
  '',
  '1. First',
  '2. Second',
  '',
  '| Item | Cost |',
  '| :--- | ---: |',
  '| Cabin | 200 |',
  '| Train | 45 |',
  '',
  '> A quote.',
  '',
  '```js',
  'const a = 1;',
  '```',
  '',
  `![The ticket](image/${PICTURE})`,
  '',
  'See [[Trees]] and [[Not shared]].',
  '',
  '<script>window.ran = true</script>',
  '',
  'Inline <img src=x onerror="window.ran = true"> html.',
].join('\n');

const shared = (body: string, extra: Partial<Shared> = {}): Shared => ({ v: 1, kind: 'note', title: 'Field notes', pages: [{ title: 'Field notes', body }], at: 1, ...extra });

vi.mock('../app/share/share.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../app/share/share.ts')>()),
  readShared: vi.fn(async () => shared(sample, { pictures: { [PICTURE]: new Uint8Array([0xff, 0xd8, 0xff, 0xe0]) } })),
}));
vi.mock('leaflet', () => ({ default: {} }));
vi.mock('leaflet/dist/leaflet.css', () => ({}));

const { Reader } = await import('./Reader.tsx');
const { readShared } = await import('../app/share/share.ts');
const { READ_MODE_KEY } = await import('./readMode.ts');

const segment = (label: string) => [...document.querySelectorAll<HTMLElement>('[role="radio"], label, button')].find((el) => el.textContent?.trim() === label);
const group = (name: string) => document.querySelector(`[aria-label="${name}"]`);

beforeEach(() => {
  localStorage.clear();
  URL.createObjectURL = vi.fn(() => 'blob:picture');
  history.replaceState(null, '', `/read.html#${'a'.repeat(22)}.${'b'.repeat(43)}`);
  delete (window as { ran?: boolean }).ran;
});
afterEach(() => vi.restoreAllMocks());

async function opened() {
  show(<Reader />);
  await waitUntil(() => expect(document.querySelector('[role="dialog"]')).toBeTruthy());
  act(() => void document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' })));
}

describe('Read | Markdown', () => {
  it('opens on Read, the page drawn as a page, and Markdown is its source, kept for this browser', async () => {
    await opened();
    await waitUntil(() => expect(document.querySelector('h1')?.textContent).toBe('Field notes'));
    expect(group('Read or Markdown')).toBeTruthy();
    expect(document.querySelector('.cm-editor')).toBeNull();
    expect(localStorage.getItem(READ_MODE_KEY)).toBeNull();
    act(() => segment('Markdown')!.click());
    await waitUntil(() => expect(document.querySelector('.cm-editor')).toBeTruthy());
    expect(localStorage.getItem(READ_MODE_KEY)).toBe('markdown');
    // Opened again in this browser: Markdown, as it was left.
    unmount();
    await opened();
    await waitUntil(() => expect(document.querySelector('.cm-editor')).toBeTruthy());
    act(() => segment('Read')!.click());
    await waitUntil(() => expect(document.querySelector('.cm-editor')).toBeNull());
    expect(localStorage.getItem(READ_MODE_KEY)).toBe('read');
  });

  it('reads as Read where the browser keeps nothing', async () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('SecurityError');
    });
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('SecurityError');
    });
    await opened();
    await waitUntil(() => expect(document.querySelector('h1')?.textContent).toBe('Field notes'));
    expect(document.querySelector('.cm-editor')).toBeNull();
    act(() => segment('Markdown')!.click());
    await waitUntil(() => expect(document.querySelector('.cm-editor')).toBeTruthy());
  });

  it('draws headings, a task list, a table, links that open in a new tab, a picture from the share, and runs nothing', async () => {
    await opened();
    await waitUntil(() => expect(document.querySelector('h2')?.textContent).toBe('To do'));
    expect(document.body.textContent).not.toContain('location:');
    expect(document.querySelector('p strong')?.textContent).toBe('bold');
    expect(document.querySelector('p em')?.textContent).toBe('slanted');
    expect(document.querySelector('p code')?.textContent).toBe('code');
    expect(document.querySelector('p del')?.textContent).toBe('gone');
    const link = [...document.querySelectorAll('a')].find((a) => a.textContent === 'a link')!;
    expect(link.getAttribute('href')).toBe('https://example.com/page');
    expect(link.getAttribute('target')).toBe('_blank');
    expect(link.getAttribute('rel')).toBe('noopener noreferrer');
    // Not a link at all: only http, https and mailto are.
    expect([...document.querySelectorAll('a')].some((a) => a.getAttribute('href')?.startsWith('javascript'))).toBe(false);
    expect(document.body.textContent).toContain('a trap');
    const boxes = [...document.querySelectorAll<HTMLInputElement>('li input[type="checkbox"]')];
    expect(boxes.map((b) => [b.checked, b.disabled, b.closest('li')?.textContent])).toEqual([
      [false, true, 'Book the venue'],
      [true, true, 'Pick the weekend'],
    ]);
    expect([...document.querySelectorAll('ol li')].map((li) => li.textContent)).toEqual(['First', 'Second']);
    expect([...document.querySelectorAll('thead th')].map((th) => th.textContent)).toEqual(['Item', 'Cost']);
    expect([...document.querySelectorAll('tbody tr')].map((tr) => [...tr.querySelectorAll('td')].map((td) => td.textContent))).toEqual([
      ['Cabin', '200'],
      ['Train', '45'],
    ]);
    expect(document.querySelectorAll<HTMLElement>('tbody td')[1]!.style.textAlign).toBe('right');
    expect(document.querySelector('blockquote')?.textContent).toBe('A quote.');
    expect(document.querySelector('pre code')?.textContent).toBe('const a = 1;');
    expect(document.querySelector('img[alt="The ticket"]')?.getAttribute('src')).toBe('blob:picture');
    // The note's own HTML is its text, and nothing of it ran or became an element.
    expect(document.body.textContent).toContain('<script>window.ran = true</script>');
    expect(document.querySelector('main script')).toBeNull();
    expect(document.querySelector('img[src="x"]')).toBeNull();
    expect((window as { ran?: boolean }).ran).toBeUndefined();
    // A wiki link to no page of the share is its words.
    expect(document.body.textContent).toContain('See Trees and Not shared.');
  });

  it('opens a notebook’s chapter by its wiki link, and has the toggle over a chapter too', async () => {
    const index = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Trees]]\n- [[Birds]]\n';
    vi.mocked(readShared).mockResolvedValueOnce({
      v: 1,
      kind: 'book',
      title: 'Field guide',
      pages: [
        { title: 'Field guide', body: index },
        { title: 'Trees', body: '# Trees\n\nOaks. See [[Birds]].' },
        { title: 'Birds', body: '# Birds\n\n- [ ] Robins' },
      ],
      at: 1,
    });
    await opened();
    await waitUntil(() => expect(document.querySelector('ol[aria-label="Pages"]')).not.toBeNull());
    act(() => [...document.querySelectorAll<HTMLButtonElement>('ol[aria-label="Pages"] button')].find((b) => b.textContent?.includes('Trees'))!.click());
    await waitUntil(() => expect(document.querySelector('h1')?.textContent).toBe('Trees'));
    expect(group('Read or Markdown')).toBeTruthy();
    act(() => [...document.querySelectorAll('button')].find((b) => b.textContent === 'Birds' && !b.closest('nav'))!.click());
    await waitUntil(() => expect(document.querySelector('h1')?.textContent).toBe('Birds'));
    expect(document.querySelector('li input[type="checkbox"]')).toBeTruthy();
  });

  it('on a meeting, is beside Summary | Transcript and not one of its segments, and only while the summary shows', async () => {
    const body = '# Launch sync\n\n## Summary\nWhat the call settled.\n\n- [ ] Book the venue.\n\n## Transcript\n\n**Sam (0:00):** Morning.';
    const meeting = { ms: 60000, hue: 'teal', at: 1, speakers: ['Sam'], turns: [{ s: 0, p: [[0, 2000, 'Morning.']] }] };
    vi.mocked(readShared).mockResolvedValueOnce({ ...shared(body), title: 'Launch sync', pages: [{ title: 'Launch sync', body }], meeting } as Shared);
    await opened();
    await waitUntil(() => expect(document.querySelector('h2')?.textContent).toBe('Summary'));
    const read = group('Read or Markdown')!;
    const summary = group('Summary or transcript')!;
    expect(read).toBeTruthy();
    expect(summary.contains(read)).toBe(false);
    expect(read.contains(summary)).toBe(false);
    expect(document.querySelector('li input[type="checkbox"]')).toBeTruthy();
    expect(document.body.textContent).not.toContain('Morning.');
    act(() => segment('Transcript')!.click());
    await waitUntil(() => expect(group('Read or Markdown')).toBeNull());
  });
});
