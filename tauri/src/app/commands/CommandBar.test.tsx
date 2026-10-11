import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { goBack } from '../core/back.ts';
import { rerender, show, typeInto } from '../../test/render.tsx';
import type { PaletteDoing, PaletteWorld } from './palette.ts';

/**
 * The palette on screen: it hands its opener out once, however many times its caller renders with a new callback -
 * the loop that once rendered a phone twenty-five times a second - and the back gesture closes it before anything
 * under it.
 */

// The Glacier kit asks matchMedia as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
const { CommandBar } = await import('./CommandBar.tsx');

const world: PaletteWorld = { notes: [{ id: 'a', title: 'Apples' }], tabs: [], workspaces: [], workspace: null, note: null, filedIn: null, pinned: false, canBack: false, canForward: false, view: 'mixed', theme: 'dark' };
const doing = { openNote: vi.fn(), newNote: vi.fn(), speak: vi.fn() } as unknown as PaletteDoing;
const palette = () => document.querySelector('[role="dialog"]');

describe('the command palette', () => {
  it('hands its opener out once, whatever its caller passes each render', () => {
    const readies = [vi.fn(), vi.fn(), vi.fn()];
    show(<CommandBar world={world} doing={doing} onReady={readies[0]} />);
    rerender(<CommandBar world={world} doing={doing} onReady={readies[1]} />);
    rerender(<CommandBar world={world} doing={doing} onReady={readies[2]} />);
    expect(readies.map((ready) => ready.mock.calls.length)).toEqual([1, 0, 0]);
  });

  it('opens from the opener it handed out, and closes on the back gesture', () => {
    let open: () => void = () => undefined;
    show(<CommandBar world={world} doing={doing} onReady={(opener) => (open = opener)} />);
    expect(palette()).toBeNull();
    act(() => open());
    expect(palette()).not.toBeNull();
    expect(document.body.textContent).toContain('Open Apples');
    // The phone's gesture, as the activity asks it of the page (core/back.ts): the palette takes it.
    let took = false;
    act(() => {
      took = goBack();
    });
    expect(took).toBe(true);
    expect(palette()).toBeNull();
  });

  it('finds a note by name past the forty newest once something is typed, and opens empty again', () => {
    // Forty-five newer notes on top, as adding Ghost.md: The Guide leaves a library.
    const notes = [...Array.from({ length: 45 }, (_, i) => ({ id: `g${i}`, title: `Chapter ${i}` })), { id: 'mine', title: 'Groceries' }];
    let open: () => void = () => undefined;
    show(<CommandBar world={{ ...world, notes }} doing={doing} onReady={(opener) => (open = opener)} />);
    act(() => open());
    expect(document.body.textContent).not.toContain('Open Groceries');
    const field = () => palette()!.querySelector('input')!;
    act(() => typeInto(field(), 'groc'));
    expect(document.body.textContent).toContain('Open Groceries');
    act(() => {
      goBack();
    });
    act(() => open());
    expect(field().value).toBe('');
    expect(document.body.textContent).not.toContain('Open Groceries');
  });
});
