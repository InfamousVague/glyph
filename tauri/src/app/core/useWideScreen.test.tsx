import { act } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { rerender, show, unmount } from '../../test/render.tsx';
import { readSidebarShown, useSidebar, useWideScreen, writeSidebarShown } from './useWideScreen.ts';

/*
 * The window's shape (useWideScreen.ts): whether a header has room for more, whether the notes sit beside the note,
 * and whether the docked sidebar is showing. jsdom has no matchMedia, and src/test/stubs.ts's never changes its mind,
 * so this file keeps one whose answers a test sets and whose listeners it tells, as a window resized would.
 */

/** Each media query's answer now, and who is listening to it. */
const media = new Map<string, boolean>();
const listening = new Map<string, Set<() => void>>();

function resize(size: { wide?: boolean; wideHeader?: boolean; tall?: boolean; mouse?: boolean }): void {
  const next = new Map([
    ['(min-width: 600px)', size.wideHeader ?? size.wide ?? false],
    ['(min-width: 660px)', size.wide ?? false],
    ['(min-height: 600px)', size.tall ?? false],
    ['(pointer: fine)', size.mouse ?? false],
  ]);
  const changed = [...next].filter(([query, on]) => media.get(query) !== on).map(([query]) => query);
  for (const [query, on] of next) media.set(query, on);
  act(() => {
    for (const query of changed) for (const listener of listening.get(query) ?? []) listener();
  });
}

beforeEach(() => {
  media.clear();
  listening.clear();
  localStorage.clear();
  window.matchMedia = (query: string) =>
    ({
      get matches() {
        return media.get(query) ?? false;
      },
      media: query,
      addEventListener: (_: string, listener: () => void) => {
        if (!listening.has(query)) listening.set(query, new Set());
        listening.get(query)!.add(listener);
      },
      removeEventListener: (_: string, listener: () => void) => listening.get(query)?.delete(listener),
    }) as unknown as MediaQueryList;
});

afterEach(() => {
  unmount();
  (document.activeElement as HTMLElement | null)?.blur();
});

/** What the hooks answer now, as the screens that use them would read them. */
let shape = { wide: false, sidebar: false };
function Shape() {
  shape = { wide: useWideScreen(), sidebar: useSidebar() };
  return null;
}

describe('the window’s shape', () => {
  it('has room for more in a header from 600px, and answers again as the phone unfolds', () => {
    resize({ wideHeader: false });
    show(<Shape />);
    expect(shape.wide).toBe(false);
    resize({ wideHeader: true });
    expect(shape.wide).toBe(true);
  });

  it('puts the notes beside the note in a window wide and tall enough, and not in a phone held sideways', () => {
    resize({ wide: true, tall: true });
    show(<Shape />);
    expect(shape.sidebar).toBe(true);
    resize({ wide: true, tall: false });
    expect(shape.sidebar).toBe(false);
    resize({ wide: false, tall: true });
    expect(shape.sidebar).toBe(false);
  });

  it('takes a short window at its word under a mouse, where the person chose its size', () => {
    resize({ wide: true, tall: false, mouse: true });
    show(<Shape />);
    expect(shape.sidebar).toBe(true);
  });

  it('keeps the two panes while something is typed into and the keyboard takes the height away', () => {
    resize({ wide: true, tall: true });
    const field = document.body.appendChild(document.createElement('textarea'));
    show(<Shape />);
    field.focus();
    resize({ wide: true, tall: false });
    expect(shape.sidebar).toBe(true);
    // Folding the phone is the shape changing, keyboard or not.
    resize({ wide: false, tall: false });
    expect(shape.sidebar).toBe(false);
    field.remove();
  });

  it('lets the height decide again once nothing is being typed into', () => {
    resize({ wide: true, tall: true });
    const field = document.body.appendChild(document.createElement('input'));
    show(<Shape />);
    field.focus();
    resize({ wide: true, tall: false });
    expect(shape.sidebar).toBe(true);
    field.blur();
    // The next time the screen is drawn, the window's own height is the answer.
    rerender(<Shape />);
    expect(shape.sidebar).toBe(false);
    field.remove();
  });
});

describe('the docked sidebar', () => {
  it('shows by default under a mouse and starts hidden under a finger', () => {
    resize({ mouse: true });
    expect(readSidebarShown()).toBe(true);
    resize({ mouse: false });
    expect(readSidebarShown()).toBe(false);
  });

  it('remembers the choice once it has been toggled', () => {
    resize({ mouse: true });
    writeSidebarShown(false);
    expect(readSidebarShown()).toBe(false);
    resize({ mouse: false });
    writeSidebarShown(true);
    expect(readSidebarShown()).toBe(true);
  });
});
