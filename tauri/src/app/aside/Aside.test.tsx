import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { makeNote } from '../../test/notes.ts';
import { button, show } from '../../test/render.tsx';
import { asideContent } from './aside.ts';

// The aside carries the version history (AsideHistory.tsx), which carries the kit, which reads matchMedia as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
const { Aside, AsideCard, AsidePanel } = await import('./Aside.tsx');

const BOOK = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Trees]]\n- [[Birds]]\n';
const notes = [makeNote('b', BOOK, { updatedAt: 5 }), makeNote('t', '# Trees\n', { updatedAt: 4 }), makeNote('x', '# Loose\n', { updatedAt: 3 })];

describe('the right-hand aside', () => {
  it('shows a page’s notebook: its pages with the open one marked, a tap opening another, the title opening the notebook', () => {
    const onOpen = vi.fn();
    const onOpenTitle = vi.fn();
    show(<Aside content={asideContent(notes, notes[1]!)!} onOpen={onOpen} onOpenTitle={onOpenTitle} />);
    expect([...document.querySelectorAll('ol[aria-label="Pages"] button')].map((b) => b.textContent?.trim())).toEqual(['1Trees', '2Birds']);
    expect(document.querySelector('[aria-current="page"]')?.textContent).toContain('Trees');
    act(() => button('2Birds').click());
    expect(onOpenTitle).toHaveBeenCalledWith('Birds');
    act(() => button('Open the notebook Field guide').click());
    expect(onOpen).toHaveBeenCalledWith('b');
  });

  it('lays out a run of chapters with no book: their numbers, the open one marked, a tap opening another by id', () => {
    const onOpen = vi.fn();
    const onClose = vi.fn();
    const run = [makeNote('c2', '# 02 · Second\n\n« [[The book]]', { updatedAt: 1 }), makeNote('c1', '# 01 · First\n\n« [[The book]]', { updatedAt: 2 })];
    show(<Aside content={asideContent(run, run[0]!)!} onOpen={onOpen} onOpenTitle={() => {}} onClose={onClose} />);
    expect(document.body.textContent).toContain('The book');
    expect([...document.querySelectorAll('ol[aria-label="Chapters"] button')].map((b) => b.textContent?.trim())).toEqual(['1First', '2Second']);
    expect(document.querySelector('[aria-current="page"]')?.textContent).toContain('Second');
    // The book isn't a note, so its name is only a name: nothing to open, and nothing made by tapping it.
    expect(document.querySelector('button[aria-label="Open The book"]')).toBeNull();
    act(() => button('1First').click());
    expect(onOpen).toHaveBeenCalledWith('c1');
    act(() => button('Close').click());
    expect(onClose).toHaveBeenCalled();
  });

  it('shows a journal’s month of entries, newest first, the open one marked, and a tap opening one by id', () => {
    const entry = (id: string, title: string, date: string) => makeNote(id, `---\ntitle: "${title}"\ndate: ${date}\n---\n**${date.slice(11)}** Words.`);
    const journal = makeNote('j', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[2026-09-27 21.40]]\n- [[2026-09-28 14.05]]\n');
    const all = [journal, entry('a', '2026-09-27 21.40', '2026-09-27T21:40'), entry('b', '2026-09-28 14.05', '2026-09-28T14:05')];
    const onOpen = vi.fn();
    show(<Aside content={asideContent(all, all[1]!)!} onOpen={onOpen} onOpenTitle={() => {}} />);
    expect(document.body.textContent).toContain('September 2026');
    expect([...document.querySelectorAll('ol[aria-label="Entries"] button')].map((b) => b.textContent?.trim())).toEqual(['2814:05 Words.', '2721:40 Words.']);
    expect(document.querySelector('[aria-current="page"]')?.textContent).toContain('21:40');
    act(() => (document.querySelector('ol[aria-label="Entries"] button') as HTMLElement).click());
    expect(onOpen).toHaveBeenCalledWith('b');
    act(() => button('Open the journal Diary').click());
    expect(onOpen).toHaveBeenCalledWith('j');
  });
});

describe('the aside as the drawer’s card', () => {
  afterEach(() => vi.useRealTimers());

  it('is a dialog at the right that closes on a tap outside, not on its own toggle, and on opening a page', () => {
    vi.useFakeTimers();
    const onClose = vi.fn();
    const onOpenTitle = vi.fn();
    const toggle = document.createElement('button');
    toggle.setAttribute('data-aside-toggle', '');
    document.body.appendChild(toggle);
    show(<AsideCard content={asideContent(notes, notes[1]!)!} history={null} onOpen={() => {}} onOpenTitle={onOpenTitle} onClose={onClose} />);
    const card = document.querySelector('[role="dialog"][data-side="end"]');
    expect(card?.getAttribute('aria-label')).toBe('Side panel');
    expect(card?.querySelector('[data-popup]')).toBeTruthy();
    // The outside listener joins on the next tick, so the press that opened the card cannot close it.
    act(() => void vi.advanceTimersByTime(0));
    toggle.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(onClose).not.toHaveBeenCalled();
    document.body.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(onClose).toHaveBeenCalledTimes(1);
    const birds = [...document.querySelectorAll<HTMLButtonElement>('ol[aria-label="Pages"] button')][1]!;
    act(() => birds.click());
    expect(onOpenTitle).toHaveBeenCalledWith('Birds');
    expect(onClose).toHaveBeenCalledTimes(2);
    toggle.remove();
  });
});

const { keepVersion, keepsVersions } = await import('../core/versions/record.ts');
const { liveNoteOpened } = await import('../core/versions/live.ts');
const { setPreferences } = await import('../core/preferences.ts');
const { ToastProvider } = await import('@glacier/react');

describe('the aside’s version history (on a desktop)', () => {
  const panel = (props: Parameters<typeof AsidePanel>[0]) => (
    <ToastProvider>
      <AsidePanel {...props} />
    </ToastProvider>
  );
  afterEach(() => localStorage.removeItem('glyph-aside-tab'));

  it('is the index and the history as two tabs where the note has both, the last one chosen kept', () => {
    const host = show(panel({ content: asideContent(notes, notes[1]!), history: { noteId: 't', title: 'Trees' }, onOpen: () => {}, onOpenTitle: () => {} }));
    const tabs = [...host.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
    expect(tabs.map((tab) => [tab.textContent, tab.getAttribute('aria-selected')])).toEqual([
      ['Index', 'true'],
      ['History', 'false'],
    ]);
    act(() => tabs[1]!.click());
    expect(host.textContent).toContain('Version history');
    expect(localStorage.getItem('glyph-aside-tab')).toBe('history');
  });

  it('is the history alone for a note with no book, and offers to start one where it keeps none', () => {
    setPreferences({ versions: {} });
    const host = show(panel({ content: null, history: { noteId: 'x', title: 'Loose' }, onOpen: () => {}, onOpenTitle: () => {} }));
    expect(host.querySelector('[role="tab"]')).toBeNull();
    expect(host.textContent).toContain('This note keeps no version history.');
    act(() => button('Keep version history', host).click());
    expect(keepsVersions('x')).toBe(true);
  });

  it('restores through the open note’s editor, as the More sheet does', async () => {
    setPreferences({ versions: { x: true } });
    await keepVersion('x', 'one', { now: Date.now() - 120_000 });
    await keepVersion('x', 'one\ntwo', { now: Date.now() - 60_000 });
    const restore = vi.fn();
    const closed = liveNoteOpened('x', { current: () => 'one\ntwo', restore });
    const host = show(panel({ content: null, history: { noteId: 'x', title: 'Loose' }, onOpen: () => {}, onOpenTitle: () => {} }));
    await act(async () => new Promise((done) => setTimeout(done, 20)));
    act(() => [...host.querySelectorAll<HTMLButtonElement>('[class*=timeline] li button')].find((b) => b.getAttribute('aria-label')?.startsWith('Version 1'))!.click());
    act(() => [...host.querySelectorAll<HTMLButtonElement>('button')].find((b) => b.textContent?.startsWith('Restore version 1'))!.click());
    expect(restore).toHaveBeenCalledWith('one', expect.objectContaining({ n: 1 }));
    closed();
  });
});

