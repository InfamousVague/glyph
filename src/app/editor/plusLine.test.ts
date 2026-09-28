import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { plusLine } from './plusLine.ts';

/**
 * Which line the + beside the line is drawn on (editor/plusLine.ts): the caret's line when it has no words (Matt:
 * "EMPTY LINES ONLY, on every platform"), and only where adding to the note makes sense.
 */

const here = { focused: true, editable: true, allowed: true };

function lineOf(doc: string, anchor = doc.length, head = anchor, over: Partial<typeof here> = {}): number | null {
  const state = EditorState.create({ doc, selection: { anchor, head } });
  return plusLine(state, { ...here, ...over })?.number ?? null;
}

describe('the line the + is drawn on', () => {
  it('is the caret’s line when it has no words', () => {
    expect(lineOf('Lunch at the harbour\n')).toBe(2);
    expect(lineOf('')).toBe(1);
  });

  it('is an empty item, to-do, choice or quote line: a lead is not words', () => {
    for (const lead of ['- ', '- [ ] ', '3. ', '- ( ) ', '> ', '> - [ ] ']) expect(lineOf(`Para\n${lead}`), lead).toBe(2);
  });

  it('is never a line with words, whatever the caret is doing on it', () => {
    expect(lineOf('Lunch at the harbour')).toBeNull();
    expect(lineOf('Lunch at the harbour', 0)).toBeNull();
    expect(lineOf('- [ ] milk')).toBeNull();
    expect(lineOf('# ')).toBeNull();
  });

  it('is never on a selection, which belongs to press and hold', () => {
    expect(lineOf('a\n\nb', 0, 3)).toBeNull();
  });

  it('is never in a view that has lost focus, cannot be edited, or is not a note being written', () => {
    expect(lineOf('', 0, 0, { focused: false })).toBeNull();
    expect(lineOf('', 0, 0, { editable: false })).toBeNull();
    expect(lineOf('', 0, 0, { allowed: false })).toBeNull();
  });

  it('is never in the front matter or a block of code', () => {
    const front = '---\ntitle: Trip\n\n---\n\nWords';
    expect(lineOf(front, front.indexOf('\n\n---') + 1)).toBeNull();
    expect(lineOf(front, front.length - 'Words'.length - 1)).toBe(5);
    const fence = 'Before\n```\n\n```\nAfter\n';
    expect(lineOf(fence, 'Before\n```\n'.length)).toBeNull();
    expect(lineOf(fence)).toBe(6);
  });
});
