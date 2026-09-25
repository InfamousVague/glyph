import { afterEach, describe, expect, it } from 'vitest';
import { act } from 'react';
import { bookNoteBody } from '../book/book.ts';
import { makeNote } from '../../test/notes.ts';
import { show, unmount } from '../../test/render.tsx';
import { NoteTree } from './NoteTree.tsx';

afterEach(() => {
  unmount();
  localStorage.clear();
});

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
    act(() => host.querySelector<HTMLButtonElement>('button[aria-label="Show each note drawn small"]')!.click());
    expect(tree.hasAttribute('data-compact')).toBe(false);
  });

  it('offers Browse files only where the device can show the folder', () => {
    const host = show(<NoteTree notes={[]} activeId={null} onOpen={() => {}} onNew={() => {}} />);
    // In a browser there is no folder to show.
    expect(host.querySelector('button[aria-label="Browse files"]')).toBeNull();
  });
});
