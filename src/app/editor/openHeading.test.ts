import { describe, expect, it } from 'vitest';
import { EditorSelection, EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { leadLine, leadOf, onNamingLine, openFirstHeading, openHeading } from './openHeading.ts';

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

describe('a reading note’s lead line', () => {
  const lead = (doc: string) => {
    const { lines, hint } = leadOf(state(doc));
    return { lines: lines.map((line) => line.text), hint: hint?.number ?? null };
  };

  it('is the first paragraph after the title, and stops at a blank line or a line that is not prose', () => {
    expect(lead('# The long road\n\nIt went on.\nAnd on.\n\nMore.')).toEqual({ lines: ['It went on.', 'And on.'], hint: null });
    expect(lead('---\nlook: reading\n---\n# Road\nStraight under it.')).toEqual({ lines: ['Straight under it.'], hint: null });
    expect(lead('# Road\n\n- a list\n\nWords.')).toEqual({ lines: [], hint: null });
    expect(lead('# Road\n\n> A quote')).toEqual({ lines: [], hint: null });
    expect(lead('# Road\n\n![a picture](p.webp)')).toEqual({ lines: [], hint: null });
    expect(lead('Road, with no title\n\nWords.')).toEqual({ lines: [], hint: null });
  });

  it('says what goes there on the empty line under the title while nothing below has words', () => {
    expect(lead('# \n')).toEqual({ lines: [], hint: 2 });
    expect(lead('# The long road\n\n')).toEqual({ lines: [], hint: 2 });
    expect(lead('# The long road')).toEqual({ lines: [], hint: null });
  });

  it('is drawn larger in the reading look only, with its hint quiet and not in the note', () => {
    const view = new EditorView({ state: EditorState.create({ doc: '# Road\n\nIt went on.\n', extensions: [leadLine()] }), parent: document.body });
    expect([...view.contentDOM.querySelectorAll('.cm-lead')].map((line) => line.textContent)).toEqual(['It went on.']);
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: '# \n' } });
    expect(view.contentDOM.querySelector('.cm-lead .cm-openHint')?.textContent).toBe('A line that says what it is about.');
    expect(view.state.doc.toString()).toBe('# \n');
    view.destroy();
  });
});
