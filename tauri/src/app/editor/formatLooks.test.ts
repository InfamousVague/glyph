import { syntaxHighlighting } from '@codemirror/language';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it } from 'vitest';
import { parseWhole } from '../../test/syntaxTree.ts';
import type { InlineFormat } from '../plugins/types.ts';
import { coveringLooks, formatLooks, styledRanges, type StyleLook } from './formatLooks.ts';
import { glyphHighlight } from './glyphHighlight.ts';
import { glyphMarkdown } from './language.ts';

// A plugin formatting drawn as a style (editor/formatLooks.ts): its words carry its CSS, and a name in brackets after
// it, where the formatting takes one, adds that name's CSS.

const glow: InlineFormat = {
  name: 'Glow',
  delimiter: '~~~',
  look: { kind: 'style', css: 'color: red;' },
  tint: (name) => (name === 'green' ? 'background: green;' : null),
};
/** A look that hides its words, as a redaction's bar does. */
const bar: InlineFormat = { name: 'Bar', delimiter: '@@', look: { kind: 'style', css: 'background: black;', clearAtCaret: true } };
const looks = new Map<string, StyleLook>([['Glow', { length: 3, css: 'color: red;', tint: glow.tint }]]);

function state(doc: string): EditorState {
  return EditorState.create({ doc, extensions: [glyphMarkdown([glow])] });
}
const styled = (doc: string) => styledRanges(state(doc), looks, { from: 0, to: doc.length }).map((r) => ({ words: doc.slice(r.from, r.to), css: r.css }));

let view: EditorView | null = null;

afterEach(() => {
  view?.destroy();
  view = null;
});

describe('a formatting drawn as a style', () => {
  it('adds the CSS of a name it knows in brackets straight after it', () => {
    expect(styled('the ~~~key~~~(green) words')).toEqual([{ words: 'key', css: 'color: red;background: green;' }]);
  });

  it('keeps its own look for a name it does not know, or brackets that are not straight after it', () => {
    // A name it does not know is a note on the words (editor/markNotes.ts), not a colour.
    expect(styled('the ~~~key~~~(Sam said so) words')).toEqual([{ words: 'key', css: 'color: red;' }]);
    expect(styled('the ~~~key~~~ (green) words')).toEqual([{ words: 'key', css: 'color: red;' }]);
    // A formatting that takes no name never reads the brackets.
    const plain = new Map<string, StyleLook>([['Glow', { length: 3, css: 'color: red;' }]]);
    const doc = 'the ~~~key~~~(green) words';
    expect(styledRanges(state(doc), plain, { from: 0, to: doc.length }).map((r) => r.css)).toEqual(['color: red;']);
  });

  it('marks the words in the editor, one mark with the look, and nothing for formattings of other kinds', () => {
    view = new EditorView({ state: EditorState.create({ doc: 'say ~~~hello~~~ there', extensions: [glyphMarkdown([glow]), formatLooks([glow])] }), parent: document.body });
    const marks = [...view.contentDOM.querySelectorAll<HTMLElement>('.cm-formatLook')];
    expect(marks.map((mark) => mark.textContent)).toEqual(['hello']);
    expect(marks[0]?.getAttribute('style')).toContain('color: red');
    expect(formatLooks([{ name: 'Spoiler', delimiter: '||', look: { kind: 'wisp' } }])).toEqual([]);
  });

  it('sits inside the highlighter’s span, so its box is the size of the words it is on (a heading’s, in a heading)', () => {
    view = new EditorView({
      state: EditorState.create({ doc: '## a ~~~big~~~ heading', extensions: [glyphMarkdown([glow]), syntaxHighlighting(glyphHighlight), formatLooks([glow])] }),
      parent: document.body,
    });
    view = parseWhole(view);
    const mark = view.contentDOM.querySelector<HTMLElement>('.cm-formatLook');
    expect(mark?.textContent).toBe('big');
    // The heading's own span wraps the look's, not the other way round: outside it, the bar was the body's height.
    const line = mark?.closest('.cm-line');
    expect(mark?.parentElement).not.toBe(line);
    expect(mark?.parentElement?.textContent).toBe('big');
  });

  it('draws a look inside a look, and nothing under one that hides its words until it is lifted', () => {
    const both = new Map<string, StyleLook>([...looks, ['Bar', { length: 2, css: 'background: black;', clearAtCaret: true }]]);
    const words = (doc: string, anchor = 0, atCaret = false) =>
      styledRanges(EditorState.create({ doc, extensions: [glyphMarkdown([glow, bar])], selection: { anchor } }), both, { from: 0, to: doc.length }, atCaret).map((r) => doc.slice(r.from, r.to));
    // The inner look's words come after the outer's, in document order, as a range set wants them. (Not at the start
    // of the line, where three tildes open a code fence.)
    expect(words('so ~~~a glow with @@a bar@@ in it~~~')).toEqual(['a glow with @@a bar@@ in it', 'a bar']);
    // Under a bar a glow would show the words, so it is not drawn; lifted, what is under the bar is drawn as it is.
    expect(words('@@a ~~~glow~~~ under a bar@@')).toEqual(['a ~~~glow~~~ under a bar']);
    expect(words('@@a ~~~glow~~~ under a bar@@', 4, true)).toEqual(['glow']);
    // The looks that hide their words, by name, for the rest of the editor (links.ts).
    expect(EditorState.create({ extensions: [formatLooks([glow, bar])] }).facet(coveringLooks)).toEqual(['Bar']);
    expect(EditorState.create({ extensions: [formatLooks([glow])] }).facet(coveringLooks)).toEqual([]);
  });
});
