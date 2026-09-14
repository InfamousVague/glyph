import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { activeBlock, activeMarks, toggleBlock, toggleMark } from './format.ts';

/**
 * What the formatting bar writes, checked against what the highlighter reads.
 *
 * The bar is the one place in the app that puts markdown syntax into the
 * document on the user's behalf, so a drift between its delimiters and the
 * grammar's would produce text that looks like a mark and renders as plain -
 * invisible in review, obvious and baffling on a phone.
 */

/** A detached view, which is all `toggleMark`/`toggleBlock` need. */
function viewOf(doc: string, anchor: number, head = anchor): EditorView {
  return new EditorView({ state: EditorState.create({ doc, selection: { anchor, head } }) });
}

const text = (view: EditorView) => view.state.doc.toString();

describe('toggleMark', () => {
  it('wraps a selection and keeps it selected', () => {
    const view = viewOf('make this bold', 10, 14);
    toggleMark(view, 'bold');
    expect(text(view)).toBe('make this **bold**');
    expect(view.state.sliceDoc(view.state.selection.main.from, view.state.selection.main.to)).toBe('bold');
  });

  it('puts the caret BETWEEN the delimiters when nothing is selected', () => {
    // Otherwise pressing Bold and typing produces text after the markers, and
    // the person has to notice and move the caret back.
    const view = viewOf('', 0);
    toggleMark(view, 'bold');
    expect(text(view)).toBe('****');
    expect(view.state.selection.main.head).toBe(2);
  });

  it('unwraps when the delimiters sit just outside the selection', () => {
    const view = viewOf('**bold**', 2, 6);
    toggleMark(view, 'bold');
    expect(text(view)).toBe('bold');
  });

  it('unwraps when the delimiters are inside the selection', () => {
    const view = viewOf('**bold**', 0, 8);
    toggleMark(view, 'bold');
    expect(text(view)).toBe('bold');
  });

  it('uses the kit delimiters, so what the bar writes is what the grammar reads', () => {
    const cases: Array<[Parameters<typeof toggleMark>[1], string]> = [
      ['bold', '**x**'],
      ['italic', '_x_'],
      ['code', '`x`'],
      ['strike', '~~x~~'],
    ];
    for (const [mark, expected] of cases) {
      const view = viewOf('x', 0, 1);
      toggleMark(view, mark);
      expect(text(view)).toBe(expected);
    }
  });
});

describe('toggleBlock', () => {
  it('prefixes the caret line', () => {
    const view = viewOf('a line', 3);
    toggleBlock(view, 'quote');
    expect(text(view)).toBe('> a line');
  });

  it('removes the prefix when every touched line has one', () => {
    const view = viewOf('- one\n- two', 0, 11);
    toggleBlock(view, 'bullet');
    expect(text(view)).toBe('one\ntwo');
  });

  it('completes a half-formatted run rather than clearing it', () => {
    const view = viewOf('- one\ntwo', 0, 9);
    toggleBlock(view, 'bullet');
    expect(text(view)).toBe('- one\n- two');
  });

  it('numbers an ordered list rather than repeating 1.', () => {
    const view = viewOf('one\ntwo\nthree', 0, 13);
    toggleBlock(view, 'number');
    expect(text(view)).toBe('1. one\n2. two\n3. three');
  });

  it('recognises a heading of any level as already-a-heading', () => {
    const view = viewOf('### deep', 4);
    expect(activeBlock(view.state)).toBe('heading');
    toggleBlock(view, 'heading');
    expect(text(view)).toBe('deep');
  });
});

describe('activeMarks', () => {
  it('reports the mark surrounding the caret', () => {
    const view = viewOf('**bold**', 2, 6);
    expect(activeMarks(view.state)).toContain('bold');
  });

  it('reports nothing in plain text', () => {
    expect(activeMarks(viewOf('plain', 2).state)).toEqual([]);
  });
});
