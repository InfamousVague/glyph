import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

// The Glacier kit asks matchMedia as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
import { makeNote } from '../../test/notes.ts';
import { stubMatchMedia } from '../../test/stubs.ts';
import { show } from '../../test/render.tsx';
import { NoteCard } from './NoteCard.tsx';
import { NoteMenuHost } from './NoteMenu.tsx';
import { byMouse, closeNoteMenu, noteMenuNow, openNoteMenu } from './noteMenu.ts';

/*
 * A note's menu at the pointer (notes/NoteMenu.tsx, notes/noteMenu.ts; docs/DESIGN.md §172): a mouse's right-click on a
 * card opens it, a touch's press and hold does not, and each row does what the card's swipe does.
 */

afterEach(() => closeNoteMenu());

const GROCERIES = makeNote('g', '# Groceries\n\n- [ ] Milk\n');

function host() {
  const actions = { onOpen: vi.fn(), onPin: vi.fn(), onArchive: vi.fn(), onDelete: vi.fn() };
  show(<NoteMenuHost notes={[GROCERIES]} {...actions} />);
  return actions;
}

const menuItem = (label: string) => [...document.querySelectorAll<HTMLElement>('[role="menuitem"]')].find((item) => item.textContent?.trim() === label);

function rightClick(target: Element, pointerType: string) {
  const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 120, clientY: 80, button: 2 });
  Object.defineProperty(event, 'pointerType', { value: pointerType });
  act(() => target.dispatchEvent(event));
  return event;
}

describe('a note’s menu', () => {
  it('opens at the pointer on a mouse’s right-click on a card, and not on a touch’s press and hold', () => {
    show(<ul><NoteCard note={GROCERIES} index={0} onOpen={() => {}} /></ul>);
    const card = document.querySelector('li')!;
    const touch = rightClick(card, 'touch');
    expect(noteMenuNow()).toBeNull();
    expect(touch.defaultPrevented).toBe(false);
    const mouse = rightClick(card, 'mouse');
    expect(noteMenuNow()).toEqual({ id: 'g', x: 120, y: 80 });
    expect(mouse.defaultPrevented).toBe(true);
  });

  it('offers Open, Pin, Archive and Delete, Delete in the danger tone', () => {
    host();
    act(() => openNoteMenu('g', 10, 10));
    expect([...document.querySelectorAll('[role="menuitem"]')].map((item) => item.textContent?.trim())).toEqual(['Open', 'Pin', 'Archive', 'Delete']);
    expect(document.querySelector('[role="menu"]')?.getAttribute('aria-label')).toBe('Groceries, note');
  });

  it('offers Add a comment second, where the app can start one, for the note it was opened on', () => {
    const actions = { onOpen: vi.fn(), onComment: vi.fn(), onPin: vi.fn(), onArchive: vi.fn(), onDelete: vi.fn() };
    show(<NoteMenuHost notes={[GROCERIES]} {...actions} />);
    act(() => openNoteMenu('g', 10, 10));
    expect([...document.querySelectorAll('[role="menuitem"]')].map((item) => item.textContent?.trim())).toEqual(['Open', 'Add a comment', 'Pin', 'Archive', 'Delete']);
    act(() => menuItem('Add a comment')!.click());
    expect(actions.onComment).toHaveBeenCalledWith(GROCERIES);
    expect(actions.onOpen).not.toHaveBeenCalled();
    expect(document.querySelector('[role="menu"]')).toBeNull();
  });

  it('deletes the note it was opened on, and closes', () => {
    const actions = host();
    act(() => openNoteMenu('g', 10, 10));
    act(() => menuItem('Delete')!.click());
    expect(actions.onDelete).toHaveBeenCalledWith(GROCERIES);
    expect(document.querySelector('[role="menu"]')).toBeNull();
  });

  it('says Unpin and Unarchive for a note pinned and archived', () => {
    const actions = { onOpen: vi.fn(), onPin: vi.fn(), onArchive: vi.fn(), onDelete: vi.fn() };
    const kept = { ...GROCERIES, starred: true, archivedAt: 5 };
    show(<NoteMenuHost notes={[kept]} {...actions} />);
    act(() => openNoteMenu('g', 10, 10));
    expect(menuItem('Unpin')).toBeDefined();
    act(() => menuItem('Unarchive')!.click());
    expect(actions.onArchive).toHaveBeenCalledWith(kept, false);
  });

  it('draws nothing for a note no longer there', () => {
    host();
    act(() => openNoteMenu('gone', 10, 10));
    expect(document.querySelector('[role="menu"]')).toBeNull();
  });

  it('takes a mouse where the event says so, and a fine pointer that hovers where it does not', () => {
    expect(byMouse({ type: 'contextmenu', pointerType: 'mouse' })).toBe(true);
    expect(byMouse({ type: 'contextmenu', pointerType: 'touch' })).toBe(false);
    stubMatchMedia(true);
    try {
      expect(byMouse({ type: 'contextmenu' })).toBe(true);
    } finally {
      stubMatchMedia(false);
    }
    expect(byMouse({ type: 'contextmenu' })).toBe(false);
  });
});
