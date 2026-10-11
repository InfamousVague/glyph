import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { button, show, typeInto, unmount } from '../../test/render.tsx';
import { goBack } from '../core/back.ts';
import { findExtension, findOf } from './find.ts';
import { FindBar } from './FindBar.tsx';

/**
 * Find and replace, as the bar on the keyboard: the count read back from the editor's own state, the arrows and Enter
 * between matches, Replace and All, and Done, Escape or the back gesture ending the search.
 */

let view: EditorView;
let host: HTMLDivElement;

function bar(doc: string, initial = '', onClose = vi.fn()) {
  host = document.createElement('div');
  document.body.appendChild(host);
  view = new EditorView({ state: EditorState.create({ doc, extensions: [findExtension()] }), parent: host });
  show(<FindBar view={view} initial={initial} onClose={onClose} />);
  return onClose;
}

const field = (label: string) => document.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`)!;
/** The bar's count - the bar's, not the editor's own announcer, which is polite too. */
const count = () => document.querySelector('[role="search"] [aria-live="polite"]')?.textContent;
const key = (name: string, shiftKey = false) =>
  act(() => {
    field('Find').dispatchEvent(new KeyboardEvent('keydown', { key: name, shiftKey, bubbles: true }));
  });

afterEach(() => {
  view?.destroy();
  host?.remove();
});

describe('the find bar', () => {
  it('finds as it is typed, and says which match of how many, or None', () => {
    bar('milk, eggs, milk');
    expect(count()).toBe('');
    typeInto(field('Find'), 'milk');
    expect(count()).toBe('1 of 2');
    typeInto(field('Find'), 'bread');
    expect(count()).toBe('None');
    expect(button('Next match').disabled).toBe(true);
  });

  it('opens on the words it was given, with them chosen to type over', () => {
    bar('milk, eggs, milk', 'eggs');
    expect(field('Find').value).toBe('eggs');
    expect(count()).toBe('1 of 1');
    expect(document.activeElement).toBe(field('Find'));
  });

  it('steps forward on Enter and the down arrow, and back on Shift+Enter and the up arrow', () => {
    bar('milk, milk, milk', 'milk');
    key('Enter');
    expect(count()).toBe('2 of 3');
    act(() => button('Next match').click());
    expect(count()).toBe('3 of 3');
    key('Enter', true);
    expect(count()).toBe('2 of 3');
    act(() => button('Previous match').click());
    expect(count()).toBe('1 of 3');
  });

  it('replaces one, then all, and says how many all was', () => {
    bar('milk, eggs, milk, milk', 'milk');
    act(() => button('Replace').click());
    typeInto(field('Replace with'), 'cream');
    act(() => button('Replace', document.querySelectorAll('[role="search"] > div')[1]!).click());
    expect(view.state.doc.toString()).toBe('cream, eggs, milk, milk');
    act(() => button('All').click());
    expect(view.state.doc.toString()).toBe('cream, eggs, cream, cream');
    expect(document.body.textContent).toContain('Replaced 2. Undo takes it back.');
  });

  it('ends the search on Done, on Escape and on the back gesture', () => {
    for (const leave of [() => act(() => button('Done').click()), () => key('Escape'), () => act(() => void goBack())]) {
      const onClose = bar('milk, eggs, milk', 'milk');
      expect(findOf(view.state).matches.length).toBe(2);
      leave();
      expect(onClose).toHaveBeenCalledTimes(1);
      expect(findOf(view.state).matches.length).toBe(0);
      unmount();
      view.destroy();
      host.remove();
    }
  });
});
