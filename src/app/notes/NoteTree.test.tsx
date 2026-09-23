import { afterEach, describe, expect, it } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import type { Note } from '../core/store.ts';
import { bookNoteBody } from '../book/book.ts';
import { NoteTree } from './NoteTree.tsx';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: Root | null = null;
let host: HTMLDivElement | null = null;
afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  localStorage.clear();
});

const note = (id: string, body: string): Note => ({ id, body, createdAt: 0, updatedAt: 0, source: 'editor' });

describe('the sidebar, names only', () => {
  it('lists each note as its kind and its name, no drawing, and keeps the choice on the device', () => {
    const notes = [note('b', bookNoteBody('Trip', ['Packing'])), note('p', '# Packing\n\n- [ ] Tent'), note('c', '---\ntitle: "Map"\n---\n{"nodes":[],"edges":[]}')];
    host = document.createElement('div');
    document.body.appendChild(host);
    root = createRoot(host);
    act(() => root!.render(<NoteTree notes={notes} activeId={null} onOpen={() => {}} onNew={() => {}} />));
    const tree = host.querySelector('[class*=tree]')!;
    expect(tree.hasAttribute('data-compact')).toBe(false);
    act(() => host!.querySelector<HTMLButtonElement>('button[aria-label="Show names only"]')!.click());
    expect(tree.hasAttribute('data-compact')).toBe(true);
    // One mark per note, and no note drawn small.
    expect(host.querySelectorAll('[class*=kind]').length).toBe(3);
    expect(host.querySelector('[class*=rowPeek]')).toBeNull();
    expect(localStorage.getItem('glyph-tree-compact')).toBe('1');
    act(() => host!.querySelector<HTMLButtonElement>('button[aria-label="Show each note drawn small"]')!.click());
    expect(tree.hasAttribute('data-compact')).toBe(false);
  });

  it('offers Browse files only where the device can show the folder', () => {
    host = document.createElement('div');
    document.body.appendChild(host);
    root = createRoot(host);
    act(() => root!.render(<NoteTree notes={[]} activeId={null} onOpen={() => {}} onNew={() => {}} />));
    // In a browser there is no folder to show.
    expect(host.querySelector('button[aria-label="Browse files"]')).toBeNull();
  });
});
