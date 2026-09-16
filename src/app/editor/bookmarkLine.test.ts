import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it } from 'vitest';
import { bookmarkRibbon, markedWords, showBookmark } from './bookmarkLine.ts';

const doc = [
  '# Launch week',
  '',
  '- [ ] Write the *pricing* page ^pricing-page',
  '',
  '   ',
  'A line of ordinary words that runs on well past the room a toast has',
].join('\n');

let view: EditorView | null = null;

function editor(text = doc): EditorView {
  view = new EditorView({ state: EditorState.create({ doc: text, extensions: [bookmarkRibbon()] }), parent: document.body });
  return view;
}

/** Which lines carry the ribbon, counting from 1. */
function ribboned(on: EditorView): number[] {
  return [...on.contentDOM.querySelectorAll('.cm-bookmarked')].map((line) => [...on.contentDOM.children].indexOf(line) + 1);
}

afterEach(() => {
  view?.destroy();
  view = null;
});

describe('the bookmark shown in the note', () => {
  it('marks nothing until a place is given, then the line that place is on', () => {
    const on = editor();
    expect(ribboned(on)).toEqual([]);
    on.dispatch({ effects: showBookmark.of(on.state.doc.line(3).from + 4) });
    expect(ribboned(on)).toEqual([3]);
  });

  it('comes off again, and holds a place past the end of the note', () => {
    const on = editor();
    on.dispatch({ effects: showBookmark.of(on.state.doc.line(3).from) });
    on.dispatch({ effects: showBookmark.of(null) });
    expect(ribboned(on)).toEqual([]);
    on.dispatch({ effects: showBookmark.of(9999) });
    expect(ribboned(on)).toEqual([6]);
  });

  it('stays on its words when the note is typed into above them', () => {
    const on = editor();
    on.dispatch({ effects: showBookmark.of(on.state.doc.line(3).from) });
    on.dispatch({ changes: { from: 0, insert: 'A first line\n' } });
    expect(ribboned(on)).toEqual([4]);
  });
});

describe('the words a bookmark sits on', () => {
  it('says them without the marks that shape them', () => {
    const on = editor();
    expect(markedWords(on, on.state.doc.line(1).from)).toBe('Launch week');
    expect(markedWords(on, on.state.doc.line(3).from)).toBe('Write the pricing page');
  });

  it('looks past blank lines, and cuts a long line short', () => {
    const on = editor();
    expect(markedWords(on, on.state.doc.line(4).from)).toBe('A line of ordinary words that…');
    expect(markedWords(editor('   \n\n'), 0)).toBeNull();
  });
});

describe('a place on a blank line', () => {
  it('ribbons the next line that has words, so the mark is where the words are', () => {
    const on = editor();
    on.dispatch({ effects: showBookmark.of(on.state.doc.line(2).from) });
    expect(ribboned(on)).toEqual([3]);
    expect(markedWords(on, on.state.doc.line(2).from)).toBe('Write the pricing page');
  });
});
