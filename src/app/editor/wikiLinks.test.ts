import { describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { glyphMarkdown } from './language.ts';
import { sameTitle, wikiLinks, wikiLinksIn } from './wikiLinks.ts';

describe('a link between notes', () => {
  it('is read out of the words, brackets and all', () => {
    const line = 'The deposit is in [[The cabin trip]], not here.';
    expect(wikiLinksIn(line)).toEqual([{ from: 18, to: 36, title: 'The cabin trip' }]);
  });

  it('takes several on a line, and nothing from empty brackets', () => {
    expect(wikiLinksIn('[[one]] and [[two]]').map((l) => l.title)).toEqual(['one', 'two']);
    expect(wikiLinksIn('[[]] and [[   ]]')).toEqual([]);
  });

  it('matches a title the way a person says it, not the way they type it', () => {
    expect(sameTitle('the cabin trip', 'The cabin trip.')).toBe(true);
    expect(sameTitle('Weekend  trip', 'weekend-trip')).toBe(true);
    expect(sameTitle('cabin', 'cabins')).toBe(false);
    expect(sameTitle('', '')).toBe(false);
  });
});

describe('how it is drawn and what a tap does', () => {
  const editor = (doc: string, known: (title: string) => boolean, open = vi.fn()) => {
    const view = new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown([], []), wikiLinks({ known, open })] }), parent: document.body });
    return { view, open };
  };

  it('draws a link to a note that exists, and one that is waiting to be written', () => {
    const { view } = editor('go to [[Here]] and [[Nowhere]]', (title) => title === 'Here');
    const marks = [...view.contentDOM.querySelectorAll('.cm-wiki')];
    expect(marks).toHaveLength(2);
    expect(marks[0]?.className).not.toContain('cm-wikiNew');
    expect(marks[1]?.className).toContain('cm-wikiNew');
    view.destroy();
  });

  it('is nothing at all when the note screen cannot open notes', () => {
    const view = new EditorView({
      state: EditorState.create({ doc: '[[Here]]', extensions: [glyphMarkdown([], []), wikiLinks(null)] }),
      parent: document.body,
    });
    expect(view.contentDOM.querySelector('.cm-wiki')).toBeNull();
    view.destroy();
  });
});
