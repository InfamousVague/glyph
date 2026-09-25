import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it } from 'vitest';
import type { InlineFormat } from '../plugins/types.ts';
import { formatLooks, styledRanges, type StyleLook } from './formatLooks.ts';
import { glyphMarkdown } from './language.ts';

// A plugin formatting drawn as a style (editor/formatLooks.ts): its words carry its CSS, and a name in brackets after
// it, where the formatting takes one, adds that name's CSS.

const glow: InlineFormat = {
  name: 'Glow',
  delimiter: '~~~',
  look: { kind: 'style', css: 'color: red;' },
  tint: (name) => (name === 'green' ? 'background: green;' : null),
};
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
});
