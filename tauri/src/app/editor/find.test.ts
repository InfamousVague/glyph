import { history, undo } from '@codemirror/commands';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it } from 'vitest';
import { endSearch, findExtension, findOf, matchesIn, replaceAll, replaceOne, search, setFind, step } from './find.ts';

describe('find and replace', () => {
  it('finds every match, case forgiven, never overlapping', () => {
    expect(matchesIn('Friday, friday, FRIDAY', 'friday').map((m) => m.from)).toEqual([0, 8, 16]);
    expect(matchesIn('aaaa', 'aa').map((m) => m.from)).toEqual([0, 2]);
    expect(matchesIn('anything', '')).toEqual([]);
  });

  it('makes the first match after the caret current, and keeps finding as the words change', () => {
    const state = EditorState.create({ doc: 'milk, eggs, milk, bread, milk', extensions: [findExtension()] });
    const found = state.update({ effects: setFind.of({ query: 'milk', near: 7 }) }).state;
    expect(findOf(found).matches.length).toBe(3);
    expect(findOf(found).current).toBe(1);
    // One replaced by hand: the search follows, one fewer.
    const edited = found.update({ changes: { from: 0, to: 4, insert: 'oat' } }).state;
    expect(findOf(edited).matches.length).toBe(2);
  });

  it('replaces every match in one change', () => {
    const state = EditorState.create({ doc: 'milk, eggs, milk', extensions: [findExtension()] });
    const found = state.update({ effects: setFind.of({ query: 'milk' }) }).state;
    const changes = findOf(found).matches.map((m) => ({ from: m.from, to: m.to, insert: 'oat milk' }));
    const replaced = found.update({ changes }).state;
    expect(replaced.doc.toString()).toBe('oat milk, eggs, oat milk');
  });
});

describe('the find bar’s commands on a note', () => {
  // What editor/FindBar.tsx drives: a search, the arrows, Replace, Replace all and Done.
  const doc = 'milk, eggs, Milk, bread, milk';
  let view: EditorView | null = null;

  function open(caret = 0): EditorView {
    view = new EditorView({ state: EditorState.create({ doc, selection: { anchor: caret }, extensions: [findExtension(), history()] }), parent: document.body });
    return view;
  }
  const current = (on: EditorView) => {
    const { matches, current: index } = findOf(on.state);
    return matches[index]?.from ?? null;
  };

  afterEach(() => {
    view?.destroy();
    view = null;
  });

  it('marks every match and makes the first one at or after the caret current', () => {
    const on = open(7);
    search(on, 'milk');
    expect(findOf(on.state).matches).toHaveLength(3);
    expect(current(on)).toBe(12);
    expect(on.dom.querySelectorAll('.cm-findMatch')).toHaveLength(2);
    expect(on.dom.querySelector('.cm-findCurrent')?.textContent).toBe('Milk');
  });

  it('steps through the matches either way, wrapping round at each end', () => {
    const on = open();
    search(on, 'milk');
    expect(current(on)).toBe(0);
    step(on, -1);
    expect(current(on)).toBe(25);
    step(on, 1);
    expect(current(on)).toBe(0);
    step(on, 1);
    step(on, 1);
    step(on, 1);
    expect(current(on)).toBe(0);
  });

  it('replaces the current match and moves on to the next', () => {
    const on = open(7);
    search(on, 'milk');
    replaceOne(on, 'oat milk');
    expect(on.state.doc.toString()).toBe('milk, eggs, oat milk, bread, milk');
    // Past what was just written, so its own "milk" is not found and replaced again.
    expect(current(on)).toBe(on.state.doc.toString().lastIndexOf('milk'));
  });

  it('replaces them all as one change, one undo taking it back, and says how many', () => {
    const on = open();
    search(on, 'milk');
    expect(replaceAll(on, 'oats')).toBe(3);
    expect(on.state.doc.toString()).toBe('oats, eggs, oats, bread, oats');
    undo(on);
    expect(on.state.doc.toString()).toBe(doc);
    search(on, 'cheese');
    expect(replaceAll(on, 'x')).toBe(0);
    expect(on.state.doc.toString()).toBe(doc);
  });

  it('ends with no marks and the current match selected, so the note picks up where the search left it', () => {
    const on = open();
    search(on, 'bread');
    endSearch(on);
    expect(findOf(on.state).matches).toEqual([]);
    expect(on.dom.querySelector('.cm-findMatch, .cm-findCurrent')).toBeNull();
    const { from, to } = on.state.selection.main;
    expect(on.state.sliceDoc(from, to)).toBe('bread');
  });
});
