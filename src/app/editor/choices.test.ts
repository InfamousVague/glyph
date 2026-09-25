import { EditorState } from '@codemirror/state';
import { describe, expect, it } from 'vitest';
import { choiceOn, groupOf, pick } from './choices.ts';

const state = (text: string) => EditorState.create({ doc: text });

describe('choices', () => {
  it('reads a round box on a bullet, and nothing else', () => {
    const s = state('- ( ) Tent\n* (x) Cabin\n- (X) Hotel\n- ( x ) no\n1. ( ) no\n- [ ] a to-do');
    expect(choiceOn(s.doc, 1)).toEqual({ line: 1, from: 2, picked: false, indent: 0 });
    expect(choiceOn(s.doc, 2)?.picked).toBe(true);
    expect(choiceOn(s.doc, 3)?.picked).toBe(true);
    expect([4, 5, 6].map((n) => choiceOn(s.doc, n))).toEqual([null, null, null]);
  });

  it('reads a choice however it is spaced after its bullet, as a to-do’s box is (core/itemSyntax.ts)', () => {
    const s = state('-  ( ) Two spaces\n*\t(x) A tab\n  - ( ) Indented\n- ( )\n- ( )Glued');
    expect(choiceOn(s.doc, 1)).toEqual({ line: 1, from: 3, picked: false, indent: 0 });
    expect(choiceOn(s.doc, 2)).toMatchObject({ from: s.doc.line(2).from + 2, picked: true });
    expect(choiceOn(s.doc, 3)).toMatchObject({ from: s.doc.line(3).from + 4, indent: 2 });
    // One with no words yet is a choice too; brackets glued to words are words.
    expect(choiceOn(s.doc, 4)).toMatchObject({ from: s.doc.line(4).from + 2, picked: false });
    expect(choiceOn(s.doc, 5)).toBeNull();
    // And the tap writes inside the brackets wherever they are.
    expect(pick(s, 1)!.state.doc.line(1).text).toBe('-  (x) Two spaces');
  });

  it('groups the choices next to each other at one indent, with lines under a choice inside the group', () => {
    const s = state('Stay?\n- ( ) Tent\n  cheap\n- ( ) Cabin\n  - ( ) Small\n  - ( ) Big\n- ( ) Hotel\n\n- ( ) Other group');
    expect(groupOf(s.doc, 2).map((c) => c.line)).toEqual([2, 4, 7]);
    expect(groupOf(s.doc, 5).map((c) => c.line)).toEqual([5, 6]);
    expect(groupOf(s.doc, 9).map((c) => c.line)).toEqual([9]);
  });

  it('picks one and clears the rest, and a picked one tapped again is cleared', () => {
    let s = state('- (x) Tent\n- ( ) Cabin\n- ( ) Hotel');
    s = pick(s, 2)!.state;
    expect(s.doc.toString()).toBe('- ( ) Tent\n- (x) Cabin\n- ( ) Hotel');
    s = pick(s, 2)!.state;
    expect(s.doc.toString()).toBe('- ( ) Tent\n- ( ) Cabin\n- ( ) Hotel');
    expect(pick(s, 1)!.isUserEvent('input')).toBe(true);
  });
});
