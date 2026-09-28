import { EditorSelection, EditorState, Text } from '@codemirror/state';
import { describe, expect, it } from 'vitest';
import { forEachLineOutsideFences, inFence, selectedLines } from './lines.ts';

describe('the lines outside fenced code', () => {
  const read = (text: string) => {
    const seen: string[] = [];
    forEachLineOutsideFences(Text.of(text.split('\n')), (line) => seen.push(line.text));
    return seen;
  };

  it('agree with the one line asked about', () => {
    const text = 'one\n```\n# not a heading\n```\ntwo\n~~~\n```\n~~~\nthree';
    const doc = Text.of(text.split('\n'));
    const outside = read(text);
    for (let n = 1; n <= doc.lines; n += 1) expect(inFence(doc, n), `line ${n}`).toBe(!outside.includes(doc.line(n).text));
  });

  it('skips a fence and everything in it, whichever marker it is written with', () => {
    expect(read('one\n```\n# not a heading\n```\ntwo\n~~~\n- [ ] not a box\n~~~\nthree')).toEqual(['one', 'two', 'three']);
  });

  it('closes a fence only on the marker it opened with', () => {
    expect(read('```\n~~~\nstill code\n```\nwords')).toEqual(['words']);
  });

  it('takes the rest of a note whose fence never closes as code', () => {
    expect(read('words\n```\nstill code')).toEqual(['words']);
  });
});

describe('the lines the selection touches', () => {
  it('are every line of every range, the lines between a range’s ends included', () => {
    const doc = 'one\ntwo\nthree\nfour\nfive';
    const state = EditorState.create({
      doc,
      selection: EditorSelection.create([EditorSelection.range(1, doc.indexOf('three') + 2), EditorSelection.cursor(doc.length)]),
      extensions: [EditorState.allowMultipleSelections.of(true)],
    });
    expect([...selectedLines(state)].sort()).toEqual([1, 2, 3, 5]);
  });
});
