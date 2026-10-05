import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';
import { VIEW_SAMPLE } from '../../test/canvas.ts';
import { preferences, reloadPreferences, setPreferences } from '../core/preferences.ts';
import { parseCanvas, type Canvas } from './jsonCanvas.ts';

vi.mock('mermaid', () => ({ default: { initialize: () => undefined, render: async (id: string) => ({ svg: `<svg id="${id}"></svg>` }) } }));
const felt = vi.hoisted(() => ({ fire: vi.fn() }));
vi.mock('../core/haptics.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/haptics.ts')>()), fireFelt: felt.fire }));

const { CanvasView } = await import('./CanvasView.tsx');

/**
 * Snapping to the grid's dots (docs/CANVAS.md; Matt: "Add the option for snapping to the grid dots on by default on
 * canvases", "Give haptics when it snaps"): on until the magnet is turned off, a card moved, resized, nudged or made
 * lands on the dots, 24px apart, and each new dot is felt.
 */

const canvas = parseCanvas(VIEW_SAMPLE) as Canvas;

function pointer(el: Element | Window, type: string, x: number, y: number, pointerType = 'mouse'): void {
  act(() => {
    el.dispatchEvent(Object.assign(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0 }), { pointerType, pointerId: 1 }));
  });
}
const tap = (el: Element, x = 10, y = 10) => act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: x, clientY: y })));
const key = (init: KeyboardEventInit) => act(() => window.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init })));
const card = (root: HTMLElement, id: string) => root.querySelector(`[data-card="${id}"]`) as HTMLElement;
const last = (onChange: ReturnType<typeof vi.fn>) => onChange.mock.calls.at(-1)![0] as Canvas;
const boxOf = (next: Canvas, id: string) => {
  const node = next.nodes.find((n) => n.id === id)!;
  return [node.x, node.y, node.width, node.height];
};

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  felt.fire.mockClear();
});
afterEach(() => vi.useRealTimers());

describe('snapping to the grid', () => {
  it('is on until it is turned off, and the magnet says which', () => {
    expect(preferences().canvasSnap).toBe(true);
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={vi.fn()} />);
    const magnet = shown.querySelector('button[aria-label="Snap to the grid"]') as HTMLElement;
    expect(magnet.getAttribute('aria-pressed')).toBe('true');
    act(() => magnet.click());
    expect(preferences().canvasSnap).toBe(false);
    expect(magnet.getAttribute('aria-pressed')).toBe('false');
    // A canvas that cannot change has nothing to snap, and no magnet.
    const still = show(<CanvasView canvas={canvas} dark={false} />);
    expect(still.querySelector('button[aria-label="Snap to the grid"]')).toBeNull();
  });

  it('lands a dragged card on the nearest dot, and ticks at each new one', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const el = card(shown, 'n');
    // n is at 300,100. Dragged 31 across and 43 down it would be at 331,143: the nearest dot is 336,144.
    pointer(el, 'pointerdown', 350, 150);
    pointer(el, 'pointermove', 360, 160);
    // 310,110: the nearest dot is 312,120. Drawn there on the way.
    expect([el.style.left, el.style.top]).toEqual(['312px', '120px']);
    expect(felt.fire).not.toHaveBeenCalled();
    pointer(el, 'pointermove', 362, 161);
    // The same dot: nothing more is felt.
    expect(felt.fire).not.toHaveBeenCalled();
    pointer(el, 'pointermove', 381, 193);
    expect(felt.fire).toHaveBeenCalledTimes(1);
    expect(felt.fire).toHaveBeenCalledWith('selection');
    pointer(el, 'pointerup', 381, 193);
    expect(boxOf(last(onChange), 'n')).toEqual([336, 144, 200, 80]);
  });

  it('moves a group and its cards by whole squares, so cards on the grid stay on it', () => {
    vi.useFakeTimers();
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const name = card(shown, 'g').querySelector('[data-group-grip]') as HTMLElement;
    // g is at -20,-20, off the grid: carried 50 across and 30 down it lands on 24,0, a move of 44 and 20 for all it holds.
    pointer(name, 'pointerdown', 20, 4, 'touch');
    pointer(name, 'pointermove', 70, 34, 'touch');
    pointer(name, 'pointerup', 70, 34, 'touch');
    expect(last(onChange).nodes.map((n) => [n.id, n.x, n.y])).toEqual([['g', 24, 0], ['t', 44, 20], ['f', 300, 0], ['n', 300, 100], ['l', 44, 120]]);
  });

  it('lands a resized card’s moving sides on the grid’s lines, the others staying put, with a tick at each', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    tap(card(shown, 'n'));
    const handle = (name: string) => shown.querySelector(`[data-handles="n"] [data-handle="${name}"]`) as HTMLElement;
    // n is 300,100 200x80: its right side is at 500, its foot at 180. Out by 30 and 10: the lines are 528 and 192.
    pointer(handle('se'), 'pointerdown', 500, 180);
    pointer(window, 'pointermove', 530, 190);
    expect(felt.fire).toHaveBeenCalledTimes(1);
    pointer(window, 'pointermove', 531, 191);
    expect(felt.fire).toHaveBeenCalledTimes(1);
    pointer(window, 'pointerup', 531, 191);
    expect(boxOf(last(onChange), 'n')).toEqual([300, 100, 228, 92]);
    // The top-left corner: its sides go to 288 and 96, and the far corner (528, 192) stays.
    pointer(handle('nw'), 'pointerdown', 300, 100);
    pointer(window, 'pointerup', 290, 95);
    expect(boxOf(last(onChange), 'n')).toEqual([288, 96, 240, 96]);
  });

  it('nudges by one dot with an arrow, from the nearest dot, and by a pixel with Alt', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    tap(card(shown, 'n'));
    // 300 is half-way to neither: the nearest line is 312 (300/24 is 12.5), and one dot along is 336. Down is untouched.
    key({ key: 'ArrowRight' });
    expect(boxOf(last(onChange), 'n').slice(0, 2)).toEqual([336, 100]);
    key({ key: 'ArrowDown', altKey: true });
    expect(boxOf(last(onChange), 'n').slice(0, 2)).toEqual([336, 101]);
  });

  it('makes a new card on a dot, and a second a square aside from it', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const add = (what: string) => {
      tap(shown.querySelector('button[aria-label="Add a card"]')!);
      tap([...document.querySelectorAll('[role="dialog"] button')].find((b) => b.textContent?.startsWith(what))!);
    };
    add('Words');
    const first = last(onChange).nodes.at(-1)!;
    expect([first.x % 24, first.y % 24].map(Math.abs)).toEqual([0, 0]);
    add('Words');
    const second = last(onChange).nodes.at(-1)!;
    expect([second.x - first.x, second.y - first.y]).toEqual([24, 24]);
  });

  it('leaves everything to the pixel with the magnet off, and nothing is felt', () => {
    setPreferences({ canvasSnap: false });
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const el = card(shown, 'n');
    pointer(el, 'pointerdown', 350, 150);
    pointer(el, 'pointermove', 381, 193);
    pointer(el, 'pointerup', 381, 193);
    expect(boxOf(last(onChange), 'n')).toEqual([331, 143, 200, 80]);
    expect(felt.fire).not.toHaveBeenCalled();
  });
});
