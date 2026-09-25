import { EditorState, Text } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { describe, expect, it } from 'vitest';
import { headingCounts, headingProgress } from './headingProgress.ts';

const doc = (text: string) => Text.of(text.split('\n'));

describe('progress under a heading', () => {
  it('counts the to-dos until the next heading of the same level, a section counting its subsections', () => {
    const note = doc(['# Trip', '## Packing', '- [x] Tent', '- [ ] Stove', '### Food', '- [X] Oats', '## Plan', '- Just a bullet', '## Chores', '1. [ ] Bins'].join('\n'));
    expect(headingCounts(note)).toEqual([
      { line: 1, done: 2, total: 4 },
      { line: 2, done: 2, total: 3 },
      { line: 5, done: 1, total: 1 },
      { line: 9, done: 0, total: 1 },
    ]);
  });

  it('counts only the boxes the note draws, so a heading never says a to-do is open that has no box to tick', () => {
    const note = doc(['## Shop', '- [ ]milk', '- [x](https://example.com/x)', '* [ ] eggs', '+ [X] bread'].join('\n'));
    expect(headingCounts(note)).toEqual([{ line: 1, done: 1, total: 2 }]);
  });

  it('ignores boxes and headings inside code', () => {
    const note = doc(['## Code', '```', '# not a heading', '- [ ] not a to-do', '```', '- [ ] real'].join('\n'));
    expect(headingCounts(note)).toEqual([{ line: 1, done: 0, total: 1 }]);
  });

  it('says the count at the end of the heading, all done in words of its own, and follows the boxes as they change', () => {
    const view = new EditorView({ state: EditorState.create({ doc: '## Shop\n- [x] milk\n- [ ] eggs', extensions: [headingProgress()] }), parent: document.body });
    const count = () => view.contentDOM.querySelector<HTMLElement>('.cm-line .cm-headingCount');
    expect(count()?.textContent).toBe('1 of 2');
    expect(count()?.getAttribute('aria-label')).toBe('1 of 2 done');
    expect(count()?.classList.contains('cm-headingCountDone')).toBe(false);
    // The widget sits after the heading's words, on its line.
    expect(count()?.closest('.cm-line')?.textContent).toBe('## Shop1 of 2');
    view.dispatch({ changes: { from: view.state.doc.line(3).from + 3, to: view.state.doc.line(3).from + 4, insert: 'x' } });
    expect(count()?.textContent).toBe('All 2 done');
    expect(count()?.getAttribute('aria-label')).toBe('2 of 2 done');
    expect(count()?.classList.contains('cm-headingCountDone')).toBe(true);
    view.destroy();
  });
});
