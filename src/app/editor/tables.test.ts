import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { glyphMarkdown } from './language.ts';
import { drawnTables, parseTable } from './tables.ts';

describe('reading a GFM table to draw it', () => {
  it('reads the header, the alignment and the rows, escaped pipes kept as text', () => {
    expect(parseTable('| Bug | Owner | Status |\n| --- | :---: | ---: |\n| Seek bar \\| drift | Matt | Open |\n| Login |')).toEqual({
      header: ['Bug', 'Owner', 'Status'],
      align: [null, 'center', 'right'],
      rows: [
        ['Seek bar | drift', 'Matt', 'Open'],
        ['Login', '', ''],
      ],
    });
  });

  it('is not a table without its divider line', () => {
    expect(parseTable('| a | b |\n| c | d |')).toBeNull();
  });
});

// What every drawn block shares (editor/drawnBlock.ts), proven on the simplest of them.
describe('a table drawn in a note', () => {
  const doc = ['Before', '', '| Bug | Owner |', '| --- | --- |', '| Seek **bar** | Matt |', '', 'After'].join('\n');
  const tableAt = doc.indexOf('| Bug');
  let view: EditorView | null = null;

  function open(readOnly = false): EditorView {
    const extensions = [glyphMarkdown(), drawnTables(), readOnly ? [EditorState.readOnly.of(true), EditorView.editable.of(false)] : []];
    view = new EditorView({ state: EditorState.create({ doc, extensions }), parent: document.body });
    return view;
  }
  const drawn = (on: EditorView) => on.dom.querySelector('.cm-glyphTable');
  const press = (on: EditorView) => on.dom.querySelector('.cm-glyphTableWrap')!.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));

  afterEach(() => {
    view?.destroy();
    view = null;
  });

  it('is drawn with its header and rows, their markup as words, in a view that has never had focus', () => {
    const on = open();
    on.dispatch({ selection: { anchor: tableAt + 3 } });
    // Not focused: a caret in the table's range still leaves it drawn, since nobody is typing.
    expect(drawn(on)?.querySelector('th')?.textContent).toBe('Bug');
    expect(drawn(on)?.querySelector('td')?.textContent).toBe('Seek bar');
  });

  // CodeMirror tells the state of a focus change a moment after the DOM's own event, so these wait for the drawing
  // itself rather than for a time.
  it('steps aside for its pipes when a press puts the caret in it, and is drawn again when the caret leaves', async () => {
    const on = open();
    press(on);
    expect(on.hasFocus).toBe(true);
    expect(on.state.selection.main.head).toBe(tableAt);
    await vi.waitFor(() => expect(drawn(on)).toBeNull());
    expect(on.contentDOM.textContent).toContain('| Bug | Owner |');

    on.dispatch({ selection: { anchor: doc.length } });
    expect(drawn(on)).not.toBeNull();
  });

  it('is drawn again when the note loses focus, wherever the caret was left', async () => {
    const on = open();
    on.focus();
    on.dispatch({ selection: { anchor: tableAt + 3 } });
    await vi.waitFor(() => expect(drawn(on)).toBeNull());
    on.contentDOM.blur();
    await vi.waitFor(() => expect(drawn(on)).not.toBeNull());
  });

  it('stays drawn in a view that cannot be edited, where a press does not open it', () => {
    const on = open(true);
    press(on);
    // Opening would have put the caret at the table's first line; the view's own handling of the press is its own.
    expect(on.state.selection.main.head).not.toBe(tableAt);
    expect(drawn(on)).not.toBeNull();
  });
});
