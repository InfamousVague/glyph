// @vitest-environment jsdom
import { EditorState } from '@codemirror/state';
import { Decoration, EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { DEFAULT_PREFERENCES, setPreferences } from '../core/preferences.ts';
import { commonEnds, wisp, wispArrivals } from './wispArrivals.ts';
import { moving, revealWisp } from './wispMotion.ts';

function state(doc = '') {
  return EditorState.create({ doc, extensions: [wispArrivals()] });
}

function heard(from: EditorState, changes: { from: number; to?: number; insert: string }, kind: 'heard' | 'rewrite' = 'heard') {
  return from.update({ changes, annotations: wisp.of({ kind }) }).state;
}

describe('text arriving from smoke in the editor', () => {
  afterEach(() => setPreferences({ motionSpeed: DEFAULT_PREFERENCES.motionSpeed }));

  it('moves at the chosen speed: a relaxed arc is longer and a brisk one shorter, and so is the wait between words', () => {
    const measure = () => {
      const letters = moving(heard(state(), { from: 0, insert: 'buy milk' }));
      return { dur: Math.min(...letters.map((m) => m.dur)), gap: letters[1]!.at - letters[0]!.at };
    };
    setPreferences({ motionSpeed: 'normal' });
    const normal = measure();
    setPreferences({ motionSpeed: 'relaxed' });
    const relaxed = measure();
    setPreferences({ motionSpeed: 'brisk' });
    const brisk = measure();
    // The arc carries up to 100 ms of jitter, so compare against its bounds rather than one draw.
    expect(relaxed.dur).toBeGreaterThanOrEqual(350 * 1.6);
    expect(brisk.dur).toBeLessThanOrEqual(450 * 0.6);
    expect(normal.dur).toBeGreaterThanOrEqual(350);
    expect(relaxed.gap).toBeCloseTo(normal.gap * 1.6, 5);
    expect(brisk.gap).toBeCloseTo(normal.gap * 0.6, 5);
    expect(document.documentElement.style.getPropertyValue('--glacier-duration-normal')).toBe('150ms');
  });

  it('finds what a rewrite really changed', () => {
    expect(commonEnds('buy mil', 'buy milk')).toEqual({ prefix: 7, suffix: 0 });
    expect(commonEnds('buy milk', 'buy oat milk')).toEqual({ prefix: 4, suffix: 4 });
    expect(commonEnds('same', 'same')).toEqual({ prefix: 4, suffix: 0 });
    expect(commonEnds('abc', 'xyz')).toEqual({ prefix: 0, suffix: 0 });
  });

  it('sets every word of a heard phrase moving, one after another, spaces aside', () => {
    const next = heard(state(), { from: 0, insert: 'buy milk' });
    const letters = moving(next);
    expect(letters.map((m) => next.doc.sliceString(m.from, m.to))).toEqual(['buy', 'milk']);
    expect(letters.every((m) => m.gone === '')).toBe(true);
    const at = letters.map((m) => m.at);
    expect(at).toEqual([...at].sort((a, b) => a - b));
    expect(at[1]! - at[0]!).toBeGreaterThan(0);
  });

  it('moves only the letters a rewrite changed, and shows what it took away', () => {
    const first = state('buy mil');
    const firmed = heard(first, { from: 0, to: 7, insert: 'buy milk' }, 'rewrite');
    expect(moving(firmed).map((m) => firmed.doc.sliceString(m.from, m.to))).toEqual(['k']);

    const swapped = heard(state('buy milk'), { from: 0, to: 8, insert: 'buy oat milk' }, 'rewrite');
    expect(moving(swapped).map((m) => swapped.doc.sliceString(m.from, m.to)).join('')).toBe('oat');

    const cut = heard(state('buy milk'), { from: 0, to: 8, insert: 'by milk' }, 'rewrite');
    const ghosts = moving(cut).filter((m) => m.gone);
    expect(ghosts.map((m) => m.gone)).toEqual(['u']);
    expect(ghosts[0]?.from).toBe(1);
  });

  it('with typing on, sets typed letters moving, ghosts a backspace, and caps a paste', () => {
    const typed = EditorState.create({ doc: '', extensions: [wispArrivals({ typing: true })] });
    const one = typed.update({ changes: { from: 0, insert: 'h' }, userEvent: 'input.type' }).state;
    expect(moving(one).map((m) => one.doc.sliceString(m.from, m.to))).toEqual(['h']);
    // A letter backspaced by hand goes at once: no smoke to stutter under the fingers.
    const gone = one.update({ changes: { from: 0, to: 1, insert: '' }, userEvent: 'delete.backward' }).state;
    expect(moving(gone).filter((m) => m.gone)).toEqual([]);
    // A word taken out at once still smokes.
    const word = EditorState.create({ doc: 'buy milk', extensions: [wispArrivals({ typing: true })] })
      .update({ changes: { from: 4, to: 8, insert: '' }, userEvent: 'delete.selection' })
      .state;
    expect(moving(word).map((m) => m.gone)).toEqual(['milk']);
    const pasted = typed.update({ changes: { from: 0, insert: 'x'.repeat(100) }, userEvent: 'input.paste' }).state;
    expect(moving(pasted).reduce((sum, m) => sum + (m.to - m.from), 0)).toBe(40);
    const programmatic = typed.update({ changes: { from: 0, insert: 'set' } }).state;
    expect(moving(programmatic)).toEqual([]);
    // A tapped box smokes its letter away where it stood; a board's own edits (a card moved, a divider dragged) do not.
    const box = EditorState.create({ doc: '- [x] milk', extensions: [wispArrivals({ typing: true })] });
    const tapped = moving(box.update({ changes: { from: 3, to: 4, insert: ' ' }, userEvent: 'input.toggle' }).state);
    expect(tapped.map((m) => [m.gone, m.from])).toEqual([['x', 3]]);
    // The one letter between two brackets that stay put dissolves where it stands: no throw across the box, no rise into it.
    expect(tapped[0]?.box).toBe(true);
    const byHand = moving(box.update({ changes: { from: 3, to: 4, insert: 'y' }, userEvent: 'input.type' }).state);
    expect(byHand.every((m) => !m.box)).toBe(true);
    expect(moving(box.update({ changes: { from: 3, to: 4, insert: ' ' }, userEvent: 'input.board' }).state)).toEqual([]);
    expect(moving(box.update({ changes: { from: 3, to: 4, insert: ' ' }, userEvent: 'input.board' }).state)).toEqual([]);
  });

  it('reveals a note already there a few words at a time, in order, blank lines aside', () => {
    const opened = EditorState.create({ doc: '# Title\n\n  - a list item  \na paragraph long enough to break into more than one piece', extensions: [wispArrivals({ typing: true })] });
    const revealed = opened.update({ effects: revealWisp.of({ from: 0, to: opened.doc.length }) }).state;
    const pieces = moving(revealed).map((m) => revealed.doc.sliceString(m.from, m.to));
    expect(pieces.slice(0, 2)).toEqual(['# Title', '- a list item']);
    expect(pieces.length).toBeGreaterThan(3);
    expect(pieces.every((p) => p.length <= 24 || !p.includes(' '))).toBe(true);
    const at = moving(revealed).map((m) => m.at);
    expect(at).toEqual([...at].sort((a, b) => a - b));
  });

  it('ignores changes without the annotation, and follows later edits', () => {
    const plain = state().update({ changes: { from: 0, insert: 'typed' } }).state;
    expect(moving(plain)).toEqual([]);
    const withHeard = heard(state(), { from: 0, insert: 'milk' });
    const shifted = withHeard.update({ changes: { from: 0, insert: 'oat ' } }).state;
    expect(moving(shifted).map((m) => shifted.doc.sliceString(m.from, m.to)).join('')).toBe('milk');
    expect(moving(shifted)[0]?.from).toBe(4);
    const deleted = shifted.update({ changes: { from: 4, to: 8, insert: '' } }).state;
    expect(moving(deleted)).toEqual([]);
  });
});

describe('words drawn arriving', () => {
  let view: EditorView | null = null;

  afterEach(() => {
    view?.destroy();
    view = null;
    vi.useRealTimers();
  });

  /** A paragraph of `count` words, heard at once: more than the pool of filters can draw together. */
  function hearAtOnce(count: number): EditorView {
    vi.useFakeTimers();
    view = new EditorView({ doc: '', extensions: [wispArrivals()], parent: document.body });
    const words = Array.from({ length: count }, (_, n) => `w${n}`).join(' ');
    view.dispatch({ changes: { from: 0, insert: words }, annotations: wisp.of({ kind: 'heard' }) });
    return view;
  }

  it('draws each moving word through a filter of its own, and no more at once than the pool holds', () => {
    const on = hearAtOnce(90);
    vi.advanceTimersByTime(1400);
    const drawing = on.dom.querySelectorAll('.cm-wispCh');
    expect(drawing.length).toBeGreaterThan(0);
    expect(drawing.length).toBeLessThanOrEqual(32);
    expect(on.dom.querySelectorAll('svg defs filter').length).toBeLessThanOrEqual(32);
    // A word whose filter is still another's waits its turn, there but unseen.
    expect(on.dom.querySelectorAll('.cm-wispWait').length).toBeGreaterThan(0);
  });

  it('settles every word of a paragraph heard at once, past as many as the pool holds', () => {
    // A word waiting on a filter once asked to be looked at again next frame; the frame loop then redrew and
    // returned every frame before it settled anything, and past 32 letters in motion none ever finished.
    const on = hearAtOnce(90);
    vi.advanceTimersByTime(10_000);
    expect(moving(on.state)).toEqual([]);
    expect(on.dom.querySelector('.cm-wispCh, .cm-wispWait')).toBeNull();
  });

  it('takes its filters away with the editor', () => {
    const on = hearAtOnce(3);
    const svg = on.dom.querySelector('svg[aria-hidden="true"]');
    expect(svg?.querySelector('defs filter feDisplacementMap')).not.toBeNull();
    on.destroy();
    view = null;
    expect(svg?.isConnected).toBe(false);
  });
});

describe('the smoke of text that went', () => {
  it('is drawn in the look the text had, where it stood', () => {
    // The box of a to-do is set in the monospace face and the accent colour (Editor.module.css `.taskMarker`); its
    // smoke, drawn as a widget of the line, took the note's prose face until it was given the same classes.
    const box = EditorView.decorations.of(Decoration.set([Decoration.mark({ class: 'probe-box' }).range(2, 5)]));
    const view = new EditorView({ doc: '- [x] milk', extensions: [box, wispArrivals({ typing: true })] });
    document.body.appendChild(view.dom);
    try {
      view.dispatch({ changes: { from: 3, to: 4, insert: ' ' }, userEvent: 'input.type' });
      const ghost = view.dom.querySelector('.cm-wispGone');
      expect(ghost?.textContent).toBe('x');
      expect(ghost?.className).toContain('probe-box');
    } finally {
      view.destroy();
    }
  });
});
