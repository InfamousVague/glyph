import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { lineSuggestions, type LineSuggestion } from './suggestions.ts';

/** Every to-do line gets a word, like the Notion plugin offers. */
function todos(body: string, run: () => Promise<void>): LineSuggestion[] {
  return body
    .split('\n')
    .map((text, index) => ({ text, line: index + 1 }))
    .filter(({ text }) => text.startsWith('- [ ] '))
    .map(({ line }) => ({ line, label: 'Notion', busyLabel: 'Sending', run }));
}

function open(doc: string, caret: number, run: () => Promise<void> = () => Promise.resolve()) {
  const state = EditorState.create({ doc, selection: { anchor: caret }, extensions: [lineSuggestions({ suggest: (body) => todos(body, run) })] });
  return new EditorView({ state, parent: document.createElement('div') });
}

const words = (view: EditorView) => [...view.contentDOM.querySelectorAll('.cm-suggest')].map((b) => b.textContent);

describe('inline suggestions', () => {
  it('puts the word after every line offered, except the one being typed', () => {
    const view = open('- [ ] milk\n- [ ] eggs\nplain\n', 0);
    expect(words(view)).toEqual(['Notion']);
    // The caret leaves the first line: both to-dos have their word.
    view.dispatch({ selection: { anchor: view.state.doc.length } });
    expect(words(view)).toEqual(['Notion', 'Notion']);
    view.destroy();
  });

  it('follows the note as it changes', () => {
    const view = open('plain\n', 0);
    expect(words(view)).toEqual([]);
    view.dispatch({ changes: { from: view.state.doc.length, insert: '- [ ] call the plumber\n' }, selection: { anchor: 0 } });
    expect(words(view)).toEqual(['Notion']);
    view.dispatch({ changes: { from: 6, to: 12, insert: '- [x] ' } });
    expect(words(view)).toEqual([]);
    view.destroy();
  });

  it('says its busy word while it runs, then the word again', async () => {
    let finish: () => void = () => undefined;
    const running = new Promise<void>((resolve) => {
      finish = resolve;
    });
    const view = open('- [ ] milk\n', 11, () => running);
    const button = view.contentDOM.querySelector<HTMLButtonElement>('.cm-suggest');
    expect(button?.textContent).toBe('Notion');
    button?.click();
    expect(words(view)).toEqual(['Sending']);
    expect(view.contentDOM.querySelector<HTMLButtonElement>('.cm-suggest')?.disabled).toBe(true);
    finish();
    await running;
    await Promise.resolve();
    expect(words(view)).toEqual(['Notion']);
    view.destroy();
  });
});
