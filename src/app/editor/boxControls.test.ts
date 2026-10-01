import { EditorSelection, EditorState } from '@codemirror/state';
import { ensureSyntaxTree } from '@codemirror/language';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it } from 'vitest';
import { boxControls, drawnBoxes } from './boxControls.ts';
import { glyphMarkdown } from './language.ts';

const state = (doc: string, anchor?: number, head = anchor) => {
  const made = EditorState.create({ doc, extensions: [glyphMarkdown()], selection: anchor === undefined ? undefined : EditorSelection.single(anchor, head) });
  ensureSyntaxTree(made, made.doc.length, 5000);
  return made;
};
const all = (s: EditorState, focused = true) => boxControls(s, 0, s.doc.length, focused);

let view: EditorView | null = null;
afterEach(() => {
  view?.destroy();
  view = null;
});

describe('boxes drawn as controls', () => {
  it('finds every to-do’s box and choice, ticked or picked, over their own three characters', () => {
    const s = state('- [ ] Milk\n- [x] Eggs\n* [X] Bread\n- ( ) Tent\n- (x) Cabin\n1. ( ) a step\nPlain [ ] words');
    expect(all(s, false)).toEqual([
      { from: 2, to: 5, kind: 'task', on: false },
      { from: 13, to: 16, kind: 'task', on: true },
      { from: 24, to: 27, kind: 'task', on: true },
      { from: 36, to: 39, kind: 'choice', on: false },
      { from: 47, to: 50, kind: 'choice', on: true },
    ]);
  });

  it('leaves the characters as typed while the caret or a selection is inside them, and only then', () => {
    const doc = '- [ ] Milk';
    // Inside the brackets: shown as typed.
    expect(all(state(doc, 3))).toEqual([]);
    expect(all(state(doc, 0, 4))).toEqual([]);
    // Before the box and at the words: still the control.
    expect(all(state(doc, 2))).toHaveLength(1);
    expect(all(state(doc, 5))).toHaveLength(1);
    expect(all(state(doc, 6))).toHaveLength(1);
    // A note without the caret draws every box.
    expect(all(state(doc, 3), false)).toHaveLength(1);
  });

  it('draws nothing in code, where a box is characters', () => {
    expect(all(state('```\n- [ ] not a to-do\n- ( ) nor a choice\n```\n- [ ] a to-do', 0), false)).toEqual([{ from: 47, to: 50, kind: 'task', on: false }]);
  });

  it('keeps the characters in the line, so it is as long as it was, and marks each box with its kind and state', () => {
    view = new EditorView({ state: EditorState.create({ doc: '- [x] Eggs\n- ( ) Tent', extensions: [glyphMarkdown(), drawnBoxes()] }), parent: document.body });
    const drawn = [...view.contentDOM.querySelectorAll<HTMLElement>('.cm-boxControl')];
    expect(drawn.map((box) => [box.textContent, box.dataset.box, box.hasAttribute('data-on')])).toEqual([
      ['[x]', 'task', true],
      ['( )', 'choice', false],
    ]);
    expect(view.contentDOM.textContent).toBe('- [x] Eggs- ( ) Tent');
  });
});
