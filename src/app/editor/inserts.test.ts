import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState, type Extension } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { history, redo, undo, undoDepth } from '@codemirror/commands';
import { ensureSyntaxTree } from '@codemirror/language';
import type { SyntaxNode } from '@lezer/common';
import { glyphMarkdown } from './language.ts';
import {
  afterComposition,
  apply,
  blockPlan,
  focusToken,
  footnotePlan,
  formPlan,
  givesWay,
  insertLineAt,
  insertSpots,
  itemPlan,
  nameLater,
  ownLinePlan,
  releaseSpot,
  reserveSpot,
  wordsPlan,
} from './inserts.ts';

/**
 * Where the things the + beside the line adds go (editor/inserts.ts), read back with the app's own parser: a thing
 * drawn on a line of its own never lands inside the list, quote or table above it, a block never takes the next line
 * of words as its own, words go where the caret is with the spaces a sentence needs, and every insert is one Undo.
 */

const PICTURE = '![](image/x.jpg)';
const PLACE = '[Cais](geo:38.7057,-9.1446)';

function stateOf(doc: string, caret = doc.length, extensions: Extension[] = []): EditorState {
  return EditorState.create({ doc, selection: { anchor: caret }, extensions: [glyphMarkdown([], []), history(), insertSpots, ...extensions] });
}

function viewOf(doc: string, caret = doc.length): EditorView {
  return new EditorView({ state: stateOf(doc, caret), parent: document.body.appendChild(document.createElement('div')) });
}

/** The doc after a plan, and where the caret went. */
function after(state: EditorState, plan: ReturnType<typeof ownLinePlan>): { doc: string; caret: number; selected: string } {
  const next = state.update({ changes: plan.changes, selection: plan.selection }).state;
  const { from, to, head } = next.selection.main;
  return { doc: next.doc.toString(), caret: head, selected: next.sliceDoc(from, to) };
}

/** The top-level block holding `needle`, and every block around it, as the app's parser reads the doc. */
function blocksAround(doc: string, needle: string): string[] {
  const state = stateOf(doc);
  const tree = ensureSyntaxTree(state, doc.length, 5000)!;
  const chain: string[] = [];
  for (let node: SyntaxNode | null = tree.resolveInner(doc.indexOf(needle) + 1, 1); node; node = node.parent) chain.push(node.name);
  return chain;
}

const outsideBlocks = (doc: string, needle: string) => {
  const chain = blocksAround(doc, needle);
  expect(chain, `${JSON.stringify(doc)}: ${chain.join(' < ')}`).not.toContain('ListItem');
  expect(chain).not.toContain('Blockquote');
  expect(chain).not.toContain('Table');
  expect(chain).toContain('Paragraph');
};

describe('a line that gives way', () => {
  it('is one with nothing on it but a lead', () => {
    for (const line of ['', '  ', '- ', '- [ ] ', '3. ', '> ', '- ( ) ']) expect(givesWay(line), line).toBe(true);
  });

  it('is never one with words, a bookmark or an anchor, which an insert would lose', () => {
    for (const line of ['words', '- [ ] milk', '- §§', '- [ ] ^anchor']) expect(givesWay(line), line).toBe(false);
  });
});

describe('a thing on a line of its own', () => {
  it('takes an empty line under a paragraph, and leaves the caret on a fresh line after it', () => {
    const state = stateOf('Trip\n\nMore', 5);
    const out = after(state, ownLinePlan(state, 5, PICTURE));
    expect(out.doc).toBe(`Trip\n${PICTURE}\n\nMore`);
    expect(out.caret).toBe(`Trip\n${PICTURE}\n`.length);
  });

  it('goes under a line with words, never splitting it', () => {
    const state = stateOf('Book the cabin by Friday', 8);
    expect(after(state, ownLinePlan(state, 8, PICTURE)).doc).toBe(`Book the cabin by Friday\n${PICTURE}\n`);
  });

  it('takes an empty to-do under an item whole, with a blank line so it is not the list’s', () => {
    const doc = '- [ ] milk\n- [ ] ';
    const state = stateOf(doc);
    const out = after(state, ownLinePlan(state, doc.length, PICTURE)).doc;
    expect(out).toBe(`- [ ] milk\n\n${PICTURE}\n`);
    outsideBlocks(out, PICTURE);
  });

  it('takes an empty middle item, ending the list there and starting it again after', () => {
    const doc = '- a\n- \n- b';
    const state = stateOf(doc, 6);
    const out = after(state, ownLinePlan(state, 6, PICTURE)).doc;
    expect(out).toBe(`- a\n\n${PICTURE}\n\n- b`);
    outsideBlocks(out, PICTURE);
  });

  it('goes under a to-do with words outside it', () => {
    const doc = '- [ ] buy milk';
    const state = stateOf(doc, 4);
    const out = after(state, ownLinePlan(state, 4, PLACE)).doc;
    expect(out).toBe(`- [ ] buy milk\n\n${PLACE}\n`);
    outsideBlocks(out, PLACE);
  });

  it('goes under a quote outside it', () => {
    const doc = '> quote';
    const state = stateOf(doc);
    const out = after(state, ownLinePlan(state, doc.length, PLACE)).doc;
    outsideBlocks(out, PLACE);
  });

  it('takes an empty quote line, outside the quote', () => {
    const doc = '> quote\n> ';
    const state = stateOf(doc);
    const out = after(state, ownLinePlan(state, doc.length, PLACE)).doc;
    expect(out).toBe(`> quote\n\n${PLACE}\n`);
    outsideBlocks(out, PLACE);
  });

  it('on the empty line under a table is not a row of it', () => {
    const doc = '| a | b |\n| --- | --- |\n| c | d |\n';
    const state = stateOf(doc);
    const out = after(state, ownLinePlan(state, doc.length, PICTURE)).doc;
    outsideBlocks(out, PICTURE);
  });

  it('keeps apart from a paragraph above when it is a link, a place, so no reader runs it into the sentence', () => {
    const doc = 'Lunch at the harbour\n';
    const state = stateOf(doc);
    const out = after(state, ownLinePlan(state, doc.length, PLACE, { apart: true }));
    expect(out.doc).toBe(`Lunch at the harbour\n\n${PLACE}\n`);
    expect(out.caret).toBe(out.doc.length);
    const tree = ensureSyntaxTree(stateOf(out.doc), out.doc.length, 5000)!;
    const paragraph = tree.resolveInner(out.doc.indexOf(PLACE) + 1, 1);
    let node: SyntaxNode | null = paragraph;
    while (node && node.name !== 'Paragraph') node = node.parent;
    expect(node?.from).toBe(out.doc.indexOf(PLACE));
    // Under a line of words that the caret is on, too; and a picture keeps to the line under the words.
    const words = stateOf('Lunch', 2);
    expect(after(words, ownLinePlan(words, 2, PLACE, { apart: true })).doc).toBe(`Lunch\n\n${PLACE}\n`);
    expect(after(state, ownLinePlan(state, doc.length, PICTURE)).doc).toBe(`Lunch at the harbour\n${PICTURE}\n`);
  });

  it('keeps out of a list item whose words run on to a line of their own', () => {
    // The second line has no lead: only the parser says it is still the item's.
    const doc = '- milk\nand eggs\n';
    const state = stateOf(doc);
    const out = after(state, ownLinePlan(state, doc.length, PICTURE)).doc;
    expect(out).toBe(`- milk\nand eggs\n\n${PICTURE}\n`);
    outsideBlocks(out, PICTURE);
  });

  it('keeps a bookmarked or anchored empty item, and goes under it', () => {
    const doc = '- [ ] ^anchor';
    const state = stateOf(doc);
    expect(after(state, ownLinePlan(state, doc.length, PICTURE)).doc).toBe(`- [ ] ^anchor\n\n${PICTURE}\n`);
  });
});

describe('a block', () => {
  const TABLE = '| Column | Column |\n| --- | --- |\n| Cell | Cell |';

  it('before a line of words leaves a blank line, so the words are not a row', () => {
    const doc = 'Para\n\nnext words';
    const state = stateOf(doc, 5);
    const out = after(state, blockPlan(state, 5, TABLE, { from: 2, to: 8 }));
    expect(out.doc).toBe(`Para\n\n${TABLE}\n\nnext words`);
    expect(out.selected).toBe('Column');
    const chain = blocksAround(out.doc, 'next words');
    expect(chain).not.toContain('TableRow');
    expect(chain).toContain('Paragraph');
  });

  it('under a paragraph on the next line gets a blank line before it, for other readers', () => {
    const doc = 'Para\n';
    const state = stateOf(doc);
    expect(after(state, blockPlan(state, doc.length, '---', { from: 3 })).doc).toBe('Para\n\n---');
  });

  it('takes an empty list item whole', () => {
    const doc = '- a\n- ';
    const state = stateOf(doc);
    const out = after(state, blockPlan(state, doc.length, TABLE, { from: 2, to: 8 })).doc;
    expect(out).toBe(`- a\n\n${TABLE}`);
  });

  it('after a line of words goes after it, a blank line first', () => {
    const doc = 'Words here';
    const state = stateOf(doc, 3);
    expect(after(state, blockPlan(state, 3, '---', { from: 3 })).doc).toBe('Words here\n\n---');
  });

  it('can leave the caret on a fresh line after it', () => {
    const doc = 'A\n\n\nB';
    const state = stateOf(doc, 3);
    const out = after(state, blockPlan(state, 3, '---', 'after'));
    expect(out.doc).toBe('A\n\n---\n\nB');
    expect(out.caret).toBe('A\n\n---\n'.length);
  });
});

describe('words at the caret', () => {
  it('are spaced from the words either side', () => {
    const state = stateOf('Met atthe harbour', 6);
    expect(after(state, wordsPlan(state, 6, '[[Lisbon]]')).doc).toBe('Met at [[Lisbon]] the harbour');
  });

  it('take a space after closing punctuation, and none on an empty line', () => {
    let state = stateOf('Done.', 5);
    expect(after(state, wordsPlan(state, 5, '14:05')).doc).toBe('Done. 14:05');
    state = stateOf('- ', 2);
    expect(after(state, wordsPlan(state, 2, '14:05')).doc).toBe('- 14:05');
  });

  it('leave the caret after them, or where the seed says', () => {
    let state = stateOf('', 0);
    expect(after(state, wordsPlan(state, 0, '28 Sep 2026, 14:05')).caret).toBe(18);
    state = stateOf('', 0);
    expect(after(state, wordsPlan(state, 0, '#tag', { from: 1, to: 4 })).selected).toBe('tag');
  });
});

describe('a to-do, and the other items', () => {
  const todo = (doc: string, caret = doc.length) => {
    const state = stateOf(doc, caret);
    return after(state, itemPlan(state, caret, 'todo'));
  };

  it('turns an empty item’s lead into a to-do’s, keeping its indent and marker', () => {
    expect(todo('- ').doc).toBe('- [ ] ');
    expect(todo('3. ').doc).toBe('3. [ ] ');
    expect(todo('  - ').doc).toBe('  - [ ] ');
    expect(todo('- ( ) ').doc).toBe('- [ ] ');
  });

  it('writes nothing on an empty to-do, and never a second box', () => {
    const out = todo('- [ ] ');
    expect(out.doc).toBe('- [ ] ');
    expect(out.caret).toBe(6);
  });

  it('keeps a quote around it, and takes the indent of the item above on an empty line', () => {
    expect(todo('> ').doc).toBe('> - [ ] ');
    expect(todo('  - milk\n').doc).toBe('  - milk\n  - [ ] ');
    expect(todo('').doc).toBe('- [ ] ');
  });

  it('under a line of words starts a new item, keeping the quote and the indent', () => {
    expect(todo('Para', 2).doc).toBe('Para\n- [ ] ');
    expect(todo('> quote', 3).doc).toBe('> quote\n> - [ ] ');
    expect(todo('  - milk', 5).doc).toBe('  - milk\n  - [ ] ');
  });

  it('makes a choice only after a bullet', () => {
    const state = stateOf('3. ');
    expect(after(state, itemPlan(state, 3, 'choice')).doc).toBe('- ( ) ');
  });

  it('numbers a new step after the one above', () => {
    const state = stateOf('1. one\n2. two\n');
    expect(after(state, itemPlan(state, state.doc.length, 'number')).doc).toBe('1. one\n2. two\n3. ');
  });

  it('turns an empty to-do into a plain item for a bulleted list', () => {
    const state = stateOf('- [ ] ');
    expect(after(state, itemPlan(state, 6, 'bullet')).doc).toBe('- ');
  });
});

describe('a line’s form', () => {
  const form = (doc: string, kind: Parameters<typeof formPlan>[2]) => {
    const state = stateOf(doc);
    return after(state, formPlan(state, doc.length, kind)).doc;
  };

  it('writes a heading, a quote and a sum on an empty line', () => {
    expect(form('', 'heading')).toBe('## ');
    expect(form('', 'quote')).toBe('> ');
    expect(form('', 'sum')).toBe('= ');
  });

  it('leaves an empty quote line a quote, and never nests another in it', () => {
    expect(form('> ', 'quote')).toBe('> ');
    expect(form('>', 'quote')).toBe('>');
  });

  it('keeps a quote around a heading, and a list’s lead before a sum', () => {
    expect(form('> ', 'heading')).toBe('> ## ');
    expect(form('- ', 'sum')).toBe('- = ');
    expect(form('- ', 'heading')).toBe('## ');
  });
});

describe('a footnote', () => {
  it('puts the next number at the caret and its line at the end of the note, the caret there', () => {
    const doc = 'Four hundred[^1]\n\nThen\n\n[^1]: Sam said so.';
    const state = stateOf(doc, 'Four hundred[^1]\n\nThen'.length);
    const out = after(state, footnotePlan(state, state.selection.main.head));
    expect(out.doc).toBe('Four hundred[^1]\n\nThen [^2]\n\n[^1]: Sam said so.\n[^2]: ');
    expect(out.caret).toBe(out.doc.length);
  });

  it('starts at 1, closing the words just above an empty line, with a blank line before its words', () => {
    const state = stateOf('Words\n', 6);
    expect(after(state, footnotePlan(state, 6)).doc).toBe('Words[^1]\n\n[^1]: ');
    const apart = stateOf('Words\n\n', 7);
    expect(after(apart, footnotePlan(apart, 7)).doc).toBe('Words\n\n[^1]\n\n[^1]: ');
  });
});

describe('one Undo for each', () => {
  it('takes back the whole insert, and nothing typed before it', () => {
    const view = viewOf('Typed');
    view.dispatch({ changes: { from: 5, insert: ' more' }, userEvent: 'input.type' });
    const doc = view.state.doc.toString();
    apply(view, blockPlan(view.state, doc.length, '| Column | Column |\n| --- | --- |\n| Cell | Cell |', { from: 2, to: 8 }));
    undo(view);
    expect(view.state.doc.toString()).toBe(doc);
    view.destroy();
  });

  it('keeps what is typed straight after it a step of its own', () => {
    const view = viewOf('Para\n');
    apply(view, itemPlan(view.state, view.state.doc.length, 'todo'));
    const end = view.state.doc.length;
    view.dispatch({ changes: { from: end, insert: 'milk' }, selection: { anchor: end + 4 }, userEvent: 'input.type' });
    undo(view);
    expect(view.state.doc.toString()).toBe('Para\n- [ ] ');
    undo(view);
    expect(view.state.doc.toString()).toBe('Para\n');
    view.destroy();
  });
});

describe('a line that arrives later', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('lands where the caret was when it was asked for, however the note changed', () => {
    const view = viewOf('Lunch at the harbour\n', 21);
    const spot = reserveSpot(view);
    view.dispatch({ changes: { from: 0, insert: 'Day two\n' } });
    insertLineAt(view, spot, PLACE, { userEvent: 'input.plus.drawn' });
    expect(view.state.doc.toString()).toBe(`Day two\nLunch at the harbour\n${PLACE}\n`);
    releaseSpot(view, spot);
    view.destroy();
  });

  it('leaves the caret alone once the person has moved on', () => {
    const view = viewOf('One\n\nTwo', 4);
    const spot = reserveSpot(view);
    view.dispatch({ selection: { anchor: 1 } });
    insertLineAt(view, spot, PLACE, { userEvent: 'input.plus.drawn' });
    expect(view.state.selection.main.head).toBe(1);
    view.destroy();
  });

  it('with a stale focus token: no focus taken, no scroll, and a caret left on the line carried past it', () => {
    const view = viewOf('One\n\n', 5);
    const other = document.body.appendChild(document.createElement('input'));
    const token = focusToken(view);
    other.focus();
    const spot = reserveSpot(view);
    const focus = vi.spyOn(view, 'focus');
    const dispatch = vi.spyOn(view, 'dispatch');
    insertLineAt(view, spot, PLACE, { userEvent: 'input.plus.drawn', token });
    expect(view.state.doc.toString()).toBe(`One\n\n${PLACE}\n`);
    // Left at the line's start, the first letter typed on coming back would go in front of the place and break it.
    expect(view.state.selection.main.head).toBe(`One\n\n${PLACE}\n`.length);
    expect(dispatch.mock.calls[0]![0]).not.toHaveProperty('scrollIntoView');
    expect(focus).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(other);
    token.done();
    view.destroy();
  });

  it('with a stale focus token leaves a caret the person put elsewhere where it is', () => {
    const view = viewOf('One\n\nTwo', 4);
    const other = document.body.appendChild(document.createElement('input'));
    const token = focusToken(view);
    other.focus();
    const spot = reserveSpot(view);
    view.dispatch({ selection: { anchor: 3 } });
    insertLineAt(view, spot, PLACE, { userEvent: 'input.plus.drawn', token, apart: true });
    expect(view.state.selection.main.head).toBe(3);
    token.done();
    view.destroy();
  });

  it('counts a focus inside the note as the note’s, and one anywhere else as somewhere else', () => {
    const view = viewOf('One\n');
    const token = focusToken(view);
    view.contentDOM.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
    expect(token.fresh()).toBe(true);
    document.body.appendChild(document.createElement('input')).focus();
    expect(token.fresh()).toBe(false);
    token.done();
    view.destroy();
  });

  it('with a fresh token: the caret after it, and focus back only if the view had lost it', () => {
    const view = viewOf('One\n\n', 5);
    const token = focusToken(view);
    const spot = reserveSpot(view);
    const focus = vi.spyOn(view, 'focus');
    insertLineAt(view, spot, PLACE, { userEvent: 'input.plus.drawn', token });
    expect(view.state.selection.main.head).toBe(`One\n\n${PLACE}\n`.length);
    expect(focus).toHaveBeenCalledTimes(1);
    token.done();
    view.destroy();
  });
});

describe('a place’s name that comes late', () => {
  const COORDS = '[38.7057, -9.1446](geo:38.7057,-9.1446)';
  const NAMED = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';

  /** The place written with its coordinates, as the + writes it when no name came in time. */
  function written(): { view: EditorView; spot: number; depth: number } {
    const view = viewOf('Lunch at the harbour\n', 21);
    const spot = reserveSpot(view);
    const landed = insertLineAt(view, spot, COORDS, { userEvent: 'input.plus.drawn' });
    releaseSpot(view, spot);
    return { view, spot: landed.spot, depth: undoDepth(view.state) };
  }

  it('is written when nothing came between, and undoes in two clean steps', () => {
    const { view, spot, depth } = written();
    expect(nameLater(view, spot, depth, COORDS, NAMED)).toBe(true);
    expect(view.state.doc.toString()).toBe(`Lunch at the harbour\n${NAMED}\n`);
    undo(view);
    expect(view.state.doc.toString()).toBe(`Lunch at the harbour\n${COORDS}\n`);
    undo(view);
    expect(view.state.doc.toString()).toBe('Lunch at the harbour\n');
    view.destroy();
  });

  it('is written after a caret move, which is not a change', () => {
    const { view, spot, depth } = written();
    view.dispatch({ selection: { anchor: 0 } });
    expect(nameLater(view, spot, depth, COORDS, NAMED)).toBe(true);
    view.destroy();
  });

  it('is not written once the person typed, and the first Undo takes back the typing', () => {
    const { view, spot, depth } = written();
    const end = view.state.doc.length;
    view.dispatch({ changes: { from: end, insert: 'Grilled sardines' }, userEvent: 'input.type' });
    expect(nameLater(view, spot, depth, COORDS, NAMED)).toBe(false);
    undo(view);
    expect(view.state.doc.toString()).toBe(`Lunch at the harbour\n${COORDS}\n`);
    view.destroy();
  });

  it('is not written while an Undo waits to be redone', () => {
    const { view, spot, depth } = written();
    const end = view.state.doc.length;
    view.dispatch({ changes: { from: end, insert: 'x' }, userEvent: 'input.type' });
    undo(view);
    expect(nameLater(view, spot, depth, COORDS, NAMED)).toBe(false);
    redo(view);
    expect(view.state.doc.toString()).toBe(`Lunch at the harbour\n${COORDS}\nx`);
    view.destroy();
  });

  it('keeps what is typed straight after it a step of its own', () => {
    const { view, spot, depth } = written();
    expect(nameLater(view, spot, depth, COORDS, NAMED)).toBe(true);
    // Right against the name, where CodeMirror would otherwise take the two as one change.
    const end = view.state.doc.length - 1;
    view.dispatch({ changes: { from: end, insert: ' at noon' }, userEvent: 'input.type' });
    undo(view);
    expect(view.state.doc.toString()).toBe(`Lunch at the harbour\n${NAMED}\n`);
    view.destroy();
  });

  it('is never written into a note whose undo is not the editor’s own, as a note live on two devices is', () => {
    const view = new EditorView({
      state: EditorState.create({ doc: 'Lunch at the harbour\n', selection: { anchor: 21 }, extensions: [glyphMarkdown([], []), insertSpots] }),
      parent: document.body.appendChild(document.createElement('div')),
    });
    const landed = insertLineAt(view, reserveSpot(view), COORDS, { userEvent: 'input.plus.drawn' });
    expect(nameLater(view, landed.spot, 0, COORDS, NAMED)).toBe(false);
    expect(view.state.doc.toString()).toBe(`Lunch at the harbour\n${COORDS}\n`);
    view.destroy();
  });

  it('is not written over a line that changed', () => {
    const { view, spot } = written();
    const at = view.state.doc.toString().indexOf('38.7057,');
    view.dispatch({ changes: { from: at, to: at + 1, insert: '4' } });
    expect(nameLater(view, spot, undoDepth(view.state), COORDS, NAMED)).toBe(false);
    view.destroy();
  });
});

describe('waiting for the keyboard to finish a word', () => {
  it('does not wait when nothing is being composed', async () => {
    const view = viewOf('');
    await expect(afterComposition(view, 300)).resolves.toBeUndefined();
    view.destroy();
  });

  it('waits for the composition to end, or for the time to run out', async () => {
    vi.useFakeTimers();
    try {
      const view = viewOf('');
      Object.defineProperty(view, 'composing', { get: () => true });
      let done = false;
      void afterComposition(view, 300).then(() => (done = true));
      await vi.advanceTimersByTimeAsync(100);
      expect(done).toBe(false);
      view.contentDOM.dispatchEvent(new CompositionEvent('compositionend'));
      await vi.advanceTimersByTimeAsync(0);
      expect(done).toBe(true);

      let late = false;
      void afterComposition(view, 300).then(() => (late = true));
      await vi.advanceTimersByTimeAsync(299);
      expect(late).toBe(false);
      await vi.advanceTimersByTimeAsync(1);
      expect(late).toBe(true);
      view.destroy();
    } finally {
      vi.useRealTimers();
    }
  });
});
