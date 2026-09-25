import { syntaxTreeAvailable } from '@codemirror/language';
import type { Transaction } from '@codemirror/state';
import { fireFelt, fireMicroTick } from '../core/haptics.ts';
import { BOX, MARKER } from '../core/itemSyntax.ts';
import { enclosing } from './syntax.ts';

/**
 * The hand under the text: which keystrokes are worth a taptic, and which are
 * not.
 *
 * The brief asks for feedback "as styles and effects are applied", and the
 * whole difficulty is in the word "applied". A person typing `**bold**` passes
 * through several plausible moments - the first `*`, the second, the closing
 * pair - and only ONE of them is the moment the text actually became bold.
 * Firing on the others is worse than firing on none: the hand learns that the
 * buzz means nothing.
 *
 * So the test is structural, not textual. A style was applied when a node
 * exists in the syntax tree AFTER the transaction that did not exist at that
 * position BEFORE it. That is true exactly once per mark, it is false inside a
 * fenced code block (where `**` is just two asterisks and a regex would happily
 * lie), and it costs one tree lookup on a tree the parser has already built -
 * `@codemirror/language` does up to 20 ms of synchronous parsing on a document
 * change, so by the time this runs the tree at the cursor is current.
 *
 * Compositions are skipped entirely. An IME rewrites the same characters over
 * and over as candidates change, and each rewrite would look like new syntax
 * appearing; on a Japanese or Korean keyboard the editor would buzz at every
 * candidate. The rule is simple: nothing is "applied" until the composition
 * commits, and the committing transaction is not itself a compose event.
 */

/** Inline marks worth a tick when they close. */
const INLINE = new Set(['StrongEmphasis', 'Emphasis', 'Strikethrough', 'InlineCode', 'Link']);

/** Block forms worth a tap when they are created. */
const BLOCK = /^(ATXHeading[1-6]|Blockquote|ListItem|FencedCode|HorizontalRule)$/;

/** Every character this transaction inserted, in order. */
function insertedText(tr: Transaction): string {
  let typed = '';
  tr.changes.iterChanges((_fromA, _toA, _fromB, _toB, inserted) => {
    typed += inserted.toString();
  });
  return typed;
}

export type FeelKind = 'mark' | 'heading' | 'block' | 'continue';

/** A newline and the marker the markdown keymap writes after it, in a quote or not, with a to-do's box if it had one. */
const CONTINUED = new RegExp(String.raw`^\n[\s>]*${MARKER}\s*(?:${BOX}\s*)?$`);

/**
 * What this transaction is worth, or null. Pure and exported so the decision
 * can be tested without a Taptic Engine to feel it - the motor is native-only
 * and silently inert everywhere a test can run, which would otherwise make
 * this the one part of the editor nobody could check.
 */
export function feelOf(tr: Transaction): FeelKind | null {
  if (!tr.docChanged) return null;
  if (tr.isUserEvent('input.type.compose')) return null;

  const typed = insertedText(tr);
  if (!typed) return null;

  // A list continuing itself onto the next line: the markdown keymap inserted
  // the marker, so the newline arrives with more than just "\n" in it.
  if (typed.startsWith('\n') && typed.length > 1 && CONTINUED.test(typed)) {
    return 'continue';
  }

  if (!tr.isUserEvent('input.type')) return null;
  const head = tr.state.selection.main.head;
  // Without a parsed tree at the caret there is nothing to compare; staying
  // silent is right, because the alternative is guessing.
  if (!syntaxTreeAvailable(tr.state, head)) return null;

  /*
   * Both branches below need the same thing: where the caret's position in the
   * NEW document sat in the OLD one, so the two trees can be asked about the
   * same spot. `tr.changes.mapPos` is the wrong direction - it maps old to new,
   * and handing it a new-document position throws outright once the document
   * has grown past the old length. `invertedDesc` is the map the other way.
   */
  const toOld = tr.changes.invertedDesc;

  /*
   * A closing delimiter was typed: did it actually close something?
   *
   * This check FALLS THROUGH rather than returning when it finds nothing,
   * because the two character sets overlap. A backtick closes inline code and
   * also, as the third of three, opens a fenced block; an early return here
   * meant ``` never registered as a block at all.
   */
  if (/[*_~`)\]]$/.test(typed)) {
    const closed = enclosing(tr.state, head, (name) => INLINE.has(name));
    if (closed && closed.to === head) {
      const before = enclosing(tr.startState, toOld.mapPos(head, -1), (name) => name === closed.name);
      if (!before) return 'mark';
    }
  }

  /*
   * Did this keystroke create a block?
   *
   * Deliberately NOT gated on which character was typed. The obvious gate - a
   * space, because a heading is "# " - is wrong, and measurably so: the grammar
   * promotes the line the moment the MARKER lands, before any space. `#` alone
   * parses as ATXHeading1, `>` as Blockquote, `-` as ListItem, `---` as
   * HorizontalRule, ``` ``` ``` as FencedCode. Since the text visibly changes
   * size and colour at that same instant, that instant is what the thumb should
   * feel; waiting for the space would put the buzz a character late, after the
   * eye had already seen it happen.
   *
   * The cost of dropping the gate is two `resolveInner` walks per keystroke,
   * each proportional to tree depth, which next to the parse itself is nothing.
   */
  const line = tr.state.doc.lineAt(head);
  // One character in, so an empty line's start does not resolve into the node
  // that precedes it.
  const probe = Math.min(line.from + 1, line.to);
  const after = enclosing(tr.state, probe, (name) => BLOCK.test(name));
  if (!after) return null;
  const before = enclosing(tr.startState, toOld.mapPos(probe, 1), (name) => BLOCK.test(name));
  if (before && before.name === after.name) return null;
  return after.name.startsWith('ATXHeading') ? 'heading' : 'block';
}

/**
 * The vocabulary, in one place so it can be read as a sentence: a mark closing
 * is a tick, a heading is heavier because it changes the shape of the page, any
 * other block is light, and a list continuing itself is texture rather than
 * news.
 */
export function feelTransaction(tr: Transaction): void {
  switch (feelOf(tr)) {
    case 'mark':
      fireFelt('selection');
      break;
    case 'heading':
      fireFelt('medium');
      break;
    case 'block':
      fireFelt('light');
      break;
    case 'continue':
      fireMicroTick();
      break;
    default:
      break;
  }
}
