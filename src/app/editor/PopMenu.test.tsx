import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from 'vitest';
import { act, useMemo, useState, type ReactNode } from 'react';
import { flushSync } from 'react-dom';
import { goBack, installBack, onBack } from '../core/back.ts';
import { show } from '../../test/render.tsx';
import { stubMatchMedia } from '../../test/stubs.ts';
import type { Reach } from './PopMenu.tsx';
import styles from './PopMenu.module.css';

/**
 * The kit's menu hung from something on the page (editor/PopMenu.tsx): that the kit really places it from the element
 * it is given, what closes it and that its owner hears so once and late enough for the kit to give the focus back, the
 * room it is given, the side of the opened Fold's crease it keeps to, and where its nested rows go.
 */

// The Glacier kit asks matchMedia as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
const { PopMenu, PopSub } = await import('./PopMenu.tsx');
const { MenuItem } = await import('@glacier/react');

let at: HTMLButtonElement;
let box: DOMRect;
let dismissed: Mock<() => void>;

/** An owner as the app's are: the menu drawn while it is open, taken down when it says it is done. */
function Owner({ placement, reach, children, now = false }: { placement?: 'bottom-start' | 'bottom-end'; reach?: Reach; children?: ReactNode; now?: boolean }) {
  const [open, setOpen] = useState(true);
  const anchor = useMemo(() => ({ current: at }), []);
  if (!open) return null;
  return (
    <PopMenu
      anchor={anchor}
      placement={placement}
      reach={reach}
      aria-label="Card"
      onDismiss={() => {
        dismissed();
        // Taken down there and then, with no render of its own to wait for: the harshest owner there is.
        if (now) flushSync(() => setOpen(false));
        else setOpen(false);
      }}
    >
      {children ?? (
        <>
          <MenuItem>Move to Done</MenuItem>
          <MenuItem>Take off the board</MenuItem>
        </>
      )}
    </PopMenu>
  );
}

const panel = () => document.querySelector<HTMLElement>('[role="menu"][aria-label="Card"]');
/** Whether `element` wears this stylesheet's class `name`. */
const wears = (element: Element, name: string) => element.classList.contains(styles[name] ?? `(no .${name})`);
const rows = () => [...document.querySelectorAll('[role="menuitem"]')].map((row) => row.textContent);
/** Lets the owner hear what was queued for it, and React draw what it did. */
const settle = () => act(async () => undefined);
const frame = () => act(async () => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));

function sized(width: number, height: number) {
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: width });
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: height });
}

beforeEach(() => {
  dismissed = vi.fn();
  at = document.body.appendChild(document.createElement('button'));
  at.textContent = 'More';
  at.setAttribute('aria-expanded', 'false');
  box = new DOMRect(100, 50, 24, 24);
  at.getBoundingClientRect = () => box;
  // The kit's panel is 300 wide wherever it is drawn; jsdom lays nothing out.
  Object.defineProperty(HTMLElement.prototype, 'offsetWidth', {
    configurable: true,
    get(this: HTMLElement) {
      return this.getAttribute('role') === 'menu' ? 300 : 0;
    },
  });
});

afterEach(() => {
  at.remove();
  Reflect.deleteProperty(HTMLElement.prototype, 'offsetWidth');
  sized(1024, 768);
  stubMatchMedia(false);
  document.documentElement.style.removeProperty('font-size');
});

describe('where it hangs', () => {
  it('hangs from the element it is given: at the body, fixed, over everything, under the element', () => {
    show(<Owner />);
    const menu = panel()!;
    expect(menu.parentElement).toBe(document.body);
    expect(menu.style.position).toBe('fixed');
    expect(menu.style.zIndex).toBe('200');
    expect(menu.style.top).toBe(`${50 + 24 + 8}px`);
    expect(menu.style.left).toBe('100px');
  });

  it('hangs from a point, a right-click’s: a mark of no size at the body, taken away with the menu', async () => {
    function AtPoint() {
      const [open, setOpen] = useState(true);
      return open ? (
        <PopMenu at={{ x: 120, y: 80 }} aria-label="Card" onDismiss={() => setOpen(false)}>
          <MenuItem>Open</MenuItem>
        </PopMenu>
      ) : null;
    }
    const realBox = HTMLElement.prototype.getBoundingClientRect;
    // jsdom lays nothing out: the mark answers where it was put, as a browser would for a fixed box of no size.
    HTMLElement.prototype.getBoundingClientRect = function (this: HTMLElement) {
      return this.dataset.popPoint === undefined ? realBox.call(this) : new DOMRect(parseFloat(this.style.left), parseFloat(this.style.top), 0, 0);
    };
    try {
      show(<AtPoint />);
      const mark = document.querySelector<HTMLElement>('[data-pop-point]')!;
      expect(mark.parentElement).toBe(document.body);
      expect(mark.style.position).toBe('fixed');
      expect(panel()!.style.top).toBe(`${80 + 8}px`);
      expect(panel()!.style.left).toBe('120px');
      act(() => void goBack());
      await settle();
      expect(panel()).toBeNull();
      expect(document.querySelector('[data-pop-point]')).toBeNull();
    } finally {
      HTMLElement.prototype.getBoundingClientRect = realBox;
    }
  });

  it('names its panel on the element while it is open, and gives the element back its own names after', async () => {
    show(<Owner />);
    expect(at.getAttribute('aria-expanded')).toBe('true');
    expect(at.getAttribute('aria-controls')).toBe(panel()!.id);
    act(() => void goBack());
    await settle();
    expect(panel()).toBeNull();
    expect(at.getAttribute('aria-expanded')).toBe('false');
    expect(at.hasAttribute('aria-controls')).toBe(false);
  });

  it('wears the room it reaches for: down from the top bar, or either way from the page', () => {
    show(<Owner reach="down" />);
    expect(wears(panel()!, 'pop')).toBe(true);
    expect(wears(panel()!, 'down')).toBe(true);
    expect(wears(panel()!, 'either')).toBe(false);
  });

  it('reaches either way by default', () => {
    show(<Owner />);
    expect(wears(panel()!, 'pop')).toBe(true);
    expect(wears(panel()!, 'either')).toBe(true);
  });
});

describe('what closes it', () => {
  it('the back gesture, taken, with the owner told once and a microtask later', async () => {
    show(<Owner />);
    let took = false;
    act(() => void (took = goBack()));
    expect(took).toBe(true);
    expect(dismissed).not.toHaveBeenCalled();
    await settle();
    expect(dismissed).toHaveBeenCalledOnce();
    expect(panel()).toBeNull();
  });

  it('Escape, once, going no further down the back stack, and the focus back on its element even when the owner takes it down at once', async () => {
    const stop = installBack();
    const under = vi.fn(() => true);
    const unstack = onBack(under);
    try {
      show(<Owner now />);
      await frame();
      // The kit takes the focus into its first row a frame after it opens.
      expect(document.activeElement?.textContent).toBe('Move to Done');
      act(() => void document.activeElement!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true })));
      await settle();
      expect(dismissed).toHaveBeenCalledOnce();
      expect(under).not.toHaveBeenCalled();
      expect(panel()).toBeNull();
      expect(document.activeElement).toBe(at);
    } finally {
      unstack();
      stop();
    }
  });

  it('a press anywhere else, even one whose target keeps it to itself; not a press on its element or in it', async () => {
    const other = document.body.appendChild(document.createElement('div'));
    // As a card keeps its press and hold for its drag (boards/drag.ts), and the lanes' line for its own.
    other.addEventListener('pointerdown', (event) => event.stopPropagation());
    try {
      show(<Owner />);
      act(() => void at.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
      act(() => void panel()!.querySelector('[role="menuitem"]')!.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
      await settle();
      expect(dismissed).not.toHaveBeenCalled();
      act(() => void other.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
      await settle();
      expect(dismissed).toHaveBeenCalledOnce();
      expect(panel()).toBeNull();
    } finally {
      other.remove();
    }
  });

  it('a press the kit hears too, heard once', async () => {
    show(<Owner />);
    act(() => void document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
    await settle();
    expect(dismissed).toHaveBeenCalledOnce();
  });

  it('its element leaving the page', async () => {
    show(<Owner />);
    at.remove();
    act(() => void window.dispatchEvent(new Event('scroll')));
    await frame();
    await settle();
    expect(dismissed).toHaveBeenCalledOnce();
  });

  it('a scroll that takes its element off the screen, and not one that leaves it on', async () => {
    show(<Owner />);
    box = new DOMRect(100, 400, 24, 24);
    act(() => void window.dispatchEvent(new Event('scroll')));
    await frame();
    await settle();
    expect(dismissed).not.toHaveBeenCalled();
    box = new DOMRect(100, -60, 24, 24);
    act(() => void window.dispatchEvent(new Event('scroll')));
    await frame();
    await settle();
    expect(dismissed).toHaveBeenCalledOnce();
  });
});

describe('the opened Fold’s crease', () => {
  const opened = () => stubMatchMedia((query) => query.includes('pointer: coarse') && window.innerWidth >= 600);
  const left = () => parseFloat(panel()!.style.left);

  it('hangs a menu from an element just left of the crease by its end, on the left', () => {
    sized(880, 790);
    opened();
    box = new DOMRect(396, 100, 24, 24);
    show(<Owner placement="bottom-start" />);
    expect(left()).toBe(420 - 300);
    expect(wears(panel()!, 'creased')).toBe(true);
  });

  it('hangs one from just right of it by its start, on the right', () => {
    sized(880, 790);
    opened();
    box = new DOMRect(460, 100, 24, 24);
    show(<Owner placement="bottom-end" />);
    expect(left()).toBe(460);
  });

  it('leaves one alone that fits its side as asked', () => {
    sized(880, 790);
    opened();
    box = new DOMRect(40, 100, 24, 24);
    show(<Owner placement="bottom-start" />);
    expect(left()).toBe(40);
    expect(wears(panel()!, 'creased')).toBe(true);
  });

  it('is no matter on a phone', () => {
    sized(412, 915);
    opened();
    box = new DOMRect(100, 100, 24, 24);
    show(<Owner placement="bottom-start" />);
    expect(left()).toBe(100);
    expect(wears(panel()!, 'creased')).toBe(false);
  });
});

describe('rows under a name', () => {
  const nested = (
    <>
      <MenuItem>Rename</MenuItem>
      <PopSub label="Colour">
        <MenuItem aria-label="Colour: Ink">Ink</MenuItem>
        <MenuItem aria-label="Colour: Sea">Sea</MenuItem>
      </PopSub>
    </>
  );
  const mouse = (query: string) => query.includes('pointer: fine') || query.includes('hover: hover');
  const inPlace = () => {
    expect(rows()).toEqual(['Rename', 'Ink', 'Sea']);
    expect(document.querySelector('[role="presentation"]')?.textContent).toBe('Colour');
    expect(document.querySelector('[aria-haspopup="menu"]')).toBeNull();
    expect(document.querySelector('[aria-label="Colour: Sea"]')).not.toBeNull();
  };

  it('are listed in place, under their name, where nothing is said of the pointer', () => {
    show(<Owner>{nested}</Owner>);
    inPlace();
  });

  it('fly out for a mouse on a window with room for a flyout either side of the menu', async () => {
    sized(1280, 900);
    stubMatchMedia(mouse);
    show(<Owner>{nested}</Owner>);
    const colour = document.querySelector<HTMLElement>('[role="menuitem"][aria-haspopup="menu"]')!;
    expect(colour.textContent).toBe('Colour');
    expect(rows()).toEqual(['Rename', 'Colour']);
    act(() => colour.click());
    await settle();
    expect(rows()).toEqual(['Rename', 'Colour', 'Ink', 'Sea']);
    // The flyout is the menu's own: a press in it closes nothing.
    const flyout = document.querySelector<HTMLElement>('[role="menu"][aria-label="Colour"]')!;
    expect(wears(flyout, 'pop')).toBe(true);
    act(() => void flyout.querySelector('[role="menuitem"]')!.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
    await settle();
    expect(dismissed).not.toHaveBeenCalled();
  });

  it('are in place for a mouse on a window without that room', () => {
    sized(1000, 800);
    stubMatchMedia(mouse);
    show(<Owner>{nested}</Owner>);
    inPlace();
  });

  it('are in place for a mouse at 1280 when the interface is at 125%', () => {
    sized(1280, 900);
    stubMatchMedia(mouse);
    document.documentElement.style.fontSize = '20px';
    show(<Owner>{nested}</Owner>);
    inPlace();
  });

  it('are in place under a finger, on the opened Fold too', () => {
    sized(880, 790);
    stubMatchMedia((query) => query.includes('pointer: coarse'));
    show(<Owner>{nested}</Owner>);
    inPlace();
  });
});
