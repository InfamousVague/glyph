import { describe, expect, it } from 'vitest';
import { EditorSelection, EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { onNamingLine, openFirstHeading, openHeading } from './openHeading.ts';

/**
 * What an open first heading says (editor/openHeading.ts): `A name` on the note's first line of words when it is a
 * heading with none, under front matter too, and nowhere else; and which line names the note, for the + beside it.
 */

const state = (doc: string, caret = doc.length) => EditorState.create({ doc, selection: EditorSelection.cursor(caret) });
const hint = (doc: string) => {
  const view = new EditorView({ state: EditorState.create({ doc, extensions: [openHeading()] }), parent: document.body });
  const found = view.contentDOM.querySelector('.cm-openHint');
  const at = found ? view.posAtDOM(found) : null;
  view.destroy();
  return found ? { words: found.textContent, at } : null;
};

describe('an open first heading', () => {
  it('says `A name` after its marks, on the first line of words, under front matter too', () => {
    expect(hint('# ')).toEqual({ words: 'A name', at: 2 });
    expect(hint('## \n\n- [ ] ')).toEqual({ words: 'A name', at: 3 });
    expect(hint('---\nlook: reading\n---\n# \n')).toEqual({ words: 'A name', at: '---\nlook: reading\n---\n# '.length });
    expect(hint('\n\n# ')?.words).toBe('A name');
  });

  it('says nothing on a heading with words, or on an empty heading further down', () => {
    expect(hint('# Title')).toBeNull();
    expect(hint('# Title\n\n## ')).toBeNull();
    expect(hint('Words.\n\n# ')).toBeNull();
    expect(hint('')).toBeNull();
    expect(openFirstHeading(state('- [ ] '))).toBeNull();
  });
});

describe('the line that names the note', () => {
  it('is a blank note’s line 1, or an open first heading, with the caret on it', () => {
    expect(onNamingLine(state(''))).toBe(true);
    expect(onNamingLine(state('# '))).toBe(true);
    expect(onNamingLine(state('\n\n', 2))).toBe(true);
    expect(onNamingLine(state('---\nlook: map\n---\n# '))).toBe(true);
  });

  it('is not a line after the name, a line with words, a list’s lead, or the front matter', () => {
    expect(onNamingLine(state('# Title\n\n'))).toBe(false);
    expect(onNamingLine(state('Words'))).toBe(false);
    expect(onNamingLine(state('- [ ] '))).toBe(false);
    expect(onNamingLine(state('---\nlook: map\n---\n', 4))).toBe(false);
  });
});
