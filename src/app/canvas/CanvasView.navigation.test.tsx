import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, typeInto, unmount } from '../../test/render.tsx';
import { CanvasView } from './CanvasView.tsx';
import { VIEW_SAMPLE } from '../../test/canvas.ts';
import { parseCanvas, type Canvas } from './jsonCanvas.ts';

/**
 * Finding your way round a canvas: two fingers that pan and pinch, a wheel that pans and a modified wheel that
 * zooms, the keys that fit the canvas and go to a card, the fit that follows the screen's size until a hand has moved
 * the view, the minimap, and the editors that wait until their card is near the screen. What is measured is the
 * world's transform, which is where the view is written (CanvasView.tsx); jsdom lays nothing out, so a screen size
 * is given where one matters.
 */

const canvas = parseCanvas(VIEW_SAMPLE) as Canvas;

/** The view as the world wears it: its offset on the screen and its scale. */
function viewOf(root: HTMLElement): { x: number; y: number; scale: number } {
  const world = root.querySelector('[class*="world"]') as HTMLElement;
  const m = /translate\(([-\d.e]+)px, ([-\d.e]+)px\) scale\(([-\d.e]+)\)/.exec(world.style.transform);
  if (!m) throw new Error(`no view in "${world.style.transform}"`);
  return { x: Number(m[1]), y: Number(m[2]), scale: Number(m[3]) };
}

/** The canvas's own element, the page every gesture lands on. */
const pageOf = (root: HTMLElement) => root.firstElementChild as HTMLElement;

/** Gives the canvas a screen of this size: jsdom lays nothing out, so it has none of its own. */
function sized(el: HTMLElement, width: number, height: number): void {
  Object.defineProperty(el, 'clientWidth', { value: width, configurable: true });
  Object.defineProperty(el, 'clientHeight', { value: height, configurable: true });
}

/** A pointer event with its own pointer id, as a second finger needs. */
function finger(el: Element, type: string, pointerId: number, clientX: number, clientY: number): void {
  act(() => {
    el.dispatchEvent(Object.assign(new MouseEvent(type, { bubbles: true, cancelable: true, clientX, clientY, button: 0, buttons: type === 'pointerup' ? 0 : 1 }), { pointerId }));
  });
}

function wheel(el: Element, init: WheelEventInit): WheelEvent {
  const event = new WheelEvent('wheel', { bubbles: true, cancelable: true, ...init });
  act(() => {
    el.dispatchEvent(event);
  });
  return event;
}

const key = (init: KeyboardEventInit) =>
  act(() => {
    window.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init }));
  });

afterEach(() => {
  unmount();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('two fingers and a wheel', () => {
  it('opens at the fitted view: with no screen to fit, room around the canvas and life size', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    expect(viewOf(shown)).toEqual({ x: 32, y: 32, scale: 1 });
  });

  it('pinches about the point between two fingers, keeping what was under them under them', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const page = pageOf(shown);
    // 100px apart, then 200px: twice the size. The point between them was (150, 100) on the screen, which with the
    // view at (32, 32) is (118, 68) of the canvas; the fingers' middle moves to (200, 100), and that point goes with it.
    finger(page, 'pointerdown', 1, 100, 100);
    finger(page, 'pointerdown', 2, 200, 100);
    finger(page, 'pointermove', 2, 300, 100);
    const view = viewOf(shown);
    expect(view.scale).toBe(2);
    expect(view.x + 118 * view.scale).toBeCloseTo(200, 5);
    expect(view.y + 68 * view.scale).toBeCloseTo(100, 5);
    finger(page, 'pointerup', 2, 300, 100);
    finger(page, 'pointerup', 1, 100, 100);
  });

  it('pans with one finger once it has moved past a tap, and not before', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const page = pageOf(shown);
    finger(page, 'pointerdown', 1, 500, 500);
    // Three pixels is still a tap.
    finger(page, 'pointermove', 1, 503, 500);
    expect(viewOf(shown)).toEqual({ x: 32, y: 32, scale: 1 });
    finger(page, 'pointermove', 1, 540, 470);
    expect(viewOf(shown)).toEqual({ x: 72, y: 2, scale: 1 });
    finger(page, 'pointerup', 1, 540, 470);
  });

  it('pans with a wheel, and zooms about the pointer with the modifier a trackpad pinch arrives with', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const page = pageOf(shown);
    const panned = wheel(page, { deltaX: 10, deltaY: 20 });
    // The page must not scroll under the canvas instead.
    expect(panned.defaultPrevented).toBe(true);
    expect(viewOf(shown)).toEqual({ x: 22, y: 12, scale: 1 });
    // At (122, 62) on the screen is (100, 50) of the canvas; zoomed in, it is still there.
    wheel(page, { deltaY: -100, ctrlKey: true, clientX: 122, clientY: 62 });
    const view = viewOf(shown);
    expect(view.scale).toBeCloseTo(Math.E, 5);
    expect(view.x + 100 * view.scale).toBeCloseTo(122, 5);
    expect(view.y + 50 * view.scale).toBeCloseTo(62, 5);
    // Never past three times life size.
    wheel(page, { deltaY: -1000, metaKey: true, clientX: 122, clientY: 62 });
    expect(viewOf(shown).scale).toBe(3);
  });
});

describe('the keys, and the fit that follows the screen', () => {
  it('fits the whole canvas on Shift+1, and goes to the card last tapped on Shift+2', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const page = pageOf(shown);
    sized(page, 1000, 600);
    wheel(page, { deltaX: 300 });
    key({ key: '!', shiftKey: true });
    // The cards run from -20 to 500 across and -20 to 180 down, which a 1000 by 600 screen holds at life size.
    expect(viewOf(shown)).toEqual({ x: (1000 - 520) / 2 + 20, y: (600 - 200) / 2 + 20, scale: 1 });
    // Nothing chosen yet: Shift+2 has nowhere to go.
    key({ key: '@', shiftKey: true });
    expect(viewOf(shown)).toEqual({ x: 260, y: 220, scale: 1 });
    act(() => (shown.querySelector('[data-card="f"]') as HTMLElement).click());
    key({ key: '@', shiftKey: true });
    // f is 300,0 200x80: centred on the screen, at life size.
    expect(viewOf(shown)).toEqual({ x: (1000 - 200) / 2 - 300, y: (600 - 80) / 2, scale: 1 });
  });

  it('leaves the keys to a field being typed in', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={vi.fn()} />);
    sized(pageOf(shown), 1000, 600);
    act(() => (shown.querySelector('[data-line="e2"] path') as SVGPathElement).dispatchEvent(new MouseEvent('click', { bubbles: true })));
    const field = shown.querySelector('input[aria-label="Words on the line"]') as HTMLInputElement;
    act(() => {
      field.dispatchEvent(new KeyboardEvent('keydown', { key: '!', shiftKey: true, bubbles: true }));
    });
    expect(viewOf(shown)).toEqual({ x: 32, y: 32, scale: 1 });
  });

  it('puts down on Escape whatever was up: the card open, the line picked, the Line tool', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={vi.fn()} />);
    const card = shown.querySelector('[data-card="t"]') as HTMLElement;
    const tap = (el: Element) => act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: 50, clientY: 40 })));
    tap(card);
    tap(card);
    expect(card.hasAttribute('data-editing')).toBe(true);
    key({ key: 'Escape' });
    expect(card.hasAttribute('data-editing')).toBe(false);

    tap(shown.querySelector('[data-line="e1"] path')!);
    expect(shown.querySelector('[data-line="e1"]')?.hasAttribute('data-picked')).toBe(true);
    key({ key: 'Escape' });
    expect(shown.querySelector('[data-picked]')).toBeNull();

    act(() => (shown.querySelector('button[aria-label^="Draw a line"]') as HTMLElement).click());
    expect(pageOf(shown).hasAttribute('data-lining')).toBe(true);
    key({ key: 'Escape' });
    expect(pageOf(shown).hasAttribute('data-lining')).toBe(false);
  });

  it('fits again when the screen changes size, until a hand has moved the view', () => {
    // Only the canvas's own watcher is told: the cards' editors watch their sizes too, and are not under test.
    const watchers: { el: Element; report: () => void }[] = [];
    vi.stubGlobal(
      'ResizeObserver',
      class {
        constructor(private readonly report: () => void) {}
        observe(el: Element): void {
          watchers.push({ el, report: () => this.report() });
        }
        disconnect(): void {}
      },
    );
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const page = pageOf(shown);
    const resized = (width: number, height: number) => {
      sized(page, width, height);
      act(() => watchers.filter((w) => w.el === page).forEach((w) => w.report()));
    };
    resized(1000, 600);
    expect(viewOf(shown)).toEqual({ x: 260, y: 220, scale: 1 });
    wheel(page, { deltaY: 40 });
    expect(viewOf(shown)).toEqual({ x: 260, y: 180, scale: 1 });
    // Moved by hand: a new size leaves the view where the hand put it.
    resized(400, 300);
    expect(viewOf(shown)).toEqual({ x: 260, y: 180, scale: 1 });
    // The fit button fits, and the view follows the screen again from there.
    act(() => (shown.querySelector('button[aria-label^="Fit the whole canvas"]') as HTMLElement).click());
    resized(1000, 600);
    expect(viewOf(shown)).toEqual({ x: 260, y: 220, scale: 1 });
    // A zoom to a card is a hand moving the view too: f centred on the screen stays centred when the screen changes.
    act(() => shown.querySelector('[data-card="f"] [data-card-title]')!.dispatchEvent(new MouseEvent('click', { bubbles: true })));
    expect(viewOf(shown)).toEqual({ x: (1000 - 200) / 2 - 300, y: (600 - 80) / 2, scale: 1 });
    resized(400, 300);
    expect(viewOf(shown)).toEqual({ x: 100, y: 260, scale: 1 });
  });
});

describe('a card’s title and the minimap', () => {
  const tap = (el: Element) => act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })));

  it('zooms to a note card on a tap of its title without opening the note, and opens it from the rest', () => {
    const open = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} wiki={{ known: () => true, open }} />);
    const card = shown.querySelector('[data-card="f"]') as HTMLElement;
    sized(pageOf(shown), 400, 300);
    tap(card.querySelector('[data-card-title]')!);
    expect(open).not.toHaveBeenCalled();
    expect(viewOf(shown)).toEqual({ x: (400 - 200) / 2 - 300, y: (300 - 80) / 2, scale: 1 });
    tap(card);
    expect(open).toHaveBeenCalledWith('Launch week', '^photos');
  });

  it('draws a minimap that tells the cards apart, draws the lines, names the group, and goes where a finger lands', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const map = shown.querySelector('svg[aria-label^="A map of the canvas"]') as SVGSVGElement;
    expect(map).not.toBeNull();
    const kinds = [...map.querySelectorAll('[data-kind]')].map((g) => g.getAttribute('data-kind'));
    expect(kinds).toEqual(['text', 'note', 'note', 'link']);
    expect(map.querySelectorAll('line').length).toBe(2);
    expect(map.querySelector('text')?.textContent).toBe('Before');
    // The link's dot, the group, four cards and the screen's box.
    expect(map.querySelectorAll('circle').length).toBe(1);
    expect(map.querySelectorAll('rect').length).toBe(6);
    // A card's colour: a preset as a hue, a hex as the card's own.
    expect(map.querySelector('[data-kind="text"]')?.getAttribute('data-hue')).toBe('moss');
    expect((map.querySelector('[data-kind="link"]') as SVGGElement).style.getPropertyValue('--app-space')).toBe('#ff8800');
  });

  it('has no minimap for a canvas of one card', () => {
    const one = parseCanvas('{ "nodes": [{ "id": "a", "type": "text", "x": 0, "y": 0, "width": 100, "height": 50, "text": "Only" }] }') as Canvas;
    const shown = show(<CanvasView canvas={one} dark={false} />);
    expect(shown.querySelector('svg[aria-label^="A map of the canvas"]')).toBeNull();
  });

  it('grows the minimap on a press that moves nothing, and a press on the canvas puts it back', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const map = shown.querySelector('svg[aria-label^="A map of the canvas"]') as SVGSVGElement;
    const world = shown.querySelector('[class*="world"]') as HTMLElement;
    const at = (type: string, x: number, y: number) =>
      act(() => map.dispatchEvent(new MouseEvent(type, { bubbles: true, clientX: x, clientY: y, buttons: type === 'pointerup' ? 0 : 1 })));
    const before = world.style.transform;
    // The press that grows it only grows it.
    expect(map.hasAttribute('data-big')).toBe(false);
    at('pointerdown', 60, 40);
    expect(map.getAttribute('data-big')).toBe('true');
    at('pointerup', 60, 40);
    expect(world.style.transform).toBe(before);
    expect(map.getAttribute('data-big')).toBe('true');
    // A press on the canvas puts it back.
    act(() => pageOf(shown).dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, clientX: 300, clientY: 300, buttons: 1 })));
    expect(map.hasAttribute('data-big')).toBe(false);
  });

  it('moves the view by what a finger moved on the map, read at the map’s size on the page, and goes where a tap on the grown map lands', () => {
    // The map is drawn from the view as a frame copies it: the frames are run by hand, so the map is drawn when the test says.
    const frames: FrameRequestCallback[] = [];
    vi.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => frames.push(callback));
    const runFrames = () => act(() => frames.splice(0).forEach((frame) => frame(0)));
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const page = pageOf(shown);
    sized(page, 400, 300);
    // Twice life size about the room's corner: the screen's box, -16,-16 and 200 by 150, is inside the cards, so the
    // map frames the cards alone - their 520 by 200 in the 164 by 104 inside the map's room, 164/520 of a unit a pixel.
    wheel(page, { deltaY: -100 * Math.log(2), ctrlKey: true, clientX: 32, clientY: 32 });
    runFrames();
    const zoomed = viewOf(shown);
    expect(zoomed.scale).toBeCloseTo(2, 10);
    const unit = 164 / 520;
    const map = shown.querySelector('svg[aria-label^="A map of the canvas"]') as SVGSVGElement;
    /** The map this wide on the page, as it is small (180) and grown (270). */
    const onPage = (width: number) => {
      map.getBoundingClientRect = () => ({ left: 0, top: 0, width, height: (width * 2) / 3, right: width, bottom: (width * 2) / 3, x: 0, y: 0, toJSON: () => ({}) }) as DOMRect;
    };
    const at = (type: string, x: number, y = 40) => act(() => map.dispatchEvent(new MouseEvent(type, { bubbles: true, clientX: x, clientY: y, buttons: type === 'pointerup' ? 0 : 1 })));

    // 27px on the small map is 27 of its units, 27/unit of the canvas; the view goes the other way by that, at its scale.
    onPage(180);
    at('pointerdown', 60);
    at('pointermove', 87);
    at('pointerup', 87);
    const dragged = viewOf(shown);
    expect(dragged.x).toBeCloseTo(zoomed.x - (27 / unit) * 2, 5);
    expect(dragged.y).toBeCloseTo(zoomed.y, 5);
    // Grown half again, the same 27px is a third fewer units.
    onPage(270);
    at('pointerdown', 60);
    at('pointermove', 87);
    at('pointerup', 87);
    expect(viewOf(shown).x).toBeCloseTo(dragged.x - (27 / 1.5 / unit) * 2, 5);

    // The middle of the grown map is the middle of the cards, 240,80, and the 400 by 300 screen is centred on it.
    at('pointerdown', 135, 90);
    at('pointerup', 135, 90);
    const went = viewOf(shown);
    expect(went.x).toBeCloseTo(200 - 240 * 2, 5);
    expect(went.y).toBeCloseTo(150 - 80 * 2, 5);
    expect(went.scale).toBeCloseTo(2, 10);
  });
});

describe('cards made only when near the screen', () => {
  it('leaves a card’s editor unmade until the card comes near, then makes it', () => {
    // Each watcher and what it watches: only the cards' own are told, not what their editors watch once made.
    const watched: { el: Element; report: (entries: { isIntersecting: boolean }[]) => void; margin: string | undefined }[] = [];
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        constructor(
          private readonly report: (entries: { isIntersecting: boolean }[]) => void,
          private readonly options?: IntersectionObserverInit,
        ) {}
        observe(el: Element): void {
          watched.push({ el, report: this.report, margin: this.options?.rootMargin });
        }
        disconnect(): void {}
      },
    );
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    const card = shown.querySelector('[data-card="t"]') as HTMLElement;
    expect(card.querySelector('.cm-content')).toBeNull();
    // Measured against the canvas with room to spare, so an editor is ready before its card is on the screen.
    const near = watched.filter((w) => card.contains(w.el));
    expect(near).toHaveLength(1);
    expect(near[0]!.margin).toBe('300px');
    act(() => near[0]!.report([{ isIntersecting: false }]));
    expect(card.querySelector('.cm-content')).toBeNull();
    act(() => near[0]!.report([{ isIntersecting: true }]));
    expect(card.querySelector('.cm-content')?.textContent).toContain('The cabin');
  });
});

describe('a picked line’s words', () => {
  it('writes the words when the field is left, and writes nothing when they did not change', () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    act(() => (shown.querySelector('[data-line="e1"] path') as SVGPathElement).dispatchEvent(new MouseEvent('click', { bubbles: true })));
    const field = shown.querySelector('input[aria-label="Words on the line"]') as HTMLInputElement;
    expect(field.value).toBe('then');
    const leave = () => act(() => field.dispatchEvent(new FocusEvent('focusout', { bubbles: true })));
    leave();
    expect(onChange).not.toHaveBeenCalled();
    typeInto(field, ' then ');
    leave();
    expect(onChange).not.toHaveBeenCalled();
    typeInto(field, 'and then');
    leave();
    expect(onChange).toHaveBeenCalledTimes(1);
    expect((onChange.mock.calls[0]![0] as Canvas).edges.find((e) => e.id === 'e1')).toMatchObject({ label: 'and then' });
  });
});
