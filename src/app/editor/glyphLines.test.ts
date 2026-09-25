import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import styles from './Editor.module.css';
import { glyphLines } from './glyphLines.ts';
import { parseWhole } from '../../test/syntaxTree.ts';
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
  view = parseWhole(new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown(), glyphLines] }), parent: document.body }));
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
    parseWhole(on);
    expect(has(lines(on)[0], 'lineH1')).toBe(true);
  });

  it('moves what it drew along with a change while an IME is composing, and draws again only once it is done', () => {
    const on = open('milk\n# eggs');
    // Redrawn under a live composition, a line's DOM is replaced and the phone's keyboard garbles what it is writing.
    let composing = true;
    Object.defineProperty(on, 'composing', { configurable: true, get: () => composing });
    on.dispatch({ changes: { from: 0, insert: '# ' } });
    parseWhole(on);
    // The heading below is still drawn as one, where it now is; the line being written is not drawn again yet.
    expect([has(lines(on)[0], 'lineH1'), has(lines(on)[1], 'lineH1')]).toEqual([false, true]);
    composing = false;
    on.dispatch({ changes: { from: on.state.doc.line(1).to, insert: 's' } });
    parseWhole(on);
    expect([has(lines(on)[0], 'lineH1'), has(lines(on)[1], 'lineH1')]).toEqual([true, true]);
  });

  it("measures a marker again once the note's face has loaded, since it was measured in the fallback", () => {
    const fonts = new EventTarget();
    Object.defineProperty(document, 'fonts', { configurable: true, value: fonts });
    try {
      // A face of its own, so no other test's measure of `- ` is the one kept.
      const on = open('- milk');
      on.contentDOM.style.fontFamily = 'Loading Face';
      on.dispatch({ changes: { from: on.state.doc.length, insert: 's' } });
      expect(lines(on)[0]?.style.getPropertyValue('--hang')).toBe('16.00px');
      // The face arrives, wider: 10px a character.
      vi.mocked(HTMLElement.prototype.getBoundingClientRect).mockImplementation(function (this: HTMLElement) {
        return new DOMRect(0, 0, (this.textContent ?? '').length * 10, 20);
      });
      on.dispatch({ changes: { from: on.state.doc.length, insert: '!' } });
      // Until the fonts say so, the width kept for the face is the one used.
      expect(lines(on)[0]?.style.getPropertyValue('--hang')).toBe('16.00px');
      fonts.dispatchEvent(new Event('loadingdone'));
      expect(lines(on)[0]?.style.getPropertyValue('--hang')).toBe('20.00px');
      on.destroy();
      view = null;
    } finally {
      delete (document as { fonts?: unknown }).fonts;
    }
  });
});
