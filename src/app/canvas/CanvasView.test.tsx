import { afterEach, describe, expect, it, vi } from 'vitest';
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
