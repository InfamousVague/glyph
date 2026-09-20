import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { CanvasView } from './CanvasView.tsx';
import { parseCanvas, type Canvas } from './jsonCanvas.ts';
import { fitted, zoomedAt } from './viewport.ts';

let root: Root | null = null;
let host: HTMLDivElement | null = null;

function show(element: React.ReactElement): HTMLDivElement {
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
  act(() => root!.render(element));
  return host;
}

afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  root = null;
  host = null;
});

const canvas = parseCanvas(`{
  "nodes": [
    { "id": "g", "type": "group", "x": -20, "y": -20, "width": 400, "height": 200, "label": "Before" },
    { "id": "t", "type": "text", "x": 0, "y": 0, "width": 200, "height": 80, "text": "# Book it\\n\\n- [ ] The cabin", "color": "4" },
    { "id": "f", "type": "file", "x": 300, "y": 0, "width": 200, "height": 80, "file": "Launch week.md", "subpath": "#^photos" },
    { "id": "n", "type": "file", "x": 300, "y": 100, "width": 200, "height": 80, "file": "Nowhere.md" },
    { "id": "l", "type": "link", "x": 0, "y": 100, "width": 200, "height": 80, "url": "https://attack.fm/glyph", "color": "#ff8800" }
  ],
  "edges": [
    { "id": "e1", "fromNode": "t", "toNode": "f", "label": "then" },
    { "id": "e2", "fromNode": "t", "toNode": "l", "toEnd": "none" }
  ]
}`) as Canvas;

describe('a canvas drawn', () => {
  it('places every card where the file puts it, the group behind, and its words in the note’s own editor', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const cards = shown.querySelectorAll('[class*="card"]');
    expect(cards.length).toBeGreaterThanOrEqual(4);
    const text = shown.querySelector('[class*="card"][data-hue="moss"]') as HTMLElement;
    expect(text.style.left).toBe('0px');
    expect(text.style.width).toBe('200px');
    expect(text.querySelector('.cm-content')?.textContent).toContain('The cabin');
    expect(text.querySelector('.cm-content')?.getAttribute('contenteditable')).toBe('false');
    const group = shown.querySelector('[class*="group"]') as HTMLElement;
    expect(group.textContent).toBe('Before');
    // The group is first in the file, so it is first in the world: under the cards.
    expect(group.compareDocumentPosition(text) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('draws each line with an arrow at its end unless told not to, and the label on it', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const edges = shown.querySelectorAll('svg g');
    expect(edges).toHaveLength(2);
    expect(edges[0]?.querySelectorAll('path')).toHaveLength(2);
    expect(edges[0]?.querySelector('text')?.textContent).toBe('then');
    expect(edges[1]?.querySelectorAll('path')).toHaveLength(1);
    expect(edges[1]?.querySelector('text')).toBeNull();
  });

  it('paints a chosen hex as the card’s own colour, and names a link by its address', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const link = shown.querySelector('a[href="https://attack.fm/glyph"]') as HTMLElement;
    expect(link.style.getPropertyValue('--app-space')).toBe('#ff8800');
    expect(link.textContent).toContain('attack.fm/glyph');
  });

  it('opens a note card by its title and anchor on a tap, and says when the note is not there', () => {
    const open = vi.fn();
    const known = (title: string) => title === 'Launch week';
    const body = (title: string) => (title === 'Launch week' ? '# Launch week\n\n- [ ] Get the photos back ^photos' : null);
    const shown = show(<CanvasView canvas={canvas} dark={false} wiki={{ known, open, body }} />);
    const found = [...shown.querySelectorAll('[role="button"]')].find((el) => el.textContent?.includes('Launch week')) as HTMLElement;
    expect(found.textContent).toContain('photos');
    act(() => found.click());
    expect(open).toHaveBeenCalledWith('Launch week', '^photos');
    const missing = [...shown.querySelectorAll('[role="button"]')].find((el) => el.textContent?.includes('Nowhere')) as HTMLElement;
    expect(missing.hasAttribute('data-waiting')).toBe(true);
    expect(missing.textContent).toContain('Not in Glyph yet');
  });
});

describe('fitting the canvas to the screen', () => {
  it('scales the whole canvas into the screen with room around it, no larger than life, centred', () => {
    const view = fitted(canvas, 1000, 600);
    // The cards run from -20 to 500 across and -20 to 180 down: 520 by 200, which fits a 1000 by 600 screen at life size.
    expect(view.scale).toBe(1);
    expect(view.x).toBe((1000 - 520) / 2 + 20);
    expect(view.y).toBe((600 - 200) / 2 + 20);
    const small = fitted(canvas, 300, 300);
    expect(small.scale).toBeCloseTo((300 - 64) / 520, 5);
    expect(fitted({ nodes: [], edges: [] }, 300, 300)).toEqual({ x: 32, y: 32, scale: 1 });
  });

  it('zooms about a point of the screen, keeping what was under it under it', () => {
    const view = { x: 100, y: 50, scale: 1 };
    // The canvas point under (300, 250) is (200, 200); at double size it must still be at (300, 250).
    const doubled = zoomedAt(view, 300, 250, 2);
    expect(doubled).toEqual({ x: 300 - 200 * 2, y: 250 - 200 * 2, scale: 2 });
    expect(zoomedAt(view, 0, 0, 99).scale).toBe(3);
    expect(zoomedAt(view, 0, 0, 0.001).scale).toBe(0.1);
  });
});

describe('a canvas edited', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const pointer = (el: Element, type: string, x: number, y: number) =>
    act(() => {
      el.dispatchEvent(new MouseEvent(type, { bubbles: true, clientX: x, clientY: y, button: 0 }));
    });
  const tapTwice = (el: Element, x: number, y: number) => {
    act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: x, clientY: y })));
    act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: x, clientY: y })));
  };

  it('is read-only without onChange, and a double-tap on the page then makes a card of words, open', () => {
    const still = show(<CanvasView canvas={canvas} dark={false} />);
    expect(still.querySelector('[role="img"]')).not.toBeNull();
    act(() => root?.unmount());
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const page = shown.firstElementChild as HTMLElement;
    expect(page.getAttribute('role')).toBeNull();
    tapTwice(page, 600, 400);
    expect(onChange).toHaveBeenCalledTimes(1);
    const next = onChange.mock.calls[0]![0] as Canvas;
    expect(next.nodes.length).toBe(canvas.nodes.length + 1);
    const made = next.nodes.at(-1)!;
    expect(made).toMatchObject({ type: 'text', text: '', width: 260, height: 120 });
    expect(made.id).toMatch(/^[0-9a-f]{16}$/);
    // Open to be written in, at once.
    expect(shown.querySelector(`[data-card="${made.id}"][data-editing]`)).not.toBeNull();
  });

  it('lifts a card on a held press and puts it down where the finger let go, to the pixel', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const card = shown.querySelector('[data-card="t"]') as HTMLElement;
    pointer(card, 'pointerdown', 50, 40);
    act(() => vi.advanceTimersByTime(250));
    expect(card.hasAttribute('data-lifted')).toBe(true);
    pointer(card, 'pointermove', 80.4, 25.6);
    pointer(card, 'pointerup', 80.4, 25.6);
    expect(onChange).toHaveBeenCalledTimes(1);
    const moved = (onChange.mock.calls[0]![0] as Canvas).nodes.find((n) => n.id === 't')!;
    expect(moved).toMatchObject({ x: 30, y: -14 });
    expect(shown.querySelector('[data-lifted]')).toBeNull();
  });

  it('pans rather than lifting when the finger moves before the hold, so the card stays put', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const card = shown.querySelector('[data-card="t"]') as HTMLElement;
    pointer(card, 'pointerdown', 50, 40);
    pointer(card, 'pointermove', 90, 40);
    act(() => vi.advanceTimersByTime(300));
    pointer(card, 'pointerup', 90, 40);
    expect(onChange).not.toHaveBeenCalled();
  });

  it('opens a card of words on a double-tap, writes what is typed into the canvas, and takes the card off', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const card = shown.querySelector('[data-card="t"]') as HTMLElement;
    tapTwice(card, 50, 40);
    expect(card.hasAttribute('data-editing')).toBe(true);
    const remove = card.querySelector('button[aria-label*="off the canvas"]') as HTMLElement;
    expect(remove).not.toBeNull();
    act(() => remove.click());
    expect(onChange).toHaveBeenCalledTimes(1);
    const next = onChange.mock.calls[0]![0] as Canvas;
    expect(next.nodes.find((n) => n.id === 't')).toBeUndefined();
    // Its two lines went with it.
    expect(next.edges).toEqual([]);
  });
});

describe('lines drawn', () => {
  const tap = (el: Element, x = 10, y = 10) => act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: x, clientY: y })));

  it('draws a line from the first card tapped to the second with the Line tool, once, and never onto itself', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const tool = shown.querySelector('button[aria-label^="Draw a line"]') as HTMLElement;
    act(() => tool.click());
    expect(shown.firstElementChild?.getAttribute('data-lining')).toBe('from');
    const from = shown.querySelector('[data-card="f"]') as HTMLElement;
    const to = shown.querySelector('[data-card="l"]') as HTMLElement;
    tap(from);
    expect(from.hasAttribute('data-line-from')).toBe(true);
    expect(shown.firstElementChild?.getAttribute('data-lining')).toBe('to');
    // The same card again is not a line.
    tap(from);
    expect(onChange).not.toHaveBeenCalled();
    tap(to);
    expect(onChange).toHaveBeenCalledTimes(1);
    const next = onChange.mock.calls[0]![0] as Canvas;
    expect(next.edges.at(-1)).toMatchObject({ fromNode: 'f', toNode: 'l' });
    expect(next.edges.at(-1)!.id).toMatch(/^[0-9a-f]{16}$/);
    // The tool is put down, and the new line is picked, its words ready to be written.
    expect(shown.firstElementChild?.hasAttribute('data-lining')).toBe(false);
    expect(shown.querySelector('input[aria-label="Words on the line"]')).not.toBeNull();
  });

  it('picks a line on a tap, writes words on it, and takes it off', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const hit = shown.querySelector('[data-line="e2"] path') as SVGPathElement;
    tap(hit);
    expect(shown.querySelector('[data-line="e2"]')?.hasAttribute('data-picked')).toBe(true);
    const field = shown.querySelector('input[aria-label="Words on the line"]') as HTMLInputElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
      setter.call(field, 'after');
      field.dispatchEvent(new Event('input', { bubbles: true }));
    });
    act(() => field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })));
    expect(onChange).toHaveBeenCalledTimes(1);
    expect((onChange.mock.calls[0]![0] as Canvas).edges.find((e) => e.id === 'e2')).toMatchObject({ label: 'after' });
    const remove = shown.querySelector('button[aria-label="Take this line off the canvas"]') as HTMLElement;
    act(() => remove.click());
    expect((onChange.mock.calls[1]![0] as Canvas).edges.find((e) => e.id === 'e2')).toBeUndefined();
  });
});
