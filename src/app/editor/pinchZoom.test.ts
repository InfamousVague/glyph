import { EditorView } from '@codemirror/view';
import { createElement, useRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { show } from '../../test/render.tsx';
import { clampZoom, pinched, readZoom, useNoteZoom, ZOOM_MAX, ZOOM_MIN } from './pinchZoom.ts';

describe('pinching a note’s text', () => {
  beforeEach(() => localStorage.clear());

  it('follows the fingers: twice as far apart, twice the size', () => {
    expect(pinched(1, 100, 200)).toBe(2);
    expect(pinched(1.2, 100, 50)).toBeCloseTo(0.7);
    expect(pinched(1.5, 100, 100)).toBe(1.5);
  });

  it('stays between the smallest and largest size', () => {
    expect(pinched(1, 100, 1000)).toBe(ZOOM_MAX);
    expect(pinched(1, 100, 10)).toBe(ZOOM_MIN);
    expect(clampZoom(Number.NaN)).toBe(1);
    expect(pinched(1.3, 0, 50)).toBe(1.3);
  });

  it('opens at the size last pinched, and at the usual size when none was', () => {
    expect(readZoom()).toBe(1);
    localStorage.setItem('glyph-note-zoom', '1.450');
    expect(readZoom()).toBe(1.45);
    localStorage.setItem('glyph-note-zoom', '9');
    expect(readZoom()).toBe(ZOOM_MAX);
    localStorage.setItem('glyph-note-zoom', 'huge');
    expect(readZoom()).toBe(1);
  });
});

describe('the pinch on a note’s page', () => {
  let view: EditorView | null = null;

  beforeEach(() => {
    localStorage.clear();
    vi.useFakeTimers();
    view = new EditorView({ doc: 'The cabin trip\n\nPack light.', parent: document.body });
  });

  afterEach(() => {
    view?.destroy();
    view = null;
    vi.useRealTimers();
  });

  /** A page for the note, the hook on it, and the page itself. */
  function page(active = true): HTMLElement {
    function Page() {
      const scroller = useRef<HTMLDivElement>(null);
      useNoteZoom(scroller, view, active);
      return createElement('div', { ref: scroller, 'data-page': '' });
    }
    return show(createElement(Page)).querySelector<HTMLElement>('[data-page]')!;
  }

  /** Fingers on the page, `apart` pixels from each other across its middle; none for a lift. */
  function fingers(on: HTMLElement, type: string, apart: number | null, count = 2): Event {
    const event = new Event(type, { bubbles: true, cancelable: true });
    const touches = apart === null ? [] : [{ clientX: 100, clientY: 100 }, { clientX: 100 + apart, clientY: 100 }].slice(0, count);
    Object.defineProperty(event, 'touches', { value: touches });
    on.dispatchEvent(event);
    return event;
  }
  const zoom = (on: HTMLElement) => on.style.getPropertyValue('--note-zoom');

  it('opens at the size last pinched', () => {
    localStorage.setItem('glyph-note-zoom', '1.450');
    expect(zoom(page())).toBe('1.45');
  });

  it('follows two fingers apart, a frame at a time, and keeps the size once they lift', () => {
    const on = page();
    expect(zoom(on)).toBe('1');
    fingers(on, 'touchstart', 100);
    const move = fingers(on, 'touchmove', 150);
    // Two fingers are a pinch, not a scroll.
    expect(move.defaultPrevented).toBe(true);
    vi.advanceTimersToNextFrame();
    expect(zoom(on)).toBe('1.5');
    fingers(on, 'touchend', null);
    expect(localStorage.getItem('glyph-note-zoom')).toBe('1.500');
  });

  it('forgets the size pinched back to the usual one', () => {
    localStorage.setItem('glyph-note-zoom', '1.500');
    const on = page();
    fingers(on, 'touchstart', 150);
    fingers(on, 'touchmove', 100);
    fingers(on, 'touchend', null);
    expect(zoom(on)).toBe('1');
    expect(localStorage.getItem('glyph-note-zoom')).toBeNull();
  });

  it('leaves one finger to scroll, and a page that is not the note’s own to itself', () => {
    const on = page();
    fingers(on, 'touchstart', 100, 1);
    const scroll = fingers(on, 'touchmove', 200, 1);
    expect(scroll.defaultPrevented).toBe(false);
    vi.advanceTimersToNextFrame();
    expect(zoom(on)).toBe('1');

    localStorage.setItem('glyph-note-zoom', '1.200');
    const still = page(false);
    expect(zoom(still)).toBe('1.2');
    fingers(still, 'touchstart', 100);
    fingers(still, 'touchmove', 200);
    vi.advanceTimersToNextFrame();
    expect(zoom(still)).toBe('1.2');
  });
});
