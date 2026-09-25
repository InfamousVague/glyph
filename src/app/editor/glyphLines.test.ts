import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import styles from './Editor.module.css';
import { glyphLines } from './glyphLines.ts';
import { glyphMarkdown } from './language.ts';

let view: EditorView | null = null;

beforeEach(() => {
  // jsdom lays nothing out: a marker measured in the editor's face is 8px a character here.
  vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (this: HTMLElement) {
    return new DOMRect(0, 0, (this.textContent ?? '').length * 8, 20);
  });
});

afterEach(() => {
  view?.destroy();
  view = null;
  vi.restoreAllMocks();
});

function open(doc: string): EditorView {
  view = new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown(), glyphLines] }), parent: document.body });
  return view;
}
const lines = (on: EditorView) => [...on.contentDOM.querySelectorAll<HTMLElement>('.cm-line')];
const has = (line: HTMLElement | undefined, name: keyof typeof styles) => Boolean(line?.classList.contains(styles[name] ?? '-'));

describe('what a line is, drawn on the line', () => {
  it('sets a heading’s line by its level, the smallest three alike', () => {
    const [one, two, three, four, five, six] = lines(open('# a\n## b\n### c\n#### d\n##### e\n###### f'));
    expect([has(one, 'lineH1'), has(two, 'lineH2'), has(three, 'lineH3'), has(four, 'lineH4')]).toEqual([true, true, true, true]);
    expect([has(five, 'lineH4'), has(six, 'lineH4')]).toEqual([true, true]);
  });

  it('draws a block of code as one card, its first and last lines carrying the corners', () => {
    const [before, top, middle, foot] = lines(open('words\n```js\nconst a = 1;\n```'));
    expect(has(before, 'lineCode')).toBe(false);
    expect([has(top, 'lineCode'), has(middle, 'lineCode'), has(foot, 'lineCode')]).toEqual([true, true, true]);
    expect([has(top, 'lineCodeTop'), has(middle, 'lineCodeTop'), has(foot, 'lineCodeFoot')]).toEqual([true, false, true]);
  });

  it('holds the space around a quote on its first and last lines', () => {
    const [top, middle, foot] = lines(open('> one\n> two\n> three'));
    expect([has(top, 'lineQuote'), has(middle, 'lineQuote'), has(foot, 'lineQuote')]).toEqual([true, true, true]);
    expect([has(top, 'lineQuoteTop'), has(middle, 'lineQuoteTop'), has(middle, 'lineQuoteFoot'), has(foot, 'lineQuoteFoot')]).toEqual([true, false, false, true]);
  });

  it('hangs a list item’s wrapped lines under its words, at its marker’s measured width', () => {
    const [bullet, numbered, todo] = lines(open('- milk\n10. eggs\n- [ ] bread'));
    expect(has(bullet, 'lineItem')).toBe(true);
    // `- `, `10. ` and `- [ ] `, at 8px a character.
    expect([bullet, numbered, todo].map((line) => line?.style.getPropertyValue('--hang'))).toEqual(['16.00px', '32.00px', '48.00px']);
  });

  it('draws again what a line has become as it is typed', () => {
    const on = open('milk');
    expect(has(lines(on)[0], 'lineH1')).toBe(false);
    on.dispatch({ changes: { from: 0, insert: '# ' } });
    expect(has(lines(on)[0], 'lineH1')).toBe(true);
  });
});
