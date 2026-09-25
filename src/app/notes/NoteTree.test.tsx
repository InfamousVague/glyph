import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { bookNoteBody } from '../book/book.ts';
import { reloadPreferences } from '../core/preferences.ts';
import { addWorkspace, fileNote } from '../core/workspaces.ts';
import { makeNote } from '../../test/notes.ts';
import { button, show, unmount } from '../../test/render.tsx';

// A row's small drawing is the editor (notes/NotePeek.tsx): here only whether a row has one is asked.
vi.mock('./NotePeek.tsx', () => ({ NotePeek: ({ className }: { className?: string }) => <div className={className} data-peek /> }));
const { NoteTree } = await import('./NoteTree.tsx');

beforeEach(() => reloadPreferences());
afterEach(() => {
  unmount();
  localStorage.clear();
  vi.useRealTimers();
});

const rows = () => [...document.querySelectorAll('ul[aria-label="Your notes"] li > button')].map((b) => b.querySelector('[class*=rowTitle]')?.textContent);

describe('the sidebar, names only', () => {
  it('lists each note as its kind and its name, no drawing, and keeps the choice on the device', () => {
    const notes = [makeNote('b', bookNoteBody('Trip', ['Packing'])), makeNote('p', '# Packing\n\n- [ ] Tent'), makeNote('c', '---\ntitle: "Map"\n---\n{"nodes":[],"edges":[]}')];
    const host = show(<NoteTree notes={notes} activeId={null} onOpen={() => {}} onNew={() => {}} />);
    const tree = host.querySelector('[class*=tree]')!;
    expect(tree.hasAttribute('data-compact')).toBe(false);
    act(() => host.querySelector<HTMLButtonElement>('button[aria-label="Show names only"]')!.click());
    expect(tree.hasAttribute('data-compact')).toBe(true);
    // One mark per note, and no note drawn small.
    expect(host.querySelectorAll('[class*=kind]').length).toBe(3);
    expect(host.querySelector('[class*=rowPeek]')).toBeNull();
    expect(localStorage.getItem('glyph-tree-compact')).toBe('1');
    // Names only has no room for the book a page is in.
    expect(host.querySelector('[title="Page 1 of Trip"]')).toBeNull();
    act(() => host.querySelector<HTMLButtonElement>('button[aria-label="Show each note drawn small"]')!.click());
    expect(tree.hasAttribute('data-compact')).toBe(false);
    // Drawn small, a page of a book says which book, and which page in full to whoever points at it.
    expect(host.querySelector('[title="Page 1 of Trip"]')?.textContent).toBe('Trip');
  });

  it('offers Browse files only where the device can show the folder', () => {
    const host = show(<NoteTree notes={[]} activeId={null} onOpen={() => {}} onNew={() => {}} />);
    // In a browser there is no folder to show.
    expect(host.querySelector('button[aria-label="Browse files"]')).toBeNull();
  });
});

describe('the sidebar’s folders', () => {
  it('puts each workspace’s notes in its folder, folds one shut and remembers it, and folds or opens them all', () => {
    const kitchen = addWorkspace('Kitchen')!;
    fileNote('a', kitchen.id);
    const host = show(<NoteTree notes={[makeNote('a', '# Apples'), makeNote('b', '# Bread')]} activeId="b" onOpen={() => undefined} onNew={() => undefined} />);
    expect(rows()).toEqual(['Apples', 'Bread']);
    expect(host.querySelector('[aria-current="page"]')?.textContent).toContain('Bread');
    const folder = () => [...host.querySelectorAll<HTMLButtonElement>('button[aria-expanded]')].find((b) => b.textContent?.includes('Kitchen'))!;
    act(() => folder().click());
    expect(folder().getAttribute('aria-expanded')).toBe('false');
    expect(rows()).toEqual(['Bread']);
    expect(JSON.parse(localStorage.getItem('glyph-tree-closed')!)).toContain(kitchen.id);
    act(() => button('Open every folder').click());
    expect(rows()).toEqual(['Apples', 'Bread']);
    act(() => button('Fold every folder').click());
    expect(rows()).toEqual(['Bread']);
  });

  it('keeps the archive shut until it is opened', () => {
    const host = show(<NoteTree notes={[makeNote('a', '# Apples'), makeNote('z', '# Old', { archivedAt: 1 })]} activeId={null} onOpen={() => undefined} onNew={() => undefined} />);
    expect(rows()).toEqual(['Apples']);
    act(() => [...host.querySelectorAll<HTMLButtonElement>('button[aria-expanded]')].find((b) => b.textContent?.includes('Archive'))!.click());
    expect(rows()).toEqual(['Apples', 'Old']);
  });

  it('says there are no notes yet when there are none', () => {
    const host = show(<NoteTree notes={[]} activeId={null} onOpen={() => undefined} onNew={() => undefined} />);
    expect(host.textContent).toContain('No notes yet.');
  });
});

describe('the trash', () => {
  const trashed = [makeNote('t1', '# Torn'), makeNote('t2', '')];

  it('is shut until opened, and brings a note back or deletes it for good from its row', () => {
    const onRestore = vi.fn();
    const onDestroy = vi.fn();
    const host = show(<NoteTree notes={[]} trashed={trashed} activeId={null} onOpen={() => undefined} onNew={() => undefined} onRestore={onRestore} onDestroy={onDestroy} />);
    expect(host.querySelector('button[aria-label="Restore Torn"]')).toBeNull();
    act(() => [...host.querySelectorAll<HTMLButtonElement>('button[aria-expanded]')].find((b) => b.textContent?.includes('Trash'))!.click());
    expect(localStorage.getItem('glyph-tree-trash-open')).toBe('1');
    act(() => button('Restore Torn').click());
    act(() => button('Delete Untitled for good').click());
    expect(onRestore).toHaveBeenCalledWith(trashed[0]);
    expect(onDestroy).toHaveBeenCalledWith(trashed[1]);
  });

  it('empties only on a second press, asked on the button itself, and stops asking after a few seconds', () => {
    vi.useFakeTimers();
    const onEmptyTrash = vi.fn();
    show(<NoteTree notes={[]} trashed={trashed} activeId={null} onOpen={() => undefined} onNew={() => undefined} onEmptyTrash={onEmptyTrash} />);
    act(() => button('Empty').click());
    expect(onEmptyTrash).not.toHaveBeenCalled();
    act(() => void vi.advanceTimersByTime(4000));
    expect(button('Empty')).toBeTruthy();
    act(() => button('Empty').click());
    act(() => button('Delete 2 for good?').click());
    expect(onEmptyTrash).toHaveBeenCalledTimes(1);
    expect(button('Empty')).toBeTruthy();
  });
});

describe('the sidebar’s foot', () => {
  it('carries what is waiting over it, and Speak and Settings in it', () => {
    const onSpeak = vi.fn();
    const onSettings = vi.fn();
    const host = show(<NoteTree notes={[]} activeId={null} onOpen={() => undefined} onNew={() => undefined} onSpeak={onSpeak} onSettings={onSettings} notices={<p>An update</p>} />);
    expect(host.querySelector('[class*=notices]')?.textContent).toBe('An update');
    act(() => button('Speak').click());
    act(() => button('Settings').click());
    expect([onSpeak.mock.calls.length, onSettings.mock.calls.length]).toEqual([1, 1]);
  });
});
