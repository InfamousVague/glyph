import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { installBack } from '../core/back.ts';
import { reloadPreferences } from '../core/preferences.ts';
import { makeNote } from '../../test/notes.ts';
import { button, show } from '../../test/render.tsx';
import { NotesDrawer } from './NotesDrawer.tsx';

/**
 * The notes drawer is a card over the note (notes/FloatingCard.tsx): it closes on a tap outside it but not on the
 * icon that opened it, on Escape and the back gesture, and on the tools that take the person somewhere else.
 */

// A note's card draws the note small with an editor (notes/NotePeek.tsx), which is nothing the card decides.
vi.mock('./NotePeek.tsx', () => ({ NotePeek: () => null }));

const notes = [makeNote('a', '# Apples'), makeNote('b', '# Bread')];
let uninstall: () => void = () => undefined;

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  uninstall = installBack();
});
afterEach(() => {
  uninstall();
  vi.useRealTimers();
});

describe('the notes drawer', () => {
  it('draws nothing while it is shut', () => {
    const host = show(<NotesDrawer open={false} notes={notes} activeId={null} onOpen={() => undefined} onNew={() => undefined} onClose={() => undefined} />);
    expect(host.innerHTML).toBe('');
  });

  it('is a card at the left that closes on a tap outside, a tick after it opened, but not on its own icon', () => {
    vi.useFakeTimers();
    const onClose = vi.fn();
    const icon = document.createElement('button');
    icon.setAttribute('data-sidebar-toggle', '');
    document.body.appendChild(icon);
    show(<NotesDrawer open notes={notes} activeId="a" onOpen={() => undefined} onNew={() => undefined} onClose={onClose} />);
    const card = document.querySelector('[role="dialog"][aria-label="Your notes"]');
    expect(card?.hasAttribute('data-side')).toBe(false);
    // The press that opened it lands before the card listens for one.
    document.body.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(onClose).not.toHaveBeenCalled();
    act(() => void vi.advanceTimersByTime(0));
    icon.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    card!.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(onClose).not.toHaveBeenCalled();
    document.body.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(onClose).toHaveBeenCalledTimes(1);
    icon.remove();
  });

  it('closes on Escape, and on its own close, and before it opens the palette', () => {
    const onClose = vi.fn();
    const onCommands = vi.fn();
    show(<NotesDrawer open notes={notes} activeId={null} onOpen={() => undefined} onNew={() => undefined} onClose={onClose} onCommands={onCommands} />);
    act(() => void window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })));
    expect(onClose).toHaveBeenCalledTimes(1);
    act(() => button('Close').click());
    expect(onClose).toHaveBeenCalledTimes(2);
    act(() => button('Search and commands').click());
    expect(onClose).toHaveBeenCalledTimes(3);
    expect(onCommands).toHaveBeenCalledTimes(1);
  });

  it('opens the note tapped', () => {
    const onOpen = vi.fn();
    show(<NotesDrawer open notes={notes} activeId={null} onOpen={onOpen} onNew={() => undefined} onClose={() => undefined} />);
    act(() => [...document.querySelectorAll<HTMLButtonElement>('ul[aria-label="Your notes"] button')].find((b) => b.textContent?.includes('Bread'))!.click());
    expect(onOpen).toHaveBeenCalledWith('b');
  });
});
