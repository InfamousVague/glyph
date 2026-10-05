import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';
import { VIEW_SAMPLE } from '../../test/canvas.ts';
import { CanvasView } from './CanvasView.tsx';
import { setPreferences } from '../core/preferences.ts';
import { parseCanvas, type Canvas } from './jsonCanvas.ts';

vi.mock('mermaid', () => ({ default: { initialize: () => undefined, render: async (id: string) => ({ svg: `<svg id="${id}"></svg>` }) } }));
const opened = vi.hoisted(() => ({ link: vi.fn(async () => undefined) }));
vi.mock('../core/linkPreview.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/linkPreview.ts')>()), openLink: opened.link }));

/**
 * The canvas's controls (docs/CANVAS.md, the eighth slice; Matt: "navigating it and resizing things are not easy
 * especially on mobile"): a tap picks and the next opens, a mouse drags a card and a finger drags the picked one, a
 * group is taken by its name, the keys, the picked card's bar, and what the + makes. Resizing by the handles is in
 * CanvasView.test.tsx, beside the sizes.
 */

const canvas = parseCanvas(VIEW_SAMPLE) as Canvas;

/** A pointer event of one kind of pointer: jsdom's MouseEvent says nothing of what made it. */
function pointer(el: Element | Window, type: string, x: number, y: number, pointerType = 'touch', button = 0): void {
  act(() => {
    el.dispatchEvent(Object.assign(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, button }), { pointerType, pointerId: 1 }));
  });
}
const tap = (el: Element, x = 10, y = 10) => act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: x, clientY: y })));
const key = (init: KeyboardEventInit) => act(() => window.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init })));
const card = (root: HTMLElement, id: string) => root.querySelector(`[data-card="${id}"]`) as HTMLElement;
const last = (onChange: ReturnType<typeof vi.fn>) => onChange.mock.calls.at(-1)![0] as Canvas;
const placeOf = (next: Canvas, id: string) => {
  const node = next.nodes.find((n) => n.id === id)!;
  return [node.x, node.y];
};
const barOf = (root: HTMLElement, id: string) => [...root.querySelectorAll(`[data-card-bar="${id}"] button`)].map((b) => b.getAttribute('aria-label'));
const press = (root: HTMLElement, id: string, label: string) => act(() => (root.querySelector(`[data-card-bar="${id}"] button[aria-label="${label}"]`) as HTMLElement).click());

// Moves here are measured to the pixel, so the magnet is off: snapping has its own tests (CanvasView.snap.test.tsx).
beforeEach(() => {
  opened.link.mockClear();
  setPreferences({ canvasSnap: false });
});

describe('picking a card', () => {
  it('picks a note card on the first tap and opens it on the next, or from its bar', () => {
    const open = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={vi.fn()} wiki={{ known: () => true, open }} />);
    const note = card(shown, 'f');
    tap(note);
    expect(open).not.toHaveBeenCalled();
    expect(note.hasAttribute('data-selected')).toBe(true);
    expect(barOf(shown, 'f')).toEqual(['Open the note', 'Draw a line from this card', 'Colour', 'Make a copy', 'Take this card off the canvas']);
    tap(note);
    expect(open).toHaveBeenCalledWith('Launch week', '^photos');
    press(shown, 'f', 'Open the note');
    expect(open).toHaveBeenCalledTimes(2);
  });

  it('picks an address on the first tap, so the page does not leave for it, and opens it on the next', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={vi.fn()} />);
    const link = card(shown, 'l');
    tap(link);
    expect(opened.link).not.toHaveBeenCalled();
    expect(link.hasAttribute('data-selected')).toBe(true);
    tap(link);
    expect(opened.link).toHaveBeenCalledWith('https://attack.fm/glyph');
  });

  it('opens a card at once on a canvas that cannot change, as it did, and picks nothing', () => {
    const open = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} wiki={{ known: () => true, open }} />);
    tap(card(shown, 'f'));
    expect(open).toHaveBeenCalledTimes(1);
    expect(shown.querySelector('[data-selected]')).toBeNull();
    expect(shown.querySelector('[data-handles]')).toBeNull();
    expect(shown.querySelector('[data-card-bar]')).toBeNull();
  });

  it('lets the card go on a tap of the page, and Escape lets go of one thing at a time', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={vi.fn()} />);
    const page = shown.firstElementChild as HTMLElement;
    tap(card(shown, 't'));
    tap(card(shown, 't'));
    expect(card(shown, 't').hasAttribute('data-editing')).toBe(true);
    key({ key: 'Escape' });
    // The writing first; the card is still picked.
    expect(card(shown, 't').hasAttribute('data-editing')).toBe(false);
    expect(card(shown, 't').hasAttribute('data-selected')).toBe(true);
    key({ key: 'Escape' });
    expect(shown.querySelector('[data-selected]')).toBeNull();
    tap(card(shown, 'n'));
    expect(card(shown, 'n').hasAttribute('data-selected')).toBe(true);
    tap(page, 700, 500);
    expect(shown.querySelector('[data-selected]')).toBeNull();
  });

  it('puts the bar under a card whose top is at the top of the screen', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={vi.fn()} />);
    // The view opens with the canvas's corner 32px in: t's top is at 52 on the screen, too near for a bar over it.
    tap(card(shown, 't'));
    expect(shown.querySelector('[data-card-bar="t"]')?.hasAttribute('data-below')).toBe(true);
    // n is 100 further down: there is room over it.
    tap(card(shown, 'n'));
    expect(shown.querySelector('[data-card-bar="n"]')?.hasAttribute('data-below')).toBe(false);
  });
});

describe('moving a card', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('moves a card with a mouse that drags it, with no hold, and picks it', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const el = card(shown, 'n');
    pointer(el, 'pointerdown', 350, 150, 'mouse');
    pointer(el, 'pointermove', 380, 190, 'mouse');
    expect(el.hasAttribute('data-lifted')).toBe(true);
    pointer(el, 'pointerup', 380, 190, 'mouse');
    expect(placeOf(last(onChange), 'n')).toEqual([330, 140]);
    expect(card(shown, 'n').hasAttribute('data-selected')).toBe(true);
  });

  it('pans under a finger that drags a card not picked, and moves the picked one', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const world = shown.querySelector('[class*="world"]') as HTMLElement;
    const before = world.style.transform;
    pointer(card(shown, 'n'), 'pointerdown', 350, 150);
    pointer(card(shown, 'n'), 'pointermove', 380, 190);
    pointer(card(shown, 'n'), 'pointerup', 380, 190);
    expect(onChange).not.toHaveBeenCalled();
    expect(world.style.transform).not.toBe(before);
    // Picked - by a tap as a finger makes one, a press and then the click - the same drag is the card's.
    pointer(card(shown, 'n'), 'pointerdown', 350, 150);
    pointer(card(shown, 'n'), 'pointerup', 350, 150);
    tap(card(shown, 'n'));
    const panned = world.style.transform;
    pointer(card(shown, 'n'), 'pointerdown', 350, 150);
    pointer(card(shown, 'n'), 'pointermove', 380, 190);
    pointer(card(shown, 'n'), 'pointerup', 380, 190);
    expect(placeOf(last(onChange), 'n')).toEqual([330, 140]);
    expect(world.style.transform).toBe(panned);
  });

  it('pans with the middle button and with Space held, whatever is under the pointer', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const world = shown.querySelector('[class*="world"]') as HTMLElement;
    const before = world.style.transform;
    pointer(card(shown, 'n'), 'pointerdown', 350, 150, 'mouse', 1);
    pointer(card(shown, 'n'), 'pointermove', 380, 190, 'mouse', 1);
    pointer(card(shown, 'n'), 'pointerup', 380, 190, 'mouse', 1);
    expect(onChange).not.toHaveBeenCalled();
    expect(world.style.transform).not.toBe(before);
    const middle = world.style.transform;
    key({ code: 'Space', key: ' ' });
    pointer(card(shown, 'n'), 'pointerdown', 350, 150, 'mouse');
    pointer(card(shown, 'n'), 'pointermove', 380, 190, 'mouse');
    pointer(card(shown, 'n'), 'pointerup', 380, 190, 'mouse');
    act(() => window.dispatchEvent(new KeyboardEvent('keyup', { code: 'Space', key: ' ' })));
    expect(onChange).not.toHaveBeenCalled();
    expect(world.style.transform).not.toBe(middle);
  });

  it('takes a group by its name, with everything in it, and pans from its ground', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const group = card(shown, 'g');
    const world = shown.querySelector('[class*="world"]') as HTMLElement;
    // jsdom lays nothing out: the group's box on the screen is given, so its ground is told from its border.
    group.getBoundingClientRect = () => ({ left: 12, top: 12, right: 412, bottom: 212, width: 400, height: 200, x: 12, y: 12, toJSON: () => ({}) }) as DOMRect;
    const before = world.style.transform;
    pointer(group, 'pointerdown', 250, 110, 'mouse');
    pointer(group, 'pointermove', 280, 140, 'mouse');
    pointer(group, 'pointerup', 280, 140, 'mouse');
    expect(onChange).not.toHaveBeenCalled();
    expect(world.style.transform).not.toBe(before);
    const name = group.querySelector('[data-group-grip]') as HTMLElement;
    expect(name.textContent).toBe('Before');
    pointer(name, 'pointerdown', 20, 4);
    pointer(name, 'pointermove', 70, 34);
    pointer(name, 'pointerup', 70, 34);
    expect(last(onChange).nodes.map((n) => [n.id, n.x, n.y])).toEqual([['g', 30, 10], ['t', 50, 30], ['f', 300, 0], ['n', 300, 100], ['l', 50, 130]]);
    // And by its border, a finger's width of it.
    pointer(group, 'pointerdown', 16, 110);
    pointer(group, 'pointermove', 36, 110);
    pointer(group, 'pointerup', 36, 110);
    expect(onChange).toHaveBeenCalledTimes(2);
  });
});

describe('the keys', () => {
  it('nudges the picked card with the arrows, ten pixels or one with Alt, and takes it off with Delete', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    key({ key: 'ArrowRight' });
    key({ key: 'Delete' });
    expect(onChange).not.toHaveBeenCalled();
    tap(card(shown, 'n'));
    key({ key: 'ArrowRight' });
    expect(placeOf(last(onChange), 'n')).toEqual([310, 100]);
    key({ key: 'ArrowUp', altKey: true });
    expect(placeOf(last(onChange), 'n')).toEqual([310, 99]);
    key({ key: 'Delete' });
    expect(last(onChange).nodes.find((n) => n.id === 'n')).toBeUndefined();
    expect(shown.querySelector('[data-card-bar]')).toBeNull();
  });

  it('leaves the keys to a card being written in', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    tap(card(shown, 't'));
    tap(card(shown, 't'));
    key({ key: 'Backspace' });
    key({ key: 'ArrowLeft' });
    expect(onChange).not.toHaveBeenCalled();
  });

  it('copies the picked card with Ctrl or Cmd+D, a step aside, and picks the copy', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    tap(card(shown, 'n'));
    key({ key: 'd', metaKey: true });
    const next = last(onChange);
    const copy = next.nodes.at(-1)!;
    expect(copy).toMatchObject({ type: 'file', file: 'Nowhere.md', x: 324, y: 124, width: 200, height: 80 });
    expect(copy.id).not.toBe('n');
    expect(shown.querySelector(`[data-card="${copy.id}"]`)?.hasAttribute('data-selected')).toBe(true);
  });
});

describe('the picked card’s bar', () => {
  it('colours a card with one of the page’s hues, and takes the colour off', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    tap(card(shown, 'n'));
    press(shown, 'n', 'Colour');
    expect(barOf(shown, 'n')).toEqual(['No colour', 'Rose', 'Ember', 'Amber', 'Moss', 'Sea', 'Violet', 'Done with the colour']);
    press(shown, 'n', 'Sea');
    expect(last(onChange).nodes.find((n) => n.id === 'n')).toMatchObject({ color: '5' });
    expect(card(shown, 'n').getAttribute('data-hue')).toBe('sea');
    press(shown, 'n', 'No colour');
    expect('color' in last(onChange).nodes.find((n) => n.id === 'n')!).toBe(false);
    press(shown, 'n', 'Done with the colour');
    expect(barOf(shown, 'n')).toContain('Make a copy');
  });

  it('starts a line from the card, so the next card tapped ends it', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    tap(card(shown, 'n'));
    press(shown, 'n', 'Draw a line from this card');
    expect(shown.firstElementChild?.getAttribute('data-lining')).toBe('to');
    expect(card(shown, 'n').hasAttribute('data-line-from')).toBe(true);
    tap(card(shown, 'l'));
    expect(last(onChange).edges.at(-1)).toMatchObject({ fromNode: 'n', toNode: 'l' });
    expect(opened.link).not.toHaveBeenCalled();
  });

  it('writes in a card of words from the bar, and says when it is done', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={vi.fn()} />);
    tap(card(shown, 't'));
    press(shown, 't', 'Write in this card');
    expect(card(shown, 't').hasAttribute('data-editing')).toBe(true);
    press(shown, 't', 'Done writing');
    expect(card(shown, 't').hasAttribute('data-editing')).toBe(false);
    expect(card(shown, 't').hasAttribute('data-selected')).toBe(true);
  });
});

describe('what the + makes', () => {
  const add = (shown: HTMLElement, what: string) => {
    tap(shown.querySelector('button[aria-label="Add a card"]')!);
    tap([...document.querySelectorAll('[role="dialog"] button')].find((b) => b.textContent?.startsWith(what))!);
  };

  it('makes a group about the picked card, under the cards, its name open to be written', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    tap(card(shown, 'n'));
    add(shown, 'A group');
    const next = last(onChange);
    // First in the file, so it is drawn under every card; with room round the card it was made about.
    expect(next.nodes[0]).toMatchObject({ type: 'group', x: 276, y: 76, width: 248, height: 128 });
    expect(next.nodes.length).toBe(canvas.nodes.length + 1);
    expect(shown.querySelector(`[data-card="${next.nodes[0]!.id}"] input`)).not.toBeNull();
  });

  it('makes a group of its own mid-screen when no card is picked', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    add(shown, 'A group');
    expect(last(onChange).nodes[0]).toMatchObject({ type: 'group', width: 480, height: 320 });
  });

  it('never sets a new card exactly on the last one', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    add(shown, 'Words');
    const first = last(onChange).nodes.at(-1)!;
    add(shown, 'A table');
    const second = last(onChange).nodes.at(-1)!;
    expect([second.x - first.x, second.y - first.y]).not.toEqual([0, 0]);
  });
});

describe('the zoom buttons', () => {
  it('go closer and further about the middle of the screen, and stop at the ends', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const world = shown.querySelector('[class*="world"]') as HTMLElement;
    const scale = () => Number(/scale\(([-\d.e]+)\)/.exec(world.style.transform)![1]);
    const before = scale();
    act(() => (shown.querySelector('button[aria-label="Zoom in"]') as HTMLElement).click());
    expect(scale()).toBeCloseTo(before * 1.3, 6);
    act(() => (shown.querySelector('button[aria-label="Zoom out"]') as HTMLElement).click());
    expect(scale()).toBeCloseTo(before, 6);
    for (let n = 0; n < 20; n += 1) act(() => (shown.querySelector('button[aria-label="Zoom out"]') as HTMLElement).click());
    expect(scale()).toBeCloseTo(0.1, 6);
  });
});
