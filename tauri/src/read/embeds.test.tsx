import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { Shared } from '../app/share/share.ts';
import { rerender, show, waitUntil } from '../test/render.tsx';
import { embedOf, sectionOf } from './embeds.ts';
import { Rendered } from './Rendered.tsx';

/*
 * Section embeds on the shared page (embeds.ts, Rendered.tsx; Matt, 2026-10-30, "add all 12"): a page of the same share
 * drawn in place as a quoted card, its heading's section or its named line or the whole page; a page the share does
 * not carry a "from [[Note]]" placeholder; a loop and a third level the placeholder too; a heading not there said so;
 * drawn again as the words change; and the reader's own page with an embed in it.
 */

await vi.hoisted(async () => (await import('../test/stubs.ts')).stubMatchMedia());

vi.mock('../app/share/share.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../app/share/share.ts')>()),
  readShared: vi.fn(),
}));
vi.mock('leaflet', () => ({ default: {} }));
vi.mock('leaflet/dist/leaflet.css', () => ({}));

const { Reader } = await import('./Reader.tsx');
const { readShared } = await import('../app/share/share.ts');

const packing = '---\ntags: trip\n---\n# Packing\n\nWhat goes in the bag.\n\n## Clothes\n\n- Shoes ^shoes\n  - The old ones\n- A coat\n\n## Papers\n\nPassports.\n';
const pages: Record<string, string> = {
  Packing: packing,
  Loop: '# Loop\n\nIt draws the trip.\n\n![[Trip]]\n',
  Deep: '# Deep\n\n![[Packing#Papers]]\n',
};
const bodyOf = (title: string) => pages[title] ?? null;

const cards = () => [...document.querySelectorAll<HTMLElement>('blockquote[data-embed]')];
const placeholders = () => [...document.querySelectorAll<HTMLElement>('[data-embed-from]')].map((p) => p.textContent);

describe('which paragraphs are embeds', () => {
  it('a note, a heading in one, a named line; not a picture, a link, or one inside a sentence', () => {
    expect(embedOf('![[Packing]]')).toEqual({ title: 'Packing', anchor: null });
    expect(embedOf(' ![[Packing#Clothes]] ')).toEqual({ title: 'Packing', anchor: 'Clothes' });
    expect(embedOf('![[Packing#^shoes|the shoes]]')).toEqual({ title: 'Packing', anchor: '^shoes' });
    expect(embedOf('![[photo.png]]')).toBeNull();
    expect(embedOf('[[Packing]]')).toBeNull();
    expect(embedOf('see ![[Packing]] here')).toBeNull();
  });

  it('what each draws: a heading to the next as high, a named line with its items, the page without its title', () => {
    expect(sectionOf(packing, 'Clothes')).toBe('## Clothes\n\n- Shoes ^shoes\n  - The old ones\n- A coat');
    expect(sectionOf(packing, 'clothes')).toBe(sectionOf(packing, 'Clothes'));
    expect(sectionOf(packing, '^shoes')).toBe('- Shoes ^shoes\n  - The old ones');
    expect(sectionOf(packing, null)).toBe('What goes in the bag.\n\n## Clothes\n\n- Shoes ^shoes\n  - The old ones\n- A coat\n\n## Papers\n\nPassports.');
    expect(sectionOf(packing, 'Nowhere')).toBeNull();
    expect(sectionOf(packing, '^gone')).toBeNull();
  });
});

describe('drawn on the page', () => {
  it('draws a page of the share in a quoted card, its title over its section, and opens it from the title', () => {
    const open = vi.fn();
    show(<Rendered body={'# Trip\n\nBefore.\n\n![[Packing#Clothes]]\n\nAfter.'} known={(t) => t in pages} open={open} bodyOf={bodyOf} />);
    const [card] = cards();
    expect(card).toBeTruthy();
    expect(card!.getAttribute('aria-label')).toBe('From Packing › Clothes');
    expect(card!.querySelector('svg')).toBeTruthy();
    expect(card!.querySelector('h2')?.textContent).toBe('Clothes');
    expect([...card!.querySelectorAll('li')].map((li) => li.firstElementChild?.textContent ?? li.textContent)).toContain('A coat');
    expect(card!.textContent).not.toContain('Passports');
    expect(document.body.textContent).not.toContain('![[');
    act(() => card!.querySelector('button')!.click());
    expect(open).toHaveBeenCalledWith('Packing');
  });

  it('a page the share does not carry is a "from [[Note]]" placeholder, and nothing is asked for it', () => {
    const asked = vi.fn(bodyOf);
    show(<Rendered body={'# Trip\n\n![[Not shared#Somewhere]]\n'} bodyOf={asked} />);
    expect(cards()).toHaveLength(0);
    expect(placeholders()).toEqual(['from [[Not shared#Somewhere]]']);
    expect(asked).toHaveBeenCalledWith('Not shared');
  });

  it('never round in a circle, and two levels at most', () => {
    // Trip draws Loop, which would draw Trip again; and Trip names itself.
    show(<Rendered body={'# Trip\n\n![[Loop]]\n\n![[Trip]]\n\n![[Deep]]\n'} bodyOf={bodyOf} />);
    expect(cards().map((c) => c.getAttribute('aria-label'))).toEqual(['From Loop', 'From Deep', 'From Packing › Papers']);
    expect(placeholders()).toEqual(['from [[Trip]]', 'from [[Trip]]']);
    expect(document.body.textContent).toContain('Passports.');
  });

  it('a heading that is not there is said so', () => {
    show(<Rendered body={'![[Packing#Nowhere]]'} bodyOf={bodyOf} />);
    expect(cards()[0]!.textContent).toContain('Packing has no heading “Nowhere”.');
  });

  it('is drawn again as the page it shows changes', () => {
    show(<Rendered body={'![[Packing#Papers]]'} bodyOf={bodyOf} />);
    expect(cards()[0]!.textContent).toContain('Passports.');
    const changed = (title: string) => (title === 'Packing' ? packing.replace('Passports.', 'Passports and the tickets.') : bodyOf(title));
    rerender(<Rendered body={'![[Packing#Papers]]'} bodyOf={changed} />);
    expect(cards()[0]!.textContent).toContain('Passports and the tickets.');
  });
});

describe('the reader', () => {
  const shared: Shared = {
    v: 1,
    kind: 'book',
    title: 'Portugal',
    pages: [
      { title: 'Portugal', body: '---\nbook: true\n---\n# Portugal\n\n- [[Trip]]\n- [[Packing]]\n' },
      { title: 'Trip', body: '# Trip\n\nThe list:\n\n![[Packing#Clothes]]\n\n![[Elsewhere]]\n' },
      { title: 'Packing', body: packing },
    ],
    at: 1,
  };
  it('draws an embed of another page of the share, and a placeholder for one that is not in it', async () => {
    vi.mocked(readShared).mockResolvedValue(shared);
    history.replaceState(null, '', `/read.html#${'a'.repeat(22)}.${'b'.repeat(43)}`);
    show(<Reader />);
    await waitUntil(() => expect(document.querySelector('[role="dialog"]')).toBeTruthy());
    act(() => void document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' })));
    const trip = [...document.querySelectorAll<HTMLElement>('a, button')].find((el) => el.textContent?.trim() === 'Trip');
    expect(trip).toBeTruthy();
    act(() => trip!.click());
    await waitUntil(() => expect(cards()).toHaveLength(1));
    expect(cards()[0]!.getAttribute('aria-label')).toBe('From Packing › Clothes');
    expect(placeholders()).toEqual(['from [[Elsewhere]]']);
  });
});
