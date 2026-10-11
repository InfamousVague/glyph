import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { stubMatchMedia } from '../../test/stubs.ts';
import { wisp, wispArrivals } from './wispArrivals.ts';
import { follow, rippledRanges, shape, wispRipples, type RippleSource } from './wispRipples.ts';

describe('ripples through the arriving words', () => {
  it('ripples only the words still arriving, one stretch a phrase, and none of the text already set', () => {
    const settled = EditorState.create({ doc: 'Already said.\n', extensions: [wispArrivals()] });
    expect(rippledRanges(settled)).toEqual([]);
    const heard = settled.update({ changes: { from: settled.doc.length, insert: 'oat milk' }, annotations: wisp.of({ kind: 'heard' }) }).state;
    const stretches = rippledRanges(heard);
    expect(stretches.map((r) => heard.doc.sliceString(r.from, r.to))).toEqual(['oat milk']);
    expect(stretches[0]!.from).toBe('Already said.\n'.length);
  });

  it('keeps a phrase on each line its own stretch, and takes no part in text leaving', () => {
    const start = EditorState.create({ doc: 'one two', extensions: [wispArrivals()] });
    const heard = start.update({ changes: { from: 7, insert: '\nthree' }, annotations: wisp.of({ kind: 'heard' }) }).state;
    expect(rippledRanges(heard).map((r) => heard.doc.sliceString(r.from, r.to))).toEqual(['three']);
    const rewrite = heard.update({ changes: { from: 0, to: 3, insert: '' }, annotations: wisp.of({ kind: 'rewrite' }) }).state;
    expect(rippledRanges(rewrite).every((r) => r.to > r.from)).toBe(true);
  });

  it('follows a voice up quickly and down slowly, and settles to nothing', () => {
    const up = follow(0, 0.6);
    expect(up).toBeGreaterThan(0.2);
    const down = follow(up, 0);
    expect(down).toBeLessThan(up);
    expect(up - down).toBeLessThan(up * 0.2);
    let level = up;
    for (let i = 0; i < 200; i += 1) level = follow(level, 0);
    expect(level).toBe(0);
  });

  it('bends nothing in silence and a full wave by ordinary talking', () => {
    expect(shape(0)).toEqual({ scale: 0, blur: 0 });
    expect(shape(0.15).scale).toBeGreaterThan(0);
    expect(shape(0.15).scale).toBeLessThan(shape(0.3).scale);
    expect(shape(0.3)).toEqual(shape(1));
    expect(shape(1).scale).toBe(30);
  });
});

describe('the ripples drawn in the recorder’s page', () => {
  let view: EditorView | null = null;
  /** The voice's level as the recorder would hand it over, and whether anything is still listening. */
  let say: ((level: number) => void) | null = null;
  const voice: RippleSource = {
    subscribe(listener) {
      say = listener;
      return () => {
        say = null;
      };
    },
  };

  afterEach(() => {
    view?.destroy();
    view = null;
    say = null;
    vi.useRealTimers();
    vi.restoreAllMocks();
    delete (window as Partial<Window>).matchMedia;
  });

  function open(): EditorView {
    vi.useFakeTimers();
    view = new EditorView({ doc: 'Already said. ', extensions: [wispArrivals(), wispRipples(voice)], parent: document.body });
    view.dispatch({ changes: { from: view.state.doc.length, insert: 'buy oat milk' }, annotations: wisp.of({ kind: 'heard' }) });
    return view;
  }
  const bend = (on: EditorView) => Number(on.dom.querySelector('filter[id^="wispripple-"] feDisplacementMap')?.getAttribute('scale'));

  it('wears its filters on the words still arriving, and none on the text already set', () => {
    const on = open();
    const rippled = [...on.dom.querySelectorAll('.cm-wispRipple')].map((mark) => mark.textContent).join('');
    expect(rippled).toContain('oat');
    expect(rippled).not.toContain('Already');
  });

  it('bends them with the voice, and stops drawing altogether once the voice and the words have settled', () => {
    const on = open();
    say?.(0.3);
    vi.advanceTimersByTime(200);
    expect(bend(on)).toBeGreaterThan(0);
    say?.(0);
    vi.advanceTimersByTime(10_000);
    expect(on.dom.querySelector('.cm-wispRipple')).toBeNull();
    // Silence costs nothing: no frame is asked for while nothing moves.
    const frames = vi.spyOn(window, 'requestAnimationFrame');
    vi.advanceTimersByTime(1_000);
    expect(frames).not.toHaveBeenCalled();
  });

  it('stops hearing the voice and takes its filters away with the editor', () => {
    const on = open();
    const svg = on.dom.querySelector('filter[id^="wispripple-"]')?.closest('svg');
    expect(say).not.toBeNull();
    on.destroy();
    view = null;
    expect(say).toBeNull();
    expect(svg?.isConnected).toBe(false);
  });

  it('draws no ripples at all where less motion is asked for', () => {
    stubMatchMedia(true);
    expect(wispRipples(voice)).toEqual([]);
  });
});
