import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { Shared } from '../app/share/share.ts';
import { show, waitUntil } from '../test/render.tsx';

/**
 * A published site, read (Site.tsx, docs/SITES.md): a notebook's pages down the side in its order, each at its own
 * address with the key kept after the #, a page's [[links]] and Previous and Next going between the site's pages
 * without leaving it, Back going back, a page the site does not have said so, and Made with Ghost.md at the foot.
 */

await vi.hoisted(async () => (await import('../test/stubs.ts')).stubMatchMedia());

const ID = 'SiteSiteSiteSiteSite01';
const KEY = 'k'.repeat(43);
const index = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n1. [[Trees]]\n2. [[Birds]]\n';
const shared: Shared = {
  v: 1,
  kind: 'book',
  title: 'Field guide',
  at: 1,
  pages: [
    { title: 'Field guide', body: index },
    { title: 'Trees', body: '# Trees\n\nOaks and ash. See [[Birds]] and [[Fish]].' },
    { title: 'Birds', body: '# Birds\n\nRobins.' },
  ],
};

vi.mock('./site.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./site.ts')>()),
  readSite: vi.fn(async () => shared),
}));

const { Site } = await import('./Site.tsx');
const { readSite } = await import('./site.ts');

const link = (words: string) => [...document.querySelectorAll('a')].find((a) => a.textContent?.includes(words));

describe('a published notebook', () => {
  it('lists its pages in order, opens each at its own address with the key kept, and says what it was made with', async () => {
    history.replaceState(null, '', `/s/${ID}#${KEY}`);
    show(<Site />);
    await waitUntil(() => expect(document.querySelector('nav[aria-label="This site’s pages"] ol')).not.toBeNull());
    expect(readSite).toHaveBeenCalledWith(ID, KEY);
    const side = document.querySelector('nav[aria-label="This site’s pages"]')!;
    expect([...side.querySelectorAll('a')].map((a) => [a.textContent, a.getAttribute('href')])).toEqual([
      ['Contents', `/s/${ID}#${KEY}`],
      ['Trees', `/s/${ID}/trees#${KEY}`],
      ['Birds', `/s/${ID}/birds#${KEY}`],
    ]);
    expect(side.querySelector('[aria-current="page"]')?.textContent).toBe('Contents');
    expect(document.querySelector('footer')?.textContent).toBe('Made with Ghost.md');
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    // A click stays on the page: the address changes, the key stays, nothing is fetched again.
    act(() => side.querySelectorAll('a')[1]!.click());
    expect(location.pathname).toBe(`/s/${ID}/trees`);
    expect(location.hash).toBe(`#${KEY}`);
    await waitUntil(() => expect(document.querySelector('.cm-content')?.textContent).toContain('Oaks and ash.'));
    expect(readSite).toHaveBeenCalledTimes(1);
    expect(document.title).toBe('Trees · Field guide');
    expect(side.querySelector('[aria-current="page"]')?.textContent).toBe('Trees');
    // Previous and Next at the foot.
    const turn = document.querySelector('nav[aria-label="Next and previous pages"]')!;
    expect([...turn.querySelectorAll('a')].map((a) => a.getAttribute('href'))).toEqual([`/s/${ID}#${KEY}`, `/s/${ID}/birds#${KEY}`]);
    act(() => turn.querySelectorAll('a')[1]!.click());
    await waitUntil(() => expect(document.querySelector('.cm-content')?.textContent).toContain('Robins.'));
    expect(location.pathname).toBe(`/s/${ID}/birds`);
    // Back is the browser's.
    act(() => {
      history.replaceState(null, '', `/s/${ID}/trees#${KEY}`);
      dispatchEvent(new PopStateEvent('popstate'));
    });
    await waitUntil(() => expect(document.querySelector('.cm-content')?.textContent).toContain('Oaks and ash.'));
  });

  it('opens a page by its own address, its [[links]] to the site\u2019s pages drawn as links and the rest as not written', async () => {
    history.replaceState(null, '', `/s/${ID}/trees#${KEY}`);
    show(<Site />);
    await waitUntil(() => expect(document.querySelector('.cm-content')?.textContent).toContain('Oaks and ash.'));
    // The press itself is CodeMirror's (wikiLinks.ts, by the point under the pointer, which jsdom has no layout for):
    // it calls the same `open` the side's links go through, above.
    const marks = [...document.querySelectorAll('.cm-content .cm-wiki')].map((el) => [el.getAttribute('title'), el.classList.contains('cm-wikiNew')]);
    expect(marks).toEqual([
      ['Birds', false],
      ['Fish', true],
    ]);
    expect(document.title).toBe('Trees · Field guide');
  });

  it('says so of a page the site does not have, with the way to its first', async () => {
    history.replaceState(null, '', `/s/${ID}/gone#${KEY}`);
    show(<Site />);
    await waitUntil(() => expect(document.body.textContent).toContain('That page isn’t in this site'));
    expect(link('Go to the first page')?.getAttribute('href')).toBe(`/s/${ID}#${KEY}`);
  });

  it('without its key, says what is missing and asks for nothing', async () => {
    vi.mocked(readSite).mockClear();
    history.replaceState(null, '', `/s/${ID}`);
    show(<Site />);
    await waitUntil(() => expect(document.body.textContent).toContain('missing the part after the #'));
    expect(readSite).not.toHaveBeenCalled();
  });
});

describe('a published notebook with no page written yet', () => {
  it('opens on its index as the app draws one, with no list of pages', async () => {
    vi.mocked(readSite).mockResolvedValueOnce({ v: 1, kind: 'book', title: 'Field guide', at: 1, pages: [{ title: 'Field guide', body: index }] });
    history.replaceState(null, '', `/s/${ID}#${KEY}`);
    show(<Site />);
    await waitUntil(() => expect(document.querySelector('article h1')?.textContent).toBe('Field guide'));
    expect(document.querySelector('nav[aria-label="This site’s pages"]')).toBeNull();
    expect(document.body.textContent).not.toContain('book: true');
  });
});

describe('a published note', () => {
  it('is its one page under its title, with no list of pages and no Previous or Next', async () => {
    vi.mocked(readSite).mockResolvedValueOnce({ v: 1, kind: 'note', title: 'Walk', at: 1, pages: [{ title: 'Walk', body: '# Walk\n\nBy the river.' }] });
    history.replaceState(null, '', `/s/${ID}#${KEY}`);
    show(<Site />);
    await waitUntil(() => expect(document.querySelector('.cm-content')?.textContent).toContain('By the river.'));
    expect(document.querySelector('nav[aria-label="This site’s pages"]')).toBeNull();
    expect(document.querySelector('nav[aria-label="Next and previous pages"]')).toBeNull();
    expect(document.querySelector('header')?.textContent).toBe('Walk');
  });
});
