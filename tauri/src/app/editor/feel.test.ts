import { describe, expect, it, vi } from 'vitest';
import { EditorState, type Transaction } from '@codemirror/state';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { ensureSyntaxTree } from '@codemirror/language';
import { feelOf, feelTransaction } from './feel.ts';

/** What the hand was given, in order: a haptic's kind, or `tick` for the micro tick. */
const felt = vi.hoisted(() => ({ calls: [] as string[] }));
vi.mock('../core/haptics.ts', () => ({
  fireFelt: (kind: string) => felt.calls.push(kind),
  fireMicroTick: () => felt.calls.push('tick'),
}));

/**
 * What the hand is allowed to say.
 *
 * These run without a Taptic Engine, which is the entire reason `feelOf` is a
 * pure function separate from the firing: the motor is native-only and
 * silently inert everywhere a test can run, so a design where the decision and
 * the buzz were one function would be the one part of the editor nobody could
 * check. Here the decision is checkable and the buzz is three lines.
 *
 * Every case types the LAST character of a construct into a document that
 * already holds the rest, because that is the moment the app claims to
 * recognise and the only one worth a taptic.
 */

const extensions = [markdown({ base: markdownLanguage })];

/** A state with the syntax tree already parsed over the whole document. */
function stateOf(doc: string): EditorState {
  const state = EditorState.create({ doc, extensions });
  ensureSyntaxTree(state, doc.length, 5_000);
  return state;
}

/**
 * Type `insert` at the end of `before` and return the resulting transaction,
 * with the tree parsed on both sides so the before/after comparison in `feelOf`
 * has something to compare.
 */
function type(before: string, insert: string): Transaction {
  const state = stateOf(before);
  const tr = state.update({
    changes: { from: before.length, insert },
    selection: { anchor: before.length + insert.length },
    userEvent: 'input.type',
  });
  ensureSyntaxTree(tr.state, tr.state.doc.length, 5_000);
  return tr;
}

describe('feelOf', () => {
  it('ticks when a bold mark closes', () => {
    expect(feelOf(type('**bold*', '*'))).toBe('mark');
  });

  it('ticks when italic, code and strikethrough close', () => {
    expect(feelOf(type('_soft', '_'))).toBe('mark');
    expect(feelOf(type('`code', '`'))).toBe('mark');
    expect(feelOf(type('~~gone~', '~'))).toBe('mark');
  });

  it('says nothing for the OPENING half of a mark', () => {
    expect(feelOf(type('a *', '*'))).toBeNull();
  });

  it('says nothing for ordinary characters', () => {
    expect(feelOf(type('hello worl', 'd'))).toBeNull();
  });

  /*
   * The marker character, not the space after it. The grammar promotes the
   * line as soon as the `#` lands - which is also when it visibly grows - so
   * waiting for the space would put the buzz a character behind the eye.
   */
  it('is heavier for a heading than for other blocks', () => {
    expect(feelOf(type('', '#'))).toBe('heading');
    expect(feelOf(type('', '>'))).toBe('block');
    expect(feelOf(type('', '-'))).toBe('block');
    expect(feelOf(type('--', '-'))).toBe('block');
    expect(feelOf(type('``', '`'))).toBe('block');
  });

  it('does not re-announce a block that was already there', () => {
    // The space after "#" does not make a second heading, and neither does
    // typing the heading's actual text.
    expect(feelOf(type('#', ' '))).toBeNull();
    expect(feelOf(type('# Titl', 'e'))).toBeNull();
  });

  /*
   * The case a regex cannot get right, and the reason this is a tree
   * comparison: inside a fenced code block `**` is two asterisks, no mark is
   * created, and a text-matching implementation would buzz anyway.
   */
  it('stays silent inside a fenced code block', () => {
    expect(feelOf(type('```\n**bold*', '*'))).toBeNull();
  });

  it('stays silent while an IME is composing', () => {
    const before = '**bold*';
    const state = stateOf(before);
    const tr = state.update({
      changes: { from: before.length, insert: '*' },
      userEvent: 'input.type.compose',
    });
    expect(feelOf(tr)).toBeNull();
  });

  it('says nothing for a transaction that changed no text', () => {
    const state = stateOf('**bold**');
    expect(feelOf(state.update({ selection: { anchor: 2 } }))).toBeNull();
  });

  /*
   * Enter in a list: the markdown keymap writes the newline and the next marker in one insert, a to-do's box too, in
   * a quote or not. Texture rather than news, but still felt.
   */
  it('feels a list continuing itself onto the next line', () => {
    const continued = (before: string, insert: string) => stateOf(before).update({ changes: { from: before.length, insert }, userEvent: 'input' });
    expect(feelOf(continued('- milk', '\n- '))).toBe('continue');
    expect(feelOf(continued('1. milk', '\n2. '))).toBe('continue');
    expect(feelOf(continued('- [ ] milk', '\n- [ ] '))).toBe('continue');
    expect(feelOf(continued('> - milk', '\n> - '))).toBe('continue');
    // A plain newline, or a line of words after it, is not a list continuing.
    expect(feelOf(continued('- milk', '\n'))).toBeNull();
    expect(feelOf(continued('- milk', '\neggs'))).toBeNull();
  });
});

describe('what each is felt as', () => {
  it('a mark closing as a tick, a heading heavier, any other block light, and a list continuing as the lightest', () => {
    feelTransaction(type('**bold*', '*'));
    feelTransaction(type('', '#'));
    feelTransaction(type('', '>'));
    feelTransaction(stateOf('- milk').update({ changes: { from: 6, insert: '\n- ' }, userEvent: 'input' }));
    feelTransaction(type('hello worl', 'd'));
    expect(felt.calls).toEqual(['selection', 'medium', 'light', 'tick']);
  });
});
