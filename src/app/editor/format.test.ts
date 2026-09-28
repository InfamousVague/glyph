import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { history, undo } from '@codemirror/commands';
import { ensureSyntaxTree } from '@codemirror/language';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import type { SyntaxNode } from '@lezer/common';
import { activeBlock, activeMarks, insertRule, insertTable, toggleBlock, toggleMark } from './format.ts';
import { glyphMarkdown } from './language.ts';

/**
 * What the formatting bar writes, checked against what the highlighter reads.
 *
 * The bar is the one place in the app that puts markdown syntax into the
 * document on the user's behalf, so a drift between its delimiters and the
 * grammar's would produce text that looks like a mark and renders as plain -
 * invisible in review, obvious and baffling on a phone.
 */

/** A detached view, which is all `toggleMark`/`toggleBlock` need. */
function viewOf(doc: string, anchor: number, head = anchor): EditorView {
  return new EditorView({ state: EditorState.create({ doc, selection: { anchor, head } }) });
}

const text = (view: EditorView) => view.state.doc.toString();

describe('toggleMark', () => {
  it('wraps a selection and keeps it selected', () => {
    const view = viewOf('make this bold', 10, 14);
    toggleMark(view, 'bold');
    expect(text(view)).toBe('make this **bold**');
    expect(view.state.sliceDoc(view.state.selection.main.from, view.state.selection.main.to)).toBe('bold');
  });

  it('puts the caret BETWEEN the delimiters when nothing is selected', () => {
    // Otherwise pressing Bold and typing produces text after the markers, and
    // the person has to notice and move the caret back.
    const view = viewOf('', 0);
    toggleMark(view, 'bold');
    expect(text(view)).toBe('****');
    expect(view.state.selection.main.head).toBe(2);
  });

  it('unwraps when the delimiters sit just outside the selection', () => {
    const view = viewOf('**bold**', 2, 6);
    toggleMark(view, 'bold');
    expect(text(view)).toBe('bold');
  });

  it('unwraps when the delimiters are inside the selection', () => {
    const view = viewOf('**bold**', 0, 8);
    toggleMark(view, 'bold');
    expect(text(view)).toBe('bold');
  });

  it('uses the kit delimiters, so what the bar writes is what the grammar reads', () => {
    const cases: Array<[Parameters<typeof toggleMark>[1], string]> = [
      ['bold', '**x**'],
      ['italic', '_x_'],
      ['code', '`x`'],
      ['strike', '~~x~~'],
    ];
    for (const [mark, expected] of cases) {
      const view = viewOf('x', 0, 1);
      toggleMark(view, mark);
      expect(text(view)).toBe(expected);
    }
  });
});

describe('toggleBlock', () => {
  it('prefixes the caret line', () => {
    const view = viewOf('a line', 3);
    toggleBlock(view, 'quote');
    expect(text(view)).toBe('> a line');
  });

  it('removes the prefix when every touched line has one', () => {
    const view = viewOf('- one\n- two', 0, 11);
    toggleBlock(view, 'bullet');
    expect(text(view)).toBe('one\ntwo');
  });

  it('completes a half-formatted run rather than clearing it', () => {
    const view = viewOf('- one\ntwo', 0, 9);
    toggleBlock(view, 'bullet');
    expect(text(view)).toBe('- one\n- two');
  });

  it('numbers an ordered list rather than repeating 1.', () => {
    const view = viewOf('one\ntwo\nthree', 0, 13);
    toggleBlock(view, 'number');
    expect(text(view)).toBe('1. one\n2. two\n3. three');
  });

  it('recognises a heading of any level as already-a-heading', () => {
    const view = viewOf('### deep', 4);
    expect(activeBlock(view.state)).toBe('heading');
    toggleBlock(view, 'heading');
    expect(text(view)).toBe('deep');
  });
});

describe("Style's table and rule", () => {
  /** The node names a doc parses to: the app's own parser, or plain GFM as Obsidian and GitHub read the file. */
  const parsed = (doc: string, plain = false) => {
    const state = EditorState.create({ doc, extensions: [plain ? markdown({ base: markdownLanguage }) : glyphMarkdown([], [])] });
    const names: string[] = [];
    ensureSyntaxTree(state, doc.length, 5000)!.iterate({ enter: (node) => void names.push(node.name) });
    return names;
  };
  /** The node holding `needle`, innermost first, as the app's parser reads `doc`. */
  const around = (doc: string, needle: string) => {
    const state = EditorState.create({ doc, extensions: [glyphMarkdown([], [])] });
    const chain: string[] = [];
    for (let node: SyntaxNode | null = ensureSyntaxTree(state, doc.length, 5000)!.resolveInner(doc.indexOf(needle) + 1, 1); node; node = node.parent) chain.push(node.name);
    return chain;
  };

  it('puts a blank line between a table and the words after it, so they are not a row', () => {
    const view = viewOf('Para\n\nnext words', 5);
    insertTable(view);
    const doc = text(view);
    expect(doc).toBe('Para\n\n| Column | Column |\n| --- | --- |\n| Cell | Cell |\n\nnext words');
    expect(around(doc, 'next words')).not.toContain('TableRow');
    // Without the blank line the same words are a row: the check can fail.
    expect(around('Para\n| Column | Column |\n| --- | --- |\n| Cell | Cell |\nnext words', 'next words')).toContain('TableRow');
  });

  it('keeps the rule under a paragraph from making it a heading where other apps read the file', () => {
    const view = viewOf('Para\n', 5);
    insertRule(view);
    expect(text(view)).toBe('Para\n\n---');
    expect(parsed(text(view), true)).not.toContain('SetextHeading2');
    // Plain GFM reads the unmended form as a heading, which is what the blank line is for.
    expect(parsed('Para\n---', true)).toContain('SetextHeading2');
  });

  it('takes an empty list item’s line', () => {
    const view = viewOf('- a\n- ', 6);
    insertTable(view);
    expect(text(view)).toBe('- a\n\n| Column | Column |\n| --- | --- |\n| Cell | Cell |');
    expect(view.state.sliceDoc(view.state.selection.main.from, view.state.selection.main.to)).toBe('Column');
  });

  it('is one step to undo', () => {
    const view = new EditorView({ state: EditorState.create({ doc: 'Words', selection: { anchor: 5 }, extensions: [history()] }) });
    insertRule(view);
    undo(view);
    expect(text(view)).toBe('Words');
  });
});

describe('activeMarks', () => {
  it('reports the mark surrounding the caret', () => {
    const view = viewOf('**bold**', 2, 6);
    expect(activeMarks(view.state)).toContain('bold');
  });

  it('reports nothing in plain text', () => {
    expect(activeMarks(viewOf('plain', 2).state)).toEqual([]);
  });
});
