import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { glyphMarkdown } from './language.ts';
import { shortLinks } from './links.ts';

function open(doc: string, caret: number) {
  const state = EditorState.create({ doc, selection: { anchor: caret }, extensions: [glyphMarkdown(), shortLinks()] });
  return new EditorView({ state, parent: document.createElement('div') });
}

describe('item marks in the editor', () => {
  const URL = 'https://www.notion.so/attackfm/Buy-milk-1a2b3c4d5e6f';

  it('draws the mark at the end of an item as one pill with the name on it', () => {
    const view = open(`- [ ] Buy milk [notion](${URL})\nplain\n`, 0);
    const pills = [...view.contentDOM.querySelectorAll('.cm-itemMark')];
    expect(pills.map((p) => p.textContent)).toEqual(['Notion']);
    expect(pills[0]?.getAttribute('title')).toBe(URL);
    // The mark's own address is inside the pill, not shortened beside it.
    expect(view.contentDOM.querySelectorAll('.cm-shortLink')).toHaveLength(0);
    view.destroy();
  });

  it('leaves an ordinary link alone: its address is shortened, the words stay', () => {
    const view = open(`- [ ] read [the board](${URL})\n`, 0);
    expect(view.contentDOM.querySelectorAll('.cm-itemMark')).toHaveLength(0);
    expect(view.contentDOM.querySelectorAll('.cm-shortLink')).toHaveLength(1);
    view.destroy();
  });

  it('is not a mark when something follows it on the line, or the line is not an item', () => {
    const view = open(`- [ ] Buy milk [notion](${URL}) today\nSee [notion](${URL})\n`, 0);
    expect(view.contentDOM.querySelectorAll('.cm-itemMark')).toHaveLength(0);
    view.destroy();
  });
});
