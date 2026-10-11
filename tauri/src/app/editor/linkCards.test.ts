import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { LINK_PREVIEW_READY, pathOf, siteOf, type LinkPreview } from '../core/linkPreview.ts';
import { provideMarkDetails, type MarkDetailsProvider } from '../core/markDetails.ts';
import { DEFAULT_PREFERENCES, setPreferences } from '../core/preferences.ts';
import { linkCards, linkLine } from './linkCards.ts';

/** What the previews know, and what was opened: fetching a page's title is core/linkPreview.ts's, not the card's. */
const previews = vi.hoisted(() => ({ known: new Map<string, LinkPreview>(), opened: [] as string[] }));
vi.mock('../core/linkPreview.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/linkPreview.ts')>()),
  previewFor: (url: string) => previews.known.get(url) ?? null,
  wantPreview: () => undefined,
  openLink: async (url: string) => {
    previews.opened.push(url);
  },
}));

// As the Notion and GitHub plugins do when they are on: they read their own links, which have their own rows.
const reading = (host: string) => ({ reads: (url: string) => url.includes(host) }) as unknown as MarkDetailsProvider;
provideMarkDetails('notion', () => reading('notion.so'));
provideMarkDetails('github', () => reading('github.com'));

describe('link preview cards', () => {
  it('are for a line that is only a link, bare, bracketed or named, in a list or not', () => {
    expect(linkLine('https://www.airbnb.com/rooms/1234')).toEqual({ url: 'https://www.airbnb.com/rooms/1234', words: null });
    expect(linkLine('  <https://example.com/a>  ')?.url).toBe('https://example.com/a');
    expect(linkLine('- [The cabin](https://airbnb.com/rooms/1)')).toEqual({ url: 'https://airbnb.com/rooms/1', words: 'The cabin' });
    expect(linkLine('- [ ] https://example.com/read-this.')?.url).toBe('https://example.com/read-this');
    expect(linkLine('1. https://example.com')?.url).toBe('https://example.com');
  });

  it('are not for a link among words, a picture, another scheme, or a link a plugin reads', () => {
    expect(linkLine('see https://example.com for more')).toBeNull();
    expect(linkLine('![a cassette](https://example.com/tape.jpg)')).toBeNull();
    expect(linkLine('ftp://example.com/file')).toBeNull();
    expect(linkLine('- [ ] Buy milk [notion](https://www.notion.so/abc123)')).toBeNull();
    expect(linkLine('https://www.notion.so/Some-page-0123456789abcdef0123456789abcdef')).toBeNull();
    expect(linkLine('- [Fix it](https://github.com/o/r/issues/4)')).toBeNull();
  });

  it('say the site and a short path', () => {
    expect(siteOf('https://www.airbnb.com/rooms/1234?x=1')).toBe('airbnb.com');
    expect(pathOf('https://www.airbnb.com/rooms/1234?x=1')).toBe('/rooms/1234?x=1');
    expect(pathOf('https://example.com/')).toBe('');
    expect(pathOf(`https://example.com/${'a'.repeat(60)}`)).toHaveLength(32);
  });
});

describe('link cards drawn in a note', () => {
  const CABIN = 'https://www.airbnb.com/rooms/1234';
  const doc = ['The trip', CABIN, '```', 'https://example.com/in-code', '```', `see ${CABIN} for more`].join('\n');
  let view: EditorView | null = null;

  beforeEach(() => {
    previews.known.clear();
    previews.opened.length = 0;
    setPreferences({ linkPreviews: true });
  });

  afterEach(() => {
    view?.destroy();
    view = null;
    setPreferences({ linkPreviews: DEFAULT_PREFERENCES.linkPreviews });
  });

  function open(): EditorView {
    view = new EditorView({ state: EditorState.create({ doc, extensions: [linkCards()] }), parent: document.body });
    return view;
  }
  const cards = (on: EditorView) => [...on.dom.querySelectorAll<HTMLElement>('.cm-linkCard')];

  it('draws a card under a line that is only a link, and none for a link in code or among words', () => {
    const on = open();
    expect(cards(on)).toHaveLength(1);
    // Until the page's title is known, the card says the site and where on it.
    expect(cards(on)[0]?.querySelector('.cm-linkCard-title')?.textContent).toBe('airbnb.com');
    expect(cards(on)[0]?.querySelector('.cm-linkCard-where')?.textContent).toBe('airbnb.com/rooms/1234');
    expect(on.contentDOM.textContent).toContain(CABIN);
  });

  it('says the page’s title and what it is about once they arrive', () => {
    const on = open();
    previews.known.set(CABIN, { url: CABIN, title: 'The cabin by the lake', site: 'Airbnb', description: 'Sleeps four.' });
    window.dispatchEvent(new Event(LINK_PREVIEW_READY));
    const [card] = cards(on);
    expect(card?.querySelector('.cm-linkCard-title')?.textContent).toBe('The cabin by the lake');
    expect(card?.querySelector('.cm-linkCard-about')?.textContent).toBe('Sleeps four.');
    expect(card?.getAttribute('aria-label')).toBe('Open The cabin by the lake');
  });

  it('opens the page on a tap, or on Enter', () => {
    const on = open();
    cards(on)[0]!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    cards(on)[0]!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    expect(previews.opened).toEqual([CABIN, CABIN]);
  });

  it('draws none with link previews off, and draws them again when they are turned back on', () => {
    setPreferences({ linkPreviews: false });
    const on = open();
    expect(cards(on)).toEqual([]);
    setPreferences({ linkPreviews: true });
    expect(cards(on)).toHaveLength(1);
  });
});
