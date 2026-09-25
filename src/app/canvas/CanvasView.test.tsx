import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, typeInto, unmount, waitUntil } from '../../test/render.tsx';
import { goBack } from '../core/back.ts';
import { CanvasView } from './CanvasView.tsx';
import { HOLD_MS } from './gestures.ts';

// Only the three the canvas calls are stood in for: the editor reads the rest of this module as it is.
/*
 * The chart card opens as a Mermaid diagram (editor/mermaid.ts), which loads the mermaid library the first time it
 * draws: a dynamic import that takes seconds to evaluate. Left real, it kept running after the chart test ended and
 * landed on the next test's turn of the queue - the drop test's `act` took two seconds alone and six under load,
 * against forty milliseconds with it out of the way. These tests are of the canvas, not of the drawing.
 */
vi.mock('mermaid', () => ({
  default: {
    initialize: () => undefined,
    render: async (id: string) => ({ svg: `<svg id="${id}"></svg>` }),
  },
}));
vi.mock('../core/images.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/images.ts')>()),
  imageUrl: (name: string) => `blob:${name}`,
  pickImage: vi.fn(async () => 'picked.jpg'),
  saveImageFile: vi.fn(async () => 'dropped.jpg'),
}));
import { VIEW_SAMPLE } from '../../test/canvas.ts';
import { parseCanvas, type Canvas } from './jsonCanvas.ts';

const canvas = parseCanvas(VIEW_SAMPLE) as Canvas;

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
    // The lines' own SVG: the minimap draws lines and names too.
    const edges = shown.querySelectorAll('[class*="edges"] g');
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
    expect(missing.textContent).toContain('Not in Ghost.md yet');
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
    unmount();
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
    act(() => vi.advanceTimersByTime(HOLD_MS + 30));
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
    act(() => vi.advanceTimersByTime(HOLD_MS + 80));
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
    typeInto(field, 'after');
    act(() => field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })));
    expect(onChange).toHaveBeenCalledTimes(1);
    expect((onChange.mock.calls[0]![0] as Canvas).edges.find((e) => e.id === 'e2')).toMatchObject({ label: 'after' });
    const remove = shown.querySelector('button[aria-label="Take this line off the canvas"]') as HTMLElement;
    act(() => remove.click());
    expect((onChange.mock.calls[1]![0] as Canvas).edges.find((e) => e.id === 'e2')).toBeUndefined();
  });
});

describe('sizes and groups', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());
  const pointer = (el: Element, type: string, x: number, y: number) =>
    act(() => {
      el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0 }));
    });
  const tapTwice = (el: Element, x: number, y: number) => {
    act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: x, clientY: y })));
    act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: x, clientY: y })));
  };

  it('lifts a group with the cards inside it, and leaves the one outside', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    // g is -20,-20 400x200, so its right edge is 380: t (0,0 200x80) and l (0,100 200x80) are wholly inside; f and n
    // (300 across, 200 wide) reach 500 and are not, so they stay.
    const group = shown.querySelector('[data-card="g"]') as HTMLElement;
    pointer(group, 'pointerdown', 10, 10);
    act(() => vi.advanceTimersByTime(HOLD_MS + 30));
    pointer(group, 'pointermove', 60, 40);
    pointer(group, 'pointerup', 60, 40);
    const next = onChange.mock.calls[0]![0] as Canvas;
    expect(next.nodes.map((n) => [n.id, n.x, n.y])).toEqual([['g', 30, 10], ['t', 50, 30], ['f', 300, 0], ['n', 300, 100], ['l', 50, 130]]);
  });

  it('opens a group on a double-tap to be named, and the cross takes only the group off', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const group = shown.querySelector('[data-card="g"]') as HTMLElement;
    tapTwice(group, 10, 10);
    const field = group.querySelector('input[aria-label="The group\u2019s name"], input[aria-label="The group\'s name"]') as HTMLInputElement;
    expect(field).not.toBeNull();
    act(() => {
      field.value = 'Trip';
      field.dispatchEvent(new FocusEvent('focusout', { bubbles: true }));
    });
    expect((onChange.mock.calls[0]![0] as Canvas).nodes[0]).toMatchObject({ id: 'g', label: 'Trip' });
    act(() => (group.querySelector('button[aria-label^="Take this group off"]') as HTMLElement).click());
    const after = onChange.mock.calls[1]![0] as Canvas;
    expect(after.nodes.find((n) => n.id === 'g')).toBeUndefined();
    expect(after.nodes.length).toBe(canvas.nodes.length - 1);
  });

  it('resizes an open card from its corner, in the canvas\u2019s pixels, no smaller than the least', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const card = shown.querySelector('[data-card="t"]') as HTMLElement;
    tapTwice(card, 50, 40);
    const corner = card.querySelector('[aria-label="Drag to resize this card"]') as HTMLElement;
    expect(corner).not.toBeNull();
    pointer(corner, 'pointerdown', 200, 80);
    pointer(window as unknown as Element, 'pointermove', 260.4, 120.6);
    pointer(window as unknown as Element, 'pointerup', 260.4, 120.6);
    expect((onChange.mock.calls.at(-1)![0] as Canvas).nodes.find((n) => n.id === 't')).toMatchObject({ width: 260, height: 121 });
    pointer(corner, 'pointerdown', 200, 80);
    pointer(window as unknown as Element, 'pointerup', 0, 0);
    expect((onChange.mock.calls.at(-1)![0] as Canvas).nodes.find((n) => n.id === 't')).toMatchObject({ width: 120, height: 60 });
  });
});

describe('more ways to add', () => {
  const tap = (el: Element) => act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })));

  it('adds a note card from the + sheet by its title, and a link card by its address', () => {
    const onChange = vi.fn();
    const titles = () => ['Launch week', 'Cabin trip'];
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} wiki={{ known: () => true, open: vi.fn(), titles }} />);
    tap(shown.querySelector('button[aria-label="Add a card"]')!);
    const note = [...document.querySelectorAll('[role="dialog"] button')].find((b) => b.textContent?.startsWith('A note'))!;
    tap(note);
    typeInto(document.querySelector('[role="dialog"] input') as HTMLInputElement, 'cab');
    const rows = [...document.querySelectorAll('[role="dialog"] ul button')].map((b) => b.textContent);
    expect(rows).toEqual(['Cabin trip']);
    tap(document.querySelector('[role="dialog"] ul button')!);
    expect((onChange.mock.calls[0]![0] as Canvas).nodes.at(-1)).toMatchObject({ type: 'file', file: 'Cabin trip.md' });
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    tap(shown.querySelector('button[aria-label="Add a card"]')!);
    tap([...document.querySelectorAll('[role="dialog"] button')].find((b) => b.textContent?.startsWith('A link'))!);
    const url = document.querySelector('[role="dialog"] input') as HTMLInputElement;
    typeInto(url, 'attack.fm');
    act(() => url.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })));
    expect((onChange.mock.calls[1]![0] as Canvas).nodes.at(-1)).toMatchObject({ type: 'link', url: 'https://attack.fm' });
  });

  it('takes a note dropped in from the sidebar as a card where it lands', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const host = shown.firstElementChild as HTMLElement;
    const data = new Map<string, string>([['application/x-glyph-note', 'n1'], ['text/plain', 'Launch week']]);
    const drop = new Event('drop', { bubbles: true, cancelable: true }) as Event & { dataTransfer: unknown; clientX: number; clientY: number };
    Object.assign(drop, { dataTransfer: { getData: (kind: string) => data.get(kind) ?? '' }, clientX: 90, clientY: 70 });
    act(() => {
      host.dispatchEvent(drop);
    });
    expect((onChange.mock.calls[0]![0] as Canvas).nodes.at(-1)).toMatchObject({ type: 'file', file: 'Launch week.md' });
  });

  it('closes the + sheet on a back gesture and on a tap beside it, adding nothing', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    tap(shown.querySelector('button[aria-label="Add a card"]')!);
    expect(document.querySelector('[role="dialog"]')).not.toBeNull();
    act(() => {
      expect(goBack()).toBe(true);
    });
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    // Nothing else is waiting for the gesture once the sheet is gone.
    expect(goBack()).toBe(false);
    tap(shown.querySelector('button[aria-label="Add a card"]')!);
    tap(document.querySelector('[role="dialog"]')!.parentElement!);
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(onChange).not.toHaveBeenCalled();
  });

  it('marks a card that is only a table, so the table fills it', () => {
    const tabled = parseCanvas(`{ "nodes": [
      { "id": "t", "type": "text", "x": 0, "y": 0, "width": 200, "height": 100, "text": "| a | b |\\n| - | - |\\n| 1 | 2 |" },
      { "id": "w", "type": "text", "x": 300, "y": 0, "width": 200, "height": 100, "text": "# Words\\n\\n| a |\\n| - |" }
    ] }`) as Canvas;
    const shown = show(<CanvasView canvas={tabled} dark={false} />);
    expect(shown.querySelector('[data-card="t"]')?.getAttribute('data-only')).toBe('table');
    expect(shown.querySelector('[data-card="w"]')?.hasAttribute('data-only')).toBe(false);
  });
});

describe('pictures, charts and the toolbar', () => {
  const tap = (el: Element) => act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })));

  it('shows icon tools at the bottom left, named for a reader', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={vi.fn()} />);
    const tools = shown.querySelector('[role="toolbar"]') as HTMLElement;
    const labels = [...tools.querySelectorAll('button')].map((b) => b.getAttribute('aria-label'));
    expect(labels).toEqual(['Add a card', 'Draw a line: tap one card, then another', 'Fit the whole canvas on the screen (Shift+1)']);
    for (const b of tools.querySelectorAll('button')) expect(b.querySelector('svg')).not.toBeNull();
  });

  it('draws a picture of Ghost.md’s own on its card, and one from elsewhere as waiting', () => {
    const withPictures = parseCanvas(`{ "nodes": [
      { "id": "mine", "type": "file", "x": 0, "y": 0, "width": 200, "height": 150, "file": "abc.jpg" },
      { "id": "theirs", "type": "file", "x": 300, "y": 0, "width": 200, "height": 150, "file": "Pictures/abc.jpg" }
    ] }`) as Canvas;
    const shown = show(<CanvasView canvas={withPictures} dark={false} />);
    expect((shown.querySelector('[data-card="mine"] img') as HTMLImageElement).getAttribute('src')).toBe('blob:abc.jpg');
    expect(shown.querySelector('[data-card="theirs"] img')).toBeNull();
    expect(shown.querySelector('[data-card="theirs"]')?.textContent).toContain('vault');
  });

  it('opens one of Ghost.md’s own pictures on a double-tap, to resize or take off, and leaves one from elsewhere shut', () => {
    const withPictures = parseCanvas(`{ "nodes": [
      { "id": "mine", "type": "file", "x": 0, "y": 0, "width": 200, "height": 150, "file": "abc.jpg" },
      { "id": "theirs", "type": "file", "x": 300, "y": 0, "width": 200, "height": 150, "file": "Pictures/abc.jpg" }
    ] }`) as Canvas;
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={withPictures} dark={false} onChange={onChange} />);
    const twice = (el: Element) => {
      act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: 20, clientY: 20 })));
      act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: 20, clientY: 20 })));
    };
    const theirs = shown.querySelector('[data-card="theirs"]') as HTMLElement;
    twice(theirs);
    expect(theirs.hasAttribute('data-editing')).toBe(false);
    const mine = shown.querySelector('[data-card="mine"]') as HTMLElement;
    twice(mine);
    expect(mine.hasAttribute('data-editing')).toBe(true);
    expect(mine.querySelector('[aria-label="Drag to resize this card"]')).not.toBeNull();
    act(() => (mine.querySelector('button[aria-label="Take this picture off the canvas"]') as HTMLElement).click());
    expect((onChange.mock.calls[0]![0] as Canvas).nodes.map((n) => n.id)).toEqual(['theirs']);
  });

  it('adds a picture from the + sheet, and a chart that starts as a diagram', async () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    tap(shown.querySelector('button[aria-label="Add a card"]')!);
    tap([...document.querySelectorAll('[role="dialog"] button')].find((b) => b.textContent?.startsWith('A picture'))!);
    // The picture is chosen and kept before its card is made: waited for, not counted in turns of the queue.
    await waitUntil(() => expect(onChange).toHaveBeenCalled());
    expect((onChange.mock.calls[0]![0] as Canvas).nodes.at(-1)).toMatchObject({ type: 'file', file: 'picked.jpg' });
    tap(shown.querySelector('button[aria-label="Add a card"]')!);
    tap([...document.querySelectorAll('[role="dialog"] button')].find((b) => b.textContent?.startsWith('A chart'))!);
    const chart = (onChange.mock.calls[1]![0] as Canvas).nodes.at(-1)!;
    expect(chart).toMatchObject({ type: 'text' });
    expect((chart as { text: string }).text.startsWith('```mermaid')).toBe(true);
    expect(shown.querySelector(`[data-card="${chart.id}"][data-editing]`)).not.toBeNull();
  });

  it('keeps a picture file dropped on the canvas and makes a card of it where it lands', async () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const drop = new Event('drop', { bubbles: true, cancelable: true }) as Event & { dataTransfer: unknown; clientX: number; clientY: number };
    Object.assign(drop, { dataTransfer: { files: [new File(['x'], 'cat.png', { type: 'image/png' })], getData: () => '' }, clientX: 40, clientY: 40 });
    await act(async () => {
      shown.firstElementChild!.dispatchEvent(drop);
    });
    // The picture is kept and then the card is made, each a turn of the queue: waited for, not counted.
    await waitUntil(() => expect(onChange).toHaveBeenCalled());
    expect((onChange.mock.calls[0]![0] as Canvas).nodes.at(-1)).toMatchObject({ type: 'file', file: 'dropped.jpg' });
  });
});
